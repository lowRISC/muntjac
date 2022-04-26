// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

`include "tl_verilator.svh"
`include "parameters.svh"

module tl_wrapper #(
    // Defined externally.
    parameter int unsigned HostDataWidth     = `HostDataWidth,
    parameter int unsigned DeviceDataWidth   = `DeviceDataWidth,
    parameter int unsigned HostAddrWidth     = `HostAddrWidth,
    parameter int unsigned DeviceAddrWidth   = `DeviceAddrWidth,
    parameter int unsigned HostSourceWidth   = `HostSourceWidth,
    parameter int unsigned DeviceSourceWidth = `DeviceSourceWidth,
    parameter int unsigned HostSinkWidth     = `HostSinkWidth,
    parameter int unsigned DeviceSinkWidth   = `DeviceSinkWidth,
    parameter int unsigned HostMaxSize       = `HostMaxSize,
    parameter int unsigned DeviceMaxSize     = `DeviceMaxSize,
    parameter bit          HostFifo          = `HostFifo,
    parameter bit          DeviceFifo        = `DeviceFifo
) (
  input logic clk_i,
  input logic rst_ni,

  `TL_VERILATOR_HOST_PORT(HostDataWidth, HostAddrWidth, HostSourceWidth, HostSinkWidth, host),
  `TL_VERILATOR_DEVICE_PORT(DeviceDataWidth, DeviceAddrWidth, DeviceSourceWidth, DeviceSinkWidth, dev)
);

  `TL_DECLARE(HostDataWidth, HostAddrWidth, HostSourceWidth, HostSinkWidth, host_tl);
  `TL_DECLARE(DeviceDataWidth, DeviceAddrWidth, DeviceSourceWidth, DeviceSinkWidth, device_tl);

  `TL_VERILATOR_BIND_HOST_PORT(host, host_tl);
  `TL_VERILATOR_BIND_DEVICE_PORT(dev, device_tl);

  tl_adapter #(
    .HostDataWidth (HostDataWidth),
    .DeviceDataWidth (DeviceDataWidth),
    .HostAddrWidth (HostAddrWidth),
    .DeviceAddrWidth (DeviceAddrWidth),
    .HostSourceWidth (HostSourceWidth),
    .DeviceSourceWidth (DeviceSourceWidth),
    .HostSinkWidth (HostSinkWidth),
    .DeviceSinkWidth (DeviceSinkWidth),
    .HostMaxSize (HostMaxSize),
    .DeviceMaxSize (DeviceMaxSize),
    .HostFifo (HostFifo),
    .DeviceFifo (DeviceFifo)
  ) dut (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_DEVICE_PORT(host, host_tl),
    `TL_CONNECT_HOST_PORT(device, device_tl)
  );

endmodule
