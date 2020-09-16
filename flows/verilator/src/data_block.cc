// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include "data_block.h"

DataBlock::DataBlock(MemoryAddress address, size_t num_bytes,
                     shared_ptr<char> ptr) {
  this->address = address;
  this->num_bytes = num_bytes;
  this->data = ptr;
}

MemoryAddress DataBlock::get_address() const {
  return address;
}

size_t DataBlock::get_num_bytes() const {
  return num_bytes;
}

shared_ptr<char> DataBlock::get_data() const {
  return data;
}
