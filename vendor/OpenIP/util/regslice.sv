/*
 * Copyright (c) 2018, Gary Guo
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 *  * Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 * CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH
 * DAMAGE.
 */

// An utility for time insulation and pipelining support. It can break combinatorial path between valid/ready
// interface. It is essentially a shallow FIFO.
//
// FORWARD: Add register stage between w_valid/data and r_valid/data.
// REVERSE: Add register stage between r_ready and w_ready.
// HIGH_PERFORMANCE: If both FORWARD and REVERSE are set, set HIGH_PERFORMANCE to 1 allows 100% throughput while set
//     HIGH_PERFORMANCE to 0 will create bubbles and allows 50% throughput only. This parameter is only honoured if
//     both FORWARD and REVERSE are 1.
module openip_regslice #(
    parameter DATA_WIDTH       = 1,
    parameter type TYPE        = logic [DATA_WIDTH-1:0],
    parameter FORWARD          = 1,
    parameter REVERSE          = 1,
    parameter HIGH_PERFORMANCE = 1
) (
    input  logic clk,
    input  logic rstn,

    input  logic w_valid,
    output logic w_ready,
    input  TYPE  w_data,

    output logic r_valid,
    input  logic r_ready,
    output TYPE  r_data
);

    if (FORWARD && REVERSE && HIGH_PERFORMANCE) begin

        // This is equivalent to a depth 2 FIFO.
        // We need two buffers to achieve 100% throughput.
        TYPE buffer;
        TYPE skid_buffer;
        logic valid;
        logic skid_valid;

        // We can accept write if the skid buffer is still empty.
        assign w_ready = !skid_valid;

        // We can accept read if the buffer is not empty.
        assign r_valid = valid;

        always_ff @(posedge clk or negedge rstn) begin
            if (!rstn) begin
                valid <= 1'b0;
                skid_valid <= 1'b0;
            end
            else begin
                // Data is read out
                if (r_ready) valid <= 1'b0;
                // Data is read in from write port or skid buffer
                if (w_valid || skid_valid) valid <= 1'b1;

                // Data is read in from write port
                if (w_valid) skid_valid <= 1'b1;
                // Data is read out to buffer
                if (!valid || r_ready) skid_valid <= 1'b0;
            end
        end

        assign r_data = buffer;
        always_ff @(posedge clk) begin
            // If buffer can be refilled, then fill from skid buffer if it has value.
            if (!valid || r_ready) buffer <= skid_valid ? skid_buffer : w_data;
            // Fill in skid buffer
            if (w_valid && w_ready) skid_buffer <= w_data;
        end

    end
    else if (FORWARD && REVERSE) begin

        // This is equivalent to a depth 1 FIFO.
        TYPE buffer;
        logic valid;

        // We can read if the buffer is not empty and write if it is.
        assign w_ready = !valid;
        assign r_valid = valid;

        always_ff @(posedge clk or negedge rstn)
            if (!rstn) begin
                valid <= 1'b0;
            end
            else begin
                // Data is read out
                if (r_valid && r_ready) valid <= 1'b0;
                // Data is written in
                if (w_valid && w_ready) valid <= 1'b1;
            end

        assign r_data = buffer;
        always_ff @(posedge clk)
            if (w_valid && w_ready) buffer <= w_data;

    end
    else if (FORWARD) begin

        TYPE buffer;
        logic valid;

        // We can read if the buffer is not empty.
        assign r_valid = valid;

        // We can write if the buffer is empty or will be emptied.
        assign w_ready = !valid || r_ready;

        always_ff @(posedge clk or negedge rstn)
            if (!rstn) begin
                valid  <= 1'b0;
            end
            else begin
                // Data is read out
                if (r_ready) valid <= 1'b0;
                // Data is written in
                if (w_valid) valid <= 1'b1;
            end

        assign r_data = buffer;
        always_ff @(posedge clk)
            if (w_valid && w_ready) buffer <= w_data;

    end
    else if (REVERSE) begin

        // This is equivalent to a fall-through depth 1 FIFO.

        TYPE buffer;
        logic valid;

        // We can read if the buffer is not empty, or data is fed in directly from w_data.
        assign r_valid = valid || w_valid;

        // We can write if the buffer is empty.
        assign w_ready = !valid;

        always_ff @(posedge clk or negedge rstn)
            if (!rstn) begin
                valid <= 1'b0;
            end
            else begin
                // Buffer will be full if: it's empty and written in, or it's full and the value is not read out.
                valid <= valid ? !r_ready : w_valid && !r_ready;
            end

        assign r_data = valid ? buffer : w_data;
        always_ff @(posedge clk)
            if (w_valid && w_ready) buffer <= w_data;

    end
    else begin

        // Direct connection without registers.
        assign r_valid = w_valid;
        assign w_ready = r_ready;
        assign r_data  = w_data;

    end

endmodule
