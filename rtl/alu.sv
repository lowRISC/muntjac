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
    input  logic [63:0] operand_a,
    input  logic [63:0] operand_b,
    input  logic            left,
    input  logic            arithmetic,
    input  logic            is_32,
    output logic [63:0] result
);

    logic [63:0] operand_a_rev;
    for (genvar i=0;i<64;i++)
        assign operand_a_rev[i] = operand_a[63-i];

    // Determine the operand to be fed into the right shifter.
    logic [63:0] shift_operand;
    logic shift_fill_bit;

    always_comb begin
        unique case ({arithmetic, left})
            2'b10: begin
                shift_operand = is_32 ? {{32{operand_a[31]}}, operand_a[31:0]} : operand_a;
                shift_fill_bit = shift_operand[63];
            end
            2'b00: begin
                shift_operand = is_32 ? {32'b0, operand_a[31:0]} : operand_a;
                shift_fill_bit = 1'b0;
            end
            2'b01: begin
                // Left shift can be done by reversing, logical right shift and reverse again.
                // We use the stream operator here for easy reversing.
                shift_operand = operand_a_rev;
                shift_fill_bit = 1'b0;
            end
            default: begin
                shift_operand = 'x;
                shift_fill_bit = 1'bx;
            end
        endcase
    end

    // Determine max shift amount through is_32.
    logic [5:0] shamt;
    assign shamt = is_32 ? {1'b0, operand_b[4:0]} : operand_b[5:0];

    // Add the fill bit to the left and perform shift.
    logic [64:0] shift_operand_ext;
    logic [63:0] shift_result;
    assign shift_operand_ext = {shift_fill_bit, shift_operand};
    assign shift_result = $signed(shift_operand_ext) >>> shamt;

    logic [63:0] shift_result_rev;
    for (genvar i=0;i<64;i++)
        assign shift_result_rev[i] = shift_result[63-i];

    // Reverse left-shift results back if needed.
    assign result = left ? shift_result_rev : shift_result;

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
        operand_a,
        operand_b,
        decoded_instr.shifter_left,
        decoded_instr.shifter_arithmetic,
        is_32,
        shift_result
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
