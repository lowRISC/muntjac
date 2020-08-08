// In the current design, we do not allow narrow transactions over AXI bus. Therefore it is essential that the CPU can extract data from wider loads. The module load_aligner can achieve this.
import cpu_common::*;

// The logic can be used for 32-bit users without hassle, simple ensure addr[2] is zero.
function automatic logic is_aligned (
    input logic [2:0] addr,
    input logic [1:0] size
);
    unique case (size)
        2'b00: is_aligned = 1'b1;
        2'b01: is_aligned = addr[0] == 0;
        2'b10: is_aligned = addr[1:0] == 0;
        2'b11: is_aligned = addr == 0;
    endcase
endfunction

// The logic can be used for 32-bit users without hassle.
// Simple ensure addr[2] is zero, and all redundant logic will be optimised out.
function automatic logic [63:0] align_load (
    input logic [63:0] value,
    input logic [2:0]  addr,
    input logic [1:0]  size,
    input logic        is_unsigned
);
    unique case ({is_unsigned, size})
        {1'b0, 2'b00}: unique case (addr[2:0])
            3'h0: align_load = signed'(value[ 0 +: 8]);
            3'h1: align_load = signed'(value[ 8 +: 8]);
            3'h2: align_load = signed'(value[16 +: 8]);
            3'h3: align_load = signed'(value[24 +: 8]);
            3'h4: align_load = signed'(value[32 +: 8]);
            3'h5: align_load = signed'(value[40 +: 8]);
            3'h6: align_load = signed'(value[48 +: 8]);
            3'h7: align_load = signed'(value[56 +: 8]);
            default: align_load = 'x;
        endcase
        {1'b1, 2'b00}: unique case (addr[2:0])
            3'h0: align_load = value[ 0 +: 8];
            3'h1: align_load = value[ 8 +: 8];
            3'h2: align_load = value[16 +: 8];
            3'h3: align_load = value[24 +: 8];
            3'h4: align_load = value[32 +: 8];
            3'h5: align_load = value[40 +: 8];
            3'h6: align_load = value[48 +: 8];
            3'h7: align_load = value[56 +: 8];
            default: align_load = 'x;
        endcase
        {1'b0, 2'b01}: unique case (addr[2:1])
            2'h0: align_load = signed'(value[ 0 +: 16]);
            2'h1: align_load = signed'(value[16 +: 16]);
            2'h2: align_load = signed'(value[32 +: 16]);
            2'h3: align_load = signed'(value[48 +: 16]);
            default: align_load = 'x;
        endcase
        {1'b1, 2'b01}: unique case (addr[2:1])
            2'h0: align_load = value[ 0 +: 16];
            2'h1: align_load = value[16 +: 16];
            2'h2: align_load = value[32 +: 16];
            2'h3: align_load = value[48 +: 16];
            default: align_load = 'x;
        endcase
        {1'b0, 2'b10}: unique case (addr[2])
            1'h0: align_load = signed'(value[ 0 +: 32]);
            1'h1: align_load = signed'(value[32 +: 32]);
            default: align_load = 'x;
        endcase
        {1'b1, 2'b10}: unique case (addr[2])
            1'h0: align_load = value[ 0 +: 32];
            1'h1: align_load = value[32 +: 32];
            default: align_load = 'x;
        endcase
        {1'b0, 2'b11}: align_load = value;
        default: align_load = 'x;
    endcase
endfunction

function automatic logic [7:0] align_strb (
    input  logic [2:0]  addr,
    input  logic [1:0]  size
);
    unique case (size)
        2'b00: align_strb = 'b1 << addr;
        2'b01: align_strb = 'b11 << addr;
        2'b10: align_strb = 'b1111 << addr;
        2'b11: align_strb = 'b11111111;
        default: align_strb = 'x;
    endcase
endfunction

function automatic logic [63:0] align_store (
    input  logic [63:0] value,
    input  logic [2:0]  addr
);
    automatic logic [5:0] addr_bits = {addr, 3'b0};
    align_store = value << addr_bits;
endfunction

// If used with 32-bit atomics, original and operand should be signed-extended
function automatic logic [63:0] do_amo_op (
    input  logic [63:0] original,
    input  logic [63:0] operand,
    input  logic [6:0]  amo
);
    unique case (amo[6:2])
        5'b00001: do_amo_op = operand;
        5'b00000: do_amo_op = original + operand;
        5'b00100: do_amo_op = original ^ operand;
        5'b01100: do_amo_op = original & operand;
        5'b01000: do_amo_op = original | operand;
        5'b10000: do_amo_op = signed'(original) < signed'(operand) ? original : operand;
        5'b10100: do_amo_op = signed'(original) < signed'(operand) ? operand : original;
        5'b11000: do_amo_op = original < operand ? original : operand;
        5'b11100: do_amo_op = original < operand ? operand : original;
        default: do_amo_op = 'x;
    endcase
endfunction

module dcache_uncached # (
    parameter XLEN = 64
) (
    // Interface to CPU
    dcache_intf.provider cache,

    // AXI channel to memory
    axi_channel.master mem
);

    wire clk = cache.clk;
    wire rstn = cache.rstn;

    wire            req_valid    = cache.req_valid;
    wire [XLEN-1:0] req_address  = cache.req_address;
    wire [XLEN-1:0] req_value    = cache.req_value;
    wire mem_op_t   req_op       = cache.req_op;
    wire [1:0]      req_size     = cache.req_size;
    wire            req_unsigned = cache.req_unsigned;
    wire [6:0]      req_amo      = cache.req_amo;
    wire            req_prv      = cache.req_prv;
    wire            req_sum      = cache.req_sum;
    wire            req_mxr      = cache.req_mxr;
    wire [XLEN-1:0] req_atp      = cache.req_atp;

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            cache.notif_ready <= 1'b0;
        end else begin
            cache.notif_ready <= cache.notif_valid;
        end
    end

    localparam ADDR_ALIGN_WIDTH = $clog2(XLEN) - 3;

    enum logic [2:0] {
        // Idle, can accept any requests
        STATE_IDLE,
        STATE_ATP_L1,
        STATE_ATP_L2,
        STATE_ATP_L3,
        // Address issued on AR channel, waiting for data on R channel.
        STATE_WAIT_R,
        // Both address and data issued, waiting for ack on B channel.
        STATE_WAIT_W,
        // Perform AMO ALU operation
        STATE_AMO
    } state;

    logic [XLEN-1:0] address;
    logic [XLEN-1:0] bus_address;
    logic [XLEN-1:0] value;
    logic [1:0] size_latch;
    logic unsigned_latch;
    mem_op_t op;
    logic [6:0] amo;

    logic [7:0] aligned_strb;
    logic [63:0] aligned_data;

    logic ar_valid;
    logic aw_valid;
    logic w_valid;

    assign mem.aw_id     = '0;
    assign mem.aw_len    = 8'h0;
    assign mem.aw_size   = $clog2(XLEN) - 3;
    assign mem.aw_burst  = axi_common::BURST_INCR;
    assign mem.aw_lock   = 1'b0;
    assign mem.aw_cache  = 4'h0;
    assign mem.aw_prot = 3'b000;
    assign mem.aw_qos    = 4'h0;
    assign mem.aw_region = 4'h0;
    assign mem.aw_user   = '0;
    assign mem.w_last    = 1'b1;
    assign mem.w_user    = '0;
    assign mem.ar_id     = '0;
    assign mem.ar_len    = 8'h0;
    assign mem.ar_size   = $clog2(XLEN) - 3;
    assign mem.ar_burst  = axi_common::BURST_INCR;
    assign mem.ar_lock   = 1'b0;
    assign mem.ar_cache  = 4'h0;
    assign mem.ar_prot = 3'b000;
    assign mem.ar_qos    = 4'h0;
    assign mem.ar_region = 4'h0;
    assign mem.ar_user   = '0;

    assign mem.ar_valid = ar_valid;
    assign mem.ar_addr = bus_address;

    assign mem.r_ready = 1'b1;

    assign mem.aw_valid = aw_valid;
    assign mem.aw_addr = bus_address;

    assign mem.w_valid = w_valid;
    assign mem.w_data = aligned_data;
    assign mem.w_strb = aligned_strb;

    assign mem.b_ready = 1'b1;

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            cache.resp_valid <= 1'b0;
            cache.resp_value <= 'x;
            cache.resp_exception <= exception_t'('x);
            cache.resp_exception.valid <= 1'b0;
            bus_address <= 'x;
            address <= 'x;
            value <= 'x;
            size_latch <= 'x;
            unsigned_latch <= 1'bx;
            op <= mem_op_t'('x);
            amo <= 'x;

            ar_valid <= 1'b0;
            aw_valid <= 1'b0;
            w_valid <= 1'b0;

            aligned_strb <= 'x;
            aligned_data <= 'x;

            state <= STATE_IDLE;
        end
        else begin
            cache.resp_valid <= 1'b0;
            cache.resp_exception.valid <= 1'b0;
            unique case (state)
                STATE_IDLE: begin
                    if (req_valid) begin
                        // Default values
                        cache.resp_value <= 'x;
                        cache.resp_exception <= exception_t'('x);
                        cache.resp_exception.valid <= 1'b0;

                        if (is_aligned(req_address, req_size)) begin
                            // Initiate load or store, mark the unit as busy.
                            address <= req_address;
                            size_latch <= req_size;
                            unsigned_latch <= req_unsigned;
                            value <= req_value;
                            op <= req_op;
                            amo <= req_amo;

                            aligned_data <= align_store (
                                .value (req_value),
                                .addr (req_address[ADDR_ALIGN_WIDTH-1:0])
                            );

                            // No address translation, skip
                            if (req_atp[XLEN-1]) begin
                                aligned_strb <= '1;
                                bus_address <= {8'b0, req_atp[43:0], req_address[38:30], 3'b0};
                                ar_valid <= 1'b1;
                                state <= STATE_ATP_L1;
                            end else begin
                                aligned_strb <= align_strb (
                                    .addr (req_address[ADDR_ALIGN_WIDTH-1:0]),
                                    .size (req_size)
                                );

                                bus_address <= req_address;
                                if (req_op != MEM_STORE && req_op != MEM_SC) begin
                                    ar_valid <= 1'b1;

                                    state <= STATE_WAIT_R;
                                end
                                else begin
                                    aw_valid <= 1'b1;
                                    w_valid <= 1'b1;

                                    state <= STATE_WAIT_W;
                                end
                            end
                        end else begin
                            // Trigger exception
                            cache.resp_exception.valid <= 1'b1;
                            cache.resp_exception.mcause_interrupt <= 1'b0;
                            cache.resp_exception.mcause_code <= req_op == MEM_LOAD ? 4'h4 : 4'h6;
                            cache.resp_exception.mtval <= req_address;
                        end
                    end
                end
                STATE_ATP_L1: begin
                    if (mem.ar_ready) begin
                        ar_valid <= 1'b0;
                    end
                    if (mem.r_valid) begin
                        if (mem.r_data[3:0] == 4'b0001) begin
                            // Next-level page table
                            bus_address <= {8'b0, mem.r_data[53:10], address[29:21], 3'b0};
                            ar_valid <= 1'b1;
                            state <= STATE_ATP_L2;
                        end else begin
                            if (mem.r_data[0] == 1'b0 || // Invalid
                                mem.r_data[3:1] == 3'b010 || mem.r_data[3:1] == 3'b110 || // Illegal
                                mem.r_data[6] == 1'b0 || // Not Accessed
                                ((mem.r_data[7] == 1'b0 || mem.r_data[2] == 1'b0) && op != MEM_LOAD) || // Write denied
                                (mem.r_data[1] == 1'b0 && !req_mxr) || // Read Instruction Memory without MXR
                                (mem.r_data[4] == 1'b0 && !req_prv) || // Accessing supervisor memory
                                (mem.r_data[4] && req_prv && !req_sum) || // Accessing user memory without SUM
                                mem.r_data[27:10] != 0) // LSBs not cleared
                            begin
                                // Trigger exception
                                cache.resp_exception.valid <= 1'b1;
                                cache.resp_exception.mcause_interrupt <= 1'b0;
                                cache.resp_exception.mcause_code <= op == MEM_LOAD ? 4'hD : 4'hF;
                                cache.resp_exception.mtval <= address;
                                state <= STATE_IDLE;
                            end else begin
                                aligned_strb <= align_strb (
                                    .addr (address[ADDR_ALIGN_WIDTH-1:0]),
                                    .size (size_latch)
                                );
                                bus_address <= {8'b0, mem.r_data[53:28], address[29:0]};
                                if (op != MEM_STORE && op != MEM_SC) begin
                                    ar_valid <= 1'b1;

                                    state <= STATE_WAIT_R;
                                end
                                else begin
                                    aw_valid <= 1'b1;
                                    w_valid <= 1'b1;

                                    state <= STATE_WAIT_W;
                                end
                            end
                        end
                    end
                end
                STATE_ATP_L2: begin
                    if (mem.ar_ready) begin
                        ar_valid <= 1'b0;
                    end
                    if (mem.r_valid) begin
                        if (mem.r_data[3:0] == 4'b0001) begin
                            // Next-level page table
                            bus_address <= {8'b0, mem.r_data[53:10], address[20:12], 3'b0};
                            ar_valid <= 1'b1;
                            state <= STATE_ATP_L3;
                        end else begin
                            if (mem.r_data[0] == 1'b0 || // Invalid
                                mem.r_data[3:1] == 3'b010 || mem.r_data[3:1] == 3'b110 || // Illegal
                                mem.r_data[6] == 1'b0 || // Not Accessed
                                ((mem.r_data[7] == 1'b0 || mem.r_data[2] == 1'b0) && op != MEM_LOAD) || // Write denied
                                (mem.r_data[1] == 1'b0 && !req_mxr) || // Read Instruction Memory without MXR
                                (mem.r_data[4] == 1'b0 && !req_prv) || // Accessing supervisor memory
                                (mem.r_data[4] && req_prv && !req_sum) || // Accessing user memory without SUM
                                (XLEN == 64 ? mem.r_data[18:10] : mem.r_data[19:10]) != 0) // LSBs not cleared
                            begin
                                // Trigger exception
                                cache.resp_exception.valid <= 1'b1;
                                cache.resp_exception.mcause_interrupt <= 1'b0;
                                cache.resp_exception.mcause_code <= op == MEM_LOAD ? 4'hD : 4'hF;
                                cache.resp_exception.mtval <= address;
                                state <= STATE_IDLE;
                            end else begin
                                aligned_strb <= align_strb (
                                    .addr (address[ADDR_ALIGN_WIDTH-1:0]),
                                    .size (size_latch)
                                );
                                bus_address <= {8'b0, mem.r_data[53:19], address[20:0]};
                                if (op != MEM_STORE && op != MEM_SC) begin
                                    ar_valid <= 1'b1;

                                    state <= STATE_WAIT_R;
                                end
                                else begin
                                    aw_valid <= 1'b1;
                                    w_valid <= 1'b1;

                                    state <= STATE_WAIT_W;
                                end
                            end
                        end
                    end
                end
                STATE_ATP_L3: begin
                    if (mem.ar_ready) begin
                        ar_valid <= 1'b0;
                    end
                    if (mem.r_valid) begin
                        if (mem.r_data[3:0] == 4'b0001 || // Non-Leaf
                            mem.r_data[0] == 1'b0 || // Invalid
                            mem.r_data[3:1] == 3'b010 || mem.r_data[3:1] == 3'b110 || // Illegal
                            mem.r_data[6] == 1'b0 || // Not Accessed
                            ((mem.r_data[7] == 1'b0 || mem.r_data[2] == 1'b0) && op != MEM_LOAD) || // Write denied
                            (mem.r_data[1] == 1'b0 && !req_mxr) || // Read Instruction Memory without MXR
                            (mem.r_data[4] == 1'b0 && !req_prv) || // Accessing supervisor memory
                            (mem.r_data[4] && req_prv && !req_sum)) // Accessing user memory without SUM
                        begin
                            // Trigger exception
                            cache.resp_exception.valid <= 1'b1;
                            cache.resp_exception.mcause_interrupt <= 1'b0;
                            cache.resp_exception.mcause_code <= op == MEM_LOAD ? 4'hD : 4'hF;
                            cache.resp_exception.mtval <= address;
                            state <= STATE_IDLE;
                        end else begin
                            aligned_strb <= align_strb (
                                .addr (address[ADDR_ALIGN_WIDTH-1:0]),
                                .size (size_latch)
                            );
                            bus_address <= {8'b0, mem.r_data[53:10], address[11:0]};
                            if (op != MEM_STORE && op != MEM_SC) begin
                                ar_valid <= 1'b1;

                                state <= STATE_WAIT_R;
                            end
                            else begin
                                aw_valid <= 1'b1;
                                w_valid <= 1'b1;

                                state <= STATE_WAIT_W;
                            end
                        end
                    end
                end
                STATE_WAIT_R: begin
                    if (mem.ar_ready) begin
                        ar_valid <= 1'b0;
                    end
                    if (mem.r_valid) begin
                        cache.resp_value <= align_load(
                            .value (mem.r_data),
                            .addr (address[ADDR_ALIGN_WIDTH-1:0]),
                            .size (size_latch),
                            .is_unsigned (unsigned_latch)
                        );
                        if (op != MEM_AMO) begin
                            cache.resp_valid <= 1'b1;
                            state <= STATE_IDLE;
                        end
                        else begin
                            state <= STATE_AMO;
                        end
                    end
                end
                STATE_AMO: begin
                    aligned_data <= align_store (
                        .value (do_amo_op(signed'(cache.resp_value), signed'(value), amo)),
                        .addr (address[ADDR_ALIGN_WIDTH-1:0])
                    );
                    aw_valid <= 1'b1;
                    w_valid <= 1'b1;
                    state <= STATE_WAIT_W;
                end
                STATE_WAIT_W: begin
                    if (mem.aw_ready) begin
                        aw_valid <= 1'b0;
                    end
                    if (mem.w_ready) begin
                        w_valid <= 1'b0;
                    end
                    if (mem.b_valid) begin
                        unique case (op)
                            MEM_STORE: cache.resp_value <= 'x;
                            MEM_SC: cache.resp_value <= 0;
                            // Keep the loaded value.
                            MEM_AMO:;
                        endcase
                        cache.resp_valid <= 1'b1;
                        state <= STATE_IDLE;
                    end
                end
            endcase
        end
    end

endmodule
