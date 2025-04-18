module muntjac_tlb import muntjac_pkg::*; #(
  parameter int unsigned NumWays = 32,
  parameter int unsigned SetsWidth = 0,
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

  localparam WaysWidth = $clog2(NumWays);

  if (WaysWidth == 0) $fatal(1, "Direct-mapped caches are not supported");

  typedef struct packed {
    page_prot_t                        prot;
    logic [VirtAddrLen-SetsWidth-13:0] vpn;
    logic [AsidLen-1:0]                asid;
    logic [PhysAddrLen-13:0]           ppn;
  } tlb_entry_t;

  if (SetsWidth == 0) begin: fully_assoc

    tlb_entry_t [NumWays-1:0] entries;

    //////////////////////////////////
    // Fully associative TLB lookup //
    //////////////////////////////////

    logic [NumWays-1:0] hits;
    logic               hit;
    tlb_entry_t         hit_entry;

    // Parallel hit check
    always_comb begin
      for (int i = 0; i < NumWays; i++) begin
        hits[i] = entries[i].prot.valid &&
                  entries[i].vpn == req_vpn_i &&
                  (entries[i].asid == req_asid_i || entries[i].prot.is_global);
      end
    end

    always_comb begin
      hit = 1'b0;
      hit_entry = tlb_entry_t'('x);
      for (int i = 0; i < NumWays; i++) begin
        if (hits[i]) begin
          hit = 1'b1;
          hit_entry = entries[i];
        end
      end
    end

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

    assign resp_hit_o  = hit_q;
    assign resp_ppn_o  = hit_ppn_q;
    assign resp_perm_o = hit_perm_q;

    //////////////////////////
    // TLB Refill and Flush //
    //////////////////////////

    logic [WaysWidth-1:0] repl_index;

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        repl_index <= 0;
        for (int i = 0; i < NumWays; i++) begin
          entries[i] <= tlb_entry_t'('x);
          entries[i].prot.valid <= 1'b0;
        end
      end else begin
        for (int i = 0; i < NumWays; i++) begin
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
          repl_index <= repl_index == NumWays - 1 ? 0 : repl_index + 1;
        end
      end
    end

  end else begin: set_assoc

    ////////////////////////
    // SRAM Instantiation //
    ////////////////////////

    logic                 read_req;
    logic [SetsWidth-1:0] read_addr;
    tlb_entry_t           read_rdata[NumWays];

    logic                 write_req;
    logic [SetsWidth-1:0] write_addr;
    tlb_entry_t           write_wdata;
    logic [NumWays-1:0]   write_ways;

    for (genvar i = 0; i < NumWays; i++) begin

      prim_ram_1r1w #(
        .Width           ($bits(tlb_entry_t)),
        .Depth           (2 ** SetsWidth),
        .DataBitsPerMask ($bits(tlb_entry_t))
      ) tag_ram (
        .clk_a_i   (clk_i),
        .clk_b_i   (clk_i),
        .a_req_i   (write_req && write_ways[i]),
        .a_addr_i  (write_addr),
        .a_wdata_i (write_wdata),
        .a_wmask_i ('1),
        .b_req_i   (read_req),
        .b_addr_i  (read_addr),
        .b_rdata_o (read_rdata[i]),
        .cfg_i     ('0)
      );

    end

    ////////////////
    // TLB lookup //
    ////////////////

    logic [AsidLen-1:0]                asid_q, asid_d;
    logic [VirtAddrLen-SetsWidth-13:0] vpn_q, vpn_d;

    logic [NumWays-1:0] hits;
    logic               hit;
    tlb_entry_t         hit_entry;

    // Parallel hit check
    always_comb begin
      for (int i = 0; i < NumWays; i++) begin
        hits[i] = read_rdata[i].prot.valid &&
                  read_rdata[i].vpn == vpn_q &&
                  (read_rdata[i].asid == asid_q || read_rdata[i].prot.is_global);
      end
    end

    always_comb begin
      hit = 1'b0;
      hit_entry = tlb_entry_t'('x);
      for (int i = 0; i < NumWays; i++) begin
        if (hits[i]) begin
          hit = 1'b1;
          hit_entry = read_rdata[i];
        end
      end
    end

    always_comb begin
      read_req = 1'b0;
      read_addr = 'x;

      asid_d = asid_q;
      vpn_d = vpn_q;

      if (req_valid_i) begin
        read_req = 1'b1;
        read_addr = req_vpn_i[SetsWidth-1:0];

        asid_d = req_asid_i;
        vpn_d = req_vpn_i[VirtAddrLen-13:SetsWidth];
      end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        asid_q <= 0;
        vpn_q <= 0;
      end else begin
        asid_q <= asid_d;
        vpn_q <= vpn_d;
      end
    end

    assign resp_hit_o  = hit;
    assign resp_ppn_o  = hit_entry.ppn;
    assign resp_perm_o = hit_entry.prot;

    //////////////////////////
    // TLB Refill and Flush //
    //////////////////////////

    logic                 flushing_q, flushing_d;
    logic [SetsWidth-1:0] flush_index_q, flush_index_d;
    logic [WaysWidth-1:0] repl_index_q, repl_index_d;

    always_comb begin
      flushing_d = flushing_q;
      flush_index_d = flush_index_q;
      repl_index_d = repl_index_q;

      write_req = 1'b0;
      write_addr = 'x;
      write_ways = '0;
      write_wdata = tlb_entry_t'('x);

      flush_resp_o = 1'b0;

      if (flushing_q) begin
        write_req = 1'b1;
        write_addr = flush_index_q;
        write_ways = '1;
        write_wdata.prot.valid = 1'b0;

        flush_index_d = flush_index_q + 1;
        if (&flush_index_q) begin
          flushing_d = 1'b0;
          flush_resp_o = 1'b1;
        end
      end else begin
        unique case (1'b1)
          flush_req_i: begin
            flushing_d = 1'b1;
          end
          refill_valid_i: begin
            repl_index_d = repl_index_q == NumWays - 1 ? 0 : repl_index_q + 1;

            write_req = 1'b1;
            write_addr = refill_vpn_i[SetsWidth-1:0];
            write_ways[repl_index_q] = 1'b1;
            write_wdata = tlb_entry_t'{
              refill_perm_i,
              refill_vpn_i[VirtAddrLen-13:SetsWidth],
              refill_asid_i,
              refill_ppn_i
            };
          end
          default:;
        endcase
      end
    end

    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        flushing_q <= 1'b0;
        flush_index_q <= 0;
        repl_index_q <= '0;
      end else begin
        flushing_q <= flushing_d;
        flush_index_q <= flush_index_d;
        repl_index_q <= repl_index_d;
      end
    end

  end

endmodule
