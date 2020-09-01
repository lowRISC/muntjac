import muntjac_pkg::*;

// Instruction fetcher continuously fetch instructions until
// it has encountered a PC override.
module instr_fetcher # (
    parameter XLEN = 64
) (
    input  logic clk_i,
    input  logic rst_ni,

    icache_intf.user icache,

    input  logic [63:0]    satp_i,
    input  priv_lvl_e      prv_i,
    input  status_t        status_i,
    // When the signals are valid, instruction fetcher needs to flush its pipeline
    // and restart fetching from the specified PC.
    input  logic           redirect_valid_i,
    input  if_reason_e     redirect_reason_i,
    input  logic [63:0]    redirect_pc_i,
    input  branch_info_t   branch_info_i,
    output logic           fetch_valid_o,
    input  logic           fetch_ready_i,
    output fetched_instr_t fetch_instr_o
);

    wire [63:0] insn_atp = {prv_i == PRIV_LVL_M ? 4'd0 : satp_i[63:60], satp_i[59:0]};

    logic [XLEN-1:0] i_pc_q;
    if_reason_e i_reason_q;
    logic i_valid_q;
    logic i_ready_q;
    logic [XLEN-1:0] i_atp_q;
    logic i_prv_q;
    logic i_sum_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            // Reset vector
            i_pc_q <= '0;
            i_reason_q <= IF_FENCE_I;
            i_valid_q <= 1'b1;
            i_atp_q <= '0;
            i_prv_q <= 1'b0;
            i_sum_q <= 1'b0;
        end else begin
            if (i_ready_q) begin
                i_valid_q <= 1'b0;
            end
            if (redirect_valid_i) begin
                i_pc_q <= redirect_pc_i;
                i_valid_q <= redirect_valid_i;
                i_reason_q <= redirect_reason_i;
                i_atp_q <= insn_atp;
                i_prv_q <= prv_i[0];
                i_sum_q <= status_i.sum;
            end
        end
    end

    logic [XLEN-1:0] pc;
    logic [XLEN-1:0] npc_word;
    logic [XLEN-1:0] npc;
    if_reason_e reason;

    logic align_ready;
    assign i_ready_q = align_ready;

    logic [XLEN-1:0] pc_next;
    if_reason_e reason_next;

    // We need to latch ATP so that its change does not affect currently prefetched instructions.
    logic [XLEN-1:0] atp_latch;
    logic prv_latch;
    logic sum_latch;

    always_ff @(posedge clk_i or negedge rst_ni)
        if (!rst_ni) begin
            atp_latch <= '0;
            prv_latch <= 1'b0;
            sum_latch <= 1'b0;
        end
        else begin
            if (i_valid_q && i_ready_q) begin
                atp_latch <= i_atp_q;
                prv_latch <= i_prv_q;
                sum_latch <= i_sum_q;
            end
        end

    ///////////////////////
    // Branch Prediction //
    ///////////////////////

    wire [63:0] train_pc = branch_info_i.pc[1] && !branch_info_i.compressed ? branch_info_i.pc + 4 : branch_info_i.pc;
    wire train_partial = branch_info_i.pc[1] ^ branch_info_i.compressed;

    logic         btb_valid_raw;
    branch_type_e btb_type;
    logic         btb_partial;
    logic [63:0]  btb_target;

    wire btb_valid = btb_valid_raw && !(pc[1] && (reason ==? 4'b???1 || btb_partial));

    muntjac_btb #(
        .IndexWidth (6)
    ) btb (
        .clk_i,
        .rst_ni,
        // Only train BTB for jump and taken branches, and only do so when mispredicted
        .train_valid_i        ((branch_info_i.branch_type[2] || branch_info_i.branch_type[0]) && redirect_valid_i),
        .train_branch_type_i  (branch_info_i.branch_type),
        .train_pc_i           (train_pc),
        .train_partial_i      (train_partial),
        .train_npc_i          (redirect_pc_i),
        .access_valid_i       (align_ready),
        .access_pc_i          (pc_next),
        .access_hit_o         (btb_valid_raw),
        .access_branch_type_o (btb_type),
        .access_partial_o     (btb_partial),
        .access_npc_o         (btb_target)
    );

    logic bht_taken;

    muntjac_bp_bimodal #(
        .IndexWidth (9)
    ) bht (
        .clk_i,
        .rst_ni,
        // Only train BHT for branches.
        .train_valid_i  (branch_info_i.branch_type inside {BRANCH_UNTAKEN, BRANCH_TAKEN}),
        // LSB determines whether this is BRANCH_TAKEN or BRANCH_UNTAKEN
        .train_taken_i  (branch_info_i.branch_type[0]),
        .train_pc_i     (train_pc),
        .access_valid_i (align_ready),
        .access_pc_i    (pc_next),
        .access_taken_o (bht_taken)
    );

    //////////////////////////
    // Return address stack //
    //////////////////////////

    logic [63:0] ras_peek_addr;
    logic        ras_peek_valid;

    // Compute RAS action
    wire ras_push = btb_valid && btb_type inside {BRANCH_CALL, BRANCH_YIELD};
    wire ras_pop  = btb_valid && btb_type inside {BRANCH_RET , BRANCH_YIELD};

    logic predict_taken;
    muntjac_ras ras (
        .clk_i,
        .rst_ni,
        .peek_valid_o (ras_peek_valid),
        .peek_addr_o  (ras_peek_addr),
        .pop_spec_i   (ras_pop && align_ready),
        .pop_i        (branch_info_i.branch_type inside {BRANCH_RET, BRANCH_YIELD}),
        .push_spec_i  (ras_push && align_ready),
        .push_i       (branch_info_i.branch_type inside {BRANCH_CALL, BRANCH_YIELD}),
        .push_addr_i  (btb_partial ? {pc[XLEN-1:2], 2'b10} : npc_word),
        .revert_i     (i_valid_q)
    );

    logic [XLEN-1:0] predict_target;
    always_comb begin
        if (btb_valid) begin
            predict_taken = btb_type[2] || bht_taken;
            if (ras_pop && ras_peek_valid) begin
                predict_target = ras_peek_addr;
            end else begin
                predict_target = btb_target;
            end
        end else begin
            predict_taken = 1'b0;
            predict_target = 'x;
        end
    end

    // Compute next PC if no branch is taken.
    // This could be just `pc + (instr_word[1:0] == 2'b11 ? 4 : 2)`, but doing so would make the
    // critical path really long. Therefore we just do `pc + 4` instead, and if we need to do +2,
    // instead, we can use MUX to do that.
    assign npc_word = {pc[XLEN-1:2], 2'b0} + 4;
    assign pc_next = i_valid_q ? {i_pc_q[XLEN-1:1], 1'b0} : (predict_taken ? predict_target : npc_word);
    assign reason_next = i_valid_q ? i_reason_q : (predict_taken ? IF_PREDICT : IF_PREFETCH);

    ///////////////
    // I$ Access //
    ///////////////

    assign icache.req_pc = pc_next;
    assign icache.req_reason = reason_next;
    assign icache.req_valid = align_ready;
    assign icache.req_sum = i_valid_q && i_ready_q ? i_sum_q : sum_latch;
    assign icache.req_atp = i_valid_q && i_ready_q ? i_atp_q : atp_latch;
    assign icache.req_prv = i_valid_q && i_ready_q ? i_prv_q : prv_latch;

    logic resp_latched;
    logic [31:0] resp_instr_latched;
    logic resp_exception_latched;

    wire align_valid = resp_latched ? 1'b1 : icache.resp_valid;
    wire [31:0] align_instr = resp_latched ? resp_instr_latched : icache.resp_instr;
    wire align_exception = resp_latched ? resp_exception_latched : icache.resp_exception;
    wire [63:0] align_pc = pc;
    wire if_reason_e align_reason = reason;
    wire [1:0] align_strb = pc[1] ? 2'b10 : (predict_taken && btb_partial ? 2'b01 : 2'b11);

    always_ff @(posedge clk_i or negedge rst_ni)
        if (!rst_ni) begin
            resp_latched <= 1'b1;
            resp_instr_latched <= '0;
            resp_exception_latched <= 1'b0;

            pc <= 0;
            reason <= IF_PREFETCH;
        end
        else begin
            if (!align_ready && icache.resp_valid) begin
                assert (!resp_latched);
                resp_latched <= 1'b1;
                resp_instr_latched <= icache.resp_instr;
                resp_exception_latched <= icache.resp_exception;
            end

            if (align_ready) begin
                resp_latched <= 1'b0;
                pc <= pc_next;
                reason <= reason_next;
            end
        end

    ///////////////////////////
    // Instruction Alignment //
    ///////////////////////////

    logic prev_valid_q, prev_valid_d;
    logic [63:0] prev_pc_q, prev_pc_d;
    if_reason_e prev_reason_q, prev_reason_d;
    logic [15:0] prev_instr_q, prev_instr_d;

    logic second_half_q, second_half_d;

    logic prev_write;

    always_comb begin
        prev_valid_d = prev_valid_q;
        prev_write = 1'b0;
        align_ready = 1'b0;
        second_half_d = second_half_q;

        fetch_valid_o = 1'b0;
        fetch_instr_o.instr_word = 'x;
        fetch_instr_o.pc = 'x;
        fetch_instr_o.if_reason = if_reason_e'('x);
        fetch_instr_o.ex_valid = 1'b0;
        fetch_instr_o.exception.cause = exc_cause_e'('x);
        fetch_instr_o.exception.tval = 'x;

        if (align_valid && align_exception) begin
            prev_valid_d = 1'b0;

            fetch_valid_o = 1'b1;
            fetch_instr_o.pc = prev_valid_q && align_reason ==? IF_PREFETCH ? prev_pc_q : align_pc;
            fetch_instr_o.if_reason = prev_valid_q && align_reason ==? IF_PREFETCH ? prev_reason_q : align_reason;
            fetch_instr_o.ex_valid = 1'b1;
            fetch_instr_o.exception.cause = EXC_CAUSE_INSTR_PAGE_FAULT;
            fetch_instr_o.exception.tval = align_pc;

            if (fetch_ready_i) align_ready = 1'b1;
        end else if (align_valid && align_strb == 2'b10 && align_instr[17:16] == 2'b11) begin
            // A redirection fetches unaligned 32-bit instruction. Keep the higher half,
            // discard the lower half, without waiting for the fetch_ready_i signal.
            prev_valid_d = 1'b1;
            prev_write = 1'b1;
            second_half_d = 1'b0;

            align_ready = 1'b1;
        end else if (align_valid) begin
            if (fetch_ready_i) begin
                prev_valid_d = 1'b0;
                prev_write = 1'b1;
                second_half_d = 1'b0;
            end

            // If a misaligned fetch is requested, it must be the result of redirection.
            if (align_strb == 2'b10 || second_half_q) begin
                // Otherwise this is a properly aligned compressed instruction, just output it.
                fetch_valid_o = 1'b1;
                fetch_instr_o.pc = {align_pc[63:2], 2'b10};
                fetch_instr_o.if_reason = second_half_q ? IF_PREFETCH : align_reason;
                fetch_instr_o.instr_word = {16'd0, align_instr[31:16]};

                if (fetch_ready_i) align_ready = 1'b1;
            end else begin
                if (prev_valid_q && align_reason ==? IF_PREFETCH) begin
                    // If there is a half word left (and we can use it), then this is the second half
                    // of a misaligned 32-bit instruction.
                    fetch_valid_o = 1'b1;
                    fetch_instr_o.pc = prev_pc_q;
                    fetch_instr_o.if_reason = prev_reason_q;
                    fetch_instr_o.instr_word = {align_instr[15:0], prev_instr_q};

                    // If the second half is also a 32-bit instruction, fetch the next word.
                    if (fetch_ready_i) begin
                        prev_valid_d = 1'b1;

                        if (align_instr[17:16] == 2'b11 || align_strb == 2'b01) begin
                            align_ready = 1'b1;
                        end else begin
                            second_half_d = 1'b1;
                        end
                    end
                end else begin
                    if (align_instr[1:0] == 2'b11) begin
                        // Full instruction, output it.
                        fetch_valid_o = 1'b1;
                        fetch_instr_o.pc = align_pc;
                        fetch_instr_o.if_reason = align_reason;
                        fetch_instr_o.instr_word = align_instr;

                        if (fetch_ready_i) align_ready = 1'b1;
                    end else begin
                        // Compressed instruction, output it.
                        fetch_valid_o = 1'b1;
                        fetch_instr_o.pc = align_pc;
                        fetch_instr_o.if_reason = align_reason;
                        fetch_instr_o.instr_word = {16'd0, align_instr[15:0]};

                        if (fetch_ready_i) begin
                            prev_valid_d = 1'b1;

                            if (align_instr[17:16] == 2'b11 || align_strb == 2'b01) begin
                                // The second half is not compressed instruction, fetch next word
                                align_ready = 1'b1;
                            end else begin
                                second_half_d = 1'b1;
                            end
                        end
                    end
                end
            end
        end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            prev_valid_q <= 1'b0;
            prev_instr_q <= 'x;
            prev_reason_q <= if_reason_e'('x);
            prev_pc_q <= 'x;
            second_half_q <= 1'b0;
        end else begin
            prev_valid_q <= prev_valid_d;
            if (prev_write) begin
                prev_instr_q <= align_instr[31:16];
                prev_pc_q <= {align_pc[63:2], 2'b10};
                prev_reason_q <= align_reason;
            end
            second_half_q <= second_half_d;
        end
    end

endmodule
