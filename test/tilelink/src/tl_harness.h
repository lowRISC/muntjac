// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Test harness for a TileLink network.

#ifndef TL_HARNESS_H
#define TL_HARNESS_H

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
    sim_duration = 0;
    randomise = false;

    this->args.set_description("Usage: " + name + " [simulator args] [tests to run]");
    this->args.add_argument("--list-tests", "List all available tests");
    this->args.add_argument("--coverage", "Dump coverage information to a file", ArgumentParser::ARGS_ONE);
    this->args.add_argument("--random-seed", "Set the random seed", ArgumentParser::ARGS_ONE);
    this->args.add_argument("--run", "Generate random traffic for the given duration (in cycles)", ArgumentParser::ARGS_ONE);

    hosts.push_back(new TileLinkHost(this->dut, 0, TL_C,  64, 0, 3));
    hosts.push_back(new TileLinkHost(this->dut, 1, TL_C,  64, 4, 5));
    hosts.push_back(new TileLinkHost(this->dut, 2, TL_UL, 64, 6, 7));
    
    devices.push_back(new TileLinkDevice(this->dut, 0, TL_C,  64, 0, 3));
    devices.push_back(new TileLinkDevice(this->dut, 1, TL_UH, 64, 4, 5));
    devices.push_back(new TileLinkDevice(this->dut, 2, TL_UL, 64, 6, 7));
  }

  int             num_hosts()   const {return hosts.size();}
  int             num_devices() const {return devices.size();}

  TileLinkHost&   host(int position)   const {return *hosts[position];}
  TileLinkDevice& device(int position) const {return *devices[position];}

  TileLinkHost&   random_host(tl_protocol_e min_protocol=TL_UL) const {
    // Assuming a host with the required protocol exists.
    while (true) {
      auto& host = *hosts[rand() % num_hosts()];
      if (host.protocol >= min_protocol)
        return host;
    }
  }

  TileLinkDevice& random_device(tl_protocol_e min_protocol=TL_UL) const {
    // Assuming a device with the required protocol exists.
    while (true) {
      auto& device = *devices[rand() % num_devices()];
      if (device.protocol >= min_protocol)
        return device;
    }
  }

  // Run a simulation for the given duration. Random requests will be generated 
  // during simulation, and responses will have random valid effects. During the
  // final `drain` clock cycles, no new requests will be generated.
  void run(bool random, int duration=1000, int drain=100) {
    randomise = random;
    for (int i=0; i<duration; i++)
      next_cycle();

    randomise = false;
    for (int i=0; i<drain; i++)
      next_cycle();
  }


  virtual void init() {
    dut.clk_i = 1;
    dut.rst_ni = 1;

    this->trace_init();
  }

  void next_cycle() {
    // TODO: this duplicates the content of Simulation::run()
    set_clock(1);
    cycle_first_half();
    this->trace_state_change();    
    this->cycle += 0.5;

    set_clock(0);
    cycle_second_half();
    this->trace_state_change();    
    this->cycle += 0.5;
  }

  void run_tests() {
    randomise = false;
    for (int test : tests_to_run) {
      cout << "Test selected: " << tests[test].description << endl;
      tests[test].function(*this);

      // Add a few empty cycles to allow signals to propagate.
      for (int wait=0; wait<100; wait++)
        next_cycle();
    }

    if (sim_duration > 0)
      run(true, sim_duration);

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

    if (this->args.found_arg("--random-seed"))
      srand(std::stoi(this->args.get_arg("--random-seed")));
    
    if (this->args.found_arg("--run"))
      sim_duration = std::stoi(this->args.get_arg("--run"));

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
    set_flow_control();
    set_outputs();
  }

  virtual void cycle_second_half() {
    dut.eval();
    get_inputs();
  }

  // Reset flow control signals from all hosts/devices. i.e. Deassert valid
  // signals if the data has been accepted.
  void set_flow_control() {
    for (auto host : hosts)
      host->set_flow_control();
    for (auto device : devices)
      device->set_flow_control();
  }

  void set_outputs() {
    for (auto host : hosts)
      host->set_outputs(randomise);
    for (auto device : devices)
      device->set_outputs(randomise);
  }

  void get_inputs() {
    for (auto host : hosts)
      host->get_inputs(randomise);
    for (auto device : devices)
      device->get_inputs(randomise);
  }

private:

  void list_tests() const {
    for (int i=0; i<tests.size(); i++)
      cout << "\t" << i << "\t" << tests[i].description << endl;
  }

  const vector<tl_test> tests;

  vector<int> tests_to_run;
  int sim_duration;

  // Whether requests should be spontaneously generated during simulation.
  // If true, responses will also have random valid content.
  bool randomise;

  bool coverage_on;
  string coverage_file;

  vector<TileLinkHost*> hosts;
  vector<TileLinkDevice*> devices;
};

#endif // TL_HARNESS_H
