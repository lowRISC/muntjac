// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include "tl_channels.h"
#include "tl_harness.h"
#include "tl_messages.h"
#include "tl_random.h"

extern TileLinkSimulation* the_sim;

// Round `address` down so it is a multiple of `unit`.
extern uint64_t align(uint64_t address, uint64_t unit);


///////////////
// Channel A //
///////////////

extern bool requires_response(tl_a_op_e opcode);

void TileLinkSenderA::queue_request(bool randomise, 
                                    map<string, int> requirements) {
  if (!this->can_start_new_transaction())
    return;

  tl_message<tl_a> request(*this, randomise, requirements);
  this->to_send.push(request);
  
  this->start_transaction(request.header.source);
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

extern bool requires_response(tl_b_op_e opcode);

// There can be an outstanding B request for any combination of source and
// address. Combine both into a single ID.
extern int get_b_id(int source_id, uint64_t address);

void TileLinkSenderB::respond(bool randomise, tl_a& request) {
  assert(this->protocol() == TL_C);

  tl_message<tl_b> response(*this, request, randomise);

  // Send Probe requests out to all masters. Should exclude the one that sent
  // the incoming request, but it doesn't hurt this simulation.
  for (int i=0; i<the_sim->num_hosts(); i++) {
    auto& host = the_sim->host(i);
    if (host.protocol != TL_C)
      continue;

    response.header.source = host.c.get_routing_id(randomise);

    int transaction = get_b_id(response.header.source, response.header.address);

    if (this->ids_in_use.find(transaction) != this->ids_in_use.end())
      throw NoAvailableIDException();

    this->to_send.push(response);
    this->start_transaction(transaction);
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

void TileLinkSenderB::queue_request(bool randomise, 
                                    map<string, int> requirements) {
  // Only TL_C uses the B channel.
  if (this->protocol() != TL_C || !this->can_start_new_transaction())
    return;

  tl_message<tl_b> request(*this, randomise, requirements);

  // Prepare to send Probe requests out to all masters.
  // Don't send anything yet though - first need to confirm that transaction
  // IDs are available.
  vector<tl_message<tl_b>> pending;
  for (int i=0; i<the_sim->num_hosts(); i++) {
    auto& host = the_sim->host(i);
    if (host.protocol != TL_C)
      continue;

    // TODO: it's unclear from the spec whether the source should be a source ID
    //       associated with the host, or just the index of the host.
    request.header.source = host.c.get_routing_id(randomise);

    int id = get_b_id(request.header.source, request.header.address);

    if (this->transaction_id_available(id))
      pending.push_back(request);
    else
      return; // Could try another source/address, but this is simpler.
  }

  // Send requests now that everything is confirmed safe.
  for (auto request : pending) {
    // We only support a subset of B requests, which are all single beats.
    this->to_send.push(request);
    this->start_transaction(get_b_id(request.header.source, request.header.address));
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

extern bool requires_response(tl_c_op_e opcode);

void TileLinkSenderC::respond(bool randomise, tl_b& request) {
  assert(this->protocol() == TL_C);

  tl_message<tl_c> response(*this, request, randomise);
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

void TileLinkSenderC::queue_request(bool randomise, 
                                    map<string, int> requirements) {
  if (this->protocol() != TL_C || !this->can_start_new_transaction())
    return;

  tl_message<tl_c> request(*this, randomise, requirements);
  this->to_send.push(request);
  
  if (requires_response(request.header.opcode))
    this->start_transaction(request.header.source);
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

extern bool requires_response(tl_d_op_e opcode);

void TileLinkSenderD::respond(bool randomise, tl_a& request) {
  tl_message<tl_d> response(*this, request, randomise);
  this->to_send.push(response);

  // ArithmeticData and LogicalData are multibeat requests, but we respond to
  // each beat individually, so we need to lock the output buffer until we
  // have responded to all beats.
  if (request.opcode == ArithmeticData || request.opcode == LogicalData) {
    // First beat.
    if (beats_remaining == 0)
      beats_remaining = std::max(1, (1 << request.size) / (this->bit_width() / 8));
    
    beats_remaining--;

    lock_output_buffer = (beats_remaining > 0);
  }
  else
    assert(!lock_output_buffer);
  
  if (requires_response(response.header.opcode))
    this->start_transaction(response.header.sink);
}

void TileLinkSenderD::respond(bool randomise, tl_c& request) {
  assert(!lock_output_buffer);
  tl_message<tl_d> response(*this, request, randomise);
  this->to_send.push(response);
  
  if (requires_response(response.header.opcode))
    this->start_transaction(response.header.sink);
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

  // The output buffer may become locked if only a partial response has been
  // queued so far.
  if (lock_output_buffer)
    return;

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

void TileLinkSenderE::respond(bool randomise, tl_d& request) {
  assert(this->protocol() == TL_C);

  tl_message<tl_e> response(*this, request, randomise);
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
