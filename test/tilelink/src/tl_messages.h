// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#ifndef TL_MESSAGES_H
#define TL_MESSAGES_H

#include <cassert>
#include <map>

#include "tilelink.h"

using std::map;
using std::string;

template<typename channel_t> class TileLinkSender;

// A "message" in TileLink terms is a sequence of beats which are all part of
// the same request/response.
class tl_message_base {
public:

  // Basic constructor for when we don't yet know how many beats this message
  // will require. `beats_to_send` must be set separately.
  tl_message_base(int channel_width_bytes) :
      channel_width_bytes(channel_width_bytes) {
    assert(channel_width_bytes > 0);

    beats_generated = 0;
  }

  // Create a message from given control signals.
  // Use `num_beats` to control how many beats are generated automatically 
  // (i.e. have dummy payloads).
  tl_message_base(int channel_width_bytes, int num_beats) :
      channel_width_bytes(channel_width_bytes),
      beats_to_send(num_beats) {
    assert(beats_to_send > 0);
    assert(channel_width_bytes > 0);

    beats_generated = 0;
  }

  bool in_progress() const {
    return beats_generated > 0;
  }

  bool finished() const {
    return beats_to_send == beats_generated;
  }

  // Roll back the number of beats sent so far.
  // Mainly for debug - generate extra beats in a message.
  void unsend() {
    beats_generated--;
  }

protected:

  // The width of the channel this message is being sent on.
  const int channel_width_bytes;

  // Number of beats to generate for this message. Usually this will be
  // determined by the `size` field in the header and the width of the channel,
  // but generating fewer beats automatically allows specific content to be
  // inserted in later beats.
  int beats_to_send;

  // Number of beats generated so far.
  int beats_generated;
};

// Empty template base class.
template<class channel_t>
class tl_message : public tl_message_base {
};


// Channel-specific behaviour.

template<>
class tl_message<tl_a> : public tl_message_base {
  typedef tl_a channel_t;
  typedef TileLinkSender<channel_t> source_t;
public:
  // Create a message from given control signals.
  // Use `num_beats` to control how many beats are generated automatically 
  // (i.e. have dummy payloads).
  tl_message(source_t& endpoint, channel_t header, int num_beats);

  // New (random) A request.
  // `requirements` maps TileLink field names to values, e.g. {{"size", 4}}.
  tl_message(source_t& endpoint, bool randomise,
             map<string, int> requirements = map<string, int>());

  // Get the next beat of a message.
  channel_t next_beat(bool randomise);

  // Modify a beat of a message.
  // `updates` maps TileLink field names to values, e.g. {{"size", 4}}.
  static channel_t modify(channel_t beat, map<string, int>& updates);

  // First beat of the message, containing all control signals.
  channel_t header;
};

template<>
class tl_message<tl_b> : public tl_message_base {
  typedef tl_b channel_t;
  typedef TileLinkSender<channel_t> source_t;
public:
  // Create a message from given control signals.
  // Use `num_beats` to control how many beats are generated automatically 
  // (i.e. have dummy payloads).
  tl_message(source_t& endpoint, channel_t header, int num_beats);

  // New (random) B request.
  // `requirements` maps TileLink field names to values, e.g. {{"size", 4}}.
  tl_message(source_t& endpoint, bool randomise,
             map<string, int> requirements = map<string, int>());

  // B response to A request.
  tl_message(source_t& endpoint, tl_a& request, bool randomise);

  // Get the next beat of a message.
  channel_t next_beat(bool randomise);

  // Modify a beat of a message.
  // `updates` maps TileLink field names to values, e.g. {{"size", 4}}.
  static channel_t modify(channel_t beat, map<string, int>& updates);

  // First beat of the message, containing all control signals.
  channel_t header;
};

template<>
class tl_message<tl_c> : public tl_message_base {
  typedef tl_c channel_t;
  typedef TileLinkSender<channel_t> source_t;
public:
  // Create a message from given control signals.
  // Use `num_beats` to control how many beats are generated automatically 
  // (i.e. have dummy payloads).
  tl_message(source_t& endpoint, channel_t header, int num_beats);

  // New (random) C request.
  // `requirements` maps TileLink field names to values, e.g. {{"size", 4}}.
  tl_message(source_t& endpoint, bool randomise,
             map<string, int> requirements = map<string, int>());

  // C response to B request.
  tl_message(source_t& endpoint, tl_b& request, bool randomise);

  // Get the next beat of a message.
  channel_t next_beat(bool randomise);

  // Modify a beat of a message.
  // `updates` maps TileLink field names to values, e.g. {{"size", 4}}.
  static channel_t modify(channel_t beat, map<string, int>& updates);

  // First beat of the message, containing all control signals.
  channel_t header;
};

template<>
class tl_message<tl_d> : public tl_message_base {
  typedef tl_d channel_t;
  typedef TileLinkSender<channel_t> source_t;
public:
  // Create a message from given control signals.
  // Use `num_beats` to control how many beats are generated automatically 
  // (i.e. have dummy payloads).
  tl_message(source_t& endpoint, channel_t header, int num_beats);

  // D response to A request.
  tl_message(source_t& endpoint, tl_a& request, bool randomise);

  // D response to C request.
  tl_message(source_t& endpoint, tl_c& request, bool randomise);

  // Get the next beat of a message.
  channel_t next_beat(bool randomise);

  // Modify a beat of a message.
  // `updates` maps TileLink field names to values, e.g. {{"size", 4}}.
  static channel_t modify(channel_t beat, map<string, int>& updates);

  // First beat of the message, containing all control signals.
  channel_t header;
};

template<>
class tl_message<tl_e> : public tl_message_base {
  typedef tl_e channel_t;
  typedef TileLinkSender<channel_t> source_t;
public:
  // Create a message from given control signals.
  // Use `num_beats` to control how many beats are generated automatically 
  // (i.e. have dummy payloads).
  tl_message(source_t& endpoint, channel_t header, int num_beats);

  // E response to D request.
  tl_message(source_t& endpoint, tl_d& request, bool randomise);

  // Get the next beat of a message.
  channel_t next_beat(bool randomise);

  // Modify a beat of a message.
  // `updates` maps TileLink field names to values, e.g. {{"size", 4}}.
  static channel_t modify(channel_t beat, map<string, int>& updates);

  // First beat of the message, containing all control signals.
  channel_t header;
};

#endif // TL_MESSAGES_H
