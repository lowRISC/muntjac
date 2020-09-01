/**
 * Package with constants used by Muntjac
 */
package muntjac_pkg;

/////////////
// Opcodes //
/////////////

typedef enum logic [6:0] {
  OPCODE_LOAD         = 7'b0000011,
  OPCODE_LOAD_FP      = 7'b0000111,
  OPCODE_MISC_MEM     = 7'b0001111,
  OPCODE_OP_IMM       = 7'b0010011,
  OPCODE_AUIPC        = 7'b0010111,
  OPCODE_OP_IMM_32    = 7'b0011011,
  OPCODE_STORE        = 7'b0100011,
  OPCODE_STORE_FP     = 7'b0100111,
  OPCODE_AMO          = 7'b0101111,
  OPCODE_OP           = 7'b0110011,
  OPCODE_LUI          = 7'b0110111,
  OPCODE_OP_32        = 7'b0111011,
  OPCODE_BRANCH       = 7'b1100011,
  OPCODE_JALR         = 7'b1100111,
  OPCODE_JAL          = 7'b1101111,
  OPCODE_SYSTEM       = 7'b1110011
} opcode_e;

//////////////////////////////////
// Control and status registers //
//////////////////////////////////

typedef enum logic [11:0] {
  // F-extension
  CSR_FFLAGS         = 12'h001,
  CSR_FRM            = 12'h002,
  CSR_FCSR           = 12'h003,

  // Base ISA
  CSR_CYCLE          = 12'hC00,
  CSR_INSTRET        = 12'hC02,
  CSR_HPMCOUNTER3    = 12'hC03,
  CSR_HPMCOUNTER4    = 12'hC04,
  CSR_HPMCOUNTER5    = 12'hC05,
  CSR_HPMCOUNTER6    = 12'hC06,
  CSR_HPMCOUNTER7    = 12'hC07,
  CSR_HPMCOUNTER8    = 12'hC08,
  CSR_HPMCOUNTER9    = 12'hC09,
  CSR_HPMCOUNTER10   = 12'hC0A,
  CSR_HPMCOUNTER11   = 12'hC0B,
  CSR_HPMCOUNTER12   = 12'hC0C,
  CSR_HPMCOUNTER13   = 12'hC0D,
  CSR_HPMCOUNTER14   = 12'hC0E,
  CSR_HPMCOUNTER15   = 12'hC0F,
  CSR_HPMCOUNTER16   = 12'hC10,
  CSR_HPMCOUNTER17   = 12'hC11,
  CSR_HPMCOUNTER18   = 12'hC12,
  CSR_HPMCOUNTER19   = 12'hC13,
  CSR_HPMCOUNTER20   = 12'hC14,
  CSR_HPMCOUNTER21   = 12'hC15,
  CSR_HPMCOUNTER22   = 12'hC16,
  CSR_HPMCOUNTER23   = 12'hC17,
  CSR_HPMCOUNTER24   = 12'hC18,
  CSR_HPMCOUNTER25   = 12'hC19,
  CSR_HPMCOUNTER26   = 12'hC1A,
  CSR_HPMCOUNTER27   = 12'hC1B,
  CSR_HPMCOUNTER28   = 12'hC1C,
  CSR_HPMCOUNTER29   = 12'hC1D,
  CSR_HPMCOUNTER30   = 12'hC1E,
  CSR_HPMCOUNTER31   = 12'hC1F,

  // S-extension
  CSR_SSTATUS        = 12'h100,
  CSR_SEDELEG        = 12'h102,
  CSR_SIDELEG        = 12'h103,
  CSR_SIE            = 12'h104,
  CSR_STVEC          = 12'h105,
  CSR_SCOUNTEREN     = 12'h106,
  CSR_SSCRATCH       = 12'h140,
  CSR_SEPC           = 12'h141,
  CSR_SCAUSE         = 12'h142,
  CSR_STVAL          = 12'h143,
  CSR_SIP            = 12'h144,
  CSR_SATP           = 12'h180,

  // Machine-mode registers
  CSR_MVENDORID      = 12'hF11,
  CSR_MARCHID        = 12'hF12,
  CSR_MIMPID         = 12'hF13,
  CSR_MHARTID        = 12'hF14,
  CSR_MSTATUS        = 12'h300,
  CSR_MISA           = 12'h301,
  CSR_MEDELEG        = 12'h302,
  CSR_MIDELEG        = 12'h303,
  CSR_MIE            = 12'h304,
  CSR_MTVEC          = 12'h305,
  CSR_MCOUNTEREN     = 12'h306,
  CSR_MSCRATCH       = 12'h340,
  CSR_MEPC           = 12'h341,
  CSR_MCAUSE         = 12'h342,
  CSR_MTVAL          = 12'h343,
  CSR_MIP            = 12'h344,

  CSR_PMPCFG0        = 12'h3A0,
  CSR_PMPCFG1        = 12'h3A1,
  CSR_PMPCFG2        = 12'h3A2,
  CSR_PMPCFG3        = 12'h3A3,
  CSR_PMPADDR0       = 12'h3B0,
  CSR_PMPADDR15      = 12'h3BF,
  CSR_MCYCLE         = 12'hB00,
  CSR_MINSTRET       = 12'hB02,
  CSR_MHPMCOUNTER3   = 12'hB03,
  CSR_MHPMCOUNTER4   = 12'hB04,
  CSR_MHPMCOUNTER5   = 12'hB05,
  CSR_MHPMCOUNTER6   = 12'hB06,
  CSR_MHPMCOUNTER7   = 12'hB07,
  CSR_MHPMCOUNTER8   = 12'hB08,
  CSR_MHPMCOUNTER9   = 12'hB09,
  CSR_MHPMCOUNTER10  = 12'hB0A,
  CSR_MHPMCOUNTER11  = 12'hB0B,
  CSR_MHPMCOUNTER12  = 12'hB0C,
  CSR_MHPMCOUNTER13  = 12'hB0D,
  CSR_MHPMCOUNTER14  = 12'hB0E,
  CSR_MHPMCOUNTER15  = 12'hB0F,
  CSR_MHPMCOUNTER16  = 12'hB10,
  CSR_MHPMCOUNTER17  = 12'hB11,
  CSR_MHPMCOUNTER18  = 12'hB12,
  CSR_MHPMCOUNTER19  = 12'hB13,
  CSR_MHPMCOUNTER20  = 12'hB14,
  CSR_MHPMCOUNTER21  = 12'hB15,
  CSR_MHPMCOUNTER22  = 12'hB16,
  CSR_MHPMCOUNTER23  = 12'hB17,
  CSR_MHPMCOUNTER24  = 12'hB18,
  CSR_MHPMCOUNTER25  = 12'hB19,
  CSR_MHPMCOUNTER26  = 12'hB1A,
  CSR_MHPMCOUNTER27  = 12'hB1B,
  CSR_MHPMCOUNTER28  = 12'hB1C,
  CSR_MHPMCOUNTER29  = 12'hB1D,
  CSR_MHPMCOUNTER30  = 12'hB1E,
  CSR_MHPMCOUNTER31  = 12'hB1F,
  CSR_MCOUNTINHIBIT  = 12'h320,
  CSR_MHPMEVENT3     = 12'h323,
  CSR_MHPMEVENT4     = 12'h324,
  CSR_MHPMEVENT5     = 12'h325,
  CSR_MHPMEVENT6     = 12'h326,
  CSR_MHPMEVENT7     = 12'h327,
  CSR_MHPMEVENT8     = 12'h328,
  CSR_MHPMEVENT9     = 12'h329,
  CSR_MHPMEVENT10    = 12'h32A,
  CSR_MHPMEVENT11    = 12'h32B,
  CSR_MHPMEVENT12    = 12'h32C,
  CSR_MHPMEVENT13    = 12'h32D,
  CSR_MHPMEVENT14    = 12'h32E,
  CSR_MHPMEVENT15    = 12'h32F,
  CSR_MHPMEVENT16    = 12'h330,
  CSR_MHPMEVENT17    = 12'h331,
  CSR_MHPMEVENT18    = 12'h332,
  CSR_MHPMEVENT19    = 12'h333,
  CSR_MHPMEVENT20    = 12'h334,
  CSR_MHPMEVENT21    = 12'h335,
  CSR_MHPMEVENT22    = 12'h336,
  CSR_MHPMEVENT23    = 12'h337,
  CSR_MHPMEVENT24    = 12'h338,
  CSR_MHPMEVENT25    = 12'h339,
  CSR_MHPMEVENT26    = 12'h33A,
  CSR_MHPMEVENT27    = 12'h33B,
  CSR_MHPMEVENT28    = 12'h33C,
  CSR_MHPMEVENT29    = 12'h33D,
  CSR_MHPMEVENT30    = 12'h33E,
  CSR_MHPMEVENT31    = 12'h33F,

  // Debug/Trace Registers
  CSR_TSELECT        = 12'h7A0,
  CSR_TDATA1         = 12'h7A1,
  CSR_TDATA2         = 12'h7A2,
  CSR_TDATA3         = 12'h7A3,
  CSR_DCSR           = 12'h7B0,
  CSR_DPC            = 12'h7B1,
  CSR_DSCRATCH       = 12'h7B2
} csr_num_e;

// CSR operations
typedef enum logic [1:0] {
  CSR_OP_READ,
  CSR_OP_WRITE,
  CSR_OP_SET,
  CSR_OP_CLEAR
} csr_op_e;

// Privileged mode
typedef enum logic [1:0] {
  PRIV_LVL_M = 2'b11,
  PRIV_LVL_H = 2'b10,
  PRIV_LVL_S = 2'b01,
  PRIV_LVL_U = 2'b00
} priv_lvl_e;

// Status register
typedef struct packed {
  logic tsr;
  logic tw;
  logic tvm;
  logic mxr;
  logic sum;
  logic mprv;
  logic [1:0] fs;
  priv_lvl_e mpp;
  logic spp;
  logic mpie;
  logic spie;
  logic mie;
  logic sie;
} status_t;

// Interrupt requests
typedef struct packed {
  logic irq_software_s;
  logic irq_software_m;
  logic irq_timer_s;
  logic irq_timer_m;
  logic irq_external_s;
  logic irq_external_m;
} irqs_t;

// Exception cause
typedef enum logic [4:0] {
  EXC_CAUSE_IRQ_SOFTWARE_S     = {1'b1, 4'd01},
  EXC_CAUSE_IRQ_SOFTWARE_M     = {1'b1, 4'd03},
  EXC_CAUSE_IRQ_TIMER_S        = {1'b1, 4'd05},
  EXC_CAUSE_IRQ_TIMER_M        = {1'b1, 4'd07},
  EXC_CAUSE_IRQ_EXTERNAL_S     = {1'b1, 4'd09},
  EXC_CAUSE_IRQ_EXTERNAL_M     = {1'b1, 4'd11},
  EXC_CAUSE_INSN_ADDR_MISA     = {1'b0, 4'd00},
  EXC_CAUSE_INSTR_ACCESS_FAULT = {1'b0, 4'd01},
  EXC_CAUSE_ILLEGAL_INSN       = {1'b0, 4'd02},
  EXC_CAUSE_BREAKPOINT         = {1'b0, 4'd03},
  EXC_CAUSE_LOAD_MISALIGN      = {1'b0, 4'd04},
  EXC_CAUSE_LOAD_ACCESS_FAULT  = {1'b0, 4'd05},
  EXC_CAUSE_STORE_MISALIGN     = {1'b0, 4'd06},
  EXC_CAUSE_STORE_ACCESS_FAULT = {1'b0, 4'd07},
  EXC_CAUSE_ECALL_UMODE        = {1'b0, 4'd08},
  EXC_CAUSE_ECALL_SMODE        = {1'b0, 4'd09},
  EXC_CAUSE_ECALL_MMODE        = {1'b0, 4'd11},
  EXC_CAUSE_INSTR_PAGE_FAULT   = {1'b0, 4'd12},
  EXC_CAUSE_LOAD_PAGE_FAULT    = {1'b0, 4'd13},
  EXC_CAUSE_STORE_PAGE_FAULT   = {1'b0, 4'd15}
} exc_cause_e;

typedef struct packed {
  exc_cause_e  cause;
  logic [63:0] tval;
} exception_t;

// CSR status bits
parameter int unsigned CSR_MSTATUS_SIE_BIT      = 1;
parameter int unsigned CSR_MSTATUS_MIE_BIT      = 3;
parameter int unsigned CSR_MSTATUS_SPIE_BIT     = 5;
parameter int unsigned CSR_MSTATUS_MPIE_BIT     = 7;
parameter int unsigned CSR_MSTATUS_SPP_BIT      = 8;
parameter int unsigned CSR_MSTATUS_MPP_BIT_LOW  = 11;
parameter int unsigned CSR_MSTATUS_MPP_BIT_HIGH = 12;
parameter int unsigned CSR_MSTATUS_FS_BIT_LOW   = 13;
parameter int unsigned CSR_MSTATUS_FS_BIT_HIGH  = 14;
parameter int unsigned CSR_MSTATUS_MPRV_BIT     = 17;
parameter int unsigned CSR_MSTATUS_SUM_BIT      = 18;
parameter int unsigned CSR_MSTATUS_MXR_BIT      = 19;
parameter int unsigned CSR_MSTATUS_TVM_BIT      = 20;
parameter int unsigned CSR_MSTATUS_TW_BIT       = 21;
parameter int unsigned CSR_MSTATUS_TSR_BIT      = 22;
parameter int unsigned CSR_MSTATUS_UXL_BIT_LOW  = 32;
parameter int unsigned CSR_MSTATUS_UXL_BIT_HIGH = 33;
parameter int unsigned CSR_MSTATUS_SXL_BIT_LOW  = 34;
parameter int unsigned CSR_MSTATUS_SXL_BIT_HIGH = 35;
parameter int unsigned CSR_MSTATUS_SD_BIT       = 63;

// CSR machine ISA
parameter logic [1:0] CSR_MISA_MXL = 2'b10; // M-XLEN: XLEN in M-Mode for RV64
parameter logic [1:0] CSR_MSTATUS_UXL = 2'b10; // U-XLEN: XLEN in U-Mode for RV64
parameter logic [1:0] CSR_MSTATUS_SXL = 2'b10; // S-XLEN: XLEN in S-Mode for RV64

// CSR interrupt pending/enable bits
parameter int unsigned CSR_SSIX_BIT = 1;
parameter int unsigned CSR_MSIX_BIT = 3;
parameter int unsigned CSR_STIX_BIT = 5;
parameter int unsigned CSR_MTIX_BIT = 7;
parameter int unsigned CSR_SEIX_BIT = 9;
parameter int unsigned CSR_MEIX_BIT = 11;

///////////////////////
// Instruction fetch //
///////////////////////

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
} if_reason_e;

typedef struct packed {
  // PC of fetched instruction.
  logic [63:0] pc;
  // Indicate if this instruction is flushed.
  if_reason_e if_reason;
  // Instruction word fetched.
  logic [31:0] instr_word;
  // Exception happened during instruction fetch.
  logic ex_valid;
  exception_t exception;
} fetched_instr_t;

typedef enum logic [2:0] {
  BRANCH_NONE    = 3'b000,
  BRANCH_UNTAKEN = 3'b010,
  BRANCH_TAKEN   = 3'b011,
  BRANCH_JUMP    = 3'b100,
  BRANCH_CALL    = 3'b101,
  BRANCH_RET     = 3'b110,
  BRANCH_YIELD   = 3'b111
} branch_type_e;

typedef struct packed {
  branch_type_e branch_type;
  // PC of the jump/branch instruction.
  logic [63:0]  pc;
  // If the instruction is compressed.
  logic         compressed;
} branch_info_t;

/////////////////
// Decoded Ops //
/////////////////

// Type of decoded op
typedef enum logic [3:0] {
  OP_ALU,
  OP_JUMP,
  OP_BRANCH,
  OP_MEM,
  OP_MUL,
  OP_DIV,
  OP_SYSTEM
} op_type_e;

// ALU operations
typedef enum logic [2:0] {
  // Arithmetics
  // For add, adder.use_pc and adder.use_imm should be set properly.
  ALU_ADD = 3'b000,
  ALU_SUB = 3'b001,

  // Shifts
  // Actual shift ops determined via shift_op_e.
  ALU_SHIFT = 3'b010,

  // Compare and set
  // Actual condition determined via condition_code_e
  ALU_SCC = 3'b011,

  // Logic operation
  ALU_XOR = 3'b100,
  ALU_OR  = 3'b110,
  ALU_AND = 3'b111
} alu_op_e;

// Opcode for shifter
// [0] determines direction (0 - left, 1 - right)
// [1] determines sign-ext (0 - logical, 1 - arithmetic)
typedef enum logic [1:0] {
  SHIFT_OP_SLL = 2'b00,
  SHIFT_OP_SRL = 2'b01,
  SHIFT_OP_SRA = 2'b11
} shift_op_e;

// Branch/comparison condition codes
typedef enum logic [2:0] {
  CC_EQ    = 3'b000,
  CC_NE    = 3'b001,
  CC_LT    = 3'b100,
  CC_GE    = 3'b101,
  CC_LTU   = 3'b110,
  CC_GEU   = 3'b111
} condition_code_e;

// MEM operations
typedef enum logic [2:0] {
  MEM_LOAD  = 3'b001,
  MEM_STORE = 3'b010,
  MEM_LR    = 3'b101,
  MEM_SC    = 3'b110,
  MEM_AMO   = 3'b111
} mem_op_e;

// Multiply operations
typedef enum logic [1:0] {
  MUL_OP_MUL    = 2'b00,
  MUL_OP_MULH   = 2'b01,
  MUL_OP_MULHSU = 2'b10,
  MUL_OP_MULHU  = 2'b11
} mul_op_e;

// Division operations
typedef enum logic [1:0] {
  DIV_OP_DIV  = 2'b00,
  DIV_OP_DIVU = 2'b01,
  DIV_OP_REM  = 2'b10,
  DIV_OP_REMU = 2'b11
} div_op_e;

// System opcodes
typedef enum logic [2:0] {
  SYS_CSR,
  // Environmental return (MRET, SRET)
  SYS_ERET,
  // TLB Flush
  SYS_SFENCE_VMA,
  SYS_FENCE_I,
  SYS_WFI
} sys_op_e;

typedef struct packed {
  logic [4:0]  rs1;
  logic [4:0]  rs2;
  logic [4:0]  rd;
  logic [31:0] immediate;

  op_type_e op_type;

  // For adder.
  // Adder is special to ALU because it is also used for branch target and address computation
  // Whether adder should use PC or RS1 as input.
  logic adder_use_pc;
  // Whether adder should use immediate or RS2 as input.
  logic adder_use_imm;

  // Whether ALU ops or adder should use rs2 or immediate.
  logic use_imm;

  // Size of operation.
  // For ALU, MUL, DIV, this currently can only be word (10) or dword (11).
  logic [1:0] size;

  // Whether zero-extension or sign-extension should be used.
  // Currently only used by MEM unit.
  logic zeroext;

  // ALU ops
  alu_op_e alu_op;

  // For shifter
  shift_op_e shift_op;

  // For comparator
  condition_code_e condition;

  // For system ops
  sys_op_e sys_op;

  // For memory unit
  mem_op_e mem_op;

  // For multiply unit
  mul_op_e mul_op;

  // For division unit
  div_op_e div_op;

  // For CSR
  csr_op_e csr_op;
  // If rs1 should be used as immediate instead of a register index
  logic csr_use_imm;

  // PC of this decoded instruction.
  logic [63:0] pc;

  // Indicate the reason that this is fetched
  if_reason_e if_reason;

  // Exception happened during decoding.
  logic ex_valid;
  exception_t exception;
} decoded_instr_t;

endpackage
