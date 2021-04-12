module muntjac_fpu_normalize_from_ieee #(
  parameter IeeeExpWidth = 8,
  parameter IeeeSigWidth = 23,
  parameter OutExpWidth = IeeeExpWidth + 1,
  parameter OutSigWidth = IeeeSigWidth,
  localparam IeeeWidth = IeeeExpWidth + IeeeSigWidth + 1
) (
  input logic [IeeeWidth - 1:0] ieee_i,
  output logic sign_o,
  output logic [OutExpWidth-1:0] exponent_o,
  output logic [OutSigWidth-1:0] significand_o,
  output logic is_normal_o,
  output logic is_zero_o,
  output logic is_subnormal_o,
  output logic is_inf_o,
  output logic is_nan_o
);

  // Unpack the IEEE formated input.
  logic ieee_sign;
  logic [IeeeExpWidth-1:0] ieee_exponent;
  logic [IeeeSigWidth-1:0] ieee_significand;
  assign {ieee_sign, ieee_exponent, ieee_significand} = ieee_i;

  // Classify the number
  wire is_exponent_zero = ieee_exponent == 0;
  wire is_exponent_max = &ieee_exponent;
  wire is_significand_zero = ieee_significand == 0;

  assign is_normal_o = !is_exponent_zero && !is_exponent_max;
  assign is_zero_o = is_exponent_zero && is_significand_zero;
  assign is_subnormal_o = is_exponent_zero && !is_significand_zero;
  assign is_inf_o = is_exponent_max && is_significand_zero;
  assign is_nan_o = is_exponent_max && !is_significand_zero;

  logic [$clog2(IeeeSigWidth)-1:0] subnormal_exponent_offset;
  logic [IeeeSigWidth-1:0] subnormal_significand;

  muntjac_fpu_normalize #(
    .DataWidth (IeeeSigWidth)
  ) normalize (
    .data_i (ieee_significand),
    .is_zero_o (),
    .shift_o (subnormal_exponent_offset),
    .data_o (subnormal_significand)
  );

  localparam signed ExponentBias = 2 ** (IeeeExpWidth - 1) - 1;

  // Flip the MSB and sign-extend for one bit.
  wire [IeeeExpWidth:0] widened_exponent = ieee_exponent - ExponentBias;
  wire [IeeeExpWidth:0] normalized_exponent = widened_exponent - (is_exponent_zero ? subnormal_exponent_offset : 0);

  assign sign_o = ieee_sign;
  assign exponent_o = OutExpWidth'(signed'(normalized_exponent));
  assign significand_o = {is_exponent_zero ? subnormal_significand << 1 : ieee_significand, {(OutSigWidth - IeeeSigWidth){1'b0}}};

endmodule

