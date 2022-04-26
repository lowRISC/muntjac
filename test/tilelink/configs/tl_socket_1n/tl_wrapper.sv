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

    parameter int unsigned NumAddressRange = `NumAddressRange,
    parameter logic [NumAddressRange-1:0][AddrWidth-1:0] AddressBase = `AddressBase,
    parameter logic [NumAddressRange-1:0][AddrWidth-1:0] AddressMask = `AddressMask,
    parameter logic [NumAddressRange-1:0][LinkWidth-1:0] AddressLink = `AddressLink,

    parameter int unsigned NumSinkRange = `NumSinkRange,
    parameter logic [NumSinkRange-1:0][SinkWidth-1:0] SinkBase = `SinkBase,
    parameter logic [NumSinkRange-1:0][SinkWidth-1:0] SinkMask = `SinkMask,
    parameter logic [NumSinkRange-1:0][LinkWidth-1:0] SinkLink = `SinkLink
) (
  input logic clk_i,
  input logic rst_ni,

  `TL_VERILATOR_HOST_PORT(DataWidth, AddrWidth, SourceWidth, SinkWidth, host),
  `TL_VERILATOR_DEVICE_PORT_ARR(DataWidth, AddrWidth, SourceWidth, SinkWidth, dev, NumLinks)
);

  `TL_DECLARE(DataWidth, AddrWidth, SourceWidth, SinkWidth, host_tl);
  `TL_DECLARE_ARR(DataWidth, AddrWidth, SourceWidth, SinkWidth, device_tl, [NumLinks-1:0]);

  `TL_VERILATOR_BIND_HOST_PORT(host, host_tl);

  for (genvar i = 0; i < NumLinks; i++) begin
    `TL_VERILATOR_BIND_DEVICE_PORT_IDX(dev, [i], device_tl, [i]);
  end

  tl_socket_1n #(
    .DataWidth (DataWidth),
    .AddrWidth (AddrWidth),
    .SourceWidth (SourceWidth),
    .SinkWidth (SinkWidth),
    .MaxSize (MaxSize),
    .NumLinks (NumLinks),
    .NumAddressRange (NumAddressRange),
    .AddressBase (AddressBase),
    .AddressMask (AddressMask),
    .AddressLink (AddressLink),
    .NumSinkRange (NumSinkRange),
    .SinkBase (SinkBase),
    .SinkMask (SinkMask),
    .SinkLink (SinkLink)
  ) dut (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_DEVICE_PORT(host, host_tl),
    `TL_CONNECT_HOST_PORT(device, device_tl)
  );

endmodule
