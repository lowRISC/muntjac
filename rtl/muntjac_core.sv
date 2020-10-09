module muntjac_core import muntjac_pkg::*; #(
  parameter int unsigned SourceWidth = 4,
  parameter int unsigned SourceBase = 0
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

  localparam [SourceWidth-1:0] DcacheSourceBase = SourceBase | 0;
  localparam [SourceWidth-1:0] IcacheSourceBase = SourceBase | 1;
  localparam [SourceWidth-1:0] DptwSourceBase = SourceBase | 2;
  localparam [SourceWidth-1:0] IptwSourceBase = SourceBase | 3;

  localparam [SourceWidth-1:0] SourceMask = 0;

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
    .SourceWidth(SourceWidth)
  ) ch[4] ();

  tl_socket_m1 #(
    .SourceWidth(SourceWidth),
    .NumLinks (4),
    .NumCachedLinks (1),

    .NumSourceRange(3),
    .SourceBase({IcacheSourceBase, DptwSourceBase, IptwSourceBase}),
    .SourceMask({      SourceMask,     SourceMask,     SourceMask}),
    .SourceLink({2'd            1, 2'd          2, 2'd          3})
  ) socket (
    .clk_i,
    .rst_ni,
    .host (ch),
    .device (mem)
  );

  muntjac_icache #(
    .SourceBase (IcacheSourceBase),
    .PtwSourceBase (IptwSourceBase)
  ) icache_inst (
      clk_i, rst_ni, icache, ch[1], ch[3]
  );

  muntjac_dcache #(
    .SourceBase (DcacheSourceBase),
    .PtwSourceBase (DptwSourceBase)
  ) dcache_inst (
      clk_i, rst_ni, dcache, ch[0], ch[2]
  );

endmodule
