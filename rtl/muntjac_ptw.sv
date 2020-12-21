module muntjac_ptw import muntjac_pkg::*; #(
  parameter int unsigned PhysAddrLen = 56,
  localparam int unsigned VirtAddrLen = 39
) (
    input  logic clk_i,
    input  logic rst_ni,

    input  logic [63:0] satp_i,

    input  logic                    req_valid_i,
    input  logic [VirtAddrLen-13:0] req_vpn_i,

    output logic                    resp_valid_o,
    output logic [PhysAddrLen-13:0] resp_ppn_o,
    output page_prot_t              resp_perm_o,

    // Memory interface
    input  logic                    mem_req_ready_i,
    output logic                    mem_req_valid_o,
    output logic [PhysAddrLen-1:0]  mem_req_address_o,
    input  logic                    mem_resp_valid_i,
    input  logic [63:0]             mem_resp_data_i
);

  typedef enum logic [2:0] {
    StateIdle,
    StateAtpL3,
    StateAtpL2,
    StateAtpL1,
    StateDone,
    StateException
  } state_e;

  state_e state_q = StateIdle, state_d;

  logic [VirtAddrLen-13:0] vpn_q, vpn_d;
  logic [PhysAddrLen-13:0] ppn_q, ppn_d;
  logic [7:0] perm_q, perm_d;

  // Memory request signals
  logic req_valid_q, req_valid_d;
  logic [PhysAddrLen-4:0] req_addr_q, req_addr_d;
  assign mem_req_valid_o = req_valid_q;
  assign mem_req_address_o = {req_addr_q, 3'd0};

  always_comb begin
    resp_valid_o = 1'b0;
    resp_perm_o = 'x;
    resp_ppn_o = 'x;

    state_d = state_q;
    vpn_d = vpn_q;
    ppn_d = ppn_q;
    perm_d = perm_q;
    req_valid_d = req_valid_q;
    req_addr_d = req_addr_q;

    unique case (state_q)
      StateIdle:;
      StateAtpL3: begin
        if (mem_req_ready_i) req_valid_d = 1'b0;

        if (mem_resp_valid_i) begin
          if (mem_resp_data_i[3:0] == 4'b0001) begin
            // Next-level page table
            req_valid_d = 1'b1;
            req_addr_d = {mem_resp_data_i[PhysAddrLen-3:10], vpn_q[17:9]};
            state_d = StateAtpL2;
          end
          else begin
            if (mem_resp_data_i[0] == 1'b0 || // Invalid
                mem_resp_data_i[3:1] == 3'b010 || mem_resp_data_i[3:1] == 3'b110 || // Illegal
                mem_resp_data_i[27:10] != 0) // LSBs not cleared
            begin
              perm_d[0] = 1'b0;
              state_d = StateDone;
            end
            else begin
              ppn_d = {mem_resp_data_i[PhysAddrLen-3:28], vpn_q[17:0]};
              perm_d = mem_resp_data_i[7:0];
              state_d = StateDone;
            end
          end
        end
      end
      StateAtpL2: begin
        if (mem_req_ready_i) req_valid_d = 1'b0;

        if (mem_resp_valid_i) begin
          if (mem_resp_data_i[3:0] == 4'b0001) begin
            // Next-level page table
            req_valid_d = 1'b1;
            req_addr_d = {mem_resp_data_i[PhysAddrLen-3:10], vpn_q[8:0]};
            state_d = StateAtpL1;
          end
          else begin
            if (mem_resp_data_i[0] == 1'b0 || // Invalid
                mem_resp_data_i[3:1] == 3'b010 || mem_resp_data_i[3:1] == 3'b110 || // Illegal
                mem_resp_data_i[18:10] != 0) // LSBs not cleared
            begin
              perm_d[0] = 1'b0;
              state_d = StateDone;
            end
            else begin
              ppn_d = {mem_resp_data_i[PhysAddrLen-3:19], vpn_q[8:0]};
              perm_d = mem_resp_data_i[7:0];
              state_d = StateDone;
            end
          end
        end
      end
      StateAtpL1: begin
        if (mem_req_ready_i) req_valid_d = 1'b0;

        if (mem_resp_valid_i) begin
          if (mem_resp_data_i[3:0] == 4'b0001 ||
              mem_resp_data_i[0] == 1'b0 || // Invalid
              mem_resp_data_i[3:1] == 3'b010 || mem_resp_data_i[3:1] == 3'b110) // Illegal
          begin
            perm_d[0] = 1'b0;
            state_d = StateDone;
          end
          else begin
            ppn_d = {mem_resp_data_i[PhysAddrLen-3:10]};
            perm_d = mem_resp_data_i[7:0];
            state_d = StateDone;
          end
        end
      end
      StateDone: begin
        resp_valid_o = 1'b1;
        resp_ppn_o = ppn_q;
        resp_perm_o.valid = perm_q[PTE_V_BIT] && perm_q[PTE_A_BIT];
        resp_perm_o.readable = perm_q[PTE_R_BIT];
        resp_perm_o.writable = perm_q[PTE_W_BIT] && perm_q[PTE_D_BIT];
        resp_perm_o.executable = perm_q[PTE_X_BIT];
        resp_perm_o.user = perm_q[PTE_U_BIT];
        resp_perm_o.is_global = perm_q[PTE_G_BIT];
        state_d = StateIdle;
      end
    endcase

    if (req_valid_i) begin
      vpn_d = req_vpn_i;
      req_valid_d = 1'b1;
      req_addr_d = {satp_i[PhysAddrLen-13:0], req_vpn_i[26:18]};
      state_d = StateAtpL3;
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= StateIdle;
      vpn_q <= 'x;
      req_valid_q <= 1'b0;
      req_addr_q <= '0;
      ppn_q <= 'x;
      perm_q <= 'x;
    end
    else begin
      state_q <= state_d;
      vpn_q <= vpn_d;
      req_valid_q <= req_valid_d;
      req_addr_q <= req_addr_d;
      ppn_q <= ppn_d;
      perm_q <= perm_d;
    end
  end

endmodule
