// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#ifndef BINARY_PARSER_H
#define BINARY_PARSER_H

#include "types.h"

class MainMemory;

class BinaryParser {

public:

  // Load the contents of a RISC-V executable and its arguments into `memory`.
  static void load_elf(int argc, char** argv, MainMemory& memory);

  // Determine the memory address of the first instruction to be executed in the
  // given program.
  static MemoryAddress entry_point(char* filename);

};

#endif  // BINARY_PARSER_H
