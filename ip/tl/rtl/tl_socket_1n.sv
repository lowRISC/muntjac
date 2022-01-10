`include "tl_util.svh"

module tl_socket_1n import tl_pkg::*; import prim_util_pkg::*; #(
  parameter  int unsigned SourceWidth   = 1,
  parameter  int unsigned SinkWidth     = 1,
  parameter  int unsigned AddrWidth     = 56,
  parameter  int unsigned DataWidth     = 64,

  parameter  int unsigned MaxSize       = 6,

  // Number of device links
  parameter  int unsigned NumLinks      = 1,
  localparam int unsigned LinkWidth     = vbits(NumLinks),

  // Address routing table.
  // These 4 parameters determine how A and C channel messages are to be routed.
  // When ranges overlap, range that is specified with larger index takes priority.
  // If no ranges match, the message is routed to Link 0.
  parameter int unsigned NumAddressRange = 1,
  parameter logic [NumAddressRange-1:0][AddrWidth-1:0] AddressBase = '0,
  parameter logic [NumAddressRange-1:0][AddrWidth-1:0] AddressMask = '0,
  parameter logic [NumAddressRange-1:0][LinkWidth-1:0] AddressLink = '0,

  // Sink ID routing table.
  // These 4 parameters determine how E channel messages are to be routed.
  // Ranges must not overlap.
  // If no ranges match, the message is routed to Link 0.
  parameter int unsigned NumSinkRange = 1,
  parameter logic [NumSinkRange-1:0][SinkWidth-1:0] SinkBase = '0,
  parameter logic [NumSinkRange-1:0][SinkWidth-1:0] SinkMask = '0,
  parameter logic [NumSinkRange-1:0][LinkWidth-1:0] SinkLink = '0
) (
  input  logic clk_i,
  input  logic rst_ni,

  `TL_DECLARE_DEVICE_PORT(DataWidth, AddrWidth, SourceWidth, SinkWidth, host),
  `TL_DECLARE_HOST_PORT_ARR(DataWidth, AddrWidth, SourceWidth, SinkWidth, device, [NumLinks-1:0])
);

  `TL_DECLARE(DataWidth, AddrWidth, SourceWidth, SinkWidth, host);
  `TL_DECLARE_ARR(DataWidth, AddrWidth, SourceWidth, SinkWidth, device, [NumLinks-1:0]);
  `TL_BIND_DEVICE_PORT(host, host);
  `TL_BIND_HOST_PORT(device, device);

  logic host_gnt_last;

  tl_burst_tracker #(
    .AddrWidth (AddrWidth),
    .DataWidth (DataWidth),
    .SourceWidth (SourceWidth),
    .SinkWidth (SinkWidth),
    .MaxSize (MaxSize)
  ) host_burst_tracker (
    .clk_i,
    .rst_ni,
    `TL_FORWARD_TAP_PORT_FROM_DEVICE(link, host),
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
    .req_last_o (),
    .rel_last_o (),
    .gnt_last_o (host_gnt_last)
  );

  ///////////////////////////////////
  // Request channel demultiplexer //
  ///////////////////////////////////

  logic [LinkWidth-1:0] req_device_id;

  always_comb begin
    req_device_id = 0;
    for (int i = 0; i < NumAddressRange; i++) begin
      if ((host_a.address &~ AddressMask[i]) == AddressBase[i]) begin
        req_device_id = AddressLink[i];
      end
    end
  end

  logic [NumLinks-1:0] req_ready_mult;

  for (genvar i = 0; i < NumLinks; i++) begin
    assign req_ready_mult[i] = host_a_valid && req_device_id == i && device_a_ready[i];
    assign device_a_valid[i] = host_a_valid && req_device_id == i;

    assign device_a[i] = host_a;
  end

  assign host_a_ready = |req_ready_mult;

  ///////////////////////////////
  // Probe channel arbitration //
  ///////////////////////////////

  logic [NumLinks-1:0] prb_arb_grant;

  openip_round_robin_arbiter #(.WIDTH(NumLinks)) prb_arb (
    .clk     (clk_i),
    .rstn    (rst_ni),
    .enable  (host_b_valid && host_b_ready),
    .request (device_b_valid),
    .grant   (prb_arb_grant)
  );

  for (genvar i = 0; i < NumLinks; i++) begin
    assign device_b_ready[i] = prb_arb_grant[i] && host_b_ready;
  end

  // Do the post-arbitration multiplexing
  always_comb begin
    host_b = 'x;
    host_b_valid = 1'b0;
    for (int i = NumLinks - 1; i >= 0; i--) begin
      if (prb_arb_grant[i]) begin
        host_b = device_b[i];
        host_b_valid = device_b_valid[i];
      end
    end
  end

  ///////////////////////////////////
  // Release channel demultiplexer //
  ///////////////////////////////////

  logic [LinkWidth-1:0] rel_device_id;

  always_comb begin
    rel_device_id = 0;
    for (int i = 0; i < NumAddressRange; i++) begin
      if ((host_c.address &~ AddressMask[i]) == AddressBase[i]) begin
        rel_device_id = AddressLink[i];
      end
    end
  end

  logic [NumLinks-1:0] rel_ready_mult;

  for (genvar i = 0; i < NumLinks; i++) begin
    assign rel_ready_mult[i] = host_c_valid && rel_device_id == i && device_c_ready[i];
    assign device_c_valid[i] = host_c_valid && rel_device_id == i;

    assign device_c[i] = host_c;
  end

  assign host_c_ready = |rel_ready_mult;

  ///////////////////////////////
  // Grant channel arbitration //
  ///////////////////////////////

  // Signals for arbitration
  logic [NumLinks-1:0] gnt_arb_grant;
  logic                gnt_locked;
  logic [NumLinks-1:0] gnt_selected;

  openip_round_robin_arbiter #(.WIDTH(NumLinks)) gnt_arb (
    .clk     (clk_i),
    .rstn    (rst_ni),
    .enable  (host_d_valid && host_d_ready && !gnt_locked),
    .request (device_d_valid),
    .grant   (gnt_arb_grant)
  );

  // Perform arbitration, and make sure that until we encounter host_gnt_last we keep the connection stable.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      gnt_locked <= 1'b0;
      gnt_selected <= '0;
    end
    else begin
      if (host_d_valid && host_d_ready) begin
        if (!gnt_locked) begin
          gnt_locked   <= 1'b1;
          gnt_selected <= gnt_arb_grant;
        end
        if (host_gnt_last) begin
          gnt_locked <= 1'b0;
        end
      end
    end
  end

  wire [NumLinks-1:0] gnt_select = gnt_locked ? gnt_selected : gnt_arb_grant;

  for (genvar i = 0; i < NumLinks; i++) begin
    assign device_d_ready[i] = gnt_select[i] && host_d_ready;
  end

  // Do the post-arbitration multiplexing
  always_comb begin
    host_d = 'x;
    host_d_valid = 1'b0;
    for (int i = NumLinks - 1; i >= 0; i--) begin
      if (gnt_select[i]) begin
        host_d = device_d[i];
        host_d_valid = device_d_valid[i];
      end
    end
  end

  ///////////////////////////////////////////
  // Acknowledgement channel demultiplexer //
  ///////////////////////////////////////////

  logic [LinkWidth-1:0] ack_device_id;

  always_comb begin
    ack_device_id = 0;
    for (int i = 0; i < NumSinkRange; i++) begin
      if ((host_e.sink &~ SinkMask[i]) == SinkBase[i]) begin
        ack_device_id = SinkLink[i];
      end
    end
  end

  logic [NumLinks-1:0] ack_ready_mult;

  for (genvar i = 0; i < NumLinks; i++) begin
    assign ack_ready_mult[i] = host_e_valid && ack_device_id == i && device_e_ready[i];
    assign device_e_valid[i] = host_e_valid && ack_device_id == i;

    assign device_e[i] = host_e;
  end

  assign host_e_ready = |ack_ready_mult;

endmodule
