// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

// Parsing of ELF binaries:
//   http://wiki.osdev.org/ELF_Tutorial
//   https://code.google.com/p/elfinfo/source/browse/trunk/elfinfo.c

// TODO
//  * Probably switch to Elf64_*
//  * Check that arguments should be stored the same way as Loki.

#include <cassert>
#include <cstring>
#include <elf.h>
#include <fstream>
#include <stdio.h>
#include <vector>
#include "binary_parser.h"
#include "main_memory.h"

using std::ifstream;
using std::vector;

DataBlock arguments(int argc, char** argv) {
  // Target memory looks like this:
  // 0x00000000 zero word
  // 0x00000004 argc word
  // 0x00000008 start of argv
  // ...
  // 0x0000???? end of argv
  // 0x0000???? zero word
  // 0x0000???? start of data pointed to by argv

  // Start of argv storage.
  size_t argv_ptr = 4 + 4 + argc * 8 + 4;

  // Fixed-size allocation for now.
  char* data = new char[1024];

  *((uint32_t*)data) = 0;
  *((uint32_t*)(data + 4)) = argc;
  *((uint32_t*)(data + 4 + 4 + argc * 8)) = 0;

  for (int i=0; i<argc; i++) {
    // Muntjac pointers are 64 bits, so cast to a datatype known to be that
    // length.
    *((uint64_t*)(data + 4 + 4 + i * 8)) = argv_ptr;
    strcpy(data + argv_ptr, argv[i]);
    argv_ptr += strlen(argv[i]);
    assert(argv_ptr < 1024);
  }

  // Wrap the array in a shared_ptr so the DataBlock can be copied safely.
  shared_ptr<char> data_ptr(data, std::default_delete<char[]>());
  return DataBlock(0, argv_ptr, data_ptr);
}

Elf64_Ehdr get_elf_header(ifstream& file) {
  Elf64_Ehdr header;
  file.seekg(0, file.beg);
  file.read((char*)&header, sizeof(Elf64_Ehdr));

  return header;
}

Elf64_Shdr get_section_header(ifstream& file, Elf64_Ehdr& elf_header,
                              int section) {
  int num_sections = elf_header.e_shnum;

  assert(section >= 0);
  assert(section <= num_sections);

  Elf64_Shdr section_header;
  uint offset = elf_header.e_shoff + elf_header.e_shentsize*section;
  file.seekg(offset, file.beg);
  file.read((char*)&section_header, sizeof(Elf32_Shdr));

  return section_header;
}

DataBlock get_section(ifstream& file, Elf64_Shdr& header) {
  uint64_t size = header.sh_size;
  uint64_t position = header.sh_addr;
  uint64_t offset = header.sh_offset;

  char* data = new char[size];
  file.seekg(offset, file.beg);
  file.read(data, size);

  // TODO: use this field?
  bool read_only = !(header.sh_flags & SHF_WRITE);

  // Wrap the array in a shared_ptr so the DataBlock can be copied safely.
  shared_ptr<char> data_ptr(data, std::default_delete<char[]>());
  return DataBlock(position, size, data_ptr);
}

vector<DataBlock> elf(char* filename) {
  ifstream file(filename);

  Elf64_Ehdr elf_header = get_elf_header(file);

  if (elf_header.e_machine != EM_RISCV)
    throw std::runtime_error("Received non-RISC-V binary to execute");

  int num_sections = elf_header.e_shnum;
  vector<DataBlock> blocks;
  for (int i=0; i<num_sections; i++) {
    Elf64_Shdr section_header = get_section_header(file, elf_header, i);

    // We are only interested in sections to be loaded into memory.
    if ((section_header.sh_flags & SHF_ALLOC) &&   // Alloc = put in memory
        (section_header.sh_type != SHT_NOBITS)) {  // No bits = data not in ELF
      DataBlock data = get_section(file, section_header);
      blocks.push_back(data);
    }
  }

  file.close();

  return blocks;
}

// Load the contents of a RISC-V executable and its arguments into `memory`.
void BinaryParser::load_elf(int argc, char** argv, MainMemory& memory) {
  if (argc < 1)
    throw std::runtime_error("No binary file specified");

  // Program arguments.
  memory.write(arguments(argc, argv));

  // Program.
  vector<DataBlock> blocks = elf(argv[0]);
  for (int i=0; i<blocks.size(); i++)
    memory.write(blocks[i]);
}

MemoryAddress BinaryParser::entry_point(char* filename) {
  // Most of this work already happens in load_elf - optimisation opportunity.
  ifstream file(filename);
  Elf64_Ehdr elf_header = get_elf_header(file);
  file.close();
  return elf_header.e_entry;
}
