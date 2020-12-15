# Muntjac privileged specification
Much of the [RISC-V privileged specification](https://github.com/riscv/riscv-isa-manual/releases/download/Ratified-IMFDQC-and-Priv-v1.11/riscv-privileged-20190608.pdf) (version 1.11) is optional. This page details the parts implemented by Muntjac.

## Control and status registers
| Name | Description |
| --- | --- |
| `MVENDORID` | Vendor ID |
| `MARCHID` | Architecture ID |
| `MIMPID` | Implementation ID |
| `MHARTID` | Hardware thread ID |
| `MSTATUS` | Machine status |
| `MISA` | ISA and extensions |
| `MEDELEG` | Machine exception delegation register |
| `MIDELEG` | Machine interrupt delegation register |
| `MIE` | Machine interrupt-enable register |
| `MTVEC` | Machine trap-handler base address |
| `MCOUNTEREN` | Machine counter enable |
| `MSCRATCH` | Scratch register for machine trap handlers |
| `MEPC` | Machine exception program counter |
| `MCAUSE` | Machine trap cause |
| `MTVAL` | Machine bad address or instruction |
| `MIP` | Machine interrupt pending |
| `SSTATUS` | Supervisor status |
| `SIE` | Supervisor interrupt-enable register |
| `STVEC` | Supervisor trap-handler base address |
| `SCOUNTEREN` | Supervisor counter enable |
| `SSCRATCH` | Scratch register for supervisor trap handlers |
| `SEPC` | Supervisor exception program counter |
| `SCAUSE` | Supervisor trap cause |
| `STVAL` | Supervisor bad address or instruction |
| `SIP` | Supervisor interrupt pending |
| `SATP` | Supervisor address translation and protection |

## Interrupts
| Name |
| --- |
| `S_SOFTWARE_INTR` |
| `M_SOFTWARE_INTR` |
| `S_TIMER_INTR` |
| `M_TIMER_INTR` |
| `S_EXTERNAL_INTR` |
| `M_EXTERNAL_INTR` |

## Exceptions
| Name |
| --- |
| `INSTRUCTION_ACCESS_FAULT` |
| `ILLEGAL_INSTRUCTION` |
| `BREAKPOINT` |
| `LOAD_ADDRESS_MISALIGNED` |
| `LOAD_ACCESS_FAULT` |
| `STORE_AMO_ADDRESS_MISALIGNED` |
| `STORE_AMO_ACCESS_FAULT` |
| `ECALL_UMODE` |
| `ECALL_SMODE` |
| `ECALL_MMODE` |
| `INSTRUCTION_PAGE_FAULT` |
| `LOAD_PAGE_FAULT` |
| `STORE_AMO_PAGE_FAULT` |
