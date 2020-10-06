// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include <cassert>

#include "exceptions.h"
#include "page_table_entry.h"
#include "page_table_walker.h"
#include "virtual_addressing.h"

PageTableWalkerSv39::PageTableWalkerSv39(MainMemory& memory) :
    memory(memory) {
  // Nothing
}

// This is the algorithm given in the RISC-V spec.
//
// A virtual address va is translated into a physical address pa as follows:
//
// 1. If XLEN equals VALEN, proceed. Otherwise, check whether each bit of
//    va[XLEN-1:VALEN] is equal to va[VALEN-1]. If not, stop and raise a
//    page-fault exception corresponding to the original access type.
//
// 2. Let a be satp.ppn × PAGESIZE, and let i = LEVELS − 1.
//
// 3. Let pte be the value of the PTE at address a+va.vpn[i]×PTESIZE.
//    If accessing pte violates a PMA or PMP check, raise an access-fault
//    exception corresponding to the original access type.
//
// 4. If pte.v = 0, or if pte.r = 0 and pte.w = 1, stop and raise a page-fault
//    exception corresponding to the original access type.
//
// 5. Otherwise, the PTE is valid. If pte.r = 1 or pte.x = 1, go to step 6.
//    Otherwise, this PTE is a pointer to the next level of the page table.
//    Let i = i − 1. If i < 0, stop and raise a page-fault exception
//    corresponding to the original access type. Otherwise, let
//    a = pte.ppn × PAGESIZE and go to step 3.
//
// 6. A leaf PTE has been found. Determine if the requested memory access is
//    allowed by the pte.r, pte.w, pte.x, and pte.u bits, given the current
//    privilege mode and the value of the SUM and MXR fields of the mstatus
//    register. If not, stop and raise a page-fault exception corresponding to
//    the original access type.
//
// 7. If i > 0 and pte.ppn[i − 1 : 0] != 0, this is a misaligned superpage; stop
//    and raise a page-fault exception corresponding to the original access
//    type.
//
// 8. If pte.a = 0, or if the memory access is a store and pte.d = 0, either
//    raise a page-fault exception corresponding to the original access type,
//    or:
//      • Set pte.a to 1 and, if the memory access is a store, also set pte.d
//        to 1.
//      • If this access violates a PMA or PMP check, raise an access-fault
//        exception corresponding to the original access type.
//      • This update and the loading of pte in step 3 must be atomic; in
//        particular, no intervening store to the PTE may be perceived to have
//        occurred in-between.
//
// 9. The translation is successful. The translated physical address is given as
//    follows:
//      • pa.pgoff = va.pgoff.
//      • If i > 0, then this is a superpage translation and
//        pa.ppn[i − 1 : 0] = va.vpn[i − 1 : 0].
//      • pa.ppn[LEVELS − 1 : i] = pte.ppn[LEVELS − 1 : i].

MemoryAddress PageTableWalkerSv39::translate(
    MemoryAddress virtual_address,
    MemoryOperation operation,
    bool supervisor, // Are we in supervisor mode?
    bool sum,        // Can S mode access U data?
    bool mxr,        // Allow loads from executable pages
    AddressTranslationProtection64 atp) { // Address translation data

  // TODO: make the addressing mode a (template?) parameter.
  assert(atp.mode() == Sv39::ATP_MODE);

  Sv39 va(virtual_address);

  // 1. Ensure all upper bits match the MSB of the virtual address.
  bool msb = (virtual_address >> (Sv39::VALEN - 1)) & 0x1;
  int64_t upper = (int64_t)virtual_address >> Sv39::VALEN;
  if ((msb && (upper != -1)) || (!msb && (upper != 0)))
    throw PageFault(virtual_address, "Invalid upper bits of virtual address");

  // 2. Initialisation.
  MemoryAddress a = atp.physical_page_number() * Sv39::PAGESIZE;
  MemoryAddress pte_address = 0;
  PageTableEntrySv39 pte(0);
  int i = Sv39::LEVELS - 1;

  while (true) {
    // 3. Access page table entry. (Not simulating memory latency).
    pte_address = a + va.virtual_page_number(i) * Sv39::PTESIZE;
    pte = PageTableEntrySv39(memory.read64(pte_address));

    // 4. Check that PTE is valid.
    if (!pte.valid() || (!pte.readable() && pte.writable()))
      throw PageFault(virtual_address, "Invalid page table entry");

    // 5. Check if this page table entry is a leaf.
    if (pte.readable() || pte.executable())
      break;

    i = i - 1;
    if (i < 0)
      throw PageFault(virtual_address, "Didn't find leaf page");
    a = pte.physical_page_number() * Sv39::PAGESIZE;
  }

  // 6. Check permissions.
  bool read = (operation == MEM_LOAD) || (operation == MEM_LR) ||
              (operation == MEM_AMO);
  bool write = (operation == MEM_STORE) || (operation == MEM_SC) ||
               (operation == MEM_AMO);
  bool execute = (operation == MEM_FETCH);
  if ((read && !(pte.readable() || (mxr && pte.executable()))) ||
      (write && !pte.writable()) ||
      (execute && !pte.executable()) ||
      (supervisor && pte.user_mode_accessible() && (!sum || (execute && pte.executable()))) ||
      (!supervisor && !pte.user_mode_accessible())) {
    throw PageFault(virtual_address, "Insufficient permissions");
  }

  // 7. Check for misaligned superpage.
  if (i > 0)
    for (uint j=0; j<i; j++)
      if (pte.physical_page_number(j) != 0)
        throw PageFault(virtual_address, "Misaligned superpage");

  // 8. Update page table entry's accessed/dirty bits.
  if (!pte.accessed() || (write && !pte.dirty())) {
    if (!pte.accessed())
      pte.set_accessed();
    if (write && !pte.dirty())
      pte.set_dirty();

    memory.write64(pte_address, pte.get_value());
  }

  // 9. Do address translation.
  uint offset = va.offset();
  uint ppn0 = (i > 0) ? va.virtual_page_number(0) : pte.physical_page_number(0);
  uint ppn1 = (i > 1) ? va.virtual_page_number(1) : pte.physical_page_number(1);
  uint ppn2 = (i > 2) ? va.virtual_page_number(2) : pte.physical_page_number(2);
  return Sv39(offset, ppn0, ppn1, ppn2).get_value();

}
