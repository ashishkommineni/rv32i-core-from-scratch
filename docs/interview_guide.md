# Interview Guide

## 1. Why use a multicycle core?

It makes state changes and bus obligations explicit. The design reuses one ALU,
has no data/control hazards, and can be verified instruction by instruction. The
trade-off is low throughput: even an ALU instruction needs separate fetch and
execute phases.

## 2. How is backpressure handled?

The request state cannot advance until `valid && ready`. All payload registers
remain unchanged during that wait. After acceptance, the FSM moves to a distinct
response state, so the same operation cannot be issued twice.

## 3. Why align the external data address?

The memory port returns a 32-bit word. The original low address bits are saved
for byte/halfword extraction, and write strobes select the target lanes. This
keeps the bus contract word-oriented while preserving RV32I byte addressing.

## 4. What makes a trap precise here?

`trap_pc` identifies the unretired instruction, `trap_value` carries the bad
target/address/instruction, and no destination write or retirement occurs. With
one instruction in flight, there are no younger instructions to flush.

## 5. Why is x0 checked twice?

Decode suppresses visible writes to x0, and sequential logic forces the storage
entry to zero. SVA checks internal storage while the retirement contract checks
that an encoded x0 destination reports zero data.

## 6. How would you pipeline it?

Add stage registers and valid/kill state; forwarding for EX/MEM and MEM/WB
dependencies; a load-use stall; branch resolution and flush; and tags that keep
request/response data associated with the correct instruction. The retirement
interface should remain the architectural verification boundary.

## 7. Is this core RISC-V compliant?

It implements and checks the listed RV32I behavior, but it has not run the
official architectural certification suite and lacks privileged architecture.
The accurate claim is “RV32I educational implementation,” not “certified core.”

## 8. Why is EBREAK not a normal trap?

The test harness needs a deterministic success stop. This project routes EBREAK
to a separately documented host-halt state, while ECALL and faults use the trap
interface. A production core should implement architectural breakpoint trap
entry and debug behavior.

## 9. What does the UVM scoreboard predict?

It consumes completed fetch and data transactions plus the retirement stream.
It reconstructs registers and next PC, recomputes each instruction result, checks
load/store lanes, and verifies terminal metadata. It does not peek at the DUT
register file to decide correctness.

## 10. What would you add next?

First add machine CSRs, `mtvec` trap entry, external/timer/software interrupts,
and `MRET`. Then run official architectural tests and formal instruction-property
checks. Performance work—pipelining, caches, and prediction—should come only
after the architectural boundary remains measurable.

