`include "tl_util.svh"

module tl_fifo_sync import tl_pkg::*; #(
  parameter  int unsigned SourceWidth   = 1,
  parameter  int unsigned SinkWidth     = 1,
  parameter  int unsigned AddrWidth     = 56,
  parameter  int unsigned DataWidth     = 64,

  parameter  bit          FifoPass        = 1'b1,
  parameter  bit          RequestFifoPass = FifoPass,
  parameter  bit          ProbeFifoPass   = FifoPass,
  parameter  bit          ReleaseFifoPass = FifoPass,
  parameter  bit          GrantFifoPass   = FifoPass,
  parameter  bit          AckFifoPass     = FifoPass,

  parameter  int unsigned FifoDepth        = 4,
  parameter  int unsigned RequestFifoDepth = FifoDepth,
  parameter  int unsigned ProbeFifoDepth   = FifoDepth,
  parameter  int unsigned ReleaseFifoDepth = FifoDepth,
  parameter  int unsigned GrantFifoDepth   = FifoDepth,
  parameter  int unsigned AckFifoDepth     = FifoDepth
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
  bit [$bits(req_t)-1:0] req_w;
  assign req_w = host_a;

  prim_fifo_sync #(
    .Width ($bits(req_t)),
    .Pass  (RequestFifoPass),
    .Depth (RequestFifoDepth)
  ) req_fifo (
    .clk_i,
    .rst_ni,
    .clr_i    (1'b0),
    .wvalid_i (host_a_valid),
    .wready_o (host_a_ready),
    .wdata_i  (req_w),
    .rvalid_o (device_a_valid),
    .rready_i (device_a_ready),
    .rdata_o  (device_a),
    .full_o   (),
    .depth_o  (),
    .err_o    ()
  );

  ///////////////////
  // Probe channel //
  ///////////////////

  typedef `TL_B_STRUCT(DataWidth, AddrWidth, SourceWidth, SinkWidth) prb_t;
  bit [$bits(prb_t)-1:0] prb_w;
  assign prb_w = device_b;

  prim_fifo_sync #(
    .Width ($bits(prb_t)),
    .Pass  (ProbeFifoPass),
    .Depth (ProbeFifoDepth)
  ) prb_fifo (
    .clk_i,
    .rst_ni,
    .clr_i    (1'b0),
    .wvalid_i (device_b_valid),
    .wready_o (device_b_ready),
    .wdata_i  (prb_w),
    .rvalid_o (host_b_valid),
    .rready_i (host_b_ready),
    .rdata_o  (host_b),
    .full_o   (),
    .depth_o  (),
    .err_o    ()
  );

  /////////////////////
  // Release channel //
  /////////////////////

  typedef `TL_C_STRUCT(DataWidth, AddrWidth, SourceWidth, SinkWidth) rel_t;
  bit [$bits(rel_t)-1:0] rel_w;
  assign rel_w = host_c;

  prim_fifo_sync #(
    .Width ($bits(rel_t)),
    .Pass  (ReleaseFifoPass),
    .Depth (ReleaseFifoDepth)
  ) rel_fifo (
    .clk_i,
    .rst_ni,
    .clr_i    (1'b0),
    .wvalid_i (host_c_valid),
    .wready_o (host_c_ready),
    .wdata_i  (rel_w),
    .rvalid_o (device_c_valid),
    .rready_i (device_c_ready),
    .rdata_o  (device_c),
    .full_o   (),
    .depth_o  (),
    .err_o    ()
  );

  ///////////////////
  // Grant channel //
  ///////////////////

  typedef `TL_D_STRUCT(DataWidth, AddrWidth, SourceWidth, SinkWidth) gnt_t;
  bit [$bits(gnt_t)-1:0] gnt_w;
  assign gnt_w = device_d;

  prim_fifo_sync #(
    .Width ($bits(gnt_t)),
    .Pass  (GrantFifoPass),
    .Depth (GrantFifoDepth)
  ) gnt_fifo (
    .clk_i,
    .rst_ni,
    .clr_i    (1'b0),
    .wvalid_i (device_d_valid),
    .wready_o (device_d_ready),
    .wdata_i  (gnt_w),
    .rvalid_o (host_d_valid),
    .rready_i (host_d_ready),
    .rdata_o  (host_d),
    .full_o   (),
    .depth_o  (),
    .err_o    ()
  );

  /////////////////////////////
  // Acknowledgement channel //
  /////////////////////////////

  prim_fifo_sync #(
    .Width (SinkWidth),
    .Pass  (AckFifoPass),
    .Depth (AckFifoDepth)
  ) ack_fifo (
    .clk_i,
    .rst_ni,
    .clr_i    (1'b0),
    .wvalid_i (host_e_valid),
    .wready_o (host_e_ready),
    .wdata_i  (host_e),
    .rvalid_o (device_e_valid),
    .rready_i (device_e_ready),
    .rdata_o  (device_e),
    .full_o   (),
    .depth_o  (),
    .err_o    ()
  );

endmodule
