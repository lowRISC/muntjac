`ifndef TL_UTIL_SV
`define TL_UTIL_SV

// TileLink size is at least 2 (for TL-UL link) and at most 4 (as the maximum size is
// 4096 bytes so size is 12). The usual value we use is 3 for TL-UH and TL-C link, but
// we prefer to fix it since it is just an extra bit and usually can be removed by optimiser.
`define TL_SIZE_WIDTH 4

// Struct definitions for each channel.
// We define them just as structs, and it's upon the user to typedef them or use them
// anonymously.

`define TL_A_STRUCT(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH) \
  struct packed { \
    tl_pkg::tl_a_op_e                    opcode ; \
    logic                          [2:0] param  ; \
    logic           [`TL_SIZE_WIDTH-1:0] size   ; \
    logic             [SOURCE_WIDTH-1:0] source ; \
    logic               [ADDR_WIDTH-1:0] address; \
    logic             [DATA_WIDTH/8-1:0] mask   ; \
    logic                                corrupt; \
    logic               [DATA_WIDTH-1:0] data   ; \
  }

`define TL_B_STRUCT(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH) \
  struct packed { \
    tl_pkg::tl_b_op_e                    opcode ; \
    logic                          [2:0] param  ; \
    logic           [`TL_SIZE_WIDTH-1:0] size   ; \
    logic             [SOURCE_WIDTH-1:0] source ; \
    logic               [ADDR_WIDTH-1:0] address; \
  }

`define TL_C_STRUCT(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH) \
  struct packed { \
    tl_pkg::tl_c_op_e                    opcode ; \
    logic                          [2:0] param  ; \
    logic           [`TL_SIZE_WIDTH-1:0] size   ; \
    logic             [SOURCE_WIDTH-1:0] source ; \
    logic               [ADDR_WIDTH-1:0] address; \
    logic                                corrupt; \
    logic               [DATA_WIDTH-1:0] data   ; \
  }

`define TL_D_STRUCT(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH) \
  struct packed { \
    tl_pkg::tl_d_op_e                    opcode ; \
    logic                          [2:0] param  ; \
    logic           [`TL_SIZE_WIDTH-1:0] size   ; \
    logic             [SOURCE_WIDTH-1:0] source ; \
    logic               [SINK_WIDTH-1:0] sink   ; \
    logic                                denied ; \
    logic                                corrupt; \
    logic               [DATA_WIDTH-1:0] data   ; \
  }

`define TL_E_STRUCT(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH) \
  struct packed { \
    logic               [SINK_WIDTH-1:0] sink   ; \
  }

// Bit width for each channel.
// Useful if you need to pack structs into dense bitvectors.

`define TL_A_WIDTH(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH) \
    ((DATA_WIDTH)+(DATA_WIDTH)/8+(ADDR_WIDTH)+(`TL_SIZE_WIDTH)+(SOURCE_WIDTH)+7)

`define TL_B_WIDTH(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH) \
    ((ADDR_WIDTH)+(`TL_SIZE_WIDTH)+(SOURCE_WIDTH)+6)

`define TL_C_WIDTH(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH) \
    ((DATA_WIDTH)+(ADDR_WIDTH)+(`TL_SIZE_WIDTH)+(SOURCE_WIDTH)+7)

`define TL_D_WIDTH(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH) \
    ((DATA_WIDTH)+(`TL_SIZE_WIDTH)+(SOURCE_WIDTH)+(SINK_WIDTH)+8)

`define TL_E_WIDTH(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH) \
    (SINK_WIDTH)

// Macros for defining a TileLink link or array of links.

`define TL_DECLARE_ARR(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH, NAME, ARR) \
  logic ARR NAME``_a_ready; \
  logic ARR NAME``_a_valid; \
  `TL_A_STRUCT(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH) ARR NAME``_a; \
  logic ARR NAME``_b_ready; \
  logic ARR NAME``_b_valid; \
  `TL_B_STRUCT(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH) ARR NAME``_b; \
  logic ARR NAME``_c_ready; \
  logic ARR NAME``_c_valid; \
  `TL_C_STRUCT(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH) ARR NAME``_c; \
  logic ARR NAME``_d_ready; \
  logic ARR NAME``_d_valid; \
  `TL_D_STRUCT(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH) ARR NAME``_d; \
  logic ARR NAME``_e_ready; \
  logic ARR NAME``_e_valid; \
  `TL_E_STRUCT(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH) ARR NAME``_e

`define TL_DECLARE(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH, NAME) \
  `TL_DECLARE_ARR(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH, NAME, )

// Macros for defining a TileLink port or array of ports.
// Three types of ports are defined: host, device and tap (all inputs).

`define TL_DECLARE_PORT_IMPL(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH, NAME, ARR, H2D, D2H, H2D_SUFFIX, D2H_SUFFIX) \
  D2H ARR NAME``_a_ready``D2H_SUFFIX, \
  H2D ARR NAME``_a_valid``H2D_SUFFIX, \
  H2D ARR [`TL_A_WIDTH(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH)-1:0] NAME``_a``H2D_SUFFIX, \
  H2D ARR NAME``_b_ready``H2D_SUFFIX, \
  D2H ARR NAME``_b_valid``D2H_SUFFIX, \
  D2H ARR [`TL_B_WIDTH(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH)-1:0] NAME``_b``D2H_SUFFIX, \
  D2H ARR NAME``_c_ready``D2H_SUFFIX, \
  H2D ARR NAME``_c_valid``H2D_SUFFIX, \
  H2D ARR [`TL_C_WIDTH(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH)-1:0] NAME``_c``H2D_SUFFIX, \
  H2D ARR NAME``_d_ready``H2D_SUFFIX, \
  D2H ARR NAME``_d_valid``D2H_SUFFIX, \
  D2H ARR [`TL_D_WIDTH(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH)-1:0] NAME``_d``D2H_SUFFIX, \
  D2H ARR NAME``_e_ready``D2H_SUFFIX, \
  H2D ARR NAME``_e_valid``H2D_SUFFIX, \
  H2D ARR [`TL_E_WIDTH(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH)-1:0] NAME``_e``H2D_SUFFIX

`define TL_DECLARE_HOST_PORT_ARR(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH, NAME, ARR) \
  `TL_DECLARE_PORT_IMPL(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH, NAME, ARR, output, input, _o, _i)

`define TL_DECLARE_HOST_PORT(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH, NAME) \
  `TL_DECLARE_HOST_PORT_ARR(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH, NAME, )

`define TL_DECLARE_DEVICE_PORT_ARR(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH, NAME, ARR) \
  `TL_DECLARE_PORT_IMPL(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH, NAME, ARR, input, output, _i, _o)

`define TL_DECLARE_DEVICE_PORT(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH, NAME) \
  `TL_DECLARE_DEVICE_PORT_ARR(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH, NAME, )

`define TL_DECLARE_TAP_PORT_ARR(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH, NAME, ARR) \
  `TL_DECLARE_PORT_IMPL(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH, NAME, ARR, input, input, _i, _i)

`define TL_DECLARE_TAP_PORT(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH, NAME) \
  `TL_DECLARE_TAP_PORT_ARR(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH, NAME, )

// Macros for connecting a TileLink link to a TileLink port, or an array of links to an array of ports.

`define TL_CONNECT_PORT_IMPL(PORT, NAME, IDX, H2D_SUFFIX, D2H_SUFFIX) \
  .PORT``_a_ready``D2H_SUFFIX (NAME``_a_ready IDX), \
  .PORT``_a_valid``H2D_SUFFIX (NAME``_a_valid IDX), \
  .PORT``_a``H2D_SUFFIX       (NAME``_a       IDX), \
  .PORT``_b_ready``H2D_SUFFIX (NAME``_b_ready IDX), \
  .PORT``_b_valid``D2H_SUFFIX (NAME``_b_valid IDX), \
  .PORT``_b``D2H_SUFFIX       (NAME``_b       IDX), \
  .PORT``_c_ready``D2H_SUFFIX (NAME``_c_ready IDX), \
  .PORT``_c_valid``H2D_SUFFIX (NAME``_c_valid IDX), \
  .PORT``_c``H2D_SUFFIX       (NAME``_c       IDX), \
  .PORT``_d_ready``H2D_SUFFIX (NAME``_d_ready IDX), \
  .PORT``_d_valid``D2H_SUFFIX (NAME``_d_valid IDX), \
  .PORT``_d``D2H_SUFFIX       (NAME``_d       IDX), \
  .PORT``_e_ready``D2H_SUFFIX (NAME``_e_ready IDX), \
  .PORT``_e_valid``H2D_SUFFIX (NAME``_e_valid IDX), \
  .PORT``_e``H2D_SUFFIX       (NAME``_e       IDX)

`define TL_CONNECT_HOST_PORT_IDX(PORT, NAME, IDX) \
  `TL_CONNECT_PORT_IMPL(PORT, NAME, IDX, _o, _i)

`define TL_CONNECT_HOST_PORT(PORT, NAME) \
  `TL_CONNECT_HOST_PORT_IDX(PORT, NAME, )

`define TL_CONNECT_DEVICE_PORT_IDX(PORT, NAME, IDX) \
  `TL_CONNECT_PORT_IMPL(PORT, NAME, IDX, _i, _o)

`define TL_CONNECT_DEVICE_PORT(PORT, NAME) \
  `TL_CONNECT_DEVICE_PORT_IDX(PORT, NAME, )

`define TL_CONNECT_TAP_PORT_IDX(PORT, NAME, IDX) \
  `TL_CONNECT_PORT_IMPL(PORT, NAME, IDX, _i, _i)

`define TL_CONNECT_TAP_PORT(PORT, NAME) \
  `TL_CONNECT_TAP_PORT_IDX(PORT, NAME, )

// Macros for fowarding a TileLink port to a TileLink port, or an array of ports to an array of ports.

`define TL_FORWARD_PORT_IMPL(PORT, NAME, IDX, H2D_SUFFIX, D2H_SUFFIX, H2D_SUFFIX2, D2H_SUFFIX2) \
  .PORT``_a_ready``D2H_SUFFIX (NAME``_a_ready``D2H_SUFFIX2 IDX), \
  .PORT``_a_valid``H2D_SUFFIX (NAME``_a_valid``H2D_SUFFIX2 IDX), \
  .PORT``_a``H2D_SUFFIX       (NAME``_a``H2D_SUFFIX2       IDX), \
  .PORT``_b_ready``H2D_SUFFIX (NAME``_b_ready``H2D_SUFFIX2 IDX), \
  .PORT``_b_valid``D2H_SUFFIX (NAME``_b_valid``D2H_SUFFIX2 IDX), \
  .PORT``_b``D2H_SUFFIX       (NAME``_b``D2H_SUFFIX2       IDX), \
  .PORT``_c_ready``D2H_SUFFIX (NAME``_c_ready``D2H_SUFFIX2 IDX), \
  .PORT``_c_valid``H2D_SUFFIX (NAME``_c_valid``H2D_SUFFIX2 IDX), \
  .PORT``_c``H2D_SUFFIX       (NAME``_c``H2D_SUFFIX2       IDX), \
  .PORT``_d_ready``H2D_SUFFIX (NAME``_d_ready``H2D_SUFFIX2 IDX), \
  .PORT``_d_valid``D2H_SUFFIX (NAME``_d_valid``D2H_SUFFIX2 IDX), \
  .PORT``_d``D2H_SUFFIX       (NAME``_d``D2H_SUFFIX2       IDX), \
  .PORT``_e_ready``D2H_SUFFIX (NAME``_e_ready``D2H_SUFFIX2 IDX), \
  .PORT``_e_valid``H2D_SUFFIX (NAME``_e_valid``H2D_SUFFIX2 IDX), \
  .PORT``_e``H2D_SUFFIX       (NAME``_e``H2D_SUFFIX2       IDX)

`define TL_FORWARD_HOST_PORT_IDX(PORT, NAME, IDX) \
  `TL_FORWARD_PORT_IMPL(PORT, NAME, IDX, _o, _i, _o, _i)

`define TL_FORWARD_HOST_PORT(PORT, NAME) \
  `TL_FORWARD_HOST_PORT_IDX(PORT, NAME, )

`define TL_FORWARD_DEVICE_PORT_IDX(PORT, NAME, IDX) \
  `TL_FORWARD_PORT_IMPL(PORT, NAME, IDX, _i, _o, _i, _o)

`define TL_FORWARD_DEVICE_PORT(PORT, NAME) \
  `TL_FORWARD_DEVICE_PORT_IDX(PORT, NAME, )

`define TL_FORWARD_TAP_PORT_IDX(PORT, NAME, IDX) \
  `TL_FORWARD_PORT_IMPL(PORT, NAME, IDX, _i, _i, _i, _i)

`define TL_FORWARD_TAP_PORT(PORT, NAME) \
  `TL_FORWARD_TAP_PORT_IDX(PORT, NAME, )

`define TL_FORWARD_TAP_PORT_FROM_HOST_IDX(PORT, NAME, IDX) \
  `TL_FORWARD_PORT_IMPL(PORT, NAME, IDX, _i, _i, _o, _i)

`define TL_FORWARD_TAP_PORT_FROM_HOST(PORT, NAME) \
  `TL_FORWARD_TAP_PORT_FROM_HOST_IDX(PORT, NAME, )

`define TL_FORWARD_TAP_PORT_FROM_DEVICE_IDX(PORT, NAME, IDX) \
  `TL_FORWARD_PORT_IMPL(PORT, NAME, IDX, _i, _i, _i, _o)

`define TL_FORWARD_TAP_PORT_FROM_DEVICE(PORT, NAME) \
  `TL_FORWARD_TAP_PORT_FROM_DEVICE_IDX(PORT, NAME, )

// Macros for bind a TileLink port to a TileLink link, or an array of ports to an array of links.

`define TL_BIND_HOST_PORT_IDX(PORT, IDX_P, NAME, IDX_L) \
  assign NAME``_a_ready   IDX_L = PORT``_a_ready_i IDX_P; \
  assign PORT``_a_valid_o IDX_P = NAME``_a_valid   IDX_L; \
  assign PORT``_a_o       IDX_P = NAME``_a         IDX_L; \
  assign PORT``_b_ready_o IDX_P = NAME``_b_ready   IDX_L; \
  assign NAME``_b_valid   IDX_L = PORT``_b_valid_i IDX_P; \
  assign NAME``_b         IDX_L = PORT``_b_i       IDX_P; \
  assign NAME``_c_ready   IDX_L = PORT``_c_ready_i IDX_P; \
  assign PORT``_c_valid_o IDX_P = NAME``_c_valid   IDX_L; \
  assign PORT``_c_o       IDX_P = NAME``_c         IDX_L; \
  assign PORT``_d_ready_o IDX_P = NAME``_d_ready   IDX_L; \
  assign NAME``_d_valid   IDX_L = PORT``_d_valid_i IDX_P; \
  assign NAME``_d         IDX_L = PORT``_d_i       IDX_P; \
  assign NAME``_e_ready   IDX_L = PORT``_e_ready_i IDX_P; \
  assign PORT``_e_valid_o IDX_P = NAME``_e_valid   IDX_L; \
  assign PORT``_e_o       IDX_P = NAME``_e         IDX_L

`define TL_BIND_HOST_PORT(PORT, NAME) \
  `TL_BIND_HOST_PORT_IDX(PORT, , NAME, )

`define TL_BIND_DEVICE_PORT_IDX(PORT, IDX_P, NAME, IDX_L) \
  assign PORT``_a_ready_o IDX_P = NAME``_a_ready   IDX_L; \
  assign NAME``_a_valid   IDX_L = PORT``_a_valid_i IDX_P; \
  assign NAME``_a         IDX_L = PORT``_a_i       IDX_P; \
  assign NAME``_b_ready   IDX_L = PORT``_b_ready_i IDX_P; \
  assign PORT``_b_valid_o IDX_P = NAME``_b_valid   IDX_L; \
  assign PORT``_b_o       IDX_P = NAME``_b         IDX_L; \
  assign PORT``_c_ready_o IDX_P = NAME``_c_ready   IDX_L; \
  assign NAME``_c_valid   IDX_L = PORT``_c_valid_i IDX_P; \
  assign NAME``_c         IDX_L = PORT``_c_i       IDX_P; \
  assign NAME``_d_ready   IDX_L = PORT``_d_ready_i IDX_P; \
  assign PORT``_d_valid_o IDX_P = NAME``_d_valid   IDX_L; \
  assign PORT``_d_o       IDX_P = NAME``_d         IDX_L; \
  assign PORT``_e_ready_o IDX_P = NAME``_e_ready   IDX_L; \
  assign NAME``_e_valid   IDX_L = PORT``_e_valid_i IDX_P; \
  assign NAME``_e         IDX_L = PORT``_e_i       IDX_P

`define TL_BIND_DEVICE_PORT(PORT, NAME) \
  `TL_BIND_DEVICE_PORT_IDX(PORT, , NAME, )

`define TL_BIND_TAP_PORT_IDX(PORT, IDX_P, NAME, IDX_L) \
  assign NAME``_a_ready   IDX_L = PORT``_a_ready_i IDX_P; \
  assign NAME``_a_valid   IDX_L = PORT``_a_valid_i IDX_P; \
  assign NAME``_a         IDX_L = PORT``_a_i       IDX_P; \
  assign NAME``_b_ready   IDX_L = PORT``_b_ready_i IDX_P; \
  assign NAME``_b_valid   IDX_L = PORT``_b_valid_i IDX_P; \
  assign NAME``_b         IDX_L = PORT``_b_i       IDX_P; \
  assign NAME``_c_ready   IDX_L = PORT``_c_ready_i IDX_P; \
  assign NAME``_c_valid   IDX_L = PORT``_c_valid_i IDX_P; \
  assign NAME``_c         IDX_L = PORT``_c_i       IDX_P; \
  assign NAME``_d_ready   IDX_L = PORT``_d_ready_i IDX_P; \
  assign NAME``_d_valid   IDX_L = PORT``_d_valid_i IDX_P; \
  assign NAME``_d         IDX_L = PORT``_d_i       IDX_P; \
  assign NAME``_e_ready   IDX_L = PORT``_e_ready_i IDX_P; \
  assign NAME``_e_valid   IDX_L = PORT``_e_valid_i IDX_P; \
  assign NAME``_e         IDX_L = PORT``_e_i       IDX_P

`define TL_BIND_TAP_PORT(PORT, NAME) \
  `TL_BIND_TAP_PORT_IDX(PORT, , NAME, )

`endif // TL_UTIL_SV
