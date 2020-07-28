import riscv::*;

// This module decompresses RV64C 16-bit instruction to the full
// RV64 instruction.
// 16-bit D-extension instructions are currently expanded to illegal instruction.
module decode_compressed (
    input  logic [15:0] compressed,
    output logic [31:0] decompressed
);

    //
    // Helper functions to reconstruct 32-bit instruction
    //

    function logic [31:0] construct_r_type (
        input  [6:0]  funct7,
        input  [4:0]  rs2,
        input  [4:0]  rs1,
        input  [2:0]  funct3,
        input  [4:0]  rd,
        input  [6:0]  opcode
    );
        construct_r_type = {funct7, rs2, rs1, funct3, rd, opcode};
    endfunction

    function logic [31:0] construct_i_type (
        input  [11:0] imm,
        input  [4:0]  rs1,
        input  [2:0]  funct3,
        input  [4:0]  rd,
        input  [6:0]  opcode
    );
        construct_i_type = {imm, rs1, funct3, rd, opcode};
    endfunction

    function logic [31:0] construct_s_type (
        input  [11:0] imm,
        input  [4:0]  rs2,
        input  [4:0]  rs1,
        input  [2:0]  funct3,
        input  [6:0]  opcode
    );
        construct_s_type = {imm[11:5], rs2, rs1, funct3, imm[4:0], opcode};
    endfunction

    function logic [31:0] construct_b_type (
        input  [12:0] imm,
        input  [4:0]  rs2,
        input  [4:0]  rs1,
        input  [2:0]  funct3,
        input  [6:0]  opcode
    );
        construct_b_type = {imm[12], imm[10:5], rs2, rs1, funct3, imm[4:1], imm[11], opcode};
    endfunction

    function logic [31:0] construct_u_type (
        input  [19:0] imm,
        input  [4:0]  rd,
        input  [6:0]  opcode
    );
        construct_u_type = {imm, rd, opcode};
    endfunction

    function logic [31:0] construct_j_type (
        input  [20:0] imm,
        input  [4:0]  rd,
        input  [6:0]  opcode
    );
        construct_j_type = {imm[20], imm[10:1], imm[11], imm[19:12], rd, opcode};
    endfunction

    //
    // De-structure fields
    //

    wire [2:0] c_funct3 = compressed[15:13];
    wire [4:0] c_rd     = compressed[11:7];
    wire [4:0] c_rs1    = c_rd;
    wire [4:0] c_rs2    = compressed[6:2];
    wire [4:0] c_rds    = {2'b01, compressed[4:2]};
    wire [4:0] c_rs1s   = {2'b01, compressed[9:7]};
    wire [4:0] c_rs2s   = c_rds;

    wire [11:0] ci_imm  = signed'({compressed[12], compressed[6:2]});
    wire [11:0] ci_lwsp_imm = {compressed[3:2], compressed[12], compressed[6:4], 2'b0};
    wire [11:0] ci_ldsp_imm = {compressed[4:2], compressed[12], compressed[6:5], 3'b0};
    wire [11:0] ci_addi16sp_imm = signed'({
        compressed[12], compressed[4:3], compressed[5], compressed[2], compressed[6], 4'b0
    });
    wire [11:0] css_swsp_imm = {compressed[8:7], compressed[12:9], 2'b0};
    wire [11:0] css_sdsp_imm = {compressed[9:7], compressed[12:10], 3'b0};

    wire [11:0] ciw_imm = {
        compressed[10:7], compressed[12:11], compressed[5], compressed[6], 2'b0
    };
    wire [11:0] cl_lw_imm = {compressed[5], compressed[12:10], compressed[6], 2'b0};
    wire [11:0] cl_ld_imm = {compressed[6:5], compressed[12:10], 3'b0};
    wire [11:0] cs_sw_imm = cl_lw_imm;
    wire [11:0] cs_sd_imm = cl_ld_imm;

    wire [12:0] cb_imm = signed'({
        compressed[12], compressed[6:5], compressed[2], compressed[11:10], compressed[4:3], 1'b0
    });
    wire [20:0] cj_imm = signed'({
        compressed[12], compressed[8], compressed[10:9], compressed[6], compressed[7],
        compressed[2], compressed[11], compressed[5:3], 1'b0
    });

    always_comb begin
        // By default decompress to an invalid instruction.
        decompressed = '0;
        unique case (compressed[1:0])
            2'b00: begin
                unique case (c_funct3)
                    3'b000: begin
                        if (ciw_imm == 0) begin
                            // Illegal instruction
                        end
                        else begin
                            // C.ADDI4SPN
                            // translate to addi rd', x2, ciw_imm
                            decompressed = construct_i_type (
                                .imm (ciw_imm),
                                .rs1 (2),
                                .funct3 (3'b000),
                                .rd (c_rds),
                                .opcode (OPCODE_OP_IMM)
                            );
                        end
                    end
                    3'b001: begin
                        // C.FLD
                        // translate to fld rd', rs1', cl_ld_imm
                        // D-extension not supported
                    end
                    3'b010: begin
                        // C.LW
                        // translate to lw rd', rs1', cl_lw_imm
                        decompressed = construct_i_type (
                            .imm (cl_lw_imm),
                            .rs1 (c_rs1s),
                            .funct3 (3'b010),
                            .rd (c_rds),
                            .opcode (OPCODE_LOAD)
                        );
                    end
                    3'b011: begin
                        // C.LD
                        // translate to ld rd', rs1', cl_ld_imm
                        decompressed = construct_i_type (
                            .imm (cl_ld_imm),
                            .rs1 (c_rs1s),
                            .funct3 (3'b011),
                            .rd (c_rds),
                            .opcode (OPCODE_LOAD)
                        );
                    end
                    3'b100: begin
                        // Reserved
                    end
                    3'b101: begin
                        // C.FSD
                        // translate to fsd rs2', rs1', cs_sd_imm
                        // D-extension not supported
                    end
                    3'b110: begin
                        // C.SW
                        // translate to sw rs2', rs1', cs_sw_imm
                        decompressed = construct_s_type (
                            .imm (cs_sw_imm),
                            .rs2 (c_rs2s),
                            .rs1 (c_rs1s),
                            .funct3 (3'b010),
                            .opcode (OPCODE_STORE)
                        );
                    end
                    3'b111: begin
                        // C.SD
                        // translate to sd rs2', rs1', cs_sd_imm
                        decompressed = construct_s_type (
                            .imm (cs_sd_imm),
                            .rs2 (c_rs2s),
                            .rs1 (c_rs1s),
                            .funct3 (3'b011),
                            .opcode (OPCODE_STORE)
                        );
                    end
                endcase
            end
            2'b01: begin
                unique case (c_funct3)
                    3'b000: begin
                        // rd = x0 is HINT
                        // r0 = 0 is C.NOP
                        // C.ADDI
                        // translate to addi rd, rd, ci_imm
                        decompressed = construct_i_type (
                            .imm (ci_imm),
                            .rs1 (c_rd),
                            .funct3 (3'b000),
                            .rd (c_rd),
                            .opcode (OPCODE_OP_IMM)
                        );
                    end
                    3'b001: begin
                        if (c_rd == 0) begin
                            // Reserved
                        end
                        else begin
                            // C.ADDIW
                            // translate to addiw rd, rd, ci_imm
                            decompressed = construct_i_type (
                                .imm (ci_imm),
                                .rs1 (c_rd),
                                .funct3 (3'b000),
                                .rd (c_rd),
                                .opcode (OPCODE_OP_IMM_32)
                            );
                        end
                    end
                    3'b010: begin
                        // rd = x0 is HINT
                        // C.LI
                        // translate to addi rd, x0, ci_imm
                        decompressed = construct_i_type (
                            .imm (ci_imm),
                            .rs1 (0),
                            .funct3 (3'b000),
                            .rd (c_rd),
                            .opcode (OPCODE_OP_IMM)
                        );
                    end
                    3'b011: begin
                        if (c_rd == 2) begin
                            if (ci_addi16sp_imm == 0) begin
                                // Reserved
                            end
                            else begin
                                // C.ADDI16SP
                                // translate to addi x2, x2, ci_addi16sp_imm
                                decompressed = construct_i_type (
                                    .imm (ci_addi16sp_imm),
                                    .rs1 (2),
                                    .funct3 (3'b000),
                                    .rd (2),
                                    .opcode (OPCODE_OP_IMM)
                                );
                            end
                        end
                        else begin
                            // rd = x0 is HINT
                            // C.LUI
                            // translate to lui rd, ci_imm
                            decompressed = construct_u_type (
                                .imm (signed'(ci_imm)),
                                .rd (c_rd),
                                .opcode (OPCODE_LUI)
                            );
                        end
                    end
                    3'b100: begin
                        unique case (compressed[11:10])
                            2'b00: begin
                                // imm = 0 is HINT
                                // C.SRLI
                                // translate to srli rs1', rs1', imm
                                decompressed = construct_i_type (
                                    .imm ({6'b000000, ci_imm[5:0]}),
                                    .rs1 (c_rs1s),
                                    .funct3 (3'b101),
                                    .rd (c_rs1s),
                                    .opcode (OPCODE_OP_IMM)
                                );
                            end
                            2'b01: begin
                                // imm = 0 is HINT
                                // C.SRAI
                                // translate to srai rs1', rs1', imm
                                decompressed = construct_i_type (
                                    .imm ({6'b010000, ci_imm[5:0]}),
                                    .rs1 (c_rs1s),
                                    .funct3 (3'b101),
                                    .rd (c_rs1s),
                                    .opcode (OPCODE_OP_IMM)
                                );
                            end
                            2'b10: begin
                                // C.ANDI
                                // translate to andi rs1', rs1', imm
                                decompressed = construct_i_type (
                                    .imm (ci_imm),
                                    .rs1 (c_rs1s),
                                    .funct3 (3'b111),
                                    .rd (c_rs1s),
                                    .opcode (OPCODE_OP_IMM)
                                );
                            end
                            2'b11: begin
                                if (compressed[12] == 0) begin
                                    // C.SUB
                                    // C.XOR
                                    // C.OR
                                    // C.AND
                                    // translates to [OP] rs1', rs1', rs2'
                                    logic [6:0] funct7;
                                    logic [2:0] funct3;
                                    unique case (compressed[6:5])
                                        2'b00: begin
                                            funct7 = 7'b0100000;
                                            funct3 = 3'b000;
                                        end
                                        2'b01: begin
                                            funct7 = 7'b0000000;
                                            funct3 = 3'b100;
                                        end
                                        2'b10: begin
                                            funct7 = 7'b0000000;
                                            funct3 = 3'b110;
                                        end
                                        2'b11: begin
                                            funct7 = 7'b0000000;
                                            funct3 = 3'b111;
                                        end
                                    endcase
                                    decompressed = construct_r_type (
                                        .funct7 (funct7),
                                        .rs2 (c_rs2s),
                                        .rs1 (c_rs1s),
                                        .funct3 (funct3),
                                        .rd (c_rs1s),
                                        .opcode (OPCODE_OP)
                                    );
                                end
                                else begin
                                    if (compressed[6] == 0) begin
                                        // C.SUBW
                                        // C.ADDW
                                        decompressed = construct_r_type (
                                            .funct7 ({1'b0, !compressed[5], 5'b00000}),
                                            .rs2 (c_rs2s),
                                            .rs1 (c_rs1s),
                                            .funct3 (3'b000),
                                            .rd (c_rs1s),
                                            .opcode (OPCODE_OP_32)
                                        );
                                    end
                                    else begin
                                        // Illegal
                                    end
                                end
                            end
                        endcase
                    end
                    3'b101: begin
                        // C.J
                        // translate to jal x0, cj_imm
                        decompressed = construct_j_type (
                            .imm (cj_imm),
                            .rd (0),
                            .opcode (OPCODE_JAL)
                        );
                    end
                    3'b110: begin
                        // C.BEQZ
                        // translate to beq rs1', x0, cb_imm
                        decompressed = construct_b_type (
                            .imm (cb_imm),
                            .rs2 (0),
                            .rs1 (c_rs1s),
                            .funct3 (3'b000),
                            .opcode (OPCODE_BRANCH)
                        );
                    end
                    3'b111: begin
                        // C.BNEZ
                        // translate to bne rs1', x0, cb_imm
                        decompressed = construct_b_type (
                            .imm (cb_imm),
                            .rs2 (0),
                            .rs1 (c_rs1s),
                            .funct3 (3'b001),
                            .opcode (OPCODE_BRANCH)
                        );
                    end
                endcase
            end
            2'b10: begin
                unique case (c_funct3)
                    3'b000: begin
                        // imm = 0 is HINT
                        // rd = 0 is HINT
                        // C.SLLI
                        // translates to slli rd, rd, ci_imm
                        decompressed = construct_i_type (
                            .imm ({6'b000000, ci_imm[5:0]}),
                            .rs1 (c_rd),
                            .funct3 (3'b001),
                            .rd (c_rd),
                            .opcode (OPCODE_OP_IMM)
                        );
                    end
                    3'b001: begin
                        // C.FLDSP
                        // translate to fld rd, x2, ci_ldsp_imm
                    end
                    3'b010: begin
                        if (c_rd == 0) begin
                            // Reserved
                        end
                        else begin
                            // C.LWSP
                            // translate to lw rd, x2, ci_lwsp_imm
                            decompressed = construct_i_type (
                                .imm (ci_lwsp_imm),
                                .rs1 (2),
                                .funct3 (3'b010),
                                .rd (c_rd),
                                .opcode (OPCODE_LOAD)
                            );
                        end
                    end
                    3'b011: begin
                        if (c_rd == 0) begin
                            // Reserved
                        end
                        else begin
                            // C.LDSP
                            // translate to ld rd, x2, ci_ldsp_imm
                            decompressed = construct_i_type (
                                .imm (ci_ldsp_imm),
                                .rs1 (2),
                                .funct3 (3'b011),
                                .rd (c_rd),
                                .opcode (OPCODE_LOAD)
                            );
                        end
                    end
                    3'b100: begin
                        if (compressed[12] == 0) begin
                            if (c_rs2 == 0) begin
                                if (c_rs1 == 0) begin
                                    // Reserved
                                end
                                else begin
                                    // C.JR
                                    // translate to jalr x0, rs1, 0
                                    decompressed = construct_i_type (
                                        .imm (0),
                                        .rs1 (c_rs1),
                                        .funct3 (3'b000),
                                        .rd (0),
                                        .opcode (OPCODE_JALR)
                                    );
                                end
                            end
                            else begin
                                // rd = 0 is HINT
                                // C.MV
                                // translate to add rd, x0, rs2
                                decompressed = construct_r_type (
                                    .funct7 (7'b0000000),
                                    .rs2 (c_rs2),
                                    .rs1 (0),
                                    .funct3 (3'b000),
                                    .rd (c_rd),
                                    .opcode (OPCODE_OP)
                                );
                            end
                        end
                        else begin
                            if (c_rs1 == 0) begin
                                // C.EBREAK
                                decompressed = 32'b000000000001_00000_000_00000_1110011;
                            end
                            else if (c_rs2 == 0) begin
                                // C.JALR
                                // translate to jalr x1, rs1, 0
                                decompressed = construct_i_type (
                                    .imm (0),
                                    .rs1 (c_rs1),
                                    .funct3 (3'b000),
                                    .rd (1),
                                    .opcode (OPCODE_JALR)
                                );
                            end
                            else begin
                                // rd = 0 is HINT
                                // C.ADD
                                // translate to add rd, rd, rs2
                                decompressed = construct_r_type (
                                    .funct7 (7'b0000000),
                                    .rs2 (c_rs2),
                                    .rs1 (c_rd),
                                    .funct3 (3'b000),
                                    .rd (c_rd),
                                    .opcode (OPCODE_OP)
                                );
                            end
                        end
                    end
                    3'b101: begin
                        // C.FSDSP
                        // translate to fsd rs2, x2, css_sdsp_imm
                    end
                    3'b110: begin
                        // C.SWSP
                        // translate to sw rs2, x2, css_swsp_imm
                        decompressed = construct_s_type (
                            .imm (css_swsp_imm),
                            .rs1 (2),
                            .rs2 (c_rs2),
                            .funct3 (3'b010),
                            .opcode (OPCODE_STORE)
                        );
                    end
                    3'b111: begin
                        // C.SDSP
                        // translate to sd rs2, x2, css_sdsp_imm
                        decompressed = construct_s_type (
                            .imm (css_sdsp_imm),
                            .rs1 (2),
                            .rs2 (c_rs2),
                            .funct3 (3'b011),
                            .opcode (OPCODE_STORE)
                        );
                    end
                endcase
            end
            // Otherwise this is a 32-bit instruction.
            default: decompressed = 'x;
        endcase
    end

endmodule
