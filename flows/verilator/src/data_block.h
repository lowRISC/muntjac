// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Contiguous block of data.

#ifndef DATA_BLOCK_H
#define DATA_BLOCK_H

#include <cstddef>
#include <memory>
#include "types.h"

using std::shared_ptr;

class DataBlock {
public:

  DataBlock(MemoryAddress address, size_t num_bytes, shared_ptr<char> ptr);

  MemoryAddress    get_address()   const;
  size_t           get_num_bytes() const;
  shared_ptr<char> get_data()      const;

private:
  shared_ptr<char> data;
  MemoryAddress    address;
  size_t           num_bytes;
};

#endif  // DATA_BLOCK_H
