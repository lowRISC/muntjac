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
    timeout = 1000000;
    trace_on = false;
    cycle = 0.0;

    parse_args(argc, argv);
  }

protected:

  // To be implemented by subclasses.
  virtual void set_clock(int value) = 0;
  virtual void set_reset(int value) = 0;
  virtual void init() = 0;
  virtual void cycle_first_half() = 0;
  virtual void cycle_second_half() = 0;

public:

  double simulation_time() const {
    return cycle;
  }

  virtual void reset() {
    set_reset(1);

    for (int i=0; i<10; i++) {
      set_clock(1);
      dut.eval();
      set_clock(0);
      dut.eval();
    }

    set_reset(0);
  }

  void end_simulation() {
    dut.final();
  }

protected:

  virtual void parse_args(int argc, char** argv) {
    // Check for simulation arguments. They all begin with a hyphen.
    int arg = 0;
    while ((arg < argc) && (argv[arg][0] == '-')) {
      string arg_string = argv[arg];

      if (arg_string.rfind("--timeout", 0) == 0) {
        string value = arg_string.substr(arg_string.find("=")+1, arg_string.size());
        timeout = std::stoi(value);
      }
      else if (arg_string.rfind("--vcd", 0) == 0) {
        string value = arg_string.substr(arg_string.find("=")+1, arg_string.size());
        trace_file = value;
        trace_on = true;
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
  }

  virtual void print_help() {
    cout << "Muntjac simulator." << endl;
    cout << endl;
    cout << "Usage: " << name << " [simulator args] <program> [program args]" << endl;
    cout << endl;
    cout << "Simulator arguments:" << endl;
    cout << "  --timeout=X\t\tForce end of simulation after X cycles" << endl;
    cout << "  --vcd=X\t\tDump VCD output to file X" << endl;
    cout << "  -v[v]\t\t\tDisplay additional information as simulation proceeds" << endl;
    cout << "  --help\t\tDisplay this information and exit" << endl;
  }

protected:
  // The component being tested.
  DUT dut;

// Simulation state.

  // The name of this component.
  string name;

  // The current clock cycle.
  double cycle;

// Simulation parameters.

  // Force end simulation after this many cycles.
  uint64_t timeout;

  // Generate VCD/FST trace file?
  bool trace_on;
  string trace_file;
  VerilatedVcdC vcd_trace;

};


// A simulator which can execute RISC-V binaries.
template<class DUT>
class RISCVSimulation : public Simulation<DUT> {
public:

  RISCVSimulation(string name, int argc, char** argv) : 
      Simulation<DUT>(name, argc, argv) {
    main_memory_latency = 10;
    csv_on = false;
    exit_code = 0;

    read_binary(argc - binary_position, argv + binary_position);
  }

protected:

  // To be implemented by subclasses.
  virtual MemoryAddress get_program_counter() = 0;
  virtual instr_trace_t get_trace_info() = 0;

public:

  int return_code() const {
    return exit_code;
  }

  void run() {
    MemoryAddress pc = 0;

    if (this->trace_on) {
      Verilated::traceEverOn(true);
    	this->dut.trace(&this->vcd_trace, 100);
    	this->vcd_trace.open(this->trace_file.c_str());
    }

    ofstream csv;
    if (csv_on) {
      csv.open(csv_file);

      // This is a subset of the required fields for riscv-dv. The remaining
      // ones are added in with a separate script which can decode instructions.
      csv << "pc,gpr,csr,binary,mode\n";
    }

    this->init();
    this->reset();
    
    this->cycle_second_half();

    while (!Verilated::gotFinish() && this->cycle < this->timeout) {
      this->set_clock(1);
      this->cycle_first_half();

      if (this->trace_on) {
        this->vcd_trace.dump((uint64_t)(10*this->cycle));
      }

      this->cycle += 0.5;
      this->set_clock(0);
      this->cycle_second_half();

      if (this->trace_on) {
        this->vcd_trace.dump((uint64_t)(10*this->cycle));
      }

      if (get_program_counter() != pc) {
        pc = get_program_counter();
        MUNTJAC_LOG(1) << "PC: 0x" << std::hex << pc << std::dec << endl;

        if (csv_on)
          csv_output_line(csv);
      }

      this->cycle += 0.5;
    }

    if (this->trace_on) {
      this->vcd_trace.flush();
      this->vcd_trace.close();
    }

    if (csv_on) {
      csv.flush();
      csv.close();
    }

    this->end_simulation();

    if (this->cycle >= this->timeout) {
      MUNTJAC_ERROR << "Simulation timed out after " << this->timeout << " cycles" << endl;
      exit(1);
    }

  }

  void reset() {
    Simulation<DUT>::reset();
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
      exit_code = write_data;
      Verilated::gotFinish(true);
    }
  }

protected:

  virtual void parse_args(int argc, char** argv) {
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
        this->timeout = std::stoi(value);
      }
      else if (arg_string.rfind("--vcd", 0) == 0) {
        string value = arg_string.substr(arg_string.find("=")+1, arg_string.size());
        this->trace_file = value;
        this->trace_on = true;
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

  virtual void print_help() {
    cout << "Muntjac simulator." << endl;
    cout << endl;
    cout << "Usage: " << this->name << " [simulator args] <program> [program args]" << endl;
    cout << endl;
    cout << "Simulator arguments:" << endl;
    cout << "  --csv=X\t\tDump a CSV trace to file X (mainly for riscv-dv)" << endl;
    cout << "  --memory-latency=X\tSet main memory latency to X cycles" << endl;
    cout << "  --timeout=X\t\tForce end of simulation after X cycles" << endl;
    cout << "  --vcd=X\t\tDump VCD output to file X" << endl;
    cout << "  -v[v]\t\t\tDisplay additional information as simulation proceeds" << endl;
    cout << "  --help\t\tDisplay this information and exit" << endl;
  }

private:

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

  void read_binary(int argc, char** argv) {
    BinaryParser::load_elf(argc, argv, memory);
    entry_point = BinaryParser::entry_point(argv[0]);

    // System calls: this may be specific to riscv-tests.
    tohost = BinaryParser::symbol_location(argv[0], "tohost");
    fromhost = BinaryParser::symbol_location(argv[0], "fromhost");
  }

  void set_entry_point(MemoryAddress pc) {
    // auipc a0, 0; ld a0, 16(a0)
    memory.write64(0x00, 0x0105350300000517);
    // jr a0
    memory.write64(0x08, 0x0000000000008502);
    // target pc
    memory.write64(0x10, pc);
  }

protected:

  MainMemory memory;

// Simulation parameters.

  // Cycles between a request arriving at main memory and a response leaving.
  int main_memory_latency;

private:

  // Generate CSV trace file?
  bool csv_on;
  string csv_file;

// Simulation state.

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
