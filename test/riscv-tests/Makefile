# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

# Simulator to use. Options are muntjac_core and muntjac_pipeline.
MUNTJAC_SIM ?= muntjac_core

# Path to directory containing test binaries.
TEST_DIR    ?= isa

ifdef MUNTJAC_ROOT
  SIM = $(MUNTJAC_ROOT)/bin/$(MUNTJAC_SIM)
else
  SIM = $(MUNTJAC_SIM)
endif

TEST_GROUPS := rv64ui rv64um rv64ua rv64uc rv64si rv64mi rv64uf rv64ud

ELFS := $(foreach group,$(TEST_GROUPS),$(wildcard $(TEST_DIR)/$(group)-*))
XMLS := $(addsuffix .xml,$(ELFS))

.PHONY: all
all: results.xml

results.xml: $(XMLS)
	echo "<testsuite tests=\"$(words $(XMLS))\">" > $@
	cat $(XMLS) >> $@
	echo "</testsuite>" >> $@

%.xml: %.trace %.etrace %.time
	echo "<testcase classname=\"Test\" name=\"$(notdir $*)\" time=\"`cat $*.time`\">" > $@
	grep -q "Exiting with argument 1$$" $*.trace || echo "<failure type=\"failure\">Failure</failure>" >> $@
	echo "<system-out>" >> $@
	sed -e "s/&/\&amp;/g" -e "s/>/\&gt;/g" -e "s/</\&lt;/g" -e "s/\"/\&quot;/g" -e "s/'/\&apos;/g" $*.trace >> $@
	echo "</system-out>" >> $@
	echo "<system-err>" >> $@
	sed -e "s/&/\&amp;/g" -e "s/>/\&gt;/g" -e "s/</\&lt;/g" -e "s/\"/\&quot;/g" -e "s/'/\&apos;/g" $*.etrace >> $@
	echo "</system-err>" >> $@
	echo "</testcase>" >> $@

%.trace %.etrace %.time: %
	/usr/bin/time --quiet -o $*.time -f "%e" timeout 60s time $(SIM) $< > $*.trace 2> $*.etrace || true

.PHONY: clean
clean:
	rm -f results.xml
	rm -f $(XMLS)
	rm -f $(wildcard $(XMLS:.xml=.trace))
	rm -f $(wildcard $(XMLS:.xml=.etrace))
	rm -f $(wildcard $(XMLS:.xml=.time))
