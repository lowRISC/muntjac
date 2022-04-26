// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#ifndef TL_RANDOM_H
#define TL_RANDOM_H

#include <cassert>
#include <cstdlib>
#include <vector>

#include "tilelink.h"

using std::vector;

// Both min and max are inclusive.
static int random_sample(int min, int max) {
  return min + (rand() % (max - min + 1));
}

static bool random_bool(float prob_true = 0.5) {
  return (rand() % 1000) < (1000 * prob_true);
}


static tl_a_op_e random_a_opcode(tl_protocol_e protocol) {
  static vector<tl_a_op_e> tl_ul = {PutFullData, PutPartialData, Get};
  static vector<tl_a_op_e> tl_uh = {PutFullData, PutPartialData, Get,
                                    ArithmeticData, LogicalData, Intent};
  static vector<tl_a_op_e> tl_c  = {PutFullData, PutPartialData, Get,
                                    ArithmeticData, LogicalData, Intent,
                                    AcquireBlock, AcquirePerm};

  switch (protocol) {
    case TL_UL: return tl_ul[random_sample(0, tl_ul.size() - 1)];
    case TL_UH: return tl_uh[random_sample(0, tl_uh.size() - 1)];
    
    case TL_C_IO_TERM:
    case TL_C_ROM_TERM:
    case TL_C:  return tl_c[random_sample(0, tl_c.size() - 1)];
    default:    assert(false && "Invalid protocol for A channel"); return Get;
  }
}

static tl_b_op_e random_b_opcode(tl_protocol_e protocol) {
  if (protocol != TL_C) {
    assert(false && "Invalid protocol for B channel");
    return ProbeBlock;
  }

  return (tl_b_op_e)random_sample(6, 7);
}

static tl_c_op_e random_c_opcode(tl_protocol_e protocol) {
  // Ignore ProbeAck(Data) - they are responses, so should not be randomised.
  static vector<tl_c_op_e> tl_c        = {Release, ReleaseData};
  static vector<tl_c_op_e> tl_rom_term = {Release};

  switch (protocol) {
    case TL_C_ROM_TERM: 
      return tl_rom_term[random_sample(0, tl_rom_term.size() - 1)];
    case TL_C:
      return tl_c[random_sample(0, tl_c.size() - 1)];
    default:
      assert(false && "Invalid protocol for C channel");
      return ProbeAck;
  }
}

static arithmetic_data_param_e random_arithmetic_data_param() {
  return (arithmetic_data_param_e)random_sample(0, 4);
}

static logical_data_param_e random_logical_data_param() {
  return (logical_data_param_e)random_sample(0, 3);
}

static intent_param_e random_intent_param() {
  return (intent_param_e)random_sample(0, 1);
}

static cap_permissions_e random_cap_permission() {
  return (cap_permissions_e)random_sample(0, 2);
}

static grow_permissions_e random_grow_permission() {
  return (grow_permissions_e)random_sample(0, 2);
}

static prune_permissions_e random_prune_permission() {
  return (prune_permissions_e)random_sample(0, 2);
}

static report_permissions_e random_report_permission() {
  return (report_permissions_e)random_sample(3, 5);
}

#endif // TL_RANDOM_H
