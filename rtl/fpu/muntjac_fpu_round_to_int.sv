module muntjac_fpu_round_to_int import muntjac_fpu_pkg::*; #(
  parameter InExpWidth = 13,
  parameter InSigWidth = 54,
  parameter IntWidth = 64
) (
  input  rounding_mode_e rounding_mode_i,
  input  logic signed_i,

  input  logic sign_i,
  input  logic signed [InExpWidth-1:0] exponent_i,
  input  logic [InSigWidth-1:0] significand_i,
  input  logic is_zero_i,
  input  logic is_inf_i,
  input  logic is_nan_i,

  output logic [IntWidth-1:0] int_o,
  output exception_flags_t exception_o
);

  // Shift the number and adjust exponent so that there are only 2 bits after fixed point (for rounding).
  wire signed [InExpWidth:0] effective_exponent = exponent_i - (IntWidth - 1);
  wire [IntWidth+1:0] effective_significand = {1'b1, significand_i, {(IntWidth-InSigWidth+1){1'b0}}};

  logic [IntWidth+1:0] int_significand;
  muntjac_fpu_right_shift #(
    .DataWidth (IntWidth + 2),
    .ShiftWidth (InExpWidth + 1)
  ) shifter (
    .data_i (effective_significand),
    .shift_i (-effective_exponent),
    .data_o (int_significand)
  );

  logic inexact;
  logic roundup;

  muntjac_fpu_round rounder (
    .rounding_mode_i,
    .sign_i,
    .significand_i (int_significand[2:0]),
    .inexact_o (inexact),
    .roundup_o (roundup)
  );

  wire [IntWidth:0] significand_rounded = int_significand[IntWidth+1:2] + roundup;

  // For a positive number, we can check if it overflows by determining from MSBs.
  wire positive_overflow = significand_rounded[IntWidth] || (signed_i && significand_rounded[IntWidth-1]);

  // For a negative number, we can check if it overflows by determing from LSBs.
  wire lsb_all_zero = significand_rounded[IntWidth-2:0] == 0;
  wire negative_overflow =
      significand_rounded[IntWidth] || // 1XXXX, always overflow
      significand_rounded[IntWidth-1] && (!signed_i || !lsb_all_zero) || // 01XXXXX, overflow if signed or not all zero
      (!signed_i && !lsb_all_zero);

  wire overflow = sign_i ? negative_overflow : positive_overflow;

  wire [IntWidth-1:0] positive_max = {!signed_i, {(IntWidth-1){1'b1}}};
  wire [IntWidth-1:0] negative_max = {signed_i, {(IntWidth-1){1'b0}}};
  wire [IntWidth-1:0] max_value = sign_i ? negative_max : positive_max;

  always_comb begin
    exception_o = '0;

    if (is_nan_i) begin
      exception_o.invalid_operation = 1'b1;
      int_o = positive_max;
    end else if (is_zero_i) begin
      int_o = 0;
    end else if (effective_exponent > 0) begin
      // Exponent is too large for significand to be any significant
      exception_o.invalid_operation = 1'b1;
      int_o = max_value;
    end else begin
      if (overflow) begin
        exception_o.invalid_operation = 1'b1;
        int_o = max_value;
      end else begin
        exception_o.inexact = inexact;
        int_o = sign_i ? -significand_rounded[IntWidth-1:0] : significand_rounded[IntWidth-1:0];
      end
    end
  end

endmodule

