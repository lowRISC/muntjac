import cpu_common::*;

module adder #(
    parameter XLEN = 64
) (
    input  logic subtract,
    input  logic [XLEN-1:0] operand_a,
    input  logic [XLEN-1:0] operand_b,
    output logic [XLEN-1:0] result
);

    logic discard;
    assign {result, discard} = {operand_a, 1'b1} + {subtract ? ~operand_b : operand_b, subtract};

endmodule

module comparator #(
    parameter XLEN = 64
) (
    input  logic [XLEN-1:0] operand_a,
    input  logic [XLEN-1:0] operand_b,
    input  comparator_op_t  op,
    input  logic [XLEN-1:0] adder_result,
    output logic            lt_flag,
    output logic            ltu_flag,
    output logic            result
);

    logic eq_flag;

    always_comb begin
        // We don't check for adder_result == 0 because it will make the critical path longer.
        eq_flag = operand_a == operand_b;

        // If MSBs are the same, look at the sign of the result is sufficient.
        // Otherwise the one with MSB 0 is larger.
        lt_flag = operand_a[XLEN-1] == operand_b[XLEN-1] ? adder_result[XLEN-1] : operand_a[XLEN-1];

        // If MSBs are the same, look at the sign of the result is sufficient.
        // Otherwise the one with MSB 1 is larger.
        ltu_flag = operand_a[XLEN-1] == operand_b[XLEN-1] ? adder_result[XLEN-1] : operand_b[XLEN-1];

        unique case (op)
           EQ: result = eq_flag;
           NE: result = !eq_flag;
           LT: result = lt_flag;
           GE: result = !lt_flag;
           LTU: result = ltu_flag;
           GEU: result = !ltu_flag;
           JUMP: result = 1'b1;
           default: result = 'x;
        endcase
    end

endmodule

module shifter #(
    parameter XLEN = 64
) (
    input  logic [XLEN-1:0] operand_a,
    input  logic [XLEN-1:0] operand_b,
    input  logic            left,
    input  logic            arithmetic,
    input  logic            is_32,
    output logic [XLEN-1:0] result
);

    logic [XLEN-1:0] operand_a_rev;
    for (genvar i=0;i<XLEN;i++)
        assign operand_a_rev[i] = operand_a[XLEN-1-i];

    // Determine the operand to be fed into the right shifter.
    logic [XLEN-1:0] shift_operand;
    logic shift_fill_bit;

    always_comb begin
        unique case ({arithmetic, left})
            2'b10: begin
                shift_operand = (XLEN == 64 && is_32) ? {{32{operand_a[31]}}, operand_a[31:0]} : operand_a;
                shift_fill_bit = shift_operand[XLEN-1];
            end
            2'b00: begin
                shift_operand = (XLEN == 64 && is_32) ? {32'b0, operand_a[31:0]} : operand_a;
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
    localparam LOG_WIDTH = $clog2(XLEN);
    logic [LOG_WIDTH-1:0] shamt;
    assign shamt = (XLEN == 64 && is_32) ? {1'b0, operand_b[4:0]} : operand_b[LOG_WIDTH-1:0];

    // Add the fill bit to the left and perform shift.
    logic [XLEN:0] shift_operand_ext;
    logic [XLEN-1:0] shift_result;
    assign shift_operand_ext = {shift_fill_bit, shift_operand};
    assign shift_result = $signed(shift_operand_ext) >>> shamt;

    logic [XLEN-1:0] shift_result_rev;
    for (genvar i=0;i<XLEN;i++)
        assign shift_result_rev[i] = shift_result[XLEN-1-i];

    // Reverse left-shift results back if needed.
    assign result = left ? shift_result_rev : shift_result;

endmodule

module alu #(
    parameter XLEN = 64
) (
    input  op_t             operator,
    input  decoded_instr_t  decoded_instr,
    input                   is_32,
    input  [XLEN-1:0]       operand_a,
    input  [XLEN-1:0]       operand_b,
    input  logic [XLEN-1:0] adder_result,
    input  logic            lt_flag,
    input  logic            ltu_flag,
    output logic [XLEN-1:0] result
);

    /* Shifter */

    logic [XLEN-1:0] shift_result;
    shifter # (
        .XLEN (XLEN)
    ) shifter (
        operand_a,
        operand_b,
        decoded_instr.shifter_left,
        decoded_instr.shifter_arithmetic,
        is_32,
        shift_result
    );

    /* Result Multiplexer */

    logic [XLEN-1:0] alu_result;
    always_comb begin
        unique case (operator)
            ADDSUB: alu_result = adder_result;
            L_AND: alu_result = operand_a & operand_b;
            L_OR: alu_result = operand_a | operand_b;
            L_XOR: alu_result = operand_a ^ operand_b;
            SHIFT: alu_result = shift_result;
            SLT: alu_result = lt_flag;
            SLTU: alu_result = ltu_flag;
            default: alu_result = 'x;
        endcase

        result = (XLEN == 64 && is_32) ? {{32{alu_result[31]}}, alu_result[31:0]} : alu_result;
    end

endmodule
