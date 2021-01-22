// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#ifndef SIMULATION_H
#define SIMULATION_H

#include <iomanip>
#include <iostream>
#include <fstream>
#include <verilated.h>
#include <verilated_vcd_c.h>

#include "binary_parser.h"
#include "logs.h"
#include "main_memory.h"

using std::ofstream;
using std::string;

template<class DUT>
class Simulation {
public:

  Simulation(string name, int argc, char** argv) {
    this->name = name;
    main_memory_latency = 10;
    timeout = 1000000;
    csv_on = false;
    trace_on = false;
    cycle = 0.0;
    exit_code = 0;

    parse_args(argc, argv);
    read_binary(argc - binary_position, argv + binary_position);
  }

protected:

  // To be implemented by subclasses.
  virtual void set_clock(int value) = 0;
  virtual void set_reset(int value) = 0;
  virtual void set_entry_point(MemoryAddress pc) = 0;
  virtual MemoryAddress get_program_counter() = 0;
  virtual instr_trace_t get_trace_info() = 0;
  virtual void init() = 0;
  virtual void cycle_first_half() = 0;
  virtual void cycle_second_half() = 0;

public:

  double simulation_time() const {
    return cycle;
  }

  int return_code() const {
    return exit_code;
  }

  void run() {
    MemoryAddress pc = 0;

    VerilatedVcdC trace;
    if (trace_on) {
      Verilated::traceEverOn(true);
    	dut.trace(&trace, 100);
    	trace.open(trace_file.c_str());
    }

    ofstream csv;
    if (csv_on) {
      csv.open(csv_file);

      // This is a subset of the required fields for riscv-dv. The remaining
      // ones are added in with a separate script which can decode instructions.
      csv << "pc,gpr,csr,binary,mode\n";
    }

    init();
    reset();

    while (!Verilated::gotFinish() && cycle < timeout) {
      set_clock(1);
      cycle_first_half();

      if (trace_on) {
        trace.dump((uint64_t)(10*cycle));
      }

      cycle += 0.5;
      set_clock(0);
      cycle_second_half();

      if (trace_on) {
        trace.dump((uint64_t)(10*cycle));
      }

      if (get_program_counter() != pc) {
        pc = get_program_counter();
        MUNTJAC_LOG(1) << "PC: 0x" << std::hex << pc << std::dec << endl;

        if (csv_on)
          csv_output_line(csv);
      }

      cycle += 0.5;
    }

    if (trace_on) {
      trace.flush();
      trace.close();
    }

    if (csv_on) {
      csv.flush();
      csv.close();
    }

    if (cycle >= timeout) {
      MUNTJAC_ERROR << "Simulation timed out after " << timeout << " cycles" << endl;
      exit(1);
    }

  }

  void reset() {
    set_reset(1);

    for (int i=0; i<10; i++) {
      set_clock(1);
      dut.eval();
      set_clock(0);
      dut.eval();
    }

    set_reset(0);
    set_entry_point(entry_point);
  }

  bool is_system_call(MemoryAddress address, uint64_t write_data) {
    return (address == tohost) || (address == fromhost);
  }

  // This behaviour is probably specific to riscv-tests.
  void system_call(MemoryAddress address, uint64_t write_data) {
    assert(is_system_call(address, write_data));

    // putchar
    if ((write_data & 0xffffffffffffff00) == 0x101000000000000)
      putchar(write_data & 0xff);
    // exit
    else {
      MUNTJAC_LOG(0) << "Exiting with argument " << write_data << endl;

      if (write_data == 1)
        exit_code = 0;
      else
        exit_code = 1;

      Verilated::gotFinish(true);
    }
  }

private:

  void parse_args(int argc, char** argv) {
    // Check for simulation arguments. They all begin with a hyphen.
    int arg = 0;
    while ((arg < argc) && (argv[arg][0] == '-')) {
      string arg_string = argv[arg];

      if (arg_string.rfind("--memory-latency", 0) == 0) {
        string value = arg_string.substr(arg_string.find("=")+1, arg_string.size());
        main_memory_latency = std::stoi(value);
      }
      else if (arg_string.rfind("--timeout", 0) == 0) {
        string value = arg_string.substr(arg_string.find("=")+1, arg_string.size());
        timeout = std::stoi(value);
      }
      else if (arg_string.rfind("--vcd", 0) == 0) {
        string value = arg_string.substr(arg_string.find("=")+1, arg_string.size());
        trace_file = value;
        trace_on = true;
      }
      else if (arg_string.rfind("--csv", 0) == 0) {
        string value = arg_string.substr(arg_string.find("=")+1, arg_string.size());
        csv_file = value;
        csv_on = true;
      }
      else if (arg_string == "-v")
        log_level = 1;
      else if (arg_string == "-vv")
        log_level = 2;
      else if (arg_string == "--help") {
        print_help();
        exit(1);
      }
      else {
        cerr << "Unsupported simulator argument: " << arg_string << endl;
        exit(1);
      }

      arg++;
    }

    if (arg == argc) {
      print_help();
      exit(1);
    }

    binary_position = arg;
  }

  void csv_output_line(ofstream& file) {
    instr_trace_t trace = get_trace_info();

    // This is a subset of the required fields for riscv-dv. The remaining
    // ones are added in with a separate script which can decode instructions.
    // The register indices will also need to be translated to names.
    file << std::hex << std::setfill('0');

    file << std::setw(16) << trace.pc << ",";
    if (trace.gpr_written && trace.gpr != 0)
      file << trace.gpr << ":" << std::setw(16) << trace.gpr_data;
    file << ",";
    if (trace.csr_written)
      file << trace.csr << ":" << std::setw(16) << trace.csr_data;
    file << ",";
    file << std::setw(8) << trace.instr_word << ",";
    file << trace.mode << "\n";
  }

  void print_help() {
    cout << "Muntjac simulator." << endl;
    cout << endl;
    cout << "Usage: " << name << " [simulator args] <program> [program args]" << endl;
    cout << endl;
    cout << "Simulator arguments:" << endl;
    cout << "  --csv=X\t\tDump a CSV trace to file X (mainly for riscv-dv)" << endl;
    cout << "  --memory-latency=X\tSet main memory latency to X cycles" << endl;
    cout << "  --timeout=X\t\tForce end of simulation after X cycles" << endl;
    cout << "  --vcd=X\t\tDump VCD output to file X" << endl;
    cout << "  -v[v]\t\t\tDisplay additional information as simulation proceeds" << endl;
    cout << "  --help\t\tDisplay this information and exit" << endl;
  }

  void read_binary(int argc, char** argv) {
    BinaryParser::load_elf(argc, argv, memory);
    entry_point = BinaryParser::entry_point(argv[0]);

    // System calls: this may be specific to riscv-tests.
    tohost = BinaryParser::symbol_location(argv[0], "tohost");
    fromhost = BinaryParser::symbol_location(argv[0], "fromhost");
  }

protected:
  // The component being tested.
  DUT dut;
  MainMemory memory;

// Simulation parameters.

  // Cycles between a request arriving at main memory and a response leaving.
  int main_memory_latency;

private:
  // Force end simulation after this many cycles.
  uint64_t timeout;

  // Generate VCD/FST trace file?
  bool trace_on;
  string trace_file;

  // Generate CSV trace file?
  bool csv_on;
  string csv_file;

// Simulation state.

  // The name of this component.
  string name;

  // The current clock cycle.
  double cycle;

  // Value to return when simulation finishes.
  int exit_code;

  // The position of the RISC-V binary in argv.
  int binary_position;

  // Memory address of the first instruction to be executed.
  MemoryAddress entry_point;

  // Memory addresses to access for system calls.
  MemoryAddress tohost;
  MemoryAddress fromhost;

};

#endif  // SIMULATION_H
