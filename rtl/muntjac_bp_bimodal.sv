module muntjac_bp_bimodal import muntjac_pkg::*; #(
    parameter int unsigned AddrLen    = 64,
    parameter int unsigned IndexWidth = 8
) (
    input  logic               clk_i,
    input  logic               rst_ni,

    input  logic               train_valid_i,
    input  logic               train_taken_i,
    input  logic [AddrLen-1:0] train_pc_i,

    input  logic               access_valid_i,
    input  logic [AddrLen-1:0] access_pc_i,
    output logic               access_taken_o
);

    // Representation is:
    // 01 - Not Taken
    // 00 - Weak Not Taken
    // 10 - Weak Taken
    // 11 - Taken
    // We swap encoding of 00 and 01 so that all states are initially weakly not taken.

    logic [1:0] mem [0:2 ** IndexWidth - 1];

    // Ensure memory has value so we don't produce X
    initial begin
        for (int i = 0; i < 2 ** IndexWidth; i++) begin
            mem[i] = 2'b00;
        end
    end

    /////////////////
    // Train Logic //
    /////////////////

    function logic [1:0] train_state(input logic [1:0] state, input logic taken);
        unique case ({state, taken})
            3'b010: return 2'b01;
            3'b000: return 2'b01;
            3'b100: return 2'b00;
            3'b110: return 2'b10;
            3'b011: return 2'b00;
            3'b001: return 2'b10;
            3'b101: return 2'b11;
            3'b111: return 2'b11;
        endcase
    endfunction

    wire [IndexWidth-1:0] train_index = train_pc_i[1 +: IndexWidth];

    always @(posedge clk_i) begin
        if (rst_ni && train_valid_i) begin
            mem[train_index] <= train_state(mem[train_index], train_taken_i);
        end
    end

    //////////////////
    // Access Logic //
    //////////////////

    wire [IndexWidth-1:0] access_index = access_pc_i[1 +: IndexWidth];

    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            access_taken_o <= 1'b0;
        end else begin
            if (access_valid_i) begin
                access_taken_o <= mem[access_index][1];
            end
        end
    end

endmodule
