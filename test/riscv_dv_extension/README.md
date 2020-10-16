[riscv-dv](https://github.com/google/riscv-dv) is a tool for generating and testing random sequences of instructions. In order to maximise test coverage, it needs to know exactly which features are and are not supported by a processor. Muntjac does not fit any of the predefined processor capabilities, so this directory contains the required configuration files.

These files are based on the RV64GC configuration, with the following changes:
 * No floating point support
 * No N-extension (user-level interrupts)
 * No vectored interrupts
 * No unaligned loads/stores

TODO: usage instructions
