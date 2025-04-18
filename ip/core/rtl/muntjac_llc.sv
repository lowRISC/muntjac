`include "prim_assert.sv"
`include "tl_util.svh"

module muntjac_llc import tl_pkg::*; import muntjac_pkg::*; import prim_util_pkg::*; #(
  // Number of sets is `2 ** SetsWidth`
  parameter SetsWidth = 8,
  // Number of ways is `2 ** WaysWidth`.
  parameter WaysWidth = 2,

  parameter DataWidth = 64,
  parameter AddrWidth = 56,
  parameter SourceWidth = 1,
  parameter int unsigned SinkWidth   = 1,

  parameter bit [SinkWidth-1:0] SinkBase = 0,
  parameter bit [SinkWidth-1:0] SinkMask = 0,

  parameter bit [SourceWidth-1:0] DeviceSourceBase = 0,
  parameter bit [SourceWidth-1:0] DeviceSourceMask = 0,

  parameter muntjac_pkg::release_policy_e ReleasePolicy = muntjac_pkg::ReleaseDirty,
  parameter int RelTrackerNum = 1,
  parameter int AcqTrackerNum = 1,
  parameter bit EnableHpm     = 0,

  // Source ID table for cacheable hosts.
  // These IDs are used for sending out Probe messages.
  // Ranges must not overlap.
  parameter NumCachedHosts = 1,
  parameter logic [NumCachedHosts-1:0][SourceWidth-1:0] SourceBase = '0,
  parameter logic [NumCachedHosts-1:0][SourceWidth-1:0] SourceMask = '0
) (
  input  logic clk_i,
  input  logic rst_ni,

  output logic hpm_acq_count_o,
  output logic hpm_rel_count_o,
  output logic hpm_miss_o,

  `TL_DECLARE_DEVICE_PORT(DataWidth, AddrWidth, SourceWidth, SinkWidth, host),
  `TL_DECLARE_HOST_PORT(DataWidth, AddrWidth, SourceWidth, SinkWidth, device)
);

  localparam WbTrackerNum = 1;

  localparam SinkNums = SinkMask + 1;
  localparam SourceNums = DeviceSourceMask + 1;

  if (WbTrackerNum > SourceNums || AcqTrackerNum > SourceNums || AcqTrackerNum > SinkNums) begin
    $fatal(1, "Not enough source or sinks for all trackers");
  end

  localparam NumWays = 2 ** WaysWidth;
  localparam MaxSize = 6;

  // A cache line is 64 bytes
  localparam LineWidth = 6;

  localparam DataWidthInBytes = DataWidth / 8;
  localparam NonBurstSize = $clog2(DataWidthInBytes);
  localparam OffsetWidth = LineWidth - NonBurstSize;

  `TL_DECLARE(DataWidth, AddrWidth, SourceWidth, SinkWidth, host);
  `TL_DECLARE(DataWidth, AddrWidth, SourceWidth, SinkWidth, device);

  // Registers host_a and host_c so its content will hold until we consumed it.
  tl_regslice #(
    .DataWidth (DataWidth),
    .AddrWidth (AddrWidth),
    .SourceWidth (SourceWidth),
    .SinkWidth (SinkWidth),
    .RequestMode (2),
    .ReleaseMode (2),
    .GrantMode (7)
  ) host_reg (
    .clk_i,
    .rst_ni,
    `TL_FORWARD_DEVICE_PORT(host, host),
    `TL_CONNECT_HOST_PORT(device, host)
  );

  // Registers device_d so its content will hold until we consumed it.
  tl_regslice #(
    .DataWidth (DataWidth),
    .AddrWidth (AddrWidth),
    .SourceWidth (SourceWidth),
    .SinkWidth (SinkWidth),
    .GrantMode (2),
    .AckMode (2)
  ) device_reg (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_DEVICE_PORT(host, device),
    `TL_FORWARD_HOST_PORT(device, device)
  );

  /////////////////////////////////
  // Burst tracker instantiation //
  /////////////////////////////////

  wire host_a_last;
  wire host_c_last;
  wire host_d_last;
  wire device_a_last;
  wire device_c_last;
  wire device_d_last;

  logic [OffsetWidth-1:0] host_c_idx;
  logic [OffsetWidth-1:0] device_d_idx;

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
    .rel_len_o (),
    .gnt_len_o (),
    .req_idx_o (),
    .rel_idx_o (host_c_idx),
    .gnt_idx_o (),
    .req_left_o (),
    .rel_left_o (),
    .gnt_left_o (),
    .req_first_o (),
    .rel_first_o (),
    .gnt_first_o (),
    .req_last_o (host_a_last),
    .rel_last_o (host_c_last),
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
    `TL_CONNECT_TAP_PORT(link, device),
    .req_len_o (),
    .rel_len_o (),
    .gnt_len_o (),
    .req_idx_o (),
    .rel_idx_o (),
    .gnt_idx_o (device_d_idx),
    .req_left_o (),
    .rel_left_o (),
    .gnt_left_o (),
    .req_first_o (),
    .rel_first_o (),
    .gnt_first_o (),
    .req_last_o (device_a_last),
    .rel_last_o (device_c_last),
    .gnt_last_o (device_d_last)
  );

  /////////////////////
  // Type definition //
  /////////////////////

  // Represent all metadatas required for tracking a cache line.
  typedef struct packed {
    logic [AddrWidth-SetsWidth-6-1:0] tag;

    // If any hart is currently owning the cache line.
    logic owned;
    // Harts sharing currently.
    logic [NumCachedHosts-1:0] mask;
    // Whether this cache line has been modified.
    logic dirty;
    // Whether we have been granted write permission to this cache line.
    logic writable;
    // Whether this cache line is valid at all.
    logic valid;
  } tag_t;

  //////////////
  // Trackers //
  //////////////

  // Tracker for a Release operation in progress.
  typedef struct packed {
    logic valid;
    logic [AddrWidth-LineWidth-1:0] address;
  } rel_tracker_t;

  rel_tracker_t [RelTrackerNum-1:0] rel_tracker;

  // Tracker for a writeback operation in progress.
  typedef struct packed {
    logic valid;
    logic [AddrWidth-LineWidth-1:0] address;
  } wb_tracker_t;

  wb_tracker_t [WbTrackerNum-1:0] wb_tracker;

  // Tracker for a Acquire operation in progress.
  typedef struct packed {
    logic valid;
    logic [AddrWidth-LineWidth-1:0] address;
    logic refilling;
  } acq_tracker_t;

  acq_tracker_t [AcqTrackerNum-1:0] acq_tracker;

  //////////////////////////////////
  // Device A Channel arbitration //
  //////////////////////////////////

  typedef `TL_A_STRUCT(DataWidth, AddrWidth, SourceWidth, SinkWidth) device_a_t;

  localparam DeviceANums = AcqTrackerNum;
  localparam DeviceAIdxAcqBase = 0;

  // Grouped signals before multiplexing/arbitration
  device_a_t [DeviceANums-1:0] device_a_mult;
  logic      [DeviceANums-1:0] device_a_valid_mult;
  logic      [DeviceANums-1:0] device_a_ready_mult;

  // Signals for arbitration
  logic [DeviceANums-1:0] device_a_arb_grant;
  logic                   device_a_locked;
  logic [DeviceANums-1:0] device_a_selected;

  openip_round_robin_arbiter #(.WIDTH(DeviceANums)) device_a_arb (
    .clk     (clk_i),
    .rstn    (rst_ni),
    .enable  (device_a_valid && device_a_ready && !device_a_locked),
    .request (device_a_valid_mult),
    .grant   (device_a_arb_grant)
  );

  // Perform arbitration, and make sure that until we encounter device_a_last we keep the connection stable.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      device_a_locked <= 1'b0;
      device_a_selected <= '0;
    end
    else begin
      if (device_a_valid && device_a_ready) begin
        if (!device_a_locked) begin
          device_a_locked   <= 1'b1;
          device_a_selected <= device_a_arb_grant;
        end
        if (device_a_last) begin
          device_a_locked <= 1'b0;
        end
      end
    end
  end

  wire [DeviceANums-1:0] device_a_select = device_a_locked ? device_a_selected : device_a_arb_grant;

  for (genvar i = 0; i < DeviceANums; i++) begin
    assign device_a_ready_mult[i] = device_a_select[i] && device_a_ready;
  end

  // Do the post-arbitration multiplexing
  always_comb begin
    device_a = 'x;
    device_a_valid = 1'b0;
    for (int i = DeviceANums - 1; i >= 0; i--) begin
      if (device_a_select[i]) begin
        device_a = device_a_mult[i];
        device_a_valid = device_a_valid_mult[i];
      end
    end
  end

  //////////////////////////////////
  // Device C channel arbitration //
  //////////////////////////////////

  typedef `TL_C_STRUCT(DataWidth, AddrWidth, SourceWidth, SinkWidth) device_c_t;

  localparam DeviceCNums = WbTrackerNum;
  localparam DeviceCIdxWbBase = 0;

  // Grouped signals before multiplexing/arbitration
  device_c_t [DeviceCNums-1:0] device_c_mult;
  logic      [DeviceCNums-1:0] device_c_valid_mult;
  logic      [DeviceCNums-1:0] device_c_ready_mult;

  device_c_t [DeviceCNums-1:0] device_c_mult_reg;
  logic      [DeviceCNums-1:0] device_c_valid_mult_reg;
  logic      [DeviceCNums-1:0] device_c_ready_mult_reg;

  // Add register slices to break combinational loop of ready signal.
  for (genvar i = 0; i < DeviceCNums; i++) begin: device_c_mult_regslice
    openip_regslice #(
      .TYPE (device_c_t),
      .FORWARD          (1'b0),
      .REVERSE          (1'b1),
      .HIGH_PERFORMANCE (1'b0)
    ) regslice (
      .clk     (clk_i),
      .rstn    (rst_ni),
      .w_valid (device_c_valid_mult[i]),
      .w_ready (device_c_ready_mult[i]),
      .w_data  (device_c_mult[i]),
      .r_valid (device_c_valid_mult_reg[i]),
      .r_ready (device_c_ready_mult_reg[i]),
      .r_data  (device_c_mult_reg[i])
    );
  end

  // Signals for arbitration
  logic [DeviceCNums-1:0] device_c_arb_grant;
  logic                   device_c_locked;
  logic [DeviceCNums-1:0] device_c_selected;

  openip_round_robin_arbiter #(.WIDTH(DeviceCNums)) device_c_arb (
    .clk     (clk_i),
    .rstn    (rst_ni),
    .enable  (device_c_valid && device_c_ready && !device_c_locked),
    .request (device_c_valid_mult_reg),
    .grant   (device_c_arb_grant)
  );

  // Perform arbitration, and make sure that until we encounter device_c_last we keep the connection stable.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      device_c_locked <= 1'b0;
      device_c_selected <= '0;
    end
    else begin
      if (device_c_valid && device_c_ready) begin
        if (!device_c_locked) begin
          device_c_locked   <= 1'b1;
          device_c_selected <= device_c_arb_grant;
        end
        if (device_c_last) begin
          device_c_locked <= 1'b0;
        end
      end
    end
  end

  wire [DeviceCNums-1:0] device_c_select = device_c_locked ? device_c_selected : device_c_arb_grant;

  for (genvar i = 0; i < DeviceCNums; i++) begin
    assign device_c_ready_mult_reg[i] = device_c_select[i] && device_c_ready;
  end

  // Do the post-arbitration multiplexing
  always_comb begin
    device_c = 'x;
    device_c_valid = 1'b0;
    for (int i = DeviceCNums - 1; i >= 0; i--) begin
      if (device_c_select[i]) begin
        device_c = device_c_mult_reg[i];
        device_c_valid = device_c_valid_mult_reg[i];
      end
    end
  end

  //////////////////////////////////
  // Device E channel arbitration //
  //////////////////////////////////

  typedef `TL_E_STRUCT(DataWidth, AddrWidth, SourceWidth, SinkWidth) device_e_t;

  localparam DeviceENums = AcqTrackerNum;
  localparam DeviceEIdxAcqBase = 0;

  // Grouped signals before multiplexing/arbitration
  device_e_t [DeviceENums-1:0] device_e_mult;
  logic      [DeviceENums-1:0] device_e_valid_mult;
  logic      [DeviceENums-1:0] device_e_ready_mult;

  device_e_t [DeviceENums-1:0] device_e_mult_reg;
  logic      [DeviceENums-1:0] device_e_valid_mult_reg;
  logic      [DeviceENums-1:0] device_e_ready_mult_reg;

  // Add register slices to break combinational loop of ready signal.
  for (genvar i = 0; i < DeviceENums; i++) begin: device_e_mult_regslice
    openip_regslice #(
      .TYPE (device_e_t),
      .FORWARD          (1'b0),
      .REVERSE          (1'b1),
      .HIGH_PERFORMANCE (1'b0)
    ) regslice (
      .clk     (clk_i),
      .rstn    (rst_ni),
      .w_valid (device_e_valid_mult[i]),
      .w_ready (device_e_ready_mult[i]),
      .w_data  (device_e_mult[i]),
      .r_valid (device_e_valid_mult_reg[i]),
      .r_ready (device_e_ready_mult_reg[i]),
      .r_data  (device_e_mult_reg[i])
    );
  end

  // Signals for arbitration
  logic [DeviceENums-1:0] device_e_arb_grant;

  openip_round_robin_arbiter #(.WIDTH(DeviceENums)) device_e_arb (
    .clk     (clk_i),
    .rstn    (rst_ni),
    .enable  (device_e_valid && device_e_ready),
    .request (device_e_valid_mult_reg),
    .grant   (device_e_arb_grant)
  );

  for (genvar i = 0; i < DeviceENums; i++) begin
    assign device_e_ready_mult_reg[i] = device_e_arb_grant[i] && device_e_ready;
  end

  // Do the post-arbitration multiplexing
  always_comb begin
    device_e = 'x;
    device_e_valid = 1'b0;
    for (int i = DeviceENums - 1; i >= 0; i--) begin
      if (device_e_arb_grant[i]) begin
        device_e = device_e_mult_reg[i];
        device_e_valid = device_e_valid_mult_reg[i];
      end
    end
  end

  ////////////////////////////////
  // Host D channel arbitration //
  ////////////////////////////////

  typedef `TL_D_STRUCT(DataWidth, AddrWidth, SourceWidth, SinkWidth) host_d_t;

  localparam HostDNums = RelTrackerNum + WbTrackerNum + AcqTrackerNum;
  localparam HostDIdxRelBase = 0;
  localparam HostDIdxWbBase = RelTrackerNum;
  localparam HostDIdxAcqBase = RelTrackerNum + WbTrackerNum;

  host_d_t [HostDNums-1:0] host_d_mult;
  logic    [HostDNums-1:0] host_d_valid_mult;
  logic    [HostDNums-1:0] host_d_ready_mult;

  host_d_t [HostDNums-1:0] host_d_mult_reg;
  logic    [HostDNums-1:0] host_d_valid_mult_reg;
  logic    [HostDNums-1:0] host_d_ready_mult_reg;

  // Add register slices to break combinational loop of ready signal.
  for (genvar i = 0; i < HostDNums; i++) begin: host_d_mult_regslice
    openip_regslice #(
      .TYPE (host_d_t),
      .FORWARD          (1'b0),
      .REVERSE          (1'b1),
      .HIGH_PERFORMANCE (1'b0)
    ) regslice (
      .clk     (clk_i),
      .rstn    (rst_ni),
      .w_valid (host_d_valid_mult[i]),
      .w_ready (host_d_ready_mult[i]),
      .w_data  (host_d_mult[i]),
      .r_valid (host_d_valid_mult_reg[i]),
      .r_ready (host_d_ready_mult_reg[i]),
      .r_data  (host_d_mult_reg[i])
    );
  end

  // Signals for arbitration
  logic [HostDNums-1:0] host_d_arb_grant;
  logic                 host_d_locked;
  logic [HostDNums-1:0] host_d_selected;

  openip_round_robin_arbiter #(.WIDTH(HostDNums)) host_d_arb (
    .clk     (clk_i),
    .rstn    (rst_ni),
    .enable  (host_d_valid && host_d_ready && !host_d_locked),
    .request (host_d_valid_mult_reg),
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
    assign host_d_ready_mult_reg[i] = host_d_select[i] && host_d_ready;
  end

  // Do the post-arbitration multiplexing
  always_comb begin
    host_d = 'x;
    host_d_valid = 1'b0;
    for (int i = HostDNums - 1; i >= 0; i--) begin
      if (host_d_select[i]) begin
        host_d = host_d_mult_reg[i];
        host_d_valid = host_d_valid_mult_reg[i];
      end
    end
  end

  ////////////////////////////////////
  // Writeback Request Multiplexing //
  ////////////////////////////////////
  // #region

  localparam WbSources = AcqTrackerNum + 1;
  localparam WbIdxProbe = 0;
  localparam WbIdxAcqBase = 1;
  localparam WbSourceBits = vbits(WbSources);

  logic [WbSources-1:0]                          wb_req_valid_mult;
  logic [WbSources-1:0]                          wb_req_ready_mult;
  logic [WbSources-1:0]                          wb_req_release_mult;
  logic [WbSources-1:0][2:0]                     wb_req_param_mult;
  logic [WbSources-1:0][AddrWidth-LineWidth-1:0] wb_req_address_mult;
  logic [WbSources-1:0]                          wb_resp_valid_mult;

  logic                           wb_req_valid;
  logic                           wb_req_ready;
  logic                           wb_req_release;
  logic [2:0]                     wb_req_param;
  logic [AddrWidth-LineWidth-1:0] wb_req_address;
  logic [WbSourceBits-1:0]        wb_req_idx;
  logic                           wb_resp_valid;
  logic [WbSourceBits-1:0]        wb_resp_idx;

  // Arbitrate multiple writeback requests and route responses
  always_comb begin
    wb_req_ready_mult = 0;
    wb_req_valid = 1'b0;
    wb_req_release = 1'bx;
    wb_req_param = 'x;
    wb_req_address = 'x;
    wb_req_idx = 'x;
    for (int i = 0; i < WbSources; i++) begin
      if (wb_req_valid_mult[i]) begin
        wb_req_ready_mult = 0;
        wb_req_ready_mult[i] = wb_req_ready;
        wb_req_valid = 1'b1;
        wb_req_release = wb_req_release_mult[i];
        wb_req_param = wb_req_param_mult[i];
        wb_req_address = wb_req_address_mult[i];
        wb_req_idx = i;
      end
    end

    wb_resp_valid_mult = 0;
    if (wb_resp_valid) begin
      wb_resp_valid_mult[wb_resp_idx] = 1'b1;
    end
  end

  logic wb_req_blocked;

  always_comb begin
    wb_req_blocked = 1'b0;

    for (int i = 0; i < AcqTrackerNum; i++) begin
      // If a Acquire tracker exists for a given address, we must not accept a writeback request
      // unless the Acquire tracker is refilling.
      //
      // This wouldn't cause a deadlock because:
      // * If the Acquire logic can serve the request, it will work on channel D which has higher
      //   priority.
      // * If the Acquire logic needs to probe before serving the request, it will work on channel
      //   B which has the same priority.
      // * If the Acquire logic needs to refill/upgrade, we can accept the request.
      if (acq_tracker[i].valid && !acq_tracker[i].refilling && acq_tracker[i].address == wb_req_address) begin
        wb_req_blocked = 1'b1;
      end
    end

    for (int i = 0; i < WbTrackerNum; i++) begin
      // If a writeback tracker exists for a given address, we must not accept a new one.
      if (wb_tracker[i].valid && wb_tracker[i].address == wb_req_address) begin
        wb_req_blocked = 1'b1;
      end
    end

    for (int i = 0; i < RelTrackerNum; i++) begin
      // If a Release tracker exists for a given address, we must not accept a writeback request
      // message to prevent a conflict.
      if (rel_tracker[i].valid && rel_tracker[i].address == wb_req_address) begin
        wb_req_blocked = 1'b1;
      end
    end

    // If a Release message if valid on C channel, we must not accept a writeback reqeust
    // for the same address to prevent a conflict.
    if (host_c_valid && host_c.address[AddrWidth-1:LineWidth] == wb_req_address) begin
      wb_req_blocked = 1'b1;
    end
  end

  // #endregion
  ///////////////////////////////////
  // Host A Channel Demultiplexing //
  ///////////////////////////////////
  // #region

  logic [AcqTrackerNum-1:0] host_a_valid_mult;
  logic [AcqTrackerNum-1:0] host_a_ready_mult;

  logic [AcqTrackerNum-1:0] host_a_tracker_match;
  logic [AcqTrackerNum-1:0] host_a_tracker_avail;
  logic host_a_blocked;

  always_comb begin
    host_a_tracker_match = '0;
    host_a_tracker_avail = '0;
    host_a_blocked = 1'b0;

    for (int i = 0; i < AcqTrackerNum; i++) begin
      // If a Acquire tracker exists for the same set, we must not accept a new A channel
      // message to prevent a potential capacity conflict, in cases where both accesses
      // misses in the cache and cause a refill to the same set and same way.
      if (acq_tracker[i].valid && acq_tracker[i].address[SetsWidth-1:0] == host_a.address[LineWidth+:SetsWidth]) begin
        // This means a conflicting but non-matching beat is routed to the tracker as well,
        // but it's okay since each allocated tracker will only process one request at a time.
        host_a_tracker_match[i] = 1'b1;
      end

      if (!acq_tracker[i].valid) begin
        host_a_tracker_avail[i] = 1'b1;
      end
    end

    for (int i = 0; i < WbTrackerNum; i++) begin
      // If a writeback tracker exists for a given address, we must not accept a new A channel
      // message to prevent a conflict.
      if (wb_tracker[i].valid && wb_tracker[i].address == host_a.address[AddrWidth-1:LineWidth]) begin
        host_a_blocked = 1'b1;
      end
    end

    for (int i = 0; i < RelTrackerNum; i++) begin
      // If a Release tracker exists for a given address, we must not accept a new A channel
      // message to prevent a conflict.
      if (rel_tracker[i].valid && rel_tracker[i].address == host_a.address[AddrWidth-1:LineWidth]) begin
        host_a_blocked = 1'b1;
      end
    end

    // If a writeback request is pending, we must not accept a new A channel message for the same
    // address to prevent a conflict.
    if (wb_req_valid && wb_req_address == host_a.address[AddrWidth-1:LineWidth]) begin
      host_a_blocked = 1'b1;
    end

    // If a Release message if valid on C channel, we must not accept a new A channel message
    // for the same address to prevent a conflict.
    if (host_c_valid && host_c.address[AddrWidth-1:LineWidth] == host_a.address[AddrWidth-1:LineWidth]) begin
      host_a_blocked = 1'b1;
    end
  end

  always_comb begin
    if (|host_a_tracker_match) begin
      // If any of the trackers matches a beat, it will be routed to that tracker.
      host_a_ready = |(host_a_ready_mult & host_a_tracker_match);
      host_a_valid_mult = {AcqTrackerNum{host_a_valid}} & host_a_tracker_match;
    end else if (host_a_blocked) begin
      // Prevent tracker allocation if it's blocked by a conflicting transaction.
      host_a_ready = 1'b0;
      host_a_valid_mult = '0;
    end else begin
      // Route to any available tracker.
      host_a_ready = |(host_a_ready_mult & host_a_tracker_avail);
      host_a_valid_mult = '0;
      for (int i = 0; i < AcqTrackerNum; i++) begin
        if (host_a_tracker_avail[i]) begin
          host_a_valid_mult = host_a_valid << i;
        end
      end
    end
  end

  // #endregion
  ///////////////////////////////////
  // Host C Channel Demultiplexing //
  ///////////////////////////////////

  localparam HostCNums = RelTrackerNum + WbTrackerNum + AcqTrackerNum;
  localparam HostCIdxRelBase = 0;
  localparam HostCIdxWbBase = RelTrackerNum;
  localparam HostCIdxAcqBase = RelTrackerNum + WbTrackerNum;

  logic [HostCNums-1:0] host_c_valid_mult;
  logic [HostCNums-1:0] host_c_ready_mult;

  logic [HostCNums-1:0] host_c_tracker_match;
  logic [RelTrackerNum-1:0] host_c_tracker_avail;

  always_comb begin
    host_c_tracker_match = '0;
    host_c_tracker_avail = '0;

    for (int i = 0; i < AcqTrackerNum; i++) begin
      // If a Acquire tracker exists for a given address, we must not accept a new C channel
      // message to prevent a conflict.
      //
      // This wouldn't cause a deadlock because:
      // * If the Acquire logic can serve the request, it will work on channel D which has higher
      //   priority.
      // * If the Acquire logic needs to probe before serving the request, it will be able to
      //   accept the Release message itself.
      // * If the Acquire logic needs to refill/upgrade, for the upgrade case it must be triggered
      //   by a write so it will probe first; for the refill case no host can have the address.
      if (acq_tracker[i].valid && acq_tracker[i].address == host_c.address[AddrWidth-1:LineWidth]) begin
        host_c_tracker_match[HostCIdxAcqBase + i] = 1'b1;
      end
    end

    for (int i = 0; i < WbTrackerNum; i++) begin
      // If a writeback tracker exists for a given address, we must not accept a new C channel
      // message to prevent a conflict.
      //
      // This wouldn't cause a deadlock because the writeback logic can accept the Release message
      // itself.
      if (wb_tracker[i].valid && wb_tracker[i].address == host_c.address[AddrWidth-1:LineWidth]) begin
        host_c_tracker_match[HostCIdxWbBase + i] = 1'b1;
      end
    end

    for (int i = 0; i < RelTrackerNum; i++) begin
      // If a Release tracker exists for a given address, we must not accept a new C channel
      // message to prevent a conflict.
      if (rel_tracker[i].valid && rel_tracker[i].address == host_c.address[AddrWidth-1:LineWidth]) begin
        host_c_tracker_match[HostCIdxRelBase + i] = 1'b1;
      end

      if (!rel_tracker[i].valid) begin
        host_c_tracker_avail[i] = 1'b1;
      end
    end
  end

  always_comb begin
    if (|host_c_tracker_match) begin
      host_c_ready = |(host_c_ready_mult & host_c_tracker_match);
      host_c_valid_mult = {HostCNums{host_c_valid}} & host_c_tracker_match;
    end else begin
      host_c_ready = |(host_c_ready_mult[HostCIdxRelBase +: RelTrackerNum] & host_c_tracker_avail);
      host_c_valid_mult = '0;
      for (int i = 0; i < RelTrackerNum; i++) begin
        if (host_c_tracker_avail[i]) begin
          host_c_valid_mult = host_c_valid << (HostCIdxRelBase + i);
        end
      end
    end
  end

  // Decode the host sending the request.
  logic [NumCachedHosts-1:0] host_c_selected;
  for (genvar i = 0; i < NumCachedHosts; i++) begin
    assign host_c_selected[i] = (host_c.source &~ SourceMask[i]) == SourceBase[i];
  end

  //////////////////////////////////
  // MEM Channel D Demultiplexing //
  //////////////////////////////////

  logic [AcqTrackerNum-1:0] device_d_gnt_valid_mult;
  logic [AcqTrackerNum-1:0] device_d_gnt_ready_mult;
  logic [WbTrackerNum-1:0]  device_d_ack_valid_mult;
  logic [WbTrackerNum-1:0]  device_d_ack_ready_mult;

  always_comb begin
    device_d_ready = 1'b0;
    device_d_gnt_valid_mult = '0;
    device_d_ack_valid_mult = '0;

    for (int i = 0; i < AcqTrackerNum; i++) begin
      if (device_d_valid && device_d.source == DeviceSourceBase + i && device_d.opcode != ReleaseAck) begin
        device_d_gnt_valid_mult[i] = 1'b1;
        device_d_ready = device_d_gnt_ready_mult[i];
      end
    end

    for (int i = 0; i < WbTrackerNum; i++) begin
      if (device_d_valid && device_d.source == DeviceSourceBase + i && device_d.opcode == ReleaseAck) begin
        device_d_ack_valid_mult[i] = 1'b1;
        device_d_ready = device_d_ack_ready_mult[i];
      end
    end
  end

  ////////////////////////////
  // Cache access multiplex //
  ////////////////////////////

  localparam TagArbNums = RelTrackerNum + WbTrackerNum + AcqTrackerNum;
  localparam TagArbIdxRelBase = 0;
  localparam TagArbIdxWbBase = RelTrackerNum;
  localparam TagArbIdxAcqBase = RelTrackerNum + WbTrackerNum;

  localparam DataArbNums = RelTrackerNum + WbTrackerNum + AcqTrackerNum;
  localparam DataArbIdxRelBase = 0;
  localparam DataArbIdxWbBase = RelTrackerNum;
  localparam DataArbIdxAcqBase = RelTrackerNum + WbTrackerNum;

  logic                 flush_tag_req;
  logic [SetsWidth-1:0] flush_tag_set;
  logic [NumWays-1:0]   flush_tag_wway;
  tag_t                 flush_tag_wdata;

  logic [TagArbNums-1:0]                             tag_arb_req;
  logic [TagArbNums-1:0]                             tag_arb_gnt;
  logic [TagArbNums-1:0][AddrWidth-NonBurstSize-1:0] tag_arb_addr;
  logic [TagArbNums-1:0][WaysWidth-1:0]              tag_arb_wway;
  logic [TagArbNums-1:0]                             tag_arb_write;
  tag_t [TagArbNums-1:0]                             tag_arb_wdata;
  logic [TagArbNums-1:0][WaysWidth-1:0]              tag_arb_way_fallback;

  logic [DataArbNums-1:0]                            data_arb_req;
  logic [DataArbNums-1:0]                            data_arb_gnt;
  logic [DataArbNums-1:0][WaysWidth-1:0]             data_arb_way;
  logic [DataArbNums-1:0][SetsWidth+OffsetWidth-1:0] data_arb_addr;
  logic [DataArbNums-1:0]                            data_arb_write;
  logic [DataArbNums-1:0][DataWidthInBytes-1:0]      data_arb_wmask;
  logic [DataArbNums-1:0][DataWidth-1:0]             data_arb_wdata;

  logic                 tag_req;
  logic [SetsWidth-1:0] tag_set;
  logic                 tag_write;
  logic [NumWays-1:0]   tag_wways;
  tag_t                 tag_wdata;
  tag_t                 tag_rdata [NumWays];

  logic [AddrWidth-LineWidth-1:0] tag_addr;
  logic [WaysWidth-1:0]           tag_way_fallback;

  logic                        data_req;
  logic [WaysWidth-1:0]        data_way;
  logic [SetsWidth-1:0]        data_set;
  logic [OffsetWidth-1:0]      data_offset;
  logic                        data_write;
  logic [DataWidthInBytes-1:0] data_wmask;
  logic [DataWidth-1:0]        data_wdata;
  logic [DataWidth-1:0]        data_rdata;

  always_comb begin
    tag_arb_gnt = '0;
    tag_req = 1'b0;
    tag_set = 'x;
    tag_write = 1'b0;
    tag_wways = '0;
    tag_wdata = tag_t'('x);
    tag_addr = 0;
    tag_way_fallback = 'x;

    // Arbitrate tag memory access. Flushing always takes priority.
    if (flush_tag_req) begin
      tag_req = 1'b1;
      tag_set = flush_tag_set;
      tag_write = 1'b1;
      tag_wways = flush_tag_wway;
      tag_wdata = flush_tag_wdata;
    end else begin
      for (int i = 0; i < TagArbNums; i++) begin
        if (tag_arb_req[i]) begin
          tag_arb_gnt = 0;
          tag_arb_gnt[i] = 1'b1;
          tag_req = 1'b1;
          tag_set = tag_arb_addr[i][OffsetWidth +: SetsWidth];
          tag_write = tag_arb_write[i];
          for (int j = 0; j < NumWays; j++) tag_wways[j] = tag_arb_wway[i] == j;
          tag_wdata = tag_arb_wdata[i];

          tag_addr = tag_arb_addr[i][AddrWidth-NonBurstSize-1:OffsetWidth];
          tag_way_fallback = tag_arb_way_fallback[i];
        end
      end
    end

    data_arb_gnt = '0;
    data_req = 1'b0;
    data_way = 'x;
    data_set = 'x;
    data_offset = 'x;
    data_write = 1'b0;
    data_wdata = 'x;
    data_wmask = 'x;

    // Arbitrate data memory access.
    for (int i = 0; i < DataArbNums; i++) begin
      if (data_arb_req[i]) begin
        data_arb_gnt = 0;
        data_arb_gnt[i] = 1'b1;
        data_req = 1'b1;
        data_way = data_arb_way[i];
        data_set = data_arb_addr[i][OffsetWidth +: SetsWidth];
        data_offset = data_arb_addr[i][0 +: OffsetWidth];
        data_write = data_arb_write[i];
        data_wmask = data_arb_wmask[i];
        data_wdata = data_arb_wdata[i];
      end
    end
  end

  /////////////////////
  // Cache tag check //
  /////////////////////

  logic [AddrWidth-LineWidth-1:0] tag_addr_q;
  logic [WaysWidth-1:0]           tag_way_fallback_q;

  logic [NumWays-1:0] hit;
  logic [WaysWidth-1:0] hit_way;

  always_comb begin
    // Find cache line that hits
    hit = '0;
    for (int i = 0; i < NumWays; i++) begin
      if (tag_rdata[i].valid &&
          tag_rdata[i].tag == tag_addr_q[AddrWidth-LineWidth-1:SetsWidth]) begin
          hit[i] = 1'b1;
      end
    end

    // Fallback to a way specified by miss handlinglogic
    hit_way = tag_way_fallback_q;

    // Empty way fallback
    for (int i = NumWays - 1; i >= 0; i--) begin
      if (!tag_rdata[i].valid) begin
        hit_way = i;
      end
    end

    for (int i = NumWays - 1; i >= 0; i--) begin
      if (hit[i]) begin
        hit_way = i;
      end
    end
  end

  wire tag_t hit_tag = tag_rdata[hit_way];

  // Reconstruct full address of hit_tag
  wire [AddrWidth-1:0] hit_tag_addr = {hit_tag.tag, tag_addr_q[SetsWidth-1:0], 6'd0};

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      tag_addr_q <= 0;
      tag_way_fallback_q <= 'x;
    end else begin
      if (tag_req) begin
        tag_addr_q <= tag_addr;
        tag_way_fallback_q <= tag_way_fallback;
      end
    end
  end

  ////////////////////////
  // SRAM Instantiation //
  ////////////////////////

  logic [DataWidth-1:0] data_wmask_expanded;
  always_comb begin
    for (int i = 0; i < DataWidthInBytes; i++) begin
      data_wmask_expanded[i * 8 +: 8] = data_wmask[i] ? 8'hff : 8'h00;
    end
  end

  for (genvar i = 0; i < NumWays; i++) begin: ram
    prim_ram_1p #(
      .Width           ($bits(tag_t)),
      .Depth           (2 ** SetsWidth),
      .DataBitsPerMask ($bits(tag_t))
    ) tag_ram (
      .clk_i   (clk_i),
      .req_i   (tag_req),
      .write_i (tag_write && tag_wways[i]),
      .addr_i  (tag_set),
      .wdata_i (tag_wdata),
      .wmask_i ('1),
      .rdata_o (tag_rdata[i]),
      .cfg_i   ('0)
    );
  end

  prim_ram_1p #(
    .Width           (DataWidth),
    .Depth           (2 ** (WaysWidth + SetsWidth + OffsetWidth)),
    .DataBitsPerMask (8)
  ) data_ram (
    .clk_i   (clk_i),
    .req_i   (data_req),
    .write_i (data_write),
    .addr_i  ({data_way, data_set, data_offset}),
    .wdata_i (data_wdata),
    .wmask_i (data_wmask_expanded),
    .rdata_o (data_rdata),
    .cfg_i   ('0)
  );

  /////////////////////
  // Probe Sequencer //
  /////////////////////

  // There are multiple situation that we need to send Probe messages to hosts,
  // and in many cases these are broadcasts. Therefore instead of having each sender
  // do the sequencing and track valid/ready signals themselves we have a single probe
  // sequencer that sends out Probe messages.

  localparam ProbeOrigins = WbTrackerNum + AcqTrackerNum;
  localparam ProbeIdxWbBase = 0;
  localparam ProbeIdxAcqBase = WbTrackerNum;

  logic [ProbeOrigins-1:0]                     probe_ready_mult;
  logic [ProbeOrigins-1:0]                     probe_valid_mult;
  logic [ProbeOrigins-1:0][NumCachedHosts-1:0] probe_mask_mult;
  logic [ProbeOrigins-1:0][2:0]                probe_param_mult;
  logic [ProbeOrigins-1:0][AddrWidth-1:0]      probe_address_mult;

  logic                      probe_ready;
  logic                      probe_valid;
  logic [NumCachedHosts-1:0] probe_mask;
  logic [2:0]                probe_param;
  logic [AddrWidth-1:0]      probe_address;

  // Arbitrate multiple probe signals
  always_comb begin
    probe_ready_mult = 0;
    probe_valid = 1'b0;
    probe_mask = 'x;
    probe_param = 'x;
    probe_address = 'x;
    for (int i = 0; i < ProbeOrigins; i++) begin
      if (probe_valid_mult[i]) begin
        probe_ready_mult = 0;
        probe_ready_mult[i] = probe_ready;
        probe_valid = 1'b1;
        probe_mask = probe_mask_mult[i];
        probe_param = probe_param_mult[i];
        probe_address = probe_address_mult[i];
      end
    end
  end

  logic [NumCachedHosts-1:0] probe_pending_q, probe_pending_d;
  logic [2:0]                probe_param_q, probe_param_d;
  logic [AddrWidth-1:0]      probe_address_q, probe_address_d;

  assign host_b_valid = |probe_pending_q;
  assign host_b.opcode = ProbeBlock;
  assign host_b.param = probe_param_q;
  assign host_b.size = LineWidth;
  assign host_b.address = probe_address_q;

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
    probe_address_d = probe_address_q;

    probe_ready = probe_pending_q == 0;

    // A probe has been acknowledged
    if (probe_pending_q != 0 && host_b_ready) begin
      probe_pending_d = probe_pending_q &~ probe_selected;
    end

    // New probing request
    if (probe_valid && probe_ready) begin
      probe_pending_d = probe_mask;
      probe_param_d = probe_param;
      probe_address_d = probe_address;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      probe_pending_q <= '0;
      probe_param_q <= 'x;
      probe_address_q <= 'x;
    end else begin
      probe_pending_q <= probe_pending_d;
      probe_param_q <= probe_param_d;
      probe_address_q <= probe_address_d;
    end
  end

  ////////////////////////////
  // Handle B Channel Probe //
  ////////////////////////////

  assign device_b_ready = wb_req_ready_mult[WbIdxProbe];
  assign wb_req_valid_mult[WbIdxProbe] = device_b_valid;
  assign wb_req_release_mult[WbIdxProbe] = 1'b0;
  assign wb_req_param_mult[WbIdxProbe] = device_b.param;
  assign wb_req_address_mult[WbIdxProbe] = device_b.address[AddrWidth-1:LineWidth];

  ////////////////////////////////
  // Dirty Data Writeback Logic //
  ////////////////////////////////

  typedef enum logic [2:0] {
    WbStateIdle,
    WbStateProbe,
    WbStateReadTag,
    WbStateCheckTag,
    WbStateDoData,
    WbStateDo,
    WbStateUpdateTag,
    WbStateDone
  } wb_state_e;

  wb_state_e                      wb_state_q, wb_state_d;
  logic [WaysWidth-1:0]           wb_way_q, wb_way_d;
  logic [OffsetWidth-1:0]         wb_offset_q, wb_offset_d;
  logic [AddrWidth-LineWidth-1:0] wb_address_q, wb_address_d;
  logic                           wb_release_q, wb_release_d;
  logic [2:0]                     wb_param_q, wb_param_d;
  tag_t                           wb_tag_q, wb_tag_d;
  logic [WbSourceBits-1:0]        wb_idx_q, wb_idx_d;

  logic                           wb_probe_sent_q, wb_probe_sent_d;
  logic                           wb_data_sent_q, wb_data_sent_d;
  logic                           wb_acked_q, wb_acked_d;

  logic wb_beat_written_q, wb_beat_written_d;
  logic wb_beat_forwarded_q, wb_beat_forwarded_d;
  logic wb_beat_acked_q, wb_beat_acked_d;

  logic                           wb_rdata_valid_q, wb_rdata_valid_d;

  logic [DataWidth-1:0] wb_data_skid;
  logic                 wb_data_skid_valid;

  localparam SourceWb = DeviceSourceBase;

  always_comb begin
    tag_arb_req[TagArbIdxWbBase] = 1'b0;
    tag_arb_addr[TagArbIdxWbBase] = 'x;
    tag_arb_write[TagArbIdxWbBase] = 1'b0;
    tag_arb_wway[TagArbIdxWbBase] = '0;
    tag_arb_wdata[TagArbIdxWbBase] = tag_t'('x);
    tag_arb_way_fallback[TagArbIdxWbBase] = 'x;

    data_arb_req[DataArbIdxWbBase] = 1'b0;
    data_arb_way[DataArbIdxWbBase] = 'x;
    data_arb_addr[DataArbIdxWbBase] = 'x;
    data_arb_write[DataArbIdxWbBase] = 1'b0;
    data_arb_wmask[DataArbIdxWbBase] = 'x;
    data_arb_wdata[DataArbIdxWbBase] = 'x;

    wb_tracker[0].valid = wb_state_q != WbStateIdle;
    wb_tracker[0].address = wb_address_q;

    wb_req_ready = 1'b0;

    wb_state_d = wb_state_q;
    wb_offset_d = wb_offset_q;
    wb_way_d = wb_way_q;
    wb_address_d = wb_address_q;
    wb_release_d = wb_release_q;
    wb_param_d = wb_param_q;
    wb_tag_d = wb_tag_q;
    wb_idx_d = wb_idx_q;

    wb_probe_sent_d = wb_probe_sent_q;
    wb_data_sent_d = wb_data_sent_q;
    wb_acked_d = wb_acked_q;

    wb_beat_written_d = wb_beat_written_q;
    wb_beat_forwarded_d = wb_beat_forwarded_q;
    wb_beat_acked_d = wb_beat_acked_q;

    wb_rdata_valid_d = wb_rdata_valid_q;

    device_c_valid_mult[DeviceCIdxWbBase] = 1'b0;
    device_c_mult[DeviceCIdxWbBase] = 'x;

    host_d_valid_mult[HostDIdxWbBase] = 1'b0;
    host_d_mult[HostDIdxWbBase] = 'x;

    host_c_ready_mult[HostCIdxWbBase] = 1'b0;

    probe_valid_mult[ProbeIdxWbBase] = 1'b0;
    probe_mask_mult[ProbeIdxWbBase] = 'x;
    probe_param_mult[ProbeIdxWbBase] = 'x;
    probe_address_mult[ProbeIdxWbBase] = 'x;

    device_d_ack_ready_mult[0] = 1'b1;
    wb_resp_valid = 1'b0;
    wb_resp_idx = 'x;

    if (device_d_ack_valid_mult[0]) wb_acked_d = 1'b1;

    unique case (wb_state_q)
      WbStateIdle: begin
        wb_req_ready = !wb_req_blocked;
        if (wb_req_valid && !wb_req_blocked) begin
          wb_offset_d = 0;
          wb_address_d = wb_req_address;
          wb_release_d = wb_req_release;
          wb_param_d = wb_req_param;
          wb_idx_d = wb_req_idx;

          wb_probe_sent_d = 1'b0;
          wb_data_sent_d = 1'b0;
          wb_acked_d = !wb_req_release;

          wb_beat_written_d = 1'b0;
          wb_beat_forwarded_d = 1'b0;
          wb_beat_acked_d = 1'b0;

          // Even though the acquire logic will have accessed the tag and obtained both the tag
          // and the way information to send us the request, that information is not up-to-date.
          // Since when the writeback is trigger, acquire logic is working on a different address,
          // so it wouldn't block the Release logic from touching this address, which may
          // potentially changed the dirtiness of the tag.
          wb_state_d = WbStateReadTag;
        end
      end

      WbStateReadTag: begin
        tag_arb_req[TagArbIdxWbBase] = 1'b1;
        tag_arb_addr[TagArbIdxWbBase] = {wb_address_q, {OffsetWidth{1'b0}}};

        if (tag_arb_gnt[TagArbIdxWbBase]) begin
          wb_state_d = WbStateCheckTag;
        end
      end

      WbStateCheckTag: begin
        wb_way_d = hit_way;
        wb_tag_d = hit_tag;

        if (~|hit) begin
          wb_param_d = NtoN;
          wb_state_d = WbStateDo;

          // We don't need a NtoN voluntary Release message.
          if (wb_release_q) begin
            wb_acked_d = 1'b1;
            wb_state_d = WbStateDone;
          end
        end else begin
          if (hit_tag.writable) begin
            wb_param_d = wb_param_q == toN ? TtoN : TtoB;
          end else begin
            wb_param_d = wb_param_q == toN ? BtoN : BtoB;
          end

          if (wb_param_q == toN ? hit_tag.mask != 0 : hit_tag.owned) begin
            wb_state_d = WbStateProbe;
          end else if (hit_tag.dirty) begin
            wb_state_d = WbStateDoData;
          end else begin
            wb_state_d = WbStateDo;

            // In this case our cache line is not dirty. If the writeback is not initiated by a
            // Probe we may omit the Release message depending on our Release policy.
            if (wb_release_q && (ReleasePolicy == muntjac_pkg::ReleaseDirty ||
                                 ReleasePolicy == muntjac_pkg::ReleaseExclusive && !hit_tag.writable)) begin
              wb_acked_d = 1'b1;
              wb_state_d = WbStateDone;
            end
          end
        end
      end

      WbStateProbe: begin
        // Send out a Probe message to all sharers if we haven't done so.
        probe_valid_mult[ProbeIdxWbBase] = !wb_probe_sent_q;
        probe_mask_mult[ProbeIdxWbBase] = wb_tag_q.mask;
        probe_param_mult[ProbeIdxWbBase] = wb_param_q == TtoB ? toB : toN;
        probe_address_mult[ProbeIdxWbBase] = {wb_address_q, {LineWidth{1'b0}}};
        if (probe_ready_mult[ProbeIdxWbBase]) wb_probe_sent_d = 1'b1;

        if (host_c_valid_mult[HostCIdxWbBase]) begin
          host_c_ready_mult[HostCIdxWbBase] = 1'b1;

          // If the beat contains data and we are not moving to N state, write it back.
          if (!wb_beat_written_q && host_c.opcode inside {ReleaseData, ProbeAckData} && wb_param_q == TtoB) begin
            data_arb_req[DataArbIdxWbBase] = 1'b1;
            data_arb_way[DataArbIdxWbBase] = wb_way_q;
            data_arb_addr[DataArbIdxWbBase] = {wb_address_q, host_c_idx};
            data_arb_write[DataArbIdxWbBase] = 1'b1;
            data_arb_wmask[DataArbIdxWbBase] = '1;
            data_arb_wdata[DataArbIdxWbBase] = host_c.data;

            // Hold the beat until written back.
            if (data_arb_gnt[DataArbIdxWbBase]) begin
              wb_beat_written_d = 1'b1;
            end else begin
              host_c_ready_mult[HostCIdxWbBase] = 1'b0;
            end
          end

          // If the beat contains data, forward it.
          if (!wb_beat_forwarded_q && host_c.opcode inside {ReleaseData, ProbeAckData}) begin
            device_c_valid_mult[DeviceCIdxWbBase] = 1'b1;
            device_c_mult[DeviceCIdxWbBase].opcode = wb_release_q ? ReleaseData : ProbeAckData;
            device_c_mult[DeviceCIdxWbBase].param = wb_param_q;
            device_c_mult[DeviceCIdxWbBase].size = LineWidth;
            device_c_mult[DeviceCIdxWbBase].source = SourceWb;
            device_c_mult[DeviceCIdxWbBase].address = {wb_address_q, {LineWidth{1'b0}}};
            device_c_mult[DeviceCIdxWbBase].corrupt = 1'b0;
            device_c_mult[DeviceCIdxWbBase].data = host_c.data;

            // Hold the beat until forwarded.
            if (device_c_ready_mult[DeviceCIdxWbBase]) begin
              wb_beat_forwarded_d = 1'b1;
            end else begin
              host_c_ready_mult[HostCIdxWbBase] = 1'b0;
            end
          end

          // If the beat is the last beat and it's a Release message, send back an ack.
          if (!wb_beat_acked_q && host_c.opcode inside {Release, ReleaseData} && host_c_last) begin
            host_d_valid_mult[HostDIdxWbBase] = 1'b1;
            host_d_mult[HostDIdxWbBase].opcode = ReleaseAck;
            host_d_mult[HostDIdxWbBase].param = 0;
            host_d_mult[HostDIdxWbBase].size = LineWidth;
            host_d_mult[HostDIdxWbBase].source = host_c.source;
            host_d_mult[HostDIdxWbBase].sink = 'x;
            host_d_mult[HostDIdxWbBase].denied = 1'b0;
            host_d_mult[HostDIdxWbBase].corrupt = 1'b0;
            host_d_mult[HostDIdxWbBase].data = 'x;

            // Hold the beat until acknowledge is sent.
            if (host_d_ready_mult[HostDIdxWbBase]) begin
              wb_beat_acked_d = 1'b1;
            end else begin
              host_c_ready_mult[HostCIdxWbBase] = 1'b0;
            end
          end

          // Bookkeeping when the beat is consumed.
          if (host_c_ready_mult[HostCIdxWbBase]) begin
            wb_beat_written_d = 1'b0;
            wb_beat_forwarded_d = 1'b0;
            wb_beat_acked_d = 1'b0;

            if (host_c_last) begin
              if (host_c.opcode inside {ReleaseData, ProbeAckData}) begin
                wb_data_sent_d = 1'b1;
              end

              if (host_c.opcode inside {ProbeAck, ProbeAckData}) begin
                wb_tag_d.owned = 1'b0;
                if (host_c.param inside {TtoN, BtoN, NtoN}) begin
                  wb_tag_d.mask = wb_tag_q.mask &~ host_c_selected;
                end
              end

              if (wb_param_q == TtoB ? !wb_tag_d.owned : wb_tag_d.mask == 0) begin
                if (wb_data_sent_d) begin
                  wb_state_d = WbStateUpdateTag;
                end else if (wb_tag_q.dirty) begin
                  wb_state_d = WbStateDoData;
                end else begin
                  wb_state_d = WbStateDo;

                  if (wb_release_q && (ReleasePolicy == muntjac_pkg::ReleaseDirty ||
                                      ReleasePolicy == muntjac_pkg::ReleaseExclusive && !wb_tag_q.writable)) begin
                    wb_acked_d = 1'b1;
                    wb_state_d = WbStateDone;
                  end
                end
              end
            end
          end
        end
      end

      WbStateDoData: begin
        device_c_valid_mult[DeviceCIdxWbBase] = 1'b0;
        device_c_mult[DeviceCIdxWbBase].opcode = wb_release_q ? ReleaseData : ProbeAckData;
        device_c_mult[DeviceCIdxWbBase].param = wb_param_q;
        device_c_mult[DeviceCIdxWbBase].size = LineWidth;
        device_c_mult[DeviceCIdxWbBase].source = SourceWb;
        device_c_mult[DeviceCIdxWbBase].address = {wb_address_q, {LineWidth{1'b0}}};
        device_c_mult[DeviceCIdxWbBase].corrupt = 1'b0;
        device_c_mult[DeviceCIdxWbBase].data = wb_data_skid_valid ? wb_data_skid : data_rdata;

        device_c_valid_mult[DeviceCIdxWbBase] = wb_rdata_valid_q;
        if (!wb_rdata_valid_q) begin
          data_arb_req[DataArbIdxWbBase] = 1'b1;
          wb_rdata_valid_d = data_arb_gnt[DataArbIdxWbBase];
        end

        data_arb_way[DataArbIdxWbBase] = wb_way_q;

        if (wb_rdata_valid_q && device_c_ready_mult[DeviceCIdxWbBase]) begin
          wb_offset_d = wb_offset_q + 1;

          if (wb_offset_d == 0) begin
            wb_state_d = WbStateUpdateTag;
            wb_rdata_valid_d = 1'b0;
          end else begin
            data_arb_req[DataArbIdxWbBase] = 1'b1;
            wb_rdata_valid_d = data_arb_gnt[DataArbIdxWbBase];
          end
        end

        data_arb_addr[DataArbIdxWbBase] = {wb_address_q[SetsWidth-1:0], wb_offset_d};
      end

      WbStateDo: begin
        device_c_valid_mult[DeviceCIdxWbBase] = 1'b1;
        device_c_mult[DeviceCIdxWbBase].opcode = wb_release_q ? Release : ProbeAck;
        device_c_mult[DeviceCIdxWbBase].param = wb_param_q;
        device_c_mult[DeviceCIdxWbBase].size = LineWidth;
        device_c_mult[DeviceCIdxWbBase].source = SourceWb;
        device_c_mult[DeviceCIdxWbBase].address = {wb_address_q, {LineWidth{1'b0}}};
        device_c_mult[DeviceCIdxWbBase].corrupt = 1'b0;
        device_c_mult[DeviceCIdxWbBase].data = 'x;

        if (device_c_ready_mult[DeviceCIdxWbBase]) begin
          wb_state_d = wb_param_q == NtoN ? WbStateDone : WbStateUpdateTag;
        end
      end

      WbStateUpdateTag: begin
        tag_arb_req[TagArbIdxWbBase] = 1'b1;
        tag_arb_addr[TagArbIdxWbBase] = {wb_address_q, {OffsetWidth{1'b0}}};
        tag_arb_write[TagArbIdxWbBase] = 1'b1;
        tag_arb_wway[TagArbIdxWbBase] = wb_way_q;
        tag_arb_wdata[TagArbIdxWbBase] = wb_tag_q;

        if (wb_param_q inside {BtoN, TtoN}) begin
          tag_arb_wdata[TagArbIdxWbBase].valid = 1'b0;
        end else begin
          tag_arb_wdata[TagArbIdxWbBase].writable = 1'b0;
        end

        if (tag_arb_gnt[TagArbIdxWbBase]) begin
          wb_state_d = WbStateDone;
        end
      end

      WbStateDone: begin
        if (wb_acked_q) begin
          wb_resp_valid = 1'b1;
          wb_resp_idx = wb_idx_q;
          wb_state_d = WbStateIdle;
        end
      end

      default:;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      wb_state_q <= WbStateIdle;
      wb_offset_q <= 0;
      wb_way_q <= 0;
      wb_address_q <= 'x;
      wb_release_q <= 1'bx;
      wb_param_q <= 'x;
      wb_tag_q <= 'x;
      wb_idx_q <= 'x;
      wb_probe_sent_q <= 1'b0;
      wb_data_sent_q <= 1'b0;
      wb_acked_q <= 1'b0;
      wb_beat_written_q <= 1'b0;
      wb_beat_forwarded_q <= 1'b0;
      wb_beat_acked_q <= 1'b0;
      wb_data_skid_valid <= 1'b0;
      wb_data_skid <= 'x;
      wb_rdata_valid_q <= 1'b0;
    end else begin
      wb_state_q <= wb_state_d;
      wb_offset_q <= wb_offset_d;
      wb_way_q <= wb_way_d;
      wb_address_q <= wb_address_d;
      wb_release_q <= wb_release_d;
      wb_param_q <= wb_param_d;
      wb_tag_q <= wb_tag_d;
      wb_idx_q <= wb_idx_d;
      wb_probe_sent_q <= wb_probe_sent_d;
      wb_data_sent_q <= wb_data_sent_d;
      wb_acked_q <= wb_acked_d;
      wb_beat_written_q <= wb_beat_written_d;
      wb_beat_forwarded_q <= wb_beat_forwarded_d;
      wb_beat_acked_q <= wb_beat_acked_d;
      wb_rdata_valid_q <= wb_rdata_valid_d;
      if (!wb_data_skid_valid && device_c_valid_mult[DeviceCIdxWbBase]) begin
        wb_data_skid_valid <= 1'b1;
        wb_data_skid <= data_rdata;
      end
      if (device_c_ready_mult[DeviceCIdxWbBase]) begin
        wb_data_skid_valid <= 1'b0;
      end
    end
  end

  /////////////////
  // Flush Logic //
  /////////////////

  typedef enum logic [2:0] {
    FlushStateReset,
    FlushStateIdle
  } flush_state_e;

  flush_state_e flush_state_q = FlushStateReset, flush_state_d;
  logic [SetsWidth-1:0] flush_index_q, flush_index_d;

  always_comb begin
    flush_tag_wway = 'x;
    flush_tag_set = 'x;
    flush_tag_req = 1'b0;
    flush_tag_wdata = tag_t'('x);

    flush_state_d = flush_state_q;
    flush_index_d = flush_index_q;

    unique case (flush_state_q)
      // Reset all states to invalid, discard changes if any.
      FlushStateReset: begin
        flush_tag_wway = '1;
        flush_tag_set = flush_index_q;
        flush_tag_req = 1'b1;
        flush_tag_wdata.valid = 1'b0;

        flush_index_d = flush_index_q + 1;

        if (&flush_index_q) begin
          flush_tag_req = 1'b0;
          flush_state_d = FlushStateIdle;
        end
      end

      FlushStateIdle:;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      flush_state_q <= FlushStateReset;
      flush_index_q <= '0;
    end else begin
      flush_state_q <= flush_state_d;
      flush_index_q <= flush_index_d;
    end
  end

  ////////////////////////////
  // Request handling logic //
  ////////////////////////////

  typedef enum logic [3:0] {
    AcqStateIdle,
    AcqStateReadTag,
    AcqStateCheckTag,
    AcqStateProbe,
    AcqStateWb,
    AcqStateFill,
    AcqStateGet,
    AcqStatePut,
    AcqStateUpdateTag,
    AcqStateAckWait
  } acq_state_e;

  // We can always receive ACKs.
  assign host_e_ready = 1'b1;

  logic [AcqTrackerNum-1:0] acq_miss;

  for (genvar AcqTrackerIdx = 0; AcqTrackerIdx < AcqTrackerNum; AcqTrackerIdx++) begin: acq_logic

    localparam ProbeIdxAcq = ProbeIdxAcqBase + AcqTrackerIdx;
    localparam HostDIdxAcq = HostDIdxAcqBase + AcqTrackerIdx;
    localparam HostAIdxAcq = AcqTrackerIdx;
    localparam HostCIdxAcq = HostCIdxAcqBase + AcqTrackerIdx;
    localparam DeviceAIdxAcq = DeviceAIdxAcqBase + AcqTrackerIdx;
    localparam DeviceEIdxAcq = DeviceEIdxAcqBase + AcqTrackerIdx;
    localparam TagArbIdxAcq = TagArbIdxAcqBase + AcqTrackerIdx;
    localparam DataArbIdxAcq = DataArbIdxAcqBase + AcqTrackerIdx;
    localparam WbIdxAcq = WbIdxAcqBase + AcqTrackerIdx;
    localparam SourceRefill = DeviceSourceBase + AcqTrackerIdx;
    localparam SinkId = SinkBase + AcqTrackerIdx;

    acq_state_e acq_state_q, acq_state_d;
    tl_a_op_e acq_opcode_q, acq_opcode_d;
    logic [2:0] acq_param_q, acq_param_d;
    logic [2:0] acq_size_q, acq_size_d;
    logic [AddrWidth-1:0] acq_address_q, acq_address_d;
    logic [SourceWidth-1:0] acq_source_q, acq_source_d;
    tag_t acq_tag_q, acq_tag_d;
    acq_state_e acq_post_write_q, acq_post_write_d;

    assign acq_miss[AcqTrackerIdx] = acq_state_q != AcqStateFill && acq_state_d == AcqStateFill;

    // Currently we don't bother to implement PLRU, so just use a round-robin fashion to choose line to evict.
    logic [WaysWidth-1:0] acq_evict_q, acq_evict_d;
    logic [WaysWidth-1:0] acq_way_q, acq_way_d;

    logic acq_rtag_valid;
    logic acq_rdata_valid_q, acq_rdata_valid_d;
    logic acq_data_skid_valid;
    logic [DataWidth-1:0] acq_data_skid;

    logic acq_wb_sent_q, acq_wb_sent_d;
    logic acq_probe_sent_q, acq_probe_sent_d;
    logic acq_refill_sent_q, acq_refill_sent_d;
    logic acq_data_sent_q, acq_data_sent_d;
    logic ack_done_q, ack_done_d;

    logic acq_beat_written_q, acq_beat_written_d;
    logic acq_beat_forwarded_q, acq_beat_forwarded_d;
    logic acq_beat_acked_q, acq_beat_acked_d;

    wire [AddrWidth-1:0] acq_tag_addr = {acq_tag_q.tag, acq_address_q[LineWidth +: SetsWidth], 6'd0};

    // Decode the host mask from the source.
    logic [NumCachedHosts-1:0] acq_host_mask;
    for (genvar i = 0; i < NumCachedHosts; i++) begin
      assign acq_host_mask[i] = (acq_source_q &~ SourceMask[i]) == SourceBase[i];
    end

    always_comb begin
      probe_valid_mult[ProbeIdxAcq] = '0;
      probe_mask_mult[ProbeIdxAcq] = 'x;
      probe_param_mult[ProbeIdxAcq] = 'x;
      probe_address_mult[ProbeIdxAcq] = 'x;

      host_d_valid_mult[HostDIdxAcq] = 1'b0;
      host_d_mult[HostDIdxAcq] = 'x;

      host_a_ready_mult[HostAIdxAcq] = 1'b0;

      host_c_ready_mult[HostCIdxAcq] = 1'b0;

      device_a_valid_mult[DeviceAIdxAcq] = 1'b0;
      device_a_mult[DeviceAIdxAcq] = 'x;

      device_e_valid_mult[DeviceEIdxAcq] = 1'b0;
      device_e_mult[DeviceEIdxAcq] = 'x;

      acq_tracker[AcqTrackerIdx].valid = acq_state_q != AcqStateIdle;
      acq_tracker[AcqTrackerIdx].address = acq_address_q[AddrWidth-1:LineWidth];
      acq_tracker[AcqTrackerIdx].refilling = acq_state_q == AcqStateFill;

      tag_arb_req[TagArbIdxAcq] = 1'b0;
      tag_arb_addr[TagArbIdxAcq] = 'x;
      tag_arb_write[TagArbIdxAcq] = 1'b0;
      tag_arb_wway[TagArbIdxAcq] = '0;
      tag_arb_wdata[TagArbIdxAcq] = 'x;
      tag_arb_way_fallback[TagArbIdxAcq] = acq_evict_q;

      data_arb_req[DataArbIdxAcq] = 1'b0;
      data_arb_way[DataArbIdxAcq] = 'x;
      data_arb_addr[DataArbIdxAcq] = 'x;
      data_arb_write[DataArbIdxAcq] = 1'b0;
      data_arb_wmask[DataArbIdxAcq] = 'x;
      data_arb_wdata[DataArbIdxAcq] = 'x;

      acq_state_d = acq_state_q;
      acq_opcode_d = acq_opcode_q;
      acq_param_d = acq_param_q;
      acq_size_d = acq_size_q;
      acq_address_d = acq_address_q;
      acq_source_d = acq_source_q;
      acq_tag_d = acq_tag_q;
      acq_post_write_d = acq_post_write_q;

      acq_wb_sent_d = acq_wb_sent_q;
      acq_probe_sent_d = acq_probe_sent_q;
      acq_refill_sent_d = acq_refill_sent_q;
      acq_data_sent_d = acq_data_sent_q;
      ack_done_d = ack_done_q;

      acq_beat_written_d = acq_beat_written_q;
      acq_beat_forwarded_d = acq_beat_forwarded_q;
      acq_beat_acked_d = acq_beat_acked_q;

      acq_rdata_valid_d = acq_rdata_valid_q;

      acq_evict_d = acq_evict_q;
      acq_way_d = acq_way_q;

      device_d_gnt_ready_mult[AcqTrackerIdx] = 1'b0;

      wb_req_valid_mult[WbIdxAcq] = 1'b0;
      wb_req_release_mult[WbIdxAcq] = 1'b1;
      wb_req_param_mult[WbIdxAcq] = toN;
      wb_req_address_mult[WbIdxAcq] = 'x;

      if (host_e_valid && host_e.sink == SinkId) ack_done_d = 1'b1;

      unique case (acq_state_q)
        AcqStateIdle: begin
          if (host_a_valid_mult[HostAIdxAcq]) begin
            acq_opcode_d = host_a.opcode;
            acq_source_d = host_a.source;
            acq_size_d = host_a.size;
            acq_address_d = host_a.address;
            acq_state_d = AcqStateReadTag;

            unique case (host_a.opcode)
              AcquireBlock, AcquirePerm: begin
                acq_param_d = host_a.param == NtoB ? toB : toT;
                ack_done_d = 1'b0;
              end
              Get: begin
                acq_param_d = toB;
                ack_done_d = 1'b1;
              end
              PutFullData, PutPartialData: begin
                acq_param_d = toT;
                ack_done_d = 1'b1;
              end
              default:;
            endcase

            acq_wb_sent_d = 1'b0;
            acq_probe_sent_d = 1'b0;
            acq_refill_sent_d = 1'b0;
            acq_data_sent_d = 1'b0;

            // For transfers without data, we have stored all information necessary, so consume this beat immediately.
            if (host_a.opcode[2]) begin
              host_a_ready_mult[HostAIdxAcq] = 1'b1;
            end
          end
        end

        AcqStateReadTag: begin
          tag_arb_req[TagArbIdxAcq] = 1'b1;
          tag_arb_addr[TagArbIdxAcq] = acq_address_q[AddrWidth-1:NonBurstSize];

          if (tag_arb_gnt[TagArbIdxAcq]) begin
            acq_state_d = AcqStateCheckTag;
          end
        end

        AcqStateCheckTag: begin
          if (acq_rtag_valid) begin
            acq_way_d = hit_way;
            acq_tag_d = hit_tag;
          end

          if (acq_rtag_valid && ~|hit) begin
            // No tag is hit, proceed to refilling
            if (hit_tag.valid && (hit_tag.mask != 0 || hit_tag.dirty)) begin
              acq_state_d = AcqStateWb;
            end else begin
              acq_state_d = AcqStateFill;
            end
            acq_evict_d = acq_evict_q + 1;

            // Set the tag to invalid to hint AcqStateFill logic.
            acq_tag_d.valid = 1'b0;
          end else begin
            case (acq_opcode_q)
              AcquireBlock, AcquirePerm: begin
                acq_state_d = AcqStateGet;

                // Case A: Not shared by anyone, most trivial case.
                if (acq_tag_d.mask == 0) begin
                  // Make the caching client own the cahce line (i.e. E state in MESI)
                  if (acq_tag_d.writable) begin
                    acq_tag_d.owned = 1'b1;
                    acq_param_d = toT;
                  end
                  acq_tag_d.mask = acq_host_mask[NumCachedHosts-1:0];
                end
                // Case B: Move into owned state
                else if (acq_param_q == toT) begin
                  // Upgrade into owned state
                  if (acq_tag_d.mask == acq_host_mask[NumCachedHosts-1:0]) begin
                    acq_tag_d.owned = 1'b1;
                  end
                  else begin
                    acq_state_d = AcqStateProbe;
                  end
                end
                // Case C: Currently owned
                else if (acq_tag_d.owned) begin
                  acq_state_d = AcqStateProbe;
                end
                // Case D: Shared
                else begin
                  // For non-caching clients this will keep mask 0.
                  acq_tag_d.mask = acq_tag_d.mask | acq_host_mask[NumCachedHosts-1:0];
                end
              end
              Get, PutFullData, PutPartialData: begin
                acq_state_d = acq_opcode_q == Get ? AcqStateGet : AcqStatePut;

                // Case A: Not shared by anyone, most trivial case.
                if (acq_tag_d.mask == 0) begin
                  // Nothing to be done
                end
                // Case B: Write
                else if (acq_opcode_q != Get) begin
                  acq_state_d = AcqStateProbe;
                end
                // Case C: Currently owned
                else if (acq_tag_d.owned) begin
                  acq_state_d = AcqStateProbe;
                end
                // Case D: Read unowned
                else begin
                  // Nothing to be done
                end
              end
            endcase

            if (acq_state_d == AcqStateGet && acq_data_sent_q) begin
              acq_state_d = AcqStateUpdateTag;
            end

            if (acq_state_d != AcqStateProbe && acq_param_q == toT && !acq_tag_d.writable) begin
              // We've got no permission for this cache line, need refill.
              acq_state_d = AcqStateFill;
            end
          end
        end

        AcqStateProbe: begin
          // Send out a Probe message to all sharers if we haven't done so.
          probe_valid_mult[ProbeIdxAcq] = !acq_probe_sent_q;
          probe_mask_mult[ProbeIdxAcq] = acq_tag_q.mask;
          probe_param_mult[ProbeIdxAcq] = acq_param_q == toT ? toN : toB;
          probe_address_mult[ProbeIdxAcq] = acq_tag_addr;
          if (probe_ready_mult[ProbeIdxAcq]) acq_probe_sent_d = 1'b1;

          if (host_c_valid_mult[HostCIdxAcq]) begin
            host_c_ready_mult[HostCIdxAcq] = 1'b1;

            // If the beat contains data, write it back.
            if (!acq_beat_written_q && host_c.opcode inside {ReleaseData, ProbeAckData}) begin
              data_arb_req[DataArbIdxAcq] = 1'b1;
              data_arb_way[DataArbIdxAcq] = acq_way_q;
              data_arb_addr[DataArbIdxAcq] = {acq_address_q[AddrWidth-1:LineWidth], host_c_idx};
              data_arb_write[DataArbIdxAcq] = 1'b1;
              data_arb_wmask[DataArbIdxAcq] = '1;
              data_arb_wdata[DataArbIdxAcq] = host_c.data;

              // Hold the beat until written back.
              if (data_arb_gnt[DataArbIdxAcq]) begin
                acq_beat_written_d = 1'b1;
              end else begin
                host_c_ready_mult[HostCIdxAcq] = 1'b0;
              end
            end

            // If the beat contains data and is forwardable, forward it.
            // Don't forward ReleaseData as it will conflict with the ReleaseAck.
            if (!acq_beat_forwarded_q && host_c.opcode == ProbeAckData &&
                acq_opcode_q inside {Get, AcquireBlock} && acq_size_q == LineWidth) begin

              host_d_valid_mult[HostDIdxAcq] = 1'b1;
              host_d_mult[HostDIdxAcq].opcode = acq_opcode_q == Get ? AccessAckData : GrantData;
              host_d_mult[HostDIdxAcq].param = acq_opcode_q == Get ? 0 : acq_param_q;
              host_d_mult[HostDIdxAcq].size = acq_size_q;
              host_d_mult[HostDIdxAcq].source = acq_source_q;
              host_d_mult[HostDIdxAcq].sink = SinkId;
              host_d_mult[HostDIdxAcq].denied = 1'b0;
              host_d_mult[HostDIdxAcq].corrupt = 1'b0;
              host_d_mult[HostDIdxAcq].data = host_c.data;

              // Hold the beat until forwarded.
              if (host_d_ready_mult[HostDIdxAcq]) begin
                acq_beat_forwarded_d = 1'b1;
              end else begin
                host_c_ready_mult[HostCIdxAcq] = 1'b0;
              end
            end

            // If the beat is the last beat and it's a Release message, send back an ack.
            if (!acq_beat_acked_q && host_c.opcode inside {Release, ReleaseData} && host_c_last) begin
              host_d_valid_mult[HostDIdxAcq] = 1'b1;
              host_d_mult[HostDIdxAcq].opcode = ReleaseAck;
              host_d_mult[HostDIdxAcq].param = 0;
              host_d_mult[HostDIdxAcq].size = LineWidth;
              host_d_mult[HostDIdxAcq].source = host_c.source;
              host_d_mult[HostDIdxAcq].sink = 'x;
              host_d_mult[HostDIdxAcq].denied = 1'b0;
              host_d_mult[HostDIdxAcq].corrupt = 1'b0;
              host_d_mult[HostDIdxAcq].data = 'x;

              // Hold the beat until acknowledge is sent.
              if (host_d_ready_mult[HostDIdxAcq]) begin
                acq_beat_acked_d = 1'b1;
              end else begin
                host_c_ready_mult[HostCIdxAcq] = 1'b0;
              end
            end

            // Bookkeeping when the beat is consumed.
            if (host_c_ready_mult[HostCIdxAcq]) begin
              acq_beat_written_d = 1'b0;
              acq_beat_forwarded_d = 1'b0;
              acq_beat_acked_d = 1'b0;

              if (host_c_last) begin
                if (host_c.opcode == ProbeAckData && acq_opcode_q inside {Get, AcquireBlock} && acq_size_q == LineWidth) begin
                  acq_data_sent_d = 1'b1;
                end

                if (host_c.opcode inside {ReleaseData, ProbeAckData}) begin
                  acq_tag_d.dirty = 1'b1;
                end

                if (host_c.opcode inside {ProbeAck, ProbeAckData}) begin
                  acq_tag_d.owned = 1'b0;
                  if (host_c.param inside {TtoN, BtoN, NtoN}) begin
                    acq_tag_d.mask = acq_tag_q.mask &~ host_c_selected;
                  end
                end

                if (acq_param_q == toT ? acq_tag_d.mask == 0 : !acq_tag_d.owned) begin
                  acq_state_d = AcqStateCheckTag;
                end
              end
            end
          end
        end

        AcqStateWb: begin
          // Send out a writeback request if we haven't done so.
          wb_req_valid_mult[WbIdxAcq] = !acq_wb_sent_q;
          wb_req_address_mult[WbIdxAcq] = acq_tag_addr[AddrWidth-1:LineWidth];
          if (wb_req_ready_mult[WbIdxAcq]) acq_wb_sent_d = 1'b1;

          // Proceed to refill once writeback is completed.
          if (wb_resp_valid_mult[WbIdxAcq]) begin
            acq_state_d = AcqStateFill;
          end
        end

        AcqStateFill: begin
          // Send out a refill message to memory if we haven't done so.
          device_a_valid_mult[DeviceAIdxAcq] = !acq_refill_sent_q;
          device_a_mult[DeviceAIdxAcq].opcode = AcquireBlock;
          device_a_mult[DeviceAIdxAcq].param = acq_tag_q.valid ? BtoT : NtoT;
          device_a_mult[DeviceAIdxAcq].size = LineWidth;
          device_a_mult[DeviceAIdxAcq].source = SourceRefill;
          device_a_mult[DeviceAIdxAcq].address = {acq_address_q[AddrWidth-1:LineWidth], {LineWidth{1'b0}}};
          device_a_mult[DeviceAIdxAcq].mask = '1;
          device_a_mult[DeviceAIdxAcq].corrupt = 1'b0;
          if (device_a_ready_mult[DeviceAIdxAcq]) acq_refill_sent_d = 1'b1;

          if (device_d_gnt_valid_mult[AcqTrackerIdx]) begin
            device_d_gnt_ready_mult[AcqTrackerIdx] = 1'b1;

            // If the beat contains data, write it back.
            if (!acq_beat_written_q && device_d.opcode == GrantData && !device_d.corrupt) begin
              data_arb_req[DataArbIdxAcq] = 1'b1;
              data_arb_way[DataArbIdxAcq] = acq_way_q;
              data_arb_addr[DataArbIdxAcq] = {acq_address_q[AddrWidth-1:LineWidth], device_d_idx};
              data_arb_write[DataArbIdxAcq] = 1'b1;
              data_arb_wmask[DataArbIdxAcq] = '1;
              data_arb_wdata[DataArbIdxAcq] = device_d.data;

              // Hold the beat until written back.
              if (data_arb_gnt[DataArbIdxAcq]) begin
                acq_beat_written_d = 1'b1;
              end else begin
                device_d_gnt_ready_mult[AcqTrackerIdx] = 1'b0;
              end
            end

            // If the beat contains data and is forwardable, forward it.
            if (!acq_beat_forwarded_q && device_d.opcode == GrantData &&
                acq_opcode_q inside {Get, AcquireBlock} && acq_size_q == LineWidth) begin

              host_d_valid_mult[HostDIdxAcq] = 1'b1;
              host_d_mult[HostDIdxAcq].opcode = acq_opcode_q == Get ? AccessAckData : GrantData;
              host_d_mult[HostDIdxAcq].param = acq_opcode_q == Get ? 0 : acq_param_q;
              host_d_mult[HostDIdxAcq].size = acq_size_q;
              host_d_mult[HostDIdxAcq].source = acq_source_q;
              host_d_mult[HostDIdxAcq].sink = SinkId;
              host_d_mult[HostDIdxAcq].denied = 1'b0;
              host_d_mult[HostDIdxAcq].corrupt = 1'b0;
              host_d_mult[HostDIdxAcq].data = device_d.data;

              // Hold the beat until forwarded.
              if (host_d_ready_mult[HostDIdxAcq]) begin
                acq_beat_forwarded_d = 1'b1;
              end else begin
                device_d_gnt_ready_mult[AcqTrackerIdx] = 1'b0;
              end
            end

            // If the beat is the last beat, send back an ack.
            if (!acq_beat_acked_q && device_d_last) begin
              device_e_valid_mult[DeviceEIdxAcq] = 1'b1;
              device_e_mult[DeviceEIdxAcq].sink = device_d.sink;

              // Hold the beat until acknowledge is sent.
              if (device_e_ready_mult[DeviceEIdxAcq]) begin
                acq_beat_acked_d = 1'b1;
              end else begin
                device_d_gnt_ready_mult[AcqTrackerIdx] = 1'b0;
              end
            end

            // Bookkeeping when the burst is completed.
            if (device_d_gnt_ready_mult[AcqTrackerIdx]) begin
              acq_beat_written_d = 1'b0;
              acq_beat_forwarded_d = 1'b0;
              acq_beat_acked_d = 1'b0;

              if (device_d_last) begin
                if (device_d.opcode == GrantData && acq_opcode_q inside {Get, AcquireBlock} && acq_size_q == LineWidth) begin
                  acq_data_sent_d = 1'b1;
                end

                acq_tag_d = 'x;
                acq_tag_d.tag = acq_address_q[AddrWidth-1:LineWidth+SetsWidth];
                acq_tag_d.owned = 1'b0;
                acq_tag_d.mask = '0;
                acq_tag_d.dirty = 1'b0;
                acq_tag_d.writable = device_d.param == toT;
                acq_tag_d.valid = 1'b1;

                // This state change must be the same cycle as our GrantAck handshake.
                // We must move away from refill state before device has a chance to send us a Probe.
                acq_state_d = AcqStateCheckTag;
              end
            end
          end
        end

        AcqStateGet: begin
          host_d_valid_mult[HostDIdxAcq] = acq_rdata_valid_q;
          host_d_mult[HostDIdxAcq].opcode = acq_opcode_q == Get ? AccessAckData : GrantData;
          host_d_mult[HostDIdxAcq].param = acq_opcode_q == Get ? 0 : acq_param_q;
          host_d_mult[HostDIdxAcq].size = acq_size_q;
          host_d_mult[HostDIdxAcq].source = acq_source_q;
          host_d_mult[HostDIdxAcq].sink = SinkId;
          host_d_mult[HostDIdxAcq].denied = 1'b0;
          host_d_mult[HostDIdxAcq].corrupt = 1'b0;
          host_d_mult[HostDIdxAcq].data = acq_data_skid_valid ? acq_data_skid : data_rdata;

          if (!acq_rdata_valid_q) begin
            data_arb_req[DataArbIdxAcq] = 1'b1;
            data_arb_way[DataArbIdxAcq] = acq_way_q;
            data_arb_addr[DataArbIdxAcq] = acq_address_d[AddrWidth-1:NonBurstSize];
            acq_rdata_valid_d = data_arb_gnt[DataArbIdxAcq];
          end

          if (acq_rdata_valid_q && host_d_ready_mult[HostDIdxAcq]) begin
            acq_address_d = acq_address_q + (2 ** NonBurstSize);
            data_arb_req[DataArbIdxAcq] = 1'b1;
            data_arb_way[DataArbIdxAcq] = acq_way_q;
            data_arb_addr[DataArbIdxAcq] = acq_address_d[AddrWidth-1:NonBurstSize];

            if ((acq_address_q >> acq_size_q) != (acq_address_d >> acq_size_q)) begin
              acq_address_d = acq_address_q;
              data_arb_req[DataArbIdxAcq] = 1'b0;

              acq_state_d = AcqStateUpdateTag;
              acq_rdata_valid_d = 1'b0;
            end else begin
              acq_rdata_valid_d = data_arb_gnt[DataArbIdxAcq];
            end
          end
        end

        AcqStatePut: begin
          if (host_a_valid_mult[HostAIdxAcq]) begin
            host_a_ready_mult[HostAIdxAcq] = 1'b1;

            if (!acq_beat_written_q) begin
              data_arb_req[DataArbIdxAcq] = 1'b1;
              data_arb_way[DataArbIdxAcq] = acq_way_q;
              data_arb_addr[DataArbIdxAcq] = acq_address_q[NonBurstSize+:SetsWidth+OffsetWidth];
              data_arb_write[DataArbIdxAcq] = 1'b1;
              data_arb_wmask[DataArbIdxAcq] = host_a.mask;
              data_arb_wdata[DataArbIdxAcq] = host_a.data;

              // Hold the beat until written back.
              if (data_arb_gnt[DataArbIdxAcq]) begin
                acq_beat_written_d = 1'b1;
              end else begin
                host_a_ready_mult[HostAIdxAcq] = 1'b0;
              end
            end

            if (!acq_beat_acked_q && host_a_last) begin
              host_d_valid_mult[HostDIdxAcq] = 1'b1;
              host_d_mult[HostDIdxAcq].opcode = AccessAck;
              host_d_mult[HostDIdxAcq].param = 0;
              host_d_mult[HostDIdxAcq].size = acq_size_q;
              host_d_mult[HostDIdxAcq].source = acq_source_q;
              host_d_mult[HostDIdxAcq].sink = 'x;
              host_d_mult[HostDIdxAcq].denied = 1'b0;
              host_d_mult[HostDIdxAcq].corrupt = 1'b0;
              host_d_mult[HostDIdxAcq].data = 'x;

              if (host_d_ready_mult[HostDIdxAcq]) begin
                acq_beat_acked_d = 1'b1;
              end else begin
                host_a_ready_mult[HostAIdxAcq] = 1'b0;
              end
            end

            if (host_a_ready_mult[HostAIdxAcq]) begin
              acq_beat_written_d = 1'b0;
              acq_beat_acked_d = 1'b0;

              acq_address_d = acq_address_q + (2 ** NonBurstSize);

              if (host_a_last) begin
                acq_tag_d.dirty = 1'b1;
                acq_address_d = acq_address_q;
                acq_state_d = AcqStateUpdateTag;
              end
            end
          end
        end

        AcqStateUpdateTag: begin
          tag_arb_req[TagArbIdxAcq] = 1'b1;
          tag_arb_addr[TagArbIdxAcq] = acq_address_q[AddrWidth-1:NonBurstSize];
          tag_arb_write[TagArbIdxAcq] = 1'b1;
          tag_arb_wway[TagArbIdxAcq] = acq_way_q;
          tag_arb_wdata[TagArbIdxAcq] = acq_tag_q;

          if (tag_arb_gnt[TagArbIdxAcq]) begin
            acq_state_d = AcqStateAckWait;
          end
        end

        AcqStateAckWait: begin
          if (ack_done_d) acq_state_d = AcqStateIdle;
        end

        default:;
      endcase
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        acq_state_q <= AcqStateIdle;
        acq_opcode_q <= tl_a_op_e'('x);
        acq_param_q <= 'x;
        acq_source_q <= 'x;
        acq_address_q <= 'x;
        acq_size_q <= '0;
        acq_evict_q <= '0;
        acq_way_q <= 'x;
        acq_tag_q <= 'x;
        acq_post_write_q <= AcqStateIdle;
        ack_done_q <= 1'b0;
        acq_wb_sent_q <= 1'b0;
        acq_probe_sent_q <= 1'b0;
        acq_refill_sent_q <= 1'b0;
        acq_beat_written_q <= 1'b0;
        acq_beat_forwarded_q <= 1'b0;
        acq_beat_acked_q <= 1'b0;
        acq_data_sent_q <= 1'b0;
        acq_rdata_valid_q <= 1'b0;
        acq_rtag_valid <= 1'b0;
        acq_data_skid_valid <= 1'b0;
        acq_data_skid <= 'x;
      end
      else begin
        acq_state_q <= acq_state_d;
        acq_opcode_q <= acq_opcode_d;
        acq_param_q <= acq_param_d;
        acq_size_q <= acq_size_d;
        acq_address_q <= acq_address_d;
        acq_source_q <= acq_source_d;
        acq_evict_q <= acq_evict_d;
        acq_way_q <= acq_way_d;
        acq_tag_q <= acq_tag_d;
        acq_post_write_q <= acq_post_write_d;
        ack_done_q <= ack_done_d;
        acq_wb_sent_q <= acq_wb_sent_d;
        acq_probe_sent_q <= acq_probe_sent_d;
        acq_refill_sent_q <= acq_refill_sent_d;
        acq_data_sent_q <= acq_data_sent_d;
        acq_beat_written_q <= acq_beat_written_d;
        acq_beat_forwarded_q <= acq_beat_forwarded_d;
        acq_beat_acked_q <= acq_beat_acked_d;
        acq_rdata_valid_q <= acq_rdata_valid_d;
        acq_rtag_valid <= tag_arb_gnt[TagArbIdxAcq];
        if (!acq_data_skid_valid && host_d_valid_mult[HostDIdxAcq]) begin
          acq_data_skid_valid <= 1'b1;
          acq_data_skid <= data_rdata;
        end
        if (host_d_ready_mult[HostDIdxAcq]) begin
          acq_data_skid_valid <= 1'b0;
        end
      end
    end

  end

  //////////////////////////////
  // Release channel handling //
  //////////////////////////////

  typedef enum logic [2:0] {
    RelStateIdle,
    RelStateReadTag,
    RelStateCheckTag,
    RelStateUpdateTag,
    RelStateDo,
    RelStateError
  } rel_state_e;

  for (genvar RelTrackerIdx = 0; RelTrackerIdx < RelTrackerNum; RelTrackerIdx++) begin: rel_logic

    localparam HostCIdxRel = HostCIdxRelBase + RelTrackerIdx;
    localparam HostDIdxRel = HostDIdxRelBase + RelTrackerIdx;
    localparam TagArbIdxRel = TagArbIdxRelBase + RelTrackerIdx;
    localparam DataArbIdxRel = DataArbIdxRelBase + RelTrackerIdx;

    rel_state_e rel_state_q, rel_state_d;
    logic rel_addr_sent_q, rel_addr_sent_d;
    logic [AddrWidth-1:0] rel_address_q, rel_address_d;
    logic [SourceWidth-1:0] rel_source_q, rel_source_d;
    logic [NumCachedHosts-1:0] rel_selected_q, rel_selected_d;
    logic rel_beat_written_q, rel_beat_written_d;
    logic rel_beat_acked_q, rel_beat_acked_d;

    tag_t rel_tag_q, rel_tag_d;
    logic [WaysWidth-1:0] rel_way_q, rel_way_d;

    always_comb begin
      host_d_valid_mult[HostDIdxRel] = 1'b0;
      host_d_mult[HostDIdxRel] = 'x;

      rel_tracker[RelTrackerIdx].valid = rel_state_q != RelStateIdle;
      rel_tracker[RelTrackerIdx].address = rel_address_q[AddrWidth-1:LineWidth];

      host_c_ready_mult[HostCIdxRel] = 1'b0;

      tag_arb_req[TagArbIdxRel] = 1'b0;
      tag_arb_addr[TagArbIdxRel] = 'x;
      tag_arb_write[TagArbIdxRel] = 1'b0;
      tag_arb_wway[TagArbIdxRel] = '0;
      tag_arb_wdata[TagArbIdxRel] = tag_t'('x);
      tag_arb_way_fallback[TagArbIdxRel] = 'x;

      data_arb_req[DataArbIdxRel] = 1'b0;
      data_arb_way[DataArbIdxRel] = 'x;
      data_arb_addr[DataArbIdxRel] = 'x;
      data_arb_write[DataArbIdxRel] = 1'b0;
      data_arb_wmask[DataArbIdxRel] = '1;
      data_arb_wdata[DataArbIdxRel] = 'x;

      rel_state_d = rel_state_q;
      rel_addr_sent_d = rel_addr_sent_q;
      rel_address_d = rel_address_q;
      rel_source_d = rel_source_q;
      rel_selected_d = rel_selected_q;

      rel_beat_written_d = rel_beat_written_q;
      rel_beat_acked_d = rel_beat_acked_q;

      rel_tag_d = rel_tag_q;
      rel_way_d = rel_way_q;

      unique case (rel_state_q)
        RelStateIdle: begin
          if (host_c_valid_mult[HostCIdxRel]) begin
            rel_address_d = host_c.address;
            rel_source_d = host_c.source;
            rel_selected_d = host_c_selected;

            if (host_c.param == NtoN) begin
              // In this case physical address supplied is invalid.
              rel_state_d = RelStateDo;
            end else begin
              rel_state_d = RelStateReadTag;
            end
          end
        end

        RelStateReadTag: begin
          tag_arb_req[TagArbIdxRel] = 1'b1;
          tag_arb_addr[TagArbIdxRel] = rel_address_q[AddrWidth-1:NonBurstSize];

          if (tag_arb_gnt[TagArbIdxRel]) begin
            rel_state_d = RelStateCheckTag;
          end
        end

        RelStateCheckTag: begin
          // Cache valid
          if (|hit) begin
            rel_state_d = RelStateDo;
            rel_tag_d = hit_tag;
            rel_way_d = hit_way;

            if (host_c.opcode == ReleaseData) begin
              rel_tag_d.dirty = 1'b1;
            end

            if (host_c.param inside {TtoN, BtoN, NtoN}) begin
              rel_tag_d.mask = hit_tag.mask &~ host_c_selected;
              if (!rel_tag_d.mask) rel_tag_d.owned = 1'b0;
            end

            if (host_c.param inside {TtoB, TtoN}) begin
              rel_tag_d.owned = 1'b0;
            end
          end else begin
            rel_state_d = RelStateError;
          end
        end

        RelStateDo: begin
          if (host_c_valid_mult[HostCIdxRel]) begin
            host_c_ready_mult[HostCIdxRel] = 1'b1;

            // If the beat contains data, write it back.
            if (!rel_beat_written_q && host_c.opcode == ReleaseData) begin
              data_arb_req[DataArbIdxRel] = 1'b1;
              data_arb_way[DataArbIdxRel] = rel_way_q;
              data_arb_addr[DataArbIdxRel] = {rel_address_q[NonBurstSize+OffsetWidth+:SetsWidth], host_c_idx};
              data_arb_write[DataArbIdxRel] = 1'b1;
              data_arb_wdata[DataArbIdxRel] = host_c.data;

              // Hold the beat until written back.
              if (data_arb_gnt[DataArbIdxRel]) begin
                rel_beat_written_d = 1'b1;
              end else begin
                host_c_ready_mult[HostCIdxRel] = 1'b0;
              end
            end

            // If the beat is the last beat, send back an Ack.
            if (!rel_beat_acked_q && host_c_last) begin
              host_d_valid_mult[HostDIdxRel] = 1'b1;
              host_d_mult[HostDIdxRel].opcode = ReleaseAck;
              host_d_mult[HostDIdxRel].param = 0;
              host_d_mult[HostDIdxRel].size = LineWidth;
              host_d_mult[HostDIdxRel].source = rel_source_q;
              host_d_mult[HostDIdxRel].sink = 'x;
              host_d_mult[HostDIdxRel].denied = 1'b0;
              host_d_mult[HostDIdxRel].corrupt = 1'b0;
              host_d_mult[HostDIdxRel].data = 'x;

              // Hold the beat until acknowledge is sent.
              if (host_d_ready_mult[HostDIdxRel]) begin
                rel_beat_acked_d = 1'b1;
              end else begin
                host_c_ready_mult[HostCIdxRel] = 1'b0;
              end
            end

            if (host_c_ready_mult[HostCIdxRel]) begin
              rel_beat_written_d = 1'b0;
              rel_beat_acked_d = 1'b0;

              if (host_c_last) begin
                rel_state_d = host_c.param == NtoN ? RelStateIdle : RelStateUpdateTag;
              end
            end
          end
        end

        RelStateUpdateTag: begin
          tag_arb_req[TagArbIdxRel] = 1'b1;
          tag_arb_addr[TagArbIdxRel] = rel_address_q[AddrWidth-1:NonBurstSize];
          tag_arb_write[TagArbIdxRel] = 1'b1;
          tag_arb_wdata[TagArbIdxRel] = rel_tag_q;
          tag_arb_wway[TagArbIdxRel] = rel_way_q;

          if (tag_arb_gnt[TagArbIdxRel]) begin
            rel_state_d = RelStateIdle;
          end
        end

        RelStateError:;

        default:;
      endcase
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        rel_state_q <= RelStateIdle;
        rel_addr_sent_q <= 1'b0;
        rel_source_q <= 'x;
        rel_address_q <= 'x;
        rel_selected_q <= '0;
        rel_beat_written_q <= 1'b0;
        rel_beat_acked_q <= 1'b0;
        rel_way_q <= 'x;
        rel_tag_q <= 'x;
      end
      else begin
        rel_state_q <= rel_state_d;
        rel_addr_sent_q <= rel_addr_sent_d;
        rel_source_q <= rel_source_d;
        rel_address_q <= rel_address_d;
        rel_selected_q <= rel_selected_d;
        rel_beat_written_q <= rel_beat_written_d;
        rel_beat_acked_q <= rel_beat_acked_d;
        rel_way_q <= rel_way_d;
        rel_tag_q <= rel_tag_d;
      end
    end

  end

  if (EnableHpm) begin
    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        hpm_acq_count_o <= 1'b0;
        hpm_rel_count_o <= 1'b0;
        hpm_miss_o <= 1'b0;
      end else begin
        hpm_acq_count_o <= host_a_valid && host_a_ready && host_a_last;
        hpm_rel_count_o <= host_c_valid && host_c_ready && host_c_last;
        hpm_miss_o <= |acq_miss;
      end
    end
  end else begin
    assign hpm_acq_count_o = 1'b0;
    assign hpm_rel_count_o = 1'b0;
    assign hpm_miss_o = 1'b0;
  end

endmodule
