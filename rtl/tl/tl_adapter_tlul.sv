// An adpater that converts an TL-UH to a TL-UL by fragmenting
// multi-beat bursts into multiple transactions.
//
// Does not change number of messages supported.
// Requires device to reply in FIFO order.
module tl_adapter_tlul import tl_pkg::*; #(
    parameter  int unsigned AddrWidth   = 56,
    parameter  int unsigned DataWidth   = 64,
    parameter  int unsigned SizeWidth   = 3,

    parameter  int unsigned HostSourceWidth = 1,
    parameter  int unsigned DeviceSourceWidth = 1,

    parameter  int unsigned HostMaxSize     = 6
) (
    input  logic       clk_i,
    input  logic       rst_ni,

    tl_channel.device  host,
    tl_channel.host    device
);

  localparam int unsigned DataWidthInBytes = DataWidth / 8;
  localparam int unsigned NonBurstSize = $clog2(DataWidthInBytes);
  localparam int unsigned MaxBurstLen = 2 ** (HostMaxSize - NonBurstSize);
  localparam int unsigned BurstLenWidth = $clog2(MaxBurstLen);

  // Check if parameters are well formed
  if (host.NumCachedHosts != 0) $fatal(1, "host.NumCachedHosts != 0");
  if (device.NumHosts != 1) $fatal(1, "device.NumHosts != 1");
  if (device.NumCachedHosts != 0) $fatal(1, "device.NumCachedHosts != 0");
  if (device.SourceIdWidth < host.SourceIdWidth + $clog2(device.NumHosts) + BurstLenWidth)
    $fatal(1, "tl_adapter_tlul does not have enough source ids");
  if (host.MaxSize > HostMaxSize) $fatal(1, "MaxSize does not match");
  if (host.DataWidth != DataWidth || device.DataWidth != DataWidth) $fatal(1, "DataWidth does not match");
  if (host.SizeWidth != SizeWidth || device.SizeWidth != SizeWidth) $fatal(1, "SizeWidth does not match");
  if (host.SourceWidth != HostSourceWidth || device.SourceWidth != DeviceSourceWidth) $fatal(1, "SourceWidth does not match");
  if (!device.FifoReply) $fatal(1, "device must reply in FIFO order");
  if (BurstLenWidth == 0) $fatal(1, "MaxBurstLen is 1 already");

  /////////////////////
  // Unused channels //
  /////////////////////

  // We don't use channel B.
  assign host.b_valid = 1'b0;
  assign host.b_opcode = tl_b_op_e'('x);
  assign host.b_param = 'x;
  assign host.b_size = 'x;
  assign host.b_source = 'x;
  assign host.b_address = 'x;
  assign host.b_mask = 'x;
  assign host.b_corrupt = 'x;
  assign host.b_data = 'x;

  // We don't use channel C and E
  assign host.c_ready = 1'b1;
  assign host.e_ready = 1'b1;

  // We don't use channel B.
  assign device.b_ready = 1'b1;

  // We don't use channel C and E
  assign device.c_valid = 1'b0;
  assign device.c_opcode = tl_c_op_e'('x);
  assign device.c_param = 'x;
  assign device.c_size = 'x;
  assign device.c_source = 'x;
  assign device.c_address = 'x;
  assign device.c_corrupt = 'x;
  assign device.c_data = 'x;
  assign device.e_valid = 1'b0;
  assign device.e_sink = 'x;

  //////////////////////////////
  // Pending transaction FIFO //
  //////////////////////////////

  // The grant channel needs some information to recover the transaction.
  // We pass the number of beats left using the LSBs of device.a_source and
  // original host.a_source in MSBs of device.a_source, both of which can be
  // retrieved via device.d_source.
  //
  // We still need to know the original size. This technically can be recovered
  // by looking at the "offset" (number of beats left) from the first beat of
  // a messsage in D channel, but it adds too much combinational path, so we
  // just add a FIFO.
  //
  // Currently the FIFO is only for the size, but it could potentially pass
  // a_source in the future so we don't need many source bits in the device.

  typedef struct packed {
    logic [SizeWidth-1:0] size;
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

  wire                       host_req_valid   = host.a_valid;
  wire tl_a_op_e             host_req_opcode  = host.a_opcode;
  wire [2:0]                 host_req_param   = host.a_param;
  wire [SizeWidth-1:0]       host_req_size    = host.a_size;
  wire [HostSourceWidth-1:0] host_req_source  = host.a_source;
  wire [AddrWidth-1:0]       host_req_address = host.a_address;
  wire [DataWidth/8-1:0]     host_req_mask    = host.a_mask;
  wire                       host_req_corrupt = host.a_corrupt;
  wire [DataWidth-1:0]       host_req_data    = host.a_data;

  wire device_req_ready = device.a_ready;

  enum logic [1:0] {
    ReqStateIdle,
    ReqStateGet,
    ReqStatePut
  } req_state_q = ReqStateIdle, req_state_d;

  logic [HostSourceWidth-1:0] source_q, source_d;
  logic [AddrWidth-1:0] address_q, address_d;
  logic [DataWidth/8-1:0] mask_q, mask_d;
  logic [BurstLenWidth-1:0] len_q, len_d;

  function automatic logic [BurstLenWidth-1:0] burst_len(input logic [SizeWidth-1:0] size);
    return (1 << (size - $clog2(DataWidth / 8))) - 1;
  endfunction

  // Compose source and offset into device.a_source.
  logic [HostSourceWidth-1:0] device_req_source;
  logic [BurstLenWidth-1:0] device_req_offset;
  assign device.a_source = {device_req_source, device_req_offset};

  always_comb begin
    host.a_ready = 1'b0;

    device.a_valid = 1'b0;
    device.a_opcode = tl_a_op_e'('x);
    device.a_param = 'x;
    device.a_address = 'x;
    device.a_mask = 'x;
    device.a_corrupt = 1'bx;
    device.a_data = 'x;

    device_req_source = 'x;
    device_req_offset = 'x;

    req_state_d = req_state_q;
    source_d = source_q;
    address_d = address_q;
    len_d = len_q;

    xact_fifo_push = 1'b0;
    xact_fifo_push_data = xact_t'{host_req_size};

    unique case (req_state_q)
      ReqStateIdle: begin
        host.a_ready = device_req_ready && xact_fifo_can_push;

        device.a_valid = host_req_valid && xact_fifo_can_push;
        device.a_opcode = host_req_opcode;
        device.a_param = host_req_param;
        device.a_size = host_req_size;
        device.a_address = host_req_address;
        device.a_mask = host_req_mask;
        device.a_corrupt = host_req_corrupt;
        device.a_data = host_req_data;

        device_req_source = host_req_source;
        device_req_offset = 0;

        if (host_req_size > NonBurstSize) begin
          device.a_size = NonBurstSize;
          device_req_offset = burst_len(host_req_size);
        end

        if (host_req_valid && device_req_ready && xact_fifo_can_push) begin
          xact_fifo_push = 1'b1;

          if (host_req_size > NonBurstSize) begin
            source_d = host_req_source;
            address_d = host_req_address + DataWidthInBytes;

            len_d = burst_len(host_req_size) - 1;
            req_state_d = host_req_opcode == Get ? ReqStateGet : ReqStatePut;
          end
        end
      end

      ReqStateGet: begin
        device.a_valid = 1'b1;
        device.a_opcode = Get;
        device.a_param = 0;
        device.a_size = NonBurstSize;
        device.a_address = address_q;
        device.a_mask = '1;
        device.a_corrupt = 1'b0;
        device.a_data = 'x;

        device_req_source = source_q;
        device_req_offset = len_q;

        if (device_req_ready) begin
          len_d = len_q - 1;
          address_d = address_q + DataWidthInBytes;
          if (len_q == 0) begin
            req_state_d = ReqStateIdle;
          end
        end
      end

      ReqStatePut: begin
        host.a_ready = device_req_ready;

        device.a_valid = host_req_valid;
        device.a_opcode = host_req_opcode;
        device.a_param = host_req_param;
        device.a_size = NonBurstSize;
        device.a_address = address_q;
        device.a_mask = host_req_mask;
        device.a_corrupt = host_req_corrupt;
        device.a_data = host_req_data;

        device_req_source = source_q;
        device_req_offset = len_q;

        if (host_req_valid && device_req_ready) begin
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

  wire                   device_gnt_valid   = device.d_valid;
  wire tl_d_op_e         device_gnt_opcode  = device.d_opcode;
  wire                   device_gnt_denied  = device.d_denied;
  wire                   device_gnt_corrupt = device.d_corrupt;
  wire [DataWidth-1:0]   device_gnt_data    = device.d_data;

  // Decompose device.d_source to the original source and an offset.
  wire [HostSourceWidth-1:0]   device_gnt_source  = device.d_source[DeviceSourceWidth-1:BurstLenWidth];
  wire [BurstLenWidth-1:0] device_gnt_offset  = device.d_source[BurstLenWidth-1:0];

  wire host_gnt_ready = host.d_ready;

  assign host.d_opcode  = device_gnt_opcode;
  assign host.d_param   = 0;
  assign host.d_source  = device_gnt_source;
  assign host.d_sink    = 'x;
  assign host.d_denied  = device_gnt_denied;
  assign host.d_corrupt = device_gnt_corrupt;
  assign host.d_data    = device_gnt_data;

  always_comb begin
    xact_fifo_pop = 1'b0;
    device.d_ready = 1'b0;
    device.d_ready = xact_fifo_peek_valid && host_gnt_ready;
    host.d_valid = xact_fifo_peek_valid && device_gnt_valid;
    host.d_size = xact_fifo_peek_data.size;

    // All non-last beat of AccessAck is to be discarded.
    if (device_gnt_valid && device_gnt_opcode == AccessAck && device_gnt_offset != 0) begin
      device.d_ready = 1'b1;
      host.d_valid = 1'b0;
    end

    // When the last beat is sent out, pop the transaction out.
    if (xact_fifo_peek_valid && device_gnt_valid && host_gnt_ready && device_gnt_offset == 0) begin
      xact_fifo_pop = 1'b1;
    end
  end

endmodule
