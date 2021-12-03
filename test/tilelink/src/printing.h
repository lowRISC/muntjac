// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#ifndef TL_PRINTING_H
#define TL_PRINTING_H

#include <iostream>
#include "tilelink.h"

std::ostream& operator<<(std::ostream& os, const tl_a_op_e& op);
std::ostream& operator<<(std::ostream& os, const tl_b_op_e& op);
std::ostream& operator<<(std::ostream& os, const tl_c_op_e& op);
std::ostream& operator<<(std::ostream& os, const tl_d_op_e& op);

std::ostream& operator<<(std::ostream& os, const tl_a& data);
std::ostream& operator<<(std::ostream& os, const tl_b& data);
std::ostream& operator<<(std::ostream& os, const tl_c& data);
std::ostream& operator<<(std::ostream& os, const tl_d& data);
std::ostream& operator<<(std::ostream& os, const tl_e& data);

#endif // TL_PRINTING_H
