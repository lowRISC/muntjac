# Front-end to back-end interface

The front-end is responsible for fetching instructions and the back-end is responsible for executing them. This interface ensures that the back-end has instructions to execute and that the front-end is aware of any control flow in the program.

## Front-end to back-end

| Signal | Type | Description |
| --- | --- | --- |
| `fetch_valid` | Boolean | Whether `fetch_instr` is valid. |
| `fetch_instr` | `fetched_instr_t` | The instruction to execute. ([More details](#fetched_instr_t)) |

## Back-end to front-end

| Signal | Type | Description |
| --- | --- | --- |
| `satp` | 64 bits | The value of the SATP (Supervisor Address Translation and Protection) control register. |
| `prv` | `priv_lvl_e` | The current privilege level. ([Available options](#priv_lvl_e)) |
| `status` | `status_t` | A collection of relevant information from the control registers. ([More details](#status_t)) |
| `redirect_valid` | Boolean | Whether a redirection (e.g. branch, jump) is currently being requested. |
| `redirect_reason` | `if_reason_e` | The reason for the requested redirection. ([Available options](#if_reason_e)) |
| `redirect_pc` | 64 bits | The new memory address to begin fetching instructions from. |
| `branch_info` | `branch_info_t` | Non-speculative information about executed branches, used (for example) to update the branch predictor. ([More details](#branch_info_t)) |
| `fetch_ready` | Boolean | Whether the back-end is ready to receive a new instruction. |

### `fetched_instr_t`
A fetched instruction and relevant metadata. A compound type consisting of:

| Field | Type | Description |
| --- | --- | --- |
| `pc` | 64 bits | Program counter. |
| `if_reason` | `if_reason_e` | Reason why the instruction was fetched (i.e. was it speculative?). ([Available options](#if_reason_e)) |
| `instr_word` | 32 bits | The instruction that was fetched. |
| `ex_valid` | Boolean | Whether an exception occurred during instruction fetch. |
| `exception` | `exception_t` | Further information on the exception. ([More details](#exception_t)) |

### `if_reason_e`
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

### `exception_t`
Information about an exception. A compound type consisting of:

| Field | Type | Description |
| --- | --- | --- |
| `cause` | `exc_cause_e` | The cause of the exception. The only possible instruction fetch exceptions in Muntjac are `EXC_CAUSE_INSTR_PAGE_FAULT` and `EXC_CAUSE_INSTR_ACCESS_FAULT`. |
| `tval` | 64 bits | Address being accessed when the exception occurred. |


### `priv_lvl_e`
Privilege levels.

| Value | Description |
| --- | --- |
| `PRIV_LVL_M` | Machine mode. |
| `PRIV_LVL_H` | Hypervisor mode. |
| `PRIV_LVL_S` | Supervisor mode. |
| `PRIV_LVL_U` | User mode. |

### `status_t`
A collection of information from the control registers consisting of:

| Field | Type | Description |
| --- | --- | --- |
| `tsr` | Boolean | The MSTATUS TSR bit (Trap Supervisor Return). |
| `tw` | Boolean | The MSTATUS TW bit (Timeout Wait). |
| `tvm` | Boolean | The MSTATUS TVM bit (Trap Virtual Memory). |
| `mxr` | Boolean | The MSTATUS MXR bit (Make eXecutable Readable). |
| `sum` | Boolean | The MSTATUS SUM bit (permit Supervisor User Memory access). |
| `mprv` | Boolean | The MSTATUS MPRV bit (Modify PRiVilege). |
| `fs` | 2 bits | The MSTATUS FS bits (Floating-point State). |
| `mpp` | `priv_lvl_e` | The MSTATUS MPP bits (Machine mode Previous Privilege). |
| `spp` | Boolean | The MSTATUS SPP bit (Supervisor mode Previous Privilege). |
| `mpie` | Boolean | The MSTATUS MPIE bit (Machine mode Previous Interrupt-Enable). |
| `spie` | Boolean | The MSTATUS SPIE bit (Supervisor mode Previous Interrupt-Enable). |
| `mie` | Boolean | The MSTATUS MIE bit (Machine mode Interrupt-Enable). |
| `sie` | Boolean | The MSTATUS SIE bit (Supervisor mode Interrupt-Enable). |

### `branch_info_t`
Information about a branch operation. A compound type consisting of:

| Field | Type | Description |
| --- | --- | --- |
| `branch_type` | `branch_type_e` | The type of branch. ([Available options](#branch_type_e)) |
| `pc` | 64 bits | The address of the branch instruction (*not* the address being branched to). |
| `compressed` | Boolean | Whether the branch instruction is compressed. |

### `branch_type_e`
Types of branch operation.

| Value | Description |
| --- | --- |
| `BRANCH_NONE` | Not a branch instruction. |
| `BRANCH_UNTAKEN` | Branch not taken. |
| `BRANCH_TAKEN` | Branch taken. |
| `BRANCH_JUMP` | Unconditional jump. |
| `BRANCH_CALL` | Environment call: request additional privilege. |
| `BRANCH_RET` | Environment return: return to previous privilege. |
| `BRANCH_YIELD` | Voluntarily yield control of the core and trigger a thread switch. |
