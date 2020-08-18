module icache_uncached # (
    parameter XLEN = 64
) (
    // Interface to CPU
    icache_intf.provider cache,

    // AXI channel to memory
    axi_channel.master mem
);

    import muntjac_pkg::*;

    localparam VA_LEN = XLEN == 64 ? 39 : 32;
    localparam PA_LEN = XLEN == 64 ? 56 : 34;

    wire clk = cache.clk;
    wire rstn = cache.rstn;

    // Bus valid/address that is only high for only cycle
    logic bus_valid;
    logic [PA_LEN-1:0] bus_address;

    enum logic [2:0] {
        STATE_FETCH,
        STATE_EXECPTION,
        STATE_ATP_L3,
        STATE_ATP_L2,
        STATE_ATP_L1
    } state, state_d;

    // Helper signal to detect if cache.req_pc is a canonical address
    // The first part checks if the highest parts are all 0, and the second part checks for all 1.
    wire canonical = !(|cache.req_pc[XLEN-1:VA_LEN-1]) | &cache.req_pc[XLEN-1:VA_LEN-1];

    logic [XLEN-1:0] latched_pc, latched_pc_d;
    logic [PA_LEN-12-1:0] cache_ppn, cache_ppn_d;
    logic [VA_LEN-12-1:0] cache_vpn, cache_vpn_d;
    logic cache_valid, cache_valid_d;

    assign mem.aw_id     = '0;
    assign mem.aw_len    = 0;
    assign mem.aw_size   = $clog2(XLEN) - 3;
    assign mem.aw_burst  = axi_common::BURST_INCR;
    assign mem.aw_lock   = '0;
    assign mem.aw_cache  = '0;
    assign mem.aw_prot   = '0;
    assign mem.aw_qos    = '0;
    assign mem.aw_region = '0;
    assign mem.aw_user   = 'x;
    assign mem.w_user    = 'x;
    assign mem.w_last    = 1'b1;
    assign mem.ar_id     = '0;
    assign mem.ar_len    = 0;
    assign mem.ar_size   = $clog2(XLEN) - 3;
    assign mem.ar_burst  = axi_common::BURST_INCR;
    assign mem.ar_lock   = '0;
    assign mem.ar_cache  = '0;
    assign mem.ar_prot   = '0;
    assign mem.ar_qos    = '0;
    assign mem.ar_region = '0;
    assign mem.ar_user   = 'x;

    always_comb begin
        // By default output to invalid
        cache.resp_valid = 1'b0;
        cache.resp_instr = 'x;
        cache.resp_exception = 1'bx;
        cache.resp_exception_plus2 = 1'b0;

        // By default keep these states
        state_d = state;
        latched_pc_d = latched_pc;
        cache_ppn_d = cache_ppn;
        cache_vpn_d = cache_vpn;
        cache_valid_d = cache_valid;

        bus_valid = 1'b0;
        bus_address = 'x;

        case (state)
            STATE_FETCH: begin
                if (mem.r_valid) begin
                    cache.resp_valid = 1'b1;
                    if (XLEN == 64)
                        cache.resp_instr = latched_pc[2] ? mem.r_data[63:32] : mem.r_data[31:0];
                    else
                        cache.resp_instr = mem.r_data;
                    cache.resp_exception = 1'b0;
                end
            end
            STATE_EXECPTION: begin
                cache.resp_valid = 1'b1;
                cache.resp_exception = 1'b1;
                state_d = STATE_FETCH;
            end
            STATE_ATP_L3: begin
                // This state is not reachable when XLEN == 32
                if (XLEN == 64 && mem.r_valid) begin
                    if (mem.r_data[3:0] == 4'b0001) begin
                        // Next-level page table
                        bus_address = {8'b0, mem.r_data[53:10], latched_pc[29:21], 3'b0};
                        bus_valid = 1'b1;
                        state_d = STATE_ATP_L2;
                    end
                    else begin
                        if (mem.r_data[0] == 1'b0 || // Invalid
                            mem.r_data[3:1] == 3'b010 || mem.r_data[3:1] == 3'b110 || // Illegal
                            mem.r_data[6] == 1'b0 || // Not Accessed
                            (mem.r_data[4] == 1'b0 && !cache.req_prv) || // Accessing supervisor memory
                            (mem.r_data[4] && cache.req_prv && !cache.req_sum) || // Accessing user memory without SUM
                            mem.r_data[27:10] != 0) // LSBs not cleared
                        begin
                            state_d = STATE_EXECPTION;
                        end
                        else begin
                            cache_valid_d = 1'b1;
                            cache_vpn_d = latched_pc[VA_LEN-1:12];
                            cache_ppn_d = {mem.r_data[53:28], latched_pc[29:12]};
                            bus_address = {cache_ppn_d, latched_pc[11:2], 2'b0};
                            bus_valid = 1'b1;
                            state_d = STATE_FETCH;
                        end
                    end
                end
            end
            STATE_ATP_L2: begin
                if (mem.r_valid) begin
                    if (mem.r_data[3:0] == 4'b0001) begin
                        // Next-level page table
                        if (XLEN == 64)
                            bus_address = {8'b0, mem.r_data[53:10], latched_pc[20:12], 3'b0};
                        else
                            bus_address = {mem.r_data[31:10], latched_pc[21:12], 2'b0};
                        bus_valid = 1'b1;
                        state_d = STATE_ATP_L1;
                    end
                    else begin
                        if (mem.r_data[0] == 1'b0 || // Invalid
                            mem.r_data[3:1] == 3'b010 || mem.r_data[3:1] == 3'b110 || // Illegal
                            mem.r_data[6] == 1'b0 || // Not Accessed
                            (mem.r_data[4] == 1'b0 && !cache.req_prv) || // Accessing supervisor memory
                            (mem.r_data[4] && cache.req_prv && !cache.req_sum) || // Accessing user memory without SUM
                            (XLEN == 64 ? mem.r_data[18:10] : mem.r_data[19:10]) != 0) // LSBs not cleared
                        begin
                            state_d = STATE_EXECPTION;
                        end
                        else begin
                            cache_valid_d = 1'b1;
                            cache_vpn_d = latched_pc[VA_LEN-1:12];
                            if (XLEN == 64)
                                cache_ppn_d = {mem.r_data[53:19], latched_pc[20:12]};
                            else
                                cache_ppn_d = {mem.r_data[31:20], latched_pc[21:12]};
                            bus_address = {cache_ppn_d, latched_pc[11:2], 2'b0};
                            bus_valid = 1'b1;
                            state_d = STATE_FETCH;
                        end
                    end
                end
            end
            STATE_ATP_L1: begin
                if (mem.r_valid) begin
                    if (mem.r_data[3:0] == 4'b0001 || // Non-Leaf
                        mem.r_data[0] == 1'b0 || // Invalid
                        mem.r_data[3:1] == 3'b010 || mem.r_data[3:1] == 3'b110 || // Illegal
                        mem.r_data[6] == 1'b0 || // Not Accessed
                        (mem.r_data[4] == 1'b0 && !cache.req_prv) || // Accessing supervisor memory
                        (mem.r_data[4] && cache.req_prv && !cache.req_sum)) // Accessing user memory without SUM
                    begin
                        state_d = STATE_EXECPTION;
                    end
                    else begin
                        cache_valid_d = 1'b1;
                        cache_vpn_d = latched_pc[VA_LEN-1:12];
                        cache_ppn_d = mem.r_data[PA_LEN-2-1:10];
                        bus_address = {cache_ppn_d, latched_pc[11:2], 2'b0};
                        bus_valid = 1'b1;
                        state_d = STATE_FETCH;
                    end
                end
            end
        endcase

        // New requests.
        if (cache.req_valid) begin
            bus_valid = 1'b1;
            latched_pc_d = {cache.req_pc[XLEN-1:1], 1'b0};
            if (!cache.req_atp[XLEN-1]) begin
                bus_address = {cache.req_pc[PA_LEN-1:2], 2'b0};
            end
            else if (!canonical) begin
                bus_valid = 1'b0;
                state_d = STATE_EXECPTION;
            end
            else if (cache_valid && cache.req_reason !=? 4'bxx11 && cache.req_pc[VA_LEN-1:12] == cache_vpn) begin
                bus_address = {cache_ppn, cache.req_pc[11:2], 2'b0};
            end
            else begin
                if (XLEN == 64) begin
                    bus_address = {8'b0, cache.req_atp[43:0], cache.req_pc[38:30], 3'b0};
                    state_d = STATE_ATP_L3;
                end
                else begin
                    bus_address = {cache.req_atp[21:0], cache.req_pc[31:22], 2'b0};
                    state_d = STATE_ATP_L2;
                end
            end

            if (cache.req_reason ==? 4'bxx11) begin
                cache_valid_d = 1'b0;
            end
        end
    end

    // State update
    always_ff @(posedge clk or negedge rstn)
        if (!rstn) begin
            state <= STATE_FETCH;
            latched_pc <= 1'b0;
            cache_vpn <= '0;
            cache_ppn <= '0;
            cache_valid <= 1'b0;
        end else begin
            state <= state_d;
            latched_pc <= latched_pc_d;
            cache_vpn <= cache_vpn_d;
            cache_ppn <= cache_ppn_d;
            cache_valid <= cache_valid_d;
        end

    // We need to hold AXI signals high until ar_ready.
    // Latch represents that the previous request hasn't yet been consumed by AXI.
    logic latched;
    logic [PA_LEN-1:0] latched_address;

    assign mem.aw_addr = 'x;
    assign mem.aw_valid = 0;
    assign mem.w_data = 'x;
    assign mem.w_strb = 'x;
    assign mem.w_valid = 0;
    assign mem.b_ready = 0;
    assign mem.ar_valid = latched ? 1'b1 : bus_valid;
    assign mem.ar_addr = latched ? latched_address: bus_address;
    assign mem.r_ready = 1'b1;

     always_ff @(posedge clk or negedge rstn)
        if (!rstn) begin
            latched <= 1'b0;
            latched_address <= 'x;
        end else begin
            if (bus_valid) begin
                // This is invalid, as latched high indicates the result isn't yet ready!
                assert (!latched);
                latched <= 1'b1;
                latched_address <= bus_address;
            end

            // If mem.ar_ready is high, the request is already consumed by AXI, so don't
            // raise latched.
            // This statement must take priority over `latched <= 1'b1`.
            if (mem.ar_ready) begin
                latched <= 1'b0;
            end
        end

endmodule
