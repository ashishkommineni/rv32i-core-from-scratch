"""Tiny dependency-free RV32I encoder used by the repository tests.

This is deliberately an encoder, not a replacement for a production assembler.
It makes the directed programs reproducible on machines without a RISC-V GNU
toolchain.  Every helper range-checks its immediate before packing fields.
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Callable


def _check_reg(reg: int) -> None:
    if not 0 <= reg < 32:
        raise ValueError(f"register x{reg} is outside x0..x31")


def _check_signed(value: int, bits: int, alignment: int = 1) -> None:
    if value % alignment:
        raise ValueError(f"immediate {value} must be aligned to {alignment}")
    lo, hi = -(1 << (bits - 1)), (1 << (bits - 1)) - 1
    if not lo <= value <= hi:
        raise ValueError(f"immediate {value} does not fit signed {bits} bits")


def r_type(f7: int, rs2: int, rs1: int, f3: int, rd: int, opcode: int = 0x33) -> int:
    for reg in (rd, rs1, rs2):
        _check_reg(reg)
    return ((f7 & 0x7F) << 25) | (rs2 << 20) | (rs1 << 15) | ((f3 & 7) << 12) | (rd << 7) | opcode


def i_type(imm: int, rs1: int, f3: int, rd: int, opcode: int = 0x13) -> int:
    _check_signed(imm, 12)
    for reg in (rd, rs1):
        _check_reg(reg)
    return ((imm & 0xFFF) << 20) | (rs1 << 15) | ((f3 & 7) << 12) | (rd << 7) | opcode


def shift_i(f7: int, shamt: int, rs1: int, f3: int, rd: int) -> int:
    if not 0 <= shamt < 32:
        raise ValueError("RV32 shift amount must be in 0..31")
    return r_type(f7, shamt, rs1, f3, rd, 0x13)


def s_type(imm: int, rs2: int, rs1: int, f3: int) -> int:
    _check_signed(imm, 12)
    for reg in (rs1, rs2):
        _check_reg(reg)
    value = imm & 0xFFF
    return ((value >> 5) << 25) | (rs2 << 20) | (rs1 << 15) | ((f3 & 7) << 12) | ((value & 0x1F) << 7) | 0x23


def b_type(offset: int, rs2: int, rs1: int, f3: int) -> int:
    _check_signed(offset, 13, 2)
    for reg in (rs1, rs2):
        _check_reg(reg)
    value = offset & 0x1FFF
    return (((value >> 12) & 1) << 31) | (((value >> 5) & 0x3F) << 25) | (rs2 << 20) | (rs1 << 15) | ((f3 & 7) << 12) | (((value >> 1) & 0xF) << 8) | (((value >> 11) & 1) << 7) | 0x63


def u_type(value: int, rd: int, opcode: int) -> int:
    _check_reg(rd)
    return (value & 0xFFFFF000) | (rd << 7) | opcode


def j_type(offset: int, rd: int) -> int:
    _check_signed(offset, 21, 2)
    _check_reg(rd)
    value = offset & 0x1FFFFF
    return (((value >> 20) & 1) << 31) | (((value >> 1) & 0x3FF) << 21) | (((value >> 11) & 1) << 20) | (((value >> 12) & 0xFF) << 12) | (rd << 7) | 0x6F


# Integer-register ALU operations.
ADD  = lambda rd, rs1, rs2: r_type(0x00, rs2, rs1, 0, rd)
SUB  = lambda rd, rs1, rs2: r_type(0x20, rs2, rs1, 0, rd)
SLL  = lambda rd, rs1, rs2: r_type(0x00, rs2, rs1, 1, rd)
SLT  = lambda rd, rs1, rs2: r_type(0x00, rs2, rs1, 2, rd)
SLTU = lambda rd, rs1, rs2: r_type(0x00, rs2, rs1, 3, rd)
XOR  = lambda rd, rs1, rs2: r_type(0x00, rs2, rs1, 4, rd)
SRL  = lambda rd, rs1, rs2: r_type(0x00, rs2, rs1, 5, rd)
SRA  = lambda rd, rs1, rs2: r_type(0x20, rs2, rs1, 5, rd)
OR   = lambda rd, rs1, rs2: r_type(0x00, rs2, rs1, 6, rd)
AND  = lambda rd, rs1, rs2: r_type(0x00, rs2, rs1, 7, rd)

ADDI  = lambda rd, rs1, imm: i_type(imm, rs1, 0, rd)
SLTI  = lambda rd, rs1, imm: i_type(imm, rs1, 2, rd)
SLTIU = lambda rd, rs1, imm: i_type(imm, rs1, 3, rd)
XORI  = lambda rd, rs1, imm: i_type(imm, rs1, 4, rd)
ORI   = lambda rd, rs1, imm: i_type(imm, rs1, 6, rd)
ANDI  = lambda rd, rs1, imm: i_type(imm, rs1, 7, rd)
SLLI  = lambda rd, rs1, shamt: shift_i(0x00, shamt, rs1, 1, rd)
SRLI  = lambda rd, rs1, shamt: shift_i(0x00, shamt, rs1, 5, rd)
SRAI  = lambda rd, rs1, shamt: shift_i(0x20, shamt, rs1, 5, rd)

LB  = lambda rd, rs1, imm: i_type(imm, rs1, 0, rd, 0x03)
LH  = lambda rd, rs1, imm: i_type(imm, rs1, 1, rd, 0x03)
LW  = lambda rd, rs1, imm: i_type(imm, rs1, 2, rd, 0x03)
LBU = lambda rd, rs1, imm: i_type(imm, rs1, 4, rd, 0x03)
LHU = lambda rd, rs1, imm: i_type(imm, rs1, 5, rd, 0x03)
SB  = lambda rs2, rs1, imm: s_type(imm, rs2, rs1, 0)
SH  = lambda rs2, rs1, imm: s_type(imm, rs2, rs1, 1)
SW  = lambda rs2, rs1, imm: s_type(imm, rs2, rs1, 2)

BEQ  = lambda rs1, rs2, off: b_type(off, rs2, rs1, 0)
BNE  = lambda rs1, rs2, off: b_type(off, rs2, rs1, 1)
BLT  = lambda rs1, rs2, off: b_type(off, rs2, rs1, 4)
BGE  = lambda rs1, rs2, off: b_type(off, rs2, rs1, 5)
BLTU = lambda rs1, rs2, off: b_type(off, rs2, rs1, 6)
BGEU = lambda rs1, rs2, off: b_type(off, rs2, rs1, 7)

LUI   = lambda rd, value: u_type(value, rd, 0x37)
AUIPC = lambda rd, value: u_type(value, rd, 0x17)
JAL   = lambda rd, off: j_type(off, rd)
JALR  = lambda rd, rs1, imm: i_type(imm, rs1, 0, rd, 0x67)

FENCE  = 0x0000000F
ECALL  = 0x00000073
EBREAK = 0x00100073
NOP    = ADDI(0, 0, 0)


@dataclass
class Fixup:
    index: int
    label: str
    encoder: Callable[[int], int]


class Program:
    """Small label-aware builder. Addresses are byte addresses."""

    def __init__(self) -> None:
        self.words: list[int] = []
        self.labels: dict[str, int] = {}
        self.fixups: list[Fixup] = []

    @property
    def pc(self) -> int:
        return len(self.words) * 4

    def emit(self, word: int) -> None:
        self.words.append(word & 0xFFFFFFFF)

    def label(self, name: str) -> None:
        if name in self.labels:
            raise ValueError(f"duplicate label {name}")
        self.labels[name] = self.pc

    def branch(self, label: str, encoder: Callable[[int], int]) -> None:
        self.fixups.append(Fixup(len(self.words), label, encoder))
        self.emit(0)

    def jal(self, rd: int, label: str) -> None:
        self.branch(label, lambda off: JAL(rd, off))

    def li(self, rd: int, value: int) -> None:
        value &= 0xFFFFFFFF
        signed = value if value < 0x80000000 else value - 0x100000000
        if -2048 <= signed <= 2047:
            self.emit(ADDI(rd, 0, signed))
            return
        upper = (value + 0x800) & 0xFFFFF000
        lower = ((value - upper) + 0x80000000) % 0x100000000 - 0x80000000
        self.emit(LUI(rd, upper))
        self.emit(ADDI(rd, rd, lower))

    def resolve(self) -> list[int]:
        words = list(self.words)
        for fix in self.fixups:
            if fix.label not in self.labels:
                raise ValueError(f"undefined label {fix.label}")
            origin = fix.index * 4
            words[fix.index] = fix.encoder(self.labels[fix.label] - origin)
        return words


def write_hex(path: str, words: list[int]) -> None:
    with open(path, "w", encoding="ascii") as handle:
        for word in words:
            handle.write(f"{word & 0xFFFFFFFF:08x}\n")
