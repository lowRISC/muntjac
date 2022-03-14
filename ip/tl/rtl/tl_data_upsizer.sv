`include "tl_util.svh"

// An adpater that expands DataWidth.
// This module performs sideband communication using source, so it increases SourceWidth.
module tl_data_upsizer import tl_pkg::*; import prim_util_pkg::*; #(
  parameter  int unsigned HostDataWidth   = 32,
  parameter  int unsigned DeviceDataWidth = 64,
  parameter  int unsigned AddrWidth   = 56,
  parameter  int unsigned HostSourceWidth   = 1,
  parameter  int unsigned DeviceSourceWidth = 2,
  parameter  int unsigned SinkWidth   = 1,
  parameter  int unsigned MaxSize     = 6
) (
  input  logic       clk_i,
  input  logic       rst_ni,

  `TL_DECLARE_DEVICE_PORT(HostDataWidth, AddrWidth, HostSourceWidth, SinkWidth, host),
  `TL_DECLARE_HOST_PORT(DeviceDataWidth, AddrWidth, DeviceSourceWidth, SinkWidth, device)
);

  if (HostDataWidth >= DeviceDataWidth) $fatal(1, "Unexpected DataWidth");

  localparam int unsigned HostDataWidthInBytes = HostDataWidth / 8;
  localparam int unsigned HostNonBurstSize = $clog2(HostDataWidthInBytes);
  localparam int unsigned HostMaxBurstLen = 2 ** (MaxSize - HostNonBurstSize);
  localparam int unsigned HostBurstLenWidth = vbits(HostMaxBurstLen);

  localparam int unsigned DeviceDataWidthInBytes = DeviceDataWidth / 8;
  localparam int unsigned DeviceNonBurstSize = $clog2(DeviceDataWidthInBytes);

  localparam int unsigned SubbeatNum = DeviceDataWidth / HostDataWidth;
  localparam int unsigned SubbeatBits = DeviceNonBurstSize - HostNonBurstSize;

  if (HostSourceWidth + SubbeatBits > DeviceSourceWidth) $fatal(1, "DeviceSourceWidth bits not enough");

  `TL_DECLARE(HostDataWidth, AddrWidth, HostSourceWidth, SinkWidth, host);
  `TL_DECLARE(DeviceDataWidth, AddrWidth, DeviceSourceWidth, SinkWidth, device);
  `TL_BIND_DEVICE_PORT(host, host);

  tl_regslice #(
    .AddrWidth (AddrWidth),
    .DataWidth (DeviceDataWidth),
    .SourceWidth (DeviceSourceWidth),
    .SinkWidth (SinkWidth),
    .GrantMode (2)
  ) device_reg (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_DEVICE_PORT(host, device),
    `TL_FORWARD_HOST_PORT(device, device)
  );

  function automatic logic [DeviceDataWidthInBytes-1:0] get_mask(
    input logic [DeviceNonBurstSize-1:0] address,
    input logic [`TL_SIZE_WIDTH-1:0] size
  );
    logic [`TL_SIZE_WIDTH-1:0] capped_size;
    capped_size = size >= DeviceNonBurstSize ? DeviceNonBurstSize : size;

    get_mask = 1;
    for (int i = 1; i <= DeviceNonBurstSize; i++) begin
      if (capped_size == i) begin
        // In this case the mask computed should be all 1
        get_mask = (1 << (2**i)) - 1;
      end else begin
        // In this case the mask is computed from existing mask shifted according to address
        if (address[i - 1]) begin
          get_mask = get_mask << (2**(i-1));
        end else begin
          get_mask = get_mask;
        end
      end
    end
  endfunction

  /////////////////////////////////
  // Burst tracker instantiation //
  /////////////////////////////////

  logic [HostBurstLenWidth-1:0] host_a_len;
  logic [HostBurstLenWidth-1:0] host_a_idx;
  logic [HostBurstLenWidth-1:0] host_a_left;
  logic [HostBurstLenWidth-1:0] host_c_len;
  logic [HostBurstLenWidth-1:0] host_c_idx;
  logic [HostBurstLenWidth-1:0] host_c_left;
  logic [HostBurstLenWidth-1:0] host_d_idx;
  logic [HostBurstLenWidth-1:0] host_d_left;

  tl_burst_tracker #(
    .DataWidth (HostDataWidth),
    .AddrWidth (AddrWidth),
    .SourceWidth (HostSourceWidth),
    .SinkWidth (SinkWidth),
    .MaxSize (MaxSize)
  ) host_burst_tracker (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_TAP_PORT(link, host),
    .req_len_o (host_a_len),
    .rel_len_o (host_c_len),
    .gnt_len_o (),
    .req_idx_o (host_a_idx),
    .rel_idx_o (host_c_idx),
    .gnt_idx_o (host_d_idx),
    .req_left_o (host_a_left),
    .rel_left_o (host_c_left),
    .gnt_left_o (host_d_left),
    .req_first_o (),
    .rel_first_o (),
    .gnt_first_o (),
    .req_last_o (),
    .rel_last_o (),
    .gnt_last_o ()
  );

  //////////////////////////
  // A channel conversion //
  //////////////////////////

  // Similar to downsizer's D channel.
  wire [SubbeatBits-1:0] a_subbeat_len = host_a_len[SubbeatBits-1:0];
  wire [SubbeatBits-1:0] a_subbeat_idx = host_a_idx[SubbeatBits-1:0];
  wire [SubbeatBits-1:0] a_subbeat_left = host_a_left[SubbeatBits-1:0];

  logic [SubbeatNum-2:0][HostDataWidth-1:0] a_data_q, a_data_d;
  logic [SubbeatNum-2:0][HostDataWidthInBytes-1:0] a_mask_q, a_mask_d;
  logic a_corrupt_q, a_corrupt_d;

  always_comb begin
    a_data_d = a_data_q;
    a_mask_d = a_mask_q;
    a_corrupt_d = a_corrupt_q;

    for (int i = 0; i < SubbeatNum - 1; i++) begin
      if ((i & a_subbeat_len) == a_subbeat_idx) begin
        a_data_d[i] = host_a.data;
        a_mask_d[i] = host_a.mask;
      end
    end

    if (host_a.corrupt) begin
      a_corrupt_d = 1'b1;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      a_data_q <= 'x;
      a_mask_q <= 'x;
      a_corrupt_q <= 1'b0;
    end else begin
      if (host_a_valid && host_a_ready) begin
        a_data_q <= a_data_d;
        a_mask_q <= a_mask_d;
        a_corrupt_q <= a_corrupt_d;

        if (a_subbeat_left == 0) begin
          a_data_q <= 'x;
          a_mask_q <= 'x;
          a_corrupt_q <= 1'b0;
        end
      end
    end
  end

  assign host_a_ready     = host_a_valid && a_subbeat_left == 0 ? device_a_ready : 1'b1;
  assign device_a_valid   = host_a_valid && a_subbeat_left == 0;
  assign device_a.opcode  = host_a.opcode;
  assign device_a.param   = host_a.param;
  assign device_a.size    = host_a.size;
  // Use source to carry sideband information to D channel handler.
  assign device_a.source  = {host_a.address[DeviceNonBurstSize-1:HostNonBurstSize], host_a.source};
  assign device_a.address = host_a.address;
  assign device_a.mask    = {host_a.mask, a_mask_d} & get_mask(host_a.address[DeviceNonBurstSize-1:0], host_a.size);
  assign device_a.corrupt = a_corrupt_d;
  assign device_a.data    = {host_a.data, a_data_d};

  //////////////////////////
  // B channel conversion //
  //////////////////////////

  assign device_b_ready = host_b_ready;
  assign host_b_valid   = device_b_valid;
  assign host_b.opcode  = device_b.opcode;
  assign host_b.param   = device_b.param;
  assign host_b.size    = device_b.size;
  assign host_b.source  = device_b.source[HostSourceWidth-1:0];
  assign host_b.address = device_b.address;

  //////////////////////////
  // C channel conversion //
  //////////////////////////

  // Similar to A channel.
  wire [SubbeatBits-1:0] c_subbeat_len = host_c_len[SubbeatBits-1:0];
  wire [SubbeatBits-1:0] c_subbeat_idx = host_c_idx[SubbeatBits-1:0];
  wire [SubbeatBits-1:0] c_subbeat_left = host_c_left[SubbeatBits-1:0];

  logic [SubbeatNum-2:0][HostDataWidth-1:0] c_data_q, c_data_d;
  logic c_corrupt_q, c_corrupt_d;

  always_comb begin
    c_data_d = c_data_q;
    c_corrupt_d = c_corrupt_q;

    for (int i = 0; i < SubbeatNum - 1; i++) begin
      if ((i & c_subbeat_len) == c_subbeat_idx) begin
        c_data_d[i] = host_c.data;
      end
    end

    if (host_c.corrupt) begin
      c_corrupt_d = 1'b1;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      c_data_q <= 'x;
      c_corrupt_q <= 1'b0;
    end else begin
      if (host_c_valid && host_c_ready) begin
        c_data_q <= c_data_d;
        c_corrupt_q <= c_corrupt_d;

        if (c_subbeat_left == 0) begin
          c_data_q <= 'x;
          c_corrupt_q <= 1'b0;
        end
      end
    end
  end

  assign host_c_ready     = host_c_valid && c_subbeat_left == 0 ? device_c_ready : 1'b1;
  assign device_c_valid   = host_c_valid && c_subbeat_left == 0;
  assign device_c.opcode  = host_c.opcode;
  assign device_c.param   = host_c.param;
  assign device_c.size    = host_c.size;
  assign device_c.source  = {host_c.address[DeviceNonBurstSize-1:HostNonBurstSize], host_c.source};
  assign device_c.address = host_c.address;
  assign device_c.corrupt = c_corrupt_d;
  assign device_c.data    = {host_c.data, c_data_d};

  //////////////////////////
  // D channel conversion //
  //////////////////////////

  // Similar to downsizer's A channel.
  wire [SubbeatBits-1:0] d_subbeat_idx = host_d_idx[SubbeatBits-1:0];
  wire [SubbeatBits-1:0] d_subbeat_left = host_d_left[SubbeatBits-1:0];

  wire [SubbeatNum-1:0][HostDataWidth-1:0] d_data_split = device_d.data;

  // The address bits needed is carried by MSBs of source as a sideband information.
  wire [SubbeatBits-1:0] d_address_idx = device_d.source[HostSourceWidth+:SubbeatBits];
  wire [SubbeatBits-1:0] d_idx = d_address_idx | d_subbeat_idx;

  assign device_d_ready = host_d_ready && device_d_valid && d_subbeat_left == 0;
  assign host_d_valid   = device_d_valid;
  assign host_d.opcode  = device_d.opcode;
  assign host_d.param   = device_d.param;
  assign host_d.size    = device_d.size;
  assign host_d.source  = device_d.source[HostSourceWidth-1:0];
  assign host_d.sink    = device_d.sink;
  assign host_d.denied  = device_d.denied;
  assign host_d.corrupt = device_d.corrupt;
  assign host_d.data    = d_data_split[d_idx];

  //////////////////////////
  // E channel connection //
  //////////////////////////

  assign host_e_ready   = device_e_ready;
  assign device_e_valid = host_e_valid;
  assign device_e.sink  = host_e.sink;

endmodule
