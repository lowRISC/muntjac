module muntjac_fpu_mul_add #(
  parameter InExpWidth = 9,
  parameter InSigWidth = 23,
  parameter OutExpWidth = 10,
  parameter OutSigWidth = 25
) (
  input  logic [1:0] op_i,
  input  muntjac_fpu_pkg::rounding_mode_e rounding_mode_i,

  input  logic a_sign_i,
  input  logic signed [InExpWidth-1:0] a_exponent_i,
  input  logic [InSigWidth-1:0] a_significand_i,
  input  logic a_is_zero_i,
  input  logic a_is_inf_i,
  input  logic a_is_nan_i,

  input  logic b_sign_i,
  input  logic signed [InExpWidth-1:0] b_exponent_i,
  input  logic [InSigWidth-1:0] b_significand_i,
  input  logic b_is_zero_i,
  input  logic b_is_inf_i,
  input  logic b_is_nan_i,

  input  logic c_sign_i,
  input  logic signed [InExpWidth-1:0] c_exponent_i,
  input  logic [InSigWidth-1:0] c_significand_i,
  input  logic c_is_zero_i,
  input  logic c_is_inf_i,
  input  logic c_is_nan_i,

  output logic resp_invalid_operation_o,
  output logic resp_sign_o,
  output logic signed [OutExpWidth-1:0] resp_exponent_o,
  output logic signed [OutSigWidth-1:0] resp_significand_o,
  output logic resp_is_zero_o,
  output logic resp_is_inf_o,
  output logic resp_is_nan_o
);

  logic mul_invalid_operation;
  logic prod_sign;
  logic signed [InExpWidth:0] prod_exponent;
  logic [InSigWidth*2:0] prod_sig;
  logic prod_is_zero;
  logic prod_is_inf;
  logic prod_is_nan;

  muntjac_fpu_mul #(
    .InExpWidth (InExpWidth),
    .InSigWidth (InSigWidth)
  ) mul (
    .a_sign_i (a_sign_i ^ op_i[1]),
    .a_exponent_i,
    .a_significand_i,
    .a_is_zero_i,
    .a_is_inf_i,
    .a_is_nan_i,
    .b_sign_i,
    .b_exponent_i,
    .b_significand_i,
    .b_is_zero_i,
    .b_is_inf_i,
    .b_is_nan_i,
    .resp_invalid_operation_o (mul_invalid_operation),
    .resp_sign_o (prod_sign),
    .resp_exponent_o (prod_exponent),
    .resp_significand_o (prod_sig),
    .resp_is_zero_o (prod_is_zero),
    .resp_is_inf_o (prod_is_inf),
    .resp_is_nan_o (prod_is_nan)
  );

  logic add_invalid_operation;

  muntjac_fpu_add #(
    .InExpWidth (InExpWidth + 1),
    .InSigWidth (InSigWidth * 2 + 1),
    .OutExpWidth (OutExpWidth),
    .OutSigWidth (OutSigWidth)
  ) add (
    .rounding_mode_i,
    .a_sign_i (prod_sign),
    .a_exponent_i (prod_exponent),
    // If product is NaN, then make it seem like a quiet NaN for the adder, to avoid setting
    // extra invalid operatio bit.
    // TODO: Rethink about how we handle NaN payloads.
    .a_significand_i ({prod_is_nan ? 1'b1 : prod_sig[InSigWidth*2], prod_sig[InSigWidth*2-1:0]}),
    .a_is_zero_i (prod_is_zero),
    .a_is_inf_i (prod_is_inf),
    .a_is_nan_i (prod_is_nan),
    .b_sign_i (c_sign_i ^ op_i[0]),
    .b_exponent_i ({c_exponent_i[InExpWidth-1], c_exponent_i}),
    .b_significand_i ({c_significand_i, {(InSigWidth + 1){1'b0}}}),
    .b_is_zero_i (c_is_zero_i),
    .b_is_inf_i (c_is_inf_i),
    .b_is_nan_i (c_is_nan_i),
    .resp_invalid_operation_o (add_invalid_operation),
    .resp_sign_o,
    .resp_exponent_o,
    .resp_significand_o,
    .resp_is_zero_o,
    .resp_is_inf_o,
    .resp_is_nan_o
  );

  assign resp_invalid_operation_o = mul_invalid_operation || add_invalid_operation;

endmodule
