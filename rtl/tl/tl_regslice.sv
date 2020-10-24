module tl_regslice import tl_pkg::*; #(
  parameter  int unsigned SourceWidth   = 1,
  parameter  int unsigned SinkWidth     = 1,
  parameter  int unsigned AddrWidth     = 56,
  parameter  int unsigned DataWidth     = 64,
  parameter  int unsigned SizeWidth     = 3,

  parameter  int unsigned RequestMode   = 0,
  parameter  int unsigned ProbeMode     = 0,
  parameter  int unsigned ReleaseMode   = 0,
  parameter  int unsigned GrantMode     = 0,
  parameter  int unsigned AckMode       = 0
) (
  input  logic clk_i,
  input  logic rst_ni,

  tl_channel.device host,
  tl_channel.host   device
);

  localparam int unsigned DataWidthInBytes = DataWidth / 8;

  if (host.SourceWidth != SourceWidth) $fatal(1, "SourceWidth mismatch");
  if (host.SinkWidth != SinkWidth) $fatal(1, "SinkWidth mismatch");
  if (host.AddrWidth != AddrWidth) $fatal(1, "AddrWidth mismatch");
  if (host.DataWidth != DataWidth) $fatal(1, "DataWidth mismatch");
  if (host.SizeWidth != SizeWidth) $fatal(1, "SizeWidth mismatch");
  if (device.SourceWidth != SourceWidth) $fatal(1, "SourceWidth mismatch");
  if (device.SinkWidth != SinkWidth) $fatal(1, "SinkWidth mismatch");
  if (device.AddrWidth != AddrWidth) $fatal(1, "AddrWidth mismatch");
  if (device.DataWidth != DataWidth) $fatal(1, "DataWidth mismatch");
  if (device.SizeWidth != SizeWidth) $fatal(1, "SizeWidth mismatch");

  /////////////////////
  // Request channel //
  /////////////////////

  typedef struct packed {
    tl_a_op_e               opcode;
    logic [2:0]             param;
    logic [SizeWidth-1:0]   size;
    logic [SourceWidth-1:0] source;
    logic [AddrWidth-1:0]   address;
    logic [DataWidth/8-1:0] mask;
    logic                   corrupt;
    logic [DataWidth-1:0]   data;
  } req_t;

  wire req_t req_w = req_t'{
    host.a_opcode,
    host.a_param,
    host.a_size,
    host.a_source,
    host.a_address,
    host.a_mask,
    host.a_corrupt,
    host.a_data
  };
  wire req_t req_r;

  openip_regslice #(
    .TYPE (req_t),
    .FORWARD          ((RequestMode & 1) != 0),
    .REVERSE          ((RequestMode & 2) != 0),
    .HIGH_PERFORMANCE ((RequestMode & 4) != 0)
  ) req_fifo (
    .clk     (clk_i),
    .rstn    (rst_ni),
    .w_valid (host.a_valid),
    .w_ready (host.a_ready),
    .w_data  (req_w),
    .r_valid (device.a_valid),
    .r_ready (device.a_ready),
    .r_data  (req_r)
  );

  assign device.a_opcode  = req_r.opcode;
  assign device.a_param   = req_r.param;
  assign device.a_size    = req_r.size;
  assign device.a_source  = req_r.source;
  assign device.a_address = req_r.address;
  assign device.a_mask    = req_r.mask;
  assign device.a_corrupt = req_r.corrupt;
  assign device.a_data    = req_r.data;

  ///////////////////
  // Probe channel //
  ///////////////////

  typedef struct packed {
    tl_b_op_e               opcode;
    logic [2:0]             param;
    logic [SizeWidth-1:0]   size;
    logic [SourceWidth-1:0] source;
    logic [AddrWidth-1:0]   address;
    logic [DataWidth/8-1:0] mask;
    logic                   corrupt;
    logic [DataWidth-1:0]   data;
  } prb_t;

  wire prb_t prb_w = prb_t'{
    device.b_opcode,
    device.b_param,
    device.b_size,
    device.b_source,
    device.b_address,
    device.b_mask,
    device.b_corrupt,
    device.b_data
  };
  wire prb_t prb_r;

  openip_regslice #(
    .TYPE (prb_t),
    .FORWARD          ((ProbeMode & 1) != 0),
    .REVERSE          ((ProbeMode & 2) != 0),
    .HIGH_PERFORMANCE ((ProbeMode & 4) != 0)
  ) prb_fifo (
    .clk     (clk_i),
    .rstn    (rst_ni),
    .w_valid (device.b_valid),
    .w_ready (device.b_ready),
    .w_data  (prb_w),
    .r_valid (host.b_valid),
    .r_ready (host.b_ready),
    .r_data  (prb_r)
  );

  assign host.b_opcode  = prb_r.opcode;
  assign host.b_param   = prb_r.param;
  assign host.b_size    = prb_r.size;
  assign host.b_source  = prb_r.source;
  assign host.b_address = prb_r.address;
  assign host.b_mask    = prb_r.mask;
  assign host.b_corrupt = prb_r.corrupt;
  assign host.b_data    = prb_r.data;

  /////////////////////
  // Release channel //
  /////////////////////

  typedef struct packed {
    tl_c_op_e               opcode;
    logic [2:0]             param;
    logic [SizeWidth-1:0]   size;
    logic [SourceWidth-1:0] source;
    logic [AddrWidth-1:0]   address;
    logic                   corrupt;
    logic [DataWidth-1:0]   data;
  } rel_t;

  wire rel_t rel_w = rel_t'{
    host.c_opcode,
    host.c_param,
    host.c_size,
    host.c_source,
    host.c_address,
    host.c_corrupt,
    host.c_data
  };
  wire rel_t rel_r;

  openip_regslice #(
    .TYPE (rel_t),
    .FORWARD          ((ReleaseMode & 1) != 0),
    .REVERSE          ((ReleaseMode & 2) != 0),
    .HIGH_PERFORMANCE ((ReleaseMode & 4) != 0)
  ) rel_fifo (
    .clk     (clk_i),
    .rstn    (rst_ni),
    .w_valid (host.c_valid),
    .w_ready (host.c_ready),
    .w_data  (rel_w),
    .r_valid (device.c_valid),
    .r_ready (device.c_ready),
    .r_data  (rel_r)
  );

  assign device.c_opcode  = rel_r.opcode;
  assign device.c_param   = rel_r.param;
  assign device.c_size    = rel_r.size;
  assign device.c_source  = rel_r.source;
  assign device.c_address = rel_r.address;
  assign device.c_corrupt = rel_r.corrupt;
  assign device.c_data    = rel_r.data;

  ///////////////////
  // Grant channel //
  ///////////////////

  typedef struct packed {
    tl_d_op_e               opcode;
    logic [2:0]             param;
    logic [SizeWidth-1:0]   size;
    logic [SourceWidth-1:0] source;
    logic [SinkWidth-1:0]   sink;
    logic                   denied;
    logic                   corrupt;
    logic [DataWidth-1:0]   data;
  } gnt_t;

  wire gnt_t gnt_w = gnt_t'{
    device.d_opcode,
    device.d_param,
    device.d_size,
    device.d_source,
    device.d_sink,
    device.d_denied,
    device.d_corrupt,
    device.d_data
  };
  wire gnt_t gnt_r;

  openip_regslice #(
    .TYPE (gnt_t),
    .FORWARD          ((GrantMode & 1) != 0),
    .REVERSE          ((GrantMode & 2) != 0),
    .HIGH_PERFORMANCE ((GrantMode & 4) != 0)
  ) gnt_fifo (
    .clk     (clk_i),
    .rstn    (rst_ni),
    .w_valid (device.d_valid),
    .w_ready (device.d_ready),
    .w_data  (gnt_w),
    .r_valid (host.d_valid),
    .r_ready (host.d_ready),
    .r_data  (gnt_r)
  );

  assign host.d_opcode  = gnt_r.opcode;
  assign host.d_param   = gnt_r.param;
  assign host.d_size    = gnt_r.size;
  assign host.d_source  = gnt_r.source;
  assign host.d_sink    = gnt_r.sink;
  assign host.d_denied  = gnt_r.denied;
  assign host.d_corrupt = gnt_r.corrupt;
  assign host.d_data    = gnt_r.data;

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
    .w_valid (host.e_valid),
    .w_ready (host.e_ready),
    .w_data  (host.e_sink),
    .r_valid (device.e_valid),
    .r_ready (device.e_ready),
    .r_data  (device.e_sink)
  );

endmodule
