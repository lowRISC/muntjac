`include "tl_util.svh"

module tl_burst_tracker import tl_pkg::*; import prim_util_pkg::*; #(
  parameter  int unsigned AddrWidth = 56,
  parameter  int unsigned DataWidth = 64,
  parameter  int unsigned SourceWidth = 1,
  parameter  int unsigned SinkWidth = 1,

  parameter  int unsigned MaxSize       = 6,

  localparam int unsigned DataWidthInBytes = DataWidth / 8,
  localparam int unsigned NonBurstSize = $clog2(DataWidthInBytes),
  localparam int unsigned MaxBurstLen = 2 ** (MaxSize - NonBurstSize),
  localparam int unsigned BurstLenWidth = vbits(MaxBurstLen)
) (
  input  logic clk_i,
  input  logic rst_ni,

  `TL_DECLARE_TAP_PORT(DataWidth, AddrWidth, SourceWidth, SinkWidth, link),

  // Total number of beats in the current burst.
  output logic [BurstLenWidth-1:0] req_len_o,
  output logic [BurstLenWidth-1:0] rel_len_o,
  output logic [BurstLenWidth-1:0] gnt_len_o,

  // Index of the current beat in the current burst.
  output logic [BurstLenWidth-1:0] req_idx_o,
  output logic [BurstLenWidth-1:0] rel_idx_o,
  output logic [BurstLenWidth-1:0] gnt_idx_o,

  // Number of beats left after the current one.
  output logic [BurstLenWidth-1:0] req_left_o,
  output logic [BurstLenWidth-1:0] rel_left_o,
  output logic [BurstLenWidth-1:0] gnt_left_o,

  // If the current beat is the first beat in the burst.
  output logic req_first_o,
  output logic rel_first_o,
  output logic gnt_first_o,

  // If the current beat is the last beat in the burst.
  output logic req_last_o,
  output logic rel_last_o,
  output logic gnt_last_o
);

  `TL_DECLARE(DataWidth, AddrWidth, SourceWidth, SinkWidth, link);
  `TL_BIND_TAP_PORT(link, link);

  function automatic logic [BurstLenWidth-1:0] burst_len(input logic [`TL_SIZE_WIDTH-1:0] size);
    if (size <= NonBurstSize) begin
      return 0;
    end else begin
      return (1 << (size - NonBurstSize)) - 1;
    end
  endfunction

  /////////////////////
  // Request channel //
  /////////////////////

  // Number of beats left in the burst (excluding the current beat).
  //
  // Note that for the first beat of a transaction, we can't have the burst length already stored
  // here, so we instead put '1 here, and AND it with req_len_o to get the actual req_left_o.
  // The merit of this design is that, for non-first beat, req_left_q & req_len_o is identical to
  // req_left_q, so we can use the same expression for both first and non-first beat.
  //
  // When a handshake happens, we simply decrease the value by 1. For non-last beat, this will yield
  // the current req_left_o for the next beat, and for last beat, this will yield '1, which fit
  // nicely with the next transaction!
  //
  // The current beat index is merely a (req_len_o - req_left_o) which is identical to req_len_o &~ req_left_o
  // which is further identical to req_len_o & req_left_q!
  logic [BurstLenWidth-1:0] req_left_q;

  assign req_len_o   = link_a.opcode < 4 ? burst_len(link_a.size) : 0;
  assign req_idx_o   = req_len_o &~ req_left_q;
  assign req_left_o  = req_len_o & req_left_q;
  assign req_first_o = &req_left_q;
  assign req_last_o  = req_left_o == 0;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      req_left_q <= '1;
    end else begin
      if (link_a_valid && link_a_ready) begin
        req_left_q <= req_left_o - 1;
      end
    end
  end

  /////////////////////////////////
  // Release channel arbitration //
  /////////////////////////////////

  logic [BurstLenWidth-1:0] rel_left_q;

  assign rel_len_o   = link_c.opcode[0] ? burst_len(link_c.size) : 0;
  assign rel_idx_o   = rel_len_o &~ rel_left_q;
  assign rel_left_o  = rel_len_o & rel_left_q;
  assign rel_first_o = &rel_left_q;
  assign rel_last_o  = rel_left_o == 0;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      rel_left_q <= '1;
    end else begin
      if (link_c_valid && link_c_ready) begin
        rel_left_q <= rel_left_o - 1;
      end
    end
  end

  ///////////////////
  // Grant channel //
  ///////////////////

  logic [BurstLenWidth-1:0] gnt_left_q;

  assign gnt_len_o   = link_d.opcode[0] ? burst_len(link_d.size) : 0;
  assign gnt_idx_o   = gnt_len_o &~ gnt_left_q;
  assign gnt_left_o  = gnt_len_o & gnt_left_q;
  assign gnt_first_o = &gnt_left_q;
  assign gnt_last_o  = gnt_left_o == 0;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      gnt_left_q <= '1;
    end else begin
      if (link_d_valid && link_d_ready) begin
        gnt_left_q <= gnt_left_o - 1;
      end
    end
  end

endmodule
