package riscv;

// Currently defined base opcodes.
typedef enum logic [6:0] {
    OPCODE_LOAD         = 7'b0000011,
    OPCODE_MISC_MEM     = 7'b0001111,
    OPCODE_OP_IMM       = 7'b0010011,
    OPCODE_AUIPC        = 7'b0010111,
    OPCODE_OP_IMM_32    = 7'b0011011,
    OPCODE_STORE        = 7'b0100011,
    OPCODE_AMO          = 7'b0101111,
    OPCODE_OP           = 7'b0110011,
    OPCODE_LUI          = 7'b0110111,
    OPCODE_OP_32        = 7'b0111011,
    OPCODE_BRANCH       = 7'b1100011,
    OPCODE_JALR         = 7'b1100111,
    OPCODE_JAL          = 7'b1101111,
    OPCODE_SYSTEM       = 7'b1110011
} opcode_e;

endpackage
