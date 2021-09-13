// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Test harness for a TileLink network.

#include <vector>

#include <verilated.h>
#include "Vtl_wrapper.h"

#include "logs.h"
#include "simulation.h"
#include "tilelink.h"

using std::vector;
class TileLinkSimulation;

typedef Vtl_wrapper DUT;

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

    this->args.set_description("Usage: " + name + " [simulator args] [tests to run]");
    this->args.add_argument("--list-tests", "List all available tests");
    this->args.add_argument("--coverage", "Dump coverage information to a file", ArgumentParser::ARGS_ONE);
  }

  // Wrapper functions.
  // Note that these advance the simulation time, so are not suitable for some
  // parallel operations.
  // TODO: add agents to watch each port, and allow requests/responses to be
  //       queued up, allowing tighter interleaving of messages.
  void send_a(int host, tl_a data) {
    set_a(host, data);
    set_a_valid(host, true);
    next_cycle();  // Ensure the message is available for at least one cycle
    await_a_ready(host);
    set_a_valid(host, false);
  }

  void send_b(int device, tl_b data) {
    set_b(device, data);
    set_b_valid(device, true);
    next_cycle();  // Ensure the message is available for at least one cycle
    await_b_ready(device);
    set_b_valid(device, false);
  }

  void send_c(int host, tl_c data) {
    set_c(host, data);
    set_c_valid(host, true);
    next_cycle();  // Ensure the message is available for at least one cycle
    await_c_ready(host);
    set_c_valid(host, false);
  }

  void send_d(int device, tl_d data) {
    set_d(device, data);
    set_d_valid(device, true);
    next_cycle();  // Ensure the message is available for at least one cycle
    await_d_ready(device);
    set_d_valid(device, false);
  }

  void send_e(int host, tl_e data) {
    set_e(host, data);
    set_e_valid(host, true);
    next_cycle();  // Ensure the message is available for at least one cycle
    await_e_ready(host);
    set_e_valid(host, false);
  }

  tl_a await_a(int device, int timeout=100) {
    for (int i=0; i<timeout; i++) {
      if (get_a_valid(device)) 
        return get_a(device);

      next_cycle();
    }

    assert(false && "No channel A message received before timeout");
    return get_a(device);
  }

  tl_b await_b(int host, int timeout=100) {
    for (int i=0; i<timeout; i++) {
      if (get_b_valid(host)) 
        return get_b(host);

      next_cycle();
    }

    assert(false && "No channel B message received before timeout");
    return get_b(host);
  }

  tl_c await_c(int device, int timeout=100) {
    for (int i=0; i<timeout; i++) {
      if (get_c_valid(device)) 
        return get_c(device);

      next_cycle();
    }

    assert(false && "No channel C message received before timeout");
    return get_c(device);
  }

  tl_d await_d(int host, int timeout=100) {
    for (int i=0; i<timeout; i++) {
      if (get_d_valid(host)) 
        return get_d(host);

      next_cycle();
    }

    assert(false && "No channel D message received before timeout");
    return get_d(host);
  }

  tl_e await_e(int device, int timeout=100) {
    for (int i=0; i<timeout; i++) {
      if (get_e_valid(device)) 
        return get_e(device);

      next_cycle();
    }

    assert(false && "No channel E message received before timeout");
    return get_e(device);
  }

  void await_a_ready(int host, int timeout=100) {
    for (int i=0; i<timeout; i++) {
      if (get_a_ready(host)) 
        return;

      next_cycle();
    }

    assert(false && "Network not ready to receive channel A message");
  }

  void await_b_ready(int device, int timeout=100) {
    for (int i=0; i<timeout; i++) {
      if (get_b_ready(device)) 
        return;

      next_cycle();
    }

    assert(false && "Network not ready to receive channel B message");
  }

  void await_c_ready(int host, int timeout=100) {
    for (int i=0; i<timeout; i++) {
      if (get_c_ready(host)) 
        return;

      next_cycle();
    }

    assert(false && "Network not ready to receive channel C message");
  }

  void await_d_ready(int device, int timeout=100) {
    for (int i=0; i<timeout; i++) {
      if (get_d_ready(device)) 
        return;

      next_cycle();
    }

    assert(false && "Network not ready to receive channel D message");
  }

  void await_e_ready(int host, int timeout=100) {
    for (int i=0; i<timeout; i++) {
      if (get_e_ready(host)) 
        return;

      next_cycle();
    }

    assert(false && "Network not ready to receive channel E message");
  }


  // Lower-level signal access.

  void set_a(int host, tl_a data) {
    dut.host_a_opcode_i[host] = data.opcode;
    dut.host_a_param_i[host] = data.param;
    dut.host_a_size_i[host] = data.size;
    dut.host_a_source_i[host] = data.source;
    dut.host_a_address_i[host] = data.address;
    dut.host_a_mask_i[host] = data.mask;
    dut.host_a_corrupt_i[host] = data.corrupt;
    dut.host_a_data_i[host] = data.data;
  }

  void set_a_valid(int host, bool valid) {
    dut.host_a_valid_i[host] = valid;
  }

  bool get_a_ready(int host) {
    return dut.host_a_ready_o[host];
  }

  tl_a get_a(int device) {
    tl_a data;

    data.opcode = dut.dev_a_opcode_o[device];
    data.param = dut.dev_a_param_o[device];
    data.size = dut.dev_a_size_o[device];
    data.source = dut.dev_a_source_o[device];
    data.address = dut.dev_a_address_o[device];
    data.mask = dut.dev_a_mask_o[device];
    data.corrupt = dut.dev_a_corrupt_o[device];
    data.data = dut.dev_a_data_o[device];

    return data;
  }

  bool get_a_valid(int device) {
    return dut.dev_a_valid_o[device];
  }

  void set_a_ready(int device, bool ready) {
    dut.dev_a_ready_i[device] = ready;
  }


  tl_b get_b(int host) {
    tl_b data;

    data.opcode = dut.host_b_opcode_o[host];
    data.param = dut.host_b_param_o[host];
    data.size = dut.host_b_size_o[host];
    data.source = dut.host_b_source_o[host];
    data.address = dut.host_b_address_o[host];
    data.mask = dut.host_b_mask_o[host];
    data.corrupt = dut.host_b_corrupt_o[host];
    data.data = dut.host_b_data_o[host];

    return data;
  }

  bool get_b_valid(int host) {
    return dut.host_b_valid_o[host];
  }

  void set_b_ready(int host, bool ready) {
    dut.host_b_ready_i[host] = ready;
  }

  void set_b(int device, tl_b data) {
    dut.dev_b_opcode_i[device] = data.opcode;
    dut.dev_b_param_i[device] = data.param;
    dut.dev_b_size_i[device] = data.size;
    dut.dev_b_source_i[device] = data.source;
    dut.dev_b_address_i[device] = data.address;
    dut.dev_b_mask_i[device] = data.mask;
    dut.dev_b_corrupt_i[device] = data.corrupt;
    dut.dev_b_data_i[device] = data.data;
  }

  void set_b_valid(int device, bool valid) {
    dut.dev_b_valid_i[device] = valid;
  }

  bool get_b_ready(int device) {
    return dut.dev_b_ready_o[device];
  }


  void set_c(int host, tl_c data) {
    dut.host_c_opcode_i[host] = data.opcode;
    dut.host_c_param_i[host] = data.param;
    dut.host_c_size_i[host] = data.size;
    dut.host_c_source_i[host] = data.source;
    dut.host_c_address_i[host] = data.address;
    dut.host_c_corrupt_i[host] = data.corrupt;
    dut.host_c_data_i[host] = data.data;
  }

  void set_c_valid(int host, bool valid) {
    dut.host_c_valid_i[host] = valid;
  }

  bool get_c_ready(int host) {
    return dut.host_c_ready_o[host];
  }

  tl_c get_c(int device) {
    tl_c data;

    data.opcode = dut.dev_c_opcode_o[device];
    data.param = dut.dev_c_param_o[device];
    data.size = dut.dev_c_size_o[device];
    data.source = dut.dev_c_source_o[device];
    data.address = dut.dev_c_address_o[device];
    data.corrupt = dut.dev_c_corrupt_o[device];
    data.data = dut.dev_c_data_o[device];

    return data;
  }

  bool get_c_valid(int device) {
    return dut.dev_c_valid_o[device];
  }

  void set_c_ready(int device, bool ready) {
    dut.dev_c_ready_i[device] = ready;
  }


  tl_d get_d(int host) {
    tl_d data;

    data.opcode = dut.host_d_opcode_o[host];
    data.param = dut.host_d_param_o[host];
    data.size = dut.host_d_size_o[host];
    data.source = dut.host_d_source_o[host];
    data.sink = dut.host_d_sink_o[host];
    data.denied = dut.host_d_denied_o[host];
    data.corrupt = dut.host_d_corrupt_o[host];
    data.data = dut.host_d_data_o[host];

    return data;
  }

  bool get_d_valid(int host) {
    return dut.host_d_valid_o[host];
  }

  void set_d_ready(int host, bool ready) {
    dut.host_d_ready_i[host] = ready;
  }

  void set_d(int device, tl_d data) {
    dut.dev_d_opcode_i[device] = data.opcode;
    dut.dev_d_param_i[device] = data.param;
    dut.dev_d_size_i[device] = data.size;
    dut.dev_d_source_i[device] = data.source;
    dut.dev_d_sink_i[device] = data.sink;
    dut.dev_d_denied_i[device] = data.denied;
    dut.dev_d_corrupt_i[device] = data.corrupt;
    dut.dev_d_data_i[device] = data.data;
  }

  void set_d_valid(int device, bool valid) {
    dut.dev_d_valid_i[device] = valid;
  }

  bool get_d_ready(int device) {
    return dut.dev_d_ready_o[device];
  }


  void set_e(int host, tl_e data) {
    dut.host_e_sink_i[host] = data.sink;
  }

  void set_e_valid(int host, bool valid) {
    dut.host_e_valid_i[host] = valid;
  }

  bool get_e_ready(int host) {
    return dut.host_e_ready_o[host];
  }

  tl_e get_e(int device) {
    tl_e data;

    data.sink = dut.dev_e_sink_o[device];

    return data;
  }

  bool get_e_valid(int device) {
    return dut.dev_e_valid_o[device];
  }

  void set_e_ready(int device, bool ready) {
    dut.dev_e_ready_i[device] = ready;
  }


  virtual void init() {
    dut.clk_i = 1;
    dut.rst_ni = 1;

    // Hosts.
    for (int i=0; i<3; i++) {
      set_b_ready(i, true);
      set_d_ready(i, true);
    }

    // Devices.
    for (int i=0; i<3; i++) {
      set_a_ready(i, true);
      set_c_ready(i, true);
      set_e_ready(i, true);
    }

    if (this->trace_on) {
      Verilated::traceEverOn(true);
    	this->dut.trace(&this->vcd_trace, 100);
    	this->vcd_trace.open(this->trace_file.c_str());
    }

    // TODO: flush/close the trace file. Difficult when we're half expecting
    // execution to finish suddenly with an assertion failure.
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

    if (this->args.found_arg("--coverage"))
      coverage_file = this->args.get_arg("--coverage");

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

    if (this->trace_on)
      this->vcd_trace.dump((uint64_t)(10*this->cycle));
    
    this->cycle += 0.5;
  }

  virtual void cycle_second_half() {
    dut.eval();

    if (this->trace_on)
      this->vcd_trace.dump((uint64_t)(10*this->cycle));

    this->cycle += 0.5;
  }

private:

  void list_tests() const {
    for (int i=0; i<tests.size(); i++)
      cout << "\t" << i << "\t" << tests[i].description << endl;
  }

  const vector<tl_test> tests;

  vector<int> tests_to_run;

  string coverage_file;
};
