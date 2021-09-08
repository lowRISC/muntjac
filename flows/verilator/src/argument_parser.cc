// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include <iostream>
#include "argument_parser.h"

using std::cout;
using std::endl;

ArgumentParser::ArgumentParser() {
  args_parsed = 0;
}

void ArgumentParser::set_description(string description) {
  program_description = description;
}

void ArgumentParser::add_argument(string name, string description, 
                                  NumArgs args) {
  struct ArgInfo info;
  info.description = description;
  info.args = args;

  arg_info[name] = info;
}

void ArgumentParser::parse_args(int argc, char** argv) {
  args_parsed = 0;
  while (args_parsed < argc) {
    string arg(argv[args_parsed]);
    string name;
    string value;

    // Allow both --arg=X and --arg X.
    if (arg.find("=") != string::npos) {
      name = arg.substr(0, arg.find("="));
      value = arg.substr(arg.find("=") + 1, arg.size());
    }
    else {
      name = arg;
      value = "";
    }

    // Stop parsing arguments but don't throw an exception if we find an
    // argument we weren't prepared for: it may just be the program to execute
    // or similar.
    if (arg_info.find(name) == arg_info.end())
      break;
    
    args_parsed++;

    // Collect value(s) if we don't already have enough.
    if (arg_info[name].args == ARGS_ONE && value == "") {
      value = string(argv[args_parsed]);
      args_parsed++;
    }
    else if (arg_info[name].args == ARGS_REMAINING) {
      while (args_parsed < argc) {
        // TODO: does the leading space break things if we later split(" ")?
        value.append(" " + string(argv[args_parsed]));
        args_parsed++;
      }
    }

    args_found[name] = value;
  }
}

int ArgumentParser::get_args_parsed() const {
  return args_parsed;
}

bool ArgumentParser::found_arg(string name) const {
  // Would prefer to use args_found.contains(name), but that's only in C++20.
  return args_found.find(name) != args_found.end();
}

string ArgumentParser::get_arg(string name) const {
  return args_found.at(name);
}

void ArgumentParser::print_help() const {
  cout << program_description << endl;
  cout << endl;
  cout << "Arguments:" << endl;

  for (auto it = arg_info.begin(); it != arg_info.end(); ++it) {
    cout << "  " << it->first;
    
    if (it->second.args == ARGS_ONE)
      cout << " X";

    cout << endl;

    cout << "        " << it->second.description << endl;
  }
}
