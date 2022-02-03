# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Generate random TileLink traffic for this many cycles.
CYCLES ?= 1000000

# Random seed.
SEED   ?= 0

MUNTJAC_ROOT = ../..

ANNOTATION_DIR = annotation
COVERAGE_FILES = tl_assert.sv  # All files defining cover points
ANNOTATION_FILES = $(addprefix $(ANNOTATION_DIR)/, $(COVERAGE_FILES))

.PHONY: all sim summary detail
all: summary

# Generate a simulator + traffic generator for a TileLink network.
sim: muntjac_tl

# Generate a coverage summary, e.g. "57/79 coverpoints hit".
summary: $(ANNOTATION_FILES)

# Generate detailed coverage information: which coverpoints were hit, and how
# many times each?
detail: tl_coverage.txt

# Would prefer to set the simulator as a dependency of this rule, but I couldn't
# get that to work nicely.
muntjac_tl:
	$(MAKE) -C $(MUNTJAC_ROOT) bin/muntjac_tl
	ln -s $(MUNTJAC_ROOT)/bin/muntjac_tl .

tl_coverage.dat: muntjac_tl
	./muntjac_tl --random-seed $(SEED) --run $(CYCLES) --coverage $@

# This command also prints an overall summary of the coverage, e.g. 78%.
# verilator_coverage claims to have a command line option to tell it where the
# Verilog source is, but I haven't found it, so this needs to run in the
# directory where the simulator was originally built.
$(ANNOTATION_FILES): tl_coverage.dat
	cd $(MUNTJAC_ROOT)/build/lowrisc_muntjac_tl_tb_0.1/sim-verilator && \
	verilator_coverage $(CURDIR)/$< --annotate $(CURDIR)/$(ANNOTATION_DIR)

tl_coverage.txt: $(ANNOTATION_FILES)
	grep -E ^.[0-9]{6} $(ANNOTATION_DIR)/tl_assert.sv > $@

.PHONY: clean
clean:
	rm -rf $(ANNOTATION_DIR)
	rm -f tl_coverage.dat
	rm -f tl_coverage.txt
	rm -f muntjac_tl
