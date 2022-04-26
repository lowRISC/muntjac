// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#include <cassert>
#include <fstream>
#include <sstream>

#include "logs.h"
#include "tl_config.h"

using std::ifstream;
using std::stoi;
using std::string;
using std::stringstream;
using std::vector;

// Remove YAML comments in-place.
string& remove_comments(string& line) {
  if (line.find_first_of("#") != string::npos)
    line.erase(line.find_first_of("#"));
  return line;
}

// Remove leading and trailing whitespace in-place.
string& strip_whitespace(string& line) {
  const char* whitespace = " \t\n\r\f\v";

  if (line.find_last_not_of(whitespace) != string::npos)
    line.erase(line.find_last_not_of(whitespace) + 1);

  if (line.find_first_not_of(whitespace) != string::npos)
    line.erase(0, line.find_first_not_of(whitespace));
  else
    line.clear();

  return line;
}

// Consider a line empty if it contains only whitespace and comments.
bool is_empty(string line) {
  remove_comments(line);
  strip_whitespace(line);

  return line.empty();
}

// Check whether one string ends with another string.
bool ends_with(const string& str, const string& suffix) {
  if (str.size() < suffix.size())
    return false;
  return str.compare(str.size() - suffix.size(), suffix.size(), suffix) == 0;
}

// Convert a string of space-separated integers into a vector of integers.
vector<int> parse_int_list(string& line) {
  vector<int> result;
  string token;
  stringstream ss(line);

  while (getline(ss, token, ' ')) {
    if (token.empty())
      continue;
    result.push_back(stoi(token));
  }

  return result;
}

tl_endpoint_config_t parse_parameters(vector<string>& data) {
  tl_endpoint_config_t component;

  for (string line : data) {
    if (line.find(":") == string::npos) {
      MUNTJAC_ERROR << "All configuration lines need the form 'name: value'" << endl;
      MUNTJAC_ERROR << "Problem line: " << line << endl;
      exit(1);
    }

    string name = line.substr(0, line.find(":"));
    string value = line.substr(line.find(":") + 1);

    strip_whitespace(name);
    remove_comments(value);
    strip_whitespace(value);

    if (name == "Protocol") {
      if (value == "TL-C")
        component.protocol = TL_C;
      else if (value == "TL-C-ROM-TERM")
        component.protocol = TL_C_ROM_TERM;
      else if (value == "TL-C-IO-TERM")
        component.protocol = TL_C_IO_TERM;
      else if (value == "TL-UH")
        component.protocol = TL_UH;
      else if (value == "TL-UL")
        component.protocol = TL_UL;
      else {
        MUNTJAC_ERROR << "Unknown protocol selected: " << value << endl;
        exit(1);
      }
    }
    else if (name == "DataWidth")
      component.data_width = stoi(value);
    else if (name == "FirstID")
      component.first_id = stoi(value);
    else if (name == "LastID")
      component.last_id = stoi(value);
    else if (name == "MaxSize")
      component.max_size = stoi(value);
    else if (name == "Fifo")
      component.fifo = stoi(value);
    else if (name == "CanDeny")
      component.can_deny = stoi(value);
    else if (ends_with(name, "Base"))
      component.bases = parse_int_list(value);
    else if (ends_with(name, "Mask"))
      component.masks = parse_int_list(value);
    else if (ends_with(name, "Target"))
      component.targets = parse_int_list(value);
    else
      MUNTJAC_WARN << "Unknown configuration parameter ignored: " << name << endl;
  }

  return component;
}

void add_component(tl_config_t& config, string& type, vector<string>& data) {
  if (data.empty())
    return;

  assert(type != "");
  tl_endpoint_config_t endpoint = parse_parameters(data);

  if (type == "host")
    config.hosts.push_back(endpoint);
  else if (type == "device")
    config.devices.push_back(endpoint);
  else
    assert(false && "Only hosts/devices supported as top-level names");
}

// Only support a simple subset of YAML for now.
// Could use a proper YAML parser, but that drags in dependencies.
tl_config_t read_config(string filename) {
  tl_config_t config;

  ifstream file(filename, std::iostream::in);

  if (!file.good()) {
    MUNTJAC_ERROR << "Unable to read configuration from " << filename << endl;
    exit(1);
  }

  string section = "";
  vector<string> component;

  while (!file.eof()) {
    string line;
    std::getline(file, line);

    if (is_empty(line))
      continue;
    else if (line.substr(0, 6) == "hosts:") {
      add_component(config, section, component);
      component.clear();

      section = "host";
    }
    else if (line.substr(0, 8) == "devices:") {
      add_component(config, section, component);
      component.clear();

      section = "device";
    }
    else {
      // Start of new component - parse previous data, if any.
      if (strip_whitespace(line)[0] == '-') {
        add_component(config, section, component);
        component.clear();

        line.erase(0, 1);  // Remove the hyphen.
      }

      component.push_back(line);
    }
  }

  add_component(config, section, component);

  MUNTJAC_LOG(1) << "Configured " << config.hosts.size() << " hosts and " 
      << config.devices.size() << " devices from " << filename << endl;

  file.close();
  return config;
}
