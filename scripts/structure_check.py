#!/usr/bin/env python3
"""Fast, dependency-free repository completeness checks."""

from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]

REQUIRED = [
    "README.md", "LICENSE", "Makefile", ".github/workflows/rtl-regression.yml",
    "rtl/rv32i_pkg.sv", "rtl/rv32i_core.sv",
    "dv/tb/rv32i_core_tb.sv", "dv/sva/rv32i_core_sva.sv",
    "dv/coverage/rv32i_isa_coverage.sv", "dv/filelists/portable.f",
    "dv/filelists/uvm.f", "dv/uvm/rv32i_uvm_top.sv",
    "dv/programs/rv32i_smoke.hex", "dv/programs/rv32i_smoke_expected.hex",
    "dv/programs/manifest.json", "tools/rv32i_asm.py", "tools/rv32i_ref.py",
    "tests/test_reference.py", "docs/specification.md",
    "docs/microarchitecture.md", "docs/verification_plan.md",
    "docs/verification_report.md", "docs/interview_guide.md",
    "assets/architecture.svg", "assets/waveform.svg",
    "results/expected_output.txt", "requirements-ci.txt",
    "scripts/uvm_syntax_check.py",
]

missing = [path for path in REQUIRED if not (ROOT / path).is_file()]
if missing:
    raise SystemExit("MISSING: " + ", ".join(missing))

manifest = json.loads((ROOT / "dv/programs/manifest.json").read_text())
if manifest.get("smoke_program_words") != 261:
    raise SystemExit(f"unexpected smoke word count: {manifest.get('smoke_program_words')}")
if len(manifest.get("coverage", [])) != 39:
    raise SystemExit(f"unexpected coverage-tag count: {len(manifest.get('coverage', []))}")

portable = (ROOT / "dv/filelists/portable.f").read_text()
for unit in ("rtl/rv32i_pkg.sv", "rtl/rv32i_core.sv",
             "dv/sva/rv32i_core_sva.sv", "dv/tb/rv32i_core_tb.sv"):
    if unit not in portable:
        raise SystemExit(f"portable file list omits {unit}")

uvm = (ROOT / "dv/filelists/uvm.f").read_text()
for marker in ("rv32i_mem_pkg.sv", "rv32i_env_pkg.sv",
               "rv32i_isa_coverage.sv", "rv32i_uvm_top.sv"):
    if marker not in uvm:
        raise SystemExit(f"UVM file list omits {marker}")

print(f"STRUCTURE_PASS files={len(REQUIRED)} program_words=261 coverage_tags=39")

