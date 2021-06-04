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
    .clr_i  (1'b0),
    .wvalid (host_a_valid),
    .wready (host_a_ready),
    .wdata  (req_w),
    .rvalid (device_a_valid),
    .rready (device_a_ready),
    .rdata  (device_a),
    .depth  ()
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
    .clr_i  (1'b0),
    .wvalid (device_b_valid),
    .wready (device_b_ready),
    .wdata  (prb_w),
    .rvalid (host_b_valid),
    .rready (host_b_ready),
    .rdata  (host_b),
    .depth  ()
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
    .clr_i  (1'b0),
    .wvalid (host_c_valid),
    .wready (host_c_ready),
    .wdata  (rel_w),
    .rvalid (device_c_valid),
    .rready (device_c_ready),
    .rdata  (device_c),
    .depth  ()
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
    .clr_i  (1'b0),
    .wvalid (device_d_valid),
    .wready (device_d_ready),
    .wdata  (gnt_w),
    .rvalid (host_d_valid),
    .rready (host_d_ready),
    .rdata  (host_d),
    .depth  ()
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
    .clr_i  (1'b0),
    .wvalid (host_e_valid),
    .wready (host_e_ready),
    .wdata  (host_e),
    .rvalid (device_e_valid),
    .rready (device_e_ready),
    .rdata  (device_e),
    .depth  ()
  );

endmodule
