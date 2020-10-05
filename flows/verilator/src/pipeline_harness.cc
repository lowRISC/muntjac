// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Test harness for a core pipeline (no caches).
// The core has two parallel connections to memory (instructins and data), so
// performance figures may not be accurate.

#include <iostream>
#include <iomanip>

#include "binary_parser.h"
#include "main_memory.h"
#include "memory_port.h"

#include <verilated.h>
#include <verilated_vcd_c.h>
#include "Vpipeline_wrapper.h"
#include "Vpipeline_wrapper_pipeline_wrapper.h"  // Verilator internals

typedef Vpipeline_wrapper DUT;

using std::cout;
using std::cerr;
using std::endl;
using std::string;

uint return_code = 0;

// Need to define this function when not compiling against SystemC.
double cycle;
double sc_time_stamp() {
  return cycle;
}

// 0 = no logging
// 1 = all logging
// Potential to add more options here.
int log_level = 0;
#define MUNTJAC_LOG(LEVEL) if (log_level >= LEVEL) cout << "[sim " << (int)sc_time_stamp() << "] "
#define MUNTJAC_ERROR cerr << "[sim] "

class InstructionPort : public MemoryPort<uint32_t> {
public:
  InstructionPort(DUT& dut, MainMemory& memory, uint latency) :
      MemoryPort<uint32_t>(memory, latency),
      dut(dut) {
    // Nothing.
  }

protected:

  virtual bool can_receive_request() {
    return dut.icache_req_valid;
  }

  virtual void get_request() {
    assert(can_receive_request());

    // TODO:
    //  * req_reason
    //  * req_prv
    //  * req_sum
    //  * req_atp

    MemoryAddress address = dut.icache_req_pc;
    uint32_t instruction = memory.read32(address);
    queue_response(instruction);
  }

  virtual bool can_send_response() {
    return true;
  }

  virtual void send_response(response_t& response) {
    dut.icache_resp_instr = response.data;
    dut.icache_resp_valid = 1;
    dut.icache_resp_exception = 0;
    response.all_sent = true;
  }

  virtual void clear_response() {
    dut.icache_resp_valid = 0;
  }

private:

  DUT& dut;
};

class DataPort : public MemoryPort<uint64_t> {
public:
  DataPort(DUT& dut, MainMemory& memory, uint latency) :
      MemoryPort<uint64_t>(memory, latency),
      dut(dut) {
    // Nothing.
  }

protected:

  virtual bool can_receive_request() {
    return dut.dcache_req_valid;
  }

  virtual void get_request() {
    assert(can_receive_request());

    // TODO:
    //  * req_prv
    //  * req_sum
    //  * req_mxr
    //  * req_atp

    MemoryAddress address = dut.dcache_req_address;

    uint64_t data_read = 0;
    uint64_t data_write = dut.dcache_req_value;

    // Data read.
    switch (dut.dcache_req_op) {
      case MEM_LOAD:
//      case MEM_LR:
      case MEM_AMO:
        // Not all request sizes are valid for all memory operations, but I
        // ignore that.
        switch (dut.dcache_req_size) {
          case 0: data_read = memory.read8(address); break;
          case 1: data_read = memory.read16(address); break;
          case 2: data_read = memory.read32(address); break;
          case 3: data_read = memory.read64(address); break;
          default:
            MUNTJAC_ERROR << "Unsupported memory request size: " << dut.dcache_req_size << endl;
            exit(1);
            break;
        }
        break;

      case MEM_STORE:
      case MEM_SC:
        // No data read.
        break;

      default:
        MUNTJAC_ERROR << "Unsupported memory operation: " << dut.dcache_req_op << endl;
        exit(1);
        break;
    }

    // Sign extension.
    if (dut.dcache_req_op == MEM_LOAD && !dut.dcache_req_unsigned) {
      int64_t signed_data = data_read;
      switch (dut.dcache_req_size) {
        case 0: data_read = (signed_data << 56) >> 56; break;
        case 1: data_read = (signed_data << 48) >> 48; break;
        case 2: data_read = (signed_data << 32) >> 32; break;
        case 3: break;
        default:
          MUNTJAC_ERROR << "Unsupported memory request size: " << dut.dcache_req_size << endl;
          exit(1);
          break;
      }
    }

    // Atomic data update.
    if (dut.dcache_req_op == MEM_AMO) {
      switch (dut.dcache_req_amo) {
        default:
          MUNTJAC_ERROR << "Unsupported atomic memory operation: " << dut.dcache_req_amo << endl;
          exit(1);
          break;
      }
    }

    // Data write.
    switch (dut.dcache_req_op) {
      case MEM_LOAD:
      case MEM_LR:
        // No data write.
        break;

      case MEM_AMO:
      case MEM_STORE:
//      case MEM_SC:
        // Not all request sizes are valid for all memory operations, but I
        // ignore that.
        switch (dut.dcache_req_size) {
          case 0: memory.write8(address, (uint8_t)data_write); break;
          case 1: memory.write16(address, (uint16_t)data_write); break;
          case 2: memory.write32(address, (uint32_t)data_write); break;
          case 3: memory.write64(address, data_write); break;
          default:
            MUNTJAC_ERROR << "Unsupported memory request size: " << dut.dcache_req_size << endl;
            exit(1);
            break;
        }
        break;

      default:
        MUNTJAC_ERROR << "Unsupported memory operation: " << dut.dcache_req_op << endl;
        exit(1);
        break;
    }

    bool has_response = (dut.dcache_req_op == MEM_LOAD) ||
                        (dut.dcache_req_op == MEM_LR) ||
                        (dut.dcache_req_op == MEM_AMO) ||
                        (dut.dcache_req_op == MEM_SC);

    if (has_response)
      queue_response(data_read);

  }

  virtual bool can_send_response() {
    return true;
  }

  virtual void send_response(response_t& response) {
    // TODO: resp_exception
    dut.dcache_resp_value = response.data;
    dut.dcache_resp_valid = 1;
    response.all_sent = true;
  }

  virtual void clear_response() {
    dut.dcache_resp_valid = 0;

    // Also respond immediately to SFENCE signals (and clear the response when
    // the signal is deasserted again).
    dut.dcache_notif_ready = dut.dcache_notif_valid;
  }

private:

  DUT& dut;
};

void init(DUT& dut) {
  cycle = 0.0;

  dut.clk_i = 0;
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

void reset(DUT& dut, MemoryAddress program_counter) {
  dut.rst_ni = 0;

  for (int i=0; i<10; i++) {
    dut.clk_i = !dut.clk_i;
    dut.eval();
    cycle += 0.5;
  }

  dut.rst_ni = 1;
  dut.eval();

  dut.pipeline_wrapper->write_reset_pc(program_counter);
}

// Trap on writes to a magic memory address.
// This behaviour may be specific to riscv-tests.
bool is_system_call(MemoryAddress address, uint64_t write_data) {
  return (address == 0x80001000);
}
void system_call(MemoryAddress address, uint64_t write_data) {
  assert(is_system_call(address, write_data));

  // putchar
  if ((write_data & 0xffffffffffffff00) == 0x101000000000000)
    putchar(write_data & 0xff);
  // exit
  else {
    MUNTJAC_LOG(0) << "Exiting with argument " << write_data << endl;

    if (write_data == 1)
      return_code = 0;
    else
      return_code = 1;

    Verilated::gotFinish(true);
  }
}

void print_help() {
  cout << "Muntjac pipeline simulator (no caches)." << endl;
  cout << endl;
  cout << "Usage: muntjac_pipeline [simulator args] <program> [program args]" << endl;
  cout << endl;
  cout << "Simulator arguments:" << endl;
  cout << "  -memory-latency=X\tSet main memory latency to X cycles" << endl;
  cout << "  -timeout=X\t\tForce end of simulation after X cycles" << endl;
  cout << "  -v\t\t\tDisplay additional information as simulation proceeds" << endl;
  cout << "  --help\t\tDisplay this information and exit" << endl;
}

int main(int argc, char** argv) {
  int main_memory_latency = 10;
  uint64_t timeout = 1000000;

  bool trace_on = false;
  string trace_file;

  // Check for simulation arguments. They all begin with a hyphen.
  int arg = 1; // Skip over argv[0] (this simulator)
  while ((arg < argc) && (argv[arg][0] == '-')) {
    string arg_string = argv[arg];

    if (arg_string.rfind("-memory-latency", 0) == 0) {
      string value = arg_string.substr(arg_string.find("=")+1, arg_string.size());
      main_memory_latency = std::stoi(value);

      // FIXME
      assert(main_memory_latency >= 2);
    }
    else if (arg_string.rfind("-timeout", 0) == 0) {
      string value = arg_string.substr(arg_string.find("=")+1, arg_string.size());
      timeout = std::stoi(value);
    }
    else if (arg_string.rfind("-trace", 0) == 0) {
      string value = arg_string.substr(arg_string.find("=")+1, arg_string.size());
      trace_file = value;
      trace_on = true;
    }
    else if (arg_string == "-v")
      log_level = 1;
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

  MainMemory memory;
  DUT dut;
  InstructionPort instruction_port(dut, memory, main_memory_latency);
  DataPort data_port(dut, memory, main_memory_latency);

  // Skip the first argument (this simulator).
  BinaryParser::load_elf(argc-arg, argv+arg, memory);
  MemoryAddress entry_point = BinaryParser::entry_point(argv[arg]);
  MemoryAddress pc = 0;

  VerilatedVcdC trace;
  if (trace_on) {
    Verilated::traceEverOn(true);
  	dut.trace(&trace, 100);
  	trace.open(trace_file.c_str());
  }

  init(dut);
  reset(dut, entry_point);

  while (!Verilated::gotFinish() && cycle < timeout) {
    dut.clk_i = !dut.clk_i;

    if (dut.clk_i) {
      instruction_port.cycle(cycle);
      data_port.cycle(cycle);
    }

    dut.eval();

    if (trace_on) {
      trace.dump((uint64_t)(10*cycle));
      trace.flush();
    }

    if (dut.dbg_pc_o != pc) {
      pc = dut.dbg_pc_o;
      MUNTJAC_LOG(1) << "PC: 0x" << std::hex << pc << std::dec << endl;
    }

    cycle += 0.5;
  }

  if (trace_on)
    trace.close();

  if (cycle >= timeout) {
    MUNTJAC_ERROR << "Simulation timed out after " << timeout << " cycles" << endl;
    exit(1);
  }

  return return_code;
}
