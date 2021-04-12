module muntjac_fpu_round_to_int_multi import muntjac_fpu_pkg::*; #(
  parameter InExpWidth = 13,
  parameter InSigWidth = 54
) (
  input  rounding_mode_e rounding_mode_i,
  input  logic signed_i,
  input  logic dword_i,

  input  logic sign_i,
  input  logic signed [InExpWidth-1:0] exponent_i,
  input  logic [InSigWidth-1:0] significand_i,
  input  logic is_zero_i,
  input  logic is_inf_i,
  input  logic is_nan_i,

  output logic [63:0] int_o,
  output exception_flags_t exception_o
);

  logic [63:0] round_int;
  exception_flags_t round_exception;

  muntjac_fpu_round_to_int #(
    .InExpWidth (InExpWidth),
    .InSigWidth (InSigWidth),
    .IntWidth (64)
  ) round (
    .rounding_mode_i,
    .signed_i,
    .sign_i,
    .exponent_i,
    .significand_i,
    .is_zero_i,
    .is_inf_i,
    .is_nan_i,
    .int_o (round_int),
    .exception_o (round_exception)
  );

  always_comb begin
    if (dword_i) begin
      int_o = round_int;
      exception_o = round_exception;
    end else begin
      int_o = {{33{round_int[31]}}, round_int[30:0]};
      exception_o = round_exception;
      if (signed_i) begin
        if (round_int[63]) begin
          // Negative value out of range, set to MIN
          if (~&round_int[62:31]) begin
            int_o = 64'hffffffff_80000000;
            exception_o.invalid_operation = 1'b1;
          end
        end else begin
          // Positive value out of range, set to MAX
          if (|round_int[62:31]) begin
            int_o = 64'h00000000_7fffffff;
            exception_o.invalid_operation = 1'b1;
          end
        end
      end else begin
        if (|round_int[63:32]) begin
          int_o = 64'hffffffff_ffffffff;
          exception_o.invalid_operation = 1'b1;
        end
      end
    end
  end

endmodule
