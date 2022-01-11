
module muntjac_fpu_round_to_ieee_multi import muntjac_fpu_pkg::*; #(
  parameter InExpWidth = 13,
  parameter InSigWidth = 54
) (
  input  logic invalid_operation_i,
  input  logic divide_by_zero_i,
  input  logic use_nan_payload_i,
  input  logic double_i,
  input  logic sign_i,
  input  logic is_zero_i,
  input  logic is_nan_i,
  input  logic is_inf_i,
  input  logic signed [InExpWidth-1:0] exponent_i,
  input  logic [InSigWidth-1:0] significand_i,
  input  rounding_mode_e rounding_mode_i,
  output logic [63:0] ieee_o,
  output exception_flags_t exception_o
);

  logic [63:0] double_ieee;
  exception_flags_t double_exception;

  muntjac_fpu_round_to_ieee #(
    .InExpWidth (InExpWidth),
    .InSigWidth (InSigWidth),
    .IeeeExpWidth (DoubleExpWidth),
    .IeeeSigWidth (DoubleSigWidth)
  ) round_double (
    .invalid_operation_i,
    .divide_by_zero_i,
    .use_nan_payload_i,
    .is_zero_i,
    .is_inf_i,
    .is_nan_i,
    .sign_i,
    .exponent_i,
    .significand_i,
    .rounding_mode_i,
    .ieee_o (double_ieee),
    .exception_o (double_exception)
  );

  logic [31:0] single_ieee;
  exception_flags_t single_exception;

  muntjac_fpu_round_to_ieee #(
    .InExpWidth (InExpWidth),
    .InSigWidth (InSigWidth),
    .IeeeExpWidth (SingleExpWidth),
    .IeeeSigWidth (SingleSigWidth)
  ) round_single (
    .invalid_operation_i,
    .divide_by_zero_i,
    .use_nan_payload_i,
    .is_zero_i,
    .is_inf_i,
    .is_nan_i,
    .sign_i,
    .exponent_i,
    .significand_i,
    .rounding_mode_i,
    .ieee_o (single_ieee),
    .exception_o (single_exception)
  );

  assign ieee_o = double_i ? double_ieee : {32'hffffffff, single_ieee};
  assign exception_o = double_i ? double_exception : single_exception;

endmodule
