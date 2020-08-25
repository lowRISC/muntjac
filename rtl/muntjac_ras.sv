module muntjac_ras #(
    parameter int unsigned AddrLen  = 64,
    parameter int unsigned NumEntry = 8
) (
    input  logic               clk_i,
    input  logic               rst_ni,

    output logic               peek_valid_o,
    output logic [AddrLen-1:0] peek_addr_o,
    input  logic               pop_i,

    input  logic               push_i,
    input  logic [AddrLen-1:0] push_addr_i
);

  localparam EntryLen = $clog2(NumEntry);

  wire do_push     =  push_i && !(pop_i && peek_valid_o);
  wire do_pop      = !push_i &&  (pop_i && peek_valid_o);
  wire do_push_pop =  push_i &&  (pop_i && peek_valid_o);

  // Implement the RAS stack as shift registers.
  logic               stack_valid [NumEntry+1:0];
  logic [AddrLen-1:0] stack_addr  [NumEntry+1:0];

  for (genvar i = 1; i <= NumEntry; i += 1) begin
    logic               entry_valid_d;
    logic [AddrLen-1:0] entry_addr_d;

    always_comb begin
      unique case (1'b1)
        do_push: begin
          entry_valid_d = stack_valid[i - 1];
          entry_addr_d  = stack_addr [i - 1];
        end
        do_pop: begin
          entry_valid_d = stack_valid[i + 1];
          entry_addr_d  = stack_addr [i + 1];
        end
        default: begin
          entry_valid_d = stack_valid[i];
          entry_addr_d  = stack_addr [i];
        end
      endcase
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        stack_valid[i] <= 1'b0;
        stack_addr [i] <= 'x;
      end else begin
        stack_valid[i] <= entry_valid_d;
        stack_addr [i] <= entry_addr_d;
      end
    end
  end

  //////////////////////
  // Top of the stack //
  //////////////////////

  assign peek_valid_o = stack_valid[1];
  assign peek_addr_o  = stack_addr [1];

  assign stack_valid[0] = 1'b1;
  assign stack_addr [0] = push_addr_i;

  /////////////////////////
  // Bottom of the stack //
  /////////////////////////

  assign stack_valid[NumEntry+1] = 1'b0;
  assign stack_addr [NumEntry+1] = 'x;

endmodule
