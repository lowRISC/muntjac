# Pipeline to data cache interface

This interface allows the pipeline to read and write information to the data cache.

Every request **must** receive a response, even if that response is only "the request completed without triggering an exception".

## Pipeline to data cache

| Signal | Type | Description |
| --- | --- | --- |
| `req_valid` | Boolean | Whether the request is valid. |
| `req_address` | 64 bits | Memory address to be accessed. |
| `req_value` | 64 bits | Value to be stored or used in atomic operations. |
| `req_op` | `mem_op_e` | Type of memory operation. ([Available options](#mem_op_e)) |
| `req_size` | 2 bits | log2(bytes to access). Not all request sizes are compatible with all request operations. |
| `req_unsigned` | Boolean | Whether `MEM_LOAD` operations are unsigned. Unused for all other operation types. |
| `req_amo` | 7 bits | When `req_op` is `MEM_AMO`, this dictates the type and ordering requirements of the operation. TODO: more detail - create a new `struct`+`enum` for AMOs? |
| `req_prv` | Boolean | Whether the core is in Supervisor mode. |
| `req_sum` | Boolean | The value of the MSTATUS control register's SUM bit (permit Supervisor User Memory access). |
| `req_mxr` | Boolean | The value of the MSTATUS control register's MXR bit (Make eXecutable Readable). |
| `req_atp` | 64 bits | The value of the ATP (Address Translation and Protection) control register. |
| `notif_valid` | Boolean | Whether a fence is being requested. |
| `notif_reason` | 1 bit | Reason for requesting a fence. 0: SATP bits changed; 1: `SFENCE.VMA` instruction executed. |

## Data cache to pipeline

| Signal | Type | Description |
| --- | --- | --- |
| `req_ready` | Boolean | Whether the cache is ready to receive a new request. |
| `resp_valid` | Boolean | Whether the response is valid. |
| `resp_value` | 64 bits | Response data. |
| `ex_valid` | Boolean | Whether there was an exception when performing the operation. |
| `ex_exception` | `exception_t` | Information about exception. ([More details](#exception_t)) |
| `notif_ready` | Boolean | Whether the requested fence operation has completed. |

## `mem_op_e`
Types of memory operation.

| Value | Description |
| --- | --- |
| `MEM_LOAD` | Load data. |
| `MEM_STORE` | Store data. |
| `MEM_LR` | Load reserved. |
| `MEM_SC` | Store conditional. |
| `MEM_AMO` | Atomic memory operation. |

## `exception_t`
Information about an exception. A compound type consisting of:

| Field | Type | Description |
| --- | --- | --- |
| `cause` | `exc_cause_e` | The cause of the exception. ([Available options](#exc_cause_e)) |
| `tval` | 64 bits | A payload with additional information, usually the address being accessed when the exception occurred. |

## `exc_cause_e`
Reasons for an exception taking place. More options are available; these are the ones relevant to the data cache.

| Value | Description |
| --- | --- |
| `EXC_CAUSE_LOAD_MISALIGN` | Misaligned load. |
| `EXC_CAUSE_LOAD_ACCESS_FAULT` | Insufficient permissions for load. |
| `EXC_CAUSE_STORE_MISALIGN` | Misaligned store. |
| `EXC_CAUSE_STORE_ACCESS_FAULT` | Insufficient permissions for store. |
| `EXC_CAUSE_LOAD_PAGE_FAULT` | Page fault on load. |
| `EXC_CAUSE_STORE_PAGE_FAULT` | Page fault on store. |
