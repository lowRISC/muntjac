// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

`include "tl_verilator.svh"
`include "parameters.svh"

module tl_wrapper #(
    // Defined externally.
    parameter int unsigned SourceWidth = `SourceWidth,
    parameter int unsigned SinkWidth   = `SinkWidth,
    parameter int unsigned AddrWidth   = `AddrWidth,
    parameter int unsigned DataWidth   = `DataWidth,
    parameter int unsigned Mode        = `Mode
    // Don't bother exposing modes of individual buffers - they're all
    // independent so can be tested using top-level parameters.
) (
  input logic clk_i,
  input logic rst_ni,

  `TL_VERILATOR_HOST_PORT(DataWidth, AddrWidth, SourceWidth, SinkWidth, host),
  `TL_VERILATOR_DEVICE_PORT(DataWidth, AddrWidth, SourceWidth, SinkWidth, dev)
);

  `TL_DECLARE(DataWidth, AddrWidth, SourceWidth, SinkWidth, host_tl);
  `TL_DECLARE(DataWidth, AddrWidth, SourceWidth, SinkWidth, device_tl);

  `TL_VERILATOR_BIND_HOST_PORT(host, host_tl);
  `TL_VERILATOR_BIND_DEVICE_PORT(dev, device_tl);

  tl_regslice #(
    .DataWidth (DataWidth),
    .AddrWidth (AddrWidth),
    .SourceWidth (SourceWidth),
    .SinkWidth (SinkWidth),
    .RequestMode (Mode),
    .ProbeMode (Mode),
    .ReleaseMode (Mode),
    .GrantMode (Mode),
    .AckMode (Mode)
  ) dut (
    .clk_i (clk_i),
    .rst_ni (rst_ni),
    `TL_CONNECT_DEVICE_PORT(host, host_tl),
    `TL_CONNECT_HOST_PORT(device, device_tl)
  );

endmodule
