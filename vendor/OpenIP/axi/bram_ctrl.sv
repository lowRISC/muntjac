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

// A component that converts an AXI-lite interface to a BRAM interface.
//
// HIGH_PERFORMANCE: By default this component runs in high performance mode (which means it can respond to one
//     read/write request every cycle). Set this parameter to 0 will turn off high performance mode, reducing a few
//     register usages.
module axi_bram_ctrl #(
    parameter DATA_WIDTH     ,
    parameter BRAM_ADDR_WIDTH,
    parameter HIGH_PERFORMANCE = 1
) (
    axi_channel.slave               master,

    output                          bram_en,
    output [DATA_WIDTH/8-1:0]       bram_we,
    output [BRAM_ADDR_WIDTH-1:0]    bram_addr,
    output [DATA_WIDTH-1:0]         bram_wrdata,
    input  [DATA_WIDTH-1:0]         bram_rddata
);

    axi_lite_channel #(
        .ADDR_WIDTH  (master.ADDR_WIDTH),
        .DATA_WIDTH  (DATA_WIDTH),
        .RELAX_CHECK (1'b1)
    ) channel (
        .clk  (master.clk),
        .rstn (master.rstn)
    );

    axi_to_lite #(
        .HIGH_PERFORMANCE (HIGH_PERFORMANCE)
    ) bridge (
        .master (master),
        .slave  (channel)
    );

    axi_lite_bram_ctrl #(
        .DATA_WIDTH       (DATA_WIDTH),
        .BRAM_ADDR_WIDTH  (BRAM_ADDR_WIDTH)
    ) controller (
        .master (channel),
        .*
    );

endmodule
