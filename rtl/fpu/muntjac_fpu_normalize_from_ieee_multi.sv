module muntjac_fpu_normalize_from_ieee_multi import muntjac_fpu_pkg::*; #(
  parameter OutExpWidth = 12,
  parameter OutSigWidth = 52
) (
  input  logic double_i,
  input  logic [63:0] ieee_i,

  output logic sign_o,
  output logic [OutExpWidth-1:0] exponent_o,
  output logic [OutSigWidth-1:0] significand_o,
  output logic is_normal_o,
  output logic is_zero_o,
  output logic is_subnormal_o,
  output logic is_inf_o,
  output logic is_nan_o
);

  wire nan_boxed = &ieee_i[63:32];

  logic single_sign;
  logic [OutExpWidth-1:0] single_exponent;
  logic [OutSigWidth-1:0] single_significand;
  logic single_is_normal;
  logic single_is_zero;
  logic single_is_subnormal;
  logic single_is_inf;
  logic single_is_nan;

  muntjac_fpu_normalize_from_ieee #(
    .IeeeExpWidth (SingleExpWidth),
    .IeeeSigWidth (SingleSigWidth),
    .OutExpWidth (OutExpWidth),
    .OutSigWidth (OutSigWidth)
  ) single_decode_a (
    .ieee_i (ieee_i[31:0]),
    .sign_o (single_sign),
    .exponent_o (single_exponent),
    .significand_o (single_significand),
    .is_normal_o (single_is_normal),
    .is_zero_o (single_is_zero),
    .is_subnormal_o (single_is_subnormal),
    .is_inf_o (single_is_inf),
    .is_nan_o (single_is_nan)
  );

  logic double_sign;
  logic [OutExpWidth-1:0] double_exponent;
  logic [OutSigWidth-1:0] double_significand;
  logic double_is_normal;
  logic double_is_zero;
  logic double_is_subnormal;
  logic double_is_inf;
  logic double_is_nan;

  muntjac_fpu_normalize_from_ieee #(
    .IeeeExpWidth (DoubleExpWidth),
    .IeeeSigWidth (DoubleSigWidth),
    .OutExpWidth (OutExpWidth),
    .OutSigWidth (OutSigWidth)
  ) double_decode_a (
    .ieee_i (ieee_i),
    .sign_o (double_sign),
    .exponent_o (double_exponent),
    .significand_o (double_significand),
    .is_normal_o (double_is_normal),
    .is_zero_o (double_is_zero),
    .is_subnormal_o (double_is_subnormal),
    .is_inf_o (double_is_inf),
    .is_nan_o (double_is_nan)
  );

  always_comb begin
    if (double_i) begin
      sign_o = double_sign;
      exponent_o = double_exponent;
      significand_o = double_significand;
      is_normal_o = double_is_normal;
      is_zero_o = double_is_zero;
      is_subnormal_o = double_is_subnormal;
      is_inf_o = double_is_inf;
      is_nan_o = double_is_nan;
    end else begin
      if (nan_boxed) begin
        sign_o = single_sign;
        exponent_o = single_exponent;
        significand_o = single_significand;
        is_normal_o = single_is_normal;
        is_zero_o = single_is_zero;
        is_subnormal_o = single_is_subnormal;
        is_inf_o = single_is_inf;
        is_nan_o = single_is_nan;
      end else begin
        // Other treat it as the canonical NaN
        sign_o = 1'b0;
        exponent_o = '0;
        significand_o = {1'b1, {(OutSigWidth-1){1'b0}}};
        is_normal_o = 1'b0;
        is_zero_o = 1'b0;
        is_subnormal_o = 1'b0;
        is_inf_o = 1'b0;
        is_nan_o = 1'b1;
      end
    end
  end

endmodule
