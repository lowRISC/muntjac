// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// One access port for main memory. All ports can access memory in parallel.

#ifndef MEMORY_PORT_H
#define MEMORY_PORT_H

#include <queue>
#include "main_memory.h"

using std::queue;

// Verilator doesn't provide access to constants defined in the RTL.
// Always ensure this matches mem_op_e in muntjac_pkg.sv.
typedef enum {
  MEM_LOAD  = 1,
  MEM_STORE = 2,
  MEM_LR    = 5,
  MEM_SC    = 6,
  MEM_AMO   = 7
} MemoryOperation;

template<typename T>
struct MemoryResponse {
  uint64_t time;  // Cycle for response to be sent.
  T data; // Data to send.
  bool all_sent; // May need to send data in multiple chunks.
};

// T is the datatype used to communicate data between the core and the cache.
// This can be a simple integer in some cases, or any arbitrary datatype.
template<typename T>
class MemoryPort {

protected:

  typedef struct MemoryResponse<T> response_t;

public:

  MemoryPort(MainMemory& memory, uint latency);

  void cycle(uint64_t time);

protected:

  virtual bool can_receive_request() = 0;
  virtual void get_request() = 0;
  virtual void queue_response(T data);
  virtual bool can_send_response() = 0;
  virtual void send_response(response_t& response) = 0;
  virtual void clear_response() = 0;

protected:

  MainMemory& memory;

private:

  uint64_t current_cycle;

  const uint latency;

  queue<response_t> responses;

};

#endif  // MEMORY_PORT_H
