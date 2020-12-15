# Muntjac

Muntjac is a minimal 64-bit RISC-V multicore processor that's easy to understand, verify, and extend. The focus is on having a clean, well-tested design which others can build upon and further customise. Performance is secondary to correctness, but the aim is to work towards a design point (considering power, performance and area) that maximises the value of Muntjac as a baseline design for educational, academic, or real-world use.

Details about the microarchitecture are available [here](microarchitecture.md).

# Features

| Feature | Description |
| --- | --- |
| [Instruction set](glossary.md#risc-v-instruction-sets) | RV64IMAC |
| [Privilege modes](glossary.md#privilege-modes) | M/S/U |
| [Virtual addressing modes](glossary.md#virtual-addressing-modes) | Sv39 |
| [Interrupt modes](glossary.md#interrupt-modes) | Direct |
| [Physical memory protection](glossary.md#physical-memory-protection) | Not supported |
| [Debug mode](glossary.md#debug-mode) | Not supported |
| [Unaligned loads/stores](glossary.md#unaligned-memory-access) | Not supported |

# Standards

The Muntjac processor meets the following standards:

| Standard | Version |
| --- | --- |
| **RV64I**: Base Integer Instruction Set, 64-bit | [2.1](https://github.com/riscv/riscv-isa-manual/releases/download/Ratified-IMAFDQC/riscv-spec-20191213.pdf) |
| **M**: Standard Extension for Integer Multiplication and Division | [2.0](https://github.com/riscv/riscv-isa-manual/releases/download/Ratified-IMAFDQC/riscv-spec-20191213.pdf) |
| **A**: Standard Extension for Atomic Instructions | [2.1](https://github.com/riscv/riscv-isa-manual/releases/download/Ratified-IMAFDQC/riscv-spec-20191213.pdf) |
| **C**: Standard Extension for Compressed Instructions | [2.0](https://github.com/riscv/riscv-isa-manual/releases/download/Ratified-IMAFDQC/riscv-spec-20191213.pdf) |
| **ZiCSR**: Control and Status Register (CSR) | [2.0](https://github.com/riscv/riscv-isa-manual/releases/download/Ratified-IMAFDQC/riscv-spec-20191213.pdf) |
| **Zifencei**: Instruction-Fetch Fence | [2.0](https://github.com/riscv/riscv-isa-manual/releases/download/Ratified-IMAFDQC/riscv-spec-20191213.pdf) |
| Machine ISA | [1.11](https://github.com/riscv/riscv-isa-manual/releases/download/Ratified-IMFDQC-and-Priv-v1.11/riscv-privileged-20190608.pdf) |
| Supervisor ISA | [1.11](https://github.com/riscv/riscv-isa-manual/releases/download/Ratified-IMFDQC-and-Priv-v1.11/riscv-privileged-20190608.pdf) |

Much of the content in the RISC-V Privileged Specification (i.e. the machine and supervisor ISAs) is optional. The features supported by Muntjac are detailed [here](privileged_spec.md).
