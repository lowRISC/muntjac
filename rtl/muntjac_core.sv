module muntjac_core import muntjac_pkg::*; #(
  parameter int unsigned SourceWidth = 4,
  parameter int unsigned SinkWidth = 1
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

  localparam [SourceWidth-1:0] DcacheSourceBase = 0;
  localparam [SourceWidth-1:0] IcacheSourceBase = 1;
  localparam [SourceWidth-1:0] DptwSourceBase = 2;
  localparam [SourceWidth-1:0] IptwSourceBase = 3;

  localparam [SourceWidth-1:0] SourceMask = 0;

  icache_h2d_t icache_h2d;
  icache_d2h_t icache_d2h;
  dcache_h2d_t dcache_h2d;
  dcache_d2h_t dcache_d2h;

  muntjac_pipeline pipeline (
      .clk_i,
      .rst_ni,
      .icache_h2d_o (icache_h2d),
      .icache_d2h_i (icache_d2h),
      .dcache_h2d_o (dcache_h2d),
      .dcache_d2h_i (dcache_d2h),
      .irq_software_m_i,
      .irq_timer_m_i,
      .irq_external_m_i,
      .irq_external_s_i,
      .hart_id_i,
      .dbg_pc_o
  );

  tl_channel #(
    .AddrWidth (56),
    .DataWidth (64),
    .SourceWidth (SourceWidth),
    .SinkWidth (SinkWidth)
  ) ch[4] ();

  tl_socket_m1 #(
    .SourceWidth (SourceWidth),
    .SinkWidth (SinkWidth),
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
    .SourceWidth (SourceWidth),
    .SinkWidth (SinkWidth),
    .SourceBase (IcacheSourceBase),
    .PtwSourceBase (IptwSourceBase)
  ) icache_inst (
    .clk_i,
    .rst_ni,
    .cache_h2d_i (icache_h2d),
    .cache_d2h_o (icache_d2h),
    .mem (ch[1]),
    .mem_ptw (ch[3])
  );

  muntjac_dcache #(
    .SourceWidth (SourceWidth),
    .SinkWidth (SinkWidth),
    .SourceBase (DcacheSourceBase),
    .PtwSourceBase (DptwSourceBase)
  ) dcache_inst (
    .clk_i,
    .rst_ni,
    .cache_h2d_i (dcache_h2d),
    .cache_d2h_o (dcache_d2h),
    .mem (ch[0]),
    .mem_ptw (ch[2])
  );

endmodule
