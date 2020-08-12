import cpu_common::*;
import riscv::*;

module csr_regfile import muntjac_pkg::*; # (
    parameter bit RV64D = 0,
    parameter bit RV64F = 0,
    parameter AsidLen = 16,
    parameter PhysLen = 56
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

    // Interrupts
    input  logic               irq_m_software_i,
    input  logic               irq_m_timer_i,
    input  logic               irq_m_external_i,
    input  logic               irq_s_external_i,

    // CSR exports
    output logic [63:0]        satp_o,
    output status_t            status_o,

    // Exception port. When ex_valid is true, ex_exception.valid is assumed to be true.
    input  logic               ex_valid,
    input  exception_t         ex_exception,
    input  logic [63:0]        ex_epc,
    output logic [63:0]        ex_tvec,

    // Exception return port
    input  logic               er_valid,
    input  priv_lvl_e          er_prv,
    output logic [63:0]        er_epc,

    // Interrupt output port
    output logic               int_valid,
    output logic [3:0]         int_cause,

    // Whether there is an interrupt pending at all, regardless if interrupts are enabled
    // according to MSTATUS.
    output logic               wfi_valid,

    // Performance counters
    input  logic               hpm_instret
);

  localparam BIT_MEI = 11;
  localparam BIT_SEI = 9;
  localparam BIT_MTI = 7;
  localparam BIT_STI = 5;
  localparam BIT_MSI = 3;
  localparam BIT_SSI = 1;

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

  // Current privilege level.
  priv_lvl_e priv_lvl_q, priv_lvl_d;

  // Status fields
  status_t mstatus_q, mstatus_d;

  assign status_o = mstatus_q;
  assign priv_mode_o = priv_lvl_q;
  assign priv_mode_lsu_o = mstatus_q.mprv ? mstatus_q.mpp : priv_lvl_q;

  // Interrupt-related
  //

  logic seip_q, seip_d;
  logic ssip_q, ssip_d;
  logic stip_q, stip_d;
  // Only 'hAAA is relevant
  logic [11:0] mie_q, mie_d;
  // Only 'h222 is relevant.
  logic [11:0] mideleg_q, mideleg_d;
  // Only 'hB35D is relevant. We don't suport PMP so we have less fault causes, and ecall from
  // M-mode cannot be delegated.
  logic [15:0] medeleg_q, medeleg_d;
  // Assemble the full MIP register from parts.
  logic [11:0] mip;
  assign mip = {
      irq_m_external_i, 1'b0, seip_q, 1'b0,
      irq_m_timer_i, 1'b0, stip_q, 1'b0,
      irq_m_software_i, 1'b0, ssip_q, 1'b0
  };

  //
  // End of Interrupt-releated

  // The last two bits of these registers must be zero. We don't support vectored mode.
  logic [63:0] mtvec_q, mtvec_d;
  logic [63:0] stvec_q, stvec_d;

  // The last two bit must be zero.
  logic [63:0] mepc_q, mepc_d;
  logic [63:0] sepc_q, sepc_d;

  logic [63:0] mscratch_q, mscratch_d;
  logic [63:0] mtval_q, mtval_d;
  logic mcause_interrupt_q, mcause_interrupt_d;
  logic [3:0] mcause_code_q, mcause_code_d;
  logic [63:0] sscratch_q, sscratch_d;
  logic [63:0] stval_q, stval_d;
  logic scause_interrupt_q, scause_interrupt_d;
  logic [3:0] scause_code_q, scause_code_d;

  // User Floating-Point CSRs.
  logic [4:0] fflags_q, fflags_d;
  logic [2:0] frm_q, frm_d;

  // Address Translation
  logic satp_mode_q, satp_mode_d;
  logic [AsidLen-1:0] satp_asid_q, satp_asid_d;
  logic [PhysLen-12-1:0] satp_ppn_q, satp_ppn_d;

  // Counter Enable
  logic [2:0] mcounteren_q, mcounteren_d;
  logic [2:0] scounteren_q, scounteren_d;

  // Hardware performance counters
  logic [63:0] mcycle_q, mcycle_d;
  logic [63:0] minstret_q, minstret_d;

  // CSRs assembled from multiple paets
  logic sd;
  logic [63:0] mstatus;
  logic [63:0] sstatus;

  assign sd = &mstatus_q.fs;

  // Hardwire UXL to 64.
  assign mstatus = {
      sd, 27'b0, 2'b10, 2'b10, 9'b0, mstatus_q.tsr, mstatus_q.tw, mstatus_q.tvm, mstatus_q.mxr, mstatus_q.sum, mstatus_q.mprv, 2'b0,
      mstatus_q.fs, mstatus_q.mpp, 2'b0, mstatus_q.spp, mstatus_q.mpie, 1'b0, mstatus_q.spie, 1'b0, mstatus_q.mie, 1'b0, mstatus_q.sie, 1'b0
  };
  assign sstatus = {
      sd, 29'b0, 2'b10, 12'b0, mstatus_q.mxr, mstatus_q.sum, 3'b0,
      mstatus_q.fs, 4'b0, mstatus_q.spp, 2'b0, mstatus_q.spie, 3'b0, mstatus_q.sie, 1'b0
  };
  assign satp_o = {satp_mode_q, 3'b0, 16'(satp_asid_q), 44'(satp_ppn_q)};

  // Privilege checking logic
  logic illegal;
  logic illegal_readonly;
  logic illegal_prv;

  always_comb begin
    illegal = 1'b0;
    illegal_readonly = check_addr_i[11:10] == 2'b11 && check_op_i != CSR_OP_READ;
    illegal_prv = check_addr_i[9:8] > priv_lvl_q;

    priority casez (check_addr_i)
      CSR_FFLAGS, CSR_FRM, CSR_FCSR: if (!RV64F || mstatus_q.fs == 2'b00) illegal = 1'b1;
      CSR_CYCLE: if (!((priv_lvl_q > PRIV_LVL_S || mcounteren_q[0]) && (priv_lvl_q > PRIV_LVL_U || scounteren_q[0]))) illegal = 1'b1;
      CSR_INSTRET: if (!((priv_lvl_q > PRIV_LVL_S || mcounteren_q[2]) && (priv_lvl_q > PRIV_LVL_U || scounteren_q[2]))) illegal = 1'b1;
      CSR_SSTATUS, CSR_SIE, CSR_STVEC, CSR_SCOUNTEREN:;
      CSR_SSCRATCH, CSR_SEPC, CSR_SCAUSE, CSR_STVAL, CSR_SIP:;
      CSR_SATP: if (priv_lvl_q != PRIV_LVL_M && mstatus_q.tvm) illegal = 1'b1;
      CSR_MVENDORID, CSR_MARCHID, CSR_MIMPID, CSR_MHARTID:;
      CSR_MSTATUS, CSR_MISA, CSR_MEDELEG, CSR_MIDELEG, CSR_MIE, CSR_MTVEC, CSR_MCOUNTEREN:;
      CSR_MSCRATCH, CSR_MEPC, CSR_MCAUSE, CSR_MTVAL, CSR_MIP:;
      CSR_MTIME: illegal = 1'b1;
      CSR_MHPMCOUNTERS, CSR_MHPMEVENTS, CSR_MCOUNTINHIBIT:;
      default: illegal = 1'b1;
    endcase
    check_illegal_o = illegal | illegal_readonly | illegal_prv;
  end

  logic [63:0] old_value;
  logic [63:0] new_value;

  // CSR reading logic
  always_comb begin
    old_value = 'x;

    priority casez (csr_addr_i)
      // User Trap Setup CSRs not supported
      // User Trap Handling CSRs not supported

      // User Floating-point CSRs
      CSR_FFLAGS: if (RV64F) old_value = fflags_q;
      CSR_FRM: if (RV64F) old_value = frm_q;
      CSR_FCSR: if (RV64F) old_value = {frm_q, fflags_q};

      // User Counter/Timers CSRs
      CSR_CYCLE: old_value = mcycle_q;
      CSR_INSTRET: old_value = minstret_q;
      // TIME and HPMCOUNTERS does not exist MCOUNTEREN bits are hardwired to zero.

      CSR_SSTATUS: old_value = sstatus;
      // SEDELEG does not exist.
      // SIDELEG does not exist.
      CSR_SIE: old_value = mie_q & mideleg_q;
      CSR_STVEC: old_value = stvec_q;
      CSR_SCOUNTEREN: old_value = scounteren_q;

      CSR_SSCRATCH: old_value = sscratch_q;
      CSR_SEPC: old_value = sepc_q;
      CSR_SCAUSE: old_value = {scause_interrupt_q, 59'b0, scause_code_q};
      CSR_STVAL: old_value = stval_q;
      CSR_SIP: old_value = mip & mideleg_q;

      CSR_SATP: old_value = satp_o;

      CSR_MVENDORID, CSR_MARCHID, CSR_MIMPID: old_value = '0;
      CSR_MHARTID: old_value = hart_id_i;

      CSR_MSTATUS: old_value = mstatus;

      // misa
      CSR_MISA: old_value = MISA_VALUE;

      CSR_MEDELEG: old_value = medeleg_q;
      CSR_MIDELEG: old_value = mideleg_q;
      CSR_MIE: old_value = mie_q;
      CSR_MTVEC: old_value = mtvec_q;
      CSR_MCOUNTEREN: old_value = mcounteren_q;

      CSR_MSCRATCH: old_value = mscratch_q;
      CSR_MEPC: old_value = mepc_q;
      CSR_MCAUSE: old_value = {mcause_interrupt_q, 59'b0, mcause_code_q};
      CSR_MTVAL: old_value = mtval_q;
      CSR_MIP: old_value = mip;

      CSR_MCYCLE: old_value = mcycle_q;
      CSR_MTIME: old_value = 'x;
      CSR_MINSTRET: old_value = minstret_q;

      // We don't support additional counters, and don't support inhibition.
      CSR_MHPMCOUNTERS: old_value = '0;
      CSR_MHPMEVENTS: old_value = '0;
      CSR_MCOUNTINHIBIT: old_value = '0;
      default: old_value = 'x;
    endcase
    priority casez (csr_addr_i)
      CSR_SIP: csr_rdata_o = old_value | {irq_s_external_i, 9'b0} & mideleg_q;
      CSR_MIP: csr_rdata_o = old_value | {irq_s_external_i, 9'b0};
      default: csr_rdata_o = old_value;
    endcase
  end

  // Perform read-modify-write operations.
  always_comb begin
    unique case (csr_op_i)
      CSR_OP_WRITE: new_value = csr_wdata_i;
      CSR_OP_SET: new_value = old_value | csr_wdata_i;
      CSR_OP_CLEAR: new_value = old_value &~ csr_wdata_i;
      // This catches both `csr_op_i = 'x` case and `csr_op_i = 2'b00` case (don't modify)
      default: new_value = 'x;
    endcase
  end

  // Write and exception handling logic
  always_comb begin
    // Everything stays the same until updated.
    priv_lvl_d = priv_lvl_q;
    mstatus_d = mstatus_q;
    stip_d = stip_q;
    ssip_d = ssip_q;
    seip_d = seip_q;
    mie_d = mie_q;
    medeleg_d = medeleg_q;
    mideleg_d = mideleg_q;
    mtvec_d = mtvec_q;
    stvec_d = stvec_q;
    mepc_d = mepc_q;
    sepc_d = sepc_q;
    mscratch_d = mscratch_q;
    mtval_d = mtval_q;
    mcause_interrupt_d = mcause_interrupt_q;
    mcause_code_d = mcause_code_q;
    sscratch_d = sscratch_q;
    stval_d = stval_q;
    scause_interrupt_d = scause_interrupt_q;
    scause_code_d = scause_code_q;
    fflags_d = fflags_q;
    frm_d = frm_q;
    satp_mode_d = satp_mode_q;
    satp_asid_d = satp_asid_q;
    satp_ppn_d = satp_ppn_q;
    mcounteren_d = mcounteren_q;
    scounteren_d = scounteren_q;
    mcycle_d = mcycle_q + 1;
    // NOTE: This probably isn't strictly correct according to the spec, as the value read may
    // be off by 1 (due to pipelining). But since only firmware can write to this value, nobody
    // should care.
    minstret_d = hpm_instret ? minstret_q + 1 : minstret_q;

    ex_tvec = 'x;

    er_epc = 'x;

    unique case (1'b1)
      ex_valid: begin
        // Delegate to S-mode if we have an exception on S/U mode and delegation is enabled.
        if (priv_lvl_q != PRIV_LVL_M &&
            (ex_exception.mcause_interrupt ? mideleg_q[ex_exception.mcause_code] : medeleg_q[ex_exception.mcause_code])) begin
          ex_tvec = stvec_q;

          scause_interrupt_d = ex_exception.mcause_interrupt;
          scause_code_d = ex_exception.mcause_code;
          stval_d = ex_exception.mtval[63:0];
          sepc_d = ex_epc;

          priv_lvl_d = PRIV_LVL_S;
          mstatus_d.sie = 1'b0;
          mstatus_d.spie = mstatus_q.sie;
          mstatus_d.spp = priv_lvl_q[0];
        end else begin
          // Exception handling vector
          ex_tvec = mtvec_q;

          // Exception info registers
          mcause_interrupt_d = ex_exception.mcause_interrupt;
          mcause_code_d = ex_exception.mcause_code;
          mtval_d = ex_exception.mtval[63:0];
          mepc_d = ex_epc;

          // Switch privilege level and set mstatus
          priv_lvl_d = PRIV_LVL_M;
          mstatus_d.mie = 1'b0;
          mstatus_d.mpie = mstatus_q.mie;
          mstatus_d.mpp = priv_lvl_q;
        end
      end
      er_valid: begin
        if (er_prv != PRIV_LVL_M) begin
          er_epc = sepc_q;

          priv_lvl_d = mstatus_q.spp ? PRIV_LVL_S : PRIV_LVL_U;
          mstatus_d.spie = 1'b1;
          mstatus_d.sie = mstatus_q.spie;
          mstatus_d.spp = 1'b0;
        end else begin
          er_epc = mepc_q;

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
          priority casez (csr_addr_i)
            // User Trap Setup CSRs not supported
            // User Trap Handling CSRs not supported

            // User Floating-point CSRs
            CSR_FFLAGS: if (RV64F) fflags_d = new_value[4:0];
            CSR_FRM: if (RV64F) frm_d = new_value[2:0];
            CSR_FCSR: if (RV64F) begin
                fflags_d = new_value[4:0];
                frm_d = new_value[7:5];
            end

            CSR_SSTATUS: begin
                mstatus_d.mxr    = new_value[19];
                mstatus_d.sum    = new_value[18];
                mstatus_d.fs     = new_value[14:13];
                mstatus_d.spp    = new_value[8];
                mstatus_d.spie   = new_value[5];
                mstatus_d.sie    = new_value[1];
            end
            // SEDELEG does not exist.
            // SIDELEG does not exist.
            CSR_SIE: mie_d = (mie_q &~ mideleg_q) | (new_value[11:0] & mideleg_q);
            CSR_STVEC: stvec_d = {new_value[63:2], 2'b0};
            CSR_SCOUNTEREN: scounteren_d = new_value[2:0] & 3'b101;

            CSR_SSCRATCH: sscratch_d = new_value;
            CSR_SEPC: sepc_d = {new_value[63:1], 1'b0};
            CSR_SCAUSE: begin
                scause_interrupt_d = new_value[63];
                scause_code_d = new_value[3:0];
            end
            CSR_STVAL: stval_d = new_value;
            CSR_SIP: begin
                if (mideleg_q[BIT_SSI]) ssip_d = new_value[BIT_SSI];
            end
            CSR_SATP: begin
                satp_mode_d = new_value[63];
                satp_asid_d = new_value[PhysLen-12 +: AsidLen];
                satp_ppn_d  = new_value[0 +: PhysLen-12];
            end

            CSR_MSTATUS: begin
                mstatus_d.tsr    = new_value[22];
                mstatus_d.tw     = new_value[21];
                mstatus_d.tvm    = new_value[20];
                mstatus_d.mxr    = new_value[19];
                mstatus_d.sum    = new_value[18];
                mstatus_d.mprv   = new_value[17];
                mstatus_d.fs     = new_value[14:13];
                // We don't support H-Mode
                if (new_value[12:11] != 2'b10) mstatus_d.mpp = priv_lvl_e'(new_value[12:11]);
                mstatus_d.spp    = new_value[8];
                mstatus_d.mpie   = new_value[7];
                mstatus_d.spie   = new_value[5];
                mstatus_d.mie    = new_value[3];
                mstatus_d.sie    = new_value[1];
            end
            CSR_MISA:;
            CSR_MEDELEG: medeleg_d = new_value[15:0] & 'hB35D;
            CSR_MIDELEG: mideleg_d = new_value[11:0] & 'h222;
            CSR_MIE: mie_d = new_value[11:0] & 'hAAA;
            CSR_MTVEC: mtvec_d = {new_value[63:2], 2'b0};
            CSR_MCOUNTEREN: mcounteren_d = new_value[2:0] & 3'b101;

            CSR_MSCRATCH: mscratch_d = new_value;
            CSR_MEPC: mepc_d = {new_value[63:1], 1'b0};
            CSR_MCAUSE: begin
                mcause_interrupt_d = new_value[63];
                mcause_code_d = new_value[3:0];
            end
            CSR_MTVAL: mtval_d = new_value;
            CSR_MIP: begin
                stip_d = new_value[BIT_STI];
                ssip_d = new_value[BIT_SSI];
                seip_d = new_value[BIT_SEI];
            end

            CSR_MCYCLE: mcycle_d = new_value;
            CSR_MINSTRET: minstret_d = new_value;

            // We don't support additional counters, and don't support inhibition.
            CSR_MHPMCOUNTERS:;
            CSR_MHPMEVENTS:;
            CSR_MCOUNTINHIBIT:;
            default:;
          endcase
        end
      end
      // If nothing is true don't change anything. We don't use unique0 here because Vivado's
      // poor support.
      default:;
    endcase
  end

  // Pending interrupt mstatus_q
  logic wfi_valid_d;
  logic [11:0] irq_high;
  logic [11:0] irq_high_enable;
  logic [11:0] irq_pending_m_d;
  logic [11:0] irq_pending_s_d;
  logic [11:0] irq_pending, irq_pending_d;

  always_comb begin
    irq_high = {
        irq_m_external_i, 1'b0, irq_s_external_i | seip_d, 1'b0,
        irq_m_timer_i, 1'b0, stip_d, 1'b0,
        irq_m_software_i, 1'b0, ssip_d, 1'b0
    };
    irq_high_enable = irq_high & mie_d;
    irq_pending_m_d = irq_high_enable & ~mideleg_d;
    irq_pending_s_d = irq_high_enable & mideleg_d;
    irq_pending_d =
        ((priv_lvl_d != PRIV_LVL_M || mstatus_d.mie) ? irq_pending_m_d : 0) |
        ((priv_lvl_d == PRIV_LVL_U || priv_lvl_d == PRIV_LVL_S && mstatus_d.sie) ? irq_pending_s_d : 0);

    int_valid = |irq_pending;
    wfi_valid_d = |irq_high_enable;
    priority case (1'b1)
      irq_pending[BIT_MEI]: int_cause = BIT_MEI;
      irq_pending[BIT_MSI]: int_cause = BIT_MSI;
      irq_pending[BIT_MTI]: int_cause = BIT_MTI;
      irq_pending[BIT_SEI]: int_cause = BIT_SEI;
      irq_pending[BIT_SSI]: int_cause = BIT_SSI;
      irq_pending[BIT_STI]: int_cause = BIT_STI;
      default: int_cause = 'x;
    endcase
  end

  // State update
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      priv_lvl_q <= PRIV_LVL_M;
      mstatus_q <= status_t'('0);
      stip_q <= '0;
      ssip_q <= '0;
      seip_q <= '0;
      mie_q <= '0;
      medeleg_q <= '0;
      mideleg_q <= '0;
      mtvec_q <= '0;
      stvec_q <= '0;
      mepc_q <= '0;
      sepc_q <= '0;
      mscratch_q <= '0;
      mtval_q <= '0;
      mcause_interrupt_q <= 1'b0;
      mcause_code_q <= '0;
      sscratch_q <= '0;
      stval_q <= '0;
      scause_interrupt_q <= 1'b0;
      scause_code_q <= '0;
      fflags_q <= '0;
      frm_q <= '0;
      satp_mode_q <= '0;
      satp_asid_q <= '0;
      satp_ppn_q <= '0;
      mcounteren_q <= '0;
      scounteren_q <= '0;
      mcycle_q <= '0;
      minstret_q <= '0;

      wfi_valid <= 1'b0;
      irq_pending <= '0;
    end
    else begin
      priv_lvl_q <= priv_lvl_d;
      mstatus_q <= mstatus_d;
      stip_q <= stip_d;
      ssip_q <= ssip_d;
      seip_q <= seip_d;
      mie_q <= mie_d;
      medeleg_q <= medeleg_d;
      mideleg_q <= mideleg_d;
      mtvec_q <= mtvec_d;
      stvec_q <= stvec_d;
      mepc_q <= mepc_d;
      sepc_q <= sepc_d;
      mscratch_q <= mscratch_d;
      mtval_q <= mtval_d;
      mcause_interrupt_q <= mcause_interrupt_d;
      mcause_code_q <= mcause_code_d;
      sscratch_q <= sscratch_d;
      stval_q <= stval_d;
      scause_interrupt_q <= scause_interrupt_d;
      scause_code_q <= scause_code_d;
      fflags_q <= fflags_d;
      frm_q <= frm_d;
      satp_mode_q <= satp_mode_d;
      satp_asid_q <= satp_asid_d;
      satp_ppn_q <= satp_ppn_d;
      mcounteren_q <= mcounteren_d;
      scounteren_q <= scounteren_d;
      mcycle_q <= mcycle_d;
      minstret_q <= minstret_d;

      wfi_valid <= wfi_valid_d;
      irq_pending <= irq_pending_d;
    end
  end

endmodule
