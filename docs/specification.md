# RV32I Core Specification

## Scope

The design implements the unprivileged RV32I integer instructions listed in the
root README with IALIGN=32. It is a single-issue, non-pipelined core with one
outstanding transaction per memory interface and no speculation.

## Reset

`rst_n` is active low. While reset is asserted, request-valid and response-ready
outputs are low, architectural registers are cleared, PC is `RESET_VECTOR`, and
the FSM is initialized to `ST_FETCH_REQ`. `RESET_VECTOR` must be four-byte
aligned. Execution begins after reset deassertion.

## Instruction interface

- The core asserts `imem_req_valid` with an aligned `imem_req_addr`.
- It holds the request address stable until `imem_req_ready` is sampled high.
- After that handshake it deasserts request valid and asserts
  `imem_rsp_ready` in the response phase.
- A response handshake with `imem_rsp_err=1` produces cause 1.
- Only one instruction request can be outstanding.

## Data interface

- Loads and stores present a word-aligned `dmem_req_addr`.
- The original byte offset is retained internally for lane extraction and trap
  metadata.
- `dmem_req_wstrb` is zero for loads and carries one, two, or four active lanes
  for legal stores.
- Request payload is stable until accepted; then the core waits for exactly one
  response.
- A failed response produces cause 5 for loads or cause 7 for stores.

## Register and retirement rules

- `x0` always reads as zero and is forced to zero every active cycle.
- A destination write becomes architecturally visible when the instruction
  retires.
- `retire_valid` is a one-cycle pulse for successfully completed instructions.
- `retire_rd` is zero and `retire_wdata` is zero when no visible destination
  write occurs, including writes encoded to `x0`.
- Trapping instructions and the host-halt `EBREAK` do not retire.

## Alignment

- Instruction fetches and taken control-flow targets must be four-byte aligned.
- Byte accesses accept every byte offset.
- Halfword accesses require address bit 0 to be zero.
- Word accesses require address bits `[1:0]` to be zero.
- A misalignment is detected before any data-bus request is issued.

## Terminal behavior

`ST_TRAP` and `ST_HALT` are sticky until reset. They are mutually exclusive and
neither state emits retirement. `ST_HALT` is a verification convention for
`EBREAK`; all architecturally modeled faults use `ST_TRAP`.

