`include "tl_util.svh"

// An adpater that converts an TL-UH to a TL-UL by fragmenting
// multi-beat bursts into multiple transactions.
//
// Does not change number of messages supported.
// Requires device to reply in FIFO order.
module tl_adapter_tlul import tl_pkg::*; #(
    parameter  int unsigned AddrWidth   = 56,
    parameter  int unsigned DataWidth   = 64,
    parameter  int unsigned SinkWidth   = 1,

    parameter  int unsigned HostSourceWidth = 1,
    parameter  int unsigned DeviceSourceWidth = 1,

    parameter  int unsigned HostMaxSize     = 6
) (
  input  logic       clk_i,
  input  logic       rst_ni,

  `TL_DECLARE_DEVICE_PORT(DataWidth, AddrWidth, HostSourceWidth, SinkWidth, host),
  `TL_DECLARE_HOST_PORT(DataWidth, AddrWidth, DeviceSourceWidth, SinkWidth, device)
);

  localparam int unsigned DataWidthInBytes = DataWidth / 8;
  localparam int unsigned NonBurstSize = $clog2(DataWidthInBytes);
  localparam int unsigned MaxBurstLen = 2 ** (HostMaxSize - NonBurstSize);
  localparam int unsigned BurstLenWidth = $clog2(MaxBurstLen);

  // Check if parameters are well formed
  if (BurstLenWidth == 0) $fatal(1, "MaxBurstLen is 1 already");

  `TL_DECLARE(DataWidth, AddrWidth, HostSourceWidth, SinkWidth, host);
  `TL_DECLARE(DataWidth, AddrWidth, DeviceSourceWidth, SinkWidth, device);
  `TL_BIND_DEVICE_PORT(host, host);
  `TL_BIND_HOST_PORT(device, device);

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

  //////////////////////////////
  // Pending transaction FIFO //
  //////////////////////////////

  // The grant channel needs some information to recover the transaction.
  // We pass the number of beats left using the LSBs of device_a.source and
  // original host_a.source in MSBs of device_a.source, both of which can be
  // retrieved via device_d.source.
  //
  // We still need to know the original size. This technically can be recovered
  // by looking at the "offset" (number of beats left) from the first beat of
  // a messsage in D channel, but it adds too much combinational path, so we
  // just add a FIFO.
  //
  // Currently the FIFO is only for the size, but it could potentially pass
  // a_source in the future so we don't need many source bits in the device.

  typedef struct packed {
    logic [`TL_SIZE_WIDTH-1:0] size;
  } xact_t;

  logic xact_fifo_can_push;
  logic xact_fifo_push;
  xact_t xact_fifo_push_data;

  logic xact_fifo_pop;
  logic xact_fifo_peek_valid;
  xact_t xact_fifo_peek_data;

  openip_regslice #(
      .TYPE             (xact_t),
      .HIGH_PERFORMANCE (1'b1)
  ) xact_fifo (
      .clk     (clk_i),
      .rstn    (rst_ni),
      .w_valid (xact_fifo_push),
      .w_ready (xact_fifo_can_push),
      .w_data  (xact_fifo_push_data),
      .r_valid (xact_fifo_peek_valid),
      .r_ready (xact_fifo_pop),
      .r_data  (xact_fifo_peek_data)
  );

  ////////////////////////
  // A channel handling //
  ////////////////////////

  enum logic [1:0] {
    ReqStateIdle,
    ReqStateGet,
    ReqStatePut
  } req_state_q = ReqStateIdle, req_state_d;

  logic [HostSourceWidth-1:0] source_q, source_d;
  logic [AddrWidth-1:0] address_q, address_d;
  logic [DataWidth/8-1:0] mask_q, mask_d;
  logic [BurstLenWidth-1:0] len_q, len_d;

  function automatic logic [BurstLenWidth-1:0] burst_len(input logic [`TL_SIZE_WIDTH-1:0] size);
    return (1 << (size - $clog2(DataWidth / 8))) - 1;
  endfunction

  // Compose source and offset into device_a.source.
  logic [HostSourceWidth-1:0] device_req_source;
  logic [BurstLenWidth-1:0] device_req_offset;
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
    source_d = source_q;
    address_d = address_q;
    len_d = len_q;

    xact_fifo_push = 1'b0;
    xact_fifo_push_data = xact_t'{host_a.size};

    unique case (req_state_q)
      ReqStateIdle: begin
        host_a_ready = device_a_ready && xact_fifo_can_push;

        device_a_valid = host_a_valid && xact_fifo_can_push;
        device_a.opcode = host_a.opcode;
        device_a.param = host_a.param;
        device_a.size = host_a.size;
        device_a.address = host_a.address;
        device_a.mask = host_a.mask;
        device_a.corrupt = host_a.corrupt;
        device_a.data = host_a.data;

        device_req_source = host_a.source;
        device_req_offset = 0;

        if (host_a.size > NonBurstSize) begin
          device_a.size = NonBurstSize;
          device_req_offset = burst_len(host_a.size);
        end

        if (host_a_valid && device_a_ready && xact_fifo_can_push) begin
          xact_fifo_push = 1'b1;

          if (host_a.size > NonBurstSize) begin
            source_d = host_a.source;
            address_d = host_a.address + DataWidthInBytes;

            len_d = burst_len(host_a.size) - 1;
            req_state_d = host_a.opcode == Get ? ReqStateGet : ReqStatePut;
          end
        end
      end

      ReqStateGet: begin
        device_a_valid = 1'b1;
        device_a.opcode = Get;
        device_a.param = 0;
        device_a.size = NonBurstSize;
        device_a.address = address_q;
        device_a.mask = '1;
        device_a.corrupt = 1'b0;
        device_a.data = 'x;

        device_req_source = source_q;
        device_req_offset = len_q;

        if (device_a_ready) begin
          len_d = len_q - 1;
          address_d = address_q + DataWidthInBytes;
          if (len_q == 0) begin
            req_state_d = ReqStateIdle;
          end
        end
      end

      ReqStatePut: begin
        host_a_ready = device_a_ready;

        device_a_valid = host_a_valid;
        device_a.opcode = host_a.opcode;
        device_a.param = host_a.param;
        device_a.size = NonBurstSize;
        device_a.address = address_q;
        device_a.mask = host_a.mask;
        device_a.corrupt = host_a.corrupt;
        device_a.data = host_a.data;

        device_req_source = source_q;
        device_req_offset = len_q;

        if (host_a_valid && device_a_ready) begin
          len_d = len_q - 1;
          address_d = address_q + DataWidthInBytes;
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
      address_q <= 'x;
      source_q <= 'x;
      len_q <= 'x;
    end
    else begin
      req_state_q <= req_state_d;
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
  wire [HostSourceWidth-1:0] device_d_source  = device_d.source[DeviceSourceWidth-1:BurstLenWidth];
  wire [BurstLenWidth-1:0]   device_d_offset  = device_d.source[BurstLenWidth-1:0];

  assign host_d.opcode  = device_d.opcode;
  assign host_d.param   = 0;
  assign host_d.source  = device_d_source;
  assign host_d.sink    = 'x;
  assign host_d.denied  = device_d.denied;
  assign host_d.corrupt = device_d.corrupt;
  assign host_d.data    = device_d.data;

  always_comb begin
    xact_fifo_pop = 1'b0;
    device_d_ready = xact_fifo_peek_valid && host_d_ready;
    host_d_valid = xact_fifo_peek_valid && device_d_valid;
    host_d.size = xact_fifo_peek_data.size;

    // All non-last beat of AccessAck is to be discarded.
    if (device_d_valid && device_d.opcode == AccessAck && device_d_offset != 0) begin
      device_d_ready = 1'b1;
      host_d_valid = 1'b0;
    end

    // When the last beat is sent out, pop the transaction out.
    if (xact_fifo_peek_valid && device_d_valid && host_d_ready && device_d_offset == 0) begin
      xact_fifo_pop = 1'b1;
    end
  end

endmodule
