`include "tl_util.svh"
`include "prim_assert.sv"

// Non-coherent I$ (Adapted from muntjac_icache_coherent)
module muntjac_icache import muntjac_pkg::*; import tl_pkg::*; # (
    parameter int unsigned DataWidth   = 64,
    // Number of ways is `2 ** WaysWidth`.
    parameter int unsigned WaysWidth   = 2,
    // Number of sets is `2 ** SetsWidth`.
    parameter int unsigned SetsWidth   = 6,
    parameter int unsigned VirtAddrLen = 39,
    parameter int unsigned PhysAddrLen = 56,
    parameter int unsigned SourceWidth = 1,
    parameter int unsigned SinkWidth   = 1,
    parameter bit [SourceWidth-1:0] SourceBase  = 0,
    parameter bit [SourceWidth-1:0] PtwSourceBase = 0,

    parameter int unsigned TlbNumWays = 32,
    parameter int unsigned TlbSetsWidth = 0,

    parameter bit          EnableHpm   = 0
) (
    input  logic clk_i,
    input  logic rst_ni,

    // Interface to CPU
    input  icache_h2d_t cache_h2d_i,
    output icache_d2h_t cache_d2h_o,

    // Hardware performance monitor events
    output logic hpm_access_o,
    output logic hpm_miss_o,
    output logic hpm_tlb_miss_o,

    // Channel for I$
    `TL_DECLARE_HOST_PORT(DataWidth, PhysAddrLen, SourceWidth, SinkWidth, mem)
);

  // This is the largest address width that we ever have to deal with.
  localparam LogicAddrLen = VirtAddrLen > PhysAddrLen ? VirtAddrLen : PhysAddrLen;

  localparam LineWidth = 6;

  localparam InterleaveWidth = $clog2(DataWidth / 32);
  localparam NumInterleave = 2 ** InterleaveWidth;
  localparam InterleaveMask = NumInterleave - 1;

  localparam OffsetWidth = 6 - 2 - InterleaveWidth;

  localparam NumWays = 2 ** WaysWidth;

  localparam DataWidthInBytes = DataWidth / 8;
  localparam NonBurstSize = $clog2(DataWidthInBytes);

  if (SetsWidth > 6) $fatal(1, "PIPT cache's SetsWidth is bounded by 6");

  `TL_DECLARE(DataWidth, PhysAddrLen, SourceWidth, SinkWidth, mem);

  // Registers mem_d so its content will hold until we consumed it.
  tl_regslice #(
    .DataWidth (DataWidth),
    .AddrWidth (PhysAddrLen),
    .SourceWidth (SourceWidth),
    .SinkWidth (SinkWidth),
    .GrantMode (2)
  ) mem_reg (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_DEVICE_PORT(host, mem),
    `TL_FORWARD_HOST_PORT(device, mem)
  );

  assign mem_b_ready = 1'b1;
  assign mem_c_valid = 1'b0;
  assign mem_c       = 'x;
  assign mem_e_valid = 1'b0;
  assign mem_e       = 'x;

  /////////////////////////////////////////
  // #region Burst tracker instantiation //

  wire mem_a_last;
  wire mem_d_last;

  logic [OffsetWidth-1:0] mem_d_idx;

  tl_burst_tracker #(
    .AddrWidth (PhysAddrLen),
    .DataWidth (DataWidth),
    .SourceWidth (SourceWidth),
    .SinkWidth (SinkWidth),
    .MaxSize (6)
  ) mem_burst_tracker (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_TAP_PORT(link, mem),
    .req_len_o (),
    .rel_len_o (),
    .gnt_len_o (),
    .req_idx_o (),
    .rel_idx_o (),
    .gnt_idx_o (mem_d_idx),
    .req_left_o (),
    .rel_left_o (),
    .gnt_left_o (),
    .req_first_o (),
    .rel_first_o (),
    .gnt_first_o (),
    .req_last_o (mem_a_last),
    .rel_last_o (),
    .gnt_last_o (mem_d_last)
  );

  // #endregion
  /////////////////////////////////////////

  //////////////////////////////
  // #region Helper functions //

  function automatic logic [63:0] tl_align_load(
      input logic [DataWidth-1:0] value,
      input logic [NonBurstSize-1:0] addr
  );
    logic [DataWidth/64-1:0][63:0] split = value;
    return split[addr >> 3];
  endfunction

  // #endregion
  //////////////////////////////

  /////////////////////////////
  // #region Type definition //

  typedef struct packed {
    // Tag, excluding the bits used for direct-mapped access and last 6 bits of offset.
    logic [PhysAddrLen-SetsWidth-LineWidth-1:0] tag;
    logic valid;
  } tag_t;

  // #endregion
  /////////////////////////////

  ////////////////////////////////
  // #region CPU Facing signals //

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

  // #endregion
  ////////////////////////////////

  ///////////////////////////////////
  // #region A channel arbitration //

  typedef `TL_A_STRUCT(DataWidth, PhysAddrLen, SourceWidth, SinkWidth) req_t;

  localparam ANums = 2;
  localparam AIdxPtw    = 0;
  localparam AIdxRefill = 1;

  // Grouped signals before multiplexing/arbitration
  req_t [ANums-1:0] mem_a_mult;
  logic [ANums-1:0] mem_a_valid_mult;
  logic [ANums-1:0] mem_a_ready_mult;

  // Signals for arbitration
  logic [ANums-1:0] mem_a_arb_grant;
  logic             mem_a_locked;
  logic [ANums-1:0] mem_a_selected;

  openip_round_robin_arbiter #(.WIDTH(ANums)) mem_a_arb (
    .clk     (clk_i),
    .rstn    (rst_ni),
    .enable  (mem_a_valid && mem_a_ready && !mem_a_locked),
    .request (mem_a_valid_mult),
    .grant   (mem_a_arb_grant)
  );

  // Perform arbitration, and make sure that until we encounter mem_a_last we keep the connection stable.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      mem_a_locked <= 1'b0;
      mem_a_selected <= '0;
    end
    else begin
      if (mem_a_valid && mem_a_ready) begin
        if (!mem_a_locked) begin
          mem_a_locked   <= 1'b1;
          mem_a_selected <= mem_a_arb_grant;
        end
        if (mem_a_last) begin
          mem_a_locked <= 1'b0;
        end
      end
    end
  end

  wire [ANums-1:0] mem_a_select = mem_a_locked ? mem_a_selected : mem_a_arb_grant;

  for (genvar i = 0; i < ANums; i++) begin
    assign mem_a_ready_mult[i] = mem_a_select[i] && mem_a_ready;
  end

  // Do the post-arbitration multiplexing
  always_comb begin
    mem_a = req_t'('x);
    mem_a_valid = 1'b0;
    for (int i = ANums - 1; i >= 0; i--) begin
      if (mem_a_select[i]) begin
        mem_a = mem_a_mult[i];
        mem_a_valid = mem_a_valid_mult[i];
      end
    end
  end

  // #endregion
  ///////////////////////////////////

  //////////////////////////////////////
  // #region D channel demultiplexing //

  wire mem_d_valid_refill  = mem_d_valid && mem_d.source != PtwSourceBase;
  wire mem_d_valid_ptw     = mem_d_valid && mem_d.source == PtwSourceBase;

  logic mem_d_ready_refill;
  logic mem_d_ready_ptw;
  assign mem_d_ready = mem_d_valid_refill ? mem_d_ready_refill : (mem_d_valid_ptw ? mem_d_ready_ptw : 1'b1);

  // #endregion
  //////////////////////////////////////

  //////////////////////////////
  // #region Lock arbitration //

  logic flush_tracker_valid;
  logic refill_tracker_valid;

  logic refill_lock_acq;
  logic flush_lock_acq;

  wire nothing_in_progress = !(refill_tracker_valid || flush_tracker_valid);

  logic refill_locking;
  logic flush_locking;

  // Arbitrate on the new holder of the lock
  always_comb begin
    refill_locking = 1'b0;
    flush_locking = 1'b0;

    if (nothing_in_progress) begin
      priority case (1'b1)
        // This blocks channel D, so it must have highest priority by TileLink rule
        refill_lock_acq: begin
          refill_locking = 1'b1;
        end
        flush_lock_acq: begin
          flush_locking = 1'b1;
        end
        default:;
      endcase
    end
  end

  // #endregion
  //////////////////////////////

  ///////////////////////////////////
  // #region SRAM access multiplex //

  logic                      access_tag_read_req;
  logic                      access_tag_read_gnt;
  logic [LogicAddrLen-6-1:0] access_tag_read_addr;
  logic                      access_tag_read_physical;

  logic                      access_data_read_req;
  logic                      access_data_read_gnt;
  logic [SetsWidth+4-1:0]    access_data_read_addr;

  logic                           refill_tag_write_req;
  logic                           refill_tag_write_gnt;
  logic [SetsWidth-1:0]           refill_tag_write_addr;
  logic [WaysWidth-1:0]           refill_tag_write_way;
  tag_t                           refill_tag_write_data;

  logic                           refill_data_write_req;
  logic                           refill_data_write_gnt;
  logic [SetsWidth+4-1:0]         refill_data_write_addr;
  logic [WaysWidth-1:0]           refill_data_write_way;
  logic [NumInterleave-1:0][31:0] refill_data_write_data;

  logic                  flush_tag_write_req;
  logic                  flush_tag_write_gnt;
  logic [SetsWidth-1:0]  flush_tag_write_addr;
  logic [NumWays-1:0]    flush_tag_write_ways;
  tag_t                  flush_tag_write_data;

  logic                              tag_write_req;
  logic                              tag_read_req;
  logic [LogicAddrLen-LineWidth-1:0] tag_addr;
  logic [NumWays-1:0]                tag_write_ways;
  tag_t                              tag_write_data;
  logic                              tag_read_physical;
  tag_t                              tag_read_data [NumWays];

  logic                           data_write_req;
  logic                           data_read_req;
  logic [SetsWidth+4-1:0]         data_addr;
  logic [WaysWidth-1:0]           data_way;
  logic [NumInterleave-1:0][31:0] data_write_data;
  logic                           data_wide;
  logic [31:0]                    data_read_data [NumWays];

  always_comb begin
    refill_tag_write_gnt = 1'b0;
    flush_tag_write_gnt = 1'b0;
    access_tag_read_gnt = 1'b0;

    tag_write_req = 1'b0;
    tag_read_req = 1'b0;
    tag_addr = 'x;
    tag_write_ways = '0;
    tag_write_data = tag_t'('x);
    tag_read_physical = 1'b1;

    priority case (1'b1)
      refill_tag_write_req: begin
        refill_tag_write_gnt = 1'b1;
        tag_write_req = 1'b1;
        tag_addr[SetsWidth-1:0] = refill_tag_write_addr;
        for (int i = 0; i < NumWays; i++) tag_write_ways[i] = refill_tag_write_way == i;
        tag_write_data = refill_tag_write_data;
      end

      flush_tag_write_req: begin
        flush_tag_write_gnt = 1'b1;
        tag_write_req = 1'b1;
        tag_addr[SetsWidth-1:0] = flush_tag_write_addr;
        tag_write_ways = flush_tag_write_ways;
        tag_write_data = flush_tag_write_data;
      end

      access_tag_read_req: begin
        access_tag_read_gnt = 1'b1;
        tag_read_req = 1'b1;
        tag_addr = access_tag_read_addr;
        tag_read_physical = access_tag_read_physical;
      end
      default:;
    endcase

    // These logic assumes that all their requests are handled immediately.
    `ASSERT(refill_tag_write, refill_tag_write_req |-> refill_tag_write_gnt);
    `ASSERT(flush_tag_write, flush_tag_write_req |-> flush_tag_write_gnt);
  end

  always_comb begin
    refill_data_write_gnt = 1'b0;
    access_data_read_gnt = 1'b0;

    data_write_req = 1'b0;
    data_read_req = 1'b0;
    data_addr = 'x;
    data_way = 'x;
    data_write_data = 'x;
    data_wide = 1'b0;

    priority case (1'b1)
      refill_data_write_req: begin
        refill_data_write_gnt = 1'b1;
        data_write_req = 1'b1;
        data_addr = refill_data_write_addr;
        data_way = refill_data_write_way;
        data_write_data = refill_data_write_data;
        data_wide = 1'b1;
      end

      access_data_read_req: begin
        access_data_read_gnt = 1'b1;
        data_read_req = 1'b1;
        data_addr = access_data_read_addr;
      end
      default:;
    endcase

    if (data_wide) begin
      data_addr = data_addr ^ (data_way & InterleaveMask);
    end

    `ASSERT(refill_data_write, refill_data_write_req |-> refill_data_write_gnt);
  end

  logic tag_read_physical_latch;
  logic [LogicAddrLen-6-1:0] tag_read_addr_latch;
  logic [3:0] data_read_addr_latch;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      tag_read_physical_latch <= 1'b1;
      tag_read_addr_latch <= 'x;
      data_read_addr_latch <= 'x;
    end else begin
      if (tag_read_req) begin
        tag_read_physical_latch <= tag_read_physical;
        tag_read_addr_latch <= tag_addr;
      end
      if (data_read_req) begin
        data_read_addr_latch <= data_addr[3:0];
      end
    end
  end

  // Interleave the read data
  logic [31:0] data_read_data_interleave [NumWays];
  for (genvar i = 0; i < NumWays; i++) begin
    assign data_read_data[i] = data_read_data_interleave[i ^ (data_read_addr_latch & InterleaveMask)];
  end

  // Interleave the write ways and data
  logic [NumWays-1:0] data_write_ways_interleave;
  logic [NumInterleave-1:0][31:0] data_write_data_interleave;
  for (genvar i = 0; i < NumWays; i++) begin
    assign data_write_ways_interleave[i] = (data_way &~ InterleaveMask) == (i &~ InterleaveMask);
  end
  for (genvar i = 0; i < NumInterleave; i++) begin
    assign data_write_data_interleave[i] = data_write_data[i ^ (data_addr & InterleaveMask)];
  end

  // #endregion
  ///////////////////////////////////

  ////////////////////////////////
  // #region SRAM Instantiation //

  for (genvar i = 0; i < NumWays; i++) begin: ram

    prim_ram_1p #(
        .Width           ($bits(tag_t)),
        .Depth           (2 ** SetsWidth),
        .DataBitsPerMask ($bits(tag_t))
    ) tag_ram (
        .clk_i   (clk_i),
        .req_i   (tag_read_req || tag_write_req),
        .write_i (tag_write_req && tag_write_ways[i]),
        .addr_i  (tag_addr[SetsWidth-1:0]),
        .wdata_i (tag_write_data),
        .wmask_i ('1),
        .rdata_o (tag_read_data[i])
    );

    wire [SetsWidth+4-1:0] data_addr_effective = data_addr ^ (data_wide ? (i & InterleaveMask) : 0);

    prim_ram_1p #(
        .Width           (32),
        .Depth           (2 ** (SetsWidth + 4)),
        .DataBitsPerMask (32)
    ) data_ram (
        .clk_i   (clk_i),
        .req_i   (data_read_req || data_write_req),
        .write_i (data_write_req && data_write_ways_interleave[i]),
        .addr_i  (data_addr_effective),
        .wdata_i (data_write_data_interleave[i & InterleaveMask]),
        .wmask_i ('1),
        .rdata_o (data_read_data_interleave[i])
    );
  end

  // #endregion
  ////////////////////////////////

  //////////////////////////
  // #region Refill Logic //

  logic [PhysAddrLen-7:0] refill_req_address;
  logic [WaysWidth-1:0]   refill_req_way;

  typedef enum logic {
    RefillStateIdle,
    RefillStateProgress
  } refill_state_e;

  refill_state_e refill_state_q = RefillStateIdle, refill_state_d;

  logic refill_tracker_valid_d;

  always_comb begin
    refill_tag_write_req = 1'b0;
    refill_tag_write_addr = 'x;
    refill_tag_write_way = 'x;
    refill_tag_write_data = tag_t'('x);

    refill_data_write_req = 1'b0;
    refill_data_write_addr = 'x;
    refill_data_write_way = 'x;
    refill_data_write_data = 'x;

    refill_tracker_valid_d = refill_tracker_valid;
    refill_lock_acq = 1'b0;
    mem_d_ready_refill = 1'b0;

    refill_state_d = refill_state_q;

    unique case (refill_state_q)
      RefillStateIdle: begin
        if (mem_d_valid_refill) begin
          refill_lock_acq = 1'b1;
          if (refill_locking) begin
            refill_state_d = RefillStateProgress;
            refill_tracker_valid_d = 1'b1;
          end
        end
      end
      RefillStateProgress: begin
        if (mem_d_valid_refill) begin
          mem_d_ready_refill = 1'b1;

          // If the beat contains data, write it.
          if (!mem_d.denied) begin
            refill_data_write_req = 1'b1;
            refill_data_write_way = refill_req_way;
            refill_data_write_addr = {refill_req_address[SetsWidth-1:0], 4'(mem_d_idx << InterleaveWidth)};
            refill_data_write_data = mem_d.data;
          end

          // Update the metadata. This should only be done once, we can do it in either time.
          if (mem_d_last && !mem_d.denied) begin
            refill_tag_write_req = 1'b1;
            refill_tag_write_way = refill_req_way;
            refill_tag_write_addr = refill_req_address[SetsWidth-1:0];
            refill_tag_write_data.tag = refill_req_address[PhysAddrLen-7:SetsWidth];
            refill_tag_write_data.valid = 1'b1;
          end

          if (mem_d_ready_refill) begin
            if (mem_d_last) begin
              refill_tracker_valid_d = 1'b0;
              refill_state_d = RefillStateIdle;
            end
          end
        end
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      refill_state_q <= RefillStateIdle;
      refill_tracker_valid <= 1'b0;
    end else begin
      refill_state_q <= refill_state_d;
      refill_tracker_valid <= refill_tracker_valid_d;
    end
  end

  // #endregion
  //////////////////////////

  ///////////////////////////////////////
  // #region Address Translation Logic //

  logic                    tlb_resp_valid;
  logic                    tlb_resp_hit;
  logic [PhysAddrLen-13:0] tlb_resp_ppn;
  page_prot_t              tlb_resp_perm;

  logic flush_tlb_resp;

  logic [VirtAddrLen-13:0] ptw_req_vpn;
  logic                    ptw_resp_valid;
  logic [PhysAddrLen-13:0] ptw_resp_ppn;
  page_prot_t              ptw_resp_perm;

  muntjac_tlb #(
    .NumWays (TlbNumWays),
    .SetsWidth (TlbSetsWidth),
    .PhysAddrLen (PhysAddrLen)
  ) tlb (
      .clk_i            (clk_i),
      .rst_ni           (rst_ni),
      .req_valid_i      (req_valid && req_atp[63]),
      .req_asid_i       (req_atp[44 +: 16]),
      .req_vpn_i        (req_address[38:12]),
      .resp_hit_o       (tlb_resp_hit),
      .resp_ppn_o       (tlb_resp_ppn),
      .resp_perm_o      (tlb_resp_perm),
      .flush_req_i      (flush_valid),
      .flush_resp_o     (flush_tlb_resp),
      .refill_valid_i   (ptw_resp_valid),
      .refill_asid_i    (req_atp[44 +: 16]),
      .refill_vpn_i     (ptw_req_vpn),
      .refill_ppn_i     (ptw_resp_ppn),
      .refill_perm_i    (ptw_resp_perm)
  );

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      tlb_resp_valid <= 1'b0;
    end else begin
      tlb_resp_valid <= req_valid && req_atp[63];
    end
  end

  logic                    ptw_a_valid;
  logic [NonBurstSize-1:0] ptw_a_address;

  muntjac_ptw #(
    .PhysAddrLen (PhysAddrLen)
  ) ptw (
      .clk_i             (clk_i),
      .rst_ni            (rst_ni),
      .req_valid_i       (tlb_resp_valid && !tlb_resp_hit),
      .req_vpn_i         (ptw_req_vpn),
      .req_pt_ppn_i      (req_atp[PhysAddrLen-13:0]),
      .resp_valid_o      (ptw_resp_valid),
      .resp_ppn_o        (ptw_resp_ppn),
      .resp_perm_o       (ptw_resp_perm),
      .mem_req_ready_i   (mem_a_ready_mult[AIdxPtw]),
      .mem_req_valid_o   (mem_a_valid_mult[AIdxPtw]),
      .mem_req_address_o (mem_a_mult[AIdxPtw].address),
      .mem_resp_valid_i  (mem_d_valid_ptw && ptw_a_valid),
      .mem_resp_data_i   (tl_align_load(mem_d.data, ptw_a_address))
  );

  assign mem_d_ready_ptw = ptw_a_valid;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      ptw_a_valid <= 1'b0;
      ptw_a_address <= 'x;
    end else begin
      if (mem_d_valid_ptw) begin
        ptw_a_valid <= 1'b0;
      end
      if (mem_a_valid_mult[AIdxPtw] && mem_a_ready_mult[AIdxPtw]) begin
        ptw_a_valid <= 1'b1;
        ptw_a_address <= mem_a_mult[AIdxPtw].address;
      end
    end
  end

  assign mem_a_mult[AIdxPtw].opcode = Get;
  assign mem_a_mult[AIdxPtw].param = 0;
  assign mem_a_mult[AIdxPtw].size = 1;
  assign mem_a_mult[AIdxPtw].source = PtwSourceBase;
  assign mem_a_mult[AIdxPtw].mask = '1;
  assign mem_a_mult[AIdxPtw].corrupt = 1'b0;
  assign mem_a_mult[AIdxPtw].data = 'x;

  // Combine TLB and PTW output.
  wire [PhysAddrLen-13:0] ppn_pulse       = tlb_resp_valid ? tlb_resp_ppn  : ptw_resp_ppn;
  wire                    ppn_valid_pulse = tlb_resp_valid ? tlb_resp_hit  : ptw_resp_valid;
  wire page_prot_t        ppn_perm_pulse  = tlb_resp_valid ? tlb_resp_perm : ptw_resp_perm;

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

  // #endregion
  ///////////////////////////////////////

  ///////////////////////////////////
  // #region Cache tag comparision //

  // Physical address of tag_read_addr_latch.
  // Note: If tag_read_physical_latch is 0, the user needs to ensure ppn_valid is 1.
  wire [PhysAddrLen-6-1:0] tag_read_addr_latch_phys = {tag_read_physical_latch ? tag_read_addr_latch[LogicAddrLen-6-1:6] : ppn, tag_read_addr_latch[5:0]};

  logic [WaysWidth-1:0] evict_way_q, evict_way_d;

  logic [NumWays-1:0] hit;
  // Contain the way number that hits. If none of the way hits, it will contain an empty way
  // or a selected way for eviction.
  logic [WaysWidth-1:0] hit_way;

  always_comb begin
    // Find cache line that hits
    hit = '0;
    for (int i = 0; i < NumWays; i++) begin
      if (tag_read_data[i].valid &&
          tag_read_data[i].tag == tag_read_addr_latch_phys[PhysAddrLen-6-1:SetsWidth]) begin
        hit[i] = 1'b1;
      end
    end

    // Pseudo-FIFO fallback
    hit_way = evict_way_q;

    // Empty way fallback
    for (int i = NumWays - 1; i >= 0; i--) begin
      if (!tag_read_data[i].valid) begin
        hit_way = i;
      end
    end

    for (int i = NumWays - 1; i >= 0; i--) begin
      if (hit[i]) begin
        hit_way = i;
      end
    end
  end

  wire [31:0] hit_data = data_read_data[hit_way];

  // #endregion
  ///////////////////////////////////

  /////////////////////////
  // #region Flush Logic //

  typedef enum logic [1:0] {
    FlushStateReset,
    FlushStateIdle,
    FlushStateLock,
    FlushStateDone
  } flush_state_e;

  flush_state_e flush_state_q = FlushStateReset, flush_state_d;
  logic flush_tracker_valid_d;
  logic flush_tlb_pending_q, flush_tlb_pending_d;
  logic [SetsWidth-1:0] flush_index_q, flush_index_d;

  always_comb begin
    flush_tag_write_ways = 'x;
    flush_tag_write_addr = 'x;
    flush_tag_write_req = 1'b0;
    flush_tag_write_data = tag_t'('x);

    flush_tracker_valid_d = flush_tracker_valid;
    flush_lock_acq = 1'b0;

    flush_ready = 1'b0;

    flush_state_d = flush_state_q;
    flush_tlb_pending_d = flush_tlb_pending_q;
    flush_index_d = flush_index_q;

    if (flush_tlb_resp) flush_tlb_pending_d = 1'b0;

    unique case (flush_state_q)
      // Reset all states to invalid, discard changes if any.
      FlushStateReset: begin
        flush_tag_write_ways = '1;
        flush_tag_write_addr = flush_index_q;
        flush_tag_write_req = 1'b1;
        flush_tag_write_data.valid = 1'b0;

        flush_index_d = flush_index_q + 1;

        if (&flush_index_q) begin
          flush_tracker_valid_d = 1'b0;
          flush_state_d = FlushStateDone;
        end
      end

      FlushStateIdle: begin
        if (flush_valid) begin
          flush_state_d = FlushStateLock;
          flush_tlb_pending_d = 1'b1;
        end
      end

      FlushStateLock: begin
        flush_lock_acq = 1'b1;

        if (flush_locking) begin
          flush_state_d = FlushStateReset;
          flush_tracker_valid_d = 1'b1;
        end
      end

      FlushStateDone: begin
        if (!flush_tlb_pending_q) begin
          flush_ready = 1'b1;
          flush_state_d = FlushStateIdle;
        end
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      flush_state_q <= FlushStateReset;
      flush_tracker_valid <= 1'b1;
      flush_tlb_pending_q <= 1'b0;
      flush_index_q <= '0;
    end else begin
      flush_state_q <= flush_state_d;
      flush_tracker_valid <= flush_tracker_valid_d;
      flush_tlb_pending_q <= flush_tlb_pending_d;
      flush_index_q <= flush_index_d;
    end
  end

  // #endregion
  /////////////////////////

  ///////////////////////////////////////////////////
  // #region Cache Miss Handling Logic (Slow Path) //

  typedef enum logic {
    MissStateIdle,
    MissStateFill
  } miss_state_e;

  miss_state_e miss_state_q, miss_state_d;

  logic                    miss_req_valid;
  logic [PhysAddrLen-1:0]  miss_req_address;

  logic miss_resp_replay;
  logic miss_resp_exception;

  logic miss_refill_sent_q, miss_refill_sent_d;

  always_comb begin
    miss_resp_replay = 1'b0;
    miss_resp_exception = 1'b0;

    mem_a_valid_mult[AIdxRefill] = 1'b0;
    mem_a_mult[AIdxRefill] = 'x;

    miss_state_d = miss_state_q;
    miss_refill_sent_d = miss_refill_sent_q;

    unique case (miss_state_q)
      MissStateIdle: begin
        if (miss_req_valid) begin
          miss_state_d = MissStateFill;
          miss_refill_sent_d = 1'b0;
        end
      end
      MissStateFill: begin
        mem_a_valid_mult[AIdxRefill] = !miss_refill_sent_q;
        mem_a_mult[AIdxRefill].opcode = Get;
        mem_a_mult[AIdxRefill].param = 0;
        mem_a_mult[AIdxRefill].size = LineWidth;
        mem_a_mult[AIdxRefill].address = {miss_req_address[PhysAddrLen-1:6], {LineWidth{1'b0}}};
        mem_a_mult[AIdxRefill].source = SourceBase;
        mem_a_mult[AIdxRefill].mask = '1;
        mem_a_mult[AIdxRefill].corrupt = 1'b0;
        if (mem_a_ready_mult[AIdxRefill]) miss_refill_sent_d = 1'b1;

        if (mem_d_valid_refill) begin
          if (mem_d_ready_refill) begin
            if (mem_d_last) begin
              miss_state_d = MissStateIdle;
              if (mem_d.denied) begin
                miss_resp_exception = 1'b1;
              end else begin
                miss_resp_replay = 1'b1;
              end
            end
          end
        end
      end
      default:;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      miss_state_q <= MissStateIdle;
      miss_refill_sent_q <= 1'b0;
    end else begin
      miss_state_q <= miss_state_d;
      miss_refill_sent_q <= miss_refill_sent_d;
    end
  end

  // #endregion
  ///////////////////////////////////////////////////

  ////////////////////////
  // #region Main Logic //

  typedef enum logic [3:0] {
    StateIdle,
    StateFetch,
    StateReplay,
    StateWaitTLB,
    StateFill,
    StateException,
    StateFlush
  } state_e;

  state_e state_q = StateIdle, state_d;

  // Information about the exception to be reported in StateException
  exc_cause_e ex_code_q, ex_code_d;

  // Helper signal to detect if req_address is a canonical address
  wire canonical_virtual  = ~|req_address[63:VirtAddrLen-1] | &req_address[63:VirtAddrLen-1];
  wire canonical_physical = ~|req_address[63:PhysAddrLen];

  logic [63:0] address_q, address_d;
  logic        atp_mode_q, atp_mode_d;
  logic        prv_q, prv_d;
  logic        sum_q, sum_d;

  logic [WaysWidth-1:0] way_q, way_d;

  wire [PhysAddrLen-1:0] address_phys = req_atp[63] ? {ppn, address_q[11:0]} : address_q[PhysAddrLen-1:0];

  always_comb begin
    resp_valid = 1'b0;
    resp_value = 'x;
    ex_valid = 1'b0;
    resp_ex_code = exc_cause_e'('x);

    miss_req_valid = 1'b0;
    miss_req_address = 'x;

    flush_valid = 1'b0;

    refill_req_address = address_phys[PhysAddrLen-1:6];
    refill_req_way = way_q;

    access_tag_read_req = 1'b0;
    access_tag_read_addr = 'x;
    access_tag_read_physical = !req_atp[63];

    access_data_read_req = 1'b0;
    access_data_read_addr = 'x;

    state_d = state_q;
    address_d = address_q;
    atp_mode_d = atp_mode_q;
    prv_d = prv_q;
    sum_d = sum_q;
    evict_way_d = evict_way_q;
    way_d = way_q;
    ex_code_d = ex_code_q;

    ptw_req_vpn = address_q[VirtAddrLen-1:12];

    unique case (state_q)
      StateIdle:;

      StateFetch: begin
        // The fast path of the access logic:
        // * Has lowest priority on read; it does not check if a conflicting operation is in progress
        //   before reading the tag (and data) for a shorter critical path. So in this state we need
        //   to first check if there is a conflict, and if so we need to replay the access.
        if (!nothing_in_progress) begin
          // If lock is held by someone, it indicates that we races with another logic, replay.
          state_d = StateReplay;
        end else if (atp_mode_q && !ppn_valid) begin
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
          resp_valid = 1'b1;
          resp_value = hit_data;
          state_d = StateIdle;
        end else begin
          way_d = hit_way;
          if (~|hit) begin
            evict_way_d = evict_way_q + 1;
          end

          state_d = StateFill;
          miss_req_valid = 1'b1;
        end
      end

      StateReplay: begin
        if (nothing_in_progress) begin
          access_tag_read_req = 1'b1;
          access_data_read_req = 1'b1;
          access_tag_read_addr = address_d[LogicAddrLen-1:LineWidth];
          access_data_read_addr = address_d[2+:SetsWidth+4];

          if (access_tag_read_gnt && access_data_read_gnt) state_d = StateFetch;
        end
      end

      StateWaitTLB: begin
        if (ppn_valid) begin
          state_d = StateReplay;
        end
      end

      StateFill: begin
        miss_req_address = address_phys;

        if (miss_resp_replay) begin
          state_d = StateReplay;
        end else if (miss_resp_exception) begin
          ex_code_d = EXC_CAUSE_INSTR_ACCESS_FAULT;
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
      access_tag_read_req = 1'b1;
      access_tag_read_addr = address_d[LogicAddrLen-1:LineWidth];
      access_data_read_req = 1'b1;
      access_data_read_addr = address_d[2+:SetsWidth+4];

      if (access_tag_read_gnt && access_data_read_gnt) begin
        state_d = StateFetch;
      end else begin
        // If we failed to perform both tag and data read this cycle, move into replay state.
        state_d = StateReplay;
      end

      if (req_reason ==? 4'b1x11) begin
        flush_valid = 1'b1;
        state_d = StateFlush;
      end

      if (req_atp[63] && !canonical_virtual) begin
        state_d = StateException;
        ex_code_d = EXC_CAUSE_INSTR_PAGE_FAULT;
      end

      if (!req_atp[63] && !canonical_physical) begin
        state_d = StateException;
        ex_code_d = EXC_CAUSE_INSTR_ACCESS_FAULT;
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
      ex_code_q <= exc_cause_e'('x);
    end else begin
      state_q <= state_d;
      address_q <= address_d;
      atp_mode_q <= atp_mode_d;
      prv_q <= prv_d;
      sum_q <= sum_d;
      evict_way_q <= evict_way_d;
      way_q <= way_d;
      ex_code_q <= ex_code_d;
    end
  end

  // #endregion
  ////////////////////////

  if (EnableHpm) begin
    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        hpm_access_o <= 1'b0;
        hpm_miss_o <= 1'b0;
        hpm_tlb_miss_o <= 1'b0;
      end else begin
        hpm_access_o <= req_valid;
        hpm_miss_o <= state_q != StateFill && state_d == StateFill;
        hpm_tlb_miss_o <= state_q != StateWaitTLB && state_d == StateWaitTLB;
      end
    end
  end else begin
    assign hpm_access_o = 1'b0;
    assign hpm_miss_o = 1'b0;
    assign hpm_tlb_miss_o = 1'b0;
  end

endmodule
