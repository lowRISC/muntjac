`include "tl_util.svh"

// An adpater that shrinks MaxSize by fragmenting multi-beat bursts into multiple transactions.
//
// Requires device to reply in FIFO order.
module tl_size_downsizer import tl_pkg::*; #(
    parameter  int unsigned AddrWidth   = 56,
    parameter  int unsigned DataWidth   = 64,
    parameter  int unsigned SinkWidth   = 1,

    parameter  int unsigned HostSourceWidth = 1,
    parameter  int unsigned DeviceSourceWidth = 1,

    parameter  int unsigned HostMaxSize     = 6,
    parameter  int unsigned DeviceMaxSize   = $clog2(DataWidth / 8)
) (
  input  logic       clk_i,
  input  logic       rst_ni,

  `TL_DECLARE_DEVICE_PORT(DataWidth, AddrWidth, HostSourceWidth, SinkWidth, host),
  `TL_DECLARE_HOST_PORT(DataWidth, AddrWidth, DeviceSourceWidth, SinkWidth, device)
);

  localparam NumTracker = 2 ** HostSourceWidth;
  localparam FragmentWidth = HostMaxSize - DeviceMaxSize;
  localparam NumFragment = 2 ** FragmentWidth;

  // Check if parameters are well formed
  if (HostMaxSize <= DeviceMaxSize) $fatal(1, "Unexpected MaxSize");
  if (FragmentWidth + HostSourceWidth < DeviceSourceWidth) $fatal(1, "Not enough DeviceSourceWidth");

  `TL_DECLARE(DataWidth, AddrWidth, HostSourceWidth, SinkWidth, host);
  `TL_DECLARE(DataWidth, AddrWidth, DeviceSourceWidth, SinkWidth, device);
  `TL_BIND_DEVICE_PORT(host, host);

  tl_regslice #(
    .DataWidth (DataWidth),
    .AddrWidth (AddrWidth),
    .SourceWidth (DeviceSourceWidth),
    .SinkWidth (SinkWidth),
    .GrantMode (1)
  ) device_reg (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_DEVICE_PORT(host, device),
    `TL_FORWARD_HOST_PORT(device, device)
  );

  /////////////////////////////////
  // Burst tracker instantiation //
  /////////////////////////////////

  logic host_a_first;
  logic host_d_last;
  logic device_a_last;

  tl_burst_tracker #(
    .DataWidth (DataWidth),
    .AddrWidth (AddrWidth),
    .SourceWidth (HostSourceWidth),
    .SinkWidth (SinkWidth),
    .MaxSize (HostMaxSize)
  ) host_burst_tracker (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_TAP_PORT(link, host),
    .req_len_o (),
    .rel_len_o (),
    .gnt_len_o (),
    .req_idx_o (),
    .rel_idx_o (),
    .gnt_idx_o (),
    .req_left_o (),
    .rel_left_o (),
    .gnt_left_o (),
    .req_first_o (host_a_first),
    .rel_first_o (),
    .gnt_first_o (),
    .req_last_o (),
    .rel_last_o (),
    .gnt_last_o (host_d_last)
  );

  tl_burst_tracker #(
    .DataWidth (DataWidth),
    .AddrWidth (AddrWidth),
    .SourceWidth (DeviceSourceWidth),
    .SinkWidth (SinkWidth),
    .MaxSize (DeviceMaxSize)
  ) device_burst_tracker (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_TAP_PORT(link, device),
    .req_len_o (),
    .rel_len_o (),
    .gnt_len_o (),
    .req_idx_o (),
    .rel_idx_o (),
    .gnt_idx_o (),
    .req_left_o (),
    .rel_left_o (),
    .gnt_left_o (),
    .req_first_o (),
    .rel_first_o (),
    .gnt_first_o (),
    .req_last_o (device_a_last),
    .rel_last_o (),
    .gnt_last_o ()
  );

  /////////////////////
  // Unused channels //
  /////////////////////

  // We don't use channel B.
  assign host_b_valid = 1'b0;
  assign host_b       = 'x;

  // We don't use channel C and E
  assign host_c_ready = 1'b1;
  assign host_e_ready = 1'b1;

  // We don't use channel B.
  assign device_b_ready = 1'b1;

  // We don't use channel C and E
  assign device_c_valid = 1'b0;
  assign device_c       = 'x;
  assign device_e_valid = 1'b0;
  assign device_e       = 'x;

  /////////////////////////////////
  // Pending transaction tracker //
  /////////////////////////////////

  // The grant channel needs some information to recover the transaction.
  // We pass the number of beats left using the LSBs of device_a.source and
  // original host_a.source in MSBs of device_a.source, both of which can be
  // retrieved via device_d.source.
  //
  // We still need to know the original size. This technically can be recovered
  // by looking at the "offset" (number of beats left) from the first beat of
  // a messsage in D channel, but it adds too much combinational path, so we
  // just add a tracker.
  //
  // Currently the tracker is only for the size, but it could potentially have
  // source in the future so we don't need many source bits in the device.

  typedef struct packed {
    logic [`TL_SIZE_WIDTH-1:0] size;
  } tracker_info_t;

  logic          [NumTracker-1:0] tracker_valid_q, tracker_valid_d;
  tracker_info_t [NumTracker-1:0] tracker_info_q, tracker_info_d;

  always_comb begin
    tracker_valid_d = tracker_valid_q;
    tracker_info_d = tracker_info_q;

    // Remove from tracker when a response is completed.
    if (host_d_valid && host_d_ready && host_d_last) begin
      tracker_valid_d[host_d.source] = 1'b0;
      tracker_info_d[host_d.source] = 'x;
    end

    // Add to tracker when a request begins.
    if (host_a_valid && host_a_ready && host_a_first) begin
      tracker_valid_d[host_a.source] = 1'b1;
      tracker_info_d[host_a.source] = {host_a.size};
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      tracker_valid_q <= '0;
    end else begin
      tracker_valid_q <= tracker_valid_d;
    end
  end

  always_ff @(posedge clk_i) begin
    tracker_info_q <= tracker_info_d;
  end

  ////////////////////////
  // A channel handling //
  ////////////////////////

  enum logic [1:0] {
    ReqStateIdle,
    ReqStateNoData,
    ReqStateData
  } req_state_q = ReqStateIdle, req_state_d;

  tl_a_op_e opcode_q, opcode_d;
  logic [2:0] param_q, param_d;
  logic [HostSourceWidth-1:0] source_q, source_d;
  logic [AddrWidth-1:0] address_q, address_d;
  logic [DataWidth/8-1:0] mask_q, mask_d;
  logic [FragmentWidth-1:0] len_q, len_d;

  function automatic logic [FragmentWidth-1:0] num_fragment(input logic [`TL_SIZE_WIDTH-1:0] size);
    return (1 << (size - DeviceMaxSize)) - 1;
  endfunction

  // Compose source and offset into device_a.source.
  logic [HostSourceWidth-1:0] device_req_source;
  logic [FragmentWidth-1:0] device_req_offset;
  assign device_a.source = {device_req_source, device_req_offset};

  always_comb begin
    host_a_ready = 1'b0;

    device_a_valid = 1'b0;
    device_a.opcode = tl_a_op_e'('x);
    device_a.param = 'x;
    device_a.address = 'x;
    device_a.mask = 'x;
    device_a.corrupt = 1'bx;
    device_a.data = 'x;

    device_req_source = 'x;
    device_req_offset = 'x;

    req_state_d = req_state_q;
    opcode_d = opcode_q;
    param_d = param_q;
    source_d = source_q;
    address_d = address_q;
    len_d = len_q;

    unique case (req_state_q)
      ReqStateIdle: begin
        host_a_ready = (host_a_valid && host_a_first ? !tracker_valid_q[host_a.source] : 1'b1) && device_a_ready;

        device_a_valid = host_a_valid && (host_a_first ? !tracker_valid_q[host_a.source] : 1'b1);
        device_a.opcode = host_a.opcode;
        device_a.param = host_a.param;
        device_a.size = host_a.size;
        device_a.address = host_a.address;
        device_a.mask = host_a.mask;
        device_a.corrupt = host_a.corrupt;
        device_a.data = host_a.data;

        device_req_source = host_a.source;
        device_req_offset = 0;

        if (host_a.size > DeviceMaxSize) begin
          device_a.size = DeviceMaxSize;
          device_req_offset = num_fragment(host_a.size);
        end

        if (device_a_valid && device_a_ready && device_a_last) begin
          opcode_d = host_a.opcode;
          param_d = host_a.param;
          source_d = host_a.source;
          address_d = host_a.address + (2 ** DeviceMaxSize);
          len_d = num_fragment(host_a.size) - 1;

          if (host_a.size > DeviceMaxSize) begin
            req_state_d = host_a.opcode < 4 ? ReqStateData : ReqStateNoData;
          end
        end
      end

      ReqStateNoData: begin
        device_a_valid = 1'b1;
        device_a.opcode = opcode_q;
        device_a.param = param_q;
        device_a.size = DeviceMaxSize;
        device_a.address = address_q;
        device_a.mask = '1;
        device_a.corrupt = 1'b0;
        device_a.data = 'x;

        device_req_source = source_q;
        device_req_offset = len_q;

        if (device_a_ready) begin
          address_d = address_q + (2 ** DeviceMaxSize);
          len_d = len_q - 1;
          if (len_q == 0) begin
            req_state_d = ReqStateIdle;
          end
        end
      end

      ReqStateData: begin
        host_a_ready = device_a_ready;

        device_a_valid = host_a_valid;
        device_a.opcode = opcode_q;
        device_a.param = param_q;
        device_a.size = DeviceMaxSize;
        device_a.address = address_q;
        device_a.mask = host_a.mask;
        device_a.corrupt = host_a.corrupt;
        device_a.data = host_a.data;

        device_req_source = source_q;
        device_req_offset = len_q;

        if (host_a_valid && device_a_ready && device_a_last) begin
          address_d = address_q + (2 ** DeviceMaxSize);
          len_d = len_q - 1;
          if (len_q == 0) begin
            req_state_d = ReqStateIdle;
          end
        end
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      req_state_q <= ReqStateIdle;
      opcode_q <= tl_a_op_e'('x);
      param_q <= 'x;
      address_q <= 'x;
      source_q <= 'x;
      len_q <= 'x;
    end
    else begin
      req_state_q <= req_state_d;
      opcode_q <= opcode_d;
      param_q <= param_d;
      address_q <= address_d;
      source_q <= source_d;
      len_q <= len_d;
    end
  end

  ////////////////////////
  // D channel handling //
  ////////////////////////

  // On D-channel, we need to group multiple beats into one.
  // For AccessAckData, we just need to fix up d_source and d_size;
  // For AccessAck, we discard all beats except the last one.

  // Note: We expect d_denied to be consistent across beats. TileLink expects
  // transaction to be atomic (it either happens or is denied and no side-effect
  // happens at all. So if the downstream device denies some beats but not others,
  // we couldn't group them anyway. So for AccessAckData, we just assume it
  // will be kept consistent by the downstream device, and for AccessAck we
  // discard all except last.

  // Decompose device_d.source to the original source and an offset.
  wire [HostSourceWidth-1:0] device_d_source  = device_d.source[FragmentWidth +: HostSourceWidth];
  wire [FragmentWidth-1:0]   device_d_offset  = device_d.source[FragmentWidth-1:0];

  assign host_d.opcode  = device_d.opcode;
  assign host_d.param   = 0;
  assign host_d.source  = device_d_source;
  assign host_d.sink    = 'x;
  assign host_d.denied  = device_d.denied;
  assign host_d.corrupt = device_d.corrupt;
  assign host_d.data    = device_d.data;

  always_comb begin
    device_d_ready = host_d_ready;
    host_d_valid = device_d_valid;
    host_d.size = tracker_info_q[device_d_source];

    // All non-last beats of replies without data are to be discarded.
    if (device_d_valid && !device_d.opcode[0] && device_d_offset != 0) begin
      device_d_ready = 1'b1;
      host_d_valid = 1'b0;
    end
  end

endmodule
