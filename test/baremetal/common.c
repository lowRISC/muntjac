// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include "common.h"

// Communication with the host system.
extern uint64_t tohost;
extern uint64_t fromhost;

// Data to write to tohost to indicate the service being requested.
// If the service takes an argument, the least significant byte will be used.
const uint64_t putchar_code = 0x0101000000000000;
const uint64_t sysexit_code = 0x0000000000000000;

int putchar(int c) {
  tohost = putchar_code | (c & 0xff);

  return c;
}

int puts(const char *str) {
  while (*str) {
    putchar(*str++);
  }

  return 0;
}

void puthex(uint64_t h) {
  uint64_t cur_digit;
  // Iterate through h taking top 4 bits each time and outputting ASCII of hex
  // digit for those 4 bits
  for (int i = 0; i < 16; i++) {
    cur_digit = h >> 60;

    if (cur_digit < 10)
      putchar('0' + cur_digit);
    else
      putchar('A' - 10 + cur_digit);

    h <<= 4;
  }
}

void sim_halt(int code) {
  tohost = sysexit_code | (code & 0xff);

  // Might not have a return address set up. Never return.
  while(1);
}

void pcount_reset() {
  asm volatile(
      "csrw minstret,       x0\n"
      "csrw mcycle,         x0\n"
  );
}

void pcount_enable(int enable) {
  // Note cycle is disabled with everything else
  unsigned int inhibit_val = enable ? 0x0 : 0xFFFFFFFFFFFFFFFF;
  // CSR 0x320 was called `mucounteren` in the privileged spec v1.9.1, it was
  // then dropped in v1.10, and then re-added in v1.11 with the name
  // `mcountinhibit`. Unfortunately, the version of binutils we use only allows
  // the old name, and LLVM only supports the new name (though this is changed
  // on trunk to support both), so we use the numeric value here for maximum
  // compatibility.
  CSR_WRITE(0x320, inhibit_val);
}

unsigned int get_mepc() {
  uint32_t result;
  CSR_READ(mepc, result);
  return result;
}

unsigned int get_mcause() {
  uint32_t result;
  CSR_READ(mcause, result);
  return result;
}

unsigned int get_mtval() {
  uint32_t result;
  CSR_READ(mtval, result);
  return result;
}

void simple_exc_handler(void) {
  puts("EXCEPTION!!!\n");
  puts("============\n");
  puts("MEPC:   0x");
  puthex(get_mepc());
  puts("\nMCAUSE: 0x");
  puthex(get_mcause());
  puts("\nMTVAL:  0x");
  puthex(get_mtval());
  putchar('\n');
  sim_halt(1);
}

/*
volatile uint64_t time_elapsed;
uint64_t time_increment;

inline static void increment_timecmp(uint64_t time_base) {
  uint64_t current_time = timer_read();
  current_time += time_base;
  timecmp_update(current_time);
}

void timer_enable(uint64_t time_base) {
  time_elapsed = 0;
  time_increment = time_base;
  // Set timer values
  increment_timecmp(time_base);
  // enable timer interrupt
  asm volatile("csrs  mie, %0\n" : : "r"(0x80));
  // enable global interrupt
  asm volatile("csrs  mstatus, %0\n" : : "r"(0x8));
}

void timer_disable(void) { asm volatile("csrc  mie, %0\n" : : "r"(0x80)); }

uint64_t timer_read(void) {
  uint32_t current_timeh;
  uint32_t current_time;
  // check if time overflowed while reading and try again
  do {
    current_timeh = DEV_READ(TIMER_BASE + TIMER_MTIMEH, 0);
    current_time = DEV_READ(TIMER_BASE + TIMER_MTIME, 0);
  } while (current_timeh != DEV_READ(TIMER_BASE + TIMER_MTIMEH, 0));
  uint64_t final_time = ((uint64_t)current_timeh << 32) | current_time;
  return final_time;
}

void timecmp_update(uint64_t new_time) {
  DEV_WRITE(TIMER_BASE + TIMER_MTIMECMP, -1);
  DEV_WRITE(TIMER_BASE + TIMER_MTIMECMPH, new_time >> 32);
  DEV_WRITE(TIMER_BASE + TIMER_MTIMECMP, new_time);
}

uint64_t get_elapsed_time(void) { return time_elapsed; }

void simple_timer_handler(void) __attribute__((interrupt));

void simple_timer_handler(void) {
  increment_timecmp(time_increment);
  time_elapsed++;
}
*/
