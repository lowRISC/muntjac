# Glossary

This page gives brief explanations of some of the terms used in this documentation, with references to further details. The target audience is anyone who has completed an undergraduate course in computer architecture.

## Control and status registers
The control and status registers (CSRs) hold information about the processor and its behaviour. Examples include:

* The make and model of the processor
* How to handle interrupts and exceptions
* [Physical memory protection](#physical-memory-protection) details
* [Virtual address translation](#virtual-addressing-modes) details
* Performance counters/monitors

Many of the CSRs are optional. Different CSRs are accessible from different [privilege modes](#privilege-modes), and some may overlap. For example, reading the `sstatus` CSR from supervisor mode will return a subset of the information returned when reading `mstatus` in machine mode.

Full details are given in the [RISC-V privileged specification](https://github.com/riscv/riscv-isa-manual/releases/download/Ratified-IMFDQC-and-Priv-v1.11/riscv-privileged-20190608.pdf).

## Debug mode
The [RISC-V Debug Specification](https://github.com/riscv/riscv-debug-spec) defines a set of interfaces which allow debugging of software running on RISC-V processors. Supported features include:

* Access to register/memory contents
* Breakpoints
* Halt/resume/step through execution

## Interrupt modes
Interrupts can be handled in two ways:

* **Direct**: all interrupts trap to the same memory address, which contains code to inspect the processor's state and determine what to do next.
* **Vectored**: interrupts trap to different memory addresses, depending on the cause of the interrupt.

The current mode is stored in the `mtvec` [CSR](#control-and-status-registers).

## Physical memory protection
Physical memory protection allows control over which memory operations (read, write, execute) are allowed to particular memory address ranges when in each [privilege mode](#privilege-modes). An exception is triggered if these restrictions are violated.

Reducing the capabilities of software allows increased security and better containment of faults if something goes wrong.

## Privilege modes
A RISC-V core may support a number of different privilege modes. The current mode may be checked when accessing registers or memory to control how data is accessed. An exception may be triggered if the requested operation is not supported by the current mode.

A core may move between privilege modes when an exception or interrupt is encountered, or by executing one of the `call`, `break` (breakpoint) or `ret` (return) instructions.

In order of increasing privilege:

| Abbreviation | Name | Intended use |
| --- | --- | --- |
| **U** | User | Applications |
| **S** | Supervisor | Operating systems |
| **M** | Machine | Setup of more-restricted modes |

There are restrictions on which combination of modes an implementation may support:

* **M** only
* **M** and **U**
* **M**, **S** and **U**

## RISC-V instruction sets
RISC-V is a modular instruction set, allowing designers to choose the most appropriate subset of features for a given system.

The base instruction set is always **RV32I** (32-bit integer) or **RV64I** (64-bit integer), with other variants being planned.

Many extensions are planned, with the most common ones listed below. Further details can be found in the [unprivileged](https://github.com/riscv/riscv-isa-manual/releases/download/Ratified-IMAFDQC/riscv-spec-20191213.pdf) and [privileged](https://github.com/riscv/riscv-isa-manual/releases/download/Ratified-IMFDQC-and-Priv-v1.11/riscv-privileged-20190608.pdf) specifications.

| Name | Description | Notes |
| --- | --- | --- |
| **M** | Integer multiplication and division | Instructions include multiply, divide, remainder, ... |
| **A** | Atomic memory operations | Instructions include load reserved, store conditional, atomic swap, atomic add, ...|
| **F** | Single-precision floating point | Requires separate floating point registers and the **ZiCSR** extension. Instructions include load/store, add, multiply, divide, square root, min/max, convert to/from integer, ... |
| **D** | Double-precision floating point | Similar to **F**. |
| **G** | Shorthand for the base **I** + **MAFD** extensions | |
| **C** | Compressed instructions | Optimised 16-bit encodings for common cases in the base **I** instruction sets. Uses smaller immediates and/or a more restricted range of registers. |
| **Q** | Quad-precision floating point | Similar to **F** and **D**. |
| **ZiCSR** | Control and status registers | Allows reads/writes to the [control and status registers](#control-and-status-registers). |
| **Zifencei** | Instruction-fetch fence | Provides explicit synchronisation between instruction fetches and writes to instruction memory. |
| **Ztso** | Total store ordering | Places extra restrictions on the ordering of memory operations. No additional instructions are provided. |

## Unaligned memory access
A memory access is considered unaligned if the address being accessed is not a multiple of the number of bytes being accessed.

For example, when accessing address `0x2`, loading a byte or halfword (2 bytes) would count as an aligned access, while accessing a word (4 bytes) or double-word (8 bytes) would count as an unaligned access.

If unaligned access is not supported by a processor, an exception may be triggered if such an access is attempted.

## Virtual addressing modes
The [RISC-V privileged specification](https://github.com/riscv/riscv-isa-manual/releases/download/Ratified-IMFDQC-and-Priv-v1.11/riscv-privileged-20190608.pdf) defines three different virtual addressing modes which control how virtual memory addresses are mapped to physical memory addresses.

The current addressing mode is stored in the `mode` [CSR](#control-and-status-registers) and may be changed during execution.

| Name | Address space | Page table levels | Page sizes |
| --- | --- | --- | --- |
| **Sv32** | 32 bits | 2 | 4 KiB, 4 MiB |
| **Sv39** | 39 bits | 3 | 4 KiB, 2 MiB, 1 GiB |
| **Sv48** | 48 bits | 4 | 4 KiB, 2 MiB, 1 GiB, 512 GiB |
