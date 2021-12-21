// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

`ifndef TL_ASSERT_UTIL_SVH
`define TL_ASSERT_UTIL_SVH

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

// Macros to assign one TileLink state to another.
// Similar to the macros in tl_util.svh, but only used by the assertions.
// It may even be possible to avoid using these with some refactoring.

`define TL_ASSIGN_IMPL(LHS, IDX_L, RHS, IDX_R, H2D_SUFFIX, D2H_SUFFIX, ASSIGN) \
  LHS``_a_ready IDX_L ASSIGN RHS``_a_ready``D2H_SUFFIX IDX_R; \
  LHS``_a_valid IDX_L ASSIGN RHS``_a_valid``H2D_SUFFIX IDX_R; \
  LHS``_a       IDX_L ASSIGN RHS``_a``H2D_SUFFIX       IDX_R; \
  LHS``_b_ready IDX_L ASSIGN RHS``_b_ready``H2D_SUFFIX IDX_R; \
  LHS``_b_valid IDX_L ASSIGN RHS``_b_valid``D2H_SUFFIX IDX_R; \
  LHS``_b       IDX_L ASSIGN RHS``_b``D2H_SUFFIX       IDX_R; \
  LHS``_c_ready IDX_L ASSIGN RHS``_c_ready``D2H_SUFFIX IDX_R; \
  LHS``_c_valid IDX_L ASSIGN RHS``_c_valid``H2D_SUFFIX IDX_R; \
  LHS``_c       IDX_L ASSIGN RHS``_c``H2D_SUFFIX       IDX_R; \
  LHS``_d_ready IDX_L ASSIGN RHS``_d_ready``H2D_SUFFIX IDX_R; \
  LHS``_d_valid IDX_L ASSIGN RHS``_d_valid``D2H_SUFFIX IDX_R; \
  LHS``_d       IDX_L ASSIGN RHS``_d``D2H_SUFFIX       IDX_R; \
  LHS``_e_ready IDX_L ASSIGN RHS``_e_ready``D2H_SUFFIX IDX_R; \
  LHS``_e_valid IDX_L ASSIGN RHS``_e_valid``H2D_SUFFIX IDX_R; \
  LHS``_e       IDX_L ASSIGN RHS``_e``H2D_SUFFIX       IDX_R

`define TL_ASSIGN_B_IMPL(LHS, IDX_L, RHS, IDX_R, H2D_SUFFIX, D2H_SUFFIX) \
  `TL_ASSIGN_IMPL(LHS, IDX_L, RHS, IDX_R, H2D_SUFFIX, D2H_SUFFIX, =)

`define TL_ASSIGN_B_IDX(LHS, IDX_L, RHS, IDX_R) \
  `TL_ASSIGN_B_IMPL(LHS, IDX_L, RHS, IDX_R, , )

`define TL_ASSIGN_B(LHS, RHS) \
  `TL_ASSIGN_B_IDX(LHS, , RHS, )

`define TL_ASSIGN_B_FROM_HOST_IDX(LHS, IDX_L, RHS, IDX_R) \
  `TL_ASSIGN_B_IMPL(LHS, IDX_L, RHS, IDX_R, _o, _i)

`define TL_ASSIGN_B_FROM_HOST(LHS, RHS) \
  `TL_ASSIGN_B_FROM_HOST_IDX(LHS, , RHS, )

`define TL_ASSIGN_B_FROM_DEVICE_IDX(LHS, IDX_L, RHS, IDX_R) \
  `TL_ASSIGN_B_IMPL(LHS, IDX_L, RHS, IDX_R, _i, _o)

`define TL_ASSIGN_B_FROM_DEVICE(LHS, RHS) \
  `TL_ASSIGN_B_FROM_DEVICE_IDX(LHS, , RHS, )

`define TL_ASSIGN_B_FROM_TAP_IDX(LHS, IDX_L, RHS, IDX_R) \
  `TL_ASSIGN_B_IMPL(LHS, IDX_L, RHS, IDX_R, _i, _i)

`define TL_ASSIGN_B_FROM_TAP(LHS, RHS) \
  `TL_ASSIGN_B_FROM_TAP_IDX(LHS, , RHS, )

`define TL_ASSIGN_NB_IMPL(LHS, IDX_L, RHS, IDX_R, H2D_SUFFIX, D2H_SUFFIX) \
  `TL_ASSIGN_IMPL(LHS, IDX_L, RHS, IDX_R, H2D_SUFFIX, D2H_SUFFIX, <=)

`define TL_ASSIGN_NB_IDX(LHS, IDX_L, RHS, IDX_R) \
  `TL_ASSIGN_NB_IMPL(LHS, IDX_L, RHS, IDX_R, , )

`define TL_ASSIGN_NB(LHS, RHS) \
  `TL_ASSIGN_NB_IDX(LHS, , RHS, )

`define TL_ASSIGN_NB_FROM_HOST_IDX(LHS, IDX_L, RHS, IDX_R) \
  `TL_ASSIGN_NB_IMPL(LHS, IDX_L, RHS, IDX_R, _o, _i)

`define TL_ASSIGN_NB_FROM_HOST(LHS, RHS) \
  `TL_ASSIGN_NB_FROM_HOST_IDX(LHS, , RHS, )

`define TL_ASSIGN_NB_FROM_DEVICE_IDX(LHS, IDX_L, RHS, IDX_R) \
  `TL_ASSIGN_NB_IMPL(LHS, IDX_L, RHS, IDX_R, _i, _o)

`define TL_ASSIGN_NB_FROM_DEVICE(LHS, RHS) \
  `TL_ASSIGN_NB_FROM_DEVICE_IDX(LHS, , RHS, )

`define TL_ASSIGN_NB_FROM_TAP_IDX(LHS, IDX_L, RHS, IDX_R) \
  `TL_ASSIGN_NB_IMPL(LHS, IDX_L, RHS, IDX_R, _i, _i)

`define TL_ASSIGN_NB_FROM_TAP(LHS, RHS) \
  `TL_ASSIGN_NB_FROM_TAP_IDX(LHS, , RHS, )

`endif // TL_ASSERT_UTIL_SVH
