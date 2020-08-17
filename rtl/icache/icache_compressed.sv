// This module can convert a misaligned & compressed instruction un-aware instruction cache to a
// cache that can properly support compressed and misaligned instruction.
module icache_compressed # (
    parameter XLEN = 64
) (
    // Interface to CPU
    icache_intf.provider cache,

    // I-Cache that does not support compressed instruction or misaligned instructions
    icache_intf.user mem
);

    import muntjac_pkg::*;

    wire clk = cache.clk;
    wire rstn = cache.rstn;

    // Some common simulators cannot handle interface signals in always_comb block properly.
    wire mem_resp_valid = mem.resp_valid;
    wire [XLEN-1:0] mem_resp_pc = mem.resp_pc;
    wire [31:0] mem_resp_instr = mem.resp_instr;
    wire mem_resp_exception = mem.resp_exception;
    wire cache_req_valid = cache.req_valid;
    wire [XLEN-1:0] cache_req_pc = cache.req_pc;
    wire if_reason_e cache_req_reason = cache.req_reason;

    // Pass these "always valid" signals to the underlying icache.
    assign mem.req_prv = cache.req_prv;
    assign mem.req_sum = cache.req_sum;
    assign mem.req_atp = cache.req_atp;

    // Fill with cache.req_pc from last cycle, which we need to reply to cache.resp_pc.
    logic [XLEN-1:0] latched_pc, latched_pc_d;

    // Set when we are fetching the first part of a misaligned instruction.
    logic fetch_first_half, fetch_first_half_d;

    // If the previous fetch retrieves the upper half but not use them, they will be stored here to
    // avoid fetching two words in next instruction fetch.
    // This include two scenarios:
    // * A word-aligned fetch fetches a compressed instruction
    // * Two second fetch of a non-aligned fetch fetches a uncompressed instruction
    logic [15:0] prev_instr, prev_instr_d;
    logic prev_valid, prev_valid_d;

    // In the case we already have the upper half of an instruction, we need to increment the PC to
    // fetch the next word. To avoid having this in the combinational path (which is our critical
    // path). Therefore, whenever we fetch an instruction, we store an incremented PC here, so when
    // the next fetch uses the upper part of current fetch, we can immediately use the incremented
    // PC.
    // This should be `(mem.req_pc &~ 3) + 4` from last cycle.
    logic [XLEN-1:0] next_pc, next_pc_d;

    always_comb begin
        // By default output to invalid
        mem.req_valid = 1'b0;
        mem.req_pc = 'x;
        mem.req_reason = if_reason_e'('x);
        cache.resp_valid = 1'b0;
        cache.resp_pc = 'x;
        cache.resp_instr = 'x;
        cache.resp_exception = 1'bx;

        // By default keep these states
        latched_pc_d = latched_pc;
        fetch_first_half_d = fetch_first_half;
        prev_instr_d = prev_instr;
        prev_valid_d = prev_valid;
        next_pc_d = next_pc;

        if (mem_resp_valid) begin
            prev_instr_d = 'x;
            prev_valid_d = 1'b0;

            // Exception happens
            if (mem_resp_exception) begin
                cache.resp_valid = 1'b1;
                cache.resp_pc = mem_resp_pc;
                cache.resp_exception = 1'b1;
            end
            else begin
                // If we are fetching the first half of a unaligned 32-bit instruction.
                if (fetch_first_half && mem_resp_instr[17:16] == 2'b11) begin
                    // Keep the higher half, discard the lower half.
                    prev_instr_d = mem_resp_instr[31:16];
                    prev_valid_d = 1'b1;

                    // And fetch the next word.
                    mem.req_valid = 1'b1;
                    mem.req_pc = next_pc;
                    next_pc_d = next_pc + 4;
                    mem.req_reason = IF_PREFETCH;
                    fetch_first_half_d = 1'b0;
                end
                else begin
                    cache.resp_valid = 1'b1;
                    cache.resp_pc = latched_pc;
                    if (latched_pc[1] == 1'b0) begin
                        if (mem_resp_instr[1:0] == 2'b11) begin
                            // A properly aligned uncompressed instruction
                            cache.resp_instr = mem_resp_instr;
                        end
                        else begin
                            // A word-aligned compressed instruction. We'll need upper half later.
                            cache.resp_instr = {16'b0, mem_resp_instr[15:0]};
                            prev_instr_d = mem_resp_instr[31:16];
                            prev_valid_d = 1'b1;
                        end
                    end
                    else begin
                        if (fetch_first_half) begin
                            // If fetch_first_half is true, it means we didn't fetch the second word
                            // for a misaligned address. This means we encountered a compressed
                            // instruction in the higher half.
                            cache.resp_instr = {16'b0, mem_resp_instr[31:16]};
                        end
                        else begin
                            // A misaligned uncompressed instruction. Reassemble it, and keep the
                            // upper half.
                            cache.resp_instr = {mem_resp_instr[15:0], prev_instr};
                            prev_instr_d = mem_resp_instr[31:16];
                            prev_valid_d = 1'b1;
                        end
                    end
                    cache.resp_exception = 1'b0;
                end
            end
        end

        if (cache_req_valid) begin
            mem.req_valid = 1'b1;
            mem.req_pc = cache_req_pc;
            mem.req_reason = cache_req_reason;
            latched_pc_d = cache_req_pc;
            next_pc_d = {cache_req_pc[XLEN-1:2], 2'b0} + 4;

            // For unaligned load we assume we first fetch the first half.
            fetch_first_half_d = cache_req_pc[1] == 1'b1;

            // Unless we already have the first half. Note that we will refetch
            // if the instruction is 16-bit to save a little bit logic.
            if (prev_valid_d && cache_req_reason ==? IF_PREFETCH && prev_instr_d[1:0] == 2'b11) begin
                mem.req_pc = next_pc;
                next_pc_d = next_pc + 4;
                // NOTE: if we already have the higher half, but the higher half is a compressed
                // instruction, we will generate an additional fetch. This is for convenience only.
                // However this violates the semantics of IF_PREFETCH for a cache that isn't
                // misaligned-aware. This is okay for now as our underlying cache does not treat
                // IF_PREFETCH and IF_PREDICT differently.
                mem.req_reason = IF_PREFETCH;
                fetch_first_half_d = 1'b0;
            end
        end
    end

    // State update
    always_ff @(posedge clk or negedge rstn)
        if (!rstn) begin
            latched_pc <= 'x;
            fetch_first_half <= 1'b0;
            prev_instr <= 'x;
            prev_valid <= 1'b0;
            next_pc <= 'x;
        end
        else begin
            latched_pc <= latched_pc_d;
            fetch_first_half <= fetch_first_half_d;
            prev_instr <= prev_instr_d;
            prev_valid <= prev_valid_d;
            next_pc <= next_pc_d;
        end

endmodule
