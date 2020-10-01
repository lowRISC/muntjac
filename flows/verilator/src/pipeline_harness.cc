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
#include "page_table_walker.h"

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

// Sign-extend the lowest `bytes` of `original` to create a signed 64-bit
// integer.
int64_t sign_extend(uint64_t original, size_t bytes) {
  int shift = 64 - (bytes * 8);
  int64_t result = original;
  return (result << shift) >> shift;
}

// TODO: move this into the main memory class.
// Select the appropriate access fault exception code for the given operation.
exc_cause_e access_fault(MemoryOperation operation) {
  switch (operation) {
    case MEM_LOAD:
    case MEM_LR:
      return EXC_CAUSE_LOAD_ACCESS_FAULT;

    case MEM_STORE:
    case MEM_SC:
    case MEM_AMO:
      return EXC_CAUSE_STORE_ACCESS_FAULT;

    case MEM_FETCH:
      return EXC_CAUSE_INSTR_ACCESS_FAULT;

    default:
      assert(false);
      break;
  }
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
      dut(dut),
      page_table_walker(memory) {
    // Nothing
  }

protected:

  virtual bool can_receive_request() {
    return dut.icache_req_valid;
  }

  virtual void get_request() {
    assert(can_receive_request());

    // Always fetch from an aligned 4-byte block. If the lower bits were
    // non-zero, the pipeline will extract the required part.
    MemoryAddress address = dut.icache_req_pc & ~0x3;

    // Do virtual -> physical address translation if necessary.
    AddressTranslationProtection64 atp(dut.icache_req_atp);
    if (atp.mode() != ATP_MODE_BARE) {
      ptw_response_t response = page_table_walker.translate(
        address,
        MEM_FETCH,
        dut.icache_req_prv,
        dut.icache_req_sum,
        false,  // MXR bit not needed by icache
        atp
      );

      if (response.exception == EXC_CAUSE_NONE)
        address = response.physical_address;
      else {
        queue_response(address, response.exception);
        return;
      }
    }

    // TODO: move this into the main memory class.
    if (address > Sv39::MAX_PHYSICAL_ADDRESS) {
      queue_response(address, access_fault(MEM_FETCH));
      return;
    }

    uint32_t instruction = memory.read32(address);
    queue_response(instruction);
  }

  virtual bool can_send_response() {
    return true;
  }

  virtual void send_response(response_t& response) {
    dut.icache_resp_instr = response.data;
    dut.icache_resp_valid = 1;
    dut.icache_resp_exception = (response.exception != EXC_CAUSE_NONE);

    if (dut.icache_resp_exception) {
      dut.icache_resp_ex_code = response.exception;

      // Invalidate the normal response. (Only dcache does this?)
      //dut.icache_resp_valid = 0;
    }

    response.all_sent = true;
  }

  virtual void clear_response() {
    dut.icache_resp_valid = 0;
    dut.icache_resp_exception = 0;
  }

private:

  DUT& dut;
  PageTableWalkerSv39 page_table_walker;
};

class DataPort : public MemoryPort<uint64_t> {
public:
  DataPort(DUT& dut, MainMemory& memory, uint latency) :
      MemoryPort<uint64_t>(memory, latency),
      dut(dut),
      page_table_walker(memory) {
    clear_all_reservations();
  }

protected:

  virtual bool can_receive_request() {
    return dut.dcache_req_valid;
  }

  virtual void get_request() {
    assert(can_receive_request());

    MemoryAddress address = dut.dcache_req_address;
    uint64_t operand = dut.dcache_req_value;

    // Do virtual -> physical address translation if necessary.
    AddressTranslationProtection64 atp(dut.dcache_req_atp);
    if (atp.mode() != ATP_MODE_BARE) {
      ptw_response_t response = page_table_walker.translate(
        address,
        (MemoryOperation)dut.dcache_req_op,
        dut.dcache_req_prv,
        dut.dcache_req_sum,
        dut.dcache_req_mxr,
        atp
      );

      if (response.exception == EXC_CAUSE_NONE)
        address = response.physical_address;
      else {
        queue_response(address, response.exception);
        return;
      }
    }

    // TODO: move this into the main memory class.
    if (address > Sv39::MAX_PHYSICAL_ADDRESS) {
      queue_response(address, access_fault((MemoryOperation)dut.dcache_req_op));
      return;
    }

    uint64_t data_read = 0;
    uint64_t data_write = 0;

    // Data read.
    switch (dut.dcache_req_op) {
      case MEM_LOAD:
      case MEM_LR:
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
        data_write = operand;
        break;

      default:
        MUNTJAC_ERROR << "Unsupported memory operation: " << dut.dcache_req_op << endl;
        exit(1);
        break;
    }

    // Sign extend data for signed loads and all atomics.
    if ((dut.dcache_req_op == MEM_LOAD && !dut.dcache_req_unsigned) ||
        (dut.dcache_req_op == MEM_AMO) ||
        (dut.dcache_req_op == MEM_LR)) {
      size_t bytes = 1 << dut.dcache_req_size;
      data_read = sign_extend(data_read, bytes);
      operand = sign_extend(operand, bytes);
    }

    // Atomic data update.
    if (dut.dcache_req_op == MEM_AMO) {
      switch (dut.dcache_req_amo >> 2) {
        case 0: data_write = data_read + operand; break;
        case 1: data_write = operand; break;
        case 4: data_write = data_read ^ operand; break;
        case 8: data_write = data_read | operand; break;
        case 12: data_write = data_read & operand; break;
        case 16: data_write = (int64_t)data_read < (int64_t)operand ? data_read : operand; break;
        case 20: data_write = (int64_t)data_read < (int64_t)operand ? operand : data_read; break;
        case 24: data_write = data_read < operand ? data_read : operand; break;
        case 28: data_write = data_read < operand ? operand : data_read; break;

        default:
          MUNTJAC_ERROR << "Unsupported atomic memory operation: " << (int)dut.dcache_req_amo << endl;
          exit(1);
          break;
      }
    }

    if (dut.dcache_req_op == MEM_LR)
      make_reservation(address);

    // Data write.
    switch (dut.dcache_req_op) {
      case MEM_LOAD:
      case MEM_LR:
        // No data write.
        break;

      case MEM_SC:
        if (check_reservation(address))
          data_read = 0;
          // no break: fall-through to MEM_STORE
        else {
          data_read = 1;
          break;
        }
      case MEM_AMO:
      case MEM_STORE:
        // Not all request sizes are valid for all memory operations, but I
        // ignore that.
        switch (dut.dcache_req_size) {
          case 0: memory.write8(address, (uint8_t)data_write); break;
          case 1: memory.write16(address, (uint16_t)data_write); break;
          case 2: memory.write32(address, (uint32_t)data_write); break;
          case 3: memory.write64(address, data_write); break;
          default:
            MUNTJAC_ERROR << "Unsupported memory request size: " << (int)dut.dcache_req_size << endl;
            exit(1);
            break;
        }
        clear_reservation(address);
        break;

      default:
        MUNTJAC_ERROR << "Unsupported memory operation: " << (int)dut.dcache_req_op << endl;
        exit(1);
        break;
    }

    // All memory operations must send a response. Even if there is no payload,
    // there may have been an exception.
    queue_response(data_read);

  }

  virtual bool can_send_response() {
    return true;
  }

  virtual void send_response(response_t& response) {
    dut.dcache_resp_value = response.data;
    dut.dcache_resp_valid = 1;
    dut.dcache_ex_valid = (response.exception != EXC_CAUSE_NONE);

    if (dut.dcache_ex_valid) {
      // Verilator breaks an exception_t (4-bit cause, 64-bit payload) down into
      // an array of 3 32-bit values. Need to do some unpacking to get the
      // information across properly.
      dut.dcache_ex_exception[2] = response.exception;
      dut.dcache_ex_exception[1] = response.data >> 32;
      dut.dcache_ex_exception[0] = response.data & 0xFFFFFFFF;

      // Invalidate the normal response.
      dut.dcache_resp_valid = 0;
    }

    response.all_sent = true;
  }

  virtual void clear_response() {
    dut.dcache_resp_valid = 0;
    dut.dcache_ex_valid = 0;

    // Also respond immediately to SFENCE signals (and clear the response when
    // the signal is deasserted again).
    dut.dcache_notif_ready = dut.dcache_notif_valid;

    if (dut.dcache_notif_valid)
      clear_all_reservations();
  }

private:

  // Do the minimum possible to support load-reserved/store-conditional.
  // Maintain a single reserved address, and clear it whenever any memory is
  // written.
  // Better performance is possible, but if you're using a simulated d-cache,
  // you probably don't care about performance.
  MemoryAddress reserved;
  bool reservation_valid;

  void make_reservation(MemoryAddress address) {
    reserved = address;
    reservation_valid = true;
  }
  bool check_reservation(MemoryAddress address) {
    return reservation_valid && (reserved == address);
  }
  void clear_reservation(MemoryAddress address) {
    clear_all_reservations();
  }
  void clear_all_reservations() {
    reservation_valid = false;
  }

  DUT& dut;
  PageTableWalkerSv39 page_table_walker;
};

void init(DUT& dut) {
  cycle = 0.0;

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

void reset(DUT& dut, MemoryAddress program_counter) {
  dut.rst_ni = 0;

  for (int i=0; i<10; i++) {
    dut.eval();
    dut.clk_i = !dut.clk_i;
  }

  dut.rst_ni = 1;
  dut.pipeline_wrapper->write_reset_pc(program_counter);
  dut.eval();
}

// Trap on accesses to magic memory addresses.
MemoryAddress tohost = -1;
MemoryAddress fromhost = -1;
bool is_system_call(MemoryAddress address, uint64_t write_data) {
  return (address == tohost) || (address == fromhost);
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
  cout << "  --memory-latency=X\tSet main memory latency to X cycles" << endl;
  cout << "  --timeout=X\t\tForce end of simulation after X cycles" << endl;
  cout << "  --trace=X\t\tDump VCD output to file X" << endl;
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

    if (arg_string.rfind("--memory-latency", 0) == 0) {
      string value = arg_string.substr(arg_string.find("=")+1, arg_string.size());
      main_memory_latency = std::stoi(value);
    }
    else if (arg_string.rfind("--timeout", 0) == 0) {
      string value = arg_string.substr(arg_string.find("=")+1, arg_string.size());
      timeout = std::stoi(value);
    }
    else if (arg_string.rfind("--trace", 0) == 0) {
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

  // System calls: this may be specific to riscv-tests.
  tohost = BinaryParser::symbol_location(argv[arg], "tohost");
  fromhost = BinaryParser::symbol_location(argv[arg], "fromhost");

  VerilatedVcdC trace;
  if (trace_on) {
    Verilated::traceEverOn(true);
  	dut.trace(&trace, 100);
  	trace.open(trace_file.c_str());
  }

  init(dut);
  reset(dut, entry_point);

  while (!Verilated::gotFinish() && cycle < timeout) {
    dut.clk_i = 1;

    dut.eval();

    if (trace_on) {
      trace.dump((uint64_t)(10*cycle));
      trace.flush();
    }


    cycle += 0.5;
    dut.clk_i = 0;

    // The pipeline updates its outputs on the posedge, so we need:
    //   posedge -> eval -> get_inputs
    instruction_port.get_inputs(cycle);
    data_port.get_inputs(cycle);

    dut.eval();

    // The pipeline may respond to these signals combinatorically, and then
    // confirm a state change on the next posedge, so we need:
    //   set_outputs -> eval -> posedge -> eval
    instruction_port.set_outputs(cycle);
    data_port.set_outputs(cycle);

    // Could have extra trace dumps between interface activity and dut activity.
    // If so, make small offsets to the dump times, e.g. 10*cycle + 2.
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
