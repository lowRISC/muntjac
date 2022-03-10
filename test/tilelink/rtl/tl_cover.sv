// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

module tl_cover import tl_pkg::*; #(
    parameter  tl_protocol_e Protocol     = TL_C,
    parameter                EndpointType = "Device", // Or "Host"
    parameter  int unsigned  AddrWidth    = 56,
    parameter  int unsigned  DataWidth    = 64,
    parameter  int unsigned  SinkWidth    = 1,
    parameter  int unsigned  SourceWidth  = 1
) (
  input logic clk_i,
  input logic rst_ni,
  `TL_DECLARE_TAP_PORT(DataWidth, AddrWidth, SourceWidth, SinkWidth, tl)
);

  // Some duplication from tl_assert here to gather the required state.
  /*verilator coverage_off*/

  // Current and previous states.
  `TL_DECLARE(DataWidth, AddrWidth, SourceWidth, SinkWidth, tl);
  `TL_DECLARE(DataWidth, AddrWidth, SourceWidth, SinkWidth, prev_tl);

  // The last beats from each channel to be accepted/declined.
  `TL_DECLARE(DataWidth, AddrWidth, SourceWidth, SinkWidth, prev_accepted);
  `TL_DECLARE(DataWidth, AddrWidth, SourceWidth, SinkWidth, prev_declined);

  // Capture the last accepted/declined beats from a named channel.
  `define CAPTURE_ACCEPTED_DECLINED(CHANNEL)                    \
    if (tl_``CHANNEL``_valid) begin                             \
      prev_accepted_``CHANNEL``_valid <= tl_``CHANNEL``_ready;  \
      prev_declined_``CHANNEL``_valid <= !tl_``CHANNEL``_ready; \
                                                                \
      if (tl_``CHANNEL``_ready) begin                           \
        prev_accepted_``CHANNEL`` <= tl_``CHANNEL``;            \
      end else begin                                            \
        prev_declined_``CHANNEL`` <= tl_``CHANNEL``;            \
      end                                                       \
    end

  always_ff @(posedge clk_i) begin
    `TL_ASSIGN_NB_FROM_TAP(tl, tl);
    `TL_ASSIGN_NB(prev_tl, tl);

    `CAPTURE_ACCEPTED_DECLINED(a);
    `CAPTURE_ACCEPTED_DECLINED(b);
    `CAPTURE_ACCEPTED_DECLINED(c);
    `CAPTURE_ACCEPTED_DECLINED(d);
    `CAPTURE_ACCEPTED_DECLINED(e);
  end

  `undef CAPTURE_ACCEPTED_DECLINED
  /*verilator coverage_on*/

  // TODO: focus on non-continuous matches, i.e. the first beat of each message.

  // Back-to-back messages are sent on a channel
  // TODO: multibeat messages shouldn't count
  `define BACK_TO_BACK(CHANNEL) \
    `SEQUENCE(``CHANNEL``BackToBack_S, \
      prev_tl_``CHANNEL``_valid && prev_tl_``CHANNEL``_ready && tl_``CHANNEL``_valid \
    ); \
    `S_COVER(``CHANNEL``BackToBack_C, ``CHANNEL``BackToBack_S)

  // A valid signal is deasserted before it is accepted by the recipient.
  `define VALID_NOT_ACCEPTED(CHANNEL) \
    `SEQUENCE(``CHANNEL``ValidNotAccepted_S, \
      prev_tl_``CHANNEL``_valid && !prev_tl_``CHANNEL``_ready && !tl_``CHANNEL``_valid \
    ); \
    `S_COVER(``CHANNEL``ValidNotAccepted_C, ``CHANNEL``ValidNotAccepted_S)
  
  // Content is changed without being accepted.
  `define CHANGED_WITHOUT_ACCEPTED(CHANNEL, NAME) \
    `SEQUENCE(``CHANNEL``_``NAME``ChangedNotAccepted_S, \
      tl_``CHANNEL``_valid && prev_declined_``CHANNEL``_valid && \
      prev_declined_``CHANNEL``.``NAME`` != tl_``CHANNEL``.``NAME`` \
    ); \
    `S_COVER(``CHANNEL``_``NAME``ChangedNotAccepted_C, ``CHANNEL``_``NAME``ChangedNotAccepted_S)

  // Consecutive messages on the same channel use the same value.
  // TODO: multibeat messages shouldn't count.
  `define CONSECUTIVE_MESSAGES_REPEAT(CHANNEL, NAME) \
    `SEQUENCE(``CHANNEL``_``NAME``Repeated_S, \
      tl_``CHANNEL``_valid && prev_accepted_``CHANNEL``_valid && \
      tl_``CHANNEL``.``NAME`` == prev_accepted_``CHANNEL``.``NAME`` \
    ); \
    `S_COVER(``CHANNEL``_``NAME``Repeated_C, ``CHANNEL``_``NAME``Repeated_S)
  
  // Check that the `corrupt` bit is used.
  `define CORRUPT_BIT_USED(CHANNEL) \
    `S_COVER(``CHANNEL``Corrupt_C, tl_``CHANNEL``.corrupt)

  // Check that the `denied` bit is used.
  `define DENIED_BIT_USED(CHANNEL) \
    `S_COVER(``CHANNEL``Denied_C, tl_``CHANNEL``.denied)
  
  // For every channel as a whole, we would like to see:
  //   * Back-to-back messages (no period where valid is low)
  //   * Valid messages being deasserted before they have been accepted
  `define STANDARD_CHANNEL_COVERAGE(CHANNEL) \
    `BACK_TO_BACK(CHANNEL) \
    `VALID_NOT_ACCEPTED(CHANNEL)
  
  // For every field of every channel, we would like to see:
  //   * The value {changes, stays the same} in consecutive messages
  //   * The value {changes, stays the same} while waiting to be accepted
  `define STANDARD_FIELD_COVERAGE(CHANNEL, NAME) \
    `CONSECUTIVE_MESSAGES_REPEAT(CHANNEL, NAME) \
    `CHANGED_WITHOUT_ACCEPTED(CHANNEL, NAME)

  `STANDARD_CHANNEL_COVERAGE(a)
  `STANDARD_FIELD_COVERAGE(a, opcode)
  `STANDARD_FIELD_COVERAGE(a, param)
  `STANDARD_FIELD_COVERAGE(a, size)
  `STANDARD_FIELD_COVERAGE(a, source)
  `STANDARD_FIELD_COVERAGE(a, address)
  `STANDARD_FIELD_COVERAGE(a, mask)
  `STANDARD_FIELD_COVERAGE(a, corrupt)
  `STANDARD_FIELD_COVERAGE(a, data)
  `CORRUPT_BIT_USED(a)

  `STANDARD_CHANNEL_COVERAGE(d)
  `STANDARD_FIELD_COVERAGE(d, opcode)
  `STANDARD_FIELD_COVERAGE(d, param)
  `STANDARD_FIELD_COVERAGE(d, size)
  `STANDARD_FIELD_COVERAGE(d, source)
  `STANDARD_FIELD_COVERAGE(d, sink)
  `STANDARD_FIELD_COVERAGE(d, denied)
  `STANDARD_FIELD_COVERAGE(d, corrupt)
  `STANDARD_FIELD_COVERAGE(d, data)
  `CORRUPT_BIT_USED(d)
  `DENIED_BIT_USED(d)

  if (Protocol == TL_C) begin : gen_tlc_channel_cov
    `STANDARD_CHANNEL_COVERAGE(b)
    `STANDARD_FIELD_COVERAGE(b, opcode)
    `STANDARD_FIELD_COVERAGE(b, param)
    `STANDARD_FIELD_COVERAGE(b, size)
    `STANDARD_FIELD_COVERAGE(b, source)
    `STANDARD_FIELD_COVERAGE(b, address)

    `STANDARD_CHANNEL_COVERAGE(c)
    `STANDARD_FIELD_COVERAGE(c, opcode)
    `STANDARD_FIELD_COVERAGE(c, param)
    `STANDARD_FIELD_COVERAGE(c, size)
    `STANDARD_FIELD_COVERAGE(c, source)
    `STANDARD_FIELD_COVERAGE(c, address)
    `STANDARD_FIELD_COVERAGE(c, corrupt)
    `STANDARD_FIELD_COVERAGE(c, data)
    `CORRUPT_BIT_USED(c)

    `STANDARD_CHANNEL_COVERAGE(e)
    `STANDARD_FIELD_COVERAGE(e, sink)
  end

  `undef BACK_TO_BACK
  `undef VALID_NOT_ACCEPTED
  `undef CHANGED_WITHOUT_ACCEPTED
  `undef CONSECUTIVE_MESSAGES_REPEAT
  `undef CORRUPT_BIT_USED
  `undef DENIED_BIT_USED
  `undef STANDARD_CHANNEL_COVERAGE
  `undef STANDARD_FIELD_COVERAGE


  // Look for simultaneous messages on all combinations of channels.
  // Covergroups aren't supported by Verilator, so pack values into a signal
  // instead.
  logic [1:0] tluh_accepted;  // Also TL-UL.
  logic [4:0] tlc_accepted;

  `define ACCEPTED(CHANNEL) tl_``CHANNEL``_valid && tl_``CHANNEL``_ready

  assign tlc_accepted =  {`ACCEPTED(a), `ACCEPTED(b), `ACCEPTED(c),
                          `ACCEPTED(d), `ACCEPTED(e)};
  assign tluh_accepted = {`ACCEPTED(a), `ACCEPTED(d)};

  `undef ACCEPTED

  // TODO: current macro can't accept multibit properties.
  if (Protocol == TL_C) begin : gen_tlc_simultaneous_cov
    //`S_COVER(tlc_simultaneous, tlc_accepted);
  end else begin : gen_tluh_simultaneous_cov
    //`S_COVER(tluh_simultaneous, tluh_accepted);
  end

endmodule


bind tl_assert tl_cover #(
  .Protocol (Protocol),
  .EndpointType (EndpointType),
  .AddrWidth (AddrWidth),
  .DataWidth (DataWidth),
  .SinkWidth (SinkWidth),
  .SourceWidth (SourceWidth)
) coverage (
  .clk_i,
  .rst_ni,
  `TL_FORWARD_TAP_PORT(tl, tl)
);
