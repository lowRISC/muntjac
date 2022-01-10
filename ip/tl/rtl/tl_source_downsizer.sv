`include "tl_util.svh"

// An adpater that shrinks SourceWidth.
module tl_source_downsizer import tl_pkg::*; #(
  parameter  int unsigned DataWidth   = 64,
  parameter  int unsigned AddrWidth   = 56,
  parameter  int unsigned HostSourceWidth   = 2,
  parameter  int unsigned DeviceSourceWidth = 1,
  parameter  int unsigned SinkWidth   = 1,
  parameter  int unsigned MaxSize     = 6
) (
  input  logic       clk_i,
  input  logic       rst_ni,

  `TL_DECLARE_DEVICE_PORT(DataWidth, AddrWidth, HostSourceWidth, SinkWidth, host),
  `TL_DECLARE_HOST_PORT(DataWidth, AddrWidth, DeviceSourceWidth, SinkWidth, device)
);

  if (HostSourceWidth <= DeviceSourceWidth) $fatal(1, "Unexpected SourceWidth");

  localparam NumTrackers = 2 ** DeviceSourceWidth;
  localparam int unsigned ExtraSourceBits = HostSourceWidth - DeviceSourceWidth;

  `TL_DECLARE(DataWidth, AddrWidth, HostSourceWidth, SinkWidth, host);
  `TL_DECLARE(DataWidth, AddrWidth, DeviceSourceWidth, SinkWidth, device);
  `TL_BIND_DEVICE_PORT(host, host);

  tl_regslice #(
    .DataWidth (DataWidth),
    .AddrWidth (AddrWidth),
    .SourceWidth (DeviceSourceWidth),
    .SinkWidth (SinkWidth),
    .GrantMode (1)
  ) device_reg (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_DEVICE_PORT(host, device),
    `TL_FORWARD_HOST_PORT(device, device)
  );

  /////////////////////////////////
  // Burst tracker instantiation //
  /////////////////////////////////

  logic host_a_first;
  logic host_c_first;
  logic host_d_last;

  tl_burst_tracker #(
    .DataWidth (DataWidth),
    .AddrWidth (AddrWidth),
    .SourceWidth (HostSourceWidth),
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
    .req_first_o (host_a_first),
    .rel_first_o (host_c_first),
    .gnt_first_o (),
    .req_last_o (),
    .rel_last_o (),
    .gnt_last_o (host_d_last)
  );

  //////////////////////////
  // A channel conversion //
  //////////////////////////

  logic [NumTrackers-1:0]                      a_tracker_valid_q, a_tracker_valid_d;
  logic [NumTrackers-1:0][ExtraSourceBits-1:0] a_tracker_source_q, a_tracker_source_d;

  always_comb begin
    a_tracker_valid_d = a_tracker_valid_q;
    a_tracker_source_d = a_tracker_source_q;

    // Remove from tracker when a response is completed.
    if (device_d_valid && device_d_ready && host_d_last && device_d.opcode != ReleaseAck) begin
      a_tracker_valid_d[device_d.source] = 1'b0;
      a_tracker_source_d[device_d.source] = 'x;
    end

    // Add to tracker when a request begins.
    if (host_a_valid && host_a_ready && host_a_first) begin
      a_tracker_valid_d[host_a.source[DeviceSourceWidth-1:0]] = 1'b1;
      a_tracker_source_d[host_a.source[DeviceSourceWidth-1:0]] = host_a.source[HostSourceWidth-1:DeviceSourceWidth];
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      a_tracker_valid_q <= '0;
    end else begin
      a_tracker_valid_q <= a_tracker_valid_d;
    end
  end

  always_ff @(posedge clk_i) begin
    a_tracker_source_q <= a_tracker_source_d;
  end

  // Only allow a new transfer through if we can add it to the tracker.
  assign host_a_ready     = (host_a_valid && host_a_first ? !a_tracker_valid_q[host_a.source[DeviceSourceWidth-1:0]] : 1'b1) && device_a_ready;
  assign device_a_valid   = host_a_valid && (host_a_first ? !a_tracker_valid_q[host_a.source[DeviceSourceWidth-1:0]] : 1'b1);
  assign device_a.opcode  = host_a.opcode;
  assign device_a.param   = host_a.param;
  assign device_a.size    = host_a.size;
  assign device_a.source  = host_a.source[DeviceSourceWidth-1:0];
  assign device_a.address = host_a.address;
  assign device_a.mask    = host_a.mask;
  assign device_a.corrupt = host_a.corrupt;
  assign device_a.data    = host_a.data;

  //////////////////////////
  // B channel conversion //
  //////////////////////////

  assign device_b_ready = host_b_ready;
  assign host_b_valid   = device_b_valid;
  assign host_b.opcode  = device_b.opcode;
  assign host_b.param   = device_b.param;
  assign host_b.size    = device_b.size;
  assign host_b.source  = device_b.source;
  assign host_b.address = device_b.address;

  //////////////////////////
  // C channel conversion //
  //////////////////////////

  // Similar to A channel.
  logic [NumTrackers-1:0]                      c_tracker_valid_q, c_tracker_valid_d;
  logic [NumTrackers-1:0][ExtraSourceBits-1:0] c_tracker_source_q, c_tracker_source_d;

  always_comb begin
    c_tracker_valid_d = c_tracker_valid_q;
    c_tracker_source_d = c_tracker_source_q;

    if (device_d_valid && device_d_ready && device_d.opcode == ReleaseAck) begin
      c_tracker_valid_d[device_d.source] = 1'b0;
      c_tracker_source_d[device_d.source] = 'x;
    end

    if (host_c_valid && host_c_ready && host_c_first && host_c.opcode inside {Release, ReleaseData}) begin
      c_tracker_valid_d[host_c.source[DeviceSourceWidth-1:0]] = 1'b1;
      c_tracker_source_d[host_c.source[DeviceSourceWidth-1:0]] = host_c.source[HostSourceWidth-1:DeviceSourceWidth];
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      c_tracker_valid_q <= '0;
    end else begin
      c_tracker_valid_q <= c_tracker_valid_d;
    end
  end

  always_ff @(posedge clk_i) begin
    c_tracker_source_q <= c_tracker_source_d;
  end

  assign host_c_ready     = (host_c_valid && host_c_first ? !c_tracker_valid_q[host_c.source[DeviceSourceWidth-1:0]] : 1'b1) && device_c_ready;
  assign device_c_valid   = host_c_valid && (host_c_first ? !c_tracker_valid_q[host_c.source[DeviceSourceWidth-1:0]] : 1'b1);
  assign device_c.opcode  = host_c.opcode;
  assign device_c.param   = host_c.param;
  assign device_c.size    = host_c.size;
  assign device_c.source  = host_c.source[DeviceSourceWidth-1:0];
  assign device_c.address = host_c.address;
  assign device_c.corrupt = host_c.corrupt;
  assign device_c.data    = host_c.data;

  //////////////////////////
  // D channel conversion //
  //////////////////////////

  assign device_d_ready = host_d_ready;
  assign host_d_valid   = device_d_valid;
  assign host_d.opcode  = device_d.opcode;
  assign host_d.param   = device_d.param;
  assign host_d.size    = device_d.size;
  // Translate to the original Source using a tracker. The logic here won't work for combinational reply, so
  // a register slice is needed.
  assign host_d.source  = {device_d.opcode != ReleaseAck ? a_tracker_source_q[device_d.source] : c_tracker_source_q[device_d.source], device_d.source};
  assign host_d.sink    = device_d.sink;
  assign host_d.denied  = device_d.denied;
  assign host_d.corrupt = device_d.corrupt;
  assign host_d.data    = device_d.data;

  //////////////////////////
  // E channel connection //
  //////////////////////////

  assign host_e_ready   = device_e_ready;
  assign device_e_valid = host_e_valid;
  assign device_e.sink  = host_e.sink;

endmodule
