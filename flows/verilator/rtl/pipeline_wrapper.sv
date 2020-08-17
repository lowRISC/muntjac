// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Currently Verilator does not allow `interface`s to be exposed by the top-
// level module (#1185). This wrapper unpacks these `interface`s for access from
// a test harness.

module pipeline_wrapper #(
    parameter XLEN = 64
) (

    // Clock and reset
    input  logic            clk_i,
    input  logic            rst_ni,

    // Instruction cache interface
    output logic            icache_req_valid,
    output logic [XLEN-1:0] icache_req_pc,
    output if_reason_t      icache_req_reason,
    output logic            icache_req_prv,
    output logic            icache_req_sum,
    output logic [XLEN-1:0] icache_req_atp,
    input  logic            icache_resp_valid,
    input  logic [XLEN-1:0] icache_resp_pc,
    input  logic [31:0]     icache_resp_instr,
    input  logic            icache_resp_exception,

    // Data cache interface
    output logic            dcache_req_valid,
    input  logic            dcache_req_ready,
    output logic [XLEN-1:0] dcache_req_address,
    output logic [XLEN-1:0] dcache_req_value,
    output mem_op_e         dcache_req_op,
    output logic [1:0]      dcache_req_size,
    output logic            dcache_req_unsigned,
    output logic [6:0]      dcache_req_amo,
    output logic            dcache_req_prv,
    output logic            dcache_req_sum,
    output logic            dcache_req_mxr,
    output logic [XLEN-1:0] dcache_req_atp,
    input  logic            dcache_resp_valid,
    input  logic [XLEN-1:0] dcache_resp_value,
    input  logic            dcache_ex_valid,
    input  exception_t      dcache_ex_exception,
    output logic            dcache_notif_valid,
    output logic            dcache_notif_reason,
    input  logic            dcache_notif_ready,

    input  logic            irq_m_timer,
    input  logic            irq_m_software,
    input  logic            irq_m_external,
    input  logic            irq_s_external,

    input  logic [XLEN-1:0] mhartid,

    // Debug connections
    output logic [XLEN-1:0] dbg_pc

);

    icache_intf #(.XLEN (XLEN)) icache(clk_i, rst_ni);
    dcache_intf #(.XLEN (XLEN)) dcache(clk_i, rst_ni);

    cpu #(
        .XLEN (XLEN)
    ) pipeline (
        .clk_i (clk_i),
        .rst_ni (rst_ni),
        .icache (icache),
        .dcache (dcache),
        .irq_m_timer (irq_m_timer),
        .irq_m_software (irq_m_software),
        .irq_m_external (irq_m_external),
        .irq_s_external (irq_s_external),
        .mhartid (mhartid),
        .dbg_pc (dbg_pc)
    );

    // Instruction cache interface
    assign icache_req_valid = icache.req_valid;
    assign icache_req_pc = icache.req_pc;
    assign icache_req_reason = icache.req_reason;
    assign icache_req_prv = icache.req_prv;
    assign icache_req_sum = icache.req_sum;
    assign icache_req_atp = icache.req_atp;
    assign icache.resp_valid = icache_resp_valid;
    assign icache.resp_pc = icache_resp_pc;
    assign icache.resp_instr = icache_resp_instr;
    assign icache.resp_exception = icache_resp_exception;

    // Data cache interface
    assign dcache_req_valid = dcache.req_valid;
    assign dcache.req_ready = dcache_req_ready;
    assign dcache_req_address = dcache.req_address;
    assign dcache_req_value = dcache.req_value;
    assign dcache_req_op = dcache.req_op;
    assign dcache_req_size = dcache.req_size;
    assign dcache_req_unsigned = dcache.req_unsigned;
    assign dcache_req_amo = dcache.req_amo;
    assign dcache_req_prv = dcache.req_prv;
    assign dcache_req_sum = dcache.req_sum;
    assign dcache_req_mxr = dcache.req_mxr;
    assign dcache_req_atp = dcache.req_atp;
    assign dcache.resp_valid = dcache_resp_valid;
    assign dcache.resp_value = dcache_resp_value;
    assign dcache.ex_valid = dcache_ex_valid;
    assign dcache.ex_exception = dcache_ex_exception;
    assign dcache_notif_valid = dcache.notif_valid;
    assign dcache_notif_reason = dcache.notif_reason;
    assign dcache.notif_ready = dcache_notif_ready;

endmodule
