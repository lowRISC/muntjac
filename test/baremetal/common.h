// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#ifndef SIMPLE_SYSTEM_COMMON_H__

#include <stdint.h>

/**
 * Enables/disables performance counters.  This affects mcycle and minstret as
 * well as the mhpmcounterN counters.
 *
 * Muntjac does not yet support disabling of counters, so this function
 * currently has no effect.
 *
 * @param enable if non-zero enables, otherwise disables
 */
void pcount_enable(int enable);

/**
 * Resets all performance counters.  This affects mcycle and minstret as well
 * as the mhpmcounterN counters.
 */
void pcount_reset();

#endif
