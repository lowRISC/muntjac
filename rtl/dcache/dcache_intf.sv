import cpu_common::*;

// Interfacing to the data cache
interface dcache_intf #(
    parameter XLEN = 64
) (
    input  logic clk,
    input  logic rstn
);
    logic            req_valid;
    logic            req_ready;
    logic [XLEN-1:0] req_address;
    // Value to be stored or to be used in AMO operation.
    logic [XLEN-1:0] req_value;
    // Type of memory operation: LOAD, STORE, LR, SC, AMO
    mem_op_t         req_op;
    // Size of access. This must only be 2'b10 and 2'b11 when req_op is LR, SC or AMO.
    logic [1:0]      req_size;
    // Whether the load should be unsigned. Relevant only when req_op is LOAD.
    logic            req_unsigned;
    // When req_op is MEM_AMO, this dictate the type and ordering requirement of the AMO op.
    // This specifies the ordering requirement for LR and SC operation.
    logic [6:0]      req_amo;
    // Address translation related properties.
    logic            req_prv;
    logic            req_sum;
    logic            req_mxr;
    logic [XLEN-1:0] req_atp;

    logic            resp_valid;
    logic [XLEN-1:0] resp_value;
    exception_t      resp_exception;

    // Notification on SFENCE.VMA
    logic            notif_valid;
    // 1'b0 -> SATP changed, 1'b1 -> SFENCE.VMA
    logic            notif_reason;
    logic            notif_ready;

    modport provider (
        input  clk,
        input  rstn,

        input  req_valid,
        output req_ready,

        input  req_address,
        input  req_value,
        input  req_op,
        input  req_size,
        input  req_unsigned,
        input  req_amo,
        input  req_prv,
        input  req_sum,
        input  req_mxr,
        input  req_atp,

        output resp_valid,
        output resp_value,
        output resp_exception,

        input  notif_valid,
        input  notif_reason,
        output notif_ready
    );

    modport user (
        input  clk,
        input  rstn,

        output req_valid,
        input  req_ready,

        output req_address,
        output req_value,
        output req_op,
        output req_size,
        output req_unsigned,
        output req_amo,
        output req_prv,
        output req_sum,
        output req_mxr,
        output req_atp,

        input  resp_valid,
        input  resp_value,
        input  resp_exception,

        output notif_valid,
        output notif_reason,
        input  notif_ready
    );

endinterface
