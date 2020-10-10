module tl_socket_m1 import tl_pkg::*; #(
  parameter  int unsigned SourceWidth   = 1,
  parameter  int unsigned SinkWidth     = 1,
  parameter  int unsigned AddrWidth     = 56,
  parameter  int unsigned DataWidth     = 64,
  parameter  int unsigned SizeWidth     = 3,

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

  tl_channel.device host[NumLinks],
  tl_channel.host   device
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

  for (genvar i = 0; i < NumLinks; i++) begin
    initial begin
      if (host[i].SourceWidth != SourceWidth) $fatal(1, "SourceWidth mismatch");
      if (host[i].SinkWidth < SinkWidth) $fatal(1, "SinkWidth mismatch");
      if (host[i].DataWidth != DataWidth) $fatal(1, "DataWidth mismatch");
      if (host[i].SizeWidth != SizeWidth) $fatal(1, "SizeWidth mismatch");
    end
  end

  if (device.SourceWidth != SourceWidth) $fatal(1, "SourceWidth mismatch");
  if (device.SinkWidth > SinkWidth) $fatal(1, "SinkWidth mismatch");
  if (device.DataWidth != DataWidth) $fatal(1, "DataWidth mismatch");
  if (device.SizeWidth != SizeWidth) $fatal(1, "SizeWidth mismatch");

  /////////////////////
  // Unused channels //
  /////////////////////

  for (genvar i = NumCachedLinks; i < NumLinks; i++) begin
    // We don't use channel B for non-caheable hosts.
    assign host[i].b_valid = 1'b0;
    assign host[i].b_opcode = tl_b_op_e'('x);
    assign host[i].b_param = 'x;
    assign host[i].b_size = 'x;
    assign host[i].b_source = 'x;
    assign host[i].b_address = 'x;
    assign host[i].b_mask = '1;
    assign host[i].b_corrupt = 1'b0;
    assign host[i].b_data = 'x;

    // We don't use channel C and E for non-caheable hosts.
    assign host[i].c_ready = 1'b1;
    assign host[i].e_ready = 1'b1;
  end

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

  // Grouped signals before multiplexing/arbitration
  req_t [NumLinks-1:0] req_mult;
  logic [NumLinks-1:0] req_valid_mult;
  logic [NumLinks-1:0] req_ready_mult;

  for (genvar i = 0; i < NumLinks; i++) begin
    assign req_mult[i] = req_t'{
      host[i].a_opcode,
      host[i].a_param,
      host[i].a_size,
      host[i].a_source,
      host[i].a_address,
      host[i].a_mask,
      host[i].a_corrupt,
      host[i].a_data
    };
    assign req_valid_mult[i] = host[i].a_valid;

    assign host[i].a_ready = req_ready_mult[i];
  end

  // Signals after multiplexing
  req_t req;
  logic req_valid;
  logic req_ready;

  assign req_ready = device.a_ready;

  assign device.a_valid   = req_valid;
  assign device.a_opcode  = req.opcode;
  assign device.a_param   = req.param;
  assign device.a_size    = req.size;
  assign device.a_source  = req.source;
  assign device.a_address = req.address;
  assign device.a_mask    = req.mask;
  assign device.a_corrupt = req.corrupt;
  assign device.a_data    = req.data;

  // Determine the boundary of a message.
  logic                     req_last;
  logic [BurstLenWidth-1:0] req_len_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      req_len_q <= 0;
    end else begin
      if (req_valid && req_ready) begin
        if (req_len_q == 0) begin
          if (req.opcode < 4)
            req_len_q <= burst_len(req.size);
        end else begin
          req_len_q <= req_len_q - 1;
        end
      end
    end
  end

  assign req_last = req_len_q == 0 ? (req.size <= NonBurstSize || req.opcode >= 4) : req_len_q == 1;

  // Signals for arbitration
  logic [NumLinks-1:0] req_arb_grant;
  logic                req_locked;
  logic [NumLinks-1:0] req_selected;

  openip_round_robin_arbiter #(.WIDTH(NumLinks)) req_arb (
    .clk     (clk_i),
    .rstn    (rst_ni),
    .enable  (!req_locked),
    .request (req_valid_mult),
    .grant   (req_arb_grant)
  );

  // Perform arbitration, and make sure that until we encounter req_last we keep the connection stable.
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      req_locked <= 1'b0;
      req_selected <= '0;
    end
    else begin
      if (req_locked) begin
        if (req_valid && req_ready && req_last) begin
          req_locked <= 1'b0;
        end
      end
      else if (req_arb_grant) begin
        req_locked   <= 1'b1;
        req_selected <= req_arb_grant;
      end
    end
  end

  for (genvar i = 0; i < NumLinks; i++) begin
    assign req_ready_mult[i] = req_locked && req_selected[i] && req_ready;
  end

  // Do the post-arbitration multiplexing
  always_comb begin
    req = req_t'('x);
    req_valid = 1'b0;
    if (req_locked) begin
      for (int i = NumLinks - 1; i >= 0; i--) begin
        if (req_selected[i]) begin
          req = req_mult[i];
          req_valid = req_valid_mult[i];
        end
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
        if ((device.b_source &~ SourceMask[i]) == SourceBase[i]) begin
          prb_host_id = SourceLink[i];
        end
      end
    end

    logic [NumCachedLinks-1:0] prb_ready_mult;

    for (genvar i = 0; i < NumCachedLinks; i++) begin
      assign prb_ready_mult[i] = device.b_valid && prb_host_id == i && host[i].b_ready;
      assign host[i].b_valid   = device.b_valid && prb_host_id == i;

      assign host[i].b_opcode  = device.b_opcode;
      assign host[i].b_param   = device.b_param;
      assign host[i].b_size    = device.b_size;
      assign host[i].b_source  = device.b_source;
      assign host[i].b_address = device.b_address;
      assign host[i].b_mask    = device.b_mask;
      assign host[i].b_corrupt = device.b_corrupt;
      assign host[i].b_data    = device.b_data;
    end

    assign device.b_ready = |prb_ready_mult;

  end

  /////////////////////////////////
  // Release channel arbitration //
  /////////////////////////////////

  typedef struct packed {
    tl_c_op_e               opcode;
    logic [2:0]             param;
    logic [SizeWidth-1:0]   size;
    logic [SourceWidth-1:0] source;
    logic [AddrWidth-1:0]   address;
    logic                   corrupt;
    logic [DataWidth-1:0]   data;
  } rel_t;

  if (NumCachedLinks != 0) begin: rel_arb

    // Grouped signals before multiplexing/arbitration
    rel_t [NumCachedLinks-1:0] rel_mult;
    logic [NumCachedLinks-1:0] rel_valid_mult;
    logic [NumCachedLinks-1:0] rel_ready_mult;

    for (genvar i = 0; i < NumCachedLinks; i++) begin
      assign rel_mult[i] = rel_t'{
        host[i].c_opcode,
        host[i].c_param,
        host[i].c_size,
        host[i].c_source,
        host[i].c_address,
        host[i].c_corrupt,
        host[i].c_data
      };
      assign rel_valid_mult[i] = host[i].c_valid;

      assign host[i].c_ready = rel_ready_mult[i];
    end

    // Signals after multiplexing
    rel_t rel;
    logic rel_valid;
    logic rel_ready;

    assign rel_ready = device.c_ready;

    assign device.c_valid   = rel_valid;
    assign device.c_opcode  = rel.opcode;
    assign device.c_param   = rel.param;
    assign device.c_size    = rel.size;
    assign device.c_source  = rel.source;
    assign device.c_address = rel.address;
    assign device.c_corrupt = rel.corrupt;
    assign device.c_data    = rel.data;

    // Determine the boundary of a message.
    logic                     rel_last;
    logic [BurstLenWidth-1:0] rel_len_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        rel_len_q <= 0;
      end else begin
        if (rel_valid && rel_ready) begin
          if (rel_len_q == 0) begin
            if (rel.opcode[0])
              rel_len_q <= burst_len(rel.size);
          end else begin
            rel_len_q <= rel_len_q - 1;
          end
        end
      end
    end

    assign rel_last = rel_len_q == 0 ? (rel.size <= NonBurstSize || !rel.opcode[0]) : rel_len_q == 1;

    // Signals for arbitration
    logic [NumCachedLinks-1:0] rel_arb_grant;
    logic                      rel_locked;
    logic [NumCachedLinks-1:0] rel_selected;

    openip_round_robin_arbiter #(.WIDTH(NumCachedLinks)) rel_arb (
      .clk     (clk_i),
      .rstn    (rst_ni),
      .enable  (!rel_locked),
      .request (rel_valid_mult),
      .grant   (rel_arb_grant)
    );

    // Perform arbitration, and make sure that until we encounter rel_last we keep the connection stable.
    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        rel_locked <= 1'b0;
        rel_selected <= '0;
      end
      else begin
        if (rel_locked) begin
          if (rel_valid && rel_ready && rel_last) begin
            rel_locked <= 1'b0;
          end
        end
        else if (rel_arb_grant) begin
          rel_locked   <= 1'b1;
          rel_selected <= rel_arb_grant;
        end
      end
    end

    for (genvar i = 0; i < NumCachedLinks; i++) begin
      assign rel_ready_mult[i] = rel_locked && rel_selected[i] && rel_ready;
    end

    // Do the post-arbitration multiplexing
    always_comb begin
      rel = rel_t'('x);
      rel_valid = 1'b0;
      if (rel_locked) begin
        for (int i = NumCachedLinks - 1; i >= 0; i--) begin
          if (rel_selected[i]) begin
            rel = rel_mult[i];
            rel_valid = rel_valid_mult[i];
          end
        end
      end
    end

  end else begin

    assign device.c_valid   = 1'b0;
    assign device.c_opcode  = tl_c_op_e'('x);
    assign device.c_param   = 'x;
    assign device.c_size    = 'x;
    assign device.c_source  = 'x;
    assign device.c_address = 'x;
    assign device.c_corrupt = 1'bx;
    assign device.c_data    = 'x;

  end

  /////////////////////////////////
  // Grant channel demultiplexer //
  /////////////////////////////////

  logic [LinkWidth-1:0] gnt_host_id;

  always_comb begin
    gnt_host_id = 0;
    for (int i = 0; i < NumSourceRange; i++) begin
      if ((device.d_source &~ SourceMask[i]) == SourceBase[i]) begin
        gnt_host_id = SourceLink[i];
      end
    end
  end

  logic [NumLinks-1:0] gnt_ready_mult;

  for (genvar i = 0; i < NumLinks; i++) begin
    assign gnt_ready_mult[i] = device.d_valid && gnt_host_id == i && host[i].d_ready;
    assign host[i].d_valid   = device.d_valid && gnt_host_id == i;

    assign host[i].d_opcode  = device.d_opcode;
    assign host[i].d_param   = device.d_param;
    assign host[i].d_size    = device.d_size;
    assign host[i].d_source  = device.d_source;
    assign host[i].d_sink    = device.d_sink;
    assign host[i].d_denied  = device.d_denied;
    assign host[i].d_corrupt = device.d_corrupt;
    assign host[i].d_data    = device.d_data;
  end

  assign device.d_ready = |gnt_ready_mult;

  /////////////////////////////////////////
  // Acknowledgement channel arbitration //
  /////////////////////////////////////////

  if (NumCachedLinks != 0) begin: ack_arb

    // Signals before multiplexing/arbitration
    logic [NumCachedLinks-1:0][SinkWidth-1:0] ack_sink_mult;
    logic [NumCachedLinks-1:0]                ack_valid_mult;
    logic [NumCachedLinks-1:0]                ack_ready_mult;

    for (genvar i = 0; i < NumCachedLinks; i++) begin
      assign ack_sink_mult[i] = host[i].e_sink;
      assign ack_valid_mult[i] = host[i].e_valid;

      assign host[i].e_ready = ack_ready_mult[i];
    end

    // Signals after multiplexing
    logic [SinkWidth-1:0] ack_sink;
    logic                 ack_valid;
    logic                 ack_ready;

    assign ack_ready = device.e_ready;

    assign device.e_valid = ack_valid;
    assign device.e_sink  = ack_sink;

    // Signals for arbitration
    logic [NumCachedLinks-1:0] ack_arb_grant;
    logic                      ack_locked;
    logic [NumCachedLinks-1:0] ack_selected;

    openip_round_robin_arbiter #(.WIDTH(NumCachedLinks)) ack_arb (
      .clk     (clk_i),
      .rstn    (rst_ni),
      .enable  (!ack_locked),
      .request (ack_valid_mult),
      .grant   (ack_arb_grant)
    );

    // Perform arbitration, and make sure that we keep the connection stable until handshake.
    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        ack_locked <= 1'b0;
        ack_selected <= '0;
      end
      else begin
        if (ack_locked) begin
          if (ack_valid && ack_ready) begin
            ack_locked <= 1'b0;
          end
        end
        else if (ack_arb_grant) begin
          ack_locked   <= 1'b1;
          ack_selected <= ack_arb_grant;
        end
      end
    end

    for (genvar i = 0; i < NumCachedLinks; i++) begin
      assign ack_ready_mult[i] = ack_locked && ack_selected[i] && ack_ready;
    end

    // Do the post-arbitration multiplexing
    always_comb begin
      ack_sink = 'x;
      ack_valid = 1'b0;
      if (ack_locked) begin
        for (int i = NumCachedLinks - 1; i >= 0; i--) begin
          if (ack_selected[i]) begin
            ack_sink = ack_sink_mult[i];
            ack_valid = ack_valid_mult[i];
          end
        end
      end
    end

  end else begin

    assign device.e_valid = 1'b0;
    assign device.e_sink  = 'x;

  end

endmodule
