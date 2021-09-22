// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#ifndef SIMULATION_H
#define SIMULATION_H

#include <iomanip>
#include <iostream>
#include <fstream>
#include <verilated.h>

// Verilator doesn't allow VCD and FST tracing simultaneously.
// FST is faster and smaller, but only supported by GTKWave.
// See the *_tb.core files to change which flag is set.
#ifdef FST_ENABLE
  #include "verilated_fst_c.h"
#endif 
#ifdef VCD_ENABLE
  #include <verilated_vcd_c.h>
#endif

#include "argument_parser.h"
#include "binary_parser.h"
#include "exceptions.h"
#include "logs.h"
#include "main_memory.h"

using std::ofstream;
using std::string;

template<class DUT>
class Simulation {
public:

  Simulation(string name) {
    this->name = name;
    timeout = 1000000;
    cycle = 0.0;

    args.add_argument("--timeout", "Force end of simulation after fixed number of cycles", ArgumentParser::ARGS_ONE);
    args.add_argument("-v", "Display basic logging information as simulation proceeds");
    args.add_argument("-vv", "Display detailed logging information as simulation proceeds");
    args.add_argument("--help", "Display this information and exit");

#ifdef FST_ENABLE
    fst_on = false;
    args.add_argument("--fst", "Dump FST output to a file (enable VCD in *_tb.core)", ArgumentParser::ARGS_ONE);
#endif 
#ifdef VCD_ENABLE
    vcd_on = false;
    args.add_argument("--vcd", "Dump VCD output to a file (enable FST in *_tb.core)", ArgumentParser::ARGS_ONE);
#endif
  }

protected:

  // To be implemented by subclasses.
  virtual void set_clock(int value) = 0;
  virtual void set_reset(int value) = 0;
  virtual void init() = 0;
  virtual void cycle_first_half() = 0;
  virtual void cycle_second_half() = 0;

  // Initialise all active traces.
  virtual void trace_init() {
#ifdef VCD_ENABLE
    if (vcd_on) {
      Verilated::traceEverOn(true);
    	dut.trace(&vcd_trace, 100);
    	vcd_trace.open(vcd_filename.c_str());
    }
#endif 
#ifdef FST_ENABLE
    if (fst_on) {
      Verilated::traceEverOn(true);
    	dut.trace(&fst_trace, 100);
    	fst_trace.open(fst_filename.c_str());
    }
#endif
  }

  // Dump information after state has changed.
  virtual void trace_state_change() {
#ifdef VCD_ENABLE
    if (vcd_on)
      vcd_trace.dump((uint64_t)(10*this->cycle));
#endif 
#ifdef FST_ENABLE
    if (fst_on)
      fst_trace.dump((uint64_t)(10*this->cycle));
#endif
  }

  // Close all active traces.
  virtual void trace_close() {
#ifdef VCD_ENABLE
    if (vcd_on) {
      vcd_trace.flush();
      vcd_trace.close();
    }
#endif
#ifdef FST_ENABLE
    if (fst_on) {
      fst_trace.flush();
      fst_trace.close();
    }
#endif
  }

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

  // Call this from all subclasses.
  virtual void parse_args(int argc, char** argv) {
    args.parse_args(argc, argv);

    if (args.found_arg("--timeout"))
      timeout = std::stoi(args.get_arg("--timeout"));
    
#ifdef FST_ENABLE
    if (args.found_arg("--fst")) {
      fst_filename = args.get_arg("--fst");
      fst_on = true;
    }
#endif

#ifdef VCD_ENABLE    
    if (args.found_arg("--vcd")) {
      vcd_filename = args.get_arg("--vcd");
      vcd_on = true;
    }
#endif

    if (args.found_arg("-v"))
      log_level = 1;
    if (args.found_arg("-vv"))
      log_level = 2;
    
    if (args.found_arg("--help")) {
      args.print_help();
      exit(0);
    }
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

  ArgumentParser args;

  // Force end simulation after this many cycles.
  uint64_t timeout;

private:
  // Generate VCD/FST trace file?
#ifdef VCD_ENABLE
  bool vcd_on;
  string vcd_filename;
  VerilatedVcdC vcd_trace;
#endif

#ifdef FST_ENABLE
  bool fst_on;
  string fst_filename;
  VerilatedFstC fst_trace;
#endif

};


// A simulator which can execute RISC-V binaries.
template<class DUT>
class RISCVSimulation : public Simulation<DUT> {
public:

  RISCVSimulation(string name) : 
      Simulation<DUT>(name) {
    main_memory_latency = 10;
    csv_on = false;
    exit_code = 0;

    this->args.set_description("Usage: " + name + " [simulator args] <program> [program args]");
    this->args.add_argument("--memory-latency", "Set main memory latency to a given number of cycles", ArgumentParser::ARGS_ONE);
    this->args.add_argument("--csv", "Dump a CSV trace to a file (mainly for riscv-dv)", ArgumentParser::ARGS_ONE);
  }

protected:

  // To be implemented by subclasses.
  virtual MemoryAddress get_program_counter() = 0;
  virtual instr_trace_t get_trace_info() = 0;

  // Initialise all active traces.
  virtual void trace_init() {
    Simulation<DUT>::trace_init();

    if (csv_on) {
      csv_trace.open(csv_filename);

      // This is a subset of the required fields for riscv-dv. The remaining
      // ones are added in with a separate script which can decode instructions.
      csv_trace << "pc,gpr,csr,binary,mode\n";
    }
  }

  // Dump information after state has changed.
  virtual void trace_state_change() {
    Simulation<DUT>::trace_state_change();

    // TODO: ensure this is happening on the expected clock edge.
    if (get_program_counter() != pc) {
      pc = get_program_counter();
      MUNTJAC_LOG(1) << "PC: 0x" << std::hex << pc << std::dec << endl;

      if (csv_on)
        csv_output_line(csv_trace);
    }
  }

  // Close all active traces.
  virtual void trace_close() {
    Simulation<DUT>::trace_close();

    if (csv_on) {
      csv_trace.flush();
      csv_trace.close();
    }
  }

public:

  int return_code() const {
    return exit_code;
  }

  void run() {
    pc = 0;

    this->trace_init();

    this->init();
    this->reset();
    
    this->cycle_second_half();

    while (!Verilated::gotFinish() && this->cycle < this->timeout) {
      this->set_clock(1);
      this->cycle_first_half();
      this->trace_state_change();
      this->cycle += 0.5;

      this->set_clock(0);
      this->cycle_second_half();
      this->trace_state_change();
      this->cycle += 0.5;
    }

    this->end_simulation();

    this->trace_close();

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

  virtual void parse_args(int argc, char** argv) {
    if (argc == 0) {
      this->args.print_help();
      exit(0);
    }

    Simulation<DUT>::parse_args(argc, argv);

    // If we found an unknown argument and it doesn't look like a flag, assume
    // it's the binary to execute.
    if (this->args.get_args_parsed() < argc) {
      int pos = this->args.get_args_parsed();
      string name(argv[pos]);

      if (name[0] == '-')
        throw InvalidArgumentException(name, pos);
      else
        binary_position = pos;
    }

    if (this->args.found_arg("--memory-latency"))
      main_memory_latency = std::stoi(this->args.get_arg("--memory-latency"));
    
    if (this->args.found_arg("--csv")) {
      csv_filename = this->args.get_arg("--csv");
      csv_on = true;
    }

    read_binary(argc - binary_position, argv + binary_position);
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

  MemoryAddress pc;

  // Generate CSV trace file?
  bool csv_on;
  string csv_filename;
  ofstream csv_trace;

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
