module muntjac_comparator import muntjac_pkg::*; (
    input  logic [63:0]     operand_a_i,
    input  logic [63:0]     operand_b_i,
    input  condition_code_e condition_i,
    input  logic [63:0]     difference_i,
    output logic            result_o
);

  logic eq_flag;
  logic lt_flag;
  logic ltu_flag;
  logic result_pre_neg;

  always_comb begin
    // We don't check for difference_i == 0 because it will make the critical path longer.
    eq_flag = operand_a_i == operand_b_i;

    // If MSBs are the same, look at the sign of the result is sufficient.
    // Otherwise the one with MSB 0 is larger.
    lt_flag = operand_a_i[63] == operand_b_i[63] ? difference_i[63] : operand_a_i[63];

    // If MSBs are the same, look at the sign of the result is sufficient.
    // Otherwise the one with MSB 1 is larger.
    ltu_flag = operand_a_i[63] == operand_b_i[63] ? difference_i[63] : operand_b_i[63];

    unique case ({condition_i[2:1], 1'b0})
      CC_FALSE: result_pre_neg = 1'b0;
      CC_EQ: result_pre_neg = eq_flag;
      CC_LT: result_pre_neg = lt_flag;
      CC_LTU: result_pre_neg = ltu_flag;
      default: result_pre_neg = 'x;
    endcase

    result_o = condition_i[0] ? !result_pre_neg : result_pre_neg;
  end

endmodule

module muntjac_shifter import muntjac_pkg::*; (
    input  logic [63:0] operand_a_i,
    input  logic [63:0] operand_b_i,
    input  shift_op_e   shift_op_i,
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
    unique casez ({word_i, shift_op_i[0]})
      2'b?0: begin
        // For left shift, we reverse the contents and perform a right shift
        for (int i = 0; i < 64; i++) shift_operand[i] = operand_a_i[63 - i];
      end
      2'b01: begin
        shift_operand = operand_a_i;
      end
      2'b11: begin
        // For 32-bit shift, pad 32-bit dummy bits on the right
        shift_operand = {operand_a_i[31:0], 32'dx};
      end
      default:;
    endcase

    shift_fill_bit = shift_op_i[1] && shift_operand[63];
    shamt = word_i ? {1'b0, operand_b_i[4:0]} : operand_b_i[5:0];

    shift_operand_ext = {shift_fill_bit, shift_operand};
    shift_result = signed'(shift_operand_ext) >>> shamt;

    result_o = 'x;
    unique casez ({word_i, shift_op_i[0]})
      2'b?0: begin
        // For left shift, reverse the shifted result back.
        for (int i = 0; i < 64; i++) result_o[i] = shift_result[63 - i];
      end
      2'b01: begin
        result_o = shift_result;
      end
      2'b11: begin
        // For 32-bit shift, remove the 32-bit padded dummy bits.
        // MSBs will be fixed by the ALU unit.
        result_o = {32'dx, shift_result[63:32]};
      end
      default:;
    endcase
  end

endmodule

module muntjac_alu import cpu_common::*; import muntjac_pkg::*; (
    input  decoded_instr_t decoded_op_i,
    input  [63:0]          rs1_i,
    input  [63:0]          rs2_i,
    output logic [63:0]    sum_o,
    output logic           compare_result_o,
    output logic [63:0]    result_o
);

  // Adder. Used for ADD, LOAD, STORE, AUIPC, JAL, JALR, BRANCH
  // This is the core component of the ALU.
  // Because the adder is also used for address (load/store and branch/jump) calculation, it uses
  //   adder.use_pc and adder.use_imm to mux inputs rather than use_imm.
  assign sum_o =
      (decoded_op_i.adder.use_pc ? decoded_op_i.pc : rs1_i) +
      (decoded_op_i.adder.use_imm ? decoded_op_i.immediate : rs2_i);

  wire [63:0] operand_b = decoded_op_i.use_imm ? decoded_op_i.immediate : rs2_i;

  // Subtractor. Used for SUB, BRANCH, SLT, SLTU
  logic [63:0] difference;
  assign difference = rs1_i - operand_b;

  // Comparator. Used for BRANCH, SLT, and SLTU
  muntjac_comparator comparator (
      .operand_a_i  (rs1_i),
      .operand_b_i  (operand_b),
      .condition_i  (decoded_op_i.condition),
      .difference_i (difference),
      .result_o     (compare_result_o)
  );

  logic [63:0] shift_result;
  muntjac_shifter shifter(
      .operand_a_i (rs1_i),
      .operand_b_i (operand_b),
      .shift_op_i  (decoded_op_i.shift_op),
      .word_i      (decoded_op_i.word),
      .result_o    (shift_result)
  );

    /* Result Multiplexer */

  logic [63:0] alu_result;
  always_comb begin
    unique case (decoded_op_i.alu_op)
      ALU_ADD:   alu_result = sum_o;
      ALU_SUB:   alu_result = difference;
      ALU_AND:   alu_result = rs1_i & operand_b;
      ALU_OR:    alu_result = rs1_i | operand_b;
      ALU_XOR:   alu_result = rs1_i ^ operand_b;
      ALU_SHIFT: alu_result = shift_result;
      ALU_SCC:   alu_result = compare_result_o;
      default:   alu_result = 'x;
    endcase

    result_o = decoded_op_i.word ? {{32{alu_result[31]}}, alu_result[31:0]} : alu_result;
  end

endmodule
