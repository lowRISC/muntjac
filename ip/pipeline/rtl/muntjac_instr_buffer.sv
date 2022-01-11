module muntjac_instr_buffer import muntjac_pkg::*; (
  input  logic           clk_i,
  input  logic           rst_ni,

  output logic                 in_ready_o,
  input  logic           [1:0] in_valid_i,
  input  fetched_instr_t [1:0] in_instr_i,

  input  logic           out_ready_i,
  output logic           out_valid_o,
  output fetched_instr_t out_instr_o
);

  logic buffer_valid_q, buffer_valid_d;
  fetched_instr_t buffer_q, buffer_d;

  always_comb begin
    buffer_valid_d = buffer_valid_q;
    buffer_d = buffer_q;

    in_ready_o = 1'b0;

    if (buffer_valid_q && !(in_valid_i[0] && in_instr_i[0].if_reason[0])) begin
      out_valid_o = 1'b1;
      out_instr_o = buffer_q;

      if (out_ready_i) begin
        buffer_valid_d = 1'b0;
        if (!in_valid_i[1]) begin
          in_ready_o = 1'b1;
          buffer_valid_d = in_valid_i[0];
          buffer_d = in_instr_i[0];
        end
      end
    end else begin
      out_valid_o = in_valid_i[0];
      out_instr_o = in_instr_i[0];

      if (out_ready_i) begin
        in_ready_o = 1'b1;
        buffer_valid_d = in_valid_i[1];
        buffer_d = in_instr_i[1];
      end else if (!in_valid_i[1]) begin
        in_ready_o = 1'b1;
        buffer_valid_d = in_valid_i[0];
        buffer_d = in_instr_i[0];
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      buffer_valid_q <= 1'b0;
      buffer_q <= 'x;
    end else begin
      buffer_valid_q <= buffer_valid_d;
      buffer_q <= buffer_d;
    end
  end

endmodule
