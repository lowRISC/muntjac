// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

`include "tl_verilator.svh"
`include "parameters.svh"

module tl_wrapper #(
    // Defined externally.
    parameter int unsigned HostDataWidth = `HostDataWidth,
    parameter int unsigned DeviceDataWidth = `DeviceDataWidth,
    parameter int unsigned AddrWidth = `AddrWidth,
    parameter int unsigned SourceWidth = `SourceWidth,
    parameter int unsigned SinkWidth = `SinkWidth,
    parameter int unsigned MaxSize = `MaxSize
) (
  input logic clk_i,
  input logic rst_ni,

  `TL_VERILATOR_HOST_PORT(HostDataWidth, AddrWidth, SourceWidth, SinkWidth, host),
  `TL_VERILATOR_DEVICE_PORT(DeviceDataWidth, AddrWidth, SourceWidth, SinkWidth, dev)
);

  `TL_DECLARE(HostDataWidth, AddrWidth, SourceWidth, SinkWidth, host_tl);
  `TL_DECLARE(DeviceDataWidth, AddrWidth, SourceWidth, SinkWidth, device_tl);

  `TL_VERILATOR_BIND_HOST_PORT(host, host_tl);
  `TL_VERILATOR_BIND_DEVICE_PORT(dev, device_tl);

  tl_data_downsizer #(
    .HostDataWidth (HostDataWidth),
    .DeviceDataWidth (DeviceDataWidth),
    .AddrWidth (AddrWidth),
    .SourceWidth (SourceWidth),
    .SinkWidth (SinkWidth),
    .MaxSize (MaxSize)
  ) dut (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_DEVICE_PORT(host, host_tl),
    `TL_CONNECT_HOST_PORT(device, device_tl)
  );

endmodule
