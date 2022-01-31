# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

TEST_DIR ?= riscv-dv/build/asm_test
SPIKE_LOG_DIR ?= riscv-dv/build/spike_sim
MUNTJAC_SIM_DIR ?= muntjac/bin
MUNTJAC_SCRIPT_DIR ?= muntjac/test/riscv-dv

ELFS := $(wildcard $(TEST_DIR)/*.o)
XMLS := $(ELFS:.o=.pipeline.xml) $(ELFS:.o=.core.xml)

.PHONY: all
all: results.xml

results.xml: $(XMLS)
	echo "<testsuite tests=\"$(words $(XMLS))\">" > $@
	cat $(XMLS) >> $@
	echo "</testsuite>" >> $@

%.xml: %.trace %.etrace %.time
	echo "<testcase classname=\"Test\" name=\"$*\" time=\"`cat $*.time`\">" > $@
	[[ -s $*.etrace ]] && echo "<failure type=\"failure\">Failure</failure>" >> $@ || true
	echo "<system-out>" >> $@
	sed -e "s/&/\&amp;/g" -e "s/>/\&gt;/g" -e "s/</\&lt;/g" -e "s/\"/\&quot;/g" -e "s/'/\&apos;/g" $*.trace >> $@
	echo "</system-out>" >> $@
	echo "<system-err>" >> $@
	sed -e "s/&/\&amp;/g" -e "s/>/\&gt;/g" -e "s/</\&lt;/g" -e "s/\"/\&quot;/g" -e "s/'/\&apos;/g" $*.etrace >> $@
	echo "</system-err>" >> $@
	echo "</testcase>" >> $@

%.pipeline.log %.pipeline.trace %.pipeline.time: %.o
	/usr/bin/time --quiet -o $*.pipeline.time -f "%e" timeout 60s time ./$(MUNTJAC_SIM_DIR)/muntjac_pipeline --csv=$*.pipeline.log $< > $*.pipeline.trace 2>&1 || true
%.core.log %.core.trace %.core.time: %.o
	/usr/bin/time --quiet -o $*.core.time -f "%e" timeout 60s time ./$(MUNTJAC_SIM_DIR)/muntjac_core --csv=$*.core.log $< > $*.core.trace 2>&1 || true

%.csv: %.log
	python3 $(MUNTJAC_SCRIPT_DIR)/muntjac_log_to_trace_csv.py --log=$< --csv=$@ --fast

# Spike's log files replace the final underscore of the binary name with a period.
%.pipeline.etrace: %.pipeline.csv
	python3 $(MUNTJAC_SCRIPT_DIR)/muntjac_trace_compare.py --ref=$(SPIKE_LOG_DIR)/`basename $* | sed -r 's/(.*)_/\1./'`.csv --muntjac=$< > $@ 2>&1 || true
%.core.etrace: %.core.csv
	python3 $(MUNTJAC_SCRIPT_DIR)/muntjac_trace_compare.py --ref=$(SPIKE_LOG_DIR)/`basename $* | sed -r 's/(.*)_/\1./'`.csv --muntjac=$< > $@ 2>&1 || true

.PHONY: clean
clean:
	rm -f $(wildcard results.xml)
	rm -f $(wildcard $(XMLS))
	rm -f $(wildcard $(XMLS:.xml=.trace))
	rm -f $(wildcard $(XMLS:.xml=.etrace))
	rm -f $(wildcard $(XMLS:.xml=.time))
	rm -f $(wildcard $(XMLS:.xml=.csv))
	rm -f $(wildcard $(XMLS:.xml=.log))
