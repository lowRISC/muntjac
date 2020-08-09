import riscv::*;
import cpu_common::*;

module cpu #(
    parameter XLEN = 64
) (
    // Clock and reset
    input  logic            clk,
    input  logic            resetn,

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
    logic data_prv;
    logic [XLEN-1:0] data_atp;
    logic [XLEN-1:0] insn_atp;
    prv_t prv;
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
        .clk (clk),
        .resetn (resetn),
        .cache_uncompressed (icache),
        .i_pc (wb_if_pc),
        .i_valid (wb_if_valid),
        .i_reason (wb_if_reason),
        .i_prv (prv[0]),
        .i_sum (status.sum),
        .i_atp (insn_atp),
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
    logic de_ex_handshaked;
    assign de_ex_handshaked = de_ex_valid && de_ex_ready;

    //
    // DE stage
    //
    logic [4:0] de_rs1_select, de_rs2_select;
    csr_t de_csr_sel;
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

    assign if_de_ready = de_ex_ready;

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            de_ex_valid <= 1'b0;
            de_ex_decoded <= decoded_instr_t'('x);
            de_rs1_select <= 'x;
            de_rs2_select <= 'x;
        end
        else begin
            // New inbound data
            if (if_de_valid && if_de_ready) begin
                de_ex_valid <= 1'b1;
                de_ex_decoded <= de_decoded;

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

    // EX-EX2 interfacing
    logic ex1_pending;
    logic ex_ex2_ready;

    // Additional value passed from EX1 to EX2. E.g. store value
    wire ex_ex2_handshaked = ex1_pending && ex_ex2_ready;

    // EX2-WB interfacing
    logic [XLEN-1:0] wb_tvec;

    //
    // EX stage
    //
    logic ex_stalled;
    logic [XLEN-1:0] ex_rs1;
    logic [XLEN-1:0] ex_rs2;

    typedef enum logic [2:0] {
        ST_NORMAL,
        ST_MISPREDICT,
        ST_FLUSH,
        ST_FLUSH2,

        // When the next instruction is an exception, an external interrupt is pending, or
        // when the next instruction is a SYSTEM instruction, we need to drain the pipeline,
        // wait for all issued instructions to commit or trap.
        ST_DRAIN,
        // Waiting for a SYSTEM instruction to complete
        ST_SYS
    } state_e;

    // States of the control logic that handles SYSTEM instructions.
    typedef enum logic [1:0] {
        SYS_IDLE,
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

    // logic ex1_pending;
    logic [4:0] ex1_rd;
    logic ex1_data_valid;
    logic [XLEN-1:0] ex1_alu_data;
    logic [XLEN-1:0] ex1_data;
    // Selecting which unit to choose from
    func_unit_e ex1_select;
    logic [XLEN-1:0] ex1_pc;

    logic ex2_pending;
    logic [4:0] ex2_rd;
    logic ex2_data_valid;
    logic [XLEN-1:0] ex2_data;
    // Selecting which unit to choose from
    func_unit_e ex2_select;
    logic [XLEN-1:0] ex2_pc;

    // Source register bypass and stall detection logic
    always_comb begin
        ex_stalled = 1'b0;

        ex_rs1 = de_ex_rs1;
        // RS1 bypass from EX2
        if (ex2_pending && ex2_rd == de_ex_decoded.rs1 && de_ex_decoded.rs1 != 0) begin
            if (ex2_data_valid) begin
                ex_rs1 = ex2_data;
            end
            else begin
                ex_stalled = 1'b1;
            end
        end
        // RS1 bypass from EX1
        if (ex1_pending && ex1_rd == de_ex_decoded.rs1 && de_ex_decoded.rs1 != 0) begin
            if (ex1_data_valid) begin
                ex_rs1 = ex1_data;
            end
            else begin
                ex_stalled = 1'b1;
            end
        end

        ex_rs2 = de_ex_rs2;
        // RS2 bypass from EX2
        if (ex2_pending && ex2_rd == de_ex_decoded.rs2 && de_ex_decoded.rs2 != 0) begin
            if (ex2_data_valid) begin
                ex_rs2 = ex2_data;
            end
            else begin
                ex_stalled = 1'b1;
            end
        end
        // RS2 bypass from EX1
        if (ex1_pending && ex1_rd == de_ex_decoded.rs2 && de_ex_decoded.rs2 != 0) begin
            if (ex1_data_valid) begin
                ex_rs2 = ex1_data;
            end
            else begin
                ex_stalled = 1'b1;
            end
        end
    end

    //
    // ALU
    //

    logic [63:0] npc;
    assign npc = de_ex_decoded.pc + (de_ex_decoded.exception.mtval[1:0] == 2'b11 ? 4 : 2);

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

    //
    // End ALU
    //

    logic [XLEN-1:0] ex_expected_pc;

    exception_t exception_pending_q, exception_pending_d;
    logic exception_issue;
    logic ex2_int_valid;
    logic [3:0] ex2_int_cause;
    logic ex2_wfi_valid;
    logic ex2_mem_notif_ready;

    exception_t ex2_mem_trap;

    // CSRs
    csr_t csr_select;
    logic [XLEN-1:0] csr_operand;
    logic [XLEN-1:0] csr_read;
    logic [XLEN-1:0] er_epc;
    assign csr_select = csr_t'(de_ex_decoded.exception.mtval[31:20]);
    assign csr_operand = de_ex_decoded.csr.imm ? {{(64-5){1'b0}}, de_ex_decoded.rs1} : ex_rs1;

    // Misprediction control
    logic ex_can_issue;
    logic ex2_can_issue;
    logic no_drain;

    // Connection between control state machine and SYS control state machine
    logic sys_issue;
    logic sys_complete;
    logic sys_pc_redirect_valid;
    if_reason_t sys_pc_redirect_reason;
    logic [XLEN-1:0] sys_pc_redirect_target;

    logic mem_ready;
    logic mul_ready;
    logic div_ready;
    assign mem_ready = dcache.req_ready;

    always_comb begin
        exception_pending_d = exception_pending_q;
        exception_issue = 1'b0;

        de_ex_ready = !ex_stalled && (ex_ex2_ready || !ex1_pending);
        ex_can_issue = 1'b0;
        ex2_can_issue = 1'b0;
        no_drain = 1'b0;
        ex_state_d = ex_state_q;

        if (de_ex_valid && de_ex_ready) begin
            case (de_ex_decoded.op_type)
                MEM: begin
                    if (!mem_ready) de_ex_ready = 1'b0;
                end
                MUL: begin
                    if (!mul_ready) de_ex_ready = 1'b0;
                end
                DIV: begin
                    if (!div_ready) de_ex_ready = 1'b0;
                end
            endcase
        end

        sys_issue = 1'b0;

        unique case (ex_state_q)
            ST_NORMAL, ST_MISPREDICT: begin
                ex_can_issue = ex_expected_pc == de_ex_decoded.pc;
                ex2_can_issue = !ex2_mem_trap.valid;

                if (de_ex_handshaked && ex_expected_pc != de_ex_decoded.pc) begin
                    ex_state_d = ST_MISPREDICT;
                end else if (de_ex_handshaked && ex_expected_pc == de_ex_decoded.pc) begin
                    ex_state_d = ST_NORMAL;
                end
            end
            ST_FLUSH: begin
                ex_can_issue = de_ex_decoded.if_reason !=? 4'bxxx0;
                if (de_ex_handshaked && ex_can_issue) begin
                    ex_state_d = ST_NORMAL;
                end
            end
            ST_FLUSH2: begin
                ex_can_issue = de_ex_decoded.if_reason !=? 4'bxxx0;
                ex2_can_issue = 1'b1;
                if (de_ex_handshaked && ex_can_issue) begin
                    ex_state_d = ST_NORMAL;
                end
            end
            ST_DRAIN: begin
                no_drain = 1'b1;
                de_ex_ready = 1'b0;
                ex2_can_issue = !ex2_mem_trap.valid;
                if (!ex1_pending && !ex2_pending) begin
                    if (exception_pending_q.valid) begin
                        de_ex_ready = 1'b1;
                        exception_issue = 1'b1;
                        ex_state_d = ST_FLUSH;
                    end else begin
                        sys_issue = 1'b1;
                        if (sys_complete) begin
                            de_ex_ready = 1'b1;
                            ex_can_issue = 1'b1;
                            ex_state_d = sys_pc_redirect_valid ? ST_FLUSH2 : ST_NORMAL;
                        end
                    end
                end
            end
            ST_SYS: begin
                no_drain = 1'b1;
                if (sys_complete) begin
                    de_ex_ready = 1'b1;
                    ex_can_issue = 1'b1;
                    ex_state_d = sys_pc_redirect_valid ? ST_FLUSH2 : ST_NORMAL;
                end
            end
            default:;
        endcase

        if (!no_drain && ex_can_issue && de_ex_valid && (
            de_ex_decoded.exception.valid ||
            ex2_int_valid ||
            (de_ex_decoded.op_type == SYSTEM)
        )) begin
            de_ex_ready = 1'b0;
            ex_can_issue = 1'b0;
            ex_state_d = ST_DRAIN;

            exception_pending_d = exception_t'('x);
            exception_pending_d.valid = 1'b0;
            if (de_ex_decoded.exception.valid) begin
                exception_pending_d = de_ex_decoded.exception;
            end else if (ex2_int_valid) begin
                exception_pending_d.valid = 1'b1;
                exception_pending_d.mcause_interrupt <= 1'b1;
                exception_pending_d.mcause_code <= ex2_int_cause;
                exception_pending_d.mtval <= '0;
            end
        end

        if (ex2_mem_trap.valid) begin
            ex_state_d = ST_FLUSH;
        end
    end

    always_comb begin
        sys_complete = 1'b0;
        sys_state_d = sys_state_q;
        sys_pc_redirect_valid = 1'b0;
        sys_pc_redirect_reason = if_reason_t'('x);
        sys_pc_redirect_target = 'x;

        unique case (sys_state_q)
            SYS_IDLE: begin
                if (sys_issue) begin
                    unique case (de_ex_decoded.sys_op)
                        // FIXME: Split the state machine
                        CSR: begin
                            sys_complete = 1'b1;
                            sys_pc_redirect_target = npc;
                            // Because SUM and SATP's mode & ASID bits are all high, we don't need to flush
                            // the pipeline on CSRxxI instructions.
                            if (de_ex_decoded.csr.op != 2'b00 && !de_ex_decoded.csr.imm) begin
                                case (csr_select)
                                    CSR_SATP: begin
                                        sys_complete = 1'b0;
                                        sys_state_d = SYS_SATP_CHANGED;
                                    end
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
                            sys_complete = 1'b1;
                            sys_pc_redirect_valid = 1'b1;
                            sys_pc_redirect_reason = IF_PROT_CHANGED;
                            sys_pc_redirect_target = er_epc;
                        end
                        FENCE_I: begin
                            sys_complete = 1'b1;
                            sys_pc_redirect_valid = 1'b1;
                            sys_pc_redirect_reason = IF_FENCE_I;
                            sys_pc_redirect_target = npc;
                        end
                        SFENCE_VMA: sys_state_d = SYS_SFENCE_VMA;
                        WFI: sys_state_d = SYS_WFI;
                        default: sys_complete = 1'b1;
                    endcase
                end
            end
            SYS_SATP_CHANGED: begin
                if (ex2_mem_notif_ready) begin
                    sys_complete = 1'b1;
                    sys_state_d = SYS_IDLE;
                    sys_pc_redirect_valid = 1'b1;
                    sys_pc_redirect_reason = IF_SATP_CHANGED;
                    sys_pc_redirect_target = npc;
                end
            end
            SYS_SFENCE_VMA: begin
                if (ex2_mem_notif_ready) begin
                    sys_complete = 1'b1;
                    sys_state_d = SYS_IDLE;
                    sys_pc_redirect_valid = 1'b1;
                    sys_pc_redirect_reason = IF_SFENCE_VMA;
                    sys_pc_redirect_target = npc;
                end
            end
            SYS_WFI: begin
                if (ex2_wfi_valid) begin
                    sys_complete = 1'b1;
                    sys_state_d = SYS_IDLE;
                end
            end
            default:;
        endcase
    end

    // State machine state assignments
    always_ff @(posedge clk or negedge resetn)
        if (!resetn) begin
            ex_state_q <= ST_FLUSH;
            sys_state_q <= SYS_IDLE;
            exception_pending_q <= exception_t'('x);
            exception_pending_q.valid <= 1'b0;
        end
        else begin
            ex_state_q <= ex_state_d;
            sys_state_q <= sys_state_d;
            exception_pending_q <= exception_pending_d;
        end

    always_ff @(posedge clk or negedge resetn)
        if (!resetn) begin
            ex1_pending <= 1'b0;
            ex1_select <= FU_ALU;
            ex1_rd <= '0;
            ex1_alu_data <= 'x;
            ex1_pc <= 'x;
            ex_expected_pc <= '0;
        end
        else begin
            // If data is already valid but we couldn't move it to EX2, we need to prevent
            // it from being moved to next state.
            if (ex1_data_valid) begin
                ex1_select <= FU_ALU;
                ex1_alu_data <= ex1_data;
            end

            if (ex_ex2_handshaked) begin
                ex1_pending <= 1'b0;
                ex1_select <= FU_ALU;
                ex1_rd <= '0;
                ex1_alu_data <= 'x;
            end

            if (de_ex_handshaked && ex_can_issue) begin
                ex1_pending <= 1'b1;
                ex1_select <= FU_ALU;
                ex1_pc <= de_ex_decoded.pc;
                ex1_rd <= de_ex_decoded.rd;
                ex1_alu_data <= 'x;

                ex_expected_pc <= npc;

                case (de_ex_decoded.op_type)
                    ALU: begin
                        ex1_alu_data <= alu_result;
                    end
                    BRANCH: begin
                        ex1_alu_data <= npc;
                        ex_expected_pc <= compare_result ? {sum[63:1], 1'b0} : npc;
                    end
                    SYSTEM: begin
                        // All other SYSTEM instructions have no return value
                        ex1_alu_data <= csr_read;
                    end
                    MEM: begin
                        ex1_select <= FU_MEM;
                    end
                    MUL: begin
                        ex1_select <= FU_MUL;
                    end
                    DIV: begin
                        ex1_select <= FU_DIV;
                    end
                endcase
            end
        end

    //
    // EX2 stage
    //

    // Results to mux from
    logic [XLEN-1:0] ex2_alu_data;
    logic mem_valid;
    logic [XLEN-1:0] mem_data;
    logic mul_valid;
    logic [XLEN-1:0] mul_data;
    logic div_valid;
    logic [XLEN-1:0] div_data;

    wire ex2_valid = ex_ex2_handshaked && ex2_can_issue;

    assign ex_ex2_ready = !ex2_pending || ex2_data_valid || ex2_mem_trap.valid;

    always_comb begin
        unique case (ex1_select)
            FU_ALU: begin
                ex1_data_valid = 1'b1;
                ex1_data = ex1_alu_data;
            end
            FU_MEM: begin
                ex1_data_valid = mem_valid;
                ex1_data = mem_data;
            end
            FU_MUL: begin
                ex1_data_valid = mul_valid;
                ex1_data = mul_data;
            end
            FU_DIV: begin
                ex1_data_valid = div_valid;
                ex1_data = div_data;
            end
            default: begin
                ex1_data_valid = 1'bx;
                ex1_data = 'x;
            end
        endcase
    end

    always_comb begin
        unique case (ex2_select)
            FU_ALU: begin
                ex2_data_valid = 1'b1;
                ex2_data = ex2_alu_data;
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

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
            ex2_pending <= 1'b0;
            ex2_select <= FU_ALU;
            ex2_alu_data <= 'x;
            ex2_pc <= 'x;
            ex2_rd <= '0;
        end
        else begin
            if (ex2_data_valid || ex2_mem_trap.valid) begin
                // Reset to default values.
                ex2_pending <= 1'b0;
                ex2_rd <= '0;
                ex2_select <= FU_ALU;
            end

            if (ex_ex2_handshaked && ex2_can_issue) begin
                ex2_pending <= 1'b1;
                ex2_select <= ex1_select;
                ex2_pc <= ex1_pc;
                ex2_rd <= ex1_rd;
                ex2_alu_data <= 'x;

                // If data is already valid, then move it to ALU register so that we don't wait
                // for other components.
                if (ex1_data_valid) begin
                    ex2_select <= FU_ALU;
                    ex2_alu_data <= ex1_data;
                end
            end
        end
    end

    // Multiplier
    mul_unit mul (
        .clk       (clk),
        .rstn      (resetn),
        .operand_a (ex_rs1),
        .operand_b (ex_rs2),
        .i_32      (de_ex_decoded.is_32),
        .i_op      (de_ex_decoded.mul.op),
        .i_valid   (de_ex_handshaked && ex_can_issue && de_ex_decoded.op_type == MUL),
        .i_ready   (mul_ready),
        .o_value   (mul_data),
        .o_valid   (mul_valid)
    );

    // Divider
    div_unit div (
        .clk        (clk),
        .rstn       (resetn),
        .operand_a  (ex_rs1),
        .operand_b  (ex_rs2),
        .use_rem_i  (de_ex_decoded.div.rem),
        .i_32       (de_ex_decoded.is_32),
        .i_unsigned (de_ex_decoded.div.is_unsigned),
        .i_valid    (de_ex_handshaked && ex_can_issue && de_ex_decoded.op_type == DIV),
        .i_ready    (div_ready),
        .o_value    (div_data),
        .o_valid    (div_valid)
    );

    //
    // EX stage - load & store
    //

    assign dcache.req_valid    = de_ex_handshaked && ex_can_issue && de_ex_decoded.op_type == MEM;
    assign dcache.req_op       = de_ex_decoded.mem.op;
    assign dcache.req_amo      = de_ex_decoded.exception.mtval[31:25];
    assign dcache.req_address  = sum;
    assign dcache.req_size     = de_ex_decoded.mem.size;
    assign dcache.req_unsigned = de_ex_decoded.mem.zeroext;
    assign dcache.req_value    = ex_rs2;
    assign dcache.req_prv      = data_prv;
    assign dcache.req_sum      = status.sum;
    assign dcache.req_mxr      = status.mxr;
    assign dcache.req_atp      = data_atp;
    assign mem_valid = dcache.resp_valid;
    assign mem_data  = dcache.resp_value;
    assign ex2_mem_trap  = dcache.resp_exception;
    assign ex2_mem_notif_ready = dcache.notif_ready;

    assign dcache.notif_valid = sys_state_d == SYS_SFENCE_VMA || (sys_issue && de_ex_decoded.op_type == SYSTEM && de_ex_decoded.sys_op == CSR && de_ex_decoded.csr.op != 2'b00 && !de_ex_decoded.csr.imm && csr_select == CSR_SATP);
    assign dcache.notif_reason = sys_state_d == SYS_SFENCE_VMA;

    //
    // Register file instantiation
    //
    reg_file # (
        .XLEN (XLEN)
    ) regfile (
        .clk (clk),
        .rstn (resetn),
        .ra_sel (de_rs1_select),
        .ra_data (de_ex_rs1),
        .rb_sel (de_rs2_select),
        .rb_data (de_ex_rs2),
        .w_sel (ex2_rd),
        .w_data (ex2_data),
        .w_en (ex2_pending && ex2_data_valid)
    );

    csr_regfile # (
        .XLEN (XLEN)
    ) csr_regfile (
        .clk (clk),
        .resetn (resetn),
        .pc_sel (de_csr_sel),
        .pc_op (de_csr_op),
        .pc_illegal (de_csr_illegal),
        .a_valid (de_ex_handshaked && ex_can_issue && de_ex_decoded.op_type == SYSTEM && de_ex_decoded.sys_op == CSR),
        .a_sel (csr_select),
        .a_op (de_ex_decoded.csr.op),
        .a_data (csr_operand),
        .a_read (csr_read),
        .ex_valid (ex2_mem_trap.valid || exception_issue),
        .ex_exception (ex2_mem_trap.valid ? ex2_mem_trap : exception_pending_q),
        .ex_epc (ex2_mem_trap.valid ? ex2_pc : de_ex_decoded.pc),
        .ex_tvec (wb_tvec),
        .er_valid (de_ex_handshaked && ex_can_issue && de_ex_decoded.op_type == SYSTEM && de_ex_decoded.sys_op == ERET),
        .er_prv (de_ex_decoded.exception.mtval[29] ? PRV_M : PRV_S),
        .er_epc (er_epc),
        .int_valid (ex2_int_valid),
        .int_cause (ex2_int_cause),
        .wfi_valid (ex2_wfi_valid),
        .mhartid (mhartid),
        .hpm_instret (ex2_pending && ex2_data_valid),
        .*
    );

    always_comb begin
        wb_if_valid = 1'b0;
        wb_if_reason = if_reason_t'('x);
        wb_if_pc = 'x;

        // WB
        if (ex2_mem_trap.valid || exception_issue) begin
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
        else if (ex_state_q == ST_NORMAL && de_ex_handshaked && ex_expected_pc != de_ex_decoded.pc) begin
            wb_if_pc = ex_expected_pc;
            wb_if_valid = 1'b1;
            wb_if_reason = IF_MISPREDICT;
        end
    end

    always_ff @(posedge clk) begin
        if (ex2_mem_trap.valid || exception_issue) begin
            $display("%t: trap %x", $time, ex2_mem_trap.valid ? ex2_pc : de_ex_decoded.pc);
        end
    end

    // Debug connections
    assign dbg_pc = ex2_pc;

endmodule
