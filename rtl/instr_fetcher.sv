import muntjac_pkg::*;

// Instruction fetcher continuously fetch instructions until
// it has encountered a PC override.
module instr_fetcher # (
    parameter XLEN = 64
) (
    input  logic clk,
    input  logic resetn,

    icache_intf.user cache_uncompressed,

    // When the signals are valid, instruction fetcher needs to flush its pipeline
    // and restart fetching from the specified PC.
    input  [XLEN-1:0] i_pc,
    input  branch_info_t i_branch_info,
    input  if_reason_e i_reason,
    input  i_valid,

    // These should always be valid.
    input  logic           i_prv,
    input  logic           i_sum,
    input  [XLEN-1:0] i_atp,

    output logic o_valid,
    input  logic o_ready,
    output fetched_instr_t o_fetched_instr
);

    logic [XLEN-1:0] i_pc_q;
    if_reason_e i_reason_q;
    logic i_valid_q;
    logic i_ready_q;
    logic [XLEN-1:0] i_atp_q;
    logic i_prv_q;
    logic i_sum_q;

    always_ff @(posedge clk or negedge resetn) begin
        if (!resetn) begin
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
            if (i_valid) begin
                i_pc_q <= i_pc;
                i_valid_q <= i_valid;
                i_reason_q <= i_reason;
                i_atp_q <= i_atp;
                i_prv_q <= i_prv;
                i_sum_q <= i_sum;
            end
        end
    end

    icache_intf cache (clk, resetn);
    icache_compressed comp_inst (cache, cache_uncompressed);

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

    always_ff @(posedge clk or negedge resetn)
        if (!resetn) begin
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
    assign cache.req_valid = o_valid && o_ready;
    assign cache.req_sum = i_valid_q && i_ready_q ? i_sum_q : sum_latch;
    assign cache.req_atp = i_valid_q && i_ready_q ? i_atp_q : atp_latch;
    assign cache.req_prv = i_valid_q && i_ready_q ? i_prv_q : prv_latch;

    logic latched;
    logic [31:0] resp_instr_latch;
    logic resp_exception_latch;
    logic resp_exception_plus2_latch;

    assign o_valid = cache.resp_valid || latched;
    assign i_ready_q = o_valid && o_ready;

    always_ff @(posedge clk or negedge resetn)
        if (!resetn) begin
            // To kick-start the frontend, we need o_valid to be high initially.
            latched <= 1'b1;
            resp_instr_latch <= '0;
            resp_exception_latch <= 1'b0;
            resp_exception_plus2_latch <= 1'b0;

            pc <= 0;
            reason <= IF_PREFETCH;
        end
        else begin
            if (!o_ready && cache.resp_valid) begin
                assert (!latched);
                latched <= 1'b1;
                resp_instr_latch <= cache.resp_instr;
                resp_exception_latch <= cache.resp_exception;
                resp_exception_plus2_latch <= cache.resp_exception_plus2;
            end

            if (o_ready) begin
                latched <= 1'b0;
            end

            if (o_valid && o_ready) begin
                pc <= pc_next;
                reason <= reason_next;
            end
        end

    assign o_fetched_instr.instr_word = latched ? resp_instr_latch : cache.resp_instr;
    assign o_fetched_instr.pc = pc;
    assign o_fetched_instr.if_reason = reason;
    assign o_fetched_instr.ex_valid = latched ? resp_exception_latch : cache.resp_exception;
    assign o_fetched_instr.exception.cause = EXC_CAUSE_INSTR_PAGE_FAULT;
    assign o_fetched_instr.exception.tval = (latched ? resp_exception_plus2_latch : cache.resp_exception_plus2) ? npc_word : pc;

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
        .clk_i                (clk),
        .rst_ni               (resetn),
        // Only train BTB for jump and taken branches, and only do so when mispredicted
        .train_valid_i        ((i_branch_info.branch_type[2] || i_branch_info.branch_type[0]) && i_valid),
        .train_branch_type_i  (i_branch_info.branch_type),
        .train_pc_i           (i_branch_info.pc),
        .train_npc_i          (i_pc),
        .access_valid_i       (o_valid && o_ready),
        .access_pc_i          (pc_next),
        .access_hit_o         (btb_valid),
        .access_branch_type_o (btb_type),
        .access_npc_o         (btb_target)
    );

    logic bht_taken;

    muntjac_bp_bimodal #(
        .IndexWidth (9)
    ) bht (
        .clk_i          (clk),
        .rst_ni         (resetn),
        // Only train BHT for branches.
        .train_valid_i  (i_branch_info.branch_type[2:1] == 2'b01),
        // LSB determines whether this is BRANCH_TAKEN or BRANCH_UNTAKEN
        .train_taken_i  (i_branch_info.branch_type[0]),
        .train_pc_i     (i_branch_info.pc),
        .access_valid_i (o_valid && o_ready),
        .access_pc_i    (pc_next),
        .access_taken_o (bht_taken)
    );

    //////////////////////////
    // Return address stack //
    //////////////////////////

    logic [63:0] ras_peek_addr;
    logic        ras_peek_valid;

    // Compute RAS action
    logic ras_push;
    logic ras_pop;

    muntjac_ras ras (
        .clk_i (clk),
        .rst_ni (resetn),
        .peek_valid_o (ras_peek_valid),
        .peek_addr_o  (ras_peek_addr),
        .pop_spec_i   (ras_pop && o_valid && o_ready),
        .pop_i        (i_branch_info.branch_type[2] && i_branch_info.branch_type[1]),
        .push_spec_i  (ras_push && o_valid && o_ready),
        .push_i       (i_branch_info.branch_type[2] && i_branch_info.branch_type[0]),
        .push_addr_i  (npc),
        .revert_i     (i_valid_q)
    );

    always_comb begin
        ras_push = btb_valid && btb_type[2] && btb_type[0];
        ras_pop  = btb_valid && btb_type[2] && btb_type[1];
    end

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
