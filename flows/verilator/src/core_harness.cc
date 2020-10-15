// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Test harness for a core pipeline (no caches).
// The core has two parallel connections to memory (instructins and data), so
// performance figures may not be accurate.

#include "logs.h"
#include "simulation.h"
#include "memory_port.h"

#include "Vcore_wrapper.h"
#include "Vcore_wrapper_core_wrapper.h"  // Verilator internals

typedef Vcore_wrapper DUT;

template<typename DUT>
class MainMemoryPort : public MemoryPort<uint64_t> {
public:
  MainMemoryPort(DUT& dut, MainMemory& memory) :
      MemoryPort<uint64_t>(memory, 1),
      dut(dut) {
    // Nothing.
  }

protected:

  virtual bool can_receive_request() {
    return dut.mem_en_o;
  }

  virtual void get_request() {
    assert(can_receive_request());

    MemoryAddress address = dut.mem_addr_o << 3;

    uint64_t data_read = 0;
    uint64_t data_write = dut.mem_wdata_o;

    // Data read.
    data_read = memory.read64(address);

    // Data write.
    if (dut.mem_we_o) {
      if (dut.mem_wmask_o != 0b11111111) {
        MUNTJAC_ERROR << "Unsupported memory write mask: " << dut.mem_wmask_o << endl;
        exit(1);
      }
      memory.write64(address, data_write);
    }

    queue_response(data_read);
  }

  virtual bool can_send_response() {
    return true;
  }

  virtual void send_response(response_t& response) {
    dut.mem_rdata_i = response.data;
    response.all_sent = true;
  }

  virtual void clear_response() {
  }

private:

  DUT& dut;
};

template<typename DUT>
class IoMemoryPort : public MemoryPort<uint64_t> {
public:
  IoMemoryPort(DUT& dut, MainMemory& memory) :
      MemoryPort<uint64_t>(memory, 1),
      dut(dut) {
    // Nothing.
  }

protected:

  virtual bool can_receive_request() {
    return dut.io_en_o;
  }

  virtual void get_request() {
    assert(can_receive_request());

    MemoryAddress address = dut.io_addr_o << 3;

    uint64_t data_read = 0;
    uint64_t data_write = dut.io_wdata_o;

    // Data read.
    data_read = memory.read64(address);

    // Data write.
    if (dut.io_we_o) {
      switch (dut.io_wmask_o) {
        case 0b00000001: memory.write8(address + 0, (uint8_t)(data_write >> 0)); break;
        case 0b00000010: memory.write8(address + 1, (uint8_t)(data_write >> 8)); break;
        case 0b00000100: memory.write8(address + 2, (uint8_t)(data_write >> 16)); break;
        case 0b00001000: memory.write8(address + 3, (uint8_t)(data_write >> 24)); break;
        case 0b00010000: memory.write8(address + 4, (uint8_t)(data_write >> 32)); break;
        case 0b00100000: memory.write8(address + 5, (uint8_t)(data_write >> 40)); break;
        case 0b01000000: memory.write8(address + 6, (uint8_t)(data_write >> 48)); break;
        case 0b10000000: memory.write8(address + 7, (uint8_t)(data_write >> 56)); break;
        case 0b00000011: memory.write16(address + 0, (uint16_t)(data_write >> 0)); break;
        case 0b00001100: memory.write16(address + 2, (uint16_t)(data_write >> 16)); break;
        case 0b00110000: memory.write16(address + 4, (uint16_t)(data_write >> 32)); break;
        case 0b11000000: memory.write16(address + 6, (uint16_t)(data_write >> 48)); break;
        case 0b00001111: memory.write32(address + 0, (uint16_t)(data_write >> 0)); break;
        case 0b11110000: memory.write32(address + 4, (uint16_t)(data_write >> 32)); break;
        case 0b11111111: memory.write64(address, data_write); break;
        default:
          MUNTJAC_ERROR << "Unsupported memory write mask: " << dut.io_wmask_o << endl;
          exit(1);
          break;
      }
    }

    queue_response(data_read);
  }

  virtual bool can_send_response() {
    return true;
  }

  virtual void send_response(response_t& response) {
    dut.io_rdata_i = response.data;
    response.all_sent = true;
  }

  virtual void clear_response() {
  }

private:

  DUT& dut;
};

class CoreSimulation : public Simulation<DUT> {
public:
  CoreSimulation(string name, int argc, char** argv) :
      Simulation<DUT>(name, argc, argv),
      main_memory_port(dut, memory),
      io_memory_port(dut, memory) {
    // Nothing
  }

protected:

  virtual void set_clock(int value) {dut.clk_i = value;}
  virtual void set_reset(int value) {dut.rst_ni = !value;}
  virtual void set_entry_point(MemoryAddress pc) {
    dut.core_wrapper->write_reset_pc(pc);
  }
  virtual MemoryAddress get_program_counter() {return dut.dbg_pc_o;}

  virtual void init() {
    dut.clk_i = 1;
    dut.rst_ni = 1;

    dut.mem_rdata_i = 0xDEADBEEF;
    dut.io_rdata_i = 0xDEADBEEF;

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

    main_memory_port.set_outputs(simulation_time());
    io_memory_port.set_outputs(simulation_time());
  }

  virtual void cycle_second_half() {
    dut.eval();

    main_memory_port.get_inputs(simulation_time());
    io_memory_port.get_inputs(simulation_time());
  }

private:
  // Implement the main memory and IO memory interfaces.
  MainMemoryPort<DUT> main_memory_port;
  IoMemoryPort<DUT> io_memory_port;
};


// Need to implement a few globally-accessible values/functions.

// 0 = no logging
// 1 = all logging
// Potential to add more options here.
int log_level = 0;

CoreSimulation* the_sim;

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
  CoreSimulation sim("muntjac_core", argc - 1, argv + 1);
  the_sim = &sim;

  sim.run();

  return sim.return_code();
}
