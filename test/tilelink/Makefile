# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Generate random TileLink traffic for this many cycles.
CYCLES ?= 1000000

# Random seed.
SEED   ?= 0

MUNTJAC_ROOT = ../..

ANNOTATION_DIR = coverage
COVERAGE_FILES = tl_cover.sv  # All files defining functional cover points
FCOV_FILES = $(addprefix $(ANNOTATION_DIR)/, $(COVERAGE_FILES))

.PHONY: all sim summary detail
all: summary

# Generate a simulator + traffic generator for a TileLink network.
sim: muntjac_tl

# Generate a coverage summary, e.g. "57/79 coverpoints hit".
# TODO: compute line and functional coverage separately
summary: line_coverage functional_coverage

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
$(FCOV_FILES): tl_coverage.dat
	cd $(MUNTJAC_ROOT)/build/lowrisc_muntjac_tl_tb_0.1/sim-verilator && \
	verilator_coverage $(CURDIR)/$< --annotate $(CURDIR)/$(ANNOTATION_DIR) \
	--annotate-all --annotate-min 1

.PHONY: line_coverage functional_coverage

functional_coverage: $(FCOV_FILES)
	$(eval TOTAL := $(shell grep -Eh ^.[0-9]{6} $^ | wc -l))
	$(eval REACHED := $(shell grep -Eh ^.[0-9]{6} $^ | grep -v ^.000000 | wc -l))
	@echo "Functional coverage ($(REACHED)/$(TOTAL)) $$(( $(REACHED) * 100 / $(TOTAL) ))%"

# We don't know in advance which line coverage files will be produced.
# Generating functional coverage files triggers their creation though, and then
# we can just filter out the coverage files afterwards.
line_coverage: $(FCOV_FILES)
	$(eval LCOV_FILES := $(shell ls $(ANNOTATION_DIR) $(addprefix -I ,$(COVERAGE_FILES))))
	$(eval FILES := $(addprefix $(ANNOTATION_DIR)/, $(LCOV_FILES)))
	$(eval TOTAL := $(shell grep -Eh ^.[0-9]{6} $(FILES) | wc -l))
	$(eval REACHED := $(shell grep -Eh ^.[0-9]{6} $(FILES) | grep -v ^.000000 | wc -l))
	@echo "Line coverage ($(REACHED)/$(TOTAL)) $$(( $(REACHED) * 100 / $(TOTAL) ))%"

.PHONY: clean
clean:
	rm -rf $(ANNOTATION_DIR)
	rm -f tl_coverage.dat
	rm -f muntjac_tl
