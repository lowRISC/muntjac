module muntjac_decoder import muntjac_pkg::*; (
  input  fetched_instr_t fetched_instr,
  output decoded_instr_t decoded_instr,

  // Currently privilege, for decode-stage privilege checking.
  input  priv_lvl_e prv,
  // Status for determining if certain operations are allowed.
  input  status_t status,

  output csr_num_e csr_sel,
  output csr_op_e csr_op,
  input  logic csr_illegal
);

  ///////////////////
  // Decompression //
  ///////////////////

  logic [31:0] instr;
  logic illegal_compressed;

  muntjac_compressed_decoder decompressor (
    .instr_i (fetched_instr.instr_word),
    .instr_o (instr),
    .illegal_instr_o (illegal_compressed)
  );

  ////////////////////
  // Field decoding //
  ////////////////////

  wire [6:0] funct7 = instr[31:25];
  wire [4:0] rs2    = instr[24:20];
  wire [4:0] rs1    = instr[19:15];
  wire [2:0] funct3 = instr[14:12];
  wire [4:0] rd     = instr[11:7];
  wire [6:0] opcode = instr[6:0];

  wire [31:0] i_imm = { {20{instr[31]}}, instr[31:20] };
  wire [31:0] s_imm = { {20{instr[31]}}, instr[31:25], instr[11:7] };
  wire [31:0] b_imm = { {20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0 };
  wire [31:0] u_imm = { instr[31:12], 12'b0 };
  wire [31:0] j_imm = { {11{instr[31]}}, instr[31], instr[19:12], instr[20], instr[30:21], 1'b0 };

  // Wire to CSR privilege checker
  assign csr_sel = csr_num_e'(instr[31:20]);
  assign csr_op = funct3[1] == 1'b1 && rs1 == 0 ? CSR_OP_READ : csr_op_e'(funct3[1:0]);

  logic rd_enable;
  logic rs1_enable;
  logic rs2_enable;

  logic illegal_instr;
  logic ecall;
  logic ebreak;

  always_comb begin
    decoded_instr = decoded_instr_t'('x);
    decoded_instr.op_type = OP_ALU;

    decoded_instr.size = 2'b11;
    decoded_instr.zeroext = 1'b0;

    decoded_instr.alu_op = alu_op_e'('x);
    decoded_instr.shift_op = shift_op_e'('x);
    decoded_instr.condition = condition_code_e'('x);

    rd_enable = 1'b0;
    rs1_enable = 1'b0;
    rs2_enable = 1'b0;

    illegal_instr = illegal_compressed;
    ecall = 1'b0;
    ebreak = 1'b0;

    // Forward these fields.
    decoded_instr.pc = fetched_instr.pc;
    decoded_instr.if_reason = fetched_instr.if_reason;

    unique case (opcode)

      ///////////
      // Jumps //
      ///////////

      OPCODE_JAL: begin
        decoded_instr.op_type = OP_BRANCH;
        decoded_instr.condition = CC_TRUE;
        rd_enable = 1'b1;
      end

      OPCODE_JALR: begin
        decoded_instr.op_type = OP_BRANCH;
        decoded_instr.condition = CC_TRUE;
        rd_enable = 1'b1;
        rs1_enable = 1'b1;

        if (funct3 != 3'b0) illegal_instr = 1'b1;
      end

      OPCODE_BRANCH: begin
        decoded_instr.op_type = OP_BRANCH;
        rs1_enable = 1'b1;
        rs2_enable = 1'b1;

        unique case (funct3)
          3'b000,
          3'b001,
          3'b100,
          3'b101,
          3'b110,
          3'b111: decoded_instr.condition = condition_code_e'(funct3);
          default: illegal_instr = 1'b1;
        endcase
      end

      ////////////////
      // Load/store //
      ////////////////

      OPCODE_STORE: begin
        decoded_instr.op_type = OP_MEM;
        decoded_instr.size = funct3[1:0];
        decoded_instr.mem_op = MEM_STORE;
        rs1_enable = 1'b1;
        rs2_enable = 1'b1;

        if (funct3[2] == 1'b1) illegal_instr = 1'b1;
      end

      OPCODE_LOAD: begin
        decoded_instr.op_type = OP_MEM;
        decoded_instr.size = funct3[1:0];
        decoded_instr.zeroext = funct3[2];
        decoded_instr.mem_op = MEM_LOAD;
        rd_enable = 1'b1;
        rs1_enable = 1'b1;

        if (funct3 == 3'b111) illegal_instr = 1'b1;
      end

      OPCODE_AMO: begin
        decoded_instr.op_type = OP_MEM;
        decoded_instr.size = funct3[1:0];
        decoded_instr.mem_op = MEM_AMO;
        rd_enable = 1'b1;
        rs1_enable = 1'b1;
        rs2_enable = 1'b1;

        unique case (funct3)
          3'b010, 3'b011:;
          default: begin
            illegal_instr = 1'b1;
          end
        endcase

        unique case (funct7[6:2])
          5'b00010: begin
            decoded_instr.mem_op = MEM_LR;
            if (rs2 != 0) begin
              illegal_instr = 1'b1;
            end
          end
          5'b00011: decoded_instr.mem_op = MEM_SC;
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
            illegal_instr = 1'b1;
          end
        endcase
      end

      /////////
      // ALU //
      /////////

      OPCODE_LUI: begin
        decoded_instr.op_type = OP_ALU;
        decoded_instr.alu_op = ALU_ADD;
        rd_enable = 1'b1;
      end

      OPCODE_AUIPC: begin
        decoded_instr.op_type = OP_ALU;
        decoded_instr.alu_op = ALU_ADD;
        rd_enable = 1'b1;
      end

      OPCODE_OP_IMM: begin
        rd_enable = 1'b1;
        rs1_enable = 1'b1;

        unique case (funct3)
          3'b000: begin
            decoded_instr.alu_op = ALU_ADD;
          end
          3'b010: begin
            decoded_instr.alu_op = ALU_SCC;
            decoded_instr.condition = CC_LT;
          end
          3'b011: begin
            decoded_instr.alu_op = ALU_SCC;
            decoded_instr.condition = CC_LTU;
          end
          3'b100: decoded_instr.alu_op = ALU_XOR;
          3'b110: decoded_instr.alu_op = ALU_OR;
          3'b111: decoded_instr.alu_op = ALU_AND;

          3'b001: begin
            decoded_instr.alu_op = ALU_SHIFT;
            decoded_instr.shift_op = SHIFT_OP_SLL;

            // Shift is invalid if imm is larger than XLEN.
            if (funct7[6:1] != 6'b0) illegal_instr = 1'b1;
          end

          3'b101: begin
            decoded_instr.alu_op = ALU_SHIFT;

            if (funct7[6:1] == 6'b0) decoded_instr.shift_op = SHIFT_OP_SRL;
            else if (funct7[6:1] == 6'b010000) decoded_instr.shift_op = SHIFT_OP_SRA;
            // Shift is invalid if imm is larger than XLEN.
            else illegal_instr = 1'b1;
          end

          default:;
        endcase
      end

      OPCODE_OP_IMM_32: begin
        decoded_instr.size = 2'b10;
        rd_enable = 1'b1;
        rs1_enable = 1'b1;

        unique case (funct3)
          3'b000: begin
            decoded_instr.alu_op = ALU_ADD;
          end
          3'b001: begin
            decoded_instr.alu_op = ALU_SHIFT;
            decoded_instr.shift_op = SHIFT_OP_SLL;

            // Shift is invalid if imm is larger than 32.
            if (funct7 != 7'b0) illegal_instr = 1'b1;
          end

          3'b101: begin
            decoded_instr.alu_op = ALU_SHIFT;

            if (funct7 == 7'b0) decoded_instr.shift_op = SHIFT_OP_SRL;
            else if (funct7 == 7'b0100000) decoded_instr.shift_op = SHIFT_OP_SRA;
            // Shift is invalid if imm is larger than 32.
            else illegal_instr = 1'b1;
          end

          default: illegal_instr = 1'b1;
        endcase
      end

      OPCODE_OP: begin
        rd_enable = 1'b1;
        rs1_enable = 1'b1;
        rs2_enable = 1'b1;

        unique casez ({funct7, funct3})
          {7'b0000001, 3'b0??}: begin
            decoded_instr.op_type = OP_MUL;
            decoded_instr.mul_op = mul_op_e'(funct3[1:0]);
          end
          {7'b0000001, 3'b1??}: begin
            decoded_instr.op_type = OP_DIV;
            decoded_instr.div_op = div_op_e'(funct3[1:0]);
          end
          {7'b0000000, 3'b000}: begin
            decoded_instr.alu_op = ALU_ADD;
          end
          {7'b0100000, 3'b000}: begin
            decoded_instr.alu_op = ALU_SUB;
          end
          {7'b0000000, 3'b010}: begin
            decoded_instr.alu_op = ALU_SCC;
            decoded_instr.condition = CC_LT;
          end
          {7'b0000000, 3'b011}: begin
            decoded_instr.alu_op = ALU_SCC;
            decoded_instr.condition = CC_LTU;
          end
          {7'b0000000, 3'b100}: decoded_instr.alu_op = ALU_XOR;
          {7'b0000000, 3'b110}: decoded_instr.alu_op = ALU_OR;
          {7'b0000000, 3'b111}: decoded_instr.alu_op = ALU_AND;
          {7'b0000000, 3'b001}: begin
            decoded_instr.alu_op = ALU_SHIFT;
            decoded_instr.shift_op = SHIFT_OP_SLL;
          end
          {7'b0000000, 3'b101}: begin
            decoded_instr.alu_op = ALU_SHIFT;
            decoded_instr.shift_op = SHIFT_OP_SRL;
          end
          {7'b0100000, 3'b101}: begin
            decoded_instr.alu_op = ALU_SHIFT;
            decoded_instr.shift_op = SHIFT_OP_SRA;
          end
          default: illegal_instr = 1'b1;
        endcase
      end

      OPCODE_OP_32: begin
        decoded_instr.size = 2'b10;
        rd_enable = 1'b1;
        rs1_enable = 1'b1;
        rs2_enable = 1'b1;

        unique casez ({funct7, funct3})
          {7'b0000001, 3'b000}: begin
            decoded_instr.op_type = OP_MUL;
            decoded_instr.mul_op = MUL_OP_MUL;
          end
          {7'b0000001, 3'b1??}: begin
            decoded_instr.op_type = OP_DIV;
            decoded_instr.div_op = div_op_e'(funct3[1:0]);
          end
          {7'b0000000, 3'b000}: begin
            decoded_instr.alu_op = ALU_ADD;
          end
          {7'b0100000, 3'b000}: begin
            decoded_instr.alu_op = ALU_SUB;
          end
          {7'b0000000, 3'b001}: begin
            decoded_instr.alu_op = ALU_SHIFT;
            decoded_instr.shift_op = SHIFT_OP_SLL;
          end
          {7'b0000000, 3'b101}: begin
            decoded_instr.alu_op = ALU_SHIFT;
            decoded_instr.shift_op = SHIFT_OP_SRL;
          end
          {7'b0100000, 3'b101}: begin
            decoded_instr.alu_op = ALU_SHIFT;
            decoded_instr.shift_op = SHIFT_OP_SRA;
          end
          default: illegal_instr = 1'b1;
        endcase
      end

      /////////////
      // Special //
      /////////////

      OPCODE_MISC_MEM: begin
        unique case (funct3)
          3'b000: begin
            // For now, decode FENCE as NOP.
            // FIXME: Revisit this design when the cache is not SeqCst.
          end
          3'b001: begin
            // XXX: fence.i is somewhat special compared to normal fence
            // because it need to wait all previous instructions to commit
            // and flush the pipeline, so decode as OP_SYSTEM instrution for now
            decoded_instr.op_type = OP_SYSTEM;
            decoded_instr.sys_op = SYS_FENCE_I;
          end
          default: illegal_instr = 1'b1;
        endcase
      end

      OPCODE_SYSTEM: begin
        // Because the backend will wait for pipeline to drain for SYSTEM instructions,
        // we just fetch both registers regardless if it's actually used by the certain
        // instruction.
        rs1_enable = 1'b1;
        rs2_enable = 1'b1;

        if (funct3[1:0] != 2'b00) begin
          decoded_instr.op_type     = OP_SYSTEM;
          decoded_instr.sys_op      = SYS_CSR;
          decoded_instr.csr_op      = csr_op;
          decoded_instr.csr_use_imm = funct3[2];
          rd_enable = 1'b1;

          if (csr_illegal) illegal_instr = 1'b1;
        end
        else begin
          // PRIV
          unique casez (instr[31:20])
            12'b0000000_00000: begin
              ecall = 1'b1;
            end
            12'b0000000_00001: begin
              ebreak = 1'b1;
            end
            12'b0011000_00010: begin
              decoded_instr.op_type = OP_SYSTEM;
              decoded_instr.sys_op  = SYS_ERET;

              // MRET is only allowed if currently in M-mode
              if (prv != PRIV_LVL_M) illegal_instr = 1'b1;
            end
            12'b0001000_00010: begin
              decoded_instr.op_type = OP_SYSTEM;
              decoded_instr.sys_op  = SYS_ERET;

              // SRET is only allowed if
              // * Currently in M-mode
              // * Currently in S-mode and TVM is not 1.
              if (prv != PRIV_LVL_M && (prv != PRIV_LVL_S || status.tsr)) illegal_instr = 1'b1;
            end
            12'b0001000_00101: begin
              decoded_instr.op_type = OP_SYSTEM;
              decoded_instr.sys_op  = SYS_WFI;

              // WFI is only allowed if
              // * Currently in M-mode
              // * Currently in S-mode and TW is not 1.
              if (prv != PRIV_LVL_M && (prv != PRIV_LVL_S || status.tw)) illegal_instr = 1'b1;
            end
            // Decode SFENCE.VMA
            12'b0001001_?????: begin
              decoded_instr.op_type = OP_SYSTEM;
              decoded_instr.sys_op  = SYS_SFENCE_VMA;

              // SFENCE.VMA is only allowed if
              // * Currently in M-mode
              // * Currently in S-mode and TVM is not 1.
              if (prv != PRIV_LVL_M && (prv != PRIV_LVL_S || status.tvm)) illegal_instr = 1'b1;
            end
            default: illegal_instr = 1'b1;
          endcase
        end
      end

      default: illegal_instr = 1'b1;
    endcase

    decoded_instr.rd  = rd_enable  ? rd  : '0;
    decoded_instr.rs1 = rs1_enable ? rs1 : '0;
    decoded_instr.rs2 = rs2_enable ? rs2 : '0;

    // Exception multiplexing
    if (fetched_instr.ex_valid) begin
      decoded_instr.ex_valid = 1'b1;
      decoded_instr.exception = fetched_instr.exception;
    end else begin
      unique case (1'b1)
        illegal_instr: begin
          decoded_instr.ex_valid = 1'b1;
          decoded_instr.exception.cause = EXC_CAUSE_ILLEGAL_INSN;
          decoded_instr.exception.tval = fetched_instr.instr_word;
        end
        ecall: begin
          decoded_instr.ex_valid = 1'b1;
          decoded_instr.exception.cause = exc_cause_e'({3'b010, prv});
          decoded_instr.exception.tval = 0;
        end
        ebreak: begin
          decoded_instr.ex_valid = 1'b1;
          decoded_instr.exception.cause = EXC_CAUSE_BREAKPOINT;
          decoded_instr.exception.tval = 0;
        end
        default: begin
          decoded_instr.ex_valid = 1'b0;
          decoded_instr.exception.cause = exc_cause_e'('x);
          decoded_instr.exception.tval = fetched_instr.instr_word;
        end
      endcase
    end

    //////////////////////////////////
    // Adder and ALU operand select //
    //////////////////////////////////

    decoded_instr.adder_use_pc = 1'bx;
    decoded_instr.adder_use_imm = 1'bx;
    decoded_instr.use_imm = 1'bx;
    unique case (opcode)
      OPCODE_LOAD, OPCODE_STORE, OPCODE_AMO, OPCODE_LUI, OPCODE_JALR: begin
        decoded_instr.adder_use_pc = 1'b0;
        decoded_instr.adder_use_imm = 1'b1;
      end
      OPCODE_OP_IMM, OPCODE_OP_IMM_32: begin
        decoded_instr.adder_use_pc = 1'b0;
        decoded_instr.adder_use_imm = 1'b1;
        decoded_instr.use_imm = 1'b1;
      end
      OPCODE_AUIPC, OPCODE_JAL: begin
        decoded_instr.adder_use_pc = 1'b1;
        decoded_instr.adder_use_imm = 1'b1;
      end
      OPCODE_BRANCH: begin
        decoded_instr.adder_use_pc = 1'b1;
        decoded_instr.adder_use_imm = 1'b1;
        decoded_instr.use_imm = 1'b0;
      end
      OPCODE_OP, OPCODE_OP_32: begin
        decoded_instr.adder_use_pc = 1'b0;
        decoded_instr.adder_use_imm = 1'b0;
        decoded_instr.use_imm = 1'b0;
      end
      default:;
    endcase

    ///////////////////////
    // Immedidate select //
    ///////////////////////

    decoded_instr.immediate = 'x;
    unique case (opcode)
      // I-type
      OPCODE_LOAD, OPCODE_OP_IMM, OPCODE_OP_IMM_32, OPCODE_JALR: begin
        decoded_instr.immediate = i_imm;
      end
      // U-Type
      OPCODE_AUIPC, OPCODE_LUI: begin
        decoded_instr.immediate = u_imm;
      end
      // S-Type
      OPCODE_STORE: begin
        decoded_instr.immediate = s_imm;
      end
      // B-Type
      OPCODE_BRANCH: begin
        decoded_instr.immediate = b_imm;
      end
      // J-Type
      OPCODE_JAL: begin
        decoded_instr.immediate = j_imm;
      end
      // Atomics. Decode immediate to zero so that adder will produce rs1.
      OPCODE_AMO: begin
        decoded_instr.immediate = '0;
      end
      default:;
    endcase
  end

endmodule
