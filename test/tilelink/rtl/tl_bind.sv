// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

bind tl_adapter tl_adapter_checker #(
  .HostDataWidth (HostDataWidth),
  .DeviceDataWidth (DeviceDataWidth),
  .HostAddrWidth (HostAddrWidth),
  .DeviceAddrWidth (DeviceAddrWidth),
  .HostSinkWidth (HostSinkWidth),
  .DeviceSinkWidth (DeviceSinkWidth),
  .HostSourceWidth (HostSourceWidth),
  .DeviceSourceWidth (DeviceSourceWidth)
) assertions (
  .clk_i,
  .rst_ni,
  `TL_FORWARD_TAP_PORT_FROM_DEVICE(host, host),
  `TL_FORWARD_TAP_PORT_FROM_HOST(device, device)
);

bind tl_adapter_bram tl_adapter_bram_checker #(
  .AddrWidth (AddrWidth),
  .DataWidth (DataWidth),
  .SourceWidth (SourceWidth)
) assertions (
  .clk_i,
  .rst_ni,
  `TL_FORWARD_TAP_PORT_FROM_DEVICE(host, host)
);

bind tl_axi_adapter tl_axi_adapter_checker #(
  .AddrWidth (AddrWidth),
  .DataWidth (DataWidth),
  .SinkWidth (SinkWidth),
  .SourceWidth (SourceWidth)
) assertions (
  .clk_i,
  .rst_ni,
  `TL_FORWARD_TAP_PORT_FROM_DEVICE(host, host)
);

bind tl_broadcast tl_broadcast_checker #(
  .AddrWidth (AddrWidth),
  .DataWidth (DataWidth),
  .SinkWidth (SinkWidth),
  .HostSourceWidth (HostSourceWidth),
  .DeviceSourceWidth (DeviceSourceWidth)
) assertions (
  .clk_i,
  .rst_ni,
  `TL_FORWARD_TAP_PORT_FROM_DEVICE(host, host),
  `TL_FORWARD_TAP_PORT_FROM_HOST(device, device)
);

bind tl_data_downsizer tl_data_downsizer_checker #(
  .AddrWidth (AddrWidth),
  .HostDataWidth (HostDataWidth),
  .DeviceDataWidth (DeviceDataWidth),
  .SinkWidth (SinkWidth),
  .SourceWidth (SourceWidth)
) assertions (
  .clk_i,
  .rst_ni,
  `TL_FORWARD_TAP_PORT_FROM_DEVICE(host, host),
  `TL_FORWARD_TAP_PORT_FROM_HOST(device, device)
);

bind tl_data_upsizer tl_data_upsizer_checker #(
  .AddrWidth (AddrWidth),
  .HostDataWidth (HostDataWidth),
  .DeviceDataWidth (DeviceDataWidth),
  .SinkWidth (SinkWidth),
  .HostSourceWidth (HostSourceWidth),
  .DeviceSourceWidth (DeviceSourceWidth)
) assertions (
  .clk_i,
  .rst_ni,
  `TL_FORWARD_TAP_PORT_FROM_DEVICE(host, host),
  `TL_FORWARD_TAP_PORT_FROM_HOST(device, device)
);

bind tl_fifo_async tl_fifo_async_checker #(
  .AddrWidth (AddrWidth),
  .DataWidth (DataWidth),
  .SinkWidth (SinkWidth),
  .SourceWidth (SourceWidth)
) assertions (
  .clk_host_i,
  .rst_host_ni,
  `TL_FORWARD_TAP_PORT_FROM_DEVICE(host, host),
  .clk_device_i,
  .rst_device_ni,
  `TL_FORWARD_TAP_PORT_FROM_HOST(device, device)
);

bind tl_fifo_converter tl_fifo_converter_checker #(
  .AddrWidth (AddrWidth),
  .DataWidth (DataWidth),
  .SinkWidth (SinkWidth),
  .HostSourceWidth (HostSourceWidth),
  .DeviceSourceWidth (DeviceSourceWidth)
) assertions (
  .clk_i,
  .rst_ni,
  `TL_FORWARD_TAP_PORT_FROM_DEVICE(host, host),
  `TL_FORWARD_TAP_PORT_FROM_HOST(device, device)
);

bind tl_fifo_sync tl_fifo_sync_checker #(
  .AddrWidth (AddrWidth),
  .DataWidth (DataWidth),
  .SinkWidth (SinkWidth),
  .SourceWidth (SourceWidth)
) assertions (
  .clk_i,
  .rst_ni,
  `TL_FORWARD_TAP_PORT_FROM_DEVICE(host, host),
  `TL_FORWARD_TAP_PORT_FROM_HOST(device, device)
);

bind tl_regslice tl_regslice_checker #(
  .AddrWidth (AddrWidth),
  .DataWidth (DataWidth),
  .SinkWidth (SinkWidth),
  .SourceWidth (SourceWidth)
) assertions (
  .clk_i,
  .rst_ni,
  `TL_FORWARD_TAP_PORT_FROM_DEVICE(host, host),
  `TL_FORWARD_TAP_PORT_FROM_HOST(device, device)
);

bind tl_sink_upsizer tl_sink_upsizer_checker #(
  .AddrWidth (AddrWidth),
  .DataWidth (DataWidth),
  .HostSinkWidth (HostSinkWidth),
  .DeviceSinkWidth (DeviceSinkWidth),
  .SourceWidth (SourceWidth)
) assertions (
  .clk_i,
  .rst_ni,
  `TL_FORWARD_TAP_PORT_FROM_DEVICE(host, host),
  `TL_FORWARD_TAP_PORT_FROM_HOST(device, device)
);

bind tl_size_downsizer tl_size_downsizer_checker #(
  .AddrWidth (AddrWidth),
  .DataWidth (DataWidth),
  .SinkWidth (SinkWidth),
  .HostSourceWidth (HostSourceWidth),
  .DeviceSourceWidth (DeviceSourceWidth)
) assertions (
  .clk_i,
  .rst_ni,
  `TL_FORWARD_TAP_PORT_FROM_DEVICE(host, host),
  `TL_FORWARD_TAP_PORT_FROM_HOST(device, device)
);

bind tl_source_downsizer tl_source_downsizer_checker #(
  .AddrWidth (AddrWidth),
  .DataWidth (DataWidth),
  .SinkWidth (SinkWidth),
  .HostSourceWidth (HostSourceWidth),
  .DeviceSourceWidth (DeviceSourceWidth)
) assertions (
  .clk_i,
  .rst_ni,
  `TL_FORWARD_TAP_PORT_FROM_DEVICE(host, host),
  `TL_FORWARD_TAP_PORT_FROM_HOST(device, device)
);

bind tl_source_shifter tl_source_shifter_checker #(
  .AddrWidth (AddrWidth),
  .DataWidth (DataWidth),
  .SinkWidth (SinkWidth),
  .HostSourceWidth (HostSourceWidth),
  .DeviceSourceWidth (DeviceSourceWidth)
) assertions (
  .clk_i,
  .rst_ni,
  `TL_FORWARD_TAP_PORT_FROM_DEVICE(host, host),
  `TL_FORWARD_TAP_PORT_FROM_HOST(device, device)
);

bind tl_io_terminator tl_terminator_checker #(
  .AddrWidth (AddrWidth),
  .DataWidth (DataWidth),
  .HostSinkWidth (HostSinkWidth),
  .HostSourceWidth (SourceWidth),
  .DeviceSourceWidth (SourceWidth)
) assertions (
  .clk_i,
  .rst_ni,
  `TL_FORWARD_TAP_PORT_FROM_DEVICE(host, host),
  `TL_FORWARD_TAP_PORT_FROM_HOST(device, device)
);

bind tl_ram_terminator tl_terminator_checker #(
  .AddrWidth (AddrWidth),
  .DataWidth (DataWidth),
  .HostSinkWidth (HostSinkWidth),
  .HostSourceWidth (HostSourceWidth),
  .DeviceSourceWidth (DeviceSourceWidth)
) assertions (
  .clk_i,
  .rst_ni,
  `TL_FORWARD_TAP_PORT_FROM_DEVICE(host, host),
  `TL_FORWARD_TAP_PORT_FROM_HOST(device, device)
);

bind tl_rom_terminator tl_terminator_checker #(
  .AddrWidth (AddrWidth),
  .DataWidth (DataWidth),
  .HostSinkWidth (HostSinkWidth),
  .HostSourceWidth (HostSourceWidth),
  .DeviceSourceWidth (DeviceSourceWidth)
) assertions (
  .clk_i,
  .rst_ni,
  `TL_FORWARD_TAP_PORT_FROM_DEVICE(host, host),
  `TL_FORWARD_TAP_PORT_FROM_HOST(device, device)
);

bind tl_socket_1n tl_socket_1n_checker #(
  .AddrWidth (AddrWidth),
  .DataWidth (DataWidth),
  .SinkWidth (SinkWidth),
  .SourceWidth (SourceWidth),
  .NumLinks (NumLinks)
) assertions (
  .clk_i,
  .rst_ni,
  `TL_FORWARD_TAP_PORT_FROM_DEVICE(host, host),
  `TL_FORWARD_TAP_PORT_FROM_HOST(device, device)
);

bind tl_socket_m1 tl_socket_m1_checker #(
  .AddrWidth (AddrWidth),
  .DataWidth (DataWidth),
  .SinkWidth (SinkWidth),
  .SourceWidth (SourceWidth),
  .NumLinks (NumLinks)
) assertions (
  .clk_i,
  .rst_ni,
  `TL_FORWARD_TAP_PORT_FROM_DEVICE(host, host),
  `TL_FORWARD_TAP_PORT_FROM_HOST(device, device)
);
