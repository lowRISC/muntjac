module muntjac_fpu_mul #(
  parameter InExpWidth = 9,
  parameter InSigWidth = 23,
  localparam OutExpWidth = InExpWidth + 1,
  localparam OutSigWidth = InSigWidth * 2 + 1
) (
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

  // Indicate the operation is invalid. If this bit is set, then all other bits about result
  // should be ignored and the result shall be considered as the canonical NaN.
  output logic resp_invalid_operation_o,
  output logic resp_sign_o,
  output logic signed [OutExpWidth-1:0] resp_exponent_o,
  output logic signed [OutSigWidth-1:0] resp_significand_o,
  output logic resp_is_zero_o,
  output logic resp_is_inf_o,
  output logic resp_is_nan_o
);

  wire a_is_signaling_nan = a_is_nan_i && !a_significand_i[InSigWidth-1];
  wire b_is_signaling_nan = b_is_nan_i && !b_significand_i[InSigWidth-1];

  // Check for invalid operation conditions and set corresponding flags if true.
  assign resp_invalid_operation_o =
    a_is_signaling_nan || b_is_signaling_nan ||
    (a_is_inf_i && b_is_zero_i) || (a_is_zero_i && b_is_inf_i);

  assign resp_is_nan_o = a_is_nan_i || b_is_nan_i;
  assign resp_is_inf_o = !resp_is_nan_o && (a_is_inf_i || b_is_inf_i);
  assign resp_is_zero_o = !resp_is_nan_o && (a_is_zero_i || b_is_zero_i);
  assign resp_sign_o = a_sign_i ^ b_sign_i;

  wire signed [InExpWidth:0] product_exp = a_exponent_i + b_exponent_i;
  // InSigWidth bits after fixed point
  wire [InSigWidth:0] a_significand_ext = {1'b1, a_significand_i};
  wire [InSigWidth:0] b_significand_ext = {1'b1, b_significand_i};
  // InSigWidth*2 bits after fixed point.
  // This value is bounded by [1, 4)
  wire [InSigWidth*2+1:0] product_significand_ext = a_significand_ext * b_significand_ext;

  // Normalize to ensure significand fits in [1, 2) and truncate away the leading 1.
  wire [InExpWidth:0] product_exp_norm = product_exp + product_significand_ext[InSigWidth*2+1];
  wire [InSigWidth*2:0] product_significand_norm = product_significand_ext[InSigWidth*2+1] ?
      product_significand_ext[InSigWidth*2:0] : {product_significand_ext[InSigWidth*2-1:0], 1'b0};

  assign resp_exponent_o = product_exp_norm;
  assign resp_significand_o = product_significand_norm;

endmodule
