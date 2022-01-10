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

// A round-robin arbiter.
module openip_round_robin_arbiter #(
    parameter WIDTH = -1
) (
    input  logic             clk,
    input  logic             rstn,
    input  logic             enable,
    input  logic [WIDTH-1:0] request,
    output logic [WIDTH-1:0] grant
);

    // High-level description of how this module works:
    // This is a round-robin arbiter design known as "mask" method. It uses two simple priority arbiter to perform
    // round robin. See "Arbiters: Design Ideas and Coding Styles (Weber 2001)" for details.
    // It first checks more significant bits than the last-granted bit. If there is a bit set, then it obviously
    // takes priority. If there isn't a bit set, then all lower bits can be considered for arbitration (this is
    // effectively all bits, as higher bits are all zero).

    logic [WIDTH-1:0] last_grant;

    // Requests with only bits set if it's more significant than the bit set in last_grant. The LSB will always be
    // zero. If last_grant is all zero, then this will be all zero.
    logic [WIDTH-1:0] masked_request;
    // ~(last_grant - 1) will produce 1s for all bits equally or more significant than the bit set in last_grant.
    // After prepending 0, it will produce 1s for all bits more significant than the bit set in last_grant.
    assign masked_request = {~(last_grant - 1), 1'b0} & request;

    logic [WIDTH-1:0] masked_grant;
    openip_priority_arbiter #(.WIDTH(WIDTH)) masked_arbiter (masked_request, masked_grant);

    logic [WIDTH-1:0] unmasked_grant;
    openip_priority_arbiter #(.WIDTH(WIDTH)) unmasked_arbiter (request, unmasked_grant);

    // Use masked_grant if it's not zero. Otherwise use unmasked_grant.
    assign grant = masked_request != 0 ? masked_grant : unmasked_grant;

    always_ff @(posedge clk or negedge rstn)
        if (!rstn) begin
            last_grant <= '0;
        end
        else if (enable) begin
            last_grant <= grant;
        end

endmodule
