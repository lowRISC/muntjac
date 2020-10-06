// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#ifndef LOGS_H
#define LOGS_H

#include <iostream>

using std::cout;
using std::cerr;
using std::endl;

extern double sc_time_stamp();

// 0 = no logging
// 1 = all logging
// Potential to add more options here.
extern int log_level;
#define MUNTJAC_LOG(LEVEL) if (log_level >= LEVEL) cout << "[sim " << (uint64_t)sc_time_stamp() << "] "

#define MUNTJAC_WARN cerr << "[sim] Warning: "
#define MUNTJAC_ERROR cerr << "[sim] Error: "

#endif  // LOGS_H
