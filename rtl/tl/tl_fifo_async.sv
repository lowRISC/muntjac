`include "tl_util.svh"

module tl_fifo_async import tl_pkg::*; #(
  parameter  int unsigned SourceWidth   = 1,
  parameter  int unsigned SinkWidth     = 1,
  parameter  int unsigned AddrWidth     = 56,
  parameter  int unsigned DataWidth     = 64,

  parameter  int unsigned FifoDepth        = 4,
  parameter  int unsigned RequestFifoDepth = FifoDepth,
  parameter  int unsigned ProbeFifoDepth   = FifoDepth,
  parameter  int unsigned ReleaseFifoDepth = FifoDepth,
  parameter  int unsigned GrantFifoDepth   = FifoDepth,
  parameter  int unsigned AckFifoDepth     = FifoDepth
) (
  input  logic clk_host_i,
  input  logic rst_host_ni,

  `TL_DECLARE_DEVICE_PORT(DataWidth, AddrWidth, SourceWidth, SinkWidth, host),

  input  logic clk_device_i,
  input  logic rst_device_ni,

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

  prim_fifo_async #(
    .Width ($bits(req_t)),
    .Depth (RequestFifoDepth)
  ) req_fifo (
    .clk_wr_i  (clk_host_i),
    .rst_wr_ni (rst_host_ni),
    .wvalid_i  (host_a_valid),
    .wready_o  (host_a_ready),
    .wdata_i   (host_a),
    .wdepth_o  (),
    .clk_rd_i  (clk_device_i),
    .rst_rd_ni (rst_device_ni),
    .rvalid_i  (device_a_valid),
    .rready_o  (device_a_ready),
    .rdata_o   (device_a),
    .rdepth_o  ()
  );

  ///////////////////
  // Probe channel //
  ///////////////////

  typedef `TL_B_STRUCT(DataWidth, AddrWidth, SourceWidth, SinkWidth) prb_t;

  prim_fifo_async #(
    .Width ($bits(prb_t)),
    .Depth (ProbeFifoDepth)
  ) prb_fifo (
    .clk_wr_i  (clk_device_i),
    .rst_wr_ni (rst_device_ni),
    .wvalid_i  (device_b_valid),
    .wready_o  (device_b_ready),
    .wdata_i   (device_b),
    .wdepth_o  (),
    .clk_rd_i  (clk_host_i),
    .rst_rd_ni (rst_host_ni),
    .rvalid_i  (host_b_valid),
    .rready_o  (host_b_ready),
    .rdata_o   (host_b),
    .rdepth_o  ()
  );

  /////////////////////
  // Release channel //
  /////////////////////

  typedef `TL_C_STRUCT(DataWidth, AddrWidth, SourceWidth, SinkWidth) rel_t;

  prim_fifo_async #(
    .Width ($bits(rel_t)),
    .Depth (ReleaseFifoDepth)
  ) rel_fifo (
    .clk_wr_i  (clk_host_i),
    .rst_wr_ni (rst_host_ni),
    .wvalid_i  (host_c_valid),
    .wready_o  (host_c_ready),
    .wdata_i   (host_c),
    .wdepth_o  (),
    .clk_rd_i  (clk_device_i),
    .rst_rd_ni (rst_device_ni),
    .rvalid_i  (device_c_valid),
    .rready_o  (device_c_ready),
    .rdata_o   (device_c),
    .rdepth_o  ()
  );

  ///////////////////
  // Grant channel //
  ///////////////////

  typedef `TL_D_STRUCT(DataWidth, AddrWidth, SourceWidth, SinkWidth) gnt_t;

  prim_fifo_async #(
    .Width ($bits(gnt_t)),
    .Depth (GrantFifoDepth)
  ) gnt_fifo (
    .clk_wr_i  (clk_device_i),
    .rst_wr_ni (rst_device_ni),
    .wvalid_i  (device_d_valid),
    .wready_o  (device_d_ready),
    .wdata_i   (device_d),
    .wdepth_o  (),
    .clk_rd_i  (clk_host_i),
    .rst_rd_ni (rst_host_ni),
    .rvalid_i  (host_d_valid),
    .rready_o  (host_d_ready),
    .rdata_o   (host_d),
    .rdepth_o  ()
  );

  /////////////////////////////
  // Acknowledgement channel //
  /////////////////////////////

  prim_fifo_async #(
    .Width (SinkWidth),
    .Depth (AckFifoDepth)
  ) ack_fifo (
    .clk_wr_i  (clk_host_i),
    .rst_wr_ni (rst_host_ni),
    .wvalid_i  (host_e_valid),
    .wready_o  (host_e_ready),
    .wdata_i   (host_e),
    .wdepth_o  (),
    .clk_rd_i  (clk_device_i),
    .rst_rd_ni (rst_device_ni),
    .rvalid_i  (device_e_valid),
    .rready_o  (device_e_ready),
    .rdata_o   (device_e),
    .rdepth_o  ()
  );

endmodule
