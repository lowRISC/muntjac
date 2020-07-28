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

// Interface that defines an AXI channel.
interface axi_channel #(
    parameter ID_WIDTH,
    parameter ADDR_WIDTH,
    parameter DATA_WIDTH,
    // Due to limitation of SystemVerilog, minimum of *_USER_WIDTH is 1. If they are unused, let optimiser trim them.
    parameter AW_USER_WIDTH = 1,
    parameter W_USER_WIDTH = 1,
    parameter B_USER_WIDTH = 1,
    parameter AR_USER_WIDTH = 1,
    parameter R_USER_WIDTH = 1
) (
    // Shared clock and reset signals.
    input logic clk,
    input logic rstn
);

    localparam STRB_WIDTH = DATA_WIDTH / 8;

    // Static checks of paramters
    // Data width must be a power of 2.
    if ((1 << $clog2(DATA_WIDTH)) != DATA_WIDTH) $fatal(1, "DATA_WIDTH is not power of 2");
    // Data width must be width [8, 1024]
    if (!(8 <= DATA_WIDTH || DATA_WIDTH <= 1024)) $fatal(1, "DATA_WIDTH is not within range [8, 1024]");

    logic [ID_WIDTH-1:0]      aw_id;
    logic [ADDR_WIDTH-1:0]    aw_addr;
    logic [7:0]               aw_len;
    logic [2:0]               aw_size;
    burst_t                   aw_burst;
    logic                     aw_lock;
    cache_t                   aw_cache;
    prot_t                    aw_prot;
    logic [3:0]               aw_qos;
    logic [3:0]               aw_region;
    logic [AW_USER_WIDTH-1:0] aw_user;
    logic                     aw_valid;
    logic                     aw_ready;

    logic [DATA_WIDTH-1:0]    w_data;
    logic [STRB_WIDTH-1:0]    w_strb;
    logic                     w_last;
    logic [W_USER_WIDTH-1:0]  w_user;
    logic                     w_valid;
    logic                     w_ready;

    logic [ID_WIDTH-1:0]      b_id;
    resp_t                    b_resp;
    logic [B_USER_WIDTH-1:0]  b_user;
    logic                     b_valid;
    logic                     b_ready;

    logic [ID_WIDTH-1:0]      ar_id;
    logic [ADDR_WIDTH-1:0]    ar_addr;
    logic [7:0]               ar_len;
    logic [2:0]               ar_size;
    burst_t                   ar_burst;
    logic                     ar_lock;
    cache_t                   ar_cache;
    prot_t                    ar_prot;
    logic [3:0]               ar_qos;
    logic [3:0]               ar_region;
    logic [AR_USER_WIDTH-1:0] ar_user;
    logic                     ar_valid;
    logic                     ar_ready;

    logic [ID_WIDTH-1:0]      r_id;
    logic [DATA_WIDTH-1:0]    r_data;
    resp_t                    r_resp;
    logic                     r_last;
    logic [R_USER_WIDTH-1:0]  r_user;
    logic                     r_valid;
    logic                     r_ready;

    modport master (
        input  clk,
        input  rstn,

        output aw_id,
        output aw_addr,
        output aw_len,
        output aw_size,
        output aw_burst,
        output aw_lock,
        output aw_cache,
        output aw_prot,
        output aw_qos,
        output aw_region,
        output aw_user,
        output aw_valid,
        input  aw_ready,

        output w_data,
        output w_strb,
        output w_last,
        output w_user,
        output w_valid,
        input  w_ready,

        input  b_id,
        input  b_resp,
        input  b_user,
        input  b_valid,
        output b_ready,

        output ar_id,
        output ar_addr,
        output ar_len,
        output ar_size,
        output ar_burst,
        output ar_lock,
        output ar_cache,
        output ar_prot,
        output ar_qos,
        output ar_region,
        output ar_user,
        output ar_valid,
        input  ar_ready,

        input  r_id,
        input  r_data,
        input  r_resp,
        input  r_last,
        input  r_user,
        input  r_valid,
        output r_ready
    );

    modport slave (
        input  clk,
        input  rstn,

        input  aw_id,
        input  aw_addr,
        input  aw_len,
        input  aw_size,
        input  aw_burst,
        input  aw_lock,
        input  aw_cache,
        input  aw_prot,
        input  aw_qos,
        input  aw_region,
        input  aw_user,
        input  aw_valid,
        output aw_ready,

        input  w_data,
        input  w_strb,
        input  w_last,
        input  w_user,
        input  w_valid,
        output w_ready,

        output b_id,
        output b_resp,
        output b_user,
        output b_valid,
        input  b_ready,

        input  ar_id,
        input  ar_addr,
        input  ar_len,
        input  ar_size,
        input  ar_burst,
        input  ar_lock,
        input  ar_cache,
        input  ar_prot,
        input  ar_qos,
        input  ar_region,
        input  ar_user,
        input  ar_valid,
        output ar_ready,

        output r_id,
        output r_data,
        output r_resp,
        output r_last,
        output r_user,
        output r_valid,
        input  r_ready
    );

    //
    // Useful packed structs for IPs to use
    //
    typedef struct packed {
        logic [ID_WIDTH-1:0]      id;
        logic [ADDR_WIDTH-1:0]    addr;
        logic [7:0]               len;
        logic [2:0]               size;
        burst_t                   burst;
        logic                     lock;
        cache_t                   cache;
        prot_t                    prot;
        logic [3:0]               qos;
        logic [3:0]               region;
        logic [AW_USER_WIDTH-1:0] user;
    } aw_pack_t;

    typedef struct packed {
        logic [DATA_WIDTH-1:0]    data;
        logic [STRB_WIDTH-1:0]    strb;
        logic                     last;
        logic [W_USER_WIDTH-1:0]  user;
    } w_pack_t;

    typedef struct packed {
        logic [ID_WIDTH-1:0]      id;
        resp_t                    resp;
        logic [B_USER_WIDTH-1:0]      user;
    } b_pack_t;

    typedef struct packed {
        logic [ID_WIDTH-1:0]      id;
        logic [ADDR_WIDTH-1:0]    addr;
        logic [7:0]               len;
        logic [2:0]               size;
        burst_t                   burst;
        logic                     lock;
        cache_t                   cache;
        prot_t                    prot;
        logic [3:0]               qos;
        logic [3:0]               region;
        logic [AR_USER_WIDTH-1:0] user;
    } ar_pack_t;

    typedef struct packed {
        logic [ID_WIDTH-1:0]     id;
        logic [DATA_WIDTH-1:0]   data;
        resp_t                   resp;
        logic                    last;
        logic [R_USER_WIDTH-1:0] user;
    } r_pack_t;

endinterface
