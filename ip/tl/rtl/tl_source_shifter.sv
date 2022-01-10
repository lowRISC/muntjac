`include "tl_util.svh"

module tl_source_shifter #(
  parameter  int unsigned HostSourceWidth = 4,
  parameter  int unsigned DeviceSourceWidth = 4,
  parameter  int unsigned SinkWidth     = 1,
  parameter  int unsigned AddrWidth     = 56,
  parameter  int unsigned DataWidth     = 64,

  parameter bit [DeviceSourceWidth-1:0] SourceBase = 0,
  parameter bit [HostSourceWidth-1:0]   SourceMask = 0
) (
  input  logic clk_i,
  input  logic rst_ni,

  `TL_DECLARE_DEVICE_PORT(DataWidth, AddrWidth, HostSourceWidth, SinkWidth, host),
  `TL_DECLARE_HOST_PORT(DataWidth, AddrWidth, DeviceSourceWidth, SinkWidth, device)
);

  `TL_DECLARE(DataWidth, AddrWidth, HostSourceWidth, SinkWidth, host);
  `TL_DECLARE(DataWidth, AddrWidth, DeviceSourceWidth, SinkWidth, device);
  `TL_BIND_DEVICE_PORT(host, host);
  `TL_BIND_HOST_PORT(device, device);

  /////////////////////
  // Request channel //
  /////////////////////

  assign host_a_ready = device_a_ready;

  assign device_a_valid   = host_a_valid;
  assign device_a.opcode  = host_a.opcode;
  assign device_a.param   = host_a.param;
  assign device_a.size    = host_a.size;
  assign device_a.address = host_a.address;
  assign device_a.mask    = host_a.mask;
  assign device_a.corrupt = host_a.corrupt;
  assign device_a.data    = host_a.data;

  assign device_a.source = SourceBase | host_a.source;

  ///////////////////
  // Probe channel //
  ///////////////////

  assign device_b_ready = host_b_ready;

  assign host_b_valid   = device_b_valid;
  assign host_b.opcode  = device_b.opcode;
  assign host_b.param   = device_b.param;
  assign host_b.size    = device_b.size;
  assign host_b.address = device_b.address;

  assign host_b.source = device_b.source & SourceMask;

  /////////////////////
  // Release channel //
  /////////////////////

  assign host_c_ready = device_c_ready;

  assign device_c_valid   = host_c_valid;
  assign device_c.opcode  = host_c.opcode;
  assign device_c.param   = host_c.param;
  assign device_c.size    = host_c.size;
  assign device_c.address = host_c.address;
  assign device_c.corrupt = host_c.corrupt;
  assign device_c.data    = host_c.data;

  assign device_c.source = SourceBase | host_c.source;

  ///////////////////
  // Grant channel //
  ///////////////////

  assign device_d_ready = host_d_ready;

  assign host_d_valid   = device_d_valid;
  assign host_d.opcode  = device_d.opcode;
  assign host_d.param   = device_d.param;
  assign host_d.size    = device_d.size;
  assign host_d.sink    = device_d.sink;
  assign host_d.denied  = device_d.denied;
  assign host_d.corrupt = device_d.corrupt;
  assign host_d.data    = device_d.data;

  assign host_d.source = device_d.source & SourceMask;

  /////////////////////////////
  // Acknowledgement channel //
  /////////////////////////////

  assign host_e_ready = device_e_ready;

  assign device_e_valid = host_e_valid;
  assign device_e.sink  = host_e.sink;

endmodule
