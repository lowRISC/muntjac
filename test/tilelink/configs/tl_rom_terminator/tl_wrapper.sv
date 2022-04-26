// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

`include "tl_verilator.svh"
`include "parameters.svh"

module tl_wrapper #(
    // Defined externally.
    parameter int unsigned DataWidth   = `DataWidth,
    parameter int unsigned AddrWidth   = `AddrWidth,
    parameter int unsigned HostSourceWidth = `HostSourceWidth,
    parameter int unsigned DeviceSourceWidth = `DeviceSourceWidth,
    parameter int unsigned HostSinkWidth = `HostSinkWidth,
    parameter int unsigned MaxSize     = `MaxSize,
    parameter int unsigned SinkBase    = `SinkBase,
    parameter int unsigned SinkMask    = `SinkMask
) (
  input logic clk_i,
  input logic rst_ni,

  `TL_VERILATOR_HOST_PORT(DataWidth, AddrWidth, HostSourceWidth, HostSinkWidth, host),
  `TL_VERILATOR_DEVICE_PORT(DataWidth, AddrWidth, DeviceSourceWidth, 1, dev)
);

  `TL_DECLARE(DataWidth, AddrWidth, HostSourceWidth, HostSinkWidth, host_tl);
  `TL_DECLARE(DataWidth, AddrWidth, DeviceSourceWidth, 1, device_tl);

  `TL_VERILATOR_BIND_HOST_PORT(host, host_tl);
  `TL_VERILATOR_BIND_DEVICE_PORT(dev, device_tl);

  tl_rom_terminator #(
    .DataWidth (DataWidth),
    .AddrWidth (AddrWidth),
    .HostSourceWidth (HostSourceWidth),
    .DeviceSourceWidth (DeviceSourceWidth),
    .HostSinkWidth (HostSinkWidth),
    .MaxSize (MaxSize),
    .SinkBase (SinkBase),
    .SinkMask (SinkMask)
  ) dut (
    .clk_i (clk_i),
    .rst_ni (rst_ni),
    `TL_CONNECT_DEVICE_PORT(host, host_tl),
    `TL_CONNECT_HOST_PORT(device, device_tl)
  );

endmodule
