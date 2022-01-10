`include "tl_util.svh"

module tl_regslice import tl_pkg::*; #(
  parameter  int unsigned SourceWidth   = 1,
  parameter  int unsigned SinkWidth     = 1,
  parameter  int unsigned AddrWidth     = 56,
  parameter  int unsigned DataWidth     = 64,

  parameter  int unsigned RequestMode   = 0,
  parameter  int unsigned ProbeMode     = 0,
  parameter  int unsigned ReleaseMode   = 0,
  parameter  int unsigned GrantMode     = 0,
  parameter  int unsigned AckMode       = 0
) (
  input  logic clk_i,
  input  logic rst_ni,

  `TL_DECLARE_DEVICE_PORT(DataWidth, AddrWidth, SourceWidth, SinkWidth, host),
  `TL_DECLARE_HOST_PORT(DataWidth, AddrWidth, SourceWidth, SinkWidth, device)
);

  `TL_DECLARE(DataWidth, AddrWidth, SourceWidth, SinkWidth, host);
  `TL_DECLARE(DataWidth, AddrWidth, SourceWidth, SinkWidth, device);
  `TL_BIND_DEVICE_PORT(host, host);
  `TL_BIND_HOST_PORT(device, device);

  /////////////////////
  // Request channel //
  /////////////////////

  typedef `TL_A_STRUCT(DataWidth, AddrWidth, SourceWidth, SinkWidth) req_t;

  openip_regslice #(
    .TYPE (req_t),
    .FORWARD          ((RequestMode & 1) != 0),
    .REVERSE          ((RequestMode & 2) != 0),
    .HIGH_PERFORMANCE ((RequestMode & 4) != 0)
  ) req_fifo (
    .clk     (clk_i),
    .rstn    (rst_ni),
    .w_valid (host_a_valid),
    .w_ready (host_a_ready),
    .w_data  (host_a),
    .r_valid (device_a_valid),
    .r_ready (device_a_ready),
    .r_data  (device_a)
  );

  ///////////////////
  // Probe channel //
  ///////////////////

  typedef `TL_B_STRUCT(DataWidth, AddrWidth, SourceWidth, SinkWidth) prb_t;

  openip_regslice #(
    .TYPE (prb_t),
    .FORWARD          ((ProbeMode & 1) != 0),
    .REVERSE          ((ProbeMode & 2) != 0),
    .HIGH_PERFORMANCE ((ProbeMode & 4) != 0)
  ) prb_fifo (
    .clk     (clk_i),
    .rstn    (rst_ni),
    .w_valid (device_b_valid),
    .w_ready (device_b_ready),
    .w_data  (device_b),
    .r_valid (host_b_valid),
    .r_ready (host_b_ready),
    .r_data  (host_b)
  );

  /////////////////////
  // Release channel //
  /////////////////////

  typedef `TL_C_STRUCT(DataWidth, AddrWidth, SourceWidth, SinkWidth) rel_t;

  openip_regslice #(
    .TYPE (rel_t),
    .FORWARD          ((ReleaseMode & 1) != 0),
    .REVERSE          ((ReleaseMode & 2) != 0),
    .HIGH_PERFORMANCE ((ReleaseMode & 4) != 0)
  ) rel_fifo (
    .clk     (clk_i),
    .rstn    (rst_ni),
    .w_valid (host_c_valid),
    .w_ready (host_c_ready),
    .w_data  (host_c),
    .r_valid (device_c_valid),
    .r_ready (device_c_ready),
    .r_data  (device_c)
  );

  ///////////////////
  // Grant channel //
  ///////////////////

  typedef `TL_D_STRUCT(DataWidth, AddrWidth, SourceWidth, SinkWidth) gnt_t;

  openip_regslice #(
    .TYPE (gnt_t),
    .FORWARD          ((GrantMode & 1) != 0),
    .REVERSE          ((GrantMode & 2) != 0),
    .HIGH_PERFORMANCE ((GrantMode & 4) != 0)
  ) gnt_fifo (
    .clk     (clk_i),
    .rstn    (rst_ni),
    .w_valid (device_d_valid),
    .w_ready (device_d_ready),
    .w_data  (device_d),
    .r_valid (host_d_valid),
    .r_ready (host_d_ready),
    .r_data  (host_d)
  );

  /////////////////////////////
  // Acknowledgement channel //
  /////////////////////////////

  openip_regslice #(
    .DATA_WIDTH (SinkWidth),
    .FORWARD          ((AckMode & 1) != 0),
    .REVERSE          ((AckMode & 2) != 0),
    .HIGH_PERFORMANCE ((AckMode & 4) != 0)
  ) ack_fifo (
    .clk     (clk_i),
    .rstn    (rst_ni),
    .w_valid (host_e_valid),
    .w_ready (host_e_ready),
    .w_data  (host_e),
    .r_valid (device_e_valid),
    .r_ready (device_e_ready),
    .r_data  (device_e)
  );

endmodule
