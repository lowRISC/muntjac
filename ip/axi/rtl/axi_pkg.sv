package axi_pkg;

typedef enum logic [1:0] {
  BURST_FIXED = 2'b00,
  BURST_INCR  = 2'b01,
  BURST_WRAP  = 2'b10
} axi_burst_t;

typedef logic [3:0] axi_cache_t;
localparam CACHE_BUFFERABLE     = 4'b0001;
localparam CACHE_MODIFIABLE     = 4'b0010;
localparam CACHE_OTHER_ALLOCATE = 4'b0100;
localparam CACHE_ALLOCATE       = 4'b1000;

typedef logic [2:0] axi_prot_t;
localparam PROT_PRIVILEGED  = 3'b001;
localparam PROT_SECURE      = 3'b010;
localparam PROT_INSTRUCTION = 3'b100;

typedef enum logic [1:0] {
  RESP_OKAY   = 2'b00,
  RESP_EXOKAY = 2'b01,
  RESP_SLVERR = 2'b10,
  RESP_DECERR = 2'b11
} axi_resp_t;

endpackage
