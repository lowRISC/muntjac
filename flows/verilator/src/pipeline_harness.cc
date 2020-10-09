// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Test harness for a core pipeline (no caches).
// The core has two parallel connections to memory (instructins and data), so
// performance figures may not be accurate.

#include "data_cache_port.h"
#include "instruction_cache_port.h"
#include "logs.h"
#include "simulation.h"

#include "Vpipeline_wrapper.h"
#include "Vpipeline_wrapper_pipeline_wrapper.h"  // Verilator internals

typedef Vpipeline_wrapper DUT;


class PipelineSimulation : public Simulation<DUT> {
public:
  PipelineSimulation(string name, int argc, char** argv) :
      Simulation<DUT>(name, argc, argv),
      instruction_port(dut, memory, main_memory_latency),
      data_port(dut, memory, main_memory_latency) {
    // Nothing
  }

protected:

  virtual void set_clock(int value) {dut.clk_i = value;}
  virtual void set_reset(int value) {dut.rst_ni = !value;}
  virtual void set_entry_point(MemoryAddress pc) {
    dut.pipeline_wrapper->write_reset_pc(pc);
  }
  virtual MemoryAddress get_program_counter() {return dut.dbg_pc_o;}

  virtual void init() {
    dut.clk_i = 1;
    dut.rst_ni = 1;

    dut.icache_resp_valid = 0;
    dut.icache_resp_instr = 0xDEADBEEF;
    dut.icache_resp_exception = 0;

    dut.dcache_req_ready = 1;
    dut.dcache_resp_valid = 0;
    dut.dcache_resp_value = 0xDEADBEEF;
    dut.dcache_ex_valid = 0;
  //  dut.dcache_ex_exception = 0;  // Need an exception_t
    dut.dcache_notif_ready = 0;

    dut.irq_timer_m_i = 0; // sip[5]
    dut.irq_software_m_i = 0;
    dut.irq_external_m_i = 0;
    dut.irq_external_s_i = 0; // sip[9]
    dut.hart_id_i = 0;
  }

  // The timing requirements are delicate. In each cycle, we have:
  //  * Two clock edges
  //  * Some number of Verilator evaluations
  //  * Extract data from the Verilator model
  //  * Pass new data to the Verilator model
  //
  // The pipeline updates its outputs on the posedge, so we need:
  //   posedge -> eval -> get_inputs
  //
  // The pipeline may respond to new inputs combinatorically, and then
  // confirm a state change on the next posedge, so we need:
  //   set_outputs -> eval -> posedge -> eval
  //
  // In order to achieve a single-cycle cache latency, we need:
  //   posedge eval -> get_inputs -> set_outputs -> posedge eval
  virtual void cycle_first_half() {
    dut.eval();

    instruction_port.set_outputs(simulation_time());
    data_port.set_outputs(simulation_time());
  }

  virtual void cycle_second_half() {
    dut.eval();

    instruction_port.get_inputs(simulation_time());
    data_port.get_inputs(simulation_time());
  }

private:
  // Implement the pipeline's interfaces to the memory hierarchy.
  InstructionCachePort<DUT> instruction_port;
  DataCachePort<DUT> data_port;
};


// Need to implement a few globally-accessible values/functions.

// 0 = no logging
// 1 = all logging
// Potential to add more options here.
int log_level = 0;

PipelineSimulation* the_sim;

double sc_time_stamp() {
  return the_sim->simulation_time();
}
bool is_system_call(MemoryAddress address, uint64_t write_data) {
  return the_sim->is_system_call(address, write_data);
}
void system_call(MemoryAddress address, uint64_t write_data) {
  the_sim->system_call(address, write_data);
}


int main(int argc, char** argv) {
  // Ignore the first argument (this binary).
  PipelineSimulation sim("muntjac_pipeline", argc - 1, argv + 1);
  the_sim = &sim;

  sim.run();

  return sim.return_code();
}
