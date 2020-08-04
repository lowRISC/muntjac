import cpu_common::*;
import riscv::*;

module decoder # (
    // Decide the base ISA to use. Note that the decoded immediate length will always be 32 bits.
    parameter XLEN = 64,
    parameter C_EXT = 1'b1
) (
    input  fetched_instr_t fetched_instr,
    output decoded_instr_t decoded_instr,

    // Currently privilege, for decode-stage privilege checking.
    input  prv_t prv,
    // Status for determining if certain operations are allowed.
    input  status_t status,

    output csr_t csr_sel,
    output logic [1:0] csr_op,
    input  logic csr_illegal
);

    // Currently we only support RV32I and RV64I base ISAs.
    initial assert (XLEN == 64 || XLEN == 32);

    //
    // Logics
    //

    // Use the structure to unpack the instruction word.
    logic [31:0] instr_word;

    if (C_EXT) begin
        // C-extension decompression.
        logic [31:0] decompressed;
        decode_compressed decomp (
            .compressed (fetched_instr.instr_word[15:0]),
            .decompressed
        );
        assign instr_word = fetched_instr.instr_word[1:0] == 2'b11 ? fetched_instr.instr_word : decompressed;
    end
    else begin
        assign instr_word = fetched_instr.instr_word;
    end

    wire [6:0] funct7 = instr_word[31:25];
    wire [4:0] rs2 = instr_word[24:20];
    wire [4:0] rs1 = instr_word[19:15];
    wire [2:0] funct3 = instr_word[14:12];
    wire [4:0] rd = instr_word[11:7];
    wire [6:0] opcode = instr_word[6:0];

    wire [31:0] i_imm = signed'(instr_word[31:20]);
    wire [31:0] u_imm = signed'({instr_word[31:12], 12'b0});
    wire [31:0] s_imm = signed'({instr_word[31:25], instr_word[11:7]});
    wire [31:0] b_imm = signed'({instr_word[31], instr_word[7], instr_word[30:25], instr_word[11:8], 1'b0});
    wire [31:0] j_imm = signed'({instr_word[31], instr_word[19:12], instr_word[20], instr_word[30:21], 1'b0});

    logic [31:0] immediate;

    // Wire to CSR privilege checker
    assign csr_sel = csr_t'(instr_word[31:20]);
    assign csr_op = funct3[1] == 1'b1 && rs1 == 0 ? 2'b00 : funct3[1:0];

    always_comb begin
        decoded_instr = decoded_instr_t'('x);
        decoded_instr.op_type = ALU;
        decoded_instr.rs1 = '0;
        decoded_instr.rs2 = '0;
        decoded_instr.rd  = '0;

        decoded_instr.is_32 = 1'b0;
        decoded_instr.adder_subtract = 1'bx;

        decoded_instr.op = op_t'('x);
        decoded_instr.shifter_left = 1'bx;
        decoded_instr.shifter_arithmetic = 1'bx;
        decoded_instr.comparator_op = comparator_op_t'('x);

        // Set exception to be illegal instruction, but do not enable it yet.
        decoded_instr.exception.valid = 1'b0;
        decoded_instr.exception.mcause_interrupt = 1'b0;
        decoded_instr.exception.mcause_code = 4'h2;
        decoded_instr.exception.mtval = fetched_instr.instr_word;

        // Forward these fields.
        decoded_instr.pc = fetched_instr.pc;
        decoded_instr.if_reason = fetched_instr.if_reason;
        decoded_instr.prediction = fetched_instr.prediction;

        case (opcode)
            OPCODE_LOAD: begin
                decoded_instr.op_type = MEM;
                decoded_instr.rs1 = rs1;
                decoded_instr.rd  = rd;

                decoded_instr.mem.op = MEM_LOAD;
                decoded_instr.mem.size = funct3[1:0];
                decoded_instr.mem.zeroext = funct3[2];
                decoded_instr.adder_subtract = 1'b0;

                if (XLEN == 32) begin
                     if (funct3[1:0] == 2'b11 || funct3 == 3'b110) decoded_instr.exception.valid = 1'b1;
                end
                else begin
                    if (funct3 == 3'b111) decoded_instr.exception.valid = 1'b1;
                end
            end

            OPCODE_MISC_MEM: begin
                unique case (funct3)
                    3'b000: begin
                        // Decode FENCE as NOP
                    end
                    3'b001: begin
                        decoded_instr.op_type = FENCE_I;
                    end
                    default: decoded_instr.exception.valid = 1'b1;
                endcase
            end

            OPCODE_OP_IMM: begin
                decoded_instr.rs1 = rs1;
                decoded_instr.rd  = rd;

                unique case (funct3)
                    3'b000: begin
                        decoded_instr.op = ADDSUB;
                        decoded_instr.adder_subtract = 1'b0;
                    end
                    3'b010: begin
                        decoded_instr.op = SLT;
                        decoded_instr.adder_subtract = 1'b1;
                    end
                    3'b011: begin
                        decoded_instr.op = SLTU;
                        decoded_instr.adder_subtract = 1'b1;
                    end
                    3'b100: decoded_instr.op = L_XOR;
                    3'b110: decoded_instr.op = L_OR;
                    3'b111: decoded_instr.op = L_AND;

                    3'b001: begin
                        decoded_instr.op = SHIFT;
                        decoded_instr.shifter_left = 1'b1;
                        decoded_instr.shifter_arithmetic = 1'b0;

                        // Shift is invalid if imm is larger than XLEN.
                        if (funct7[6:1] != 6'b0) decoded_instr.exception.valid = 1'b1;
                        if (XLEN == 32 && funct7[0] != 1'b0) decoded_instr.exception.valid = 1'b1;
                    end

                    3'b101: begin
                        decoded_instr.op = SHIFT;
                        decoded_instr.shifter_left = 1'b0;

                        if (funct7[6:1] == 6'b0) decoded_instr.shifter_arithmetic = 1'b0;
                        else if (funct7[6:1] == 6'b010000) decoded_instr.shifter_arithmetic = 1'b1;
                        // Shift is invalid if imm is larger than XLEN.
                        else decoded_instr.exception.valid = 1'b1;

                        if (XLEN == 32 && funct7[0] != 1'b0) decoded_instr.exception.valid = 1'b1;
                    end
                endcase
            end

            OPCODE_AUIPC: begin
                decoded_instr.op_type = AUIPC;
                decoded_instr.rd      = rd;
            end

            OPCODE_OP_IMM_32: begin
                if (XLEN == 32) decoded_instr.exception.valid = 1'b1;
                else begin
                    decoded_instr.rs1   = rs1;
                    decoded_instr.rd    = rd;
                    decoded_instr.is_32 = 1'b1;

                    unique case (funct3)
                        3'b000: begin
                            decoded_instr.op = ADDSUB;
                            decoded_instr.adder_subtract = 1'b0;
                        end
                        3'b001: begin
                            decoded_instr.op = SHIFT;
                            decoded_instr.shifter_left = 1'b1;
                            decoded_instr.shifter_arithmetic = 1'b0;

                            // Shift is invalid if imm is larger than 32.
                            if (funct7 != 7'b0) decoded_instr.exception.valid = 1'b1;
                        end

                        3'b101: begin
                            decoded_instr.op = SHIFT;
                            decoded_instr.shifter_left = 1'b0;

                            if (funct7 == 7'b0) decoded_instr.shifter_arithmetic = 1'b0;
                            else if (funct7 == 7'b0100000) decoded_instr.shifter_arithmetic = 1'b1;
                            // Shift is invalid if imm is larger than 32.
                            else decoded_instr.exception.valid = 1'b1;
                        end

                        default: decoded_instr.exception.valid = 1'b1;
                    endcase
                end
            end

            OPCODE_STORE: begin
                decoded_instr.op_type = MEM;
                decoded_instr.rs1 = rs1;
                decoded_instr.rs2 = rs2;
                decoded_instr.mem.op = MEM_STORE;
                decoded_instr.mem.size = funct3[1:0];
                decoded_instr.adder_subtract = 1'b0;
                if (funct3[2] == 1'b1) decoded_instr.exception.valid = 1'b1;
                if (XLEN == 32 && funct3[1:0] == 2'b11) decoded_instr.exception.valid = 1'b1;
            end

            OPCODE_AMO: begin
                decoded_instr.op_type = MEM;
                decoded_instr.rs1 = rs1;
                decoded_instr.rs2 = rs2;
                decoded_instr.rd  = rd;
                decoded_instr.mem.size = funct3[1:0];
                decoded_instr.mem.zeroext = 1'b0;
                decoded_instr.mem.op = MEM_AMO;
                decoded_instr.adder_subtract = 1'b0;

                unique case (funct3)
                    3'b010, 3'b011:;
                    default: begin
                        decoded_instr.exception.valid = 1'b1;
                    end
                endcase

                unique case (funct7[6:2])
                    5'b00010: begin
                        decoded_instr.mem.op = MEM_LR;
                        if (rs2 != 0) begin
                            decoded_instr.exception.valid = 1'b1;
                        end
                    end
                    5'b00011: decoded_instr.mem.op = MEM_SC;
                    5'b00001,
                    5'b00000,
                    5'b00100,
                    5'b01100,
                    5'b01000,
                    5'b10000,
                    5'b10100,
                    5'b11000,
                    5'b11100:;
                    default: begin
                        decoded_instr.exception.valid = 1'b1;
                    end
                endcase
            end

            OPCODE_OP: begin
                decoded_instr.rs1 = rs1;
                decoded_instr.rs2 = rs2;
                decoded_instr.rd  = rd;

                unique casez ({funct7, funct3})
                    {7'b0000001, 3'b0??}: begin
                        decoded_instr.op_type = MUL;
                        decoded_instr.mul.op = funct3[1:0];
                    end
                    {7'b0000001, 3'b1??}: begin
                        decoded_instr.op_type = DIV;
                        decoded_instr.div.is_unsigned = funct3[0];
                        decoded_instr.div.rem = funct3[1];
                    end
                    {7'b0000000, 3'b000}: begin
                        decoded_instr.op = ADDSUB;
                        decoded_instr.adder_subtract = 1'b0;
                    end
                    {7'b0100000, 3'b000}: begin
                        decoded_instr.op = ADDSUB;
                        decoded_instr.adder_subtract = 1'b1;
                    end
                    {7'b0000000, 3'b010}: begin
                        decoded_instr.op = SLT;
                        decoded_instr.adder_subtract = 1'b1;
                    end
                    {7'b0000000, 3'b011}: begin
                        decoded_instr.op = SLTU;
                        decoded_instr.adder_subtract = 1'b1;
                    end
                    {7'b0000000, 3'b100}: decoded_instr.op = L_XOR;
                    {7'b0000000, 3'b110}: decoded_instr.op = L_OR;
                    {7'b0000000, 3'b111}: decoded_instr.op = L_AND;
                    {7'b0000000, 3'b001}: begin
                        decoded_instr.op = SHIFT;
                        decoded_instr.shifter_left = 1'b1;
                        decoded_instr.shifter_arithmetic = 1'b0;
                    end
                    {7'b0000000, 3'b101}: begin
                        decoded_instr.op = SHIFT;
                        decoded_instr.shifter_left = 1'b0;
                        decoded_instr.shifter_arithmetic = 1'b0;
                    end
                    {7'b0100000, 3'b101}: begin
                        decoded_instr.op = SHIFT;
                        decoded_instr.shifter_left = 1'b0;
                        decoded_instr.shifter_arithmetic = 1'b1;
                    end
                    default: decoded_instr.exception.valid = 1'b1;
                endcase
            end

            OPCODE_LUI: begin
                decoded_instr.rd = rd;
                decoded_instr.op_type = ALU;
                decoded_instr.op = ADDSUB;
                decoded_instr.adder_subtract = 1'b0;
            end

            OPCODE_OP_32: begin
                if (XLEN == 32) decoded_instr.exception.valid = 1'b1;
                else begin
                    decoded_instr.rs1   = rs1;
                    decoded_instr.rs2   = rs2;
                    decoded_instr.rd    = rd;
                    decoded_instr.is_32 = 1'b1;

                    unique casez ({funct7, funct3})
                        {7'b0000001, 3'b000}: begin
                            decoded_instr.op_type = MUL;
                            decoded_instr.mul.op = 2'b00;
                        end
                        {7'b0000001, 3'b1??}: begin
                            decoded_instr.op_type = DIV;
                            decoded_instr.div.is_unsigned = funct3[0];
                            decoded_instr.div.rem = funct3[1];
                        end
                        {7'b0000000, 3'b000}: begin
                            decoded_instr.op = ADDSUB;
                            decoded_instr.adder_subtract = 1'b0;
                        end
                        {7'b0100000, 3'b000}: begin
                            decoded_instr.op = ADDSUB;
                            decoded_instr.adder_subtract  = 1'b1;
                        end
                        {7'b0000000, 3'b001}: begin
                            decoded_instr.op = SHIFT;
                            decoded_instr.shifter_left = 1'b1;
                            decoded_instr.shifter_arithmetic = 1'b0;
                        end
                        {7'b0000000, 3'b101}: begin
                            decoded_instr.op = SHIFT;
                            decoded_instr.shifter_left = 1'b0;
                            decoded_instr.shifter_arithmetic = 1'b0;
                        end
                        {7'b0100000, 3'b101}: begin
                            decoded_instr.op = SHIFT;
                            decoded_instr.shifter_left = 1'b0;
                            decoded_instr.shifter_arithmetic = 1'b1;
                        end
                        default: decoded_instr.exception.valid = 1'b1;
                    endcase
                end
            end

            OPCODE_BRANCH: begin
                decoded_instr.op_type = BRANCH;
                decoded_instr.rs1     = rs1;
                decoded_instr.rs2     = rs2;
                decoded_instr.adder_subtract = 1'b1;

                unique case (funct3)
                    3'b000: decoded_instr.comparator_op = EQ;
                    3'b001: decoded_instr.comparator_op = NE;
                    3'b100: decoded_instr.comparator_op = LT;
                    3'b101: decoded_instr.comparator_op = GE;
                    3'b110: decoded_instr.comparator_op = LTU;
                    3'b111: decoded_instr.comparator_op = GEU;
                    default: decoded_instr.exception.valid = 1'b1;
                endcase
            end

            OPCODE_JALR: begin
                decoded_instr.op_type = JALR;
                decoded_instr.rs1     = rs1;
                decoded_instr.rd      = rd;
                decoded_instr.adder_subtract = 1'b0;
                if (funct3 != 3'b0) decoded_instr.exception.valid = 1'b1;
            end

            OPCODE_JAL: begin
                decoded_instr.op_type = BRANCH;
                decoded_instr.rd      = rd;
                decoded_instr.comparator_op = JUMP;
            end

            OPCODE_SYSTEM: begin
                if (funct3[1:0] != 2'b00) begin
                    decoded_instr.op_type = CSR;
                    decoded_instr.rs1     = rs1;
                    decoded_instr.rd      = rd;
                    decoded_instr.csr.op  = csr_op;
                    decoded_instr.csr.imm = funct3[2];

                    if (csr_illegal) decoded_instr.exception.valid = 1'b1;
                end
                else begin
                    // PRIV
                    unique casez (instr_word[31:20])
                        12'b0000000_00000: begin
                            // ECALL
                            decoded_instr.exception.mcause_code = {2'b10, prv};
                            decoded_instr.exception.valid = 1'b1;
                            decoded_instr.exception.mtval = 0;
                        end
                        12'b0000000_00001: begin
                            decoded_instr.exception.mcause_code = 4'h3;
                            decoded_instr.exception.valid = 1'b1;
                            decoded_instr.exception.mtval = 0;
                        end
                        12'b0011000_00010: begin
                            decoded_instr.op_type = ERET;

                            // MRET is only allowed if currently in M-mode
                            if (prv != PRV_M) decoded_instr.exception.valid = 1'b1;
                        end
                        12'b0001000_00010: begin
                            decoded_instr.op_type = ERET;

                            // SRET is only allowed if
                            // * Currently in M-mode
                            // * Currently in S-mode and TVM is not 1.
                            if (prv != PRV_M && (prv != PRV_S || status.tsr)) decoded_instr.exception.valid = 1'b1;
                        end
                        12'b0001000_00101: begin
                            decoded_instr.op_type = WFI;

                            // WFI is only allowed if
                            // * Currently in M-mode
                            // * Currently in S-mode and TW is not 1.
                            if (prv != PRV_M && (prv != PRV_S || status.tw)) decoded_instr.exception.valid = 1'b1;
                        end
                        // Decode SFENCE.VMA
                        12'b0001001_?????: begin
                            decoded_instr.op_type = SFENCE_VMA;
                            decoded_instr.rs1 = rs1;
                            decoded_instr.rs2 = rs2;

                            // SFENCE.VMA is only allowed if
                            // * Currently in M-mode
                            // * Currently in S-mode and TVM is not 1.
                            if (prv != PRV_M && (prv != PRV_S || status.tvm)) decoded_instr.exception.valid = 1'b1;
                        end
                        default: decoded_instr.exception.valid = 1'b1;
                    endcase
                end
            end

            default: decoded_instr.exception.valid = 1'b1;
        endcase

        // Handle exception in load fault
        if (fetched_instr.exception.valid) begin
            decoded_instr.exception = fetched_instr.exception;
        end

        // Immedidate decoding logic
        decoded_instr.use_imm = 1'b0;
        unique case (opcode)
            // I-type
            OPCODE_LOAD, OPCODE_OP_IMM, OPCODE_OP_IMM_32, OPCODE_JALR: begin
                decoded_instr.use_imm = 1'b1;
                immediate = i_imm;
            end
            // U-Type
            OPCODE_AUIPC, OPCODE_LUI: begin
                decoded_instr.use_imm = 1'b1;
                immediate = u_imm;
            end
            // S-Type
            OPCODE_STORE: begin
                decoded_instr.use_imm = 1'b1;
                immediate = s_imm;
            end
            // B-Type
            OPCODE_BRANCH: begin
                immediate = b_imm;
            end
            // J-Type
            OPCODE_JAL: begin
                immediate = j_imm;
            end
            // Atomics. This probably should better be handled in EX stage.
            OPCODE_AMO: begin
                decoded_instr.use_imm = 1'b1;
                immediate = '0;
            end
            default: immediate = 'x;
        endcase
        decoded_instr.immediate = signed'(immediate);
    end

endmodule
