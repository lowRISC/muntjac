// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include <cassert>
#include <cstring>
#include "main_memory.h"

extern bool is_system_call(MemoryAddress address, uint64_t write_data);
extern void system_call(MemoryAddress address, uint64_t write_data);

// Use a simple paging mechanism so we don't have to allocate an entire virtual
// address space.
// Default: 1MB pages
#define LOG2_PAGE_SIZE 20
#define PAGE_SIZE (1 << LOG2_PAGE_SIZE)

MemoryAddress get_tag(MemoryAddress address) {
  return address & ~(PAGE_SIZE - 1);
}

MemoryAddress get_offset(MemoryAddress address) {
  return address & (PAGE_SIZE - 1);
}

MainMemory::MainMemory() {
  // Nothing
}

MainMemory::~MainMemory() {
  for (auto it=pages.begin(); it != pages.end(); ++it)
    delete[] it->second;
}

DataBlock MainMemory::read(MemoryAddress address, size_t num_bytes) {

  char* data = new char[num_bytes];

  // Check whether all requested data is in one page.
  if (get_offset(address) + num_bytes <= PAGE_SIZE) {
    char* page = get_page(address);
    MemoryAddress offset = get_offset(address);
    memcpy(data, page + offset, num_bytes);
  }
  else {
    size_t bytes_copied = 0;
    while (bytes_copied < num_bytes) {
      char* page = get_page(address + bytes_copied);
      MemoryAddress offset = get_offset(address + bytes_copied);

      size_t bytes_to_copy = num_bytes - bytes_copied;
      if (bytes_to_copy > PAGE_SIZE)
        bytes_to_copy = PAGE_SIZE;

      memcpy(data + bytes_copied, page + offset, bytes_to_copy);

      bytes_copied += bytes_to_copy;
    }
  }

  // Wrap the array in a shared_ptr so the DataBlock can be copied safely.
  shared_ptr<char> data_ptr(data, std::default_delete<char[]>());
  return DataBlock(address, num_bytes, data_ptr);

}

void MainMemory::write(DataBlock data) {
  size_t bytes_copied = 0;
  while (bytes_copied < data.get_num_bytes()) {
    char* page = get_page(data.get_address() + bytes_copied);
    MemoryAddress offset = get_offset(data.get_address() + bytes_copied);

    size_t bytes_to_copy = data.get_num_bytes() - bytes_copied;
    if (offset + bytes_to_copy > PAGE_SIZE)
      bytes_to_copy = PAGE_SIZE - offset;

    memcpy(page + offset, data.get_data().get() + bytes_copied, bytes_to_copy);

    bytes_copied += bytes_to_copy;
  }
}

uint8_t MainMemory::read8(MemoryAddress address) {
  char* page = get_page(address);
  MemoryAddress offset = get_offset(address);
  return page[offset];
}

uint16_t MainMemory::read16(MemoryAddress address) {
  char* page = get_page(address);
  MemoryAddress offset = get_offset(address);
  uint16_t result;

  // Whole value is in one page.
  if (offset <= PAGE_SIZE - 2)
    result = *((uint16_t*)(page + offset));
  // Value spans two pages. This is rare, so not optimised.
  else {
    uint8_t* result_ptr = (uint8_t*)(&result);
    char* next_page = get_page(address + PAGE_SIZE);

    memcpy(result_ptr, page + offset, PAGE_SIZE - offset);
    memcpy(result_ptr + PAGE_SIZE - offset, next_page, offset + 2 - PAGE_SIZE);
  }

  return result;
}

uint32_t MainMemory::read32(MemoryAddress address) {
  char* page = get_page(address);
  MemoryAddress offset = get_offset(address);
  uint32_t result;

  // Whole value is in one page.
  if (offset <= PAGE_SIZE - 4)
    result = *((uint32_t*)(page + offset));
  // Value spans two pages. This is rare, so not optimised.
  else {
    uint8_t* result_ptr = (uint8_t*)(&result);
    char* next_page = get_page(address + PAGE_SIZE);

    memcpy(result_ptr, page + offset, PAGE_SIZE - offset);
    memcpy(result_ptr + PAGE_SIZE - offset, next_page, offset + 4 - PAGE_SIZE);
  }

  return result;
}

uint64_t MainMemory::read64(MemoryAddress address) {
  char* page = get_page(address);
  MemoryAddress offset = get_offset(address);
  uint64_t result;

  // Whole value is in one page.
  if (offset <= PAGE_SIZE - 8)
    result = *((uint64_t*)(page + offset));
  // Value spans two pages. This is rare, so not optimised.
  else {
    uint8_t* result_ptr = (uint8_t*)(&result);
    char* next_page = get_page(address + PAGE_SIZE);

    memcpy(result_ptr, page + offset, PAGE_SIZE - offset);
    memcpy(result_ptr + PAGE_SIZE - offset, next_page, offset + 8 - PAGE_SIZE);
  }

  return result;
}

void MainMemory::write8(MemoryAddress address, uint8_t data) {
  if (is_system_call(address, data)) {
    system_call(address, data);
    return;
  }

  char* page = get_page(address);
  MemoryAddress offset = get_offset(address);
  page[offset] = data;
}

void MainMemory::write16(MemoryAddress address, uint16_t data) {
  if (is_system_call(address, data)) {
    system_call(address, data);
    return;
  }

  char* page = get_page(address);
  MemoryAddress offset = get_offset(address);
  uint16_t result = data;

  // Whole value is in one page.
  if (offset <= PAGE_SIZE - 2)
    *((uint16_t*)(page + offset)) = result;
  // Value spans two pages. This is rare, so not optimised.
  else {
    uint8_t* result_ptr = (uint8_t*)(&result);
    char* next_page = get_page(address + PAGE_SIZE);

    memcpy(page + offset, result_ptr, PAGE_SIZE - offset);
    memcpy(next_page, result_ptr + PAGE_SIZE - offset, offset + 2 - PAGE_SIZE);
  }
}

void MainMemory::write32(MemoryAddress address, uint32_t data) {
  if (is_system_call(address, data)) {
    system_call(address, data);
    return;
  }

  char* page = get_page(address);
  MemoryAddress offset = get_offset(address);
  uint32_t result = data;

  // Whole value is in one page.
  if (offset <= PAGE_SIZE - 4)
    *((uint32_t*)(page + offset)) = result;
  // Value spans two pages. This is rare, so not optimised.
  else {
    uint8_t* result_ptr = (uint8_t*)(&result);
    char* next_page = get_page(address + PAGE_SIZE);

    memcpy(page + offset, result_ptr, PAGE_SIZE - offset);
    memcpy(next_page, result_ptr + PAGE_SIZE - offset, offset + 4 - PAGE_SIZE);
  }
}

void MainMemory::write64(MemoryAddress address, uint64_t data) {
  if (is_system_call(address, data)) {
    system_call(address, data);
    return;
  }

  char* page = get_page(address);
  MemoryAddress offset = get_offset(address);
  uint64_t result = data;

  // Whole value is in one page.
  if (offset <= PAGE_SIZE - 8)
    *((uint64_t*)(page + offset)) = result;
  // Value spans two pages. This is rare, so not optimised.
  else {
    uint8_t* result_ptr = (uint8_t*)(&result);
    char* next_page = get_page(address + PAGE_SIZE);

    memcpy(page + offset, result_ptr, PAGE_SIZE - offset);
    memcpy(next_page, result_ptr + PAGE_SIZE - offset, offset + 8 - PAGE_SIZE);
  }
}

char* MainMemory::get_page(MemoryAddress address) {
  MemoryAddress tag = get_tag(address);

  if (pages.find(tag) == pages.end())
    return allocate_new_page(tag);
  else
    return pages[tag];
}

char* MainMemory::allocate_new_page(MemoryAddress address) {
  MemoryAddress tag = get_tag(address);
  assert(pages.find(tag) == pages.end());

  char* page = new char[PAGE_SIZE];
  pages[tag] = page;

  return page;
}
