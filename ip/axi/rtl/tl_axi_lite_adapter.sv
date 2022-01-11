`include "tl_util.svh"
`include "axi_util.svh"

// TL-UL to AXI-Lite bridge.
//
// SinkWidth is fixed to 1 because sink is unused for TL-UL link.
// MaxSize is fixed to $clog2(DataWidth) because burst is not supported for TL-UL.
module tl_axi_lite_adapter import tl_pkg::*; #(
  parameter  int unsigned DataWidth   = 64,
  parameter  int unsigned AddrWidth   = 56,
  parameter  int unsigned SourceWidth = 1
) (
  input  logic clk_i,
  input  logic rst_ni,

  `TL_DECLARE_DEVICE_PORT(DataWidth, AddrWidth, SourceWidth, 1, host),
  `AXI_LITE_DECLARE_HOST_PORT(DataWidth, AddrWidth, device)
);

  `TL_DECLARE(DataWidth, AddrWidth, SourceWidth, 1, host);
  `AXI_LITE_DECLARE(DataWidth, AddrWidth, device);

  // Register slice needed because we may use host_a without asserting host_a_ready.
  tl_regslice #(
    .DataWidth (DataWidth),
    .AddrWidth (AddrWidth),
    .SourceWidth (SourceWidth),
    .SinkWidth (1),
    .RequestMode (2)
  ) host_reg (
    .clk_i,
    .rst_ni,
    `TL_FORWARD_DEVICE_PORT(host, host),
    `TL_CONNECT_HOST_PORT(device, host)
  );

  // Register slice needed because we may use host_a without asserting host_a_ready.
  axi_lite_regslice #(
    .DataWidth (DataWidth),
    .AddrWidth (AddrWidth),
    .BMode (2),
    .RMode (2)
  ) device_reg (
    .clk_i,
    .rst_ni,
    `AXI_CONNECT_DEVICE_PORT(host, device),
    `AXI_FORWARD_HOST_PORT(device, device)
  );

  /////////////////////////////
  // #region Unused channels //

  assign host_b_valid = 1'b0;
  assign host_b       = 'x;
  assign host_c_ready = 1'b1;
  assign host_e_ready = 1'b1;

  // #endregion
  /////////////////////////////

  ////////////////////////////////////////
  // #region Host D Channel arbitration //

  typedef `TL_D_STRUCT(DataWidth, AddrWidth, SourceWidth, 1) host_d_t;

  localparam HostDNums = 2;
  localparam HostDIdxB = 0;
  localparam HostDIdxR = 1;

  // Grouped signals before multiplexing/arbitration
  host_d_t [HostDNums-1:0] host_d_mult;
  logic    [HostDNums-1:0] host_d_valid_mult;
  logic    [HostDNums-1:0] host_d_ready_mult;

  // Signals for arbitration
  logic [HostDNums-1:0] host_d_arb_grant;

  openip_round_robin_arbiter #(.WIDTH(HostDNums)) host_d_arb (
    .clk     (clk_i),
    .rstn    (rst_ni),
    .enable  (host_d_valid && host_d_ready && !host_d_locked),
    .request (host_d_valid_mult),
    .grant   (host_d_arb_grant)
  );

  // No burst is allowed for TL-UL or AXI-Lite, so no lock signals are needed.
  for (genvar i = 0; i < HostDNums; i++) begin
    assign host_d_ready_mult[i] = host_d_arb_grant[i] && host_d_ready;
  end

  // Do the post-arbitration multiplexing
  always_comb begin
    host_d = 'x;
    host_d_valid = 1'b0;
    for (int i = HostDNums - 1; i >= 0; i--) begin
      if (host_d_arb_grant[i]) begin
        host_d = host_d_mult[i];
        host_d_valid = host_d_valid_mult[i];
      end
    end
  end

  // #endregion
  ////////////////////////////////////////

  /////////////////////////////////////////
  // #region Pending Transaction Tracker //

  logic                      tracker_valid_q, tracker_valid_d;
  logic [`TL_SIZE_WIDTH-1:0] tracker_size_q, tracker_size_d;
  logic [SourceWidth-1:0]    tracker_source_q, tracker_source_d;

  always_comb begin
    tracker_valid_d = tracker_valid_q;
    tracker_size_d = tracker_size_q;
    tracker_source_d = tracker_source_q;

    // Remove from tracker when a response is completed.
    if (host_d_valid && host_d_ready) begin
      tracker_valid_d = 1'b0;
      tracker_size_d = 'x;
      tracker_source_d = 'x;
    end

    // Add to tracker when a request begins.
    if (host_a_valid && host_a_ready) begin
      tracker_valid_d = 1'b1;
      tracker_size_d = host_a.size;
      tracker_source_d = host_a.source;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      tracker_valid_q <= '0;
      tracker_size_q <= 'x;
      tracker_source_q <= 'x;
    end else begin
      tracker_valid_q <= tracker_valid_d;
      tracker_size_q <= tracker_size_d;
      tracker_source_q <= tracker_source_d;
    end
  end

  // #endregion
  /////////////////////////////////////////

  logic aw_sent_q, aw_sent_d;
  logic w_sent_q, w_sent_d;

  always_comb begin
    host_a_ready = 1'b0;
    device_aw_valid = 1'b0;
    device_aw = 'x;
    device_aw.prot = '0;
    device_w_valid = 1'b0;
    device_w = 'x;
    device_ar_valid = 1'b0;
    device_ar = 'x;
    device_ar.prot = '0;

    aw_sent_d = aw_sent_q;
    w_sent_d = w_sent_q;

    if (host_a_valid && !tracker_valid_q) begin
      host_a_ready = 1'b1;

      if (host_a.opcode == Get) begin
        host_a_ready = device_ar_ready;
        device_ar_valid = 1'b1;
        device_ar.addr = host_a.address;
      end else begin
        if (!aw_sent_q) begin
          device_aw_valid = 1'b1;
          device_aw.addr = host_a.address;
          if (device_aw_ready) begin
            aw_sent_d = 1'b1;
          end else begin
            host_a_ready = 1'b0;
          end
        end

        if (!w_sent_q) begin
          device_w_valid = 1'b1;
          device_w.data = host_a.data;
          device_w.strb = host_a.mask;
          if (device_w_ready) begin
            w_sent_d = 1'b1;
          end else begin
            host_a_ready = 1'b0;
          end
        end

        if (host_a_ready) begin
          aw_sent_d = 1'b0;
          w_sent_d = 1'b0;
        end
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      aw_sent_q <= 1'b0;
      w_sent_q <= 1'b0;
    end else begin
      aw_sent_q <= aw_sent_d;
      w_sent_q <= w_sent_d;
    end
  end

  always_comb begin
    device_r_ready = 1'b0;
    host_d_valid_mult[HostDIdxR] = 1'b0;
    host_d_mult[HostDIdxR] = 'x;

    if (device_r_valid) begin
      device_r_ready = host_d_ready_mult[HostDIdxR];
      host_d_valid_mult[HostDIdxR] = 1'b1;
      host_d_mult[HostDIdxR].opcode = AccessAckData;
      host_d_mult[HostDIdxR].param = 0;
      host_d_mult[HostDIdxR].size = tracker_size_q;
      host_d_mult[HostDIdxR].source = tracker_source_q;
      host_d_mult[HostDIdxR].denied = device_r.resp[1];
      host_d_mult[HostDIdxR].corrupt = 1'b0;
      host_d_mult[HostDIdxR].data = device_r.data;
    end
  end

  always_comb begin
    device_b_ready = 1'b0;
    host_d_valid_mult[HostDIdxB] = 1'b0;
    host_d_mult[HostDIdxB] = 'x;

    if (device_b_valid) begin
      device_b_ready = host_d_ready_mult[HostDIdxB];
      host_d_valid_mult[HostDIdxB] = 1'b1;
      host_d_mult[HostDIdxB].opcode = AccessAck;
      host_d_mult[HostDIdxB].param = 0;
      host_d_mult[HostDIdxB].size = tracker_size_q;
      host_d_mult[HostDIdxB].source = tracker_source_q;
      host_d_mult[HostDIdxB].denied = device_b.resp[1];
      host_d_mult[HostDIdxB].corrupt = 1'b0;
      host_d_mult[HostDIdxB].data = 'x;
    end
  end

endmodule
