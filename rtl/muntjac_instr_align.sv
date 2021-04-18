module muntjac_instr_align import muntjac_pkg::*; (
  input  logic           clk_i,
  input  logic           rst_ni,

  output logic           unaligned_ready_o,
  input  logic           unaligned_valid_i,
  input  logic [63:0]    unaligned_pc_i,
  input  logic           unaligned_exception_i,
  input  exc_cause_e     unaligned_ex_code_i,
  input  if_reason_e     unaligned_reason_i,
  input  logic [1:0]     unaligned_strb_i,
  input  logic [31:0]    unaligned_instr_i,

  input  logic           aligned_ready_i,
  output logic           aligned_valid_o,
  output fetched_instr_t aligned_instr_o
);

  logic prev_valid_q, prev_valid_d;
  logic [63:0] prev_pc_q;
  if_reason_e prev_reason_q, prev_reason_d;
  logic [15:0] prev_instr_q;

  logic second_half_q, second_half_d;

  always_comb begin
    prev_valid_d = prev_valid_q;
    unaligned_ready_o = 1'b0;
    second_half_d = second_half_q;
    prev_reason_d = IF_PREFETCH;

    aligned_valid_o = 1'b0;
    aligned_instr_o.instr_word = 'x;
    aligned_instr_o.pc = 'x;
    aligned_instr_o.if_reason = if_reason_e'('x);
    aligned_instr_o.ex_valid = 1'b0;
    aligned_instr_o.exception.cause = exc_cause_e'('x);
    aligned_instr_o.exception.tval = 'x;

    if (unaligned_valid_i && unaligned_exception_i) begin
      prev_valid_d = 1'b0;

      aligned_valid_o = 1'b1;
      aligned_instr_o.pc = prev_valid_q && unaligned_reason_i ==? IF_PREFETCH ? prev_pc_q : unaligned_pc_i;
      aligned_instr_o.if_reason = prev_valid_q && unaligned_reason_i ==? IF_PREFETCH ? prev_reason_q : unaligned_reason_i;
      aligned_instr_o.ex_valid = 1'b1;
      aligned_instr_o.exception.cause = unaligned_ex_code_i;
      aligned_instr_o.exception.tval = unaligned_pc_i;

      if (aligned_ready_i) unaligned_ready_o = 1'b1;
    end else if (unaligned_valid_i && unaligned_strb_i == 2'b10 && unaligned_instr_i[17:16] == 2'b11) begin
      // A redirection fetches unaligned 32-bit instruction. Keep the higher half,
      // discard the lower half, without waiting for the aligned_ready_i signal.
      prev_valid_d = 1'b1;
      second_half_d = 1'b0;
      prev_reason_d = unaligned_reason_i;

      unaligned_ready_o = 1'b1;
    end else if (unaligned_valid_i) begin
      if (aligned_ready_i) begin
        prev_valid_d = 1'b0;
        second_half_d = 1'b0;
      end

      if (unaligned_strb_i == 2'b10 || second_half_q) begin
        // Misaligned compressed instruction.
        aligned_valid_o = 1'b1;
        aligned_instr_o.pc = {unaligned_pc_i[63:2], 2'b10};
        aligned_instr_o.if_reason = second_half_q ? IF_PREFETCH : unaligned_reason_i;
        aligned_instr_o.instr_word = {16'd0, unaligned_instr_i[31:16]};

        if (aligned_ready_i) unaligned_ready_o = 1'b1;
      end else begin
        if (prev_valid_q && unaligned_reason_i ==? IF_PREFETCH) begin
          // If there is a half word left (and we can use it), then this is the second half
          // of a misaligned 32-bit instruction.
          aligned_valid_o = 1'b1;
          aligned_instr_o.pc = prev_pc_q;
          aligned_instr_o.if_reason = prev_reason_q;
          aligned_instr_o.instr_word = {unaligned_instr_i[15:0], prev_instr_q};

          // If the second half is also a 32-bit instruction, fetch the next word.
          if (aligned_ready_i) begin
            prev_valid_d = 1'b1;

            if (unaligned_instr_i[17:16] == 2'b11 || unaligned_strb_i == 2'b01) begin
              unaligned_ready_o = 1'b1;
            end else begin
              second_half_d = 1'b1;
            end
          end
        end else begin
          if (unaligned_instr_i[1:0] == 2'b11) begin
            // Full instruction, output it.
            aligned_valid_o = 1'b1;
            aligned_instr_o.pc = unaligned_pc_i;
            aligned_instr_o.if_reason = unaligned_reason_i;
            aligned_instr_o.instr_word = unaligned_instr_i;

            if (aligned_ready_i) unaligned_ready_o = 1'b1;
          end else begin
            // Compressed instruction, output it.
            aligned_valid_o = 1'b1;
            aligned_instr_o.pc = unaligned_pc_i;
            aligned_instr_o.if_reason = unaligned_reason_i;
            aligned_instr_o.instr_word = {16'd0, unaligned_instr_i[15:0]};

            if (aligned_ready_i) begin
              prev_valid_d = 1'b1;

              if (unaligned_instr_i[17:16] == 2'b11 || unaligned_strb_i == 2'b01) begin
                // The second half is not compressed instruction, fetch next word
                unaligned_ready_o = 1'b1;
              end else begin
                second_half_d = 1'b1;
              end
            end
          end
        end
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      prev_valid_q <= 1'b0;
      second_half_q <= 1'b0;
      prev_instr_q <= 'x;
      prev_reason_q <= if_reason_e'('x);
      prev_pc_q <= 'x;
    end else begin
      prev_valid_q <= prev_valid_d;
      second_half_q <= second_half_d;
      if (unaligned_ready_o) begin
        prev_instr_q <= unaligned_instr_i[31:16];
        prev_pc_q <= {unaligned_pc_i[63:2], 2'b10};
        prev_reason_q <= prev_reason_d;
      end
    end
  end

endmodule
