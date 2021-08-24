`include "tl_util.svh"

// This module terminates a TL-C link and converts it to a TL-UH link.
// It will deny all requests that need write permission. It will allow Get requests through and
// convert readonly Acquire to Get.
module tl_rom_terminator import tl_pkg::*; import muntjac_pkg::*; #(
  parameter  int unsigned DataWidth   = 64,
  parameter  int unsigned AddrWidth   = 56,
  parameter  int unsigned HostSourceWidth = 1,
  parameter  int unsigned DeviceSourceWidth = 1,
  parameter  int unsigned SinkWidth   = 1,
  parameter  int unsigned MaxSize     = 6,

  parameter  bit [SinkWidth-1:0] SinkBase = 0,
  parameter  bit [SinkWidth-1:0] SinkMask = 0
) (
  input  logic clk_i,
  input  logic rst_ni,

  `TL_DECLARE_DEVICE_PORT(DataWidth, AddrWidth, HostSourceWidth, SinkWidth, host),
  `TL_DECLARE_HOST_PORT(DataWidth, AddrWidth, DeviceSourceWidth, SinkWidth, device)
);

  localparam SinkNums = SinkMask + 1;
  localparam SinkBits = prim_util_pkg::vbits(SinkNums);

  if (DeviceSourceWidth < HostSourceWidth + 1) begin
    $fatal(1, "Not enough SourceWidth");
  end

  `TL_DECLARE(DataWidth, AddrWidth, HostSourceWidth, SinkWidth, host);
  `TL_DECLARE(DataWidth, AddrWidth, DeviceSourceWidth, SinkWidth, device);
  `TL_BIND_DEVICE_PORT(host, host);
  `TL_BIND_HOST_PORT(device, device);

  typedef `TL_D_STRUCT(DataWidth, AddrWidth, HostSourceWidth, SinkWidth) host_d_t;

  /////////////////////////////////////////
  // #region Burst tracker instantiation //

  wire host_d_first;
  wire host_d_last;

  tl_burst_tracker #(
    .AddrWidth (AddrWidth),
    .DataWidth (DataWidth),
    .SourceWidth (HostSourceWidth),
    .SinkWidth (SinkWidth),
    .MaxSize (MaxSize)
  ) host_burst_tracker (
    .clk_i,
    .rst_ni,
    `TL_FORWARD_TAP_PORT_FROM_DEVICE(link, host),
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
    .req_last_o (),
    .rel_last_o (),
    .gnt_last_o (host_d_last)
  );

  // #endregion
  /////////////////////////////////////////

  /////////////////////////////
  // #region Unused channels //

  assign host_b_valid = 1'b0;
  assign host_b       = 'x;

  assign device_b_ready = 1'b1;

  assign device_c_valid = 1'b0;
  assign device_c       = 'x;

  assign device_e_valid = 1'b0;
  assign device_e       = 'x;

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

  ////////////////////////////////////////
  // #region Host D Channel arbitration //

  localparam HostDNums = 3;
  localparam HostDIdxGnt = 0;
  localparam HostDIdxAcq = 1;
  localparam HostDIdxRel = 2;

  // Grouped signals before multiplexing/arbitration
  host_d_t [HostDNums-1:0] host_d_mult;
  logic    [HostDNums-1:0] host_d_valid_mult;
  logic    [HostDNums-1:0] host_d_ready_mult;

  // Signals for arbitration
  logic [HostDNums-1:0] host_d_arb_grant;
  logic                 host_d_locked;
  logic [HostDNums-1:0] host_d_selected;

  openip_round_robin_arbiter #(.WIDTH(HostDNums)) host_d_arb (
    .clk     (clk_i),
    .rstn    (rst_ni),
    .enable  (host_d_valid && host_d_ready && !host_d_locked),
    .request (host_d_valid_mult),
    .grant   (host_d_arb_grant)
  );

  // Perform arbitration, and make sure that until we encounter host_d_last we keep the connection stable.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      host_d_locked <= 1'b0;
      host_d_selected <= '0;
    end
    else begin
      if (host_d_valid && host_d_ready) begin
        if (!host_d_locked) begin
          host_d_locked   <= 1'b1;
          host_d_selected <= host_d_arb_grant;
        end
        if (host_d_last) begin
          host_d_locked <= 1'b0;
        end
      end
    end
  end

  wire [HostDNums-1:0] host_d_select = host_d_locked ? host_d_selected : host_d_arb_grant;

  for (genvar i = 0; i < HostDNums; i++) begin
    assign host_d_ready_mult[i] = host_d_select[i] && host_d_ready_nosink;
  end

  // Do the post-arbitration multiplexing
  always_comb begin
    host_d_nosink = 'x;
    host_d_valid_nosink = 1'b0;
    for (int i = HostDNums - 1; i >= 0; i--) begin
      if (host_d_select[i]) begin
        host_d_nosink = host_d_mult[i];
        host_d_valid_nosink = host_d_valid_mult[i];
      end
    end
  end

  // #endregion
  ////////////////////////////////////////

  logic host_a_allowed;
  always_comb begin
    case (host_a.opcode)
      AcquireBlock, AcquirePerm: begin
        host_a_allowed = host_a.param == NtoB;
      end
      Get: begin
        host_a_allowed = 1'b1;
      end
      default: begin
        host_a_allowed = 1'b0;
      end
    endcase
  end

  always_comb begin
    host_a_ready = 1'b1;
    device_a_valid = 1'b0;
    device_a = 'x;
    host_d_valid_mult[HostDIdxAcq] = 1'b0;
    host_d_mult[HostDIdxAcq] = 'x;

    if (host_a_valid) begin
      if (!host_a_allowed) begin
        // For a write request, we deny with a Grant immediately.
        host_a_ready = host_d_ready_mult[HostDIdxAcq];
        host_d_valid_mult[HostDIdxAcq] = 1'b1;
        host_d_mult[HostDIdxAcq].opcode = host_a.opcode inside {AcquireBlock, AcquirePerm} ? Grant : AccessAck;
        host_d_mult[HostDIdxAcq].param = host_a.opcode inside {AcquireBlock, AcquirePerm} ? toN : 0;
        host_d_mult[HostDIdxAcq].size = host_a.size;
        host_d_mult[HostDIdxAcq].source = host_a.source;
        host_d_mult[HostDIdxAcq].denied = 1'b1;
        host_d_mult[HostDIdxAcq].corrupt = 1'b0;
        host_d_mult[HostDIdxAcq].data = 'x;
      end else begin
        // For all other requests forward to device.
        // For AcquireBlock transform it to Get, while GrantData will be transformed from AccessAckData.
        host_a_ready = device_a_ready;
        device_a_valid = 1'b1;
        device_a.opcode = host_a.opcode inside {AcquireBlock, AcquirePerm} ? Get : host_a.opcode;
        device_a.param = 0;
        device_a.size = host_a.size;
        device_a.source = {host_a.opcode inside {AcquireBlock, AcquirePerm} ? 1'b1 : 1'b0, host_a.source};
        device_a.address = host_a.address;
        device_a.mask = host_a.mask;
        device_a.corrupt = host_a.corrupt;
        device_a.data = host_a.data;
      end
    end
  end

  always_comb begin
    host_c_ready = 1'b1;
    host_d_valid_mult[HostDIdxRel] = 1'b0;
    host_d_mult[HostDIdxRel] = 'x;

    if (host_c_valid) begin
      // The only C channel message we expect to receive is Release, just reply with a ReleaseAck.
      host_c_ready = host_d_ready_mult[HostDIdxRel];
      host_d_valid_mult[HostDIdxRel] = 1'b1;
      host_d_mult[HostDIdxRel].opcode = ReleaseAck;
      host_d_mult[HostDIdxRel].param = 0;
      host_d_mult[HostDIdxRel].size = host_c.size;
      host_d_mult[HostDIdxRel].source = host_c.source;
      host_d_mult[HostDIdxRel].denied = 1'b0;
      host_d_mult[HostDIdxRel].corrupt = 1'b0;
      host_d_mult[HostDIdxRel].data = 'x;
    end
  end

  always_comb begin
    device_d_ready = 1'b0;
    host_d_valid_mult[HostDIdxGnt] = 1'b0;
    host_d_mult[HostDIdxGnt] = 'x;

    if (device_d_valid) begin
      device_d_ready = host_d_ready_mult[HostDIdxGnt];
      host_d_valid_mult[HostDIdxGnt] = 1'b1;
      unique case (device_d.source[HostSourceWidth+:1])
        1'b0: begin
          host_d_mult[HostDIdxGnt].opcode = device_d.opcode;
          host_d_mult[HostDIdxGnt].param = 0;
        end
        1'b1: begin
          host_d_mult[HostDIdxGnt].opcode = GrantData;
          host_d_mult[HostDIdxGnt].param = toB;
        end
        default:;
      endcase
      host_d_mult[HostDIdxGnt].size = device_d.size;
      host_d_mult[HostDIdxGnt].source = device_d.source[HostSourceWidth-1:0];
      host_d_mult[HostDIdxGnt].denied = device_d.denied;
      host_d_mult[HostDIdxGnt].corrupt = device_d.corrupt;
      host_d_mult[HostDIdxGnt].data = device_d.data;
    end
  end

endmodule
