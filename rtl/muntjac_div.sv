module muntjac_div import muntjac_pkg::*; (
  // Clock and reset
  input  logic        clk_i,
  input  logic        rst_ni,

  input  logic [63:0] operand_a_i,
  input  logic [63:0] operand_b_i,
  input  div_op_e     req_op_i,
  input  logic        req_word_i,
  input  logic        req_valid_i,
  output logic        req_ready_o,

  output logic [63:0] resp_value_o,
  output logic        resp_valid_o
);

  typedef enum logic {
    StateIdle,
    StateProgress
  } state_e;

  state_e state_q = StateIdle, state_d;

  logic a_sign;
  logic b_sign;
  logic [63:0] a_mag;
  logic [63:0] b_mag;
  logic [63:0] a_rev;

  logic use_rem_d, use_rem_q;

  wire i_unsigned = req_op_i[0];
  wire use_rem_i = req_op_i[1];

  // Prepare the input by extracting sign, mangitude and deal with sign-extension
  always_comb begin
    if (req_word_i == 1'b0) begin
      if (i_unsigned == 1'b0 && operand_a_i[63]) begin
        a_sign = 1'b1;
        a_mag = -operand_a_i;
      end else begin
        a_sign = 1'b0;
        a_mag = operand_a_i;
      end

      if (i_unsigned == 1'b0 && operand_b_i[63]) begin
        b_sign = 1'b1;
        b_mag = -operand_b_i;
      end else begin
        b_sign = 1'b0;
        b_mag = operand_b_i;
      end

      for (int i = 0; i < 64; i++) a_rev[i] = a_mag[63 - i];
    end else begin
      if (i_unsigned == 1'b0 && operand_a_i[31]) begin
        a_sign = 1'b1;
        a_mag = -signed'(operand_a_i[31:0]);
      end else begin
        a_sign = 1'b0;
        a_mag = operand_a_i[31:0];
      end

      if (i_unsigned == 1'b0 && operand_b_i[31]) begin
        b_sign = 1'b1;
        b_mag = -signed'(operand_b_i[31:0]);
      end else begin
        b_sign = 1'b0;
        b_mag = operand_b_i[31:0];
      end

      a_rev[63:32] = 0;
      for (int i = 0; i < 32; i++) a_rev[i] = a_mag[31 - i];
    end
  end

  logic [63:0] a_q, a_d;
  logic [63:0] b_q, b_d;
  logic        quo_neg_q, quo_neg_d;
  logic        rem_neg_q, rem_neg_d;
  logic        word_q, word_d;
  logic [5:0]  iter_q, iter_d;
  logic [63:0] quo_q, quo_d;
  logic [63:0] rem_q, rem_d;
  logic o_valid_d;
  logic [63:0] o_value_d;

  assign req_ready_o = state_q == StateIdle;

  always_comb begin
    state_d = state_q;

    // Shifters
    iter_d = iter_q;
    quo_d = {quo_q, 1'b0};
    rem_d = {rem_q, a_q[0]};
    a_d = a_q[63:1];

    // Keep those values constant
    b_d = b_q;
    quo_neg_d = quo_neg_q;
    rem_neg_d = rem_neg_q;
    word_d = word_q;
    use_rem_d = use_rem_q;

    // Output are invalid unless otherwise specified
    o_valid_d = 1'b0;
    o_value_d = 'x;

    unique case (state_q)
      StateIdle: begin
        if (req_valid_i) begin
          state_d = StateProgress;
          iter_d = req_word_i ? 31 : 63;
          quo_d = 0;
          rem_d = 0;
          a_d = a_rev;
          b_d = b_mag;
          // If we are dividing some by zero, the circuit will produce '1 as the quotient.
          // So we should not negate it, even if a_sign is negative.
          quo_neg_d = a_sign ^ b_sign && b_mag != 0;
          rem_neg_d = a_sign;
          word_d = req_word_i;
          use_rem_d = use_rem_i;
        end
      end
      StateProgress: begin
        iter_d = iter_q - 1;

        if (rem_d >= b_q) begin
          rem_d = rem_d - b_q;
          quo_d[0] = 1'b1;
        end

        if (iter_q == 0) begin
          state_d = StateIdle;
          o_valid_d = 1'b1;
          if (use_rem_q) begin
            o_value_d = rem_neg_q ? -rem_d : rem_d;
          end else begin
            o_value_d = quo_neg_q ? -quo_d : quo_d;
          end
          if (word_q) begin
            o_value_d = signed'(o_value_d[31:0]);
          end
        end
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= StateIdle;
      iter_q <= 0;
      quo_q <= 'x;
      rem_q <= 'x;
      a_q <= 'x;
      b_q <= 'x;
      quo_neg_q <= 'x;
      rem_neg_q <= 'x;
      word_q <= 'x;
      use_rem_q <= 'x;
      resp_valid_o <= 1'b0;
      resp_value_o <= 'x;
    end else begin
      state_q <= state_d;
      iter_q <= iter_d;
      quo_q <= quo_d;
      rem_q <= rem_d;
      a_q <= a_d;
      b_q <= b_d;
      quo_neg_q <= quo_neg_d;
      rem_neg_q <= rem_neg_d;
      word_q <= word_d;
      use_rem_q <= use_rem_d;
      resp_valid_o <= o_valid_d;
      resp_value_o <= o_value_d;
    end
  end

endmodule
