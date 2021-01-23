`include "tl_util.svh"

// An adpater that converts an TL-UL interface to a BRAM interface.
module tl_adapter_bram #(
  parameter  int unsigned AddrWidth   = 56,
  parameter  int unsigned DataWidth   = 64,
  parameter  int unsigned SourceWidth = 1,
  parameter  int unsigned SinkWidth   = 1,
  parameter  int unsigned BramAddrWidth    = 12,
  localparam int unsigned DataWidthInBytes = DataWidth / 8
) (
  input  logic                        clk_i,
  input  logic                        rst_ni,

  `TL_DECLARE_DEVICE_PORT(DataWidth, AddrWidth, SourceWidth, SinkWidth, host),

  output logic                        bram_en_o,
  output logic                        bram_we_o,
  output logic [BramAddrWidth-1:0]    bram_addr_o,
  output logic [DataWidthInBytes-1:0] bram_wmask_o,
  output logic [DataWidth-1:0]        bram_wdata_o,
  input  logic [DataWidth-1:0]        bram_rdata_i
);

  import tl_pkg::*;

  localparam NonBurstSize = $clog2(DataWidthInBytes);

  // Static checks of interface matching
  if (NonBurstSize + BramAddrWidth > AddrWidth) $fatal(1, "AddrWidth mismatch");

  `TL_DECLARE(DataWidth, AddrWidth, SourceWidth, SinkWidth, host);
  `TL_BIND_DEVICE_PORT(host, host);

  /////////////////////
  // Unused channels //
  /////////////////////

  // We don't use channel B.
  assign host_b_valid = 1'b0;
  assign host_b       = 'x;

  // We don't use channel C and E
  assign host_c_ready = 1'b1;
  assign host_e_ready = 1'b1;

  /////////////////////////////////
  // Request channel handshaking //
  /////////////////////////////////

  // We can perform an op if no pending data is to be received on D channel.
  assign host_a_ready = !host_d_valid || host_d_ready;
  wire   do_op        = host_a_valid && host_a_ready;

  ////////////////////////
  // Connection to BRAM //
  ////////////////////////

  assign bram_en_o    = do_op;
  assign bram_we_o    = host_a.opcode != Get;
  assign bram_addr_o  = host_a.address[NonBurstSize +: BramAddrWidth];
  assign bram_wmask_o = host_a.mask;
  assign bram_wdata_o = host_a.data;

  /////////////////////////////
  // Response handling logic //
  /////////////////////////////

  assign host_d.param   = 0;
  assign host_d.sink    = 'x;
  assign host_d.denied  = 1'b0;
  assign host_d.corrupt = 1'b0;
  assign host_d.data    = bram_rdata_i;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      host_d_valid  <= 1'b0;
      host_d.opcode <= tl_d_op_e'('x);
      host_d.size   <= 'x;
      host_d.source <= 'x;
    end
    else begin
      if (host_d_valid && host_d_ready) begin
        host_d_valid <= 1'b0;
      end
      if (do_op) begin
        host_d_valid  <= 1'b1;
        host_d.opcode <= host_a.opcode != Get ? AccessAck : AccessAckData;
        host_d.size   <= host_a.size;
        host_d.source <= host_a.source;
      end
    end
  end

endmodule
