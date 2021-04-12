module muntjac_fpu_normalize_from_int #(
  parameter IntWidth = 64,
  parameter OutExpWidth = 9,
  parameter OutSigWidth = 23
) (
  input  logic signed_i,
  input  logic [IntWidth-1:0] int_i,

  output logic resp_sign_o,
  output logic signed [OutExpWidth-1:0] resp_exponent_o,
  output logic signed [OutSigWidth-1:0] resp_significand_o,
  output logic resp_is_zero_o
);

  // Determine sign and extract magnitude
  assign resp_sign_o = signed_i && int_i[IntWidth-1];
  wire [IntWidth-1:0] abs = resp_sign_o ? -int_i : int_i;

  logic [$clog2(IntWidth)-1:0] norm_shift;
  logic [IntWidth-1:0] norm_sig;

  muntjac_fpu_normalize #(
    .DataWidth (64)
  ) int_to_fp (
    .data_i (abs),
    .is_zero_o (resp_is_zero_o),
    .shift_o (norm_shift),
    .data_o (norm_sig)
  );

  assign resp_exponent_o = (IntWidth - 1) - norm_shift;
  assign resp_significand_o = {norm_sig[IntWidth-2-:OutSigWidth-1], |norm_sig[IntWidth-2-OutSigWidth+1:0]};

endmodule
