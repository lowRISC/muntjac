package cpu_common;

// Reason for instruction fetch
typedef enum logic [3:0] {
    // An instruction prefetch that follows the previous instruction in program counter order.
    IF_PREFETCH = 4'bxx00,
    // An instruction prefetch commanded by the branch predictor.
    IF_PREDICT = 4'bxx10,
    // An instruction fetch caused by misprediction.
    IF_MISPREDICT = 4'bxx01,
    // Memory protection bits, e.g. MSTATUS, PRV or SATP has been changed
    IF_PROT_CHANGED = 4'b0011,
    // SATP has been changed
    IF_SATP_CHANGED = 4'b0111,
    // FENCE.I is executed
    IF_FENCE_I = 4'b1011,
    // SFENCE.VMA is executed.
    IF_SFENCE_VMA = 4'b1111
} if_reason_t;

// MEM operations
typedef enum logic [2:0] {
    MEM_LOAD  = 3'b001,
    MEM_STORE = 3'b010,
    MEM_LR    = 3'b101,
    MEM_SC    = 3'b110,
    MEM_AMO   = 3'b111
} mem_op_t;

typedef struct packed {
    logic [4:0]  rs1;
    logic [4:0]  rs2;
    logic [4:0]  rd;
    logic [63:0] immediate;

    muntjac_pkg::op_type_e op_type;

    // For adder.
    // Adder is special to ALU because it is also used for branch target and address computation
    struct packed {
        // Whether adder should use PC or RS1 as input.
        logic use_pc;
        // Whether adder should use immediate or RS2 as input.
        logic use_imm;
    } adder;

    // Whether ALU ops or adder should use rs2 or immediate.
    logic use_imm;

    // Whether the operation is one of 32-bit operation.
    // Used by ALU, MUL and DIV
    logic word;

    // ALU ops
    muntjac_pkg::alu_op_e alu_op;

    // For shifter
    muntjac_pkg::shift_op_e shift_op;

    // For comparator
    muntjac_pkg::condition_code_e condition;

    // For system ops
    muntjac_pkg::sys_op_e sys_op;

    // For memory unit
    struct packed {
        mem_op_t    op;
        // Size of load/store (8 << load_store_size) is the size in bits.
        logic [1:0] size;
        // Whether load operation should perform sign extension.
        logic       zeroext;
    } mem;

    // For multiply unit
    struct packed {
        logic [1:0] op;
    } mul;

    // For division unit
    struct packed {
        logic is_unsigned;
        logic rem;
    } div;

    // Information relevant only to the CSR
    struct packed {
        // 00 - READ, 01 - WRITE, 10 - SET, 11 - CLEAR
        muntjac_pkg::csr_op_e op;
        // If rs1 should be used as immediate instead of a register index
        logic       imm;
    } csr;

    // PC of this decoded instruction.
    logic [63:0] pc;

    // Indicate the reason that this is fetched
    if_reason_t if_reason;

    // Exception happened during decoding.
    logic ex_valid;
    muntjac_pkg::exception_t  exception;
} decoded_instr_t;

typedef struct packed {
    // PC of fetched instruction.
    logic [63:0] pc;
    // Indicate if this instruction is flushed.
    if_reason_t if_reason;
    // Instruction word fetched.
    logic [31:0] instr_word;
    // Exception happened during instruction fetch.
    logic ex_valid;
    muntjac_pkg::exception_t  exception;
} fetched_instr_t;

endpackage
