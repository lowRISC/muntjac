// The raw TileLink module without any register slice added.
//
// In general do not use this because this is not TileLink compliant as this
// guarantees host channel A remains stable after a valid, which does not hold
// in TileLink.
module tl_broadcast_raw import tl_pkg::*; #(
  parameter AddrWidth = 56,
  parameter DataWidth = 64,
  parameter SizeWidth = 3,
  parameter SourceWidth = 1,
  parameter SinkWidth = 1,

  // Address property table.
  // This table is used to determine if a given address range is cacheable or writable.
  // 2'b00 -> Normal
  // 2'b01 -> Readonly (e.g. ROM)
  // 2'b10 -> I/O
  // When ranges overlap, range that is specified with larger index takes priority.
  // If no ranges match, the property is assumed to be normal.
  parameter int unsigned NumAddressRange = 1,
  parameter bit [NumAddressRange-1:0][AddrWidth-1:0] AddressBase = '0,
  parameter bit [NumAddressRange-1:0][AddrWidth-1:0] AddressMask = '0,
  parameter bit [NumAddressRange-1:0][1:0]           AddressProperty = '0,

  // Source ID table for cacheable hosts.
  // These IDs are used for sending out Probe messages.
  // Ranges must not overlap.
  parameter NumCachedHosts = 1,
  parameter logic [NumCachedHosts-1:0][SourceWidth-1:0] SourceBase = '0,
  parameter logic [NumCachedHosts-1:0][SourceWidth-1:0] SourceMask = '0
) (
  input  logic clk_i,
  input  logic rst_ni,

  tl_channel.device host,
  tl_channel.host   device
);

  import prim_util_pkg::*;

  localparam MaxSize = 6;

  localparam int unsigned DataWidthInBytes = DataWidth / 8;
  localparam int unsigned NonBurstSize = $clog2(DataWidthInBytes);
  localparam int unsigned MaxBurstLen = 2 ** (MaxSize - NonBurstSize);
  localparam int unsigned BurstLenWidth = vbits(MaxBurstLen);

  // Types of device-side requests that we have to process:
  // AccessAckData:
  // * GrantData (toT) if the request is AcquireBlock (NtoT, BtoT)
  // * GrantData (toB) if the request is AcquireBlock (NtoB)
  // * AccessAckData   if the request is uncached
  // AccessAck:
  // * <drop>          if the request is ProbeAckData
  // * ReleaseAck      if the request is ReleaseData
  // * AccessAckData   if the request is uncached
  //
  // To differentiate these we will need to tag them using source IDs.
  // Note that ProbeAckData message itself carries no meaningful source ID (ProbeAckData is not a
  // request, so the host can use any of its source ID), so we need to use the ID of the
  // operation that causes the Probe. This luckily also allows us to encode GrantData and <drop>
  // using the same bits because Acquire cannot be inflight when Probing is not yet completed.

  localparam logic [1:0] XACT_ACQUIRE_TO_T   = 0;
  localparam logic [1:0] XACT_ACQUIRE_TO_B   = 1;
  localparam logic [1:0] XACT_PROBE_ACK_DATA = 0;
  localparam logic [1:0] XACT_RELEASE_DATA   = 2;
  localparam logic [1:0] XACT_UNCACHED       = 3;

  /////////////////////////////////
  // Burst tracker instantiation //
  /////////////////////////////////

  wire host_req_last;
  wire host_gnt_last;
  wire device_req_last;
  wire device_gnt_last;

  tl_burst_tracker #(
    .DataWidth (DataWidth),
    .SizeWidth (SizeWidth),
    .MaxSize (MaxSize)
  ) host_burst_tracker (
    .clk_i,
    .rst_ni,
    .link (host),
    .req_len_o (),
    .prb_len_o (),
    .rel_len_o (),
    .gnt_len_o (),
    .req_idx_o (),
    .prb_idx_o (),
    .rel_idx_o (),
    .gnt_idx_o (),
    .req_left_o (),
    .prb_left_o (),
    .rel_left_o (),
    .gnt_left_o (),
    .req_first_o (),
    .prb_first_o (),
    .rel_first_o (),
    .gnt_first_o (),
    .req_last_o (host_req_last),
    .prb_last_o (),
    .rel_last_o (),
    .gnt_last_o (host_gnt_last)
  );

  tl_burst_tracker #(
    .DataWidth (DataWidth),
    .SizeWidth (SizeWidth),
    .MaxSize (MaxSize)
  ) device_burst_tracker (
    .clk_i,
    .rst_ni,
    .link (device),
    .req_len_o (),
    .prb_len_o (),
    .rel_len_o (),
    .gnt_len_o (),
    .req_idx_o (),
    .prb_idx_o (),
    .rel_idx_o (),
    .gnt_idx_o (),
    .req_left_o (),
    .prb_left_o (),
    .rel_left_o (),
    .gnt_left_o (),
    .req_first_o (),
    .prb_first_o (),
    .rel_first_o (),
    .gnt_first_o (),
    .req_last_o (device_req_last),
    .prb_last_o (),
    .rel_last_o (),
    .gnt_last_o (device_gnt_last)
  );

  /////////////////////
  // Unused channels //
  /////////////////////

  assign device.b_ready   = 1'b1;

  assign device.c_valid   = 1'b0;
  assign device.c_opcode  = tl_c_op_e'('x);
  assign device.c_param   = 'x;
  assign device.c_size    = 'x;
  assign device.c_source  = 'x;
  assign device.c_address = 'x;
  assign device.c_corrupt = 'x;
  assign device.c_data    = 'x;

  assign device.e_valid   = 1'b0;
  assign device.e_sink    = 'x;

  /////////////////////////////////
  // Request channel arbitration //
  /////////////////////////////////

  typedef struct packed {
    tl_a_op_e               opcode;
    logic [2:0]             param;
    logic [SizeWidth-1:0]   size;
    logic [SourceWidth-1:0] source;
    logic [AddrWidth-1:0]   address;
    logic [DataWidth/8-1:0] mask;
    logic                   corrupt;
    logic [DataWidth-1:0]   data;
  } req_t;

  // We have two origins of A channel requests to device:
  // 0. Host C channel ProbeAckData/ReleaseData
  // 1. Host A channel request
  localparam ReqOrigins = 2;

  // Grouped signals before multiplexing/arbitration
  req_t [ReqOrigins-1:0] device_req_mult;
  logic [ReqOrigins-1:0] device_req_valid_mult;
  logic [ReqOrigins-1:0] device_req_ready_mult;

  // Signals after multiplexing
  req_t device_req;
  logic device_req_valid;
  logic device_req_ready;

  assign device_req_ready = device.a_ready;

  assign device.a_valid   = device_req_valid;
  assign device.a_opcode  = device_req.opcode;
  assign device.a_param   = device_req.param;
  assign device.a_size    = device_req.size;
  assign device.a_source  = device_req.source;
  assign device.a_address = device_req.address;
  assign device.a_mask    = device_req.mask;
  assign device.a_corrupt = device_req.corrupt;
  assign device.a_data    = device_req.data;

  // Signals for arbitration
  logic [ReqOrigins-1:0] device_req_arb_grant;
  logic                  device_req_locked;
  logic [ReqOrigins-1:0] device_req_selected;

  openip_round_robin_arbiter #(.WIDTH(ReqOrigins)) device_req_arb (
    .clk     (clk_i),
    .rstn    (rst_ni),
    .enable  (!device_req_locked),
    .request (device_req_valid_mult),
    .grant   (device_req_arb_grant)
  );

  // Perform arbitration, and make sure that until we encounter device_req_last we keep the connection stable.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      device_req_locked <= 1'b0;
      device_req_selected <= '0;
    end
    else begin
      if (device_req_locked) begin
        if (device_req_valid && device_req_ready && device_req_last) begin
          device_req_locked <= 1'b0;
        end
      end
      else if (|device_req_arb_grant) begin
        device_req_locked   <= 1'b1;
        device_req_selected <= device_req_arb_grant;
      end
    end
  end

  for (genvar i = 0; i < ReqOrigins; i++) begin
    assign device_req_ready_mult[i] = device_req_locked && device_req_selected[i] && device_req_ready;
  end

  // Do the post-arbitration multiplexing
  always_comb begin
    device_req = req_t'('x);
    device_req_valid = 1'b0;
    if (device_req_locked) begin
      for (int i = ReqOrigins - 1; i >= 0; i--) begin
        if (device_req_selected[i]) begin
          device_req = device_req_mult[i];
          device_req_valid = device_req_valid_mult[i];
        end
      end
    end
  end

  ///////////////////////////////
  // Grant channel arbitration //
  ///////////////////////////////

  typedef struct packed {
    tl_d_op_e               opcode;
    logic [2:0]             param;
    logic [SizeWidth-1:0]   size;
    logic [SourceWidth-1:0] source;
    logic [SinkWidth-1:0]   sink;
    logic                   denied;
    logic                   corrupt;
    logic [DataWidth-1:0]   data;
  } gnt_t;

  // We have three origins of D channel response to host:
  // 0. ReleaseAck response to host's Release
  // 1. Grant response to host's AcquirePerm, or a denied response to a rejected host request
  // 2. Device D channel response
  localparam GntOrigins = 3;

  // Grouped signals before multiplexing/arbitration
  gnt_t [GntOrigins-1:0] host_gnt_mult;
  logic [GntOrigins-1:0] host_gnt_valid_mult;
  logic [GntOrigins-1:0] host_gnt_ready_mult;

  // Signals after multiplexing
  gnt_t host_gnt;
  logic host_gnt_valid;
  logic host_gnt_ready;

  assign host_gnt_ready = host.d_ready;

  assign host.d_valid   = host_gnt_valid;
  assign host.d_opcode  = host_gnt.opcode;
  assign host.d_param   = host_gnt.param;
  assign host.d_size    = host_gnt.size;
  assign host.d_source  = host_gnt.source;
  assign host.d_sink    = host_gnt.sink;
  assign host.d_denied  = host_gnt.denied;
  assign host.d_corrupt = host_gnt.corrupt;
  assign host.d_data    = host_gnt.data;

  // Signals for arbitration
  logic [GntOrigins-1:0] host_gnt_arb_grant;
  logic                host_gnt_locked;
  logic [GntOrigins-1:0] host_gnt_selected;

  openip_round_robin_arbiter #(.WIDTH(GntOrigins)) host_gnt_arb (
    .clk     (clk_i),
    .rstn    (rst_ni),
    .enable  (!host_gnt_locked),
    .request (host_gnt_valid_mult),
    .grant   (host_gnt_arb_grant)
  );

  // Perform arbitration, and make sure that until we encounter host_gnt_last we keep the connection stable.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      host_gnt_locked <= 1'b0;
      host_gnt_selected <= '0;
    end
    else begin
      if (host_gnt_locked) begin
        if (host_gnt_valid && host_gnt_ready && host_gnt_last) begin
          host_gnt_locked <= 1'b0;
        end
      end
      else if (|host_gnt_arb_grant) begin
        host_gnt_locked   <= 1'b1;
        host_gnt_selected <= host_gnt_arb_grant;
      end
    end
  end

  for (genvar i = 0; i < GntOrigins; i++) begin
    assign host_gnt_ready_mult[i] = host_gnt_locked && host_gnt_selected[i] && host_gnt_ready;
  end

  // Do the post-arbitration multiplexing
  always_comb begin
    host_gnt = gnt_t'('x);
    host_gnt_valid = 1'b0;
    if (host_gnt_locked) begin
      for (int i = GntOrigins - 1; i >= 0; i--) begin
        if (host_gnt_selected[i]) begin
          host_gnt = host_gnt_mult[i];
          host_gnt_valid = host_gnt_valid_mult[i];
        end
      end
    end
  end

  /////////////////////////////////////////////
  // Request channel handling and core logic //
  /////////////////////////////////////////////

  wire                   host_req_valid   = host.a_valid;
  wire tl_a_op_e         host_req_opcode  = host.a_opcode;
  wire [2:0]             host_req_param   = host.a_param;
  wire [SizeWidth-1:0]   host_req_size    = host.a_size;
  wire [SourceWidth-1:0] host_req_source  = host.a_source;
  wire [AddrWidth-1:0]   host_req_address = host.a_address;
  wire [DataWidth/8-1:0] host_req_mask    = host.a_mask;
  wire                   host_req_corrupt = host.a_corrupt;
  wire [DataWidth-1:0]   host_req_data    = host.a_data;

  // Decode the host sending the request.
  logic [NumCachedHosts-1:0] req_selected;
  for (genvar i = 0; i < NumCachedHosts; i++) begin
    assign req_selected[i] = (host.a_source &~ SourceMask[i]) == SourceBase[i];
  end

  // Check if the request is allowed.
  logic       req_allowed;
  logic [1:0] req_address_property;
  always_comb begin
    // Decode the property of the address requested.
    req_address_property = 0;
    for (int i = 0; i < NumAddressRange; i++) begin
      if ((host_req_address &~ AddressMask[i]) == AddressBase[i]) begin
        req_address_property = AddressProperty[i];
      end
    end

    // Check the request with the address property.
    req_allowed = 1'b1;
    case (host_req_opcode)
      AcquireBlock, AcquirePerm: begin
        if (req_address_property == 2) begin
          req_allowed = 1'b0;
        end else if (req_address_property == 1 && host_req_param != NtoB) begin
          req_allowed = 1'b0;
        end
      end
      PutFullData: begin
        if (req_address_property == 1) begin
          req_allowed = 1'b0;
        end
      end
    endcase
  end

  // States of the cache.
  typedef enum logic [2:0] {
    StateIdle,
    StateInv,
    StateReq,
    StateGrant,
    StateDeny,
    StateWait
  } state_e;

  state_e state_q = StateIdle, state_d;
  tl_a_op_e opcode_q, opcode_d;
  logic [AddrWidth-1:0] address_q, address_d;
  logic [1:0] xact_type_q, xact_type_d;
  logic [SourceWidth-1:0] source_q, source_d;
  logic [2:0] inv_param_q, inv_param_d;

  // Tracking pending handshakes
  logic [NumCachedHosts-1:0] probe_ack_pending_q, probe_ack_pending_d;
  logic ack_done_q, ack_done_d;
  logic grant_done_q, grant_done_d;

  // Interfacing with probe sequencer
  logic                      probe_ready;
  logic                      probe_valid;
  logic [NumCachedHosts-1:0] probe_mask;
  logic [2:0]                probe_param;

  logic probe_ack_complete;
  logic probe_ack_data_complete;
  logic grant_complete;
  logic ack_complete;

  always_comb begin
    // The outbound request channel.
    device_req_valid_mult[1] = 1'b0;
    device_req_mult[1].opcode = tl_a_op_e'('x);
    device_req_mult[1].param = 'x;
    device_req_mult[1].size = 'x;
    device_req_mult[1].address = 'x;
    device_req_mult[1].mask = 'x;
    device_req_mult[1].data = 'x;
    device_req_mult[1].corrupt = 1'b0;
    device_req_mult[1].source = 0;

    // The instant response channel.
    // * Grant message in response to AcquirePerm
    // * Grant (denied) message in response to a rejected Acquire request
    // * AccessAck message in response to a rejected PutFullData request
    host_gnt_valid_mult[1] = 1'b0;
    host_gnt_mult[1].opcode = tl_d_op_e'('x);
    host_gnt_mult[1].param = 'x;
    host_gnt_mult[1].size = 'x;
    host_gnt_mult[1].source = 'x;
    host_gnt_mult[1].sink = 'x;
    host_gnt_mult[1].denied = 1'b0;
    host_gnt_mult[1].corrupt = 1'b0;
    host_gnt_mult[1].data = 'x;

    probe_valid = 1'b0;
    probe_mask = 'x;
    probe_param = 'x;
    host.a_ready = 1'b0;

    state_d = state_q;
    opcode_d = opcode_q;
    address_d = address_q;
    xact_type_d = xact_type_q;
    source_d = source_q;

    probe_ack_pending_d = probe_ack_pending_q;
    ack_done_d = ack_done_q;
    grant_done_d = grant_done_q;

    if (ack_complete) ack_done_d = 1'b1;
    if (grant_complete) grant_done_d = 1'b1;

    unique case (state_q)
      StateIdle: begin
        if (host_req_valid) begin
          opcode_d = host_req_opcode;
          address_d = host_req_address;
          source_d = host_req_source;
          ack_done_d = 1'b0;
          grant_done_d = 1'b0;

          // Send out probe and wait for reply.
          probe_valid = 1'b1;
          probe_mask = ~req_selected;
          state_d = StateInv;
          probe_ack_pending_d = req_selected == 0 ? NumCachedHosts : NumCachedHosts - 1;

          case (host_req_opcode)
            AcquireBlock, AcquirePerm: begin
              xact_type_d = host_req_param == NtoB ? XACT_ACQUIRE_TO_B : XACT_ACQUIRE_TO_T;
              probe_param = host_req_param == NtoB ? toB : toN;
            end
            Get, PutFullData: begin
              // Uncached requests have no GrantAck message.
              ack_done_d = 1'b1;

              xact_type_d = XACT_UNCACHED;
              probe_param = host_req_opcode == Get ? toB : toN;
            end
          endcase

          if (!req_allowed) begin
            probe_valid = 1'b0;
            state_d = StateDeny;
          end
        end
      end

      // Wait for all probes to be acked.
      StateInv: begin
        if (probe_ack_complete || probe_ack_data_complete) begin
          probe_ack_pending_d = probe_ack_pending_q - 1;
        end

        if (probe_ack_pending_d == 0) begin
          // We can return to the caller.
          state_d = opcode_q == AcquirePerm ? StateGrant : StateReq;
        end
      end

      StateReq: begin
        device_req_valid_mult[1] = host_req_valid;
        device_req_mult[1].opcode = xact_type_q != XACT_UNCACHED ? Get : opcode_q;
        device_req_mult[1].size = host_req_size;
        device_req_mult[1].param = 0;
        device_req_mult[1].source = {source_q, xact_type_q};
        device_req_mult[1].address = address_q;
        device_req_mult[1].mask = host_req_mask;
        device_req_mult[1].data = host_req_data;
        host.a_ready = device_req_ready_mult[1];
        if (device_req_ready_mult[1] && host_req_valid && host_req_last) begin
          state_d = opcode_q == AcquireBlock ? StateWait : StateIdle;
        end
      end

      StateGrant: begin
        host.a_ready = host_req_valid && host_req_last ? host_gnt_ready_mult[1] : 1'b1;
        host_gnt_valid_mult[1] = host_req_valid && host_req_last;
        host_gnt_mult[1].opcode = Grant;
        host_gnt_mult[1].param = xact_type_q;
        host_gnt_mult[1].source = source_q;
        host_gnt_mult[1].size = host_req_size;
        host_gnt_mult[1].denied = 1'b0;
        if (host_gnt_ready_mult[1] && host_req_valid && host_req_last) begin
          grant_done_d = 1'b1;
          state_d = StateWait;
        end
      end

      StateDeny: begin
        host.a_ready = host_req_valid && host_req_last ? host_gnt_ready_mult[1] : 1'b1;
        host_gnt_valid_mult[1] = host_req_valid && host_req_last;
        host_gnt_mult[1].opcode = opcode_q == PutFullData ? AccessAck : Grant;
        host_gnt_mult[1].param = toN;
        host_gnt_mult[1].source = source_q;
        host_gnt_mult[1].size = host_req_size;
        host_gnt_mult[1].denied = 1'b1;
        if (host_gnt_ready_mult[1] && host_req_valid && host_req_last) begin
          grant_done_d = 1'b1;
          state_d = StateWait;
        end
      end

      StateWait: begin
        if (ack_done_d && grant_done_d) state_d = StateIdle;
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni)
    if (!rst_ni) begin
      state_q <= StateIdle;
      opcode_q <= tl_a_op_e'('x);
      address_q <= 'x;
      xact_type_q <= 'x;
      source_q <= 'x;
      probe_ack_pending_q <= 'x;
      ack_done_q <= 'x;
      grant_done_q <= 'x;
    end
    else begin
      state_q <= state_d;
      opcode_q <= opcode_d;
      address_q <= address_d;
      xact_type_q <= xact_type_d;
      source_q <= source_d;
      probe_ack_pending_q <= probe_ack_pending_d;
      ack_done_q <= ack_done_d;
      grant_done_q <= grant_done_d;
    end

  ////////////////////////////
  // Probe channel handling //
  ////////////////////////////

  // Probes yet to be sent.
  logic [NumCachedHosts-1:0] probe_pending_q, probe_pending_d;
  logic [2:0]                probe_param_q, probe_param_d;

  assign host.b_valid = |probe_pending_q;
  assign host.b_opcode = ProbeBlock;
  assign host.b_param = probe_param_q;
  assign host.b_size = 6;
  assign host.b_address = {address_q[AddrWidth-1:6], 6'd0};
  assign host.b_mask = '1;
  assign host.b_corrupt = 1'b0;
  assign host.b_data = 'x;

  // Zero or onehot bit mask of currently probing host.
  logic [NumCachedHosts-1:0] probe_selected;
  always_comb begin
    host.b_source = 'x;
    probe_selected = '0;
    for (int i = 0; i < NumCachedHosts; i++) begin
      if (probe_pending_q[i]) begin
        probe_selected = '0;
        probe_selected[i] = 1'b1;
        host.b_source = SourceBase[i];
      end
    end
  end

  wire host_prb_ready = host.b_ready;

  always_comb begin
    probe_pending_d = probe_pending_q;
    probe_param_d = probe_param_q;

    probe_ready = probe_pending_q == 0;

    // A probe has been acknowledged
    if (probe_pending_q != 0 && host_prb_ready) begin
      probe_pending_d = probe_pending_q &~ probe_selected;
    end

    // New probing request
    if (probe_valid) begin
      probe_pending_d = probe_mask;
      probe_param_d = probe_param;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      probe_pending_q <= '0;
      probe_param_q <= 'x;
    end else begin
      probe_pending_q <= probe_pending_d;
      probe_param_q <= probe_param_d;
    end
  end

  //////////////////////////////
  // Release channel handling //
  //////////////////////////////

  wire                   ack_valid   = host.c_valid;
  wire tl_c_op_e         ack_opcode  = host.c_opcode;
  wire [SizeWidth-1:0]   ack_size    = host.c_size;
  wire [SourceWidth-1:0] ack_source  = host.c_source;
  wire [AddrWidth-1:0]   ack_address = host.c_address;
  wire                   ack_corrupt = host.c_corrupt;
  wire [DataWidth-1:0]   ack_data    = host.c_data;

  // The release channel is relatively easy because it does not have complex ordering requirements
  // with other channels.
  //
  // We can possibly get 4 types of messages here: ProbeAck[Data], Release[Data].
  // ProbeAck:
  //   No action should be performed by the device; we can simply signal the probe logic and drop this message.
  // ProbeAckData:
  //   We need to signal the probe logic, and transform this message into a PutFullData and send
  //   it down to the device. The device's reply should be ignored.
  // Release:
  //   No action should be performed by the device; but we need to respond with a ReleaseAck. This
  //   reply can be done in combinationally.
  // ReleaseData:
  //   Transform this message into PutFullData and send it down to the device. The device's reply should
  //   be transformed to a ReleaseAck and send back to the host.

  always_comb begin
    device_req_valid_mult[0] = 1'b0;
    device_req_mult[0].opcode = PutFullData;
    device_req_mult[0].param = 0;
    device_req_mult[0].size = ack_size;
    device_req_mult[0].source = 'x;
    device_req_mult[0].address = ack_address;
    device_req_mult[0].mask = '1; // TODO: Make sure ack_size >= NonBurstSize
    device_req_mult[0].corrupt = ack_corrupt;
    device_req_mult[0].data = ack_data;

    // ReleaseAck message in response to a Release.
    host_gnt_valid_mult[0] = 1'b0;
    host_gnt_mult[0].opcode = ReleaseAck;
    host_gnt_mult[0].param = 0;
    host_gnt_mult[0].size = ack_size;
    host_gnt_mult[0].source = ack_source;
    host_gnt_mult[0].sink = 'x;
    host_gnt_mult[0].denied = 1'b0;
    host_gnt_mult[0].corrupt = 1'b0;
    host_gnt_mult[0].data = 'x;

    host.c_ready = 1'b0;

    probe_ack_complete = 1'b0;

    if (ack_valid) begin
      unique case (ack_opcode)
        ProbeAck: begin
          // Drop
          host.c_ready = 1'b1;
          probe_ack_complete = 1'b1;
        end
        ProbeAckData: begin
          device_req_valid_mult[0] = ack_valid;
          device_req_mult[0].source = {source_q, XACT_PROBE_ACK_DATA};
          host.c_ready = device_req_ready_mult[0];
        end
        Release: begin
          // Reply with ReleaseAck
          host_gnt_valid_mult[0] = 1'b1;
          host.c_ready = host_gnt_ready_mult[0];
        end
        ReleaseData: begin
          device_req_valid_mult[0] = ack_valid;
          device_req_mult[0].source = {ack_source, XACT_RELEASE_DATA};
          host.c_ready = device_req_ready_mult[0];
        end
      endcase
    end
  end

  ////////////////////////////
  // Grant channel handling //
  ////////////////////////////

  wire                   device_gnt_valid   = device.d_valid;
  wire tl_d_op_e         device_gnt_opcode  = device.d_opcode;
  wire [SizeWidth-1:0]   device_gnt_size    = device.d_size;
  wire [SourceWidth-1:0] device_gnt_source  = device.d_source;
  wire                   device_gnt_denied  = device.d_denied;
  wire                   device_gnt_corrupt = device.d_corrupt;
  wire [DataWidth-1:0]   device_gnt_data    = device.d_data;

  always_comb begin
    host_gnt_valid_mult[2] = 1'b0;
    host_gnt_mult[2].opcode = tl_d_op_e'('x);
    host_gnt_mult[2].param = 'x;
    host_gnt_mult[2].size = device_gnt_size;
    host_gnt_mult[2].source = device_gnt_source[SourceWidth-1:2];
    host_gnt_mult[2].sink = 0;
    host_gnt_mult[2].denied = device_gnt_denied;
    host_gnt_mult[2].corrupt = device_gnt_corrupt;
    host_gnt_mult[2].data = device_gnt_data;

    device.d_ready = 1'b0;

    probe_ack_data_complete = 1'b0;
    grant_complete = 1'b0;

    if (device_gnt_valid) begin
      unique case (device_gnt_source[1:0])
        XACT_ACQUIRE_TO_T: begin
          // In this case this is XACT_PROBE_ACK_DATA
          if (device_gnt_opcode == AccessAck) begin
            // Drop
            device.d_ready = 1'b1;
            probe_ack_data_complete = 1'b1;
          end else begin
            host_gnt_valid_mult[2] = 1'b1;
            host_gnt_mult[2].opcode = GrantData;
            host_gnt_mult[2].param = toT;
            device.d_ready = host_gnt_ready_mult[2];

            grant_complete = device_gnt_last;
          end
        end
        XACT_ACQUIRE_TO_B: begin
          host_gnt_valid_mult[2] = 1'b1;
          host_gnt_mult[2].opcode = GrantData;
          host_gnt_mult[2].param = toB;
          device.d_ready = host_gnt_ready_mult[2];

          grant_complete = device_gnt_last;
        end
        XACT_RELEASE_DATA: begin
          host_gnt_valid_mult[2] = 1'b1;
          host_gnt_mult[2].opcode = ReleaseAck;
          host_gnt_mult[2].param = 0;
          device.d_ready = host_gnt_ready_mult[2];
        end
        XACT_UNCACHED: begin
          host_gnt_valid_mult[2] = 1'b1;
          host_gnt_mult[2].opcode = device_gnt_opcode;
          host_gnt_mult[2].param = 0;
          device.d_ready = host_gnt_ready_mult[2];

          grant_complete = device_gnt_last;
        end
      endcase
    end
  end

  //////////////////////////////////////
  // Acknowledgement channel handling //
  //////////////////////////////////////

  // Acknowledgement channel is always available.
  assign ack_complete = host.e_valid;
  assign host.e_ready = 1'b1;

endmodule

module tl_broadcast import tl_pkg::*; #(
  parameter AddrWidth = 56,
  parameter DataWidth = 64,
  parameter SizeWidth = 3,
  parameter SourceWidth = 1,
  parameter SinkWidth = 1,

  // Address property table.
  // This table is used to determine if a given address range is cacheable or writable.
  // 2'b00 -> Normal
  // 2'b01 -> Readonly (e.g. ROM)
  // 2'b10 -> I/O
  // When ranges overlap, range that is specified with larger index takes priority.
  // If no ranges match, the property is assumed to be normal.
  parameter int unsigned NumAddressRange = 1,
  parameter bit [NumAddressRange-1:0][AddrWidth-1:0] AddressBase = '0,
  parameter bit [NumAddressRange-1:0][AddrWidth-1:0] AddressMask = '0,
  parameter bit [NumAddressRange-1:0][1:0]           AddressProperty = '0,

  // Source ID table for cacheable hosts.
  // These IDs are used for sending out Probe messages.
  // Ranges must not overlap.
  parameter NumCachedHosts = 1,
  parameter logic [NumCachedHosts-1:0][SourceWidth-1:0] SourceBase = '0,
  parameter logic [NumCachedHosts-1:0][SourceWidth-1:0] SourceMask = '0
) (
  input  logic clk_i,
  input  logic rst_ni,

  tl_channel.device host,
  tl_channel.host   device
);

  tl_channel #(
    .AddrWidth (AddrWidth),
    .DataWidth (DataWidth),
    .SizeWidth (SizeWidth),
    .SourceWidth (SourceWidth),
    .SinkWidth (SinkWidth)
  ) host_reg_ch ();

  tl_regslice #(
    .AddrWidth (AddrWidth),
    .DataWidth (DataWidth),
    .SizeWidth (SizeWidth),
    .SourceWidth (SourceWidth),
    .SinkWidth (SinkWidth),
    .RequestMode (1)
  ) host_reg (
    .clk_i,
    .rst_ni,
    .host,
    .device (host_reg_ch)
  );

  tl_broadcast_raw #(
    .AddrWidth (AddrWidth),
    .DataWidth (DataWidth),
    .SizeWidth (SizeWidth),
    .SourceWidth (SourceWidth),
    .SinkWidth (SinkWidth),
    .NumAddressRange (NumAddressRange),
    .AddressBase (AddressBase),
    .AddressMask (AddressMask),
    .AddressProperty (AddressProperty),
    .NumCachedHosts (NumCachedHosts),
    .SourceBase (SourceBase),
    .SourceMask (SourceMask)
  ) inst (
    .clk_i,
    .rst_ni,
    .host (host_reg_ch),
    .device
  );

endmodule
