"""Executable RV32I architectural reference model for repository programs."""
from __future__ import annotations

import argparse
from dataclasses import dataclass, field
from pathlib import Path


MASK32 = 0xFFFFFFFF


def u32(value: int) -> int:
    return value & MASK32


def sext(value: int, bits: int) -> int:
    value &= (1 << bits) - 1
    sign = 1 << (bits - 1)
    return value - (1 << bits) if value & sign else value


def signed(value: int) -> int:
    return sext(value, 32)


class Trap(RuntimeError):
    def __init__(self, cause: int, pc: int, value: int):
        super().__init__(f"trap cause={cause} pc=0x{pc:08x} value=0x{value:08x}")
        self.cause, self.pc, self.value = cause, pc, value


@dataclass
class Machine:
    program: list[int]
    memory_size: int = 4096
    pc: int = 0
    regs: list[int] = field(default_factory=lambda: [0] * 32)
    retired: int = 0
    halted: bool = False
    coverage: set[str] = field(default_factory=set)

    def __post_init__(self) -> None:
        self.mem = bytearray(self.memory_size)

    def _read(self, addr: int, size: int) -> int:
        if addr < 0 or addr + size > len(self.mem):
            raise Trap(5, self.pc, addr)
        return int.from_bytes(self.mem[addr:addr + size], "little")

    def _write(self, addr: int, size: int, value: int) -> None:
        if addr < 0 or addr + size > len(self.mem):
            raise Trap(7, self.pc, addr)
        self.mem[addr:addr + size] = (value & ((1 << (size * 8)) - 1)).to_bytes(size, "little")

    def step(self) -> None:
        if self.pc & 3:
            raise Trap(0, self.pc, self.pc)
        index = self.pc >> 2
        if index >= len(self.program):
            raise Trap(1, self.pc, self.pc)
        insn = self.program[index]
        opcode, rd = insn & 0x7F, (insn >> 7) & 31
        f3, rs1, rs2 = (insn >> 12) & 7, (insn >> 15) & 31, (insn >> 20) & 31
        f7 = (insn >> 25) & 0x7F
        a, b = self.regs[rs1], self.regs[rs2]
        next_pc, result, write_rd = u32(self.pc + 4), 0, False
        imm_i = sext(insn >> 20, 12)
        imm_s = sext(((insn >> 25) << 5) | ((insn >> 7) & 31), 12)
        imm_b = sext((((insn >> 31) & 1) << 12) | (((insn >> 7) & 1) << 11) | (((insn >> 25) & 0x3F) << 5) | (((insn >> 8) & 0xF) << 1), 13)
        imm_j = sext((((insn >> 31) & 1) << 20) | (((insn >> 12) & 0xFF) << 12) | (((insn >> 20) & 1) << 11) | (((insn >> 21) & 0x3FF) << 1), 21)
        name = ""

        if opcode == 0x37:
            name, result, write_rd = "lui", insn & 0xFFFFF000, True
        elif opcode == 0x17:
            name, result, write_rd = "auipc", u32(self.pc + (insn & 0xFFFFF000)), True
        elif opcode == 0x6F:
            name, result, write_rd = "jal", next_pc, True
            next_pc = u32(self.pc + imm_j)
            if next_pc & 3:
                raise Trap(0, self.pc, next_pc)
        elif opcode == 0x67 and f3 == 0:
            name, result, write_rd = "jalr", next_pc, True
            next_pc = u32(a + imm_i) & ~1
            if next_pc & 3:
                raise Trap(0, self.pc, next_pc)
        elif opcode == 0x63:
            conditions = {
                0: ("beq", a == b), 1: ("bne", a != b),
                4: ("blt", signed(a) < signed(b)), 5: ("bge", signed(a) >= signed(b)),
                6: ("bltu", a < b), 7: ("bgeu", a >= b),
            }
            if f3 not in conditions:
                raise Trap(2, self.pc, insn)
            name, taken = conditions[f3]
            if taken:
                next_pc = u32(self.pc + imm_b)
                if next_pc & 3:
                    raise Trap(0, self.pc, next_pc)
        elif opcode == 0x03:
            addr = u32(a + imm_i)
            desc = {0: ("lb", 1, True), 1: ("lh", 2, True), 2: ("lw", 4, False), 4: ("lbu", 1, False), 5: ("lhu", 2, False)}
            if f3 not in desc:
                raise Trap(2, self.pc, insn)
            name, size, sign_extend = desc[f3]
            if addr % size:
                raise Trap(4, self.pc, addr)
            raw = self._read(addr, size)
            result = u32(sext(raw, size * 8) if sign_extend else raw)
            write_rd = True
        elif opcode == 0x23:
            addr = u32(a + imm_s)
            desc = {0: ("sb", 1), 1: ("sh", 2), 2: ("sw", 4)}
            if f3 not in desc:
                raise Trap(2, self.pc, insn)
            name, size = desc[f3]
            if addr % size:
                raise Trap(6, self.pc, addr)
            self._write(addr, size, b)
        elif opcode == 0x13:
            table = {
                0: ("addi", u32(a + imm_i)), 2: ("slti", int(signed(a) < imm_i)),
                3: ("sltiu", int(a < u32(imm_i))), 4: ("xori", a ^ u32(imm_i)),
                6: ("ori", a | u32(imm_i)), 7: ("andi", a & u32(imm_i)),
            }
            if f3 in table:
                name, result = table[f3]
            elif f3 == 1 and f7 == 0:
                name, result = "slli", u32(a << rs2)
            elif f3 == 5 and f7 == 0:
                name, result = "srli", a >> rs2
            elif f3 == 5 and f7 == 0x20:
                name, result = "srai", u32(signed(a) >> rs2)
            else:
                raise Trap(2, self.pc, insn)
            write_rd = True
        elif opcode == 0x33:
            operations = {
                (0x00, 0): ("add", u32(a + b)), (0x20, 0): ("sub", u32(a - b)),
                (0x00, 1): ("sll", u32(a << (b & 31))),
                (0x00, 2): ("slt", int(signed(a) < signed(b))),
                (0x00, 3): ("sltu", int(a < b)), (0x00, 4): ("xor", a ^ b),
                (0x00, 5): ("srl", a >> (b & 31)),
                (0x20, 5): ("sra", u32(signed(a) >> (b & 31))),
                (0x00, 6): ("or", a | b), (0x00, 7): ("and", a & b),
            }
            if (f7, f3) not in operations:
                raise Trap(2, self.pc, insn)
            name, result = operations[(f7, f3)]
            write_rd = True
        elif opcode == 0x0F and f3 == 0:
            name = "fence"
        elif insn == 0x00100073:
            self.halted, name = True, "ebreak"
            self.coverage.add(name)
            return
        elif insn == 0x00000073:
            raise Trap(11, self.pc, 0)
        else:
            raise Trap(2, self.pc, insn)

        if write_rd and rd:
            self.regs[rd] = u32(result)
        self.regs[0] = 0
        self.pc, self.retired = next_pc, self.retired + 1
        self.coverage.add(name)

    def run(self, limit: int = 10000) -> None:
        while not self.halted and self.retired < limit:
            self.step()
        if not self.halted:
            raise RuntimeError(f"program did not halt within {limit} retired instructions")


def load_hex(path: Path) -> list[int]:
    return [int(line, 16) for line in path.read_text().splitlines() if line.strip()]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("program", type=Path)
    parser.add_argument("--signature", type=Path)
    parser.add_argument("--signature-base", type=lambda x: int(x, 0), default=0x400)
    parser.add_argument("--signature-words", type=int, default=64)
    args = parser.parse_args()
    machine = Machine(load_hex(args.program))
    machine.run()
    print(f"REFERENCE_PASS retired={machine.retired} coverage={len(machine.coverage)}")
    if args.signature:
        start = args.signature_base
        words = [int.from_bytes(machine.mem[start + 4*i:start + 4*i + 4], "little") for i in range(args.signature_words)]
        args.signature.write_text("".join(f"{word:08x}\n" for word in words), encoding="ascii")


if __name__ == "__main__":
    main()
