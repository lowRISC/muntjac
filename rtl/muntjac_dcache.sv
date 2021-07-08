`include "tl_util.svh"
`include "prim_assert.sv"

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
    parameter bit [SourceWidth-1:0] SourceBase  = 0,
    parameter bit [SourceWidth-1:0] PtwSourceBase = 0,

    parameter int unsigned TlbNumWays = 32,
    parameter int unsigned TlbSetsWidth = 0,

    parameter bit          EnableHpm   = 0

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
    `TL_DECLARE_HOST_PORT(DataWidth, PhysAddrLen, SourceWidth, SinkWidth, mem)
);

  // This is the largest address width that we ever have to deal with.
  localparam LogicAddrLen = VirtAddrLen > PhysAddrLen ? VirtAddrLen : PhysAddrLen;

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
    .prb_len_o (),
    .rel_len_o (),
    .gnt_len_o (),
    .req_idx_o (),
    .prb_idx_o (),
    .rel_idx_o (),
    .gnt_idx_o (mem_d_idx),
    .req_left_o (),
    .prb_left_o (),
    .rel_left_o (),
    .gnt_left_o (),
    .req_first_o (),
    .prb_first_o (),
    .rel_first_o (),
    .gnt_first_o (),
    .req_last_o (mem_a_last),
    .prb_last_o (),
    .rel_last_o (),
    .gnt_last_o (mem_d_last)
  );

  // #endregion
  /////////////////////////////////////////

  //////////////////////////////
  // #region Helper functions //

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

  function automatic logic [63:0] combine_word (
      input  logic [63:0] old_value,
      input  logic [63:0] new_value,
      input  logic [7:0]  mask
  );

    combine_word = old_value;
    for (int i = 0; i < 8; i++) begin
      if (mask[i]) combine_word[i * 8 +: 8] = new_value[i * 8 +: 8];
    end

  endfunction

  function automatic logic [63:0] do_amo_op (
      // We make these bit instead of logic, because addition and subtraction will produce x
      // if any bits of these are x. So even if highest bits are x it also corrupt lower bits.
      input  bit   [63:0] original,
      input  bit   [63:0] operand,
      input  logic [7:0]  mask,
      input  logic [6:0]  amo
  );

    automatic logic [31:0] difference_lsb;
    automatic logic        borrow_lsb;
    automatic logic [31:0] difference_msb;
    automatic logic [63:0] difference;

    automatic logic original_sign;
    automatic logic operand_sign;
    automatic logic difference_sign;
    automatic logic lt_flag;

    // Perform subtraction. Only propagating the borrow bit if `mask[3]` is set.
    {borrow_lsb, difference_lsb} = {1'b0, original[31:0]} + {1'b0, ~operand[31:0]} + 33'b1;
    difference_msb = original[63:32] + ~operand[63:32] + {31'b0, !mask[3] | borrow_lsb};
    difference = {difference_msb, difference_lsb};

    // Get the sign bits for comparision needs
    original_sign = mask[7] ? original[63] : original[31];
    operand_sign = mask[7] ? operand[63] : operand[31];
    difference_sign = mask[7] ? difference[63] : difference[31];

    // If MSBs are the same, look at the sign of the result is sufficient.
    // Otherwise the one with MSB 0 is larger (if signed) and smaller (if unsigned).
    lt_flag = original_sign == operand_sign ? difference_sign : (amo[5] ? operand_sign : original_sign);

    unique casez (amo[6:2])
      5'b00001: do_amo_op = operand;
      5'b00000: begin
        automatic logic [31:0] sum_lsb;
        automatic logic        carry_lsb;
        automatic logic [31:0] sum_msb;

        {carry_lsb, sum_lsb} = {1'b0, original[31:0]} + {1'b0, operand[31:0]};
        sum_msb = original[63:32] + operand[63:32] + {31'b0, mask[3] & carry_lsb};
        do_amo_op = {sum_msb, sum_lsb};
      end
      5'b00100: do_amo_op = original ^ operand;
      5'b01100: do_amo_op = original & operand;
      5'b01000: do_amo_op = original | operand;
      5'b1?000: do_amo_op = lt_flag ? original : operand;
      5'b1?100: do_amo_op = lt_flag ? operand : original;
      default: do_amo_op = 'x;
    endcase
  endfunction

  // #endregion
  //////////////////////////////

  /////////////////////////////
  // #region Type definition //

  typedef struct packed {
    // Tag, excluding the bits used for direct-mapped access and last 6 bits of offset.
    logic [PhysAddrLen-SetsWidth-LineWidth-1:0] tag;
    logic writable;
    logic dirty;
    logic valid;
  } tag_t;

  // #endregion
  /////////////////////////////

  ////////////////////////////////
  // #region CPU Facing signals //

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

  wire mem_d_valid_refill  = mem_d_valid && mem_d.opcode inside {Grant, GrantData};
  wire mem_d_valid_rel_ack = mem_d_valid && mem_d.opcode == ReleaseAck;
  wire mem_d_valid_access  = mem_d_valid && mem_d.source != PtwSourceBase && mem_d.opcode inside {AccessAck, AccessAckData};
  wire mem_d_valid_ptw     = mem_d_valid && mem_d.source == PtwSourceBase;

  logic mem_d_ready_refill;
  logic mem_d_ready_ptw;
  assign mem_d_ready = mem_d_valid_refill ? mem_d_ready_refill : (mem_d_valid_ptw ? mem_d_ready_ptw : 1'b1);

  // #endregion
  //////////////////////////////////////

  //////////////////////////////
  // #region Lock arbitration //

  logic probe_tracker_valid;
  logic flush_tracker_valid;
  logic refill_tracker_valid;
  logic writeback_tracker_valid;

  // Used for blocking other components from acquiring the lock while access lock writes back dirty
  // data.
  logic access_lock_acq;

  logic refill_lock_acq;
  logic probe_lock_acq;
  logic writeback_lock_acq;
  logic flush_lock_acq;

  // Indicates the most recently refilled set number.
  // A valid recently-refilled set would prevent the probe logic from invalidating the cache line,
  // therefore ensuring forward progress.
  // Cleared once a store has happened or 16 cycles have lapsed.
  logic       access_lock_valid;
  logic [5:0] access_lock_addr;

  wire nothing_in_progress = !(refill_tracker_valid || probe_tracker_valid || writeback_tracker_valid || flush_tracker_valid);

  logic refill_locking;
  logic probe_locking;
  logic flush_locking;

  // Arbitrate on the new holder of the lock
  always_comb begin
    refill_locking = 1'b0;
    probe_locking = 1'b0;
    flush_locking = 1'b0;

    if (nothing_in_progress) begin
      priority case (1'b1)
        access_lock_acq:;
        writeback_lock_acq:;
        // This blocks channel D, so it must have highest priority by TileLink rule
        refill_lock_acq: begin
          refill_locking = 1'b1;
        end
        // This blocks other agents, so make it more important than the rest.
        probe_lock_acq: begin
          probe_locking = 1'b1;
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
  logic [LogicAddrLen-3-1:0] access_data_read_addr;

  logic                   access_tag_write_req;
  logic                   access_tag_write_gnt;
  logic [SetsWidth-1:0]   access_tag_write_addr;
  logic [WaysWidth-1:0]   access_tag_write_way;
  tag_t                   access_tag_write_data;

  logic                   access_data_write_req;
  logic                   access_data_write_gnt;
  logic [SetsWidth+3-1:0] access_data_write_addr;
  logic [WaysWidth-1:0]   access_data_write_way;
  logic [63:0]            access_data_write_data;

  logic                   wb_data_read_req;
  logic                   wb_data_read_gnt;
  logic [SetsWidth+3-1:0] wb_data_read_addr;
  logic [WaysWidth-1:0]   wb_data_read_way;

  logic                           refill_tag_write_req;
  logic                           refill_tag_write_gnt;
  logic [SetsWidth-1:0]           refill_tag_write_addr;
  logic [WaysWidth-1:0]           refill_tag_write_way;
  tag_t                           refill_tag_write_data;

  logic                           refill_data_write_req;
  logic                           refill_data_write_gnt;
  logic [SetsWidth+3-1:0]         refill_data_write_addr;
  logic [WaysWidth-1:0]           refill_data_write_way;
  logic [NumInterleave-1:0][63:0] refill_data_write_data;

  logic                      probe_tag_read_req;
  logic                      probe_tag_read_gnt;
  logic [LogicAddrLen-6-1:0] probe_tag_read_addr;

  logic                  probe_tag_write_req;
  logic                  probe_tag_write_gnt;
  logic [SetsWidth-1:0]  probe_tag_write_addr;
  logic [NumWays-1:0]    probe_tag_write_ways;
  tag_t                  probe_tag_write_data;

  logic                  flush_tag_read_req;
  logic                  flush_tag_read_gnt;
  logic [SetsWidth-1:0]  flush_tag_read_addr;

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
  logic [SetsWidth+3-1:0]         data_addr;
  logic [WaysWidth-1:0]           data_way;
  logic [NumInterleave-1:0][63:0] data_write_data;
  logic                           data_wide;
  logic [63:0]                    data_read_data [NumWays];

  always_comb begin
    refill_tag_write_gnt = 1'b0;
    probe_tag_write_gnt = 1'b0;
    probe_tag_read_gnt = 1'b0;
    flush_tag_write_gnt = 1'b0;
    flush_tag_read_gnt = 1'b0;
    access_tag_write_gnt = 1'b0;
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

      probe_tag_write_req: begin
        probe_tag_write_gnt = 1'b1;
        tag_write_req = 1'b1;
        tag_addr[SetsWidth-1:0] = probe_tag_write_addr;
        tag_write_ways = probe_tag_write_ways;
        tag_write_data = probe_tag_write_data;
      end
      probe_tag_read_req: begin
        probe_tag_read_gnt = 1'b1;
        tag_read_req = 1'b1;
        tag_addr = probe_tag_read_addr;
        tag_read_physical = 1'b1;
      end

      flush_tag_write_req: begin
        flush_tag_write_gnt = 1'b1;
        tag_write_req = 1'b1;
        tag_addr[SetsWidth-1:0] = flush_tag_write_addr;
        tag_write_ways = flush_tag_write_ways;
        tag_write_data = flush_tag_write_data;
      end
      flush_tag_read_req: begin
        flush_tag_read_gnt = 1'b1;
        tag_read_req = 1'b1;
        tag_addr = flush_tag_read_addr;
        tag_read_physical = 1'b1;
      end

      access_tag_write_req: begin
        access_tag_write_gnt = 1'b1;
        tag_write_req = 1'b1;
        tag_addr[SetsWidth-1:0] = access_tag_write_addr;
        for (int i = 0; i < NumWays; i++) tag_write_ways[i] = access_tag_write_way == i;
        tag_write_data = access_tag_write_data;
      end
      // Access logic has lowest read priority so that it prevents the cache from
      // starving other cores.
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
    `ASSERT(probe_tag_write, probe_tag_write_req |-> probe_tag_write_gnt);
    `ASSERT(probe_tag_read, probe_tag_read_req |-> probe_tag_read_gnt);
    `ASSERT(flush_tag_write, flush_tag_write_req |-> flush_tag_write_gnt);
    `ASSERT(flush_tag_read, flush_tag_read_req |-> flush_tag_read_gnt);
    `ASSERT(access_tag_write, access_tag_write_req |-> access_tag_write_gnt);
  end

  always_comb begin
    refill_data_write_gnt = 1'b0;
    wb_data_read_gnt = 1'b0;
    access_data_write_gnt = 1'b0;
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

      wb_data_read_req: begin
        wb_data_read_gnt = 1'b1;
        data_read_req = 1'b1;
        data_addr = wb_data_read_addr;
        data_way = wb_data_read_way;
        data_wide = 1'b1;
      end

      access_data_write_req: begin
        access_data_write_gnt = 1'b1;
        data_write_req = 1'b1;
        data_addr = access_data_write_addr;
        data_way = access_data_write_way;
        data_write_data = {NumInterleave{access_data_write_data}};
      end
      // Access logic has lowest read priority so that it prevents the cache from
      // starving other cores.
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
    `ASSERT(wb_data_read, wb_data_read_req |-> wb_data_read_gnt);
    `ASSERT(access_data_write, access_data_write_req |-> access_data_write_gnt);
  end

  logic tag_read_physical_latch;
  logic [LogicAddrLen-6-1:0] tag_read_addr_latch;
  logic [2:0] data_read_addr_latch;
  logic [WaysWidth-1:0] data_way_latch;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      tag_read_physical_latch <= 1'b1;
      tag_read_addr_latch <= 'x;
      data_read_addr_latch <= 'x;
      data_way_latch <= 'x;
    end else begin
      if (tag_read_req) begin
        tag_read_physical_latch <= tag_read_physical;
        tag_read_addr_latch <= tag_addr;
      end
      if (data_read_req) begin
        data_read_addr_latch <= data_addr[2:0];
        data_way_latch <= data_way;
      end
    end
  end

  // Interleave the read data
  logic [63:0] data_read_data_interleave [NumWays];
  for (genvar i = 0; i < NumWays; i++) begin
    assign data_read_data[i] = data_read_data_interleave[i ^ (data_read_addr_latch & InterleaveMask)];
  end
  logic [DataWidth-1:0] data_read_data_wide;
  always_comb begin
    for (int i = 0; i < NumInterleave; i++) begin
      data_read_data_wide[i * 64 +: 64] = data_read_data[(data_way_latch &~ InterleaveMask) | i];
    end
  end

  // Interleave the write ways and data
  logic [NumWays-1:0] data_write_ways_interleave;
  logic [NumInterleave-1:0][63:0] data_write_data_interleave;
  for (genvar i = 0; i < NumWays; i++) begin
    assign data_write_ways_interleave[i] =
      (data_way &~ InterleaveMask) == (i &~ InterleaveMask) &&
      (data_wide || (data_way & InterleaveMask) == ((i ^ data_addr) & InterleaveMask));
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

    wire [SetsWidth+3-1:0] data_addr_effective = data_addr ^ (data_wide ? (i & InterleaveMask) : 0);

    prim_ram_1p #(
        .Width           (64),
        .Depth           (2 ** (SetsWidth + 3)),
        .DataBitsPerMask (64)
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

  ////////////////////////////////////////
  // #region Dirty Data Writeback Logic //

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

  typedef enum logic [1:0] {
    WbStateIdle,
    WbStateProgress,
    WbStateWait
  } wb_state_e;

  wb_state_e              wb_state_q, wb_state_d;
  logic [WaysWidth-1:0]   wb_way_q, wb_way_d;
  logic [OffsetWidth-1:0] wb_index_q, wb_index_d;
  tl_c_op_e               wb_opcode_q, wb_opcode_d;
  logic [2:0]             wb_param_q, wb_param_d;
  logic [PhysAddrLen-7:0] wb_address_q, wb_address_d;

  logic evict_completed_q, evict_completed_d;

  logic [DataWidth-1:0] wb_data_skid;
  logic [DataWidth-1:0] wb_data_skid_valid;

  assign writeback_tracker_valid = wb_state_q != WbStateIdle;

  always_comb begin
    wb_data_read_req = 1'b0;
    wb_data_read_addr = 'x;
    wb_data_read_way = 'x;

    writeback_lock_acq = 1'b0;

    wb_state_d = wb_state_q;
    wb_index_d = wb_index_q;
    wb_way_d = wb_way_q;
    wb_opcode_d = wb_opcode_q;
    wb_param_d = wb_param_q;
    wb_address_d = wb_address_q;

    mem_c_valid = 1'b0;
    mem_c = 'x;

    evict_completed_d = evict_completed_q;
    if (mem_d_valid_rel_ack) begin
      evict_completed_d = 1'b1;
    end

    unique case (wb_state_q)
      WbStateIdle: begin
        if (wb_req_valid) begin
          writeback_lock_acq = 1'b1;
          wb_state_d = WbStateProgress;
          wb_way_d = wb_req_way;
          wb_opcode_d = wb_req_active ?
            (wb_req_dirty ? ReleaseData : Release) :
            (wb_req_dirty ? ProbeAckData : ProbeAck);
          wb_param_d = wb_req_param;
          wb_address_d = wb_req_address;
          evict_completed_d = 1'b0;

          // When wb_req_dirty is false, set wb_index to 0 to hint this is the last cycle.
          wb_index_d = wb_req_dirty ? 1 : 0;
          if (wb_req_dirty) begin
            wb_data_read_req = 1'b1;
            wb_data_read_way = wb_way_d;
            wb_data_read_addr = {wb_address_d[SetsWidth-1:0], 3'd0};
          end
        end
      end

      WbStateProgress: begin
        mem_c_valid = 1'b1;
        mem_c.opcode = wb_opcode_q;
        mem_c.param = wb_param_q;
        mem_c.size = 6;
        mem_c.source = SourceBase;
        mem_c.address = {wb_address_q, 6'd0};
        mem_c.corrupt = 1'b0;
        mem_c.data = wb_data_skid_valid ? wb_data_skid : data_read_data_wide;

        if (mem_c_ready) begin
          wb_index_d = wb_index_q + 1;

          if (wb_index_q == 0) begin
            // Last cycle. Signal the invoker and clear progress bit.
            wb_state_d = wb_opcode_q inside {Release, ReleaseData} ? WbStateWait : WbStateIdle;
          end else begin
            wb_data_read_req = 1'b1;
            wb_data_read_way = wb_way_d;
            wb_data_read_addr = {wb_address_d[SetsWidth-1:0], 3'(wb_index_q << InterleaveWidth)};
          end
        end
      end

      WbStateWait: begin
        if (evict_completed_d) begin
          wb_state_d = WbStateIdle;
        end
      end

      default:;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      wb_state_q <= WbStateIdle;
      wb_index_q <= 0;
      wb_way_q <= 0;
      wb_opcode_q <= tl_c_op_e'('x);
      wb_param_q <= 'x;
      wb_address_q <= 'x;
      evict_completed_q <= 1'b0;
      wb_data_skid_valid <= 1'b0;
      wb_data_skid <= 'x;
    end else begin
      wb_state_q <= wb_state_d;
      wb_index_q <= wb_index_d;
      wb_way_q <= wb_way_d;
      wb_opcode_q <= wb_opcode_d;
      wb_param_q <= wb_param_d;
      wb_address_q <= wb_address_d;
      evict_completed_q <= evict_completed_d;
      if (!wb_data_skid_valid && mem_c_valid) begin
        wb_data_skid_valid <= 1'b1;
        wb_data_skid <= data_read_data_wide;
      end
      if (mem_c_ready) begin
        wb_data_skid_valid <= 1'b0;
      end
    end
  end

  // #endregion
  ////////////////////////////////////////

  //////////////////////////
  // #region Refill Logic //

  typedef `TL_D_STRUCT(DataWidth, PhysAddrLen, SourceWidth, SinkWidth) gnt_t;

  logic refill_fifo_insert;
  logic refill_fifo_valid;
  logic refill_fifo_ready;
  logic refill_fifo_last;
  gnt_t refill_fifo_beat;
  logic [OffsetWidth-1:0] refill_fifo_idx;

  // Use bit instead of logic here because fifo has an assertion that requires data to be known.
  bit [$bits(gnt_t)-1:0] gnt_w;
  assign gnt_w = mem_d;

  prim_fifo_sync #(
    .Width ($bits(gnt_t) + 1 + OffsetWidth),
    .Pass  (1'b1),
    .Depth (2 ** (LineWidth - NonBurstSize))
  ) refill_fifo (
    .clk_i,
    .rst_ni,
    .clr_i  (1'b0),
    .wvalid (refill_fifo_insert),
    .wready (),
    .wdata  ({gnt_w, mem_d_last, mem_d_idx}),
    .rvalid (refill_fifo_valid),
    .rready (refill_fifo_ready),
    .rdata  ({refill_fifo_beat, refill_fifo_last, refill_fifo_idx}),
    .depth  ()
  );

  logic refill_beat_saved_q, refill_beat_saved_d;
  logic refill_beat_acked_q, refill_beat_acked_d;

  always_comb begin
    refill_beat_saved_d = refill_beat_saved_q;
    refill_beat_acked_d = refill_beat_acked_q;

    refill_fifo_insert = 1'b0;
    mem_d_ready_refill = 1'b0;
    mem_e_valid = 1'b0;
    mem_e = 'x;

    if (mem_d_valid_refill) begin
      mem_d_ready_refill = 1'b1;

      if (!refill_beat_saved_q) begin
        refill_fifo_insert = 1'b1;
        refill_beat_saved_d = 1'b1;
      end

      // Send back an ack to memory. To avoid unnecessary blocking we add a FIFO to the
      // E channel.
      // It's okay to send back an ack now, because refill logic takes priority to the probe logic
      // so we will indeed observe the effect of refill before any further probes.
      if (!refill_beat_acked_q && mem_d_last) begin
        mem_e_valid = 1'b1;
        mem_e.sink = mem_d.sink;

        // Hold the beat until acknowledge is sent.
        if (mem_e_ready) begin
          refill_beat_acked_d = 1'b1;
        end else begin
          mem_d_ready_refill = 1'b0;
        end
      end

      if (mem_d_ready_refill) begin
        refill_beat_saved_d = 1'b0;
        refill_beat_acked_d = 1'b0;
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      refill_beat_saved_q <= 1'b0;
      refill_beat_acked_q <= 1'b0;
    end else begin
      refill_beat_saved_q <= refill_beat_saved_d;
      refill_beat_acked_q <= refill_beat_acked_d;
    end
  end

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
    refill_fifo_ready = 1'b0;

    refill_state_d = refill_state_q;

    unique case (refill_state_q)
      RefillStateIdle: begin
        if (refill_fifo_valid) begin
          refill_lock_acq = 1'b1;
          if (refill_locking) begin
            refill_state_d = RefillStateProgress;
            refill_tracker_valid_d = 1'b1;
          end
        end
      end
      RefillStateProgress: begin
        if (refill_fifo_valid) begin
          refill_fifo_ready = 1'b1;

          // If the beat contains data, write it.
          if (refill_fifo_beat.opcode == GrantData && !refill_fifo_beat.denied) begin
            refill_data_write_req = 1'b1;
            refill_data_write_way = refill_req_way;
            refill_data_write_addr = {refill_req_address[SetsWidth-1:0], 3'(refill_fifo_idx << InterleaveWidth)};
            refill_data_write_data = refill_fifo_beat.data;
          end

          // Update the metadata. This should only be done once, we can do it in either time.
          if (refill_fifo_last && !refill_fifo_beat.denied) begin
            refill_tag_write_req = 1'b1;
            refill_tag_write_way = refill_req_way;
            refill_tag_write_addr = refill_req_address[SetsWidth-1:0];
            refill_tag_write_data.tag = refill_req_address[PhysAddrLen-7:SetsWidth];
            refill_tag_write_data.writable = refill_fifo_beat.param == tl_pkg::toT;
            refill_tag_write_data.dirty = 1'b0;
            refill_tag_write_data.valid = 1'b1;
          end

          if (refill_fifo_ready) begin
            if (refill_fifo_last) begin
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

  wire tag_t hit_tag = tag_read_data[hit_way];
  wire [63:0] hit_data = data_read_data[hit_way];

  // #endregion
  ///////////////////////////////////

  /////////////////////////
  // #region Probe Logic //

  typedef enum logic {
    ProbeStateIdle,
    ProbeStateCheck
  } probe_state_e;

  probe_state_e probe_state_q = ProbeStateIdle, probe_state_d;
  logic probe_tracker_valid_d;

  logic [PhysAddrLen-7:0] probe_address_q, probe_address_d;
  logic [2:0] probe_param_q, probe_param_d;

  always_comb begin
    probe_tracker_valid_d = probe_tracker_valid;
    probe_lock_acq = 1'b0;
    probe_tag_read_req = 1'b0;
    probe_tag_read_addr = 'x;

    probe_tag_write_req = 1'b0;
    probe_tag_write_ways = 'x;
    probe_tag_write_addr = 'x;
    probe_tag_write_data = tag_t'('x);

    wb_probe_req_valid = 1'b0;
    wb_probe_req_way = 'x;
    wb_probe_req_address = 'x;
    wb_probe_req_dirty = 1'bx;
    wb_probe_req_param = 'x;

    probe_state_d = probe_state_q;
    probe_address_d = probe_address_q;
    probe_param_d = probe_param_q;

    mem_b_ready = 1'b0;

    unique case (probe_state_q)
      // Waiting for a probe request to reach us.
      ProbeStateIdle: begin
        probe_lock_acq = mem_b_valid;
        if (access_lock_valid && access_lock_addr == mem_b.address[11:6]) begin
          probe_lock_acq = 1'b0;
        end

        if (probe_locking) begin
          mem_b_ready = 1'b1;
          probe_address_d = mem_b.address[PhysAddrLen-1:6];
          probe_param_d = mem_b.param;

          // Does the tag read necessary for performing invalidation
          probe_tag_read_req = 1'b1;
          probe_tag_read_addr = probe_address_d;

          probe_state_d = ProbeStateCheck;
          probe_tracker_valid_d = 1'b1;
        end
      end
      // Act upon tag read
      ProbeStateCheck: begin
        probe_state_d = ProbeStateIdle;

        // Lock transferred to writeback logic.
        probe_tracker_valid_d = 1'b0;

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

          probe_tag_write_req = 1'b1;
          probe_tag_write_ways = hit;
          probe_tag_write_addr = probe_address_q[0+:SetsWidth];

          if (probe_param_q == tl_pkg::toB) begin
            probe_tag_write_data = hit_tag;
            probe_tag_write_data.dirty = 1'b0;
            probe_tag_write_data.writable = 1'b0;
          end else begin
            probe_tag_write_data.valid = 1'b0;
          end
        end
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      probe_state_q <= ProbeStateIdle;
      probe_tracker_valid <= 1'b0;
      probe_address_q <= 'x;
      probe_param_q <= 'x;
    end else begin
      probe_state_q <= probe_state_d;
      probe_tracker_valid <= probe_tracker_valid_d;
      probe_address_q <= probe_address_d;
      probe_param_q <= probe_param_d;
    end
  end

  // #endregion
  /////////////////////////

  /////////////////////////
  // #region Flush Logic //

  typedef enum logic [2:0] {
    FlushStateReset,
    FlushStateIdle,
    FlushStateReadTag,
    FlushStateCheck,
    FlushStateDone
  } flush_state_e;

  flush_state_e flush_state_q = FlushStateReset, flush_state_d;
  logic flush_tracker_valid_d;
  logic flush_tlb_pending_q, flush_tlb_pending_d;
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
      if (tag_read_data[i].valid &&
          tag_read_data[i].writable) begin
        flush_has_dirty = 1'b1;
        flush_dirty_way = i;
        flush_dirty_tag = tag_read_data[i];
      end
    end
  end

  always_comb begin
    flush_tag_read_addr = 'x;
    flush_tag_read_req = 1'b0;
    flush_tag_write_ways = 'x;
    flush_tag_write_addr = 'x;
    flush_tag_write_req = 1'b0;
    flush_tag_write_data = tag_t'('x);

    flush_tracker_valid_d = flush_tracker_valid;
    flush_lock_acq = 1'b0;

    wb_flush_req_valid = 1'b0;
    wb_flush_req_way = 'x;
    wb_flush_req_address = 'x;
    wb_flush_req_dirty = 1'bx;
    wb_flush_req_param = 'x;

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
          flush_state_d = FlushStateIdle;
        end
      end

      FlushStateIdle: begin
        if (flush_valid) begin
          // flush_state_d = FlushStateReadTag;
          flush_state_d = FlushStateDone;
          flush_tlb_pending_d = 1'b1;
        end
      end

      // Read the tag to prepare for the dirtiness check.
      FlushStateReadTag: begin
        flush_lock_acq = !flush_tracker_valid;

        if (flush_tracker_valid || flush_locking) begin
          // Performs tag read to determine how to flush.
          flush_tag_read_req = 1'b1;
          flush_tag_read_addr = flush_index_q;

          flush_state_d = FlushStateCheck;
          flush_tracker_valid_d = 1'b1;
        end
      end

      // Check tags and initiate cache line release.
      FlushStateCheck: begin
        flush_state_d = FlushStateReadTag;

        if (flush_has_dirty) begin
          // If eviction is necesasry do it.
          flush_tracker_valid_d = 1'b0;

          wb_flush_req_valid = 1'b1;
          wb_flush_req_way = flush_dirty_way;
          wb_flush_req_address = {flush_dirty_tag.tag, flush_index_q};
          wb_flush_req_dirty = flush_dirty_tag.dirty;
          wb_flush_req_param = TtoN;

          flush_tag_write_req = 1'b1;
          flush_tag_write_ways = '0;
          flush_tag_write_ways[flush_dirty_way] = 1'b1;
          flush_tag_write_addr = flush_index_q;
          flush_tag_write_data.valid = 1'b0;
        end else begin
          // Otherwise just invalidate all our copies and move to next index.
          flush_index_d = flush_index_q + 1;

          flush_tag_write_req = 1'b1;
          flush_tag_write_ways = '1;
          flush_tag_write_addr = flush_index_q;
          flush_tag_write_data.valid = 1'b0;

          if (&flush_index_q) begin
            flush_tracker_valid_d = 1'b0;
            flush_state_d = FlushStateDone;
          end
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

  typedef enum logic [2:0] {
    MissStateIdle,
    MissStateFill,
    MissStateUncached
  } miss_state_e;

  miss_state_e miss_state_q, miss_state_d;

  logic                    miss_req_valid;
  logic                    miss_req_upgrade;
  mem_op_e                 miss_req_op;
  logic [PhysAddrLen-1:0]  miss_req_address;
  logic [1:0]              miss_req_size;
  logic [7:0]              miss_req_mask;
  logic [63:0]             miss_req_data;

  logic miss_resp_replay;
  logic miss_resp_exception;
  logic miss_resp_valid;
  logic [63:0] miss_resp_data;

  logic miss_upgrade_q, miss_upgrade_d;
  logic miss_refill_sent_q, miss_refill_sent_d;
  logic miss_uncached_sent_q, miss_uncached_sent_d;

  always_comb begin
    miss_resp_replay = 1'b0;
    miss_resp_exception = 1'b0;
    miss_resp_valid = 1'b0;
    miss_resp_data = 'x;

    mem_a_valid_mult[AIdxRefill] = 1'b0;
    mem_a_mult[AIdxRefill] = 'x;

    miss_state_d = miss_state_q;
    miss_upgrade_d = miss_upgrade_q;
    miss_refill_sent_d = miss_refill_sent_q;
    miss_uncached_sent_d = miss_uncached_sent_q;

    unique case (miss_state_q)
      MissStateIdle: begin
        if (miss_req_valid) begin
          miss_state_d = MissStateFill;
          miss_upgrade_d = miss_req_upgrade;
          miss_refill_sent_d = 1'b0;
        end
      end
      MissStateFill: begin
        mem_a_valid_mult[AIdxRefill] = !miss_refill_sent_q;
        mem_a_mult[AIdxRefill].opcode = AcquireBlock;
        mem_a_mult[AIdxRefill].param = miss_req_op != MEM_LOAD ? (miss_upgrade_q ? tl_pkg::BtoT : tl_pkg::NtoT) : tl_pkg::NtoB;
        mem_a_mult[AIdxRefill].size = LineWidth;
        mem_a_mult[AIdxRefill].address = {miss_req_address[PhysAddrLen-1:6], {LineWidth{1'b0}}};
        mem_a_mult[AIdxRefill].source = SourceBase;
        mem_a_mult[AIdxRefill].mask = '1;
        mem_a_mult[AIdxRefill].corrupt = 1'b0;
        if (mem_a_ready_mult[AIdxRefill]) miss_refill_sent_d = 1'b1;

        if (refill_fifo_valid) begin
          if (refill_fifo_ready) begin
            if (refill_fifo_last) begin
              miss_state_d = MissStateIdle;
              if (refill_fifo_beat.denied) begin
                // In case of denied, this can be:
                // * An actual access error
                // * The target just denies AcquireBlock
                // So if the op is MEM_LOAD or MEM_STORE, we try uncached access, otherwise it is an access error.
                case (miss_req_op)
                  MEM_LOAD, MEM_STORE: begin
                    miss_uncached_sent_d = 1'b0;
                    miss_state_d = MissStateUncached;
                  end
                  default: begin
                    miss_resp_exception = 1'b1;
                  end
                endcase
              end else begin
                miss_resp_replay = 1'b1;
              end
            end
          end
        end
      end
      MissStateUncached: begin
        mem_a_valid_mult[AIdxRefill] = !miss_uncached_sent_q;
        mem_a_mult[AIdxRefill].opcode = miss_req_op[0] ? Get : PutFullData;
        mem_a_mult[AIdxRefill].param = 0;
        mem_a_mult[AIdxRefill].size = miss_req_size;
        mem_a_mult[AIdxRefill].address = miss_req_address;
        mem_a_mult[AIdxRefill].source = SourceBase;
        mem_a_mult[AIdxRefill].mask = tl_align_strb(miss_req_mask, miss_req_address[NonBurstSize-1:0]);
        mem_a_mult[AIdxRefill].data = tl_align_store(miss_req_data);
        if (mem_a_ready_mult[AIdxRefill]) miss_uncached_sent_d = 1'b1;

        if (mem_d_valid_access) begin
          miss_state_d = MissStateIdle;
          if (mem_d.denied) begin
            miss_resp_exception = 1'b1;
          end else begin
            miss_resp_valid = 1'b1;
            miss_resp_data = tl_align_load(mem_d.data, miss_req_address[NonBurstSize-1:0]);
          end
        end
      end
      default:;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      miss_state_q <= MissStateIdle;
      miss_upgrade_q <= 1'b0;
      miss_refill_sent_q <= 1'b0;
      miss_uncached_sent_q <= 1'b0;
    end else begin
      miss_state_q <= miss_state_d;
      miss_upgrade_q <= miss_upgrade_d;
      miss_refill_sent_q <= miss_refill_sent_d;
      miss_uncached_sent_q <= miss_uncached_sent_d;
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
    StateException
  } state_e;

  state_e state_q = StateIdle, state_d;

  // Information about the exception to be reported in StateException
  exc_cause_e ex_code_q, ex_code_d;

  // Helper signal to detect if req_address is a canonical address
  wire canonical_virtual  = ~|req_address[63:VirtAddrLen-1] | &req_address[63:VirtAddrLen-1];
  wire canonical_physical = ~|req_address[63:PhysAddrLen];

  logic [63:0] address_q, address_d;
  logic [63:0] value_q, value_d;
  logic [7:0]  mask_q, mask_d;
  logic [1:0]  size_q, size_d;
  size_ext_e   size_ext_q, size_ext_d;
  mem_op_e     op_q, op_d;
  logic [6:0]  amo_q, amo_d;

  wire [63:0] amo_result = do_amo_op(hit_data, value_q, mask_q, amo_q);

  logic                    reserved_q, reserved_d;
  logic [LogicAddrLen-7:0] reservation_q, reservation_d;
  logic                    reservation_failed_q, reservation_failed_d;

  logic [WaysWidth-1:0] way_q, way_d;

  wire [PhysAddrLen-1:0] address_phys = req_atp[63] ? {ppn, address_q[11:0]} : address_q[PhysAddrLen-1:0];

  logic [SetsWidth-1:0] access_lock_addr_d;
  logic [5:0] access_lock_timer_q, access_lock_timer_d;
  assign access_lock_valid = access_lock_timer_q != 0;

  assign access_lock_acq = access_tag_write_req;

  always_comb begin
    cache_d2h_o.req_ready = 1'b0;
    resp_valid = 1'b0;
    resp_value = 'x;
    ex_valid = 1'b0;
    ex_exception = exception_t'('x);

    miss_req_valid = 1'b0;
    miss_req_upgrade = 1'bx;
    miss_req_address = 'x;
    miss_req_op = mem_op_e'('x);
    miss_req_size = 'x;
    miss_req_mask = 'x;
    miss_req_data = 'x;

    wb_rel_req_valid = 1'b0;
    wb_rel_req_way = 'x;
    wb_rel_req_address = 'x;
    wb_rel_req_dirty = 1'bx;
    wb_rel_req_param = 'x;

    refill_req_address = address_phys[PhysAddrLen-1:6];
    refill_req_way = way_q;

    access_tag_read_req = 1'b0;
    access_tag_read_addr = 'x;
    access_tag_read_physical = !req_atp[63];

    access_data_read_req = 1'b0;
    access_data_read_addr = 'x;

    access_tag_write_req = 1'b0;
    access_tag_write_addr = address_q[LineWidth+:SetsWidth];
    access_tag_write_way = hit_way;
    access_tag_write_data = hit_tag;
    access_tag_write_data.dirty = 1'b1;

    access_data_write_way = hit_way;
    access_data_write_addr = address_q[3+:SetsWidth+3];
    access_data_write_req = 1'b0;
    access_data_write_data = combine_word(hit_data, amo_result, mask_q);

    state_d = state_q;
    address_d = address_q;
    value_d = value_q;
    mask_d = mask_q;
    size_d = size_q;
    size_ext_d = size_ext_q;
    op_d = op_q;
    amo_d = amo_q;
    evict_way_d = evict_way_q;
    way_d = way_q;
    ex_code_d = ex_code_q;

    reserved_d = reserved_q;
    reservation_d = reservation_q;
    reservation_failed_d = reservation_failed_q;

    access_lock_addr_d = access_lock_addr;
    access_lock_timer_d = access_lock_timer_q;
    if (access_lock_timer_q != 0 && !probe_tracker_valid) begin
      access_lock_timer_d = access_lock_timer_q - 1;
    end

    ptw_req_vpn = address_q[VirtAddrLen-1:12];

    unique case (state_q)
      StateIdle: begin
        cache_d2h_o.req_ready = 1'b1;
      end

      StateFetch: begin
        // The fast path of the access logic:
        // * Has lowest priority on read; it does not check if a conflicting operation is in progress
        //   before reading the tag (and data) for a shorter critical path. So in this state we need
        //   to first check if there is a conflict, and if so we need to replay the access.
        // * Has highest priority on write or writeback. This ensures that the tag or data we just
        //   fetched is up-to-date, so that any operation performed in this cycle is atomic. Note
        //   that (at least currently) writeback cannot be triggered while there are no conflicting
        //   operation.
        //   This high priority is guaranteed by
        //   - asserting access_lock_acq whenever a tag write is performed.
        //   - when data write is performed, we know that refill logic is not active, and writeback
        //     logic is not yet active (the only other concurrent trigger is writeback triggered by
        //     probe, but that won't happen in the first cycle of probe).
        if (!nothing_in_progress) begin
          // If lock is held by someone, it indicates that we races with another logic, replay.
          state_d = StateReplay;
        end else if (req_atp[63] && !ppn_valid) begin
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
        end else if (|hit && (hit_tag.writable || op_q == MEM_LOAD)) begin
          if (reservation_failed_q) begin
            cache_d2h_o.req_ready = 1'b1;
            resp_valid = 1'b1;
            resp_value = 1;
            state_d = StateIdle;
          end else begin

            cache_d2h_o.req_ready = 1'b1;
            resp_valid = 1'b1;
            resp_value = op_q[0] ? align_load(
                .value (hit_data),
                .addr (address_q[2:0]),
                .size (size_q),
                .size_ext (size_ext_q)
            ) : 0;
            state_d = StateIdle;

            // MEM_STORE/MEM_SC/MEM_AMO
            if (op_q[1]) begin
              // Write data and make tag dirty.
              access_data_write_req = 1'b1;
              access_tag_write_req = !hit_tag.dirty;
            end
          end

          if (op_q[1]) begin
            // Early release of timer once we've done a write; forward progress could be
            // guaranteed and we won't starve other core.
            // There is no need to care if it's successful write or not.
            access_lock_timer_d = 0;
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

          state_d = StateFill;
          miss_req_valid = 1'b1;
          miss_req_upgrade = |hit;

          if (hit_tag.valid &&
              hit_tag.writable) begin

            wb_rel_req_valid = 1'b1;
            wb_rel_req_way = way_d;
            wb_rel_req_address = {hit_tag.tag, address_q[6+:SetsWidth]};
            wb_rel_req_dirty = hit_tag.dirty;
            wb_rel_req_param = TtoN;
          end

          // Make tag invalid
          access_tag_write_req = 1'b1;
          access_tag_write_data.valid = 1'b0;

          // Early release of timer if we missed.
          access_lock_timer_d = 0;
        end
      end

      StateReplay: begin
        if (nothing_in_progress) begin
          access_tag_read_req = 1'b1;
          access_data_read_req = 1'b1;
          access_tag_read_addr = address_d[LogicAddrLen-1:LineWidth];
          access_data_read_addr = address_d[LogicAddrLen-1:3];

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
        miss_req_op = op_q;
        miss_req_size = size_q;
        miss_req_mask = mask_q;
        miss_req_data = value_q;

        if (miss_resp_replay) begin
          // Timer starts ticking for 16 cycles which gives us exclusive access to the cache line
          // that we just acquired. This ensures forward progress.
          // IMPORTANT: For this to work the timer must start in the same cycle that the refiller
          // logic goes from "in progress" state to "idle".
          access_lock_addr_d = address_q[LineWidth+:6];
          access_lock_timer_d = 16;
          state_d = StateReplay;
        end else if (miss_resp_valid) begin
          resp_valid = 1'b1;
          resp_value = align_load(
              .value (miss_resp_data),
              .addr (address_q[2:0]),
              .size (size_q),
              .size_ext (size_ext_q)
          );
          state_d = StateIdle;
        end else if (miss_resp_exception) begin
          ex_code_d = op_q == MEM_LOAD ? EXC_CAUSE_LOAD_ACCESS_FAULT : EXC_CAUSE_STORE_ACCESS_FAULT;
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
      value_d = align_store(req_value, req_address[2:0]);
      mask_d = align_strb(req_address[2:0], req_size);

      // Load reservation. The reservation is single-use; it is cleared by any other memory access.
      reserved_d = req_op == MEM_LR;
      reservation_d = req_address[LogicAddrLen-1:6];
      reservation_failed_d = req_op == MEM_SC && (req_address[LogicAddrLen-1:6] != reservation_q || !reserved_q);

      // Access the cache
      access_tag_read_req = 1'b1;
      access_tag_read_addr = address_d[LogicAddrLen-1:LineWidth];
      access_data_read_req = 1'b1;
      access_data_read_addr = address_d[LogicAddrLen-1:3];

      if (access_tag_read_gnt && ((req_op == MEM_STORE && req_size == 3) || access_data_read_gnt)) begin
        state_d = StateFetch;
      end else begin
        // If we failed to perform both tag and data read this cycle, move into replay state.
        state_d = StateReplay;
      end

      // Misaligned memory load/store will trigger an exception.
      if (!is_aligned(req_address[2:0], req_size)) begin
        state_d = StateException;
        ex_code_d = req_op == MEM_LOAD ? EXC_CAUSE_LOAD_MISALIGN : EXC_CAUSE_STORE_MISALIGN;
      end

      if (req_atp[63] && !canonical_virtual) begin
        state_d = StateException;
        ex_code_d = req_op == MEM_LOAD ? EXC_CAUSE_LOAD_PAGE_FAULT : EXC_CAUSE_STORE_PAGE_FAULT;
      end

      if (!req_atp[63] && !canonical_physical) begin
        state_d = StateException;
        ex_code_d = req_op == MEM_LOAD ? EXC_CAUSE_LOAD_ACCESS_FAULT : EXC_CAUSE_STORE_ACCESS_FAULT;
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= StateIdle;
      address_q <= '0;
      value_q <= 'x;
      mask_q <= 'x;
      size_q <= 'x;
      size_ext_q <= size_ext_e'('x);
      op_q <= mem_op_e'('x);
      amo_q <= 'x;
      evict_way_q <= 0;
      way_q <= 'x;
      ex_code_q <= exc_cause_e'('x);
      reserved_q <= 1'b0;
      reservation_q <= 'x;
      reservation_failed_q <= 1'bx;
      access_lock_addr <= 'x;
      access_lock_timer_q <= 0;
    end else begin
      state_q <= state_d;
      address_q <= address_d;
      value_q <= value_d;
      mask_q <= mask_d;
      size_q <= size_d;
      size_ext_q <= size_ext_d;
      op_q <= op_d;
      amo_q <= amo_d;
      evict_way_q <= evict_way_d;
      way_q <= way_d;
      ex_code_q <= ex_code_d;
      reserved_q <= reserved_d;
      reservation_q <= reservation_d;
      reservation_failed_q <= reservation_failed_d;
      access_lock_addr <= access_lock_addr_d;
      access_lock_timer_q <= access_lock_timer_d;
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
