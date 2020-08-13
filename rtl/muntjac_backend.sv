module muntjac_backend import cpu_common::*; import muntjac_pkg::*; (
    // Clock and reset
    input  logic            clk_i,
    input  logic            rst_ni,

    // LSU interface
    dcache_intf.user dcache,

    // Interface with frontend
    output logic [63:0]   satp_o,
    output priv_lvl_e     prv_o,
    output status_t       status_o,
    output logic          redirect_valid_o,
    output if_reason_t    redirect_reason_o,
    output logic [63:0]   redirect_pc_o,
    input                 fetch_valid_i,
    output                fetch_ready_o,
    input fetched_instr_t fetch_instr_i,

    // Interrupts
    input  logic irq_software_m_i,
    input  logic irq_timer_m_i,
    input  logic irq_external_m_i,
    input  logic irq_external_s_i,

    input  logic [63:0] hart_id_i,

    // Debug connections
    output logic [63:0]    dbg_pc_o
);

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
        SYS_ST_IDLE,
        SYS_ST_OP,
        // SATP changed. Wait for cache to ack
        SYS_ST_SATP_CHANGED,
        // SFENCE.VMA is issued. Waiting for flush to completer
        SYS_ST_SFENCE_VMA,
        // Waiting for interrupt to arrive. Clock can be stopped.
        SYS_ST_WFI
    } sys_state_e;

    typedef enum logic [1:0] {
        FU_ALU,
        FU_MEM,
        FU_MUL,
        FU_DIV
    } func_unit_e;

    /////////////
    // Decoder //
    /////////////

    logic de_ex_valid;
    logic de_ex_ready;
    decoded_instr_t de_ex_decoded;
    logic [63:0] de_ex_rs1;
    logic [63:0] de_ex_rs2;

    logic [4:0] de_rs1_select, de_rs2_select;
    csr_num_e de_csr_sel;
    csr_op_e de_csr_op;
    logic de_csr_illegal;
    decoded_instr_t de_decoded;

    decoder decoder (
        .fetched_instr (fetch_instr_i),
        .decoded_instr (de_decoded),
        .prv (prv_o),
        .status (status_o),
        .csr_sel (de_csr_sel),
        .csr_op (de_csr_op),
        .csr_illegal (de_csr_illegal)
    );

    assign fetch_ready_o = !de_ex_valid || de_ex_ready;

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
            if (fetch_valid_i && fetch_ready_o) begin
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

    ///////////////////////////////////////////
    // Data Bypass and Data Hazard Detection //
    ///////////////////////////////////////////

    logic data_hazard;
    logic [63:0] ex_rs1;
    logic [63:0] ex_rs2;

    logic ex1_pending_q;
    logic [4:0] ex1_rd_q;
    logic ex1_data_valid;
    logic [63:0] ex1_data;

    logic ex2_pending_q;
    logic [4:0] ex2_rd_q;
    logic ex2_data_valid;
    logic [63:0] ex2_data;

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
    logic ex1_ready;

    always_comb begin
        // Treat exception and SYSTEM instruction as a structure hazard, because they may influence
        // control registers so they effectively conflict with any other instruction.
        struct_hazard = !ex1_ready || de_ex_decoded.ex_valid;
        unique case (de_ex_decoded.op_type)
            OP_MEM: begin
                if (!mem_ready) struct_hazard = 1'b1;
            end
            OP_MUL: begin
                if (!mul_ready) struct_hazard = 1'b1;
            end
            OP_DIV: begin
                if (!div_ready) struct_hazard = 1'b1;
            end
            OP_SYSTEM: struct_hazard = 1'b1;
            default:;
        endcase
    end

    //////////////////////////////
    // Control Hazard Detection //
    //////////////////////////////

    state_e ex_state_q, ex_state_d;
    sys_state_e sys_state_q, sys_state_d;

    logic control_hazard;
    logic sys_ready;
    logic [63:0] ex_expected_pc_q;
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
            ST_SYS: begin
                // This will allow us to consume the SYSTEM instruction.
                // Note that ex_issue will not be high when SYSTEM instruction is consumed, but
                // rather we inject it into EX1 stage via sys_issue.
                control_hazard = sys_ready;
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
    logic [63:0] sys_pc_redirect_target;

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
            end else if (de_ex_decoded.op_type == OP_SYSTEM) begin
                sys_issue = 1'b1;
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
    logic [63:0] csr_read;
    logic [63:0] er_epc;
    assign csr_select = csr_num_e'(de_ex_decoded.exception.tval[31:20]);

    logic wfi_valid;
    logic mem_notif_ready;

    logic [63:0] eret_pc_q, eret_pc_d;

    always_comb begin
        sys_ready = 1'b0;
        sys_state_d = sys_state_q;
        sys_pc_redirect_valid = 1'b0;
        sys_pc_redirect_reason = if_reason_t'('x);
        sys_pc_redirect_target = 'x;
        eret_pc_d = 'x;

        unique case (sys_state_q)
            SYS_ST_IDLE: begin
                if (sys_issue) begin
                    sys_state_d = SYS_ST_OP;
                    unique case (de_ex_decoded.sys_op)
                        SYS_CSR: begin
                            if (de_ex_decoded.csr.op != CSR_OP_READ && csr_select == CSR_SATP) begin
                                sys_state_d = SYS_ST_SATP_CHANGED;
                            end
                        end
                        SYS_ERET: begin
                            eret_pc_d = er_epc;
                        end
                        SYS_SFENCE_VMA: begin
                            sys_state_d = SYS_ST_SFENCE_VMA;
                        end
                        SYS_WFI: sys_state_d = SYS_ST_WFI;
                        default:;
                    endcase
                end
            end
            SYS_ST_OP: begin
                sys_ready = 1'b1;
                sys_state_d = SYS_ST_IDLE;
                unique case (de_ex_decoded.sys_op)
                    // FIXME: Split the state machine
                    SYS_CSR: begin
                        sys_pc_redirect_target = npc;
                        if (de_ex_decoded.csr.op != CSR_OP_READ) begin
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
                    SYS_ERET: begin
                        sys_pc_redirect_valid = 1'b1;
                        sys_pc_redirect_reason = IF_PROT_CHANGED;
                        sys_pc_redirect_target = eret_pc_q;
                    end
                    SYS_FENCE_I: begin
                        sys_pc_redirect_valid = 1'b1;
                        sys_pc_redirect_reason = IF_FENCE_I;
                        sys_pc_redirect_target = npc;
                    end
                    default:;
                endcase
            end
            SYS_ST_SATP_CHANGED: begin
                if (mem_notif_ready) begin
                    sys_ready = 1'b1;
                    sys_state_d = SYS_ST_IDLE;
                    sys_pc_redirect_valid = 1'b1;
                    sys_pc_redirect_reason = IF_SATP_CHANGED;
                    sys_pc_redirect_target = npc;
                end
            end
            SYS_ST_SFENCE_VMA: begin
                if (mem_notif_ready) begin
                    sys_ready = 1'b1;
                    sys_state_d = SYS_ST_IDLE;
                    sys_pc_redirect_valid = 1'b1;
                    sys_pc_redirect_reason = IF_SFENCE_VMA;
                    sys_pc_redirect_target = npc;
                end
            end
            SYS_ST_WFI: begin
                if (wfi_valid) begin
                    sys_ready = 1'b1;
                    sys_state_d = SYS_ST_IDLE;
                end
            end
            default:;
        endcase
    end

    // State machine state assignments
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            sys_state_q <= SYS_ST_IDLE;
            eret_pc_q <= 'x;
        end
        else begin
            sys_state_q <= sys_state_d;
            eret_pc_q <= eret_pc_d;
        end
    end

    /////////
    // ALU //
    /////////

    // ALU
    logic [63:0] sum;
    logic        compare_result;
    logic [63:0] alu_result;
    muntjac_alu alu (
        .decoded_op_i     (de_ex_decoded),
        .rs1_i            (ex_rs1),
        .rs2_i            (ex_rs2),
        .sum_o            (sum),
        .compare_result_o (compare_result),
        .result_o         (alu_result)
    );

    ///////////////
    // EX1 stage //
    ///////////////

    // Results to mux from
    logic mem_valid;
    logic [63:0] mem_data;
    logic mul_valid;
    logic [63:0] mul_data;
    logic div_valid;
    logic [63:0] div_data;

    logic ex2_ready;
    assign ex1_ready = ex2_ready || !ex1_pending_q;
    assign ex2_ready = !ex2_pending_q || ex2_data_valid;

    func_unit_e ex1_select_q;
    logic [63:0] ex1_alu_data_q;
    logic [63:0] ex1_pc_q;

    func_unit_e ex2_select_q;
    logic [63:0] ex2_alu_data_q;
    logic [63:0] ex2_pc_q;

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
    logic [63:0] ex1_alu_data_d;
    logic [63:0] ex1_pc_d;
    logic [4:0] ex1_rd_d;
    logic [63:0] ex_expected_pc_d;

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

        unique case (1'b1)
            ex_issue: begin
                ex1_pending_d = 1'b1;
                ex1_select_d = FU_ALU;
                ex1_pc_d = de_ex_decoded.pc;
                ex1_rd_d = de_ex_decoded.rd;
                ex1_alu_data_d = 'x;

                ex_expected_pc_d = npc;

                unique case (de_ex_decoded.op_type)
                    OP_ALU: begin
                        ex1_alu_data_d = alu_result;
                    end
                    OP_BRANCH: begin
                        ex1_alu_data_d = npc;
                        ex_expected_pc_d = compare_result ? {sum[63:1], 1'b0} : npc;
                    end
                    OP_MEM: begin
                        ex1_select_d = FU_MEM;
                    end
                    OP_MUL: begin
                        ex1_select_d = FU_MUL;
                    end
                    OP_DIV: begin
                        ex1_select_d = FU_DIV;
                    end
                    default:;
                endcase
            end
            sys_issue: begin
                // Injection from control state machine when a SYSTEM instruction is being processed.
                // Otherwise equivalent to ex_issue
                ex1_pending_d = 1'b1;
                ex1_select_d = FU_ALU;
                ex1_pc_d = de_ex_decoded.pc;
                ex1_rd_d = de_ex_decoded.rd;
                ex1_alu_data_d = 'x;

                ex_expected_pc_d = npc;

                // All other SYSTEM instructions have no return value
                ex1_alu_data_d = csr_read;
            end
            default:;
        endcase
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
    logic [63:0] ex2_alu_data_d;
    logic [63:0] ex2_pc_d;
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
        // FIXME: This will incorrectly increment instret by 1.
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
        .i_32      (de_ex_decoded.word),
        .i_op      (de_ex_decoded.mul.op),
        .i_valid   (ex_issue && de_ex_decoded.op_type == OP_MUL),
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
        .i_32       (de_ex_decoded.word),
        .i_unsigned (de_ex_decoded.div.is_unsigned),
        .i_valid    (ex_issue && de_ex_decoded.op_type == OP_DIV),
        .i_ready    (div_ready),
        .o_value    (div_data),
        .o_valid    (div_valid)
    );

    //
    // EX stage - load & store
    //

    priv_lvl_e data_prv;
    assign dcache.req_valid    = ex_issue && de_ex_decoded.op_type == OP_MEM;
    assign dcache.req_op       = de_ex_decoded.mem.op;
    assign dcache.req_amo      = de_ex_decoded.exception.tval[31:25];
    assign dcache.req_address  = sum;
    assign dcache.req_size     = de_ex_decoded.mem.size;
    assign dcache.req_unsigned = de_ex_decoded.mem.zeroext;
    assign dcache.req_value    = ex_rs2;
    assign dcache.req_prv      = data_prv[0];
    assign dcache.req_sum      = status_o.sum;
    assign dcache.req_mxr      = status_o.mxr;
    assign dcache.req_atp      = {data_prv == PRIV_LVL_M ? 4'd0 : satp_o[63:60], satp_o[59:0]};
    assign mem_valid = dcache.resp_valid;
    assign mem_data  = dcache.resp_value;
    assign mem_trap_valid = dcache.ex_valid;
    assign mem_trap  = dcache.ex_exception;
    assign mem_notif_ready = dcache.notif_ready;
    assign mem_ready = dcache.req_ready;

    assign dcache.notif_valid = sys_state_q == SYS_ST_IDLE && (sys_state_d == SYS_ST_SFENCE_VMA || sys_state_d == SYS_ST_SATP_CHANGED);
    assign dcache.notif_reason = sys_state_d == SYS_ST_SFENCE_VMA;

    //
    // Register file instantiation
    //
    reg_file # (
        .XLEN (64)
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

    logic [63:0] wb_tvec;
    muntjac_cs_registers csr_regfile (
        .clk_i,
        .rst_ni,
        .hart_id_i (hart_id_i),
        .priv_mode_o (prv_o),
        .priv_mode_lsu_o (data_prv),
        .check_addr_i (de_csr_sel),
        .check_op_i (csr_op_e'(de_csr_op)),
        .check_illegal_o (de_csr_illegal),
        .csr_addr_i (csr_select),
        .csr_wdata_i (de_ex_decoded.csr.imm ? {{(64-5){1'b0}}, de_ex_decoded.rs1} : ex_rs1),
        .csr_op_i (de_ex_decoded.csr.op),
        .csr_op_en_i (sys_issue && de_ex_decoded.sys_op == SYS_CSR),
        .csr_rdata_o (csr_read),
        .irq_software_m_i (irq_software_m_i),
        .irq_timer_m_i (irq_timer_m_i),
        .irq_external_m_i (irq_external_m_i),
        .irq_external_s_i (irq_external_s_i),
        .irq_pending_o (wfi_valid),
        .irq_valid_o (int_valid),
        .irq_cause_o (int_cause),
        .satp_o (satp_o),
        .status_o (status_o),
        .ex_valid_i (mem_trap_valid || exception_issue),
        .ex_exception_i (mem_trap_valid ? mem_trap : de_ex_decoded.exception),
        .ex_epc_i (mem_trap_valid ? (ex2_pending_q == FU_MEM ? ex2_pc_q : ex1_pc_q) : de_ex_decoded.pc),
        .ex_tvec_o (wb_tvec),
        .er_valid_i (sys_issue && de_ex_decoded.sys_op == SYS_ERET),
        .er_prv_i (de_ex_decoded.exception.tval[29] ? PRIV_LVL_M : PRIV_LVL_S),
        .er_epc_o (er_epc),
        .instr_ret_i (ex2_pending_q && ex2_data_valid)
    );

    always_comb begin
        redirect_valid_o = 1'b0;
        redirect_reason_o = if_reason_t'('x);
        redirect_pc_o = 'x;

        // WB
        if (mem_trap_valid || exception_issue) begin
            redirect_pc_o = wb_tvec;
            redirect_valid_o = 1'b1;
            // PRV change
            redirect_reason_o = IF_PROT_CHANGED;
        end
        else if (sys_pc_redirect_valid) begin
            redirect_pc_o = sys_pc_redirect_target;
            redirect_valid_o = 1'b1;
            redirect_reason_o = sys_pc_redirect_reason;
        end
        else if (ex_state_q == ST_NORMAL && !mispredict_q && de_ex_valid && control_hazard) begin
            redirect_pc_o = ex_expected_pc_q;
            redirect_valid_o = 1'b1;
            redirect_reason_o = IF_MISPREDICT;
        end
    end

    always_ff @(posedge clk_i) begin
        if (mem_trap_valid || exception_issue) begin
            $display("%t: trap %x", $time, mem_trap_valid ? ex2_pc_q : de_ex_decoded.pc);
        end
    end

    // Debug connections
    assign dbg_pc_o = ex2_pc_q;

endmodule