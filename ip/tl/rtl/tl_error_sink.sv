`include "tl_util.svh"

// This module denys all TileLink requests.
module tl_error_sink import tl_pkg::*; import muntjac_pkg::*; #(
  parameter  int unsigned DataWidth   = 64,
  parameter  int unsigned AddrWidth   = 56,
  parameter  int unsigned SourceWidth = 1,
  parameter  int unsigned SinkWidth = 1,
  parameter  int unsigned MaxSize     = 6,

  parameter  bit [SinkWidth-1:0] SinkBase = 0,
  parameter  bit [SinkWidth-1:0] SinkMask = 0
) (
  input  logic clk_i,
  input  logic rst_ni,

  `TL_DECLARE_DEVICE_PORT(DataWidth, AddrWidth, SourceWidth, SinkWidth, host)
);

  localparam SinkNums = SinkMask + 1;
  localparam SinkBits = prim_util_pkg::vbits(SinkNums);

  `TL_DECLARE(DataWidth, AddrWidth, SourceWidth, SinkWidth, host);
  `TL_BIND_DEVICE_PORT(host, host);

  typedef `TL_D_STRUCT(DataWidth, AddrWidth, SourceWidth, SinkWidth) host_d_t;

  /////////////////////////////////////////
  // #region Burst tracker instantiation //

  wire host_a_last;
  wire host_d_first;
  wire host_d_last;

  tl_burst_tracker #(
    .AddrWidth (AddrWidth),
    .DataWidth (DataWidth),
    .SourceWidth (SourceWidth),
    .SinkWidth (SinkWidth),
    .MaxSize (MaxSize)
  ) host_burst_tracker (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_TAP_PORT(link, host),
    .req_len_o (),
    .rel_len_o (),
    .gnt_len_o (),
    .req_idx_o (),
    .rel_idx_o (),
    .gnt_idx_o (),
    .req_left_o (),
    .rel_left_o (),
    .gnt_left_o (),
    .req_first_o (),
    .rel_first_o (),
    .gnt_first_o (host_d_first),
    .req_last_o (host_a_last),
    .rel_last_o (),
    .gnt_last_o (host_d_last)
  );

  // #endregion
  /////////////////////////////////////////

  /////////////////////////////
  // #region Unused channels //

  assign host_b_valid   = 1'b0;
  assign host_b         = 'x;

  // We should never receive any C channel message.
  assign host_c_ready   = 1'b1;

  // #endregion
  /////////////////////////////

  /////////////////////////////
  // #region Sink Management //

  // In this module we conceptually can handle infinite number of outstanding transactions, but
  // as TileLink requires Sink identifiers to not be reused until a GrantAck is received, this
  // logic keeps track of all available sink identifiers usable.
  //
  // All other logics in this module do not need to supply a plausible Sink. This logic will
  // intercept all host's D channel messages and inject a free Sink id if necessary.

  logic [SinkNums-1:0] sink_tracker_q, sink_tracker_d;
  logic [SinkBits-1:0] sink_q, sink_d;
  logic [SinkBits-1:0] sink_avail_idx;
  logic                sink_avail;

  host_d_t host_d_nosink;
  logic    host_d_valid_nosink;
  logic    host_d_ready_nosink;

  always_comb begin
    sink_avail = 1'b0;
    sink_avail_idx = 'x;

    for (int i = SinkNums - 1; i >=0 ; i--) begin
      if (sink_tracker_q[i]) begin
        sink_avail = 1'b1;
        sink_avail_idx = i;
      end
    end
  end

  assign host_e_ready = 1'b1;

  always_comb begin
    sink_tracker_d = sink_tracker_q;
    sink_d = sink_q;

    host_d_ready_nosink = host_d_ready;
    host_d_valid = host_d_valid_nosink;
    host_d = host_d_nosink;
    host_d.sink = SinkBase | sink_q;

    if (host_d_valid_nosink && host_d_first && host_d.opcode inside {Grant, GrantData}) begin
      host_d.sink = SinkBase | sink_avail_idx;
      if (sink_avail) begin
        // Allocate a new sink id.
        if (host_d_ready) begin
          sink_d = sink_avail_idx;
          sink_tracker_d[sink_avail_idx] = 1'b0;
        end
      end else begin
        // Block if no sink id is available.
        host_d_ready_nosink = 1'b0;
        host_d_valid = 1'b0;
      end
    end

    if (host_e_valid) begin
      // Free a sink id.
      sink_tracker_d[host_e.sink & SinkMask] = 1'b1;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      sink_tracker_q <= '1;
      sink_q <= 'x;
    end else begin
      sink_tracker_q <= sink_tracker_d;
      sink_q <= sink_d;
    end
  end

  // #endregion
  /////////////////////////////

  always_comb begin
    host_a_ready = 1'b1;
    host_d_valid_nosink = 1'b0;
    host_d_nosink = 'x;

    if (host_a_valid && host_a_last) begin
      host_a_ready = host_d_ready_nosink && host_d_last;
      host_d_valid_nosink = 1'b1;
      host_d_nosink.opcode = host_a.opcode inside {AcquireBlock, AcquirePerm} ? Grant : (host_a.opcode == Get ? AccessAckData : AccessAck);
      host_d_nosink.param = host_a.opcode inside {AcquireBlock, AcquirePerm} ? toN : 0;
      host_d_nosink.size = host_a.size;
      host_d_nosink.source = host_a.source;
      host_d_nosink.denied = 1'b1;
      host_d_nosink.corrupt = host_a.opcode == Get ? 1'b1 : 1'b0;
      host_d_nosink.data = 'x;
    end
  end

endmodule
