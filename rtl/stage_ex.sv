import cpu_common::*;

// This module contains the EX stage (combinational) of the pipeline.
module stage_ex #(
    parameter XLEN = 64
) (
    input  logic            clk,
    input  logic            rstn,

    input  decoded_instr_t  i_decoded,
    input  [XLEN-1:0]       i_rs1,
    input  logic [XLEN-1:0] i_rs2,

    output logic            o_value_valid,
    output logic [XLEN-1:0] o_val,
    output logic [XLEN-1:0] o_val2,
    output logic [XLEN-1:0] o_npc,
    output logic            o_mispredict
);

    logic [XLEN-1:0] npc;
    assign npc = i_decoded.pc + (i_decoded.exception.mtval[1:0] == 2'b11 ? 4 : 2);

    // Adder for PC and immediate.
    // Only used for AUIPC, JAL and branch
    logic [XLEN-1:0] pc_imm_adder;
    assign pc_imm_adder = i_decoded.pc + i_decoded.immediate;

    // Adder.
    // This is the core component of the EX stage.
    // It is used for add, sub and compare.
    wire [XLEN-1:0] operand_b = i_decoded.use_imm ? i_decoded.immediate : i_rs2;
    logic [XLEN-1:0] adder_result;
    adder #(
        .XLEN (XLEN)
    ) adder (
        .subtract (i_decoded.adder_subtract),
        .operand_a (i_rs1),
        .operand_b (operand_b),
        .result (adder_result)
    );

    // Comparator. Used in BRANCH, SLT, and SLTU
    logic lt_flag;
    logic ltu_flag;
    logic compare_result;
    comparator #(
        .XLEN (XLEN)
    ) comparator (
        .operand_a    (i_rs1),
        .operand_b    (operand_b),
        .op           (i_decoded.comparator_op),
        .adder_result,
        .lt_flag,
        .ltu_flag,
        .result       (compare_result)
    );

    // ALU
    logic [XLEN-1:0] alu_result;
    alu #(
        .XLEN (XLEN)
    ) alu (
        .operator      (i_decoded.op),
        .decoded_instr (i_decoded),
        .is_32         (i_decoded.is_32),
        .operand_a     (i_rs1),
        .operand_b     (operand_b),
        .adder_result  (adder_result),
        .lt_flag,
        .ltu_flag,
        .result        (alu_result)
    );

    always_comb begin
        o_value_valid = 1'b0;
        o_val = 'x;
        o_val2 = 'x;
        o_npc = npc;

        // The default case is that we think there is no branching happening. So if a branch is predicted to be taken,
        // then it is a misprediction and we need flushing.
        o_mispredict = i_decoded.prediction.taken;

        if (!i_decoded.exception.valid) begin
            case (i_decoded.op_type)
                ALU: begin
                    o_value_valid = 1'b1;
                    o_val = alu_result;
                end
                AUIPC: begin
                    o_value_valid = 1'b1;
                    o_val = pc_imm_adder;
                end
                // As EX1 can be speculatively executed,
                // Therefore we will compute next PC and misprediction information, but
                // instruction misalign and misprediction handling are all done in stage 2.
                BRANCH: begin
                    o_value_valid = 1'b1;
                    o_val = npc;
                    o_mispredict = compare_result != i_decoded.prediction.taken;
                    o_npc = compare_result ? pc_imm_adder : npc;
                end
                JALR: begin
                    o_value_valid = 1'b1;
                    o_val = npc;
                    o_mispredict = 1'b1;
                    o_npc = {adder_result[XLEN-1:1], 1'b0};
                end
                CSR: begin
                    o_val = i_decoded.csr.imm ? {{(XLEN-5){1'b0}}, i_decoded.rs1} : i_rs1;
                end
                MEM: begin
                    o_val = adder_result;
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
