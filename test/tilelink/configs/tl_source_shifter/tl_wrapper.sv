// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

`include "tl_verilator.svh"
`include "parameters.svh"

module tl_wrapper #(
    // Defined externally.
    parameter int unsigned DataWidth = `DataWidth,
    parameter int unsigned AddrWidth = `AddrWidth,
    parameter int unsigned HostSourceWidth = `HostSourceWidth,
    parameter int unsigned DeviceSourceWidth = `DeviceSourceWidth,
    parameter int unsigned SinkWidth = `SinkWidth,
    parameter bit [DeviceSourceWidth-1:0] SourceBase = `SourceBase,
    parameter bit [HostSourceWidth-1:0]   SourceMask = `SourceMask
) (
  input logic clk_i,
  input logic rst_ni,

  `TL_VERILATOR_HOST_PORT(DataWidth, AddrWidth, HostSourceWidth, SinkWidth, host),
  `TL_VERILATOR_DEVICE_PORT(DataWidth, AddrWidth, DeviceSourceWidth, SinkWidth, dev)
);

  `TL_DECLARE(DataWidth, AddrWidth, HostSourceWidth, SinkWidth, host_tl);
  `TL_DECLARE(DataWidth, AddrWidth, DeviceSourceWidth, SinkWidth, device_tl);

  `TL_VERILATOR_BIND_HOST_PORT(host, host_tl);
  `TL_VERILATOR_BIND_DEVICE_PORT(dev, device_tl);

  tl_source_shifter #(
    .DataWidth (DataWidth),
    .AddrWidth (AddrWidth),
    .HostSourceWidth (HostSourceWidth),
    .DeviceSourceWidth (DeviceSourceWidth),
    .SinkWidth (SinkWidth),
    .SourceBase (SourceBase),
    .SourceMask (SourceMask)
  ) dut (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_DEVICE_PORT(host, host_tl),
    `TL_CONNECT_HOST_PORT(device, device_tl)
  );

endmodule
