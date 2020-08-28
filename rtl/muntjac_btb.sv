module muntjac_btb import muntjac_pkg::*; #(
    parameter int unsigned AddrLen    = 64,
    parameter int unsigned IndexWidth = 8
) (
    input  logic               clk_i,
    input  logic               rst_ni,

    input  logic               train_valid_i,
    input  branch_type_e       train_branch_type_i,
    input  logic [AddrLen-1:0] train_pc_i,
    input  logic [AddrLen-1:0] train_npc_i,

    input  logic               access_valid_i,
    input  logic [AddrLen-1:0] access_pc_i,
    output logic               access_hit_o,
    output branch_type_e       access_branch_type_o,
    output logic [AddrLen-1:0] access_npc_o
);

    localparam TagWidth = AddrLen - IndexWidth - 1;

    typedef struct packed {
        logic [TagWidth-1:0] tag;
        logic [AddrLen-2:0]  target;
        branch_type_e        branch_type;
    } btb_entry_t;

    btb_entry_t mem [0:2 ** IndexWidth - 1];

     // Ensure memory has value so we don't produce X
    initial begin
        for (int i = 0; i < 2 ** IndexWidth; i++) begin
            mem[i] = '0;
        end
    end

    /////////////////
    // Train Logic //
    /////////////////

    wire [IndexWidth-1:0] train_index = train_pc_i[1 +: IndexWidth];
    wire [TagWidth-1:0]   train_tag   = train_pc_i[1 + IndexWidth +: TagWidth];

    always @(posedge clk_i) begin
        if (rst_ni && train_valid_i) begin
            mem[train_index] <= btb_entry_t'{
                train_tag,
                train_npc_i[AddrLen-1:1],
                train_branch_type_i
            };
        end
    end

    //////////////////
    // Access Logic //
    //////////////////

    wire [IndexWidth-1:0] access_index = access_pc_i[1 +: IndexWidth];
    wire [TagWidth-1:0]   access_tag   = access_pc_i[1 + IndexWidth +: TagWidth];

    btb_entry_t entry;
    logic [TagWidth-1:0] access_tag_q;

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            entry <= '0;
            access_tag_q <= '1;
        end else begin
            if (access_valid_i) begin
                entry <= mem[access_index];
                access_tag_q <= access_tag;
            end
        end
    end

    always_comb begin
        access_hit_o = entry.tag == access_tag_q;
        access_npc_o = {entry.target, 1'b0};
        access_branch_type_o = entry.branch_type;
    end

endmodule
