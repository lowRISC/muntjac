module muntjac_fpu_normalize #(
  parameter DataWidth = 1,
  localparam ShiftWidth = $clog2(DataWidth)
) (
  input  logic [DataWidth-1:0] data_i,
  output logic is_zero_o,
  output logic [ShiftWidth-1:0] shift_o,
  output logic [DataWidth-1:0] data_o
);

  // To normalize the number, we need to know number of leading zeros.
  // First we reverse the number and then we only need to calculate number of trailing zeroes.

  logic [DataWidth-1:0] data_reversed;
  always_comb begin
    for (int i = 0; i < DataWidth; i++) begin
      data_reversed[i] = data_i[DataWidth - 1 - i];
    end
  end

  // Extract the lowest set bit of data_reversed. This is the bit hack version for it.
  wire [DataWidth-1:0] data_reversed_lsb = data_reversed & (-data_reversed);

  // Now since we know that there are at most one bit set in data_reversed_lsb, we can find
  // out the index of that bit in parallel (note that that bit index is precisely number of
  // leading zeroes for data_i).
  always_comb begin
    shift_o = '0;
    for (int i = 0; i < DataWidth; i++) begin
      shift_o |= data_reversed_lsb[i] ? ShiftWidth'(i) : 0;
    end
  end

  assign data_o = data_i << shift_o;
  assign is_zero_o = data_i == 0;

endmodule
