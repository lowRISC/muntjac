// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

`ifndef TL_VERILATOR_SVH
`define TL_VERILATOR_SVH

// Macros for defining arrays of ports for individual TileLink channels.
// All connections to Verilator are arrays of ports.
// These are separate from those in tl_util because we want to avoid packing
// data into arrays, which is awkward to handle consistently from both sides
// of the Verilog/C++ interface.

`define TL_A_VERILATOR(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH, NAME, ARR, H2D, D2H, H2D_SUFFIX, D2H_SUFFIX) \
  D2H logic                                NAME``_a_ready``D2H_SUFFIX   ARR, \
  H2D logic                                NAME``_a_valid``H2D_SUFFIX   ARR, \
  H2D tl_pkg::tl_a_op_e                    NAME``_a_opcode``H2D_SUFFIX  ARR, \
  H2D logic                          [2:0] NAME``_a_param``H2D_SUFFIX   ARR, \
  H2D logic           [`TL_SIZE_WIDTH-1:0] NAME``_a_size``H2D_SUFFIX    ARR, \
  H2D logic             [SOURCE_WIDTH-1:0] NAME``_a_source``H2D_SUFFIX  ARR, \
  H2D logic               [ADDR_WIDTH-1:0] NAME``_a_address``H2D_SUFFIX ARR, \
  H2D logic             [DATA_WIDTH/8-1:0] NAME``_a_mask``H2D_SUFFIX    ARR, \
  H2D logic                                NAME``_a_corrupt``H2D_SUFFIX ARR, \
  H2D logic               [DATA_WIDTH-1:0] NAME``_a_data``H2D_SUFFIX    ARR

`define TL_B_VERILATOR(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH, NAME, ARR, H2D, D2H, H2D_SUFFIX, D2H_SUFFIX) \
  H2D logic                                NAME``_b_ready``H2D_SUFFIX   ARR, \
  D2H logic                                NAME``_b_valid``D2H_SUFFIX   ARR, \
  D2H tl_pkg::tl_b_op_e                    NAME``_b_opcode``D2H_SUFFIX  ARR, \
  D2H logic                          [2:0] NAME``_b_param``D2H_SUFFIX   ARR, \
  D2H logic           [`TL_SIZE_WIDTH-1:0] NAME``_b_size``D2H_SUFFIX    ARR, \
  D2H logic             [SOURCE_WIDTH-1:0] NAME``_b_source``D2H_SUFFIX  ARR, \
  D2H logic               [ADDR_WIDTH-1:0] NAME``_b_address``D2H_SUFFIX ARR

`define TL_C_VERILATOR(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH, NAME, ARR, H2D, D2H, H2D_SUFFIX, D2H_SUFFIX) \
  D2H logic                                NAME``_c_ready``D2H_SUFFIX   ARR, \
  H2D logic                                NAME``_c_valid``H2D_SUFFIX   ARR, \
  H2D tl_pkg::tl_c_op_e                    NAME``_c_opcode``H2D_SUFFIX  ARR, \
  H2D logic                          [2:0] NAME``_c_param``H2D_SUFFIX   ARR, \
  H2D logic           [`TL_SIZE_WIDTH-1:0] NAME``_c_size``H2D_SUFFIX    ARR, \
  H2D logic             [SOURCE_WIDTH-1:0] NAME``_c_source``H2D_SUFFIX  ARR, \
  H2D logic               [ADDR_WIDTH-1:0] NAME``_c_address``H2D_SUFFIX ARR, \
  H2D logic                                NAME``_c_corrupt``H2D_SUFFIX ARR, \
  H2D logic               [DATA_WIDTH-1:0] NAME``_c_data``H2D_SUFFIX    ARR

`define TL_D_VERILATOR(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH, NAME, ARR, H2D, D2H, H2D_SUFFIX, D2H_SUFFIX) \
  H2D logic                                NAME``_d_ready``H2D_SUFFIX   ARR, \
  D2H logic                                NAME``_d_valid``D2H_SUFFIX   ARR, \
  D2H tl_pkg::tl_d_op_e                    NAME``_d_opcode``D2H_SUFFIX  ARR, \
  D2H logic                          [2:0] NAME``_d_param``D2H_SUFFIX   ARR, \
  D2H logic           [`TL_SIZE_WIDTH-1:0] NAME``_d_size``D2H_SUFFIX    ARR, \
  D2H logic             [SOURCE_WIDTH-1:0] NAME``_d_source``D2H_SUFFIX  ARR, \
  D2H logic               [SINK_WIDTH-1:0] NAME``_d_sink``D2H_SUFFIX    ARR, \
  D2H logic                                NAME``_d_denied``D2H_SUFFIX  ARR, \
  D2H logic                                NAME``_d_corrupt``D2H_SUFFIX ARR, \
  D2H logic               [DATA_WIDTH-1:0] NAME``_d_data``D2H_SUFFIX    ARR

`define TL_E_VERILATOR(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH, NAME, ARR, H2D, D2H, H2D_SUFFIX, D2H_SUFFIX) \
  D2H logic                                NAME``_e_ready``D2H_SUFFIX   ARR, \
  H2D logic                                NAME``_e_valid``H2D_SUFFIX   ARR, \
  H2D logic               [SINK_WIDTH-1:0] NAME``_e_sink``H2D_SUFFIX    ARR

// Macros for defining a TileLink array of ports.

`define TL_VERILATOR_PORT_IMPL(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH, NAME, ARR, H2D, D2H, H2D_SUFFIX, D2H_SUFFIX) \
  `TL_A_VERILATOR(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH, NAME, ARR, H2D, D2H, H2D_SUFFIX, D2H_SUFFIX), \
  `TL_B_VERILATOR(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH, NAME, ARR, H2D, D2H, H2D_SUFFIX, D2H_SUFFIX), \
  `TL_C_VERILATOR(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH, NAME, ARR, H2D, D2H, H2D_SUFFIX, D2H_SUFFIX), \
  `TL_D_VERILATOR(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH, NAME, ARR, H2D, D2H, H2D_SUFFIX, D2H_SUFFIX), \
  `TL_E_VERILATOR(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH, NAME, ARR, H2D, D2H, H2D_SUFFIX, D2H_SUFFIX)

`define TL_VERILATOR_HOST_PORT_ARR(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH, NAME, LINKS) \
  `TL_VERILATOR_PORT_IMPL(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH, NAME, [LINKS-1:0], input, output, _i, _o)

`define TL_VERILATOR_HOST_PORT(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH, NAME) \
  `TL_VERILATOR_HOST_PORT_ARR(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH, NAME, 1)

`define TL_VERILATOR_DEVICE_PORT_ARR(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH, NAME, LINKS) \
  `TL_VERILATOR_PORT_IMPL(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH, NAME, [LINKS-1:0], output, input, _o, _i)

`define TL_VERILATOR_DEVICE_PORT(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH, NAME) \
  `TL_VERILATOR_DEVICE_PORT_ARR(DATA_WIDTH, ADDR_WIDTH, SOURCE_WIDTH, SINK_WIDTH, NAME, 1)

// Macros to bind Verilator ports to standard TileLink signals.

`define TL_VERILATOR_BIND_HOST_PORT_IDX(PORT, IDX_P, LINK, IDX_L) \
  assign PORT``_a_ready_o    IDX_P = LINK``_a_ready      IDX_L;   \
  assign LINK``_a_valid      IDX_L = PORT``_a_valid_i    IDX_P;   \
  assign LINK``_a``IDX_L``.opcode  = PORT``_a_opcode_i   IDX_P;   \
  assign LINK``_a``IDX_L``.param   = PORT``_a_param_i    IDX_P;   \
  assign LINK``_a``IDX_L``.size    = PORT``_a_size_i     IDX_P;   \
  assign LINK``_a``IDX_L``.source  = PORT``_a_source_i   IDX_P;   \
  assign LINK``_a``IDX_L``.address = PORT``_a_address_i  IDX_P;   \
  assign LINK``_a``IDX_L``.mask    = PORT``_a_mask_i     IDX_P;   \
  assign LINK``_a``IDX_L``.corrupt = PORT``_a_corrupt_i  IDX_P;   \
  assign LINK``_a``IDX_L``.data    = PORT``_a_data_i     IDX_P;   \
                                                                  \
  assign LINK``_b_ready      IDX_L = PORT``_b_ready_i    IDX_P;   \
  assign PORT``_b_valid_o    IDX_P = LINK``_b_valid      IDX_L;   \
  assign PORT``_b_opcode_o   IDX_P = LINK``_b``IDX_L``.opcode ;   \
  assign PORT``_b_param_o    IDX_P = LINK``_b``IDX_L``.param  ;   \
  assign PORT``_b_size_o     IDX_P = LINK``_b``IDX_L``.size   ;   \
  assign PORT``_b_source_o   IDX_P = LINK``_b``IDX_L``.source ;   \
  assign PORT``_b_address_o  IDX_P = LINK``_b``IDX_L``.address;   \
                                                                  \
  assign PORT``_c_ready_o    IDX_P = LINK``_c_ready      IDX_L;   \
  assign LINK``_c_valid      IDX_L = PORT``_c_valid_i    IDX_P;   \
  assign LINK``_c``IDX_L``.opcode  = PORT``_c_opcode_i   IDX_P;   \
  assign LINK``_c``IDX_L``.param   = PORT``_c_param_i    IDX_P;   \
  assign LINK``_c``IDX_L``.size    = PORT``_c_size_i     IDX_P;   \
  assign LINK``_c``IDX_L``.source  = PORT``_c_source_i   IDX_P;   \
  assign LINK``_c``IDX_L``.address = PORT``_c_address_i  IDX_P;   \
  assign LINK``_c``IDX_L``.corrupt = PORT``_c_corrupt_i  IDX_P;   \
  assign LINK``_c``IDX_L``.data    = PORT``_c_data_i     IDX_P;   \
                                                                  \
  assign LINK``_d_ready      IDX_L = PORT``_d_ready_i    IDX_P;   \
  assign PORT``_d_valid_o    IDX_P = LINK``_d_valid      IDX_L;   \
  assign PORT``_d_opcode_o   IDX_P = LINK``_d``IDX_L``.opcode ;   \
  assign PORT``_d_param_o    IDX_P = LINK``_d``IDX_L``.param  ;   \
  assign PORT``_d_size_o     IDX_P = LINK``_d``IDX_L``.size   ;   \
  assign PORT``_d_source_o   IDX_P = LINK``_d``IDX_L``.source ;   \
  assign PORT``_d_sink_o     IDX_P = LINK``_d``IDX_L``.sink   ;   \
  assign PORT``_d_denied_o   IDX_P = LINK``_d``IDX_L``.denied ;   \
  assign PORT``_d_corrupt_o  IDX_P = LINK``_d``IDX_L``.corrupt;   \
  assign PORT``_d_data_o     IDX_P = LINK``_d``IDX_L``.data   ;   \
                                                                  \
  assign PORT``_e_ready_o    IDX_P = LINK``_e_ready      IDX_L;   \
  assign LINK``_e_valid      IDX_L = PORT``_e_valid_i    IDX_P;   \
  assign LINK``_e``IDX_L``.sink    = PORT``_e_sink_i     IDX_P

`define TL_VERILATOR_BIND_HOST_PORT(PORT, LINK) \
  `TL_VERILATOR_BIND_HOST_PORT_IDX(PORT, [0], LINK, ) 

`define TL_VERILATOR_BIND_DEVICE_PORT_IDX(PORT, IDX_P, LINK, IDX_L) \
  assign LINK``_a_ready      IDX_L = PORT``_a_ready_i    IDX_P;     \
  assign PORT``_a_valid_o    IDX_P = LINK``_a_valid      IDX_L;     \
  assign PORT``_a_opcode_o   IDX_P = LINK``_a``IDX_L``.opcode ;     \
  assign PORT``_a_param_o    IDX_P = LINK``_a``IDX_L``.param  ;     \
  assign PORT``_a_size_o     IDX_P = LINK``_a``IDX_L``.size   ;     \
  assign PORT``_a_source_o   IDX_P = LINK``_a``IDX_L``.source ;     \
  assign PORT``_a_address_o  IDX_P = LINK``_a``IDX_L``.address;     \
  assign PORT``_a_mask_o     IDX_P = LINK``_a``IDX_L``.mask   ;     \
  assign PORT``_a_corrupt_o  IDX_P = LINK``_a``IDX_L``.corrupt;     \
  assign PORT``_a_data_o     IDX_P = LINK``_a``IDX_L``.data   ;     \
                                                                    \
  assign PORT``_b_ready_o    IDX_P = LINK``_b_ready      IDX_L;     \
  assign LINK``_b_valid      IDX_L = PORT``_b_valid_i    IDX_P;     \
  assign LINK``_b``IDX_L``.opcode  = PORT``_b_opcode_i   IDX_P;     \
  assign LINK``_b``IDX_L``.param   = PORT``_b_param_i    IDX_P;     \
  assign LINK``_b``IDX_L``.size    = PORT``_b_size_i     IDX_P;     \
  assign LINK``_b``IDX_L``.source  = PORT``_b_source_i   IDX_P;     \
  assign LINK``_b``IDX_L``.address = PORT``_b_address_i  IDX_P;     \
                                                                    \
  assign LINK``_c_ready      IDX_L = PORT``_c_ready_i    IDX_P;     \
  assign PORT``_c_valid_o    IDX_P = LINK``_c_valid      IDX_L;     \
  assign PORT``_c_opcode_o   IDX_P = LINK``_c``IDX_L``.opcode ;     \
  assign PORT``_c_param_o    IDX_P = LINK``_c``IDX_L``.param  ;     \
  assign PORT``_c_size_o     IDX_P = LINK``_c``IDX_L``.size   ;     \
  assign PORT``_c_source_o   IDX_P = LINK``_c``IDX_L``.source ;     \
  assign PORT``_c_address_o  IDX_P = LINK``_c``IDX_L``.address;     \
  assign PORT``_c_corrupt_o  IDX_P = LINK``_c``IDX_L``.corrupt;     \
  assign PORT``_c_data_o     IDX_P = LINK``_c``IDX_L``.data   ;     \
                                                                    \
  assign PORT``_d_ready_o    IDX_P = LINK``_d_ready      IDX_L;     \
  assign LINK``_d_valid      IDX_L = PORT``_d_valid_i    IDX_P;     \
  assign LINK``_d``IDX_L``.opcode  = PORT``_d_opcode_i   IDX_P;     \
  assign LINK``_d``IDX_L``.param   = PORT``_d_param_i    IDX_P;     \
  assign LINK``_d``IDX_L``.size    = PORT``_d_size_i     IDX_P;     \
  assign LINK``_d``IDX_L``.source  = PORT``_d_source_i   IDX_P;     \
  assign LINK``_d``IDX_L``.sink    = PORT``_d_sink_i     IDX_P;     \
  assign LINK``_d``IDX_L``.denied  = PORT``_d_denied_i   IDX_P;     \
  assign LINK``_d``IDX_L``.corrupt = PORT``_d_corrupt_i  IDX_P;     \
  assign LINK``_d``IDX_L``.data    = PORT``_d_data_i     IDX_P;     \
                                                                    \
  assign LINK``_e_ready      IDX_L = PORT``_e_ready_i    IDX_P;     \
  assign PORT``_e_valid_o    IDX_P = LINK``_e_valid      IDX_L;     \
  assign PORT``_e_sink_o     IDX_P = LINK``_e``IDX_L``.sink

`define TL_VERILATOR_BIND_DEVICE_PORT(PORT, LINK) \
  `TL_VERILATOR_BIND_DEVICE_PORT_IDX(PORT, [0], LINK, ) 

`endif // TL_VERILATOR_SVH
