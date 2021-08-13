// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

module tl_wrapper #(
    parameter int unsigned AddrWidth = 56,
    parameter int unsigned DataWidth = 64,
    parameter int unsigned SourceWidth = 4,
    parameter int unsigned SinkWidth = 2
) (
  // Clock and reset
  input  logic                               clk_i,
  input  logic                               rst_ni,

  // Need to define all signals instead of using structs. Verilator packs
  // structs into arrays, which makes unpacking difficult on the C++ side.

  // Hosts.
  output logic                               host_a_ready_o   [2:0],
  input  logic                               host_a_valid_i   [2:0],
  input  tl_pkg::tl_a_op_e                   host_a_opcode_i  [2:0],
  input  logic                         [2:0] host_a_param_i   [2:0],
  input  logic          [`TL_SIZE_WIDTH-1:0] host_a_size_i    [2:0],
  input  logic             [SourceWidth-1:0] host_a_source_i  [2:0],
  input  logic               [AddrWidth-1:0] host_a_address_i [2:0],
  input  logic             [DataWidth/8-1:0] host_a_mask_i    [2:0],
  input  logic                               host_a_corrupt_i [2:0],
  input  logic               [DataWidth-1:0] host_a_data_i    [2:0],

  input  logic                               host_b_ready_i   [2:0],
  output logic                               host_b_valid_o   [2:0],
  output tl_pkg::tl_b_op_e                   host_b_opcode_o  [2:0],
  output logic                         [2:0] host_b_param_o   [2:0],
  output logic          [`TL_SIZE_WIDTH-1:0] host_b_size_o    [2:0],
  output logic             [SourceWidth-1:0] host_b_source_o  [2:0],
  output logic               [AddrWidth-1:0] host_b_address_o [2:0],
  output logic             [DataWidth/8-1:0] host_b_mask_o    [2:0],
  output logic                               host_b_corrupt_o [2:0],
  output logic               [DataWidth-1:0] host_b_data_o    [2:0], 

  output logic                               host_c_ready_o   [2:0],
  input  logic                               host_c_valid_i   [2:0],
  input  tl_pkg::tl_c_op_e                   host_c_opcode_i  [2:0],
  input  logic                         [2:0] host_c_param_i   [2:0],
  input  logic          [`TL_SIZE_WIDTH-1:0] host_c_size_i    [2:0],
  input  logic             [SourceWidth-1:0] host_c_source_i  [2:0],
  input  logic               [AddrWidth-1:0] host_c_address_i [2:0],
  input  logic                               host_c_corrupt_i [2:0],
  input  logic               [DataWidth-1:0] host_c_data_i    [2:0],

  input  logic                               host_d_ready_i   [2:0],
  output logic                               host_d_valid_o   [2:0],
  output tl_pkg::tl_d_op_e                   host_d_opcode_o  [2:0],
  output logic                         [2:0] host_d_param_o   [2:0],
  output logic          [`TL_SIZE_WIDTH-1:0] host_d_size_o    [2:0],
  output logic             [SourceWidth-1:0] host_d_source_o  [2:0],
  output logic               [SinkWidth-1:0] host_d_sink_o    [2:0],
  output logic                               host_d_denied_o  [2:0],
  output logic                               host_d_corrupt_o [2:0],
  output logic               [DataWidth-1:0] host_d_data_o    [2:0],

  output logic                               host_e_ready_o   [2:0],
  input  logic                               host_e_valid_i   [2:0],
  input  logic               [SinkWidth-1:0] host_e_sink_i    [2:0],

  // Devices.
  input  logic                               dev_a_ready_i    [2:0],
  output logic                               dev_a_valid_o    [2:0],
  output tl_pkg::tl_a_op_e                   dev_a_opcode_o   [2:0],
  output logic                         [2:0] dev_a_param_o    [2:0],
  output logic          [`TL_SIZE_WIDTH-1:0] dev_a_size_o     [2:0],
  output logic             [SourceWidth-1:0] dev_a_source_o   [2:0],
  output logic               [AddrWidth-1:0] dev_a_address_o  [2:0],
  output logic             [DataWidth/8-1:0] dev_a_mask_o     [2:0],
  output logic                               dev_a_corrupt_o  [2:0],
  output logic               [DataWidth-1:0] dev_a_data_o     [2:0],

  output logic                               dev_b_ready_o    [2:0],
  input  logic                               dev_b_valid_i    [2:0],
  input  tl_pkg::tl_b_op_e                   dev_b_opcode_i   [2:0],
  input  logic                         [2:0] dev_b_param_i    [2:0],
  input  logic          [`TL_SIZE_WIDTH-1:0] dev_b_size_i     [2:0],
  input  logic             [SourceWidth-1:0] dev_b_source_i   [2:0],
  input  logic               [AddrWidth-1:0] dev_b_address_i  [2:0],
  input  logic             [DataWidth/8-1:0] dev_b_mask_i     [2:0],
  input  logic                               dev_b_corrupt_i  [2:0],
  input  logic               [DataWidth-1:0] dev_b_data_i     [2:0], 

  input  logic                               dev_c_ready_i    [2:0],
  output logic                               dev_c_valid_o    [2:0],
  output tl_pkg::tl_c_op_e                   dev_c_opcode_o   [2:0],
  output logic                         [2:0] dev_c_param_o    [2:0],
  output logic          [`TL_SIZE_WIDTH-1:0] dev_c_size_o     [2:0],
  output logic             [SourceWidth-1:0] dev_c_source_o   [2:0],
  output logic               [AddrWidth-1:0] dev_c_address_o  [2:0],
  output logic                               dev_c_corrupt_o  [2:0],
  output logic               [DataWidth-1:0] dev_c_data_o     [2:0],

  output logic                               dev_d_ready_o    [2:0],
  input  logic                               dev_d_valid_i    [2:0],
  input  tl_pkg::tl_d_op_e                   dev_d_opcode_i   [2:0],
  input  logic                         [2:0] dev_d_param_i    [2:0],
  input  logic          [`TL_SIZE_WIDTH-1:0] dev_d_size_i     [2:0],
  input  logic             [SourceWidth-1:0] dev_d_source_i   [2:0],
  input  logic               [SinkWidth-1:0] dev_d_sink_i     [2:0],
  input  logic                               dev_d_denied_i   [2:0],
  input  logic                               dev_d_corrupt_i  [2:0],
  input  logic               [DataWidth-1:0] dev_d_data_i     [2:0],

  input  logic                               dev_e_ready_i    [2:0],
  output logic                               dev_e_valid_o    [2:0],
  output logic               [SinkWidth-1:0] dev_e_sink_o     [2:0]
);

// TileLink structure:
//
//  host0 (TL-C)              host1 (TL-UH)             host2 (TL-UL)
//       |_________________________|_________________________|
//                                 | (host_tl)
//                             socket_m1
//                                 | (tl_channel)
//                             socket_1n
//        _________________________|_________________________
//       |                         | (dev_tl)                |
//   dev0 (TL-C)               dev1 (TL-UH)             tlul_bridge
//                                                           | (tl_ul)
//                                                       dev2 (TL-UL)
//
// TODO:
//  * Put some more adapters in to change more parameters
//  * See if theres a way to enforce TL-UH device and/or TL-UH/TL-UL hosts.

  `TL_DECLARE_ARR(DataWidth, AddrWidth, SourceWidth, SinkWidth, host_tl, [2:0]);
  `TL_DECLARE(DataWidth, AddrWidth, SourceWidth, SinkWidth, tl_channel);

  tl_socket_m1 #(
    .SourceWidth (SourceWidth),
    .SinkWidth   (SinkWidth),
    .AddrWidth   (AddrWidth),
    .DataWidth   (DataWidth),
    .NumLinks    (3),

    // TODO: Not 100% sure of the difference between these two
    .NumCachedHosts (1),
    .NumCachedLinks (0),

    .NumSourceRange (2),  // Excluding default source 0
    .SourceBase ({{{SourceWidth-2{1'b0}}, 2'd1}, {{SourceWidth-2{1'b0}}, 2'd2}}),
    .SourceMask ({{SourceWidth{1'b0}}, {SourceWidth{1'b0}}}),
    .SourceLink ({2'd1, 2'd2})
  ) socket_m1 (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_DEVICE_PORT(host, host_tl),
    `TL_CONNECT_HOST_PORT(device, tl_channel)
  );

  `TL_DECLARE_ARR(DataWidth, AddrWidth, SourceWidth, SinkWidth, dev_tl, [2:0]);

  tl_socket_1n #(
    .SourceWidth (SourceWidth),
    .SinkWidth   (SinkWidth),
    .NumLinks    (3),
    .NumAddressRange (2),  // Excluding default sink 0
    .AddressBase ({56'h10000000, 56'h20000000}),
    .AddressMask ({56'h0fffffff, 56'h0fffffff}),
    .AddressLink ({2'd        1, 2'd        2}),
    .NumSinkRange (2),
    .SinkBase ({{{SinkWidth-2{1'b0}}, 2'd1}, {{SinkWidth-2{1'b0}}, 2'd2}}),
    .SinkMask ({{SinkWidth{1'b0}}, {SinkWidth{1'b0}}}),
    .SinkLink ({2'd1, 2'd2})
  ) socket_1n (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_DEVICE_PORT(host, tl_channel),
    `TL_CONNECT_HOST_PORT(device, dev_tl)
  );

  `TL_DECLARE(DataWidth, AddrWidth, SourceWidth, SinkWidth, dev_tlul);

  tl_adapter_tlul #(
    .HostSourceWidth (SourceWidth),
    .DeviceSourceWidth (SourceWidth),
    .SinkWidth (SinkWidth)
  ) tlul_bridge (
    .clk_i,
    .rst_ni,
    `TL_CONNECT_DEVICE_PORT_IDX(host, dev_tl, [2]),
    `TL_CONNECT_HOST_PORT(device, dev_tlul)
  );

  // Can't use normal macros here because the names are slightly different with
  // unpacked structs.

  // From hosts.
  for (genvar i=0; i<3; i++) begin
    assign host_a_ready_o[i] = host_tl_a_ready[i];
    assign host_tl_a_valid[i] = host_a_valid_i[i];
    assign host_tl_a[i].opcode = host_a_opcode_i[i];
    assign host_tl_a[i].param = host_a_param_i[i];
    assign host_tl_a[i].size = host_a_size_i[i];
    assign host_tl_a[i].source = host_a_source_i[i];
    assign host_tl_a[i].address = host_a_address_i[i];
    assign host_tl_a[i].mask = host_a_mask_i[i];
    assign host_tl_a[i].corrupt = host_a_corrupt_i[i];
    assign host_tl_a[i].data = host_a_data_i[i];

    assign host_tl_b_ready[i] = host_b_ready_i[i];
    assign host_b_valid_o[i] = host_tl_b_valid[i];
    assign host_b_opcode_o[i] = host_tl_b[i].opcode;
    assign host_b_param_o[i] = host_tl_b[i].param;
    assign host_b_size_o[i] = host_tl_b[i].size;
    assign host_b_source_o[i] = host_tl_b[i].source;
    assign host_b_address_o[i] = host_tl_b[i].address;
    assign host_b_mask_o[i] = host_tl_b[i].mask;
    assign host_b_corrupt_o[i] = host_tl_b[i].corrupt;
    assign host_b_data_o[i] = host_tl_b[i].data;

    assign host_c_ready_o[i] = host_tl_c_ready[i];
    assign host_tl_c_valid[i] = host_c_valid_i[i];
    assign host_tl_c[i].opcode = host_c_opcode_i[i];
    assign host_tl_c[i].param = host_c_param_i[i];
    assign host_tl_c[i].size = host_c_size_i[i];
    assign host_tl_c[i].source = host_c_source_i[i];
    assign host_tl_c[i].address = host_c_address_i[i];
    assign host_tl_c[i].corrupt = host_c_corrupt_i[i];
    assign host_tl_c[i].data = host_c_data_i[i];

    assign host_tl_d_ready[i] = host_d_ready_i[i];
    assign host_d_valid_o[i] = host_tl_d_valid[i];
    assign host_d_opcode_o[i] = host_tl_d[i].opcode;
    assign host_d_param_o[i] = host_tl_d[i].param;
    assign host_d_size_o[i] = host_tl_d[i].size;
    assign host_d_source_o[i] = host_tl_d[i].source;
    assign host_d_sink_o[i] = host_tl_d[i].sink;
    assign host_d_denied_o[i] = host_tl_d[i].denied;
    assign host_d_corrupt_o[i] = host_tl_d[i].corrupt;
    assign host_d_data_o[i] = host_tl_d[i].data;

    assign host_e_ready_o[i] = host_tl_e_ready[i];
    assign host_tl_e_valid[i] = host_e_valid_i[i];
    assign host_tl_e[i].sink = host_e_sink_i[i];
  end

  // To devices.
  for (genvar i=0; i<2; i++) begin
    assign dev_tl_a_ready[i] = dev_a_ready_i[i];
    assign dev_a_valid_o[i] = dev_tl_a_valid[i];
    assign dev_a_opcode_o[i] = dev_tl_a[i].opcode;
    assign dev_a_param_o[i] = dev_tl_a[i].param;
    assign dev_a_size_o[i] = dev_tl_a[i].size;
    assign dev_a_source_o[i] = dev_tl_a[i].source;
    assign dev_a_address_o[i] = dev_tl_a[i].address;
    assign dev_a_mask_o[i] = dev_tl_a[i].mask;
    assign dev_a_corrupt_o[i] = dev_tl_a[i].corrupt;
    assign dev_a_data_o[i] = dev_tl_a[i].data;
    
    assign dev_b_ready_o[i] = dev_tl_b_ready[i];
    assign dev_tl_b_valid[i] = dev_b_valid_i[i];
    assign dev_tl_b[i].opcode = dev_b_opcode_i[i];
    assign dev_tl_b[i].param = dev_b_param_i[i];
    assign dev_tl_b[i].size = dev_b_size_i[i];
    assign dev_tl_b[i].source = dev_b_source_i[i];
    assign dev_tl_b[i].address = dev_b_address_i[i];
    assign dev_tl_b[i].mask = dev_b_mask_i[i];
    assign dev_tl_b[i].corrupt = dev_b_corrupt_i[i];
    assign dev_tl_b[i].data = dev_b_data_i[i];

    assign dev_tl_c_ready[i] = dev_c_ready_i[i];
    assign dev_c_valid_o[i] = dev_tl_c_valid[i];
    assign dev_c_opcode_o[i] = dev_tl_c[i].opcode;
    assign dev_c_param_o[i] = dev_tl_c[i].param;
    assign dev_c_size_o[i] = dev_tl_c[i].size;
    assign dev_c_source_o[i] = dev_tl_c[i].source;
    assign dev_c_address_o[i] = dev_tl_c[i].address;
    assign dev_c_corrupt_o[i] = dev_tl_c[i].corrupt;
    assign dev_c_data_o[i] = dev_tl_c[i].data;

    assign dev_d_ready_o[i] = dev_tl_d_ready[i];
    assign dev_tl_d_valid[i] = dev_d_valid_i[i];
    assign dev_tl_d[i].opcode = dev_d_opcode_i[i];
    assign dev_tl_d[i].param = dev_d_param_i[i];
    assign dev_tl_d[i].size = dev_d_size_i[i];
    assign dev_tl_d[i].source = dev_d_source_i[i];
    assign dev_tl_d[i].sink = dev_d_sink_i[i];
    assign dev_tl_d[i].denied = dev_d_denied_i[i];
    assign dev_tl_d[i].corrupt = dev_d_corrupt_i[i];
    assign dev_tl_d[i].data = dev_d_data_i[i];

    assign dev_tl_e_ready[i] = dev_e_ready_i[i];
    assign dev_e_valid_o[i] = dev_tl_e_valid[i];
    assign dev_e_sink_o[i] = dev_tl_e[i].sink;
  end

  assign dev_tlul_a_ready = dev_a_ready_i[2];
  assign dev_a_valid_o[2] = dev_tlul_a_valid;
  assign dev_a_opcode_o[2] = dev_tlul_a.opcode;
  assign dev_a_param_o[2] = dev_tlul_a.param;
  assign dev_a_size_o[2] = dev_tlul_a.size;
  assign dev_a_source_o[2] = dev_tlul_a.source;
  assign dev_a_address_o[2] = dev_tlul_a.address;
  assign dev_a_mask_o[2] = dev_tlul_a.mask;
  assign dev_a_corrupt_o[2] = dev_tlul_a.corrupt;
  assign dev_a_data_o[2] = dev_tlul_a.data;

  assign dev_b_ready_o[2] = dev_tlul_b_ready;
  assign dev_tlul_b_valid = dev_b_valid_i[2];
  assign dev_tlul_b.opcode = dev_b_opcode_i[2];
  assign dev_tlul_b.param = dev_b_param_i[2];
  assign dev_tlul_b.size = dev_b_size_i[2];
  assign dev_tlul_b.source = dev_b_source_i[2];
  assign dev_tlul_b.address = dev_b_address_i[2];
  assign dev_tlul_b.mask = dev_b_mask_i[2];
  assign dev_tlul_b.corrupt = dev_b_corrupt_i[2];
  assign dev_tlul_b.data = dev_b_data_i[2];

  assign dev_tlul_c_ready = dev_c_ready_i[2];
  assign dev_c_valid_o[2] = dev_tlul_c_valid;
  assign dev_c_opcode_o[2] = dev_tlul_c.opcode;
  assign dev_c_param_o[2] = dev_tlul_c.param;
  assign dev_c_size_o[2] = dev_tlul_c.size;
  assign dev_c_source_o[2] = dev_tlul_c.source;
  assign dev_c_address_o[2] = dev_tlul_c.address;
  assign dev_c_corrupt_o[2] = dev_tlul_c.corrupt;
  assign dev_c_data_o[2] = dev_tlul_c.data;

  assign dev_d_ready_o[2] = dev_tlul_d_ready;
  assign dev_tlul_d_valid = dev_d_valid_i[2];
  assign dev_tlul_d.opcode = dev_d_opcode_i[2];
  assign dev_tlul_d.param = dev_d_param_i[2];
  assign dev_tlul_d.size = dev_d_size_i[2];
  assign dev_tlul_d.source = dev_d_source_i[2];
  assign dev_tlul_d.sink = dev_d_sink_i[2];
  assign dev_tlul_d.denied = dev_d_denied_i[2];
  assign dev_tlul_d.corrupt = dev_d_corrupt_i[2];
  assign dev_tlul_d.data = dev_d_data_i[2];

  assign dev_tlul_e_ready = dev_e_ready_i[2];
  assign dev_e_valid_o[2] = dev_tlul_e_valid;
  assign dev_e_sink_o[2] = dev_tlul_e.sink;

endmodule
