# CoreMark

[CoreMark](https://github.com/eembc/coremark) is a benchmark used to measure the performance of general-purpose processors. This directory contains files which target the CoreMark build process at the Muntjac processor and provide necessary functions for timing, memory allocation, etc. It is heavily based on [Ibex's implementation](https://github.com/lowRISC/ibex/tree/master/examples/sw/benchmarks).

Normally, results are quoted using CoreMarks/MHz to isolate the effects of the processor design from the physical implementation. Muntjac has not yet been optimised for clock frequency, so results are subject to change significantly.

To run CoreMark on Muntjac, from CoreMark's directory (not this extension), run:

```
make \
  PORT_DIR=$MUNTJAC_ROOT/test/coremark \
  RISCV_TOOLS=/path/to/compiler/toolchain/directory \
  MUNTJAC_SIM=$MUNTJAC_ROOT/bin/muntjac_core \
  ITERATIONS=20
```

Results will be recorded in `run1.log`.
