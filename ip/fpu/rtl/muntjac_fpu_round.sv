module muntjac_fpu_round import muntjac_fpu_pkg::*; (
  input  rounding_mode_e rounding_mode_i,
  input  logic sign_i,
  input  logic [2:0] significand_i,

  output logic inexact_o,
  output logic roundup_o
);

  // For rounding we only need to look at the last two bits.
  // Let a be the first bit beyond target precision, and b be the second bit.
  // In operations that cannot produce accurate result we use the last bit (b) to denote whether
  // there are any remainder, so
  // * If a=0, b=0, then the remainder is 0.
  // * If a=0, b=1, then the remainder is in range (0, 0.5)
  // * If a=1, b=0, then the remainder is 0.5.
  // * If a=1, b=1, then the remainder is in range (0.5, 1).
  // Combine a, b and target rounding mode we can therefore decide on how to round.

  always_comb begin
    inexact_o = 1'b0;
    roundup_o = 1'b0;

    if (significand_i[1:0] != 0) begin
      inexact_o = 1'b1;

      unique case (rounding_mode_i)
        RoundTiesToEven: begin
          roundup_o = significand_i[1:0] == 2'b11 || significand_i == 3'b110;
        end
        RoundTowardZero:;
        RoundTowardNegative: begin
          roundup_o = sign_i && significand_i[1:0] != 2'b00;
        end
        RoundTowardPositive: begin
          roundup_o = !sign_i && significand_i[1:0] != 2'b00;
        end
        RoundTiesToAway: begin
          roundup_o = significand_i[1] == 1'b1;
        end
        default:;
      endcase
    end
  end

endmodule
