# riscv-tests

[riscv-tests](https://github.com/riscv-software-src/riscv-tests) is a suite of unit tests for the RISC-V ISA.

We run all tests from the following groups, except `rv64mi-p-breakpoint` which is not part of the core RISC-V specification.

| Test group | Bit width | Privilege level | Instruction set (extension) |
| --- | --- | --- | --- |
| `rv64ui` | 64 | User | Integer |
| `rv64um` | 64 | User | Multiplication and division |
| `rv64ua` | 64 | User | Atomic |
| `rv64uc` | 64 | User | Compressed |
| `rv64uf` | 64 | User | Single-precision floating point |
| `rv64ud` | 64 | User | Double-precision floating point |
| `rv64si` | 64 | Supervisor | Integer |
| `rv64mi` | 64 | Machine | Integer |

## Build tests
Building the tests largely follows the [standard procedure](https://github.com/riscv-software-src/riscv-tests#building-from-repository). We make slight tweaks to hook up the `exit` system call and remove the `breakpoint` test. From the riscv-tests directory (not this one):

```
# Replace provided linker script so system calls reach the host machine.
cp $(MUNTJAC_ROOT)/flows/link.ld env/p/link.ld

cd isa
make -j$(nproc)
rm *.dump
rm rv64mi-p-breakpoint
```

# Run tests
The tests are now ready to run as they are, e.g.:

```
muntjac_core rv64ui-p-add
```

To run all tests and generate a JUnit XML results file, use the Makefile in this directory. Failing tests will be marked with a `failure` tag.

```
export TEST_DIR=$(RISCV_TESTS_DIR)/isa

make results.xml -j$(nproc)
```
