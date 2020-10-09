interface tl_channel #(
    // Property of the signals
    parameter  int unsigned SourceWidth   = 1,
    parameter  int unsigned SinkWidth     = 1,
    parameter  int unsigned AddrWidth     = 56,
    parameter  int unsigned DataWidth     = 64,
    parameter  int unsigned SizeWidth     = 3
);

  import tl_pkg::*;

  localparam int unsigned MaskWidth = DataWidth / 8;

  if ((1 << $clog2(DataWidth)) != DataWidth) $fatal(1, "DataWidth is not power of 2");

  logic                       a_ready;
  logic                       a_valid;
  tl_a_op_e                   a_opcode;
  logic                 [2:0] a_param;
  logic       [SizeWidth-1:0] a_size;
  logic     [SourceWidth-1:0] a_source;
  logic       [AddrWidth-1:0] a_address;
  logic       [MaskWidth-1:0] a_mask;
  logic                       a_corrupt;
  logic       [DataWidth-1:0] a_data;

  logic                       b_ready;
  logic                       b_valid;
  tl_b_op_e                   b_opcode;
  logic                 [2:0] b_param;
  logic       [SizeWidth-1:0] b_size;
  logic     [SourceWidth-1:0] b_source;
  logic       [AddrWidth-1:0] b_address;
  logic       [MaskWidth-1:0] b_mask;
  logic                       b_corrupt;
  logic       [DataWidth-1:0] b_data;

  logic                       c_ready;
  logic                       c_valid;
  tl_c_op_e                   c_opcode;
  logic                 [2:0] c_param;
  logic       [SizeWidth-1:0] c_size;
  logic     [SourceWidth-1:0] c_source;
  logic       [AddrWidth-1:0] c_address;
  logic                       c_corrupt;
  logic       [DataWidth-1:0] c_data;

  logic                       d_ready;
  logic                       d_valid;
  tl_d_op_e                   d_opcode;
  logic                 [2:0] d_param;
  logic       [SizeWidth-1:0] d_size;
  logic     [SourceWidth-1:0] d_source;
  logic       [SinkWidth-1:0] d_sink;
  logic                       d_denied;
  logic                       d_corrupt;
  logic       [DataWidth-1:0] d_data;

  logic                       e_ready;
  logic                       e_valid;
  logic       [SinkWidth-1:0] e_sink;

  modport host (
    input  a_ready,
    output a_valid,
    output a_opcode,
    output a_param,
    output a_size,
    output a_source,
    output a_address,
    output a_mask,
    output a_corrupt,
    output a_data,

    output b_ready,
    input  b_valid,
    input  b_opcode,
    input  b_param,
    input  b_size,
    input  b_source,
    input  b_address,
    input  b_mask,
    input  b_corrupt,
    input  b_data,

    input  c_ready,
    output c_valid,
    output c_opcode,
    output c_param,
    output c_size,
    output c_source,
    output c_address,
    output c_corrupt,
    output c_data,

    output d_ready,
    input  d_valid,
    input  d_opcode,
    input  d_param,
    input  d_size,
    input  d_source,
    input  d_sink,
    input  d_denied,
    input  d_corrupt,
    input  d_data,

    input  e_ready,
    output e_valid,
    output e_sink
  );

  modport device (
    output a_ready,
    input  a_valid,
    input  a_opcode,
    input  a_param,
    input  a_size,
    input  a_source,
    input  a_address,
    input  a_mask,
    input  a_corrupt,
    input  a_data,

    input  b_ready,
    output b_valid,
    output b_opcode,
    output b_param,
    output b_size,
    output b_source,
    output b_address,
    output b_mask,
    output b_corrupt,
    output b_data,

    output c_ready,
    input  c_valid,
    input  c_opcode,
    input  c_param,
    input  c_size,
    input  c_source,
    input  c_address,
    input  c_corrupt,
    input  c_data,

    input  d_ready,
    output d_valid,
    output d_opcode,
    output d_param,
    output d_size,
    output d_source,
    output d_sink,
    output d_denied,
    output d_corrupt,
    output d_data,

    output e_ready,
    input  e_valid,
    input  e_sink
  );

endinterface
