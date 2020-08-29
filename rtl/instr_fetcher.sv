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

    icache_intf cache (clk_i, rst_ni);
    icache_compressed comp_inst (cache, icache);

    logic [XLEN-1:0] pc;
    logic [XLEN-1:0] npc_word;
    logic [XLEN-1:0] npc;
    if_reason_e reason;

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

    assign cache.req_pc = pc_next;
    assign cache.req_reason = reason_next;
    assign cache.req_valid = fetch_valid_o && fetch_ready_i;
    assign cache.req_sum = i_valid_q && i_ready_q ? i_sum_q : sum_latch;
    assign cache.req_atp = i_valid_q && i_ready_q ? i_atp_q : atp_latch;
    assign cache.req_prv = i_valid_q && i_ready_q ? i_prv_q : prv_latch;

    logic latched;
    logic [31:0] resp_instr_latch;
    logic resp_exception_latch;
    logic resp_exception_plus2_latch;

    assign fetch_valid_o = cache.resp_valid || latched;
    assign i_ready_q = fetch_valid_o && fetch_ready_i;

    always_ff @(posedge clk_i or negedge rst_ni)
        if (!rst_ni) begin
            // To kick-start the frontend, we need fetch_valid_o to be high initially.
            latched <= 1'b1;
            resp_instr_latch <= '0;
            resp_exception_latch <= 1'b0;
            resp_exception_plus2_latch <= 1'b0;

            pc <= 0;
            reason <= IF_PREFETCH;
        end
        else begin
            if (!fetch_ready_i && cache.resp_valid) begin
                assert (!latched);
                latched <= 1'b1;
                resp_instr_latch <= cache.resp_instr;
                resp_exception_latch <= cache.resp_exception;
                resp_exception_plus2_latch <= cache.resp_exception_plus2;
            end

            if (fetch_ready_i) begin
                latched <= 1'b0;
            end

            if (fetch_valid_o && fetch_ready_i) begin
                pc <= pc_next;
                reason <= reason_next;
            end
        end

    assign fetch_instr_o.instr_word = latched ? resp_instr_latch : cache.resp_instr;
    assign fetch_instr_o.pc = pc;
    assign fetch_instr_o.if_reason = reason;
    assign fetch_instr_o.ex_valid = latched ? resp_exception_latch : cache.resp_exception;
    assign fetch_instr_o.exception.cause = EXC_CAUSE_INSTR_PAGE_FAULT;
    assign fetch_instr_o.exception.tval = (latched ? resp_exception_plus2_latch : cache.resp_exception_plus2) ? npc_word : pc;

    //
    // Static branch prediction
    //

    wire [XLEN-1:0] instr_word = latched ? resp_instr_latch : cache.resp_instr;

    ///////////////////////
    // Branch Prediction //
    ///////////////////////

    logic         btb_valid;
    branch_type_e btb_type;
    logic [63:0]  btb_target;

    muntjac_btb #(
        .IndexWidth (6)
    ) btb (
        .clk_i,
        .rst_ni,
        // Only train BTB for jump and taken branches, and only do so when mispredicted
        .train_valid_i        ((branch_info_i.branch_type[2] || branch_info_i.branch_type[0]) && redirect_valid_i),
        .train_branch_type_i  (branch_info_i.branch_type),
        .train_pc_i           (branch_info_i.pc),
        .train_npc_i          (redirect_pc_i),
        .access_valid_i       (fetch_valid_o && fetch_ready_i),
        .access_pc_i          (pc_next),
        .access_hit_o         (btb_valid),
        .access_branch_type_o (btb_type),
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
        .train_pc_i     (branch_info_i.pc),
        .access_valid_i (fetch_valid_o && fetch_ready_i),
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

    muntjac_ras ras (
        .clk_i,
        .rst_ni,
        .peek_valid_o (ras_peek_valid),
        .peek_addr_o  (ras_peek_addr),
        .pop_spec_i   (ras_pop && fetch_valid_o && fetch_ready_i),
        .pop_i        (branch_info_i.branch_type inside {BRANCH_RET, BRANCH_YIELD}),
        .push_spec_i  (ras_push && fetch_valid_o && fetch_ready_i),
        .push_i       (branch_info_i.branch_type inside {BRANCH_CALL, BRANCH_YIELD}),
        .push_addr_i  (npc),
        .revert_i     (i_valid_q)
    );

    logic predict_taken;
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
    always_comb begin
        npc = npc_word;
        if (instr_word[1:0] == 2'b11) begin
            // Need to do +4, so copy bit 1.
            npc[1] = pc[1];
        end
        else if (!pc[1]) begin
            // Need to do +2.
            // If pc[1] is 1, zeroing out bit 1 and +4 is exactly +2.
            // If pc[1] is 0, just keep the higher bit and set bit 1 to 1.
            npc = {pc[XLEN-1:2], 2'b10};
        end
    end

    assign pc_next = i_valid_q ? {i_pc_q[XLEN-1:1], 1'b0} : (predict_taken ? predict_target : npc);
    assign reason_next = i_valid_q ? i_reason_q : (predict_taken ? IF_PREDICT : IF_PREFETCH);

endmodule
