# Microarchitecture Walkthrough

## Datapath

The datapath contains a 32-word register file, PC, instruction register,
immediate generators, combinational ALU/compare logic, and registers that hold a
pending data transaction. No pipeline bypass or hazard logic is needed because
only one instruction is active.

## Control

The FSM separates every externally backpressured action:

1. `ST_FETCH_REQ` keeps the instruction address valid.
2. `ST_FETCH_RSP` waits for the returned word or an access error.
3. `ST_EXECUTE` performs register-only instructions in one cycle, checks traps,
   or captures a load/store request.
4. `ST_DMEM_REQ` holds the complete data payload.
5. `ST_DMEM_RSP` commits a successful load/store or raises an access fault.

This separation ensures that a late response cannot be confused with a new
request and makes handshake assertions simple.

## Immediate construction

I-, S-, B-, U-, and J-type immediates are assembled directly from the
instruction fields and sign-extended to 32 bits. B and J immediates append the
implicit low zero bit. JALR clears target bit 0 and then applies the four-byte
alignment rule used by this RV32I-only implementation.

## Memory lanes

The external data address is word aligned. A byte store shifts its source by
`8*offset` and asserts one strobe lane. A halfword store shifts by bit 1 and
asserts `0011` or `1100`. Loads shift the returned word by the saved byte offset
before sign or zero extension.

## Precision of traps

No destination register, memory request, or retirement is committed for an
illegal or misaligned operation. A response error is detected after the request
has completed, but the instruction still does not retire. The stored instruction
PC and original offset preserve precise `trap_pc` and `trap_value` metadata.

