// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#ifndef VIRTUAL_ADDRESSING_H
#define VIRTUAL_ADDRESSING_H

#include <cstdint>

// Paging modes. Taken from the RISC-V spec.
typedef enum {
  ATP_MODE_BARE = 0,
  ATP_MODE_SV32 = 1,
  ATP_MODE_SV39 = 8,
  ATP_MODE_SV48 = 9
} atp_mode_e;


// Details about how translation should work. Used by the atp control registers.
class AddressTranslationProtection64 {
public:

  AddressTranslationProtection64(uint64_t value) : value(value) {}

  atp_mode_e mode()                 const {return (atp_mode_e)((value >> 60) & 0xF);}
  uint       address_space_id()     const {return (value >> 44) & 0xFFFF;}
  uint64_t   physical_page_number() const {return (value >> 0)  & 0xFFFFFFFFFFFULL;}

private:

  uint64_t value;

};


// A virtual/physical address in the 3-level Sv39 system.
class Sv39 {
public:

  // The maximum physical memory address allowed by the spec.
  static const MemoryAddress MAX_PHYSICAL_ADDRESS = (1ULL << 56) - 1;

  // Base ISA width.
  static const uint XLEN = 64;

  // Bits in a virtual address.
  static const uint VALEN = 39;

  // Minimum size of a page.
  static const uint PAGESIZE = 4096;

  // Bytes in a page table entry.
  static const uint PTESIZE = 8;

  // Maximum depth of page table hierarchy.
  static const uint LEVELS = 3;

  // Corresponding MODE bits in the SATP control register.
  static const atp_mode_e ATP_MODE = ATP_MODE_SV39;

  Sv39(uint64_t value) : value(value) {}
  Sv39(uint offset, uint ppn0, uint ppn1, uint ppn2) {
    value = offset
          + ((ppn0 & 0x1FF) << 12)
          + ((ppn1 & 0x1FF) << 21)
          + ((ppn2 & 0x3FFFFFF) << 30);  // ppn2 is larger than the others
  }

  uint64_t get_value() const {return value;}

  uint     offset()    const {return (value >> 0) & 0xFFF;}

  // There are up to three page numbers, with indices 0, 1 and 2. Any other
  // index results in all three page numbers being concatenated and returned as
  // a single value.
  uint64_t virtual_page_number(int index=-1) const {
    switch (index) {
      case 0:  return (value >> 12) & 0x1FF;
      case 1:  return (value >> 21) & 0x1FF;
      case 2:  return (value >> 30) & 0x1FF;
      default: return (value >> 12) & 0x7FFFFFFULL;
    }
  }

private:

  uint64_t value;

};

#endif  // VIRTUAL_ADDRESSING_H
