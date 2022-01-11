module muntjac_fpu_div_sqrt #(
  parameter InExpWidth = 9,
  parameter InSigWidth = 23,
  parameter OutExpWidth = 10,
  parameter OutSigWidth = 25
) (
  input  logic rst_ni,
  input  logic clk_i,

  output logic req_ready_o,
  input  logic req_valid_i,
  input  logic sqrt_i,

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

  output logic resp_valid_o,
  output logic resp_invalid_operation_o,
  output logic resp_divide_by_zero_o,
  output logic resp_sign_o,
  output logic signed [OutExpWidth-1:0] resp_exponent_o,
  output logic signed [OutSigWidth-1:0] resp_significand_o,
  output logic resp_is_zero_o,
  output logic resp_is_inf_o,
  output logic resp_is_nan_o
);

  wire signed [OutExpWidth-1:0] a_exponent_ext = OutExpWidth'(a_exponent_i);
  wire signed [OutExpWidth-1:0] b_exponent_ext = OutExpWidth'(b_exponent_i);

  wire signed [OutExpWidth-1:0] a_exponent_over_2 = a_exponent_ext >>> 1;

  ///////////////////////////
  // Special case handling //
  ///////////////////////////

  wire a_is_signaling_nan = a_is_nan_i && !a_significand_i[InSigWidth-1];
  wire b_is_signaling_nan = b_is_nan_i && !b_significand_i[InSigWidth-1];

  wire invalid_operation_div = (a_is_signaling_nan || b_is_signaling_nan) || (a_is_inf_i && b_is_inf_i) || (a_is_zero_i && b_is_zero_i);
  wire invalid_operation_sqrt = a_is_signaling_nan || (!a_is_nan_i && !a_is_zero_i && a_sign_i);
  wire divide_by_zero = !a_is_nan_i & !a_is_inf_i && !a_is_zero_i && b_is_zero_i;
  wire exception = sqrt_i ? invalid_operation_sqrt : invalid_operation_div || divide_by_zero;

  wire quotient_sign = sqrt_i ? a_sign_i : a_sign_i ^ b_sign_i;
  wire special_is_zero = sqrt_i ? a_is_zero_i : a_is_zero_i || b_is_inf_i;
  wire special_is_inf  = sqrt_i ? a_is_inf_i  : a_is_inf_i  || b_is_zero_i;
  wire special_is_nan = sqrt_i ? a_is_nan_i || invalid_operation_sqrt : a_is_nan_i || b_is_nan_i || invalid_operation_div;

  wire a_special = a_is_nan_i || a_is_inf_i || a_is_zero_i;
  wire b_special = b_is_nan_i || b_is_inf_i || b_is_zero_i;
  wire special = a_special || (sqrt_i ? a_sign_i : b_special);

  // Derivation of the algorithm we use:
  //
  // For divison, start from the following straight-forward pseudo-algorithm
  // ```
  // quotient = 0
  // for (bit = 1; bit != 1ulp; bit /= 2) {
  //   if (significand_a >= (quotient + bit) * significand_b) {
  //     quotient += bit;
  //   }
  // }
  // if (significand_a >= quotient * significand_b) quotient += 1ulp
  // ```
  //
  // Define remainder = significand_a - quotient * significand_b, then
  //     significand_a >= (quotient + bit) * significand_b
  // =>  significand_a - quotient * significand_b >= bit * significand_b
  // =>  remainder >= bit * significand_b
  //
  // So we have
  // ```
  // quotient = 0
  // remainder = significand_a
  // for (bit = 1; bit != 1ulp; bit /= 2) {
  //   if (remainder >= bit * significand_b) {
  //     quotient += bit;
  //     remainder -= bit * significand_b;
  //   }
  // }
  // if (remainder != 0) quotient += 1ulp
  // ```
  //
  // Define remainder' = remainder / bit:
  // ```
  // quotient = 0
  // remainder' = significand_a
  // for (bit = 1; bit != 1ulp; bit /= 2) {
  //   if (remainder' >= significand) {
  //     quotient += bit;
  //     remainder' -= significand;
  //   }
  //   remainder' *= 2;
  // }
  // if (remainder' != 0) quotient += 1ulp
  // ```
  //
  // For square-root, start from the following straight-forward pseudo-algorithm
  // ```
  // quotient = 0
  // for (bit = 1; bit != 1ulp; bit /= 2) {
  //   if (significand_a >= (quotient + bit) ** 2) {
  //       quotient += bit;
  //   }
  // }
  // if (significand_a >= quotient ** 2) quotient += 1ulp
  // ```
  //
  // Define remainder = significand_a - quotient ** 2, then
  //     significand_a >= (quotient + bit) ** 2
  // =>  significand_a - quotient ** 2 >= 2 * bit * quotient + bit ** 2
  // =>  remainder >= 2 * bit * quotient + bit ** 2
  //
  // So we have
  // ```
  // quotient = 0
  // remainder = significand_a
  // for (bit = 1; bit != 1ulp; bit /= 2) {
  //   if (remainder >= 2 * bit * quotient + bit ** 2) {
  //     quotient += bit;
  //     remainder -= 2 * bit * quotient + bit ** 2;
  //   }
  // }
  // if (remainder != 0) quotient += 1ulp
  // ```
  //
  // Define remainder' = remainder / bit:
  // ```
  // quotient = 0
  // remainder' = significand_a
  // for (bit = 1; bit != 1ulp; bit /= 2) {
  //   if (remainder' >= 2 * quotient + bit) {
  //     quotient += bit;
  //     remainder' -= 2 * quotient + bit;
  //   }
  //   remainder' *= 2;
  // }
  // if (remainder' != 0) quotient += 1ulp
  // ```
  //
  // Now we see that division and square root are quite similar so we can do them in the same logic.
  //
  // For division, if significand_a < significand_b, the significand of the quotient will be
  // within [0.5, 1), so we can normalise it by start with significand_a * 2, and then minus 1
  // from the exponent. For square root, if exponent_a is not multiple of 2, we can substract 1
  // from that and similarly start with significand_a * 2.
  //
  // With normalisation, quotient is known to be bound in [1, 2) and remainder is bound in [0, 8).
  // The trial subtraction difference is bound in (-2, 4).
  // We will use fixed point representation with (OutSigWidth-1) binary digits after the point.

  typedef enum logic [1:0] {
    StateIdle,
    StateCompute,
    StateOutput
  } state_e;

  state_e state_q, state_d;
  logic sqrt_q, sqrt_d;
  logic [InSigWidth-1:0] b_significand_q, b_significand_d;
  logic exception_q, exception_d;
  logic quotient_sign_q, quotient_sign_d;
  logic signed [OutExpWidth-1:0] quotient_exponent_q, quotient_exponent_d;
  logic quotient_is_zero_q, quotient_is_zero_d;
  logic quotient_is_inf_q, quotient_is_inf_d;
  logic quotient_is_nan_q, quotient_is_nan_d;

  logic        [OutSigWidth-1:0] quotient_q, quotient_d;
  logic        [OutSigWidth+1:0] remainder_q, remainder_d;
  logic        [OutSigWidth-1:0] bit_q, bit_d;
  logic        [OutSigWidth  :0] subtrahend;
  logic signed [OutSigWidth+1:0] difference;

  always_comb begin
    if (sqrt_q) begin
      subtrahend = {quotient_q, 1'b0} | {1'b0, bit_q};
    end else begin
      subtrahend = {2'b01, b_significand_q, {(OutSigWidth-InSigWidth-1){1'b0}}};
    end
    difference = remainder_q - subtrahend;
  end

  always_comb begin
    state_d = state_q;
    sqrt_d = sqrt_q;
    b_significand_d = b_significand_q;
    exception_d = exception_q;
    quotient_sign_d = quotient_sign_q;
    quotient_exponent_d = quotient_exponent_q;
    quotient_is_zero_d = quotient_is_zero_q;
    quotient_is_inf_d = quotient_is_inf_q;
    quotient_is_nan_d = quotient_is_nan_q;
    remainder_d = remainder_q;
    quotient_d = quotient_q;
    bit_d = bit_q;

    req_ready_o = 1'b0;
    resp_valid_o = 1'b0;

    unique case (state_q)
      StateIdle: begin
        req_ready_o = 1'b1;

        if (req_valid_i) begin
          state_d = special ? StateOutput : StateCompute;

          sqrt_d = sqrt_i;
          b_significand_d = b_significand_i;
          exception_d = exception;
          quotient_sign_d = quotient_sign;
          quotient_exponent_d = sqrt_i ? a_exponent_over_2 :
              a_exponent_ext - b_exponent_ext - OutExpWidth'(a_significand_i < b_significand_i);
          quotient_is_zero_d = special_is_zero;
          quotient_is_inf_d = special_is_inf;
          quotient_is_nan_d = special_is_nan;

          quotient_d = 0;
          if (sqrt_i ? a_exponent_ext[0] : a_significand_i < b_significand_i) begin
            remainder_d = {2'b01, a_significand_i, {(OutSigWidth-InSigWidth){1'b0}}};
          end else begin
            remainder_d = {3'b001, a_significand_i, {(OutSigWidth-InSigWidth-1){1'b0}}};
          end
          bit_d = {1'b1, {(OutSigWidth-1){1'b0}}};
        end
      end

      StateCompute: begin
        if (difference >= 0) begin
          remainder_d = {difference[OutSigWidth:0], 1'b0};
          quotient_d = quotient_q | bit_q;
        end else begin
          remainder_d = {remainder_q[OutSigWidth:0], 1'b0};
        end
        bit_d = bit_q >> 1;

        if (bit_q[0]) begin
          // Reached the last bit. Move to output state
          state_d = StateOutput;
        end
      end

      StateOutput: begin
        resp_valid_o = 1'b1;
        state_d = StateIdle;
      end

      default:;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= StateIdle;
      sqrt_q <= 1'bx;
      b_significand_q <= 'x;
      exception_q <= 1'bx;
      quotient_sign_q <= 1'bx;
      quotient_exponent_q <= 'x;
      quotient_is_zero_q <= 1'bx;
      quotient_is_inf_q <= 1'bx;
      quotient_is_nan_q <= 1'bx;
      remainder_q <= 'x;
      quotient_q <= 'x;
      bit_q <= 'x;
    end else begin
      state_q <= state_d;
      sqrt_q <= sqrt_d;
      b_significand_q <= b_significand_d;
      exception_q <= exception_d;
      quotient_sign_q <= quotient_sign_d;
      quotient_exponent_q <= quotient_exponent_d;
      quotient_is_zero_q <= quotient_is_zero_d;
      quotient_is_inf_q <= quotient_is_inf_d;
      quotient_is_nan_q <= quotient_is_nan_d;
      remainder_q <= remainder_d;
      quotient_q <= quotient_d;
      bit_q <= bit_d;
    end
  end

  assign resp_invalid_operation_o = exception_q && quotient_is_nan_q;
  assign resp_divide_by_zero_o = exception_q && !quotient_is_nan_q;
  assign resp_sign_o = quotient_sign_q;
  assign resp_exponent_o = quotient_exponent_q;
  assign resp_significand_o = {quotient_q[OutSigWidth-2:0], remainder_q != 0};
  assign resp_is_zero_o = quotient_is_zero_q;
  assign resp_is_inf_o = quotient_is_inf_q;
  assign resp_is_nan_o = quotient_is_nan_q;

endmodule
