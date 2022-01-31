# Muntjac testing
This directory contains a set of build/configuration instructions for various test suites that are compatible with Muntjac.

Most tests will require a compatible compiler toolchain. We use one configured for Muntjac from [lowrisc-toolchains](https://github.com/lowRISC/lowrisc-toolchains). Set the `RISCV_TOOLS` environment variable to the directory you unpack the toolchain into.

If not using an operating system on Muntjac (i.e. "baremetal", the default for software simulation), the toolchain will need to be tweaked to interface with the hardware directly. See [here](https://github.com/db434/newlib-muntjac-baremetal) for instructions.

See also:
 * A [Dhrystone port](https://github.com/db434/benchmark-dhrystone) for performance testing
