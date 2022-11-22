`include "tl_util.svh"

// An adapter that joins two TileLink links with different parameters.
module tl_adapter import tl_pkg::*; #(
  parameter  int unsigned DataWidth   = 64,
  parameter  int unsigned AddrWidth   = 56,
  parameter  int unsigned SinkWidth   = 1,
  parameter  int unsigned SourceWidth = 2,
  parameter  int unsigned MaxSize     = 6,
  parameter  bit          Fifo        = 1'b0,

  parameter  int unsigned HostDataWidth     = DataWidth,
  parameter  int unsigned DeviceDataWidth   = DataWidth,
  parameter  int unsigned HostAddrWidth     = AddrWidth,
  parameter  int unsigned DeviceAddrWidth   = AddrWidth,
  parameter  int unsigned HostSinkWidth     = SinkWidth,
  parameter  int unsigned DeviceSinkWidth   = SinkWidth,
  parameter  int unsigned HostSourceWidth   = SourceWidth,
  parameter  int unsigned DeviceSourceWidth = SourceWidth,
  parameter  int unsigned HostMaxSize       = MaxSize,
  parameter  int unsigned DeviceMaxSize     = MaxSize,

  parameter  bit HostFifo   = Fifo,
  parameter  bit DeviceFifo = Fifo
) (
  input  logic       clk_i,
  input  logic       rst_ni,

  `TL_DECLARE_DEVICE_PORT(HostDataWidth, HostAddrWidth, HostSourceWidth, HostSinkWidth, host),
  `TL_DECLARE_HOST_PORT(DeviceDataWidth, DeviceAddrWidth, DeviceSourceWidth, DeviceSinkWidth, device)
);

  localparam DataCvtSourceWidth =
      HostDataWidth >= DeviceDataWidth ? HostSourceWidth : HostSourceWidth + $clog2(DeviceDataWidth / HostDataWidth);
  `TL_DECLARE(DeviceDataWidth, HostAddrWidth, DataCvtSourceWidth, HostSinkWidth, data_cvt);

  if (HostDataWidth > DeviceDataWidth) begin: data_downsize
    tl_data_downsizer #(
      .HostDataWidth (HostDataWidth),
      .DeviceDataWidth (DeviceDataWidth),
      .AddrWidth (HostAddrWidth),
      .SourceWidth (DataCvtSourceWidth),
      .SinkWidth (HostSinkWidth),
      .MaxSize (HostMaxSize)
    ) data_downsizer (
      .clk_i,
      .rst_ni,
      `TL_FORWARD_DEVICE_PORT(host, host),
      `TL_CONNECT_HOST_PORT(device, data_cvt)
    );
  end else if (HostDataWidth < DeviceDataWidth) begin: data_upsize
    tl_data_upsizer #(
      .HostDataWidth (HostDataWidth),
      .DeviceDataWidth (DeviceDataWidth),
      .AddrWidth (HostAddrWidth),
      .HostSourceWidth (HostSourceWidth),
      .DeviceSourceWidth (DataCvtSourceWidth),
      .SinkWidth (HostSinkWidth),
      .MaxSize (HostMaxSize)
    ) data_downsizer (
      .clk_i,
      .rst_ni,
      `TL_FORWARD_DEVICE_PORT(host, host),
      `TL_CONNECT_HOST_PORT(device, data_cvt)
    );
  end else begin: data_keep
    `TL_BIND_DEVICE_PORT(host, data_cvt);
  end

  localparam SizeCvtSoruceWidth =
      HostMaxSize > DeviceMaxSize ? DataCvtSourceWidth + HostMaxSize - DeviceMaxSize : DataCvtSourceWidth;
  `TL_DECLARE(DeviceDataWidth, HostAddrWidth, SizeCvtSoruceWidth, HostSinkWidth, size_cvt);

  if (HostMaxSize > DeviceMaxSize) begin: size_downsize
    tl_size_downsizer #(
      .DataWidth (DeviceDataWidth),
      .AddrWidth (HostAddrWidth),
      .HostSourceWidth (DataCvtSourceWidth),
      .DeviceSourceWidth (SizeCvtSoruceWidth),
      .SinkWidth (HostSinkWidth),
      .HostMaxSize (HostMaxSize),
      .DeviceMaxSize (DeviceMaxSize)
    ) size_downsizer (
      .clk_i,
      .rst_ni,
      `TL_CONNECT_DEVICE_PORT(host, data_cvt),
      `TL_CONNECT_HOST_PORT(device, size_cvt)
    );
  end else begin: size_keep
    assign data_cvt_a_ready = size_cvt_a_ready;
    assign size_cvt_a_valid = data_cvt_a_valid;
    assign size_cvt_a       = data_cvt_a      ;
    assign size_cvt_b_ready = data_cvt_b_ready;
    assign data_cvt_b_valid = size_cvt_b_valid;
    assign data_cvt_b       = size_cvt_b      ;
    assign data_cvt_c_ready = size_cvt_c_ready;
    assign size_cvt_c_valid = data_cvt_c_valid;
    assign size_cvt_c       = data_cvt_c      ;
    assign size_cvt_d_ready = data_cvt_d_ready;
    assign data_cvt_d_valid = size_cvt_d_valid;
    assign data_cvt_d       = size_cvt_d      ;
    assign data_cvt_e_ready = size_cvt_e_ready;
    assign size_cvt_e_valid = data_cvt_e_valid;
    assign size_cvt_e       = data_cvt_e      ;
  end

  `TL_DECLARE(DeviceDataWidth, HostAddrWidth, DeviceSourceWidth, HostSinkWidth, source_cvt);

  if ((HostFifo || HostMaxSize > DeviceMaxSize) && !DeviceFifo) begin: source_fifo
    tl_fifo_converter #(
      .DataWidth (DeviceDataWidth),
      .AddrWidth (HostAddrWidth),
      .HostSourceWidth (SizeCvtSoruceWidth),
      .DeviceSourceWidth (DeviceSourceWidth),
      .SinkWidth (HostSinkWidth),
      .MaxSize (DeviceMaxSize)
    ) data_downsizer (
      .clk_i,
      .rst_ni,
      `TL_CONNECT_DEVICE_PORT(host, size_cvt),
      `TL_CONNECT_HOST_PORT(device, source_cvt)
    );
  end else if (SizeCvtSoruceWidth > DeviceSourceWidth) begin: source_downsize
    tl_source_downsizer #(
      .DataWidth (DeviceDataWidth),
      .AddrWidth (HostAddrWidth),
      .HostSourceWidth (SizeCvtSoruceWidth),
      .DeviceSourceWidth (DeviceSourceWidth),
      .SinkWidth (HostSinkWidth),
      .MaxSize (DeviceMaxSize)
    ) data_downsizer (
      .clk_i,
      .rst_ni,
      `TL_CONNECT_DEVICE_PORT(host, size_cvt),
      `TL_CONNECT_HOST_PORT(device, source_cvt)
    );
  end else begin: source_keep
    assign size_cvt_a_ready     = source_cvt_a_ready;
    assign source_cvt_a_valid   = size_cvt_a_valid;
    assign source_cvt_a.opcode  = size_cvt_a.opcode;
    assign source_cvt_a.param   = size_cvt_a.param;
    assign source_cvt_a.size    = size_cvt_a.size;
    assign source_cvt_a.source  = size_cvt_a.source;
    assign source_cvt_a.address = size_cvt_a.address;
    assign source_cvt_a.mask    = size_cvt_a.mask;
    assign source_cvt_a.corrupt = size_cvt_a.corrupt;
    assign source_cvt_a.data    = size_cvt_a.data;

    assign source_cvt_b_ready = size_cvt_b_ready;
    assign size_cvt_b_valid   = source_cvt_b_valid;
    assign size_cvt_b.opcode  = source_cvt_b.opcode;
    assign size_cvt_b.param   = source_cvt_b.param;
    assign size_cvt_b.size    = source_cvt_b.size;
    assign size_cvt_b.source  = source_cvt_b.source;
    assign size_cvt_b.address = source_cvt_b.address;

    assign size_cvt_c_ready     = source_cvt_c_ready;
    assign source_cvt_c_valid   = size_cvt_c_valid;
    assign source_cvt_c.opcode  = size_cvt_c.opcode;
    assign source_cvt_c.param   = size_cvt_c.param;
    assign source_cvt_c.size    = size_cvt_c.size;
    assign source_cvt_c.source  = size_cvt_c.source;
    assign source_cvt_c.address = size_cvt_c.address;
    assign source_cvt_c.corrupt = size_cvt_c.corrupt;
    assign source_cvt_c.data    = size_cvt_c.data;

    assign source_cvt_d_ready = size_cvt_d_ready;
    assign size_cvt_d_valid   = source_cvt_d_valid;
    assign size_cvt_d.opcode  = source_cvt_d.opcode;
    assign size_cvt_d.param   = source_cvt_d.param;
    assign size_cvt_d.size    = source_cvt_d.size;
    assign size_cvt_d.source  = source_cvt_d.source;
    assign size_cvt_d.sink    = source_cvt_d.sink;
    assign size_cvt_d.denied  = source_cvt_d.denied;
    assign size_cvt_d.corrupt = source_cvt_d.corrupt;
    assign size_cvt_d.data    = source_cvt_d.data;

    assign size_cvt_e_ready   = source_cvt_e_ready;
    assign source_cvt_e_valid = size_cvt_e_valid;
    assign source_cvt_e.sink  = size_cvt_e.sink;
  end

  `TL_DECLARE(DeviceDataWidth, HostAddrWidth, DeviceSourceWidth, DeviceSinkWidth, sink_cvt);

  if (HostSinkWidth < DeviceSinkWidth) begin: sink_upsize
    tl_sink_upsizer #(
      .DataWidth (DeviceDataWidth),
      .AddrWidth (HostAddrWidth),
      .SourceWidth (DeviceSourceWidth),
      .HostSinkWidth (HostSinkWidth),
      .DeviceSinkWidth (DeviceSinkWidth),
      .MaxSize (DeviceMaxSize)
    ) data_downsizer (
      .clk_i,
      .rst_ni,
      `TL_CONNECT_DEVICE_PORT(host, source_cvt),
      `TL_CONNECT_HOST_PORT(device, sink_cvt)
    );
  end else begin: sink_keep
    assign source_cvt_a_ready = sink_cvt_a_ready;
    assign sink_cvt_a_valid   = source_cvt_a_valid;
    assign sink_cvt_a.opcode  = source_cvt_a.opcode;
    assign sink_cvt_a.param   = source_cvt_a.param;
    assign sink_cvt_a.size    = source_cvt_a.size;
    assign sink_cvt_a.source  = source_cvt_a.source;
    assign sink_cvt_a.address = source_cvt_a.address;
    assign sink_cvt_a.mask    = source_cvt_a.mask;
    assign sink_cvt_a.corrupt = source_cvt_a.corrupt;
    assign sink_cvt_a.data    = source_cvt_a.data;

    assign sink_cvt_b_ready     = source_cvt_b_ready;
    assign source_cvt_b_valid   = sink_cvt_b_valid;
    assign source_cvt_b.opcode  = sink_cvt_b.opcode;
    assign source_cvt_b.param   = sink_cvt_b.param;
    assign source_cvt_b.size    = sink_cvt_b.size;
    assign source_cvt_b.source  = sink_cvt_b.source;
    assign source_cvt_b.address = sink_cvt_b.address;

    assign source_cvt_c_ready = sink_cvt_c_ready;
    assign sink_cvt_c_valid   = source_cvt_c_valid;
    assign sink_cvt_c.opcode  = source_cvt_c.opcode;
    assign sink_cvt_c.param   = source_cvt_c.param;
    assign sink_cvt_c.size    = source_cvt_c.size;
    assign sink_cvt_c.source  = source_cvt_c.source;
    assign sink_cvt_c.address = source_cvt_c.address;
    assign sink_cvt_c.corrupt = source_cvt_c.corrupt;
    assign sink_cvt_c.data    = source_cvt_c.data;

    assign sink_cvt_d_ready     = source_cvt_d_ready;
    assign source_cvt_d_valid   = sink_cvt_d_valid;
    assign source_cvt_d.opcode  = sink_cvt_d.opcode;
    assign source_cvt_d.param   = sink_cvt_d.param;
    assign source_cvt_d.size    = sink_cvt_d.size;
    assign source_cvt_d.source  = sink_cvt_d.source;
    assign source_cvt_d.sink    = sink_cvt_d.sink;
    assign source_cvt_d.denied  = sink_cvt_d.denied;
    assign source_cvt_d.corrupt = sink_cvt_d.corrupt;
    assign source_cvt_d.data    = sink_cvt_d.data;

    assign source_cvt_e_ready = sink_cvt_e_ready;
    assign sink_cvt_e_valid   = source_cvt_e_valid;
    assign sink_cvt_e.sink    = source_cvt_e.sink;
  end

  `TL_DECLARE(DeviceDataWidth, DeviceAddrWidth, DeviceSourceWidth, DeviceSinkWidth, device);
  `TL_BIND_HOST_PORT(device, device);

  assign sink_cvt_a_ready = device_a_ready;
  assign device_a_valid   = sink_cvt_a_valid;
  assign device_a.opcode  = sink_cvt_a.opcode;
  assign device_a.param   = sink_cvt_a.param;
  assign device_a.size    = sink_cvt_a.size;
  assign device_a.source  = sink_cvt_a.source;
  assign device_a.address = sink_cvt_a.address;
  assign device_a.mask    = sink_cvt_a.mask;
  assign device_a.corrupt = sink_cvt_a.corrupt;
  assign device_a.data    = sink_cvt_a.data;

  assign device_b_ready     = sink_cvt_b_ready;
  assign sink_cvt_b_valid   = device_b_valid;
  assign sink_cvt_b.opcode  = device_b.opcode;
  assign sink_cvt_b.param   = device_b.param;
  assign sink_cvt_b.size    = device_b.size;
  assign sink_cvt_b.source  = device_b.source;
  assign sink_cvt_b.address = device_b.address;

  assign sink_cvt_c_ready = device_c_ready;
  assign device_c_valid   = sink_cvt_c_valid;
  assign device_c.opcode  = sink_cvt_c.opcode;
  assign device_c.param   = sink_cvt_c.param;
  assign device_c.size    = sink_cvt_c.size;
  assign device_c.source  = sink_cvt_c.source;
  assign device_c.address = sink_cvt_c.address;
  assign device_c.corrupt = sink_cvt_c.corrupt;
  assign device_c.data    = sink_cvt_c.data;

  assign device_d_ready     = sink_cvt_d_ready;
  assign sink_cvt_d_valid   = device_d_valid;
  assign sink_cvt_d.opcode  = device_d.opcode;
  assign sink_cvt_d.param   = device_d.param;
  assign sink_cvt_d.size    = device_d.size;
  assign sink_cvt_d.source  = device_d.source;
  assign sink_cvt_d.sink    = device_d.sink;
  assign sink_cvt_d.denied  = device_d.denied;
  assign sink_cvt_d.corrupt = device_d.corrupt;
  assign sink_cvt_d.data    = device_d.data;

  assign sink_cvt_e_ready = device_e_ready;
  assign device_e_valid   = sink_cvt_e_valid;
  assign device_e.sink    = sink_cvt_e.sink;

endmodule
