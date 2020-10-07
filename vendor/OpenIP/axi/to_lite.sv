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

// A bridge that connects an AXI master with an AXI-Lite slave. It requires address and data width to match and does
// not perform width conversion. It will convert bursts into multiple transactions.
//
// HIGH_PERFORMANCE: If turned on, it can initiate a read/write request every cycle. Turn if off will reduce a few
//     register usages. If can be turned off with marginal performance impact if transactions are in large bursts.
module axi_to_lite #(
    parameter HIGH_PERFORMANCE = 1
) (
    axi_channel.slave       master,
    axi_lite_channel.master slave
);

    // Static checks of interface matching
    if (master.DATA_WIDTH != slave.DATA_WIDTH ||
        master.ADDR_WIDTH != slave.ADDR_WIDTH)
        $fatal(1, "Parameter mismatch");

    // Extract clk and rstn signals from interfaces
    logic clk;
    logic rstn;
    assign clk = master.clk;
    assign rstn = master.rstn;

    // High-level description of how this module works:
    // For simplicity and code clearity, all channels have been decoupled.
    // * Read address and write address channels simply convert all bursts into individual transactions and propagate
    //   them to the slave device.
    // * Read data channel is required to set the id and last signals. We will use a FIFO to pass the ar_id and ar_len
    //   from the read address channel to read data channel in order for it to set these signals properly.
    // * Write data channel is passed through directly. As AXI mandates burst not to be interrupted, we can safely
    //   discard w_last.
    // * Write response channel will need to accumulate the responses from lite side and only send a single write
    //   response back to the master device. Similarly we will be using a FIFO to pass aw_id and aw_len.

    // Pack id and len into one single structure for use of FIFO.
    typedef struct packed {
        logic [master.ID_WIDTH-1:0] id;
        logic [7:0]                 len;
    } xact_t;

    //
    // Address increment handling
    //
    // AXI defined three burst types:
    // * FIXED: most simple type, just don't change address at all.
    // * INCR : need to align address and then increase by (1 << axsize)
    //          for realigning apply mask out (1 << axsize) - 1
    // * WRAP : first perform INCR, but wrap within an aligned address block of size (axlen << axsize)
    //          for wrapping, simply mask out len
    //
    // AXI requires address to not cross 4K boundary, so only lower 12 bits are touched.

    function automatic logic [11:0] increment(
        input logic [11:0] addr,
        input logic [2:0]  size,
        input logic [3:0]  wrap_len,
        input burst_t      burst
    );

        automatic logic [7:0] shift;
        automatic logic [11:0] incr_mask;
        automatic logic [11:0] wrap_mask;
        shift = 1 << size;
        incr_mask = shift - 1;
        // AXI requires len to be 1, 3, 7 or 15, so they are naturally masks.
        wrap_mask = wrap_len << size;

        unique case (burst)
            BURST_FIXED:
                increment = addr;
            BURST_INCR:
                increment = (addr &~ incr_mask) + shift;
            BURST_WRAP:
                // Basically this restricts the addition to be within the mask and keeps things outside mask fixed.
                increment = ((addr + shift) & wrap_mask) | (addr &~ wrap_mask);
            default:
                increment = 'x;
        endcase

    endfunction

    //
    // Read address chanel
    //

    // Whether we are in the process of sending out bursts
    logic                         ar_in_burst;
    // The address to send to slave, and the next address.
    logic [master.ADDR_WIDTH-1:0] ar_addr, ar_addr_next;
    // Remaining burst length and its next value.
    logic [7:0]                   ar_len, ar_len_next;
    // The latched values from master.
    prot_t                        ar_prot;
    // When the FIFO to read response channel is full, we need to prepare to stall read address channel.
    // So we have this signal here which will be provided by the FIFO, and we can only proceed if it is asserted.
    logic                         rfifo_ready;
    // The following registers are latched for calculating the next address.
    // Variable _switched means its value either comes from aw channel (if ar_in_burst is low) or from register (if
    // ar_in_burst is high). They are necessary to calculate ar_addr_next. Even though ar_addr is necessary for
    // calculating the next address, its switched exists already as slave.ar_addr.
    // Previous version of this code do not have these switched signals, but instead store previous address into
    // ar_addr and feed ar_addr_next directly into slave.ar_addr, but it seems that Quartus cannot perform flip-flop
    // migration in this case and causes timing issues.
    logic [2:0]                   ar_size, ar_size_switched;
    burst_t                       ar_burst, ar_burst_switched;
    logic [3:0]                   ar_wrap_len, ar_wrap_len_switched;

    assign ar_size_switched     = ar_in_burst ? ar_size : master.ar_size;
    assign ar_wrap_len_switched = ar_in_burst ? ar_wrap_len : master.ar_len[3:0];
    assign ar_burst_switched    = ar_in_burst ? ar_burst : master.ar_burst;

    // Calculate the next address and remaining length within the burst.
    if (master.ADDR_WIDTH > 12)
        assign ar_addr_next = {
            slave.ar_addr[master.ADDR_WIDTH-1:12],
            increment(slave.ar_addr[11:0], ar_size_switched, ar_wrap_len_switched, ar_burst_switched)
        };
    else
        assign ar_addr_next = increment(slave.ar_addr, ar_size_switched, ar_wrap_len_switched, ar_burst_switched);
    assign ar_len_next = ar_len - 1;

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            ar_in_burst <= 1'b0;
            ar_size     <= 'x;
            ar_burst    <= burst_t'('x);
            ar_prot     <= 'x;
            ar_addr     <= 'x;
            ar_len      <= 'x;
            ar_wrap_len <= 'x;
        end
        else begin
            // When we are breaking bursty transaction
            if (ar_in_burst) begin
                if (slave.ar_ready) begin
                    // When this is the last write transaction to send
                    if (ar_len_next == 8'h0) begin
                        // Move out from burst mode.
                        ar_in_burst <= 1'b0;
                        ar_size     <= 'x;
                        ar_burst    <= burst_t'('x);
                        ar_prot     <= 'x;
                        ar_addr     <= 'x;
                        ar_len      <= 'x;
                        ar_wrap_len <= 'x;
                    end
                    else begin
                        ar_addr     <= ar_addr_next;
                        ar_len      <= ar_len_next;
                    end
                end
            end
            else begin
                // When master creates a bursty transaction
                // The condition here is actually (slave.ar_valid && slave.ar_ready && master.ar_len != 8'h0) which
                // perfectly matches the code for all other channels but we expand it out here just in case the
                // synthesiser cannot figure out the expansion.
                if (rfifo_ready && master.ar_valid && slave.ar_ready && master.ar_len != 8'h0) begin
                    // Move into burst mode.
                    ar_in_burst <= 1'b1;
                    ar_size     <= master.ar_size;
                    ar_burst    <= master.ar_burst;
                    ar_addr     <= ar_addr_next;
                    ar_prot     <= master.ar_prot;
                    ar_len      <= master.ar_len;
                    ar_wrap_len <= master.ar_len[3:0];
                end
            end
        end
    end

    // If ar_in_burst is not true (and rfifo_ready is asserted), connect master and slave together, otherwise use
    // the bridge's own register.
    // ar_id is reflected via FIFO
    assign slave.ar_addr   = ar_in_burst ? ar_addr : master.ar_addr;
    // ar_len is managed by this bridge
    // ar_size is managed by this bridge
    // ar_burst is managed by this bridge
    // ar_lock is discarded
    // ar_cache is discarded
    assign slave.ar_prot   = ar_in_burst ? ar_prot : master.ar_prot;
    // ar_qos is discarded
    // ar_region is discarded
    // ar_user is discarded
    assign slave.ar_valid  = ar_in_burst ? 1'b1 : master.ar_valid && rfifo_ready;
    assign master.ar_ready = ar_in_burst ? 1'b0 : slave.ar_ready && rfifo_ready;

    //
    // Read data channel
    //

    // Signal about packed transaction information from/to FIFO
    logic                       rfifo_valid;
    xact_t                      rfifo_xact;
    // The state definition below is very similar to read address channel.
    logic                       r_in_burst;
    logic [master.ID_WIDTH-1:0] r_id;
    logic [7:0]                 r_len, r_len_next;

    assign r_len_next = r_len - 1;

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            r_in_burst <= 1'b0;
            r_id       <= 'x;
            r_len      <= 'x;
        end
        else begin
            // When we are counting for bursty transaction
            if (r_in_burst) begin
                if (slave.r_ready && slave.r_valid) begin
                    // When this is the last read response to worry about
                    if (r_len_next == 8'h0) begin
                        // Move out from burst mode.
                        r_in_burst <= 1'b0;
                        r_id       <= 'x;
                        r_len      <= 'x;
                    end
                    else begin
                        r_len      <= r_len_next;
                    end
                end
            end
            else begin
                // We only take element out of FIFO when first read response arrives. (see later FIFO interfacing)
                // When a read response comes the FIFO should already have valid data in it, so we assert here.
                assert (!slave.r_valid || rfifo_valid) else $fatal(1, "Read response comes without a read request");

                // When slave starts to respond to a bursty transaction.
                if (slave.r_ready && slave.r_valid && rfifo_xact.len != 8'h0) begin
                    // Move into burst mode.
                    r_in_burst <= 1'b1;
                    r_id       <= rfifo_xact.id;
                    r_len      <= rfifo_xact.len;
                end
            end
        end
    end

    // Perform ID reflection.
    assign master.r_id    = r_in_burst ? r_id : rfifo_xact.id;
    assign master.r_data  = slave.r_data;
    assign master.r_resp  = slave.r_resp;
    // Set last when this is the last one in a bursty transaction or this completes a single-word transaction.
    assign master.r_last  = (r_in_burst ? r_len_next : rfifo_xact.len) == 8'h0;
    // assign master.r_last = slave.r_last;
    assign master.r_user  = 'x;
    assign master.r_valid = slave.r_valid;
    assign slave.r_ready  = master.r_ready;

    //
    // Write address chanel. This is identical to the read address channel, so comments are removed.
    //

    logic                         aw_in_burst;
    logic [master.ADDR_WIDTH-1:0] aw_addr, aw_addr_next;
    logic [7:0]                   aw_len, aw_len_next;
    prot_t                        aw_prot;
    logic                         wfifo_ready;
    logic [2:0]                   aw_size, aw_size_switched;
    burst_t                       aw_burst, aw_burst_switched;
    logic [3:0]                   aw_wrap_len, aw_wrap_len_switched;

    assign aw_size_switched     = aw_in_burst ? aw_size : master.aw_size;
    assign aw_wrap_len_switched = aw_in_burst ? aw_wrap_len : master.aw_len[3:0];
    assign aw_burst_switched    = aw_in_burst ? aw_burst : master.aw_burst;

    if (master.ADDR_WIDTH > 12)
        assign aw_addr_next = {
            slave.aw_addr[master.ADDR_WIDTH-1:12],
            increment(slave.aw_addr[11:0], aw_size_switched, aw_wrap_len_switched, aw_burst_switched)
        };
    else
        assign aw_addr_next = increment(slave.aw_addr, aw_size_switched, aw_wrap_len_switched, aw_burst_switched);
    assign aw_len_next = aw_len - 1;

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            aw_in_burst <= 1'b0;
            aw_size     <= 'x;
            aw_burst    <= burst_t'('x);
            aw_prot     <= 'x;
            aw_addr     <= 'x;
            aw_len      <= 'x;
            aw_wrap_len <= 'x;
        end
        else begin
            if (aw_in_burst) begin
                if (slave.aw_ready) begin
                    if (aw_len_next == 8'h0) begin
                        aw_in_burst <= 1'b0;
                        aw_size     <= 'x;
                        aw_burst    <= burst_t'('x);
                        aw_prot     <= 'x;
                        aw_addr     <= 'x;
                        aw_len      <= 'x;
                        aw_wrap_len <= 'x;
                    end
                    else begin
                        aw_addr     <= aw_addr_next;
                        aw_len      <= aw_len_next;
                    end
                end
            end
            else begin
                if (wfifo_ready && master.aw_valid && slave.aw_ready && master.aw_len != 8'h0) begin
                    aw_in_burst <= 1'b1;
                    aw_size     <= master.aw_size;
                    aw_burst    <= master.aw_burst;
                    aw_addr     <= aw_addr_next;
                    aw_prot     <= master.aw_prot;
                    aw_len      <= master.aw_len;
                    aw_wrap_len <= master.aw_len[3:0];
                end
            end
        end
    end

    assign slave.aw_addr   = aw_in_burst ? aw_addr : master.aw_addr;
    assign slave.aw_prot   = aw_in_burst ? aw_prot : master.aw_prot;
    assign slave.aw_valid  = aw_in_burst ? 1'b1 : master.aw_valid && rfifo_ready;
    assign master.aw_ready = aw_in_burst ? 1'b0 : slave.aw_ready && rfifo_ready;

    //
    // Write data channel
    //

    assign slave.w_data   = master.w_data;
    assign slave.w_strb   = master.w_strb;
    // w_last is discarded
    // w_user is discarded
    assign slave.w_valid  = master.w_valid;
    assign master.w_ready = slave.w_ready;

    //
    // Write response channel
    //

    /// Signal about packed transaction information from/to FIFO
    logic                       wfifo_valid;
    xact_t                      wfifo_xact;
    // The state definition below is very similar to read response channel.
    logic                       b_in_burst;
    logic [master.ID_WIDTH-1:0] b_id;
    logic [7:0]                 b_len, b_len_next;
    // The current response to be returned and its next state.
    resp_t                      b_resp, b_resp_next;

    assign b_len_next  = b_len - 1;
    // If b_resp is already an error response, retain it, otherwise use the new response.
    assign b_resp_next = b_resp[1] ? b_resp : slave.b_resp;

    always_ff @(posedge clk or negedge rstn) begin
        if (!rstn) begin
            b_in_burst <= 1'b0;
            b_id       <= 'x;
            b_len      <= 'x;
            b_resp     <= resp_t'('x);
        end
        else begin
            // When we are counting for bursty transaction
            if (b_in_burst) begin
                if (slave.b_ready && slave.b_valid) begin
                    // When this is the last read response to worry about
                    if (b_len_next == 8'h0) begin
                        // Move out from burst mode.
                        b_in_burst <= 1'b0;
                        b_id       <= 'x;
                        b_len      <= 'x;
                        b_resp     <= resp_t'('x);
                    end
                    else begin
                        b_len      <= b_len_next;
                        b_resp     <= b_resp_next;
                    end
                end
            end
            else begin
                // The condition of popping from FIFO and assertion is similar to the read response case.
                assert (!slave.b_valid || wfifo_valid) else $fatal(1, "Write response comes without a write request");

                // When slave starts to respond to a bursty transaction.
                // No need for slave.b_ready condition here as wfifo_xact.len != 8'h0 implies it.
                if (slave.b_valid && wfifo_xact.len != 8'h0) begin
                    // Move into burst mode.
                    b_in_burst <= 1'b1;
                    b_id       <= wfifo_xact.id;
                    b_len      <= wfifo_xact.len;
                    b_resp     <= slave.b_resp;
                end
            end
        end
    end

    // Whether this will be the last write response of the transaction.
    logic b_last;
    assign b_last = (b_in_burst ? b_len_next : wfifo_xact.len) == 8'h0;

    // Perform ID reflection.
    assign master.b_id    = b_in_burst ? b_id : wfifo_xact.id;
    assign master.b_resp  = b_in_burst ? b_resp_next : slave.b_resp;
    assign master.b_user  = 'x;
    // If this is not going to be the last one, then we will not assert this and we have to merge the responses.
    assign master.b_valid = b_last ? slave.b_valid  : 1'b0;
    // If this is not going to be the last one, then we will assert this so we can data for merging.
    assign slave.b_ready  = b_last ? master.b_ready : 1'b1;

    //
    // Register slices (FIFOs) for passing information around.
    //

    openip_regslice #(
        .TYPE             (xact_t),
        .HIGH_PERFORMANCE (HIGH_PERFORMANCE)
    ) rfifo (
        .clk     (clk),
        .rstn    (rstn),
        .w_valid (!ar_in_burst && master.ar_valid && master.ar_ready),
        .w_ready (rfifo_ready),
        .w_data  (xact_t'{master.ar_id, master.ar_len}),
        .r_valid (rfifo_valid),
        .r_ready (!r_in_burst && slave.r_ready && slave.r_valid),
        .r_data  (rfifo_xact)
    );

    openip_regslice #(
        .TYPE             (xact_t),
        .HIGH_PERFORMANCE (HIGH_PERFORMANCE)
    ) wfifo (
        .clk     (clk),
        .rstn    (rstn),
        .w_valid (!aw_in_burst && master.aw_valid && master.aw_ready),
        .w_ready (wfifo_ready),
        .w_data  (xact_t'{master.aw_id, master.aw_len}),
        .r_valid (wfifo_valid),
        .r_ready (!b_in_burst && slave.b_ready && slave.b_valid),
        .r_data  (wfifo_xact)
    );

endmodule
