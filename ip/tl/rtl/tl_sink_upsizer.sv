`include "tl_util.svh"

// An adpater that expands SinkWidth.
module tl_sink_upsizer import tl_pkg::*; #(
  parameter  int unsigned DataWidth   = 64,
  parameter  int unsigned AddrWidth   = 56,
  parameter  int unsigned SourceWidth = 1,
  parameter  int unsigned HostSinkWidth   = 1,
  parameter  int unsigned DeviceSinkWidth = 2,
  parameter  int unsigned MaxSize     = 6
) (
  input  logic       clk_i,
  input  logic       rst_ni,

  `TL_DECLARE_DEVICE_PORT(DataWidth, AddrWidth, SourceWidth, HostSinkWidth, host),
  `TL_DECLARE_HOST_PORT(DataWidth, AddrWidth, SourceWidth, DeviceSinkWidth, device)
);

  if (HostSinkWidth >= DeviceSinkWidth) $fatal(1, "Unexpected SinkWidth");

  localparam NumTrackers = 2 ** HostSinkWidth;
  localparam int unsigned ExtraSinkBits = DeviceSinkWidth - HostSinkWidth;

  `TL_DECLARE(DataWidth, AddrWidth, SourceWidth, HostSinkWidth, host);
  `TL_DECLARE(DataWidth, AddrWidth, SourceWidth, DeviceSinkWidth, device);
  `TL_BIND_HOST_PORT(device, device);

  tl_regslice #(
    .DataWidth (DataWidth),
    .AddrWidth (AddrWidth),
    .SourceWidth (SourceWidth),
    .SinkWidth (HostSinkWidth),
    .AckMode (1)
  ) host_reg (
    .clk_i,
    .rst_ni,
    `TL_FORWARD_DEVICE_PORT(host, host),
    `TL_CONNECT_HOST_PORT(device, host)
  );

  /////////////////////////////////
  // Burst tracker instantiation //
  /////////////////////////////////

  logic device_d_first;

  tl_burst_tracker #(
    .DataWidth (DataWidth),
    .AddrWidth (AddrWidth),
    .SourceWidth (SourceWidth),
    .SinkWidth (DeviceSinkWidth),
    .MaxSize (MaxSize)
  ) device_burst_tracker (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_TAP_PORT(link, device),
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
    .gnt_first_o (device_d_first),
    .req_last_o (),
    .rel_last_o (),
    .gnt_last_o ()
  );

  //////////////////////////
  // A channel connection //
  //////////////////////////

  assign host_a_ready   = device_a_ready;
  assign device_a_valid = host_a_valid;
  assign device_a       = host_a;

  //////////////////////////
  // B channel connection //
  //////////////////////////

  assign device_b_ready = host_b_ready;
  assign host_b_valid   = device_b_valid;
  assign host_b         = device_b;

  //////////////////////////
  // C channel connection //
  //////////////////////////

  assign host_c_ready   = device_c_ready;
  assign device_c_valid = host_c_valid;
  assign device_c       = host_c;

  //////////////////////////
  // D channel conversion //
  //////////////////////////

  wire device_d_alloc_sink = device_d_valid && device_d_first && device_d.opcode inside {Grant, GrantData};

  logic [NumTrackers-1:0]                    d_tracker_valid_q, d_tracker_valid_d;
  logic [NumTrackers-1:0][ExtraSinkBits-1:0] d_tracker_sink_q, d_tracker_sink_d;

  always_comb begin
    d_tracker_valid_d = d_tracker_valid_q;
    d_tracker_sink_d = d_tracker_sink_q;

    if (host_e_valid && host_e_ready) begin
      d_tracker_valid_d[host_e.sink] = 1'b0;
      d_tracker_sink_d[host_e.sink] = 'x;
    end

    if (device_d_alloc_sink && device_d_ready) begin
      d_tracker_valid_d[device_d.sink[HostSinkWidth-1:0]] = 1'b1;
      d_tracker_sink_d[device_d.sink[HostSinkWidth-1:0]] = device_d.sink[DeviceSinkWidth-1:HostSinkWidth];
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      d_tracker_valid_q <= '0;
    end else begin
      d_tracker_valid_q <= d_tracker_valid_d;
    end
  end

  always_ff @(posedge clk_i) begin
    d_tracker_sink_q <= d_tracker_sink_d;
  end

  assign device_d_ready = host_d_ready && (device_d_alloc_sink ? !d_tracker_valid_q[device_d.sink[HostSinkWidth-1:0]] : 1'b1);
  assign host_d_valid   = device_d_valid && (device_d_alloc_sink ? !d_tracker_valid_q[device_d.sink[HostSinkWidth-1:0]] : 1'b1);
  assign host_d.opcode  = device_d.opcode;
  assign host_d.param   = device_d.param;
  assign host_d.size    = device_d.size;
  assign host_d.source  = device_d.source;
  assign host_d.sink    = device_d.sink[HostSinkWidth-1:0];
  assign host_d.denied  = device_d.denied;
  assign host_d.corrupt = device_d.corrupt;
  assign host_d.data    = device_d.data;

  //////////////////////////
  // E channel conversion //
  //////////////////////////

  assign host_e_ready   = device_e_ready;
  assign device_e_valid = host_e_valid;
  assign device_e.sink  = {d_tracker_sink_q[host_e.sink], host_e.sink};

endmodule
