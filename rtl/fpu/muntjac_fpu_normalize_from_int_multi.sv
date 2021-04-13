module muntjac_fpu_normalize_from_int_multi #(
  parameter OutExpWidth = 9,
  parameter OutSigWidth = 23
) (
  input  logic signed_i,
  input  logic dword_i,
  input  logic [63:0] int_i,

  output logic resp_sign_o,
  output logic signed [OutExpWidth-1:0] resp_exponent_o,
  output logic signed [OutSigWidth-1:0] resp_significand_o,
  output logic resp_is_zero_o
);

  logic [63:0] input_int;
  always_comb begin
    if (dword_i) begin
      input_int = int_i;
    end else begin
      input_int = signed_i ? {{32{int_i[31]}}, int_i[31:0]} : {32'd0, int_i[31:0]};
    end
  end

  muntjac_fpu_normalize_from_int #(
    .OutExpWidth (OutExpWidth),
    .OutSigWidth (OutSigWidth)
  ) int_to_fp (
    .signed_i,
    .int_i (input_int),
    .resp_sign_o,
    .resp_exponent_o,
    .resp_significand_o,
    .resp_is_zero_o
  );

endmodule
