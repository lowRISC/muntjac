module muntjac_ras #(
    parameter int unsigned AddrLen  = 64,
    parameter int unsigned NumEntry = 8
) (
    input  logic               clk_i,
    input  logic               rst_ni,

    output logic               peek_valid_o,
    output logic [AddrLen-1:0] peek_addr_o,
    input  logic               pop_spec_i,
    input  logic               pop_i,

    input  logic               push_spec_i,
    input  logic               push_i,
    input  logic [AddrLen-1:0] push_addr_i,

    // Revert speculative state
    input  logic               revert_i
);

  localparam EntryWidth = $clog2(NumEntry);

  logic [AddrLen-1:0] mem [0:NumEntry-1];
  logic [EntryWidth-1:0] ptr_spec_q, ptr_spec_d;
  logic [EntryWidth-1:0] ptr_q, ptr_d;

  // Ensure memory has value so we don't produce X
  initial begin
    for (int i = 0; i < NumEntry; i++) begin
      mem[i] = '0;
    end
  end

  // Combinational read
  assign peek_valid_o = 1'b1;
  assign peek_addr_o = mem[ptr_spec_q];

  always_comb begin
    unique case ({push_spec_i, pop_spec_i})
      2'b10: ptr_spec_d = ptr_q + 1;
      2'b01: ptr_spec_d = ptr_q - 1;
      default: ptr_spec_d = ptr_spec_q;
    endcase

    unique case ({push_i, pop_i})
      2'b10: ptr_d = ptr_q + 1;
      2'b01: ptr_d = ptr_q - 1;
      default: ptr_d = ptr_q;
    endcase

    if (revert_i) ptr_spec_d = ptr_d;
  end

  // Stack update
  always @(posedge clk_i) begin
    if (rst_ni && push_spec_i) begin
      mem[ptr_spec_d] <= push_addr_i;
    end
  end

  // State update
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      ptr_spec_q <= '0;
      ptr_q <= '0;
    end else begin
      ptr_spec_q <= ptr_spec_d;
      ptr_q <= ptr_d;
    end
  end

endmodule
