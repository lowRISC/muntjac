// Register file.
// This register file does not implement any data bypassing/forwarding.
module reg_file # (
    parameter XLEN = 64
) (
    // Clock and reset
    input  logic               clk,
    input  logic               rstn,

    // Read port A
    input  logic [4:0]         ra_sel,
    output logic [XLEN-1:0]    ra_data,

    // Read port B
    input  logic [4:0]         rb_sel,
    output logic [XLEN-1:0]    rb_data,

    // Write port
    input  logic [4:0]         w_sel,
    input  logic [XLEN-1:0]    w_data,
    input  logic               w_en
);

    bit [XLEN-1:0] registers [1:31];

    // Read ports
    assign ra_data = ra_sel == 0 ? 0 : registers[ra_sel];
    assign rb_data = rb_sel == 0 ? 0 : registers[rb_sel];

    // Write port
    always_ff @(posedge clk) begin
        if (w_en)
            registers[w_sel] <= w_data;
    end

endmodule
