// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#ifndef ARGUMENT_PARSER_H
#define ARGUMENT_PARSER_H

#include <map>
#include <string>
using std::map;
using std::string;

class ArgumentParser {

public:

  enum NumArgs {
    ARGS_NONE,      // No arguments, just a flag
    ARGS_ONE,       // Single argument, can be "--flag=X" or "--flag X"
    ARGS_REMAINING  // All remaining arguments are grouped together
  };

  ArgumentParser();

  // Information about the simulator and how to use it.
  void set_description(string description);

  // Watch for a new argument.
  void add_argument(string name, string description, NumArgs args=ARGS_NONE);

  // Parse the command line arguments. May be called multiple times.
  void parse_args(int argc, char** argv);

  // Return whether the named argument was seen during `parse_args`.
  bool found_arg(string name) const;

  // Return the number of arguments parsed. Used to find the point where parsing
  // failed if an unexpected argument was found.
  int get_args_parsed() const;

  // Get the value of the named argument (assuming it was provided).
  // An empty string is returned if ARGS_NONE was specified for this argument,
  // and a single string containing space-separated arguments is provided for
  // ARGS_REMAINING.
  string get_arg(string name) const;

  // Print information about all available arguments.
  void print_help() const;

private:

  struct ArgInfo {
    string       description;
    enum NumArgs args;
  };

  string program_description;
  map<string, struct ArgInfo> arg_info;    // Map name to information
  map<string, string>         args_found;  // Map name to argument

  int args_parsed;

};

#endif  // ARGUMENT_PARSER_H
