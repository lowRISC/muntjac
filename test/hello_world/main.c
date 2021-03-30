// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include "common.h"

int main(int argc, char **argv) {

  putchar('a');
  putchar('b');
  putchar('c');
  putchar('\n');

  puts("Hello world!\n");
  
  puthex(0xDEADBEEFBAADF00D);
  putchar('\n');

  return 0;
}
