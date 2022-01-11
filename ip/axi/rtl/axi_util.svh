`ifndef AXI_UTIL_SV
`define AXI_UTIL_SV

// Struct definitions for each channel.
// We define them just as structs, and it's upon the user to typedef them or use them
// anonymously.

`define AXI_AW_STRUCT(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH) \
  struct packed { \
    logic                  [ID_WIDTH-1:0] id    ; \
    logic                [ADDR_WIDTH-1:0] addr  ; \
    logic                           [7:0] len   ; \
    logic                           [2:0] size  ; \
    axi_pkg::axi_burst_t                  burst ; \
    logic                                 lock  ; \
    axi_pkg::axi_cache_t                  cache ; \
    axi_pkg::axi_prot_t                   prot  ; \
    logic                           [3:0] qos   ; \
    logic                           [3:0] region; \
  }

`define AXI_W_STRUCT(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH) \
  struct packed { \
    logic                [DATA_WIDTH-1:0] data  ; \
    logic              [DATA_WIDTH/8-1:0] strb  ; \
    logic                                 last  ; \
  }

`define AXI_B_STRUCT(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH) \
  struct packed { \
    logic                  [ID_WIDTH-1:0] id    ; \
    axi_pkg::axi_resp_t                   resp  ; \
  }

`define AXI_AR_STRUCT(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH) \
  struct packed { \
    logic                  [ID_WIDTH-1:0] id    ; \
    logic                [ADDR_WIDTH-1:0] addr  ; \
    logic                           [7:0] len   ; \
    logic                           [2:0] size  ; \
    axi_pkg::axi_burst_t                  burst ; \
    logic                                 lock  ; \
    axi_pkg::axi_cache_t                  cache ; \
    axi_pkg::axi_prot_t                   prot  ; \
    logic                           [3:0] qos   ; \
    logic                           [3:0] region; \
  }

`define AXI_R_STRUCT(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH) \
  struct packed { \
    logic                  [ID_WIDTH-1:0] id    ; \
    logic                [DATA_WIDTH-1:0] data  ; \
    axi_pkg::axi_resp_t                   resp  ; \
    logic                                 last  ; \
  }

// Bit width for each channel.
// Useful if you need to pack structs into dense bitvectors.

`define AXI_AW_WIDTH(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH) \
    ((ADDR_WIDTH)+(ID_WIDTH)+29)

`define AXI_W_WIDTH(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH) \
    ((DATA_WIDTH)+(DATA_WIDTH)/8+1)

`define AXI_B_WIDTH(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH) \
    ((ID_WIDTH)+2)

`define AXI_AR_WIDTH(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH) \
    ((ADDR_WIDTH)+(ID_WIDTH)+29)

`define AXI_R_WIDTH(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH) \
    ((DATA_WIDTH)+(ID_WIDTH)+3)

// Macros for defining a AXI link or array of links.

`define AXI_DECLARE_ARR(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, NAME, ARR) \
  logic ARR NAME``_aw_ready; \
  logic ARR NAME``_aw_valid; \
  `AXI_AW_STRUCT(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH) ARR NAME``_aw; \
  logic ARR NAME``_w_ready; \
  logic ARR NAME``_w_valid; \
  `AXI_W_STRUCT(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH) ARR NAME``_w; \
  logic ARR NAME``_b_ready; \
  logic ARR NAME``_b_valid; \
  `AXI_B_STRUCT(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH) ARR NAME``_b; \
  logic ARR NAME``_ar_ready; \
  logic ARR NAME``_ar_valid; \
  `AXI_AR_STRUCT(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH) ARR NAME``_ar; \
  logic ARR NAME``_r_ready; \
  logic ARR NAME``_r_valid; \
  `AXI_R_STRUCT(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH) ARR NAME``_r

`define AXI_DECLARE(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, NAME) \
  `AXI_DECLARE_ARR(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, NAME, )

// Macros for defining a AXI port or array of ports.
// Three types of ports are defined: host, device and tap (all inputs).

`define AXI_DECLARE_PORT_IMPL(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, NAME, ARR, H2D, D2H, H2D_SUFFIX, D2H_SUFFIX) \
  D2H ARR NAME``_aw_ready``D2H_SUFFIX, \
  H2D ARR NAME``_aw_valid``H2D_SUFFIX, \
  H2D ARR [`AXI_AW_WIDTH(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH)-1:0] NAME``_aw``H2D_SUFFIX, \
  D2H ARR NAME``_w_ready``D2H_SUFFIX, \
  H2D ARR NAME``_w_valid``H2D_SUFFIX, \
  H2D ARR [`AXI_W_WIDTH(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH)-1:0] NAME``_w``H2D_SUFFIX, \
  H2D ARR NAME``_b_ready``H2D_SUFFIX, \
  D2H ARR NAME``_b_valid``D2H_SUFFIX, \
  D2H ARR [`AXI_B_WIDTH(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH)-1:0] NAME``_b``D2H_SUFFIX, \
  D2H ARR NAME``_ar_ready``D2H_SUFFIX, \
  H2D ARR NAME``_ar_valid``H2D_SUFFIX, \
  H2D ARR [`AXI_AR_WIDTH(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH)-1:0] NAME``_ar``H2D_SUFFIX, \
  H2D ARR NAME``_r_ready``H2D_SUFFIX, \
  D2H ARR NAME``_r_valid``D2H_SUFFIX, \
  D2H ARR [`AXI_R_WIDTH(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH)-1:0] NAME``_r``D2H_SUFFIX

`define AXI_DECLARE_HOST_PORT_ARR(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, NAME, ARR) \
  `AXI_DECLARE_PORT_IMPL(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, NAME, ARR, output, input, _o, _i)

`define AXI_DECLARE_HOST_PORT(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, NAME) \
  `AXI_DECLARE_HOST_PORT_ARR(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, NAME, )

`define AXI_DECLARE_DEVICE_PORT_ARR(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, NAME, ARR) \
  `AXI_DECLARE_PORT_IMPL(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, NAME, ARR, input, output, _i, _o)

`define AXI_DECLARE_DEVICE_PORT(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, NAME) \
  `AXI_DECLARE_DEVICE_PORT_ARR(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, NAME, )

`define AXI_DECLARE_TAP_PORT_ARR(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, NAME, ARR) \
  `AXI_DECLARE_PORT_IMPL(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, NAME, ARR, input, input, _i, _i)

`define AXI_DECLARE_TAP_PORT(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, NAME) \
  `AXI_DECLARE_TAP_PORT_ARR(DATA_WIDTH, ADDR_WIDTH, ID_WIDTH, NAME, )

// Macros for connecting a AXI link to a AXI port, or an array of links to an array of ports.

`define AXI_CONNECT_PORT_IMPL(PORT, NAME, IDX, H2D_SUFFIX, D2H_SUFFIX) \
  .PORT``_aw_ready``D2H_SUFFIX (NAME``_aw_ready IDX), \
  .PORT``_aw_valid``H2D_SUFFIX (NAME``_aw_valid IDX), \
  .PORT``_aw``H2D_SUFFIX       (NAME``_aw       IDX), \
  .PORT``_w_ready``D2H_SUFFIX  (NAME``_w_ready  IDX), \
  .PORT``_w_valid``H2D_SUFFIX  (NAME``_w_valid  IDX), \
  .PORT``_w``H2D_SUFFIX        (NAME``_w        IDX), \
  .PORT``_b_ready``H2D_SUFFIX  (NAME``_b_ready  IDX), \
  .PORT``_b_valid``D2H_SUFFIX  (NAME``_b_valid  IDX), \
  .PORT``_b``D2H_SUFFIX        (NAME``_b        IDX), \
  .PORT``_ar_ready``D2H_SUFFIX (NAME``_ar_ready IDX), \
  .PORT``_ar_valid``H2D_SUFFIX (NAME``_ar_valid IDX), \
  .PORT``_ar``H2D_SUFFIX       (NAME``_ar       IDX), \
  .PORT``_r_ready``H2D_SUFFIX  (NAME``_r_ready  IDX), \
  .PORT``_r_valid``D2H_SUFFIX  (NAME``_r_valid  IDX), \
  .PORT``_r``D2H_SUFFIX        (NAME``_r        IDX)

`define AXI_CONNECT_HOST_PORT_IDX(PORT, NAME, IDX) \
  `AXI_CONNECT_PORT_IMPL(PORT, NAME, IDX, _o, _i)

`define AXI_CONNECT_HOST_PORT(PORT, NAME) \
  `AXI_CONNECT_HOST_PORT_IDX(PORT, NAME, )

`define AXI_CONNECT_DEVICE_PORT_IDX(PORT, NAME, IDX) \
  `AXI_CONNECT_PORT_IMPL(PORT, NAME, IDX, _i, _o)

`define AXI_CONNECT_DEVICE_PORT(PORT, NAME) \
  `AXI_CONNECT_DEVICE_PORT_IDX(PORT, NAME, )

`define AXI_CONNECT_TAP_PORT_IDX(PORT, NAME, IDX) \
  `AXI_CONNECT_PORT_IMPL(PORT, NAME, IDX, _i, _i)

`define AXI_CONNECT_TAP_PORT(PORT, NAME) \
  `AXI_CONNECT_TAP_PORT_IDX(PORT, NAME, )

// Macros for fowarding a AXI port to a AXI port, or an array of ports to an array of ports.

`define AXI_FORWARD_PORT_IMPL(PORT, NAME, IDX, H2D_SUFFIX, D2H_SUFFIX, H2D_SUFFIX2, D2H_SUFFIX2) \
  .PORT``_aw_ready``D2H_SUFFIX (NAME``_aw_ready``D2H_SUFFIX2 IDX), \
  .PORT``_aw_valid``H2D_SUFFIX (NAME``_aw_valid``H2D_SUFFIX2 IDX), \
  .PORT``_aw``H2D_SUFFIX       (NAME``_aw``H2D_SUFFIX2       IDX), \
  .PORT``_w_ready``D2H_SUFFIX  (NAME``_w_ready``D2H_SUFFIX2  IDX), \
  .PORT``_w_valid``H2D_SUFFIX  (NAME``_w_valid``H2D_SUFFIX2  IDX), \
  .PORT``_w``H2D_SUFFIX        (NAME``_w``H2D_SUFFIX2        IDX), \
  .PORT``_b_ready``H2D_SUFFIX  (NAME``_b_ready``H2D_SUFFIX2  IDX), \
  .PORT``_b_valid``D2H_SUFFIX  (NAME``_b_valid``D2H_SUFFIX2  IDX), \
  .PORT``_b``D2H_SUFFIX        (NAME``_b``D2H_SUFFIX2        IDX), \
  .PORT``_ar_ready``D2H_SUFFIX (NAME``_ar_ready``D2H_SUFFIX2 IDX), \
  .PORT``_ar_valid``H2D_SUFFIX (NAME``_ar_valid``H2D_SUFFIX2 IDX), \
  .PORT``_ar``H2D_SUFFIX       (NAME``_ar``H2D_SUFFIX2       IDX), \
  .PORT``_r_ready``H2D_SUFFIX  (NAME``_r_ready``H2D_SUFFIX2  IDX), \
  .PORT``_r_valid``D2H_SUFFIX  (NAME``_r_valid``D2H_SUFFIX2  IDX), \
  .PORT``_r``D2H_SUFFIX        (NAME``_r``D2H_SUFFIX2        IDX)

`define AXI_FORWARD_HOST_PORT_IDX(PORT, NAME, IDX) \
  `AXI_FORWARD_PORT_IMPL(PORT, NAME, IDX, _o, _i, _o, _i)

`define AXI_FORWARD_HOST_PORT(PORT, NAME) \
  `AXI_FORWARD_HOST_PORT_IDX(PORT, NAME, )

`define AXI_FORWARD_DEVICE_PORT_IDX(PORT, NAME, IDX) \
  `AXI_FORWARD_PORT_IMPL(PORT, NAME, IDX, _i, _o, _i, _o)

`define AXI_FORWARD_DEVICE_PORT(PORT, NAME) \
  `AXI_FORWARD_DEVICE_PORT_IDX(PORT, NAME, )

`define AXI_FORWARD_TAP_PORT_IDX(PORT, NAME, IDX) \
  `AXI_FORWARD_PORT_IMPL(PORT, NAME, IDX, _i, _i, _i, _i)

`define AXI_FORWARD_TAP_PORT(PORT, NAME) \
  `AXI_FORWARD_TAP_PORT_IDX(PORT, NAME, )

`define AXI_FORWARD_TAP_PORT_FROM_HOST_IDX(PORT, NAME, IDX) \
  `AXI_FORWARD_PORT_IMPL(PORT, NAME, IDX, _i, _i, _o, _i)

`define AXI_FORWARD_TAP_PORT_FROM_HOST(PORT, NAME) \
  `AXI_FORWARD_TAP_PORT_FROM_HOST_IDX(PORT, NAME, )

`define AXI_FORWARD_TAP_PORT_FROM_DEVICE_IDX(PORT, NAME, IDX) \
  `AXI_FORWARD_PORT_IMPL(PORT, NAME, IDX, _i, _i, _i, _o)

`define AXI_FORWARD_TAP_PORT_FROM_DEVICE(PORT, NAME) \
  `AXI_FORWARD_TAP_PORT_FROM_DEVICE_IDX(PORT, NAME, )

// Macros for bind a AXI port to a AXI link, or an array of ports to an array of links.

`define AXI_BIND_HOST_PORT_IDX(PORT, IDX_P, NAME, IDX_L) \
  assign NAME``_aw_ready   IDX_L = PORT``_aw_ready_i IDX_P; \
  assign PORT``_aw_valid_o IDX_P = NAME``_aw_valid   IDX_L; \
  assign PORT``_aw_o       IDX_P = NAME``_aw         IDX_L; \
  assign NAME``_w_ready    IDX_L = PORT``_w_ready_i  IDX_P; \
  assign PORT``_w_valid_o  IDX_P = NAME``_w_valid    IDX_L; \
  assign PORT``_w_o        IDX_P = NAME``_w          IDX_L; \
  assign PORT``_b_ready_o  IDX_P = NAME``_b_ready    IDX_L; \
  assign NAME``_b_valid    IDX_L = PORT``_b_valid_i  IDX_P; \
  assign NAME``_b          IDX_L = PORT``_b_i        IDX_P; \
  assign NAME``_ar_ready   IDX_L = PORT``_ar_ready_i IDX_P; \
  assign PORT``_ar_valid_o IDX_P = NAME``_ar_valid   IDX_L; \
  assign PORT``_ar_o       IDX_P = NAME``_ar         IDX_L; \
  assign PORT``_r_ready_o  IDX_P = NAME``_r_ready    IDX_L; \
  assign NAME``_r_valid    IDX_L = PORT``_r_valid_i  IDX_P; \
  assign NAME``_r          IDX_L = PORT``_r_i        IDX_P

`define AXI_BIND_HOST_PORT(PORT, NAME) \
  `AXI_BIND_HOST_PORT_IDX(PORT, , NAME, )

`define AXI_BIND_DEVICE_PORT_IDX(PORT, IDX_P, NAME, IDX_L) \
  assign PORT``_aw_ready_o IDX_P = NAME``_aw_ready   IDX_L; \
  assign NAME``_aw_valid   IDX_L = PORT``_aw_valid_i IDX_P; \
  assign NAME``_aw         IDX_L = PORT``_aw_i       IDX_P; \
  assign PORT``_w_ready_o  IDX_P = NAME``_w_ready    IDX_L; \
  assign NAME``_w_valid    IDX_L = PORT``_w_valid_i  IDX_P; \
  assign NAME``_w          IDX_L = PORT``_w_i        IDX_P; \
  assign NAME``_b_ready    IDX_L = PORT``_b_ready_i  IDX_P; \
  assign PORT``_b_valid_o  IDX_P = NAME``_b_valid    IDX_L; \
  assign PORT``_b_o        IDX_P = NAME``_b          IDX_L; \
  assign PORT``_ar_ready_o IDX_P = NAME``_ar_ready   IDX_L; \
  assign NAME``_ar_valid   IDX_L = PORT``_ar_valid_i IDX_P; \
  assign NAME``_ar         IDX_L = PORT``_ar_i       IDX_P; \
  assign NAME``_r_ready    IDX_L = PORT``_r_ready_i  IDX_P; \
  assign PORT``_r_valid_o  IDX_P = NAME``_r_valid    IDX_L; \
  assign PORT``_r_o        IDX_P = NAME``_r          IDX_L

`define AXI_BIND_DEVICE_PORT(PORT, NAME) \
  `AXI_BIND_DEVICE_PORT_IDX(PORT, , NAME, )

`define AXI_BIND_TAP_PORT_IDX(PORT, IDX_P, NAME, IDX_L) \
  assign NAME``_aw_ready   IDX_L = PORT``_aw_ready_i IDX_P; \
  assign NAME``_aw_valid   IDX_L = PORT``_aw_valid_i IDX_P; \
  assign NAME``_aw         IDX_L = PORT``_aw_i       IDX_P; \
  assign NAME``_w_ready    IDX_L = PORT``_w_ready_i  IDX_P; \
  assign NAME``_w_valid    IDX_L = PORT``_w_valid_i  IDX_P; \
  assign NAME``_w          IDX_L = PORT``_w_i        IDX_P; \
  assign NAME``_b_ready    IDX_L = PORT``_b_ready_i  IDX_P; \
  assign NAME``_b_valid    IDX_L = PORT``_b_valid_i  IDX_P; \
  assign NAME``_b          IDX_L = PORT``_b_i        IDX_P; \
  assign NAME``_ar_ready   IDX_L = PORT``_ar_ready_i IDX_P; \
  assign NAME``_ar_valid   IDX_L = PORT``_ar_valid_i IDX_P; \
  assign NAME``_ar         IDX_L = PORT``_ar_i       IDX_P; \
  assign NAME``_r_ready    IDX_L = PORT``_r_ready_i  IDX_P; \
  assign NAME``_r_valid    IDX_L = PORT``_r_valid_i  IDX_P; \
  assign NAME``_r          IDX_L = PORT``_r_i        IDX_P

`define AXI_BIND_TAP_PORT(PORT, NAME) \
  `AXI_BIND_TAP_PORT_IDX(PORT, , NAME, )

`endif // AXI_UTIL_SV
