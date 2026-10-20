#!/usr/bin/env python3
import json
import subprocess
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

import rv32i_asm as a
from rv32i_ref import Machine, Trap, load_hex


class EncodingTests(unittest.TestCase):
    def test_known_encodings(self):
        self.assertEqual(a.ADDI(1, 0, 1), 0x00100093)
        self.assertEqual(a.ADD(3, 1, 2), 0x002081B3)
        self.assertEqual(a.SUB(3, 1, 2), 0x402081B3)
        self.assertEqual(a.EBREAK, 0x00100073)

    def test_immediate_range_checks(self):
        with self.assertRaises(ValueError):
            a.ADDI(1, 0, 2048)
        with self.assertRaises(ValueError):
            a.JAL(1, 3)


class ProgramTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        subprocess.run([sys.executable, str(ROOT / "scripts" / "gen_programs.py")], check=True)

    def test_smoke_reference_and_signature(self):
        program_dir = ROOT / "dv" / "programs"
        machine = Machine(load_hex(program_dir / "rv32i_smoke.hex"))
        machine.run()
        manifest = json.loads((program_dir / "manifest.json").read_text())
        actual = [int.from_bytes(machine.mem[0x400 + 4*i:0x404 + 4*i], "little") for i in range(64)]
        expected = load_hex(program_dir / "rv32i_smoke_expected.hex")
        self.assertEqual(actual, expected)
        self.assertEqual(actual[0], 0x600D600D)
        self.assertEqual(set(manifest["coverage"]), machine.coverage)
        self.assertEqual(machine.regs[0], 0)

    def test_terminal_traps(self):
        program_dir = ROOT / "dv" / "programs"
        manifest = json.loads((program_dir / "manifest.json").read_text())
        for name, expected_cause in manifest["trap_tests"].items():
            if name.endswith("access_fault"):
                continue
            with self.subTest(name=name):
                machine = Machine(load_hex(program_dir / f"{name}.hex"))
                with self.assertRaises(Trap) as caught:
                    machine.run()
                self.assertEqual(caught.exception.cause, expected_cause)


if __name__ == "__main__":
    unittest.main(verbosity=2)
