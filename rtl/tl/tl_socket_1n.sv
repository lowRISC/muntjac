module tl_socket_1n import tl_pkg::*; #(
  parameter  int unsigned SourceWidth   = 1,
  parameter  int unsigned SinkWidth     = 1,
  parameter  int unsigned AddrWidth     = 56,
  parameter  int unsigned DataWidth     = 64,
  parameter  int unsigned SizeWidth     = 3,

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

  tl_channel.device host,
  tl_channel.host   device[NumLinks]
);

  import prim_util_pkg::*;

  localparam int unsigned DataWidthInBytes = DataWidth / 8;
  localparam int unsigned NonBurstSize = $clog2(DataWidthInBytes);
  localparam int unsigned MaxBurstLen = 2 ** (MaxSize - NonBurstSize);
  localparam int unsigned BurstLenWidth = vbits(MaxBurstLen);

  function automatic logic [BurstLenWidth-1:0] burst_len(input logic [SizeWidth-1:0] size);
    if (size <= NonBurstSize) begin
      return 0;
    end else begin
      return (1 << (size - NonBurstSize)) - 1;
    end
  endfunction

  if (host.SourceWidth != SourceWidth) $fatal(1, "SourceWidth mismatch");
  if (host.SinkWidth > SinkWidth) $fatal(1, "SinkWidth mismatch");
  if (host.DataWidth != DataWidth) $fatal(1, "DataWidth mismatch");
  if (host.SizeWidth != SizeWidth) $fatal(1, "SizeWidth mismatch");
  if (host.MaxSize < MaxSize) $fatal(1, "MaxSize mismatch");
  if (host.FifoReply) $fatal(1, "socket_1n does not perserve FIFO order");

  for (genvar i = 0; i < NumLinks; i++) begin
    initial begin
      if (device[i].SourceWidth != SourceWidth) $fatal(1, "SourceWidth mismatch");
      if (device[i].SinkWidth < SinkWidth) $fatal(1, "SinkWidth mismatch");
      if (device[i].DataWidth != DataWidth) $fatal(1, "DataWidth mismatch");
      if (device[i].SizeWidth != SizeWidth) $fatal(1, "SizeWidth mismatch");
      if (device[i].MaxSize > MaxSize) $fatal(1, "MaxSize mismatch");
    end
  end

  ///////////////////////////////////
  // Request channel demultiplexer //
  ///////////////////////////////////

  logic [LinkWidth-1:0] req_device_id;

  always_comb begin
    req_device_id = 0;
    for (int i = 0; i < NumAddressRange; i++) begin
      if ((host.a_address &~ AddressMask[i]) == AddressBase[i]) begin
        req_device_id = AddressLink[i];
      end
    end
  end

  logic [NumLinks-1:0] req_ready_mult;

  for (genvar i = 0; i < NumLinks; i++) begin
    assign req_ready_mult[i] = host.a_valid && req_device_id == i && device[i].a_ready;
    assign device[i].a_valid   = host.a_valid && req_device_id == i;

    assign device[i].a_opcode  = host.a_opcode;
    assign device[i].a_param   = host.a_param;
    assign device[i].a_size    = host.a_size;
    assign device[i].a_source  = host.a_source;
    assign device[i].a_address = host.a_address;
    assign device[i].a_mask    = host.a_mask;
    assign device[i].a_corrupt = host.a_corrupt;
    assign device[i].a_data    = host.a_data;
  end

  assign host.a_ready = |req_ready_mult;

  ///////////////////////////////
  // Probe channel arbitration //
  ///////////////////////////////

  typedef struct packed {
    tl_b_op_e               opcode;
    logic [2:0]             param;
    logic [SizeWidth-1:0]   size;
    logic [SourceWidth-1:0] source;
    logic [AddrWidth-1:0]   address;
    logic [DataWidth/8-1:0] mask;
    logic                   corrupt;
    logic [DataWidth-1:0]   data;
  } prb_t;

  // Grouped signals before multiplexing/arbitration
  prb_t [NumLinks-1:0] prb_mult;
  logic [NumLinks-1:0] prb_valid_mult;
  logic [NumLinks-1:0] prb_ready_mult;

  for (genvar i = 0; i < NumLinks; i++) begin
    assign prb_mult[i] = prb_t'{
      device[i].b_opcode,
      device[i].b_param,
      device[i].b_size,
      device[i].b_source,
      device[i].b_address,
      device[i].b_mask,
      device[i].b_corrupt,
      device[i].b_data
    };
    assign prb_valid_mult[i] = device[i].b_valid;

    assign device[i].b_ready = prb_ready_mult[i];
  end

  // Signals after multiplexing
  prb_t prb;
  logic prb_valid;
  logic prb_ready;

  assign prb_ready = host.b_ready;

  assign host.b_valid   = prb_valid;
  assign host.b_opcode  = prb.opcode;
  assign host.b_param   = prb.param;
  assign host.b_size    = prb.size;
  assign host.b_source  = prb.source;
  assign host.b_address = prb.address;
  assign host.b_mask    = prb.mask;
  assign host.b_corrupt = prb.corrupt;
  assign host.b_data    = prb.data;

  // Determine the boundary of a message.
  logic                     prb_last;
  logic [BurstLenWidth-1:0] prb_len_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      prb_len_q <= 0;
    end else begin
      if (prb_valid && prb_ready) begin
        if (prb_len_q == 0) begin
          if (prb.opcode < 4)
            prb_len_q <= burst_len(prb.size);
        end else begin
          prb_len_q <= prb_len_q - 1;
        end
      end
    end
  end

  assign prb_last = prb_len_q == 0 ? (prb.size <= NonBurstSize || prb.opcode >= 4) : prb_len_q == 1;

  // Signals for arbitration
  logic [NumLinks-1:0] prb_arb_grant;
  logic                prb_locked;
  logic [NumLinks-1:0] prb_selected;

  openip_round_robin_arbiter #(.WIDTH(NumLinks)) prb_arb (
    .clk     (clk_i),
    .rstn    (rst_ni),
    .enable  (!prb_locked),
    .request (prb_valid_mult),
    .grant   (prb_arb_grant)
  );

  // Perform arbitration, and make sure that until we encounter prb_last we keep the connection stable.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      prb_locked <= 1'b0;
      prb_selected <= '0;
    end
    else begin
      if (prb_locked) begin
        if (prb_valid && prb_ready && prb_last) begin
          prb_locked <= 1'b0;
        end
      end
      else if (prb_arb_grant) begin
        prb_locked   <= 1'b1;
        prb_selected <= prb_arb_grant;
      end
    end
  end

  for (genvar i = 0; i < NumLinks; i++) begin
    assign prb_ready_mult[i] = prb_locked && prb_selected[i] && prb_ready;
  end

  // Do the post-arbitration multiplexing
  always_comb begin
    prb = prb_t'('x);
    prb_valid = 1'b0;
    if (prb_locked) begin
      for (int i = NumLinks - 1; i >= 0; i--) begin
        if (prb_selected[i]) begin
          prb = prb_mult[i];
          prb_valid = prb_valid_mult[i];
        end
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
      if ((host.c_address &~ AddressMask[i]) == AddressBase[i]) begin
        rel_device_id = AddressLink[i];
      end
    end
  end

  logic [NumLinks-1:0] rel_ready_mult;

  for (genvar i = 0; i < NumLinks; i++) begin
    assign rel_ready_mult[i] = host.c_valid && rel_device_id == i && device[i].c_ready;
    assign device[i].c_valid   = host.c_valid && rel_device_id == i;

    assign device[i].c_opcode  = host.c_opcode;
    assign device[i].c_param   = host.c_param;
    assign device[i].c_size    = host.c_size;
    assign device[i].c_source  = host.c_source;
    assign device[i].c_address = host.c_address;
    assign device[i].c_corrupt = host.c_corrupt;
    assign device[i].c_data    = host.c_data;
  end

  assign host.c_ready = |rel_ready_mult;

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

  // Grouped signals before multiplexing/arbitration
  gnt_t [NumLinks-1:0] gnt_mult;
  logic [NumLinks-1:0] gnt_valid_mult;
  logic [NumLinks-1:0] gnt_ready_mult;

  for (genvar i = 0; i < NumLinks; i++) begin
    assign gnt_mult[i] = gnt_t'{
      device[i].d_opcode,
      device[i].d_param,
      device[i].d_size,
      device[i].d_source,
      device[i].d_sink,
      device[i].d_denied,
      device[i].d_corrupt,
      device[i].d_data
    };
    assign gnt_valid_mult[i] = device[i].d_valid;

    assign device[i].d_ready = gnt_ready_mult[i];
  end

  // Signals after multiplexing
  gnt_t gnt;
  logic gnt_valid;
  logic gnt_ready;

  assign gnt_ready = host.d_ready;

  assign host.d_valid   = gnt_valid;
  assign host.d_opcode  = gnt.opcode;
  assign host.d_param   = gnt.param;
  assign host.d_size    = gnt.size;
  assign host.d_source  = gnt.source;
  assign host.d_sink    = gnt.sink;
  assign host.d_denied  = gnt.denied;
  assign host.d_corrupt = gnt.corrupt;
  assign host.d_data    = gnt.data;

  // Determine the boundary of a message.
  logic                     gnt_last;
  logic [BurstLenWidth-1:0] gnt_len_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      gnt_len_q <= 0;
    end else begin
      if (gnt_valid && gnt_ready) begin
        if (gnt_len_q == 0) begin
          if (gnt.opcode[0])
            gnt_len_q <= burst_len(gnt.size);
        end else begin
          gnt_len_q <= gnt_len_q - 1;
        end
      end
    end
  end

  assign gnt_last = gnt_len_q == 0 ? (gnt.size <= NonBurstSize || !gnt.opcode[0]) : gnt_len_q == 1;

  // Signals for arbitration
  logic [NumLinks-1:0] gnt_arb_grant;
  logic                gnt_locked;
  logic [NumLinks-1:0] gnt_selected;

  openip_round_robin_arbiter #(.WIDTH(NumLinks)) gnt_arb (
    .clk     (clk_i),
    .rstn    (rst_ni),
    .enable  (!gnt_locked),
    .request (gnt_valid_mult),
    .grant   (gnt_arb_grant)
  );

  // Perform arbitration, and make sure that until we encounter gnt_last we keep the connection stable.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      gnt_locked <= 1'b0;
      gnt_selected <= '0;
    end
    else begin
      if (gnt_locked) begin
        if (gnt_valid && gnt_ready && gnt_last) begin
          gnt_locked <= 1'b0;
        end
      end
      else if (gnt_arb_grant) begin
        gnt_locked   <= 1'b1;
        gnt_selected <= gnt_arb_grant;
      end
    end
  end

  for (genvar i = 0; i < NumLinks; i++) begin
    assign gnt_ready_mult[i] = gnt_locked && gnt_selected[i] && gnt_ready;
  end

  // Do the post-arbitration multiplexing
  always_comb begin
    gnt = gnt_t'('x);
    gnt_valid = 1'b0;
    if (gnt_locked) begin
      for (int i = NumLinks - 1; i >= 0; i--) begin
        if (gnt_selected[i]) begin
          gnt = gnt_mult[i];
          gnt_valid = gnt_valid_mult[i];
        end
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
      if ((host.e_sink &~ SinkMask[i]) == SinkBase[i]) begin
        ack_device_id = SinkLink[i];
      end
    end
  end

  logic [NumLinks-1:0] ack_ready_mult;

  for (genvar i = 0; i < NumLinks; i++) begin
    assign ack_ready_mult[i] = host.e_valid && ack_device_id == i && device[i].e_ready;
    assign device[i].e_valid = host.e_valid && ack_device_id == i;

    assign device[i].e_sink  = host.e_sink;
  end

  assign host.e_ready = |ack_ready_mult;

endmodule
