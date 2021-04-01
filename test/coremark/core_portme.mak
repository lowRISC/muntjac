# Copyright lowRISC contributors.
# Copyright 2018 Embedded Microprocessor Benchmark Consortium (EEMBC)
# Original Author: Shay Gal-on
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

MUNTJAC_ROOT        ?= $(realpath $(PORT_DIR)/../..)

RISCV_ABI 					?= lp64
RISCV_ISA 					?= rv64imac
RISCV_TUPLE 				?= riscv64-unknown-elf
RISCV_TOOLS         ?= # Directory where the compiler, linker, etc. can be found
MUNTJAC_SIM         ?= $(MUNTJAC_ROOT)/bin/muntjac_core

ifdef RISCV_TOOLS
  RISCV_PREFIX = $(RISCV_TOOLS)/bin/$(RISCV_TUPLE)
else
  RISCV_PREFIX = $(RISCV_TUPLE)
endif

# Extra Muntjac stuff to help get freestanding programs running.
BAREMETAL_DIR        = $(MUNTJAC_ROOT)/test/baremetal
BAREMETAL_SRC				 = $(wildcard $(BAREMETAL_DIR)/*.c)
CRT0								 = $(BAREMETAL_DIR)/crt0.S
LINKER_SCRIPT				 = $(BAREMETAL_DIR)/link.ld

OUTFILES = $(OPATH)coremark.map

NAME                 = coremark
PORT_CLEAN          := $(OUTFILES)

# Flag : OUTFLAG
#	Use this flag to define how to to get an executable (e.g -o)
OUTFLAG = -o
# Flag : CC
#	Use this flag to define compiler to use
CC = $(RISCV_PREFIX)-gcc
# Flag : LD
#	Use this flag to define compiler to use
LD = $(RISCV_PREFIX)-ld
# Flag : AS
#	Use this flag to define compiler to use
AS = $(RISCV_PREFIX)-as
# Flag : CFLAGS
#	Use this flag to define compiler options. Note, you can add compiler options from the command line using XCFLAGS="other flags"
PORT_CFLAGS = -g -march=$(RISCV_ISA) -mabi=$(RISCV_ABI) -static -mcmodel=medany -mtune=sifive-3-series \
  -O3 -falign-functions=16 -funroll-all-loops \
	-finline-functions -falign-jumps=4 \
  -nostdlib -nostartfiles -ffreestanding -mstrict-align \
	-DTOTAL_DATA_SIZE=2000 -DMAIN_HAS_NOARGC=1 \
	-DPERFORMANCE_RUN=1

CFLAGS += $(PORT_CFLAGS) $(XCFLAGS) -I$(PORT_DIR) -I$(BAREMETAL_DIR) -I.

# Flag : LFLAGS_END
#	Define any libraries needed for linking or other flags that should come at the end of the link line (e.g. linker scripts).
#	Note : On certain platforms, the default clock_gettime implementation is supported but requires linking of librt.
LFLAGS_END = -T $(LINKER_SCRIPT) -lm -lgcc

FLAGS_STR = "$(PORT_CFLAGS) $(XCFLAGS) $(XLFLAGS) $(LFLAGS_END)"

#SEPARATE_COMPILE=1
# Flag : SEPARATE_COMPILE
# You must also define below how to create an object file, and how to link.
OBJOUT 	= -o
LFLAGS 	=
ASFLAGS =
OFLAG 	= -o
COUT   	= -c

# Flag : PORT_SRCS
# 	Port specific source files can be added here
#	You may also need cvt.c if the fcvt functions are not provided as intrinsics by your compiler!
PORT_SRCS = $(PORT_DIR)/core_portme.c $(PORT_DIR)/ee_printf.c ./barebones/cvt.c $(BAREMETAL_SRC) $(CRT0)
vpath %.c $(PORT_DIR)
vpath %.s $(PORT_DIR)

# Flag : LOAD
#	For a simple port, we assume self hosted compile and run, no load needed.
# This variable needs to be defined, or the system defaults to running CoreMark
# on the host machine.
LOAD = echo "LOAD step not needed by Muntjac"

# Flag : RUN
#	For a simple port, we assume self hosted compile and run, simple invocation of the executable
RUN = $(MUNTJAC_SIM) --timeout=1000000000

OEXT = .o
EXE = .elf

$(OPATH)$(PORT_DIR)/%$(OEXT) : %.c
	$(CC) $(CFLAGS) $(XCFLAGS) $(COUT) $< $(OBJOUT) $@

$(OPATH)%$(OEXT) : %.c
	$(CC) $(CFLAGS) $(XCFLAGS) $(COUT) $< $(OBJOUT) $@

$(OPATH)$(PORT_DIR)/%$(OEXT) : %.s
	$(AS) $(ASFLAGS) $< $(OBJOUT) $@

# Target : port_pre% and port_post%
# For the purpose of this simple port, no pre or post steps needed.

.PHONY : port_clean port_prebuild port_postbuild port_prerun port_postrun port_preload port_postload

# FLAG : OPATH
# Path to the output folder. Default - current folder.
MKDIR = mkdir -p
