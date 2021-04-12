module muntjac_fpu_add #(
  parameter InExpWidth = 9,
  parameter InSigWidth = 23,
  parameter OutExpWidth = 10,
  parameter OutSigWidth = 25
) (
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

  output logic resp_invalid_operation_o,
  output logic resp_sign_o,
  output logic signed [OutExpWidth-1:0] resp_exponent_o,
  output logic signed [OutSigWidth-1:0] resp_significand_o,
  output logic resp_is_zero_o,
  output logic resp_is_inf_o,
  output logic resp_is_nan_o
);

  // Use the larger of the SigWidth as the internal width.
  localparam InternalSigWidth = InSigWidth > OutSigWidth ? InSigWidth : OutSigWidth;

  wire substract_magnitude = a_sign_i ^ b_sign_i;
  wire cancellation_zero_sign = rounding_mode_i == muntjac_fpu_pkg::RoundTowardNegative;

  wire a_is_signaling_nan = a_is_nan_i && !a_significand_i[InSigWidth-1];
  wire b_is_signaling_nan = b_is_nan_i && !b_significand_i[InSigWidth-1];

  // Check for invalid operation conditions and set corresponding flags if true.
  assign resp_invalid_operation_o =
    a_is_signaling_nan || b_is_signaling_nan ||
    (a_is_inf_i && b_is_inf_i && substract_magnitude);

  assign resp_is_nan_o = a_is_nan_i || b_is_nan_i;
  assign resp_is_inf_o = !resp_is_nan_o && (a_is_inf_i || b_is_inf_i);
  wire special_is_zero = a_is_zero_i && b_is_zero_i;

  wire special = resp_is_nan_o || resp_is_inf_o || special_is_zero;
  wire special_sign =
      a_is_inf_i ? a_sign_i :
      b_is_inf_i ? b_sign_i :
      special_is_zero ? (substract_magnitude ? cancellation_zero_sign : a_sign_i) : 1'b0;

  // Determine the order of the two operands.
  // We need to know which one is larger to align significand and ensure magnitude is positive.
  wire signed [InExpWidth:0] exponent_difference = a_exponent_i - b_exponent_i;
  wire signed [InExpWidth:0] neg_exponent_difference = -exponent_difference;
  wire swap_operand = exponent_difference < 0 || (exponent_difference == 0 && a_significand_i < b_significand_i);

  // Add back the explicit 1 bit and shift accordingly.
  wire [InternalSigWidth:0] a_significand_ext = {1'b1, a_significand_i, {(InternalSigWidth-InSigWidth){1'b0}}};
  wire [InternalSigWidth:0] b_significand_ext = {1'b1, b_significand_i, {(InternalSigWidth-InSigWidth){1'b0}}};
  wire [InternalSigWidth:0] a_significand_shifted;
  wire [InternalSigWidth:0] b_significand_shifted;

  muntjac_fpu_right_shift #(
    .DataWidth(InternalSigWidth+1),
    .ShiftWidth(InExpWidth)
  ) a_shift (
    .data_i (a_significand_ext),
    // The result is only used if exponent_difference <= 0
    .shift_i (neg_exponent_difference[InExpWidth-1:0]),
    .data_o (a_significand_shifted)
  );

  muntjac_fpu_right_shift #(
    .DataWidth(InternalSigWidth+1),
    .ShiftWidth(InExpWidth)
  ) b_shift (
    .data_i (b_significand_ext),
    // The result is only used if exponent_difference >= 0
    .shift_i (exponent_difference[InExpWidth-1:0]),
    .data_o (b_significand_shifted)
  );

  wire [InternalSigWidth:0] big_significand_norm = swap_operand ? b_significand_ext : a_significand_ext;
  wire [InternalSigWidth:0] small_significand_norm = swap_operand ? a_significand_shifted : b_significand_shifted;
  wire [InternalSigWidth+1:0] sum = substract_magnitude ? big_significand_norm - small_significand_norm : big_significand_norm + small_significand_norm;

  // Normalize the result

  logic [$clog2(InternalSigWidth+2)-1:0] norm_shift;
  logic [InternalSigWidth+1:0] norm_sig;
  logic norm_zero;

  muntjac_fpu_normalize #(
    .DataWidth (InternalSigWidth+2)
  ) normalize (
    .data_i (sum),
    .is_zero_o (norm_zero),
    .shift_o (norm_shift),
    .data_o (norm_sig)
  );

  // Multiplex the final result

  wire [InternalSigWidth+1:0] resp_sig =
      a_is_zero_i ? {b_significand_ext, 1'b0} :
      b_is_zero_i ? {a_significand_ext, 1'b0} : norm_sig;

  assign resp_is_zero_o = special ? special_is_zero : norm_zero;
  assign resp_sign_o =
      special ? special_sign :
      a_is_zero_i ? b_sign_i :
      b_is_zero_i ? a_sign_i :
      norm_zero ? cancellation_zero_sign : (swap_operand ? b_sign_i : a_sign_i);
  assign resp_exponent_o =
      a_is_zero_i ? b_exponent_i :
      b_is_zero_i ? a_exponent_i : (swap_operand ? b_exponent_i : a_exponent_i) + 1 - OutExpWidth'(norm_shift);

 assign resp_significand_o = {resp_sig[InternalSigWidth-:OutSigWidth-1], |resp_sig[InternalSigWidth-OutSigWidth+1:0]};

endmodule
