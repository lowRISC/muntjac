`include "tl_util.svh"

module tl_socket_m1 import tl_pkg::*; import prim_util_pkg::*; #(
  parameter  int unsigned SourceWidth   = 1,
  parameter  int unsigned SinkWidth     = 1,
  parameter  int unsigned AddrWidth     = 56,
  parameter  int unsigned DataWidth     = 64,

  parameter  int unsigned MaxSize        = 6,
  parameter  int unsigned NumCachedHosts = 1,

  // Number of host links
  parameter  int unsigned NumLinks       = 1,
  localparam int unsigned LinkWidth     = vbits(NumLinks),
  // Number of host links that contain cached hosts
  parameter  int unsigned NumCachedLinks = NumLinks,

  // Source ID routing table.
  // These 4 parameters determine how B and C channel messages are to be routed.
  // Ranges must not overlap.
  // If no ranges match, the message is routed to Link 0.
  parameter int unsigned NumSourceRange = 1,
  parameter logic [NumSourceRange-1:0][SourceWidth-1:0] SourceBase = '0,
  parameter logic [NumSourceRange-1:0][SourceWidth-1:0] SourceMask = '0,
  parameter logic [NumSourceRange-1:0][LinkWidth-1:0]   SourceLink = '0
) (
  input  logic clk_i,
  input  logic rst_ni,

  `TL_DECLARE_DEVICE_PORT_ARR(DataWidth, AddrWidth, SourceWidth, SinkWidth, host, [NumLinks-1:0]),
  `TL_DECLARE_HOST_PORT(DataWidth, AddrWidth, SourceWidth, SinkWidth, device)
);

  `TL_DECLARE_ARR(DataWidth, AddrWidth, SourceWidth, SinkWidth, host, [NumLinks-1:0]);
  `TL_DECLARE(DataWidth, AddrWidth, SourceWidth, SinkWidth, device);
  `TL_BIND_DEVICE_PORT(host, host);
  `TL_BIND_HOST_PORT(device, device);

  logic device_req_last;
  logic device_rel_last;

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
    .rel_last_o (device_rel_last),
    .gnt_last_o ()
  );

  /////////////////////
  // Unused channels //
  /////////////////////

  for (genvar i = NumCachedLinks; i < NumLinks; i++) begin
    // We don't use channel B for non-caheable hosts.
    assign host_b_valid[i] = 1'b0;
    assign host_b[i]       = 'x;

    // We don't use channel C and E for non-caheable hosts.
    assign host_c_ready[i] = 1'b1;
    assign host_e_ready[i] = 1'b1;
  end

  /////////////////////////////////
  // Request channel arbitration //
  /////////////////////////////////

  logic [NumLinks-1:0] req_arb_grant;
  logic                req_locked;
  logic [NumLinks-1:0] req_selected;

  openip_round_robin_arbiter #(.WIDTH(NumLinks)) req_arb (
    .clk     (clk_i),
    .rstn    (rst_ni),
    .enable  (device_a_valid && device_a_ready && !req_locked),
    .request (host_a_valid),
    .grant   (req_arb_grant)
  );

  // Perform arbitration, and make sure that until we encounter device_req_last we keep the connection stable.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      req_locked <= 1'b0;
      req_selected <= '0;
    end
    else begin
      if (device_a_valid && device_a_ready) begin
        if (!req_locked) begin
          req_locked   <= 1'b1;
          req_selected <= req_arb_grant;
        end
        if (device_req_last) begin
          req_locked <= 1'b0;
        end
      end
    end
  end

  wire [NumLinks-1:0] req_select = req_locked ? req_selected : req_arb_grant;

  for (genvar i = 0; i < NumLinks; i++) begin
    assign host_a_ready[i] = req_select[i] && device_a_ready;
  end

  // Do the post-arbitration multiplexing
  always_comb begin
    device_a = 'x;
    device_a_valid = 1'b0;
    for (int i = NumLinks - 1; i >= 0; i--) begin
      if (req_select[i]) begin
        device_a = host_a[i];
        device_a_valid = host_a_valid[i];
      end
    end
  end

  /////////////////////////////////
  // Probe channel demultiplexer //
  /////////////////////////////////

  if (NumCachedLinks != 0) begin: prb_demux

    logic [LinkWidth-1:0] prb_host_id;

    always_comb begin
      prb_host_id = 0;
      for (int i = 0; i < NumSourceRange; i++) begin
        if ((device_b.source &~ SourceMask[i]) == SourceBase[i]) begin
          prb_host_id = SourceLink[i];
        end
      end
    end

    logic [NumCachedLinks-1:0] prb_ready_mult;

    for (genvar i = 0; i < NumCachedLinks; i++) begin
      assign prb_ready_mult[i] = device_b_valid && prb_host_id == i && host_b_ready[i];
      assign host_b_valid[i]   = device_b_valid && prb_host_id == i;

      assign host_b[i] = device_b;
    end

    assign device_b_ready = |prb_ready_mult;

  end else begin

    assign device_b_ready = 1'b1;

  end

  /////////////////////////////////
  // Release channel arbitration //
  /////////////////////////////////

  if (NumCachedLinks != 0) begin: rel_arb

    logic [NumCachedLinks-1:0] rel_arb_grant;
    logic                      rel_locked;
    logic [NumCachedLinks-1:0] rel_selected;

    openip_round_robin_arbiter #(.WIDTH(NumCachedLinks)) rel_arb (
      .clk     (clk_i),
      .rstn    (rst_ni),
      .enable  (device_c_valid && device_c_ready && !rel_locked),
      .request (host_c_valid[NumCachedLinks-1:0]),
      .grant   (rel_arb_grant)
    );

    // Perform arbitration, and make sure that until we encounter device_rel_last we keep the connection stable.
    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        rel_locked <= 1'b0;
        rel_selected <= '0;
      end
      else begin
        if (device_c_valid && device_c_ready) begin
          if (!rel_locked) begin
            rel_locked   <= 1'b1;
            rel_selected <= rel_arb_grant;
          end
          if (device_rel_last) begin
            rel_locked <= 1'b0;
          end
        end
      end
    end

    wire [NumCachedLinks-1:0] rel_select = rel_locked ? rel_selected : rel_arb_grant;

    for (genvar i = 0; i < NumCachedLinks; i++) begin
      assign host_c_ready[i] = rel_select[i] && device_c_ready;
    end

    // Do the post-arbitration multiplexing
    always_comb begin
      device_c = 'x;
      device_c_valid = 1'b0;
      for (int i = NumCachedLinks - 1; i >= 0; i--) begin
        if (rel_select[i]) begin
          device_c = host_c[i];
          device_c_valid = host_c_valid[i];
        end
      end
    end

  end else begin

    assign device_c_valid = 1'b0;
    assign device_c       = 'x;

  end

  /////////////////////////////////
  // Grant channel demultiplexer //
  /////////////////////////////////

  logic [LinkWidth-1:0] gnt_host_id;

  always_comb begin
    gnt_host_id = 0;
    for (int i = 0; i < NumSourceRange; i++) begin
      if ((device_d.source &~ SourceMask[i]) == SourceBase[i]) begin
        gnt_host_id = SourceLink[i];
      end
    end
  end

  logic [NumLinks-1:0] gnt_ready_mult;

  for (genvar i = 0; i < NumLinks; i++) begin
    assign gnt_ready_mult[i] = device_d_valid && gnt_host_id == i && host_d_ready[i];
    assign host_d_valid[i]   = device_d_valid && gnt_host_id == i;

    assign host_d[i] = device_d;
  end

  assign device_d_ready = |gnt_ready_mult;

  /////////////////////////////////////////
  // Acknowledgement channel arbitration //
  /////////////////////////////////////////

  if (NumCachedLinks != 0) begin: ack_arb

    logic [NumCachedLinks-1:0] ack_arb_grant;

    openip_round_robin_arbiter #(.WIDTH(NumCachedLinks)) ack_arb (
      .clk     (clk_i),
      .rstn    (rst_ni),
      .enable  (device_e_valid && device_e_ready),
      .request (host_e_valid[NumCachedLinks-1:0]),
      .grant   (ack_arb_grant)
    );

    for (genvar i = 0; i < NumCachedLinks; i++) begin
      assign host_e_ready[i] = ack_arb_grant[i] && device_e_ready;
    end

    // Do the post-arbitration multiplexing
    always_comb begin
      device_e = 'x;
      device_e_valid = 1'b0;
      for (int i = NumCachedLinks - 1; i >= 0; i--) begin
        if (ack_arb_grant[i]) begin
          device_e = host_e[i];
          device_e_valid = host_e_valid[i];
        end
      end
    end

  end else begin

    assign device_e_valid = 1'b0;
    assign device_e       = 'x;

  end

endmodule
