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
} opcode;

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
} csr_t;

endpackage