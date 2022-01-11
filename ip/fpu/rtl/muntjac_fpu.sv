module muntjac_fpu import muntjac_fpu_pkg::*; (
  input  logic        clk_i,
  input  logic        rst_ni,

  input  logic [63:0]     req_rs1_i,
  input  logic [63:0]     foperand_a_i,
  input  logic [63:0]     foperand_b_i,
  input  logic [63:0]     foperand_c_i,
  input  fp_op_t          req_op_i,
  input  rounding_mode_e  req_rm_i,
  input  logic            req_double_i,
  input  logic            req_valid_i,
  output logic            req_ready_o,

  output logic [63:0]      resp_value_o,
  output exception_flags_t resp_flags_o,
  output logic             resp_valid_o
);

  // IEEE-754 encoded numbers will not need extra significand precision when normalized, but
  // due to subnormal numbers being normalized then need extra bit in exponent.
  localparam DecodedExpWidth = DoubleExpWidth + 1;
  localparam DecodedSigWidth = DoubleSigWidth;

  // Doing multiplication and division will expand the range of exponent by 1 from DecodedExpWidth.
  // We need 2 extra bits for significand to allow correct rounding.
  localparam IntermediateExpWidth = DoubleExpWidth + 2;
  localparam IntermediateSigWidth = DoubleSigWidth + 2;

  typedef struct packed {
    logic sign;
    logic signed [DecodedExpWidth-1:0] exponent;
    logic [DecodedSigWidth-1:0] significand;
    logic is_zero;
    logic is_inf;
    logic is_nan;
  } decoded_fp_t;

  typedef struct packed {
    logic sign;
    logic signed [IntermediateExpWidth-1:0] exponent;
    logic [IntermediateSigWidth-1:0] significand;
    logic is_zero;
    logic is_inf;
    logic is_nan;
  } intermediate_fp_t;

  localparam decoded_fp_t DEC_ZERO = '{
    sign: 1'b0,
    exponent: '0,
    significand: '0,
    is_zero: 1'b1,
    is_inf: 1'b0,
    is_nan: 1'b0
  };
  localparam decoded_fp_t DEC_ONE = '{
    sign: 1'b0,
    exponent: '0,
    significand: '0,
    is_zero: 1'b0,
    is_inf: 1'b0,
    is_nan: 1'b0
  };
  localparam decoded_fp_t DEC_NAN = '{
    sign: 1'b0,
    exponent: '0,
    significand: {1'b1, 51'd0},
    is_zero: 1'b0,
    is_inf: 1'b0,
    is_nan: 1'b1
  };

  /////////////////////////////////
  // #region Input Normalization //

  // The first step is to transform all inputs, whether IEEE-754 encoded floating point or integer,
  // into the normalized form, i.e. represented as sig*2^exp where sig is in [1,2)

  logic decode_as_double;
  decoded_fp_t operand_a_dec;
  decoded_fp_t operand_b_dec;
  decoded_fp_t operand_c_dec;
  logic operand_a_dec_is_normal;
  logic operand_a_dec_is_subnormal;

  muntjac_fpu_normalize_from_ieee_multi #(
    .OutExpWidth (DecodedExpWidth),
    .OutSigWidth (DecodedSigWidth)
  ) decode_a (
    .double_i (decode_as_double),
    .ieee_i (foperand_a_i),
    .sign_o (operand_a_dec.sign),
    .exponent_o (operand_a_dec.exponent),
    .significand_o (operand_a_dec.significand),
    .is_normal_o (operand_a_dec_is_normal),
    .is_zero_o (operand_a_dec.is_zero),
    .is_subnormal_o (operand_a_dec_is_subnormal),
    .is_inf_o (operand_a_dec.is_inf),
    .is_nan_o (operand_a_dec.is_nan)
  );

  muntjac_fpu_normalize_from_ieee_multi #(
    .OutExpWidth (DecodedExpWidth),
    .OutSigWidth (DecodedSigWidth)
  ) decode_b (
    .double_i (decode_as_double),
    .ieee_i (foperand_b_i),
    .sign_o (operand_b_dec.sign),
    .exponent_o (operand_b_dec.exponent),
    .significand_o (operand_b_dec.significand),
    .is_normal_o (),
    .is_zero_o (operand_b_dec.is_zero),
    .is_subnormal_o (),
    .is_inf_o (operand_b_dec.is_inf),
    .is_nan_o (operand_b_dec.is_nan)
  );

  muntjac_fpu_normalize_from_ieee_multi #(
    .OutExpWidth (DecodedExpWidth),
    .OutSigWidth (DecodedSigWidth)
  ) decode_c (
    .double_i (decode_as_double),
    .ieee_i (foperand_c_i),
    .sign_o (operand_c_dec.sign),
    .exponent_o (operand_c_dec.exponent),
    .significand_o (operand_c_dec.significand),
    .is_normal_o (),
    .is_zero_o (operand_c_dec.is_zero),
    .is_subnormal_o (),
    .is_inf_o (operand_c_dec.is_inf),
    .is_nan_o (operand_c_dec.is_nan)
  );

  logic        i2f_signed;
  logic        i2f_dword;
  intermediate_fp_t i2f_out;
  assign i2f_out.is_inf = 1'b0;
  assign i2f_out.is_nan = 1'b0;

  muntjac_fpu_normalize_from_int_multi #(
    .OutExpWidth (IntermediateExpWidth),
    .OutSigWidth (IntermediateSigWidth)
  ) int_to_fp (
    .signed_i (i2f_signed),
    .dword_i (i2f_dword),
    .int_i (req_rs1_i),
    .resp_sign_o (i2f_out.sign),
    .resp_exponent_o (i2f_out.exponent),
    .resp_significand_o (i2f_out.significand),
    .resp_is_zero_o (i2f_out.is_zero)
  );

  // #endregion
  /////////////////////////////////

  ///////////////////////////
  // #region Compute Units //

  rounding_mode_e rm;
  decoded_fp_t dec_a;
  decoded_fp_t dec_b;
  decoded_fp_t dec_c;

  // FMA is slow so we give it 3 extra stages for pipelining.
  logic fma_in_valid, fma_out_valid_q, fma_out_valid_q2;
  logic fma_out_flag_invalid, fma_out_flag_invalid_q, fma_out_flag_invalid_q2;
  intermediate_fp_t fma_out, fma_out_q, fma_out_q2;

  muntjac_fpu_mul_add #(
    .InExpWidth (DecodedExpWidth),
    .InSigWidth (DecodedSigWidth),
    .OutExpWidth (IntermediateExpWidth),
    .OutSigWidth (IntermediateSigWidth)
  ) fma_unit (
    .rounding_mode_i (rm),
    .a_sign_i (dec_a.sign),
    .a_exponent_i (dec_a.exponent),
    .a_significand_i (dec_a.significand),
    .a_is_zero_i (dec_a.is_zero),
    .a_is_inf_i (dec_a.is_inf),
    .a_is_nan_i (dec_a.is_nan),
    .b_sign_i (dec_b.sign),
    .b_exponent_i (dec_b.exponent),
    .b_significand_i (dec_b.significand),
    .b_is_zero_i (dec_b.is_zero),
    .b_is_inf_i (dec_b.is_inf),
    .b_is_nan_i (dec_b.is_nan),
    .c_sign_i (dec_c.sign),
    .c_exponent_i (dec_c.exponent),
    .c_significand_i (dec_c.significand),
    .c_is_zero_i (dec_c.is_zero),
    .c_is_inf_i (dec_c.is_inf),
    .c_is_nan_i (dec_c.is_nan),
    .resp_invalid_operation_o (fma_out_flag_invalid),
    .resp_sign_o (fma_out.sign),
    .resp_exponent_o (fma_out.exponent),
    .resp_significand_o (fma_out.significand),
    .resp_is_zero_o (fma_out.is_zero),
    .resp_is_inf_o (fma_out.is_inf),
    .resp_is_nan_o (fma_out.is_nan)
  );

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      fma_out_valid_q <= 1'b0;
      fma_out_valid_q2 <= 1'b0;
      fma_out_flag_invalid_q <= 1'bx;
      fma_out_flag_invalid_q2 <= 1'bx;
      fma_out_q <= 'x;
      fma_out_q2 <= 'x;
    end else begin
      fma_out_valid_q <= fma_in_valid;
      fma_out_valid_q2 <= fma_out_valid_q;
      fma_out_flag_invalid_q <= fma_out_flag_invalid;
      fma_out_flag_invalid_q2 <= fma_out_flag_invalid_q;
      fma_out_q <= fma_out;
      fma_out_q2 <= fma_out_q;
    end
  end

  logic div_in_valid;
  logic div_in_sqrt;
  logic div_out_valid;
  logic div_out_flag_invalid;
  logic div_out_flag_infinite;
  intermediate_fp_t div_out;

  muntjac_fpu_div_sqrt #(
    .InExpWidth (DecodedExpWidth),
    .InSigWidth (DecodedSigWidth),
    .OutExpWidth (IntermediateExpWidth),
    .OutSigWidth (IntermediateSigWidth)
  ) div_unit (
    .clk_i,
    .rst_ni,
    .req_ready_o (),
    .req_valid_i (div_in_valid),
    .sqrt_i (div_in_sqrt),
    .a_sign_i (dec_a.sign),
    .a_exponent_i (dec_a.exponent),
    .a_significand_i (dec_a.significand),
    .a_is_zero_i (dec_a.is_zero),
    .a_is_inf_i (dec_a.is_inf),
    .a_is_nan_i (dec_a.is_nan),
    .b_sign_i (dec_b.sign),
    .b_exponent_i (dec_b.exponent),
    .b_significand_i (dec_b.significand),
    .b_is_zero_i (dec_b.is_zero),
    .b_is_inf_i (dec_b.is_inf),
    .b_is_nan_i (dec_b.is_nan),
    .resp_valid_o (div_out_valid),
    .resp_invalid_operation_o (div_out_flag_invalid),
    .resp_divide_by_zero_o (div_out_flag_infinite),
    .resp_sign_o (div_out.sign),
    .resp_exponent_o (div_out.exponent),
    .resp_significand_o (div_out.significand),
    .resp_is_zero_o (div_out.is_zero),
    .resp_is_inf_o (div_out.is_inf),
    .resp_is_nan_o (div_out.is_nan)
  );

  logic compare_signaling;
  logic compare_lt;
  logic compare_eq;
  logic compare_invalid_operation;

  muntjac_fpu_compare #(
    .ExpWidth (DecodedExpWidth),
    .SigWidth (DecodedSigWidth)
  ) compare_unit (
    .a_sign_i (dec_a.sign),
    .a_exponent_i (dec_a.exponent),
    .a_significand_i (dec_a.significand),
    .a_is_zero_i (dec_a.is_zero),
    .a_is_inf_i (dec_a.is_inf),
    .a_is_nan_i (dec_a.is_nan),
    .b_sign_i (dec_b.sign),
    .b_exponent_i (dec_b.exponent),
    .b_significand_i (dec_b.significand),
    .b_is_zero_i (dec_b.is_zero),
    .b_is_inf_i (dec_b.is_inf),
    .b_is_nan_i (dec_b.is_nan),
    .signaling_i (compare_signaling),
    .lt_o (compare_lt),
    .eq_o (compare_eq),
    .unordered_o (),
    .invalid_operation_o (compare_invalid_operation)
  );

  // Min-max logic.

  logic minmax_max;
  decoded_fp_t minmax_result;

  always_comb begin
    if (dec_a.is_nan && dec_b.is_nan) begin
      minmax_result = DEC_NAN;
    end else if (dec_a.is_nan) begin
      minmax_result = dec_b;
    end else if (dec_b.is_nan) begin
      minmax_result = dec_a;
    end else if (compare_eq) begin
      // We must treat -0 to be less than +0 per spec.
      minmax_result = minmax_max == dec_a.sign ? dec_b : dec_a;
    end else begin
      minmax_result = minmax_max == compare_lt ? dec_b : dec_a;
    end
  end

  // #endregion
  ///////////////////////////

  /////////////////////////////////
  // #region Rounding and Output //


  logic round_invalid_operation;
  logic round_divide_by_zero;
  logic round_use_nan_payload;
  logic round_use_double;
  intermediate_fp_t dec_round;
  exception_flags_t round_out_flags;
  logic [63:0] round_out_ieee;

  muntjac_fpu_round_to_ieee_multi #(
    .InExpWidth (IntermediateExpWidth),
    .InSigWidth (IntermediateSigWidth)
  ) round_double (
    .invalid_operation_i (round_invalid_operation),
    .divide_by_zero_i (round_divide_by_zero),
    .use_nan_payload_i (round_use_nan_payload),
    .double_i (round_use_double),
    .is_zero_i (dec_round.is_zero),
    .is_inf_i (dec_round.is_inf),
    .is_nan_i (dec_round.is_nan),
    .sign_i (dec_round.sign),
    .exponent_i (dec_round.exponent),
    .significand_i (dec_round.significand),
    .rounding_mode_i (rm),
    .ieee_o (round_out_ieee),
    .exception_o (round_out_flags)
  );

  logic f2i_signed;
  logic f2i_dword;
  logic [63:0] f2i_out;
  exception_flags_t f2i_flags;

  muntjac_fpu_round_to_int_multi #(
    .InExpWidth (DecodedExpWidth),
    .InSigWidth (DecodedSigWidth)
  ) fp_to_int (
    .rounding_mode_i (rm),
    .signed_i (f2i_signed),
    .dword_i (f2i_dword),
    .sign_i (dec_a.sign),
    .exponent_i (dec_a.exponent),
    .significand_i (dec_a.significand),
    .is_zero_i (dec_a.is_zero),
    .is_inf_i (dec_a.is_inf),
    .is_nan_i (dec_a.is_nan),
    .int_o (f2i_out),
    .exception_o (f2i_flags)
  );

  // #ednregion
  /////////////////////////////////

  typedef enum logic [2:0] {
    // Idle
    StateIdle,
    // FMA stages active
    StateFma,
    // Divider active
    StateDiv,
    // Other non-expensive tasks:
    // * Compare/Min/Max
    // * Sign manipulation
    // * Conversion
    StateMisc,
    // Rounding, common to FMA/DIV/MISC tasks.
    // Some may bypass this stage.
    StateRound
  } state_e;

  state_e state_q = StateIdle, state_d;

  fp_op_t op_q, op_d;
  logic op_double_q, op_double_d;

  rounding_mode_e rm_d;
  decoded_fp_t dec_a_d;
  decoded_fp_t dec_b_d;
  decoded_fp_t dec_c_d;

  logic in_valid_q, in_valid_d;

  logic round_flag_invalid_d;
  logic round_divide_by_zero_d;
  logic round_use_nan_payload_d;
  intermediate_fp_t dec_round_d;

  logic output_valid_d;
  logic [63:0] output_value_d;
  exception_flags_t output_flags_d;

  always_comb begin
    state_d = state_q;
    op_d = op_q;
    op_double_d = op_double_q;
    rm_d = rm;
    dec_a_d = dec_a;
    dec_b_d = dec_b;
    dec_c_d = dec_c;
    in_valid_d = in_valid_q;
    round_flag_invalid_d = round_invalid_operation;
    round_divide_by_zero_d = round_divide_by_zero;
    round_use_nan_payload_d = round_use_nan_payload;
    dec_round_d = dec_round;
    output_value_d = resp_value_o;
    output_flags_d = resp_flags_o;
    output_valid_d = 1'b0;

    req_ready_o = 1'b0;
    decode_as_double = 1'bx;
    i2f_signed = 1'bx;
    i2f_dword = 1'bx;
    fma_in_valid = 1'b0;
    div_in_valid = 1'b0;
    div_in_sqrt = 1'b0;
    compare_signaling = 1'bx;
    minmax_max = 1'bx;
    f2i_signed = 1'bx;
    f2i_dword = 1'bx;
    round_use_double = 1'bx;

    unique case (state_q)
      StateIdle: begin
        req_ready_o = 1'b1;

        if (req_valid_i) begin
          op_d = req_op_i;
          op_double_d = req_double_i;
          decode_as_double = req_double_i;
          rm_d = req_rm_i;
          dec_a_d = operand_a_dec;
          dec_b_d = operand_b_dec;
          dec_c_d = operand_c_dec;
          in_valid_d = 1'b1;
          round_flag_invalid_d = 1'b0;
          round_divide_by_zero_d = 1'b0;
          round_use_nan_payload_d = 1'b0;
          output_flags_d = '0;

          unique case (req_op_i.op_type)
            FP_OP_ADDSUB: begin
              state_d = StateFma;
              dec_c_d = dec_b_d;
              dec_b_d = DEC_ONE;

              if (req_op_i.param[0]) begin
                dec_c_d.sign = !dec_c_d.sign;
              end
            end
            FP_OP_MUL: begin
              state_d = StateFma;
              dec_c_d = DEC_ZERO;

              // Use the same sign as product, so that a * b + 0 == a * b
              dec_c_d.sign = dec_a_d.sign ^ dec_b_d.sign;
            end
            FP_OP_FMA: begin
              state_d = StateFma;

              if (req_op_i.param[0]) begin
                dec_c_d.sign = !dec_c_d.sign;
              end

              if (req_op_i.param[1]) begin
                dec_a_d.sign = !dec_a_d.sign;
              end
            end
            FP_OP_DIVSQRT: begin
              state_d = StateDiv;
            end
            FP_OP_CMP: state_d = StateMisc;
            FP_OP_CLASS: begin
              state_d = StateIdle;
              output_valid_d = 1'b1;
              output_value_d = {
                54'd0,
                operand_a_dec.is_nan && operand_a_dec.significand[DecodedSigWidth-1],
                operand_a_dec.is_nan && !operand_a_dec.significand[DecodedSigWidth-1],
                !operand_a_dec.sign && operand_a_dec.is_inf,
                !operand_a_dec.sign && operand_a_dec_is_normal,
                !operand_a_dec.sign && operand_a_dec_is_subnormal,
                !operand_a_dec.sign && operand_a_dec.is_zero,
                operand_a_dec.sign && operand_a_dec.is_zero,
                operand_a_dec.sign && operand_a_dec_is_subnormal,
                operand_a_dec.sign && operand_a_dec_is_normal,
                operand_a_dec.sign && operand_a_dec.is_inf
              };
            end
            FP_OP_CVT_F2F: begin
              // For float-to-float format conversion we'll need to revert the flag.
              // as req_double_i indicates the output format.
              decode_as_double = !req_double_i;
              state_d = StateMisc;
            end
            FP_OP_SGNJ: begin
              state_d = StateMisc;
              // SGNJ is the only instruction that requires NaN payload to be preserved.
              round_use_nan_payload_d = 1'b1;
            end
            FP_OP_MV_I2F: begin
              state_d = StateIdle;
              output_valid_d = 1'b1;
              output_value_d = req_double_i ? req_rs1_i : {32'hffffffff, req_rs1_i[31:0]};
            end
            FP_OP_MV_F2I: begin
              state_d = StateIdle;
              output_valid_d = 1'b1;
              output_value_d = req_double_i ? foperand_a_i : {{32{foperand_a_i[31]}}, foperand_a_i[31:0]};
            end
            FP_OP_CVT_F2I: state_d = StateMisc;
            FP_OP_CVT_I2F: begin
              i2f_signed = req_op_i.param inside {FP_PARAM_W, FP_PARAM_L};
              i2f_dword = req_op_i.param inside {FP_PARAM_L, FP_PARAM_LU};
              state_d = StateRound;
              dec_round_d = i2f_out;
            end
            default: state_d = StateMisc;
          endcase
        end
      end
      StateFma: begin
        in_valid_d = 1'b0;
        fma_in_valid = in_valid_q;

        if (fma_out_valid_q2) begin
          state_d = StateRound;
          round_flag_invalid_d = fma_out_flag_invalid_q2;
          dec_round_d = fma_out_q2;
        end
      end
      StateDiv: begin
        in_valid_d = 1'b0;
        div_in_valid = in_valid_q;
        div_in_sqrt = op_q.param == FP_PARAM_SQRT;

        if (div_out_valid) begin
          state_d = StateRound;
          round_flag_invalid_d = div_out_flag_invalid;
          round_divide_by_zero_d = div_out_flag_infinite;
          dec_round_d = div_out;
        end
      end
      StateMisc: begin
        compare_signaling = op_q.op_type == FP_OP_CMP && op_q.param != FP_PARAM_EQ;
        minmax_max = op_q.param == FP_PARAM_MAX;
        f2i_signed = op_q.param inside {FP_PARAM_W, FP_PARAM_L};
        f2i_dword = op_q.param inside {FP_PARAM_L, FP_PARAM_LU};

        unique case (op_q.op_type)
          FP_OP_CMP: begin
            state_d = StateIdle;
            output_valid_d = 1'b1;
            unique case (op_q.param)
              FP_PARAM_EQ: output_value_d = {63'd0, compare_eq};
              FP_PARAM_LT: output_value_d = {63'd0, compare_lt};
              FP_PARAM_LE: output_value_d = {63'd0, compare_eq || compare_lt};
              default: output_value_d = 'x;
            endcase
            output_flags_d = {compare_invalid_operation, 4'b0};
          end
          FP_OP_MINMAX: begin
            state_d = StateRound;
            dec_round_d.is_nan = minmax_result.is_nan;
            dec_round_d.is_inf = minmax_result.is_inf;
            dec_round_d.is_zero = minmax_result.is_zero;
            dec_round_d.sign = minmax_result.sign;
            dec_round_d.exponent = IntermediateExpWidth'(minmax_result.exponent);
            dec_round_d.significand = {minmax_result.significand, 2'b00};

            // MINMAX will not output NaN even when compare_invalid_operation is set,
            // so don't pass to rounder.
            output_flags_d = {compare_invalid_operation, 4'b0};
          end
          FP_OP_CVT_F2F: begin
            state_d = StateRound;
            // Raise invalid operation flag is the value converted is a signaling NaN.
            round_flag_invalid_d = dec_a.is_nan && !dec_a.significand[DecodedSigWidth-1];
            round_divide_by_zero_d = 1'b0;
            dec_round_d.is_nan = dec_a.is_nan;
            dec_round_d.is_inf = dec_a.is_inf;
            dec_round_d.is_zero = dec_a.is_zero;
            dec_round_d.sign = dec_a.sign;
            dec_round_d.exponent = IntermediateExpWidth'(dec_a.exponent);
            dec_round_d.significand = {dec_a.significand, 2'b00};
          end
          FP_OP_SGNJ: begin
            state_d = StateRound;
            dec_round_d.is_nan = dec_a.is_nan;
            dec_round_d.is_inf = dec_a.is_inf;
            dec_round_d.is_zero = dec_a.is_zero;
            dec_round_d.exponent = IntermediateExpWidth'(dec_a.exponent);
            dec_round_d.significand = {dec_a.significand, 2'b00};
            unique case (op_q.param)
              FP_PARAM_SGNJ: dec_round_d.sign = dec_b.sign;
              FP_PARAM_SGNJN: dec_round_d.sign = ~dec_b.sign;
              FP_PARAM_SGNJX: dec_round_d.sign = dec_a.sign ^ dec_b.sign;
              default: dec_round_d.sign = 1'bx;
            endcase
          end
          FP_OP_CVT_F2I: begin
            state_d = StateIdle;
            output_valid_d = 1'b1;
            output_value_d = f2i_out;
            output_flags_d = f2i_flags;
          end
          default:;
        endcase
      end
      StateRound: begin
        round_use_double = op_double_q;
        state_d = StateIdle;
        output_valid_d = 1'b1;
        output_value_d = round_out_ieee;
        // Minmax may set flags already, so OR it instead of overwrite it.
        output_flags_d = resp_flags_o | round_out_flags;
      end
      default:;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= StateIdle;
      op_q <= fp_op_t'('x);
      op_double_q <= 1'bx;
      rm <= rounding_mode_e'('x);
      dec_a <= 'x;
      dec_b <= 'x;
      dec_c <= 'x;
      in_valid_q <= 1'b0;
      round_invalid_operation <= 1'b0;
      round_divide_by_zero <= 1'b0;
      round_use_nan_payload <= 1'b0;
      dec_round <= 'x;
      resp_value_o <= 'x;
      resp_flags_o <= 'x;
      resp_valid_o <= 1'b0;
    end else begin
      state_q <= state_d;
      op_q <= op_d;
      op_double_q <= op_double_d;
      rm <= rm_d;
      dec_a <= dec_a_d;
      dec_b <= dec_b_d;
      dec_c <= dec_c_d;
      in_valid_q <= in_valid_d;
      round_invalid_operation <= round_flag_invalid_d;
      round_divide_by_zero <= round_divide_by_zero_d;
      round_use_nan_payload <= round_use_nan_payload_d;
      dec_round <= dec_round_d;
      resp_value_o <= output_value_d;
      resp_flags_o <= output_flags_d;
      resp_valid_o <= output_valid_d;
    end
  end

endmodule
