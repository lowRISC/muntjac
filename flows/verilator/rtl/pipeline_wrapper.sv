// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Currently Verilator does not allow `interface`s to be exposed by the top-
// level module (#1185). This wrapper unpacks these `interface`s for access from
// a test harness.

module pipeline_wrapper import muntjac_pkg::*; #(
) (

    // Clock and reset
    input  logic            clk_i,
    input  logic            rst_ni,

    // Instruction cache interface
    output logic            icache_req_valid,
    output logic [63:0]     icache_req_pc,
    output if_reason_e      icache_req_reason,
    output logic            icache_req_prv,
    output logic            icache_req_sum,
    output logic [63:0]     icache_req_atp,
    input  logic            icache_resp_valid,
    input  logic [31:0]     icache_resp_instr,
    input  logic            icache_resp_exception,
    input  exc_cause_e      icache_resp_ex_code,

    // Data cache interface
    output logic            dcache_req_valid,
    input  logic            dcache_req_ready,
    output logic [63:0]     dcache_req_address,
    output logic [63:0]     dcache_req_value,
    output mem_op_e         dcache_req_op,
    output logic [1:0]      dcache_req_size,
    output size_ext_e       dcache_req_size_ext,
    output logic [6:0]      dcache_req_amo,
    output logic            dcache_req_prv,
    output logic            dcache_req_sum,
    output logic            dcache_req_mxr,
    output logic [63:0]     dcache_req_atp,
    input  logic            dcache_resp_valid,
    input  logic [63:0]     dcache_resp_value,
    input  logic            dcache_ex_valid,
    input  exception_t      dcache_ex_exception,
    output logic            dcache_notif_valid,
    output logic            dcache_notif_reason,
    input  logic            dcache_notif_ready,

    input  logic            irq_software_m_i,
    input  logic            irq_timer_m_i,
    input  logic            irq_external_m_i,
    input  logic            irq_external_s_i,

    input  logic [63:0]     hart_id_i,

    // Debug connections
`ifdef TRACE_ENABLE
    output logic [31:0]     dbg_instr_word_o,
    output priv_lvl_e       dbg_mode_o,
    output logic            dbg_gpr_written_o,
    output logic [4:0]      dbg_gpr_o,
    output logic [63:0]     dbg_gpr_data_o,
    output logic            dbg_csr_written_o,
    output csr_num_e        dbg_csr_o,
    output logic [63:0]     dbg_csr_data_o,
`endif
    output logic [63:0]     dbg_pc_o

);

  icache_h2d_t icache_h2d;
  icache_d2h_t icache_d2h;
  dcache_h2d_t dcache_h2d;
  dcache_d2h_t dcache_d2h;

  instr_trace_t dbg_o;

  muntjac_pipeline #(
  ) pipeline (
      .clk_i (clk_i),
      .rst_ni (rst_ni),
      .icache_h2d_o (icache_h2d),
      .icache_d2h_i (icache_d2h),
      .dcache_h2d_o (dcache_h2d),
      .dcache_d2h_i (dcache_d2h),
      .irq_software_m_i,
      .irq_timer_m_i,
      .irq_external_m_i,
      .irq_external_s_i,
      .hart_id_i,
      .dbg_o
  );

  // Instruction cache interface
  assign icache_req_valid = icache_h2d.req_valid;
  assign icache_req_pc = icache_h2d.req_pc;
  assign icache_req_reason = icache_h2d.req_reason;
  assign icache_req_prv = icache_h2d.req_prv;
  assign icache_req_sum = icache_h2d.req_sum;
  assign icache_req_atp = icache_h2d.req_atp;
  assign icache_d2h.resp_valid = icache_resp_valid;
  assign icache_d2h.resp_instr = icache_resp_instr;
  assign icache_d2h.resp_exception = icache_resp_exception;
  assign icache_d2h.resp_ex_code = icache_resp_ex_code;

  // Data cache interface
  assign dcache_d2h.req_ready = dcache_req_ready;
  assign dcache_req_valid = dcache_h2d.req_valid;
  assign dcache_req_address = dcache_h2d.req_address;
  assign dcache_req_value = dcache_h2d.req_value;
  assign dcache_req_op = dcache_h2d.req_op;
  assign dcache_req_size = dcache_h2d.req_size;
  assign dcache_req_size_ext = dcache_h2d.req_size_ext;
  assign dcache_req_amo = dcache_h2d.req_amo;
  assign dcache_req_prv = dcache_h2d.req_prv;
  assign dcache_req_sum = dcache_h2d.req_sum;
  assign dcache_req_mxr = dcache_h2d.req_mxr;
  assign dcache_req_atp = dcache_h2d.req_atp;
  assign dcache_d2h.resp_valid = dcache_resp_valid;
  assign dcache_d2h.resp_value = dcache_resp_value;
  assign dcache_d2h.ex_valid = dcache_ex_valid;
  assign dcache_d2h.ex_exception = dcache_ex_exception;
  assign dcache_d2h.notif_ready = dcache_notif_ready;
  assign dcache_notif_valid = dcache_h2d.notif_valid;
  assign dcache_notif_reason = dcache_h2d.notif_reason;

  // Debug connections
  assign dbg_pc_o = dbg_o.pc;
`ifdef TRACE_ENABLE
  assign dbg_instr_word_o = dbg_o.instr_word;
  assign dbg_mode_o = dbg_o.mode;
  assign dbg_gpr_written_o = dbg_o.gpr_written;
  assign dbg_gpr_o = dbg_o.gpr;
  assign dbg_gpr_data_o = dbg_o.gpr_data;
  assign dbg_csr_written_o = dbg_o.csr_written;
  assign dbg_csr_o = dbg_o.csr;
  assign dbg_csr_data_o = dbg_o.csr_data;
`endif

  // Set the pipeline's program counter during reset.
  function write_reset_pc;
    // verilator public
    input [63:0] new_pc;
    begin
      pipeline.frontend.redirect_valid_i = 1;
      pipeline.frontend.redirect_reason_i = IF_FENCE_I;
      pipeline.frontend.redirect_pc_i = new_pc;
    end
  endfunction

endmodule
