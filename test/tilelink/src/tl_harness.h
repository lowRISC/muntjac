// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Test harness for a TileLink network.

#include <vector>
#include <verilated.h>

#include "logs.h"
#include "simulation.h"
#include "tl_channels.h"

using std::vector;
class TileLinkSimulation;


typedef void (*tl_test_fn)(TileLinkSimulation& sim);
typedef struct {
  tl_test_fn function;
  string     description;
} tl_test;


class TileLinkSimulation : public Simulation<DUT> {
public:
  TileLinkSimulation(string name, vector<tl_test>& tests) :
      Simulation<DUT>(name),
      tests(tests),
      coverage_file("coverage.dat") {
    coverage_on = false;

    this->args.set_description("Usage: " + name + " [simulator args] [tests to run]");
    this->args.add_argument("--list-tests", "List all available tests");
    this->args.add_argument("--coverage", "Dump coverage information to a file", ArgumentParser::ARGS_ONE);

    hosts.push_back(new TileLinkHost(this->dut, 0, TL_C,  64));
    hosts.push_back(new TileLinkHost(this->dut, 1, TL_UH, 64));
    hosts.push_back(new TileLinkHost(this->dut, 2, TL_UL, 64));
    
    devices.push_back(new TileLinkDevice(this->dut, 0, TL_C,  64));
    devices.push_back(new TileLinkDevice(this->dut, 1, TL_UH, 64));
    devices.push_back(new TileLinkDevice(this->dut, 2, TL_UL, 64));
  }

  TileLinkHost&   host(int position)   const {return *hosts[position];}
  TileLinkDevice& device(int position) const {return *devices[position];}

  // Run a deterministic simulation until there have been `timeout` cycles of
  // inactivity. No new requests will be generated, but default responses will
  // be created and sent for any transactions still in the system.
  void run_deterministic(int timeout=100) {

  }

  // Run a simulation with random valid requests and responses for `duration`
  // clock cycles. No new requests will be generated for the final `drain`
  // cycles to allow the system to reach a quiescent state.
  void run_random(int duration=1000, int drain=100) {
    // TODO
  }


  virtual void init() {
    dut.clk_i = 1;
    dut.rst_ni = 1;

    for (TileLinkHost* host : hosts) {
      host->b.set_ready(true);
      host->d.set_ready(true);
    }

    for (TileLinkDevice* device : devices) {
      device->a.set_ready(true);
      device->c.set_ready(true);
      device->e.set_ready(true);
    }

    this->trace_init();
  }

  void next_cycle() {
    set_clock(1);
    cycle_first_half();
    set_clock(0);
    cycle_second_half();
  }

  void run() {
    for (int test : tests_to_run) {
      cout << "Test selected: " << tests[test].description << endl;
      tests[test].function(*this);

      // Add a few empty cycles to allow signals to propagate.
      for (int wait=0; wait<100; wait++)
        next_cycle();
    }

    end_simulation();

    this->trace_close();

    if (coverage_on)
      Verilated::threadContextp()->coveragep()->write(coverage_file.c_str());

    cout << "No assertions triggered" << endl;
  }

  virtual void parse_args(int argc, char** argv) {
    if (argc == 0) {
      this->args.print_help();
      exit(0);
    }

    Simulation<DUT>::parse_args(argc, argv);

    if (this->args.found_arg("--list-tests")) {
      list_tests();
      exit(0);
    }

    if (this->args.found_arg("--coverage")) {
      coverage_on = true;
      coverage_file = this->args.get_arg("--coverage");
    }

    // If we found an unknown argument, assume it's the beginning of a list of
    // tests to run.
    if (this->args.get_args_parsed() < argc) {
      for (int i=this->args.get_args_parsed(); i<argc; i++) {
        int test = atoi(argv[i]);
        assert(test < tests.size());
        tests_to_run.push_back(test);
      }
    }
  }

protected:

  virtual void set_clock(int value) {dut.clk_i = value;}
  virtual void set_reset(int value) {dut.rst_ni = !value;}

  virtual void cycle_first_half() {
    dut.eval();
    reset_flow_control();
    this->trace_state_change();    
    this->cycle += 0.5;
  }

  virtual void cycle_second_half() {
    dut.eval();
    eval_endpoints();

    if (this->trace_on)
      this->vcd_trace.dump((uint64_t)(10*this->cycle));

    this->trace_state_change();
    this->cycle += 0.5;
  }

private:

  void list_tests() const {
    for (int i=0; i<tests.size(); i++)
      cout << "\t" << i << "\t" << tests[i].description << endl;
  }

  const vector<tl_test> tests;

  vector<int> tests_to_run;

  bool coverage_on;
  string coverage_file;

  vector<TileLinkHost*> hosts;
  vector<TileLinkDevice*> devices;
};
