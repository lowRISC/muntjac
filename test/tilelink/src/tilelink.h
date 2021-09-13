// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include <cstdint>

typedef struct {
    int      opcode;
    int      param;
    int      size;
    int      source;
    uint64_t address;
    int      mask;
    bool     corrupt;
    uint64_t data;
} tl_a;

typedef struct {
    int      opcode;
    int      param;
    int      size;
    int      source;
    uint64_t address;
    int      mask;
    bool     corrupt;
    uint64_t data;
} tl_b;

typedef struct {
    int      opcode;
    int      param;
    int      size;
    int      source;
    uint64_t address;
    bool     corrupt;
    uint64_t data;
} tl_c;

typedef struct {
    int      opcode;
    int      param;
    int      size;
    int      source;
    int      sink;
    bool     denied;
    bool     corrupt;
    uint64_t data;
} tl_d;

typedef struct {
    int      sink;
} tl_e;

typedef struct {
    bool     enable;
    bool     write_enable;
    uint64_t address;
    int      write_mask;
    uint64_t write_data;
    uint64_t read_data;
} bram_ifc;
