`include "tl_util.svh"

module muntjac_dcache import muntjac_pkg::*; import tl_pkg::*; # (
    parameter int unsigned DataWidth   = 64,
    // Number of ways is `2 ** WaysWidth`.
    parameter int unsigned WaysWidth   = 2,
    // Number of sets is `2 ** SetsWidth`.
    parameter int unsigned SetsWidth   = 6,
    parameter int unsigned VirtAddrLen = 39,
    parameter int unsigned PhysAddrLen = 56,
    parameter int unsigned AddrWidth   = PhysAddrLen,
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
  `TL_DECLARE(64, PhysAddrLen, SourceWidth, SinkWidth, mem_ptw);
  `TL_BIND_HOST_PORT(mem, mem);
  `TL_BIND_HOST_PORT(mem_ptw, mem_ptw);

  /////////////////////////////////////////
  // #region Burst tracker instantiation //

  wire mem_a_last;

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
    .gnt_idx_o (),
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
    .gnt_last_o ()
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
  localparam AIdxRefill = 0;
  localparam AIdxUncached = 1;

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
    .Depth (2 ** (LineWidth - NonBurstSize) + 1)
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

  // #endregion
  //////////////////////////////////////

  //////////////////////////////
  // #region Lock arbitration //

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

  logic access_lock_acq_pending_q, access_lock_acq_pending_d;
  logic flush_lock_acq_pending_q, flush_lock_acq_pending_d;
  lock_holder_e lock_holder_q, lock_holder_d;

  wire refill_locking = lock_holder_d == LockHolderRefill;
  wire probe_locking  = lock_holder_d == LockHolderProbe;
  wire access_locking = lock_holder_d == LockHolderAccess;
  wire flush_locking  = lock_holder_d == LockHolderFlush;

  // Arbitrate on the new holder of the lock
  always_comb begin
    lock_holder_d = lock_holder_q;
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
        refill_lock_acq: begin
          lock_holder_d = LockHolderRefill;
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
      access_lock_acq_pending_q <= 1'b0;
      flush_lock_acq_pending_q <= 1'b0;
      lock_holder_q <= LockHolderFlush;
    end else begin
      access_lock_acq_pending_q <= access_lock_acq_pending_d;
      flush_lock_acq_pending_q <= flush_lock_acq_pending_d;
      lock_holder_q <= lock_holder_d;
    end
  end

  // #endregion
  //////////////////////////////

  ///////////////////////////////////
  // #region SRAM access multiplex //

  logic                      access_tag_read_req;
  logic [LogicAddrLen-6-1:0] access_tag_read_addr;
  logic                      access_tag_read_physical;

  logic                      access_data_read_req;
  logic [LogicAddrLen-3-1:0] access_data_read_addr;

  logic                   access_tag_write_req;
  logic [SetsWidth-1:0]   access_tag_write_addr;
  logic [WaysWidth-1:0]   access_tag_write_way;
  tag_t                   access_tag_write_data;

  logic                   access_data_write_req;
  logic [SetsWidth+3-1:0] access_data_write_addr;
  logic [WaysWidth-1:0]   access_data_write_way;
  logic [63:0]            access_data_write_data;

  logic                   wb_data_read_req;
  logic [SetsWidth+3-1:0] wb_data_read_addr;
  logic [WaysWidth-1:0]   wb_data_read_way;

  logic                           refill_tag_write_req;
  logic [SetsWidth-1:0]           refill_tag_write_addr;
  logic [WaysWidth-1:0]           refill_tag_write_way;
  tag_t                           refill_tag_write_data;

  logic                           refill_data_write_req;
  logic [SetsWidth+3-1:0]         refill_data_write_addr;
  logic [WaysWidth-1:0]           refill_data_write_way;
  logic [NumInterleave-1:0][63:0] refill_data_write_data;

  logic                      probe_tag_read_req;
  logic [LogicAddrLen-6-1:0] probe_tag_read_addr;

  logic                  probe_tag_write_req;
  logic [SetsWidth-1:0]  probe_tag_write_addr;
  logic [NumWays-1:0]    probe_tag_write_ways;
  tag_t                  probe_tag_write_data;

  logic                  flush_tag_read_req;
  logic [SetsWidth-1:0]  flush_tag_read_addr;

  logic                  flush_tag_write_req;
  logic [SetsWidth-1:0]  flush_tag_write_addr;
  logic [NumWays-1:0]    flush_tag_write_ways;
  tag_t                  flush_tag_write_data;

  logic                              tag_read_req;
  logic [LogicAddrLen-LineWidth-1:0] tag_read_addr;
  logic                              tag_read_physical;
  tag_t                              tag_read_data [NumWays];

  logic                      data_read_req;
  logic [LogicAddrLen-3-1:0] data_read_addr;
  logic [WaysWidth-1:0]      data_read_way;
  logic                      data_read_wide;
  logic [63:0]               data_read_data [NumWays];

  logic                 tag_write_req;
  logic [SetsWidth-1:0] tag_write_addr;
  logic [NumWays-1:0]   tag_write_ways;
  tag_t                 tag_write_data;

  logic                           data_write_req;
  logic [SetsWidth+3-1:0]         data_write_addr;
  logic [WaysWidth-1:0]           data_write_way;
  logic [NumInterleave-1:0][63:0] data_write_data;
  logic                           data_write_wide;

  always_comb begin
    tag_read_req = 1'b0;
    tag_read_addr = 'x;
    tag_read_physical = 1'b1;

    priority case (1'b1)
      probe_tag_read_req: begin
        tag_read_req = 1'b1;
        tag_read_addr = probe_tag_read_addr;
        tag_read_physical = 1'b1;
      end
      flush_tag_read_req: begin
        tag_read_req = 1'b1;
        tag_read_addr = flush_tag_read_addr;
        tag_read_physical = 1'b1;
      end
      access_tag_read_req: begin
        tag_read_req = 1'b1;
        tag_read_addr = access_tag_read_addr;
        tag_read_physical = access_tag_read_physical;
      end
      default:;
    endcase
  end

  always_comb begin
    data_read_req = 1'b0;
    data_read_addr = 'x;
    data_read_way = 'x;
    data_read_wide = 1'b0;

    priority case (1'b1)
      wb_data_read_req: begin
        data_read_req = 1'b1;
        data_read_addr = wb_data_read_addr;
        data_read_way = wb_data_read_way;
        data_read_wide = 1'b1;
      end
      access_data_read_req: begin
        data_read_req = 1'b1;
        data_read_addr = access_data_read_addr;
      end
      default:;
    endcase

    if (data_read_wide) begin
      data_read_addr = data_read_addr ^ (data_read_way & InterleaveMask);
    end
  end

  logic tag_read_physical_latch;
  logic [LogicAddrLen-6-1:0] tag_read_addr_latch;
  logic [LogicAddrLen-3-1:0] data_read_addr_latch;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      tag_read_physical_latch <= 1'b1;
      tag_read_addr_latch <= 'x;
      data_read_addr_latch <= 'x;
      data_way_latch <= 'x;
    end else begin
      if (tag_read_req) begin
        tag_read_physical_latch <= tag_read_physical;
        tag_read_addr_latch <= tag_read_addr;
      end
      if (data_read_req) begin
          data_read_addr_latch <= data_read_addr;
      end
    end
  end

  // Interleave the read data
  logic [63:0] data_read_data_interleave [NumWays];
  for (genvar i = 0; i < NumWays; i++) begin
    assign data_read_data[i] = data_read_data_interleave[i ^ (data_read_addr_latch & InterleaveMask)];
  end

  always_comb begin
    tag_write_addr = 'x;
    tag_write_req = 1'b0;
    tag_write_ways = '0;
    tag_write_data = tag_t'('x);

    // Unlike read, write can happen at the cycle of lock release. However the writer must ensure
    // that the new lock acquirer will not access the same address.
    priority case (1'b1)
      refill_tag_write_req: begin
        tag_write_req = 1'b1;
        tag_write_addr = refill_tag_write_addr;
        for (int i = 0; i < NumWays; i++) tag_write_ways[i] = refill_tag_write_way == i;
        tag_write_data = refill_tag_write_data;
      end
      probe_tag_write_req: begin
        tag_write_req = 1'b1;
        tag_write_addr = probe_tag_write_addr;
        tag_write_ways = probe_tag_write_ways;
        tag_write_data = probe_tag_write_data;
      end
      flush_tag_write_req: begin
        tag_write_req = 1'b1;
        tag_write_addr = flush_tag_write_addr;
        tag_write_ways = flush_tag_write_ways;
        tag_write_data = flush_tag_write_data;
      end
      access_tag_write_req: begin
        tag_write_req = 1'b1;
        tag_write_addr = access_tag_write_addr;
        for (int i = 0; i < NumWays; i++) tag_write_ways[i] = access_tag_write_way == i;
        tag_write_data = access_tag_write_data;
      end
      default:;
    endcase
  end

  always_comb begin
    data_write_req = 1'b0;
    data_write_addr = 'x;
    data_write_way = 'x;
    data_write_data = 'x;
    data_write_wide = 1'b0;

    // Unlike read, write can happen at the cycle of lock release. However the writer must ensure
    // that the new lock acquirer will not access the same address.
    priority case (1'b1)
      refill_data_write_req: begin
        data_write_req = 1'b1;
        data_write_addr = refill_data_write_addr;
        data_write_way = refill_data_write_way;
        data_write_data = refill_data_write_data;
        data_write_wide = 1'b1;
      end
      access_data_write_req: begin
        data_write_req = 1'b1;
        data_write_addr = access_data_write_addr;
        data_write_way = access_data_write_way;
        data_write_data = {NumInterleave{access_data_write_data}};
      end
      default:;
    endcase

    if (data_write_wide) begin
      data_write_addr = data_write_addr ^ (data_write_way & InterleaveMask);
    end
  end

  // Interleave the write ways and data
  logic [NumWays-1:0] data_write_ways_interleave;
  logic [NumInterleave-1:0][63:0] data_write_data_interleave;
  for (genvar i = 0; i < NumWays; i++) begin
    assign data_write_ways_interleave[i] =
      (data_write_way &~ InterleaveMask) == (i &~ InterleaveMask) &&
      (data_write_wide || (data_write_way & InterleaveMask) == ((i ^ data_write_addr) & InterleaveMask));
  end
  for (genvar i = 0; i < NumInterleave; i++) begin
    assign data_write_data_interleave[i] = data_write_data[i ^ (data_write_addr & InterleaveMask)];
  end

  // #endregion
  ///////////////////////////////////

  ////////////////////////////////
  // #region SRAM Instantiation //

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
      if (tag_read_req) begin
        tag_bypass <= tag_write_data;
      end
      if (data_read_req) begin
        data_bypass <= data_write_data_interleave;
      end
    end
  end

  for (genvar i = 0; i < NumWays; i++) begin: ram

    logic tag_bypass_valid;
    logic data_bypass_valid;

    tag_t        tag_raw;
    logic [63:0] data_raw;
    logic [63:0] data_bypassed;

    wire [SetsWidth+3-1:0] data_read_addr_effective = data_read_addr ^ (data_read_wide ? (i & InterleaveMask) : 0);
    wire [SetsWidth+3-1:0] data_write_addr_effective = data_write_addr ^ (data_write_wide ? (i & InterleaveMask) : 0);

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        tag_bypass_valid <= 1'b0;
        data_bypass_valid <= 0;
      end else begin
        if (tag_read_req) begin
          tag_bypass_valid <= 1'b0;
          if (tag_write_req && tag_write_ways[i] && tag_write_addr[SetsWidth-1:0] == tag_read_addr[SetsWidth-1:0]) begin
            tag_bypass_valid <= 1'b1;
          end
        end
        if (data_read_req) begin
          data_bypass_valid <= 0;
          if (data_write_req && data_write_ways_interleave[i] && data_write_addr_effective == data_read_addr_effective) begin
            data_bypass_valid <= 1'b1;
          end
        end
      end
    end

    assign tag_read_data[i] = tag_bypass_valid ? tag_bypass : tag_raw;
    assign data_read_data_interleave[i] = data_bypass_valid ? data_bypass[i & InterleaveMask] : data_raw;

    prim_generic_ram_simple_2p #(
        .Width           ($bits(tag_t)),
        .Depth           (2 ** SetsWidth),
        .DataBitsPerMask ($bits(tag_t))
    ) tag_ram (
        .clk_a_i   (clk_i),
        .clk_b_i   (clk_i),

        .a_req_i   (tag_read_req),
        .a_addr_i  (tag_read_addr[SetsWidth-1:0]),
        .a_rdata_o (tag_raw),

        .b_req_i   (tag_write_req && tag_write_ways[i]),
        .b_addr_i  (tag_write_addr[SetsWidth-1:0]),
        .b_wdata_i (tag_write_data),
        .b_wmask_i ('1)
    );

    prim_generic_ram_simple_2p #(
        .Width           (64),
        .Depth           (2 ** (SetsWidth + 3)),
        .DataBitsPerMask (8)
    ) data_ram (
        .clk_a_i   (clk_i),
        .clk_b_i   (clk_i),

        .a_req_i   (data_read_req),
        .a_addr_i  (data_read_addr_effective),
        .a_rdata_o (data_raw),

        .b_req_i   (data_write_req && data_write_ways_interleave[i]),
        .b_addr_i  (data_write_addr_effective),
        .b_wdata_i (data_write_data_interleave[i & InterleaveMask]),
        .b_wmask_i ('1)
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

  logic                   wb_progress_q, wb_progress_d;
  logic [WaysWidth-1:0]   wb_way_q, wb_way_d;
  logic [OffsetWidth-1:0] wb_index_q, wb_index_d;
  tl_c_op_e               wb_opcode_q, wb_opcode_d;
  logic [2:0]             wb_param_q, wb_param_d;
  logic [PhysAddrLen-7:0] wb_address_q, wb_address_d;

  always_comb begin
    wb_data_read_req = 1'b0;
    wb_data_read_addr = 'x;
    wb_data_read_way = 'x;

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
      mem_c.data[i * 64 +: 64] = data_read_data[(wb_way_q &~ InterleaveMask) | i];
    end

    if (wb_progress_q && mem_c_ready) begin
      wb_index_d = wb_index_q + 1;

      if (wb_index_q == 0) begin
        // Last cycle. Signal the invoker and clear progress bit.
        wb_progress_d = 1'b0;

        // Release SRAM access lock
        release_lock_rel = 1'b1;
      end else begin
        wb_data_read_req = 1'b1;
        wb_data_read_way = wb_way_d;
        wb_data_read_addr = {wb_address_d[SetsWidth-1:0], 3'(wb_index_q << InterleaveWidth)};
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
        wb_data_read_req = 1'b1;
        wb_data_read_way = wb_way_d;
        wb_data_read_addr = {wb_address_d[SetsWidth-1:0], 3'd0};
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

  // #endregion
  ////////////////////////////////////////

  //////////////////////////
  // #region Refill Logic //

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
    refill_tag_write_req = 1'b0;
    refill_tag_write_addr = 'x;
    refill_tag_write_way = 'x;
    refill_tag_write_data = tag_t'('x);

    refill_data_write_req = 1'b0;
    refill_data_write_addr = 'x;
    refill_data_write_way = 'x;
    refill_data_write_data = 'x;

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
          if (refill_locking) begin
            refill_state_d = RefillStateProgress;
          end
        end
      end
      RefillStateProgress: begin
        mem_grant_ready_refill = 1'b1;
        refill_tag_write_way = refill_req_way;
        refill_tag_write_addr = refill_req_address[SetsWidth-1:0];

        refill_data_write_way = refill_req_way;
        refill_data_write_addr = {refill_req_address[SetsWidth-1:0], 3'(refill_index_q << InterleaveWidth)};

        refill_data_write_req = mem_grant_valid_refill && mem_grant_opcode == GrantData && !mem_grant_denied;
        refill_data_write_data = mem_grant_data;

        // Update the metadata. This should only be done once, we can do it in either time.
        refill_tag_write_req = mem_grant_valid_refill && &refill_index_q && !mem_grant_denied;
        refill_tag_write_data.tag = refill_req_address[PhysAddrLen-7:SetsWidth];
        refill_tag_write_data.writable = mem_grant_param == tl_pkg::toT;
        refill_tag_write_data.dirty = 1'b0;
        refill_tag_write_data.valid = 1'b1;

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

  // #endregion
  //////////////////////////

  ///////////////////////////////////////
  // #region Address Translation Logic //

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

  // #endregion
  ///////////////////////////////////

  /////////////////////////
  // #region Probe Logic //

  logic evict_completed_q, evict_completed_d;

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

    // probe_lock and related signals are for forward progress guarantees.
    probe_lock_d = probe_lock_q;
    if (probe_lock_q != 0) probe_lock_d = probe_lock_q - 1;
    if (probe_lock) probe_lock_d = 16;

    unique case (probe_state_q)
      // Waiting for a probe request to reach us.
      ProbeStateIdle: begin
        probe_lock_acq = probe_lock_q == 0 && mem_b_valid && evict_completed_q;

        if (probe_locking) begin
          mem_b_ready = 1'b1;
          probe_address_d = mem_b.address[PhysAddrLen-1:6];
          probe_param_d = mem_b.param;

          // Does the tag read necessary for performing invalidation
          probe_tag_read_req = 1'b1;
          probe_tag_read_addr = probe_address_d;

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

  // #endregion
  /////////////////////////

  /////////////////////////
  // #region Flush Logic //

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
        flush_tag_write_ways = '1;
        flush_tag_write_addr = flush_index_q;
        flush_tag_write_req = 1'b1;
        flush_tag_write_data.valid = 1'b0;

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
          flush_tag_read_req = 1'b1;
          flush_tag_read_addr = flush_index_d;

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

          flush_tag_read_req = 1'b1;
          flush_tag_read_addr = flush_index_d;

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

  // #endregion
  /////////////////////////

  ///////////////////////////////////////////////////
  // #region Cache Miss Handling Logic (Slow Path) //

  logic                             acq_req_valid;
  logic [2:0]                       acq_req_param;
  logic [PhysAddrLen-LineWidth-1:0] acq_req_address;

  logic acq_resp_valid;
  logic acq_resp_exception;

  logic acq_pending_q, acq_pending_d;
  logic acq_req_sent_q, acq_req_sent_d;

  always_comb begin
    acq_resp_valid = 1'b0;
    acq_resp_exception = 1'b0;

    mem_a_valid_mult[AIdxRefill] = 1'b0;
    mem_a_mult[AIdxRefill] = 'x;

    acq_pending_d = acq_pending_q;
    acq_req_sent_d = acq_req_sent_q;

    if (acq_pending_q) begin
      mem_a_valid_mult[AIdxRefill] = !acq_req_sent_q;
      mem_a_mult[AIdxRefill].opcode = AcquireBlock;
      mem_a_mult[AIdxRefill].param = acq_req_param;
      mem_a_mult[AIdxRefill].size = 6;
      mem_a_mult[AIdxRefill].address = {acq_req_address, {LineWidth{1'b0}}};
      mem_a_mult[AIdxRefill].source = SourceBase;
      mem_a_mult[AIdxRefill].mask = '1;
      mem_a_mult[AIdxRefill].corrupt = 1'b0;

      if (mem_a_ready_mult[AIdxRefill]) begin
        acq_req_sent_d = 1'b1;
      end

      if (mem_grant_last) begin
        acq_pending_d = 1'b0;
        acq_resp_valid = 1'b1;
        if (mem_grant_denied) begin
          acq_resp_exception = 1'b1;
        end
      end
    end

    if (acq_req_valid) begin
      acq_pending_d = 1'b1;
      acq_req_sent_d = 1'b0;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      acq_pending_q <= 1'b0;
      acq_req_sent_q <= 1'b0;
    end else begin
      acq_pending_q <= acq_pending_d;
      acq_req_sent_q <= acq_req_sent_d;
    end
  end

  // #endregion
  ///////////////////////////////////////////////////

  //////////////////////////////////////////
  // #region Uncached Memory Access Logic //

  logic                   uncached_req_valid;
  logic                   uncached_req_write;
  logic [1:0]             uncached_req_size;
  logic [PhysAddrLen-1:0] uncached_req_address;
  logic [7:0]             uncached_req_mask;
  logic [63:0]            uncached_req_data;

  logic        uncached_resp_valid;
  logic        uncached_resp_exception;
  logic [63:0] uncached_resp_data;

  logic uncached_pending_q, uncached_pending_d;
  logic uncached_req_sent_q, uncached_req_sent_d;

  always_comb begin
    uncached_resp_valid = 1'b0;
    uncached_resp_exception = 1'b0;
    uncached_resp_data = 'x;

    mem_a_valid_mult[AIdxUncached] = 1'b0;
    mem_a_mult[AIdxUncached] = 'x;

    uncached_pending_d = uncached_pending_q;
    uncached_req_sent_d = uncached_req_sent_q;

    if (uncached_pending_q) begin
      mem_a_valid_mult[AIdxUncached] = !uncached_req_sent_q;
      mem_a_mult[AIdxUncached].opcode = uncached_req_write ? PutFullData : Get;
      mem_a_mult[AIdxUncached].param = 0;
      mem_a_mult[AIdxUncached].size = uncached_req_size;
      mem_a_mult[AIdxUncached].address = uncached_req_address;
      mem_a_mult[AIdxUncached].source = SourceBase;
      mem_a_mult[AIdxUncached].mask = tl_align_strb(uncached_req_mask, uncached_req_address[NonBurstSize-1:0]);
      mem_a_mult[AIdxUncached].data = tl_align_store(uncached_req_data);

      if (mem_a_ready_mult[AIdxUncached]) begin
        uncached_req_sent_d = 1'b1;
      end

      if (mem_grant_valid_access) begin
        uncached_pending_d = 1'b0;
        uncached_resp_valid = 1'b1;
        if (mem_grant_denied) begin
          uncached_resp_exception = 1'b1;
        end else begin
          uncached_resp_data = tl_align_load(mem_grant_data, uncached_req_address[NonBurstSize-1:0]);
        end
      end
    end

    if (uncached_req_valid) begin
      uncached_pending_d = 1'b1;
      uncached_req_sent_d = 1'b0;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      uncached_pending_q <= 1'b0;
      uncached_req_sent_q <= 1'b0;
    end else begin
      uncached_pending_q <= uncached_pending_d;
      uncached_req_sent_q <= uncached_req_sent_d;
    end
  end

  // #endregion
  //////////////////////////////////////////

  ////////////////////////
  // #region Main Logic //

  typedef enum logic [3:0] {
    StateIdle,
    StateFetch,
    StateReplay,
    StateWaitTLB,
    StateFill,
    StateReplayPre,
    StateUncachedPre,
    StateExceptionPre,
    StateUncached,
    StateExceptionLocked,
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

  wire [63:0] hit_data = data_read_data[hit_way];
  wire [63:0] amo_result = do_amo_op(hit_data, value_q, mask_q, amo_q);

  logic                    reserved_q, reserved_d;
  logic [LogicAddrLen-7:0] reservation_q, reservation_d;
  logic                    reservation_failed_q, reservation_failed_d;

  logic [WaysWidth-1:0] way_q, way_d;

  wire [PhysAddrLen-1:0] address_phys = req_atp[63] ? {ppn, address_q[11:0]} : address_q[PhysAddrLen-1:0];

  always_comb begin
    cache_d2h_o.req_ready = 1'b0;
    resp_valid = 1'b0;
    resp_value = 'x;
    ex_valid = 1'b0;
    ex_exception = exception_t'('x);

    acq_req_valid = 1'b0;
    acq_req_param = 'x;
    acq_req_address = 'x;

    uncached_req_valid = 1'b0;
    uncached_req_write = 'x;
    uncached_req_size = 'x;
    uncached_req_address = 'x;
    uncached_req_mask = 'x;
    uncached_req_data = 'x;

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

    access_lock_acq = 1'b0;
    access_lock_rel = 1'b0;

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
    evict_completed_d = evict_completed_q;

    reserved_d = reserved_q;
    reservation_d = reservation_q;
    reservation_failed_d = reservation_failed_q;

    if (mem_grant_valid_rel_ack) begin
      evict_completed_d = 1'b1;
    end

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
            access_tag_write_req = 1'b1;
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

          evict_completed_d = 1'b1;
          state_d = StateFill;
          acq_req_valid = 1'b1;

          if (hit_tag.valid &&
              hit_tag.writable) begin
            evict_completed_d = 1'b0;

            wb_rel_req_valid = 1'b1;
            wb_rel_req_way = way_d;
            wb_rel_req_address = {hit_tag.tag, address_q[6+:SetsWidth]};
            wb_rel_req_dirty = hit_tag.dirty;
            wb_rel_req_param = TtoN;
          end

          // Make tag invalid
          access_tag_write_req = 1'b1;
          access_tag_write_data.valid = 1'b0;
        end
      end

      StateReplay: begin
        access_tag_read_addr = address_d[LogicAddrLen-1:LineWidth];
        access_data_read_addr = address_d[LogicAddrLen-1:3];
        if (access_locking) begin
          access_tag_read_req = 1'b1;
          access_data_read_req = 1'b1;
          state_d = StateFetch;
        end
      end

      StateWaitTLB: begin
        if (ppn_valid) begin
          access_lock_acq = 1'b1;
          state_d = StateReplay;
        end
      end

      StateFill: begin
        acq_req_param = op_q != MEM_LOAD ? tl_pkg::NtoT : tl_pkg::NtoB;
        acq_req_address = address_phys[PhysAddrLen-1:6];

        if (acq_resp_valid) begin
          if (acq_resp_exception) begin
            // In case of denied, this can be:
            // * An actual access error
            // * The target just denies AcquireBlock
            // So if the op is MEM_LOAD or MEM_STORE, we try uncached access, otherwise it is an access error.
            case (op_q)
              MEM_LOAD, MEM_STORE: begin
                state_d = StateUncachedPre;
              end
              MEM_LR, MEM_SC, MEM_AMO: begin
                ex_code_d = EXC_CAUSE_STORE_ACCESS_FAULT;
                state_d = StateExceptionPre;
              end
            endcase
          end else begin
            // Re-acquire lock that refiller released.
            // FIXME: Maybe should let refiller give lock back to us like I$.
            state_d = StateReplayPre;
          end
        end
      end

      StateReplayPre: begin
        if (evict_completed_d) begin
          state_d = StateReplay;
          access_lock_acq = 1'b1;
        end
      end

      StateUncachedPre: begin
        if (evict_completed_d) begin
          state_d = StateUncached;
          uncached_req_valid = 1'b1;
        end
      end

      StateExceptionPre: begin
        if (evict_completed_d) begin
          state_d = StateException;
        end
      end

      StateUncached: begin
        uncached_req_write = !op_q[0];
        uncached_req_size = size_q;
        uncached_req_address = address_phys;
        uncached_req_mask = mask_q;
        uncached_req_data = value_q;

        if (uncached_resp_valid) begin
          if (uncached_resp_exception) begin
            state_d = StateException;
            ex_code_d = op_q == MEM_LOAD ? EXC_CAUSE_LOAD_ACCESS_FAULT : EXC_CAUSE_STORE_ACCESS_FAULT;
          end
          else begin
            cache_d2h_o.req_ready = 1'b1;
            resp_valid = 1'b1;
            resp_value = align_load(
                .value (uncached_resp_data),
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
      value_d = align_store(req_value, req_address[2:0]);
      mask_d = align_strb(req_address[2:0], req_size);

      // Access the cache
      access_lock_acq = 1'b1;
      access_tag_read_addr = address_d[LogicAddrLen-1:LineWidth];
      access_data_read_addr = address_d[LogicAddrLen-1:3];

      if (access_locking) begin
        access_tag_read_req = 1'b1;
        access_data_read_req = 1'b1;
      end

      // Load reservation. The reservation is single-use; it is cleared by any other memory access.
      reserved_d = req_op == MEM_LR;
      reservation_d = req_address[LogicAddrLen-1:6];
      reservation_failed_d = req_op == MEM_SC && (req_address[LogicAddrLen-1:6] != reservation_q || !reserved_q);

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
      mask_q <= 'x;
      size_q <= 'x;
      size_ext_q <= size_ext_e'('x);
      op_q <= mem_op_e'('x);
      amo_q <= 'x;
      evict_way_q <= 0;
      way_q <= 'x;
      evict_completed_q <= 1'b1;
      ex_code_q <= exc_cause_e'('x);
      reserved_q <= 1'b0;
      reservation_q <= 'x;
      reservation_failed_q <= 1'bx;
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
      evict_completed_q <= evict_completed_d;
      ex_code_q <= ex_code_d;
      reserved_q <= reserved_d;
      reservation_q <= reservation_d;
      reservation_failed_q <= reservation_failed_d;
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
