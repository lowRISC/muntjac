// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#ifndef EXCEPTIONS_H
#define EXCEPTIONS_H

#include <string>

#include "types.h"

using std::string;

class MuntjacException : public std::exception {
public:
  MuntjacException(string description);
  virtual const char* what() const noexcept;
private:
  const string message;
};

class AccessFault : public MuntjacException {
public:
  AccessFault(MemoryAddress address, string description);
  exc_cause_e get_exception_code(MemoryOperation operation) const;
private:
  const MemoryAddress address;
};

class AlignmentFault : public MuntjacException {
public:
  AlignmentFault(MemoryAddress address);
  exc_cause_e get_exception_code(MemoryOperation operation) const;
private:
  const MemoryAddress address;
};

class PageFault : public MuntjacException {
public:
  PageFault(MemoryAddress address, string description);
  exc_cause_e get_exception_code(MemoryOperation operation) const;
private:
  const MemoryAddress address;
};


class SimulatorException : public std::exception {
public:
  SimulatorException(string description);
  virtual const char* what() const noexcept;
private:
  const string message;
};

class InvalidArgumentException : public SimulatorException {
public:
  InvalidArgumentException(string argument, int position);
  string get_name() const;
  int get_position() const;
private:
  const string name;
  const int position;
};

#endif  // EXCEPTIONS_H
