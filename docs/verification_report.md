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

### Simulator-dependent evidence

The GitHub Actions workflow installs Verilator, executes `make regress`, and
therefore provides the authoritative public portable-RTL result for its commit.
The exact run status and logs should be read from the commit check; this document
does not hard-code a result that could become stale.

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

