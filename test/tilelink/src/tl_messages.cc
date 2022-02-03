// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include "tl_channels.h"
#include "tl_harness.h"
#include "tl_messages.h"
#include "tl_random.h"

extern TileLinkSimulation* the_sim;

tl_protocol_e max_common_protocol(tl_protocol_e p1, tl_protocol_e p2) {
  return (p1 > p2) ? p2 : p1;
}

// This needs to match the routing tables in tl_wrapper.sv.
uint64_t get_address(uint64_t address, int device) {
  return address + device * 0x10000000;
}

// Round `address` down so it is a multiple of `unit`.
uint64_t align(uint64_t address, uint64_t unit) {
  return address - (address % unit);
}

// Generate a byte mask indicating all byte lanes are active.
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

// Generate a byte mask for a given amount of data.
// `size` is the TileLink field, log2(bytes).
// TODO: redundant, see above.
int full_mask(int size) {
  int num_bytes = 1 << size;
  return (1 << num_bytes) - 1;
}

// `size` == log2(bytes)
int size_to_bits(int size) {return 8 * (1 << size);}
int bits_to_size(int bits) {return (int)(log2(bits / 8));}

int max(int a, int b)      {return (a > b) ? a : b;}

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

int num_beats(tl_a_op_e opcode, int size, int channel_width_bytes) {
  if (has_payload(opcode))
    return max(1, (1 << size) / channel_width_bytes);
  else
    return 1;
}

tl_a new_a_request(TileLinkSender<tl_a>& endpoint, bool randomise) {
  tl_a request;

  if (randomise) {
    auto& host = static_cast<const TileLinkHost&>(endpoint.get_parent());
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
    request.source = endpoint.get_transaction_id(randomise);

    int raw_address = random_sample(0, 0x1000 - 1);
    int aligned_address = align(raw_address, 1 << request.size);
    request.address = get_address(aligned_address, device.position);

    request.mask = complete_mask(request.address, 1 << request.size, endpoint.bit_width() / 8);
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
    request.size = endpoint.beat_size();
    request.source = endpoint.get_transaction_id(randomise);
    request.address = get_address(0x3000, 0);
    request.mask = full_mask(request.size);
    request.corrupt = false;
    request.data = 0xDEADBEEFCAFEF00D;
  }

  return request;
}

tl_message<tl_a>::tl_message(TileLinkSender<tl_a>& endpoint,
                             tl_a header, int num_beats) :
    tl_message_base(endpoint.bit_width() / 8, num_beats),
    header(header) {
  // Nothing
}

tl_message<tl_a>::tl_message(TileLinkSender<tl_a>& endpoint,
                             bool randomise, map<string, int> requirements) :
    tl_message_base(endpoint.bit_width() / 8),
    header(modify(new_a_request(endpoint, randomise), requirements)) {
  beats_to_send = num_beats(header.opcode, header.size, endpoint.bit_width() / 8);
  assert(beats_to_send > 0);
}

tl_a tl_message<tl_a>::next_beat(bool randomise) {
  tl_a beat = header;

  beat.address += beats_generated * channel_width_bytes;
  beat.data += beats_generated;

  if (randomise) {
    if (beat.opcode == PutPartialData)
      beat.mask = complete_mask(beat.address, 1 << beat.size, 
                                channel_width_bytes) & rand();
    
    if (has_payload(beat.opcode))
      beat.corrupt = random_bool(0.05);
  }

  beats_generated++;

  return beat;
}

tl_a tl_message<tl_a>::modify(tl_a beat, map<string, int>& updates) {
  if (updates.find("opcode") != updates.end())
    beat.opcode = (tl_a_op_e)updates["opcode"];
  if (updates.find("param") != updates.end())
    beat.param = updates["param"];
  if (updates.find("size") != updates.end())
    beat.size = updates["size"];
  if (updates.find("source") != updates.end())
    beat.source = updates["source"];
  if (updates.find("address") != updates.end())
    beat.address = updates["address"];
  if (updates.find("mask") != updates.end())
    beat.mask = updates["mask"];
  if (updates.find("corrupt") != updates.end())
    beat.corrupt = updates["corrupt"];
  if (updates.find("data") != updates.end())
    beat.data = updates["data"];
  
  return beat;
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

int num_beats(tl_b_op_e opcode, int size, int channel_width_bytes) {
  if (has_payload(opcode))
    return max(1, (1 << size) / channel_width_bytes);
  else
    return 1;
}

// There can be an outstanding B request for any combination of source and
// address. Combine both into a single ID.
int get_b_id(int source_id, uint64_t address) {
  // Addresses are currently generated in the range 0x0 to 0xFFF.
  // The bits at 0xF0000000 are modified to allow routing to a device.
  // This leaves 0x0FFFF000 untouched for us to insert the source ID.
  return address + (source_id << 16);
}

tl_b new_b_request(TileLinkSender<tl_b>& endpoint, bool randomise) {
  tl_b request;

  auto& host = the_sim->random_host(TL_C);
  auto& device = static_cast<const TileLinkDevice&>(endpoint.get_parent());

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
      int id = get_b_id(request.source, request.address);

      if (endpoint.transaction_id_available(id))
        break;
    }
  }
  else {
    request.opcode = ProbeBlock;
    request.param = 0;
    request.size = endpoint.beat_size();
    request.source = host.c.get_routing_id(randomise);
    request.address = get_address(0x3000, 0);

    int id = get_b_id(request.source, request.address);

    // If this address/source combination is in use, try the next one.
    while (!endpoint.transaction_id_available(id)) {
      request.address += size_to_bits(request.size) / 8;
      id = get_b_id(request.source, request.address);
    }
  }

  return request;
}

tl_message<tl_b>::tl_message(TileLinkSender<tl_b>& endpoint,
                             tl_b header, int num_beats) :
    tl_message_base(endpoint.bit_width() / 8, num_beats),
    header(header) {
  // Nothing
}

tl_message<tl_b>::tl_message(TileLinkSender<tl_b>& endpoint,
                             bool randomise, map<string, int> requirements) :
    tl_message_base(endpoint.bit_width() / 8),
    header(modify(new_b_request(endpoint, randomise), requirements)) {
  beats_to_send = num_beats(header.opcode, header.size, endpoint.bit_width() / 8);
  assert(beats_to_send > 0);
}

tl_b new_b_response(TileLinkSender<tl_b>& endpoint, tl_a& request,
                    bool randomise) {
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

tl_message<tl_b>::tl_message(TileLinkSender<tl_b>& endpoint, tl_a& request,
                             bool randomise) :
    header(new_b_response(endpoint, request, randomise)),
    tl_message_base(endpoint.bit_width() / 8,
                    num_beats(header.opcode, header.size, endpoint.bit_width() / 8)) {
  // Nothing
}

tl_b tl_message<tl_b>::next_beat(bool randomise) {
  // All supported B messages are a single beat.
  assert(beats_generated == 0);
  beats_generated++;
  return header;
}

tl_b tl_message<tl_b>::modify(tl_b beat, map<string, int>& updates) {
  if (updates.find("opcode") != updates.end())
    beat.opcode = (tl_b_op_e)updates["opcode"];
  if (updates.find("param") != updates.end())
    beat.param = updates["param"];
  if (updates.find("size") != updates.end())
    beat.size = updates["size"];
  if (updates.find("source") != updates.end())
    beat.source = updates["source"];
  if (updates.find("address") != updates.end())
    beat.address = updates["address"];
  
  return beat;
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

int num_beats(tl_c_op_e opcode, int size, int channel_width_bytes) {
  if (has_payload(opcode))
    return max(1, (1 << size) / channel_width_bytes);
  else
    return 1;
}

tl_c new_c_request(TileLinkSender<tl_c>& endpoint, bool randomise) {
  // Only Release(Data) can happen without a previous B message to respond to.
  tl_c request;

  if (randomise) {
    auto& device = the_sim->random_device(TL_C);

    request.opcode = (tl_c_op_e)random_sample(6, 7);
    request.param = random_bool() ? (int)random_prune_permission()
                                  : (int)random_report_permission();

    request.size = random_sample(0, 5); // 1 byte to 32 bytes
    request.source = endpoint.get_transaction_id(randomise);

    int raw_address = random_sample(0, 0x1000 - 1);
    int aligned_address = align(raw_address, 1 << request.size);
    request.address = get_address(aligned_address, device.position);
    
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
    request.size = endpoint.beat_size();
    request.source = endpoint.get_transaction_id(randomise);
    request.address = get_address(0x3000, 0);
    request.corrupt = false;
    request.data = 0xDEADBEEFCAFEF00D;
  }

  return request;
}

tl_message<tl_c>::tl_message(TileLinkSender<tl_c>& endpoint,
                             tl_c header, int num_beats) :
    tl_message_base(endpoint.bit_width() / 8, num_beats),
    header(header) {
  // Nothing
}

tl_message<tl_c>::tl_message(TileLinkSender<tl_c>& endpoint,
                             bool randomise, map<string, int> requirements) :
    tl_message_base(endpoint.bit_width() / 8),
    header(modify(new_c_request(endpoint, randomise), requirements)) {
  beats_to_send = num_beats(header.opcode, header.size, endpoint.bit_width() / 8);
  assert(beats_to_send > 0);
}

tl_c new_c_response(TileLinkSender<tl_c>& endpoint, tl_b& request,
                    bool randomise) {
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

tl_message<tl_c>::tl_message(TileLinkSender<tl_c>& endpoint, tl_b& request,
                             bool randomise) :
    tl_message_base(endpoint.bit_width() / 8),
    header(new_c_response(endpoint, request, randomise)) {
  beats_to_send = num_beats(header.opcode, header.size, endpoint.bit_width() / 8);
  assert(beats_to_send > 0);
}

tl_c tl_message<tl_c>::next_beat(bool randomise) {
  tl_c beat = header;

  beat.address += beats_generated * channel_width_bytes;
  beat.data += beats_generated;

  if (randomise) {
    if (has_payload(beat.opcode))
      beat.corrupt = random_bool(0.05);
  }

  beats_generated++;

  return beat;
}

tl_c tl_message<tl_c>::modify(tl_c beat, map<string, int>& updates) {
  if (updates.find("opcode") != updates.end())
    beat.opcode = (tl_c_op_e)updates["opcode"];
  if (updates.find("param") != updates.end())
    beat.param = updates["param"];
  if (updates.find("size") != updates.end())
    beat.size = updates["size"];
  if (updates.find("source") != updates.end())
    beat.source = updates["source"];
  if (updates.find("address") != updates.end())
    beat.address = updates["address"];
  if (updates.find("corrupt") != updates.end())
    beat.corrupt = updates["corrupt"];
  if (updates.find("data") != updates.end())
    beat.data = updates["data"];
  
  return beat;
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

int num_beats(tl_d_op_e opcode, int size, int channel_width_bytes) {
  if (has_payload(opcode))
    return max(1, (1 << size) / channel_width_bytes);
  else
    return 1;
}

int num_beats(tl_d_op_e opcode, tl_a_op_e request, int size, int channel_width_bytes) {
  // LogicalData and ArithmeticData responses are multibeat, but so are their
  // requests, so instead of waiting for the entire request to arrive, we want
  // to send a single-beat response after each request beat.

  if (has_payload(opcode) && request != LogicalData && request != ArithmeticData)
    return max(1, (1 << size) / channel_width_bytes);
  else
    return 1;
}

tl_d new_d_response(TileLinkSender<tl_d>& endpoint, tl_a& request,
                    bool randomise) {
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
    response.sink = endpoint.get_transaction_id(randomise);
  else
    response.sink = endpoint.get_routing_id(randomise);

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

tl_message<tl_d>::tl_message(TileLinkSender<tl_d>& endpoint,
                             tl_d header, int num_beats) :
    tl_message_base(endpoint.bit_width() / 8, num_beats),
    header(header) {
  // Nothing
}

tl_message<tl_d>::tl_message(TileLinkSender<tl_d>& endpoint, tl_a& request,
                             bool randomise) :
    tl_message_base(endpoint.bit_width() / 8),
    header(new_d_response(endpoint, request, randomise)) {
  beats_to_send = num_beats(header.opcode, request.opcode, header.size,
                            endpoint.bit_width() / 8);
  assert(beats_to_send > 0);
}

tl_d new_d_response(TileLinkSender<tl_d>& endpoint, tl_c& request,
                    bool randomise) {
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
  response.sink = endpoint.get_routing_id(randomise);
  response.denied = false;
  response.corrupt = false;
  response.data = 0;

  return response;
}

tl_message<tl_d>::tl_message(TileLinkSender<tl_d>& endpoint, tl_c& request,
                             bool randomise) :
    tl_message_base(endpoint.bit_width() / 8),
    header(new_d_response(endpoint, request, randomise)) {
  beats_to_send = num_beats(header.opcode, header.size, endpoint.bit_width() / 8);
  assert(beats_to_send > 0);
}

tl_d tl_message<tl_d>::next_beat(bool randomise) {
  tl_d beat = header;

  beat.data += beats_generated;

  if (randomise)
    if (has_payload(beat.opcode))
      beat.corrupt = beat.denied || random_bool(0.05);

  beats_generated++;

  return beat;
}

tl_d tl_message<tl_d>::modify(tl_d beat, map<string, int>& updates) {
  if (updates.find("opcode") != updates.end())
    beat.opcode = (tl_d_op_e)updates["opcode"];
  if (updates.find("param") != updates.end())
    beat.param = updates["param"];
  if (updates.find("size") != updates.end())
    beat.size = updates["size"];
  if (updates.find("source") != updates.end())
    beat.source = updates["source"];
  if (updates.find("sink") != updates.end())
    beat.sink = updates["sink"];
  if (updates.find("denied") != updates.end())
    beat.denied = updates["denied"];
  if (updates.find("corrupt") != updates.end())
    beat.corrupt = updates["corrupt"];
  if (updates.find("data") != updates.end())
    beat.data = updates["data"];

  return beat;
}


///////////////
// Channel E //
///////////////

tl_e new_e_response(TileLinkSender<tl_e>& endpoint, tl_d& request,
                    bool randomise) {
  tl_e response;
  response.sink = request.sink;
  return response;
}

tl_message<tl_e>::tl_message(TileLinkSender<tl_e>& endpoint,
                             tl_e header, int num_beats) :
    tl_message_base(endpoint.bit_width() / 8, num_beats),
    header(header) {
  // Nothing
}

tl_message<tl_e>::tl_message(TileLinkSender<tl_e>& endpoint, tl_d& request,
                             bool randomise) :
    tl_message_base(endpoint.bit_width() / 8, 1),
    header(new_e_response(endpoint, request, randomise)) {
  // Nothing
}

tl_e tl_message<tl_e>::next_beat(bool randomise) {
  // All E messages are a single beat.
  assert(beats_generated == 0);
  beats_generated++;
  return header;
}

tl_e tl_message<tl_e>::modify(tl_e beat, map<string, int>& updates) {
  if (updates.find("sink") != updates.end())
    beat.sink = updates["sink"];
  
  return beat;
}
