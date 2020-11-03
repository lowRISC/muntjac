# Muntjac

Muntjac is a minimal 64-bit RISC-V multicore processor that's easy to understand, verify, and extend. The focus is on having a clean, well-tested design which others can build upon and further customise. Performance is secondary to correctness, but the aim is to work towards a design point (in terms of PPA) that maximises the value of Muntjac as a baseline design for educational, academic, or real-world use.

Details about the microarchitecture are available [here](microarchitecture.md).

# Features

| Feature | Description |
| --- | --- |
| Instruction set | RV64IMAC (integer, multiply, atomics, compressed; no floating point) |
| Privilege modes | M/S/U (machine/supervisor/user) |
| Virtual addressing | Sv39 |
| Interrupt mode | Direct (not vectored) |
| Physical memory protection | Not supported |
| Debug mode | Not supported |
| Unaligned loads/stores | Not supported |

# Standards

The Muntjac processor meets the following standards:

| Standard | Version |
| --- | --- |
| **RV64I**: Base Integer Instruction Set, 64-bit | 2.1 |
| **M**: Standard Extension for Integer Multiplication and Division | 2.0 |
| **A**: Standard Extension for Atomic Instructions | 2.1 |
| **C**: Standard Extension for Compressed Instructions | 2.0 |
| **ZiCSR**: Control and Status Register (CSR) | 2.0 |
| **Zifencei**: Instruction-Fetch Fence | 2.0 |
| Machine ISA | 1.11 |
| Supervisor ISA | 1.11 |

Much of the content in the RISC-V Privileged Specification is optional. The features supported by Muntjac are detailed [here](privileged_spec.md).
