module muntjac_fpu_compare #(
  parameter ExpWidth = 9,
  parameter SigWidth = 23
) (
  input  logic a_sign_i,
  input  logic signed [ExpWidth-1:0] a_exponent_i,
  input  logic [SigWidth-1:0] a_significand_i,
  input  logic a_is_zero_i,
  input  logic a_is_inf_i,
  input  logic a_is_nan_i,

  input  logic b_sign_i,
  input  logic signed [ExpWidth-1:0] b_exponent_i,
  input  logic [SigWidth-1:0] b_significand_i,
  input  logic b_is_zero_i,
  input  logic b_is_inf_i,
  input  logic b_is_nan_i,

  input  logic signaling_i,
  output logic lt_o,
  output logic eq_o,
  output logic unordered_o,
  output logic invalid_operation_o
);

  wire a_is_signaling_nan = a_is_nan_i && !a_significand_i[SigWidth-1];
  wire b_is_signaling_nan = b_is_nan_i && !b_significand_i[SigWidth-1];

  wire exponent_eq = a_exponent_i == b_exponent_i;
  wire exponent_lt = a_exponent_i < b_exponent_i;
  wire significand_eq = a_significand_i == b_significand_i;
  wire significand_lt = a_significand_i < b_significand_i;
  wire exp_sig_eq = exponent_eq && significand_eq;
  wire exp_sig_lt = exponent_lt || (exponent_eq && significand_lt);

  assign unordered_o = a_is_nan_i || b_is_nan_i;

  logic ordered_eq;
  logic ordered_lt;
  always_comb begin
    ordered_eq = 1'b0;
    ordered_lt = 1'b0;

    if (a_is_zero_i && b_is_zero_i) begin
      ordered_eq = 1'b1;
    end else if (a_is_zero_i) begin
      ordered_lt = !b_sign_i;
    end else if (b_is_zero_i) begin
      ordered_lt = a_sign_i;
    end else if (a_sign_i != b_sign_i) begin
      ordered_lt = a_sign_i;
    end else begin
      if (a_is_inf_i && b_is_inf_i) begin
        ordered_eq = 1'b1;
      end else if (a_is_inf_i) begin
        ordered_lt = a_sign_i;
      end else if (b_is_inf_i) begin
        ordered_lt = !b_sign_i;
      end else if (exp_sig_eq) begin
        ordered_eq = 1'b1;
      end else begin
        ordered_lt = exp_sig_lt ^ a_sign_i;
      end
    end
  end

  assign invalid_operation_o = a_is_signaling_nan || b_is_signaling_nan || (signaling_i && unordered_o);
  assign lt_o = !unordered_o && ordered_lt;
  assign eq_o = !unordered_o && ordered_eq;

endmodule

