module muntjac_fpu_right_shift #(
  parameter DataWidth = 1,
  parameter ShiftWidth = 1
) (
  input  logic [DataWidth-1:0] data_i,
  input  logic [ShiftWidth-1:0] shift_i,
  output logic [DataWidth-1:0] data_o
);

  logic [DataWidth-1:0] residual;
  for (genvar i = 0; i < DataWidth; i++) begin
    assign residual[i] = |data_i[i:0];
  end

  wire [$clog2(DataWidth)-1:0] shift_bounded = shift_i[$clog2(DataWidth)-1:0];

  assign data_o =
    shift_i >= ShiftWidth'(DataWidth) ? {{(DataWidth-1){1'b0}}, residual[DataWidth-1]}
                                      : {data_i[DataWidth-1:1] >> shift_bounded, residual[shift_bounded]};

endmodule
