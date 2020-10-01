// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#ifndef PAGE_TABLE_WALKER_H
#define PAGE_TABLE_WALKER_H

#include "main_memory.h"
#include "types.h"
#include "virtual_addressing.h"

typedef struct {
  MemoryAddress physical_address;
  exc_cause_e   exception;
} ptw_response_t;

class PageTableWalkerSv39 {
public:

  PageTableWalkerSv39(MainMemory& memory);

  ptw_response_t translate(MemoryAddress virtual_address,
                           MemoryOperation operation,
                           bool supervisor, // Are we in supervisor mode?
                           bool sum,        // Can S mode access U data?
                           bool mxr,        // Allow loads from executable pages
                           AddressTranslationProtection64 atp);

private:

  static const uint XLEN = 64;
  static const uint VALEN = 39;
  static const uint PAGESIZE = 4096;
  static const uint PTESIZE = 8;
  static const uint LEVELS = 3;

  MainMemory& memory;

};

#endif  // PAGE_TABLE_WALKER_H
