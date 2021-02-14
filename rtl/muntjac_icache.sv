// Non-coherent I$ (Adapted from muntjac_icache_coherent)
module muntjac_icache import muntjac_pkg::*; import tl_pkg::*; # (
    // Number of ways is `2 ** WaysWidth`.
    parameter int unsigned WaysWidth   = 2,
    // Number of sets is `2 ** SetsWidth`.
    parameter int unsigned SetsWidth   = 6,
    parameter int unsigned VirtAddrLen = 39,
    parameter int unsigned PhysAddrLen = 56,
    parameter int unsigned SourceWidth = 1,
    parameter int unsigned SinkWidth   = 1,

    parameter bit [SourceWidth-1:0] SourceBase  = 0,
    parameter bit [SourceWidth-1:0] PtwSourceBase = 0
) (
    input  logic clk_i,
    input  logic rst_ni,

    // Interface to CPU
    input  icache_h2d_t cache_h2d_i,
    output icache_d2h_t cache_d2h_o,

    // Channel for D$
    tl_channel.host mem,

    // Channel for PTW
    tl_channel.host mem_ptw
);

  // This is the largest address width that we ever have to deal with.
  localparam AddrLen = VirtAddrLen > PhysAddrLen ? VirtAddrLen : PhysAddrLen;

  localparam NumWays = 2 ** WaysWidth;

  if (SetsWidth > 6) $fatal(1, "PIPT cache's SetsWidth is bounded by 6");

  /////////////////////
  // Type definition //
  /////////////////////

  typedef struct packed {
    // Tag, excluding the bits used for direct-mapped access and last 6 bits of offset.
    logic [PhysAddrLen-SetsWidth-6-1:0] tag;
    logic valid;
  } tag_t;

  ////////////////////////
  // CPU Facing signals //
  ////////////////////////

  wire             req_valid    = cache_h2d_i.req_valid;
  wire [63:0]      req_address  = cache_h2d_i.req_pc;
  wire if_reason_e req_reason   = cache_h2d_i.req_reason;
  wire             req_prv      = cache_h2d_i.req_prv;
  wire             req_sum      = cache_h2d_i.req_sum;
  wire [63:0]      req_atp      = cache_h2d_i.req_atp;

  logic flush_valid;
  logic flush_ready;

  logic        resp_valid;
  logic [31:0] resp_value;
  logic        ex_valid;
  exc_cause_e  resp_ex_code;

  assign cache_d2h_o.resp_valid     = resp_valid || ex_valid;
  assign cache_d2h_o.resp_instr     = resp_value;
  assign cache_d2h_o.resp_exception = ex_valid;
  assign cache_d2h_o.resp_ex_code   = resp_ex_code;

  //////////////////////////////////
  // MEM Channel D Demultiplexing //
  //////////////////////////////////

  wire           mem_grant_valid  = mem.d_valid;
  wire [63:0]    mem_grant_data   = mem.d_data;
  wire tl_d_op_e mem_grant_opcode = mem.d_opcode;
  wire           mem_grant_denied = mem.d_denied;

  logic mem_grant_ready;
  assign mem.d_ready = mem_grant_ready;

  assign mem.b_ready   = 1'b1;
  assign mem.c_valid   = 1'b0;
  assign mem.c_opcode  = tl_c_op_e'('x);
  assign mem.c_param   = 'x;
  assign mem.c_size    = 'x;
  assign mem.c_source  = 'x;
  assign mem.c_address = 'x;
  assign mem.c_corrupt = 1'bx;
  assign mem.c_data    = 'x;

  //////////////////////////////
  // Cache access arbitration //
  //////////////////////////////

  logic refill_lock_acq;
  // probe_lock_rel is not defined because probe always transfer the lock to write-back module.
  logic access_lock_acq;
  // access_lock_rel, flush_lock_rel is not always paired with access_lock_req. When a dirty cache
  // line needs to be evicted/flushed, it will transfer the lock to the write-back module.
  logic access_lock_rel;
  logic flush_lock_acq;
  logic flush_lock_rel;

  // Refill logic giving lock to access
  logic refill_lock_move;

  typedef enum logic [1:0] {
    LockHolderNone,
    LockHolderRefill,
    LockHolderAccess,
    LockHolderFlush
  } lock_holder_e;

  logic refill_lock_acq_pending_q, refill_lock_acq_pending_d;
  logic access_lock_acq_pending_q, access_lock_acq_pending_d;
  logic flush_lock_acq_pending_q, flush_lock_acq_pending_d;
  lock_holder_e lock_holder_q, lock_holder_d;

  wire refill_locked  = lock_holder_q == LockHolderRefill;
  wire access_locking = lock_holder_d == LockHolderAccess;
  wire flush_locking  = lock_holder_d == LockHolderFlush;

  // Arbitrate on the new holder of the lock
  always_comb begin
    lock_holder_d = lock_holder_q;
    refill_lock_acq_pending_d = refill_lock_acq_pending_q || refill_lock_acq;
    access_lock_acq_pending_d = access_lock_acq_pending_q || access_lock_acq;
    flush_lock_acq_pending_d = flush_lock_acq_pending_q || flush_lock_acq;

    if (access_lock_rel || flush_lock_rel) begin
      lock_holder_d = LockHolderNone;
    end

    if (refill_lock_move) begin
      lock_holder_d = LockHolderAccess;
    end

    if (lock_holder_d == LockHolderNone) begin
      priority case (1'b1)
        // This blocks channel D, so it must have highest priority by TileLink rule
        refill_lock_acq_pending_d: begin
          lock_holder_d = LockHolderRefill;
          refill_lock_acq_pending_d = 1'b0;
        end
        // This should have no priority difference from access as they are mutually exclusive.
        flush_lock_acq_pending_d: begin
          lock_holder_d = LockHolderFlush;
          flush_lock_acq_pending_d = 1'b0;
        end
        access_lock_acq_pending_d: begin
          lock_holder_d = LockHolderAccess;
          access_lock_acq_pending_d = 1'b0;
        end
        default:;
      endcase
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      refill_lock_acq_pending_q <= 1'b0;
      access_lock_acq_pending_q <= 1'b0;
      flush_lock_acq_pending_q <= 1'b0;
      lock_holder_q <= LockHolderFlush;
    end else begin
      refill_lock_acq_pending_q <= refill_lock_acq_pending_d;
      access_lock_acq_pending_q <= access_lock_acq_pending_d;
      flush_lock_acq_pending_q <= flush_lock_acq_pending_d;
      lock_holder_q <= lock_holder_d;
    end
  end

  ////////////////////////////
  // Cache access multiplex //
  ////////////////////////////

  logic [AddrLen-3-1:0]   access_read_addr;
  logic                   access_read_req_tag;
  logic                   access_read_req_data;
  logic                   access_read_physical;
  logic [WaysWidth-1:0]   access_write_way;
  logic [SetsWidth+3-1:0] access_write_addr;
  logic                   access_write_req_tag;
  tag_t                   access_write_tag;

  logic [WaysWidth-1:0]   refill_write_way;
  logic [SetsWidth+3-1:0] refill_write_addr;
  logic                   refill_write_req_tag;
  tag_t                   refill_write_tag;
  logic                   refill_write_req_data;
  logic [63:0]            refill_write_data;

  logic [NumWays-1:0]    flush_write_ways;
  logic [SetsWidth-1:0]  flush_write_index;
  logic                  flush_write_req_tag;
  tag_t                  flush_write_tag;

  logic read_req_tag;
  logic read_req_data;
  logic read_physical;
  logic [AddrLen-3-1:0] read_addr;

  logic [SetsWidth+3-1:0] write_addr;
  tag_t read_tag [NumWays];
  tag_t write_tag;
  logic write_req_tag;
  logic write_req_data;
  logic [NumWays-1:0] write_ways;
  logic [63:0] read_data [NumWays];
  logic [63:0] write_data;

  always_comb begin
    read_req_tag = 1'b0;
    read_req_data = 1'b0;
    read_addr = 'x;
    read_physical = 1'b1;

    // Multiplex with _d version here because read happens the next cycle.
    unique case (lock_holder_d)
      LockHolderAccess: begin
        read_req_tag = access_read_req_tag;
        read_req_data = access_read_req_data;
        read_addr = access_read_addr;
        read_physical = access_read_physical;
      end
      default:;
    endcase
  end

  logic read_physical_latch;
  logic [AddrLen-3-1:0] read_addr_latch;
  always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
          read_physical_latch <= 1'b1;
          read_addr_latch <= 'x;
      end else begin
          if (read_req_tag || read_req_data) begin
              read_physical_latch <= read_physical;
              read_addr_latch <= read_addr;
          end
      end
  end

  always_comb begin
    write_addr = 'x;
    write_req_tag = 1'b0;
    write_req_data = 1'b0;
    write_ways = '0;
    write_data = 'x;
    write_tag = tag_t'('x);

    // Unlike read, write can happen at the cycle of lock release. However the writer must ensure
    // that the new lock acquirer will not access the same address.
    unique case (lock_holder_q)
      LockHolderRefill: begin
        write_addr = refill_write_addr;
        write_req_tag = refill_write_req_tag;
        write_req_data = refill_write_req_data;
        for (int i = 0; i < NumWays; i++) write_ways[i] = refill_write_way == i;
        write_data = refill_write_data;
        write_tag = refill_write_tag;
      end
      LockHolderFlush: begin
        write_addr = {flush_write_index, 3'dx};
        write_req_tag = flush_write_req_tag;
        write_ways = flush_write_ways;
        write_tag = flush_write_tag;
      end
      LockHolderAccess: begin
        write_addr = access_write_addr;
        write_req_tag = access_write_req_tag;
        for (int i = 0; i < NumWays; i++) write_ways[i] = access_write_way == i;
        write_tag = access_write_tag;
      end
      default:;
    endcase
  end

  ////////////////////////
  // SRAM Instantiation //
  ////////////////////////

  // When a read/write to the same address happens in the same cycle, they may cause conflict.
  // While it is possible to keep track of the previous address and stall for one cycle if
  // possible, it is generally difficult to ensure correctness when there are so many components
  // that can access this SRAM. So we instead choose to use bypass here.
  //
  // The bypassed tag/data is shared across all ways but the valid bits are private to each ways
  // because of write enable signals.

  tag_t        tag_bypass;
  logic [63:0] data_bypass;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      tag_bypass <= tag_t'('x);
      data_bypass <= 'x;
    end else begin
      if (read_req_tag) begin
        tag_bypass <= write_tag;
      end
      if (read_req_data) begin
        data_bypass <= write_data;
      end
    end
  end

  for (genvar i = 0; i < NumWays; i++) begin

    logic tag_bypass_valid;
    logic data_bypass_valid;

    tag_t        tag_raw;
    logic [63:0] data_raw;

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        tag_bypass_valid <= 1'b0;
        data_bypass_valid <= 1'b0;
      end else begin
        if (read_req_tag) begin
          tag_bypass_valid <= 1'b0;
          if (write_req_tag && write_ways[i] && write_addr[SetsWidth+3-1:3] == read_addr[SetsWidth+3-1:3]) begin
            tag_bypass_valid <= 1'b1;
          end
        end
        if (read_req_data) begin
          data_bypass_valid <= 1'b0;
          if (write_req_data && write_ways[i] && write_addr == read_addr[SetsWidth+3-1:0]) begin
            data_bypass_valid <= 1'b1;
          end
        end
      end
    end

    assign read_tag[i] = tag_bypass_valid ? tag_bypass : tag_raw;
    assign read_data[i] = data_bypass_valid ? data_bypass : data_raw;

    prim_generic_ram_simple_2p #(
        .Width           ($bits(tag_t)),
        .Depth           (2 ** SetsWidth),
        .DataBitsPerMask ($bits(tag_t))
    ) tag_ram (
        .clk_a_i   (clk_i),
        .clk_b_i   (clk_i),

        .a_req_i   (read_req_tag),
        .a_addr_i  (read_addr[SetsWidth+3-1:3]),
        .a_rdata_o (tag_raw),

        .b_req_i   (write_req_tag && write_ways[i]),
        .b_addr_i  (write_addr[SetsWidth+3-1:3]),
        .b_wdata_i (write_tag),
        .b_wmask_i ('1)
    );

    prim_generic_ram_simple_2p #(
        .Width           (64),
        .Depth           (2 ** (SetsWidth + 3)),
        .DataBitsPerMask (8)
    ) data_ram (
        .clk_a_i   (clk_i),
        .clk_b_i   (clk_i),

        .a_req_i   (read_req_data),
        .a_addr_i  (read_addr[SetsWidth+3-1:0]),
        .a_rdata_o (data_raw),

        .b_req_i   (write_req_data && write_ways[i]),
        .b_addr_i  (write_addr),
        .b_wdata_i (write_data),
        .b_wmask_i ('1)
    );
  end

  //////////////////
  // Refill Logic //
  //////////////////

  logic [PhysAddrLen-7:0] refill_req_address;
  logic [WaysWidth-1:0]   refill_req_way;

  logic [2:0] refill_index_q, refill_index_d;

  typedef enum logic [1:0] {
    RefillStateIdle,
    RefillStateProgress,
    RefillStateComplete
  } refill_state_e;

  refill_state_e refill_state_q = RefillStateIdle, refill_state_d;

  logic mem_grant_last;

  assign mem.e_valid = 1'b0;
  assign mem.e_sink = 'x;

  always_comb begin
    refill_write_way = 'x;
    refill_write_addr = 'x;
    refill_write_req_tag = 'x;
    refill_write_tag = tag_t'('x);
    refill_write_req_data = 'x;
    refill_write_data = 'x;

    refill_lock_acq = 1'b0;
    refill_lock_move = 1'b0;
    mem_grant_ready = 1'b0;

    mem_grant_last = 1'b0;

    refill_index_d = refill_index_q;
    refill_state_d = refill_state_q;

    unique case (refill_state_q)
      RefillStateIdle: begin
        if (mem_grant_valid) begin
          refill_index_d = mem_grant_opcode == AccessAckData ? 0 : 7;

          refill_lock_acq = 1'b1;
          refill_state_d = RefillStateProgress;
        end
      end
      RefillStateProgress: begin
        mem_grant_ready = refill_locked;
        refill_write_way = refill_req_way;
        refill_write_addr = {refill_req_address[SetsWidth-1:0], refill_index_q};

        refill_write_req_data = mem_grant_valid && mem_grant_opcode == AccessAckData && !mem_grant_denied;
        refill_write_data = mem_grant_data;

        // Update the metadata. This should only be done once, we can do it in either time.
        refill_write_req_tag = mem_grant_valid && &refill_index_q && !mem_grant_denied;
        refill_write_tag.tag = refill_req_address[PhysAddrLen-7:SetsWidth];
        refill_write_tag.valid = 1'b1;

        if (mem_grant_valid && mem_grant_ready) begin
          refill_index_d = refill_index_q + 1;
          if (&refill_index_q) begin
            mem_grant_last = 1'b1;
            refill_state_d = RefillStateComplete;
          end
        end
      end
      RefillStateComplete: begin
        refill_index_d = 0;
        refill_lock_move = 1'b1;
        refill_state_d = RefillStateIdle;
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      refill_index_q <= 0;
      refill_state_q <= RefillStateIdle;
    end else begin
      refill_index_q <= refill_index_d;
      refill_state_q <= refill_state_d;
    end
  end

  ///////////////////////////////
  // Address Translation Logic //
  ///////////////////////////////

  logic [PhysAddrLen-13:0] ppn_pulse;
  page_prot_t              ppn_perm_pulse;
  logic                    ppn_valid_pulse;

  logic                    ptw_req_valid;
  logic [VirtAddrLen-13:0] ptw_req_vpn;
  logic                    ptw_resp_valid;
  logic [PhysAddrLen-13:0] ptw_resp_ppn;
  page_prot_t              ptw_resp_perm;

  muntjac_tlb #(
    .PhysAddrLen (PhysAddrLen)
  ) tlb (
      .clk_i            (clk_i),
      .rst_ni           (rst_ni),
      .satp_i           (req_atp),
      .req_valid_i      (req_valid && req_atp[63]),
      .req_vpn_i        (req_address[38:12]),
      .resp_valid_o     (ppn_valid_pulse),
      .resp_ppn_o       (ppn_pulse),
      .resp_perm_o      (ppn_perm_pulse),
      .flush_req_i      (flush_valid),
      // FIXME: Properly respond to flush signals if TLB cannot be flushed in a single cycle
      .flush_resp_o     (),
      .ptw_req_ready_i  (1'b1),
      .ptw_req_valid_o  (ptw_req_valid),
      .ptw_req_vpn_o    (ptw_req_vpn),
      .ptw_resp_valid_i (ptw_resp_valid),
      .ptw_resp_ppn_i   (ptw_resp_ppn),
      .ptw_resp_perm_i  (ptw_resp_perm)
  );

  muntjac_ptw #(
    .PhysAddrLen (PhysAddrLen)
  ) ptw (
      .clk_i             (clk_i),
      .rst_ni            (rst_ni),
      .satp_i            (req_atp),
      .req_valid_i       (ptw_req_valid),
      .req_vpn_i         (ptw_req_vpn),
      .resp_valid_o      (ptw_resp_valid),
      .resp_ppn_o        (ptw_resp_ppn),
      .resp_perm_o       (ptw_resp_perm),
      .mem_req_ready_i   (mem_ptw.a_ready),
      .mem_req_valid_o   (mem_ptw.a_valid),
      .mem_req_address_o (mem_ptw.a_address),
      .mem_resp_valid_i  (mem_ptw.d_valid),
      .mem_resp_data_i   (mem_ptw.d_data)
  );

  assign mem_ptw.a_opcode = Get;
  assign mem_ptw.a_param = 0;
  assign mem_ptw.a_size = 1;
  assign mem_ptw.a_source = PtwSourceBase;
  assign mem_ptw.a_mask = '1;
  assign mem_ptw.a_corrupt = 1'b0;
  assign mem_ptw.a_data = 'x;

  assign mem_ptw.b_ready = 1'b1;

  assign mem_ptw.c_valid = 1'b0;
  assign mem_ptw.c_opcode = tl_c_op_e'('x);
  assign mem_ptw.c_param = 'x;
  assign mem_ptw.c_size = 'x;
  assign mem_ptw.c_source = 'x;
  assign mem_ptw.c_address = 'x;
  assign mem_ptw.c_corrupt = 1'bx;
  assign mem_ptw.c_data = 'x;

  assign mem_ptw.d_ready = 1'b1;

  assign mem_ptw.e_valid = 1'b0;
  assign mem_ptw.e_sink = 'x;

  // PPN response is just single pulse. The logic below extends it.
  logic [43:0] ppn_latch;
  logic        ppn_valid_latch;
  page_prot_t  ppn_perm_latch;

  always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
          ppn_valid_latch <= 1'b0;
          ppn_latch <= 'x;
          ppn_perm_latch <= page_prot_t'('x);
      end else begin
          if (ppn_valid_pulse) begin
              ppn_valid_latch <= 1'b1;
              ppn_latch <= ppn_pulse;
              ppn_perm_latch <= ppn_perm_pulse;
          end
          if (req_valid && req_atp[63]) begin
              ppn_valid_latch <= 1'b0;
          end
      end
  end

  wire             ppn_valid = ppn_valid_pulse ? 1'b1 : ppn_valid_latch;
  wire [43:0]      ppn       = ppn_valid_pulse ? ppn_pulse : ppn_latch;
  wire page_prot_t ppn_perm  = ppn_valid_pulse ? ppn_perm_pulse : ppn_perm_latch;

  ///////////////////////////
  // Cache tag comparision //
  ///////////////////////////

  // Physical address of read_addr_latch.
  // Note: If read_physical_latch is 0, the user needs to ensure ppn_valid is 1.
  wire [PhysAddrLen-3-1:0] read_addr_phys = {read_physical_latch ? read_addr_latch[AddrLen-3-1:9] : ppn, read_addr_latch[8:0]};

  logic [WaysWidth-1:0] evict_way_q, evict_way_d;

  logic [NumWays-1:0] hit;
  // Contain the way number that hits. If none of the way hits, it will contain an empty way
  // or a selected way for eviction.
  logic [WaysWidth-1:0] hit_way;

  always_comb begin
    // Find cache line that hits
    hit = '0;
    for (int i = 0; i < NumWays; i++) begin
      if (read_tag[i].valid &&
          read_tag[i].tag == read_addr_phys[PhysAddrLen-3-1:SetsWidth+3]) begin
        hit[i] = 1'b1;
      end
    end

    // Pseudo-FIFO fallback
    hit_way = evict_way_q;

    // Empty way fallback
    for (int i = NumWays - 1; i >= 0; i--) begin
      if (!read_tag[i].valid) begin
        hit_way = i;
      end
    end

    for (int i = NumWays - 1; i >= 0; i--) begin
      if (hit[i]) begin
        hit_way = i;
      end
    end
  end

  wire tag_t hit_tag = read_tag[hit_way];

  /////////////////
  // Flush Logic //
  /////////////////

  typedef enum logic [1:0] {
    FlushStateReset,
    FlushStateIdle,
    FlushStateCheck,
    FlushStateDone
  } flush_state_e;

  flush_state_e flush_state_q = FlushStateReset, flush_state_d;
  logic [SetsWidth-1:0] flush_index_q, flush_index_d;

  always_comb begin
    flush_write_ways = 'x;
    flush_write_index = 'x;
    flush_write_req_tag = 1'b0;
    flush_write_tag = tag_t'('x);

    flush_lock_acq = 1'b0;
    flush_lock_rel = 1'b0;

    flush_ready = 1'b0;

    flush_state_d = flush_state_q;
    flush_index_d = flush_index_q;

    unique case (flush_state_q)
      // Reset all states to invalid, discard changes if any.
      FlushStateReset: begin
        flush_write_ways = '1;
        flush_write_index = flush_index_q;
        flush_write_req_tag = 1'b1;
        flush_write_tag.valid = 1'b0;

        flush_index_d = flush_index_q + 1;

        if (&flush_index_q) begin
          flush_lock_rel = 1'b1;
          flush_state_d = FlushStateDone;
        end
      end

      // Read the tag to prepare for the dirtiness check.
      // This also serves as the idle state as flush_locking would normally stay low.
      FlushStateIdle: begin
        if (flush_locking) begin
          flush_state_d = FlushStateReset;
        end

        if (flush_valid) begin
          flush_lock_acq = 1'b1;
        end
      end

      FlushStateDone: begin
        flush_ready = 1'b1;
        flush_state_d = FlushStateIdle;
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      flush_state_q <= FlushStateReset;
      flush_index_q <= '0;
    end else begin
      flush_state_q <= flush_state_d;
      flush_index_q <= flush_index_d;
    end
  end

  ////////////////
  // Main Logic //
  ////////////////

  typedef enum logic [3:0] {
    StateIdle,
    StateFetch,
    StateReplay,
    StateWaitTLB,
    StateFill,
    StateExceptionLocked,
    StateException,
    StateFlush
  } state_e;

  state_e state_q = StateIdle, state_d;

  // Information about the exception to be reported in StateException
  exc_cause_e ex_code_q, ex_code_d;

  // Fill-related logic
  logic req_sent_q, req_sent_d;

  // Helper signal to detect if req_address is a canonical address
  wire canonical_virtual  = ~|req_address[63:VirtAddrLen-1] | &req_address[63:VirtAddrLen-1];
  wire canonical_physical = ~|req_address[63:PhysAddrLen];

  logic [63:0] address_q, address_d;
  logic        atp_mode_q, atp_mode_d;
  logic        prv_q, prv_d;
  logic        sum_q, sum_d;

  wire [63:0] hit_data = read_data[hit_way];
  wire [31:0] hit_data_aligned = address_q[2] ? hit_data[63:32] : hit_data[31:0];

  logic [WaysWidth-1:0] way_q, way_d;

  wire [PhysAddrLen-1:0] address_phys = req_atp[63] ? {ppn, address_q[11:0]} : address_q[PhysAddrLen-1:0];

  assign mem.a_source = SourceBase;
  assign mem.a_corrupt = 1'b0;
  assign mem.a_data = 'x;
  wire mem_req_ready   = mem.a_ready;

  always_comb begin
    resp_valid = 1'b0;
    resp_value = 'x;
    ex_valid = 1'b0;
    resp_ex_code = exc_cause_e'('x);
    mem.a_valid = 1'b0;
    mem.a_opcode = tl_a_op_e'('x);
    mem.a_address = 'x;
    mem.a_param = 'x;
    mem.a_size = 'x;
    mem.a_mask = 'x;

    refill_req_address = address_phys[PhysAddrLen-1:6];
    refill_req_way = way_q;

    access_read_req_tag = 1'b0;
    access_read_req_data = 1'b0;
    access_read_addr = 'x;
    access_read_physical = !req_atp[63];

    access_write_way = hit_way;
    access_write_addr = address_q[3+:SetsWidth+3];
    access_write_req_tag = 1'b0;
    access_write_tag = hit_tag;

    access_lock_acq = 1'b0;
    access_lock_rel = 1'b0;

    flush_valid = 1'b0;

    state_d = state_q;
    address_d = address_q;
    atp_mode_d = atp_mode_q;
    prv_d = prv_q;
    sum_d = sum_q;
    evict_way_d = evict_way_q;
    way_d = way_q;
    ex_code_d = ex_code_q;
    req_sent_d = req_sent_q;

    unique case (state_q)
      StateIdle:;

      StateFetch: begin
        // Release the access lock. In this state we either complete an access, or we need to
        // wait for refill/TLB access. In either case we will need to release the lock and
        // re-acquire later to prevent deadlock.
        access_lock_rel = 1'b1;

        if (atp_mode_q && !ppn_valid) begin
          // TLB miss, wait for it to be ready again.
          state_d = StateWaitTLB;
        end
        else if (atp_mode_q && (
            !ppn_perm.valid  || // Invalid
            !ppn_perm.executable || // Not executable denied
            (!ppn_perm.user && !prv_q) || // Accessing supervisor memory
            (ppn_perm.user && prv_q && !sum_q) // Accessing user memory without SUM
        )) begin
          // Exception from page table lookup.
          state_d = StateException;
          ex_code_d = EXC_CAUSE_INSTR_PAGE_FAULT;
        end else if (|hit) begin
          // Cache valid with required permission.

          resp_valid = 1'b1;
          resp_value = hit_data_aligned;
          state_d = StateIdle;
        end else begin
          way_d = hit_way;
          if (~|hit) begin
            evict_way_d = evict_way_q + 1;
          end

          req_sent_d = 1'b0;
          state_d = StateFill;
        end
      end

      StateReplay: begin
        access_read_req_tag = 1'b1;
        access_read_req_data = 1'b1;
        access_read_addr = address_d[AddrLen-1:3];
        if (access_locking) state_d = StateFetch;
      end

      StateWaitTLB: begin
        if (ppn_valid) begin
          access_lock_acq = 1'b1;
          state_d = StateReplay;
        end
      end

      StateFill: begin
        mem.a_valid = !req_sent_q;
        mem.a_opcode = Get;
        mem.a_param = 0;
        mem.a_size = 6;
        mem.a_address = {address_phys[PhysAddrLen-1:6], 6'd0};
        mem.a_mask = '1;
        if (mem_req_ready) begin
          req_sent_d = 1'b1;
        end

        if (mem_grant_last) begin
          if (mem_grant_denied) begin
            ex_code_d = EXC_CAUSE_INSTR_ACCESS_FAULT;
            state_d = StateExceptionLocked;
          end else begin
            // Refiller will give us the lock after refilling completed, so no need to deal with lock here.
            state_d = StateReplay;
          end
        end
      end

      StateExceptionLocked: begin
        if (lock_holder_q == LockHolderAccess) begin
          access_lock_rel = 1'b1;
          state_d = StateException;
        end
      end

      StateException: begin
        ex_valid = 1'b1;
        resp_ex_code = ex_code_q;
        state_d = StateIdle;
      end

      StateFlush: begin
        if (flush_ready) begin
          access_lock_acq = 1'b1;
          state_d = StateReplay;
        end
      end
    endcase

    if (req_valid) begin
      address_d = req_address;
      atp_mode_d = req_atp[63];
      prv_d = req_prv;
      sum_d = req_sum;

      // Access the cache
      access_lock_acq = 1'b1;
      access_read_req_tag = 1'b1;
      access_read_req_data = 1'b1;
      access_read_addr = address_d[AddrLen-1:3];

      state_d = StateFetch;

      // If we failed to acquire the lock this cycle, move into replay state.
      if (!access_locking) state_d = StateReplay;

      if (req_atp[63] && !canonical_virtual) begin
        state_d = StateExceptionLocked;
        ex_code_d = EXC_CAUSE_INSTR_PAGE_FAULT;
      end

      if (!req_atp[63] && !canonical_physical) begin
        state_d = StateExceptionLocked;
        ex_code_d = EXC_CAUSE_INSTR_ACCESS_FAULT;
      end

      if (req_reason ==? 4'b1x11) begin
        access_lock_acq = 1'b0;
        flush_valid = 1'b1;
        state_d = StateFlush;
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= StateFlush;
      address_q <= '0;
      atp_mode_q <= 1'b0;
      prv_q <= 1'bx;
      sum_q <= 1'bx;
      evict_way_q <= 0;
      way_q <= 'x;
      req_sent_q <= '0;
      ex_code_q <= exc_cause_e'('x);
    end else begin
      state_q <= state_d;
      address_q <= address_d;
      atp_mode_q <= atp_mode_d;
      prv_q <= prv_d;
      sum_q <= sum_d;
      evict_way_q <= evict_way_d;
      way_q <= way_d;
      req_sent_q <= req_sent_d;
      ex_code_q <= ex_code_d;
    end
  end

endmodule
