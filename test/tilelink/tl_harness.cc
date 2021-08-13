// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Test harness for a TileLink network.

#include "logs.h"
#include "simulation.h"

#include <verilated.h>
#include "Vtl_wrapper.h"

#include "tilelink.h"

typedef Vtl_wrapper DUT;

class TileLinkSimulation : public Simulation<DUT> {
public:
  TileLinkSimulation(string name, int argc, char** argv) :
      Simulation<DUT>(name, argc, argv) {
    // Nothing
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
};


// Need to implement a few globally-accessible values/functions.

// 0 = no logging
// 1 = all logging
// Potential to add more options here.
int log_level = 0;

TileLinkSimulation* the_sim;

double sc_time_stamp() {
  return the_sim->simulation_time();
}
bool is_system_call(MemoryAddress address, uint64_t write_data) {
  return false;
}
void system_call(MemoryAddress address, uint64_t write_data) {}


tl_a basic_a_request() {
  tl_a request;
  request.opcode = 0; // PutFullData
  request.param = 0;
  request.size = 3; // 2^3 = 8 bytes = 64 bits
  request.source = 0;
  request.address = 0x00003000; // Should be routed to device 0
  request.mask = 0xFF;
  request.corrupt = false;
  request.data = 0xDEADBEEF;

  return request;
}

tl_d basic_d_response(int device, tl_a& request) {
  tl_d response;

  if (request.opcode == 0) // PutFullData
    response.opcode = 0;
  else if (request.opcode == 4) // Get
    response.opcode = 1;
  else
    assert(false && "Unsupported request opcode");

  response.param = 0;
  response.size = request.size;
  response.source = request.source;
  response.sink = device;
  response.denied = false;
  response.corrupt = false;
  response.data = 0x12345678;

  return response;
}


// Normal write operation (should pass).
void valid_write_operation(TileLinkSimulation& sim) {
  tl_a request = basic_a_request();
  request.opcode = 0; // PutFullData
  sim.send_a(0, request);

  tl_a req_received = sim.await_a(0);
  assert(req_received.address == request.address);
  assert(req_received.opcode == request.opcode);
  assert(req_received.mask == request.mask);
  assert(req_received.data == request.data);

  tl_d response = basic_d_response(0, req_received);
  sim.send_d(0, response);

  tl_d resp_received = sim.await_d(0);
  assert(!resp_received.denied);
  assert(!resp_received.corrupt);
  assert(resp_received.source == request.source);
  assert(resp_received.opcode == 0); // AccessAck (for Put requests)
}

// Normal read operation (should pass).
void valid_read_operation(TileLinkSimulation& sim) {
  tl_a request = basic_a_request();
  request.opcode = 4; // Get
  request.source = 1;
  sim.send_a(request.source, request);

  tl_a req_received = sim.await_a(0);
  assert(req_received.address == request.address);
  assert(req_received.opcode == request.opcode);
  assert(req_received.mask == request.mask);

  tl_d response = basic_d_response(0, req_received);
  sim.send_d(0, response);

  tl_d resp_received = sim.await_d(request.source);
  assert(!resp_received.denied);
  assert(!resp_received.corrupt);
  assert(resp_received.data == response.data);
  assert(resp_received.source == request.source);
  assert(resp_received.opcode == 1); // AccessAckData (for Get and Atomic requests)
}

// Send from host 1 to device 1 (should pass).
void valid_dev1_operation(TileLinkSimulation& sim) {
  tl_a request = basic_a_request();
  request.address = 0x10003000;
  request.source = 1;
  sim.send_a(1, request);

  tl_a req_received = sim.await_a(1);
  assert(req_received.address == request.address);
  assert(req_received.opcode == request.opcode);
  assert(req_received.mask == request.mask);
  assert(req_received.data == request.data);

  tl_d response = basic_d_response(1, req_received);
  sim.send_d(1, response);

  tl_d resp_received = sim.await_d(1);
  assert(!resp_received.denied);
  assert(!resp_received.corrupt);
  assert(resp_received.source == request.source);
  assert(resp_received.opcode == 0); // AccessAck (for Put requests)
}

// Multiple simultaneous requests from multiple sources (should pass)
void multiple_valid_requests(TileLinkSimulation& sim) {
  // dev0 request
  tl_a dev0_request = basic_a_request();
  dev0_request.source = 0;
  sim.send_a(0, dev0_request);

  tl_a dev0_received = sim.await_a(0);
  
  // dev1 request
  tl_a dev1_request = basic_a_request();
  dev1_request.address = 0x10003000;
  dev1_request.source = 1;
  sim.send_a(1, dev1_request);

  tl_a dev1_received = sim.await_a(1);

  // dev1 response
  tl_d dev1_response = basic_d_response(1, dev1_received);
  sim.send_d(1, dev1_response);

  tl_d dev1_d = sim.await_d(1);
  assert(!dev1_d.denied);
  assert(!dev1_d.corrupt);
  assert(dev1_d.source == dev1_request.source);
  assert(dev1_d.opcode == 0); // AccessAck (for Put requests)

  // dev0 response
  tl_d dev0_response = basic_d_response(0, dev0_received);
  sim.send_d(0, dev0_response);

  tl_d dev0_d = sim.await_d(0);
  assert(!dev0_d.denied);
  assert(!dev0_d.corrupt);
  assert(dev0_d.source == dev0_request.source);
  assert(dev0_d.opcode == 0); // AccessAck (for Put requests)
}

// Write operation with 2 beats. Should pass on TL-C and TL-UH.
void multibeat_tlc(TileLinkSimulation& sim) {
  tl_a request = basic_a_request();
  request.opcode = 0; // PutFullData
  request.size = 4; // 2^4 = 16 bytes = 2 beats
  sim.send_a(0, request);

  tl_a req_received = sim.await_a(0);
  assert(req_received.data == request.data);

  tl_a request2 = request;
  request2.address += 8;
  request2.data = 0x87654321;
  sim.send_a(0, request2);

  tl_a req2_received = sim.await_a(0);
  assert(req2_received.data == request2.data);

  tl_d response = basic_d_response(0, req2_received);
  sim.send_d(0, response);

  tl_d resp_received = sim.await_d(0);
}

// Write operation with 2 beats. Illegal on TL-UL, but adapter should help.
void multibeat_tlul(TileLinkSimulation& sim) {
  tl_a request = basic_a_request();
  request.opcode = 0; // PutFullData
  request.size = 4; // 2^4 = 16 bytes = 2 beats
  request.address = 0x20003000; // To device 2 (TL-UL)
  sim.send_a(0, request);

  tl_a req_received = sim.await_a(2);
  assert(req_received.data == request.data);

  // TL-UL adapter needs to split request in two, so need to ack each part.
  tl_d response = basic_d_response(2, req_received);
  sim.send_d(2, response);

  // TODO: test different interleavings of the beats.

  tl_a request2 = request;
  request2.address += 8;
  request2.data = 0x87654321;
  sim.send_a(0, request2);

  tl_a req2_received = sim.await_a(2);
  assert(req2_received.data == request2.data);

  tl_d response2 = basic_d_response(2, req2_received);
  sim.send_d(2, response2);

  tl_d resp2_received = sim.await_d(0);
}

// Only requests with data payloads are allowed to be marked corrupt.
void a_corrupt_payload(TileLinkSimulation& sim) {
  tl_a request = basic_a_request();
  request.opcode = 0; // PutFullData (so request contains data)
  request.corrupt = 1;
  sim.send_a(0, request);
  tl_a req_received = sim.await_a(0);

  tl_d response = basic_d_response(0, req_received);
  sim.send_d(0, response);
  tl_d resp_received = sim.await_d(0);
}

void all_passing_tests(TileLinkSimulation& sim) {
  valid_write_operation(sim);
  valid_read_operation(sim);
  valid_dev1_operation(sim);
  multiple_valid_requests(sim);
  multibeat_tlc(sim);
  multibeat_tlul(sim);
  a_corrupt_payload(sim);
}

// Illegal A opcode
void a_illegal_opcode(TileLinkSimulation& sim) {
  tl_a request = basic_a_request();
  request.address = 0x20003000; // Device 2, TL-UL.
  request.opcode = 2; // ArithmeticData - only illegal for TL-UL.

  sim.send_a(0, request);
}

// Illegal A param
void a_illegal_param(TileLinkSimulation& sim) {
  tl_a request = basic_a_request();
  request.param = 2; // Reserved - only 0 is allowed.

  sim.send_a(0, request);
}

// Size too small for mask
void a_size_too_small(TileLinkSimulation& sim) {
  tl_a request = basic_a_request();
  request.size = 1;
  request.mask = 0xF;
  request.opcode = 4; // Get

  sim.send_a(0, request);
}

// Size doesn't match mask when doing a "full" access
void a_size_mask_mismatch(TileLinkSimulation& sim) {
  tl_a request = basic_a_request();
  request.size = 3;
  request.mask = 0xF;
  request.opcode = 0; // PutFullData

  sim.send_a(0, request);
}

// Address not aligned to size
void a_unaligned_address(TileLinkSimulation& sim) {
  tl_a request = basic_a_request();
  request.address += 1;

  sim.send_a(0, request);
}

// Multibeat requests must increment the address by the width of the bus.
void a_multibeat_addr_inc(TileLinkSimulation& sim) {
  tl_a request = basic_a_request();
  request.opcode = 0; // PutFullData
  request.size = 4; // 2^4 = 16 bytes = 128 bits
  sim.send_a(0, request);

  tl_a req_received = sim.await_a(0);
  assert(req_received.data == request.data);

  tl_a request2 = request;
  request2.address += 0;  // Not allowed
  request2.data = 0x87654321;
  sim.send_a(0, request2);

  tl_a req2_received = sim.await_a(0);
  assert(req2_received.data == request2.data);

  tl_d response = basic_d_response(0, req2_received);
  sim.send_d(0, response);

  tl_d resp_received = sim.await_d(0);
}

// Multibeat requests must keep control signals constant (opcode, param, size,
// source).
void a_multibeat_ctrl_const(TileLinkSimulation& sim) {
  tl_a request = basic_a_request();
  request.opcode = 0; // PutFullData
  request.size = 4; // 2^4 = 16 bytes = 128 bits
  sim.send_a(0, request);

  tl_a req_received = sim.await_a(0);
  assert(req_received.data == request.data);

  tl_a request2 = request;
  request2.address += 8;
  request2.data = 0x87654321;
  request2.size = 3;  // Not allowed
  sim.send_a(0, request2);

  tl_a req2_received = sim.await_a(0);
  assert(req2_received.data == request2.data);

  tl_d response = basic_d_response(0, req2_received);
  sim.send_d(0, response);

  tl_d resp_received = sim.await_d(0);
}

// Too many beats in burst request.
void a_too_many_beats(TileLinkSimulation& sim) {
  tl_a request = basic_a_request();
  request.opcode = 0; // PutFullData
  request.size = 4; // 2^4 = 16 bytes = 128 bits = 2 beats
  sim.send_a(0, request);

  tl_a req_received = sim.await_a(0);
  assert(req_received.data == request.data);

  tl_a request2 = request;
  request2.address += 8;
  request2.data = 0x87654321;
  sim.send_a(0, request2);

  tl_a req2_received = sim.await_a(0);
  assert(req2_received.data == request2.data);

  tl_a request3 = request2;
  request3.address += 8;
  request3.data = 0x18273645;
  sim.send_a(0, request3);

  tl_a req3_received = sim.await_a(0);
  assert(req3_received.data == request3.data);

  tl_d response = basic_d_response(0, req3_received);
  sim.send_d(0, response);

  tl_d resp_received = sim.await_d(0);
}

// Too few beats in burst request.
void a_too_few_beats(TileLinkSimulation& sim) {
  tl_a request = basic_a_request();
  request.opcode = 0; // PutFullData
  request.size = 4; // 2^4 = 16 bytes = 128 bits = 2 beats
  sim.send_a(0, request);

  tl_a req_received = sim.await_a(0);
  assert(req_received.data == request.data);

  tl_d response = basic_d_response(0, req_received);
  sim.send_d(0, response);

  tl_d resp_received = sim.await_d(0);
}

// Non-contiguous mask
void a_noncontiguous_mask(TileLinkSimulation& sim) {
  tl_a request = basic_a_request();
  request.opcode = 4; // Get
  request.size = 2;
  request.mask = 0x33;

  sim.send_a(0, request);
}

// Multibeat requests must have all bits of the mask set high.
void a_multibeat_bad_mask(TileLinkSimulation& sim) {
  tl_a request = basic_a_request();
  request.opcode = 0; // PutFullData
  request.size = 4; // 2^4 = 16 bytes = 128 bits
  sim.send_a(0, request);

  tl_a req_received = sim.await_a(0);
  assert(req_received.data == request.data);

  tl_a request2 = request;
  request2.address += 8;
  request2.data = 0x87654321;
  request2.mask = 0xF0;  // Not allowed
  sim.send_a(0, request2);

  tl_a req2_received = sim.await_a(0);
  assert(req2_received.data == request2.data);

  tl_d response = basic_d_response(0, req_received);
  sim.send_d(0, response);

  tl_d resp_received = sim.await_d(0);
}

// Masks must be aligned with the bus width (64 bits in this case).
// If a narrow request is made and the address is not also aligned with the bus
// width, the mask (and data) must be offset within the bus.
void a_misaligned_mask(TileLinkSimulation& sim) {
  tl_a request = basic_a_request();
  request.opcode = 0; // PutFullData
  request.size = 0; // 1 byte
  request.address = 0x3001; // Data and mask should be offset by 1: mask = 0x2
  request.mask = 0x4;
  sim.send_a(0, request);

  tl_a req_received = sim.await_a(0);
  tl_d response = basic_d_response(0, req_received);
  sim.send_d(0, response);
  tl_d resp_received = sim.await_d(0);
}

// Only requests with data payloads are allowed to be marked corrupt.
void a_corrupt_without_payload(TileLinkSimulation& sim) {
  tl_a request = basic_a_request();
  request.opcode = 4; // Get (so request contains no data)
  request.corrupt = 1;
  sim.send_a(0, request);
  tl_a req_received = sim.await_a(0);

  tl_d response = basic_d_response(0, req_received);
  sim.send_d(0, response);
  tl_d resp_received = sim.await_d(0);
}

// Illegal D opcode
void d_illegal_opcode(TileLinkSimulation& sim) {
  tl_a request = basic_a_request();
  sim.send_a(0, request);
  tl_a req_received = sim.await_a(0);

  tl_d response = basic_d_response(0, req_received);
  response.opcode = 2;
  sim.send_d(0, response);
  tl_d resp_received = sim.await_d(0);
}

// Illegal D param
void d_illegal_param(TileLinkSimulation& sim) {
  tl_a request = basic_a_request();
  sim.send_a(0, request);
  tl_a req_received = sim.await_a(0);

  tl_d response = basic_d_response(0, req_received);
  response.param = 2;
  sim.send_d(0, response);
  tl_d resp_received = sim.await_d(0);
}

// Response size differs from request size
void d_size_mismatch(TileLinkSimulation& sim) {
  tl_a request = basic_a_request();
  sim.send_a(0, request);
  tl_a req_received = sim.await_a(0);

  tl_d response = basic_d_response(0, req_received);
  response.size = request.size - 1;
  sim.send_d(0, response);
  tl_d resp_received = sim.await_d(0);
}

// Too many beats in burst response
// This will probably get picked up as a "response without request", as the
// request will be cleared from the assertion state when the expected number of
// beats have arrived.
void d_too_many_beats(TileLinkSimulation& sim) {
  tl_a request = basic_a_request();
  request.opcode = 4; // Get
  request.size = 4; // 2**4 = 16 bytes = 2 beats
  sim.send_a(0, request);
  tl_a req_received = sim.await_a(0);

  tl_d response = basic_d_response(0, req_received);
  sim.send_d(0, response);
  tl_d resp_received = sim.await_d(0);

  tl_d response2 = response;
  response2.data = 0x87654321;
  sim.send_d(0, response2);
  tl_d resp2_received = sim.await_d(0);

  tl_d response3 = response;
  response3.data = 0x18273645;
  sim.send_d(0, response3);
  tl_d resp3_received = sim.await_d(0);
}

// Too few beats in burst response
// This will probably get picked up as an "outstanding request at end of sim"
void d_too_few_beats(TileLinkSimulation& sim) {
  tl_a request = basic_a_request();
  request.opcode = 4; // Get
  request.size = 4; // 2**4 = 16 bytes = 2 beats
  sim.send_a(0, request);
  tl_a req_received = sim.await_a(0);

  tl_d response = basic_d_response(0, req_received);
  sim.send_d(0, response);
  tl_d resp_received = sim.await_d(0);
}

// Response without request from same source
void d_response_without_request(TileLinkSimulation& sim) {
  tl_a request = basic_a_request();
  sim.send_a(0, request);
  tl_a req_received = sim.await_a(0);

  tl_d response = basic_d_response(0, req_received);
  response.source = request.source + 1;
  sim.send_d(0, response);
  tl_d resp_received = sim.await_d(0);
}

// Request denied without corrupting response.
void d_denied_without_corrupt(TileLinkSimulation& sim) {
  tl_a request = basic_a_request();
  request.opcode = 4;  // Get
  sim.send_a(0, request);
  tl_a req_received = sim.await_a(0);

  tl_d response = basic_d_response(0, req_received);
  response.denied = 1;
  response.corrupt = 0;
  sim.send_d(0, response);
  tl_d resp_received = sim.await_d(0);
}

typedef void (*tl_test_fn)(TileLinkSimulation& sim);
typedef struct {
  tl_test_fn function;
  string     description;
} tl_test;

// TODO: more legal operation/param/channel combinations
//       B/C/E channel tests (though assertions are mostly copied from A/D)
#define NUM_TESTS 28
tl_test tests[NUM_TESTS] = {
  {all_passing_tests, "All tests which should trigger no assertions"},
  {valid_write_operation, "Valid write operation (should pass)"},
  {valid_read_operation, "Valid read operation (should pass)"},
  {valid_dev1_operation, "Non-default host/device (should pass)"},
  {multiple_valid_requests, "Concurrent requests (should pass)"},
  {multibeat_tlc, "Multibeat request (should pass)"},
  {multibeat_tlul, "Multibeat request on TL-UL (should pass)"},
  {a_corrupt_payload, "Request with payload is marked corrupt (should pass)"},
  {a_illegal_opcode, "Illegal opcode on A channel"},
  {a_illegal_param, "Illegal parameter on A channel"},
  {a_size_too_small, "Request size smaller than mask"},
  {a_size_mask_mismatch, "Request size doesn't match mask for \"full\" access"},
  {a_unaligned_address, "Misaligned request address"},
  {a_multibeat_addr_inc, "Multibeat requests must increment the address"},
  {a_multibeat_ctrl_const, "Multibeat requests must keep control signals constant"},
  {a_too_many_beats, "Multibeat request with too many beats"},
  {a_too_few_beats, "Multibeat request with too few beats"},
  {a_noncontiguous_mask, "Noncontiguous mask for a \"full\" request"},
  {a_multibeat_bad_mask, "Multibeat request with incomplete mask"},
  {a_misaligned_mask, "Mask is correct size but in wrong position"},
  {a_corrupt_without_payload, "Request without payload is marked corrupt"},
  {d_illegal_opcode, "Illegal opcode on D channel"},
  {d_illegal_param, "Illegal parameter on D channel"},
  {d_size_mismatch, "Response size differs from request size"},
  {d_too_many_beats, "Multibeat response with too many beats"},
  {d_too_few_beats, "Multibeat response with too few beats"},
  {d_response_without_request, "Response received with no matching request"},
  {d_denied_without_corrupt, "Response denied but not marked corrupt"}
};

int main(int argc, char** argv) {
  // Ignore the first argument (this binary).
  // TODO: argument parsing doesn't work properly at the moment: can't get a VCD
  //       trace for a broken test.
  TileLinkSimulation sim("tilelink", argc - 1, argv + 1);
  the_sim = &sim;

  sim.init();
  sim.reset();

  if (argc <= 1) {
    cout << "Please select one or more tests:" << endl;
    for (int i=0; i<NUM_TESTS; i++)
      cout << "\t" << i << "\t" << tests[i].description << endl;
    return 1;
  }
  else {
    for (int i=1; i<argc; i++) {
      int selected_test = atoi(argv[i]);

      assert(selected_test < NUM_TESTS);

      cout << "Test selected: " << tests[selected_test].description << endl;
      tests[selected_test].function(sim);

      // Add a few empty cycles to allow signals to propagate.
      for (int wait=0; wait<100; wait++)
        sim.next_cycle();
    }

    sim.end_simulation();

    cout << "No assertions triggered" << endl;
  }

  return 0;
}
