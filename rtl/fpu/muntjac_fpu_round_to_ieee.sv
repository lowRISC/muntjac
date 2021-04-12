
module muntjac_fpu_round_to_ieee import muntjac_fpu_pkg::*; #(
  parameter InExpWidth = 13,
  parameter InSigWidth = 54,
  parameter IeeeExpWidth = 11,
  parameter IeeeSigWidth = 52,
  localparam IeeeWidth = IeeeExpWidth + IeeeSigWidth + 1
) (
  input  logic invalid_operation_i,
  input  logic divide_by_zero_i,
  input  logic use_nan_payload_i,
  input  logic sign_i,
  input  logic is_zero_i,
  input  logic is_nan_i,
  input  logic is_inf_i,
  input  logic signed [InExpWidth-1:0] exponent_i,
  input  logic [InSigWidth-1:0] significand_i,
  input  rounding_mode_e rounding_mode_i,
  output logic [IeeeWidth-1:0] ieee_o,
  output exception_flags_t exception_o
);

  localparam ExponentBias = 2 ** (IeeeExpWidth - 1) - 1;
  localparam MinimumExponent = 1 - ExponentBias;
  localparam MaximumExponent = 2 ** IeeeExpWidth - ExponentBias;

  // For subnormal numbers, we will set the basis as MinimumExponent and shift accordingly.
  // Otherwise we don't perform any shifts (so set subnormal_shift to 0).
  // We must shift before rounding as this will affect the inexact flag.
  wire signed [InExpWidth-1:0] subnormal_exponent_difference = MinimumExponent - exponent_i;
  wire signed [InExpWidth-1:0] exponent_basis = subnormal_exponent_difference >= 0 ? MinimumExponent : exponent_i;
  wire signed [InExpWidth-1:0] subnormal_shift = subnormal_exponent_difference >= 0 ? subnormal_exponent_difference : 0;

  logic [InSigWidth:0] subnormal_significand;
  muntjac_fpu_right_shift #(
    .DataWidth (InSigWidth + 1),
    .ShiftWidth (InExpWidth)
  ) subnormal_shifter (
    .data_i ({1'b1, significand_i}),
    .shift_i (subnormal_shift),
    .data_o (subnormal_significand)
  );

  // We only need IeeeSigWidth+3 bits (1 for explicit 1 and 2 for rounding). If we have extra
  // then just right-shfit them away.
  wire [IeeeSigWidth+2:0] significand_to_round =
      {subnormal_significand[InSigWidth-:IeeeSigWidth+2], |subnormal_significand[InSigWidth-IeeeSigWidth-2:0]};

  // Now perform the rounding. For rounding we only need to look at the last two bits.
  // Let a be the first bit beyond target precision, and b be the second bit.
  // In operations that cannot produce accurate result we use the last bit (b) to denote whether
  // there are any remainder, so
  // * If a=0, b=0, then the remainder is 0.
  // * If a=0, b=1, then the remainder is in range (0, 0.5)
  // * If a=1, b=0, then the remainder is 0.5.
  // * If a=1, b=1, then the remainder is in range (0.5, 1).
  // Combine a, b and target rounding mode we can therefore decide on how to round.

  logic inexact;
  logic roundup;

  always_comb begin
    inexact = 1'b0;
    roundup = 1'b0;

    if (significand_to_round[1:0] != 0) begin
      inexact = 1'b1;

      unique case (rounding_mode_i)
        RoundTiesToEven: begin
          roundup = significand_to_round[1:0] == 2'b11 || significand_to_round[2:0] == 3'b110;
        end
        RoundTowardZero:;
        RoundTowardNegative: begin
          roundup = sign_i && significand_to_round[1:0] != 2'b00;
        end
        RoundTowardPositive: begin
          roundup = !sign_i && significand_to_round[1:0] != 2'b00;
        end
        RoundTiesToAway: begin
          roundup = significand_to_round[1] == 1'b1;
        end
        default:;
      endcase
    end
  end

  wire [IeeeSigWidth+1:0] significand_rounded = significand_to_round[IeeeSigWidth+2:2] + roundup;

  // Our rounding may cause the numnber to bump from 1.111... to 10.000, so we need to take that into account.
  wire signed [InExpWidth-1:0] adjusted_exponent = significand_rounded[IeeeSigWidth+1] ? exponent_basis + 1 : exponent_basis;
  wire signed [IeeeSigWidth:0] adjusted_significand = significand_rounded[IeeeSigWidth+1] ? significand_rounded[IeeeSigWidth+1:1] : significand_rounded[IeeeSigWidth:0];

  logic ieee_sign;
  logic [IeeeExpWidth-1:0] ieee_exponent;
  logic [IeeeSigWidth-1:0] ieee_significand;

  always_comb begin
    exception_o = '0;
    ieee_sign = sign_i;

    if (invalid_operation_i || is_nan_i) begin
      exception_o.invalid_operation = invalid_operation_i;
      ieee_sign = use_nan_payload_i ? sign_i : 1'b0;
      ieee_exponent = '1;
      ieee_significand = use_nan_payload_i ? significand_i[InSigWidth-1-:IeeeSigWidth] : {1'b1, {(IeeeSigWidth-1){1'b0}}};
    end else if (is_inf_i) begin
      exception_o.divide_by_zero = divide_by_zero_i;
      ieee_exponent = '1;
      ieee_significand = '0;
    end else if (is_zero_i) begin
      ieee_exponent = '0;
      ieee_significand = '0;
    end else begin
      exception_o.inexact = inexact;

      if (adjusted_exponent > MaximumExponent) begin
        // Finite number overflows
        exception_o.inexact = 1'b1;
        exception_o.overflow = 1'b1;

        if ((sign_i && rounding_mode_i == RoundTowardPositive) ||
            (!sign_i && rounding_mode_i == RoundTowardNegative) ||
            rounding_mode_i == RoundTowardZero) begin
          ieee_exponent = '1 - 1;
          ieee_significand = '1;
        end else begin
          ieee_exponent = '1;
          ieee_significand = '0;
        end
      end else if (!adjusted_significand[IeeeSigWidth]) begin
        exception_o.underflow = inexact;

        ieee_exponent = 0;
        ieee_significand = adjusted_significand[IeeeSigWidth-1:0];
      end else begin
        ieee_exponent = adjusted_exponent + ExponentBias;
        ieee_significand = adjusted_significand[IeeeSigWidth-1:0];
      end
    end
  end

  assign ieee_o = {ieee_sign, ieee_exponent, ieee_significand};

endmodule