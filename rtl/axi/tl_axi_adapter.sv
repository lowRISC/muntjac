`include "tl_util.svh"
`include "axi_util.svh"

// TL-UH to AXI bridge.
//
// SinkWidth is fixed to 1 because sink is unused for TL-UH link.
module tl_axi_adapter import tl_pkg::*; #(
  parameter  int unsigned DataWidth   = 64,
  parameter  int unsigned AddrWidth   = 56,
  parameter  int unsigned SourceWidth = 1,
  parameter  int unsigned MaxSize     = 6,
  parameter  int unsigned IdWidth     = SourceWidth
) (
  input  logic clk_i,
  input  logic rst_ni,

  `TL_DECLARE_DEVICE_PORT(DataWidth, AddrWidth, SourceWidth, 1, host),
  `AXI_DECLARE_HOST_PORT(DataWidth, AddrWidth, IdWidth, device)
);

  localparam NumTracker = 2 ** SourceWidth;

  if (IdWidth < SourceWidth) begin
    $fatal(1, "Not enough IdWidth");
  end

  localparam int unsigned DataWidthInBytes = DataWidth / 8;
  localparam int unsigned NonBurstSize = $clog2(DataWidthInBytes);

  `TL_DECLARE(DataWidth, AddrWidth, SourceWidth, 1, host);
  `AXI_DECLARE(DataWidth, AddrWidth, IdWidth, device);

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

  // Register slice needed because combinational signal from valid to ready.
  axi_regslice #(
    .DataWidth (DataWidth),
    .AddrWidth (AddrWidth),
    .IdWidth (IdWidth),
    .BMode (2),
    .RMode (2)
  ) device_reg (
    .clk_i,
    .rst_ni,
    `AXI_CONNECT_DEVICE_PORT(host, device),
    `AXI_FORWARD_HOST_PORT(device, device)
  );

  /////////////////////////////////////////
  // #region Burst tracker instantiation //

  logic host_a_first;
  logic host_a_last;
  logic host_d_last;

  tl_burst_tracker #(
    .DataWidth (DataWidth),
    .AddrWidth (AddrWidth),
    .SourceWidth (SourceWidth),
    .SinkWidth (1),
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
    .req_first_o (host_a_first),
    .rel_first_o (),
    .gnt_first_o (),
    .req_last_o (host_a_last),
    .rel_last_o (),
    .gnt_last_o (host_d_last)
  );

  // #endregion
  /////////////////////////////////////////

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
  logic                 host_d_locked;
  logic [HostDNums-1:0] host_d_selected;

  openip_round_robin_arbiter #(.WIDTH(HostDNums)) host_d_arb (
    .clk     (clk_i),
    .rstn    (rst_ni),
    .enable  (host_d_valid && host_d_ready && !host_d_locked),
    .request (host_d_valid_mult),
    .grant   (host_d_arb_grant)
  );

  // Perform arbitration, and make sure that until we encounter host_d_last we keep the connection stable.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      host_d_locked <= 1'b0;
      host_d_selected <= '0;
    end
    else begin
      if (host_d_valid && host_d_ready) begin
        if (!host_d_locked) begin
          host_d_locked   <= 1'b1;
          host_d_selected <= host_d_arb_grant;
        end
        if (host_d_last) begin
          host_d_locked <= 1'b0;
        end
      end
    end
  end

  wire [HostDNums-1:0] host_d_select = host_d_locked ? host_d_selected : host_d_arb_grant;

  for (genvar i = 0; i < HostDNums; i++) begin
    assign host_d_ready_mult[i] = host_d_select[i] && host_d_ready;
  end

  // Do the post-arbitration multiplexing
  always_comb begin
    host_d = 'x;
    host_d_valid = 1'b0;
    for (int i = HostDNums - 1; i >= 0; i--) begin
      if (host_d_select[i]) begin
        host_d = host_d_mult[i];
        host_d_valid = host_d_valid_mult[i];
      end
    end
  end

  // #endregion
  ////////////////////////////////////////

  /////////////////////////////////////////
  // #region Pending Transaction Tracker //

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

  // #endregion
  /////////////////////////////////////////

  function automatic logic [7:0] axi_burst_len(input logic [`TL_SIZE_WIDTH-1:0] size);
    if (size <= NonBurstSize) begin
      return 0;
    end else begin
      return (1 << (size - NonBurstSize)) - 1;
    end
  endfunction

  function automatic logic [2:0] axi_burst_size(input logic [`TL_SIZE_WIDTH-1:0] size);
    if (size <= NonBurstSize) begin
      return size;
    end else begin
      return NonBurstSize;
    end
  endfunction

  logic aw_sent_q, aw_sent_d;
  logic w_sent_q, w_sent_d;

  always_comb begin
    host_a_ready = 1'b1;
    device_aw_valid = 1'b0;
    device_aw = 'x;
    device_aw.burst  = axi_pkg::BURST_INCR;
    device_aw.lock   = '0;
    device_aw.cache  = '0;
    device_aw.prot   = '0;
    device_aw.qos    = '0;
    device_aw.region = '0;
    device_w_valid = 1'b0;
    device_w = 'x;
    device_ar_valid = 1'b0;
    device_ar = 'x;
    device_ar.burst  = axi_pkg::BURST_INCR;
    device_ar.lock   = '0;
    device_ar.cache  = '0;
    device_ar.prot   = '0;
    device_ar.qos    = '0;
    device_ar.region = '0;

    aw_sent_d = aw_sent_q;
    w_sent_d = w_sent_q;

    if (host_a_valid) begin
      if (host_a.opcode == Get) begin
        host_a_ready = device_ar_ready;
        device_ar_valid = 1'b1;
        device_ar.addr = host_a.address;
        device_ar.id = host_a.source;
        device_ar.len = axi_burst_len(host_a.size);
        device_ar.size = axi_burst_size(host_a.size);
      end else begin
        if (!aw_sent_q && host_a_first) begin
          device_aw_valid = 1'b1;
          device_aw.addr = host_a.address;
          device_aw.id = host_a.source;
          device_aw.len = axi_burst_len(host_a.size);
          device_aw.size = axi_burst_size(host_a.size);
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
          device_w.last = host_a_last;
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
      host_d_mult[HostDIdxR].size = tracker_info_q[device_r.id];
      host_d_mult[HostDIdxR].source = device_r.id;
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
      host_d_mult[HostDIdxB].size = tracker_info_q[device_b.id];
      host_d_mult[HostDIdxB].source = device_b.id;
      host_d_mult[HostDIdxB].denied = device_b.resp[1];
      host_d_mult[HostDIdxB].corrupt = 1'b0;
      host_d_mult[HostDIdxB].data = 'x;
    end
  end

endmodule
