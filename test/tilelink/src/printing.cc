// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include <iomanip>
#include "printing.h"

using std::ostream;
using std::hex;
using std::dec;
using std::setw;

// TODO: more functions to print params nicely?

std::ostream& operator<<(std::ostream& os, const tl_a_op_e& op) {
  switch (op) {
    case PutFullData:    return os << "PutFullData";
    case PutPartialData: return os << "PutPartialData";
    case ArithmeticData: return os << "ArithmeticData";
    case LogicalData:    return os << "LogicalData";
    case Get:            return os << "Get";
    case Intent:         return os << "Intent";
    case AcquireBlock:   return os << "AcquireBlock";
    case AcquirePerm:    return os << "AcquirePerm";
  }
}

std::ostream& operator<<(std::ostream& os, const tl_b_op_e& op) {
  switch (op) {
    case ProbeBlock:     return os << "ProbeBlock";
    case ProbePerm:      return os << "ProbePerm";
  }
}

std::ostream& operator<<(std::ostream& os, const tl_c_op_e& op) {
  switch (op) {
    case ProbeAck:       return os << "ProbeAck";
    case ProbeAckData:   return os << "ProbeAckData";
    case Release:        return os << "Release";
    case ReleaseData:    return os << "ReleaseData";
  }
}

std::ostream& operator<<(std::ostream& os, const tl_d_op_e& op) {
  switch (op) {
    case AccessAck:      return os << "AccessAck";
    case AccessAckData:  return os << "AccessAckData";
    case HintAck:        return os << "HintAck";
    case Grant:          return os << "Grant";
    case GrantData:      return os << "GrantData";
    case ReleaseAck:     return os << "ReleaseAck";
  }
}


ostream& operator<<(ostream& os, const tl_a& data) { 
  return os <<  "op:"      << setw(14) << data.opcode 
            << " param:"   << data.param
            << " size:"    << data.size 
            << " src:"     << data.source
            << " addr:0x"  << setw(8)  << hex << data.address << dec
            << " mask:0x"  << setw(2)  << hex << data.mask    << dec
            << " corrupt:" << data.corrupt
            << " data:0x"  << setw(16) << hex << data.data    << dec;
}

ostream& operator<<(ostream& os, const tl_b& data) { 
  return os <<  "op:"      << setw(14) << data.opcode 
            << " param:"   << data.param
            << " size:"    << data.size 
            << " src:"     << data.source
            << " addr:0x"  << setw(8)  << hex << data.address << dec;
}

ostream& operator<<(ostream& os, const tl_c& data) { 
  return os <<  "op:"      << setw(14) << data.opcode 
            << " param:"   << data.param
            << " size:"    << data.size 
            << " src:"     << data.source
            << " addr:0x"  << setw(8)  << hex << data.address << dec
            << " corrupt:" << data.corrupt
            << " data:0x"  << setw(16) << hex << data.data    << dec;
}

ostream& operator<<(ostream& os, const tl_d& data) { 
  return os <<  "op:"      << setw(14) << data.opcode 
            << " param:"   << data.param
            << " size:"    << data.size 
            << " src:"     << data.source
            << " sink:"    << data.sink
            << " denied:"  << data.denied
            << " corrupt:" << data.corrupt
            << " data:0x"  << setw(16) << hex << data.data    << dec;
}

ostream& operator<<(ostream& os, const tl_e& data) { 
  return os << " sink:"    << data.sink;
}
