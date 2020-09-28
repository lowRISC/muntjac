// Interfacing to the instruction cache
interface icache_intf #(
    parameter XLEN = 64
) (
    input  logic clk,
    input  logic rstn
);

    import muntjac_pkg::*;

    logic            req_valid;
    logic [XLEN-1:0] req_pc;
    if_reason_e      req_reason;
    // The following values are for address translation. Because they usually are fed directly from
    // CSR register file, when they are changed, pipeline should be flushed. This includes:
    // * Change MSTATUS's SUM bit via CSR read/write
    // * Change privilege level, i.e. trap, interrupt and eret
    // * Change address translation, i.e. change SATP and SFENCE.VMA
    logic            req_prv;
    logic            req_sum;
    logic [XLEN-1:0] req_atp;

    logic            resp_valid;
    logic [31:0]     resp_instr;
    // This tells whether exception happens during instruction fetch.
    logic            resp_exception;
    exc_cause_e      resp_ex_code;

    // A note on flow control: currently there are no flow control signals. The cache is expected
    // only to process one request at a time for now, and the output must be immediately consumed
    // as valid is high for single cycle per request.

    modport provider (
        input  clk,
        input  rstn,

        input  req_valid,
        input  req_pc,
        input  req_reason,
        input  req_prv,
        input  req_sum,
        input  req_atp,

        output resp_valid,
        output resp_instr,
        output resp_exception,
        output resp_ex_code
    );

    modport user (
        input  clk,
        input  rstn,

        output req_valid,
        output req_pc,
        output req_reason,
        output req_prv,
        output req_sum,
        output req_atp,

        input  resp_valid,
        input  resp_instr,
        input  resp_exception,
        input  resp_ex_code
    );

endinterface
