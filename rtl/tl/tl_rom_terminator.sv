`include "tl_util.svh"

module tl_rom_terminator import tl_pkg::*; import muntjac_pkg::*; #(
  parameter  int unsigned DataWidth   = 64,
  parameter  int unsigned AddrWidth   = 56,
  parameter  int unsigned SourceWidth = 1,
  parameter  int unsigned SinkWidth   = 1,
  parameter  int unsigned MaxSize     = 6,

  parameter  bit [SinkWidth-1:0] SinkBase = 0
) (
  input  logic clk_i,
  input  logic rst_ni,

  `TL_DECLARE_DEVICE_PORT(DataWidth, AddrWidth, SourceWidth, SinkWidth, host),
  `TL_DECLARE_HOST_PORT(DataWidth, AddrWidth, SourceWidth, SinkWidth, device)
);

  `TL_DECLARE(DataWidth, AddrWidth, SourceWidth, SinkWidth, host);
  `TL_DECLARE(DataWidth, AddrWidth, SourceWidth, SinkWidth, device);
  `TL_BIND_HOST_PORT(device, device);

  tl_regslice #(
    .AddrWidth (AddrWidth),
    .DataWidth (DataWidth),
    .SourceWidth (SourceWidth),
    .SinkWidth (SinkWidth),
    .RequestMode (2)
  ) host_reg (
    .clk_i,
    .rst_ni,
    `TL_FORWARD_DEVICE_PORT(host, host),
    `TL_CONNECT_HOST_PORT(device, host)
  );

  /////////////////////////////////
  // Burst tracker instantiation //
  /////////////////////////////////

  wire host_req_last;
  wire host_c_first;
  wire host_d_last;
  wire device_req_last;
  wire device_gnt_last;

  tl_burst_tracker #(
    .AddrWidth (AddrWidth),
    .DataWidth (DataWidth),
    .SourceWidth (SourceWidth),
    .SinkWidth (SinkWidth),
    .MaxSize (MaxSize)
  ) host_burst_tracker (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_TAP_PORT(link, host),
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
    .rel_last_o (host_c_first),
    .gnt_last_o (host_d_last)
  );

  tl_burst_tracker #(
    .AddrWidth (AddrWidth),
    .DataWidth (DataWidth),
    .SourceWidth (SourceWidth),
    .SinkWidth (SinkWidth),
    .MaxSize (MaxSize)
  ) device_burst_tracker (
    .clk_i,
    .rst_ni,
    `TL_FORWARD_TAP_PORT_FROM_HOST(link, device),
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

  assign host_b_valid   = 1'b0;
  assign host_b         = 'x;

  assign device_b_ready = 1'b1;

  assign device_c_valid = 1'b0;
  assign device_c       = 'x;

  assign device_e_valid = 1'b0;
  assign device_e       = 'x;

  ///////////////////////////////
  // Grant channel arbitration //
  ///////////////////////////////

  typedef `TL_D_STRUCT(DataWidth, AddrWidth, SourceWidth, SinkWidth) gnt_t;

  // We have 2 origins of D channel response to host:
  // 0. ReleaseAck response to host's Release
  // 2. Device D channel response
  localparam GntOrigins = 2;
  localparam GntIdxRel = 0;
  localparam GntIdxResp = 1;

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

  // Perform arbitration, and make sure that until we encounter host_d_last we keep the connection stable.
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
        if (host_d_last) begin
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

  ///////////////////////
  // Handle ROM memory //
  ///////////////////////

  logic req_allowed;
  always_comb begin
    case (host_a.opcode)
      AcquireBlock, AcquirePerm: begin
        req_allowed = host_a.param == NtoB;
      end
      Get: begin
        req_allowed = 1'b1;
      end
      default: begin
        req_allowed = 1'b0;
      end
    endcase
  end

  typedef enum logic [3:0] {
    IoStateIdle,
    IoStateActive,
    IoStateException,
    IoStateAckWait
  } io_state_e;

  io_state_e io_state_q, io_state_d;
  tl_a_op_e io_opcode_q, io_opcode_d;
  logic [2:0] io_param_q, io_param_d;
  logic io_req_sent_q, io_req_sent_d;
  logic io_resp_sent_q, io_resp_sent_d;
  logic io_ack_done_q, io_ack_done_d;

  assign host_e_ready = 1'b1;

  always_comb begin
    device_a_valid = 1'b0;
    device_a = 'x;

    host_gnt_valid_mult[GntIdxResp] = 1'b0;
    host_gnt_mult[GntIdxResp] = 'x;

    device_d_ready = 1'b0;

    host_a_ready = 1'b0;

    io_state_d = io_state_q;
    io_opcode_d = io_opcode_q;
    io_param_d = io_param_q;
    io_req_sent_d = io_req_sent_q;
    io_resp_sent_d = io_resp_sent_q;
    io_ack_done_d = io_ack_done_q;

    if (host_e_valid) io_ack_done_d = 1'b1;

    unique case (io_state_q)
      IoStateIdle: begin
        if (host_a_valid) begin
          io_opcode_d = host_a.opcode;
          io_param_d = host_a.param == NtoB ? toB : toT;
          io_req_sent_d = 1'b0;
          io_resp_sent_d = 1'b0;
          io_ack_done_d = !(host_a.opcode inside {AcquireBlock, AcquirePerm});

          if (req_allowed) begin
            io_state_d = IoStateActive;
          end else begin
            io_state_d = IoStateException;
          end
        end
      end

      IoStateActive: begin
        device_a_valid = !io_req_sent_q && host_a_valid;
        device_a.opcode = io_opcode_q == AcquireBlock ? Get : io_opcode_q;
        device_a.param = 0;
        device_a.size = host_a.size;
        device_a.source = host_a.source;
        device_a.address = host_a.address;
        device_a.mask = host_a.mask;
        device_a.corrupt = 1'b0;
        device_a.data = host_a.data;

        host_a_ready = !io_req_sent_q && device_a_ready;
        if (host_a_valid && device_a_ready && host_req_last) begin
          io_req_sent_d = 1'b1;
        end

        device_d_ready = !io_resp_sent_q && host_gnt_ready_mult[GntIdxResp];
        host_gnt_valid_mult[GntIdxResp] = device_d_valid;
        host_gnt_mult[GntIdxResp].opcode = io_opcode_q == AcquireBlock ? GrantData : device_d.opcode;
        host_gnt_mult[GntIdxResp].param = io_param_q;
        host_gnt_mult[GntIdxResp].size = device_d.size;
        host_gnt_mult[GntIdxResp].source = device_d.source;
        host_gnt_mult[GntIdxResp].sink = SinkBase;
        host_gnt_mult[GntIdxResp].denied = device_d.denied;
        host_gnt_mult[GntIdxResp].corrupt = device_d.corrupt;
        host_gnt_mult[GntIdxResp].data = device_d.data;

        if (device_d_valid && host_gnt_ready_mult[GntIdxResp] && device_gnt_last) begin
          io_resp_sent_d = 1'b1;
        end

        if (io_req_sent_d && io_resp_sent_d && io_ack_done_d) begin
          io_state_d = IoStateIdle;
        end
      end

      IoStateException: begin
        // If we haven't see last, we need to make sure the entire request is discarded,
        // not just the first cycle of the burst.
        if (!(host_a_valid && host_req_last)) begin
          host_a_ready = 1'b1;
        end else begin
          host_gnt_valid_mult[GntIdxResp] = 1'b1;
          host_gnt_mult[GntIdxResp].opcode = host_a.opcode == AcquireBlock ? Grant : (host_a.opcode == Get ? AccessAckData : AccessAck);
          host_gnt_mult[GntIdxResp].param = 0;
          host_gnt_mult[GntIdxResp].size = host_a.size;
          host_gnt_mult[GntIdxResp].source = host_a.source;
          host_gnt_mult[GntIdxResp].sink = SinkBase;
          host_gnt_mult[GntIdxResp].denied = 1'b1;
          host_gnt_mult[GntIdxResp].corrupt = host_a.opcode == Get ? 1'b1 : 1'b0;

          if (host_gnt_ready_mult[GntIdxResp]) begin
            if (host_d_last) begin
              host_a_ready = 1'b1;

              io_state_d = IoStateAckWait;
            end
          end
        end
      end

      IoStateAckWait: begin
        if (io_ack_done_d) io_state_d = IoStateIdle;
      end

      default:;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      io_state_q <= IoStateIdle;
      io_opcode_q <= tl_a_op_e'('x);
      io_param_q <= 'x;
      io_req_sent_q <= 1'b0;
      io_resp_sent_q <= 1'b0;
      io_ack_done_q <= 1'b0;
    end
    else begin
      io_state_q <= io_state_d;
      io_opcode_q <= io_opcode_d;
      io_param_q <= io_param_d;
      io_req_sent_q <= io_req_sent_d;
      io_resp_sent_q <= io_resp_sent_d;
      io_ack_done_q <= io_ack_done_d;
    end
  end

  //////////////////////////////
  // Release channel handling //
  //////////////////////////////

  // This terminator backs ROM or IO memory. We never send out any Probe, so the only possible
  // message on channel C is Release and since no dirty cache line writeback is possible we can
  // just respond with ReleaseAck.
  //
  // We simply use combinational logic to respond: respond on the first beat of host_c message.

  assign host_c_ready = host_c_valid && host_c_first ? host_gnt_ready_mult[GntIdxRel] : 1'b1;
  assign host_gnt_valid_mult[GntIdxRel] = host_c_valid && host_c_first;
  assign host_gnt_mult[GntIdxRel].opcode = ReleaseAck;
  assign host_gnt_mult[GntIdxRel].param = 0;
  assign host_gnt_mult[GntIdxRel].source = host_c.source;
  assign host_gnt_mult[GntIdxRel].sink = SinkBase;
  assign host_gnt_mult[GntIdxRel].denied = 1'b0;
  assign host_gnt_mult[GntIdxRel].corrupt = 1'b0;
  assign host_gnt_mult[GntIdxRel].data = 'x;

endmodule
