// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#ifndef PAGE_TABLE_WALKER_H
#define PAGE_TABLE_WALKER_H

#include "main_memory.h"
#include "types.h"
#include "virtual_addressing.h"

class PageTableWalkerSv39 {
public:

  PageTableWalkerSv39(MainMemory& memory);

  // Perform virtual->physical address translation.
  // This may throw a PageFault, and the underlying memory accesses may throw
  // AccessFaults.
  MemoryAddress translate(MemoryAddress virtual_address,
                          MemoryOperation operation,
                          bool supervisor, // Are we in supervisor mode?
                          bool sum,        // Can S mode access U data?
                          bool mxr,        // Allow loads from executable pages
                          AddressTranslationProtection64 atp);

private:

  MainMemory& memory;

};

#endif  // PAGE_TABLE_WALKER_H
