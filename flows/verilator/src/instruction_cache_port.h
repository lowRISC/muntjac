// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#ifndef INSTRUCTION_CACHE_PORT_H
#define INSTRUCTION_CACHE_PORT_H

#include "exceptions.h"
#include "memory_port.h"
#include "page_table_walker.h"

// Port to connect a module to main memory via the icache interface. A cache is
// not modelled; only the interface to one.
// The DUT class must provide all signals specified in the icache interface,
// with all hierarchy flattened.
// e.g. icache.resp_valid must be named icache_resp_valid
template<class DUT>
class InstructionCachePort : public MemoryPort<uint32_t> {
public:
  InstructionCachePort(DUT& dut, MainMemory& memory, uint latency) :
      MemoryPort<uint32_t>(memory, latency),
      dut(dut),
      page_table_walker(memory) {
    // Nothing
  }

protected:

  virtual bool can_receive_request() {
    return dut.icache_req_valid;
  }

  virtual void get_request() {
    assert(can_receive_request());

    // Always fetch from an aligned 4-byte block. If the lower bits were
    // non-zero, the pipeline will extract the required part.
    MemoryAddress address = dut.icache_req_pc & ~0x3;

    try {
      // Do virtual -> physical address translation if necessary.
      AddressTranslationProtection64 atp(dut.icache_req_atp);
      if (atp.mode() != ATP_MODE_BARE) {
        address = page_table_walker.translate(
          address,
          MEM_FETCH,
          dut.icache_req_prv,
          dut.icache_req_sum,
          false,  // MXR bit not needed by icache
          atp
        );
      }

      uint32_t instruction = memory.read32(address);
      queue_response(instruction);
    }
    catch (const PageFault& e) {
      queue_response(address, e.get_exception_code(MEM_FETCH));
    }
    catch (const AccessFault& e) {
      queue_response(address, e.get_exception_code(MEM_FETCH));
    }
  }

  virtual bool can_send_response() {
    return true;
  }

  virtual void send_response(response_t& response) {
    dut.icache_resp_instr = response.data;
    dut.icache_resp_valid = 1;
    dut.icache_resp_exception = (response.exception != EXC_CAUSE_NONE);

    if (dut.icache_resp_exception) {
      dut.icache_resp_ex_code = response.exception;

      // Invalidate the normal response. (Only dcache does this?)
      //dut.icache_resp_valid = 0;
    }

    response.all_sent = true;
  }

  virtual void clear_response() {
    dut.icache_resp_valid = 0;
    dut.icache_resp_exception = 0;
  }

private:

  DUT& dut;
  PageTableWalkerSv39 page_table_walker;
};

#endif  // INSTRUCTION_CACHE_PORT_H
