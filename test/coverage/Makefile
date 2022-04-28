# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

MUNTJAC_ROOT  ?= ../..

SIM           ?= $(MUNTJAC_ROOT)/bin/muntjac_core
BUILD_DIR     ?= $(MUNTJAC_ROOT)/build/lowrisc_muntjac_core_tb_0.1/sim-verilator

COVERAGE       = $(addsuffix .cov, $(TESTS))
COV_TOTAL      = total.cov

# Source files we are interested in the coverage of.
# Ignore axi (unused) and tilelink (tested separately).
PIPELINE_SRC   = $(notdir $(wildcard $(MUNTJAC_ROOT)/ip/pipeline/rtl/*.sv))
CORE_SRC       = $(notdir $(wildcard $(MUNTJAC_ROOT)/ip/core/rtl/*.sv))
FPU_SRC        = $(notdir $(wildcard $(MUNTJAC_ROOT)/ip/fpu/rtl/*.sv))
ALL_SRC        = $(PIPELINE_SRC) $(CORE_SRC) $(FPU_SRC)

ANNOTATION_DIR = coverage
ANNOTATED_SRC  = $(addprefix $(ANNOTATION_DIR)/, $(ALL_SRC))

.PHONY: pipeline_coverage core_coverage fpu_coverage coverage all
all: coverage
coverage: pipeline_coverage core_coverage fpu_coverage

# Simulate one test to generate one coverage report.
# The name of the test is the name of the coverage report without ".cov".
# Ignore errors.
$(COVERAGE):
	-$(SIM) --coverage $@ $(basename $@)

# Merge coverage reports from all simulations.
$(COV_TOTAL): $(COVERAGE)
ifndef TESTS
	$(error Please set the TESTS variable to a list of binaries to execute)
endif
	verilator_coverage -write $@ $^

# Annotate each line of source code with how many times it was reached.
# verilator_coverage claims to have a command line option to tell it where the
# Verilog source is, but I haven't found it, so this needs to run in the
# directory where the simulator was originally built.
# (Using PHONY annotate because we don't know that all files will be annotated.)
.PHONY: annotate
annotate: $(COV_TOTAL)
	cd $(BUILD_DIR) && \
	verilator_coverage $(CURDIR)/$< --annotate $(CURDIR)/$(ANNOTATION_DIR) \
	--annotate-all --annotate-min 1

pipeline_coverage: annotate
	@echo -n "ip/pipeline line coverage: "
	@python3 $(MUNTJAC_ROOT)/test/coverage/coverage_filter.py --annotation-dir \
	$(ANNOTATION_DIR) --files $(PIPELINE_SRC)

core_coverage: annotate
	@echo -n "ip/core line coverage:     "
	@python3 $(MUNTJAC_ROOT)/test/coverage/coverage_filter.py --annotation-dir \
	$(ANNOTATION_DIR) --files $(CORE_SRC)

fpu_coverage: annotate
	@echo -n "ip/fpu line coverage:      "
	@python3 $(MUNTJAC_ROOT)/test/coverage/coverage_filter.py --annotation-dir \
	$(ANNOTATION_DIR) --files $(FPU_SRC)

.PHONY: clean
clean:
	rm -f $(COVERAGE) $(COV_TOTAL)
	rm -rf $(ANNOTATION_DIR)
