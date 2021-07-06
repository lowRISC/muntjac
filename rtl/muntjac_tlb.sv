module muntjac_tlb import muntjac_pkg::*; #(
  parameter int unsigned NumEntry = 32,
  parameter int unsigned AsidLen  = 16,
  parameter int unsigned PhysAddrLen = 56,
  localparam int unsigned VirtAddrLen = 39
) (
    input  logic                    clk_i,
    input  logic                    rst_ni,

    // TLB Lookup Request (Pulse)
    input  logic                    req_valid_i,
    input  logic [AsidLen-1:0]      req_asid_i,
    input  logic [VirtAddrLen-13:0] req_vpn_i,

    // TLB Lookup Response (Pulse)
    output logic                    resp_hit_o,
    output logic [PhysAddrLen-13:0] resp_ppn_o,
    output page_prot_t              resp_perm_o,

    // TLB Flush Request and Response (Pulses)
    input  logic                    flush_req_i,
    output logic                    flush_resp_o,

    // TLB Refill Request (Pulse)
    input  logic                    refill_valid_i,
    input  logic [AsidLen-1:0]      refill_asid_i,
    input  logic [VirtAddrLen-13:0] refill_vpn_i,
    input  logic [PhysAddrLen-13:0] refill_ppn_i,
    input  page_prot_t              refill_perm_i
);

  localparam IndexWidth = $clog2(NumEntry);

  typedef struct packed {
    page_prot_t              prot;
    logic [VirtAddrLen-13:0] vpn;
    logic [AsidLen-1:0]      asid;
    logic [PhysAddrLen-13:0] ppn;
  } tlb_entry_t;

  tlb_entry_t [NumEntry-1:0] entries;
  
  //////////////////////////////////
  // Fully associative TLB lookup //
  //////////////////////////////////

  logic [NumEntry-1:0] hits;
  logic                hit;
  tlb_entry_t          hit_entry;

  // Parallel hit check
  always_comb begin
    for (int i = 0; i < NumEntry; i++) begin
      hits[i] = entries[i].prot.valid &&
                entries[i].vpn == req_vpn_i &&
                (entries[i].asid == req_asid_i || entries[i].prot.is_global);
    end
  end

  always_comb begin
    hit = 1'b0;
    hit_entry = tlb_entry_t'('x);
    for (int i = 0; i < NumEntry; i++) begin
      if (hits[i]) begin
        hit = 1'b1;
        hit_entry = entries[i];
      end
    end
  end

  //////////////////////////
  // TLB Refill and Flush //
  //////////////////////////

  logic [IndexWidth-1:0] repl_index;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      repl_index <= 0;
      for (int i = 0; i < NumEntry; i++) begin
        entries[i] <= tlb_entry_t'('x);
        entries[i].prot.valid <= 1'b0;
      end
    end else begin
      for (int i = 0; i < NumEntry; i++) begin
        if (refill_valid_i && repl_index == i) begin
          entries[i] <= tlb_entry_t'{
            refill_perm_i,
            refill_vpn_i,
            refill_asid_i,
            refill_ppn_i
          };
        end
        if (flush_req_i) begin
          entries[i].prot.valid <= 1'b0;
        end
      end
      if (refill_valid_i) begin
        repl_index <= repl_index == NumEntry - 1 ? 0 : repl_index + 1;
      end
    end
  end

  ////////////
  // Output //
  ////////////

  logic hit_q;
  logic [PhysAddrLen-13:0] hit_ppn_q;
  page_prot_t hit_perm_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      flush_resp_o <= 1'b0;
      hit_q <= 1'b0;
      hit_ppn_q <= 'x;
      hit_perm_q <= page_prot_t'('x);
    end else begin
      flush_resp_o <= 1'b0;
      hit_q <= 1'b0;
      hit_ppn_q <= 'x;
      hit_perm_q <= page_prot_t'('x);

      if (req_valid_i) begin
        hit_q      <= hit;
        hit_ppn_q  <= hit_entry.ppn;
        hit_perm_q <= hit_entry.prot;
      end

      if (flush_req_i) flush_resp_o <= 1'b1;
    end
  end

  assign resp_hit_o   = hit_q;
  assign resp_ppn_o   = hit_ppn_q;
  assign resp_perm_o  = hit_perm_q;

endmodule
