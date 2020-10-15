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
    output logic [63:0]     dbg_pc_o

);

  tl_channel #(
    .SourceWidth(7)
  ) mem_tlul(), io_tlul();

  tl_adapter_bram #(
    .DataWidth (64),
    .BramAddrWidth (53)
  ) mem_tlul_bram_bridge (
    .clk_i,
    .rst_ni,
    .host (mem_tlul),
    .bram_en_o    (mem_en_o),
    .bram_we_o    (mem_we_o),
    .bram_wmask_o (mem_wmask_o),
    .bram_addr_o  (mem_addr_o),
    .bram_wdata_o (mem_wdata_o),
    .bram_rdata_i (mem_rdata_i)
  );

  tl_adapter_bram #(
    .DataWidth (64),
    .BramAddrWidth (53)
  ) io_tlul_bram_bridge (
    .clk_i,
    .rst_ni,
    .host (io_tlul),
    .bram_en_o    (io_en_o),
    .bram_we_o    (io_we_o),
    .bram_wmask_o (io_wmask_o),
    .bram_addr_o  (io_addr_o),
    .bram_wdata_o (io_wdata_o),
    .bram_rdata_i (io_rdata_i)
  );

  tl_channel #(
    .SourceWidth (4)
  ) mem_split[2]();

  tl_adapter_tlul #(
    .HostSourceWidth (4),
    .DeviceSourceWidth (7)
  ) mem_tlul_bridge (
    .clk_i,
    .rst_ni,
    .host (mem_split[0]),
    .device (mem_tlul)
  );

  tl_adapter_tlul #(
    .HostSourceWidth (4),
    .DeviceSourceWidth (7)
  ) io_tlul_bridge (
    .clk_i,
    .rst_ni,
    .host (mem_split[1]),
    .device (io_tlul)
  );

  tl_channel #(
    .SourceWidth(4)
  ) mem();
  tl_socket_1n #(
    .SourceWidth (4),
    .NumLinks    (2),
    .NumAddressRange (1),
    .AddressBase ({56'h80010000}),
    .AddressMask ({56'h      3f}),
    .AddressLink ({1'd        1}),
    .NumSinkRange (1),
    .SinkBase ({1'h1}),
    .SinkMask ({1'h0}),
    .SinkLink ({1'd1})
  ) socket_1n (
    .clk_i,
    .rst_ni,
    .host (mem),
    .device (mem_split)
  );

  tl_channel #(
    .AddrWidth(56),
    .DataWidth(64),
    .SourceWidth(4)
  ) ch_aggregate();

  tl_broadcast #(
    .AddrWidth(56),
    .DataWidth(64),
    .SourceWidth(4),
    .NumAddressRange (1),
    .AddressBase ({56'h80010000}),
    .AddressMask ({56'h      3f}),
    .AddressProperty ({2'd        2}),
    .NumCachedHosts(1),
    .SourceBase({4'd0}),
    .SourceMask({4'd0})
  ) broadcaster (
    .clk_i,
    .rst_ni,
    .host (ch_aggregate),
    .device (mem)
  );

  muntjac_core core (
    .clk_i (clk_i),
    .rst_ni (rst_ni),
    .mem (ch_aggregate),
    .irq_software_m_i,
    .irq_timer_m_i,
    .irq_external_m_i,
    .irq_external_s_i,
    .hart_id_i,
    .dbg_pc_o
  );

  // Set the pipeline's program counter during reset.
  function write_reset_pc;
    // verilator public
    input [63:0] new_pc;
    begin
      core.pipeline.frontend.redirect_valid_i = 1;
      core.pipeline.frontend.redirect_reason_i = IF_FENCE_I;
      core.pipeline.frontend.redirect_pc_i = new_pc;
    end
  endfunction

endmodule
