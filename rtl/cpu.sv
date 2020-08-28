import muntjac_pkg::*;

module cpu #(
    parameter XLEN = 64
) (
    // Clock and reset
    input  logic            clk_i,
    input  logic            rst_ni,

    // Memory interfaces
    icache_intf.user icache,
    dcache_intf.user dcache,

    input  logic irq_m_timer,
    input  logic irq_m_software,
    input  logic irq_m_external,
    input  logic irq_s_external,

    input  logic [XLEN-1:0] mhartid,

    // Debug connections
    output logic [XLEN-1:0]    dbg_pc
);

    // CSR
    logic [XLEN-1:0] satp;
    priv_lvl_e prv;
    status_t status;

    // WB-IF interfacing, valid only when a PC override is required.
    logic wb_if_valid;
    if_reason_e wb_if_reason;
    logic [XLEN-1:0] wb_if_pc;
    branch_info_t wb_if_branch_info;

    // IF-DE interfacing
    logic if_de_valid;
    logic if_de_ready;
    fetched_instr_t if_de_instr;

    //
    // IF stage
    //
    instr_fetcher #(
        .XLEN(XLEN)
    ) fetcher (
        .clk (clk_i),
        .resetn (rst_ni),
        .cache_uncompressed (icache),
        .i_pc (wb_if_pc),
        .i_branch_info (wb_if_branch_info),
        .i_valid (wb_if_valid),
        .i_reason (wb_if_reason),
        .i_prv (prv[0]),
        .i_sum (status.sum),
        .i_atp ({prv == PRIV_LVL_M ? 4'd0 : satp[63:60], satp[59:0]}),
        .o_valid (if_de_valid),
        .o_ready (if_de_ready),
        .o_fetched_instr (if_de_instr)
    );

    muntjac_backend backend (
        .clk_i,
        .rst_ni,
        .dcache,
        .satp_o (satp),
        .prv_o  (prv),
        .status_o (status),
        .redirect_valid_o (wb_if_valid),
        .redirect_reason_o (wb_if_reason),
        .redirect_pc_o (wb_if_pc),
        .branch_info_o (wb_if_branch_info),
        .fetch_valid_i (if_de_valid),
        .fetch_ready_o (if_de_ready),
        .fetch_instr_i (if_de_instr),
        .irq_software_m_i (irq_m_software),
        .irq_timer_m_i (irq_m_timer),
        .irq_external_m_i (irq_m_external),
        .irq_external_s_i (irq_s_external),
        .hart_id_i (mhartid),
        .dbg_pc_o (dbg_pc)
    );

endmodule
