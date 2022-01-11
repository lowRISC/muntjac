`include "axi_util.svh"

module axi_regslice #(
  parameter  int unsigned DataWidth     = 64,
  parameter  int unsigned AddrWidth     = 56,
  parameter  int unsigned IdWidth       = 1,

  parameter  int unsigned AwMode        = 0,
  parameter  int unsigned WMode         = 0,
  parameter  int unsigned BMode         = 0,
  parameter  int unsigned ArMode        = 0,
  parameter  int unsigned RMode         = 0
) (
  input  logic clk_i,
  input  logic rst_ni,

  `AXI_DECLARE_DEVICE_PORT(DataWidth, AddrWidth, IdWidth, host),
  `AXI_DECLARE_HOST_PORT(DataWidth, AddrWidth, IdWidth, device)
);

  `AXI_DECLARE(DataWidth, AddrWidth, IdWidth, host);
  `AXI_DECLARE(DataWidth, AddrWidth, IdWidth, device);
  `AXI_BIND_DEVICE_PORT(host, host);
  `AXI_BIND_HOST_PORT(device, device);

  ////////////////////////
  // #region AW channel //

  typedef `AXI_AW_STRUCT(DataWidth, AddrWidth, IdWidth) aw_t;

  openip_regslice #(
    .TYPE (aw_t),
    .FORWARD          ((AwMode & 1) != 0),
    .REVERSE          ((AwMode & 2) != 0),
    .HIGH_PERFORMANCE ((AwMode & 4) != 0)
  ) aw_fifo (
    .clk     (clk_i),
    .rstn    (rst_ni),
    .w_valid (host_aw_valid),
    .w_ready (host_aw_ready),
    .w_data  (host_aw),
    .r_valid (device_aw_valid),
    .r_ready (device_aw_ready),
    .r_data  (device_aw)
  );

  // #endregion
  ////////////////////////

  ///////////////////////
  // #region W channel //

  typedef `AXI_W_STRUCT(DataWidth, AddrWidth, IdWidth) w_t;

  openip_regslice #(
    .TYPE (w_t),
    .FORWARD          ((WMode & 1) != 0),
    .REVERSE          ((WMode & 2) != 0),
    .HIGH_PERFORMANCE ((WMode & 4) != 0)
  ) w_fifo (
    .clk     (clk_i),
    .rstn    (rst_ni),
    .w_valid (host_w_valid),
    .w_ready (host_w_ready),
    .w_data  (host_w),
    .r_valid (device_w_valid),
    .r_ready (device_w_ready),
    .r_data  (device_w)
  );

  // #endregion
  ///////////////////////

  ///////////////////////
  // #region B channel //

  typedef `AXI_B_STRUCT(DataWidth, AddrWidth, IdWidth) b_t;

  openip_regslice #(
    .TYPE (b_t),
    .FORWARD          ((BMode & 1) != 0),
    .REVERSE          ((BMode & 2) != 0),
    .HIGH_PERFORMANCE ((BMode & 4) != 0)
  ) b_fifo (
    .clk     (clk_i),
    .rstn    (rst_ni),
    .w_valid (device_b_valid),
    .w_ready (device_b_ready),
    .w_data  (device_b),
    .r_valid (host_b_valid),
    .r_ready (host_b_ready),
    .r_data  (host_b)
  );

  // #endregion
  ///////////////////////

  ////////////////////////
  // #region AR channel //

  typedef `AXI_AR_STRUCT(DataWidth, AddrWidth, IdWidth) ar_t;

  openip_regslice #(
    .TYPE (ar_t),
    .FORWARD          ((ArMode & 1) != 0),
    .REVERSE          ((ArMode & 2) != 0),
    .HIGH_PERFORMANCE ((ArMode & 4) != 0)
  ) ar_fifo (
    .clk     (clk_i),
    .rstn    (rst_ni),
    .w_valid (host_ar_valid),
    .w_ready (host_ar_ready),
    .w_data  (host_ar),
    .r_valid (device_ar_valid),
    .r_ready (device_ar_ready),
    .r_data  (device_ar)
  );

  // #endregion
  ////////////////////////

  ///////////////////////
  // #region R channel //

  typedef `AXI_R_STRUCT(DataWidth, AddrWidth, IdWidth) r_t;

  openip_regslice #(
    .TYPE (r_t),
    .FORWARD          ((RMode & 1) != 0),
    .REVERSE          ((RMode & 2) != 0),
    .HIGH_PERFORMANCE ((RMode & 4) != 0)
  ) r_fifo (
    .clk     (clk_i),
    .rstn    (rst_ni),
    .w_valid (device_r_valid),
    .w_ready (device_r_ready),
    .w_data  (device_r),
    .r_valid (host_r_valid),
    .r_ready (host_r_ready),
    .r_data  (host_r)
  );

  // #endregion
  ///////////////////////

endmodule
