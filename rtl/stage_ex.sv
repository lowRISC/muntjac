import cpu_common::*;

// This module contains the EX stage (combinational) of the pipeline.
module stage_ex (
    input  logic            clk,
    input  logic            rstn,

    input  decoded_instr_t  i_decoded,
    input  [63:0]       i_rs1,
    input  logic [63:0] i_rs2,

    output logic            o_value_valid,
    output logic [63:0] o_val,
    output logic [63:0] o_val2,
    output logic [63:0] o_npc
);

    logic [63:0] npc;
    assign npc = i_decoded.pc + (i_decoded.exception.mtval[1:0] == 2'b11 ? 4 : 2);

    wire [63:0] operand_b = i_decoded.use_imm ? i_decoded.immediate : i_rs2;

    // Adder.
    // This is the core component of the EX stage.
    // It is used for ADD, LOAD, STORE, AUIPC, JAL, JALR, BRANCH
    logic [63:0] sum;
    assign sum = (i_decoded.adder.use_pc ? i_decoded.pc : i_rs1) + (i_decoded.adder.use_imm ? i_decoded.immediate : i_rs2);

    // Subtractor.
    // It is used for SUB, BRANCH, SLT, SLTU
    logic [63:0] difference;
    assign difference = i_rs1 - operand_b;

    // Comparator. Used in BRANCH, SLT, and SLTU
    logic compare_result;
    comparator comparator (
        .operand_a_i  (i_rs1),
        .operand_b_i  (operand_b),
        .condition_i  (i_decoded.condition),
        .difference_i (difference),
        .result_o     (compare_result)
    );

    // ALU
    logic [63:0] alu_result;
    alu alu (
        .operator      (i_decoded.op),
        .decoded_instr (i_decoded),
        .is_32         (i_decoded.is_32),
        .operand_a     (i_rs1),
        .operand_b     (operand_b),
        .sum_i         (sum),
        .difference_i  (difference),
        .compare_result_i (compare_result),
        .result           (alu_result)
    );

    always_comb begin
        o_value_valid = 1'b0;
        o_val = 'x;
        o_val2 = 'x;
        o_npc = npc;

        if (!i_decoded.exception.valid) begin
            case (i_decoded.op_type)
                ALU: begin
                    o_value_valid = 1'b1;
                    o_val = alu_result;
                end
                // As EX1 can be speculatively executed,
                // Therefore we will compute next PC and misprediction information, but
                // Misprediction handling are all done in stage 2.
                BRANCH: begin
                    o_value_valid = 1'b1;
                    o_val = npc;
                    o_npc = compare_result ? {sum[63:1], 1'b0} : npc;
                end
                CSR: begin
                    o_val = i_decoded.csr.imm ? {{(64-5){1'b0}}, i_decoded.rs1} : i_rs1;
                end
                MEM: begin
                    o_val = sum;
                    // For store and AMO
                    o_val2 = i_rs2;
                end
                MUL: begin
                    // Leave this to stage 2.
                    o_val = i_rs1;
                    o_val2 = i_rs2;
                end
                DIV: begin
                    // Leave this to stage 2.
                    o_val = i_rs1;
                    o_val2 = i_rs2;
                end
                ERET: begin
                    // Leave this to stage 2.
                end
                SFENCE_VMA: begin
                    // Leave this to stage 2.
                    o_val = i_rs1;
                    o_val2 = i_rs2;
                end
            endcase
        end
    end

endmodule
