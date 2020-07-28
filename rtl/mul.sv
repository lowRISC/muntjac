module mul_unit (
    // Clock and reset
    input  logic        clk,
    input  logic        rstn,

    input  logic [63:0] operand_a,
    input  logic [63:0] operand_b,
    input  logic [1:0]  i_op,
    input  logic        i_32,
    input  logic        i_valid,

    output logic [63:0] o_value,
    output logic        o_valid
);

    // This multiplication unit will split operation into 17x17 multiplication, so that the 18x18
    // or 18x25 DSP units on FPGA can be utilised. We only use 1 of those DSP units.
    //
    // MULW -> 4 cycles
    // MUL  -> 11 cycles
    // MULH -> 17 cycles

    // FSM States
    enum logic {
        IDLE,
        BUSY
    } state = IDLE, state_d;
    logic [1:0] a_idx, a_idx_d;
    logic [1:0] b_idx, b_idx_d;

    // Latched input operands. We latch them instead of using the combinational input for timing
    // proposes.
    logic [64:0] op_a, op_a_d;
    logic [64:0] op_b, op_b_d;
    logic op_l, op_l_d;
    logic op_32, op_32_d;

    // Multadd
    logic [36:0] accum, accum_d;
    logic [16:0] mac_op_a;
    logic [16:0] mac_op_b;
    logic [36:0] mac_prod;

    // Output signals
    logic o_valid_d;
    logic [63:0] o_value_d;

    // Perform multiplication
    always_comb begin
        unique case (a_idx)
            0: mac_op_a = op_a[15:0];
            1: mac_op_a = op_a[31:16];
            2: mac_op_a = op_a[47:32];
            3: mac_op_a = op_a[64:48];
            default: mac_op_a = 'x;
        endcase
        unique case (b_idx)
            0: mac_op_b = op_b[15:0];
            1: mac_op_b = op_b[31:16];
            2: mac_op_b = op_b[47:32];
            3: mac_op_b = op_b[64:48];
            default: mac_op_b = 'x;
        endcase
        mac_prod = signed'(accum) + signed'(mac_op_a) * signed'(mac_op_b);
    end

    always_comb begin
        op_a_d = op_a;
        op_b_d = op_b;
        op_l_d = op_l;
        op_32_d = op_32;
        state_d = state;
        accum_d = 'x;
        o_value_d = 'x;
        o_valid_d = 1'b0;

        a_idx_d = 'x;
        b_idx_d = 'x;

        unique case (state)
            IDLE: begin
                if (i_valid) begin
                    op_a_d = {i_op != 2'b11 ? operand_a[63] : 1'b0, operand_a};
                    op_b_d = {i_op[1] != 1'b1 ? operand_b[63] : 1'b0, operand_b};
                    op_l_d = i_op == 2'b00;
                    op_32_d = i_32;

                    o_value_d = 'x;
                    accum_d = '0;
                    a_idx_d = 0;
                    b_idx_d = 0;
                    state_d = BUSY;
                end
            end
            BUSY: begin
                accum_d = mac_prod;
                o_value_d = o_value;

                unique case ({a_idx, b_idx})
                    {2'd0, 2'd0}: begin
                        o_value_d[15:0] = mac_prod[15:0];
                        accum_d = signed'(mac_prod[36:16]);
                        a_idx_d = 1;
                        b_idx_d = 0;
                    end

                    {2'd1, 2'd0}: begin
                        a_idx_d = 0;
                        b_idx_d = 1;
                    end
                    {2'd0, 2'd1}: begin
                        o_value_d[63:16] = signed'(mac_prod[15:0]);
                        if (op_32) begin
                            o_valid_d = 1'b1;
                            accum_d = 'x;
                            state_d = IDLE;
                        end else begin
                            accum_d = signed'(mac_prod[36:16]);
                            a_idx_d = 0;
                            b_idx_d = 2;
                        end
                    end

                    {2'd0, 2'd2}: begin
                        a_idx_d = 1;
                        b_idx_d = 1;
                    end
                    {2'd1, 2'd1}: begin
                        a_idx_d = 2;
                        b_idx_d = 0;
                    end
                    {2'd2, 2'd0}: begin
                        o_value_d[47:32] = mac_prod[15:0];
                        accum_d = signed'(mac_prod[36:16]);
                        a_idx_d = 3;
                        b_idx_d = 0;
                    end

                    {2'd3, 2'd0}: begin
                        a_idx_d = 2;
                        b_idx_d = 1;
                    end
                    {2'd2, 2'd1}: begin
                        a_idx_d = 1;
                        b_idx_d = 2;
                    end
                    {2'd1, 2'd2}: begin
                        a_idx_d = 0;
                        b_idx_d = 3;
                    end
                    {2'd0, 2'd3}: begin
                        o_value_d[63:48] = mac_prod[15:0];
                        if (op_l) begin
                            o_valid_d = 1'b1;
                            accum_d = 'x;
                            state_d = IDLE;
                        end else begin
                            accum_d = signed'(mac_prod[36:16]);
                            a_idx_d = 1;
                            b_idx_d = 3;
                        end
                    end

                    {2'd1, 2'd3}: begin
                        a_idx_d = 2;
                        b_idx_d = 2;
                    end
                    {2'd2, 2'd2}: begin
                        a_idx_d = 3;
                        b_idx_d = 1;
                    end
                    {2'd3, 2'd1}: begin
                        o_value_d[15:0] = mac_prod[15:0];
                        accum_d = signed'(mac_prod[36:16]);
                        a_idx_d = 3;
                        b_idx_d = 2;
                    end

                    {2'd3, 2'd2}: begin
                        a_idx_d = 2;
                        b_idx_d = 3;
                    end
                    {2'd2, 2'd3}: begin
                        o_value_d[31:16] = mac_prod[15:0];
                        accum_d = signed'(mac_prod[36:16]);
                        a_idx_d = 3;
                        b_idx_d = 3;
                    end

                    {2'd3, 2'd3}: begin
                        o_value_d[63:32] = mac_prod;
                        o_valid_d = 1'b1;
                        accum_d = 'x;
                        state_d = IDLE;
                    end
                endcase
            end
        endcase
    end

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            state <= IDLE;
            op_a <= 'x;
            op_b <= 'x;
            op_l <= 1'bx;
            op_32 <= 1'bx;
            accum <= '0;
            o_valid <= 1'b0;
            o_value <= 'x;
            a_idx <= 'x;
            b_idx <= 'x;
        end else begin
            state <= state_d;
            op_a <= op_a_d;
            op_b <= op_b_d;
            op_l <= op_l_d;
            op_32 <= op_32_d;
            accum <= accum_d;
            o_valid <= o_valid_d;
            o_value <= o_value_d;
            a_idx <= a_idx_d;
            b_idx <= b_idx_d;
        end
    end

endmodule

module div_unit (
    // Clock and reset
    input  logic        clk,
    input  logic        rstn,

    input  logic [63:0] operand_a,
    input  logic [63:0] operand_b,
    input  logic        i_unsigned,
    input  logic        i_32,
    input  logic        i_valid,

    output logic [63:0] o_quo,
    output logic [63:0] o_rem,
    output logic        o_valid
);

    logic a_sign;
    logic b_sign;
    logic [63:0] a_mag;
    logic [63:0] b_mag;
    logic [63:0] a_rev;

    // Prepare the input by extracting sign, mangitude and deal with sign-extension
    always_comb begin
        if (i_32 == 1'b0) begin
            if (i_unsigned == 1'b0 && operand_a[63]) begin
                a_sign = 1'b1;
                a_mag = -operand_a;
            end else begin
                a_sign = 1'b0;
                a_mag = operand_a;
            end

            if (i_unsigned == 1'b0 && operand_b[63]) begin
                b_sign = 1'b1;
                b_mag = -operand_b;
            end else begin
                b_sign = 1'b0;
                b_mag = operand_b;
            end

            for (int i = 0; i < 64; i++) a_rev[i] = a_mag[63 - i];
        end else begin
            if (i_unsigned == 1'b0 && operand_a[31]) begin
                a_sign = 1'b1;
                a_mag = -signed'(operand_a[31:0]);
            end else begin
                a_sign = 1'b0;
                a_mag = operand_a[31:0];
            end

            if (i_unsigned == 1'b0 && operand_b[31]) begin
                b_sign = 1'b1;
                b_mag = -signed'(operand_b[31:0]);
            end else begin
                b_sign = 1'b0;
                b_mag = operand_b[31:0];
            end

            a_rev[63:32] = 0;
            for (int i = 0; i < 32; i++) a_rev[i] = a_mag[31 - i];
        end
    end

    logic [63:0] a, a_d;
    logic [63:0] b, b_d;
    logic        quo_neg, quo_neg_d;
    logic        rem_neg, rem_neg_d;
    logic        o_32, o_32_d;
    // Number of iterations left. If this is zero, it means we are idle waiting for input.
    logic [6:0]  iter, iter_d;
    logic [63:0] quo, quo_d;
    logic [63:0] rem, rem_d;
    logic o_valid_d;
    logic [63:0] o_quo_d, o_rem_d;

    always_comb begin
        // Shifters
        iter_d = iter - 1;
        quo_d = {quo, 1'b0};
        rem_d = {rem, a[0]};
        a_d = a[63:1];

        // Keep those values constant
        b_d = b;
        quo_neg_d = quo_neg;
        rem_neg_d = rem_neg;
        o_32_d = o_32;

        // Output are invalid unless otherwise specified
        o_valid_d = 1'b0;
        o_quo_d = 'x;
        o_rem_d = 'x;

        if (iter == 0) begin
            if (i_valid) begin
                iter_d = i_32 ? 32 : 64;
                quo_d = 0;
                rem_d = 0;
                a_d = a_rev;
                b_d = b_mag;
                // If we are dividing some by zero, the circuit will produce '1 as the quotient.
                // So we should not negate it, even if a_sign is negative.
                quo_neg_d = a_sign ^ b_sign && b_mag != 0;
                rem_neg_d = a_sign;
                o_32_d = i_32;
            end else begin
                iter_d = 0;
            end
        end else begin
            if (rem_d >= b) begin
                rem_d = rem_d - b;
                quo_d[0] = 1'b1;
            end

            if (iter_d == 0) begin
                o_valid_d = 1'b1;
                o_quo_d = quo_neg ? -quo_d : quo_d;
                o_rem_d = rem_neg ? -rem_d : rem_d;
                if (o_32) begin
                    o_quo_d = signed'(o_quo_d[31:0]);
                    o_rem_d = signed'(o_rem_d[31:0]);
                end
            end
        end
    end

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            iter <= 0;
            quo <= 'x;
            rem <= 'x;
            a <= 'x;
            b <= 'x;
            quo_neg <= 'x;
            rem_neg <= 'x;
            o_32 <= 'x;
            o_valid <= 1'b0;
            o_quo <= 'x;
            o_rem <= 'x;
        end else begin
            iter <= iter_d;
            quo <= quo_d;
            rem <= rem_d;
            a <= a_d;
            b <= b_d;
            quo_neg <= quo_neg_d;
            rem_neg <= rem_neg_d;
            o_32 <= o_32_d;
            o_valid <= o_valid_d;
            o_quo <= o_quo_d;
            o_rem <= o_rem_d;
        end
    end

endmodule
