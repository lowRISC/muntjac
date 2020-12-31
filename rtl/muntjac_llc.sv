module muntjac_llc_raw import tl_pkg::*; import muntjac_pkg::*; #(
  // Number of sets is `2 ** SetsWidth`
  parameter SetsWidth = 8,
  // Number of ways is `2 ** WaysWidth`.
  parameter WaysWidth = 2,

  parameter AddrWidth = 56,
  parameter DataWidth = 64,
  parameter SizeWidth = 3,
  parameter SourceWidth = 1,
  parameter int unsigned SinkWidth   = 1,

  // Address property table.
  // This table is used to determine if a given address range is cacheable or writable.
  // 2'b00 -> Normal
  // 2'b01 -> Readonly (e.g. ROM)
  // 2'b10 -> I/O
  // When ranges overlap, range that is specified with larger index takes priority.
  // If no ranges match, the property is assumed to be normal.
  parameter int unsigned NumAddressRange = 1,
  parameter bit [NumAddressRange-1:0][AddrWidth-1:0] AddressBase = '0,
  parameter bit [NumAddressRange-1:0][AddrWidth-1:0] AddressMask = '0,
  parameter bit [NumAddressRange-1:0][1:0]           AddressProperty = '0,

  // Source ID table for cacheable hosts.
  // These IDs are used for sending out Probe messages.
  // Ranges must not overlap.
  parameter NumCachedHosts = 1,
  parameter logic [NumCachedHosts-1:0][SourceWidth-1:0] SourceBase = '0,
  parameter logic [NumCachedHosts-1:0][SourceWidth-1:0] SourceMask = '0
) (
    input  logic clk_i,
    input  logic rst_ni,
    // Interface to CPU
    tl_channel.device host,

    // Interface to memory
    tl_channel.host device
);

  localparam NumWays = 2 ** WaysWidth;
  localparam MaxSize = 6;

  /////////////////////////////////
  // Burst tracker instantiation //
  /////////////////////////////////

  wire host_req_last;
  wire rel_last;
  wire host_gnt_last;
  wire device_req_last;
  wire device_gnt_last;

  tl_burst_tracker #(
    .DataWidth (DataWidth),
    .SizeWidth (SizeWidth),
    .MaxSize (MaxSize)
  ) host_burst_tracker (
    .clk_i,
    .rst_ni,
    .link (host),
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
    .rel_last_o (rel_last),
    .gnt_last_o (host_gnt_last)
  );

  tl_burst_tracker #(
    .DataWidth (DataWidth),
    .SizeWidth (SizeWidth),
    .MaxSize (MaxSize)
  ) device_burst_tracker (
    .clk_i,
    .rst_ni,
    .link (device),
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

  assign device.b_ready   = 1'b1;

  assign device.c_valid   = 1'b0;
  assign device.c_opcode  = tl_c_op_e'('x);
  assign device.c_param   = 'x;
  assign device.c_size    = 'x;
  assign device.c_source  = 'x;
  assign device.c_address = 'x;
  assign device.c_corrupt = 'x;
  assign device.c_data    = 'x;

  assign device.e_valid   = 1'b0;
  assign device.e_sink    = 'x;

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

  // We have two origins of A channel requests to device:
  // 0. Dirty data writeback
  // 1. Cache line refill
  // 2. Uncached access
  localparam ReqOrigins = 3;
  localparam ReqIdxWb = 0;
  localparam ReqIdxRefill = 1;
  localparam ReqIdxUncached = 2;

  // Grouped signals before multiplexing/arbitration
  req_t [ReqOrigins-1:0] device_req_mult;
  logic [ReqOrigins-1:0] device_req_valid_mult;
  logic [ReqOrigins-1:0] device_req_ready_mult;

  // Signals after multiplexing
  req_t device_req;
  logic device_req_valid;
  logic device_req_ready;

  assign device_req_ready = device.a_ready;

  assign device.a_valid   = device_req_valid;
  assign device.a_opcode  = device_req.opcode;
  assign device.a_param   = device_req.param;
  assign device.a_size    = device_req.size;
  assign device.a_source  = device_req.source;
  assign device.a_address = device_req.address;
  assign device.a_mask    = device_req.mask;
  assign device.a_corrupt = device_req.corrupt;
  assign device.a_data    = device_req.data;

  // Signals for arbitration
  logic [ReqOrigins-1:0] device_req_arb_grant;
  logic                  device_req_locked;
  logic [ReqOrigins-1:0] device_req_selected;

  openip_round_robin_arbiter #(.WIDTH(ReqOrigins)) device_req_arb (
    .clk     (clk_i),
    .rstn    (rst_ni),
    .enable  (device_req_valid && device_req_ready && !device_req_locked),
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
      if (device_req_valid && device_req_ready) begin
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
    assign device_req_ready_mult[i] = device_req_select[i] && device_req_ready;
  end

  // Do the post-arbitration multiplexing
  always_comb begin
    device_req = req_t'('x);
    device_req_valid = 1'b0;
    for (int i = ReqOrigins - 1; i >= 0; i--) begin
      if (device_req_select[i]) begin
        device_req = device_req_mult[i];
        device_req_valid = device_req_valid_mult[i];
      end
    end
  end

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

  // We have three origins of D channel response to host:
  // 0. ReleaseAck response to host's Release
  // 1. Device D channel response
  // 2. Uncached access
  localparam GntOrigins = 3;
  localparam GntIdxRel = 0;
  localparam GntIdxReq = 1;
  localparam GntIdxUncached = 2;

  // Grouped signals before multiplexing/arbitration
  gnt_t [GntOrigins-1:0] host_gnt_mult;
  logic [GntOrigins-1:0] host_gnt_valid_mult;
  logic [GntOrigins-1:0] host_gnt_ready_mult;

  // Signals after multiplexing
  gnt_t host_gnt;
  logic host_gnt_valid;
  logic host_gnt_ready;

  assign host_gnt_ready = host.d_ready;

  assign host.d_valid   = host_gnt_valid;
  assign host.d_opcode  = host_gnt.opcode;
  assign host.d_param   = host_gnt.param;
  assign host.d_size    = host_gnt.size;
  assign host.d_source  = host_gnt.source;
  assign host.d_sink    = host_gnt.sink;
  assign host.d_denied  = host_gnt.denied;
  assign host.d_corrupt = host_gnt.corrupt;
  assign host.d_data    = host_gnt.data;

  // Signals for arbitration
  logic [GntOrigins-1:0] host_gnt_arb_grant;
  logic                  host_gnt_locked;
  logic [GntOrigins-1:0] host_gnt_selected;

  openip_round_robin_arbiter #(.WIDTH(GntOrigins)) host_gnt_arb (
    .clk     (clk_i),
    .rstn    (rst_ni),
    .enable  (host_gnt_valid && host_gnt_ready && !host_gnt_locked),
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
      if (host_gnt_valid && host_gnt_ready) begin
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
    assign host_gnt_ready_mult[i] = host_gnt_select[i] && host_gnt_ready;
  end

  // Do the post-arbitration multiplexing
  always_comb begin
    host_gnt = gnt_t'('x);
    host_gnt_valid = 1'b0;
    for (int i = GntOrigins - 1; i >= 0; i--) begin
      if (host_gnt_select[i]) begin
        host_gnt = host_gnt_mult[i];
        host_gnt_valid = host_gnt_valid_mult[i];
      end
    end
  end

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
    // Whether this cache line is valid at all.
    logic valid;
  } tag_t;

  //////////////////////////////////
  // MEM Channel D Demultiplexing //
  //////////////////////////////////

  wire tl_d_op_e       device_gnt_opcode  = device.d_opcode;
  wire [SizeWidth-1:0] device_gnt_size    = device.d_size;
  wire [2:0]           device_gnt_param   = device.d_param;
  wire                 device_gnt_denied  = device.d_denied;
  wire                 device_gnt_corrupt = device.d_corrupt;
  wire [63:0]          device_gnt_data    = device.d_data;

  localparam SourceRefill = 0;
  localparam SourceWriteback = 1;
  localparam SourceAccess = 2;
  localparam SourceUncached = 3;

  wire device_gnt_valid_refill = device.d_valid && device.d_source == SourceRefill;
  wire device_gnt_valid_writeback = device.d_valid && device.d_source == SourceWriteback;
  wire device_gnt_valid_access = device.d_valid && device.d_source == SourceAccess;
  wire device_gnt_valid_uncached = device.d_valid && device.d_source == SourceUncached;

  logic device_gnt_ready_refill;
  logic device_gnt_ready_writeback;
  logic device_gnt_ready_access;
  logic device_gnt_ready_uncached;
  assign device.d_ready = device_gnt_valid_refill ? device_gnt_ready_refill :
                          device_gnt_valid_writeback ? device_gnt_ready_writeback :
                          device_gnt_ready_access ? device_gnt_ready_access : device_gnt_ready_uncached;

  ///////////////////////////////////
  // Host Channel E Demultiplexing //
  ///////////////////////////////////

  localparam SinkReq = 0;
  localparam SinkUncached = 1;

  wire host_ack_valid_req = host.e_valid && host.e_sink == SinkReq;
  wire host_ack_valid_uncached = host.e_valid && host.e_sink == SinkUncached;

  assign host.e_ready = 1'b1;

  //////////////////////////////
  // Cache access arbitration //
  //////////////////////////////

  logic refill_lock_acq;
  logic refill_lock_rel;
  logic wb_lock_move;
  logic wb_lock_rel;
  logic access_lock_acq;
  logic access_lock_rel;
  logic release_lock_acq;
  logic release_lock_rel;
  logic flush_lock_acq;
  logic flush_lock_rel;

  typedef enum logic [2:0] {
    LockHolderNone,
    LockHolderRefill,
    LockHolderWriteback,
    LockHolderAccess,
    LockHolderRelease,
    LockHolderFlush
  } lock_holder_e;

  logic flush_lock_acq_pending_q, flush_lock_acq_pending_d;
  lock_holder_e lock_holder_q, lock_holder_d;

  wire refill_locked  = lock_holder_q == LockHolderRefill;
  wire access_locking = lock_holder_d == LockHolderAccess;
  wire access_locked = lock_holder_q == LockHolderAccess;
  wire release_locking  = lock_holder_d == LockHolderRelease;
  wire flush_locking  = lock_holder_d == LockHolderFlush;

  // Arbitrate on the new holder of the lock
  always_comb begin
    lock_holder_d = lock_holder_q;
    flush_lock_acq_pending_d = flush_lock_acq_pending_q || flush_lock_acq;

    if (refill_lock_rel || wb_lock_rel || access_lock_rel || release_lock_rel || flush_lock_rel) begin
      lock_holder_d = LockHolderNone;
    end

    if (wb_lock_move) begin
      lock_holder_d = LockHolderWriteback;
    end

    if (lock_holder_d == LockHolderNone) begin
      priority case (1'b1)
        refill_lock_acq: begin
          lock_holder_d = LockHolderRefill;
        end
        flush_lock_acq_pending_d: begin
          lock_holder_d = LockHolderFlush;
          flush_lock_acq_pending_d = 1'b0;
        end
        release_lock_acq: begin
          lock_holder_d = LockHolderRelease;
        end
        access_lock_acq: begin
          lock_holder_d = LockHolderAccess;
        end
        default:;
      endcase
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      flush_lock_acq_pending_q <= 1'b0;
      lock_holder_q <= LockHolderFlush;
    end else begin
      flush_lock_acq_pending_q <= flush_lock_acq_pending_d;
      lock_holder_q <= lock_holder_d;
    end
  end

  ////////////////////////////
  // Cache access multiplex //
  ////////////////////////////

  logic                   wb_data_req;
  logic [WaysWidth-1:0]   wb_data_way;
  logic [SetsWidth+3-1:0] wb_data_addr;

  logic                     access_tag_req;
  logic [AddrWidth-3-1:0] access_tag_addr;
  logic [WaysWidth-1:0]     access_tag_wway;
  logic                     access_tag_write;
  tag_t                     access_tag_wdata;

  logic                   access_data_req;
  logic [WaysWidth-1:0]   access_data_way;
  logic [SetsWidth+3-1:0] access_data_addr;
  logic                   access_data_write;
  logic [7:0]             access_data_wmask;
  logic [63:0]            access_data_wdata;

  logic                   refill_tag_req;
  logic [SetsWidth+3-1:0] refill_tag_addr;
  logic [WaysWidth-1:0]   refill_tag_wway;
  tag_t                   refill_tag_wdata;

  logic                   refill_data_req;
  logic [WaysWidth-1:0]   refill_data_way;
  logic [SetsWidth+3-1:0] refill_data_addr;
  logic [63:0]            refill_data_wdata;

  logic                     release_tag_req;
  logic [AddrWidth-3-1:0] release_tag_addr;
  logic                     release_tag_write;
  logic [WaysWidth-1:0]     release_tag_wway;
  tag_t                     release_tag_wdata;

  logic                   release_data_req;
  logic [WaysWidth-1:0]   release_data_way;
  logic [SetsWidth+3-1:0] release_data_addr;
  logic                   release_data_write;
  logic [63:0]            release_data_wdata;

  logic                  flush_tag_req;
  logic [SetsWidth-1:0]  flush_tag_set;
  logic [NumWays-1:0]    flush_tag_wway;
  tag_t                  flush_tag_wdata;

  logic                 tag_req;
  logic [SetsWidth-1:0] tag_set;
  logic                 tag_write;
  logic [NumWays-1:0]   tag_wways;
  tag_t                 tag_wdata;
  tag_t                 tag_rdata [NumWays];

  logic [AddrWidth-6-1:0] tag_addr;

  logic                 data_req;
  logic [WaysWidth-1:0] data_way;
  logic [SetsWidth-1:0] data_set;
  logic [2:0]           data_offset;
  logic                 data_write;
  logic [7:0]           data_wmask;
  logic [63:0]          data_wdata;
  logic [63:0]          data_rdata;

  always_comb begin
    tag_req = 1'b0;
    tag_set = 'x;
    tag_write = 1'b0;
    tag_wways = '0;
    tag_wdata = tag_t'('x);
    tag_addr = 0;

    data_req = 1'b0;
    data_way = 'x;
    data_set = 'x;
    data_offset = 'x;
    data_write = 1'b0;
    data_wdata = 'x;
    data_wmask = 'x;

    // Tag memory access
    unique case (lock_holder_d)
      LockHolderRefill: begin
        tag_req = refill_tag_req;
        tag_set = refill_tag_addr[SetsWidth+3-1:3];
        tag_write = 1'b1;
        for (int i = 0; i < NumWays; i++) tag_wways[i] = refill_tag_wway == i;
        tag_wdata = refill_tag_wdata;
      end
      LockHolderFlush: begin
        tag_req = flush_tag_req;
        tag_set = flush_tag_set;
        tag_write = 1'b1;
        tag_wways = flush_tag_wway;
        tag_wdata = flush_tag_wdata;
      end
      LockHolderRelease: begin
        tag_req = release_tag_req;
        tag_set = release_tag_addr[SetsWidth+3-1:3];
        tag_write = release_tag_write;
        for (int i = 0; i < NumWays; i++) tag_wways[i] = release_tag_wway == i;
        tag_wdata = release_tag_wdata;

        tag_addr = release_tag_addr[AddrWidth-3-1:3];
      end
      LockHolderAccess: begin
        tag_req = access_tag_req;
        tag_set = access_tag_addr[SetsWidth+3-1:3];
        tag_write = access_tag_write;
        for (int i = 0; i < NumWays; i++) tag_wways[i] = access_tag_wway == i;
        tag_wdata = access_tag_wdata;

        tag_addr = access_tag_addr[AddrWidth-3-1:3];
      end
      default:;
    endcase

    // Data memory access
    unique case (lock_holder_d)
      LockHolderRefill: begin
        data_req = refill_data_req;
        data_way = refill_data_way;
        data_set = refill_data_addr[SetsWidth+3-1:3];
        data_offset = refill_data_addr[2:0];
        data_write = 1'b1;
        data_wmask = '1;
        data_wdata = refill_data_wdata;
      end
      LockHolderWriteback: begin
        data_req = wb_data_req;
        data_way = wb_data_way;
        data_set = wb_data_addr[SetsWidth+3-1:3];
        data_offset = wb_data_addr[2:0];
      end
      LockHolderRelease: begin
        data_req = release_data_req;
        data_way = release_data_way;
        data_set = release_data_addr[SetsWidth+3-1:3];
        data_offset = release_data_addr[2:0];
        data_write = release_data_write;
        data_wmask = '1;
        data_wdata = release_data_wdata;
      end
      LockHolderAccess: begin
        data_req = access_data_req;
        data_way = access_data_way;
        data_set = access_data_addr[SetsWidth+3-1:3];
        data_offset = access_data_addr[2:0];
        data_write = access_data_write;
        data_wmask = access_data_wmask;
        data_wdata = access_data_wdata;
      end
      default:;
    endcase
  end

  /////////////////////
  // Cache tag check //
  /////////////////////

  logic [AddrWidth-6-1:0] tag_addr_q;

  logic [NumWays-1:0] hit;
  logic [WaysWidth-1:0] hit_way_fallback;
  logic [WaysWidth-1:0] hit_way;

  always_comb begin
    // Find cache line that hits
    hit = '0;
    for (int i = 0; i < NumWays; i++) begin
      if (tag_rdata[i].valid &&
          tag_rdata[i].tag == tag_addr[AddrWidth-6-1:SetsWidth]) begin
          hit[i] = 1'b1;
      end
    end

    // Fallback to a way specified by miss handlinglogic
    hit_way = hit_way_fallback;

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
    end else begin
      if (tag_req) begin
        tag_addr_q <= tag_addr;
      end
    end
  end

  ////////////////////////
  // SRAM Instantiation //
  ////////////////////////

  logic [63:0] data_wmask_expanded;
  always_comb begin
    for (int i = 0; i < 8; i++) begin
      data_wmask_expanded[i * 8 +: 8] = data_wmask[i] ? 8'hff : 8'h00;
    end
  end

  for (genvar i = 0; i < NumWays; i++) begin: ram
    prim_generic_ram_1p #(
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
      .rdata_o (tag_rdata[i])
    );
  end

  prim_generic_ram_1p #(
    .Width           (64),
    .Depth           (2 ** (WaysWidth + SetsWidth + 3)),
    .DataBitsPerMask (8)
  ) data_ram (
    .clk_i   (clk_i),
    .req_i   (data_req),
    .write_i (data_write),
    .addr_i  ({data_way, data_set, data_offset}),
    .wdata_i (data_wdata),
    .wmask_i (data_wmask_expanded),
    .rdata_o (data_rdata)
  );

  ////////////////////////////////
  // Dirty Data Writeback Logic //
  ////////////////////////////////

  typedef enum logic [1:0] {
    WbStateIdle,
    WbStateInit,
    WbStateProgress,
    WbStateDone
  } wb_state_e;

  logic                 wb_req_valid;
  logic [WaysWidth-1:0] wb_req_way;
  logic [AddrWidth-7:0] wb_req_address;

  logic wb_complete;

  wb_state_e            wb_state_q, wb_state_d;
  logic [WaysWidth-1:0] wb_way_q, wb_way_d;
  logic [2:0]           wb_offset_q, wb_offset_d;
  logic [AddrWidth-7:0] wb_address_q, wb_address_d;

  always_comb begin
    wb_data_req = 1'b0;
    wb_data_way = 'x;
    wb_data_addr = 'x;

    wb_lock_move = 1'b0;
    wb_lock_rel = 1'b0;

    wb_state_d = wb_state_q;
    wb_offset_d = wb_offset_q;
    wb_way_d = wb_way_q;
    wb_address_d = wb_address_q;

    device_req_valid_mult[ReqIdxWb] = 1'b0;
    device_req_mult[ReqIdxWb].opcode = PutFullData;
    device_req_mult[ReqIdxWb].param = 0;
    device_req_mult[ReqIdxWb].size = 6;
    device_req_mult[ReqIdxWb].source = SourceWriteback;
    device_req_mult[ReqIdxWb].address = {wb_address_q, 6'd0};
    device_req_mult[ReqIdxWb].mask = '1;
    device_req_mult[ReqIdxWb].corrupt = 1'b0;
    device_req_mult[ReqIdxWb].data = data_rdata;

    device_gnt_ready_writeback = 1'b1;
    wb_complete = device_gnt_valid_writeback;

    unique case (wb_state_q)
      WbStateIdle:;

      WbStateInit: begin
        wb_lock_move = 1'b1;
        wb_data_req = 1'b1;
        wb_data_way = wb_way_q;
        wb_data_addr = {wb_address_q[SetsWidth-1:0], wb_offset_q};
        wb_offset_d = wb_offset_q + 1;
        wb_state_d = WbStateProgress;
      end

      WbStateProgress: begin
        device_req_valid_mult[ReqIdxWb] = 1'b1;

        wb_data_way = wb_way_q;
        wb_data_addr = {wb_address_q[SetsWidth-1:0], wb_offset_q};

        if (device_req_ready_mult[ReqIdxWb]) begin
          wb_offset_d = wb_offset_q + 1;

          if (wb_offset_q == 0) begin
            wb_state_d = WbStateDone;
          end else begin
            wb_data_req = 1'b1;
          end
        end
      end

      WbStateDone: begin
        wb_lock_rel = 1'b1;
        wb_state_d = WbStateIdle;
      end

      default:;
    endcase

    if (wb_req_valid) begin
      wb_state_d = WbStateInit;
      wb_offset_d = 0;
      wb_way_d = wb_req_way;
      wb_address_d = wb_req_address;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      wb_state_q <= WbStateIdle;
      wb_offset_q <= 0;
      wb_way_q <= 0;
      wb_address_q <= 'x;
    end else begin
      wb_state_q <= wb_state_d;
      wb_offset_q <= wb_offset_d;
      wb_way_q <= wb_way_d;
      wb_address_q <= wb_address_d;
    end
  end

  //////////////////
  // Refill Logic //
  //////////////////

  logic                 refill_req_valid;
  logic [AddrWidth-7:0] refill_req_address;
  logic [WaysWidth-1:0] refill_req_way;

  logic refill_complete;

  typedef enum logic [1:0] {
    RefillStateIdle,
    RefillStateProgress,
    RefillStateComplete
  } refill_state_e;

  refill_state_e refill_state_q = RefillStateIdle, refill_state_d;

  logic                 refill_req_sent_q, refill_req_sent_d;
  logic [AddrWidth-7:0] refill_address_q, refill_address_d;
  logic [WaysWidth-1:0] refill_way_q, refill_way_d;
  logic [2:0]           refill_index_q, refill_index_d;

  always_comb begin
    refill_tag_wway = 'x;
    refill_tag_addr = 'x;
    refill_tag_req = 1'b0;
    refill_tag_wdata = tag_t'('x);

    refill_data_req = 1'b0;
    refill_data_way = 'x;
    refill_data_addr = 'x;
    refill_data_wdata = 'x;

    refill_lock_acq = !refill_locked && !refill_req_sent_q;
    refill_lock_rel = 1'b0;
    device_gnt_ready_refill = 1'b0;
    refill_complete = 1'b0;

    refill_state_d = refill_state_q;
    refill_req_sent_d = refill_req_sent_q;
    refill_address_d = refill_address_q;
    refill_way_d = refill_way_q;
    refill_index_d = refill_index_q;

    device_req_valid_mult[ReqIdxRefill] = !refill_req_sent_q && refill_locked;
    device_req_mult[ReqIdxRefill].opcode = Get;
    device_req_mult[ReqIdxRefill].param = 0;
    device_req_mult[ReqIdxRefill].size = 6;
    device_req_mult[ReqIdxRefill].source = SourceRefill;
    device_req_mult[ReqIdxRefill].address = {refill_address_q, 6'd0};
    device_req_mult[ReqIdxRefill].mask = '1;
    device_req_mult[ReqIdxRefill].corrupt = 1'b0;

    if (device_req_ready_mult[ReqIdxRefill]) refill_req_sent_d = 1'b1;

    if (refill_req_valid) begin
      refill_req_sent_d = 1'b0;
      refill_address_d = refill_req_address;
      refill_way_d = refill_req_way;
      refill_index_d = 0;
    end

    unique case (refill_state_q)
      RefillStateIdle: begin
        if (device_gnt_valid_refill) begin
          refill_state_d = RefillStateProgress;
        end
      end
      RefillStateProgress: begin
        device_gnt_ready_refill = refill_locked;
        refill_tag_wway = refill_way_q;
        refill_tag_addr = {refill_address_q[SetsWidth-1:0], refill_index_q};

        refill_data_way = refill_way_q;
        refill_data_addr = {refill_address_q[SetsWidth-1:0], refill_index_q};

        refill_data_req = device_gnt_valid_refill && device_gnt_opcode == AccessAckData && !device_gnt_denied;
        refill_data_wdata = device_gnt_data;

        // Update the metadata. This should only be done once, we can do it in either time.
        refill_tag_req = device_gnt_valid_refill && &refill_index_q && !device_gnt_denied;
        refill_tag_wdata = tag_t'('x);
        refill_tag_wdata.tag = refill_address_q[AddrWidth-7:SetsWidth];
        refill_tag_wdata.owned = 1'b0;
        refill_tag_wdata.mask = '0;
        refill_tag_wdata.dirty = 1'b0;
        refill_tag_wdata.valid = 1'b1;

        if (device_gnt_valid_refill && device_gnt_ready_refill) begin
          refill_index_d = refill_index_q + 1;
          if (device_gnt_last) begin
            refill_state_d = RefillStateComplete;
            refill_complete = 1'b1;
          end
        end
      end
      RefillStateComplete: begin
        refill_lock_rel = 1'b1;
        refill_state_d = RefillStateIdle;
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      refill_state_q <= RefillStateIdle;
      refill_req_sent_q <= 1'b1;
      refill_address_q <= 'x;
      refill_way_q <= 'x;
      refill_index_q <= 0;
    end else begin
      refill_state_q <= refill_state_d;
      refill_req_sent_q <= refill_req_sent_d;
      refill_address_q <= refill_address_d;
      refill_way_q <= refill_way_d;
      refill_index_q <= refill_index_d;
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

    flush_lock_acq = 1'b0;
    flush_lock_rel = 1'b0;

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
          flush_lock_rel = 1'b1;
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

  ///////////////////////////////
  // Handle I/O and ROM memory //
  ///////////////////////////////

  logic req_valid;
  logic req_ready;

  assign req_valid = host.a_valid;
  assign host.a_ready = req_ready;

  wire tl_a_op_e         req_opcode  = host.a_opcode;
  wire [AddrWidth-1:0]   req_address = host.a_address;
  wire [SourceWidth-1:0] req_source  = host.a_source;
  wire [2:0]             req_param   = host.a_param;
  wire [SizeWidth-1:0]   req_size    = host.a_size;
  wire [DataWidth/8-1:0] req_mask    = host.a_mask;
  wire [DataWidth-1:0]   req_data    = host.a_data;

  logic [1:0] req_address_property;
  always_comb begin
    // Decode the property of the address requested.
    req_address_property = 0;
    for (int i = 0; i < NumAddressRange; i++) begin
      if ((req_address &~ AddressMask[i]) == AddressBase[i]) begin
        req_address_property = AddressProperty[i];
      end
    end
  end

  logic req_allowed;
  always_comb begin
    // Check if the request is allowed with the address property.
    req_allowed = 1'b1;
    case (req_opcode)
      AcquireBlock, AcquirePerm: begin
        if (req_address_property == 2) begin
          req_allowed = 1'b0;
        end else if (req_address_property == 1 && req_param != NtoB) begin
          req_allowed = 1'b0;
        end
      end
      PutPartialData, PutFullData: begin
        if (req_address_property == 1) begin
          req_allowed = 1'b0;
        end
      end
    endcase
  end

  logic req_ready_ram;
  logic req_ready_io;
  assign req_ready = req_valid && req_address_property == 0 ? req_ready_ram : req_ready_io;

  typedef enum logic [3:0] {
    IoStateIdle,
    IoStateActive,
    IoStateException,
    IoStateAckWait
  } io_state_e;

  io_state_e io_state_q, io_state_d;
  tl_a_op_e io_opcode_q, io_opcode_d;
  logic [2:0] io_param_q, io_param_d;
  logic [SourceWidth-1:0] io_source_q, io_source_d;
  logic io_req_sent_q, io_req_sent_d;
  logic io_resp_sent_q, io_resp_sent_d;
  logic [2:0] io_len_q, io_len_d;
  logic io_ack_done_q, io_ack_done_d;

  always_comb begin
    device_req_valid_mult[ReqIdxUncached] = 1'b0;
    device_req_mult[ReqIdxUncached] = req_t'('x);

    host_gnt_valid_mult[GntIdxUncached] = 1'b0;
    host_gnt_mult[GntIdxUncached] = gnt_t'('x);

    device_gnt_ready_uncached = 1'b0;

    req_ready_io = 1'b0;

    io_state_d = io_state_q;
    io_opcode_d = io_opcode_q;
    io_param_d = io_param_q;
    io_source_d = io_source_q;
    io_req_sent_d = io_req_sent_q;
    io_resp_sent_d = io_resp_sent_q;
    io_len_d = io_len_q;
    io_ack_done_d = io_ack_done_q;

    if (host_ack_valid_uncached) io_ack_done_d = 1'b1;

    unique case (io_state_q)
      IoStateIdle: begin
        if (req_valid && req_address_property != 0) begin
          io_opcode_d = req_opcode;
          io_param_d = req_param == NtoB ? toB : toT;
          io_source_d = req_source;
          io_req_sent_d = 1'b0;
          io_resp_sent_d = 1'b0;
          io_ack_done_d = !(req_opcode inside {AcquireBlock, AcquirePerm});

          if (req_allowed) begin
            io_state_d = IoStateActive;
          end else begin
            io_state_d = IoStateException;
          end
        end
      end

      IoStateActive: begin
        device_req_valid_mult[ReqIdxUncached] = !io_req_sent_q && req_valid;
        device_req_mult[ReqIdxUncached].opcode = io_opcode_q == AcquireBlock ? Get : io_opcode_q;
        device_req_mult[ReqIdxUncached].param = 0;
        device_req_mult[ReqIdxUncached].size = req_size;
        device_req_mult[ReqIdxUncached].source = SourceUncached;
        device_req_mult[ReqIdxUncached].address = req_address;
        device_req_mult[ReqIdxUncached].mask = req_mask;
        device_req_mult[ReqIdxUncached].corrupt = 1'b0;
        device_req_mult[ReqIdxUncached].data = req_data;

        req_ready_io = !io_req_sent_q && device_req_ready_mult[ReqIdxUncached];
        if (req_valid && device_req_ready_mult[ReqIdxUncached] && host_req_last) begin
          io_req_sent_d = 1'b1;
        end

        device_gnt_ready_uncached = !io_resp_sent_q && host_gnt_ready_mult[GntIdxUncached];
        host_gnt_valid_mult[GntIdxUncached] = device_gnt_valid_uncached;
        host_gnt_mult[GntIdxUncached].opcode = io_opcode_q == AcquireBlock ? GrantData : device_gnt_opcode;
        host_gnt_mult[GntIdxUncached].param = io_param_q;
        host_gnt_mult[GntIdxUncached].size = device_gnt_size;
        host_gnt_mult[GntIdxUncached].source = io_source_q;
        host_gnt_mult[GntIdxUncached].sink = SinkUncached;
        host_gnt_mult[GntIdxUncached].denied = device_gnt_denied;
        host_gnt_mult[GntIdxUncached].corrupt = device_gnt_corrupt;
        host_gnt_mult[GntIdxUncached].data = device_gnt_data;

        if (device_gnt_valid_uncached && host_gnt_ready_mult[GntIdxUncached] && device_gnt_last) begin
          io_resp_sent_d = 1'b1;
        end

        if (io_req_sent_d && io_resp_sent_d && io_ack_done_d) begin
          io_state_d = IoStateIdle;
        end
      end

      IoStateException: begin
        // If we haven't see last, we need to make sure the entire request is discarded,
        // not just the first cycle of the burst.
        if (!(req_valid && host_req_last)) begin
          req_ready_io = 1'b1;
        end else begin
          host_gnt_valid_mult[GntIdxUncached] = 1'b1;
          host_gnt_mult[GntIdxUncached].opcode = req_opcode == AcquireBlock ? Grant : (req_opcode == Get ? AccessAckData : AccessAck);
          host_gnt_mult[GntIdxUncached].param = 0;
          host_gnt_mult[GntIdxUncached].size = 6;
          host_gnt_mult[GntIdxUncached].source = req_source;
          host_gnt_mult[GntIdxUncached].sink = SinkUncached;
          host_gnt_mult[GntIdxUncached].denied = 1'b1;
          host_gnt_mult[GntIdxUncached].corrupt = req_opcode == Get ? 1'b1 : 1'b0;

          if (host_gnt_ready_mult[GntIdxUncached]) begin
            io_len_d = io_len_q + 1;
            if (req_opcode != Get || io_len_q == 7) begin
              req_ready_io = 1'b1;

              io_state_d = IoStateAckWait;
              io_len_d = 0;
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
      io_source_q <= 'x;
      io_req_sent_q <= 1'b0;
      io_resp_sent_q <= 1'b0;
      io_len_q <= 0;
      io_ack_done_q <= 1'b0;
    end
    else begin
      io_state_q <= io_state_d;
      io_opcode_q <= io_opcode_d;
      io_param_q <= io_param_d;
      io_source_q <= io_source_d;
      io_req_sent_q <= io_req_sent_d;
      io_resp_sent_q <= io_resp_sent_d;
      io_len_q <= io_len_d;
      io_ack_done_q <= io_ack_done_d;
    end
  end

  ////////////////////////////
  // Request handling logic //
  ////////////////////////////

  // Decode the host sending the request.
  logic [NumCachedHosts-1:0] req_selected;
  for (genvar i = 0; i < NumCachedHosts; i++) begin
    assign req_selected[i] = (host.a_source &~ SourceMask[i]) == SourceBase[i];
  end

  typedef enum logic [3:0] {
    StateIdle,

    StateLookup,
    StateGet,
    StatePut,
    StatePutAck,

    StateInv,
    StateWb,
    StateFill,
    StateReplay,

    StateAckWait
  } state_e;

  state_e state_q = StateIdle, state_d;

  tl_a_op_e opcode_q, opcode_d;
  logic [2:0] param_q, param_d;
  logic [2:0] size_q, size_d;
  logic [AddrWidth-1:0] address_q, address_d;
  logic [SourceWidth-1:0] source_q, source_d;

  logic ack_done_q, ack_done_d;

  // Interfacing with probe sequencer
  logic                      probe_ready;
  logic                      probe_valid;
  logic [NumCachedHosts-1:0] probe_mask;
  logic [2:0]                probe_param;
  logic [AddrWidth-1:0]      probe_address;

  logic [NumCachedHosts-1:0] probe_ack_complete;

  // Currently we don't bother to implement PLRU, so just use a round-robin fashion to choose line to evict.
  logic [WaysWidth-1:0] evict_q, evict_d;
  logic [WaysWidth-1:0] way_q, way_d;

  assign hit_way_fallback = evict_q;

  // The state to enter after invalidation has completed.
  state_e post_inv_q, post_inv_d;

  logic [NumCachedHosts-1:0] prb_ack_pending_q, prb_ack_pending_d;

  always_comb begin
    probe_valid = '0;
    probe_mask = 'x;
    probe_param = 'x;
    probe_address = 'x;

    host_gnt_valid_mult[GntIdxReq] = 1'b0;
    host_gnt_mult[GntIdxReq] = gnt_t'('x);

    req_ready_ram = 1'b0;

    device_gnt_ready_access = 1'b0;

    access_tag_wdata = tag_t'('x);
    access_tag_write = 1'b0;
    access_tag_wway = '0;

    access_data_req = 1'b0;
    access_data_way = way_q;
    access_data_addr = 'x;
    access_data_write = 1'b0;
    access_data_wmask = 'x;
    access_data_wdata = 'x;

    ack_done_d = ack_done_q;

    state_d = state_q;
    opcode_d = opcode_q;
    param_d = param_q;
    size_d = size_q;
    address_d = address_q;
    source_d = source_q;

    evict_d = evict_q;
    way_d = way_q;
    post_inv_d = post_inv_q;

    prb_ack_pending_d = prb_ack_pending_q;

    refill_req_valid = 1'b0;
    refill_req_address = 'x;
    refill_req_way = 'x;

    wb_req_valid = 1'b0;
    wb_req_way = 'x;
    wb_req_address = 'x;

    access_lock_acq = 1'b0;
    access_lock_rel = 1'b0;
    access_tag_req = 1'b0;

    if (host_ack_valid_req) ack_done_d = 1'b1;

    unique case (state_q)
      StateIdle: begin
        access_tag_req = 1'b1;
        access_lock_acq = req_valid && req_address_property == 0;

        if (access_locking) begin
          opcode_d = req_opcode;
          param_d = req_param == NtoB ? toB : toT;
          source_d = req_source;
          size_d = req_size;
          address_d = req_address;
          ack_done_d = !(req_opcode inside {AcquireBlock, AcquirePerm});
          state_d = StateLookup;
        end
      end

      StateReplay: begin
        access_tag_req = 1'b1;
        access_lock_acq = 1'b1;

        if (access_locking) begin
          state_d = StateLookup;
        end
      end

      StateLookup: begin
        way_d = hit_way;

        access_tag_req = 1'b1;
        access_tag_wdata = hit_tag;
        access_tag_wway = hit_way;

        access_data_req = 1'b1;
        access_data_way = hit_way;
        access_data_addr = address_q[AddrWidth-1:3];

        if (|hit) begin
          case (opcode_q)
            AcquireBlock, AcquirePerm: begin
              state_d = StateGet;

              // Case A: Not shared by anyone, most trivial case.
              if (hit_tag.mask == 0) begin
                // Make the caching client own the cahce line (i.e. E state in MESI)
                access_tag_wdata.owned = 1'b1;
                param_d = toT;
                access_tag_wdata.mask = req_selected[NumCachedHosts-1:0];
                access_tag_write = 1'b1;
              end
              // Case B: Move into owned state
              else if (param_q == toT) begin
                // Upgrade into owned state
                if (hit_tag.mask == req_selected[NumCachedHosts-1:0]) begin
                  access_tag_wdata.owned = 1'b1;
                  access_tag_write = 1'b1;
                end
                else begin
                  probe_valid = 1'b1;
                  probe_param = toN;
                end
              end
              // Case C: Currently owned
              else if (hit_tag.owned) begin
                probe_valid = 1'b1;
                probe_param = toB;
              end
              // Case D: Shared
              else begin
                // For non-caching clients this will keep mask 0.
                access_tag_wdata.mask = hit_tag.mask | req_selected[NumCachedHosts-1:0];
                access_tag_write = 1'b1;
              end
            end
            Get, PutFullData, PutPartialData: begin
              state_d = opcode_q == Get ? StateGet : StatePut;

              // Case A: Not shared by anyone, most trivial case.
              if (hit_tag.mask == 0) begin
                if (opcode_q != Get) begin
                  access_tag_wdata.dirty = 1'b1;
                  access_tag_write = 1'b1;
                end
              end
              // Case B: Write
              else if (opcode_q != Get) begin
                probe_valid = 1'b1;
                probe_param = toN;
              end
              // Case C: Currently owned
              else if (hit_tag.owned) begin
                probe_valid = 1'b1;
                probe_param = toB;
              end
              // Case D: Read unowned
              else begin
                // Nothing to be done
              end
            end
          endcase
        end
        else begin
          if (hit_tag.valid && hit_tag.mask != 0) begin
            probe_valid = 1'b1;
            probe_param = toN;
          end else if (hit_tag.valid && hit_tag.dirty) begin
            state_d = StateWb;
            wb_req_valid = 1'b1;
            wb_req_way = hit_way;
            wb_req_address = hit_tag_addr[AddrWidth-1:6];
          end else begin
            state_d = StateFill;
            evict_d = evict_q + 1;
            refill_req_valid = 1'b1;
            refill_req_address = address_q[AddrWidth-1:6];
            refill_req_way = hit_way;
          end
        end

        // Filling extra probe parameters.
        probe_mask = hit_tag.mask;
        probe_address = hit_tag_addr;

        if (probe_valid) begin
          access_tag_wdata.owned = 1'b0;
          if (probe_param == toN) access_tag_wdata.mask = 0;
          access_tag_write = 1'b1;

          prb_ack_pending_d = hit_tag.mask;
          post_inv_d = StateLookup;
          state_d = StateInv;
        end
      end

      // Wait for the invalidation ack to reach us.
      StateInv: begin
        access_tag_req = 1'b1;
        access_lock_rel = access_locked;

        if (|probe_ack_complete) begin
          prb_ack_pending_d = prb_ack_pending_q &~ probe_ack_complete;
        end

        if (prb_ack_pending_d == 0) begin
          access_lock_acq = 1'b1;
        end

        if (access_locking) begin
          state_d = post_inv_q;
        end
      end

      StateWb: begin
        if (wb_complete) begin
          state_d = StateFill;
          refill_req_valid = 1'b1;
          refill_req_address = address_q[AddrWidth-1:6];
          refill_req_way = way_q;
        end
      end

      StateFill: begin
        // Release access lock if held.
        access_lock_rel = access_locked;

        if (refill_complete) begin
          state_d = StateReplay;
        end
      end

      StateGet: begin
        host_gnt_valid_mult[GntIdxReq] = 1'b1;
        host_gnt_mult[GntIdxReq].opcode = opcode_q == AcquireBlock ? GrantData : AccessAckData;
        host_gnt_mult[GntIdxReq].param = param_q;
        host_gnt_mult[GntIdxReq].size = req_size;
        host_gnt_mult[GntIdxReq].source = source_q;
        host_gnt_mult[GntIdxReq].sink = SinkReq;
        host_gnt_mult[GntIdxReq].denied = 1'b0;
        host_gnt_mult[GntIdxReq].corrupt = 1'b0;
        host_gnt_mult[GntIdxReq].data = data_rdata;

        if (host_gnt_ready_mult[GntIdxReq]) begin
          address_d = address_q + 8;
          access_data_req = 1'b1;
          access_data_addr = address_d[AddrWidth-1:3];

          if (host_gnt_last) begin
            // Consume the request
            req_ready_ram = 1'b1;

            access_lock_rel = 1'b1;
            state_d = StateAckWait;
          end
        end
      end

      StatePut: begin
        req_ready_ram = 1'b1;

        access_data_req = req_valid;
        access_data_addr = address_q[3+:SetsWidth+3];
        access_data_write = 1'b1;
        access_data_wmask = req_mask;
        access_data_wdata = req_data;

        if (req_valid) begin
          address_d = address_q + 8;
        end

        if (req_valid && host_req_last) begin
          state_d = StatePutAck;
        end
      end

      StatePutAck: begin
        host_gnt_valid_mult[GntIdxReq] = 1'b1;
        host_gnt_mult[GntIdxReq].opcode = AccessAck;
        host_gnt_mult[GntIdxReq].param = 0;
        host_gnt_mult[GntIdxReq].size = size_q;
        host_gnt_mult[GntIdxReq].source = source_q;
        host_gnt_mult[GntIdxReq].sink = 'x;
        host_gnt_mult[GntIdxReq].denied = 1'b0;
        host_gnt_mult[GntIdxReq].corrupt = 1'b0;
        host_gnt_mult[GntIdxReq].data = 'x;

        if (host_gnt_ready_mult[GntIdxReq]) begin
          access_lock_rel = 1'b1;
          state_d = StateIdle;
        end
      end

      StateAckWait: begin
        if (ack_done_d) state_d = StateIdle;
      end
    endcase

    access_tag_addr = address_d[AddrWidth-1:3];
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= StateIdle;
      opcode_q <= tl_a_op_e'('x);
      param_q <= 'x;
      source_q <= 'x;
      address_q <= 'x;
      size_q <= '0;
      evict_q <= '0;
      way_q <= 'x;
      post_inv_q <= state_e'('x);
      prb_ack_pending_q <= 'x;
      ack_done_q <= 1'b0;
    end
    else begin
      state_q <= state_d;
      opcode_q <= opcode_d;
      param_q <= param_d;
      size_q <= size_d;
      address_q <= address_d;
      source_q <= source_d;
      evict_q <= evict_d;
      way_q <= way_d;
      post_inv_q <= post_inv_d;
      prb_ack_pending_q <= prb_ack_pending_d;
      ack_done_q <= ack_done_d;
    end
  end

  ////////////////////////////
  // Probe channel handling //
  ////////////////////////////

  // Probes yet to be sent.
  logic [NumCachedHosts-1:0] probe_pending_q, probe_pending_d;
  logic [2:0]                probe_param_q, probe_param_d;
  logic [AddrWidth-1:0]      probe_address_q, probe_address_d;

  assign host.b_valid = |probe_pending_q;
  assign host.b_opcode = ProbeBlock;
  assign host.b_param = probe_param_q;
  assign host.b_size = 6;
  assign host.b_address = probe_address_q;
  assign host.b_mask = '1;
  assign host.b_corrupt = 1'b0;
  assign host.b_data = 'x;

  // Zero or onehot bit mask of currently probing host.
  logic [NumCachedHosts-1:0] probe_selected;
  always_comb begin
    host.b_source = 'x;
    probe_selected = '0;
    for (int i = 0; i < NumCachedHosts; i++) begin
      if (probe_pending_q[i]) begin
        probe_selected = '0;
        probe_selected[i] = 1'b1;
        host.b_source = SourceBase[i];
      end
    end
  end

  wire host_prb_ready = host.b_ready;

  always_comb begin
    probe_pending_d = probe_pending_q;
    probe_param_d = probe_param_q;
    probe_address_d = probe_address_q;

    probe_ready = probe_pending_q == 0;

    // A probe has been acknowledged
    if (probe_pending_q != 0 && host_prb_ready) begin
      probe_pending_d = probe_pending_q &~ probe_selected;
    end

    // New probing request
    if (probe_valid) begin
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

  //////////////////////////////
  // Release channel handling //
  //////////////////////////////

  logic rel_valid;
  logic rel_ready;

  assign rel_valid = host.c_valid;
  assign host.c_ready = rel_ready;

  wire tl_c_op_e         rel_opcode  = host.c_opcode;
  wire [2:0]             rel_param   = host.c_param;
  wire [AddrWidth-1:0]   rel_address = host.c_address;
  wire [DataWidth-1:0]   rel_data    = host.c_data;
  wire [SourceWidth-1:0] rel_source  = host.c_source;

  // Decode the host sending the request.
  logic [NumCachedHosts-1:0] rel_selected;
  for (genvar i = 0; i < NumCachedHosts; i++) begin
    assign rel_selected[i] = (host.c_source &~ SourceMask[i]) == SourceBase[i];
  end

  typedef enum logic [2:0] {
    RelStateIdle,
    RelStateLookup,
    RelStateDo,
    RelStateReleaseAck,
    RelStateComplete,
    RelStateError
  } rel_state_e;

  rel_state_e rel_state_q, rel_state_d;
  logic rel_addr_sent_q, rel_addr_sent_d;
  logic [AddrWidth-1:0] rel_wptr_q, rel_wptr_d;
  logic [SourceWidth-1:0] rel_source_q, rel_source_d;
  logic [NumCachedHosts-1:0] rel_selected_q, rel_selected_d;

  always_comb begin
    host_gnt_valid_mult[GntIdxRel] = 1'b0;
    host_gnt_mult[GntIdxRel] = gnt_t'('x);

    rel_ready = 1'b0;

    release_tag_wdata = tag_t'('x);
    release_tag_write = 1'b0;
    release_tag_wway = '0;

    release_data_req = 1'b0;
    release_data_way = 'x;
    release_data_addr = 'x;
    release_data_write = 1'b0;
    release_data_wdata = 'x;

    release_tag_req = 1'b0;
    release_tag_addr = rel_address[AddrWidth-1:3];

    rel_state_d = rel_state_q;
    rel_addr_sent_d = rel_addr_sent_q;
    rel_wptr_d = rel_wptr_q;
    rel_source_d = rel_source_q;
    rel_selected_d = rel_selected_q;

    release_lock_acq = 1'b0;
    release_lock_rel = 1'b0;

    probe_ack_complete = '0;

    unique case (rel_state_q)
      RelStateIdle: begin
        release_tag_req = 1'b1;

        if (rel_valid) begin
          release_lock_acq = 1'b1;
        end

        if (release_locking) begin
          rel_wptr_d = rel_address;
          rel_source_d = rel_source;
          rel_selected_d = rel_selected;

          if (rel_param == NtoN) begin
            // In this case physical address supplied is invalid.
            rel_state_d = RelStateDo;
          end else begin
            rel_state_d = RelStateLookup;
          end
        end
      end

      RelStateLookup: begin
        // Cache valid
        if (|hit) begin
          release_tag_write = 1'b1;
          release_tag_wdata = hit_tag;
          release_tag_wway = hit_way;

          if (rel_opcode inside {ProbeAckData, ReleaseData}) begin
            release_tag_req = 1'b1;
            release_tag_wdata.dirty = 1'b1;
          end

          if (rel_param inside {TtoN, BtoN, NtoN}) begin
            release_tag_req = 1'b1;
            release_tag_wdata.mask = hit_tag.mask &~ rel_selected;
            if (!release_tag_wdata.mask) release_tag_wdata.owned = 1'b0;
          end

          rel_state_d = RelStateDo;
        end else begin
          rel_state_d = RelStateError;
        end
      end

      RelStateDo: begin
        rel_ready = 1'b1;

        release_data_req = rel_valid && (rel_opcode == ProbeAckData || rel_opcode == ReleaseData);
        release_data_way = hit_way;
        release_data_addr = rel_wptr_q[3+:SetsWidth+3];
        release_data_write = 1'b1;
        release_data_wdata = rel_data;

        if (rel_valid) begin
          rel_wptr_d = rel_wptr_q + 8;
        end

        if (rel_valid && rel_last) begin
          if (rel_opcode inside {ProbeAckData, ProbeAck}) begin
            rel_state_d = RelStateComplete;
          end else begin
            rel_state_d = RelStateReleaseAck;
          end
        end
      end

      RelStateReleaseAck: begin
        host_gnt_valid_mult[GntIdxRel] = 1'b1;
        host_gnt_mult[GntIdxRel].opcode = ReleaseAck;
        host_gnt_mult[GntIdxRel].param = 0;
        host_gnt_mult[GntIdxRel].size = 6;
        host_gnt_mult[GntIdxRel].source = rel_source_q;
        host_gnt_mult[GntIdxRel].sink = 'x;
        host_gnt_mult[GntIdxRel].denied = 1'b0;
        host_gnt_mult[GntIdxRel].corrupt = 1'b0;
        host_gnt_mult[GntIdxRel].data = 'x;

        if (host_gnt_ready_mult[GntIdxRel]) begin
          release_lock_rel = 1'b1;
          rel_state_d = RelStateIdle;
        end
      end

      RelStateComplete: begin
        probe_ack_complete = rel_selected_q;
        release_lock_rel = 1'b1;
        rel_state_d = RelStateIdle;
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
      rel_wptr_q <= 'x;
      rel_selected_q <= '0;
    end
    else begin
      rel_state_q <= rel_state_d;
      rel_addr_sent_q <= rel_addr_sent_d;
      rel_source_q <= rel_source_d;
      rel_wptr_q <= rel_wptr_d;
      rel_selected_q <= rel_selected_d;
    end
  end

endmodule

module muntjac_llc import tl_pkg::*; #(
    // Number of sets is `2 ** SetsWidth`
  parameter SetsWidth = 8,
  // Number of ways is `2 ** WaysWidth`.
  parameter WaysWidth = 2,

  parameter AddrWidth = 56,
  parameter DataWidth = 64,
  parameter SizeWidth = 3,
  parameter SourceWidth = 1,
  parameter SinkWidth = 1,

  // Address property table.
  // This table is used to determine if a given address range is cacheable or writable.
  // 2'b00 -> Normal
  // 2'b01 -> Readonly (e.g. ROM)
  // 2'b10 -> I/O
  // When ranges overlap, range that is specified with larger index takes priority.
  // If no ranges match, the property is assumed to be normal.
  parameter int unsigned NumAddressRange = 1,
  parameter bit [NumAddressRange-1:0][AddrWidth-1:0] AddressBase = '0,
  parameter bit [NumAddressRange-1:0][AddrWidth-1:0] AddressMask = '0,
  parameter bit [NumAddressRange-1:0][1:0]           AddressProperty = '0,

  // Source ID table for cacheable hosts.
  // These IDs are used for sending out Probe messages.
  // Ranges must not overlap.
  parameter NumCachedHosts = 1,
  parameter logic [NumCachedHosts-1:0][SourceWidth-1:0] SourceBase = '0,
  parameter logic [NumCachedHosts-1:0][SourceWidth-1:0] SourceMask = '0
) (
  input  logic clk_i,
  input  logic rst_ni,

  tl_channel.device host,
  tl_channel.host   device
);

  tl_channel #(
    .AddrWidth (AddrWidth),
    .DataWidth (DataWidth),
    .SizeWidth (SizeWidth),
    .SourceWidth (SourceWidth),
    .SinkWidth (SinkWidth)
  ) host_reg_ch ();

  tl_regslice #(
    .AddrWidth (AddrWidth),
    .DataWidth (DataWidth),
    .SizeWidth (SizeWidth),
    .SourceWidth (SourceWidth),
    .SinkWidth (SinkWidth),
    .RequestMode (1),
    .ReleaseMode (1)
  ) host_reg (
    .clk_i,
    .rst_ni,
    .host,
    .device (host_reg_ch)
  );

  muntjac_llc_raw #(
    .SetsWidth (SetsWidth),
    .WaysWidth (WaysWidth),
    .AddrWidth (AddrWidth),
    .DataWidth (DataWidth),
    .SizeWidth (SizeWidth),
    .SourceWidth (SourceWidth),
    .SinkWidth (SinkWidth),
    .NumAddressRange (NumAddressRange),
    .AddressBase (AddressBase),
    .AddressMask (AddressMask),
    .AddressProperty (AddressProperty),
    .NumCachedHosts (NumCachedHosts),
    .SourceBase (SourceBase),
    .SourceMask (SourceMask)
  ) inst (
    .clk_i,
    .rst_ni,
    .host (host_reg_ch),
    .device
  );

endmodule
