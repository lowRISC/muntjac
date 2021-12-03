// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Modules to apply assertions to all TileLink IP. 
//
// Exceptions:
//  * Modules which do not manipulate TileLink signals (or make trivial changes)
//    * tl_burst_tracker
//    * tl_fifo_async
//    * tl_source_shifter
//  * Anything included as part of the general-purpose tl_adapter

module tl_adapter_checker import tl_pkg::*; #(
    parameter int unsigned HostDataWidth,
    parameter int unsigned DeviceDataWidth,
    parameter int unsigned HostAddrWidth,
    parameter int unsigned DeviceAddrWidth,
    parameter int unsigned HostSinkWidth,
    parameter int unsigned DeviceSinkWidth,
    parameter int unsigned HostSourceWidth,
    parameter int unsigned DeviceSourceWidth
) (
  input logic clk_i,
  input logic rst_ni,

  `TL_DECLARE_TAP_PORT(HostDataWidth, HostAddrWidth, HostSourceWidth, HostSinkWidth, host),
  `TL_DECLARE_TAP_PORT(DeviceDataWidth, DeviceAddrWidth, DeviceSourceWidth, DeviceSinkWidth, device)
);

  tl_assert #(
    .Protocol (TL_C),
    .EndpointType ("Host"),
    .AddrWidth (HostAddrWidth),
    .DataWidth (HostDataWidth),
    .SinkWidth (HostSinkWidth),
    .SourceWidth (HostSourceWidth)
  ) host_checker (
    .clk_i,
    .rst_ni,
    `TL_FORWARD_TAP_PORT(tl, host)
  );

  tl_assert #(
    .Protocol (TL_C),
    .EndpointType ("Device"),
    .AddrWidth (DeviceAddrWidth),
    .DataWidth (DeviceDataWidth),
    .SinkWidth (DeviceSinkWidth),
    .SourceWidth (DeviceSourceWidth)
  ) device_checker (
    .clk_i,
    .rst_ni,
    `TL_FORWARD_TAP_PORT(tl, device)
  );

endmodule


module tl_adapter_bram_checker import tl_pkg::*; #(
    parameter int unsigned AddrWidth,
    parameter int unsigned DataWidth,
    parameter int unsigned SourceWidth
) (
  input logic clk_i,
  input logic rst_ni,

  `TL_DECLARE_TAP_PORT(DataWidth, AddrWidth, SourceWidth, 1, host)
);

  tl_assert #(
    .Protocol (TL_UL),
    .EndpointType ("Host"),
    .AddrWidth (AddrWidth),
    .DataWidth (DataWidth),
    .SinkWidth (1),
    .SourceWidth (SourceWidth)
  ) host_checker (
    .clk_i,
    .rst_ni,
    `TL_FORWARD_TAP_PORT(tl, host)
  );

endmodule


module tl_axi_adapter_checker import tl_pkg::*; #(
    parameter int unsigned AddrWidth,
    parameter int unsigned DataWidth,
    parameter int unsigned SourceWidth,
    parameter int unsigned SinkWidth
) (
  input logic clk_i,
  input logic rst_ni,

  `TL_DECLARE_TAP_PORT(DataWidth, AddrWidth, SourceWidth, SinkWidth, host)
);

  tl_assert #(
    .Protocol (TL_UH),
    .EndpointType ("Host"),
    .AddrWidth (AddrWidth),
    .DataWidth (DataWidth),
    .SinkWidth (SinkWidth),
    .SourceWidth (SourceWidth)
  ) host_checker (
    .clk_i,
    .rst_ni,
    `TL_FORWARD_TAP_PORT(tl, host)
  );

endmodule


module tl_broadcast_checker import tl_pkg::*; #(
    parameter int unsigned AddrWidth,
    parameter int unsigned DataWidth,
    parameter int unsigned SourceWidth,
    parameter int unsigned SinkWidth
) (
  input logic clk_i,
  input logic rst_ni,

  `TL_DECLARE_TAP_PORT(DataWidth, AddrWidth, SourceWidth, SinkWidth, host),
  `TL_DECLARE_TAP_PORT(DataWidth, AddrWidth, SourceWidth, SinkWidth, device)
);

  tl_assert #(
    .Protocol (TL_C),
    .EndpointType ("Host"),
    .AddrWidth (AddrWidth),
    .DataWidth (DataWidth),
    .SinkWidth (SinkWidth),
    .SourceWidth (SourceWidth)
  ) host_checker (
    .clk_i,
    .rst_ni,
    `TL_FORWARD_TAP_PORT(tl, host)
  );

  tl_assert #(
    .Protocol (TL_C),
    .EndpointType ("Device"),
    .AddrWidth (AddrWidth),
    .DataWidth (DataWidth),
    .SinkWidth (SinkWidth),
    .SourceWidth (SourceWidth)
  ) device_checker (
    .clk_i,
    .rst_ni,
    `TL_FORWARD_TAP_PORT(tl, device)
  );

endmodule


module tl_socket_1n_checker import tl_pkg::*; #(
    parameter int unsigned AddrWidth,
    parameter int unsigned DataWidth,
    parameter int unsigned SourceWidth,
    parameter int unsigned SinkWidth,
    parameter int unsigned NumLinks
) (
  input logic clk_i,
  input logic rst_ni,

  `TL_DECLARE_TAP_PORT(DataWidth, AddrWidth, SourceWidth, SinkWidth, host),
  `TL_DECLARE_TAP_PORT_ARR(DataWidth, AddrWidth, SourceWidth, SinkWidth, device, [NumLinks-1:0])
);

  tl_assert #(
    .Protocol (TL_C),
    .EndpointType ("Host"),
    .AddrWidth (AddrWidth),
    .DataWidth (DataWidth),
    .SinkWidth (SinkWidth),
    .SourceWidth (SourceWidth)
  ) host_checker (
    .clk_i,
    .rst_ni,
    `TL_FORWARD_TAP_PORT(tl, host)
  );

  for (genvar i=0; i < NumLinks; i++) begin
    tl_assert #(
      .Protocol (TL_C),
      .EndpointType ("Device"),
      .AddrWidth (AddrWidth),
      .DataWidth (DataWidth),
      .SinkWidth (SinkWidth),
      .SourceWidth (SourceWidth)
    ) device_checker (
      .clk_i,
      .rst_ni,
      `TL_FORWARD_TAP_PORT_IDX(tl, device, [i])
    );
  end

endmodule


module tl_socket_m1_checker import tl_pkg::*; #(
    parameter int unsigned SourceWidth,
    parameter int unsigned SinkWidth,
    parameter int unsigned AddrWidth,
    parameter int unsigned DataWidth,
    parameter int unsigned NumLinks
) (
  input logic clk_i,
  input logic rst_ni,

  `TL_DECLARE_TAP_PORT_ARR(DataWidth, AddrWidth, SourceWidth, SinkWidth, host, [NumLinks-1:0]),
  `TL_DECLARE_TAP_PORT(DataWidth, AddrWidth, SourceWidth, SinkWidth, device)
);

  for (genvar i=0; i < NumLinks; i++) begin
    tl_assert #(
      .Protocol (TL_C),
      .EndpointType ("Host"),
      .AddrWidth (AddrWidth),
      .DataWidth (DataWidth),
      .SinkWidth (SinkWidth),
      .SourceWidth (SourceWidth)
    ) host_checker (
      .clk_i,
      .rst_ni,
      `TL_FORWARD_TAP_PORT_IDX(tl, host, [i])
    );
  end

  tl_assert #(
    .Protocol (TL_C),
    .EndpointType ("Device"),
    .AddrWidth (AddrWidth),
    .DataWidth (DataWidth),
    .SinkWidth (SinkWidth),
    .SourceWidth (SourceWidth)
  ) device_checker (
    .clk_i,
    .rst_ni,
    `TL_FORWARD_TAP_PORT(tl, device)
  );

endmodule


module tl_terminator_checker import tl_pkg::*; #(
    parameter int unsigned AddrWidth,
    parameter int unsigned DataWidth,
    parameter int unsigned HostSourceWidth,
    parameter int unsigned DeviceSourceWidth,
    parameter int unsigned HostSinkWidth
) (
  input logic clk_i,
  input logic rst_ni,

  `TL_DECLARE_TAP_PORT(DataWidth, AddrWidth, HostSourceWidth, HostSinkWidth, host),
  `TL_DECLARE_TAP_PORT(DataWidth, AddrWidth, DeviceSourceWidth, 1, device)
);

  tl_assert #(
    .Protocol (TL_C),
    .EndpointType ("Host"),
    .AddrWidth (AddrWidth),
    .DataWidth (DataWidth),
    .SinkWidth (HostSinkWidth),
    .SourceWidth (HostSourceWidth)
  ) host_checker (
    .clk_i,
    .rst_ni,
    `TL_FORWARD_TAP_PORT(tl, host)
  );

  tl_assert #(
    .Protocol (TL_UH),
    .EndpointType ("Device"),
    .AddrWidth (AddrWidth),
    .DataWidth (DataWidth),
    .SinkWidth (1),
    .SourceWidth (DeviceSourceWidth)
  ) device_checker (
    .clk_i,
    .rst_ni,
    `TL_FORWARD_TAP_PORT(tl, device)
  );

endmodule
