// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#ifndef TL_CONFIG_H
#define TL_CONFIG_H

#include <string>
#include <vector>
#include "tilelink.h"

// Configuration of a single host/device.
typedef struct {
  // Highest protocol this component supports. (TL_C > TL_UH > TL_UL)
  tl_protocol_e protocol;

  // Bits of data sent in one beat.
  int data_width;

  // Source/sink ID range owned by this component.
  int first_id;
  int last_id;

  // log2(max beats per message)
  int max_size;

  // Produces/requires responses in FIFO order.
  bool fifo;

  // Component is able to deny requests.
  bool can_deny;

  // Routing table telling which sink/source IDs are owned by other components.
  std::vector<int> bases;
  std::vector<int> masks;
  std::vector<int> targets;
} tl_endpoint_config_t;

// Configuration of all endpoints of a DUT.
typedef struct {
  std::vector<tl_endpoint_config_t> hosts;
  std::vector<tl_endpoint_config_t> devices;
} tl_config_t;

// Read a YAML config file.
tl_config_t read_config(std::string filename);

#endif // TL_CONFIG_H
