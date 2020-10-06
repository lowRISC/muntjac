// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include <cassert>

#include "logs.h"
#include "main_memory.h"
#include "memory_port.h"

// Need to list the possible template parameters.
template class MemoryPort<uint32_t>;
template class MemoryPort<uint64_t>;


template<typename T>
MemoryPort<T>::MemoryPort(MainMemory& memory, uint latency) :
    latency(latency),
    memory(memory) {
  // Nothing
}

template<typename T>
void MemoryPort<T>::get_inputs(uint64_t time) {
  current_cycle = time;

  // Receive requests from core.
  if (can_receive_request())
    get_request();  // Puts requests into request queue.
}

template<typename T>
void MemoryPort<T>::set_outputs(uint64_t time) {
  current_cycle = time;

  // Clear any previous outputs.
  clear_response();

  // Send responses to core.
  if (!responses.empty() && responses.front().time <= time && can_send_response()) {
    send_response(responses.front());

    // Remove the response from the queue when it has all been sent.
    if (responses.front().all_sent)
      responses.pop();
  }
}

template<typename T>
void MemoryPort<T>::queue_response(T data, exc_cause_e exception) {
  response_t response;
  response.time = current_cycle + latency;
  response.data = data;
  response.exception = exception;
  response.all_sent = false;

  responses.push(response);
}
