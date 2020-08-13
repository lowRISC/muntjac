import riscv::*;
import cpu_common::*;
import muntjac_pkg::*;

module cpu #(
    parameter XLEN = 64
) (
    // Clock and reset
    input  logic            clk_i,
    input  logic            rst_ni,

    // Memory interfaces
    icache_intf.user icache,
    dcache_intf.user dcache,

    input  logic irq_m_timer,
    input  logic irq_m_software,
    input  logic irq_m_external,
    input  logic irq_s_external,

    input  logic [XLEN-1:0] mhartid,

    // Debug connections
    output logic [XLEN-1:0]    dbg_pc
);

    localparam BRANCH_PRED = 1;

    // CSR
    logic [XLEN-1:0] satp;
    priv_lvl_e prv;
    priv_lvl_e data_prv;
    status_t status;

    // WB-IF interfacing, valid only when a PC override is required.
    logic wb_if_valid;
    if_reason_t wb_if_reason;
    logic [XLEN-1:0] wb_if_pc;

    // IF-DE interfacing
    logic if_de_valid;
    logic if_de_ready;
    fetched_instr_t if_de_instr;

    //
    // IF stage
    //
    instr_fetcher #(
        .XLEN(XLEN),
        .BRANCH_PRED (BRANCH_PRED)
    ) fetcher (
        .clk (clk_i),
        .resetn (rst_ni),
        .cache_uncompressed (icache),
        .i_pc (wb_if_pc),
        .i_valid (wb_if_valid),
        .i_reason (wb_if_reason),
        .i_prv (prv[0]),
        .i_sum (status.sum),
        .i_atp ({prv == PRIV_LVL_M ? 4'd0 : satp[63:60], satp[59:0]}),
        .o_valid (if_de_valid),
        .o_ready (if_de_ready),
        .o_fetched_instr (if_de_instr)
    );

    // DE-EX interfacing
    logic de_ex_valid;
    logic de_ex_ready;
    decoded_instr_t de_ex_decoded;
    logic [XLEN-1:0] de_ex_rs1;
    logic [XLEN-1:0] de_ex_rs2;

    //
    // DE stage
    //
    logic [4:0] de_rs1_select, de_rs2_select;
    csr_num_e de_csr_sel;
    logic [1:0] de_csr_op;
    logic de_csr_illegal;
    decoded_instr_t de_decoded;

    decoder decoder (
        .fetched_instr (if_de_instr),
        .decoded_instr (de_decoded),
        .prv (prv),
        .status (status),
        .csr_sel (de_csr_sel),
        .csr_op (de_csr_op),
        .csr_illegal (de_csr_illegal)
    );

    assign if_de_ready = !de_ex_valid || de_ex_ready;

    logic int_valid;
    exc_cause_e int_cause;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            de_ex_valid <= 1'b0;
            de_ex_decoded <= decoded_instr_t'('x);
            de_ex_decoded.ex_valid <= 1'b0;
            de_rs1_select <= 'x;
            de_rs2_select <= 'x;
        end
        else begin
            // New inbound data
            if (if_de_valid && if_de_ready) begin
                de_ex_valid <= 1'b1;
                de_ex_decoded <= de_decoded;

                // Interrupt injection
                // FIXME: Prefer trap or interrupt?
                if (!de_decoded.ex_valid && int_valid) begin
                    de_ex_decoded.ex_valid <= 1'b1;
                    de_ex_decoded.exception.cause <= int_cause;
                    de_ex_decoded.exception.tval <= '0;
                end

                // Regfile will read register into rs1_value and rs2_value
                de_rs1_select <= de_decoded.rs1;
                de_rs2_select <= de_decoded.rs2;
            end
            // No new inbound data - deassert valid if ready is asserted.
            else if (de_ex_valid && de_ex_ready) begin
                de_ex_valid <= 1'b0;
            end
        end
    end

    // EX2-WB interfacing
    logic [XLEN-1:0] wb_tvec;

    //
    // EX stage
    //

    typedef enum logic [1:0] {
        ST_NORMAL,
        ST_FLUSH,

        // When the next instruction is an exception, an external interrupt is pending, or
        // when the next instruction is a SYSTEM instruction, we need to drain the pipeline,
        // wait for all issued instructions to commit or trap.
        ST_INT,
        // Waiting for a SYSTEM instruction to complete
        ST_SYS
    } state_e;

    // States of the control logic that handles SYSTEM instructions.
    typedef enum logic [2:0] {
        SYS_IDLE,
        SYS_OP,
        // SATP changed. Wait for cache to ack
        SYS_SATP_CHANGED,
        // SFENCE.VMA is issued. Waiting for flush to completer
        SYS_SFENCE_VMA,
        // Waiting for interrupt to arrive. Clock can be stopped.
        SYS_WFI
    } sys_state_e;

    typedef enum logic [1:0] {
        FU_ALU,
        FU_MEM,
        FU_MUL,
        FU_DIV
    } func_unit_e;

    state_e ex_state_q, ex_state_d;
    sys_state_e sys_state_q, sys_state_d;

    ///////////////////////////////////////////
    // Data Bypass and Data Hazard Detection //
    ///////////////////////////////////////////

    logic data_hazard;
    logic [XLEN-1:0] ex_rs1;
    logic [XLEN-1:0] ex_rs2;

    logic ex1_pending_q;
    logic [4:0] ex1_rd_q;
    logic ex1_data_valid;
    logic [XLEN-1:0] ex1_data;

    logic ex2_pending_q;
    logic [4:0] ex2_rd_q;
    logic ex2_data_valid;
    logic [XLEN-1:0] ex2_data;

    always_comb begin
        data_hazard = 1'b0;

        ex_rs1 = de_ex_rs1;
        // RS1 bypass from EX2
        if (ex2_pending_q && ex2_rd_q == de_ex_decoded.rs1 && de_ex_decoded.rs1 != 0) begin
            if (ex2_data_valid) begin
                ex_rs1 = ex2_data;
            end
            else begin
                data_hazard = 1'b1;
            end
        end
        // RS1 bypass from EX1
        if (ex1_pending_q && ex1_rd_q == de_ex_decoded.rs1 && de_ex_decoded.rs1 != 0) begin
            if (ex1_data_valid) begin
                ex_rs1 = ex1_data;
            end
            else begin
                data_hazard = 1'b1;
            end
        end

        ex_rs2 = de_ex_rs2;
        // RS2 bypass from EX2
        if (ex2_pending_q && ex2_rd_q == de_ex_decoded.rs2 && de_ex_decoded.rs2 != 0) begin
            if (ex2_data_valid) begin
                ex_rs2 = ex2_data;
            end
            else begin
                data_hazard = 1'b1;
            end
        end
        // RS2 bypass from EX1
        if (ex1_pending_q && ex1_rd_q == de_ex_decoded.rs2 && de_ex_decoded.rs2 != 0) begin
            if (ex1_data_valid) begin
                ex_rs2 = ex1_data;
            end
            else begin
                data_hazard = 1'b1;
            end
        end
    end

    ////////////////////////////////
    // Structure Hazard Detection //
    ////////////////////////////////

    logic struct_hazard;

    logic mem_ready;
    logic mul_ready;
    logic div_ready;
    logic sys_ready;
    logic ex1_ready;

    always_comb begin
        // Treat exception and SYSTEM instruction as a structure hazard, because they may influence
        // control registers so they effectively conflict with any other instruction.
        struct_hazard = !ex1_ready || de_ex_decoded.ex_valid;
        unique case (de_ex_decoded.op_type)
            MEM: begin
                if (!mem_ready) struct_hazard = 1'b1;
            end
            MUL: begin
                if (!mul_ready) struct_hazard = 1'b1;
            end
            DIV: begin
                if (!div_ready) struct_hazard = 1'b1;
            end
            SYSTEM: begin
                if (!sys_ready) struct_hazard = 1'b1;
            end
            default:;
        endcase
    end

    //////////////////////////////
    // Control Hazard Detection //
    //////////////////////////////

    logic control_hazard;
    logic [XLEN-1:0] ex_expected_pc_q;
    logic mem_trap_valid;
    exception_t mem_trap;

    always_comb begin
        control_hazard = 1'b0;
        unique case (ex_state_q)
            ST_NORMAL: begin
                control_hazard = ex_expected_pc_q != de_ex_decoded.pc || mem_trap_valid;
            end
            ST_FLUSH: begin
                control_hazard = de_ex_decoded.if_reason ==? 4'bxxx0;
            end
            ST_INT: begin
                control_hazard = 1'b1;
            end
            default:;
        endcase
    end

    ////////////////////////
    // Core State Machine //
    ////////////////////////

    logic [63:0] npc;
    assign npc = de_ex_decoded.pc + (de_ex_decoded.exception.tval[1:0] == 2'b11 ? 4 : 2);

    logic exception_issue;

    logic sys_issue;
    logic sys_pc_redirect_valid;
    if_reason_t sys_pc_redirect_reason;
    logic [XLEN-1:0] sys_pc_redirect_target;

    logic mispredict_q, mispredict_d;

    wire ex_issue = de_ex_valid && !data_hazard && !struct_hazard && !control_hazard;
    assign de_ex_ready = (!data_hazard && !struct_hazard) || control_hazard;

    always_comb begin
        exception_issue = 1'b0;
        sys_issue = 1'b0;

        ex_state_d = ex_state_q;
        mispredict_d = mispredict_q;

        unique case (ex_state_q)
            ST_NORMAL: begin
                if (de_ex_valid && de_ex_ready) mispredict_d = ex_expected_pc_q != de_ex_decoded.pc;
            end
            ST_FLUSH: begin
                mispredict_d = 1'b0;
                if (ex_issue) begin
                    ex_state_d = ST_NORMAL;
                end
            end
            ST_INT: begin
                mispredict_d = 1'b0;
                exception_issue = 1'b1;
                ex_state_d = ST_FLUSH;
            end
            ST_SYS: begin
                sys_issue = 1'b1;
                mispredict_d = 1'b0;
                if (sys_ready) begin
                    ex_state_d = sys_pc_redirect_valid ? ST_FLUSH : ST_NORMAL;
                end
            end
            default:;
        endcase

        if ((ex_state_q == ST_NORMAL || ex_state_q == ST_FLUSH) &&
            de_ex_valid && !control_hazard && !ex1_pending_q && !ex2_pending_q) begin

            if (de_ex_decoded.ex_valid) begin
                ex_state_d = ST_INT;
            end else if (de_ex_decoded.op_type == SYSTEM) begin
                ex_state_d = ST_SYS;
            end
        end

        if (mem_trap_valid) begin
            ex_state_d = ST_FLUSH;
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            ex_state_q <= ST_FLUSH;
            mispredict_q <= 1'b0;
        end
        else begin
            ex_state_q <= ex_state_d;
            mispredict_q <= mispredict_d;
        end
    end

    ///////////////////////////
    // Control State Machine //
    ///////////////////////////

    // CSRs
    csr_num_e csr_select;
    logic [XLEN-1:0] csr_read;
    logic [XLEN-1:0] er_epc;
    assign csr_select = csr_num_e'(de_ex_decoded.exception.tval[31:20]);

    logic wfi_valid;
    logic mem_notif_ready;

    always_comb begin
        sys_ready = 1'b0;
        sys_state_d = sys_state_q;
        sys_pc_redirect_valid = 1'b0;
        sys_pc_redirect_reason = if_reason_t'('x);
        sys_pc_redirect_target = 'x;

        unique case (sys_state_q)
            SYS_IDLE: begin
                if (sys_issue) begin
                    sys_state_d = SYS_OP;
                    unique case (de_ex_decoded.sys_op)
                        CSR: begin
                            if (de_ex_decoded.csr.op != 2'b00 && csr_select == CSR_SATP) sys_state_d = SYS_SATP_CHANGED;
                        end
                        SFENCE_VMA: sys_state_d = SYS_SFENCE_VMA;
                        WFI: sys_state_d = SYS_WFI;
                        default:;
                    endcase
                end
            end
            SYS_OP: begin
                sys_ready = 1'b1;
                sys_state_d = SYS_IDLE;
                unique case (de_ex_decoded.sys_op)
                    // FIXME: Split the state machine
                    CSR: begin
                        sys_pc_redirect_target = npc;
                        if (de_ex_decoded.csr.op != 2'b00) begin
                            case (csr_select)
                                CSR_MSTATUS: begin
                                    sys_pc_redirect_valid = 1'b1;
                                    sys_pc_redirect_reason = IF_PROT_CHANGED;
                                end
                                CSR_SSTATUS: begin
                                    sys_pc_redirect_valid = 1'b1;
                                    sys_pc_redirect_reason = IF_PROT_CHANGED;
                                end
                            endcase
                        end
                    end
                    ERET: begin
                        sys_pc_redirect_valid = 1'b1;
                        sys_pc_redirect_reason = IF_PROT_CHANGED;
                        sys_pc_redirect_target = er_epc;
                    end
                    FENCE_I: begin
                        sys_pc_redirect_valid = 1'b1;
                        sys_pc_redirect_reason = IF_FENCE_I;
                        sys_pc_redirect_target = npc;
                    end
                    default:;
                endcase
            end
            SYS_SATP_CHANGED: begin
                if (mem_notif_ready) begin
                    sys_ready = 1'b1;
                    sys_state_d = SYS_IDLE;
                    sys_pc_redirect_valid = 1'b1;
                    sys_pc_redirect_reason = IF_SATP_CHANGED;
                    sys_pc_redirect_target = npc;
                end
            end
            SYS_SFENCE_VMA: begin
                if (mem_notif_ready) begin
                    sys_ready = 1'b1;
                    sys_state_d = SYS_IDLE;
                    sys_pc_redirect_valid = 1'b1;
                    sys_pc_redirect_reason = IF_SFENCE_VMA;
                    sys_pc_redirect_target = npc;
                end
            end
            SYS_WFI: begin
                if (wfi_valid) begin
                    sys_ready = 1'b1;
                    sys_state_d = SYS_IDLE;
                end
            end
            default:;
        endcase
    end

    // State machine state assignments
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            sys_state_q <= SYS_IDLE;
        end
        else begin
            sys_state_q <= sys_state_d;
        end
    end

    /////////
    // ALU //
    /////////

    wire [63:0] operand_b = de_ex_decoded.use_imm ? de_ex_decoded.immediate : ex_rs2;

    // Adder.
    // This is the core component of the EX stage.
    // It is used for ADD, LOAD, STORE, AUIPC, JAL, JALR, BRANCH
    logic [63:0] sum;
    assign sum = (de_ex_decoded.adder.use_pc ? de_ex_decoded.pc : ex_rs1) + (de_ex_decoded.adder.use_imm ? de_ex_decoded.immediate : ex_rs2);

    // Subtractor.
    // It is used for SUB, BRANCH, SLT, SLTU
    logic [63:0] difference;
    assign difference = ex_rs1 - operand_b;

    // Comparator. Used in BRANCH, SLT, and SLTU
    logic compare_result;
    comparator comparator (
        .operand_a_i  (ex_rs1),
        .operand_b_i  (operand_b),
        .condition_i  (de_ex_decoded.condition),
        .difference_i (difference),
        .result_o     (compare_result)
    );

    // ALU
    logic [63:0] alu_result;
    alu alu (
        .operator      (de_ex_decoded.op),
        .decoded_instr (de_ex_decoded),
        .is_32         (de_ex_decoded.is_32),
        .operand_a     (ex_rs1),
        .operand_b     (operand_b),
        .sum_i         (sum),
        .difference_i  (difference),
        .compare_result_i (compare_result),
        .result           (alu_result)
    );

    ///////////////
    // EX1 stage //
    ///////////////

    // Results to mux from
    logic mem_valid;
    logic [XLEN-1:0] mem_data;
    logic mul_valid;
    logic [XLEN-1:0] mul_data;
    logic div_valid;
    logic [XLEN-1:0] div_data;

    logic ex2_ready;
    assign ex1_ready = ex2_ready || !ex1_pending_q;
    assign ex2_ready = !ex2_pending_q || ex2_data_valid;

    func_unit_e ex1_select_q;
    logic [XLEN-1:0] ex1_alu_data_q;
    logic [XLEN-1:0] ex1_pc_q;

    func_unit_e ex2_select_q;
    logic [XLEN-1:0] ex2_alu_data_q;
    logic [XLEN-1:0] ex2_pc_q;

    always_comb begin
        unique case (ex1_select_q)
            FU_ALU: begin
                ex1_data_valid = 1'b1;
                ex1_data = ex1_alu_data_q;
            end
            FU_MEM: begin
                // If ex2_select_q matches ex1_select_q, then the valid signal is for EX2, so don;t
                // rely on it. The same follows for FU_MUL and FU_DIV.
                ex1_data_valid = mem_valid && ex2_select_q != FU_MEM;
                ex1_data = mem_data;
            end
            FU_MUL: begin
                ex1_data_valid = mul_valid && ex2_select_q != FU_MUL;
                ex1_data = mul_data;
            end
            FU_DIV: begin
                ex1_data_valid = div_valid && ex2_select_q != FU_DIV;
                ex1_data = div_data;
            end
            default: begin
                ex1_data_valid = 1'bx;
                ex1_data = 'x;
            end
        endcase
    end

    logic ex1_pending_d;
    func_unit_e ex1_select_d;
    logic [XLEN-1:0] ex1_alu_data_d;
    logic [XLEN-1:0] ex1_pc_d;
    logic [4:0] ex1_rd_d;
    logic [XLEN-1:0] ex_expected_pc_d;

    always_comb begin
        ex1_pending_d = ex1_pending_q;
        ex1_select_d = ex1_select_q;
        ex1_alu_data_d = ex1_alu_data_q;
        ex1_pc_d = ex1_pc_q;
        ex1_rd_d = ex1_rd_q;
        ex_expected_pc_d = ex_expected_pc_q;

        // If data is already valid but we couldn't move it to EX2, we need to prevent
        // it from being moved to next state.
        if (ex1_data_valid) begin
            ex1_select_d = FU_ALU;
            ex1_alu_data_d = ex1_data;
        end

        // Reset to default values when the instruction progresses to EX2, or when the MEM
        // instruction traps regardless whether it is trapped in EX1 or EX2.
        // If it traps in EX1, then we should cancel it. If it traps in EX2, then any pending
        // non-memory instruction should run to completion, and EX2 will pick that up for us.
        if (ex2_ready || mem_trap_valid) begin
            ex1_pending_d = 1'b0;
            ex1_select_d = FU_ALU;
            ex1_rd_d = '0;
            ex1_alu_data_d = 'x;
        end

        if (ex_issue) begin
            ex1_pending_d = 1'b1;
            ex1_select_d = FU_ALU;
            ex1_pc_d = de_ex_decoded.pc;
            ex1_rd_d = de_ex_decoded.rd;
            ex1_alu_data_d = 'x;

            ex_expected_pc_d = npc;

            case (de_ex_decoded.op_type)
                ALU: begin
                    ex1_alu_data_d = alu_result;
                end
                BRANCH: begin
                    ex1_alu_data_d = npc;
                    ex_expected_pc_d = compare_result ? {sum[63:1], 1'b0} : npc;
                end
                SYSTEM: begin
                    // All other SYSTEM instructions have no return value
                    ex1_alu_data_d = csr_read;
                end
                MEM: begin
                    ex1_select_d = FU_MEM;
                end
                MUL: begin
                    ex1_select_d = FU_MUL;
                end
                DIV: begin
                    ex1_select_d = FU_DIV;
                end
            endcase
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            ex1_pending_q <= 1'b0;
            ex1_select_q <= FU_ALU;
            ex1_rd_q <= '0;
            ex1_alu_data_q <= 'x;
            ex1_pc_q <= 'x;
            ex_expected_pc_q <= '0;
        end
        else begin
            ex1_pending_q <= ex1_pending_d;
            ex1_select_q <= ex1_select_d;
            ex1_alu_data_q <= ex1_alu_data_d;
            ex1_pc_q <= ex1_pc_d;
            ex1_rd_q <= ex1_rd_d;
            ex_expected_pc_q <= ex_expected_pc_d;
        end
    end

    ///////////////
    // EX2 stage //
    ///////////////

    always_comb begin
        unique case (ex2_select_q)
            FU_ALU: begin
                ex2_data_valid = 1'b1;
                ex2_data = ex2_alu_data_q;
            end
            FU_MEM: begin
                ex2_data_valid = mem_valid;
                ex2_data = mem_data;
            end
            FU_MUL: begin
                ex2_data_valid = mul_valid;
                ex2_data = mul_data;
            end
            FU_DIV: begin
                ex2_data_valid = div_valid;
                ex2_data = div_data;
            end
            default: begin
                ex2_data_valid = 1'bx;
                ex2_data = 'x;
            end
        endcase
    end

    logic ex2_pending_d;
    func_unit_e ex2_select_d;
    logic [XLEN-1:0] ex2_alu_data_d;
    logic [XLEN-1:0] ex2_pc_d;
    logic [4:0] ex2_rd_d;

    always_comb begin
        ex2_pending_d = ex2_pending_q;
        ex2_select_d = ex2_select_q;
        ex2_alu_data_d = ex2_alu_data_q;
        ex2_pc_d = ex2_pc_q;
        ex2_rd_d = ex2_rd_q;

        // Reset to default values when committed, or when the MEM traps in EX2 stage.
        // Note that if the trap is in EX1 stage, current instruction in EX2 (if any)
        // should still continue until commit.
        if (ex2_data_valid || (ex2_select_q == FU_MEM && mem_trap_valid)) begin
            ex2_pending_d = 1'b0;
            ex2_select_d = FU_ALU;
            ex2_rd_d = '0;
            ex2_alu_data_d = 'x;
        end

        // If a MEM trap happens in EX2 stage, and EX1 stage is executing a non-memory
        // instruction and not yet completed, if we do nothing we might read out that value
        // after pipeline restarts. As a safeguard, wait until that to complete but don't
        // commit the value.
        if (ex2_select_q == FU_MEM && mem_trap_valid && ex1_select_q != FU_MEM && !ex1_data_valid) begin
            ex2_pending_d = 1'b1;
            ex2_select_d = ex1_select_q;
            ex2_rd_d = '0;
            ex2_alu_data_d = 'x;
        end

        // Progress an instruction from EX1 to EX2.
        // Do not progress an instruction if a MEM traps in EX1. (We don't need to check
        // ex_select to ensure the MEM is not trapped in EX2 here, as otherwise ex_pending
        // is true and ex2_data_valid is false, so this won't be executed anyway)
        if (ex1_pending_q && ex2_ready && !mem_trap_valid) begin
            ex2_pending_d = 1'b1;
            ex2_select_d = ex1_select_q;
            ex2_pc_d = ex1_pc_q;
            ex2_rd_d = ex1_rd_q;
            ex2_alu_data_d = 'x;

            // If data is already valid, then move it to ALU register so that we don't wait
            // for it.
            if (ex1_data_valid) begin
                ex2_select_d = FU_ALU;
                ex2_alu_data_d = ex1_data;
            end
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            ex2_pending_q <= 1'b0;
            ex2_select_q <= FU_ALU;
            ex2_alu_data_q <= 'x;
            ex2_pc_q <= 'x;
            ex2_rd_q <= '0;
        end
        else begin
            ex2_pending_q <= ex2_pending_d;
            ex2_select_q <= ex2_select_d;
            ex2_alu_data_q <= ex2_alu_data_d;
            ex2_pc_q <= ex2_pc_d;
            ex2_rd_q <= ex2_rd_d;
        end
    end

    // Multiplier
    mul_unit mul (
        .clk       (clk_i),
        .rstn      (rst_ni),
        .operand_a (ex_rs1),
        .operand_b (ex_rs2),
        .i_32      (de_ex_decoded.is_32),
        .i_op      (de_ex_decoded.mul.op),
        .i_valid   (ex_issue && de_ex_decoded.op_type == MUL),
        .i_ready   (mul_ready),
        .o_value   (mul_data),
        .o_valid   (mul_valid)
    );

    // Divider
    div_unit div (
        .clk        (clk_i),
        .rstn       (rst_ni),
        .operand_a  (ex_rs1),
        .operand_b  (ex_rs2),
        .use_rem_i  (de_ex_decoded.div.rem),
        .i_32       (de_ex_decoded.is_32),
        .i_unsigned (de_ex_decoded.div.is_unsigned),
        .i_valid    (ex_issue && de_ex_decoded.op_type == DIV),
        .i_ready    (div_ready),
        .o_value    (div_data),
        .o_valid    (div_valid)
    );

    //
    // EX stage - load & store
    //

    assign dcache.req_valid    = ex_issue && de_ex_decoded.op_type == MEM;
    assign dcache.req_op       = de_ex_decoded.mem.op;
    assign dcache.req_amo      = de_ex_decoded.exception.tval[31:25];
    assign dcache.req_address  = sum;
    assign dcache.req_size     = de_ex_decoded.mem.size;
    assign dcache.req_unsigned = de_ex_decoded.mem.zeroext;
    assign dcache.req_value    = ex_rs2;
    assign dcache.req_prv      = data_prv[0];
    assign dcache.req_sum      = status.sum;
    assign dcache.req_mxr      = status.mxr;
    assign dcache.req_atp      = {data_prv == PRIV_LVL_M ? 4'd0 : satp[63:60], satp[59:0]};
    assign mem_valid = dcache.resp_valid;
    assign mem_data  = dcache.resp_value;
    assign mem_trap_valid = dcache.ex_valid;
    assign mem_trap  = dcache.ex_exception;
    assign mem_notif_ready = dcache.notif_ready;
    assign mem_ready = dcache.req_ready;

    assign dcache.notif_valid = sys_state_d == SYS_SFENCE_VMA || (sys_issue && de_ex_decoded.sys_op == CSR && de_ex_decoded.csr.op != 2'b00 && csr_select == CSR_SATP);
    assign dcache.notif_reason = sys_state_d == SYS_SFENCE_VMA;

    //
    // Register file instantiation
    //
    reg_file # (
        .XLEN (XLEN)
    ) regfile (
        .clk (clk_i),
        .rstn (rst_ni),
        .ra_sel (de_rs1_select),
        .ra_data (de_ex_rs1),
        .rb_sel (de_rs2_select),
        .rb_data (de_ex_rs2),
        .w_sel (ex2_rd_q),
        .w_data (ex2_data),
        .w_en (ex2_pending_q && ex2_data_valid)
    );

    muntjac_cs_registers csr_regfile (
        .clk_i,
        .rst_ni,
        .hart_id_i (mhartid),
        .priv_mode_o (prv),
        .priv_mode_lsu_o (data_prv),
        .check_addr_i (de_csr_sel),
        .check_op_i (csr_op_e'(de_csr_op)),
        .check_illegal_o (de_csr_illegal),
        .csr_addr_i (csr_select),
        .csr_wdata_i (de_ex_decoded.csr.imm ? {{(64-5){1'b0}}, de_ex_decoded.rs1} : ex_rs1),
        .csr_op_i (csr_op_e'(de_ex_decoded.csr.op)),
        .csr_op_en_i (ex_issue && de_ex_decoded.op_type == SYSTEM && de_ex_decoded.sys_op == CSR),
        .csr_rdata_o (csr_read),
        .irq_software_m_i (irq_m_software),
        .irq_timer_m_i (irq_m_timer),
        .irq_external_m_i (irq_m_external),
        .irq_external_s_i (irq_s_external),
        .irq_pending_o (wfi_valid),
        .irq_valid_o (int_valid),
        .irq_cause_o (int_cause),
        .satp_o (satp),
        .status_o (status),
        .ex_valid_i (mem_trap_valid || exception_issue),
        .ex_exception_i (mem_trap_valid ? mem_trap : de_ex_decoded.exception),
        .ex_epc_i (mem_trap_valid ? (ex2_pending_q == FU_MEM ? ex2_pc_q : ex1_pc_q) : de_ex_decoded.pc),
        .ex_tvec_o (wb_tvec),
        .er_valid_i (ex_issue && de_ex_decoded.op_type == SYSTEM && de_ex_decoded.sys_op == ERET),
        .er_prv_i (de_ex_decoded.exception.tval[29] ? PRIV_LVL_M : PRIV_LVL_S),
        .er_epc_o (er_epc),
        .instr_ret_i (ex2_pending_q && ex2_data_valid)
    );

    always_comb begin
        wb_if_valid = 1'b0;
        wb_if_reason = if_reason_t'('x);
        wb_if_pc = 'x;

        // WB
        if (mem_trap_valid || exception_issue) begin
            wb_if_pc = wb_tvec;
            wb_if_valid = 1'b1;
            // PRV change
            wb_if_reason = IF_PROT_CHANGED;
        end
        else if (sys_pc_redirect_valid) begin
            wb_if_pc = sys_pc_redirect_target;
            wb_if_valid = 1'b1;
            wb_if_reason = sys_pc_redirect_reason;
        end
        else if (ex_state_q == ST_NORMAL && !mispredict_q && de_ex_valid && control_hazard) begin
            wb_if_pc = ex_expected_pc_q;
            wb_if_valid = 1'b1;
            wb_if_reason = IF_MISPREDICT;
        end
    end

    always_ff @(posedge clk_i) begin
        if (mem_trap_valid || exception_issue) begin
            $display("%t: trap %x", $time, mem_trap_valid ? ex2_pc_q : de_ex_decoded.pc);
        end
    end

    // Debug connections
    assign dbg_pc = ex2_pc_q;

endmodule
