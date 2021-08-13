TARGET_DIR?=bin
FUSESOC?=~/.local/bin/fusesoc

# Pass extra flags to FuseSoC. e.g. EXTRA_FLAGS=assertions_on
EXTRA_FLAGS ?= 
FUSESOC_FLAGS = $(addprefix --flag ,$(EXTRA_FLAGS))

.PHONY: sim sim-pipeline sim-core
sim: sim-core
sim-pipeline: $(TARGET_DIR)/muntjac_pipeline
sim-core: $(TARGET_DIR)/muntjac_core

.PHONY: clean
clean:
	rm -rf build
	rm -rf $(TARGET_DIR)

# TODO: Lint the entire core when the caches have been tidied up.
.PHONY: lint
lint:
	$(FUSESOC) --cores-root=. run --target=lint --tool=verilator $(FUSESOC_FLAGS) lowrisc:muntjac:pipeline_tb:0.1

# Currently valid for muntjac_pipeline and muntjac_core only.
$(TARGET_DIR)/muntjac_%: FORCE | $(TARGET_DIR)
	rm -rf build
	$(FUSESOC) --cores-root=. run --target=sim --tool=verilator --build $(FUSESOC_FLAGS) lowrisc:muntjac:$*_tb:0.1
	cp build/lowrisc_muntjac_$*_tb_0.1/sim-verilator/muntjac_$* $@

$(TARGET_DIR):
	mkdir -p $@

.PHONY: FORCE
FORCE:
