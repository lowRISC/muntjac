module muntjac_btb import muntjac_pkg::*; #(
    parameter int unsigned AddrLen    = 64,
    parameter int unsigned IndexWidth = 8
) (
    input  logic               clk_i,
    input  logic               rst_ni,

    input  logic               train_valid_i,
    input  branch_type_e       train_branch_type_i,
    input  logic [AddrLen-1:0] train_pc_i,
    input  logic               train_partial_i,
    input  logic [AddrLen-1:0] train_npc_i,

    input  logic               access_valid_i,
    input  logic [AddrLen-1:0] access_pc_i,
    output logic               access_hit_o,
    output branch_type_e       access_branch_type_o,
    output logic               access_partial_o,
    output logic [AddrLen-1:0] access_npc_o
);

  localparam TagWidth = AddrLen - IndexWidth - 2;

  typedef struct packed {
    logic [TagWidth-1:0] tag;
    logic                partial;
    logic [AddrLen-2:0]  target;
    branch_type_e        branch_type;
  } btb_entry_t;

  logic                  a_req;
  logic [IndexWidth-1:0] a_addr;
  btb_entry_t            a_data;
  logic                  b_req;
  logic [IndexWidth-1:0] b_addr;
  btb_entry_t            b_data;

  prim_generic_ram_2p #(
    .Width           ($bits(btb_entry_t)),
    .Depth           (2 ** IndexWidth),
    .DataBitsPerMask ($bits(btb_entry_t))
  ) mem (
    .clk_a_i   (clk_i),
    .clk_b_i   (clk_i),

    .a_req_i   (a_req),
    .a_write_i (1'b0),
    .a_addr_i  (a_addr),
    .a_wdata_i ('0),
    .a_wmask_i ('0),
    .a_rdata_o (a_data),

    .b_req_i   (b_req),
    .b_write_i (1'b1),
    .b_addr_i  (b_addr),
    .b_wdata_i (b_data),
    .b_wmask_i ('1),
    .b_rdata_o ()
  );

  /////////////////
  // Reset Logic //
  /////////////////

  logic reset_in_progress_q, reset_in_progress_d;
  logic [IndexWidth-1:0] reset_index_q, reset_index_d;

  always_comb begin
    reset_in_progress_d = reset_in_progress_q;
    reset_index_d = reset_index_q;

    if (reset_in_progress_q) begin
      reset_index_d = reset_index_q + 1;
      if (reset_index_d == 0) begin
        reset_in_progress_d = 1'b0;
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      reset_in_progress_q <= 1'b1;
      reset_index_q <= '0;
    end else begin
      reset_in_progress_q <= reset_in_progress_d;
      reset_index_q <= reset_index_d;
    end
  end

  /////////////////
  // Train Logic //
  /////////////////

  wire [IndexWidth-1:0] train_index = train_pc_i[2 +: IndexWidth];
  wire [TagWidth-1:0]   train_tag   = train_pc_i[2 + IndexWidth +: TagWidth];

  assign b_req = reset_in_progress_q ? 1'b1 : train_valid_i;
  assign b_addr = reset_in_progress_q ? reset_index_q : train_index;
  assign b_data = reset_in_progress_q ? '0 : btb_entry_t'{
      train_tag,
      train_partial_i,
      train_npc_i[AddrLen-1:1],
      train_branch_type_i
  };

  //////////////////
  // Access Logic //
  //////////////////

  wire [IndexWidth-1:0] access_index = access_pc_i[2 +: IndexWidth];
  wire [TagWidth-1:0]   access_tag   = access_pc_i[2 + IndexWidth +: TagWidth];

  assign a_req  = rst_ni && access_valid_i;
  assign a_addr = access_index;

  logic [TagWidth-1:0] access_tag_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      access_tag_q <= '1;
    end else begin
      if (access_valid_i) begin
        access_tag_q <= access_tag;
      end
    end
  end

  always_comb begin
    access_hit_o = a_data.tag == access_tag_q;
    access_branch_type_o = a_data.branch_type;
    access_partial_o = a_data.partial;
    access_npc_o = {a_data.target, 1'b0};
  end

endmodule
