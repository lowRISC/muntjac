// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Simulated main memory.
// Uses a simple form of virtual memory so we only need to simulate the parts
// of the address space that are actually used.

#ifndef MAIN_MEMORY_H
#define MAIN_MEMORY_H

#include <map>
#include "data_block.h"
#include "types.h"

class MainMemory {

public:

  MainMemory();
  ~MainMemory();

  // Read `num_bytes` bytes, starting at `address`.
  DataBlock read(MemoryAddress address, size_t num_bytes);

  // Write a block of data into memory.
  void write(DataBlock data);

  // Read data. All values are unsigned.
  uint8_t  read8(MemoryAddress address);
  uint16_t read16(MemoryAddress address);
  uint32_t read32(MemoryAddress address);
  uint64_t read64(MemoryAddress address);

  // Write data.
  void     write8(MemoryAddress address, uint8_t data);
  void     write16(MemoryAddress address, uint16_t data);
  void     write32(MemoryAddress address, uint32_t data);
  void     write64(MemoryAddress address, uint64_t data);

private:

  char* get_page(MemoryAddress address);

  // Create a new page and record it in the page map.
  char* allocate_new_page(MemoryAddress address);

  std::map<MemoryAddress, char*> pages;

};

#endif  // MAIN_MEMORY_H
