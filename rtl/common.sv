package cpu_common;

typedef enum logic [3:0] {
    // Normal ALU operation
    ALU,
    // Branching and jumps
    BRANCH,
    MEM,
    MUL,
    DIV,
    SYSTEM,
    FENCE_I
} op_type_t;

typedef enum logic [1:0] {
    CSR,
    // Environmental return (MRET, SRET)
    ERET,
    // TLB Flush
    SFENCE_VMA,
    WFI
} sys_op_t;

// ALU operations
typedef enum logic [2:0] {
    // Arithmetic
    ADD = 3'b000,
    SUB = 3'b001,
    // Shifts
    SHIFT = 3'b010,
    // Compare and set
    SCC = 3'b011,
    // Bit operation
    L_XOR = 3'b100, L_OR = 3'b110, L_AND = 3'b111
} op_t;

// Branch/comparison condition codes
typedef enum logic [2:0] {
    CC_FALSE,
    CC_TRUE,
    CC_EQ,
    CC_NE,
    CC_LT,
    CC_GE,
    CC_LTU,
    CC_GEU
} condition_code_e;

// Reason for instruction fetch
typedef enum logic [3:0] {
    // An instruction prefetch that follows the previous instruction in program counter order.
    IF_PREFETCH = 4'bxx00,
    // An instruction prefetch commanded by the branch predictor.
    IF_PREDICT = 4'bxx10,
    // An instruction fetch caused by misprediction.
    IF_MISPREDICT = 4'bxx01,
    // SUM or privilege level have been changed
    IF_PROT_CHANGED = 4'b0011,
    IF_EXCEPTION = 4'b1011,
    // SATP has been changed
    IF_SATP_CHANGED = 4'b0111,
    // Either FENCE.I or SFENCE.VMA is executed.
    IF_FLUSH = 4'b1111
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
    logic valid;
    logic mcause_interrupt;
    logic [3:0] mcause_code;
    // 32-bit CPU should only use the lower bits.
    logic [63:0] mtval;
} exception_t;

typedef struct packed {
    // Decoded instruction parts
    op_type_t    op_type;
    logic [4:0]  rs1;
    logic [4:0]  rs2;
    logic [4:0]  rd;
    logic [63:0] immediate;

    // Whether the operation is one of 32-bit operation.
    // Used by ALU, MUL and DIV
    logic is_32;

    // Information relevant to the adder.
    // Adder is special to ALU because it is also used for branch target and address computation
    struct packed {
        // Whether adder should use PC or RS1 as input.
        logic use_pc;
        // Whether adder should use immediate or RS2 as input.
        logic use_imm;
    } adder;

    sys_op_t sys_op;

    // Whether ALU ops or adder should use rs2 or immediate.
    logic use_imm;

    // ALU ops
    op_t op;

    // For shifter
    logic shifter_left;
    logic shifter_arithmetic;

    // For comparator
    condition_code_e condition;

    // Information relevant only to the memory unit.
    struct packed {
        mem_op_t    op;
        // Size of load/store (8 << load_store_size) is the size in bits.
        logic [1:0] size;
        // Whether load operation should perform sign extension.
        logic       zeroext;
    } mem;

    struct packed {
        logic [1:0] op;
    } mul;

    struct packed {
        logic is_unsigned;
        logic rem;
    } div;

    // Information relevant only to the CSR
    struct packed {
        // 00 - READ, 01 - WRITE, 10 - SET, 11 - CLEAR
        logic [1:0] op;
        // If rs1 should be used as immediate instead of a register index
        logic       imm;
    } csr;

    // Traps related fields.
    logic        mret;

    // PC of decoded instruction.
    logic [63:0] pc;
    // Indicate the reason that this is fetched
    if_reason_t if_reason;
    // Exception happened during decoding.
    exception_t  exception;
} decoded_instr_t;

typedef struct packed {
    // PC of fetched instruction.
    logic [63:0] pc;
    // Indicate if this instruction is flushed.
    if_reason_t if_reason;
    // Instruction word fetched.
    logic [31:0] instr_word;
    // Exception happened during instruction fetch.
    exception_t  exception;
} fetched_instr_t;

typedef struct packed {
    logic tsr;
    logic tw;
    logic tvm;
    logic mxr;
    logic sum;
    logic mprv;
    logic [1:0] fs;
    riscv::prv_t mpp;
    logic spp;
    logic mpie;
    logic spie;
    logic mie;
    logic sie;
} status_t;

endpackage
