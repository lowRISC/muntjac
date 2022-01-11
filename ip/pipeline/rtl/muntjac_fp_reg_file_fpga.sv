// Register file.
module muntjac_fp_reg_file import muntjac_pkg::*; # (
    parameter int unsigned DataWidth = 64,
    parameter rv64f_e      RV64F = RV64FMem
) (
    // Clock and reset
    input  logic                 clk_i,
    input  logic                 rst_ni,

    // Read port A
    input  logic [4:0]           raddr_a_i,
    output logic [DataWidth-1:0] rdata_a_o,

    // Read port B
    input  logic [4:0]           raddr_b_i,
    output logic [DataWidth-1:0] rdata_b_o,

    // Read port C
    input  logic [4:0]           raddr_c_i,
    output logic [DataWidth-1:0] rdata_c_o,

    // Write port
    input  logic [4:0]           waddr_a_i,
    input  logic [DataWidth-1:0] wdata_a_i,
    input  logic                 we_a_i
);

  bit [DataWidth-1:0] registers [0:31];

  // Read ports
  assign rdata_b_o = registers[raddr_b_i];

  if (RV64F == RV64FFull) begin
    assign rdata_a_o = registers[raddr_a_i];
    assign rdata_c_o = registers[raddr_c_i];
  end else begin
    // We only need all 3 read ports in full FPU mode.
    // In RV64FMem mode, only frs2 will be used (by LOAD_FP).
    // All 1 is NaN.
    assign rdata_a_o = '1;
    assign rdata_c_o = '1;
  end

  // Write port
  always_ff @(posedge clk_i) begin
    if (we_a_i)
      registers[waddr_a_i] <= wdata_a_i;
  end

endmodule
