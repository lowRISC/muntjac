# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Parent Makefiles may define any of the following to customise compilation:
#  * RISCV_TOOLS: directory containing RISC-V compiler toolchain
#  * OUTFILE: the name of the binary to produce
#  * PROGRAM_CFLAGS: compiler flags
#  * PROGRAM_INCS: list of include directories, including appropriate -I flags
#  * PROGRAM_LIBS: list of libraries, including appropriate -l flags
#  * PROGRAM_SRCS: list of source files (both .c and .S)

RISCV_ABI 	?= lp64
RISCV_ISA 	?= rv64imac
RISCV_TUPLE ?= riscv64-unknown-elf

ifdef RISCV_TOOLS
  RISCV_PREFIX = $(RISCV_TOOLS)/bin/$(RISCV_TUPLE)
else
  RISCV_PREFIX = $(RISCV_TUPLE)
endif

CC      = $(RISCV_PREFIX)-gcc
OBJCOPY = $(RISCV_PREFIX)-objcopy
OBJDUMP = $(RISCV_PREFIX)-objdump

COMMON_DIR = $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))

COMMON_SRCS = $(wildcard $(COMMON_DIR)/*.c) $(COMMON_DIR)/crt0.S
COMMON_INCS = -I$(COMMON_DIR)
LINKER_SCRIPT = $(COMMON_DIR)/link.ld

SRCS = $(COMMON_SRCS) $(PROGRAM_SRCS)
INCS = $(COMMON_INCS) $(PROGRAM_INCS)

CFLAGS = -march=$(RISCV_ISA) -mabi=$(RISCV_ABI) -static -mcmodel=medany -g \
	-fvisibility=hidden -nostdlib -nostartfiles -ffreestanding $(PROGRAM_CFLAGS)


all: $(OUTFILE)

$(OUTFILE): $(SRCS) $(LINKER_SCRIPT)
	$(CC) $(CFLAGS) $(INCS) $(SRCS) -T $(LINKER_SCRIPT) -o $@ $(PROGRAM_LIBS)

clean:
	$(RM) -f $(OUTFILE)
