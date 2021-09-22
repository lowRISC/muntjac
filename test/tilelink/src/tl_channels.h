// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include <queue>
#include "tilelink.h"
#include "Vtl_wrapper.h"

using std::queue;

typedef Vtl_wrapper DUT;

extern void next_cycle();

// Base class for a host/device, with connections to all TileLink channels.
class TileLinkEndpoint {
public:
  TileLinkEndpoint(DUT& dut, int position, tl_protocol_e protocol, int bit_width) :
      dut(dut), position(position), protocol(protocol), bit_width(bit_width) {
    // Nothing
  }

  DUT& dut;
  const int position;
  const tl_protocol_e protocol;
  const int bit_width;
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

  // `size` == log2(bytes)
  static int size_to_bits(int size) {return 8 * (1 << size);}
  static int bits_to_size(int bits) {return (int)(log2(bits / 8));}

  // The maximum value of the `size` field of any single-beat message on this
  // channel.
  int beat_size() const {return bits_to_size(bit_width());}

  // `size` is the TileLink field, log2(bytes).
  int full_mask(int size) const {
    int num_bytes = 1 << size;
    return (1 << num_bytes) - 1;
  }

private:
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
  void change_next_beat(map<string, int>& updates) {
    modifications.push(updates);
  }

  virtual bool get_ready() const = 0;
  virtual void set_data(channel data) = 0;
  virtual void set_valid(bool valid) = 0;

  // TODO
  // sendLoop()? Continuously try to send(), with random delays and possibly change response

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

protected:

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

  virtual void set_data(tl_a beat) {
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

  // TODO: this is single-beat only
  tl_a default_request() const {
    tl_a request;
    request.opcode = 0; // PutFullData
    request.param = 0;
    request.size = this->beat_size();
    request.source = this->position();
    request.address = this->get_address(0x3000, 0);
    request.mask = this->full_mask(request.size);
    request.corrupt = false;
    request.data = 0xDEADBEEFCAFEF00D;
    return request;
  }

  tl_a random_request() const {
    // TODO
    return default_request();
  }

  // TODO multibeat
  void new_request() {
    tl_a request = random_request();

    if (!this->modifications.empty()) {
      auto updates = this->modifications.front();
      modify(request, updates);
      this->modifications.pop();
    }

    this->to_send.push(request);
  }

private:
  static void modify(tl_a& request, map<string, int>& updates) {
    if (updates.find("opcode") != updates.end())
      request.opcode = updates["opcode"];
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
};

class TileLinkSenderB : public TileLinkSender<tl_b> {
public:
  TileLinkSenderB(TileLinkEndpoint& parent) : 
      TileLinkSender<tl_b>(parent) {}

  virtual bool get_ready() const {
    return this->dut().dev_b_ready_o[this->position()];
  }

  virtual void set_data(tl_b beat) {
    this->dut().dev_b_opcode_i[this->position()]  = beat.opcode;
    this->dut().dev_b_param_i[this->position()]   = beat.param;
    this->dut().dev_b_size_i[this->position()]    = beat.size;
    this->dut().dev_b_source_i[this->position()]  = beat.source;
    this->dut().dev_b_address_i[this->position()] = beat.address;
    this->dut().dev_b_mask_i[this->position()]    = beat.mask;
    this->dut().dev_b_corrupt_i[this->position()] = beat.corrupt;
    this->dut().dev_b_data_i[this->position()]    = beat.data;
  }

  virtual void set_valid(bool valid) {
    this->dut().dev_b_valid_i[this->position()] = valid;
  }

private:
  static void modify(tl_b& request, map<string, int>& updates) {
    if (updates.find("opcode") != updates.end())
      request.opcode = updates["opcode"];
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
};

class TileLinkSenderC : public TileLinkSender<tl_c> {
public:
  TileLinkSenderC(TileLinkEndpoint& parent) : 
      TileLinkSender<tl_c>(parent) {}

  virtual bool get_ready() const {
    return this->dut().host_c_ready_o[this->position()];
  }

  virtual void set_data(tl_c beat) {
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

private:
  static void modify(tl_c& response, map<string, int>& updates) {
    if (updates.find("opcode") != updates.end())
      response.opcode = updates["opcode"];
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
};

class TileLinkSenderD : public TileLinkSender<tl_d> {
public:
  TileLinkSenderD(TileLinkEndpoint& parent) : 
      TileLinkSender<tl_d>(parent) {}

  virtual bool get_ready() const {
    return this->dut().dev_d_ready_o[this->position()];
  }

  virtual void set_data(tl_d beat) {
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

  // TODO: this is single-beat only
  tl_d default_response(tl_a& request) const {
    tl_d response;

    // TODO: more opcodes
    //       get the data from somewhere
    if (request.opcode == 0) // PutFullData
      response.opcode = 0;
    else if (request.opcode == 4) // Get
      response.opcode = 1;
    else
      assert(false && "Unsupported request opcode");

    response.param = 0;
    response.size = request.size;
    response.source = request.source;
    response.sink = this->position();
    response.denied = false;
    response.corrupt = false;
    response.data = 0x1234567890abcdef;

    return response;
  }

  tl_d random_response(tl_a& request) const {
    // TODO
    return default_response(request);
  }

  // TODO: allow multi-beat responses
  // TODO: respond to C messages too
  void respond(tl_a& request) {
    tl_d response = random_response(request);

    // TODO: also allow modifications to drop/repeat a beat
    if (!this->modifications.empty()) {
      auto updates = this->modifications.front();
      modify(response, updates);
      this->modifications.pop();
    }

    this->to_send.push(response);
  }

private:
  static void modify(tl_d& response, map<string, int>& updates) {
    if (updates.find("opcode") != updates.end())
      response.opcode = updates["opcode"];
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
};

class TileLinkSenderE : public TileLinkSender<tl_e> {
public:
  TileLinkSenderE(TileLinkEndpoint& parent) : 
      TileLinkSender<tl_e>(parent) {}

  virtual bool get_ready() const {
    return this->dut().host_e_ready_o[this->position()];
  }

  virtual void set_data(tl_e beat) {
    this->dut().host_e_sink_i[this->position()] = beat.sink;
  }

  virtual void set_valid(bool valid) {
    this->dut().host_e_valid_i[this->position()] = valid;
  }

private:
  static void modify(tl_e& response, map<string, int>& updates) {
    if (updates.find("sink") != updates.end())
      response.sink = updates["sink"];
  }
};


template<class channel>
class TileLinkReceiver : public TileLinkChannelEnd<channel> {
public:
  TileLinkReceiver(TileLinkEndpoint& parent) : 
      TileLinkChannelEnd<channel>(parent) {
    // Nothing
  }

  virtual bool get_valid() const = 0;
  virtual channel get_data() const = 0;

  channel await(int timeout=100) {
    for (int i=0; i<timeout; i++) {
      if (this->get_valid()) 
        return this->get_data();

      next_cycle();
    }

    assert(false && "No message received before timeout");
    return this->get_data();
  }

  // receiveLoop()? Continuously try to receive() with random delays - is that allowed?
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

    data.opcode  = this->dut().dev_a_opcode_o[this->position()];
    data.param   = this->dut().dev_a_param_o[this->position()];
    data.size    = this->dut().dev_a_size_o[this->position()];
    data.source  = this->dut().dev_a_source_o[this->position()];
    data.address = this->dut().dev_a_address_o[this->position()];
    data.mask    = this->dut().dev_a_mask_o[this->position()];
    data.corrupt = this->dut().dev_a_corrupt_o[this->position()];
    data.data    = this->dut().dev_a_data_o[this->position()];

    return data;
  }

  void set_ready(bool ready) {
    this->dut().dev_a_ready_i[this->position()] = ready;
  }
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

    data.opcode  = this->dut().host_b_opcode_o[this->position()];
    data.param   = this->dut().host_b_param_o[this->position()];
    data.size    = this->dut().host_b_size_o[this->position()];
    data.source  = this->dut().host_b_source_o[this->position()];
    data.address = this->dut().host_b_address_o[this->position()];
    data.mask    = this->dut().host_b_mask_o[this->position()];
    data.corrupt = this->dut().host_b_corrupt_o[this->position()];
    data.data    = this->dut().host_b_data_o[this->position()];

    return data;
  }

  void set_ready(bool ready) {
    this->dut().host_b_ready_i[this->position()] = ready;
  }
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

    data.opcode  = this->dut().dev_c_opcode_o[this->position()];
    data.param   = this->dut().dev_c_param_o[this->position()];
    data.size    = this->dut().dev_c_size_o[this->position()];
    data.source  = this->dut().dev_c_source_o[this->position()];
    data.address = this->dut().dev_c_address_o[this->position()];
    data.corrupt = this->dut().dev_c_corrupt_o[this->position()];
    data.data    = this->dut().dev_c_data_o[this->position()];

    return data;
  }

  void set_ready(bool ready) {
    this->dut().dev_c_ready_i[this->position()] = ready;
  }
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

    data.opcode  = this->dut().host_d_opcode_o[this->position()];
    data.param   = this->dut().host_d_param_o[this->position()];
    data.size    = this->dut().host_d_size_o[this->position()];
    data.source  = this->dut().host_d_source_o[this->position()];
    data.sink    = this->dut().host_d_sink_o[this->position()];
    data.denied  = this->dut().host_d_denied_o[this->position()];
    data.corrupt = this->dut().host_d_corrupt_o[this->position()];
    data.data    = this->dut().host_d_data_o[this->position()];

    return data;
  }

  void set_ready(bool ready) {
    this->dut().host_d_ready_i[this->position()] = ready;
  }
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

  void set_ready(bool ready) {
    this->dut().dev_e_ready_i[this->position()] = ready;
  }
};


class TileLinkHost : public TileLinkEndpoint {
public:
  TileLinkHost(DUT& dut, int position, tl_protocol_e protocol, int bit_width) :
      TileLinkEndpoint(dut, position, protocol, bit_width),
      a(*this),
      b(*this),
      c(*this),
      d(*this),
      e(*this) {
    // Nothing
  }

  TileLinkSenderA   a;
  TileLinkReceiverB b;
  TileLinkSenderC   c;
  TileLinkReceiverD d;
  TileLinkSenderE   e;
};

class TileLinkDevice : public TileLinkEndpoint {
public:
  TileLinkDevice(DUT& dut, int position, tl_protocol_e protocol, int bit_width) : 
      TileLinkEndpoint(dut, position, protocol, bit_width),
      a(*this),
      b(*this),
      c(*this),
      d(*this),
      e(*this) {
    // Nothing
  }

  TileLinkReceiverA a;
  TileLinkSenderB   b;
  TileLinkReceiverC c;
  TileLinkSenderD   d;
  TileLinkReceiverE e;
};
