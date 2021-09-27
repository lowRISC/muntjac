// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#ifndef TL_CHANNELS_H
#define TL_CHANNELS_H

#include <iomanip>
#include <map>
#include <queue>
#include <set>
#include <vector>

#include "logs.h"
#include "random.h"
#include "tilelink.h"
#include "tl_exceptions.h"
#include "Vtl_wrapper.h"

using std::map;
using std::pair;
using std::queue;
using std::set;
using std::string;
using std::vector;

typedef Vtl_wrapper DUT;

extern void next_cycle();

// Base class for a host/device, with connections to all TileLink channels.
class TileLinkEndpoint {
public:
  TileLinkEndpoint(DUT& dut, int position, tl_protocol_e protocol, 
                   int bit_width, int first_id, int last_id) :
      dut(dut), position(position), protocol(protocol), bit_width(bit_width),
      first_id(first_id), last_id(last_id) {
    // Nothing
  }

  // The TileLink network being tested.
  DUT& dut;

  // The position of this host/device in the array of hosts/devices.
  const int position;

  // Whether this component supports TL-UL, TL-UH or TL-C.
  const tl_protocol_e protocol;

  // Amount of data this component can send/receive in one beat.
  const int bit_width;

  // The range of source/sink IDs allocated to this component.
  const int first_id;
  const int last_id;
};

// Base class for the start/end of any TileLink channel (A, B, C, D, E).
template<class channel>
class TileLinkChannelEnd {
public:
  TileLinkChannelEnd(TileLinkEndpoint& parent) : parent(parent) {
    // Nothing
  }

  // specialisations have extra methods to generate standard responses
  //   e.g. endpoint<D> has respond(A), respond(C)
  //   also randomChange(A)? What would that be used for?
protected:
  DUT& dut() const               {return parent.dut;}
  int position() const           {return parent.position;}
  tl_protocol_e protocol() const {return parent.protocol;}
  int bit_width() const          {return parent.bit_width;}
  int first_id() const           {return parent.first_id;}
  int last_id() const            {return parent.last_id;}

  // `size` == log2(bytes)
  static int size_to_bits(int size) {return 8 * (1 << size);}
  static int bits_to_size(int bits) {return (int)(log2(bits / 8));}

  // The maximum value of the `size` field of any single-beat message on this
  // channel.
  int beat_size() const {return bits_to_size(bit_width());}

  // The number of beats in a message with given `size`. This assumes the`size`
  // corresponds to this message, and not the associated request/response.
  int num_beats(int size) const {
    int total_bits = size_to_bits(size);
    int beat_bits = bit_width();
    return (total_bits > beat_bits) ? (total_bits / beat_bits) : 1;
  }

  // `size` is the TileLink field, log2(bytes).
  int full_mask(int size) const {
    int num_bytes = 1 << size;
    return (1 << num_bytes) - 1;
  }

  TileLinkEndpoint& parent;
};


template<class channel>
class TileLinkSender : public TileLinkChannelEnd<channel> {
public:
  TileLinkSender(TileLinkEndpoint& parent) : 
      TileLinkChannelEnd<channel>(parent) {
    // Nothing
  }

  // Queue up a change to be applied to a sent beat. Whenever a beat is sent,
  // the queue is checked for outstanding updates, and the next available update
  // is applied, if there is one. A single update may modify multitple fields
  // of the message.
  void change_next_beat(map<string, int> updates) {
    modifications.push(updates);
  }

  // One clock cycle of behaviour.
  void step(bool randomise) {
    // Randomly reorder the pending requests.
    // Currently disabled for TL-UL components because the TL-UL adapter
    // requires FIFO order. Could alternatively require FIFO converters in the
    // TileLink network.
    if (this->protocol() != TL_UL && randomise && random_bool(0.5))
      this->reorder_requests();

    // Generate responses to any pending requests and put them in the queue.
    // Randomly stall, i.e. don't respond for a cycle.
    if (!randomise || random_bool(0.8))
      this->respond();

    // We are in the process of sending a beat.
    if (this->get_valid()) {
      // Last beat sent has been accepted.
      if (this->get_ready())
        this->set_valid(false);
      // Last beat sent is still waiting.
      else {
        // Nothing yet: continue waiting.
        // Could reorder the contents of the queue, but we do that at response
        // time, so no need to do it again here?
        return;
      }
    }

    if (!to_send.empty()) {
      channel data = to_send.front();
      map<string, int> updates;

      if (!modifications.empty()) {
        updates = modifications.front();
        this->modify(data, updates);
        modifications.pop();
      }

      if (updates.find("duplicate_beat") == updates.end())
        to_send.pop();

      if (updates.find("drop_beat") == updates.end()) {
        this->set_data(data);
        this->set_valid(true);
      }
    }
  }

  virtual bool get_ready() const = 0;
  virtual bool get_valid() const = 0;
  virtual void set_data(channel data) = 0;
  virtual void set_valid(bool valid) = 0;

protected:

  // Modify `data` according to the fields/values provided in `updates`.
  virtual void modify(channel& data, map<string, int>& updates) = 0;

  // Generate (but don't send) responses to any pending requests. This may not
  // be possible if, for example, there are no spare transaction IDs. In that
  // case, nothing happens.
  virtual void respond() = 0;

  // Reorder the contentst of request queue(s).
  virtual void reorder_requests() = 0;

public:

  // This needs to match the routing tables in tl_wrapper.sv.
  uint64_t get_address(uint64_t address, int device) const {
    return address + device * 0x10000000;
  }

  // Wait until the network is ready to receive a new beat.
  // This updates simulation time, so is not suitable for parallel operations.
  void await_ready(int timeout=100) {
    for (int i=0; i<timeout; i++) {
      if (this->get_ready()) 
        return;

      next_cycle();
    }

    assert(false && "Network not ready to receive message");
  }

  // Send a beat onto the network and wait until it has been accepted.
  // This updates simulation time, so is not suitable for parallel operations.
  void send(channel data) {
    this->set_data(data);
    this->set_valid(true);
    next_cycle();  // Ensure the message is available for at least one cycle
    this->await_ready();
    this->set_valid(false);
  }

  bool can_start_new_transaction() const {
    return ids_in_use.size() < (this->last_id() - this->first_id() + 1);
  }

  // An ID for a transaction. IDs can be reused, but not until the previous
  // transaction has completed.
  int get_transaction_id(bool randomise=false) const {
    if (!can_start_new_transaction())
      throw NoAvailableIDException();

    if (randomise) {
      while (true) {
        int id = this->first_id() + (rand() % (this->last_id() - this->first_id() + 1));
        if (ids_in_use.find(id) == ids_in_use.end())
          return id;
      }
    }
    else {
      // Find first available ID.
      for (int id=this->first_id(); id<=this->last_id(); id++)
        if (ids_in_use.find(id) == ids_in_use.end())
          return id;

      assert(false && "Couldn't find available transaction ID");
      return -1;
    }
  }

  // Like a transaction ID, but we don't care if it's already in use.
  int get_routing_id(bool randomise=false) const {
    if (randomise)
      return this->first_id() + (rand() % (this->last_id() - this->first_id() + 1));
    else
      return this->first_id();
  }

  void start_transaction(int id) {
    assert(ids_in_use.find(id) == ids_in_use.end());
    ids_in_use.insert(id);
  }
  void end_transaction(int id) {
    assert(ids_in_use.find(id) != ids_in_use.end());
    ids_in_use.erase(id);
  }

protected:

  // Source/sink IDs currently in use. Most channels only allow one outstanding
  // transaction per ID.
  set<int> ids_in_use;

  queue<channel> to_send;
  queue<map<string, int>> modifications;
};

class TileLinkSenderA : public TileLinkSender<tl_a> {
public:
  TileLinkSenderA(TileLinkEndpoint& parent) : 
      TileLinkSender<tl_a>(parent) {}

  virtual bool get_ready() const {
    return this->dut().host_a_ready_o[this->position()];
  }

  virtual bool get_valid() const {
    return this->dut().host_a_valid_i[this->position()];
  }

  virtual void set_data(tl_a beat) {
    MUNTJAC_LOG(1) << "Host   " << this->position() << "A sending"
                   << " op:" << beat.opcode 
                   << " param:" << beat.param
                   << " size:" << beat.size 
                   << " src:" << beat.source
                   << " addr:0x" << std::hex << std::setw(8) << beat.address 
                   << " mask:0x" << std::setw(2) << beat.mask 
                   << " corrupt:" << beat.corrupt
                   << " data:0x" << std::setw(16) << beat.data << std::dec 
                   << std::endl;

    this->dut().host_a_opcode_i[this->position()]  = beat.opcode;
    this->dut().host_a_param_i[this->position()]   = beat.param;
    this->dut().host_a_size_i[this->position()]    = beat.size;
    this->dut().host_a_source_i[this->position()]  = beat.source;
    this->dut().host_a_address_i[this->position()] = beat.address;
    this->dut().host_a_mask_i[this->position()]    = beat.mask;
    this->dut().host_a_corrupt_i[this->position()] = beat.corrupt;
    this->dut().host_a_data_i[this->position()]    = beat.data;
  }

  virtual void set_valid(bool valid) {
    this->dut().host_a_valid_i[this->position()] = valid;
  }

  // Generate a new valid request. Requests always consist of a single beat when
  // not randomised.
  tl_a new_request(bool randomise) const;

  // Generate a single beat from a request. The address, etc. will be updated
  // appropriately as the beat number increases.
  tl_a get_beat(bool randomise, tl_a& request, int index) const;

  // Create and enqueue a new request. `requirements` can be used to force
  // fields to have particular values.
  void queue_request(bool randomise, 
                     map<string, int> requirements = map<string, int>());

protected:
  virtual void modify(tl_a& request, map<string, int>& updates) {
    if (updates.find("opcode") != updates.end())
      request.opcode = (tl_a_op_e)updates["opcode"];
    if (updates.find("param") != updates.end())
      request.param = updates["param"];
    if (updates.find("size") != updates.end())
      request.size = updates["size"];
    if (updates.find("source") != updates.end())
      request.source = updates["source"];
    if (updates.find("address") != updates.end())
      request.address = updates["address"];
    if (updates.find("mask") != updates.end())
      request.mask = updates["mask"];
    if (updates.find("corrupt") != updates.end())
      request.corrupt = updates["corrupt"];
    if (updates.find("data") != updates.end())
      request.data = updates["data"];
  }

  virtual void respond();

  virtual void reorder_requests() {
    // No requests to reorder.
  }
};

class TileLinkSenderB : public TileLinkSender<tl_b> {
public:
  TileLinkSenderB(TileLinkEndpoint& parent) : 
      TileLinkSender<tl_b>(parent) {}

  virtual bool get_ready() const {
    return this->dut().dev_b_ready_o[this->position()];
  }

  virtual bool get_valid() const {
    return this->dut().dev_b_valid_i[this->position()];
  }

  virtual void set_data(tl_b beat) {
    MUNTJAC_LOG(1) << "Device " << this->position() << "B sending"
                   << " op:" << beat.opcode 
                   << " param:" << beat.param
                   << " size:" << beat.size 
                   << " src:" << beat.source
                   << " addr:0x" << std::hex << std::setw(8) << beat.address 
                   << std::dec 
                   << std::endl;

    this->dut().dev_b_opcode_i[this->position()]  = beat.opcode;
    this->dut().dev_b_param_i[this->position()]   = beat.param;
    this->dut().dev_b_size_i[this->position()]    = beat.size;
    this->dut().dev_b_source_i[this->position()]  = beat.source;
    this->dut().dev_b_address_i[this->position()] = beat.address;
  }

  virtual void set_valid(bool valid) {
    this->dut().dev_b_valid_i[this->position()] = valid;
  }

  void handle_request(bool randomise, tl_a& request) {
    a_requests.push(pair<bool, tl_a>(randomise, request));
  }

  // Generate the first beat of a response.
  tl_b new_response(bool randomise, tl_a& request) const;

  // Respond to an A request.
  void respond(bool randomise, tl_a& request);

  // Generate a new valid request.
  tl_b new_request(bool randomise) const;

  // Create and enqueue a new request. `requirements` can be used to force
  // fields to have particular values.
  void queue_request(bool randomise, 
                     map<string, int> requirements = map<string, int>());

protected:
  virtual void modify(tl_b& request, map<string, int>& updates) {
    if (updates.find("opcode") != updates.end())
      request.opcode = (tl_b_op_e)updates["opcode"];
    if (updates.find("param") != updates.end())
      request.param = updates["param"];
    if (updates.find("size") != updates.end())
      request.size = updates["size"];
    if (updates.find("source") != updates.end())
      request.source = updates["source"];
    if (updates.find("address") != updates.end())
      request.address = updates["address"];
  }

  virtual void respond();

  virtual void reorder_requests() {
    // Simple for now: move the front request to the back of the queue.
    if (!a_requests.empty()) {
      a_requests.push(a_requests.front());
      a_requests.pop();
    }
  }

private:
  // If we are not able to respond to a request immediately, queue it here.
  queue<pair<bool, tl_a>> a_requests;
};

class TileLinkSenderC : public TileLinkSender<tl_c> {
public:
  TileLinkSenderC(TileLinkEndpoint& parent) : 
      TileLinkSender<tl_c>(parent) {}

  virtual bool get_ready() const {
    return this->dut().host_c_ready_o[this->position()];
  }

  virtual bool get_valid() const {
    return this->dut().host_c_valid_i[this->position()];
  }

  virtual void set_data(tl_c beat) {
    MUNTJAC_LOG(1) << "Host   " << this->position() << "C sending"
                   << " op:" << beat.opcode 
                   << " param:" << beat.param
                   << " size:" << beat.size 
                   << " src:" << beat.source
                   << " addr:0x" << std::hex << std::setw(8) << beat.address
                   << " corrupt:" << beat.corrupt
                   << " data:0x" << std::setw(16) << beat.data << std::dec 
                   << std::endl;

    this->dut().host_c_opcode_i[this->position()]  = beat.opcode;
    this->dut().host_c_param_i[this->position()]   = beat.param;
    this->dut().host_c_size_i[this->position()]    = beat.size;
    this->dut().host_c_source_i[this->position()]  = beat.source;
    this->dut().host_c_address_i[this->position()] = beat.address;
    this->dut().host_c_corrupt_i[this->position()] = beat.corrupt;
    this->dut().host_c_data_i[this->position()]    = beat.data;
  }

  virtual void set_valid(bool valid) {
    this->dut().host_c_valid_i[this->position()] = valid;
  }

  void handle_request(bool randomise, tl_b& request) {
    b_requests.push(pair<bool, tl_b>(randomise, request));
  }

  // Generate the first beat of a response.
  tl_c new_response(bool randomise, tl_b& request) const;

  // Generate response beats from the first beat.
  tl_c get_beat(bool randomise, tl_c& response, int index) const;

  // Respond to a B request.
  void respond(bool randomise, tl_b& request);

  // Generate the first beat of a request (write back dirty data).
  tl_c new_request(bool randomise) const;

  // Create and enqueue a new request. `requirements` can be used to force
  // fields to have particular values.
  void queue_request(bool randomise, 
                     map<string, int> requirements = map<string, int>());

protected:

  virtual void modify(tl_c& response, map<string, int>& updates) {
    if (updates.find("opcode") != updates.end())
      response.opcode = (tl_c_op_e)updates["opcode"];
    if (updates.find("param") != updates.end())
      response.param = updates["param"];
    if (updates.find("size") != updates.end())
      response.size = updates["size"];
    if (updates.find("source") != updates.end())
      response.source = updates["source"];
    if (updates.find("address") != updates.end())
      response.address = updates["address"];
    if (updates.find("corrupt") != updates.end())
      response.corrupt = updates["corrupt"];
    if (updates.find("data") != updates.end())
      response.data = updates["data"];
  }

  virtual void respond();

  virtual void reorder_requests() {
    // Simple for now: move the front request to the back of the queue.
    if (!b_requests.empty()) {
      b_requests.push(b_requests.front());
      b_requests.pop();
    }
  }

private:
  // If we are not able to respond to a request immediately, queue it here.
  queue<pair<bool, tl_b>> b_requests;
};

class TileLinkSenderD : public TileLinkSender<tl_d> {
public:
  TileLinkSenderD(TileLinkEndpoint& parent) : 
      TileLinkSender<tl_d>(parent) {}

  virtual bool get_ready() const {
    return this->dut().dev_d_ready_o[this->position()];
  }

  virtual bool get_valid() const {
    return this->dut().dev_d_valid_i[this->position()];
  }

  virtual void set_data(tl_d beat) {
    MUNTJAC_LOG(1) << "Device " << this->position() << "D sending"
                   << " op:" << beat.opcode 
                   << " param:" << beat.param
                   << " size:" << beat.size 
                   << " src:" << beat.source
                   << " sink:" << beat.sink
                   << " denied:" << beat.denied
                   << " corrupt:" << beat.corrupt
                   << " data:0x" << std::hex << std::setw(16) << beat.data << std::dec 
                   << std::endl;

    this->dut().dev_d_opcode_i[this->position()]  = beat.opcode;
    this->dut().dev_d_param_i[this->position()]   = beat.param;
    this->dut().dev_d_size_i[this->position()]    = beat.size;
    this->dut().dev_d_source_i[this->position()]  = beat.source;
    this->dut().dev_d_sink_i[this->position()]    = beat.sink;
    this->dut().dev_d_denied_i[this->position()]  = beat.denied;
    this->dut().dev_d_corrupt_i[this->position()] = beat.corrupt;
    this->dut().dev_d_data_i[this->position()]    = beat.data;
  }

  virtual void set_valid(bool valid) {
    this->dut().dev_d_valid_i[this->position()] = valid;
  }

  void handle_request(bool randomise, tl_a& request) {
    a_requests.push(pair<bool, tl_a>(randomise, request));
  }

  void handle_request(bool randomise, tl_c& request) {
    c_requests.push(pair<bool, tl_c>(randomise, request));
  }

  // Generate the first beat of a response.
  tl_d new_response(bool randomise, tl_a& request) const;
  tl_d new_response(bool randomise, tl_c& request) const;

  // Generate response beats from the first beat.
  tl_d get_beat(bool randomise, tl_d& response, int index) const;

  void respond(bool randomise, tl_a& request);
  void respond(bool randomise, tl_c& request);

protected:

  virtual void modify(tl_d& response, map<string, int>& updates) {
    if (updates.find("opcode") != updates.end())
      response.opcode = (tl_d_op_e)updates["opcode"];
    if (updates.find("param") != updates.end())
      response.param = updates["param"];
    if (updates.find("size") != updates.end())
      response.size = updates["size"];
    if (updates.find("source") != updates.end())
      response.source = updates["source"];
    if (updates.find("sink") != updates.end())
      response.sink = updates["sink"];
    if (updates.find("denied") != updates.end())
      response.denied = updates["denied"];
    if (updates.find("corrupt") != updates.end())
      response.corrupt = updates["corrupt"];
    if (updates.find("data") != updates.end())
      response.data = updates["data"];
  }

  virtual void respond();

  virtual void reorder_requests() {
    // Simple for now: move the front request to the back of the queue.

    // A->D requests are not so simple. ArithmeticData and LogicalData requests
    // are multiple beats long. We can't swap a single beat out from a multibeat
    // request, and we can't swap a beat into the middle of a multibeat request.

    if (!a_requests.empty()) {
      // Take special care with ArithmeticData and LogicalData. These requests
      // can have multiple beats so doing a single push/pop might break things.
      if (a_requests.front().second.opcode != ArithmeticData &&
          a_requests.front().second.opcode != LogicalData &&
          a_requests.back().second.opcode != ArithmeticData &&
          a_requests.back().second.opcode != LogicalData) {
        a_requests.push(a_requests.front());
        a_requests.pop();
      }
    }
    if (!c_requests.empty()) {
      c_requests.push(c_requests.front());
      c_requests.pop();
    }
  }

private:
  // If we are not able to respond to a request immediately, queue it here.
  queue<pair<bool, tl_a>> a_requests;
  queue<pair<bool, tl_c>> c_requests;
};

class TileLinkSenderE : public TileLinkSender<tl_e> {
public:
  TileLinkSenderE(TileLinkEndpoint& parent) : 
      TileLinkSender<tl_e>(parent) {}

  virtual bool get_ready() const {
    return this->dut().host_e_ready_o[this->position()];
  }

  virtual bool get_valid() const {
    return this->dut().host_e_valid_i[this->position()];
  }

  virtual void set_data(tl_e beat) {
    MUNTJAC_LOG(1) << "Host   " << this->position() << "E sending"
                   << " sink:" << beat.sink
                   << std::endl;

    this->dut().host_e_sink_i[this->position()] = beat.sink;
  }

  virtual void set_valid(bool valid) {
    this->dut().host_e_valid_i[this->position()] = valid;
  }

  void handle_request(bool randomise, tl_d& request) {
    d_requests.push(pair<bool, tl_d>(randomise, request));
  }

  tl_e new_response(bool randomise, tl_d& request) const;

  void respond(bool randomise, tl_d& request);

protected:

  virtual void modify(tl_e& response, map<string, int>& updates) {
    if (updates.find("sink") != updates.end())
      response.sink = updates["sink"];
  }

  virtual void respond();

  virtual void reorder_requests() {
    // Simple for now: move the front request to the back of the queue.
    if (!d_requests.empty()) {
      d_requests.push(d_requests.front());
      d_requests.pop();
    }
  }

private:
  // If we are not able to respond to a request immediately, queue it here.
  queue<pair<bool, tl_d>> d_requests;
};


template<class channel>
class TileLinkReceiver : public TileLinkChannelEnd<channel> {
public:
  TileLinkReceiver(TileLinkEndpoint& parent) : 
      TileLinkChannelEnd<channel>(parent) {
    beats_remaining = 0;
    stall = false;
  }

  virtual bool get_valid() const = 0;
  virtual channel get_data() const = 0;
  virtual void set_ready(bool ready) = 0;

  // All channels must be able to respond to their own messages. Some channels
  // may inspect the messages and delegate to other channels (e.g. A -> D).
  virtual void handle_beat(bool randomise, channel data) = 0;

  channel await(int timeout=100) {
    for (int i=0; i<timeout; i++) {
      if (this->get_valid()) 
        return this->get_data();

      next_cycle();
    }

    assert(false && "No message received before timeout");
    return this->get_data();
  }

  bool stall;

  // Respond to inputs immediately if available.
  void step(bool randomise) {
    // TODO: Randomly stall.
    //bool stall = randomise && random_bool(0.8);
    //bool stall = false;

    if (this->get_valid() && !stall)
      this->handle_beat(randomise, this->get_data());

    stall = randomise && random_bool(0.8);
    this->set_ready(!stall);
  }

protected:

  // Determine whether this is the final beat of a multi-beat message.
  // Assumes no interleaving of messages (our assertions should catch this).
  void new_beat_arrived(int size) {
    if (all_beats_arrived())
      beats_remaining = this->num_beats(size);
    
    beats_remaining--;
  }
  bool all_beats_arrived() const {
    return beats_remaining == 0;
  }

private:

  // Some messages should only receive a response when all beats have arrived.
  int beats_remaining;

};

class TileLinkReceiverA : public TileLinkReceiver<tl_a> {
public:
  TileLinkReceiverA(TileLinkEndpoint& parent) : 
      TileLinkReceiver<tl_a>(parent) {}

  virtual bool get_valid() const {
    return this->dut().dev_a_valid_o[this->position()];
  }

  virtual tl_a get_data() const {
    tl_a data;

    data.opcode  = (tl_a_op_e)this->dut().dev_a_opcode_o[this->position()];
    data.param   = this->dut().dev_a_param_o[this->position()];
    data.size    = this->dut().dev_a_size_o[this->position()];
    data.source  = this->dut().dev_a_source_o[this->position()];
    data.address = this->dut().dev_a_address_o[this->position()];
    data.mask    = this->dut().dev_a_mask_o[this->position()];
    data.corrupt = this->dut().dev_a_corrupt_o[this->position()];
    data.data    = this->dut().dev_a_data_o[this->position()];

    return data;
  }

  virtual void set_ready(bool ready) {
    this->dut().dev_a_ready_i[this->position()] = ready;
  }

  virtual void handle_beat(bool randomise, tl_a data);
};

class TileLinkReceiverB : public TileLinkReceiver<tl_b> {
public:
  TileLinkReceiverB(TileLinkEndpoint& parent) : 
      TileLinkReceiver<tl_b>(parent) {}

  virtual bool get_valid() const {
    return this->dut().host_b_valid_o[this->position()];
  }

  virtual tl_b get_data() const {
    tl_b data;

    data.opcode  = (tl_b_op_e)this->dut().host_b_opcode_o[this->position()];
    data.param   = this->dut().host_b_param_o[this->position()];
    data.size    = this->dut().host_b_size_o[this->position()];
    data.source  = this->dut().host_b_source_o[this->position()];
    data.address = this->dut().host_b_address_o[this->position()];

    return data;
  }

  virtual void set_ready(bool ready) {
    this->dut().host_b_ready_i[this->position()] = ready;
  }

  virtual void handle_beat(bool randomise, tl_b data);
};

class TileLinkReceiverC : public TileLinkReceiver<tl_c> {
public:
  TileLinkReceiverC(TileLinkEndpoint& parent) : 
      TileLinkReceiver<tl_c>(parent) {}

  virtual bool get_valid() const {
    return this->dut().dev_c_valid_o[this->position()];
  }

  virtual tl_c get_data() const {
    tl_c data;

    data.opcode  = (tl_c_op_e)this->dut().dev_c_opcode_o[this->position()];
    data.param   = this->dut().dev_c_param_o[this->position()];
    data.size    = this->dut().dev_c_size_o[this->position()];
    data.source  = this->dut().dev_c_source_o[this->position()];
    data.address = this->dut().dev_c_address_o[this->position()];
    data.corrupt = this->dut().dev_c_corrupt_o[this->position()];
    data.data    = this->dut().dev_c_data_o[this->position()];

    return data;
  }

  virtual void set_ready(bool ready) {
    this->dut().dev_c_ready_i[this->position()] = ready;
  }

  virtual void handle_beat(bool randomise, tl_c data);
};

class TileLinkReceiverD : public TileLinkReceiver<tl_d> {
public:
  TileLinkReceiverD(TileLinkEndpoint& parent) : 
      TileLinkReceiver<tl_d>(parent) {}

  virtual bool get_valid() const {
    return this->dut().host_d_valid_o[this->position()];
  }

  virtual tl_d get_data() const {
    tl_d data;

    data.opcode  = (tl_d_op_e)this->dut().host_d_opcode_o[this->position()];
    data.param   = this->dut().host_d_param_o[this->position()];
    data.size    = this->dut().host_d_size_o[this->position()];
    data.source  = this->dut().host_d_source_o[this->position()];
    data.sink    = this->dut().host_d_sink_o[this->position()];
    data.denied  = this->dut().host_d_denied_o[this->position()];
    data.corrupt = this->dut().host_d_corrupt_o[this->position()];
    data.data    = this->dut().host_d_data_o[this->position()];

    return data;
  }

  virtual void set_ready(bool ready) {
    this->dut().host_d_ready_i[this->position()] = ready;
  }

  virtual void handle_beat(bool randomise, tl_d data);
};

class TileLinkReceiverE : public TileLinkReceiver<tl_e> {
public:
  TileLinkReceiverE(TileLinkEndpoint& parent) : 
      TileLinkReceiver<tl_e>(parent) {}

  virtual bool get_valid() const {
    return this->dut().dev_e_valid_o[this->position()];
  }

  virtual tl_e get_data() const {
    tl_e data;

    data.sink = this->dut().dev_e_sink_o[this->position()];

    return data;
  }

  virtual void set_ready(bool ready) {
    this->dut().dev_e_ready_i[this->position()] = ready;
  }

  virtual void handle_beat(bool randomise, tl_e data);
};


class TileLinkHost : public TileLinkEndpoint {
public:
  TileLinkHost(DUT& dut, int position, tl_protocol_e protocol, int bit_width,
               int first_source_id, int last_source_id) :
      TileLinkEndpoint(dut, position, protocol, bit_width, first_source_id,
                       last_source_id),
      a(*this),
      b(*this),
      c(*this),
      d(*this),
      e(*this) {
    // Nothing
  }

  void step(bool randomise) {
    // Randomly inject new requests.
    if (randomise) {
      // 1 in 10 chance in each clock cycle. Reasonable?
      if (random_bool(0.1))
        a.queue_request(true);
      if (random_bool(0.1))
        c.queue_request(true);
    }

    a.step(randomise);
    b.step(randomise);
    c.step(randomise);
    d.step(randomise);
    e.step(randomise);
  }

  TileLinkSenderA   a;
  TileLinkReceiverB b;
  TileLinkSenderC   c;
  TileLinkReceiverD d;
  TileLinkSenderE   e;
};

class TileLinkDevice : public TileLinkEndpoint {
public:
  TileLinkDevice(DUT& dut, int position, tl_protocol_e protocol, int bit_width,
                 int first_sink_id, int last_sink_id) : 
      TileLinkEndpoint(dut, position, protocol, bit_width, first_sink_id,
                       last_sink_id),
      a(*this),
      b(*this),
      c(*this),
      d(*this),
      e(*this) {
    // Nothing
  }

  void step(bool randomise) {
    // Randomly inject new requests.
    if (randomise) {
      // 1 in 20 chance in each clock cycle. Reasonable?
      if (random_bool(0.05))
        b.queue_request(true);
    }

    a.step(randomise);
    b.step(randomise);
    c.step(randomise);
    d.step(randomise);
    e.step(randomise);
  }

  TileLinkReceiverA a;
  TileLinkSenderB   b;
  TileLinkReceiverC c;
  TileLinkSenderD   d;
  TileLinkReceiverE e;
};

#endif // TL_CHANNELS_H
