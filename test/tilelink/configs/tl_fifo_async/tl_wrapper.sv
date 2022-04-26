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
    parameter int unsigned FifoDepth   = `FifoDepth
    // Don't bother exposing depths of different FIFOs - they're all independent
    // so can be tested using different values of FifoDepth.
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

  // Ideally we would use different clocks here. The obvious approach is to use
  // clk and !clk, but the test framework doesn't allow signals to change on
  // the negative clock edge.
  tl_fifo_async #(
    .DataWidth (DataWidth),
    .AddrWidth (AddrWidth),
    .SourceWidth (SourceWidth),
    .SinkWidth (SinkWidth),
    .FifoDepth (FifoDepth)
  ) dut (
    .clk_host_i (clk_i),
    .rst_host_ni (rst_ni),
    `TL_CONNECT_DEVICE_PORT(host, host_tl),
    .clk_device_i (clk_i),
    .rst_device_ni (rst_ni),
    `TL_CONNECT_HOST_PORT(device, device_tl)
  );

endmodule
