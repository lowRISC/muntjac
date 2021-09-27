// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

bind tl_adapter tl_adapter_checker #(
  .HostDataWidth(HostDataWidth),
  .DeviceDataWidth(DeviceDataWidth),
  .HostAddrWidth(HostAddrWidth),
  .DeviceAddrWidth(DeviceAddrWidth),
  .HostSinkWidth(HostSinkWidth),
  .DeviceSinkWidth(DeviceSinkWidth),
  .HostSourceWidth(HostSourceWidth),
  .DeviceSourceWidth(DeviceSourceWidth)
) tl_adapter_assert (
  .clk_i,
  .rst_ni,
  `TL_FORWARD_TAP_PORT_FROM_DEVICE(host, host),
  `TL_FORWARD_TAP_PORT_FROM_HOST(device, device)
);

bind tl_adapter_bram tl_adapter_bram_checker #(
  .AddrWidth(AddrWidth),
  .DataWidth(DataWidth),
  .SinkWidth(SinkWidth),
  .SourceWidth(SourceWidth)
) tl_adapter_bram_assert (
  .clk_i,
  .rst_ni,
  `TL_FORWARD_TAP_PORT_FROM_DEVICE(host, host)
);

bind tl_axi_adapter tl_axi_adapter_checker #(
  .AddrWidth(AddrWidth),
  .DataWidth(DataWidth),
  .SinkWidth(SinkWidth),
  .SourceWidth(SourceWidth)
) tl_axi_adapter_assert (
  .clk_i,
  .rst_ni,
  `TL_FORWARD_TAP_PORT_FROM_DEVICE(host, host)
);

bind tl_broadcast tl_broadcast_checker #(
  .AddrWidth(AddrWidth),
  .DataWidth(DataWidth),
  .SinkWidth(SinkWidth),
  .SourceWidth(SourceWidth)
) tl_broadcast_assert (
  .clk_i,
  .rst_ni,
  `TL_FORWARD_TAP_PORT_FROM_DEVICE(host, host),
  `TL_FORWARD_TAP_PORT_FROM_HOST(device, device)
);

bind tl_io_terminator tl_terminator_checker #(
  .AddrWidth(AddrWidth),
  .DataWidth(DataWidth),
  .HostSinkWidth(HostSinkWidth),
  .HostSourceWidth(SourceWidth),
  .DeviceSourceWidth(SourceWidth)
) tl_io_terminator_assert (
  .clk_i,
  .rst_ni,
  `TL_FORWARD_TAP_PORT_FROM_DEVICE(host, host),
  `TL_FORWARD_TAP_PORT_FROM_HOST(device, device)
);

bind tl_ram_terminator tl_terminator_checker #(
  .AddrWidth(AddrWidth),
  .DataWidth(DataWidth),
  .HostSinkWidth(HostSinkWidth),
  .HostSourceWidth(HostSourceWidth),
  .DeviceSourceWidth(DeviceSourceWidth)
) tl_ram_terminator_assert (
  .clk_i,
  .rst_ni,
  `TL_FORWARD_TAP_PORT_FROM_DEVICE(host, host),
  `TL_FORWARD_TAP_PORT_FROM_HOST(device, device)
);

bind tl_rom_terminator tl_terminator_checker #(
  .AddrWidth(AddrWidth),
  .DataWidth(DataWidth),
  .HostSinkWidth(HostSinkWidth),
  .HostSourceWidth(HostSourceWidth),
  .DeviceSourceWidth(DeviceSourceWidth)
) tl_rom_terminator_assert (
  .clk_i,
  .rst_ni,
  `TL_FORWARD_TAP_PORT_FROM_DEVICE(host, host),
  `TL_FORWARD_TAP_PORT_FROM_HOST(device, device)
);

bind tl_socket_1n tl_socket_1n_checker #(
  .AddrWidth(AddrWidth),
  .DataWidth(DataWidth),
  .SinkWidth(SinkWidth),
  .SourceWidth(SourceWidth),
  .NumLinks(NumLinks)
) tl_socket_1n_assert (
  .clk_i,
  .rst_ni,
  `TL_FORWARD_TAP_PORT_FROM_DEVICE(host, host),
  `TL_FORWARD_TAP_PORT_FROM_HOST(device, device)
);

bind tl_socket_m1 tl_socket_m1_checker #(
  .AddrWidth(AddrWidth),
  .DataWidth(DataWidth),
  .SinkWidth(SinkWidth),
  .SourceWidth(SourceWidth),
  .NumLinks(NumLinks)
) tl_socket_m1_assert (
  .clk_i,
  .rst_ni,
  `TL_FORWARD_TAP_PORT_FROM_DEVICE(host, host),
  `TL_FORWARD_TAP_PORT_FROM_HOST(device, device)
);
