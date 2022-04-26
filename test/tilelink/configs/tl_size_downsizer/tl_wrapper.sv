// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

`include "tl_verilator.svh"
`include "parameters.svh"

module tl_wrapper #(
    // Defined externally.
    parameter int unsigned DataWidth = `DataWidth,
    parameter int unsigned AddrWidth = `AddrWidth,
    parameter int unsigned SinkWidth = `SinkWidth,
    parameter int unsigned HostSourceWidth = `HostSourceWidth,
    parameter int unsigned DeviceSourceWidth = `DeviceSourceWidth,
    parameter int unsigned HostMaxSize = `HostMaxSize,
    parameter int unsigned DeviceMaxSize = `DeviceMaxSize
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

  tl_size_downsizer #(
    .DataWidth (DataWidth),
    .AddrWidth (AddrWidth),
    .SinkWidth (SinkWidth),
    .HostSourceWidth (HostSourceWidth),
    .DeviceSourceWidth (DeviceSourceWidth),
    .HostMaxSize (HostMaxSize),
    .DeviceMaxSize (DeviceMaxSize)
  ) dut (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_DEVICE_PORT(host, host_tl),
    `TL_CONNECT_HOST_PORT(device, device_tl)
  );

endmodule
