// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#ifndef TILELINK_H
#define TILELINK_H

#include <cstdint>

// Normal protocol levels, plus a couple of extras for components which convert
// from one protocol to another. Since these components instantly deny some
// requests, they generally do not support any message types which follow a
// denied request. The traffic generator does not track these dependencies, so
// we need to restrict which operations are supported here.
// TODO: either track dependencies, or allow particular request types to be
//       added/removed from the configuration files.
typedef enum {
  TL_UL          = 0,
  TL_UH          = 1,
  TL_C_IO_TERM   = 2,
  TL_C_ROM_TERM  = 3,
  TL_C           = 4
} tl_protocol_e;

typedef enum {
  PutFullData    = 0,
  PutPartialData = 1,
  ArithmeticData = 2,
  LogicalData    = 3,
  Get            = 4,
  Intent         = 5,
  AcquireBlock   = 6,
  AcquirePerm    = 7
} tl_a_op_e;

typedef enum {
  // We do not support A messages being forwarded to B.
  ProbeBlock     = 6,
  ProbePerm      = 7
} tl_b_op_e;

typedef enum {
  // We do not support C messages being forwarded to D.
  ProbeAck       = 4,
  ProbeAckData   = 5,
  Release        = 6,
  ReleaseData    = 7
} tl_c_op_e;

typedef enum {
  AccessAck      = 0,
  AccessAckData  = 1,
  HintAck        = 2,
  Grant          = 4,
  GrantData      = 5,
  ReleaseAck     = 6
} tl_d_op_e;


typedef enum {
  ArithmeticMin  = 0,
  ArithmeticMax  = 1,
  ArithmeticMinU = 2,
  ArithmeticMaxU = 3,
  ArithmeticAdd  = 4
} arithmetic_data_param_e;

typedef enum {
  LogicalXor     = 0,
  LogicalOr      = 1,
  LogicalAnd     = 2,
  LogicalSwap    = 3
} logical_data_param_e;

typedef enum {
  IntentPrefetchRead  = 0,
  IntentPrefetchWrite = 1
} intent_param_e;

typedef enum {
  CapToT         = 0,
  CapToB         = 1,
  CapToN         = 2
} cap_permissions_e;

typedef enum {
  GrowNtoB       = 0,
  GrowNtoT       = 1,
  GrowBtoT       = 2
} grow_permissions_e;

typedef enum {
  PruneTtoB       = 0,
  PruneTtoN       = 1,
  PruneBtoN       = 2
} prune_permissions_e;

typedef enum {
  ReportTtoT      = 3,
  ReportBtoB      = 4,
  ReportNtoN      = 5
} report_permissions_e;


typedef struct {
  tl_a_op_e opcode;
  int       param;
  int       size;
  int       source;
  uint64_t  address;
  int       mask;
  bool      corrupt;
  uint64_t  data;
} tl_a;

typedef struct {
  tl_b_op_e opcode;
  int       param;
  int       size;
  int       source;
  uint64_t  address;

  // We do not support A messages being forwarded to B.
  // int       mask;
  // bool      corrupt;
  // uint64_t  data;
} tl_b;

typedef struct {
  tl_c_op_e opcode;
  int       param;
  int       size;
  int       source;
  uint64_t  address;
  bool      corrupt;
  uint64_t  data;
} tl_c;

typedef struct {
  tl_d_op_e opcode;
  int       param;
  int       size;
  int       source;
  int       sink;
  bool      denied;
  bool      corrupt;
  uint64_t  data;
} tl_d;

typedef struct {
  int       sink;
} tl_e;

typedef struct {
  bool      enable;
  bool      write_enable;
  uint64_t  address;
  int       write_mask;
  uint64_t  write_data;
  uint64_t  read_data;
} bram_ifc;

#endif // TILELINK_H
