module muntjac_instr_align import muntjac_pkg::*; # (
  parameter OutWidth = 1
) (
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
  output logic           [OutWidth-1:0] aligned_valid_o,
  output fetched_instr_t [OutWidth-1:0] aligned_instr_o
);

  // Muntjac I$ only need to handle aligned memory accesses, but the instruction stream does not
  // have to be aligned. This module will shape the unaligned instruction hword-stream and output
  // instructions stream with boundaries separated.
  //
  // To do so, we need to handle instructions spanning two input words.
  //
  // The full window covers two words (minus one hword):
  // Previously fetched word
  //       \_________/
  //              Newly fetched word
  //                 \_________/
  //       +---------+---------+
  //       |////|    |    |    |
  //       +---------+---------+
  //         ^ the first hword of previous fetched word is definitely processed already, so no need to store
  //                 ^ the PC of this window will point here
  //
  // The + nodes denoted above are aligned to input words, so PC of the window will also do.

  localparam InputSize = 2;
  localparam BufferSize = InputSize - 1;
  localparam WindowSize = BufferSize + InputSize;
  localparam IndexWidth = $clog2(WindowSize + 1);
  localparam InputIndexWidth = $clog2(InputSize + 1);
  localparam BufferIndexWidth = $clog2(BufferSize + 1);

  logic [BufferSize-1:0][15:0] buffer_q, buffer_d;
  logic [BufferIndexWidth-1:0] buffer_start_idx_q, buffer_start_idx_d;
  logic [BufferIndexWidth-1:0] buffer_end_idx_q, buffer_end_idx_d;

  // PC at the end of buffer (so when buffer is used this is equal to PC of the combined window).
  logic [63:0] buffer_pc_q, buffer_pc_d;
  // IF reason code for the first hword in the buffer.
  if_reason_e buffer_reason_q, buffer_reason_d;

  // Checks if the buffer contains any hwords.
  wire buffer_empty = buffer_start_idx_q == buffer_end_idx_q;

  // Checks if buffer is empty enough so that we cannot produce anything without
  // taking inputs.
  // TODO: BufferSize != 1?
  wire buffer_instr_empty = buffer_start_idx_q == buffer_end_idx_q || buffer_q[0][1:0] == 2'b11;

  // Checks if buffer is full enough so that we cannot take more inputs.
  // TODO: BufferSize != 1?
  wire buffer_instr_full = OutWidth == 1 ? buffer_start_idx_q != buffer_end_idx_q && buffer_q[0][1:0] != 2'b11 : 1'b0;

  // TODO: InputSize != 2?
  wire [InputIndexWidth-1:0] input_start_idx = unaligned_strb_i[0] ? 0 : 1;
  wire [InputIndexWidth-1:0] input_end_idx = unaligned_strb_i[1] ? 2 : 1;
  wire [63:0] input_pc = unaligned_pc_i &~ 3;

  // Determine whether buffer or input should be used.
  logic use_buffer;
  logic use_input;

  always_comb begin
    use_buffer = 1'b0;
    use_input = 1'b0;
    if (unaligned_valid_i && unaligned_reason_i[0]) begin
      // A redirection happens, ignore about content in the buffer.
      use_buffer = 1'b0;
      use_input = 1'b1;
    end else if (unaligned_valid_i && !unaligned_exception_i && unaligned_reason_i ==? IF_PREFETCH) begin
      // Prefetched data, can combine with buffer.
      // Use input if buffer is not already full.
      use_buffer = 1'b1;
      use_input = !buffer_instr_full;
    end else if (!buffer_instr_empty) begin
      // A branch prediction or exception happens, we need to drain any full instructions left.
      use_buffer = 1'b1;
      use_input = 1'b0;
    end else if (unaligned_valid_i && unaligned_exception_i && unaligned_reason_i ==? IF_PREFETCH) begin
      // Exception during prefetch. Keep buffer to ensure PC calculation is correct.
      use_buffer = 1'b1;
      use_input = 1'b1;
    end else if (unaligned_valid_i) begin
      // Branch prediction happens. Discard the buffer.
      use_buffer = 1'b0;
      use_input = 1'b1;
    end else begin
      use_buffer = 1'b1;
      use_input = 1'b0;
    end
  end

  // Aggregate information for the window.
  wire [WindowSize-1:0][15:0] window_instr = {unaligned_instr_i, buffer_q};
  logic [IndexWidth-1:0] window_start_idx;
  logic [IndexWidth-1:0] window_end_idx;
  logic [63:0] window_pc;
  logic window_exception;
  if_reason_e window_reason;

  always_comb begin
    window_start_idx = use_buffer ? IndexWidth'(buffer_start_idx_q) : input_start_idx + BufferSize;
    window_end_idx = use_input ? input_end_idx + BufferSize : IndexWidth'(buffer_end_idx_q);

    if (use_input) begin
      window_pc = input_pc;
      window_exception = unaligned_exception_i;
    end else begin
      window_pc = buffer_pc_q;
      window_exception = 1'b0;
    end

    if (use_buffer && !buffer_empty) begin
      window_reason = buffer_reason_q;
    end else begin
      window_reason = unaligned_reason_i;
    end
  end

  // Compute the length of instructions. This part does not handle exceptions.

  // Length of the separated instruction (in hwords). Will be 0 if no full instruction can be found.
  logic [OutWidth:0][IndexWidth-1:0] insn_idx;
  logic [OutWidth-1:0][1:0]          insn_length;

  always_comb begin
    insn_idx[0] = window_start_idx;
    for (int i = 0; i < OutWidth; i++) begin
      if (insn_idx[i] == window_end_idx) begin
        // Window is empty
        insn_length[i] = 0;
      end else if (window_instr[insn_idx[i]][1:0] != 2'b11) begin
        // 1-hword instruction.
        insn_length[i] = 1;
      end else if (window_end_idx == insn_idx[i] + 1) begin
        // 2-hword instruction, but we don't have second hword valid.
        insn_length[i] = 0;
      end else begin
        // 2-hword instruction.
        insn_length[i] = 2;
      end
      insn_idx[i + 1] = insn_idx[i] + insn_length[i];
    end
  end

  always_comb begin
    buffer_start_idx_d = buffer_start_idx_q;
    buffer_end_idx_d = buffer_end_idx_q;
    buffer_d = buffer_q;
    buffer_pc_d = buffer_pc_q;
    buffer_reason_d = buffer_reason_q;
    unaligned_ready_o = 1'b0;

    aligned_valid_o = '0;
    aligned_instr_o = 'x;
    for (int i = 0; i < OutWidth; i++) aligned_instr_o[i].ex_valid = 1'b0;

    if (window_exception) begin
      aligned_valid_o[0] = 1'b1;
      aligned_instr_o[0].pc = window_pc + (64'(insn_idx[0]) - BufferSize) * 2;
      aligned_instr_o[0].if_reason = window_reason;
      aligned_instr_o[0].ex_valid = 1'b1;
      aligned_instr_o[0].exception.cause = unaligned_ex_code_i;
      aligned_instr_o[0].exception.tval = window_pc + input_start_idx * 2;

      // In case of exception, buffer is cleared.
      if (aligned_ready_i) begin
        buffer_start_idx_d = 1;
        buffer_end_idx_d = 1;
        unaligned_ready_o = 1'b1;
      end
    end else begin
      for (int i = 0; i < OutWidth; i++) begin
        aligned_valid_o[i] = insn_length[i] != 0;
        aligned_instr_o[i].pc = window_pc + (64'(insn_idx[i]) - BufferSize) * 2;
        aligned_instr_o[i].if_reason = i == 0 ? window_reason : IF_PREFETCH;
        aligned_instr_o[i].instr_word = {
          insn_length[i] == 1 ? 16'd0 : window_instr[insn_idx[i] + 1],
          window_instr[insn_idx[i]]
        };
      end

      if (insn_length[0] == 0 || aligned_ready_i) begin
        if (insn_length[0] != 0) begin
          // If anything is decoded, then the leftover must be IF_PREFETCH.
          buffer_reason_d = IF_PREFETCH;
        end else begin
          // Otherwise we have to keep window_reason.
          buffer_reason_d = window_reason;
        end

        if (use_input) begin
          // If input is being used, the buffer will be shifted.
          buffer_d = window_instr[InputSize +: BufferSize];
          buffer_start_idx_d = BufferIndexWidth'(insn_idx[OutWidth] - IndexWidth'(InputSize));
          buffer_end_idx_d = BufferIndexWidth'(input_end_idx - IndexWidth'(InputSize - BufferSize));
          buffer_pc_d = input_pc + InputSize * 2;
          unaligned_ready_o = 1'b1;
        end else begin
          // Otherwise the buffer should not change.
          buffer_start_idx_d = BufferIndexWidth'(insn_idx[OutWidth]);
        end
      end
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      buffer_start_idx_q <= BufferIndexWidth'(BufferSize);
      buffer_end_idx_q <= BufferIndexWidth'(BufferSize);
      buffer_q <= 'x;
      buffer_reason_q <= if_reason_e'('x);
      buffer_pc_q <= 'x;
    end else begin
      buffer_start_idx_q <= buffer_start_idx_d;
      buffer_end_idx_q <= buffer_end_idx_d;
      buffer_q <= buffer_d;
      buffer_pc_q <= buffer_pc_d;
      buffer_reason_q <= buffer_reason_d;
    end
  end

endmodule
