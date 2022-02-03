// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include "tl_harness.h"

extern vector<tl_test> tests;

// Need to implement a few globally-accessible values/functions.

// 0 = no logging
// 1 = all logging
// Potential to add more options here.
int log_level = 0;

TileLinkSimulation* the_sim;

double sc_time_stamp() {
  return the_sim->simulation_time();
}
bool is_system_call(MemoryAddress address, uint64_t write_data) {
  return false;
}
void system_call(MemoryAddress address, uint64_t write_data) {}

// Be careful using this: it changes the simulation time, so is not suitable
// for parallel operations.
void next_cycle() {
  the_sim->next_cycle();
}


int main(int argc, char** argv) {
  TileLinkSimulation sim("tilelink", tests);
  the_sim = &sim;

  // Ignore the first argument (this simulator).
  sim.parse_args(argc - 1, argv + 1);

  sim.init();
  sim.reset();

  sim.run_tests();

  return 0;
}
