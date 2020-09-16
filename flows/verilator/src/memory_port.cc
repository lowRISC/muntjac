// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

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
void MemoryPort<T>::cycle(uint64_t time) {
  current_cycle = time;

  // Clear any previous outputs.
  clear_response();

  // Receive requests from core.
  if (can_receive_request())
    get_request();  // Puts requests into request queue.

  // Send responses to core.
  if (!responses.empty() && responses.front().time <= time && can_send_response()) {
    send_response(responses.front());

    // Remove the response from the queue when it has all been sent.
    if (responses.front().all_sent)
      responses.pop();
  }
}

template<typename T>
void MemoryPort<T>::queue_response(T data) {
  // Send data the cycle before it is due to arrive.
  response_t response;
  response.time = current_cycle + latency - 1;
  response.data = data;
  response.all_sent = false;

  responses.push(response);
}
