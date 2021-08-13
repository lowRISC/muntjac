package tl_pkg;

typedef enum logic [1:0] {
  TL_UL          = 2'h0,
  TL_UH          = 2'h1,
  TL_C           = 2'h2
} tl_protocol_e;

typedef enum logic [2:0] {
  PutFullData    = 3'h0,
  PutPartialData = 3'h1,
  ArithmeticData = 3'h2,
  LogicalData    = 3'h3,
  Get            = 3'h4,
  Intent         = 3'h5,
  AcquireBlock   = 3'h6,
  AcquirePerm    = 3'h7
} tl_a_op_e;

typedef enum logic [2:0] {
  // We does not support A messages being forwarded to B.
  ProbeBlock     = 3'h6,
  ProbePerm      = 3'h7
} tl_b_op_e;

typedef enum logic [2:0] {
  // We does not support C messages to be forwarded to D.
  ProbeAck     = 3'h4,
  ProbeAckData = 3'h5,
  Release      = 3'h6,
  ReleaseData  = 3'h7
} tl_c_op_e;

typedef enum logic [2:0] {
  AccessAck     = 3'h0,
  AccessAckData = 3'h1,
  HintAck       = 3'h2,
  Grant         = 3'h4,
  GrantData     = 3'h5,
  ReleaseAck    = 3'h6
} tl_d_op_e;

parameter logic [2:0]  toT = 0;
parameter logic [2:0]  toB = 1;
parameter logic [2:0]  toN = 2;

parameter logic [2:0] NtoB = 0;
parameter logic [2:0] NtoT = 1;
parameter logic [2:0] BtoT = 2;

parameter logic [2:0] TtoB = 0;
parameter logic [2:0] TtoN = 1;
parameter logic [2:0] BtoN = 2;

parameter logic [2:0] TtoT = 3;
parameter logic [2:0] BtoB = 4;
parameter logic [2:0] NtoN = 5;

endpackage
