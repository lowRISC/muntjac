module muntjac_tlb import muntjac_pkg::*; #(
  parameter int unsigned NumEntry = 32,
  parameter int unsigned AsidLen  = 16,
  parameter int unsigned PhysAddrLen = 56,
  localparam int unsigned VirtAddrLen = 39
) (
    input  logic                    clk_i,
    input  logic                    rst_ni,

    input  logic [63:0]             satp_i,

    // TLB Lookup Request (Pulse)
    input  logic                    req_valid_i,
    input  logic [VirtAddrLen-13:0] req_vpn_i,

    // TLB Lookup Response (Pulse)
    output logic                    resp_valid_o,
    output logic [PhysAddrLen-13:0] resp_ppn_o,
    output page_prot_t              resp_perm_o,

    // TLB Flush Request and Response (Pulses)
    input  logic                    flush_req_i,
    output logic                    flush_resp_o,

    // PTW Request
    input  logic                    ptw_req_ready_i,
    output logic                    ptw_req_valid_o,
    output logic [VirtAddrLen-13:0] ptw_req_vpn_o,

    // PTW Response (Pulse)
    input  logic                    ptw_resp_valid_i,
    input  logic [PhysAddrLen-13:0] ptw_resp_ppn_i,
    input  page_prot_t              ptw_resp_perm_i
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
                (entries[i].asid == satp_i[44 +: AsidLen] || entries[i].prot.is_global);
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

  ///////////////////////
  // TLB Miss Handling //
  ///////////////////////

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      ptw_req_vpn_o <= 'x;
      ptw_req_valid_o <= 1'b0;
    end else begin
      // Clear valid signal on handshake
      if (ptw_req_ready_i) ptw_req_valid_o <= 1'b0;

      if (req_valid_i) begin
        ptw_req_vpn_o <= req_vpn_i;
        if (!hit) begin
          ptw_req_valid_o <= 1'b1;
        end
      end
    end
  end 

  ////////////////
  // TLB Refill //
  ////////////////

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
        if (ptw_resp_valid_i && repl_index == i) begin
          entries[i] <= tlb_entry_t'{
            ptw_resp_perm_i,
            ptw_req_vpn_o,
            satp_i[44 +: AsidLen],
            ptw_resp_ppn_i
          };
        end
        if (flush_req_i) begin
          entries[i].prot.valid <= 1'b0;
        end
      end
      if (ptw_resp_valid_i) begin
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

  // When the TLB is not hit, the miss logic will send a request to PTW.
  // When PTW sends back its response, we both add it to the TLB and forward to our requestor.
  assign resp_valid_o = hit_q ? 1'b1       : ptw_resp_valid_i;
  assign resp_ppn_o   = hit_q ? hit_ppn_q  : ptw_resp_ppn_i;
  assign resp_perm_o  = hit_q ? hit_perm_q : ptw_resp_perm_i;

endmodule
