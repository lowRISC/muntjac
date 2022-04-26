// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

`include "tl_verilator.svh"
`include "parameters.svh"

module tl_wrapper import prim_util_pkg::*; #(
    // Defined externally.
    parameter int unsigned DataWidth = `DataWidth,
    parameter int unsigned AddrWidth = `AddrWidth,
    parameter int unsigned SourceWidth = `SourceWidth,
    parameter int unsigned SinkWidth = `SinkWidth,
    parameter int unsigned MaxSize = `MaxSize,

    parameter int unsigned NumLinks = `NumLinks,
    localparam int unsigned LinkWidth = vbits(NumLinks),

    parameter int unsigned NumCachedHosts = `NumCachedHosts,
    parameter int unsigned NumCachedLinks = `NumCachedLinks,

    parameter int unsigned NumSourceRange = `NumSourceRange,
    parameter logic [NumSourceRange-1:0][SourceWidth-1:0] SourceBase = `SourceBase,
    parameter logic [NumSourceRange-1:0][SourceWidth-1:0] SourceMask = `SourceMask,
    parameter logic [NumSourceRange-1:0][LinkWidth-1:0]   SourceLink = `SourceLink
) (
  input logic clk_i,
  input logic rst_ni,

  `TL_VERILATOR_HOST_PORT_ARR(DataWidth, AddrWidth, SourceWidth, SinkWidth, host, NumLinks),
  `TL_VERILATOR_DEVICE_PORT(DataWidth, AddrWidth, SourceWidth, SinkWidth, dev)
);

  `TL_DECLARE_ARR(DataWidth, AddrWidth, SourceWidth, SinkWidth, host_tl, [NumLinks-1:0]);
  `TL_DECLARE(DataWidth, AddrWidth, SourceWidth, SinkWidth, device_tl);

  for (genvar i = 0; i < NumLinks; i++) begin
    `TL_VERILATOR_BIND_HOST_PORT_IDX(host, [i], host_tl, [i]);
  end

  `TL_VERILATOR_BIND_DEVICE_PORT(dev, device_tl);

  tl_socket_m1 #(
    .DataWidth (DataWidth),
    .AddrWidth (AddrWidth),
    .SourceWidth (SourceWidth),
    .SinkWidth (SinkWidth),
    .MaxSize (MaxSize),
    .NumLinks (NumLinks),
    .NumCachedHosts (NumCachedHosts),
    .NumCachedLinks (NumCachedLinks),
    .NumSourceRange (NumSourceRange),
    .SourceBase (SourceBase),
    .SourceMask (SourceMask),
    .SourceLink (SourceLink)
  ) dut (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_DEVICE_PORT(host, host_tl),
    `TL_CONNECT_HOST_PORT(device, device_tl)
  );

endmodule
