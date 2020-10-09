# Pipeline to instruction cache interface

This interface allows the pipeline to fetch instructions from the instruction cache.

There are no flow control signals. The cache is expected to process only one request at a time, and the output must be consumed immediately.

All `valid` signals should remain high for at most one clock cycle per request/response.

## Pipeline to instruction cache

| Signal | Type | Description |
| --- | --- | --- |
| `req_valid` | Boolean | Whether the request is valid. |
| `req_pc` | 64 bits | Memory address to be accessed. The cache will round this address down to the nearest 4-byte boundary, with the pipeline expected to extract the portion of the response that it needs. |
| `req_reason` | `if_reason_e` | Reason for accessing instruction cache. ([Available options](#if_reason_e)) |
| `req_prv` | Boolean | Whether the core was in Supervisor mode at the time of the most recent non-speculative instruction fetch. |
| `req_sum` | Boolean | The value of the MSTATUS control register's SUM bit (permit Supervisor User Memory access) at the time of the most recent non-speculative instruction fetch. |
| `req_atp` | 64 bits | The value of the ATP (Address Translation and Protection) control register at the time of the most recent non-speculative instruction fetch. |

## Instruction cache to pipeline

| Signal | Type | Description |
| --- | --- | --- |
| `resp_valid` | Boolean | Whether the response is valid. |
| `resp_instr` | 32 bits | Response instruction. |
| `resp_exception` | Boolean | Whether there was an exception when accessing the instruction. |
| `resp_ex_code` | `exc_cause_e` | The type of exception. ([Available options](#exc_cause_e)) |

## `if_reason_e`
Reasons for an instruction fetch taking place.

| Value | Description |
| --- | --- |
| `IF_PREFETCH` | An instruction prefetch that follows the previous instruction in program counter order. |
| `IF_PREDICT` | An instruction prefetch commanded by the branch predictor. |
| `IF_MISPREDICT` | An instruction fetch caused by misprediction. |
| `IF_PROT_CHANGED` | Memory protection bits, e.g. `MSTATUS`, `PRV` or `SATP` has been changed. |
| `IF_SATP_CHANGED` | The SATP (Supervisor Address Translation and Protection) control register has been changed. |
| `IF_FENCE_I` | The `FENCE.I` instruction was executed. |
| `IF_SFENCE_VMA` | The `SFENCE.VMA` instruction was executed. |

## `exc_cause_e`
Reasons for an exception taking place. More options are available; these are the ones relevant to the instruction cache.

| Value | Description |
| --- | --- |
| `EXC_CAUSE_INSTR_ACCESS_FAULT` | Insufficient permissions. |
| `EXC_CAUSE_INSTR_PAGE_FAULT` | Page fault. |
