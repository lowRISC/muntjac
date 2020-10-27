module muntjac_mul import muntjac_pkg::*; (
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
  typedef enum logic {
    StateIdle,
    StateProgress
  } state_e;

  state_e state_q = StateIdle, state_d;

  logic [1:0] a_idx_q, a_idx_d;
  logic [1:0] b_idx_q, b_idx_d;

  // Latched input operands. We latch them instead of using the combinational input for timing
  // proposes.
  logic [64:0] a_q, a_d;
  logic [64:0] b_q, b_d;
  logic op_low_q, op_low_d;
  logic op_word_q, op_word_d;

  // Multadd
  logic [34:0] accum, accum_d;
  logic [16:0] mac_op_a;
  logic [16:0] mac_op_b;
  logic [34:0] mac_prod;

  // Output signals
  logic o_valid_d;
  logic [63:0] o_value_d;

  // Perform multiplication
  assign req_ready_o = state_q == StateIdle;
  always_comb begin
    unique case (a_idx_q)
      0: mac_op_a = {1'b0, a_q[15:0]};
      1: mac_op_a = {1'b0, a_q[31:16]};
      2: mac_op_a = {1'b0, a_q[47:32]};
      3: mac_op_a = a_q[64:48];
      default: mac_op_a = 'x;
    endcase
    unique case (b_idx_q)
      0: mac_op_b = {1'b0, b_q[15:0]};
      1: mac_op_b = {1'b0, b_q[31:16]};
      2: mac_op_b = {1'b0, b_q[47:32]};
      3: mac_op_b = b_q[64:48];
      default: mac_op_b = 'x;
    endcase
    mac_prod = signed'(accum) + signed'(mac_op_a) * signed'(mac_op_b);
  end

  always_comb begin
    a_d = a_q;
    b_d = b_q;
    op_low_d = op_low_q;
    op_word_d = op_word_q;
    state_d = state_q;
    accum_d = 'x;
    o_value_d = 'x;
    o_valid_d = 1'b0;

    a_idx_d = 'x;
    b_idx_d = 'x;

    unique case (state_q)
      StateIdle: begin
        if (req_valid_i) begin
          a_d = {req_op_i != MUL_OP_MULHU ? operand_a_i[63] : 1'b0, operand_a_i};
          b_d = {req_op_i[1] == 1'b0 ? operand_b_i[63] : 1'b0, operand_b_i};
          op_low_d = req_op_i == MUL_OP_MUL;
          op_word_d = req_word_i;

          o_value_d = 'x;
          accum_d = '0;
          a_idx_d = 0;
          b_idx_d = 0;
          state_d = StateProgress;
        end
      end
      StateProgress: begin
        accum_d = mac_prod;
        o_value_d = resp_value_o;

        unique case ({a_idx_q, b_idx_q})
          {2'd0, 2'd0}: begin
            o_value_d[15:0] = mac_prod[15:0];
            accum_d = signed'(mac_prod[34:16]);
            a_idx_d = 1;
            b_idx_d = 0;
          end

          {2'd1, 2'd0}: begin
            a_idx_d = 0;
            b_idx_d = 1;
          end
          {2'd0, 2'd1}: begin
            o_value_d[63:16] = signed'(mac_prod[15:0]);
            if (op_word_q) begin
              o_valid_d = 1'b1;
              accum_d = 'x;
              state_d = StateIdle;
            end else begin
              accum_d = signed'(mac_prod[34:16]);
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
            accum_d = signed'(mac_prod[34:16]);
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
            if (op_low_q) begin
              o_valid_d = 1'b1;
              accum_d = 'x;
              state_d = StateIdle;
            end else begin
              accum_d = signed'(mac_prod[34:16]);
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
            accum_d = signed'(mac_prod[34:16]);
            a_idx_d = 3;
            b_idx_d = 2;
          end

          {2'd3, 2'd2}: begin
            a_idx_d = 2;
            b_idx_d = 3;
          end
          {2'd2, 2'd3}: begin
            o_value_d[31:16] = mac_prod[15:0];
            accum_d = signed'(mac_prod[34:16]);
            a_idx_d = 3;
            b_idx_d = 3;
          end

          {2'd3, 2'd3}: begin
            o_value_d[63:32] = mac_prod[31:0];
            o_valid_d = 1'b1;
            accum_d = 'x;
            state_d = StateIdle;
          end
        endcase
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= StateIdle;
      a_q <= 'x;
      b_q <= 'x;
      op_low_q <= 1'bx;
      op_word_q <= 1'bx;
      accum <= '0;
      resp_valid_o <= 1'b0;
      resp_value_o <= 'x;
      a_idx_q <= 'x;
      b_idx_q <= 'x;
    end else begin
      state_q <= state_d;
      a_q <= a_d;
      b_q <= b_d;
      op_low_q <= op_low_d;
      op_word_q <= op_word_d;
      accum <= accum_d;
      resp_valid_o <= o_valid_d;
      resp_value_o <= o_value_d;
      a_idx_q <= a_idx_d;
      b_idx_q <= b_idx_d;
    end
  end

endmodule
