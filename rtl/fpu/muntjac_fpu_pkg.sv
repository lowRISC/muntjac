package muntjac_fpu_pkg;

localparam SingleExpWidth = 8;
localparam SingleSigWidth = 23;
localparam DoubleExpWidth = 11;
localparam DoubleSigWidth = 52;

typedef enum logic [2:0] {
  RoundTiesToEven     = 3'b000,
  RoundTowardZero     = 3'b001,
  RoundTowardNegative = 3'b010,
  RoundTowardPositive = 3'b011,
  RoundTiesToAway     = 3'b100
} rounding_mode_e;

typedef struct packed {
  logic invalid_operation;
  logic divide_by_zero;
  logic overflow;
  logic underflow;
  logic inexact;
} exception_flags_t;

endpackage
