import cpu_common::*;

module comparator (
    input  logic [63:0] operand_a,
    input  logic [63:0] operand_b,
    input  condition_code_e op,

    // Value of operand_a - operand_b
    input  logic [63:0] difference_i,

    output logic            result
);

    logic eq_flag;
    logic lt_flag;
    logic ltu_flag;
    logic result_before_neg;

    always_comb begin
        // We don't check for difference_i == 0 because it will make the critical path longer.
        eq_flag = operand_a == operand_b;

        // If MSBs are the same, look at the sign of the result is sufficient.
        // Otherwise the one with MSB 0 is larger.
        lt_flag = operand_a[63] == operand_b[63] ? difference_i[63] : operand_a[63];

        // If MSBs are the same, look at the sign of the result is sufficient.
        // Otherwise the one with MSB 1 is larger.
        ltu_flag = operand_a[63] == operand_b[63] ? difference_i[63] : operand_b[63];

        unique case ({op[2:1], 1'b0})
           CC_FALSE: result_before_neg = 1'b0;
           CC_EQ: result_before_neg = eq_flag;
           CC_LT: result_before_neg = lt_flag;
           CC_LTU: result_before_neg = ltu_flag;
           default: result = 'x;
        endcase

        result = op[0] ? !result_before_neg : result_before_neg;
    end

endmodule

module shifter (
    input  logic [63:0] operand_a_i,
    input  logic [63:0] operand_b_i,
    input  logic        left_i,
    input  logic        arithmetic_i,
    // If set, this is a word op (32-bit)
    input  logic        word_i,
    output logic [63:0] result_o
);

    // Determine the operand to be fed into the right shifter.
    logic [63:0] shift_operand;
    logic shift_fill_bit;
    logic [5:0] shamt;
    logic [64:0] shift_operand_ext;
    logic [63:0] shift_result;

    always_comb begin
        shift_operand = 'x;
        unique casez ({word_i, left_i})
            2'b00: begin
                shift_operand = operand_a_i;
            end
            2'b10: begin
                shift_operand = {operand_a_i[31:0], 32'dx};
            end
            2'b?1: begin
                for (int i = 0; i < 64; i++) shift_operand[i] = operand_a_i[63 - i];
            end
            default:;
        endcase

        shift_fill_bit = arithmetic && shift_operand[63];
        shamt = word_i ? {1'b0, operand_b_i[4:0]} : operand_b_i[5:0];

        shift_operand_ext = {shift_fill_bit, shift_operand};
        shift_result = signed'(shift_operand_ext) >>> shamt;

        result_o = 'x;
        unique casez ({word_i, left_i})
            2'b00: begin
                result_o = shift_result;
            end
            2'b10: begin
                result_o = {32'dx, shift_result[63:32]};
            end
            2'b?1: begin
                for (int i = 0; i < 64; i++) result_o[i] = shift_result[63 - i];
            end
            default:;
        endcase
    end

endmodule

module alu (
    input  op_t             operator,
    input  decoded_instr_t  decoded_instr,
    input                   is_32,
    input  [63:0]       operand_a,
    input  [63:0]       operand_b,

    // operand_a + operand_b
    input  logic [63:0] sum_i,
    // operand_a - operand_b
    input  logic [63:0] difference_i,
    input  logic            compare_result_i,
    output logic [63:0] result
);

    /* Shifter */

    logic [63:0] shift_result;
    shifter shifter(
        .operand_a_i  (operand_a),
        .operand_b_i  (operand_b),
        .left_i       (decoded_instr.shifter_left),
        .arithmetic_i (decoded_instr.shifter_arithmetic),
        .word_i       (is_32),
        .result_o     (shift_result)
    );

    /* Result Multiplexer */

    logic [63:0] alu_result;
    always_comb begin
        unique case (operator)
            ADD: alu_result = sum_i;
            SUB: alu_result = difference_i;
            L_AND: alu_result = operand_a & operand_b;
            L_OR: alu_result = operand_a | operand_b;
            L_XOR: alu_result = operand_a ^ operand_b;
            SHIFT: alu_result = shift_result;
            SCC: alu_result = compare_result_i;
            default: alu_result = 'x;
        endcase

        result = is_32 ? {{32{alu_result[31]}}, alu_result[31:0]} : alu_result;
    end

endmodule
