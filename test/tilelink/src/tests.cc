// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include "tl_harness.h"

// TODO: for passing tests, run on many combinations of host/device
// TODO: more legal operation/param/channel combinations
// TODO: B/C/E channel tests (though assertions are mostly copied from A/D)

// TODO: address which is aligned at host, but enters wider channel so becomes misaligned

// Normal write operation (should pass).
void valid_write_operation(TileLinkSimulation& sim) {
  auto& host = sim.host(0);
  auto& device = sim.device(0);

  tl_a request = host.a.new_request(false);
  request.opcode = PutFullData;
  host.a.start_transaction(request.source);
  host.a.send(request);

  tl_a req_received = device.a.await();
  assert(req_received.address == request.address);
  assert(req_received.opcode == request.opcode);
  assert(req_received.mask == request.mask);
  assert(req_received.data == request.data);

  tl_d resp_received = host.d.await();
  assert(!resp_received.denied);
  assert(!resp_received.corrupt);
  assert(resp_received.source == request.source);
  assert(resp_received.opcode == AccessAck); // For Put requests
}

// Normal read operation (should pass).
void valid_read_operation(TileLinkSimulation& sim) {
  auto& host = sim.host(1);
  auto& device = sim.device(0);

  tl_a request = host.a.new_request(false);
  request.opcode = Get;
  host.a.start_transaction(request.source);
  host.a.send(request);
  device.d.change_next_beat({{"data", 0x1234}});

  tl_a req_received = device.a.await();
  assert(req_received.address == request.address);
  assert(req_received.opcode == request.opcode);
  assert(req_received.mask == request.mask);

  tl_d resp_received = host.d.await();
  assert(!resp_received.denied);
  assert(!resp_received.corrupt);
  assert(resp_received.data == 0x1234);
  assert(resp_received.source == request.source);
  assert(resp_received.opcode == AccessAckData); // For Get and Atomic requests
}

// Send from host 1 to device 1 (should pass).
void valid_dev1_operation(TileLinkSimulation& sim) {
  auto& host = sim.host(1);
  auto& device = sim.device(1);

  tl_a request = host.a.new_request(false);
  request.address = host.a.get_address(0x3000, 1);
  host.a.start_transaction(request.source);
  host.a.send(request);

  tl_a req_received = device.a.await();
  assert(req_received.address == request.address);
  assert(req_received.opcode == request.opcode);
  assert(req_received.mask == request.mask);
  assert(req_received.data == request.data);

  tl_d resp_received = host.d.await();
  assert(!resp_received.denied);
  assert(!resp_received.corrupt);
  assert(resp_received.source == request.source);
  assert(resp_received.opcode == AccessAck); // For Put requests
}

// Multiple simultaneous requests from multiple sources (should pass)
void multiple_valid_requests(TileLinkSimulation& sim) {
  auto& host0 = sim.host(0);
  auto& host1 = sim.host(1);
  auto& device0 = sim.device(0);
  auto& device1 = sim.device(1);

  // host0 -> dev0 request
  tl_a dev0_request = host0.a.new_request(false);
  host0.a.start_transaction(dev0_request.source);
  host0.a.send(dev0_request);
  
  // host1 -> dev1 request
  tl_a dev1_request = host1.a.new_request(false);
  dev1_request.address = host1.a.get_address(0x3000, 1);
  host1.a.start_transaction(dev1_request.source);
  host1.a.send(dev1_request);

  tl_a dev0_received = device0.a.await();
  tl_a dev1_received = device1.a.await();

  // dev0 -> host0 response
  tl_d dev0_d = host0.d.await();
  assert(!dev0_d.denied);
  assert(!dev0_d.corrupt);
  assert(dev0_d.source == dev0_request.source);
  assert(dev0_d.opcode == AccessAck); // For Put requests

  // dev1 -> host1 response
  tl_d dev1_d = host1.d.await();
  assert(!dev1_d.denied);
  assert(!dev1_d.corrupt);
  assert(dev1_d.source == dev1_request.source);
  assert(dev1_d.opcode == AccessAck); // For Put requests
}

// Write operation with 2 beats. Should pass on TL-C and TL-UH.
void multibeat_tlc(TileLinkSimulation& sim) {
  auto& host = sim.host(0);
  auto& device = sim.device(0);

  tl_a request = host.a.new_request(false);
  request.opcode = PutFullData;
  request.size = 4; // 2^4 = 16 bytes = 2 beats
  host.a.start_transaction(request.source);
  host.a.send(request);

  tl_a req_received = device.a.await();
  assert(req_received.data == request.data);

  tl_a request2 = request;
  request2.address += 8;
  request2.data = 0x87654321;
  host.a.send(request2);

  // Wait at least one cycle so there is time for the previous beat to go
  // invalid.
  next_cycle();

  tl_a req2_received = device.a.await();
  assert(req2_received.data == request2.data);

  tl_d resp_received = host.d.await();
}

// Write operation with 2 beats. Illegal on TL-UL, but adapter should help.
void multibeat_tlul(TileLinkSimulation& sim) {
  auto& host = sim.host(0);
  auto& device = sim.device(2); // TL-UL

  tl_a request = host.a.new_request(false);
  request.opcode = PutFullData;
  request.size = 4; // 2^4 = 16 bytes = 2 beats
  request.address = host.a.get_address(0x3000, 2);
  host.a.start_transaction(request.source);
  host.a.send(request);

  tl_a request2 = request;
  request2.address += 8;
  request2.data = 0x87654321;
  host.a.send(request2);

  tl_a req_received = device.a.await();
  assert(req_received.data == request.data);

  // Wait at least one cycle so there is time for the previous beat to go
  // invalid.
  next_cycle();

  tl_a req2_received = device.a.await();
  assert(req2_received.data == request2.data);

  tl_d resp2_received = host.d.await();
}

// Only requests with data payloads are allowed to be marked corrupt.
void a_corrupt_payload(TileLinkSimulation& sim) {
  auto& host = sim.host(0);
  auto& device = sim.device(0);

  tl_a request = host.a.new_request(false);
  request.opcode = PutFullData; // So request contains data
  request.corrupt = true;
  host.a.start_transaction(request.source);
  host.a.send(request);

  tl_a req_received = device.a.await();
  tl_d resp_received = host.d.await();
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
  auto& host = sim.host(0);

  // Send TL-UH request to TL-UL device.
  host.a.queue_request(false, {{"opcode", (int)ArithmeticData},
                               {"address", host.a.get_address(0x3000, 2)}});
  
  sim.run(false);
}

// Illegal A param
void a_illegal_param(TileLinkSimulation& sim) {
  auto& host = sim.host(0);

  host.a.queue_request(false, {{"opcode", (int)PutFullData},
                               {"param",                 2}}); // Only 0 allowed
  
  sim.run(false);
}

// Size too small for mask
void a_size_too_small(TileLinkSimulation& sim) {
  auto& host = sim.host(0);

  host.a.queue_request(false, {{"opcode", (int)Get},
                               {"size",          1},   // 2**1 = 2 byte request
                               {"mask",        0xF}}); // 4 bits implies 4 bytes
  
  sim.run(false);
}

// Size doesn't match mask when doing a "full" access
void a_size_mask_mismatch(TileLinkSimulation& sim) {
  auto& host = sim.host(0);

  host.a.queue_request(false, {{"opcode", (int)PutFullData},
                               {"size",          3},   // 2**3 = 8 byte request
                               {"mask",        0xF}}); // 4 bits implies 4 bytes
  
  sim.run(false);
}

// Address not aligned to size
void a_unaligned_address(TileLinkSimulation& sim) {
  auto& host = sim.host(0);

  host.a.queue_request(false, {{"size",         3},   // 2**3 = 8 byte request
                               {"address", 0x3001}});
  
  sim.run(false);
}

// Multibeat requests must increment the address by the width of the bus.
void a_multibeat_addr_inc(TileLinkSimulation& sim) {
  auto& host = sim.host(0);
  auto& device = sim.device(0);

  host.a.queue_request(false, {{"opcode", (int)PutFullData},
                               {"size",                  4}, // 2 beats
                               {"address",          0x3000}});
  host.a.change_next_beat({}); // Let first beat through as-is
  host.a.change_next_beat({{"address", 0x3000}}); // Increment of 0
  
  sim.run(false);
}

// Multibeat requests must keep control signals constant (opcode, param, size,
// source).
void a_multibeat_ctrl_const(TileLinkSimulation& sim) {
  auto& host = sim.host(0);

  host.a.queue_request(false, {{"opcode", (int)PutFullData},
                               {"size",          4}}); // 2**4 = 16 bytes = 2 beats
  host.a.change_next_beat({}); // Let first beat through as-is
  host.a.change_next_beat({{"size", 3}}); // Not allowed
  
  sim.run(false);
}

// Too many beats in burst request.
void a_too_many_beats(TileLinkSimulation& sim) {
  auto& host = sim.host(0);
  auto& device = sim.device(0);

  // Need to use lower-level methods to force a late response.
  tl_a request = host.a.new_request(false);
  request.opcode = PutFullData;
  request.size = 4; // 2^4 = 16 bytes = 128 bits = 2 beats
  host.a.send(request);

  tl_a req_received = device.a.await();
  assert(req_received.data == request.data);

  tl_a request2 = request;
  request2.address += 8;
  request2.data = 0x87654321;
  host.a.send(request2);

  // Wait at least one cycle so there is time for the previous beat to go
  // invalid.
  next_cycle();

  tl_a req2_received = device.a.await();
  assert(req2_received.data == request2.data);

  tl_a request3 = request2;
  request3.address += 8;
  request3.data = 0x18273645;
  host.a.send(request3);

  // Wait at least one cycle so there is time for the previous beat to go
  // invalid.
  next_cycle();

  tl_a req3_received = device.a.await();
  assert(req3_received.data == request3.data);

  tl_d response = device.d.new_response(false, req3_received);
  device.d.send(response);

  tl_d resp_received = host.d.await();
}

// Too few beats in burst request.
void a_too_few_beats(TileLinkSimulation& sim) {
  auto& host = sim.host(0);
  auto& device = sim.device(0);
  
  // Need to use lower-level methods to force an early response.
  tl_a request = host.a.new_request(false);
  request.opcode = PutFullData;
  request.size = 4; // 2^4 = 16 bytes = 128 bits = 2 beats
  host.a.send(request);

  tl_a req_received = device.a.await();
  assert(req_received.data == request.data);

  tl_d response = device.d.new_response(false, req_received);
  device.d.send(response);

  tl_d resp_received = host.d.await();
}

// Non-contiguous mask
void a_noncontiguous_mask(TileLinkSimulation& sim) {
  auto& host = sim.host(0);

  host.a.queue_request(false, {{"opcode", (int)Get}, 
                               {"size",          2},
                               {"mask",       0x33}}); // In binary: 00110011

  sim.run(false);
}

// Multibeat requests must have all bits of the mask set high.
void a_multibeat_bad_mask(TileLinkSimulation& sim) {
  auto& host = sim.host(0);

  host.a.queue_request(false, {{"opcode", (int)PutFullData},
                               {"size",          4}}); // 2**4 = 16 bytes = 2 beats
  host.a.change_next_beat({}); // Let first beat through as-is
  host.a.change_next_beat({{"mask", 0xF0}}); // Not allowed
  
  sim.run(false);
}

// Masks must be aligned with the bus width (64 bits in this case).
// If a narrow request is made and the address is not also aligned with the bus
// width, the mask (and data) must be offset within the bus.
void a_misaligned_mask(TileLinkSimulation& sim) {
  auto& host = sim.host(0);

  host.a.queue_request(false, {{"opcode", (int)PutFullData},
                               {"size",          0},   // 2**0 = 1 byte request
                               {"address",  0x3001},   // Offset = 1
                               {"mask",        0x4}}); // Offset = 2 (mismatch)
  
  sim.run(false);
}

// Only requests with data payloads are allowed to be marked corrupt.
void a_corrupt_without_payload(TileLinkSimulation& sim) {
  auto& host = sim.host(0);
  auto& device = sim.device(0);

  host.a.queue_request(false, {{"opcode", (int)Get},
                               {"corrupt",       1}});
  
  sim.run(false);
}

// Illegal D opcode
void d_illegal_opcode(TileLinkSimulation& sim) {
  auto& host = sim.host(0);
  auto& device = sim.device(0);

  host.a.queue_request(false, {{"opcode", (int)PutFullData}});
  device.d.change_next_beat({{"opcode", (int)HintAck}}); // Should be AccessAck
  
  sim.run(false);
}

// Illegal D param
void d_illegal_param(TileLinkSimulation& sim) {
  auto& host = sim.host(0);
  auto& device = sim.device(0);

  host.a.queue_request(false, {{"opcode", (int)PutFullData}});
  device.d.change_next_beat({{"param", 2}}); // Should be 0
  
  sim.run(false);
}

// Response size differs from request size
void d_size_mismatch(TileLinkSimulation& sim) {
  auto& host = sim.host(0);
  auto& device = sim.device(0);

  host.a.queue_request(false, {{"size", 3}});
  device.d.change_next_beat({{"size", 2}});
  
  sim.run(false);
}

// Too many beats in burst response
// This will probably get picked up as a "response without request", as the
// request will be cleared from the assertion state when the expected number of
// beats have arrived.
void d_too_many_beats(TileLinkSimulation& sim) {
  auto& host = sim.host(0);
  auto& device = sim.device(0);

  host.a.queue_request(false, {{"opcode", (int)Get},
                               {"size",          4}, // 2**4 = 16 bytes = 2 beats
                               {"address",  0x3000}});
  device.d.change_next_beat({}); // Let first beat through as-is
  device.d.change_next_beat({{"duplicate_beat", 0}}); // Duplicate second beat
  device.d.change_next_beat({{"address", 0x3010}}); // Valid third beat address
  
  sim.run(false);
}

// Too few beats in burst response
// This will probably get picked up as an "outstanding request at end of sim"
void d_too_few_beats(TileLinkSimulation& sim) {
  auto& host = sim.host(0);
  auto& device = sim.device(0);

  host.a.queue_request(false, {{"opcode", (int)Get},
                               {"size",          4}}); // 2**4 = 16 bytes = 2 beats
  device.d.change_next_beat({}); // Let first beat through as-is
  device.d.change_next_beat({{"drop_beat", 0}}); // Drop the second beat
  
  sim.run(false);
}

// Response without request from same source
void d_response_without_request(TileLinkSimulation& sim) {
  auto& host = sim.host(0);
  auto& device = sim.device(0);

  host.a.queue_request(false);
  device.d.change_next_beat({{"source", 1}}); // Should be match host 0
  
  sim.run(false);
}

// Request denied without corrupting response.
void d_denied_without_corrupt(TileLinkSimulation& sim) {
  auto& host = sim.host(0);
  auto& device = sim.device(0);

  host.a.queue_request(false, {{"opcode", (int)Get}});
  device.d.change_next_beat({{"denied",  1},
                             {"corrupt", 0}});
  
  sim.run(false);
}

vector<tl_test> tests = {
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
