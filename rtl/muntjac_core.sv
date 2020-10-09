module muntjac_core import muntjac_pkg::*; #(
) (
    // Clock and reset
    input  logic            clk_i,
    input  logic            rst_ni,

    // Memory interface
    tl_channel.host mem,

    input  logic irq_software_m_i,
    input  logic irq_timer_m_i,
    input  logic irq_external_m_i,
    input  logic irq_external_s_i,

    input  logic [63:0] hart_id_i,

    // Debug connections
    output logic [63:0] dbg_pc_o
);

  icache_intf icache();
  dcache_intf dcache();

  muntjac_pipeline pipeline (
      .clk_i,
      .rst_ni,
      .icache (icache),
      .dcache (dcache),
      .irq_software_m_i,
      .irq_timer_m_i,
      .irq_external_m_i,
      .irq_external_s_i,
      .hart_id_i,
      .dbg_pc_o
  );

  tl_channel #(
    .AddrWidth(56),
    .DataWidth(64),
    .SourceWidth(4)
  ) ch[4] ();

  tl_socket_m1 #(
    .SourceWidth(4),
    .SourceIdWidth(0),
    .NumLinks (4)
  ) socket (
    .clk_i,
    .rst_ni,
    .host (ch),
    .device (mem)
  );

  muntjac_icache icache_inst (
      clk_i, rst_ni, icache, ch[1], ch[3]
  );

  muntjac_dcache dcache_inst (
      clk_i, rst_ni, dcache, ch[0], ch[2]
  );

endmodule
