`include "tl_util.svh"

module muntjac_dcache import muntjac_pkg::*; import tl_pkg::*; # (
    parameter int unsigned DataWidth   = 64,
    // Number of ways is `2 ** WaysWidth`.
    parameter int unsigned WaysWidth   = 2,
    // Number of sets is `2 ** SetsWidth`.
    parameter int unsigned SetsWidth   = 6,
    parameter int unsigned VirtAddrLen = 39,
    parameter int unsigned PhysAddrLen = 56,
    parameter int unsigned SourceWidth = 1,
    parameter int unsigned SinkWidth   = 1,
    parameter bit          EnableHpm   = 0,

    parameter bit [SourceWidth-1:0] SourceBase  = 0,
    parameter bit [SourceWidth-1:0] PtwSourceBase = 0
) (
    input  logic clk_i,
    input  logic rst_ni,

    // Interface to CPU
    input  dcache_h2d_t cache_h2d_i,
    output dcache_d2h_t cache_d2h_o,

    // Hardware performance monitor events
    output logic hpm_access_o,
    output logic hpm_miss_o,
    output logic hpm_tlb_miss_o,

    // Channel for D$
    `TL_DECLARE_HOST_PORT(DataWidth, PhysAddrLen, SourceWidth, SinkWidth, mem),
    // Channel for PTW
    `TL_DECLARE_HOST_PORT(64, PhysAddrLen, SourceWidth, SinkWidth, mem_ptw)
);

  // This is the largest address width that we ever have to deal with.
  localparam AddrLen = VirtAddrLen > PhysAddrLen ? VirtAddrLen : PhysAddrLen;

  localparam LineWidth = 6;

  localparam InterleaveWidth = $clog2(DataWidth / 64);
  localparam NumInterleave = 2 ** InterleaveWidth;
  localparam InterleaveMask = NumInterleave - 1;

  localparam OffsetWidth = 6 - 3 - InterleaveWidth;

  localparam NumWays = 2 ** WaysWidth;

  localparam DataWidthInBytes = DataWidth / 8;
  localparam NonBurstSize = $clog2(DataWidthInBytes);

  if (SetsWidth > 6) $fatal(1, "PIPT cache's SetsWidth is bounded by 6");

  `TL_DECLARE(DataWidth, PhysAddrLen, SourceWidth, SinkWidth, mem);
  `TL_DECLARE(64, PhysAddrLen, SourceWidth, SinkWidth, mem_ptw);
  `TL_BIND_HOST_PORT(mem, mem);
  `TL_BIND_HOST_PORT(mem_ptw, mem_ptw);

  //////////////////////
  // Helper functions //
  //////////////////////

  // Check if memory access is properly aligned.
  function automatic logic is_aligned (
      input logic [2:0] addr,
      input logic [1:0] size
  );
    unique case (size)
      2'b00: is_aligned = 1'b1;
      2'b01: is_aligned = addr[0] == 0;
      2'b10: is_aligned = addr[1:0] == 0;
      2'b11: is_aligned = addr == 0;
    endcase
  endfunction

  function automatic logic [63:0] sext8(input logic [7:0] value, input size_ext_e size_ext);
    unique case (size_ext)
      SizeExtZero: return 64'(value);
      SizeExtSigned: return 64'(signed'(value));
      default: return 'x;
    endcase
  endfunction

  function automatic logic [63:0] sext16(input logic [15:0] value, input size_ext_e size_ext);
    unique case (size_ext)
      SizeExtZero: return 64'(value);
      SizeExtSigned: return 64'(signed'(value));
      default: return 'x;
    endcase
  endfunction

  function automatic logic [63:0] sext32(input logic [31:0] value, input size_ext_e size_ext);
    unique case (size_ext)
      SizeExtZero: return 64'(value);
      SizeExtOne: return {32'hffffffff, value};
      SizeExtSigned: return 64'(signed'(value));
      default: return 'x;
    endcase
  endfunction

  function automatic logic [63:0] align_load (
      input logic [63:0] value,
      input logic [2:0]  addr,
      input logic [1:0]  size,
      input size_ext_e   size_ext
  );
    unique case (size)
      2'b00: unique case (addr[2:0])
        3'h0: align_load = sext8(value[ 0 +: 8], size_ext);
        3'h1: align_load = sext8(value[ 8 +: 8], size_ext);
        3'h2: align_load = sext8(value[16 +: 8], size_ext);
        3'h3: align_load = sext8(value[24 +: 8], size_ext);
        3'h4: align_load = sext8(value[32 +: 8], size_ext);
        3'h5: align_load = sext8(value[40 +: 8], size_ext);
        3'h6: align_load = sext8(value[48 +: 8], size_ext);
        3'h7: align_load = sext8(value[56 +: 8], size_ext);
        default: align_load = 'x;
      endcase
      2'b01: unique case (addr[2:1])
        2'h0: align_load = sext16(value[ 0 +: 16], size_ext);
        2'h1: align_load = sext16(value[16 +: 16], size_ext);
        2'h2: align_load = sext16(value[32 +: 16], size_ext);
        2'h3: align_load = sext16(value[48 +: 16], size_ext);
        default: align_load = 'x;
      endcase
      2'b10: unique case (addr[2])
        1'h0: align_load = sext32(value[ 0 +: 32], size_ext);
        1'h1: align_load = sext32(value[32 +: 32], size_ext);
        default: align_load = 'x;
      endcase
      2'b11: align_load = value;
      default: align_load = 'x;
    endcase
  endfunction

  function automatic logic [63:0] tl_align_load(
      input logic [DataWidth-1:0] value,
      input logic [NonBurstSize-1:0] addr
  );
    logic [NumInterleave-1:0][63:0] split = value;
    return split[addr >> 3];
  endfunction

  function automatic logic [7:0] align_strb (
      input  logic [2:0]  addr,
      input  logic [1:0]  size
  );
    unique case (size)
      2'b00: align_strb = 'b1 << addr;
      2'b01: align_strb = 'b11 << addr;
      2'b10: align_strb = 'b1111 << addr;
      2'b11: align_strb = 'b11111111;
      default: align_strb = 'x;
    endcase
  endfunction

  function automatic logic [DataWidthInBytes-1:0] tl_align_strb(
    input logic [7:0] strb,
    input logic [NonBurstSize-1:0] addr
  );
    if (DataWidth == 64) begin
      return strb;
    end else begin
      for (int i = 0; i < DataWidth / 64; i++) begin
        tl_align_strb[i * 8 +: 8] = addr[(DataWidth == 64 ? 3 : NonBurstSize-1):3] == i ? strb : 0;
      end
    end
  endfunction

  function automatic logic [63:0] align_store (
      input  logic [63:0] value,
      input  logic [2:0]  addr
  );
    unique case (addr)
      3'h0: align_store = value;
      3'h1: align_store = {48'dx, value[7:0], 8'dx};
      3'h2: align_store = {32'dx, value[15:0], 16'dx};
      3'h3: align_store = {32'dx, value[7:0], 24'dx};
      3'h4: align_store = {value[31:0], 32'dx};
      3'h5: align_store = {16'dx, value[7:0], 40'dx};
      3'h6: align_store = {value[15:0], 48'dx};
      3'h7: align_store = {value[7:0], 56'dx};
      default: align_store = 'x;
    endcase
  endfunction

  function automatic logic [DataWidth-1:0] tl_align_store(input logic [63:0] value);
    for (int i = 0; i < DataWidth / 64; i++) begin
      tl_align_store[i * 64 +: 64] = value;
    end
  endfunction

  function automatic logic [63:0] do_amo_op (
      // We make these bit instead of logic, because addition and subtraction will produce x
      // if any bits of these are x. So even if highest bits are x it also corrupt lower bits.
      input  bit   [63:0] original,
      input  bit   [63:0] operand,
      input  logic [1:0]  size,
      input  logic [6:0]  amo
  );

    // Do a substraction. The 63rd and 31st bit would give us enough information for comparision.
    automatic logic [63:0] difference = original - operand;

    // Get the sign bits for comparision needs
    automatic logic original_sign = size == 2'b11 ? original[63] : original[31];
    automatic logic operand_sign = size == 2'b11 ? operand[63] : operand[31];
    automatic logic difference_sign = size == 2'b11 ? difference[63] : difference[31];

    // If MSBs are the same, look at the sign of the result is sufficient.
    // Otherwise the one with MSB 0 is larger (if signed) and smaller (if unsigned).
    automatic logic lt_flag = original_sign == operand_sign ? difference_sign : (amo[5] ? operand_sign : original_sign);

    unique casez (amo[6:2])
      5'b00001: do_amo_op = operand;
      5'b00000: do_amo_op = original + operand;
      5'b00100: do_amo_op = original ^ operand;
      5'b01100: do_amo_op = original & operand;
      5'b01000: do_amo_op = original | operand;
      5'b1?000: do_amo_op = lt_flag ? original : operand;
      5'b1?100: do_amo_op = lt_flag ? operand : original;
      default: do_amo_op = 'x;
    endcase
  endfunction

  /////////////////////
  // Type definition //
  /////////////////////

  typedef struct packed {
    // Tag, excluding the bits used for direct-mapped access and last 6 bits of offset.
    logic [PhysAddrLen-SetsWidth-LineWidth-1:0] tag;
    logic writable;
    logic dirty;
    logic valid;
  } tag_t;

  ////////////////////////
  // CPU Facing signals //
  ////////////////////////

  wire            req_valid    = cache_h2d_i.req_valid;
  wire [63:0]     req_address  = cache_h2d_i.req_address;
  wire [63:0]     req_value    = cache_h2d_i.req_value;
  wire mem_op_e   req_op       = cache_h2d_i.req_op;
  wire [1:0]      req_size     = cache_h2d_i.req_size;
  wire size_ext_e req_size_ext = cache_h2d_i.req_size_ext;
  wire [6:0]      req_amo      = cache_h2d_i.req_amo;
  wire            req_prv      = cache_h2d_i.req_prv;
  wire            req_sum      = cache_h2d_i.req_sum;
  wire            req_mxr      = cache_h2d_i.req_mxr;
  wire [63:0]     req_atp      = cache_h2d_i.req_atp;

  logic flush_valid;
  logic flush_ready;

  assign flush_valid = cache_h2d_i.notif_valid;
  assign cache_d2h_o.notif_ready = flush_ready;

  logic        resp_valid;
  logic [63:0] resp_value;
  logic        ex_valid;
  exception_t  ex_exception;

  assign cache_d2h_o.ex_valid = ex_valid;
  assign cache_d2h_o.ex_exception = ex_exception;

  // Register responses
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      cache_d2h_o.resp_valid <= 1'b0;
      cache_d2h_o.resp_value <= 'x;
    end else begin
      cache_d2h_o.resp_valid <= resp_valid;
      cache_d2h_o.resp_value <= resp_value;
    end
  end

  //////////////////////////////////
  // MEM Channel D Demultiplexing //
  //////////////////////////////////

  // Refilling needs to take a lock, but it may be blocked by the writeback. This violates
  // TileLink's rule that D takes priority to C channel. To ensure deadlock freedom, we
  // can simply insert a FIFO for D channel (as we can only have 1 D-channel message pending).

  typedef `TL_D_STRUCT(DataWidth, PhysAddrLen, SourceWidth, SinkWidth) gnt_t;

  logic mem_grant_valid;
  logic mem_grant_ready;
  gnt_t gnt_r;

  // Use bit instead of logic here because fifo has an assertion that requires data to be known.
  bit [$bits(gnt_t)-1:0] gnt_w;
  assign gnt_w = mem_d;

  prim_fifo_sync #(
    .Width ($bits(gnt_t)),
    .Pass  (1'b1),
    .Depth (2 ** (LineWidth - NonBurstSize))
  ) gnt_fifo (
    .clk_i,
    .rst_ni,
    .clr_i  (1'b0),
    .wvalid (mem_d_valid),
    .wready (mem_d_ready),
    .wdata  (gnt_w),
    .rvalid (mem_grant_valid),
    .rready (mem_grant_ready),
    .rdata  (gnt_r),
    .depth  ()
  );

  wire [DataWidth-1:0] mem_grant_data   = gnt_r.data;
  wire tl_d_op_e       mem_grant_opcode = gnt_r.opcode;
  wire [2:0]           mem_grant_param  = gnt_r.param;
  wire [SinkWidth-1:0] mem_grant_sink   = gnt_r.sink;
  wire                 mem_grant_denied = gnt_r.denied;

  wire mem_grant_valid_refill  = mem_grant_valid && gnt_r.opcode inside {Grant, GrantData};
  wire mem_grant_valid_rel_ack = mem_grant_valid && gnt_r.opcode == ReleaseAck;
  wire mem_grant_valid_access  = mem_grant_valid && gnt_r.opcode inside {AccessAck, AccessAckData};

  logic mem_grant_ready_refill;
  assign mem_grant_ready = mem_grant_valid_refill ? mem_grant_ready_refill : 1'b1;

  //////////////////////////////
  // Cache access arbitration //
  //////////////////////////////

  logic refill_lock_acq;
  logic refill_lock_rel;
  // Unlike {refill, access, flush}_lock_acq, probe_lock_acq is not set pulse signal; logic must
  // maintain it if it still wants lock.
  logic probe_lock_acq;
  // probe_lock_rel is not defined because probe always transfer the lock to write-back module.
  logic release_lock_rel;
  logic access_lock_acq;
  // access_lock_rel, flush_lock_rel is not always paired with access_lock_req. When a dirty cache
  // line needs to be evicted/flushed, it will transfer the lock to the write-back module.
  logic access_lock_rel;
  logic flush_lock_acq;
  logic flush_lock_rel;

  // WB logic taking lock from probe/access
  logic release_lock_move;

  typedef enum logic [2:0] {
    LockHolderNone,
    LockHolderRefill,
    LockHolderProbe,
    LockHolderAccess,
    LockHolderRelease,
    LockHolderFlush
  } lock_holder_e;

  logic refill_lock_acq_pending_q, refill_lock_acq_pending_d;
  logic access_lock_acq_pending_q, access_lock_acq_pending_d;
  logic flush_lock_acq_pending_q, flush_lock_acq_pending_d;
  lock_holder_e lock_holder_q, lock_holder_d;

  wire refill_locked  = lock_holder_q == LockHolderRefill;
  wire probe_locking  = lock_holder_d == LockHolderProbe;
  wire access_locking = lock_holder_d == LockHolderAccess;
  wire flush_locking  = lock_holder_d == LockHolderFlush;

  // Arbitrate on the new holder of the lock
  always_comb begin
    lock_holder_d = lock_holder_q;
    refill_lock_acq_pending_d = refill_lock_acq_pending_q || refill_lock_acq;
    access_lock_acq_pending_d = access_lock_acq_pending_q || access_lock_acq;
    flush_lock_acq_pending_d = flush_lock_acq_pending_q || flush_lock_acq;

    if (refill_lock_rel || release_lock_rel || access_lock_rel || flush_lock_rel) begin
      lock_holder_d = LockHolderNone;
    end

    if (release_lock_move) begin
      lock_holder_d = LockHolderRelease;
    end

    if (lock_holder_d == LockHolderNone) begin
      priority case (1'b1)
        // This blocks channel D, so it must have highest priority by TileLink rule
        refill_lock_acq_pending_d: begin
          lock_holder_d = LockHolderRefill;
          refill_lock_acq_pending_d = 1'b0;
        end
        // This blocks other agents, so make it more important than the rest.
        probe_lock_acq: begin
          lock_holder_d = LockHolderProbe;
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
  logic                   access_write_req_data;
  logic [7:0]             access_write_strb;
  logic [63:0]            access_write_data;

  logic [SetsWidth+3-1:0] wb_read_addr;
  logic                   wb_read_req_data;
  logic [WaysWidth-1:0]   wb_read_way;

  logic [WaysWidth-1:0]           refill_write_way;
  logic [SetsWidth+3-1:0]         refill_write_addr;
  logic                           refill_write_req_tag;
  tag_t                           refill_write_tag;
  logic                           refill_write_req_data;
  logic [NumInterleave-1:0][63:0] refill_write_data;

  logic [AddrLen-6-1:0]  probe_read_index;
  logic                  probe_read_req_tag;
  logic [NumWays-1:0]    probe_write_ways;
  logic [SetsWidth-1:0]  probe_write_index;
  logic                  probe_write_req_tag;
  tag_t                  probe_write_tag;

  logic [SetsWidth-1:0]  flush_read_index;
  logic                  flush_read_req_tag;
  logic [NumWays-1:0]    flush_write_ways;
  logic [SetsWidth-1:0]  flush_write_index;
  logic                  flush_write_req_tag;
  tag_t                  flush_write_tag;

  logic read_req_tag;
  logic read_req_data;
  logic read_req_data_interleave;
  logic read_physical;
  logic [AddrLen-3-1:0] read_addr;

  logic [SetsWidth+3-1:0] write_addr;
  tag_t read_tag [NumWays];
  tag_t write_tag;
  logic write_req_tag;
  logic write_req_data;
  logic write_req_data_interleave;
  logic [NumWays-1:0] write_ways;
  logic [NumWays-1:0] write_ways_interleave;
  logic [63:0] read_data_preinterleave [NumWays];
  logic [63:0] read_data [NumWays];
  logic [NumInterleave-1:0][63:0] write_data;
  logic [NumInterleave-1:0][63:0] write_data_interleave;
  logic [7:0] write_strb;

  always_comb begin
    read_req_tag = 1'b0;
    read_req_data = 1'b0;
    read_req_data_interleave = 1'b0;
    read_addr = 'x;
    read_physical = 1'b1;

    // Multiplex with _d version here because read happens the next cycle.
    unique case (lock_holder_d)
      LockHolderRelease: begin
        read_req_data = wb_read_req_data;
        read_req_data_interleave = 1'b1;
        read_addr = wb_read_addr ^ (wb_read_way & InterleaveMask);
      end
      LockHolderProbe: begin
        read_req_tag = probe_read_req_tag;
        read_addr = {probe_read_index, 3'dx};
      end
      LockHolderFlush: begin
        read_req_tag = flush_read_req_tag;
        read_addr = {flush_read_index, 3'dx};
      end
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

  // Interleave the read data
  for (genvar i = 0; i < NumWays; i++) begin
    assign read_data[i] = read_data_preinterleave[i ^ (read_addr_latch & InterleaveMask)];
  end

  always_comb begin
    write_addr = 'x;
    write_req_tag = 1'b0;
    write_req_data = 1'b0;
    write_req_data_interleave = 1'b0;
    write_ways = '0;
    write_strb = 'x;
    write_data = 'x;
    write_tag = tag_t'('x);

    // Unlike read, write can happen at the cycle of lock release. However the writer must ensure
    // that the new lock acquirer will not access the same address.
    unique case (lock_holder_q)
      LockHolderRefill: begin
        write_addr = refill_write_addr ^ (refill_write_way & InterleaveMask);
        write_req_tag = refill_write_req_tag;
        write_req_data = refill_write_req_data;
        write_req_data_interleave = 1'b1;
        for (int i = 0; i < NumWays; i++) write_ways[i] = refill_write_way == i;
        write_strb = '1;
        write_data = refill_write_data;
        write_tag = refill_write_tag;
      end
      LockHolderProbe: begin
        write_addr = {probe_write_index, 3'dx};
        write_req_tag = probe_write_req_tag;
        write_ways = probe_write_ways;
        write_tag = probe_write_tag;
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
        write_req_data = access_write_req_data;
        for (int i = 0; i < NumWays; i++) write_ways[i] = access_write_way == i;
        write_strb = access_write_strb;
        write_data = {NumInterleave{access_write_data}};
        write_tag = access_write_tag;
      end
      default:;
    endcase
  end

  // Interleave the write ways
  for (genvar i = 0; i < NumWays; i++) begin
    assign write_ways_interleave[i] = write_req_data_interleave ? write_ways[(i &~ InterleaveMask) | (write_addr & InterleaveMask)] : write_ways[i ^ (write_addr & InterleaveMask)];
  end
  for (genvar i = 0; i < NumInterleave; i++) begin
    assign write_data_interleave[i] = write_data[i ^ (write_addr & InterleaveMask)];
  end

  ////////////////////////
  // SRAM Instantiation //
  ////////////////////////

  logic [63:0] write_strb_expanded;
  always_comb begin
    for (int i = 0; i < 8; i++) begin
      write_strb_expanded[i * 8 +: 8] = write_strb[i] ? 8'hff : 8'h00;
    end
  end

  // When a read/write to the same address happens in the same cycle, they may cause conflict.
  // While it is possible to keep track of the previous address and stall for one cycle if
  // possible, it is generally difficult to ensure correctness when there are so many components
  // that can access this SRAM. So we instead choose to use bypass here.
  //
  // The bypassed tag/data is shared across all ways but the valid bits are private to each ways
  // because of write enable signals.

  tag_t                           tag_bypass;
  logic [NumInterleave-1:0][63:0] data_bypass;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      tag_bypass <= tag_t'('x);
      data_bypass <= 'x;
    end else begin
      if (read_req_tag) begin
        tag_bypass <= write_tag;
      end
      if (read_req_data) begin
        data_bypass <= write_data_interleave;
      end
    end
  end

  for (genvar i = 0; i < NumWays; i++) begin: ram

    logic tag_bypass_valid;
    logic [7:0] data_bypass_valid;

    tag_t        tag_raw;
    logic [63:0] data_raw;
    logic [63:0] data_bypassed;

    wire [SetsWidth+3-1:0] effective_read_addr = read_addr ^ (read_req_data_interleave ? (i & InterleaveMask) : 0);
    wire [SetsWidth+3-1:0] effective_write_addr = write_addr ^ (write_req_data_interleave ? (i & InterleaveMask) : 0);

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        tag_bypass_valid <= 1'b0;
        data_bypass_valid <= 0;
      end else begin
        if (read_req_tag) begin
          tag_bypass_valid <= 1'b0;
          if (write_req_tag && write_ways[i] && write_addr[SetsWidth+3-1:3] == read_addr[SetsWidth+3-1:3]) begin
            tag_bypass_valid <= 1'b1;
          end
        end
        if (read_req_data) begin
          data_bypass_valid <= 0;
          if (write_req_data && write_ways_interleave[i] && effective_write_addr == effective_read_addr) begin
            data_bypass_valid <= write_strb;
          end
        end
      end
    end

    assign read_tag[i] = tag_bypass_valid ? tag_bypass : tag_raw;
    always_comb begin
      for (int j = 0; j < 8; j++) begin
        data_bypassed[j*8 +: 8] = data_bypass_valid[j] ? data_bypass[i & InterleaveMask][j*8 +: 8] : data_raw[j*8 +: 8];
      end
    end
    assign read_data_preinterleave[i] = data_bypassed;

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
        .a_addr_i  (effective_read_addr),
        .a_rdata_o (data_raw),

        .b_req_i   (write_req_data && write_ways_interleave[i]),
        .b_addr_i  (effective_write_addr),
        .b_wdata_i (write_data_interleave[i & InterleaveMask]),
        .b_wmask_i (write_strb_expanded)
    );
  end

  ////////////////////////////////
  // Dirty Data Writeback Logic //
  ////////////////////////////////

  logic                   wb_flush_req_valid;
  logic [WaysWidth-1:0]   wb_flush_req_way;
  logic [PhysAddrLen-7:0] wb_flush_req_address;
  logic                   wb_flush_req_dirty;
  logic [2:0]             wb_flush_req_param;

  logic                   wb_probe_req_valid;
  logic [WaysWidth-1:0]   wb_probe_req_way;
  logic [PhysAddrLen-7:0] wb_probe_req_address;
  logic                   wb_probe_req_dirty;
  logic [2:0]             wb_probe_req_param;

  logic                   wb_rel_req_valid;
  logic [WaysWidth-1:0]   wb_rel_req_way;
  logic [PhysAddrLen-7:0] wb_rel_req_address;
  logic                   wb_rel_req_dirty;
  logic [2:0]             wb_rel_req_param;

  logic                   wb_req_valid;
  logic                   wb_req_active;
  logic [WaysWidth-1:0]   wb_req_way;
  logic [PhysAddrLen-7:0] wb_req_address;
  logic                   wb_req_dirty;
  logic [2:0]             wb_req_param;

  // Multiplex write-back requests.
  // As the invoker needs to hold access lock already, this is merely a simple multiplex, without
  // complex handshaking.
  always_comb begin
    wb_req_valid = 1'b0;
    wb_req_active = 1'bx;
    wb_req_way = 'x;
    wb_req_address = 'x;
    wb_req_dirty = 1'bx;
    wb_req_param = 'x;

    unique case (1'b1)
      wb_flush_req_valid: begin
        wb_req_valid = 1'b1;
        wb_req_active = 1'b1;
        wb_req_way = wb_flush_req_way;
        wb_req_address = wb_flush_req_address;
        wb_req_dirty = wb_flush_req_dirty;
        wb_req_param = wb_flush_req_param;
      end
      wb_probe_req_valid: begin
        wb_req_valid = 1'b1;
        wb_req_active = 1'b0;
        wb_req_way = wb_probe_req_way;
        wb_req_address = wb_probe_req_address;
        wb_req_dirty = wb_probe_req_dirty;
        wb_req_param = wb_probe_req_param;
      end
      wb_rel_req_valid: begin
        wb_req_valid = 1'b1;
        wb_req_active = 1'b1;
        wb_req_way = wb_rel_req_way;
        wb_req_address = wb_rel_req_address;
        wb_req_dirty = wb_rel_req_dirty;
        wb_req_param = wb_rel_req_param;
      end
      default:;
    endcase
  end

  logic                   wb_progress_q, wb_progress_d;
  logic [WaysWidth-1:0]   wb_way_q, wb_way_d;
  logic [OffsetWidth-1:0] wb_index_q, wb_index_d;
  tl_c_op_e               wb_opcode_q, wb_opcode_d;
  logic [2:0]             wb_param_q, wb_param_d;
  logic [PhysAddrLen-7:0] wb_address_q, wb_address_d;

  always_comb begin
    wb_read_req_data = 1'b0;
    wb_read_addr = 'x;
    wb_read_way = 'x;

    release_lock_move = 1'b0;
    release_lock_rel = 1'b0;

    wb_progress_d = wb_progress_q;
    wb_index_d = wb_index_q;
    wb_way_d = wb_way_q;
    wb_opcode_d = wb_opcode_q;
    wb_param_d = wb_param_q;
    wb_address_d = wb_address_q;

    mem_c_valid = wb_progress_q;
    mem_c.opcode = wb_opcode_q;
    mem_c.param = wb_param_q;
    mem_c.size = 6;
    mem_c.source = SourceBase;
    mem_c.address = {wb_address_q, 6'd0};
    mem_c.corrupt = 1'b0;
    for (int i = 0; i < NumInterleave; i++) begin
      mem_c.data[i * 64 +: 64] = read_data[(wb_way_q &~ InterleaveMask) | i];
    end

    if (wb_progress_q && mem_c_ready) begin
      wb_index_d = wb_index_q + 1;

      if (wb_index_q == 0) begin
        // Last cycle. Signal the invoker and clear progress bit.
        wb_progress_d = 1'b0;

        // Release SRAM access lock
        release_lock_rel = 1'b1;
      end else begin
        wb_read_req_data = 1'b1;
        wb_read_way = wb_way_d;
        wb_read_addr = {wb_address_d[SetsWidth-1:0], 3'(wb_index_q << InterleaveWidth)};
      end
    end

    if (wb_req_valid) begin
      release_lock_move = 1'b1;
      wb_progress_d = 1'b1;
      wb_way_d = wb_req_way;
      wb_opcode_d = wb_req_active ?
        (wb_req_dirty ? ReleaseData : Release) :
        (wb_req_dirty ? ProbeAckData : ProbeAck);
      wb_param_d = wb_req_param;
      wb_address_d = wb_req_address;

      // When wb_req_dirty is false, set wb_index to 0 to hint this is the last cycle.
      wb_index_d = wb_req_dirty ? 1 : 0;
      if (wb_req_dirty) begin
        wb_read_req_data = 1'b1;
        wb_read_way = wb_way_d;
        wb_read_addr = {wb_address_d[SetsWidth-1:0], 3'd0};
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      wb_progress_q <= 1'b0;
      wb_index_q <= 0;
      wb_way_q <= 0;
      wb_opcode_q <= tl_c_op_e'('x);
      wb_param_q <= 'x;
      wb_address_q <= 'x;
    end else begin
      wb_progress_q <= wb_progress_d;
      wb_index_q <= wb_index_d;
      wb_way_q <= wb_way_d;
      wb_opcode_q <= wb_opcode_d;
      wb_param_q <= wb_param_d;
      wb_address_q <= wb_address_d;
    end
  end

  //////////////////
  // Refill Logic //
  //////////////////

  logic [PhysAddrLen-7:0] refill_req_address;
  logic [WaysWidth-1:0]   refill_req_way;

  logic probe_lock;

  logic [OffsetWidth-1:0] refill_index_q, refill_index_d;

  logic [SinkWidth-1:0] ack_sink_q, ack_sink_d;
  logic                 ack_pending_q, ack_pending_d;

  typedef enum logic [1:0] {
    RefillStateIdle,
    RefillStateProgress,
    RefillStateComplete
  } refill_state_e;

  refill_state_e refill_state_q = RefillStateIdle, refill_state_d;

  logic mem_grant_last;

  always_comb begin
    refill_write_way = 'x;
    refill_write_addr = 'x;
    refill_write_req_tag = 1'b0;
    refill_write_tag = tag_t'('x);
    refill_write_req_data = 1'b0;
    refill_write_data = 'x;

    refill_lock_acq = 1'b0;
    refill_lock_rel = 1'b0;
    mem_grant_ready_refill = 1'b0;

    probe_lock = 1'b0;
    mem_grant_last = 1'b0;

    refill_index_d = refill_index_q;
    refill_state_d = refill_state_q;
    ack_sink_d = ack_sink_q;
    ack_pending_d = ack_pending_q;

    mem_e_valid = ack_pending_q;
    mem_e.sink = ack_sink_q;

    // Process Ack on E channel
    if (mem_e_ready) ack_pending_d = 1'b0;

    unique case (refill_state_q)
      RefillStateIdle: begin
        if (mem_grant_valid_refill) begin
          refill_index_d = mem_grant_opcode == GrantData ? 0 : (2 ** OffsetWidth - 1);
          ack_sink_d = mem_grant_sink;
          ack_pending_d = 1'b1;

          refill_lock_acq = 1'b1;
          refill_state_d = RefillStateProgress;
        end
      end
      RefillStateProgress: begin
        mem_grant_ready_refill = refill_locked;
        refill_write_way = refill_req_way;
        refill_write_addr = {refill_req_address[SetsWidth-1:0], 3'(refill_index_q << InterleaveWidth)};

        refill_write_req_data = mem_grant_valid_refill && mem_grant_opcode == GrantData && !mem_grant_denied;
        refill_write_data = mem_grant_data;

        // Update the metadata. This should only be done once, we can do it in either time.
        refill_write_req_tag = mem_grant_valid_refill && &refill_index_q && !mem_grant_denied;
        refill_write_tag.tag = refill_req_address[PhysAddrLen-7:SetsWidth];
        refill_write_tag.writable = mem_grant_param == tl_pkg::toT;
        refill_write_tag.dirty = 1'b0;
        refill_write_tag.valid = 1'b1;

        if (mem_grant_valid_refill && mem_grant_ready_refill) begin
          refill_index_d = refill_index_q + 1;
          if (&refill_index_q) begin
            mem_grant_last = 1'b1;
            probe_lock = 1'b1;
            refill_state_d = RefillStateComplete;
          end
        end
      end
      RefillStateComplete: begin
        if (!ack_pending_d) begin
          // Lock the data cache for 16 cycles to guarantee forward progess.
          probe_lock = 1'b1;

          refill_index_d = 0;
          refill_lock_rel = 1'b1;
          refill_state_d = RefillStateIdle;
        end
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      refill_index_q <= 0;
      refill_state_q <= RefillStateIdle;
      ack_sink_q <= 'x;
      ack_pending_q <= 1'b0;
    end else begin
      refill_index_q <= refill_index_d;
      refill_state_q <= refill_state_d;
      ack_sink_q <= ack_sink_d;
      ack_pending_q <= ack_pending_d;
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
      .req_valid_i       (ptw_req_valid),
      .req_vpn_i         (ptw_req_vpn),
      .req_pt_ppn_i      (req_atp[PhysAddrLen-13:0]),
      .resp_valid_o      (ptw_resp_valid),
      .resp_ppn_o        (ptw_resp_ppn),
      .resp_perm_o       (ptw_resp_perm),
      .mem_req_ready_i   (mem_ptw_a_ready),
      .mem_req_valid_o   (mem_ptw_a_valid),
      .mem_req_address_o (mem_ptw_a.address),
      .mem_resp_valid_i  (mem_ptw_d_valid),
      .mem_resp_data_i   (mem_ptw_d.data)
  );

  assign mem_ptw_a.opcode = Get;
  assign mem_ptw_a.param = 0;
  assign mem_ptw_a.size = 1;
  assign mem_ptw_a.source = PtwSourceBase;
  assign mem_ptw_a.mask = '1;
  assign mem_ptw_a.corrupt = 1'b0;
  assign mem_ptw_a.data = 'x;

  assign mem_ptw_b_ready = 1'b1;

  assign mem_ptw_c_valid = 1'b0;
  assign mem_ptw_c       = 'x;

  assign mem_ptw_d_ready = 1'b1;

  assign mem_ptw_e_valid = 1'b0;
  assign mem_ptw_e       = 'x;

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
  // Probe Logic //
  /////////////////

  typedef enum logic {
    ProbeStateIdle,
    ProbeStateCheck
  } probe_state_e;

  probe_state_e probe_state_q = ProbeStateIdle, probe_state_d;

  logic [PhysAddrLen-7:0] probe_address_q, probe_address_d;
  logic [2:0] probe_param_q, probe_param_d;
  logic [4:0] probe_lock_q, probe_lock_d;

  always_comb begin
    probe_lock_acq = 1'b0;
    probe_read_req_tag = 1'b0;
    probe_read_index = 'x;

    probe_write_req_tag = 1'b0;
    probe_write_ways = 'x;
    probe_write_index = 'x;
    probe_write_tag = tag_t'('x);

    wb_probe_req_valid = 1'b0;
    wb_probe_req_way = 'x;
    wb_probe_req_address = 'x;
    wb_probe_req_dirty = 1'bx;
    wb_probe_req_param = 'x;

    probe_state_d = probe_state_q;
    probe_address_d = probe_address_q;
    probe_param_d = probe_param_q;

    mem_b_ready = 1'b0;

    // probe_lock and related signals are for forward progress guarantees.
    probe_lock_d = probe_lock_q;
    if (probe_lock_q != 0) probe_lock_d = probe_lock_q - 1;
    if (probe_lock) probe_lock_d = 16;

    unique case (probe_state_q)
      // Waiting for a probe request to reach us.
      ProbeStateIdle: begin
        probe_lock_acq = probe_lock_q == 0 && mem_b_valid;

        if (probe_locking) begin
          mem_b_ready = 1'b1;
          probe_address_d = mem_b.address[PhysAddrLen-1:6];
          probe_param_d = mem_b.param;

          // Does the tag read necessary for performing invalidation
          probe_read_req_tag = 1'b1;
          probe_read_index = probe_address_d;

          probe_state_d = ProbeStateCheck;
        end
      end
      // Act upon tag read
      ProbeStateCheck: begin
        probe_state_d = ProbeStateIdle;

        wb_probe_req_valid = 1'b1;
        wb_probe_req_way = hit_way;
        wb_probe_req_address = probe_address_q;
        wb_probe_req_dirty = 1'b0;
        wb_probe_req_param = NtoN;

        if (|hit) begin
          wb_probe_req_dirty = hit_tag.dirty;
          wb_probe_req_param = probe_param_q == tl_pkg::toB ?
              (hit_tag.writable ? TtoB : BtoB) :
              (hit_tag.writable ? TtoN : BtoN);

          probe_write_req_tag = 1'b1;
          probe_write_ways = hit;
          probe_write_index = probe_address_q[0+:SetsWidth];

          if (probe_param_q == tl_pkg::toB) begin
            probe_write_tag = hit_tag;
            probe_write_tag.dirty = 1'b0;
            probe_write_tag.writable = 1'b0;
          end else begin
            probe_write_tag.valid = 1'b0;
          end
        end
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      probe_state_q <= ProbeStateIdle;
      probe_address_q <= 'x;
      probe_param_q <= 'x;
      probe_lock_q <= 0;
    end else begin
      probe_state_q <= probe_state_d;
      probe_address_q <= probe_address_d;
      probe_param_q <= probe_param_d;
      probe_lock_q <= probe_lock_d;
    end
  end

  /////////////////
  // Flush Logic //
  /////////////////

  typedef enum logic [2:0] {
    FlushStateReset,
    FlushStateIdle,
    FlushStateCheck,
    FlushStateAck,
    FlushStateDone
  } flush_state_e;

  flush_state_e flush_state_q = FlushStateReset, flush_state_d;
  logic [SetsWidth-1:0] flush_index_q, flush_index_d;

  // Dirty tag check
  logic                 flush_has_dirty;
  logic [WaysWidth-1:0] flush_dirty_way;
  tag_t                 flush_dirty_tag;
  always_comb begin
    flush_has_dirty = 1'b0;
    flush_dirty_way = 'x;
    flush_dirty_tag = tag_t'('x);
    for (int i = NumWays - 1; i >= 0; i--) begin
      if (read_tag[i].valid &&
          read_tag[i].writable) begin
        flush_has_dirty = 1'b1;
        flush_dirty_way = i;
        flush_dirty_tag = read_tag[i];
      end
    end
  end

  always_comb begin
    flush_read_index = 'x;
    flush_read_req_tag = 1'b0;
    flush_write_ways = 'x;
    flush_write_index = 'x;
    flush_write_req_tag = 1'b0;
    flush_write_tag = tag_t'('x);

    flush_lock_acq = 1'b0;
    flush_lock_rel = 1'b0;

    wb_flush_req_valid = 1'b0;
    wb_flush_req_way = 'x;
    wb_flush_req_address = 'x;
    wb_flush_req_dirty = 1'bx;
    wb_flush_req_param = 'x;

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
          flush_state_d = FlushStateIdle;
        end
      end

      // Read the tag to prepare for the dirtiness check.
      // This also serves as the idle state as flush_locking would normally stay low.
      FlushStateIdle: begin
        if (flush_locking) begin
          // Performs tag read to determine how to flush
          flush_read_req_tag = 1'b1;
          flush_read_index = flush_index_d;

          flush_state_d = FlushStateCheck;
        end
      end

      // Check tags and initiate cache line release.
      FlushStateCheck: begin
        if (flush_has_dirty) begin
          // If eviction is necesasry do it.
          flush_state_d = FlushStateAck;

          wb_flush_req_valid = 1'b1;
          wb_flush_req_way = flush_dirty_way;
          wb_flush_req_address = {flush_dirty_tag.tag, flush_index_q};
          wb_flush_req_dirty = flush_dirty_tag.dirty;
          wb_flush_req_param = TtoN;

          flush_write_req_tag = 1'b1;
          flush_write_ways = '0;
          flush_write_ways[flush_dirty_way] = 1'b1;
          flush_write_index = flush_index_q;
          flush_write_tag.valid = 1'b0;
        end else begin
          // Otherwise just invalidate all our copies and move to next index.

          flush_index_d = flush_index_q + 1;

          flush_write_req_tag = 1'b1;
          flush_write_ways = '1;
          flush_write_index = flush_index_q;

          flush_write_tag.valid = 1'b0;

          flush_read_req_tag = 1'b1;
          flush_read_index = flush_index_d;

          if (&flush_index_q) begin
            flush_state_d = FlushStateDone;
          end
        end
      end

      FlushStateAck: begin
        if (mem_grant_valid_rel_ack) begin
          flush_state_d = FlushStateIdle;
          // Write-back has consumed our lock, re-acquire.
          flush_lock_acq = 1'b1;
        end
      end

      FlushStateDone: begin
        flush_ready = 1'b1;
        // flush_lock_rel = 1'b1;
        flush_state_d = FlushStateIdle;
      end
    endcase

    if (flush_valid) begin
      // flush_lock_acq = 1'b1;
      flush_state_d = FlushStateDone;
    end
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
    StateEvict,
    StateFill,
    StateUncached,
    StateExceptionLocked,
    StateException
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
  logic [63:0] value_q, value_d;
  logic [1:0]  size_q, size_d;
  size_ext_e   size_ext_q, size_ext_d;
  mem_op_e     op_q, op_d;
  logic [6:0]  amo_q, amo_d;

  wire [63:0] hit_data = read_data[hit_way];
  wire [63:0] hit_data_aligned = align_load(
      .value (hit_data),
      .addr (address_q[2:0]),
      .size (size_q),
      .size_ext (size_ext_q)
  );
  wire [63:0] amo_result = do_amo_op(hit_data_aligned, value_q, size_q, amo_q);

  logic               reserved_q, reserved_d;
  logic [AddrLen-7:0] reservation_q, reservation_d;
  logic               reservation_failed_q, reservation_failed_d;

  logic [WaysWidth-1:0] way_q, way_d;

  wire [PhysAddrLen-1:0] address_phys = req_atp[63] ? {ppn, address_q[11:0]} : address_q[PhysAddrLen-1:0];

  always_comb begin
    cache_d2h_o.req_ready = 1'b0;
    resp_valid = 1'b0;
    resp_value = 'x;
    ex_valid = 1'b0;
    ex_exception = exception_t'('x);
    mem_a_valid = 1'b0;
    mem_a = 'x;
    mem_a.source = SourceBase;
    mem_a.corrupt = 1'b0;

    wb_rel_req_valid = 1'b0;
    wb_rel_req_way = 'x;
    wb_rel_req_address = 'x;
    wb_rel_req_dirty = 1'bx;
    wb_rel_req_param = 'x;

    refill_req_address = address_phys[PhysAddrLen-1:6];
    refill_req_way = way_q;

    access_read_req_tag = 1'b0;
    access_read_req_data = 1'b0;
    access_read_addr = 'x;
    access_read_physical = !req_atp[63];

    access_write_way = hit_way;
    access_write_addr = address_q[3+:SetsWidth+3];
    access_write_req_data = 1'b0;
    access_write_strb = align_strb(address_q[2:0], size_q);
    access_write_data = align_store(amo_result, address_q[2:0]);
    access_write_req_tag = 1'b0;
    access_write_tag = hit_tag;
    access_write_tag.dirty = 1'b1;

    access_lock_acq = 1'b0;
    access_lock_rel = 1'b0;

    state_d = state_q;
    address_d = address_q;
    value_d = value_q;
    size_d = size_q;
    size_ext_d = size_ext_q;
    op_d = op_q;
    amo_d = amo_q;
    evict_way_d = evict_way_q;
    way_d = way_q;
    ex_code_d = ex_code_q;
    req_sent_d = req_sent_q;

    reserved_d = reserved_q;
    reservation_d = reservation_q;
    reservation_failed_d = reservation_failed_q;

    unique case (state_q)
      StateIdle: begin
        cache_d2h_o.req_ready = 1'b1;
      end

      StateFetch: begin
        // Release the access lock. In this state we either complete an access, or we need to
        // wait for refill/TLB access. In either case we will need to release the lock and
        // re-acquire later to prevent deadlock.
        //
        // Note: When we are evicting, we will move the lock from access to writeback, so
        // conceptually we shouldn't be releasing the lock. However this is okay because
        // release_lock_move takes precedence to access_lock_rel.
        access_lock_rel = 1'b1;

        if (req_atp[63] && !ppn_valid) begin
          // TLB miss, wait for it to be ready again.
          state_d = StateWaitTLB;
        end
        else if (req_atp[63] && (
            !ppn_perm.valid  || // Invalid
            (!ppn_perm.writable && op_q != MEM_LOAD) || // Write denied
            (!ppn_perm.readable && !req_mxr) || // Read Instruction Memory without MXR
            (!ppn_perm.user && !req_prv) || // Accessing supervisor memory
            (ppn_perm.user && req_prv && !req_sum) // Accessing user memory without SUM
        )) begin
          // Exception from page table lookup.
          state_d = StateException;
          ex_code_d = op_q == MEM_LOAD ? EXC_CAUSE_LOAD_PAGE_FAULT : EXC_CAUSE_STORE_PAGE_FAULT;
        end else if (reservation_failed_q) begin
          cache_d2h_o.req_ready = 1'b1;
          resp_valid = 1'b1;
          resp_value = 1;
          state_d = StateIdle;
        end else if (|hit && (hit_tag.writable || op_q == MEM_LOAD)) begin
          // Cache valid with required permission.

          cache_d2h_o.req_ready = 1'b1;
          resp_valid = 1'b1;
          resp_value = op_q[0] ? hit_data_aligned : 0;
          state_d = StateIdle;

          // MEM_STORE/MEM_SC/MEM_AMO
          if (op_q[1]) begin
            // Write data and make tag dirty.
            access_write_req_data = 1'b1;
            access_write_req_tag = 1'b1;
          end
        end else if (op_q == MEM_SC) begin
          cache_d2h_o.req_ready = 1'b1;
          resp_valid = 1'b1;
          resp_value = 1;
          state_d = StateIdle;
        end else begin
          way_d = hit_way;
          if (~|hit) begin
            evict_way_d = evict_way_q + 1;
          end

          req_sent_d = 1'b0;
          state_d = StateFill;

          if (hit_tag.valid &&
              hit_tag.writable) begin
            state_d = StateEvict;

            wb_rel_req_valid = 1'b1;
            wb_rel_req_way = way_d;
            wb_rel_req_address = {hit_tag.tag, address_q[6+:SetsWidth]};
            wb_rel_req_dirty = hit_tag.dirty;
            wb_rel_req_param = TtoN;

            // Make tag invalid
            access_write_req_tag = 1'b1;
            access_write_tag.valid = 1'b0;
          end
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

      StateEvict: begin
        if (mem_grant_valid_rel_ack) begin
          state_d = StateFill;
        end
      end

      StateFill: begin
        mem_a_valid = !req_sent_q;
        mem_a.opcode = AcquireBlock;
        mem_a.param = op_q != MEM_LOAD ? (|hit ? tl_pkg::BtoT : tl_pkg::NtoT) : tl_pkg::NtoB;
        mem_a.size = 6;
        mem_a.address = {address_phys[PhysAddrLen-1:6], 6'd0};
        mem_a.mask = '1;
        if (mem_a_ready) begin
          req_sent_d = 1'b1;
        end

        if (mem_grant_last) begin
          if (mem_grant_denied) begin
            // In case of denied, this can be:
            // * An actual access error
            // * The target just denies AcquireBlock
            // So if the op is MEM_LOAD or MEM_STORE, we try uncached access, otherwise it is an access error.
            case (op_q)
              MEM_LOAD, MEM_STORE: begin
                req_sent_d = 1'b0;
                state_d = StateUncached;
              end
              MEM_LR, MEM_SC, MEM_AMO: begin
                ex_code_d = EXC_CAUSE_STORE_ACCESS_FAULT;
                state_d = StateException;
              end
            endcase
          end else begin
            // Re-acquire lock that refiller released.
            // FIXME: Maybe should let refiller give lock back to us like I$.
            state_d = StateReplay;
            access_lock_acq = 1'b1;
          end
        end
      end

      StateUncached: begin
        mem_a_valid = !req_sent_q;
        mem_a.opcode = op_q[0] ? Get : PutFullData;
        mem_a.param = 0;
        mem_a.size = size_q;
        mem_a.address = address_phys;
        mem_a.mask = tl_align_strb(align_strb(address_q[2:0], size_q), address_q[NonBurstSize-1:0]);
        mem_a.data = tl_align_store(align_store(value_q, address_q[2:0]));
        if (mem_a_ready) req_sent_d = 1'b1;

        if (mem_grant_valid_access) begin
          if (mem_grant_denied) begin
            state_d = StateException;
            ex_code_d = op_q == MEM_LOAD ? EXC_CAUSE_LOAD_ACCESS_FAULT : EXC_CAUSE_STORE_ACCESS_FAULT;
          end
          else begin
            cache_d2h_o.req_ready = 1'b1;
            resp_valid = 1'b1;
            resp_value = align_load(
                .value (tl_align_load(mem_grant_data, address_q[NonBurstSize-1:0])),
                .addr (address_q[2:0]),
                .size (size_q),
                .size_ext (size_ext_q)
            );
            state_d = StateIdle;
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
        ex_exception.cause = ex_code_q;
        ex_exception.tval = address_q;
        state_d = StateIdle;
      end
    endcase

    if (req_valid) begin
      address_d = req_address;
      size_d = req_size;
      size_ext_d = req_size_ext;
      op_d = req_op;
      // Translate MEM_STORE/MEM_SC to AMOSWAP, so we can reuse the AMOALU.
      amo_d = !req_op[0] ? 7'b0000100 : req_amo;
      value_d = req_value;

      // Access the cache
      access_lock_acq = 1'b1;
      access_read_req_tag = 1'b1;
      access_read_req_data = 1'b1;
      access_read_addr = address_d[AddrLen-1:3];

      // Load reservation. The reservation is single-use; it is cleared by any other memory access.
      reserved_d = req_op == MEM_LR;
      reservation_d = req_address[AddrLen-1:6];
      reservation_failed_d = req_op == MEM_SC && (req_address[AddrLen-1:6] != reservation_q || !reserved_q);

      state_d = StateFetch;

      // If we failed to acquire the lock this cycle, move into replay state.
      if (!access_locking) state_d = StateReplay;

      // Misaligned memory load/store will trigger an exception.
      // Note that we would like to avoid complicating the condition for access_lock_acq
      // to trigger, so move to an intermediate state to have the lock released.
      if (!is_aligned(req_address[2:0], req_size)) begin
        state_d = StateExceptionLocked;
        ex_code_d = req_op == MEM_LOAD ? EXC_CAUSE_LOAD_MISALIGN : EXC_CAUSE_STORE_MISALIGN;
      end

      if (req_atp[63] && !canonical_virtual) begin
        state_d = StateExceptionLocked;
        ex_code_d = req_op == MEM_LOAD ? EXC_CAUSE_LOAD_PAGE_FAULT : EXC_CAUSE_STORE_PAGE_FAULT;
      end

      if (!req_atp[63] && !canonical_physical) begin
        state_d = StateExceptionLocked;
        ex_code_d = req_op == MEM_LOAD ? EXC_CAUSE_LOAD_ACCESS_FAULT : EXC_CAUSE_STORE_ACCESS_FAULT;
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= StateIdle;
      address_q <= '0;
      value_q <= 'x;
      size_q <= 'x;
      size_ext_q <= size_ext_e'('x);
      op_q <= mem_op_e'('x);
      amo_q <= 'x;
      evict_way_q <= 0;
      way_q <= 'x;
      req_sent_q <= '0;
      ex_code_q <= exc_cause_e'('x);
      reserved_q <= 1'b0;
      reservation_q <= 'x;
      reservation_failed_q <= 1'bx;
    end else begin
      state_q <= state_d;
      address_q <= address_d;
      value_q <= value_d;
      size_q <= size_d;
      size_ext_q <= size_ext_d;
      op_q <= op_d;
      amo_q <= amo_d;
      evict_way_q <= evict_way_d;
      way_q <= way_d;
      req_sent_q <= req_sent_d;
      ex_code_q <= ex_code_d;
      reserved_q <= reserved_d;
      reservation_q <= reservation_d;
      reservation_failed_q <= reservation_failed_d;
    end
  end

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
