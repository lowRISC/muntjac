`include "tl_util.svh"
`include "axi_util.svh"

// AXI to TL-UH bridge.
module axi_tl_adapter import tl_pkg::*; import axi_pkg::*; #(
    parameter  int unsigned DataWidth   = 64,
    parameter  int unsigned AddrWidth   = 56,
    parameter  int unsigned SourceWidth = 1,
    parameter  int unsigned SinkWidth   = 1,
    parameter  int unsigned MaxSize     = 6,
    parameter  int unsigned IdWidth     = 1
) (
  input  logic       clk_i,
  input  logic       rst_ni,

  `AXI_DECLARE_DEVICE_PORT(DataWidth, AddrWidth, IdWidth, host),
  `TL_DECLARE_HOST_PORT(DataWidth, AddrWidth, SourceWidth, SinkWidth, device)
);

  localparam int unsigned DataWidthInBytes = DataWidth / 8;
  localparam int unsigned NonBurstSize = $clog2(DataWidthInBytes);
  localparam int unsigned UncappedLog2MaxBurstLen = MaxSize - NonBurstSize;
  // Cap the maximum burst length to the maximum supported by the AXI protocol.
  localparam int unsigned Log2MaxBurstLen = UncappedLog2MaxBurstLen > 8 ? 8 : UncappedLog2MaxBurstLen;
  localparam int unsigned MaxBurstLen = 2 ** Log2MaxBurstLen;

  // FIFO converter will use fresh source IDs for outbound, so we can use source IDs
  // carry information at will, and they don't have to be unique.
  localparam int unsigned DeviceSourceWidth = IdWidth + 1;

  `AXI_DECLARE(DataWidth, AddrWidth, IdWidth, host);
  `TL_DECLARE(DataWidth, AddrWidth, DeviceSourceWidth, SinkWidth, device);

  // AXI forbid combinational path between input and outputs.
  // We have a path from {aw,ar}_valid to {aw,ar}_ready.
  // w_valid to w_ready path, while not present in this module, is allowed by TileLink
  // so we also guard against that.
  axi_regslice #(
    .DataWidth (DataWidth),
    .AddrWidth (AddrWidth),
    .IdWidth (IdWidth),
    .AwMode (2),
    .WMode (2),
    .BMode (0),
    .ArMode (2),
    .RMode (0)
  ) host_regslice (
    .clk_i,
    .rst_ni,
    `AXI_FORWARD_DEVICE_PORT(host, host),
    `AXI_CONNECT_HOST_PORT(device, host)
  );

  tl_fifo_converter #(
    .DataWidth (DataWidth),
    .AddrWidth (AddrWidth),
    .HostSourceWidth (DeviceSourceWidth),
    .DeviceSourceWidth (SourceWidth),
    .SinkWidth (SinkWidth),
    .MaxSize (MaxSize)
  ) fifo_cvt (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_DEVICE_PORT(host, device),
    `TL_FORWARD_HOST_PORT(device, device)
  );

  // We don't use channel B, C, E.
  assign device_b_ready = 1'b1;
  assign device_c_valid = 1'b0;
  assign device_c       = 'x;
  assign device_e_valid = 1'b0;
  assign device_e       = 'x;

  ///////////////////////////
  // #region Burst Tracker //

  logic device_a_last;
  logic device_d_last;

  tl_burst_tracker #(
    .AddrWidth (AddrWidth),
    .DataWidth (DataWidth),
    .SourceWidth (DeviceSourceWidth),
    .SinkWidth (SinkWidth),
    .MaxSize (MaxSize)
  ) tl_burst_tracker (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_TAP_PORT(link, device),
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
    .req_last_o (device_a_last),
    .rel_last_o (),
    .gnt_last_o (device_d_last)
  );

  // #endregion
  ///////////////////////////

  ///////////////////////////
  // #region Fragmentation //

  logic [AddrWidth-1:0] pending_address_q;
  logic [8:0] pending_len_q;
  logic [2:0] pending_size_q;

  logic [`TL_SIZE_WIDTH-1:0] fragment_size;
  logic [AddrWidth-1:0] remainder_address;
  logic [8:0] remainder_len;

  always_comb begin
    if (pending_size_q < NonBurstSize) begin
      // No narrow burst support.
      fragment_size = pending_size_q;
      remainder_address = 'x;
      remainder_len = 0;
    end else begin
      logic [`TL_SIZE_WIDTH:0] len_left;
      logic [`TL_SIZE_WIDTH:0] alignment;
      logic [`TL_SIZE_WIDTH:0] max_size;
      logic [8:0] max_len;

      // Find the most signifcant bit that is a 1.
      // This would be the floor of log2 of the size.
      //     len | log2 | 2**log2
      //  0b1111 |    3 | 0b1000
      //  0b1110 |    3 | 0b1000
      //  0b1000 |    3 | 0b1000
      //  0b0111 |    2 | 0b0100
      len_left = 0;
      for (int i = 1; i < Log2MaxBurstLen; i++) begin
        if (pending_len_q[i]) begin
          len_left = i;
        end
      end
      if (pending_len_q[8:Log2MaxBurstLen]) begin
        len_left = Log2MaxBurstLen;
      end

      // Find the least significant bit that is a 1.
      // This would be the log2 of the natural alignment of the address.
      // Example:
      // address | alignment | log2
      //  0b1111 |         1 |    0
      //  0b1110 |         2 |    1
      //  0b1100 |         4 |    2
      // Capped at 8 because the largest burst is 256.
      alignment = Log2MaxBurstLen;
      for (int i = Log2MaxBurstLen - 1; i >= 0; i--) begin
        if (pending_address_q[i + NonBurstSize]) begin
          alignment = i;
        end
      end

      max_size = len_left > alignment ? alignment : len_left;
      max_len = (1 << max_size);

      fragment_size = max_size + NonBurstSize;
      remainder_address = pending_address_q + (max_len << NonBurstSize);
      remainder_len = pending_len_q - max_len;
    end
  end

  // #endregion
  ///////////////////////////

  ///////////////////////
  // #region A Channel //

  function automatic logic [DataWidthInBytes-1:0] get_mask(
    input logic [NonBurstSize-1:0] address,
    input logic [`TL_SIZE_WIDTH-1:0] size
  );
    logic [`TL_SIZE_WIDTH-1:0] capped_size;
    capped_size = size >= NonBurstSize ? NonBurstSize : size;

    get_mask = 1;
    for (int i = 1; i <= NonBurstSize; i++) begin
      if (capped_size == i) begin
        // In this case the mask computed should be all 1
        get_mask = (1 << (2**i)) - 1;
      end else begin
        // In this case the mask is computed from existing mask shifted according to address
        if (address[i - 1]) begin
          get_mask = get_mask << (2**(i-1));
        end else begin
          get_mask = get_mask;
        end
      end
    end
  endfunction

  enum logic [1:0] {
    StateIdle,
    StateGet,
    StatePut
  } state_q, state_d;

  logic [AddrWidth-1:0] pending_address_d;
  logic [8:0] pending_len_d;
  logic [2:0] pending_size_d;
  logic [IdWidth-1:0] id_q, id_d;

  // Track whether the last handled transaction is read or write to ensure fairness.
  logic last_req_write_q, last_req_write_d;

  wire handle_write = host_aw_valid && (!host_ar_valid || !last_req_write_q);
  wire handle_read = host_ar_valid && (!host_aw_valid || last_req_write_q);

  always_comb begin
    device_a_valid = 1'b0;
    device_a = 'x;

    host_ar_ready = 1'b0;
    host_aw_ready = 1'b0;
    host_w_ready = 1'b0;

    state_d = state_q;
    id_d = id_q;
    pending_address_d = pending_address_q;
    pending_len_d = pending_len_q;
    pending_size_d = pending_size_q;
    last_req_write_d = last_req_write_q;

    unique case (state_q)
      StateIdle: begin
        if (handle_write) begin
          host_aw_ready = 1'b1;
          id_d = host_aw.id;
          // Force the alignment (AXI doesn't mandate it)
          pending_address_d = host_aw.addr >> host_aw.size << host_aw.size;
          pending_len_d = host_aw.len + 1;
          pending_size_d = host_aw.size;
          state_d = StatePut;
          last_req_write_d = 1'b1;
        end else if (handle_read) begin
          host_ar_ready = 1'b1;
          id_d = host_ar.id;
          pending_address_d = host_ar.addr >> host_ar.size << host_ar.size;
          pending_len_d = host_ar.len + 1;
          pending_size_d = host_ar.size;
          state_d = StateGet;
          last_req_write_d = 1'b0;
        end
      end

      StateGet: begin
        device_a_valid   = 1'b1;
        device_a.opcode  = Get;
        device_a.param   = 0;
        device_a.size    = fragment_size;
        // The source here don't have to be unique, because we have a fifo converter.
        device_a.source  = {id_q, remainder_len == 0};
        device_a.address = pending_address_q;
        device_a.mask    = get_mask(pending_address_q, fragment_size);
        device_a.corrupt = 1'b0;
        device_a.data   = 'x;

        if (device_a_ready) begin
          if (remainder_len != 0) begin
            pending_address_d = remainder_address;
            pending_len_d = remainder_len;
          end else begin
            state_d = StateIdle;
          end
        end
      end

      StatePut: begin
        host_w_ready  = device_a_ready;
        device_a_valid   = host_w_valid;
        device_a.opcode  = PutPartialData;
        device_a.param   = 0;
        device_a.size    = fragment_size;
        device_a.source  = {id_q, remainder_len == 0};
        device_a.address = pending_address_q;
        device_a.mask    = host_w.strb;
        device_a.corrupt = 1'b0;
        device_a.data    = host_w.data;

        if (device_a_valid && device_a_ready && device_a_last) begin
          if (remainder_len != 0) begin
            pending_address_d = remainder_address;
            pending_len_d = remainder_len;
          end else begin
            state_d = StateIdle;
          end
        end
      end
      default:;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni)
    if (!rst_ni) begin
      state_q <= StateIdle;
      id_q <= 'x;
      pending_address_q <= '0;
      pending_len_q <= '0;
      pending_size_q <= '0;
      last_req_write_q <= 1'b0;
    end
    else begin
      state_q <= state_d;
      id_q <= id_d;
      pending_address_q <= pending_address_d;
      pending_len_q <= pending_len_d;
      pending_size_q <= pending_size_d;
      last_req_write_q <= last_req_write_d;
    end

  // #endregion
  ///////////////////////

  ///////////////////////
  // #region D Channel //

  always_comb begin
    device_d_ready = 1'b0;

    host_r_valid = 1'b0;
    host_r = 'x;
    host_b_valid = 1'b0;
    host_b = 'x;

    if (device_d_valid) begin
      if (device_d.opcode == AccessAckData) begin
        device_d_ready = host_r_ready;
        host_r_valid = 1'b1;
        host_r.id    = device_d.source[IdWidth:1];
        host_r.data  = device_d.data;
        host_r.resp  = device_d.denied ? RESP_SLVERR : RESP_OKAY;
        host_r.last  = device_d_last && device_d.source[0];
      end else begin
        if (device_d.source[0]) begin
          device_d_ready = host_b_ready;
          host_b_valid = 1'b1;
          host_b.id    = device_d.source[IdWidth:1];
          host_b.resp  = device_d.denied ? RESP_SLVERR : RESP_OKAY;
        end else begin
          device_d_ready = 1'b1;
        end
      end
    end
  end

  // #endregion
  ///////////////////////

endmodule
