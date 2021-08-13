// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

`ifndef VERILATOR
  `define SEQUENCE_SUPPORTED
`endif

`ifdef SEQUENCE_SUPPORTED
  `define SEQUENCE(NAME, EXPRESSION) \
    sequence NAME;                   \
      EXPRESSION;                    \
    endsequence
  `define IMPLIES(A, B) \
    ((A) |-> (B))
  `define AND and
  `define OR or
  `define NOT not
`else
  `define SEQUENCE(NAME, EXPRESSION) \
    logic NAME;                      \
    assign NAME = EXPRESSION
  `define IMPLIES(A, B) \
    ((A) ? (B) : '1)
  `define AND &&
  `define OR ||
  `define NOT !
`endif

`undef SEQUENCE_SUPPORTED

// We do not use lowRISC's recommended assertion macros as they disable
// assertions on Verilator. We instead use a Verilator-compatible subset of
// the SVA features.

// Synthesisable assert: an implementation of ASSERT which is always active.
// It is the user's responsibility to ensure the assertion is disabled when
// appropriate, and that any arguments are compatible with the simulation/
// synthesis platform.
// Note: use negedge clk to avoid possible race conditions

// Converts an arbitrary block of code into a Verilog string
`define PRIM_STRINGIFY(__x) `"__x`"

// ASSERT_RPT is available to change the reporting mechanism when an assert fails
`define ASSERT_RPT(__name)                                                  \
  $error("[ASSERT FAILED] [%m] %s (%s:%0d)", __name, `__FILE__, `__LINE__);

// TODO: make synthesisable

`define S_ASSERT(__name, __prop)                                                  \
  __name: assert property (@(negedge clk_i) disable iff (rst_ni === '0) (__prop)) \
    else begin                                                                    \
      `ASSERT_RPT(`PRIM_STRINGIFY(__name))                                        \
    end

`define S_ASSUME(__name, __prop)                                                  \
  __name: assert property (@(negedge clk_i) disable iff (rst_ni === '0) (__prop)) \
    else begin                                                                    \
      `ASSERT_RPT(`PRIM_STRINGIFY(__name))                                        \
    end

`define S_ASSERT_I(__name, __prop)         \
  __name: assert (__prop)                  \
    else begin                             \
      `ASSERT_RPT(`PRIM_STRINGIFY(__name)) \
    end

`define S_ASSERT_IF(__name, __prop, __enable) \
  `S_ASSERT(__name, `IMPLIES((__enable), (__prop)))

`define S_ASSERT_FINAL(__name, __prop)       \
  final begin                                \
    __name: assert (__prop)                  \
      else begin                             \
        `ASSERT_RPT(`PRIM_STRINGIFY(__name)) \
      end                                    \
  end

`define S_ASSERT_KNOWN(__name, __sig)   \
  `S_ASSERT(__name, !$isunknown(__sig))

`define S_ASSERT_KNOWN_IF(__name, __sig, __enable)   \
  `S_ASSERT_KNOWN(__name``KnownEnable, __enable)     \
  `S_ASSERT_IF(__name, !$isunknown(__sig), __enable)

`define S_COVER(__name, __prop) \
  __name: cover property (@(negedge clk_i) disable iff (rst_ni === '0) (__prop));
