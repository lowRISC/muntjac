# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Component to test. Default: simple network containing a range of components.
DUT          ?= default

# Generate random TileLink traffic for this many cycles.
CYCLES       ?= 1000000

# Random seed.
SEED         ?= 0

# For testing and coverage, we need to build a separate simulator for each
# configuration of the component being tested.
# Configurations are described in the configs directory.
CONFIG_GEN    = configs/tl_config_generator.py
CONFIG_DIR    = configs/$(DUT)
MASTER_CONFIG = $(CONFIG_DIR)/configs.yaml

# Special case for the default DUT which doesn't have configuration options.
ifeq ($(DUT), default)
	CONFIGS   = $(DUT)
	SIMS      = $(DUT).sim
else
	CONFIGS	  = $(shell python3 $(CONFIG_GEN) --input $(MASTER_CONFIG) --list-names)
	SIMS      = $(addprefix $(DUT)-, $(addsuffix .sim, $(CONFIGS)))
endif

CPP_CONFIGS   = $(addprefix $(CONFIG_DIR)/,$(addsuffix .yaml, $(CONFIGS)))
VLOG_CONFIGS  = $(addprefix $(CONFIG_DIR)/,$(addsuffix .svh, $(CONFIGS)))

# Verilog expects the parameters to be in the same location every time.
VLOG_PARAMS   = $(CONFIG_DIR)/parameters.svh

# One test per simulator configuration.
TESTS         = $(patsubst %.sim,%.test,$(SIMS))

# One coverage report per simulator configuration.
COVERAGE_DATA = $(patsubst %.sim,%.cov,$(SIMS))
TOTAL_COV     = total.cov

# Function to recover a configuration name from a simulator name.
define config_name
$(word 2,$(subst -, ,$1))
endef

# TODO: add a proper testing command which runs all simulations without coverage.

MUNTJAC_ROOT = ../..
BUILD_DIR    = build/lowrisc_tl_test_$(DUT)_0.1/sim-verilator
FUSESOC     ?= ~/.local/bin/fusesoc

ANNOTATION_DIR = coverage
COVERAGE_SRC = tl_cover.sv  # All files defining functional cover points
FCOV_FILES = $(addprefix $(ANNOTATION_DIR)/, $(COVERAGE_SRC))

# FuseSoC doesn't allow multiple parallel builds. Fortunately, each build is
# parallel internally, so this isn't too slow.
.NOTPARALLEL:

.PHONY: all sim test coverage
all: coverage

# Generate a simulator + traffic generator for a TileLink network.
sim: $(SIMS)

# Run simulations to see if any assertions fail.
test: $(TESTS)

# Generate a coverage summary, e.g. "57/79 coverpoints hit".
# The default DUT doesn't have a meaningful line coverage result, so skip it.
ifeq ($(DUT), default)
coverage: functional_coverage
else
coverage: line_coverage functional_coverage
endif

# Generate C++ and Verilog configuration files.
%.yaml %.svh:
	python3 $(CONFIG_GEN) --input $(dir $*)/configs.yaml --config $(notdir $*) --verilog $*.svh --cpp $*.yaml

# Merge coverage reports from all simulations.
$(TOTAL_COV): $(COVERAGE_DATA)
	verilator_coverage -write $@ $^

# Annotate Verilog source code with the number of times each cover point was
# reached during testing.
# This command also prints an overall summary of the coverage, e.g. 78%.
# verilator_coverage claims to have a command line option to tell it where the
# Verilog source is, but I haven't found it, so this needs to run in the
# directory where the simulator was originally built.
$(FCOV_FILES): $(TOTAL_COV)
	cd $(BUILD_DIR) && \
	verilator_coverage $(CURDIR)/$< --annotate $(CURDIR)/$(ANNOTATION_DIR) \
	--annotate-all --annotate-min 1

.PHONY: functional_coverage line_coverage

# Summarise functional coverage results.
functional_coverage: $(FCOV_FILES)
	$(eval TOTAL := $(shell grep -Eh ^.[0-9]{6} $^ | wc -l))
	$(eval REACHED := $(shell grep -Eh ^.[0-9]{6} $^ | grep -v ^.000000 | wc -l))
	@echo "Functional coverage ($(REACHED)/$(TOTAL)) $$(( $(REACHED) * 100 / $(TOTAL) ))%"

# Summarise line coverage results.
# Ignore coverage results for all files except the DUT. Depending on how the DUT
# uses its subcomponents, it may not be possible to achieve a high coverage.
# Assume that subcomponents will be tested in isolation elsewhere.
# TODO: this can fail if there are no cover points in the DUT (i.e. it delegates
#       to subcomponents).
line_coverage: $(FCOV_FILES)
	$(eval FILES := $(ANNOTATION_DIR)/$(DUT).sv)
	$(eval TOTAL := $(shell grep -Eh ^.[0-9]{6} $(FILES) | wc -l))
	$(eval REACHED := $(shell grep -Eh ^.[0-9]{6} $(FILES) | grep -v ^.000000 | wc -l))
	@echo "Line coverage, DUT only ($(REACHED)/$(TOTAL)) $$(( $(REACHED) * 100 / $(TOTAL) ))%"

.PHONY: clean
clean:
	rm -rf build
	rm -rf $(ANNOTATION_DIR)
	rm -f $(COVERAGE_DATA) $(TOTAL_COV)
	rm -f $(CPP_CONFIGS) $(VLOG_CONFIGS) $(VLOG_PARAMS)
	rm -f $(SIMS)

# The remaining rules use functions to determine dependencies, which need to be
# expanded twice.
.SECONDEXPANSION:

# Special case for default simulator - no configuration required.
default.sim:
	$(FUSESOC) --cores-root=$(MUNTJAC_ROOT) run --target=sim --tool=verilator --build lowrisc:tl_test:$(DUT):0.1
	cp build/lowrisc_tl_test_$(DUT)_0.1/sim-verilator/$(DUT) $@

# Special case for default simulator - no configuration generation required.
default.test: default.sim
	./$< --random-seed $(SEED) --run $(CYCLES) --config $(CONFIG_DIR)/config.yaml

# Special case for default simulator - no configuration generation required.
default.cov: default.sim
	./$< --random-seed $(SEED) --run $(CYCLES) --coverage $@ --config $(CONFIG_DIR)/config.yaml

# Build a simulator for a particular configuration of a particular DUT.
%.sim: $$(CONFIG_DIR)/$$(call config_name,$$*).svh
	rm -rf build
	cp $< $(VLOG_PARAMS)
	$(FUSESOC) --cores-root=$(MUNTJAC_ROOT) run --target=sim --tool=verilator --build lowrisc:tl_test:$(DUT):0.1
	cp build/lowrisc_tl_test_$(DUT)_0.1/sim-verilator/$(DUT) $@

# Run a simulation without collecting coverage data.
%.test: $$*.sim $$(CONFIG_DIR)/$$(call config_name,$$*).yaml
	./$< --random-seed $(SEED) --run $(CYCLES) --config $(CONFIG_DIR)/$(call config_name,$*).yaml

# Run a simulation to get a coverage report.
%.cov: $$*.sim $$(CONFIG_DIR)/$$(call config_name,$$*).yaml
	./$< --random-seed $(SEED) --run $(CYCLES) --coverage $@ --config $(CONFIG_DIR)/$(call config_name,$*).yaml
