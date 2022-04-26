`include "tl_util.svh"

module tl_broadcast import tl_pkg::*; #(
  parameter  int unsigned AddrWidth = 56,
  parameter  int unsigned DataWidth = 64,
  parameter  int unsigned HostSourceWidth = 1,
  parameter  int unsigned DeviceSourceWidth = 1,
  parameter  int unsigned SinkWidth = 1,
  parameter  int unsigned MaxSize = 6,

  // Source ID table for cacheable hosts.
  // These IDs are used for sending out Probe messages.
  // Ranges must not overlap.
  parameter NumCachedHosts = 1,
  parameter logic [NumCachedHosts-1:0][HostSourceWidth-1:0] SourceBase = '0,
  parameter logic [NumCachedHosts-1:0][HostSourceWidth-1:0] SourceMask = '0
) (
  input  logic clk_i,
  input  logic rst_ni,

  `TL_DECLARE_DEVICE_PORT(DataWidth, AddrWidth, HostSourceWidth, SinkWidth, host),
  `TL_DECLARE_HOST_PORT(DataWidth, AddrWidth, DeviceSourceWidth, SinkWidth, device)
);

  import prim_util_pkg::*;

  if (DeviceSourceWidth < HostSourceWidth + 2) $fatal(1, "Not enough DeviceSourceWidth");

  localparam int unsigned DataWidthInBytes = DataWidth / 8;
  localparam int unsigned NonBurstSize = $clog2(DataWidthInBytes);

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

  `TL_DECLARE(DataWidth, AddrWidth, HostSourceWidth, SinkWidth, host);
  `TL_DECLARE(DataWidth, AddrWidth, DeviceSourceWidth, SinkWidth, device);
  `TL_BIND_HOST_PORT(device, device);

  tl_regslice #(
    .AddrWidth (AddrWidth),
    .DataWidth (DataWidth),
    .SourceWidth (HostSourceWidth),
    .SinkWidth (SinkWidth),
    .RequestMode (2),
    .ReleaseMode (2)
  ) host_reg (
    .clk_i,
    .rst_ni,
    `TL_FORWARD_DEVICE_PORT(host, host),
    `TL_CONNECT_HOST_PORT(device, host)
  );

  function automatic logic [DataWidthInBytes-1:0] get_mask(
    input logic [NonBurstSize-1:0] address,
    input logic [`TL_SIZE_WIDTH-1:0] size
  );
    logic [`TL_SIZE_WIDTH-1:0] capped_size;
    capped_size = size >= NonBurstSize ? NonBurstSize : size;

    get_mask = 1;
    for (int i = 1; i <= NonBurstSize; i++) begin
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

  wire host_req_last;
  wire host_gnt_last;
  wire device_req_last;
  wire device_gnt_last;

  tl_burst_tracker #(
    .AddrWidth (AddrWidth),
    .DataWidth (DataWidth),
    .SourceWidth (HostSourceWidth),
    .SinkWidth (SinkWidth),
    .MaxSize (MaxSize)
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
    .req_first_o (),
    .rel_first_o (),
    .gnt_first_o (),
    .req_last_o (host_req_last),
    .rel_last_o (),
    .gnt_last_o (host_gnt_last)
  );

  tl_burst_tracker #(
    .AddrWidth (AddrWidth),
    .DataWidth (DataWidth),
    .SourceWidth (DeviceSourceWidth),
    .SinkWidth (SinkWidth),
    .MaxSize (MaxSize)
  ) device_burst_tracker (
    .clk_i,
    .rst_ni,
    `TL_FORWARD_TAP_PORT_FROM_HOST(link, device),
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
    .req_last_o (device_req_last),
    .rel_last_o (),
    .gnt_last_o (device_gnt_last)
  );

  /////////////////////
  // Unused channels //
  /////////////////////

  assign device_b_ready = 1'b1;

  assign device_c_valid = 1'b0;
  assign device_c       = 'x;

  assign device_e_valid = 1'b0;
  assign device_e       = 'x;

  /////////////////////////////////
  // Request channel arbitration //
  /////////////////////////////////

  typedef `TL_A_STRUCT(DataWidth, AddrWidth, DeviceSourceWidth, SinkWidth) req_t;

  // We have two origins of A channel requests to device:
  // 0. Host C channel ProbeAckData/ReleaseData
  // 1. Host A channel request
  localparam ReqOrigins = 2;

  // Grouped signals before multiplexing/arbitration
  req_t [ReqOrigins-1:0] device_req_mult;
  logic [ReqOrigins-1:0] device_req_valid_mult;
  logic [ReqOrigins-1:0] device_req_ready_mult;

  // Signals for arbitration
  logic [ReqOrigins-1:0] device_req_arb_grant;
  logic                  device_req_locked;
  logic [ReqOrigins-1:0] device_req_selected;

  openip_round_robin_arbiter #(.WIDTH(ReqOrigins)) device_req_arb (
    .clk     (clk_i),
    .rstn    (rst_ni),
    .enable  (device_a_valid && device_a_ready && !device_req_locked),
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
      if (device_a_valid && device_a_ready) begin
        if (!device_req_locked) begin
          device_req_locked   <= 1'b1;
          device_req_selected <= device_req_arb_grant;
        end
        if (device_req_last) begin
          device_req_locked <= 1'b0;
        end
      end
    end
  end

  wire [ReqOrigins-1:0] device_req_select = device_req_locked ? device_req_selected : device_req_arb_grant;

  for (genvar i = 0; i < ReqOrigins; i++) begin
    assign device_req_ready_mult[i] = device_req_select[i] && device_a_ready;
  end

  // Do the post-arbitration multiplexing
  always_comb begin
    device_a = req_t'('x);
    device_a_valid = 1'b0;
    for (int i = ReqOrigins - 1; i >= 0; i--) begin
      if (device_req_select[i]) begin
        device_a = device_req_mult[i];
        device_a_valid = device_req_valid_mult[i];
      end
    end
  end

  ///////////////////////////////
  // Grant channel arbitration //
  ///////////////////////////////

  typedef `TL_D_STRUCT(DataWidth, AddrWidth, HostSourceWidth, SinkWidth) gnt_t;

  // We have three origins of D channel response to host:
  // 0. ReleaseAck response to host's Release
  // 1. Grant response to host's AcquirePerm, or a denied response to a rejected host request
  // 2. Device D channel response
  localparam GntOrigins = 3;

  // Grouped signals before multiplexing/arbitration
  gnt_t [GntOrigins-1:0] host_gnt_mult;
  logic [GntOrigins-1:0] host_gnt_valid_mult;
  logic [GntOrigins-1:0] host_gnt_ready_mult;

  // Signals for arbitration
  logic [GntOrigins-1:0] host_gnt_arb_grant;
  logic                  host_gnt_locked;
  logic [GntOrigins-1:0] host_gnt_selected;

  openip_round_robin_arbiter #(.WIDTH(GntOrigins)) host_gnt_arb (
    .clk     (clk_i),
    .rstn    (rst_ni),
    .enable  (host_d_valid && host_d_ready && !host_gnt_locked),
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
      if (host_d_valid && host_d_ready) begin
        if (!host_gnt_locked) begin
          host_gnt_locked   <= 1'b1;
          host_gnt_selected <= host_gnt_arb_grant;
        end
        if (host_gnt_last) begin
          host_gnt_locked <= 1'b0;
        end
      end
    end
  end

  wire [GntOrigins-1:0] host_gnt_select = host_gnt_locked ? host_gnt_selected : host_gnt_arb_grant;

  for (genvar i = 0; i < GntOrigins; i++) begin
    assign host_gnt_ready_mult[i] = host_gnt_select[i] && host_d_ready;
  end

  // Do the post-arbitration multiplexing
  always_comb begin
    host_d = gnt_t'('x);
    host_d_valid = 1'b0;
    for (int i = GntOrigins - 1; i >= 0; i--) begin
      if (host_gnt_select[i]) begin
        host_d = host_gnt_mult[i];
        host_d_valid = host_gnt_valid_mult[i];
      end
    end
  end

  /////////////////////////////////////////////
  // Request channel handling and core logic //
  /////////////////////////////////////////////

  // Decode the host sending the request.
  logic [NumCachedHosts-1:0] req_selected;
  for (genvar i = 0; i < NumCachedHosts; i++) begin
    assign req_selected[i] = (host_a.source &~ SourceMask[i]) == SourceBase[i];
  end

  // States of the cache.
  typedef enum logic [2:0] {
    StateIdle,
    StateInv,
    StateReq,
    StateGrant,
    StateWait
  } state_e;

  state_e state_q = StateIdle, state_d;
  tl_a_op_e opcode_q, opcode_d;
  logic [AddrWidth-1:0] address_q, address_d;
  logic [1:0] xact_type_q, xact_type_d;
  logic [HostSourceWidth-1:0] source_q, source_d;
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
    host_a_ready = 1'b0;

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
        if (host_a_valid) begin
          opcode_d = host_a.opcode;
          address_d = host_a.address;
          source_d = host_a.source;
          ack_done_d = 1'b0;
          grant_done_d = 1'b0;

          // Send out probe and wait for reply.
          probe_valid = 1'b1;
          probe_mask = ~req_selected;
          state_d = StateInv;
          probe_ack_pending_d = req_selected == 0 ? NumCachedHosts : NumCachedHosts - 1;

          case (host_a.opcode)
            AcquireBlock, AcquirePerm: begin
              xact_type_d = host_a.param == NtoB ? XACT_ACQUIRE_TO_B : XACT_ACQUIRE_TO_T;
              probe_param = host_a.param == NtoB ? toB : toN;
            end
            Get, PutPartialData, PutFullData, LogicalData, ArithmeticData, Intent: begin
              // Uncached requests have no GrantAck message.
              ack_done_d = 1'b1;

              xact_type_d = XACT_UNCACHED;
              probe_param = host_a.opcode == Get ? toB : toN;
            end
          endcase
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
        device_req_valid_mult[1] = host_a_valid;
        device_req_mult[1].opcode = xact_type_q != XACT_UNCACHED ? Get : opcode_q;
        device_req_mult[1].size = host_a.size;
        device_req_mult[1].param = xact_type_q != XACT_UNCACHED ? 0 : host_a.param;
        device_req_mult[1].source = {source_q, xact_type_q};
        device_req_mult[1].address = address_q;
        device_req_mult[1].mask = host_a.mask;
        device_req_mult[1].corrupt = host_a.corrupt;
        device_req_mult[1].data = host_a.data;
        host_a_ready = device_req_ready_mult[1];
        if (device_req_ready_mult[1] && host_a_valid && host_req_last) begin
          state_d = opcode_q == AcquireBlock ? StateWait : StateIdle;
        end
      end

      StateGrant: begin
        host_a_ready = host_a_valid && host_req_last ? host_gnt_ready_mult[1] : 1'b1;
        host_gnt_valid_mult[1] = host_a_valid && host_req_last;
        host_gnt_mult[1].opcode = Grant;
        host_gnt_mult[1].param = xact_type_q;
        host_gnt_mult[1].source = source_q;
        host_gnt_mult[1].size = host_a.size;
        host_gnt_mult[1].denied = 1'b0;
        if (host_gnt_ready_mult[1] && host_a_valid && host_req_last) begin
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

  assign host_b_valid = |probe_pending_q;
  assign host_b.opcode = ProbeBlock;
  assign host_b.param = probe_param_q;
  assign host_b.size = 6;
  assign host_b.address = {address_q[AddrWidth-1:6], 6'd0};

  // Zero or onehot bit mask of currently probing host.
  logic [NumCachedHosts-1:0] probe_selected;
  always_comb begin
    host_b.source = 'x;
    probe_selected = '0;
    for (int i = 0; i < NumCachedHosts; i++) begin
      if (probe_pending_q[i]) begin
        probe_selected = '0;
        probe_selected[i] = 1'b1;
        host_b.source = SourceBase[i];
      end
    end
  end

  always_comb begin
    probe_pending_d = probe_pending_q;
    probe_param_d = probe_param_q;

    probe_ready = probe_pending_q == 0;

    // A probe has been acknowledged
    if (probe_pending_q != 0 && host_b_ready) begin
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
    device_req_mult[0].size = host_c.size;
    device_req_mult[0].source = 'x;
    device_req_mult[0].address = host_c.address;
    device_req_mult[0].mask = get_mask(host_c.address, host_c.size);
    device_req_mult[0].corrupt = host_c.corrupt;
    device_req_mult[0].data = host_c.data;

    // ReleaseAck message in response to a Release.
    host_gnt_valid_mult[0] = 1'b0;
    host_gnt_mult[0].opcode = ReleaseAck;
    host_gnt_mult[0].param = 0;
    host_gnt_mult[0].size = host_c.size;
    host_gnt_mult[0].source = host_c.source;
    host_gnt_mult[0].sink = 'x;
    host_gnt_mult[0].denied = 1'b0;
    host_gnt_mult[0].corrupt = 1'b0;
    host_gnt_mult[0].data = 'x;

    host_c_ready = 1'b0;

    probe_ack_complete = 1'b0;

    if (host_c_valid) begin
      unique case (host_c.opcode)
        ProbeAck: begin
          // Drop
          host_c_ready = 1'b1;
          probe_ack_complete = 1'b1;
        end
        ProbeAckData: begin
          device_req_valid_mult[0] = host_c_valid;
          device_req_mult[0].source = {source_q, XACT_PROBE_ACK_DATA};
          host_c_ready = device_req_ready_mult[0];
        end
        Release: begin
          // Reply with ReleaseAck
          host_gnt_valid_mult[0] = 1'b1;
          host_c_ready = host_gnt_ready_mult[0];
        end
        ReleaseData: begin
          device_req_valid_mult[0] = host_c_valid;
          device_req_mult[0].source = {host_c.source, XACT_RELEASE_DATA};
          host_c_ready = device_req_ready_mult[0];
        end
      endcase
    end
  end

  ////////////////////////////
  // Grant channel handling //
  ////////////////////////////

  always_comb begin
    host_gnt_valid_mult[2] = 1'b0;
    host_gnt_mult[2].opcode = tl_d_op_e'('x);
    host_gnt_mult[2].param = 'x;
    host_gnt_mult[2].size = device_d.size;
    host_gnt_mult[2].source = device_d.source[2+:HostSourceWidth];
    host_gnt_mult[2].sink = 0;
    host_gnt_mult[2].denied = device_d.denied;
    host_gnt_mult[2].corrupt = device_d.corrupt;
    host_gnt_mult[2].data = device_d.data;

    device_d_ready = 1'b0;

    probe_ack_data_complete = 1'b0;
    grant_complete = 1'b0;

    if (device_d_valid) begin
      unique case (device_d.source[1:0])
        XACT_ACQUIRE_TO_T: begin
          // In this case this is XACT_PROBE_ACK_DATA
          if (device_d.opcode == AccessAck) begin
            // Drop
            device_d_ready = 1'b1;
            probe_ack_data_complete = 1'b1;
          end else begin
            host_gnt_valid_mult[2] = 1'b1;
            host_gnt_mult[2].opcode = GrantData;
            host_gnt_mult[2].param = toT;
            device_d_ready = host_gnt_ready_mult[2];

            grant_complete = device_gnt_last;
          end
        end
        XACT_ACQUIRE_TO_B: begin
          host_gnt_valid_mult[2] = 1'b1;
          host_gnt_mult[2].opcode = GrantData;
          host_gnt_mult[2].param = toB;
          device_d_ready = host_gnt_ready_mult[2];

          grant_complete = device_gnt_last;
        end
        XACT_RELEASE_DATA: begin
          host_gnt_valid_mult[2] = 1'b1;
          host_gnt_mult[2].opcode = ReleaseAck;
          host_gnt_mult[2].param = 0;
          host_gnt_mult[2].denied = 0;
          device_d_ready = host_gnt_ready_mult[2];
        end
        XACT_UNCACHED: begin
          host_gnt_valid_mult[2] = 1'b1;
          host_gnt_mult[2].opcode = device_d.opcode;
          host_gnt_mult[2].param = 0;
          device_d_ready = host_gnt_ready_mult[2];

          grant_complete = device_gnt_last;
        end
      endcase
    end
  end

  //////////////////////////////////////
  // Acknowledgement channel handling //
  //////////////////////////////////////

  // Acknowledgement channel is always available.
  assign ack_complete = host_e_valid;
  assign host_e_ready = 1'b1;

endmodule
