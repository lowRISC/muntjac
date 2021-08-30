// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

module core_wrapper import muntjac_pkg::*; #(
) (

    // Clock and reset
    input  logic            clk_i,
    input  logic            rst_ni,

    output logic            mem_en_o,
    output logic            mem_we_o,
    output logic [52:0]     mem_addr_o,
    output logic [7:0]      mem_wmask_o,
    output logic [63:0]     mem_wdata_o,
    input  logic [63:0]     mem_rdata_i,

    output logic            io_en_o,
    output logic            io_we_o,
    output logic [52:0]     io_addr_o,
    output logic [7:0]      io_wmask_o,
    output logic [63:0]     io_wdata_o,
    input  logic [63:0]     io_rdata_i,

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

  localparam SinkWidth = 2;

  `TL_DECLARE(64, 56, 9, 1, mem_tlul);
  `TL_DECLARE(64, 56, 7, 1, io_tlul);

  tl_adapter_bram #(
    .DataWidth (64),
    .SourceWidth(9),
    .SinkWidth (1),
    .BramAddrWidth (53)
  ) mem_tlul_bram_bridge (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_DEVICE_PORT(host, mem_tlul),
    .bram_en_o    (mem_en_o),
    .bram_we_o    (mem_we_o),
    .bram_wmask_o (mem_wmask_o),
    .bram_addr_o  (mem_addr_o),
    .bram_wdata_o (mem_wdata_o),
    .bram_rdata_i (mem_rdata_i)
  );

  tl_adapter_bram #(
    .DataWidth (64),
    .SourceWidth(7),
    .SinkWidth (1),
    .BramAddrWidth (53)
  ) io_tlul_bram_bridge (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_DEVICE_PORT(host, io_tlul),
    .bram_en_o    (io_en_o),
    .bram_we_o    (io_we_o),
    .bram_wmask_o (io_wmask_o),
    .bram_addr_o  (io_addr_o),
    .bram_wdata_o (io_wdata_o),
    .bram_rdata_i (io_rdata_i)
  );

  `TL_DECLARE(64, 56, 6, 1, mem);
  `TL_DECLARE(64, 56, 4, 1, io);

  tl_adapter_tlul #(
    .HostSourceWidth (6),
    .DeviceSourceWidth (9),
    .SinkWidth (1),
  ) mem_tlul_bridge (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_DEVICE_PORT(host, mem),
    `TL_CONNECT_HOST_PORT(device, mem_tlul)
  );

  tl_adapter_tlul #(
    .HostSourceWidth (6),
    .DeviceSourceWidth (9),
    .SinkWidth (1)
  ) io_tlul_bridge (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_DEVICE_PORT(host, io),
    `TL_CONNECT_HOST_PORT(device, io_tlul)
  );

  `TL_DECLARE(64, 56, 6, SinkWidth, mem_tlc_term);
  tl_ram_terminator #(
    .DataWidth(64),
    .AddrWidth(56),
    .HostSourceWidth(4),
    .DeviceSourceWidth(6),
    .HostSinkWidth (SinkWidth),
    .SinkBase (0),
    .SinkMask (2 ** SinkWidth - 1)
  ) ram_term (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_DEVICE_PORT(host, mem_tlc_term),
    `TL_CONNECT_HOST_PORT(device, mem)
  );

  localparam [SinkWidth-1:0] CacheSinkBase = 0;
  localparam [SinkWidth-1:0] CacheSinkMask = 1;
  localparam [SinkWidth-1:0] IoSinkBase = 2;
  localparam [SinkWidth-1:0] IoSinkMask = 0;

  logic hpm_acq_count;
  logic hpm_rel_count;
  logic hpm_miss;

  `TL_DECLARE_ARR(64, 56, 4, SinkWidth, mem_tlc, [1:0]);
  muntjac_llc #(
    .AddrWidth(56),
    .DataWidth(64),
    .SourceWidth(4),
    .SinkWidth (SinkWidth),
    .SinkBase (CacheSinkBase),
    .SinkMask (CacheSinkMask),
    .NumCachedHosts(1),
    .SourceBase({4'd0}),
    .SourceMask({4'd0})
  ) llc (
    .clk_i,
    .rst_ni,
    .hpm_acq_count_o (hpm_acq_count),
    .hpm_rel_count_o (hpm_rel_count),
    .hpm_miss_o (hpm_miss),
    `TL_CONNECT_DEVICE_PORT_IDX(host, mem_tlc, [0]),
    `TL_CONNECT_HOST_PORT(device, mem_tlc_term)
  );

  `TL_DECLARE(64, 56, 4, SinkWidth, io_tlc);
  tl_io_terminator #(
    .AddrWidth(56),
    .DataWidth(64),
    .SourceWidth(4),
    .HostSinkWidth (SinkWidth),
    .SinkBase (IoSinkBase)
  ) io_term (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_DEVICE_PORT_IDX(host, mem_tlc, [1]),
    `TL_CONNECT_HOST_PORT(device, io)
  );

  `TL_DECLARE(64, 56, 4, SinkWidth, ch_aggregate);
  tl_socket_1n #(
    .SourceWidth (4),
    .SinkWidth   (SinkWidth),
    .NumLinks    (2),
    .NumAddressRange (1),
    .AddressBase ({56'h80010000}),
    .AddressMask ({56'h      3f}),
    .AddressLink ({1'd        1}),
    .NumSinkRange (1),
    .SinkBase ({IoSinkBase}),
    .SinkMask ({IoSinkMask}),
    .SinkLink ({1'd1})
  ) socket_1n (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_DEVICE_PORT(host, ch_aggregate),
    `TL_CONNECT_HOST_PORT(device, mem_tlc)
  );

  instr_trace_t dbg_o;

  muntjac_core #(
    .SourceWidth (4),
    .SinkWidth (SinkWidth),
    .RV64F (muntjac_pkg::RV64FFull)
  ) core (
    .clk_i (clk_i),
    .rst_ni (rst_ni),
    `TL_CONNECT_HOST_PORT(mem, ch_aggregate),
    .irq_software_m_i,
    .irq_timer_m_i,
    .irq_external_m_i,
    .irq_external_s_i,
    .hart_id_i,
    .hpm_event_i ({hpm_miss, hpm_rel_count, hpm_acq_count, 3'b0, 3'b0, 1'b0}),
    .dbg_o
  );

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

endmodule
