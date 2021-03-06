`include "tl_util.svh"

module muntjac_core import muntjac_pkg::*; #(
  // Bus width
  parameter DataWidth = 64,

  // Number of bits of physical address supported. This must not exceed 56.
  // This must match AddrWidth of the TileLink interface.
  parameter PhysAddrLen = 56,

  parameter rv64f_e RV64F = RV64FNone,

  parameter int unsigned DCacheWaysWidth = 2,
  parameter int unsigned DCacheSetsWidth = 6,
  parameter int unsigned ICacheWaysWidth = 2,
  parameter int unsigned ICacheSetsWidth = 6,
  parameter int unsigned DTlbNumWays = 4,
  parameter int unsigned DTlbSetsWidth = 3,
  parameter int unsigned ITlbNumWays = 4,
  parameter int unsigned ITlbSetsWidth = 3,

  // Number of additional hardware performance monitor counters other than mcycle and minstret.
  parameter int unsigned MHPMCounterNum = 0,
  parameter bit          MHPMICacheEnable = 1'b0,
  parameter bit          MHPMDCacheEnable = 1'b0,

  parameter int unsigned SourceWidth = 4,
  parameter int unsigned SinkWidth = 1
) (
    // Clock and reset
    input  logic            clk_i,
    input  logic            rst_ni,

    // Memory interface
    `TL_DECLARE_HOST_PORT(DataWidth, PhysAddrLen, SourceWidth, SinkWidth, mem),

    input  logic irq_software_m_i,
    input  logic irq_timer_m_i,
    input  logic irq_external_m_i,
    input  logic irq_external_s_i,

    input  logic [63:0] hart_id_i,

    input  logic [HPM_EVENT_NUM-1:0] hpm_event_i,

    // Debug connections
    output instr_trace_t dbg_o
);

  `TL_DECLARE(DataWidth, PhysAddrLen, SourceWidth, SinkWidth, mem);
  `TL_BIND_HOST_PORT(mem, mem);

  localparam [SourceWidth-1:0] DcacheSourceBase = 0;
  localparam [SourceWidth-1:0] IcacheSourceBase = 1;
  localparam [SourceWidth-1:0] DptwSourceBase = 2;
  localparam [SourceWidth-1:0] IptwSourceBase = 3;

  localparam [SourceWidth-1:0] SourceMask = 2;

  icache_h2d_t icache_h2d;
  icache_d2h_t icache_d2h;
  dcache_h2d_t dcache_h2d;
  dcache_d2h_t dcache_d2h;

  logic [HPM_EVENT_NUM-1:0] hpm_event;
  logic hpm_icache_access;
  logic hpm_icache_miss;
  logic hpm_itlb_miss;
  logic hpm_dcache_access;
  logic hpm_dcache_miss;
  logic hpm_dtlb_miss;
  always_comb begin
    // Passthrough exterior performance counters.
    hpm_event = hpm_event_i;
    hpm_event[HPM_EVENT_NONE] = 1'b0;
    hpm_event[HPM_EVENT_L1_ICACHE_ACCESS] = hpm_icache_access;
    hpm_event[HPM_EVENT_L1_ICACHE_MISS  ] = hpm_icache_miss;
    hpm_event[HPM_EVENT_L1_ITLB_MISS    ] = hpm_itlb_miss;
    hpm_event[HPM_EVENT_L1_DCACHE_ACCESS] = hpm_dcache_access;
    hpm_event[HPM_EVENT_L1_DCACHE_MISS  ] = hpm_dcache_miss;
    hpm_event[HPM_EVENT_L1_DTLB_MISS    ] = hpm_dtlb_miss;
  end

  muntjac_pipeline #(
    .PhysAddrLen (PhysAddrLen),
    .RV64F (RV64F),
    .MHPMCounterNum (MHPMCounterNum)
  ) pipeline (
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
      .hpm_event_i (hpm_event),
      .dbg_o
  );

  `TL_DECLARE_ARR(DataWidth, PhysAddrLen, SourceWidth, SinkWidth, ch, [1:0]);
  tl_socket_m1 #(
    .DataWidth(DataWidth),
    .AddrWidth (PhysAddrLen),
    .SourceWidth (SourceWidth),
    .SinkWidth (SinkWidth),
    .NumLinks (2),
    .NumCachedLinks (1),

    .NumSourceRange(1),
    .SourceBase({IcacheSourceBase}),
    .SourceMask({      SourceMask}),
    .SourceLink({1'd            1})
  ) socket (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_DEVICE_PORT(host, ch),
    `TL_CONNECT_HOST_PORT(device, mem)
  );

  muntjac_icache #(
    .DataWidth (DataWidth),
    .WaysWidth (ICacheWaysWidth),
    .SetsWidth (ICacheSetsWidth),
    .PhysAddrLen (PhysAddrLen),
    .SourceWidth (SourceWidth),
    .SinkWidth (SinkWidth),
    .SourceBase (IcacheSourceBase),
    .PtwSourceBase (IptwSourceBase),
    .TlbNumWays (ITlbNumWays),
    .TlbSetsWidth (ITlbSetsWidth),
    .EnableHpm (MHPMICacheEnable)
  ) icache_inst (
    .clk_i,
    .rst_ni,
    .cache_h2d_i (icache_h2d),
    .cache_d2h_o (icache_d2h),
    .hpm_access_o (hpm_icache_access),
    .hpm_miss_o (hpm_icache_miss),
    .hpm_tlb_miss_o (hpm_itlb_miss),
    `TL_CONNECT_HOST_PORT_IDX(mem, ch, [1])
  );

  muntjac_dcache #(
    .DataWidth (DataWidth),
    .WaysWidth (DCacheWaysWidth),
    .SetsWidth (DCacheSetsWidth),
    .PhysAddrLen (PhysAddrLen),
    .SourceWidth (SourceWidth),
    .SinkWidth (SinkWidth),
    .SourceBase (DcacheSourceBase),
    .PtwSourceBase (DptwSourceBase),
    .TlbNumWays (DTlbNumWays),
    .TlbSetsWidth (DTlbSetsWidth),
    .EnableHpm (MHPMDCacheEnable)
  ) dcache_inst (
    .clk_i,
    .rst_ni,
    .cache_h2d_i (dcache_h2d),
    .cache_d2h_o (dcache_d2h),
    .hpm_access_o (hpm_dcache_access),
    .hpm_miss_o (hpm_dcache_miss),
    .hpm_tlb_miss_o (hpm_dtlb_miss),
    `TL_CONNECT_HOST_PORT_IDX(mem, ch, [0])
  );

endmodule
