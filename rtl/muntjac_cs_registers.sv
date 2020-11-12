module muntjac_cs_registers import muntjac_pkg::*; # (
  parameter bit RV64D = 0,
  parameter bit RV64F = 0,
  parameter AsidLen = 16,

  // Number of bits of physical address supported. This must not exceed 56.
  parameter PhysAddrLen = 56,

  // Number of bits of virtual address supported. This currently must be 39.
  parameter VirtAddrLen = 39
) (
    // Clock and reset
    input  logic               clk_i,
    input  logic               rst_ni,

    // Hart ID
    input  logic [63:0]        hart_id_i,

    // Privilege mode
    output priv_lvl_e          priv_mode_o,
    output priv_lvl_e          priv_mode_lsu_o,

    // CSR Access check port (in ID stage)
    input  csr_num_e           check_addr_i,
    input  csr_op_e            check_op_i,
    output logic               check_illegal_o,

    // Interface to registers (SRAM like)
    input  csr_num_e           csr_addr_i,
    input  logic [63:0]        csr_wdata_i,
    input  csr_op_e            csr_op_i,
    input                      csr_op_en_i,
    output logic [63:0]        csr_rdata_o,

`ifdef TRACE_ENABLE
    output logic [63:0]        csr_wdata_o,
`endif

    // Interrupts
    input  logic               irq_software_m_i,
    input  logic               irq_timer_m_i,
    input  logic               irq_external_m_i,
    input  logic               irq_external_s_i,
    output logic               irq_pending_o,
    output logic               irq_valid_o,
    output exc_cause_e         irq_cause_o,

    // CSR exports
    output logic [63:0]        satp_o,
    output status_t            status_o,
    output logic [2:0]         frm_o,

    // Exception
    input  logic               ex_valid_i,
    input  exception_t         ex_exception_i,
    input  logic [63:0]        ex_epc_i,
    output logic [63:0]        ex_tvec_o,

    // Exception return
    input  logic               er_valid_i,
    input  priv_lvl_e          er_prv_i,
    output logic [63:0]        er_epc_o,

    // Floating-point register status tracker
    input  logic               make_fs_dirty_i,
    input  logic [4:0]         set_fflags_i,

    // Performance counters
    input  logic               instr_ret_i
);

  // Number of bits required to recover a legal full 64-bit address.
  // This requires one extra bit for physical address because we need to perform sign extension.
  localparam LogicSextAddrLen = PhysAddrLen >= VirtAddrLen ? PhysAddrLen + 1 : VirtAddrLen;

  // misa
  localparam logic [63:0] MISA_VALUE =
      (1                 <<  0)  // A - Atomic Instructions extension
    | (1                 <<  2)  // C - Compressed extension
    | (64'(RV64D)        <<  3)  // D - Double precision floating-point extension
    | (0                 <<  4)  // E - RV32E base ISA
    | (64'(RV64F)        <<  5)  // F - Single precision floating-point extension
    | (1                 <<  8)  // I - RV32I/64I/128I base ISA
    | (1                 << 12)  // M - Integer Multiply/Divide extension
    | (0                 << 13)  // N - User level interrupts supported
    | (1                 << 18)  // S - Supervisor mode implemented
    | (1                 << 20)  // U - User mode implemented
    | (0                 << 23)  // X - Non-standard extensions present
    | (64'(CSR_MISA_MXL) << 62); // M-XLEN

  //////////////////
  // Control CSRs //
  //////////////////

  priv_lvl_e priv_lvl_q, priv_lvl_d;
  status_t  mstatus_q, mstatus_d;

  // Address Translation
  logic satp_mode_q, satp_mode_d;
  logic [AsidLen-1:0] satp_asid_q, satp_asid_d;
  logic [PhysAddrLen-12-1:0] satp_ppn_q, satp_ppn_d;

  assign status_o = mstatus_q;
  assign priv_mode_o = priv_lvl_q;
  assign priv_mode_lsu_o = mstatus_q.mprv ? mstatus_q.mpp : priv_lvl_q;
  assign satp_o = {satp_mode_q, 3'b0, 16'(satp_asid_q), 44'(satp_ppn_q)};

  ////////////////////
  // Interrupt CSRs //
  ////////////////////

  logic ssip_q, ssip_d;
  logic stip_q, stip_d;
  logic seip_q, seip_d;

  irqs_t mip;
  assign mip.irq_software_s = ssip_q;
  assign mip.irq_software_m = irq_software_m_i;
  assign mip.irq_timer_s    = stip_q;
  assign mip.irq_timer_m    = irq_timer_m_i;
  assign mip.irq_external_s = irq_external_s_i || seip_q;
  assign mip.irq_external_m = irq_external_m_i;

  irqs_t mie_q, mie_d;
  irqs_t mideleg_q, mideleg_d;
  logic [15:0] medeleg_q, medeleg_d;

  function logic is_delegated(input exc_cause_e cause);
    unique case (cause)
      EXC_CAUSE_IRQ_SOFTWARE_S    : return mideleg_q.irq_software_s;
      EXC_CAUSE_IRQ_TIMER_S       : return mideleg_q.irq_timer_s;
      EXC_CAUSE_IRQ_EXTERNAL_S    : return mideleg_q.irq_external_s;
      EXC_CAUSE_INSTR_ACCESS_FAULT: return medeleg_q[EXC_CAUSE_INSTR_ACCESS_FAULT];
      EXC_CAUSE_ILLEGAL_INSN      : return medeleg_q[EXC_CAUSE_ILLEGAL_INSN      ];
      EXC_CAUSE_BREAKPOINT        : return medeleg_q[EXC_CAUSE_BREAKPOINT        ];
      EXC_CAUSE_LOAD_MISALIGN     : return medeleg_q[EXC_CAUSE_LOAD_MISALIGN     ];
      EXC_CAUSE_LOAD_ACCESS_FAULT : return medeleg_q[EXC_CAUSE_LOAD_ACCESS_FAULT ];
      EXC_CAUSE_STORE_MISALIGN    : return medeleg_q[EXC_CAUSE_STORE_MISALIGN    ];
      EXC_CAUSE_STORE_ACCESS_FAULT: return medeleg_q[EXC_CAUSE_STORE_ACCESS_FAULT];
      EXC_CAUSE_ECALL_UMODE       : return medeleg_q[EXC_CAUSE_ECALL_UMODE       ];
      EXC_CAUSE_ECALL_SMODE       : return medeleg_q[EXC_CAUSE_ECALL_SMODE       ];
      EXC_CAUSE_INSTR_PAGE_FAULT  : return medeleg_q[EXC_CAUSE_INSTR_PAGE_FAULT  ];
      EXC_CAUSE_LOAD_PAGE_FAULT   : return medeleg_q[EXC_CAUSE_LOAD_PAGE_FAULT   ];
      EXC_CAUSE_STORE_PAGE_FAULT  : return medeleg_q[EXC_CAUSE_STORE_PAGE_FAULT  ];
      default: return 1'b0;
    endcase
  endfunction

  // Here we use irq_pending to mean the IRQs that are available and enabled, while
  // irq_valid means the pending IRQs that could be processed now (aka not delegated to lower
  // privilege level and current privilege level has interrupt enabled).
  irqs_t irq_pending;
  irqs_t irq_valid_m;
  irqs_t irq_valid_s;
  irqs_t irq_valid;

  assign irq_pending = mip & mie_q;
  assign irq_pending_o = |irq_pending;

  assign irq_valid_m = priv_lvl_q != PRIV_LVL_M || mstatus_q.mie ? irq_pending & ~mideleg_q : '0;
  assign irq_valid_s = priv_lvl_q == PRIV_LVL_U || (priv_lvl_q == PRIV_LVL_S && mstatus_q.sie) ? irq_pending & mideleg_q : 0;
  assign irq_valid = irq_valid_m | irq_valid_s;
  assign irq_valid_o = |irq_valid;

  always_comb begin
    irq_cause_o = exc_cause_e'('x);
    priority case (1'b1)
      irq_pending.irq_external_m: irq_cause_o = EXC_CAUSE_IRQ_EXTERNAL_M;
      irq_pending.irq_software_m: irq_cause_o = EXC_CAUSE_IRQ_SOFTWARE_M;
      irq_pending.irq_timer_m   : irq_cause_o = EXC_CAUSE_IRQ_TIMER_M;
      irq_pending.irq_external_s: irq_cause_o = EXC_CAUSE_IRQ_EXTERNAL_S;
      irq_pending.irq_software_s: irq_cause_o = EXC_CAUSE_IRQ_SOFTWARE_S;
      irq_pending.irq_timer_s   : irq_cause_o = EXC_CAUSE_IRQ_TIMER_S;
      default:;
    endcase
  end

  ////////////////////////
  // Trap Handling CSRs //
  ////////////////////////

  logic [63:0]                 mscratch_q, mscratch_d;
  logic [63:0]                 mepc_q, mepc_d;
  exc_cause_e                  mcause_q, mcause_d;
  logic [LogicSextAddrLen-1:0] mtvec_q, mtvec_d;
  logic [63:0]                 mtval_q, mtval_d;

  logic [63:0]                 sscratch_q, sscratch_d;
  logic [63:0]                 sepc_q, sepc_d;
  exc_cause_e                  scause_q, scause_d;
  logic [LogicSextAddrLen-1:0] stvec_q, stvec_d;
  logic [63:0]                 stval_q, stval_d;

  ////////////////
  // Other CSRs //
  ////////////////

  // User Floating-Point CSRs.
  logic [4:0] fflags_q, fflags_d;
  logic [2:0] frm_q, frm_d;
  assign frm_o = frm_q;

  // Counter Enable
  logic [2:0] mcounteren_q, mcounteren_d;
  logic [2:0] scounteren_q, scounteren_d;

  // Hardware performance counters
  logic mcycle_we;
  logic minstret_we;
  logic [63:0] mcycle_q, mcycle_d;
  logic [63:0] minstret_q, minstret_d;

  //////////////////////////////
  // Privilege checking logic //
  //////////////////////////////

  logic illegal;
  logic illegal_readonly;
  logic illegal_prv;

  always_comb begin
    illegal = 1'b0;
    illegal_readonly = check_addr_i[11:10] == 2'b11 && check_op_i != CSR_OP_READ;
    illegal_prv = check_addr_i[9:8] > priv_lvl_q;

    unique case (check_addr_i)
      CSR_FFLAGS, CSR_FRM, CSR_FCSR: if (!RV64F || mstatus_q.fs == 2'b00) illegal = 1'b1;
      CSR_CYCLE: if (!((priv_lvl_q > PRIV_LVL_S || mcounteren_q[0]) && (priv_lvl_q > PRIV_LVL_U || scounteren_q[0]))) illegal = 1'b1;
      CSR_INSTRET: if (!((priv_lvl_q > PRIV_LVL_S || mcounteren_q[2]) && (priv_lvl_q > PRIV_LVL_U || scounteren_q[2]))) illegal = 1'b1;
      CSR_SSTATUS, CSR_SIE, CSR_STVEC, CSR_SCOUNTEREN:;
      CSR_SSCRATCH, CSR_SEPC, CSR_SCAUSE, CSR_STVAL, CSR_SIP:;
      CSR_SATP: if (priv_lvl_q != PRIV_LVL_M && mstatus_q.tvm) illegal = 1'b1;
      CSR_MVENDORID, CSR_MARCHID, CSR_MIMPID, CSR_MHARTID:;
      CSR_MSTATUS, CSR_MISA, CSR_MEDELEG, CSR_MIDELEG, CSR_MIE, CSR_MTVEC, CSR_MCOUNTEREN:;
      CSR_MSCRATCH, CSR_MEPC, CSR_MCAUSE, CSR_MTVAL, CSR_MIP:;
      CSR_MCYCLE,
      CSR_MINSTRET,
      CSR_MHPMCOUNTER3,
      CSR_MHPMCOUNTER4,  CSR_MHPMCOUNTER5,  CSR_MHPMCOUNTER6,  CSR_MHPMCOUNTER7,
      CSR_MHPMCOUNTER8,  CSR_MHPMCOUNTER9,  CSR_MHPMCOUNTER10, CSR_MHPMCOUNTER11,
      CSR_MHPMCOUNTER12, CSR_MHPMCOUNTER13, CSR_MHPMCOUNTER14, CSR_MHPMCOUNTER15,
      CSR_MHPMCOUNTER16, CSR_MHPMCOUNTER17, CSR_MHPMCOUNTER18, CSR_MHPMCOUNTER19,
      CSR_MHPMCOUNTER20, CSR_MHPMCOUNTER21, CSR_MHPMCOUNTER22, CSR_MHPMCOUNTER23,
      CSR_MHPMCOUNTER24, CSR_MHPMCOUNTER25, CSR_MHPMCOUNTER26, CSR_MHPMCOUNTER27,
      CSR_MHPMCOUNTER28, CSR_MHPMCOUNTER29, CSR_MHPMCOUNTER30, CSR_MHPMCOUNTER31,
      CSR_MHPMEVENT3,
      CSR_MHPMEVENT4,  CSR_MHPMEVENT5,  CSR_MHPMEVENT6,  CSR_MHPMEVENT7,
      CSR_MHPMEVENT8,  CSR_MHPMEVENT9,  CSR_MHPMEVENT10, CSR_MHPMEVENT11,
      CSR_MHPMEVENT12, CSR_MHPMEVENT13, CSR_MHPMEVENT14, CSR_MHPMEVENT15,
      CSR_MHPMEVENT16, CSR_MHPMEVENT17, CSR_MHPMEVENT18, CSR_MHPMEVENT19,
      CSR_MHPMEVENT20, CSR_MHPMEVENT21, CSR_MHPMEVENT22, CSR_MHPMEVENT23,
      CSR_MHPMEVENT24, CSR_MHPMEVENT25, CSR_MHPMEVENT26, CSR_MHPMEVENT27,
      CSR_MHPMEVENT28, CSR_MHPMEVENT29, CSR_MHPMEVENT30, CSR_MHPMEVENT31,
      CSR_MCOUNTINHIBIT:;
      default: illegal = 1'b1;
    endcase
    check_illegal_o = illegal | illegal_readonly | illegal_prv;
  end

  ////////////////
  // Read logic //
  ////////////////

  logic [63:0] csr_rdata_int;

  always_comb begin
    csr_rdata_int = '0;

    unique case (csr_addr_i)
      // User Trap Setup CSRs not supported
      // User Trap Handling CSRs not supported

      // User Floating-point CSRs
      CSR_FFLAGS: if (RV64F) csr_rdata_int = {59'b0, fflags_q};
      CSR_FRM: if (RV64F) csr_rdata_int = {61'b0, frm_q};
      CSR_FCSR: if (RV64F) csr_rdata_int = {56'b0, frm_q, fflags_q};

      // User Counter/Timers CSRs
      CSR_CYCLE: csr_rdata_int = mcycle_q;
      CSR_INSTRET: csr_rdata_int = minstret_q;
      // TIME and HPMCOUNTERS does not exist MCOUNTEREN bits are hardwired to zero.

      CSR_SSTATUS: begin
        csr_rdata_int = '0;
        csr_rdata_int[CSR_MSTATUS_SIE_BIT]                              = mstatus_q.sie;
        csr_rdata_int[CSR_MSTATUS_SPIE_BIT]                             = mstatus_q.spie;
        csr_rdata_int[CSR_MSTATUS_SPP_BIT]                              = mstatus_q.spp;
        csr_rdata_int[CSR_MSTATUS_FS_BIT_HIGH:CSR_MSTATUS_FS_BIT_LOW]   = mstatus_q.fs;
        csr_rdata_int[CSR_MSTATUS_SUM_BIT]                              = mstatus_q.sum;
        csr_rdata_int[CSR_MSTATUS_MXR_BIT]                              = mstatus_q.mxr;
        csr_rdata_int[CSR_MSTATUS_UXL_BIT_HIGH:CSR_MSTATUS_UXL_BIT_LOW] = CSR_MSTATUS_UXL;
        csr_rdata_int[CSR_MSTATUS_SD_BIT]                               = &mstatus_q.fs;
      end
      // SEDELEG does not exist.
      // SIDELEG does not exist.
      CSR_SIE: begin
        csr_rdata_int = '0;
        if (mideleg_q.irq_software_s) csr_rdata_int[CSR_SSIX_BIT] = mie_q.irq_software_s;
        if (mideleg_q.irq_timer_s   ) csr_rdata_int[CSR_STIX_BIT] = mie_q.irq_timer_s;
        if (mideleg_q.irq_external_s) csr_rdata_int[CSR_SEIX_BIT] = mie_q.irq_external_s;
      end
      CSR_STVEC: csr_rdata_int = 64'(signed'(stvec_q));
      CSR_SCOUNTEREN: csr_rdata_int = {61'b0, scounteren_q};

      CSR_SSCRATCH: csr_rdata_int = sscratch_q;
      CSR_SEPC: csr_rdata_int = sepc_q;
      CSR_SCAUSE: csr_rdata_int = {scause_q[4], 59'b0, scause_q[3:0]};
      CSR_STVAL: csr_rdata_int = stval_q;
      CSR_SIP: begin
        csr_rdata_int = '0;
        if (mideleg_q.irq_software_s) csr_rdata_int[CSR_SSIX_BIT] = mip.irq_software_s;
        if (mideleg_q.irq_timer_s   ) csr_rdata_int[CSR_STIX_BIT] = mip.irq_timer_s;
        if (mideleg_q.irq_external_s) csr_rdata_int[CSR_SEIX_BIT] = seip_q;
      end

      CSR_SATP: csr_rdata_int = satp_o;

      CSR_MVENDORID, CSR_MARCHID, CSR_MIMPID: csr_rdata_int = '0;
      CSR_MHARTID: csr_rdata_int = hart_id_i;

      CSR_MSTATUS: begin
        csr_rdata_int = '0;
        csr_rdata_int[CSR_MSTATUS_SIE_BIT]                              = mstatus_q.sie;
        csr_rdata_int[CSR_MSTATUS_MIE_BIT]                              = mstatus_q.mie;
        csr_rdata_int[CSR_MSTATUS_SPIE_BIT]                             = mstatus_q.spie;
        csr_rdata_int[CSR_MSTATUS_MPIE_BIT]                             = mstatus_q.mpie;
        csr_rdata_int[CSR_MSTATUS_SPP_BIT]                              = mstatus_q.spp;
        csr_rdata_int[CSR_MSTATUS_MPP_BIT_HIGH:CSR_MSTATUS_MPP_BIT_LOW] = mstatus_q.mpp;
        csr_rdata_int[CSR_MSTATUS_FS_BIT_HIGH:CSR_MSTATUS_FS_BIT_LOW]   = mstatus_q.fs;
        csr_rdata_int[CSR_MSTATUS_MPRV_BIT]                             = mstatus_q.mprv;
        csr_rdata_int[CSR_MSTATUS_SUM_BIT]                              = mstatus_q.sum;
        csr_rdata_int[CSR_MSTATUS_MXR_BIT]                              = mstatus_q.mxr;
        csr_rdata_int[CSR_MSTATUS_TVM_BIT]                              = mstatus_q.tvm;
        csr_rdata_int[CSR_MSTATUS_TW_BIT]                               = mstatus_q.tw;
        csr_rdata_int[CSR_MSTATUS_TSR_BIT]                              = mstatus_q.tsr;
        csr_rdata_int[CSR_MSTATUS_UXL_BIT_HIGH:CSR_MSTATUS_UXL_BIT_LOW] = CSR_MSTATUS_UXL;
        csr_rdata_int[CSR_MSTATUS_SXL_BIT_HIGH:CSR_MSTATUS_SXL_BIT_LOW] = CSR_MSTATUS_SXL;
        csr_rdata_int[CSR_MSTATUS_SD_BIT]                               = &mstatus_q.fs;
      end

      // misa
      CSR_MISA: csr_rdata_int = MISA_VALUE;

      CSR_MEDELEG: csr_rdata_int = {48'b0, medeleg_q};
      CSR_MIDELEG: begin
        csr_rdata_int = '0;
        csr_rdata_int[CSR_SSIX_BIT] = mideleg_q.irq_software_s;
        csr_rdata_int[CSR_STIX_BIT] = mideleg_q.irq_timer_s;
        csr_rdata_int[CSR_SEIX_BIT] = mideleg_q.irq_external_s;
      end
      CSR_MIE: begin
        csr_rdata_int = '0;
        csr_rdata_int[CSR_SSIX_BIT] = mie_q.irq_software_s;
        csr_rdata_int[CSR_MSIX_BIT] = mie_q.irq_software_m;
        csr_rdata_int[CSR_STIX_BIT] = mie_q.irq_timer_s;
        csr_rdata_int[CSR_MTIX_BIT] = mie_q.irq_timer_m;
        csr_rdata_int[CSR_SEIX_BIT] = mie_q.irq_external_s;
        csr_rdata_int[CSR_MEIX_BIT] = mie_q.irq_external_m;
      end
      CSR_MTVEC: csr_rdata_int = 64'(signed'(mtvec_q));
      CSR_MCOUNTEREN: csr_rdata_int = {61'b0, mcounteren_q};

      CSR_MSCRATCH: csr_rdata_int = mscratch_q;
      CSR_MEPC: csr_rdata_int = mepc_q;
      CSR_MCAUSE: csr_rdata_int = {mcause_q[4], 59'b0, mcause_q[3:0]};
      CSR_MTVAL: csr_rdata_int = mtval_q;
      CSR_MIP: begin
        csr_rdata_int = '0;
        csr_rdata_int[CSR_SSIX_BIT] = mip.irq_software_s;
        csr_rdata_int[CSR_MSIX_BIT] = mip.irq_software_m;
        csr_rdata_int[CSR_STIX_BIT] = mip.irq_timer_s;
        csr_rdata_int[CSR_MTIX_BIT] = mip.irq_timer_m;
        csr_rdata_int[CSR_SEIX_BIT] = seip_q;
        csr_rdata_int[CSR_MEIX_BIT] = mip.irq_external_m;
      end

      CSR_MCYCLE: csr_rdata_int = mcycle_q;
      CSR_MINSTRET: csr_rdata_int = minstret_q;

      // We don't yet support additional counters nor inhibition.
      CSR_MHPMCOUNTER3,
      CSR_MHPMCOUNTER4,  CSR_MHPMCOUNTER5,  CSR_MHPMCOUNTER6,  CSR_MHPMCOUNTER7,
      CSR_MHPMCOUNTER8,  CSR_MHPMCOUNTER9,  CSR_MHPMCOUNTER10, CSR_MHPMCOUNTER11,
      CSR_MHPMCOUNTER12, CSR_MHPMCOUNTER13, CSR_MHPMCOUNTER14, CSR_MHPMCOUNTER15,
      CSR_MHPMCOUNTER16, CSR_MHPMCOUNTER17, CSR_MHPMCOUNTER18, CSR_MHPMCOUNTER19,
      CSR_MHPMCOUNTER20, CSR_MHPMCOUNTER21, CSR_MHPMCOUNTER22, CSR_MHPMCOUNTER23,
      CSR_MHPMCOUNTER24, CSR_MHPMCOUNTER25, CSR_MHPMCOUNTER26, CSR_MHPMCOUNTER27,
      CSR_MHPMCOUNTER28, CSR_MHPMCOUNTER29, CSR_MHPMCOUNTER30, CSR_MHPMCOUNTER31: csr_rdata_int = '0;
      CSR_MHPMEVENT3,
      CSR_MHPMEVENT4,  CSR_MHPMEVENT5,  CSR_MHPMEVENT6,  CSR_MHPMEVENT7,
      CSR_MHPMEVENT8,  CSR_MHPMEVENT9,  CSR_MHPMEVENT10, CSR_MHPMEVENT11,
      CSR_MHPMEVENT12, CSR_MHPMEVENT13, CSR_MHPMEVENT14, CSR_MHPMEVENT15,
      CSR_MHPMEVENT16, CSR_MHPMEVENT17, CSR_MHPMEVENT18, CSR_MHPMEVENT19,
      CSR_MHPMEVENT20, CSR_MHPMEVENT21, CSR_MHPMEVENT22, CSR_MHPMEVENT23,
      CSR_MHPMEVENT24, CSR_MHPMEVENT25, CSR_MHPMEVENT26, CSR_MHPMEVENT27,
      CSR_MHPMEVENT28, CSR_MHPMEVENT29, CSR_MHPMEVENT30, CSR_MHPMEVENT31: csr_rdata_int = '0;
      CSR_MCOUNTINHIBIT: csr_rdata_int = '0;
      default: csr_rdata_int = 'x;
    endcase

    csr_rdata_o = csr_rdata_int;
    unique case (csr_addr_i)
      CSR_SIP: begin
        if (mideleg_q.irq_external_s) csr_rdata_o[CSR_SEIX_BIT] = mip.irq_external_s;
      end
      CSR_MIP: begin
        csr_rdata_o[CSR_SEIX_BIT] = mip.irq_external_s;
      end
      default:;
    endcase
  end

  /////////////////
  // Write logic //
  /////////////////

  logic [63:0] csr_wdata_int;

`ifdef TRACE_ENABLE
  assign csr_wdata_o = csr_wdata_int;
`endif

  // Perform CSR operation
  always_comb begin
    unique case (csr_op_i)
      CSR_OP_WRITE: csr_wdata_int =  csr_wdata_i;
      CSR_OP_SET:   csr_wdata_int =  csr_wdata_i | csr_rdata_int;
      CSR_OP_CLEAR: csr_wdata_int = ~csr_wdata_i & csr_rdata_int;
      default:      csr_wdata_int = 'x;
    endcase
  end

  // Write and exception handling logic
  always_comb begin
    ssip_d = ssip_q;
    stip_d = stip_q;
    seip_d = seip_q;
    mie_d = mie_q;
    medeleg_d = medeleg_q;
    mideleg_d = mideleg_q;

    mscratch_d = mscratch_q;
    mepc_d = mepc_q;
    mcause_d = mcause_q;
    mtval_d = mtval_q;
    mtvec_d = mtvec_q;
    sscratch_d = sscratch_q;
    sepc_d = sepc_q;
    scause_d = scause_q;
    stval_d = stval_q;
    stvec_d = stvec_q;
    satp_mode_d = satp_mode_q;
    satp_asid_d = satp_asid_q;
    satp_ppn_d = satp_ppn_q;

    priv_lvl_d = priv_lvl_q;
    mstatus_d = mstatus_q;

    fflags_d = fflags_q;
    frm_d = frm_q;

    mcounteren_d = mcounteren_q;
    scounteren_d = scounteren_q;

    mcycle_we = 1'b0;
    minstret_we = 1'b0;

    ex_tvec_o = 'x;
    er_epc_o = 'x;

    if (RV64F) begin
      if (make_fs_dirty_i) begin
        mstatus_d.fs = 2'b11;
      end

      if (|set_fflags_i) begin
        fflags_d = fflags_q | set_fflags_i;
        mstatus_d.fs = 2'b11;
      end
    end

    unique case (1'b1)
      ex_valid_i: begin
        // Delegate to S-mode if we have an exception on S/U mode and delegation is enabled.
        if (priv_lvl_q != PRIV_LVL_M && is_delegated(ex_exception_i.cause)) begin
          ex_tvec_o = 64'(signed'(stvec_q));

          scause_d = ex_exception_i.cause;
          stval_d = ex_exception_i.tval;
          sepc_d = ex_epc_i;

          priv_lvl_d = PRIV_LVL_S;
          mstatus_d.sie = 1'b0;
          mstatus_d.spie = mstatus_q.sie;
          mstatus_d.spp = priv_lvl_q[0];
        end else begin
          // Exception handling vector
          ex_tvec_o = 64'(signed'(mtvec_q));

          // Exception info registers
          mcause_d = ex_exception_i.cause;
          mtval_d = ex_exception_i.tval;
          mepc_d = ex_epc_i;

          // Switch privilege level and set mstatus
          priv_lvl_d = PRIV_LVL_M;
          mstatus_d.mie = 1'b0;
          mstatus_d.mpie = mstatus_q.mie;
          mstatus_d.mpp = priv_lvl_q;
        end
      end
      er_valid_i: begin
        if (er_prv_i != PRIV_LVL_M) begin
          er_epc_o = sepc_q;

          priv_lvl_d = mstatus_q.spp ? PRIV_LVL_S : PRIV_LVL_U;
          mstatus_d.spie = 1'b1;
          mstatus_d.sie = mstatus_q.spie;
          mstatus_d.spp = 1'b0;
        end else begin
          er_epc_o = mepc_q;

          priv_lvl_d = mstatus_q.mpp;
          mstatus_d.mpie = 1'b1;
          mstatus_d.mie = mstatus_q.mpie;
          mstatus_d.mpp = PRIV_LVL_U;
          // Clear MPRV when leaving M-mode
          if (mstatus_q.mpp != PRIV_LVL_M) mstatus_d.mprv = 1'b0;
        end
      end
      csr_op_en_i: begin
        if (csr_op_i != CSR_OP_READ) begin
          unique case (csr_addr_i)
            // User Trap Setup CSRs not supported
            // User Trap Handling CSRs not supported

            // User Floating-point CSRs
            CSR_FFLAGS: if (RV64F) begin
              fflags_d = csr_wdata_int[4:0];
              mstatus_d.fs = 2'b11;
            end
            CSR_FRM: if (RV64F) begin
              frm_d = csr_wdata_int[2:0];
              mstatus_d.fs = 2'b11;
            end
            CSR_FCSR: if (RV64F) begin
              fflags_d = csr_wdata_int[4:0];
              frm_d = csr_wdata_int[7:5];
              mstatus_d.fs = 2'b11;
            end

            CSR_SSTATUS: begin
              mstatus_d.sie  = csr_wdata_int[CSR_MSTATUS_SIE_BIT];
              mstatus_d.spie = csr_wdata_int[CSR_MSTATUS_SPIE_BIT];
              mstatus_d.spp  = csr_wdata_int[CSR_MSTATUS_SPP_BIT];
              mstatus_d.fs   = csr_wdata_int[CSR_MSTATUS_FS_BIT_HIGH:CSR_MSTATUS_FS_BIT_LOW];
              mstatus_d.sum  = csr_wdata_int[CSR_MSTATUS_SUM_BIT];
              mstatus_d.mxr  = csr_wdata_int[CSR_MSTATUS_MXR_BIT];
            end
            // SEDELEG does not exist.
            // SIDELEG does not exist.
            CSR_SIE: begin
              if (mideleg_q.irq_software_s) mie_d.irq_software_s = csr_wdata_int[CSR_SSIX_BIT];
              if (mideleg_q.irq_timer_s   ) mie_d.irq_timer_s    = csr_wdata_int[CSR_STIX_BIT];
              if (mideleg_q.irq_external_s) mie_d.irq_external_s = csr_wdata_int[CSR_SEIX_BIT];
            end
            CSR_STVEC: stvec_d = {csr_wdata_int[LogicSextAddrLen-1:2], 2'b0};
            CSR_SCOUNTEREN: scounteren_d = csr_wdata_int[2:0] & 3'b101;

            CSR_SSCRATCH: sscratch_d = csr_wdata_int;
            CSR_SEPC: sepc_d = {csr_wdata_int[63:1], 1'b0};
            CSR_SCAUSE: begin
              scause_d = exc_cause_e'({csr_wdata_int[63], csr_wdata_int[3:0]});
            end
            CSR_STVAL: stval_d = csr_wdata_int;
            CSR_SIP: begin
              if (mideleg_q.irq_software_s) ssip_d = csr_wdata_int[CSR_SSIX_BIT];
            end
            CSR_SATP: begin
              satp_mode_d = csr_wdata_int[63];
              satp_asid_d = csr_wdata_int[44 +: AsidLen];
              satp_ppn_d  = csr_wdata_int[0 +: PhysAddrLen-12];
            end

            CSR_MSTATUS: begin
              mstatus_d.sie  = csr_wdata_int[CSR_MSTATUS_SIE_BIT];
              mstatus_d.mie  = csr_wdata_int[CSR_MSTATUS_MIE_BIT];
              mstatus_d.spie = csr_wdata_int[CSR_MSTATUS_SPIE_BIT];
              mstatus_d.mpie = csr_wdata_int[CSR_MSTATUS_MPIE_BIT];
              mstatus_d.spp  = csr_wdata_int[CSR_MSTATUS_SPP_BIT];
              mstatus_d.mpp  = priv_lvl_e'(csr_wdata_int[CSR_MSTATUS_MPP_BIT_HIGH:CSR_MSTATUS_MPP_BIT_LOW]);
              mstatus_d.fs   = csr_wdata_int[CSR_MSTATUS_FS_BIT_HIGH:CSR_MSTATUS_FS_BIT_LOW];
              mstatus_d.mprv = csr_wdata_int[CSR_MSTATUS_MPRV_BIT];
              mstatus_d.sum  = csr_wdata_int[CSR_MSTATUS_SUM_BIT];
              mstatus_d.mxr  = csr_wdata_int[CSR_MSTATUS_MXR_BIT];
              mstatus_d.tvm  = csr_wdata_int[CSR_MSTATUS_TVM_BIT];
              mstatus_d.tw   = csr_wdata_int[CSR_MSTATUS_TW_BIT];
              mstatus_d.tsr  = csr_wdata_int[CSR_MSTATUS_TSR_BIT];
              // Convert illegal values to M-mode
              if (mstatus_d.mpp == PRIV_LVL_H) begin
                mstatus_d.mpp = PRIV_LVL_M;
              end
            end
            CSR_MISA:;
            CSR_MEDELEG: begin
              // This exeception will not happen with C-ext enabled, but riscv-isa-test seems to
              // require it.
              medeleg_d[EXC_CAUSE_INSN_ADDR_MISA    ] = csr_wdata_int[EXC_CAUSE_INSN_ADDR_MISA    ];
              medeleg_d[EXC_CAUSE_INSTR_ACCESS_FAULT] = csr_wdata_int[EXC_CAUSE_INSTR_ACCESS_FAULT];
              medeleg_d[EXC_CAUSE_ILLEGAL_INSN      ] = csr_wdata_int[EXC_CAUSE_ILLEGAL_INSN      ];
              medeleg_d[EXC_CAUSE_BREAKPOINT        ] = csr_wdata_int[EXC_CAUSE_BREAKPOINT        ];
              medeleg_d[EXC_CAUSE_LOAD_MISALIGN     ] = csr_wdata_int[EXC_CAUSE_LOAD_MISALIGN     ];
              medeleg_d[EXC_CAUSE_LOAD_ACCESS_FAULT ] = csr_wdata_int[EXC_CAUSE_LOAD_ACCESS_FAULT ];
              medeleg_d[EXC_CAUSE_STORE_MISALIGN    ] = csr_wdata_int[EXC_CAUSE_STORE_MISALIGN    ];
              medeleg_d[EXC_CAUSE_STORE_ACCESS_FAULT] = csr_wdata_int[EXC_CAUSE_STORE_ACCESS_FAULT];
              medeleg_d[EXC_CAUSE_ECALL_UMODE       ] = csr_wdata_int[EXC_CAUSE_ECALL_UMODE       ];
              medeleg_d[EXC_CAUSE_ECALL_SMODE       ] = csr_wdata_int[EXC_CAUSE_ECALL_SMODE       ];
              medeleg_d[EXC_CAUSE_INSTR_PAGE_FAULT  ] = csr_wdata_int[EXC_CAUSE_INSTR_PAGE_FAULT  ];
              medeleg_d[EXC_CAUSE_LOAD_PAGE_FAULT   ] = csr_wdata_int[EXC_CAUSE_LOAD_PAGE_FAULT   ];
              medeleg_d[EXC_CAUSE_STORE_PAGE_FAULT  ] = csr_wdata_int[EXC_CAUSE_STORE_PAGE_FAULT  ];
            end
            CSR_MIDELEG: begin
              mideleg_d.irq_software_s = csr_wdata_int[CSR_SSIX_BIT];
              mideleg_d.irq_timer_s    = csr_wdata_int[CSR_STIX_BIT];
              mideleg_d.irq_external_s = csr_wdata_int[CSR_SEIX_BIT];
            end
            CSR_MIE: begin
              mie_d.irq_software_s = csr_wdata_int[CSR_SSIX_BIT];
              mie_d.irq_software_m = csr_wdata_int[CSR_MSIX_BIT];
              mie_d.irq_timer_s    = csr_wdata_int[CSR_STIX_BIT];
              mie_d.irq_timer_m    = csr_wdata_int[CSR_MTIX_BIT];
              mie_d.irq_external_s = csr_wdata_int[CSR_SEIX_BIT];
              mie_d.irq_external_m = csr_wdata_int[CSR_MEIX_BIT];
            end
            CSR_MTVEC: mtvec_d = {csr_wdata_int[LogicSextAddrLen-1:2], 2'b0};
            CSR_MCOUNTEREN: mcounteren_d = csr_wdata_int[2:0] & 3'b101;

            CSR_MSCRATCH: mscratch_d = csr_wdata_int;
            CSR_MEPC: mepc_d = {csr_wdata_int[63:1], 1'b0};
            CSR_MCAUSE: begin
                mcause_d = exc_cause_e'({csr_wdata_int[63], csr_wdata_int[3:0]});
            end
            CSR_MTVAL: mtval_d = csr_wdata_int;
            CSR_MIP: begin
              stip_d = csr_wdata_int[CSR_STIX_BIT];
              ssip_d = csr_wdata_int[CSR_SSIX_BIT];
              seip_d = csr_wdata_int[CSR_SEIX_BIT];
            end

            CSR_MCYCLE: mcycle_we = 1'b1;
            CSR_MINSTRET: minstret_we = 1'b1;
            default:;
          endcase
        end
      end
      default:;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      ssip_q <= '0;
      stip_q <= '0;
      seip_q <= '0;
      mie_q <= '0;
      medeleg_q <= '0;
      mideleg_q <= '0;

      mscratch_q <= '0;
      mepc_q <= '0;
      mcause_q <= exc_cause_e'('0);
      mtval_q <= '0;
      mtvec_q <= '0;
      sscratch_q <= '0;
      sepc_q <= '0;
      scause_q <= exc_cause_e'('0);
      stval_q <= '0;
      stvec_q <= '0;

      priv_lvl_q <= PRIV_LVL_M;
      mstatus_q <= status_t'('0);
      satp_mode_q <= '0;
      satp_asid_q <= '0;
      satp_ppn_q <= '0;

      fflags_q <= '0;
      frm_q <= '0;

      mcounteren_q <= '0;
      scounteren_q <= '0;
    end
    else begin
      ssip_q <= ssip_d;
      stip_q <= stip_d;
      seip_q <= seip_d;
      mie_q <= mie_d;
      medeleg_q <= medeleg_d;
      mideleg_q <= mideleg_d;

      mscratch_q <= mscratch_d;
      mepc_q <= mepc_d;
      mcause_q <= mcause_d;
      mtval_q <= mtval_d;
      mtvec_q <= mtvec_d;
      sscratch_q <= sscratch_d;
      sepc_q <= sepc_d;
      scause_q <= scause_d;
      stval_q <= stval_d;
      stvec_q <= stvec_d;

      priv_lvl_q <= priv_lvl_d;
      mstatus_q <= mstatus_d;
      satp_mode_q <= satp_mode_d;
      satp_asid_q <= satp_asid_d;
      satp_ppn_q <= satp_ppn_d;

      fflags_q <= fflags_d;
      frm_q <= frm_d;

      mcounteren_q <= mcounteren_d;
      scounteren_q <= scounteren_d;
    end
  end

  //////////////////////////
  //  Performance monitor //
  //////////////////////////

  always_comb begin
    mcycle_d = mcycle_q;
    minstret_d = minstret_q;

    if (1'b1) mcycle_d = mcycle_q + 1;
    if (instr_ret_i) minstret_d = minstret_q + 1;

    if (mcycle_we) mcycle_d = csr_wdata_int;
    if (minstret_we) minstret_d = csr_wdata_int;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      mcycle_q <= '0;
      minstret_q <= '0;
    end
    else begin
      mcycle_q <= mcycle_d;
      minstret_q <= minstret_d;
    end
  end

endmodule
