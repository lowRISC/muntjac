// Copyright lowRISC contributors.
// Licensed under the Apache License, Version 2.0, see LICENSE for details.
// SPDX-License-Identifier: Apache-2.0

#ifndef DATA_CACHE_PORT_H
#define DATA_CACHE_PORT_H

#include <cassert>

#include "exceptions.h"
#include "logs.h"
#include "memory_port.h"
#include "page_table_walker.h"

// Port to connect a module to main memory via the dcache interface. A cache is
// not modelled; only the interface to one.
// The DUT class must provide all signals specified in the dcache interface,
// with all hierarchy flattened.
// e.g. dcache.resp_valid must be named dcache_resp_valid
template<class DUT>
class DataCachePort : public MemoryPort<uint64_t> {
public:

  DataCachePort(DUT& dut, MainMemory& memory, uint latency) :
      MemoryPort<uint64_t>(memory, latency),
      dut(dut),
      page_table_walker(memory) {
    delayed_notif_ready = 0;
    clear_all_reservations();
  }

protected:

  virtual bool can_receive_request() {
    return dut.dcache_req_valid;
  }

  virtual void get_request() {
    assert(can_receive_request());

    MemoryAddress address = dut.dcache_req_address;
    MemoryOperation operation = (MemoryOperation)dut.dcache_req_op;
    uint64_t operand = dut.dcache_req_value;

    try {
      if (!aligned(address, dut.dcache_req_size))
        throw AlignmentFault(address);

      // Do virtual -> physical address translation if necessary.
      AddressTranslationProtection64 atp(dut.dcache_req_atp);
      if (atp.mode() != ATP_MODE_BARE) {
        address = page_table_walker.translate(
          address,
          operation,
          dut.dcache_req_prv,
          dut.dcache_req_sum,
          dut.dcache_req_mxr,
          atp
        );
      }

      // Data read.
      uint64_t data_read = read_memory(operation, dut.dcache_req_size, address);
      uint64_t data_write = operand;

      // Sign extend data for signed loads and all atomics.
      if ((operation == MEM_LOAD) ||
          (operation == MEM_AMO) ||
          (operation == MEM_LR)) {
        size_t bytes = 1 << dut.dcache_req_size;
        data_read = size_extend(data_read, bytes, (SizeExtension)dut.dcache_req_size_ext);
        operand = size_extend(operand, bytes, (SizeExtension)dut.dcache_req_size_ext);
      }

      // Atomic data update.
      // The bottom two bits of the amo field represent ordering constraints and
      // are not used here.
      if (operation == MEM_AMO)
        data_write = atomic_update(dut.dcache_req_amo >> 2, data_read, operand);

      if (operation == MEM_LR)
        make_reservation(address);

      if (operation == MEM_SC)
        data_read = !check_reservation(address);

      // Data write.
      write_memory(operation, dut.dcache_req_size, address, data_write);

      // All memory operations must send a response. Even if there is no
      // payload,we need to signal that the request completed successfully.
      queue_response(data_read);
    }
    catch (const AccessFault& e) {
      queue_response(address, e.get_exception_code(operation));
    }
    catch (const AlignmentFault& e) {
      queue_response(address, e.get_exception_code(operation));
    }
    catch (const PageFault& e) {
      queue_response(address, e.get_exception_code(operation));
    }

  }

  virtual bool can_send_response() {
    return true;
  }

  virtual void send_response(response_t& response) {
    dut.dcache_resp_value = response.data;
    dut.dcache_resp_valid = 1;
    dut.dcache_ex_valid = (response.exception != EXC_CAUSE_NONE);

    if (dut.dcache_ex_valid) {
      // Verilator breaks an exception_t (4-bit cause, 64-bit payload) down into
      // an array of 3 32-bit values. Need to do some unpacking to get the
      // information across properly.
      dut.dcache_ex_exception[2] = response.exception;
      dut.dcache_ex_exception[1] = response.data >> 32;
      dut.dcache_ex_exception[0] = response.data & 0xFFFFFFFF;

      // Invalidate the normal response.
      dut.dcache_resp_valid = 0;
    }

    response.all_sent = true;
  }

  virtual void clear_response() {
    dut.dcache_resp_valid = 0;
    dut.dcache_ex_valid = 0;

    // Also respond immediately to SFENCE signals (and clear the response when
    // the signal is deasserted again).
    // Update: an immediate response is too fast. Add a 1 cycle delay.
    //dut.dcache_notif_ready = dut.dcache_notif_valid;
    dut.dcache_notif_ready = delayed_notif_ready;
    delayed_notif_ready = dut.dcache_notif_valid;

    if (dut.dcache_notif_valid)
      clear_all_reservations();
  }

private:

  bool aligned(MemoryAddress address, int alignment) {
    switch (alignment) {
      case 0: return true;
      case 1: return (address & 0x1) == 0;
      case 2: return (address & 0x3) == 0;
      case 3: return (address & 0x7) == 0;
      default:
        MUNTJAC_ERROR << "Invalid alignment parameter: " << alignment << endl;
        exit(1);
        break;
    }
  }

  // Zero-extend the lowest `bytes` of `original` to create a signed 64-bit
  // integer.
  int64_t zero_extend(uint64_t original, size_t bytes) {
    int shift = 64 - (bytes * 8);
    return (original << shift) >> shift;
  }

  // One-extend the lowest `bytes` of `original` to create a signed 64-bit
  // integer.
  int64_t one_extend(uint64_t original, size_t bytes) {
    return ~zero_extend(~original, bytes);
  }

  // Sign-extend the lowest `bytes` of `original` to create a signed 64-bit
  // integer.
  int64_t sign_extend(uint64_t original, size_t bytes) {
    int shift = 64 - (bytes * 8);
    int64_t result = original;
    return (result << shift) >> shift;
  }

  // Size-extend the lowest `bytes` of `original` to create a signed 64-bit
  // integer.
  int64_t size_extend(uint64_t original, size_t bytes, SizeExtension size_ext) {
    switch (size_ext) {
      case SIZE_EXT_ZERO: return zero_extend(original, bytes);
      case SIZE_EXT_ONE: return one_extend(original, bytes);
      case SIZE_EXT_SIGNED: return sign_extend(original, bytes);
      default: assert(false); break;
    }
  }

  uint64_t read_memory(MemoryOperation operation, uint log2_size,
                       MemoryAddress address) {
    switch (operation) {
      case MEM_LOAD:
      case MEM_LR:
      case MEM_AMO:
        // Not all request sizes are valid for all memory operations, but I
        // ignore that.
        switch (log2_size) {
          case 0: return memory.read8(address);
          case 1: return memory.read16(address);
          case 2: return memory.read32(address);
          case 3: return memory.read64(address);
          default:
            MUNTJAC_ERROR << "Unsupported memory request size: " << dut.dcache_req_size << endl;
            exit(1);
            break;
        }
        break;

      case MEM_SC:
      case MEM_STORE:
        // No data read.
        break;

      default:
        MUNTJAC_ERROR << "Unsupported memory operation: " << dut.dcache_req_op << endl;
        exit(1);
        break;
    }

    return 0;
  }

  uint64_t atomic_update(uint operation, uint64_t original, uint64_t operand) {
    switch (operation) {
      case 0: return original + operand;
      case 1: return operand;
      case 4: return original ^ operand;
      case 8: return original | operand;
      case 12: return original & operand;
      case 16: return (int64_t)original < (int64_t)operand ? original : operand;
      case 20: return (int64_t)original < (int64_t)operand ? operand : original;
      case 24: return original < operand ? original : operand;
      case 28: return original < operand ? operand : original;

      default:
        MUNTJAC_ERROR << "Unsupported atomic memory operation: " << operation << endl;
        exit(1);
        break;
    }

    return 0;
  }

  void write_memory(MemoryOperation operation, uint log2_size,
                    MemoryAddress address, uint64_t data) {
    switch (operation) {
      case MEM_LOAD:
      case MEM_LR:
        // No data write.
        break;

      case MEM_SC:
        if (!check_reservation(address))
          break;
        // else: fall-through to MEM_STORE
      case MEM_AMO:
      case MEM_STORE:
        // Not all request sizes are valid for all memory operations, but I
        // ignore that.
        switch (log2_size) {
          case 0: memory.write8(address, (uint8_t)data); break;
          case 1: memory.write16(address, (uint16_t)data); break;
          case 2: memory.write32(address, (uint32_t)data); break;
          case 3: memory.write64(address, data); break;
          default:
            MUNTJAC_ERROR << "Unsupported memory request size: " << log2_size << endl;
            exit(1);
            break;
        }
        clear_reservation(address);
        break;

      default:
        MUNTJAC_ERROR << "Unsupported memory operation: " << (int)operation << endl;
        exit(1);
        break;
    }
  }

  // Do the minimum possible to support load-reserved/store-conditional.
  // Maintain a single reserved address, and clear it whenever any memory is
  // written.
  // Better performance is possible, but if you're using a simulated d-cache,
  // you probably don't care about performance.
  MemoryAddress reserved;
  bool reservation_valid;

  void make_reservation(MemoryAddress address) {
    reserved = address;
    reservation_valid = true;
  }
  bool check_reservation(MemoryAddress address) {
    return reservation_valid && (reserved == address);
  }
  void clear_reservation(MemoryAddress address) {
    clear_all_reservations();
  }
  void clear_all_reservations() {
    reservation_valid = false;
  }

  DUT& dut;
  PageTableWalkerSv39 page_table_walker;

  // The current pipeline does not check this signal until the cycle after it
  // requests a flush. Add an artificial delay.
  bool delayed_notif_ready;
};

#endif  // DATA_CACHE_PORT_H
