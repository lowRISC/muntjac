import cpu_common::*;
import riscv::*;

module csr_regfile # (
    parameter XLEN = 64,
    parameter A_EXT = 1'b1,
    parameter D_EXT = 1'b0,
    parameter F_EXT = 1'b0,
    parameter M_EXT = 1'b1,
    parameter ASIDLEN = XLEN == 64 ? 16 : 9,
    parameter PHYSLEN = XLEN == 64 ? 56 : 34
) (
    // Clock and reset
    input  logic               clk,
    input  logic               resetn,

    // Privilege check port used by the decoding stage
    input  csr_t               pc_sel,
    input  logic [1:0]         pc_op,
    output logic               pc_illegal,

    // Access port
    input  logic               a_valid,
    input  csr_t               a_sel,
    input  logic [1:0]         a_op,
    input  logic [XLEN-1:0]    a_data,
    output logic [XLEN-1:0]    a_read,

    // Exception port. When ex_valid is true, ex_exception.valid is assumed to be true.
    input  logic               ex_valid,
    input  exception_t         ex_exception,
    input  logic [XLEN-1:0]    ex_epc,
    output logic [XLEN-1:0]    ex_tvec,

    // Exception return port
    input  logic               er_valid,
    input  prv_t               er_prv,
    output logic [XLEN-1:0]    er_epc,

    // Interrupt pending registers
    input  logic               irq_m_external,
    input  logic               irq_m_software,
    input  logic               irq_m_timer,
    input  logic               irq_s_external,

    // Interrupt output port
    output logic               int_valid,
    output logic [3:0]         int_cause,

    // Whether there is an interrupt pending at all, regardless if interrupts are enabled
    // according to MSTATUS.
    output logic               wfi_valid,

    // Effective ATP for data access. It is computed from current privilege level, MPRV and SATP.
    output logic               data_prv,
    output logic [XLEN-1:0]    data_atp,
    // Effective ATP for instruction access. It is computed from current privilege level.
    output logic [XLEN-1:0]    insn_atp,
    output prv_t               prv,
    output status_t            status,

    // ID of the current hart
    input  logic [XLEN-1:0]    mhartid,

    // Performance counters
    input  logic               hpm_instret
);

    localparam BIT_MEI = 11;
    localparam BIT_SEI = 9;
    localparam BIT_MTI = 7;
    localparam BIT_STI = 5;
    localparam BIT_MSI = 3;
    localparam BIT_SSI = 1;

    localparam MISA_VAL =
        {XLEN == 64 ? 2'b10 : 2'b01, {(XLEN-28){1'b0}}, 26'h100} // Base ISA
        | 26'h40000 // S-Mode
        | (A_EXT ? 26'h1 : 0) // A-extension
        | 26'h4 // C-extension
        | (D_EXT ? 26'h8 : 0) // D-extension
        | (F_EXT ? 26'h20 : 0) // F-extension
        | (M_EXT ? 26'h1000 : 0) // M-extension
        | 26'h100000; // U-Mode

    // Current privilege level. prv is defined at port.
    prv_t prv_d;

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
        irq_m_external, 1'b0, seip, 1'b0,
        irq_m_timer, 1'b0, stip, 1'b0,
        irq_m_software, 1'b0, ssip, 1'b0
    };

    //
    // End of Interrupt-releated

    // The last two bits of these registers must be zero. We don't support vectored mode.
    logic [XLEN-1:0] mtvec, mtvec_d;
    logic [XLEN-1:0] stvec, stvec_d;

    // The last two bit must be zero.
    logic [XLEN-1:0] mepc, mepc_d;
    logic [XLEN-1:0] sepc, sepc_d;

    logic [XLEN-1:0] mscratch, mscratch_d;
    logic [XLEN-1:0] mtval, mtval_d;
    logic mcause_interrupt, mcause_interrupt_d;
    logic [3:0] mcause_code, mcause_code_d;
    logic [XLEN-1:0] sscratch, sscratch_d;
    logic [XLEN-1:0] stval, stval_d;
    logic scause_interrupt, scause_interrupt_d;
    logic [3:0] scause_code, scause_code_d;

    // User Floating-Point CSRs.
    logic [4:0] fflags, fflags_d;
    logic [2:0] frm, frm_d;

    // Address Translation
    logic satp_mode, satp_mode_d;
    logic [ASIDLEN-1:0] satp_asid, satp_asid_d;
    logic [PHYSLEN-12-1:0] satp_ppn, satp_ppn_d;

    // Counter Enable
    logic [2:0] mcounteren, mcounteren_d;
    logic [2:0] scounteren, scounteren_d;

    // Hardware performance counters
    logic [63:0] mcycle, mcycle_d;
    logic [63:0] minstret, minstret_d;

    // CSRs assembled from multiple paets
    logic sd;
    logic [XLEN-1:0] mstatus;
    logic [XLEN-1:0] sstatus;
    logic [XLEN-1:0] mcause;
    logic [XLEN-1:0] scause;
    logic data_atp_mode;
    logic insn_atp_mode;
    logic [XLEN-1:0] satp;

    assign sd = &status.fs;
    assign mcause = {mcause_interrupt, {(XLEN-5){1'b0}}, mcause_code};
    assign scause = {scause_interrupt, {(XLEN-5){1'b0}}, scause_code};

    // This value is only relevant when data_atp_mode is not zero.
    assign data_prv = prv == PRV_M ? status.mpp[0] : prv[0];

    assign data_atp_mode = prv == PRV_M && (!status.mprv || status.mpp == PRV_M) ? 1'b0 : satp_mode;
    assign insn_atp_mode = prv == PRV_M ? 1'b0 : satp_mode;
    if (XLEN == 64) begin
        // Hardwire UXL to 64.
        assign mstatus = {
            sd, 27'b0, 2'b10, 2'b10, 9'b0, status.tsr, status.tw, status.tvm, status.mxr, status.sum, status.mprv, 2'b0,
            status.fs, status.mpp, 2'b0, status.spp, status.mpie, 1'b0, status.spie, 1'b0, status.mie, 1'b0, status.sie, 1'b0
        };
        assign sstatus = {
            sd, 29'b0, 2'b10, 12'b0, status.mxr, status.sum, 3'b0,
            status.fs, 4'b0, status.spp, 2'b0, status.spie, 3'b0, status.sie, 1'b0
        };
        assign satp = {satp_mode, 3'b0, 16'(satp_asid), 44'(satp_ppn)};
        assign data_atp = {data_atp_mode, 3'b0, 16'(satp_asid), 44'(satp_ppn)};
        assign insn_atp = {insn_atp_mode, 3'b0, 16'(satp_asid), 44'(satp_ppn)};
    end else begin
        assign mstatus = {
            sd, 8'b0, status.tsr, status.tw, status.tvm, status.mxr, status.sum, status.mprv, 2'b0,
            status.fs, status.mpp, 2'b0, status.spp, status.mpie, 1'b0, status.spie, 1'b0, status.mie, 1'b0, status.sie, 1'b0
        };
        assign sstatus = {
            sd, 11'b0, status.mxr, status.sum, 3'b0,
            status.fs, 4'b0, status.spp, 2'b0, status.spie, 3'b0, status.sie, 1'b0
        };
        assign satp = {satp_mode, 9'(satp_asid), 22'(satp_ppn)};
        assign data_atp = {data_atp_mode, 9'(satp_asid), 22'(satp_ppn)};
        assign insn_atp = {insn_atp_mode, 9'(satp_asid), 22'(satp_ppn)};
    end

    // Privilege checking logic
    logic illegal;
    logic illegal_readonly;
    logic illegal_prv;

    always_comb begin
        illegal = 1'b0;
        illegal_readonly = pc_sel[11:10] == 2'b11 && pc_op != 2'b00;
        illegal_prv = pc_sel[9:8] > prv;

        priority casez (pc_sel)
            CSR_FFLAGS, CSR_FRM, CSR_FCSR: if (!F_EXT || status.fs == 2'b00) illegal = 1'b1;
            CSR_CYCLE: if (!((prv > PRV_S || mcounteren[0]) && (prv > PRV_U || scounteren[0]))) illegal = 1'b1;
            CSR_INSTRET: if (!((prv > PRV_S || mcounteren[2]) && (prv > PRV_U || scounteren[2]))) illegal = 1'b1;
            CSR_SSTATUS, CSR_SIE, CSR_STVEC, CSR_SCOUNTEREN:;
            CSR_SSCRATCH, CSR_SEPC, CSR_SCAUSE, CSR_STVAL, CSR_SIP:;
            CSR_SATP: if (prv != PRV_M && status.tvm) illegal = 1'b1;
            CSR_MVENDORID, CSR_MARCHID, CSR_MIMPID, CSR_MHARTID:;
            CSR_MSTATUS, CSR_MISA, CSR_MEDELEG, CSR_MIDELEG, CSR_MIE, CSR_MTVEC, CSR_MCOUNTEREN:;
            CSR_MSCRATCH, CSR_MEPC, CSR_MCAUSE, CSR_MTVAL, CSR_MIP:;
            CSR_MTIME: illegal = 1'b1;
            CSR_MHPMCOUNTERS, CSR_MHPMEVENTS, CSR_MCOUNTINHIBIT:;
            default: illegal = 1'b1;
        endcase
        pc_illegal = illegal | illegal_readonly | illegal_prv;
    end

    logic [XLEN-1:0] old_value;
    logic [XLEN-1:0] new_value;

    // CSR reading logic
    always_comb begin
        old_value = 'x;

        priority casez (a_sel)
            // User Trap Setup CSRs not supported
            // User Trap Handling CSRs not supported

            // User Floating-point CSRs
            CSR_FFLAGS: if (F_EXT) old_value = fflags;
            CSR_FRM: if (F_EXT) old_value = frm;
            CSR_FCSR: if (F_EXT) old_value = {frm, fflags};

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
            CSR_SCAUSE: old_value = scause;
            CSR_STVAL: old_value = stval;
            CSR_SIP: old_value = mip & mideleg;

            CSR_SATP: old_value = satp;

            CSR_MVENDORID, CSR_MARCHID, CSR_MIMPID: old_value = '0;
            CSR_MHARTID: old_value = mhartid;

            CSR_MSTATUS: old_value = mstatus;
            CSR_MISA: old_value = MISA_VAL;
            CSR_MEDELEG: old_value = medeleg;
            CSR_MIDELEG: old_value = mideleg;
            CSR_MIE: old_value = mie;
            CSR_MTVEC: old_value = mtvec;
            CSR_MCOUNTEREN: old_value = mcounteren;

            CSR_MSCRATCH: old_value = mscratch;
            CSR_MEPC: old_value = mepc;
            CSR_MCAUSE: old_value = mcause;
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
        priority casez (a_sel)
            CSR_SIP: a_read = old_value | {irq_s_external, 9'b0} & mideleg;
            CSR_MIP: a_read = old_value | {irq_s_external, 9'b0};
            default: a_read = old_value;
        endcase
    end

    // Perform read-modify-write operations.
    always_comb begin
        unique case (a_op)
            2'b01: new_value = a_data;
            2'b10: new_value = old_value | a_data;
            2'b11: new_value = old_value &~ a_data;
            // This catches both `a_op = 'x` case and `a_op = 2'b00` case (don't modify)
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
                if (prv_d != PRV_M &&
                    (ex_exception.mcause_interrupt ? mideleg[ex_exception.mcause_code] : medeleg[ex_exception.mcause_code])) begin
                    ex_tvec = stvec;

                    scause_interrupt_d = ex_exception.mcause_interrupt;
                    scause_code_d = ex_exception.mcause_code;
                    stval_d = ex_exception.mtval[XLEN-1:0];
                    sepc_d = ex_epc;

                    prv_d = PRV_S;
                    status_d.sie = 1'b0;
                    status_d.spie = status.sie;
                    status_d.spp = prv[0];
                end else begin
                    // Exception handling vector
                    ex_tvec = mtvec;

                    // Exception info registers
                    mcause_interrupt_d = ex_exception.mcause_interrupt;
                    mcause_code_d = ex_exception.mcause_code;
                    mtval_d = ex_exception.mtval[XLEN-1:0];
                    mepc_d = ex_epc;

                    // Switch privilege level and set mstatus
                    prv_d = PRV_M;
                    status_d.mie = 1'b0;
                    status_d.mpie = status.mie;
                    status_d.mpp = prv;
                end
            end
            er_valid: begin
                if (er_prv != PRV_M) begin
                    er_epc = sepc;

                    prv_d = status.spp ? PRV_S : PRV_U;
                    status_d.spie = 1'b1;
                    status_d.sie = status.spie;
                    status_d.spp = 1'b0;
                end else begin
                    er_epc = mepc;

                    prv_d = status.mpp;
                    status_d.mpie = 1'b1;
                    status_d.mie = status.mpie;
                    status_d.mpp = PRV_U;
                    // Clear MPRV when leaving M-mode
                    if (status.mpp != PRV_M) status_d.mprv = 1'b0;
                end
            end
            a_valid: begin
                if (a_op != 2'b00) begin
                    priority casez (a_sel)
                        // User Trap Setup CSRs not supported
                        // User Trap Handling CSRs not supported

                        // User Floating-point CSRs
                        CSR_FFLAGS: if (F_EXT) fflags_d = new_value[4:0];
                        CSR_FRM: if (F_EXT) frm_d = new_value[2:0];
                        CSR_FCSR: if (F_EXT) begin
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
                        CSR_STVEC: stvec_d = {new_value[XLEN-1:2], 2'b0};
                        CSR_SCOUNTEREN: scounteren_d = new_value[2:0] & 3'b101;

                        CSR_SSCRATCH: sscratch_d = new_value;
                        CSR_SEPC: sepc_d = {new_value[XLEN-1:1], 1'b0};
                        CSR_SCAUSE: begin
                            scause_interrupt_d = new_value[XLEN-1];
                            scause_code_d = new_value[3:0];
                        end
                        CSR_STVAL: stval_d = new_value;
                        CSR_SIP: begin
                            if (mideleg[BIT_SSI]) ssip_d = new_value[BIT_SSI];
                        end
                        CSR_SATP: begin
                            satp_mode_d = new_value[XLEN-1];
                            satp_asid_d = new_value[PHYSLEN-12 +: ASIDLEN];
                            satp_ppn_d  = new_value[0 +: PHYSLEN-12];
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
                            if (new_value[12:11] != 2'b10) status_d.mpp = prv_t'(new_value[12:11]);
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
                        CSR_MTVEC: mtvec_d = {new_value[XLEN-1:2], 2'b0};
                        CSR_MCOUNTEREN: mcounteren_d = new_value[2:0] & 3'b101;

                        CSR_MSCRATCH: mscratch_d = new_value;
                        CSR_MEPC: mepc_d = {new_value[XLEN-1:1], 1'b0};
                        CSR_MCAUSE: begin
                            mcause_interrupt_d = new_value[XLEN-1];
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
            irq_m_external, 1'b0, irq_s_external | seip_d, 1'b0,
            irq_m_timer, 1'b0, stip_d, 1'b0,
            irq_m_software, 1'b0, ssip_d, 1'b0
        };
        irq_high_enable = irq_high & mie_d;
        irq_pending_m_d = irq_high_enable & ~mideleg_d;
        irq_pending_s_d = irq_high_enable & mideleg_d;
        irq_pending_d =
            ((prv_d != PRV_M || status_d.mie) ? irq_pending_m_d : 0) |
            ((prv_d == PRV_U || prv_d == PRV_S && status_d.sie) ? irq_pending_s_d : 0);

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
    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            prv <= PRV_M;
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
