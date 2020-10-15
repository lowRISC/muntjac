module mul_unit import muntjac_pkg::*; (
    // Clock and reset
    input  logic        clk_i,
    input  logic        rst_ni,

    input  logic [63:0] operand_a_i,
    input  logic [63:0] operand_b_i,
    input  mul_op_e     req_op_i,
    input  logic        req_word_i,
    input  logic        req_valid_i,
    output logic        req_ready_o,

    output logic        resp_valid_o,
    output logic [63:0] resp_value_o
);

  // This multiplication unit will split operation into 17x17 multiplication, so that the 18x18
  // or 18x25 DSP units on FPGA can be utilised. We only use 1 of those DSP units.
  //
  // MULW -> 4 cycles
  // MUL  -> 11 cycles
  // MULH -> 17 cycles

  // FSM States
  enum logic {
    IDLE,
    BUSY
  } state = IDLE, state_d;

  logic [1:0] a_idx, a_idx_d;
  logic [1:0] b_idx, b_idx_d;

  // Latched input operands. We latch them instead of using the combinational input for timing
  // proposes.
  logic [64:0] op_a, op_a_d;
  logic [64:0] op_b, op_b_d;
  logic op_l, op_l_d;
  logic op_32, op_32_d;

  // Multadd
  logic [36:0] accum, accum_d;
  logic [16:0] mac_op_a;
  logic [16:0] mac_op_b;
  logic [36:0] mac_prod;

  // Output signals
  logic o_valid_d;
  logic [63:0] o_value_d;

  // Perform multiplication
  assign req_ready_o = state == IDLE;
  always_comb begin
    unique case (a_idx)
      0: mac_op_a = op_a[15:0];
      1: mac_op_a = op_a[31:16];
      2: mac_op_a = op_a[47:32];
      3: mac_op_a = op_a[64:48];
      default: mac_op_a = 'x;
    endcase
    unique case (b_idx)
      0: mac_op_b = op_b[15:0];
      1: mac_op_b = op_b[31:16];
      2: mac_op_b = op_b[47:32];
      3: mac_op_b = op_b[64:48];
      default: mac_op_b = 'x;
    endcase
    mac_prod = signed'(accum) + signed'(mac_op_a) * signed'(mac_op_b);
  end

  always_comb begin
    op_a_d = op_a;
    op_b_d = op_b;
    op_l_d = op_l;
    op_32_d = op_32;
    state_d = state;
    accum_d = 'x;
    o_value_d = 'x;
    o_valid_d = 1'b0;

    a_idx_d = 'x;
    b_idx_d = 'x;

    unique case (state)
      IDLE: begin
        if (req_valid_i) begin
          op_a_d = {req_op_i != MUL_OP_MULHU ? operand_a_i[63] : 1'b0, operand_a_i};
          op_b_d = {req_op_i[1] != 1'b1 ? operand_b_i[63] : 1'b0, operand_b_i};
          op_l_d = req_op_i == MUL_OP_MUL;
          op_32_d = req_word_i;

          o_value_d = 'x;
          accum_d = '0;
          a_idx_d = 0;
          b_idx_d = 0;
          state_d = BUSY;
        end
      end
      BUSY: begin
        accum_d = mac_prod;
        o_value_d = resp_value_o;

        unique case ({a_idx, b_idx})
          {2'd0, 2'd0}: begin
            o_value_d[15:0] = mac_prod[15:0];
            accum_d = signed'(mac_prod[36:16]);
            a_idx_d = 1;
            b_idx_d = 0;
          end

          {2'd1, 2'd0}: begin
            a_idx_d = 0;
            b_idx_d = 1;
          end
          {2'd0, 2'd1}: begin
            o_value_d[63:16] = signed'(mac_prod[15:0]);
            if (op_32) begin
              o_valid_d = 1'b1;
              accum_d = 'x;
              state_d = IDLE;
            end else begin
              accum_d = signed'(mac_prod[36:16]);
              a_idx_d = 0;
              b_idx_d = 2;
            end
          end

          {2'd0, 2'd2}: begin
            a_idx_d = 1;
            b_idx_d = 1;
          end
          {2'd1, 2'd1}: begin
            a_idx_d = 2;
            b_idx_d = 0;
          end
          {2'd2, 2'd0}: begin
            o_value_d[47:32] = mac_prod[15:0];
            accum_d = signed'(mac_prod[36:16]);
            a_idx_d = 3;
            b_idx_d = 0;
          end

          {2'd3, 2'd0}: begin
            a_idx_d = 2;
            b_idx_d = 1;
          end
          {2'd2, 2'd1}: begin
            a_idx_d = 1;
            b_idx_d = 2;
          end
          {2'd1, 2'd2}: begin
            a_idx_d = 0;
            b_idx_d = 3;
          end
          {2'd0, 2'd3}: begin
            o_value_d[63:48] = mac_prod[15:0];
            if (op_l) begin
              o_valid_d = 1'b1;
              accum_d = 'x;
              state_d = IDLE;
            end else begin
              accum_d = signed'(mac_prod[36:16]);
              a_idx_d = 1;
              b_idx_d = 3;
            end
          end

          {2'd1, 2'd3}: begin
            a_idx_d = 2;
            b_idx_d = 2;
          end
          {2'd2, 2'd2}: begin
            a_idx_d = 3;
            b_idx_d = 1;
          end
          {2'd3, 2'd1}: begin
            o_value_d[15:0] = mac_prod[15:0];
            accum_d = signed'(mac_prod[36:16]);
            a_idx_d = 3;
            b_idx_d = 2;
          end

          {2'd3, 2'd2}: begin
            a_idx_d = 2;
            b_idx_d = 3;
          end
          {2'd2, 2'd3}: begin
            o_value_d[31:16] = mac_prod[15:0];
            accum_d = signed'(mac_prod[36:16]);
            a_idx_d = 3;
            b_idx_d = 3;
          end

          {2'd3, 2'd3}: begin
            o_value_d[63:32] = mac_prod;
            o_valid_d = 1'b1;
            accum_d = 'x;
            state_d = IDLE;
          end
        endcase
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state <= IDLE;
      op_a <= 'x;
      op_b <= 'x;
      op_l <= 1'bx;
      op_32 <= 1'bx;
      accum <= '0;
      resp_valid_o <= 1'b0;
      resp_value_o <= 'x;
      a_idx <= 'x;
      b_idx <= 'x;
    end else begin
      state <= state_d;
      op_a <= op_a_d;
      op_b <= op_b_d;
      op_l <= op_l_d;
      op_32 <= op_32_d;
      accum <= accum_d;
      resp_valid_o <= o_valid_d;
      resp_value_o <= o_value_d;
      a_idx <= a_idx_d;
      b_idx <= b_idx_d;
    end
  end

endmodule

module div_unit import muntjac_pkg::*; (
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

  logic [63:0] a, a_d;
  logic [63:0] b, b_d;
  logic        quo_neg, quo_neg_d;
  logic        rem_neg, rem_neg_d;
  logic        o_32, o_32_d;
  // Number of iterations left. If this is zero, it means we are idle waiting for input.
  logic [6:0]  iter, iter_d;
  logic [63:0] quo, quo_d;
  logic [63:0] rem, rem_d;
  logic o_valid_d;
  logic [63:0] o_value_d;

  assign req_ready_o = iter == 0;
  always_comb begin
    // Shifters
    iter_d = iter - 1;
    quo_d = {quo, 1'b0};
    rem_d = {rem, a[0]};
    a_d = a[63:1];

    // Keep those values constant
    b_d = b;
    quo_neg_d = quo_neg;
    rem_neg_d = rem_neg;
    o_32_d = o_32;
    use_rem_d = use_rem_q;

    // Output are invalid unless otherwise specified
    o_valid_d = 1'b0;
    o_value_d = 'x;

    if (iter == 0) begin
      if (req_valid_i) begin
        iter_d = req_word_i ? 32 : 64;
        quo_d = 0;
        rem_d = 0;
        a_d = a_rev;
        b_d = b_mag;
        // If we are dividing some by zero, the circuit will produce '1 as the quotient.
        // So we should not negate it, even if a_sign is negative.
        quo_neg_d = a_sign ^ b_sign && b_mag != 0;
        rem_neg_d = a_sign;
        o_32_d = req_word_i;
        use_rem_d = use_rem_i;
      end else begin
        iter_d = 0;
      end
    end else begin
      if (rem_d >= b) begin
        rem_d = rem_d - b;
        quo_d[0] = 1'b1;
      end

      if (iter_d == 0) begin
        o_valid_d = 1'b1;
        if (use_rem_q) begin
          o_value_d = rem_neg ? -rem_d : rem_d;
        end else begin
          o_value_d = quo_neg ? -quo_d : quo_d;
        end
        if (o_32) begin
          o_value_d = signed'(o_value_d[31:0]);
        end
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      iter <= 0;
      quo <= 'x;
      rem <= 'x;
      a <= 'x;
      b <= 'x;
      quo_neg <= 'x;
      rem_neg <= 'x;
      o_32 <= 'x;
      use_rem_q <= 'x;
      resp_valid_o <= 1'b0;
      resp_value_o <= 'x;
    end else begin
      iter <= iter_d;
      quo <= quo_d;
      rem <= rem_d;
      a <= a_d;
      b <= b_d;
      quo_neg <= quo_neg_d;
      rem_neg <= rem_neg_d;
      o_32 <= o_32_d;
      use_rem_q <= use_rem_d;
      resp_valid_o <= o_valid_d;
      resp_value_o <= o_value_d;
    end
  end

endmodule
