/**
 * Package with constants used by Muntjac
 */
package muntjac_pkg;

/////////////
// Opcodes //
/////////////

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

/////////////////
// Decoded Ops //
/////////////////

// Type of decoded op
typedef enum logic [3:0] {
    OP_ALU,
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
  CC_FALSE,
  CC_TRUE,
  CC_EQ,
  CC_NE,
  CC_LT,
  CC_GE,
  CC_LTU,
  CC_GEU
} condition_code_e;

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

//////////////////////////////////
// Control and status registers //
//////////////////////////////////

typedef enum logic [11:0] {
  // F-extension
  CSR_FFLAGS          = 12'h001,
  CSR_FRM             = 12'h002,
  CSR_FCSR            = 12'h003,

  // Base ISA
  CSR_CYCLE           = 12'hC00,
  CSR_TIME            = 12'hC01,
  CSR_INSTRET         = 12'hC02,
  CSR_CYCLEH          = 12'hC80,
  CSR_TIMEH           = 12'hC81,
  CSR_INSTRETH        = 12'hC82,
  CSR_HPMCOUNTERS     = 12'b1100000?????,
  CSR_HPMCOUNTER3     = 12'hC03,
  CSR_HPMCOUNTER31    = 12'hC1F,
  CSR_HPMCOUNTER3H    = 12'hC83,
  CSR_HPMCOUNTER31H   = 12'hC9F,
  CSR_HPMCOUNTERSH    = 12'b1100100?????,

  // S-extension
  CSR_SSTATUS         = 12'h100,
  CSR_SEDELEG         = 12'h102,
  CSR_SIDELEG         = 12'h103,
  CSR_SIE             = 12'h104,
  CSR_STVEC           = 12'h105,
  CSR_SCOUNTEREN      = 12'h106,
  CSR_SSCRATCH        = 12'h140,
  CSR_SEPC            = 12'h141,
  CSR_SCAUSE          = 12'h142,
  CSR_STVAL           = 12'h143,
  CSR_SIP             = 12'h144,
  CSR_SATP            = 12'h180,

  // Machine-mode registers
  CSR_MVENDORID       = 12'hF11,
  CSR_MARCHID         = 12'hF12,
  CSR_MIMPID          = 12'hF13,
  CSR_MHARTID         = 12'hF14,
  CSR_MSTATUS         = 12'h300,
  CSR_MISA            = 12'h301,
  CSR_MEDELEG         = 12'h302,
  CSR_MIDELEG         = 12'h303,
  CSR_MIE             = 12'h304,
  CSR_MTVEC           = 12'h305,
  CSR_MCOUNTEREN      = 12'h306,
  CSR_MSCRATCH        = 12'h340,
  CSR_MEPC            = 12'h341,
  CSR_MCAUSE          = 12'h342,
  CSR_MTVAL           = 12'h343,
  CSR_MIP             = 12'h344,

  CSR_PMPCFG0         = 12'h3A0,
  CSR_PMPCFG1         = 12'h3A1,
  CSR_PMPCFG2         = 12'h3A2,
  CSR_PMPCFG3         = 12'h3A3,
  CSR_PMPADDR0        = 12'h3B0,
  CSR_PMPADDR15       = 12'h3BF,
  CSR_MCYCLE          = 12'hB00,
  CSR_MTIME           = 12'hB01,
  CSR_MINSTRET        = 12'hB02,
  CSR_MCYCLEH         = 12'hB80,
  CSR_MTIMEH          = 12'hB81,
  CSR_MINSTRETH       = 12'hB82,
  CSR_MHPMCOUNTERS    = 12'b1011000?????,
  CSR_MHPMCOUNTER3    = 12'hB03,
  CSR_MHPMCOUNTER31   = 12'hB1F,
  CSR_MHPMCOUNTERSH   = 12'b1011100?????,
  CSR_MHPMCOUNTER3H   = 12'hB83,
  CSR_MHPMCOUNTER31H  = 12'hB9F,
  CSR_MCOUNTINHIBIT   = 12'h320,
  CSR_MHPMEVENTS      = 12'b0011001?????,
  CSR_MHPMEVENT3      = 12'h323,
  CSR_MHPMEVENT31     = 12'h33F,

  // Debug/Trace Registers
  CSR_TSELECT         = 12'h7A0,
  CSR_TDATA1          = 12'h7A1,
  CSR_TDATA2          = 12'h7A2,
  CSR_TDATA3          = 12'h7A3,
  CSR_DCSR            = 12'h7B0,
  CSR_DPC             = 12'h7B1,
  CSR_DSCRATCH        = 12'h7B2
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

endpackage
