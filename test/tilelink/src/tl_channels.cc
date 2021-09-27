// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include "random.h"
#include "tl_channels.h"
#include "tl_harness.h"

extern TileLinkSimulation* the_sim;

tl_protocol_e max_common_protocol(tl_protocol_e p1, tl_protocol_e p2) {
  return (p1 > p2) ? p2 : p1;
}

// Round `address` down so it is a multiple of `unit`.
uint64_t align(uint64_t address, uint64_t unit) {
  return address - (address % unit);
}

uint64_t complete_mask(uint64_t address, int size_bytes, int channel_bytes) {
  // Requests larger than (or equal to) the channel set all bits.
  if (size_bytes >= channel_bytes)
    return (1 << channel_bytes) - 1;
  else {
    uint64_t mask = (1 << size_bytes) - 1; // 1 bit set for each byte
    mask <<= (address % channel_bytes);    // Move mask within channel
    return mask;
  }
}


///////////////
// Channel A //
///////////////

bool has_payload(tl_a_op_e opcode) {
  return (opcode == PutFullData) ||
         (opcode == PutPartialData) ||
         (opcode == ArithmeticData) ||
         (opcode == LogicalData);
}

bool requires_response(tl_a_op_e opcode) {
  // All A opcodes need responses.
  return true;
}

tl_a TileLinkSenderA::new_request(bool randomise) const {
  tl_a request;

  if (randomise) {
    auto& host = static_cast<TileLinkHost&>(this->parent);
    auto& device = the_sim->random_device();
    tl_protocol_e protocol = max_common_protocol(host.protocol, device.protocol);

    request.opcode = random_a_opcode(protocol);

    switch (request.opcode) {
      case ArithmeticData:
        request.param = (int)random_arithmetic_data_param();
        break;
      case LogicalData:
        request.param = (int)random_logical_data_param();
        break;
      case Intent:
        request.param = (int)random_intent_param();
        break;
      case AcquireBlock:
      case AcquirePerm:
        request.param = (int)random_grow_permission();
        break;
      default:
        request.param = 0;
        break;
    }

    request.size = random_sample(0, 5); // 1 byte to 32 bytes
    request.source = this->get_transaction_id(randomise);

    int raw_address = random_sample(0, 0x1000 - 1);
    int aligned_address = align(raw_address, 1 << request.size);
    request.address = this->get_address(aligned_address, device.position);

    request.mask = complete_mask(request.address, 1 << request.size, this->bit_width() / 8);
    if (request.opcode == PutPartialData)
      request.mask &= rand();
    
    if (has_payload(request.opcode)) {
      request.corrupt = random_bool(0.05);
      request.data = align(rand(), 160); // A round number in both hex and dec
    }
    else
      request.corrupt = false;
  }
  else {
    request.opcode = PutFullData;
    request.param = 0;
    request.size = this->beat_size();
    request.source = this->get_transaction_id(randomise);
    request.address = this->get_address(0x3000, 0);
    request.mask = this->full_mask(request.size);
    request.corrupt = false;
    request.data = 0xDEADBEEFCAFEF00D;
  }

  return request;
}

tl_a TileLinkSenderA::get_beat(bool randomise, tl_a& request, int index) const {
  tl_a beat = request;

  beat.address += index * this->bit_width() / 8;
  beat.data += index;

  if (randomise) {
    if (beat.opcode == PutPartialData)
      beat.mask = complete_mask(beat.address, 1 << beat.size, this->bit_width() / 8) & rand();
    
    if (has_payload(beat.opcode))
      beat.corrupt = random_bool(0.05);
  }

  return beat;
}

void TileLinkSenderA::queue_request(bool randomise, 
                                    map<string, int> requirements) {
  if (!this->can_start_new_transaction())
    return;

  tl_a request = new_request(randomise);
  modify(request, requirements);

  bool multibeat = has_payload(request.opcode);  
  if (multibeat)
    for (int beat=0; beat<this->num_beats(request.size); beat++)
      this->to_send.push(get_beat(randomise, request, beat));
  else
    this->to_send.push(request);
  
  this->start_transaction(request.source);
}

void TileLinkSenderA::respond() {
  // Do nothing: the A channel doesn't respond to any others.
}

void TileLinkReceiverA::handle_beat(bool randomise, tl_a data) {
  TileLinkDevice& device = static_cast<TileLinkDevice&>(this->parent);

  switch (data.opcode) {
    case PutFullData:
    case PutPartialData:
      this->new_beat_arrived(data.size);
      // Create response only when full message has arrived.
      if (this->all_beats_arrived())
        device.d.handle_request(randomise, data);
      break;
    
    case ArithmeticData:
    case LogicalData:
    case Get:
    case Intent:
      device.d.handle_request(randomise, data);
      break;
    
    case AcquireBlock:
    case AcquirePerm:
      device.b.handle_request(randomise, data);
      // D response should wait until B has finished its work, but that
      // shouldn't matter for this sort of simulation.
      device.d.handle_request(randomise, data);
      break;
  }
}


///////////////
// Channel B //
///////////////

bool has_payload(tl_b_op_e opcode) {
  // We don't support forwarding A messages to B, and none of the remaining
  // operations have payloads.
  return false;
}

bool requires_response(tl_b_op_e opcode) {
  // All B opcodes need responses.
  return true;
}

// There can be an outstanding B request for any combination of source and
// address. Combine both into a single ID.
int get_b_id(int source_id, uint64_t address) {
  // Addresses are currently generated in the range 0x0 to 0xFFF.
  // The bits at 0xF0000000 are modified to allow routing to a device.
  // This leaves 0x0FFFF000 untouched for us to insert the source ID.
  return address + (source_id << 16);
}

tl_b TileLinkSenderB::new_response(bool randomise, tl_a& request) const {
  tl_b response;

  switch (request.opcode) {
    case AcquireBlock: response.opcode = ProbeBlock; break;
    case AcquirePerm:  response.opcode = ProbePerm;  break;

    default: assert(false && "Unsupported A opcode"); break;
  }

  response.size = request.size;
  response.address = request.address;

  if (randomise) {
    response.param = random_cap_permission();
    response.source = rand();
  }
  else {
    response.param = 0;
    response.source = 0;
  }

  return response;
}

void TileLinkSenderB::respond(bool randomise, tl_a& request) {
  assert(this->protocol() == TL_C);

  tl_b response = new_response(randomise, request);

  // Send Probe requests out to all masters. Should exclude the one that sent
  // the incoming request, but it doesn't hurt this simulation.
  for (int i=0; i<the_sim->num_hosts(); i++) {
    auto& host = the_sim->host(i);
    if (host.protocol != TL_C)
      continue;

    response.source = host.c.get_routing_id(randomise);

    if (this->ids_in_use.find(get_b_id(response.source, response.address)) != 
        this->ids_in_use.end())
      throw NoAvailableIDException();

    // All supported B messages contain a single beat.
    this->to_send.push(response);
    this->start_transaction(get_b_id(response.source, response.address));
  }
}

void TileLinkSenderB::respond() {
  // Try to respond to all pending requests. This may fail if we run out of
  // unique transaction IDs.
  int num_requests = a_requests.size();
  for (int i=0; i<num_requests; i++) {
    auto request = a_requests.front();
    a_requests.pop();

    try {
      bool randomise = request.first;
      tl_a beat = request.second;
      respond(randomise, beat);
    }
    catch (NoAvailableIDException& e) {
      // Return the request to the pending queue. Note: requests may be
      // reordered if a later one succeeds.
      a_requests.push(request);
    }
  }
}

tl_b TileLinkSenderB::new_request(bool randomise) const {
  tl_b request;

  auto& host = the_sim->random_host(TL_C);
  auto& device = static_cast<TileLinkDevice&>(this->parent);

  if (randomise) {
    request.opcode = random_b_opcode();
    request.param = random_cap_permission();
    request.size = random_sample(0, 5); // 1 byte to 32 bytes
    request.source = host.c.get_routing_id(randomise);

    // Can't use an address/source combination that's already in use, so
    // generate new addresses until an unused one is found.
    // Assumes an unused address/source combination exists.
    while (true) {
      int raw_address = random_sample(0, 0x1000 - 1);
      request.address = align(raw_address, 1 << request.size);

      if (this->ids_in_use.find(get_b_id(request.source, request.address)) ==
          this->ids_in_use.end())
        break;
    }
  }
  else {
    request.opcode = ProbeBlock;
    request.param = 0;
    request.size = this->beat_size();
    request.source = host.c.get_routing_id(randomise);
    request.address = this->get_address(0x3000, 0);

    // If this address/source combination is in use, try the next one.
    while (this->ids_in_use.find(get_b_id(request.source, request.address)) !=
           this->ids_in_use.end())
      request.address += size_to_bits(request.size) / 8;
  }

  return request;
}


void TileLinkSenderB::queue_request(bool randomise, 
                                    map<string, int> requirements) {
  // Only TL_C uses the B channel.
  if (this->protocol() != TL_C || !this->can_start_new_transaction())
    return;

  tl_b request = new_request(randomise);
  modify(request, requirements);

  // Send Probe requests out to all masters.
  for (int i=0; i<the_sim->num_hosts(); i++) {
    auto& host = the_sim->host(i);
    if (host.protocol != TL_C)
      continue;

    // TODO: it's unclear from the spec whether the source should be a source ID
    //       associated with the host, or just the index of the host.
    request.source = host.c.get_routing_id(randomise);

    // We only support a subset of B requests, which are all single beats.
    this->to_send.push(request);
    this->start_transaction(get_b_id(request.source, request.address));
  }
}

void TileLinkReceiverB::handle_beat(bool randomise, tl_b data) {
  TileLinkHost& host = static_cast<TileLinkHost&>(this->parent);

  // We don't support forwarding A requests to channel B, so few opcodes are
  // allowed.
  switch (data.opcode) {
    case ProbeBlock:
    case ProbePerm:
      host.c.handle_request(randomise, data);
      break;
    
    default:
      assert(false && "Unsupported B opcode");
      break;
  }
}


///////////////
// Channel C //
///////////////

bool has_payload(tl_c_op_e opcode) {
  return (opcode == ProbeAckData) || (opcode == ReleaseData);
}

bool requires_response(tl_c_op_e opcode) {
  return (opcode == Release) || (opcode == ReleaseData);
}

tl_c TileLinkSenderC::new_response(bool randomise, tl_b& request) const {
  tl_c response;

  // We don't support all B opcodes.
  switch (request.opcode) {
    case ProbeBlock: response.opcode = ProbeAck; break; // Or ProbeAckData
    case ProbePerm:  response.opcode = ProbeAck; break;

    default:
      assert(false && "Unsupported B opcode");
      break;
  }

  response.size = request.size;
  response.source = request.source;
  response.address = request.address;

  if (randomise) {
    // 20% chance of writing back data.
    if (request.opcode == ProbeBlock && random_bool(0.2))
      response.opcode = ProbeAckData;

    // Note: not checking that this matches the request.
    response.param = random_bool() ? (int)random_prune_permission()
                                   : (int)random_report_permission();
    
    if (has_payload(response.opcode)) {
      response.corrupt = random_bool(0.05);
      response.data = align(rand(), 160); // A round number in both hex and dec
    }
    else
      response.corrupt = false;
  }
  else {
    response.param = 0;
    response.corrupt = 0;
    response.data = 0;
  }

  return response;
}

tl_c TileLinkSenderC::get_beat(bool randomise, tl_c& response, int index) const {
  tl_c beat = response;

  beat.address += index * this->bit_width() / 8;
  beat.data += index;

  if (randomise) {
    if (has_payload(beat.opcode))
      beat.corrupt = random_bool(0.05);
  }

  return beat;
}

void TileLinkSenderC::respond(bool randomise, tl_b& request) {
  assert(this->protocol() == TL_C);

  tl_c response = new_response(randomise, request);

  bool multibeat = has_payload(response.opcode);
  if (multibeat)
    for (int beat=0; beat<this->num_beats(request.size); beat++)
      this->to_send.push(get_beat(randomise, response, beat));
  else
    this->to_send.push(response);
}

void TileLinkSenderC::respond() {
  // Try to respond to all pending requests. This may fail if we run out of
  // unique transaction IDs.
  int num_requests = b_requests.size();
  for (int i=0; i<num_requests; i++) {
    auto request = b_requests.front();
    b_requests.pop();

    try {
      bool randomise = request.first;
      tl_b beat = request.second;
      respond(randomise, beat);
    }
    catch (NoAvailableIDException& e) {
      // Return the request to the pending queue. Note: requests may be
      // reordered if a later one succeeds.
      b_requests.push(request);
    }
  }
}

tl_c TileLinkSenderC::new_request(bool randomise) const {
  // Only Release(Data) can happen without a previous B message to respond to.
  tl_c request;

  if (randomise) {
    auto& device = the_sim->random_device(TL_C);

    request.opcode = (tl_c_op_e)random_sample(6, 7);
    request.param = random_bool() ? (int)random_prune_permission()
                                  : (int)random_report_permission();

    request.size = random_sample(0, 5); // 1 byte to 32 bytes
    request.source = this->get_transaction_id(randomise);

    int raw_address = random_sample(0, 0x1000 - 1);
    int aligned_address = align(raw_address, 1 << request.size);
    request.address = this->get_address(aligned_address, device.position);
    
    if (has_payload(request.opcode)) {
      request.corrupt = random_bool(0.05);
      request.data = align(rand(), 160); // A round number in both hex and dec
    }
    else
      request.corrupt = false;
  }
  else {
    request.opcode = Release;
    request.param = 0;
    request.size = this->beat_size();
    request.source = this->get_transaction_id(randomise);
    request.address = this->get_address(0x3000, 0);
    request.corrupt = false;
    request.data = 0xDEADBEEFCAFEF00D;
  }

  return request;
}

void TileLinkSenderC::queue_request(bool randomise, 
                                    map<string, int> requirements) {
  if (this->protocol() != TL_C || !this->can_start_new_transaction())
    return;

  tl_c request = new_request(randomise);
  modify(request, requirements);

  bool multibeat = has_payload(request.opcode);  
  if (multibeat)
    for (int beat=0; beat<this->num_beats(request.size); beat++)
      this->to_send.push(get_beat(randomise, request, beat));
  else
    this->to_send.push(request);
  
  if (requires_response(request.opcode))
    this->start_transaction(request.source);
}

void TileLinkReceiverC::handle_beat(bool randomise, tl_c data) {
  assert(this->protocol() == TL_C);

  TileLinkDevice& device = static_cast<TileLinkDevice&>(this->parent);

  // We don't support forwarding C responses to channel D, so few opcodes are
  // allowed.
  switch (data.opcode) {
    case ProbeAck:
      device.b.end_transaction(get_b_id(data.source, data.address));
      break;

    case ProbeAckData:
      this->new_beat_arrived(data.size);
      if (this->all_beats_arrived()) {
        uint64_t first_beat_addr = align(data.address, 1 << data.size);
        device.b.end_transaction(get_b_id(data.source, first_beat_addr));
      }
      break;

    case Release:
      device.d.handle_request(randomise, data);
      break;

    case ReleaseData:
      this->new_beat_arrived(data.size);
      // Create response only when full message has arrived.
      if (this->all_beats_arrived())
        device.d.handle_request(randomise, data);
      break;
  }
}


///////////////
// Channel D //
///////////////

bool has_payload(tl_d_op_e opcode) {
  return (opcode == AccessAckData) || (opcode == GrantData);
}

bool requires_response(tl_d_op_e opcode) {
  return (opcode == Grant) || (opcode == GrantData);
}

tl_d TileLinkSenderD::new_response(bool randomise, tl_a& request) const {
  tl_d response;

  switch (request.opcode) {
    case PutFullData:    response.opcode = AccessAck;     break;
    case PutPartialData: response.opcode = AccessAck;     break;
    case ArithmeticData: response.opcode = AccessAckData; break;
    case LogicalData:    response.opcode = AccessAckData; break;
    case Get:            response.opcode = AccessAckData; break;
    case Intent:         response.opcode = HintAck;       break;
    case AcquireBlock:   response.opcode = Grant;         break; // Or GrantData
    case AcquirePerm:    response.opcode = Grant;         break;
  }

  response.size = request.size;
  response.source = request.source;

  // The sink field is only used when we expect a response.
  if (requires_response(response.opcode))
    response.sink = this->get_transaction_id(randomise);
  else
    response.sink = this->get_routing_id(randomise);

  if (randomise) {
    // Should be deterministic based on request.param, but randomising for now.
    if (request.opcode == AcquireBlock && random_bool(0.2))
      response.opcode = GrantData;
    
    switch (response.opcode) {
      case Grant:
      case GrantData:
        response.param = (int)random_cap_permission(); break;

      default:
        response.param = 0; break;
    }
    response.denied = random_bool(0.1);
    response.corrupt = 
      has_payload(response.opcode) ? (response.denied || random_bool(0.1)) : 0;
    response.data = align(rand(), 160); // A round number in both hex and dec
  }
  else {
    response.param = 0;
    response.denied = false;
    response.corrupt = false;
    response.data = 0xDEADBEEFCAFEF00D;
  }

  return response;
}

tl_d TileLinkSenderD::new_response(bool randomise, tl_c& request) const {
  // Nothing to randomise here.
  tl_d response;

  switch (request.opcode) {
    case Release:
    case ReleaseData:
      response.opcode = ReleaseAck;
      break;
    
    default:
      assert(false && "D can't respond to unexpected C opcode");
  }

  response.param = 0;
  response.size = request.size;
  response.source = request.source;
  response.sink = this->get_routing_id(randomise);
  response.denied = false;
  response.corrupt = false;
  response.data = 0;

  return response;
}

tl_d TileLinkSenderD::get_beat(bool randomise, tl_d& response, int index) const {
  tl_d beat = response;

  beat.data += index;

  if (randomise)
    if (has_payload(beat.opcode))
      beat.corrupt = beat.denied || random_bool(0.05);

  return beat;
}

void TileLinkSenderD::respond(bool randomise, tl_a& request) {
  tl_d response = new_response(randomise, request);

  // LogicalData and ArithmeticData responses are multibeat, but so are their
  // requests, so we only want to respond with a single beat each time.
  bool multibeat = has_payload(response.opcode) && !has_payload(request.opcode);
  if (multibeat)
    for (int beat=0; beat<this->num_beats(request.size); beat++)
      this->to_send.push(get_beat(randomise, response, beat));
  else
    this->to_send.push(response);
  
  if (requires_response(response.opcode))
    this->start_transaction(response.sink);
}

void TileLinkSenderD::respond(bool randomise, tl_c& request) {
  tl_d response = new_response(randomise, request);

  // Only possible response is ReleaseAck, which is a single beat.
  this->to_send.push(response);
}

void TileLinkSenderD::respond() {
  // Try to respond to all pending requests. This may fail if we run out of
  // unique transaction IDs.
  int num_a_requests = a_requests.size();
  for (int i=0; i<num_a_requests; i++) {
    auto request = a_requests.front();
    a_requests.pop();

    try {
      bool randomise = request.first;
      tl_a beat = request.second;
      respond(randomise, beat);
    }
    catch (NoAvailableIDException& e) {
      // Return the request to the pending queue. Note: requests may be
      // reordered if a later one succeeds.
      a_requests.push(request);
    }
  }

  int num_c_requests = c_requests.size();
  for (int i=0; i<num_c_requests; i++) {
    auto request = c_requests.front();
    c_requests.pop();

    try {
      bool randomise = request.first;
      tl_c beat = request.second;
      respond(randomise, beat);
    }
    catch (NoAvailableIDException& e) {
      // Return the request to the pending queue. Note: requests may be
      // reordered if a later one succeeds.
      c_requests.push(request);
    }
  }
}

void TileLinkReceiverD::handle_beat(bool randomise, tl_d data) {
  TileLinkHost& host = static_cast<TileLinkHost&>(this->parent);

  switch (data.opcode) {
    case AccessAck:
    case HintAck:
      host.a.end_transaction(data.source);
      break;

    case AccessAckData:
      this->new_beat_arrived(data.size);
      if (this->all_beats_arrived())
        host.a.end_transaction(data.source);
      break;

    case ReleaseAck:
      host.c.end_transaction(data.source);
      break;

    case Grant:
      host.a.end_transaction(data.source);
      host.e.handle_request(randomise, data);
      break;

    case GrantData:
      this->new_beat_arrived(data.size);
      // Create response only when full message has arrived.
      if (this->all_beats_arrived()) {
        host.a.end_transaction(data.source);
        host.e.handle_request(randomise, data);
      }
      break;
  }
}


///////////////
// Channel E //
///////////////

tl_e TileLinkSenderE::new_response(bool randomise, tl_d& request) const {
  tl_e response;
  response.sink = request.sink;
  return response;
}

void TileLinkSenderE::respond(bool randomise, tl_d& request) {
  assert(this->protocol() == TL_C);

  tl_e response = new_response(randomise, request);

  // Only possible response is GrantAck, which is a single beat.
  this->to_send.push(response);
}

void TileLinkSenderE::respond() {
  // Try to respond to all pending requests. This may fail if we run out of
  // unique transaction IDs.
  int num_requests = d_requests.size();
  for (int i=0; i<num_requests; i++) {
    auto request = d_requests.front();
    d_requests.pop();

    try {
      bool randomise = request.first;
      tl_d beat = request.second;
      respond(randomise, beat);
    }
    catch (NoAvailableIDException& e) {
      // Return the request to the pending queue. Note: requests may be
      // reordered if a later one succeeds.
      d_requests.push(request);
    }
  }
}

void TileLinkReceiverE::handle_beat(bool randomise, tl_e data) {
  assert(this->protocol() == TL_C);

  TileLinkDevice& device = static_cast<TileLinkDevice&>(this->parent);
  device.d.end_transaction(data.sink);
}
