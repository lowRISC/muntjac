module tl_source_shifter #(
  parameter  int unsigned HostSourceWidth = 4,
  parameter  int unsigned DeviceSourceWidth = 4,

  parameter bit [DeviceSourceWidth-1:0] SourceBase = 0,
  parameter bit [HostSourceWidth-1:0]   SourceMask = 0
) (
  input  logic clk_i,
  input  logic rst_ni,

  tl_channel.device host,
  tl_channel.host   device
);

  if (host.SourceWidth != HostSourceWidth) $fatal(1, "SourceWidth mismatch");
  if (device.SourceWidth != DeviceSourceWidth) $fatal(1, "SourceWidth mismatch");

  if (host.SinkWidth != device.SinkWidth) $fatal(1, "SinkWidth mismatch");
  if (host.AddrWidth != device.AddrWidth) $fatal(1, "AddrWidth mismatch");
  if (host.DataWidth != device.DataWidth) $fatal(1, "DataWidth mismatch");
  if (host.SizeWidth != device.SizeWidth) $fatal(1, "SizeWidth mismatch");

  /////////////////////
  // Request channel //
  /////////////////////

  assign host.a_ready = device.a_ready;

  assign device.a_valid   = host.a_valid;
  assign device.a_opcode  = host.a_opcode;
  assign device.a_param   = host.a_param;
  assign device.a_size    = host.a_size;
  assign device.a_address = host.a_address;
  assign device.a_mask    = host.a_mask;
  assign device.a_corrupt = host.a_corrupt;
  assign device.a_data    = host.a_data;

  assign device.a_source = SourceBase | host.a_source;

  ///////////////////
  // Probe channel //
  ///////////////////

  assign device.b_ready = host.b_ready;

  assign host.b_valid   = device.b_valid;
  assign host.b_opcode  = device.b_opcode;
  assign host.b_param   = device.b_param;
  assign host.b_size    = device.b_size;
  assign host.b_address = device.b_address;
  assign host.b_mask    = device.b_mask;
  assign host.b_corrupt = device.b_corrupt;
  assign host.b_data    = device.b_data;

  assign host.b_source = device.b_source & SourceMask;

  /////////////////////
  // Release channel //
  /////////////////////

  assign host.c_ready = device.c_ready;

  assign device.c_valid   = host.c_valid;
  assign device.c_opcode  = host.c_opcode;
  assign device.c_param   = host.c_param;
  assign device.c_size    = host.c_size;
  assign device.c_address = host.c_address;
  assign device.c_corrupt = host.c_corrupt;
  assign device.c_data    = host.c_data;

  assign device.c_source = SourceBase | host.c_source;

  ///////////////////
  // Grant channel //
  ///////////////////

  assign device.d_ready = host.d_ready;

  assign host.d_valid   = device.d_valid;
  assign host.d_opcode  = device.d_opcode;
  assign host.d_param   = device.d_param;
  assign host.d_size    = device.d_size;
  assign host.d_sink    = device.d_sink;
  assign host.d_denied  = device.d_denied;
  assign host.d_corrupt = device.d_corrupt;
  assign host.d_data    = device.d_data;

  assign host.d_source = device.d_source & SourceMask;

  /////////////////////////////
  // Acknowledgement channel //
  /////////////////////////////

  assign host.e_ready = device.e_ready;

  assign device.e_valid = host.e_valid;
  assign device.e_sink  = host.e_sink;

endmodule
