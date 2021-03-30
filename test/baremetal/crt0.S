# Copyright lowRISC contributors.
# Licensed under the Apache License, Version 2.0, see LICENSE for details.
# SPDX-License-Identifier: Apache-2.0

  .section .text.init
  .align  6
  .weak stvec_handler
  .weak mtvec_handler
  .globl _start

_start:
  /* reset vector */
  j reset_vector
  .align 2

reset_vector:
  li x1, 0
  li x2, 0
  li x3, 0
  li x4, 0
  li x5, 0
  li x6, 0
  li x7, 0
  li x8, 0
  li x9, 0
  li x10, 0
  li x11, 0
  li x12, 0
  li x13, 0
  li x14, 0
  li x15, 0
  li x16, 0
  li x17, 0
  li x18, 0
  li x19, 0
  li x20, 0
  li x21, 0
  li x22, 0
  li x23, 0
  li x24, 0
  li x25, 0
  li x26, 0
  li x27, 0
  li x28, 0
  li x29, 0
  li x30, 0
  li x31, 0

  # Set up stack pointer and global pointer.

  # norelax:  the linker likes to use gp-relative addresses because it can often
  #           generate them in 1 instruction instead of 2. This doesn't make
  #           sense when initialising gp for the first time, so prevent it.
  # push/pop: save and restore linker options so norelax doesn't affect other
  #           sections unless it was already set.
  .option push
  .option norelax
  la   x3, __global_pointer
  .option pop

  la   x2, __stack_start
  # Set frame pointer here if necessary. x8 <= x2

csr_init:
  csrwi satp, 0
  csrwi mie, 0
  csrwi medeleg, 0
  csrwi mideleg, 0
  la x10, simple_exc_handler
  csrw mtvec, x10

main_entry:
  # Jump to main program entry point (argc = argv = 0)
  addi x10, x0, 0
  addi x11, x0, 0
  jal x1, main

  # Halt simulation
  addi x10, x0, 0
  j sim_halt
