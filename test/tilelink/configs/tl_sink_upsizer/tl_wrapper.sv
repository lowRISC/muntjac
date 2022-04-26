// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

`include "tl_verilator.svh"
`include "parameters.svh"

module tl_wrapper #(
    // Defined externally.
    parameter int unsigned DataWidth = `DataWidth,
    parameter int unsigned AddrWidth = `AddrWidth,
    parameter int unsigned SourceWidth = `SourceWidth,
    parameter int unsigned HostSinkWidth = `HostSinkWidth,
    parameter int unsigned DeviceSinkWidth = `DeviceSinkWidth,
    parameter int unsigned MaxSize = `MaxSize
) (
  input logic clk_i,
  input logic rst_ni,

  `TL_VERILATOR_HOST_PORT(DataWidth, AddrWidth, SourceWidth, HostSinkWidth, host),
  `TL_VERILATOR_DEVICE_PORT(DataWidth, AddrWidth, SourceWidth, DeviceSinkWidth, dev)
);

  `TL_DECLARE(DataWidth, AddrWidth, SourceWidth, HostSinkWidth, host_tl);
  `TL_DECLARE(DataWidth, AddrWidth, SourceWidth, DeviceSinkWidth, device_tl);

  `TL_VERILATOR_BIND_HOST_PORT(host, host_tl);
  `TL_VERILATOR_BIND_DEVICE_PORT(dev, device_tl);

  tl_sink_upsizer #(
    .DataWidth (DataWidth),
    .AddrWidth (AddrWidth),
    .SourceWidth (SourceWidth),
    .HostSinkWidth (HostSinkWidth),
    .DeviceSinkWidth (DeviceSinkWidth),
    .MaxSize (MaxSize)
  ) dut (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_DEVICE_PORT(host, host_tl),
    `TL_CONNECT_HOST_PORT(device, device_tl)
  );

endmodule
