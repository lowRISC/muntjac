# Muntjac riscv-dv extension
[riscv-dv](https://github.com/google/riscv-dv) is a tool for generating and testing random sequences of instructions. In order to maximise test coverage, it needs to know exactly which features are and are not supported by a processor. Muntjac does not fit any of the predefined processor capabilities, so this directory contains the required configuration files.

These files are based on the RV64GC configuration, with the following changes:
 * No floating point support
 * No N-extension (user-level interrupts)
 * No vectored interrupts
 * No unaligned loads/stores

## Setup
This has been tested on Ubuntu >= 16.04 with VCS and Spike.

Install riscv-dv and your choice of RISC-V instruction set simulator. If using Spike, use the `--enable-commitlog` flag when running `configure`, and set `SPIKE_PATH` to the build directory.

You will also need access to a SystemVerilog simulator with UVM support, such as VCS. Ensure this simulator is on your `PATH`.

```
export RISCV_TOOLS=path/to/your/toolchain
export RISCV_GCC=$RISCV_TOOLS/bin/riscv64-unknown-elf-gcc
export RISCV_OBJCOPY=$RISCV_TOOLS/bin/riscv64-unknown-elf-objcopy
```

```
pip3 install riscv-model
```

## Usage
Execute riscv-dv with the following command to use this extension. You may need to specify your own instruction set simulator (default: Spike) and SystemVerilog simulator (default: VCS).

```
python3 run.py -cs=$MUNTJAC_ROOT/test/riscv-dv/ --mabi=lp64 --isa=rv64imac -o=build
```

RISC-V programs will be generated in `build/asm_test`.

TODO: cov.py

To generate a JUnit-style XML of test results (e.g. for continuous integration), use the provided Makefile:

```
export TEST_DIR=riscv-dv/build/asm_test
export SPIKE_LOG_DIR=riscv-dv/build/spike_sim
export MUNTJAC_SIM_DIR=$MUNTJAC_ROOT/bin
export MUNTJAC_SCRIPT_DIR=$MUNTJAC_ROOT/test/riscv-dv

make -f $MUNTJAC_SCRIPT_DIR/Makefile
```

Alternatively, the individual steps are as follows.

Generate a Muntjac trace using:

```
muntjac_pipeline --csv=<logfile> <program>
```

Convert this CSV output to the required format using:

```
python3 $MUNTJAC_ROOT/test/riscv-dv/muntjac_log_to_trace_csv.py --log=<logfile> --csv=<csvfile>
```

Note that this conversion is *best effort*. Some of the fields are only there to improve human readability, and do not contribute to equivalence checking. These fields are not guaranteed be populated correctly.

To compare the Muntjac trace with the reference trace, use:

```
python3 $MUNTJAC_ROOT/test/riscv-dv/muntjac_trace_compare.py --ref=<file> --muntjac=<file>
```

This will produce no output if the traces are equivalent, and highlight the point of divergence otherwise.
