`ifndef AXI_LITE_UTIL_SV
`define AXI_LITE_UTIL_SV

// Struct definitions for each channel.
// We define them just as structs, and it's upon the user to typedef them or use them
// anonymously.

`define AXI_LITE_AW_STRUCT(DATA_WIDTH, ADDR_WIDTH) \
  struct packed { \
    logic                [ADDR_WIDTH-1:0] addr  ; \
    axi_pkg::axi_prot_t                   prot  ; \
  }

`define AXI_LITE_W_STRUCT(DATA_WIDTH, ADDR_WIDTH) \
  struct packed { \
    logic                [DATA_WIDTH-1:0] data  ; \
    logic              [DATA_WIDTH/8-1:0] strb  ; \
  }

`define AXI_LITE_B_STRUCT(DATA_WIDTH, ADDR_WIDTH) \
  struct packed { \
    axi_pkg::axi_resp_t                   resp  ; \
  }

`define AXI_LITE_AR_STRUCT(DATA_WIDTH, ADDR_WIDTH) \
  struct packed { \
    logic                [ADDR_WIDTH-1:0] addr  ; \
    axi_pkg::axi_prot_t                   prot  ; \
  }

`define AXI_LITE_R_STRUCT(DATA_WIDTH, ADDR_WIDTH) \
  struct packed { \
    logic                [DATA_WIDTH-1:0] data  ; \
    axi_pkg::axi_resp_t                   resp  ; \
  }

// Bit width for each channel.
// Useful if you need to pack structs into dense bitvectors.

`define AXI_LITE_AW_WIDTH(DATA_WIDTH, ADDR_WIDTH) \
    ((ADDR_WIDTH)+3)

`define AXI_LITE_W_WIDTH(DATA_WIDTH, ADDR_WIDTH) \
    ((DATA_WIDTH)+(DATA_WIDTH)/8)

`define AXI_LITE_B_WIDTH(DATA_WIDTH, ADDR_WIDTH) \
    (2)

`define AXI_LITE_AR_WIDTH(DATA_WIDTH, ADDR_WIDTH) \
    ((ADDR_WIDTH)+3)

`define AXI_LITE_R_WIDTH(DATA_WIDTH, ADDR_WIDTH) \
    ((DATA_WIDTH)+2)

// Macros for defining a AXI-Lite link or array of links.

`define AXI_LITE_DECLARE_ARR(DATA_WIDTH, ADDR_WIDTH, NAME, ARR) \
  logic ARR NAME``_aw_ready; \
  logic ARR NAME``_aw_valid; \
  `AXI_LITE_AW_STRUCT(DATA_WIDTH, ADDR_WIDTH) ARR NAME``_aw; \
  logic ARR NAME``_w_ready; \
  logic ARR NAME``_w_valid; \
  `AXI_LITE_W_STRUCT(DATA_WIDTH, ADDR_WIDTH) ARR NAME``_w; \
  logic ARR NAME``_b_ready; \
  logic ARR NAME``_b_valid; \
  `AXI_LITE_B_STRUCT(DATA_WIDTH, ADDR_WIDTH) ARR NAME``_b; \
  logic ARR NAME``_ar_ready; \
  logic ARR NAME``_ar_valid; \
  `AXI_LITE_AR_STRUCT(DATA_WIDTH, ADDR_WIDTH) ARR NAME``_ar; \
  logic ARR NAME``_r_ready; \
  logic ARR NAME``_r_valid; \
  `AXI_LITE_R_STRUCT(DATA_WIDTH, ADDR_WIDTH) ARR NAME``_r

`define AXI_LITE_DECLARE(DATA_WIDTH, ADDR_WIDTH, NAME) \
  `AXI_LITE_DECLARE_ARR(DATA_WIDTH, ADDR_WIDTH, NAME, )

// Macros for defining a AXI-Lite port or array of ports.
// Three types of ports are defined: host, device and tap (all inputs).

`define AXI_LITE_DECLARE_PORT_IMPL(DATA_WIDTH, ADDR_WIDTH, NAME, ARR, H2D, D2H, H2D_SUFFIX, D2H_SUFFIX) \
  D2H ARR NAME``_aw_ready``D2H_SUFFIX, \
  H2D ARR NAME``_aw_valid``H2D_SUFFIX, \
  H2D ARR [`AXI_LITE_AW_WIDTH(DATA_WIDTH, ADDR_WIDTH)-1:0] NAME``_aw``H2D_SUFFIX, \
  D2H ARR NAME``_w_ready``D2H_SUFFIX, \
  H2D ARR NAME``_w_valid``H2D_SUFFIX, \
  H2D ARR [`AXI_LITE_W_WIDTH(DATA_WIDTH, ADDR_WIDTH)-1:0] NAME``_w``H2D_SUFFIX, \
  H2D ARR NAME``_b_ready``H2D_SUFFIX, \
  D2H ARR NAME``_b_valid``D2H_SUFFIX, \
  D2H ARR [`AXI_LITE_B_WIDTH(DATA_WIDTH, ADDR_WIDTH)-1:0] NAME``_b``D2H_SUFFIX, \
  D2H ARR NAME``_ar_ready``D2H_SUFFIX, \
  H2D ARR NAME``_ar_valid``H2D_SUFFIX, \
  H2D ARR [`AXI_LITE_AR_WIDTH(DATA_WIDTH, ADDR_WIDTH)-1:0] NAME``_ar``H2D_SUFFIX, \
  H2D ARR NAME``_r_ready``H2D_SUFFIX, \
  D2H ARR NAME``_r_valid``D2H_SUFFIX, \
  D2H ARR [`AXI_LITE_R_WIDTH(DATA_WIDTH, ADDR_WIDTH)-1:0] NAME``_r``D2H_SUFFIX

`define AXI_LITE_DECLARE_HOST_PORT_ARR(DATA_WIDTH, ADDR_WIDTH, NAME, ARR) \
  `AXI_LITE_DECLARE_PORT_IMPL(DATA_WIDTH, ADDR_WIDTH, NAME, ARR, output, input, _o, _i)

`define AXI_LITE_DECLARE_HOST_PORT(DATA_WIDTH, ADDR_WIDTH, NAME) \
  `AXI_LITE_DECLARE_HOST_PORT_ARR(DATA_WIDTH, ADDR_WIDTH, NAME, )

`define AXI_LITE_DECLARE_DEVICE_PORT_ARR(DATA_WIDTH, ADDR_WIDTH, NAME, ARR) \
  `AXI_LITE_DECLARE_PORT_IMPL(DATA_WIDTH, ADDR_WIDTH, NAME, ARR, input, output, _i, _o)

`define AXI_LITE_DECLARE_DEVICE_PORT(DATA_WIDTH, ADDR_WIDTH, NAME) \
  `AXI_LITE_DECLARE_DEVICE_PORT_ARR(DATA_WIDTH, ADDR_WIDTH, NAME, )

`define AXI_LITE_DECLARE_TAP_PORT_ARR(DATA_WIDTH, ADDR_WIDTH, NAME, ARR) \
  `AXI_LITE_DECLARE_PORT_IMPL(DATA_WIDTH, ADDR_WIDTH, NAME, ARR, input, input, _i, _i)

`define AXI_LITE_DECLARE_TAP_PORT(DATA_WIDTH, ADDR_WIDTH, NAME) \
  `AXI_LITE_DECLARE_TAP_PORT_ARR(DATA_WIDTH, ADDR_WIDTH, NAME, )

`endif // AXI_UTIL_SV
