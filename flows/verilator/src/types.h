// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#ifndef TYPES_H
#define TYPES_H

#include <cstdint>

typedef uint64_t MemoryAddress;

// Verilator doesn't provide access to constants defined in the RTL.
// Always ensure this matches mem_op_e in muntjac_pkg.sv.
typedef enum {
  MEM_LOAD  = 1,
  MEM_STORE = 2,
  MEM_LR    = 5,
  MEM_SC    = 6,
  MEM_AMO   = 7,
  MEM_FETCH = 100  // Not used in the Verilog
} MemoryOperation;

// From muntjac_pkg/RISC-V spec, with added EXC_CAUSE_NONE.
typedef enum {
  EXC_CAUSE_IRQ_SOFTWARE_S     = 17,
  EXC_CAUSE_IRQ_SOFTWARE_M     = 19,
  EXC_CAUSE_IRQ_TIMER_S        = 21,
  EXC_CAUSE_IRQ_TIMER_M        = 23,
  EXC_CAUSE_IRQ_EXTERNAL_S     = 25,
  EXC_CAUSE_IRQ_EXTERNAL_M     = 27,
  EXC_CAUSE_INSN_ADDR_MISA     = 0,
  EXC_CAUSE_INSTR_ACCESS_FAULT = 1,
  EXC_CAUSE_ILLEGAL_INSN       = 2,
  EXC_CAUSE_BREAKPOINT         = 3,
  EXC_CAUSE_LOAD_MISALIGN      = 4,
  EXC_CAUSE_LOAD_ACCESS_FAULT  = 5,
  EXC_CAUSE_STORE_MISALIGN     = 6,
  EXC_CAUSE_STORE_ACCESS_FAULT = 7,
  EXC_CAUSE_ECALL_UMODE        = 8,
  EXC_CAUSE_ECALL_SMODE        = 9,
  EXC_CAUSE_ECALL_MMODE        = 11,
  EXC_CAUSE_INSTR_PAGE_FAULT   = 12,
  EXC_CAUSE_LOAD_PAGE_FAULT    = 13,
  EXC_CAUSE_STORE_PAGE_FAULT   = 15,

  EXC_CAUSE_NONE               = 100
} exc_cause_e;

#endif  // TYPES_H
