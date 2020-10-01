// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#ifndef PAGE_TABLE_ENTRY_H
#define PAGE_TABLE_ENTRY_H

#include <cstdint>

class PageTableEntrySv39 {
public:

  PageTableEntrySv39(uint64_t value) : value(value) {}

  bool valid()                const {return (value >> 0) & 0x1;}

  bool readable()             const {return (value >> 1) & 0x1;}
  bool writable()             const {return (value >> 2) & 0x1;}
  bool executable()           const {return (value >> 3) & 0x1;}

  bool user_mode_accessible() const {return (value >> 4) & 0x1;}
  bool global()               const {return (value >> 5) & 0x1;}

  bool accessed()             const {return (value >> 6) & 0x1;}
  bool dirty()                const {return (value >> 7) & 0x1;}

  // There are up to three page numbers, with indices 0, 1 and 2. Any other
  // index results in all three page numbers being concatenated and returned as
  // a single value.
  uint64_t physical_page_number(int index=-1) const {
    switch (index) {
      case 0:  return (value >> 10) & 0x1FF;
      case 1:  return (value >> 19) & 0x1FF;
      case 2:  return (value >> 28) & 0x3FFFFFF;
      default: return (value >> 10) & 0xFFFFFFFFFFFULL;
    }
  }

  uint64_t get_value()        const {return value;}

  void set_accessed()               {value |= (1 << 6);}
  void set_dirty()                  {value |= (1 << 7);}

private:

  uint64_t value;

};

#endif  // PAGE_TABLE_ENTRY_H
