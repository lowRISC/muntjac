// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#ifndef TL_EXCEPTIONS_H
#define TL_EXCEPTIONS_H

#include <exception>

// Exception for when no TileLink transaction IDs are available. This
// should always be caught, and should result in a pause until IDs become
// available again.
class NoAvailableIDException : public std::exception {
public:
  NoAvailableIDException() : std::exception() {}
  virtual const char* what() const noexcept {return "No TileLink IDs";}
};

#endif // TL_EXCEPTIONS_H
