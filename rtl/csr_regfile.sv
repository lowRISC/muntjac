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

    // SATP
    output logic [63:0]        satp_o,

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

    // Effective ATP for instruction access. It is computed from current privilege level.
    output status_t            status,

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
  priv_lvl_e prv, prv_d;

  assign priv_mode_o = prv;
  assign priv_mode_lsu_o = status.mprv ? status.mpp : prv;

  // Status fields
  status_t status_d;

  // Interrupt-related
  //

  logic seip, seip_d;
  logic ssip, ssip_d;
  logic stip, stip_d;
  // Only 'hAAA is relevant
  logic [11:0] mie, mie_d;
  // Only 'h222 is relevant.
  logic [11:0] mideleg, mideleg_d;
  // Only 'hB35D is relevant. We don't suport PMP so we have less fault causes, and ecall from
  // M-mode cannot be delegated.
  logic [15:0] medeleg, medeleg_d;
  // Assemble the full MIP register from parts.
  logic [11:0] mip;
  assign mip = {
      irq_m_external_i, 1'b0, seip, 1'b0,
      irq_m_timer_i, 1'b0, stip, 1'b0,
      irq_m_software_i, 1'b0, ssip, 1'b0
  };

  //
  // End of Interrupt-releated

  // The last two bits of these registers must be zero. We don't support vectored mode.
  logic [63:0] mtvec, mtvec_d;
  logic [63:0] stvec, stvec_d;

  // The last two bit must be zero.
  logic [63:0] mepc, mepc_d;
  logic [63:0] sepc, sepc_d;

  logic [63:0] mscratch, mscratch_d;
  logic [63:0] mtval, mtval_d;
  logic mcause_interrupt, mcause_interrupt_d;
  logic [3:0] mcause_code, mcause_code_d;
  logic [63:0] sscratch, sscratch_d;
  logic [63:0] stval, stval_d;
  logic scause_interrupt, scause_interrupt_d;
  logic [3:0] scause_code, scause_code_d;

  // User Floating-Point CSRs.
  logic [4:0] fflags, fflags_d;
  logic [2:0] frm, frm_d;

  // Address Translation
  logic satp_mode, satp_mode_d;
  logic [AsidLen-1:0] satp_asid, satp_asid_d;
  logic [PhysLen-12-1:0] satp_ppn, satp_ppn_d;

  // Counter Enable
  logic [2:0] mcounteren, mcounteren_d;
  logic [2:0] scounteren, scounteren_d;

  // Hardware performance counters
  logic [63:0] mcycle, mcycle_d;
  logic [63:0] minstret, minstret_d;

  // CSRs assembled from multiple paets
  logic sd;
  logic [63:0] mstatus;
  logic [63:0] sstatus;

  assign sd = &status.fs;

  // Hardwire UXL to 64.
  assign mstatus = {
      sd, 27'b0, 2'b10, 2'b10, 9'b0, status.tsr, status.tw, status.tvm, status.mxr, status.sum, status.mprv, 2'b0,
      status.fs, status.mpp, 2'b0, status.spp, status.mpie, 1'b0, status.spie, 1'b0, status.mie, 1'b0, status.sie, 1'b0
  };
  assign sstatus = {
      sd, 29'b0, 2'b10, 12'b0, status.mxr, status.sum, 3'b0,
      status.fs, 4'b0, status.spp, 2'b0, status.spie, 3'b0, status.sie, 1'b0
  };
  assign satp_o = {satp_mode, 3'b0, 16'(satp_asid), 44'(satp_ppn)};

  // Privilege checking logic
  logic illegal;
  logic illegal_readonly;
  logic illegal_prv;

  always_comb begin
    illegal = 1'b0;
    illegal_readonly = check_addr_i[11:10] == 2'b11 && check_op_i != CSR_OP_READ;
    illegal_prv = check_addr_i[9:8] > prv;

    priority casez (check_addr_i)
      CSR_FFLAGS, CSR_FRM, CSR_FCSR: if (!RV64F || status.fs == 2'b00) illegal = 1'b1;
      CSR_CYCLE: if (!((prv > PRIV_LVL_S || mcounteren[0]) && (prv > PRIV_LVL_U || scounteren[0]))) illegal = 1'b1;
      CSR_INSTRET: if (!((prv > PRIV_LVL_S || mcounteren[2]) && (prv > PRIV_LVL_U || scounteren[2]))) illegal = 1'b1;
      CSR_SSTATUS, CSR_SIE, CSR_STVEC, CSR_SCOUNTEREN:;
      CSR_SSCRATCH, CSR_SEPC, CSR_SCAUSE, CSR_STVAL, CSR_SIP:;
      CSR_SATP: if (prv != PRIV_LVL_M && status.tvm) illegal = 1'b1;
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
      CSR_FFLAGS: if (RV64F) old_value = fflags;
      CSR_FRM: if (RV64F) old_value = frm;
      CSR_FCSR: if (RV64F) old_value = {frm, fflags};

      // User Counter/Timers CSRs
      CSR_CYCLE: old_value = mcycle;
      CSR_INSTRET: old_value = minstret;
      // TIME and HPMCOUNTERS does not exist MCOUNTEREN bits are hardwired to zero.

      CSR_SSTATUS: old_value = sstatus;
      // SEDELEG does not exist.
      // SIDELEG does not exist.
      CSR_SIE: old_value = mie & mideleg;
      CSR_STVEC: old_value = stvec;
      CSR_SCOUNTEREN: old_value = scounteren;

      CSR_SSCRATCH: old_value = sscratch;
      CSR_SEPC: old_value = sepc;
      CSR_SCAUSE: old_value = {scause_interrupt, 59'b0, scause_code};
      CSR_STVAL: old_value = stval;
      CSR_SIP: old_value = mip & mideleg;

      CSR_SATP: old_value = satp_o;

      CSR_MVENDORID, CSR_MARCHID, CSR_MIMPID: old_value = '0;
      CSR_MHARTID: old_value = hart_id_i;

      CSR_MSTATUS: old_value = mstatus;

      // misa
      CSR_MISA: old_value = MISA_VALUE;

      CSR_MEDELEG: old_value = medeleg;
      CSR_MIDELEG: old_value = mideleg;
      CSR_MIE: old_value = mie;
      CSR_MTVEC: old_value = mtvec;
      CSR_MCOUNTEREN: old_value = mcounteren;

      CSR_MSCRATCH: old_value = mscratch;
      CSR_MEPC: old_value = mepc;
      CSR_MCAUSE: old_value = {mcause_interrupt, 59'b0, mcause_code};
      CSR_MTVAL: old_value = mtval;
      CSR_MIP: old_value = mip;

      CSR_MCYCLE: old_value = mcycle;
      CSR_MTIME: old_value = 'x;
      CSR_MINSTRET: old_value = minstret;

      // We don't support additional counters, and don't support inhibition.
      CSR_MHPMCOUNTERS: old_value = '0;
      CSR_MHPMEVENTS: old_value = '0;
      CSR_MCOUNTINHIBIT: old_value = '0;
      default: old_value = 'x;
    endcase
    priority casez (csr_addr_i)
      CSR_SIP: csr_rdata_o = old_value | {irq_s_external_i, 9'b0} & mideleg;
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
    prv_d = prv;
    status_d = status;
    stip_d = stip;
    ssip_d = ssip;
    seip_d = seip;
    mie_d = mie;
    medeleg_d = medeleg;
    mideleg_d = mideleg;
    mtvec_d = mtvec;
    stvec_d = stvec;
    mepc_d = mepc;
    sepc_d = sepc;
    mscratch_d = mscratch;
    mtval_d = mtval;
    mcause_interrupt_d = mcause_interrupt;
    mcause_code_d = mcause_code;
    sscratch_d = sscratch;
    stval_d = stval;
    scause_interrupt_d = scause_interrupt;
    scause_code_d = scause_code;
    fflags_d = fflags;
    frm_d = frm;
    satp_mode_d = satp_mode;
    satp_asid_d = satp_asid;
    satp_ppn_d = satp_ppn;
    mcounteren_d = mcounteren;
    scounteren_d = scounteren;
    mcycle_d = mcycle + 1;
    // NOTE: This probably isn't strictly correct according to the spec, as the value read may
    // be off by 1 (due to pipelining). But since only firmware can write to this value, nobody
    // should care.
    minstret_d = hpm_instret ? minstret + 1 : minstret;

    ex_tvec = 'x;

    er_epc = 'x;

    unique case (1'b1)
      ex_valid: begin
        // Delegate to S-mode if we have an exception on S/U mode and delegation is enabled.
        if (prv != PRIV_LVL_M &&
            (ex_exception.mcause_interrupt ? mideleg[ex_exception.mcause_code] : medeleg[ex_exception.mcause_code])) begin
          ex_tvec = stvec;

          scause_interrupt_d = ex_exception.mcause_interrupt;
          scause_code_d = ex_exception.mcause_code;
          stval_d = ex_exception.mtval[63:0];
          sepc_d = ex_epc;

          prv_d = PRIV_LVL_S;
          status_d.sie = 1'b0;
          status_d.spie = status.sie;
          status_d.spp = prv[0];
        end else begin
          // Exception handling vector
          ex_tvec = mtvec;

          // Exception info registers
          mcause_interrupt_d = ex_exception.mcause_interrupt;
          mcause_code_d = ex_exception.mcause_code;
          mtval_d = ex_exception.mtval[63:0];
          mepc_d = ex_epc;

          // Switch privilege level and set mstatus
          prv_d = PRIV_LVL_M;
          status_d.mie = 1'b0;
          status_d.mpie = status.mie;
          status_d.mpp = prv;
        end
      end
      er_valid: begin
        if (er_prv != PRIV_LVL_M) begin
          er_epc = sepc;

          prv_d = status.spp ? PRIV_LVL_S : PRIV_LVL_U;
          status_d.spie = 1'b1;
          status_d.sie = status.spie;
          status_d.spp = 1'b0;
        end else begin
          er_epc = mepc;

          prv_d = status.mpp;
          status_d.mpie = 1'b1;
          status_d.mie = status.mpie;
          status_d.mpp = PRIV_LVL_U;
          // Clear MPRV when leaving M-mode
          if (status.mpp != PRIV_LVL_M) status_d.mprv = 1'b0;
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
                status_d.mxr    = new_value[19];
                status_d.sum    = new_value[18];
                status_d.fs     = new_value[14:13];
                status_d.spp    = new_value[8];
                status_d.spie   = new_value[5];
                status_d.sie    = new_value[1];
            end
            // SEDELEG does not exist.
            // SIDELEG does not exist.
            CSR_SIE: mie_d = (mie &~ mideleg) | (new_value[11:0] & mideleg);
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
                if (mideleg[BIT_SSI]) ssip_d = new_value[BIT_SSI];
            end
            CSR_SATP: begin
                satp_mode_d = new_value[63];
                satp_asid_d = new_value[PhysLen-12 +: AsidLen];
                satp_ppn_d  = new_value[0 +: PhysLen-12];
            end

            CSR_MSTATUS: begin
                status_d.tsr    = new_value[22];
                status_d.tw     = new_value[21];
                status_d.tvm    = new_value[20];
                status_d.mxr    = new_value[19];
                status_d.sum    = new_value[18];
                status_d.mprv   = new_value[17];
                status_d.fs     = new_value[14:13];
                // We don't support H-Mode
                if (new_value[12:11] != 2'b10) status_d.mpp = priv_lvl_e'(new_value[12:11]);
                status_d.spp    = new_value[8];
                status_d.mpie   = new_value[7];
                status_d.spie   = new_value[5];
                status_d.mie    = new_value[3];
                status_d.sie    = new_value[1];
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

  // Pending interrupt status
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
        ((prv_d != PRIV_LVL_M || status_d.mie) ? irq_pending_m_d : 0) |
        ((prv_d == PRIV_LVL_U || prv_d == PRIV_LVL_S && status_d.sie) ? irq_pending_s_d : 0);

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
      prv <= PRIV_LVL_M;
      status <= status_t'('0);
      stip <= '0;
      ssip <= '0;
      seip <= '0;
      mie <= '0;
      medeleg <= '0;
      mideleg <= '0;
      mtvec <= '0;
      stvec <= '0;
      mepc <= '0;
      sepc <= '0;
      mscratch <= '0;
      mtval <= '0;
      mcause_interrupt <= 1'b0;
      mcause_code <= '0;
      sscratch <= '0;
      stval <= '0;
      scause_interrupt <= 1'b0;
      scause_code <= '0;
      mtval <= '0;
      fflags <= '0;
      frm <= '0;
      satp_mode <= '0;
      satp_asid <= '0;
      satp_ppn <= '0;
      mcounteren <= '0;
      scounteren <= '0;
      mcycle <= '0;
      minstret <= '0;

      wfi_valid <= 1'b0;
      irq_pending <= '0;
    end
    else begin
      prv <= prv_d;
      status <= status_d;
      stip <= stip_d;
      ssip <= ssip_d;
      seip <= seip_d;
      mie <= mie_d;
      medeleg <= medeleg_d;
      mideleg <= mideleg_d;
      mtvec <= mtvec_d;
      stvec <= stvec_d;
      mepc <= mepc_d;
      sepc <= sepc_d;
      mscratch <= mscratch_d;
      mtval <= mtval_d;
      mcause_interrupt <= mcause_interrupt_d;
      mcause_code <= mcause_code_d;
      sscratch <= sscratch_d;
      stval <= stval_d;
      scause_interrupt <= scause_interrupt_d;
      scause_code <= scause_code_d;
      fflags <= fflags_d;
      frm <= frm_d;
      satp_mode <= satp_mode_d;
      satp_asid <= satp_asid_d;
      satp_ppn <= satp_ppn_d;
      mcounteren <= mcounteren_d;
      scounteren <= scounteren_d;
      mcycle <= mcycle_d;
      minstret <= minstret_d;

      wfi_valid <= wfi_valid_d;
      irq_pending <= irq_pending_d;
    end
  end

endmodule
