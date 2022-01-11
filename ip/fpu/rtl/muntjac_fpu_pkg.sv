package muntjac_fpu_pkg;

//////////////////////////////////////
// Floating-point related constants //
//////////////////////////////////////

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

////////////////////////////////
// Decoded floating point ops //
////////////////////////////////

// Floating-point operation types
typedef enum logic [3:0] {
  FP_OP_ADDSUB,
  FP_OP_MUL,
  FP_OP_DIVSQRT,
  FP_OP_SGNJ,
  FP_OP_MINMAX,
  FP_OP_CVT_F2F,
  FP_OP_CVT_I2F,
  FP_OP_CVT_F2I,
  FP_OP_MV_I2F,
  FP_OP_MV_F2I,
  FP_OP_CLASS,
  FP_OP_CMP,
  FP_OP_FMA
} fp_op_e;

// Floating-point operations
typedef struct packed {
  fp_op_e op_type;
  logic [1:0] param;
} fp_op_t;

// Parameter for FP_OP_SGNJ
parameter FP_PARAM_SGNJ  = 2'b00;
parameter FP_PARAM_SGNJN = 2'b01;
parameter FP_PARAM_SGNJX = 2'b10;

// Parameter for FP_OP_MINMAX
parameter FP_PARAM_MIN = 2'b00;
parameter FP_PARAM_MAX = 2'b01;

// Parameter for FP_OP_CMP
parameter FP_PARAM_LE = 2'b00;
parameter FP_PARAM_LT = 2'b01;
parameter FP_PARAM_EQ = 2'b10;

// Parameter for FP_OP_DIVSQRT
parameter FP_PARAM_DIV  = 2'b00;
parameter FP_PARAM_SQRT = 2'b01;

// Parameter for FP_OP_ADDSUB
parameter FP_PARAM_ADD = 2'b00;
parameter FP_PARAM_SUB = 2'b01;

// Parameter for FP_OP_FMA
parameter FP_PARAM_MADD = 2'b00;
parameter FP_PARAM_MSUB = 2'b01;
parameter FP_PARAM_NMSUB = 2'b10;
parameter FP_PARAM_NMADD = 2'b11;

// Parameter for FP_OP_CVT_I2F, FP_OP_CVT_F2I
parameter FP_PARAM_W = 2'b00;
parameter FP_PARAM_WU = 2'b01;
parameter FP_PARAM_L = 2'b10;
parameter FP_PARAM_LU = 2'b11;

endpackage
