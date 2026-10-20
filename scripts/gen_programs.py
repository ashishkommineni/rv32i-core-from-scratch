#!/usr/bin/env python3
"""Generate deterministic directed RV32I programs and the golden signature."""
from __future__ import annotations

import json
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))

import rv32i_asm as a  # noqa: E402
from rv32i_ref import Machine  # noqa: E402


PROGRAM_DIR = ROOT / "dv" / "programs"
SIGNATURE_BASE = 0x400
SIGNATURE_WORDS = 64


def make_smoke() -> tuple[list[int], list[int], set[str]]:
    p = a.Program()
    sig_index = 1

    def save(reg: int) -> None:
        nonlocal sig_index
        p.emit(a.SW(reg, 1, sig_index * 4))
        sig_index += 1

    p.li(1, SIGNATURE_BASE)
    p.li(2, 0x80000005)
    p.li(3, 3)

    register_ops = [a.ADD, a.SUB, a.SLL, a.SLT, a.SLTU, a.XOR, a.SRL, a.SRA, a.OR, a.AND]
    for operation in register_ops:
        p.emit(operation(4, 2, 3))
        save(4)

    immediate_ops = [
        a.ADDI(4, 2, -7), a.SLTI(4, 2, 0), a.SLTIU(4, 3, 5),
        a.XORI(4, 2, -1), a.ORI(4, 3, 0x120), a.ANDI(4, 2, 0x7F),
        a.SLLI(4, 3, 7), a.SRLI(4, 2, 4), a.SRAI(4, 2, 4),
    ]
    for instruction in immediate_ops:
        p.emit(instruction)
        save(4)

    p.emit(a.LUI(4, 0x12345000))
    save(4)
    p.emit(a.AUIPC(4, 0x00001000))
    save(4)

    # Byte/half/word stores and signed/unsigned loads.
    p.li(10, 0x600)
    p.li(11, 0x80FF7F01)
    p.emit(a.SW(11, 10, 0))
    for instruction in (
        a.LB(4, 10, 0), a.LB(4, 10, 2), a.LBU(4, 10, 2),
        a.LH(4, 10, 0), a.LH(4, 10, 2), a.LHU(4, 10, 2), a.LW(4, 10, 0),
    ):
        p.emit(instruction)
        save(4)
    p.li(12, 0xAA)
    p.emit(a.SB(12, 10, 1))
    p.emit(a.LW(4, 10, 0))
    save(4)
    p.li(13, 0x55CC)
    p.emit(a.SH(13, 10, 2))
    p.emit(a.LW(4, 10, 0))
    save(4)

    branch_cases = [
        ("beq_t", a.BEQ, 7, 7, True), ("beq_n", a.BEQ, 7, 8, False),
        ("bne_t", a.BNE, 7, 8, True), ("bne_n", a.BNE, 7, 7, False),
        ("blt_t", a.BLT, -2, 1, True), ("blt_n", a.BLT, 2, 1, False),
        ("bge_t", a.BGE, 2, -1, True), ("bge_n", a.BGE, -2, 1, False),
        ("bltu_t", a.BLTU, 1, 2, True), ("bltu_n", a.BLTU, -1, 2, False),
        ("bgeu_t", a.BGEU, -1, 2, True), ("bgeu_n", a.BGEU, 1, 2, False),
    ]
    for name, encoder, lhs, rhs, should_take in branch_cases:
        p.li(5, lhs)
        p.li(6, rhs)
        p.emit(a.ADDI(7, 0, 1))
        if should_take:
            p.branch(f"{name}_ok", lambda off, enc=encoder: enc(5, 6, off))
            p.emit(a.ADDI(7, 0, 0))
            p.label(f"{name}_ok")
        else:
            p.branch(f"{name}_bad", lambda off, enc=encoder: enc(5, 6, off))
            p.jal(0, f"{name}_done")
            p.label(f"{name}_bad")
            p.emit(a.ADDI(7, 0, 0))
            p.label(f"{name}_done")
        save(7)

    # JAL calls a tiny subroutine; JALR returns to the link address.
    p.emit(a.ADDI(7, 0, 0))
    p.jal(8, "subroutine")
    p.label("after_return")
    save(7)
    save(8)
    p.jal(0, "after_subroutine")
    p.label("subroutine")
    p.emit(a.ADDI(7, 0, 1))
    p.emit(a.JALR(0, 8, 0))
    p.label("after_subroutine")

    p.emit(a.FENCE)
    p.emit(a.ADDI(0, 0, 123))
    save(0)

    # Reproducible arithmetic stress. The golden model computes the signatures.
    rng = random.Random(0x52563332)
    random_ops = register_ops + register_ops[:6]
    for operation in random_ops:
        p.li(14, rng.getrandbits(32))
        p.li(15, rng.getrandbits(32))
        p.emit(operation(16, 14, 15))
        save(16)

    if sig_index >= SIGNATURE_WORDS:
        raise RuntimeError("signature region is too small")
    p.li(17, 0x600D600D)
    p.emit(a.SW(17, 1, 0))
    p.emit(a.EBREAK)

    words = p.resolve()
    machine = Machine(words)
    machine.run()
    signature = [int.from_bytes(machine.mem[SIGNATURE_BASE + 4*i:SIGNATURE_BASE + 4*i + 4], "little") for i in range(SIGNATURE_WORDS)]
    required = {
        "lui", "auipc", "jal", "jalr", "beq", "bne", "blt", "bge", "bltu", "bgeu",
        "lb", "lh", "lw", "lbu", "lhu", "sb", "sh", "sw", "addi", "slti", "sltiu",
        "xori", "ori", "andi", "slli", "srli", "srai", "add", "sub", "sll", "slt",
        "sltu", "xor", "srl", "sra", "or", "and", "fence", "ebreak",
    }
    missing = required - machine.coverage
    if missing:
        raise RuntimeError(f"generator coverage hole: {sorted(missing)}")
    return words, signature, machine.coverage


def main() -> None:
    PROGRAM_DIR.mkdir(parents=True, exist_ok=True)
    words, signature, coverage = make_smoke()
    a.write_hex(str(PROGRAM_DIR / "rv32i_smoke.hex"), words)
    a.write_hex(str(PROGRAM_DIR / "rv32i_smoke_expected.hex"), signature)

    traps = {
        "illegal": ([0xFFFFFFFF], 2),
        "instr_misaligned": ([a.JAL(0, 2)], 0),
        "load_misaligned": ([a.ADDI(1, 0, 1), a.LW(2, 1, 0)], 4),
        "store_misaligned": ([a.ADDI(1, 0, 2), a.SW(2, 1, 0)], 6),
        "ecall": ([a.ECALL], 11),
        # The bus model injects the access faults for these legal requests.
        "imem_access_fault": ([a.EBREAK], 1),
        "load_access_fault": ([a.LW(2, 0, 0), a.EBREAK], 5),
        "store_access_fault": ([a.SW(0, 0, 0), a.EBREAK], 7),
    }
    for name, (program, _) in traps.items():
        a.write_hex(str(PROGRAM_DIR / f"{name}.hex"), program)

    manifest = {
        "generator_seed": "0x52563332",
        "signature_base": SIGNATURE_BASE,
        "signature_words": SIGNATURE_WORDS,
        "smoke_program_words": len(words),
        "coverage": sorted(coverage),
        "trap_tests": {name: cause for name, (_, cause) in traps.items()},
    }
    (PROGRAM_DIR / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    print(f"GENERATE_PASS words={len(words)} coverage={len(coverage)}")


if __name__ == "__main__":
    main()
