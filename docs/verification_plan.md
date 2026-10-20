# Verification Plan

## Requirements-to-check matrix

| Requirement | Portable check | SVA/UVM check |
|---|---|---|
| Every implemented RV32I operation computes correctly | generated smoke program and signature | retirement scoreboard + ISA covergroups |
| x0 remains zero | signature cases | `ap_x0_storage_is_zero`, trace check |
| Request remains stable under backpressure | variable-latency memories | stable-request assertions |
| Loads/stores select correct byte lanes | directed signature | request coverage and scoreboard |
| Taken/not-taken branches update PC correctly | directed branch matrix | branch outcome cross |
| Misalignment does not issue data traffic | three trap images | terminal scoreboard and alignment assertions |
| Bus errors map to correct causes | three injected-error tests | response/error coverage |
| Illegal instruction and ECALL metadata | directed images | trap cause coverage |
| Terminal states do not retire | every terminal test | terminal assertions |

## Portable regression

The smoke image is generated from instruction encoders and interpreted by a
separate Python model. Its memory signature covers all register ALU operations,
all immediate ALU operations, every legal branch relation, all load extensions,
all store sizes and byte lanes, LUI/AUIPC, JAL/JALR, and FENCE.

Eight single-purpose images validate causes 0, 1, 2, 4, 5, 6, 7, and 11. The
testbench introduces instruction and data wait states, checks the signature,
enforces portable coverage masks, and terminates on the first mismatch.

## UVM architecture

- Active memory agents respond independently on instruction and data ports.
- Monitors publish completed transactions, never raw attempts.
- The trace monitor publishes retire, trap, and host-halt events.
- The scoreboard reconstructs the register file and next PC, matches each
  retirement to its fetch, and matches loads/stores to completed data traffic.
- Functional coverage samples opcodes, function fields, branch outcomes,
  request lanes, stalls, responses, and trap causes.
- Tests check the final memory signature or the selected terminal cause.

## Coverage policy

Portable bitmask gates must cover every implemented OP, OP-IMM, branch, load,
store, and control instruction class in the smoke program. UVM covergroups are
provided for richer simulator coverage. No percentage is claimed until a real
coverage database is generated and reviewed; excluded privileged and extension
instructions are out of scope rather than coverage holes.

