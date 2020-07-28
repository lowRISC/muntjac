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

import axi_common::*;

// Interface that defines an AXI-Lite channel.
//
// RELAX_CHECK: The AXI specification requires DATA_WIDTH to be 32 or 64. Set RELAX_CHECK to 1 will relax this
//     limitation to be same as AXI. This can be useful for some implementations.
interface axi_lite_channel #(
    parameter ADDR_WIDTH = -1,
    parameter DATA_WIDTH = -1,
    parameter RELAX_CHECK = 0
) (
    // Shared clock and reset signals.
    input logic clk,
    input logic rstn
);

    localparam STRB_WIDTH = DATA_WIDTH / 8;

    // Static checks of paramters
    if (RELAX_CHECK) begin
        // Data width must be a power of 2.
        if ((1 << $clog2(DATA_WIDTH)) != DATA_WIDTH) $fatal(1, "DATA_WIDTH is not power of 2");
        // Data width must be width [8, 1024]
        if (!(8 <= DATA_WIDTH && DATA_WIDTH <= 1024)) $fatal(1, "DATA_WIDTH is not within range [8, 1024]");
    end
    else begin
        if (DATA_WIDTH != 32 && DATA_WIDTH != 64) $fatal(1, "DATA_WIDTH must be either 32 or 64");
    end

    logic [ADDR_WIDTH-1:0]   aw_addr;
    prot_t                   aw_prot;
    logic                    aw_valid;
    logic                    aw_ready;

    logic [DATA_WIDTH-1:0]   w_data;
    logic [STRB_WIDTH-1:0]   w_strb;
    logic                    w_valid;
    logic                    w_ready;

    resp_t                   b_resp;
    logic                    b_valid;
    logic                    b_ready;

    logic [ADDR_WIDTH-1:0]   ar_addr;
    prot_t                   ar_prot;
    logic                    ar_valid;
    logic                    ar_ready;

    logic [DATA_WIDTH-1:0]   r_data;
    resp_t                   r_resp;
    logic                    r_valid;
    logic                    r_ready;

    modport master (
        input  clk,
        input  rstn,

        output aw_addr,
        output aw_prot,
        output aw_valid,
        input  aw_ready,

        output w_data,
        output w_strb,
        output w_valid,
        input  w_ready,

        input  b_resp,
        input  b_valid,
        output b_ready,

        output ar_addr,
        output ar_prot,
        output ar_valid,
        input  ar_ready,

        input  r_data,
        input  r_resp,
        input  r_valid,
        output r_ready
    );

    modport slave (
        input  clk,
        input  rstn,

        input  aw_addr,
        input  aw_prot,
        input  aw_valid,
        output aw_ready,

        input  w_data,
        input  w_strb,
        input  w_valid,
        output w_ready,

        output b_resp,
        output b_valid,
        input  b_ready,

        input  ar_addr,
        input  ar_prot,
        input  ar_valid,
        output ar_ready,

        output r_data,
        output r_resp,
        output r_valid,
        input  r_ready
    );

    //
    // Useful packed structs for IPs to use
    //
    typedef struct packed {
        logic [ADDR_WIDTH-1:0]    addr;
        prot_t                    prot;
    } ax_pack_t;

    typedef struct packed {
        logic [DATA_WIDTH-1:0]    data;
        logic [STRB_WIDTH-1:0]    strb;
    } w_pack_t;

    typedef struct packed {
        logic [DATA_WIDTH-1:0]   data;
        resp_t                   resp;
    } r_pack_t;

endinterface
