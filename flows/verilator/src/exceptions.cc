// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include <cassert>

#include "exceptions.h"
#include "logs.h"

MuntjacException::MuntjacException(string description) :
    std::exception(),
    message(description) {
  MUNTJAC_LOG(2) << this->what() << endl;
}

const char* MuntjacException::what() const noexcept {
  return message.c_str();
}


AccessFault::AccessFault(MemoryAddress address, string description) :
    MuntjacException("Access fault: " + description),
    address(address) {
  // Nothing
}

exc_cause_e AccessFault::get_exception_code(MemoryOperation operation) const {
  switch (operation) {
    case MEM_LOAD:
    case MEM_LR:
      return EXC_CAUSE_LOAD_ACCESS_FAULT;

    case MEM_STORE:
    case MEM_SC:
    case MEM_AMO:
      return EXC_CAUSE_STORE_ACCESS_FAULT;

    case MEM_FETCH:
      return EXC_CAUSE_INSTR_ACCESS_FAULT;

    default:
      assert(false);
      break;
  }
}


AlignmentFault::AlignmentFault(MemoryAddress address) :
    MuntjacException("Alignment fault"),
    address(address) {
  // Nothing
}

exc_cause_e AlignmentFault::get_exception_code(MemoryOperation operation) const {
  switch (operation) {
    case MEM_LOAD:
    case MEM_LR:
      return EXC_CAUSE_LOAD_MISALIGN;

    case MEM_STORE:
    case MEM_SC:
    case MEM_AMO:
      return EXC_CAUSE_STORE_MISALIGN;

//    case MEM_FETCH:
    default:
      assert(false);
      break;
  }
}


PageFault::PageFault(MemoryAddress address, string description) :
    MuntjacException("Page fault: " + description),
    address(address) {
  // Nothing
}

exc_cause_e PageFault::get_exception_code(MemoryOperation operation) const {
  switch (operation) {
    case MEM_LOAD:
    case MEM_LR:
      return EXC_CAUSE_LOAD_PAGE_FAULT;

    case MEM_STORE:
    case MEM_SC:
    case MEM_AMO:
      return EXC_CAUSE_STORE_PAGE_FAULT;

    case MEM_FETCH:
      return EXC_CAUSE_INSTR_PAGE_FAULT;

    default:
      assert(false);
      break;
  }
}
