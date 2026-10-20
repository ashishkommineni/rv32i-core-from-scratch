# Verification Report

## Evidence classes

This project keeps executable evidence separate from prepared-but-unexecuted
flows.

### Environment-independent evidence

- `scripts/gen_programs.py` deterministically regenerates all program images,
  the expected signature, and `manifest.json`.
- `tests/test_reference.py` checks instruction encodings, immediate range
  rejection, the 261-word smoke program, 39 required coverage tags, and all
  terminal programs with the independent interpreter.
- `scripts/structure_check.py` checks the expected repository, RTL, DV, program,
  documentation, diagram, workflow, and license files.
- `scripts/uvm_syntax_check.py` parses every UVM/interface/coverage/top source
  unit with pinned `pyslang` 12.0.0. This is a syntax gate, not a UVM run.

### Simulator-dependent evidence

The GitHub Actions workflow installs Verilator and executes `make regress`.
Public [run 39377134405](https://github.com/ashishkommineni/rv32i-core-from-scratch/actions/runs/39377134405)
completed successfully on 2026-10-20 with Verilator 5.020. It checked the
generated reference data, elaborated the bound assertions, ran the complete
smoke signature, and ran all eight terminal cases.

```text
TEST_PASS name=smoke cycles=1666 retired=248 cause=3
TEST_PASS name=illegal cycles=6 retired=0 cause=2
TEST_PASS name=instr_misaligned cycles=6 retired=0 cause=0
TEST_PASS name=load_misaligned cycles=10 retired=1 cause=4
TEST_PASS name=store_misaligned cycles=10 retired=1 cause=6
TEST_PASS name=ecall cycles=6 retired=0 cause=11
TEST_PASS name=imem_access_fault cycles=5 retired=0 cause=1
TEST_PASS name=load_access_fault cycles=12 retired=0 cause=5
TEST_PASS name=store_access_fault cycles=12 retired=0 cause=7
```

The cycle and retirement counts are captured evidence for this generated image
and memory-latency model; they are not fixed microarchitectural guarantees.

The Xcelium UVM targets are source-complete but require Cadence Xcelium and UVM
1.2. A future signed-off run should archive:

- Xcelium version and command line;
- Git commit and random seed;
- UVM report summary with zero errors/fatals;
- assertion summary;
- IMC code and functional coverage reports;
- waived/excluded bins with rationale.

Until those artifacts exist, this repository makes no Xcelium-pass or UVM
coverage-percentage claim.

## Expected portable tests

| Test | Expected terminal behavior |
|---|---|
| `smoke` | host halt, signature match, all portable coverage gates pass |
| `illegal` | trap cause 2 |
| `instr_misaligned` | trap cause 0 |
| `load_misaligned` | trap cause 4 |
| `store_misaligned` | trap cause 6 |
| `ecall` | trap cause 11 |
| `imem_access_fault` | trap cause 1 |
| `load_access_fault` | trap cause 5 |
| `store_access_fault` | trap cause 7 |

