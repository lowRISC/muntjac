`include "tl_util.svh"

// An adpater that shrinks DataWidth.
module tl_data_downsizer import tl_pkg::*; import prim_util_pkg::*; #(
  parameter  int unsigned HostDataWidth   = 64,
  parameter  int unsigned DeviceDataWidth = 32,
  parameter  int unsigned AddrWidth   = 56,
  parameter  int unsigned SourceWidth = 1,
  parameter  int unsigned SinkWidth   = 1,
  parameter  int unsigned MaxSize     = 6
) (
  input  logic       clk_i,
  input  logic       rst_ni,

  `TL_DECLARE_DEVICE_PORT(HostDataWidth, AddrWidth, SourceWidth, SinkWidth, host),
  `TL_DECLARE_HOST_PORT(DeviceDataWidth, AddrWidth, SourceWidth, SinkWidth, device)
);

  if (HostDataWidth <= DeviceDataWidth) $fatal(1, "Unexpected DataWidth");

  localparam int unsigned HostDataWidthInBytes = HostDataWidth / 8;
  localparam int unsigned HostNonBurstSize = $clog2(HostDataWidthInBytes);

  localparam int unsigned DeviceDataWidthInBytes = DeviceDataWidth / 8;
  localparam int unsigned DeviceNonBurstSize = $clog2(DeviceDataWidthInBytes);
  localparam int unsigned DeviceMaxBurstLen = 2 ** (MaxSize - DeviceNonBurstSize);
  localparam int unsigned DeviceBurstLenWidth = vbits(DeviceMaxBurstLen);

  localparam int unsigned SubbeatNum = HostDataWidth / DeviceDataWidth;
  localparam int unsigned SubbeatBits = HostNonBurstSize - DeviceNonBurstSize;

  `TL_DECLARE(HostDataWidth, AddrWidth, SourceWidth, SinkWidth, host);
  `TL_DECLARE(DeviceDataWidth, AddrWidth, SourceWidth, SinkWidth, device);
  `TL_BIND_HOST_PORT(device, device);

  tl_regslice #(
    .DataWidth (HostDataWidth),
    .AddrWidth (AddrWidth),
    .SourceWidth (SourceWidth),
    .SinkWidth (SinkWidth),
    .RequestMode (2),
    .ReleaseMode (2)
  ) host_reg (
    .clk_i,
    .rst_ni,
    `TL_FORWARD_DEVICE_PORT(host, host),
    `TL_CONNECT_HOST_PORT(device, host)
  );

  /////////////////////////////////
  // Burst tracker instantiation //
  /////////////////////////////////

  logic [DeviceBurstLenWidth-1:0] device_a_idx;
  logic [DeviceBurstLenWidth-1:0] device_a_left;
  logic [DeviceBurstLenWidth-1:0] device_c_idx;
  logic [DeviceBurstLenWidth-1:0] device_c_left;
  logic [DeviceBurstLenWidth-1:0] device_d_len;
  logic [DeviceBurstLenWidth-1:0] device_d_idx;
  logic [DeviceBurstLenWidth-1:0] device_d_left;

  tl_burst_tracker #(
    .DataWidth (DeviceDataWidth),
    .AddrWidth (AddrWidth),
    .SourceWidth (SourceWidth),
    .SinkWidth (SinkWidth),
    .MaxSize (MaxSize)
  ) device_burst_tracker (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_TAP_PORT(link, device),
    .req_len_o (),
    .rel_len_o (),
    .gnt_len_o (device_d_len),
    .req_idx_o (device_a_idx),
    .rel_idx_o (device_c_idx),
    .gnt_idx_o (device_d_idx),
    .req_left_o (device_a_left),
    .rel_left_o (device_c_left),
    .gnt_left_o (device_d_left),
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

  // We break a beat in host into multiple subbeats in device, so we need to track the index of
  // the current subbeat in a host beat and how many subbeats are left.
  // We can simply utilise the device_a_idx and device_a_left provided by the burst tracker and only
  // use the LSBs.
  // If the transfer size is smaller than DeviceNonBurstSize this break up will not happen. Luckily
  // in this case we still get correct a_subbeat_{idx, left} because device_a_{idx, left} are all 0.
  wire [SubbeatBits-1:0] a_subbeat_idx = device_a_idx[SubbeatBits-1:0];
  wire [SubbeatBits-1:0] a_subbeat_left = device_a_left[SubbeatBits-1:0];

  // Unpack mask and data signals to correct width.
  wire [SubbeatNum-1:0][DeviceDataWidth-1:0] a_data_split = host_a.data;
  wire [SubbeatNum-1:0][DeviceDataWidthInBytes-1:0] a_mask_split = host_a.mask;

  // Index into the unpacked mask/data calculated base on address.
  // This is the starting index of the first subbeat.
  wire [SubbeatBits-1:0] a_address_idx = host_a.address[HostNonBurstSize-1:DeviceNonBurstSize];
  // The aggregated index. Logically this is a_address_idx + a_subbeat_idx, but since all transfers are aligned
  // in TileLink we can use OR instead of ADD.
  wire [SubbeatBits-1:0] a_idx = a_address_idx | a_subbeat_idx;

  // Wire channels up, only consume a host beat when this is the last subbeat.
  // The logic here makes use of content in host_a before we assert host_a_ready, so A channel must be
  // for the module to expose correct TileLink behaviour.
  assign host_a_ready     = device_a_ready && host_a_valid && a_subbeat_left == 0;
  assign device_a_valid   = host_a_valid;
  assign device_a.opcode  = host_a.opcode;
  assign device_a.param   = host_a.param;
  assign device_a.size    = host_a.size;
  assign device_a.source  = host_a.source;
  assign device_a.address = host_a.address;
  assign device_a.mask    = a_mask_split[a_idx];
  assign device_a.corrupt = host_a.corrupt;
  assign device_a.data    = a_data_split[a_idx];

  //////////////////////////
  // B channel conversion //
  //////////////////////////

  assign device_b_ready = host_b_ready;
  assign host_b_valid   = device_b_valid;
  assign host_b.opcode  = device_b.opcode;
  assign host_b.param   = device_b.param;
  assign host_b.size    = device_b.size;
  assign host_b.source  = device_b.source;
  assign host_b.address = device_b.address;

  //////////////////////////
  // C channel conversion //
  //////////////////////////

  // Similar to A channel.
  wire [SubbeatBits-1:0] c_subbeat_idx = device_c_idx[SubbeatBits-1:0];
  wire [SubbeatBits-1:0] c_subbeat_left = device_c_left[SubbeatBits-1:0];

  wire [SubbeatNum-1:0][DeviceDataWidth-1:0] c_data_split = host_c.data;

  wire [SubbeatBits-1:0] c_address_idx = host_c.address[HostNonBurstSize-1:DeviceNonBurstSize];
  wire [SubbeatBits-1:0] c_idx = c_address_idx | c_subbeat_idx;

  assign host_c_ready     = device_c_ready && host_c_valid && c_subbeat_left == 0;
  assign device_c_valid   = host_c_valid;
  assign device_c.opcode  = host_c.opcode;
  assign device_c.param   = host_c.param;
  assign device_c.size    = host_c.size;
  assign device_c.source  = host_c.source;
  assign device_c.address = host_c.address;
  assign device_c.corrupt = host_c.corrupt;
  assign device_c.data    = c_data_split[c_idx];

  //////////////////////////
  // D channel conversion //
  //////////////////////////

  wire [SubbeatBits-1:0] d_subbeat_len = device_d_len[SubbeatBits-1:0];
  wire [SubbeatBits-1:0] d_subbeat_idx = device_d_idx[SubbeatBits-1:0];
  wire [SubbeatBits-1:0] d_subbeat_left = device_d_left[SubbeatBits-1:0];

  // Both d_data_q and d_data_d contain (SubbeatNum - 1) beats. We don't need to store
  // the most significant subbeat because it is always the last subbeat, so we can just
  // use device_d.data.
  logic [SubbeatNum-2:0][DeviceDataWidth-1:0] d_data_q, d_data_d;
  logic d_corrupt_q, d_corrupt_d;

  always_comb begin
    d_data_d = d_data_q;
    d_corrupt_d = d_corrupt_q;

    for (int i = 0; i < SubbeatNum - 1; i++) begin
      // For transfers smaller than HostDataWidth, we need to "tile" data to fill the entire
      // HostDataWidth to ensure that the host can retrieve the data correctly regardless the
      // LSBs of request address (Tiling them will allow this module to be stateless).
      // To "tile" correctly regardless the size, we need i % device_d_len == d_subbeat_idx,
      // and d_subbeat_len is just that device_d_len minus 1 in this case.
      //
      // When transfers are greater than or equal to HostDataWidth, this ought just be i == d_subbeat_idx,
      // which is also okay becasue d_subbeat_len will be all 1 in this case.
      if ((i & d_subbeat_len) == d_subbeat_idx) begin
        d_data_d[i] = device_d.data;
      end
    end

    // If any subbeat is corrupted, the whole combined beat is.
    if (device_d.corrupt) begin
      d_corrupt_d = 1'b1;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      d_data_q <= 'x;
      d_corrupt_q <= 1'b0;
    end else begin
      if (device_d_valid && device_d_ready) begin
        d_data_q <= d_data_d;
        d_corrupt_q <= d_corrupt_d;

        // Reset to default state after last beat.
        if (d_subbeat_left == 0) begin
          d_data_q <= 'x;
          d_corrupt_q <= 1'b0;
        end
      end
    end
  end

  // Wire channels up, only forward the last subbeat and consume all subbeats that not.
  assign device_d_ready = device_d_valid && d_subbeat_left == 0 ? host_d_ready : 1'b1;
  assign host_d_valid   = device_d_valid && d_subbeat_left == 0;
  assign host_d.opcode  = device_d.opcode;
  assign host_d.param   = device_d.param;
  assign host_d.size    = device_d.size;
  assign host_d.source  = device_d.source;
  assign host_d.sink    = device_d.sink;
  assign host_d.denied  = device_d.denied;
  assign host_d.corrupt = d_corrupt_d;
  assign host_d.data    = {device_d.data, d_data_d};

  //////////////////////////
  // E channel connection //
  //////////////////////////

  assign host_e_ready   = device_e_ready;
  assign device_e_valid = host_e_valid;
  assign device_e.sink  = host_e.sink;

endmodule
