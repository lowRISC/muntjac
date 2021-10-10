  `include "tl_util.svh"

// An adpater that makes sure responses to requests are in FIFO order.
module tl_fifo_converter import tl_pkg::*; #(
  parameter  int unsigned DataWidth   = 64,
  parameter  int unsigned AddrWidth   = 56,
  parameter  int unsigned HostSourceWidth   = 2,
  parameter  int unsigned DeviceSourceWidth = 1,
  parameter  int unsigned SinkWidth   = 1,
  parameter  int unsigned MaxSize     = 6,

  parameter  int unsigned TrackerWidth = HostSourceWidth < DeviceSourceWidth ? HostSourceWidth : DeviceSourceWidth
) (
  input  logic       clk_i,
  input  logic       rst_ni,

  `TL_DECLARE_DEVICE_PORT(DataWidth, AddrWidth, HostSourceWidth, SinkWidth, host),
  `TL_DECLARE_HOST_PORT(DataWidth, AddrWidth, DeviceSourceWidth, SinkWidth, device)
);

  if (DeviceSourceWidth < TrackerWidth) $fatal(1, "Unexpected SourceWidth");

  localparam NumTracker = 2 ** TrackerWidth;

  localparam int unsigned DataWidthInBytes = DataWidth / 8;
  localparam int unsigned NonBurstSize = $clog2(DataWidthInBytes);
  localparam int unsigned MaxBurstLen = 2 ** (MaxSize - NonBurstSize);
  localparam int unsigned BurstLenWidth = prim_util_pkg::vbits(MaxBurstLen);

  `TL_DECLARE(DataWidth, AddrWidth, HostSourceWidth, SinkWidth, host);
  `TL_DECLARE(DataWidth, AddrWidth, DeviceSourceWidth, SinkWidth, device);
  `TL_DECLARE(DataWidth, AddrWidth, HostSourceWidth, SinkWidth, tmp);
  `TL_BIND_DEVICE_PORT(host, host);
  `TL_BIND_HOST_PORT(device, device);

  // TODO: Support B, C, E channels if we need to FIFOify them
  assign device_b_ready = 1'b1;
  assign host_b_valid   = 1'b0;
  assign host_b         = 'x;

  assign host_c_ready   = 1'b1;
  assign device_c_valid = 1'b0;
  assign device_c       = 'x;

  assign host_e_ready   = 1'b1;
  assign device_e_valid = 1'b0;
  assign device_e       = 'x;

  /////////////////////////////////////////
  // #region Burst tracker instantiation //

  logic host_a_first;
  logic host_a_last;

  logic device_d_last;
  logic [BurstLenWidth-1:0] device_d_idx;

  logic tmp_d_last;
  logic [BurstLenWidth-1:0] tmp_d_idx;

  tl_burst_tracker #(
    .DataWidth (DataWidth),
    .AddrWidth (AddrWidth),
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
    .req_first_o (host_a_first),
    .rel_first_o (),
    .gnt_first_o (),
    .req_last_o (host_a_last),
    .rel_last_o (),
    .gnt_last_o ()
  );

  tl_burst_tracker #(
    .DataWidth (DataWidth),
    .AddrWidth (AddrWidth),
    .SourceWidth (DeviceSourceWidth),
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
    .req_last_o (),
    .rel_last_o (),
    .gnt_last_o (device_d_last)
  );

  tl_burst_tracker #(
    .DataWidth (DataWidth),
    .AddrWidth (AddrWidth),
    .SourceWidth (HostSourceWidth),
    .SinkWidth (SinkWidth),
    .MaxSize (MaxSize)
  ) tmp_burst_tracker (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_TAP_PORT(link, tmp),
    .req_len_o (),
    .rel_len_o (),
    .gnt_len_o (),
    .req_idx_o (),
    .rel_idx_o (),
    .gnt_idx_o (tmp_d_idx),
    .req_left_o (),
    .rel_left_o (),
    .gnt_left_o (),
    .req_first_o (),
    .rel_first_o (),
    .gnt_first_o (),
    .req_last_o (),
    .rel_last_o (),
    .gnt_last_o (tmp_d_last)
  );

  // #endregion
  /////////////////////////////////////////

  //////////////////////////////////////
  // #region Tracker and ctrl signals //

  // Control signals for response.
  typedef struct packed {
    tl_pkg::tl_d_op_e                    opcode ;
    logic                          [2:0] param  ;
    logic           [`TL_SIZE_WIDTH-1:0] size   ;
    logic                [SinkWidth-1:0] sink   ;
    logic                                denied ;
  } d_ctrl_t;

  logic [NumTracker-1:0]                      tracker_valid_q, tracker_valid_d;
  logic [NumTracker-1:0]                      tracker_ready_q, tracker_ready_d;
  logic [NumTracker-1:0][HostSourceWidth-1:0] tracker_source_q, tracker_source_d;

  d_ctrl_t [NumTracker-1:0]                  tracker_ctrl_q;

  logic [TrackerWidth-1:0] tracker_a_idx_q, tracker_a_idx_d;
  logic [TrackerWidth-1:0] tracker_d_idx_q, tracker_d_idx_d;

  always_ff @(posedge clk_i) begin
    if (device_d_valid) begin
      if (device_d_last) begin
        tracker_ctrl_q[device_d.source[TrackerWidth-1:0]] <= {device_d.opcode, device_d.param, device_d.size, device_d.sink, device_d.denied};
      end
    end
  end

  always_comb begin
    tracker_valid_d = tracker_valid_q;
    tracker_source_d = tracker_source_q;
    tracker_ready_d = tracker_ready_q;
    tracker_a_idx_d = tracker_a_idx_q;
    tracker_d_idx_d = tracker_d_idx_q;

    if (device_d_valid && device_d_ready && device_d_last) begin
      tracker_ready_d[device_d.source[TrackerWidth-1:0]] = 1'b1;
    end

    // Remove from tracker when a response is completed.
    if (tmp_d_valid && tmp_d_ready && tmp_d_last) begin
      tracker_valid_d[tracker_d_idx_q] = 1'b0;
      tracker_source_d[tracker_d_idx_q] = 'x;
      tracker_ready_d[tracker_d_idx_q] = 1'b0;
      tracker_d_idx_d = tracker_d_idx_q + 1;
    end

    // Add to tracker when a request begins.
    if (host_a_valid && host_a_ready && host_a_first) begin
      tracker_valid_d[tracker_a_idx_q] = 1'b1;
      tracker_source_d[tracker_a_idx_q] = host_a.source;
    end

    // Increment tracker counter after request fully sent.
    if (host_a_valid && host_a_ready && host_a_last) begin
      tracker_a_idx_d = tracker_a_idx_q + 1;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      tracker_valid_q <= '0;
      tracker_ready_q <= '0;
      tracker_a_idx_q <= '0;
      tracker_d_idx_q <= '0;
    end else begin
      tracker_valid_q <= tracker_valid_d;
      tracker_ready_q <= tracker_ready_d;
      tracker_a_idx_q <= tracker_a_idx_d;
      tracker_d_idx_q <= tracker_d_idx_d;
    end
  end

  always_ff @(posedge clk_i) begin
    tracker_source_q <= tracker_source_d;
  end

  // Only allow a new transfer through if we can add it to the tracker.
  assign host_a_ready     = (host_a_valid && host_a_first ? !tracker_valid_q[tracker_a_idx_q] : 1'b1) && device_a_ready;
  assign device_a_valid   = host_a_valid && (host_a_first ? !tracker_valid_q[tracker_a_idx_q] : 1'b1);
  assign device_a.opcode  = host_a.opcode;
  assign device_a.param   = host_a.param;
  assign device_a.size    = host_a.size;
  assign device_a.source  = tracker_a_idx_q;
  assign device_a.address = host_a.address;
  assign device_a.mask    = host_a.mask;
  assign device_a.corrupt = host_a.corrupt;
  assign device_a.data    = host_a.data;

  // We are always ready to accept a response from D channel.
  assign device_d_ready = 1'b1;

  // Send opcode and size to the tmp link for tmp_d_idx calulcation.
  assign tmp_d_ready = !host_d_valid || host_d_ready;
  assign tmp_d_valid   = tracker_ready_q[tracker_d_idx_q];
  assign tmp_d.opcode  = tracker_ctrl_q[tracker_d_idx_q].opcode;
  assign tmp_d.size    = tracker_ctrl_q[tracker_d_idx_q].size;

  // A register slice between host and tmp so that data can be placed SRAMs.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      host_d_valid <= 1'b0;
    end else begin
      if (host_d_ready) begin
        host_d_valid <= 1'b0;
      end
      if (tmp_d_valid) begin
        host_d_valid <= 1'b1;
      end
    end
  end

  always_ff @(posedge clk_i) begin
    if (tmp_d_valid && tmp_d_ready) begin
      host_d.opcode  <= tmp_d.opcode;
      host_d.size    <= tmp_d.size;

      host_d.param   <= tracker_ctrl_q[tracker_d_idx_q].param;
      host_d.source  <= tracker_source_q[tracker_d_idx_q];
      host_d.sink    <= tracker_ctrl_q[tracker_d_idx_q].sink;
      host_d.denied  <= tracker_ctrl_q[tracker_d_idx_q].denied;
    end
  end

  // #endregion
  //////////////////////////////////////

  //////////////////////////
  // #region Data signals //

  // Data signals for response.
  typedef struct packed {
    logic                 corrupt;
    logic [DataWidth-1:0] data;
  } d_data_t;

  // Use `logic` instead struct, a single dim array instead multiple, so tools
  // are more likely to recongise this as a RAM.
  //
  // On Xilinx also hint that this should be a distributed RAM. The tracker number
  // are usually not high, so this isn't deep enough to worth a BRAM.
`ifdef FPGA_XILINX
  (* ram_style = "distributed" *)
`endif
  logic [DataWidth:0] tracker_data_q [NumTracker*MaxBurstLen];
  logic                     tracker_data_w_valid;
  logic [TrackerWidth-1:0]  tracker_data_w_idx;
  logic [BurstLenWidth-1:0] tracker_data_w_beat_idx;
  d_data_t                  tracker_data_w_data;
  logic                     tracker_data_r_valid;
  logic [TrackerWidth-1:0]  tracker_data_r_idx;
  logic [BurstLenWidth-1:0] tracker_data_r_beat_idx;
  d_data_t                  tracker_data_r_data;

  always_ff @(posedge clk_i) begin
    if (tracker_data_w_valid) begin
      tracker_data_q[{tracker_data_w_idx, tracker_data_w_beat_idx}] <= tracker_data_w_data;
    end
    if (tracker_data_r_valid) begin
      tracker_data_r_data <= tracker_data_q[{tracker_data_r_idx, tracker_data_r_beat_idx}];
    end
  end

  assign tracker_data_w_valid = device_d_valid;
  assign tracker_data_w_idx = device_d.source[TrackerWidth-1:0];
  assign tracker_data_w_beat_idx = device_d_idx;
  assign tracker_data_w_data = {device_d.corrupt, device_d.data};

  assign tracker_data_r_valid = tmp_d_valid && tmp_d_ready;
  assign tracker_data_r_idx = tracker_d_idx_q;
  assign tracker_data_r_beat_idx = tmp_d_idx;
  assign host_d.corrupt = tracker_data_r_data.corrupt;
  assign host_d.data    = tracker_data_r_data.data;

  // #endregion
  //////////////////////////

endmodule
