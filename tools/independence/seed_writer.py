#!/usr/bin/env python3
"""tools/independence/seed_writer.py: the seed format, written a second time.

docs/SEED_FORMAT.md describes the Mach-O that tools/v5/link_lib.rail (lk_link_file) writes
around any program the compiler emits: the seed, rail_native, is that container around the
compiler's own text. This file is the document's proof: a writer in another language, by
another code path, that reads the same `.s` subset and must produce the same bytes. Nothing
from the Rail tree is imported; the only inputs are the `.s` and the document. Section
numbers in the comments are the document's.

    python3 tools/independence/seed_writer.py tools/independence/exit42.s /tmp/exit42_py
    ./rail_native run tools/independence/link_file.rail tools/independence/exit42.s /tmp/exit42_rail
    cmp /tmp/exit42_py /tmp/exit42_rail && /tmp/exit42_py; echo $?      # 42

tools/independence/seed_format_gate.sh runs exactly that. Exit 0 when the file was written,
2 on an input the format does not admit (the message names the line).

The writer assembles only the instructions exit42.s needs (section 8): the instruction set
is Arm's and is not what the document specifies. A `.s` with any other mnemonic is refused.
"""
from __future__ import annotations

import hashlib
import re
import struct
import sys

PAGE = 16384
TEXT_VM_BASE = 0x100000000
HEADER = 32
LC_BYTES_14 = 1176            # section 3: the 14 load commands of every seed
LC_END = HEADER + LC_BYTES_14  # 1208: where __text starts when there is no extra dylib
LC_DYLIB = 56


def die(msg: str) -> None:
    sys.stderr.write(f"seed_writer: {msg}\n")
    sys.exit(2)


def align(n: int, a: int) -> int:
    return (n + a - 1) // a * a


# ---------------------------------------------------------------------------------------------
# Section 1: reading the .s
# ---------------------------------------------------------------------------------------------

ESCAPES = {"n": 10, "t": 9, "r": 13, '"': 34, "\\": 92}


def decode_string(line: str) -> bytes:
    """The quoted body of an .asciz/.ascii line, with the five escapes the compiler writes."""
    i = line.find('"')
    if i < 0:
        return b""
    out = bytearray()
    j = i + 1
    while j < len(line):
        c = line[j]
        if c == '"':
            break
        if c == "\\" and j + 1 < len(line):
            e = line[j + 1]
            out.append(ESCAPES.get(e, ord(e)))
            j += 2
            continue
        out.append(ord(c))
        j += 1
    return bytes(out)


def strip_comment(s: str) -> str:
    i = s.find(";")
    return s if i < 0 else s[:i]


def imm(s: str) -> int:
    s = s.strip().lstrip("#")
    neg = s.startswith("-")
    if neg:
        s = s[1:]
    v = int(s, 16) if s.lower().startswith("0x") else int(s)
    return -v if neg else v


def classify(line: str) -> str:
    """One of: skip, sec_text, sec_other, asciz, ascii, align, label, insn (section 1.1)."""
    s = line.lstrip(" \t")
    if s == "" or s[0] == ";":
        return "skip"
    if s[0] == ".":
        if s.startswith(".section"):
            return "sec_text" if "__TEXT,__text" in line else "sec_other"
        if s.startswith(".text"):
            return "sec_text"
        if s.startswith((".data", ".zerofill")):
            return "sec_other"
        if s.startswith(".asciz"):
            return "asciz"
        if s.startswith(".ascii"):
            return "ascii"
        if s.startswith(".p2align"):
            return "align"
        return "label" if s.rstrip().endswith(":") else "skip"
    return "label" if s.rstrip().endswith(":") else "insn"


def section_of(line: str) -> int:
    """The data walk's section after a switch line: 0 text, 1 __data, 3 __mod_init_func,
    9 other; -1 when the line is not a switch (section 1.2)."""
    s = line.lstrip(" \t")
    if s.startswith(".section"):
        if "__TEXT,__text" in line:
            return 0
        if "__DATA,__mod_init_func" in line:
            return 3
        if "__DATA,__data" in line:
            return 1
        return 9
    if s.startswith(".text"):
        return 0
    if s.startswith(".data"):
        return 1
    return -1


def p2align_n(line: str) -> int:
    return int(line.split()[1])


def data_dir_size(off: int, line: str) -> int:
    s = line.lstrip(" \t")
    if s.startswith(".quad"):
        return 8
    if s.startswith(".long"):
        return 4
    if s.startswith(".byte"):
        return len(s[5:].split(","))
    if s.startswith(".asciz"):
        return len(decode_string(line)) + 1
    if s.startswith(".ascii"):
        return len(decode_string(line))
    if s.startswith(".space"):
        return imm(s.split()[1])
    if s.startswith(".short"):
        return 2
    if s.startswith(".p2align"):
        return align(off, 1 << p2align_n(s)) - off
    return 0


def text_size_of(line_kind: str, off: int, line: str) -> int:
    if line_kind == "insn":
        return 4
    if line_kind == "asciz":
        return len(decode_string(line)) + 1
    if line_kind == "ascii":
        return len(decode_string(line))
    if line_kind == "align":
        return align(off, 1 << p2align_n(line.lstrip())) - off
    return 0


class Source:
    """The .s as the linker reads it: text labels and relocations (1.1), data and bss
    symbols with the three section sizes (1.2), imports (1.3)."""

    def __init__(self, text: str):
        self.lines = text.split("\n")
        self.kinds = [classify(l) for l in self.lines]
        self.text_labels: dict[str, int] = {}
        self.text_size = 0
        self.data_syms: dict[str, tuple[int, int]] = {}  # name -> (1 data | 2 bss, offset)
        self.data_size = self.bss_size = self.modinit_size = 0
        self._walk_text()
        self._walk_data()
        self.imports = self._imports()

    def _walk_text(self) -> None:
        off, in_text = 0, True
        for line, k in zip(self.lines, self.kinds):
            if k == "sec_text":
                in_text = True
            elif k == "sec_other":
                in_text = False
            elif not in_text or k == "skip":
                continue
            elif k == "label":
                self.text_labels[line.strip()[:-1]] = off
            else:
                off += text_size_of(k, off, line)
        self.text_size = off

    def _walk_data(self) -> None:
        sec, data, bss, mod = 0, 0, 0, 0
        for line, k in zip(self.lines, self.kinds):
            if k == "insn":
                continue
            sw = section_of(line)
            if sw >= 0:
                sec = sw
                continue
            s = line.strip()
            if s == "":
                continue
            if s.startswith(".zerofill"):
                _, _, name, size, al = [p.strip() for p in s[len(".zerofill"):].split(",")]
                base = align(bss, 1 << imm(al))
                self.data_syms[name] = (2, base)
                bss = base + imm(size)
            elif s.startswith(".comm"):
                name, size, al = [p.strip() for p in s[len(".comm"):].split(",")]
                base = align(bss, 1 << imm(al))
                self.data_syms[name] = (2, base)
                bss = base + imm(size)
            elif s.endswith(":"):
                if sec == 1:
                    self.data_syms[s[:-1]] = (1, data)
            elif sec == 1:
                data += data_dir_size(data, s)
            elif sec == 3:
                mod += data_dir_size(mod, s)
        self.data_size, self.bss_size, self.modinit_size = data, bss, mod

    def _imports(self) -> list[str]:
        seen: list[str] = []
        for _, name in self.relocs():
            if name not in seen:
                seen.append(name)
        return seen

    def relocs(self) -> list[tuple[int, str]]:
        """(text offset, symbol) of every bl/b whose target is neither a text label nor a
        dotted local label, in source order (1.3)."""
        out, off, in_text = [], 0, True
        for line, k in zip(self.lines, self.kinds):
            if k == "sec_text":
                in_text = True
            elif k == "sec_other":
                in_text = False
            elif not in_text or k in ("skip", "label"):
                continue
            elif k == "insn":
                parts = strip_comment(line).split(None, 1)
                mn, ops = parts[0], (parts[1].strip() if len(parts) > 1 else "")
                if mn in ("bl", "b") and ops not in self.text_labels and not ops.startswith("."):
                    out.append((off, ops))
                off += 4
            else:
                off += text_size_of(k, off, line)
        return out


# ---------------------------------------------------------------------------------------------
# Section 2: the layout
# ---------------------------------------------------------------------------------------------

class Layout:
    def __init__(self, src: Source):
        n = len(src.imports)
        self.nx = 1 if any(s.startswith("_sqlite3_") for s in src.imports) else 0
        self.text_foff = LC_END + LC_DYLIB * self.nx
        self.text_vmaddr = TEXT_VM_BASE + self.text_foff
        self.stubs_foff = align(self.text_foff + src.text_size, 4)
        self.stubs_vmaddr = TEXT_VM_BASE + self.stubs_foff
        self.text_seg_fsz = align(self.stubs_foff + 12 * n, PAGE)
        self.got_foff = self.text_seg_fsz
        self.got_vmaddr = TEXT_VM_BASE + self.got_foff
        self.modinit_foff = align(self.got_foff + 8 * n, 8)
        self.modinit_vmaddr = TEXT_VM_BASE + self.modinit_foff
        self.datac_seg_fsz = align(self.modinit_foff + src.modinit_size - self.got_foff, PAGE)
        self.data_foff = self.got_foff + self.datac_seg_fsz
        self.data_vmaddr = TEXT_VM_BASE + self.data_foff
        self.bss_vmaddr = align(self.data_vmaddr + src.data_size, 8)
        self.data_seg_fsz = align(src.data_size, PAGE)
        self.data_seg_vmsz = align(self.bss_vmaddr + src.bss_size - self.data_vmaddr, PAGE)
        self.linkedit_foff = self.data_foff + self.data_seg_fsz
        self.linkedit_vmaddr = TEXT_VM_BASE + self.data_foff + self.data_seg_vmsz

    def resolve(self, src: Source, sym: str) -> int:
        if sym in src.data_syms:
            sec, off = src.data_syms[sym]
            return (self.data_vmaddr if sec == 1 else self.bss_vmaddr) + off
        if sym in src.text_labels:
            return self.text_vmaddr + src.text_labels[sym]
        die(f"symbol {sym} is neither a data, bss nor text symbol")
        return -1


class LinkEdit:
    """Section 5: the subsections of __LINKEDIT, in file order."""

    def __init__(self, lay: Layout, rebase_sz: int, bind_sz: int, n_imp: int, str_sz: int):
        self.rebase_off = lay.linkedit_foff
        self.rebase_sz = rebase_sz
        self.bind_off = align(self.rebase_off + rebase_sz, 8)
        self.bind_sz = bind_sz
        self.sym_off = align(self.bind_off + bind_sz, 8)
        self.nsyms = n_imp + 2
        self.ind_off = self.sym_off + 16 * self.nsyms
        self.nind = 2 * n_imp
        self.str_off = self.ind_off + 4 * self.nind
        self.str_sz = str_sz
        self.cs_off = align(self.str_off + str_sz, 16)
        n_code = (self.cs_off + PAGE - 1) // PAGE
        self.cd_size = 96 + (2 + n_code) * 32
        self.sig_total = self.cd_size + 40
        self.file_size = self.cs_off + self.sig_total


# ---------------------------------------------------------------------------------------------
# Section 8: the handful of encodings exit42.s uses (Arm's ISA, not the format's)
# ---------------------------------------------------------------------------------------------

def reg(s: str) -> int:
    s = s.strip().strip("[]!")
    if s in ("sp", "xzr", "wzr"):
        return 31
    return int(s[1:])


def encode(mn: str, ops: str, off: int, src: Source) -> int:
    o = [p.strip() for p in ops.split(",")] if ops else []
    if mn == "ret":
        return 0xD65F03C0
    if mn == "nop":
        return 0xD503201F
    if mn == "svc":
        return 0xD4000001 | (imm(o[0]) & 0xFFFF) << 5
    if mn == "mov" and o[1].startswith("#"):
        v = imm(o[1])
        if not 0 <= v <= 0xFFFF:
            die(f"mov immediate {v} out of the writer's range")
        return 0xD2800000 | v << 5 | reg(o[0])
    if mn in ("movz", "movk"):
        hw = imm(o[2].split()[1]) // 16 if len(o) > 2 else 0
        base = 0xD2800000 if mn == "movz" else 0xF2800000
        return base | hw << 21 | (imm(o[1]) & 0xFFFF) << 5 | reg(o[0])
    if mn in ("bl", "b"):
        base = 0x94000000 if mn == "bl" else 0x14000000
        if o[0] in src.text_labels:
            delta = src.text_labels[o[0]] - off
            return base | (delta // 4) & 0x3FFFFFF
        return base            # an import: section 4.2 patches the branch to its stub
    if mn == "adr":
        delta = src.text_labels[o[1]] - off
        return 0x10000000 | (delta & 3) << 29 | ((delta >> 2) & 0x7FFFF) << 5 | reg(o[0])
    if mn == "adrp":
        return 0x90000000 | reg(o[0])            # the page immediate is baked in section 4.1
    if mn == "add":
        if o[2].startswith("#"):
            return 0x91000000 | (imm(o[2]) & 0xFFF) << 10 | reg(o[1]) << 5 | reg(o[0])
        if "@PAGEOFF" in o[2]:
            return 0x91000000 | reg(o[1]) << 5 | reg(o[0])
        return 0x8B000000 | reg(o[2]) << 16 | reg(o[1]) << 5 | reg(o[0])
    if mn in ("ldr", "str"):
        base = 0xF9400000 if mn == "ldr" else 0xF9000000
        n = reg(o[1])
        if len(o) == 2:
            return base | n << 5 | reg(o[0])
        if "@PAGEOFF" in o[2]:
            return base | n << 5 | reg(o[0])
        return base | (imm(o[2].rstrip("]")) // 8) << 10 | n << 5 | reg(o[0])
    die(f"no encoding for `{mn} {ops}` in the writer")
    return 0


def assemble_text(src: Source, lay: Layout) -> bytearray:
    """The __text image (section 4): instructions, inline strings, alignment padding, then
    the @PAGE/@PAGEOFF baking (4.1) and the import branches to their stubs (4.2)."""
    buf = bytearray(src.text_size)
    off, in_text = 0, True
    page_fixups: list[tuple[int, str, str]] = []
    for line, k in zip(src.lines, src.kinds):
        if k == "sec_text":
            in_text = True
        elif k == "sec_other":
            in_text = False
        elif not in_text or k in ("skip", "label"):
            continue
        elif k in ("asciz", "ascii"):
            b = decode_string(line) + (b"\0" if k == "asciz" else b"")
            buf[off:off + len(b)] = b
            off += len(b)
        elif k == "align":
            target = align(off, 1 << p2align_n(line.lstrip()))
            while off < target:               # zero bytes to a 4-boundary, then NOP words
                if off % 4 == 0:
                    buf[off:off + 4] = struct.pack("<I", 0xD503201F)
                    off += 4
                else:
                    buf[off] = 0
                    off += 1
        else:
            parts = strip_comment(line).split(None, 1)
            mn, ops = parts[0], (parts[1].strip() if len(parts) > 1 else "")
            word = encode(mn, ops, off, src)
            m = re.search(r"([A-Za-z0-9_.]+)@PAGE", ops)
            if m is not None:
                page_fixups.append((off, mn, m.group(1)))
            buf[off:off + 4] = struct.pack("<I", word)
            off += 4
    for off, mn, sym in page_fixups:                       # 4.1
        word = struct.unpack_from("<I", buf, off)[0]
        addr = lay.resolve(src, sym)
        if mn == "adrp":
            pc = lay.text_vmaddr + off
            p21 = ((addr & ~0xFFF) - (pc & ~0xFFF)) // 4096 & 0x1FFFFF
            word |= (p21 & 3) << 29 | (p21 >> 2 & 0x7FFFF) << 5
        elif mn == "add":
            word |= (addr & 0xFFF) << 10
        else:                                              # ldr/str: scaled by the access size
            scale = 1 << (word >> 30 & 3)
            word |= ((addr & 0xFFF) // scale) << 10
        struct.pack_into("<I", buf, off, word)
    for off, sym in src.relocs():                          # 4.2
        stub = lay.stubs_vmaddr + 12 * src.imports.index(sym)
        delta = stub - (lay.text_vmaddr + off)
        struct.pack_into("<I", buf, off, 0x94000000 | (delta // 4) & 0x3FFFFFF)
    return buf


# ---------------------------------------------------------------------------------------------
# Section 4.4: the __data image and its rebases
# ---------------------------------------------------------------------------------------------

def operand_value(t: str, src: Source, lay: Layout) -> tuple[int, bool]:
    t = t.strip()
    m = re.match(r"[A-Za-z0-9_.]+", t)
    if t and (t[0] == "_" or t[0] == ".") and m is not None:
        sym = m.group(0)
        rest = t[len(sym):]
        addend = imm(rest.split("+", 1)[1]) if "+" in rest else 0
        return lay.resolve(src, sym) + addend, True
    return imm(t), False


def data_image(src: Source, lay: Layout) -> tuple[bytearray, list[int]]:
    buf = bytearray(src.data_size + 16)
    rebs: list[int] = []
    sec, off = 0, 0
    for line, k in zip(src.lines, src.kinds):
        if k == "insn":
            continue
        sw = section_of(line)
        if sw >= 0:
            sec = sw
            continue
        if sec != 1:
            continue
        s = line.strip()
        if s == "" or s.endswith(":"):
            continue
        if s.startswith(".quad"):
            v, ptr = operand_value(s[5:], src, lay)
            struct.pack_into("<Q", buf, off, v & 0xFFFFFFFFFFFFFFFF)
            if ptr:
                rebs.append(off)
            off += 8
        elif s.startswith(".long"):
            v, _ = operand_value(s[5:], src, lay)
            struct.pack_into("<I", buf, off, v & 0xFFFFFFFF)
            off += 4
        elif s.startswith(".short"):
            v, _ = operand_value(s[6:], src, lay)
            struct.pack_into("<H", buf, off, v & 0xFFFF)
            off += 2
        elif s.startswith(".byte"):
            vals = [imm(x) for x in s[5:].split(",")]
            buf[off:off + len(vals)] = bytes(v & 0xFF for v in vals)
            off += len(vals)
        elif s.startswith((".asciz", ".ascii")):
            b = decode_string(line) + (b"\0" if s.startswith(".asciz") else b"")
            buf[off:off + len(b)] = b
            off += len(b)
        elif s.startswith(".p2align"):
            off = align(off, 1 << p2align_n(s))
    return buf[:src.data_size], rebs


# ---------------------------------------------------------------------------------------------
# Section 5: dyld info, symbols, strings
# ---------------------------------------------------------------------------------------------

def uleb(v: int) -> bytes:
    out = bytearray()
    while True:
        b = v & 0x7F
        v >>= 7
        if v:
            out.append(b | 0x80)
        else:
            out.append(b)
            return bytes(out)


def rebase_stream(modinit_doff: int, data_rebs: list[int]) -> bytes:
    """5.1: SET_TYPE pointer; SET_SEG 2 at the module initialiser, DO_REBASE 1; SET_SEG 3 at
    the first data pointer, DO_REBASE 1, then per pointer ADD_ADDR (gap past the previous
    pointer's 8 bytes, only when nonzero) and DO_REBASE 1; DONE. With no data pointer the
    linker rebases __DATA+0 (head of an empty list is 0): reproduced, not recommended."""
    rebs = data_rebs or [0]
    out = bytearray([0x11, 0x22]) + uleb(modinit_doff) + bytes([0x51, 0x23]) + uleb(rebs[0]) + bytes([0x51])
    prev = rebs[0]
    for r in rebs[1:]:
        gap = r - (prev + 8)
        if gap:
            out += bytes([0x30]) + uleb(gap)
        out.append(0x51)
        prev = r
    out.append(0)
    return bytes(out)


def ordinal(sym: str) -> int:
    return 2 if sym.startswith("_sqlite3_") else 1


def bind_stream(imports: list[str]) -> bytes:
    """5.2: SET_DYLIB_ORDINAL_IMM; SET_SYMBOL name; SET_TYPE pointer; SET_SEG 2 offset 0;
    DO_BIND; then per import SET_SYMBOL, DO_BIND (a new ordinal only when it changes); DONE."""
    out = bytearray([0x10 | ordinal(imports[0]), 0x40]) + imports[0].encode() + b"\0"
    out += bytes([0x51, 0x72]) + uleb(0) + bytes([0x90])
    prev = ordinal(imports[0])
    for sym in imports[1:]:
        o = ordinal(sym)
        if o != prev:
            out.append(0x10 | o)
            prev = o
        out += bytes([0x40]) + sym.encode() + b"\0" + bytes([0x90])
    out.append(0)
    return bytes(out)


def string_table(imports: list[str]) -> bytes:
    return b"\x20\0__mh_execute_header\0_main\0" + b"".join(s.encode() + b"\0" for s in imports)


def symbol_table(imports: list[str], main_vaddr: int) -> bytes:
    """5.3: nlist_64 for __mh_execute_header, _main, then each import."""
    out = struct.pack("<IBBHQ", 2, 0x0F, 1, 0x10, TEXT_VM_BASE)
    out += struct.pack("<IBBHQ", 22, 0x0F, 1, 0, main_vaddr)
    strx = 28
    for sym in imports:
        out += struct.pack("<IBBHQ", strx, 0x01, 0, 0x100, 0)
        strx += len(sym) + 1
    return out


# ---------------------------------------------------------------------------------------------
# Section 3: the header and the load commands
# ---------------------------------------------------------------------------------------------

def segment(name: str, vmaddr: int, vmsize: int, foff: int, fsize: int, maxp: int, initp: int,
            sections: list[bytes], flags: int) -> bytes:
    hdr = struct.pack("<II16sQQQQIIII", 0x19, 72 + 80 * len(sections), name.encode(),
                      vmaddr, vmsize, foff, fsize, maxp, initp, len(sections), flags)
    return hdr + b"".join(sections)


def section(sect: str, seg: str, addr: int, size: int, foff: int, al: int, flags: int,
            r1: int, r2: int) -> bytes:
    return struct.pack("<16s16sQQIIIIIIII", sect.encode(), seg.encode(), addr, size, foff, al,
                       0, 0, flags, r1, r2, 0)


def dylib(name: str, current: int) -> bytes:
    body = struct.pack("<IIIIII", 12, LC_DYLIB, 24, 2, current, 0x10000) + name.encode() + b"\0"
    return body + b"\0" * (LC_DYLIB - len(body))


def load_commands(src: Source, lay: Layout, le: LinkEdit, main_vaddr: int) -> bytes:
    n = len(src.imports)
    ncmds = 14 + lay.nx
    out = struct.pack("<IIIIIIII", 0xFEEDFACF, 0x0100000C, 0, 2, ncmds, LC_BYTES_14 + LC_DYLIB * lay.nx,
                      0x200085, 0)
    out += segment("__PAGEZERO", 0, TEXT_VM_BASE, 0, 0, 0, 0, [], 0)
    out += segment("__TEXT", TEXT_VM_BASE, lay.text_seg_fsz, 0, lay.text_seg_fsz, 5, 5, [
        section("__text", "__TEXT", lay.text_vmaddr, src.text_size, lay.text_foff, 2, 0x80000400, 0, 0),
        section("__stubs", "__TEXT", lay.stubs_vmaddr, 12 * n, lay.stubs_foff, 2, 0x80000408, 0, 12),
    ], 0)
    out += segment("__DATA_CONST", lay.got_vmaddr, lay.datac_seg_fsz, lay.got_foff, lay.datac_seg_fsz, 3, 3, [
        section("__got", "__DATA_CONST", lay.got_vmaddr, 8 * n, lay.got_foff, 3, 6, n, 0),
        section("__mod_init_func", "__DATA_CONST", lay.modinit_vmaddr, src.modinit_size, lay.modinit_foff, 3, 9, 0, 0),
    ], 0x10)
    out += segment("__DATA", lay.data_vmaddr, lay.data_seg_vmsz, lay.data_foff, lay.data_seg_fsz, 3, 3, [
        section("__data", "__DATA", lay.data_vmaddr, src.data_size, lay.data_foff, 3, 0, 0, 0),
        section("__bss", "__DATA", lay.bss_vmaddr, src.bss_size, 0, 3, 1, 0, 0),
    ], 0)
    le_fsz = le.file_size - lay.linkedit_foff
    out += segment("__LINKEDIT", lay.linkedit_vmaddr, align(le_fsz, PAGE), lay.linkedit_foff, le_fsz, 1, 1, [], 0)
    out += struct.pack("<IIIIIIIIIIII", 0x80000022, 48, le.rebase_off, le.rebase_sz, le.bind_off, le.bind_sz,
                       0, 0, 0, 0, 0, 0)
    out += struct.pack("<IIIIII", 2, 24, le.sym_off, le.nsyms, le.str_off, le.str_sz)
    out += struct.pack("<IIIIIIIIIIIIIIIIIIII", 11, 80, 0, 0, 0, 2, 2, n, 0, 0, 0, 0, 0, 0,
                       le.ind_off, le.nind, 0, 0, 0, 0)
    out += struct.pack("<III", 14, 32, 12) + b"/usr/lib/dyld\0" + b"\0" * 6
    uuid = bytearray(16)
    uuid[6], uuid[8] = 0x40, 0x80
    out += struct.pack("<II", 27, 24) + bytes(uuid)
    out += struct.pack("<IIIIIIII", 0x32, 32, 1, 0x1A0000, 0x1A0000, 1, 3, 1)
    out += struct.pack("<IIQQ", 0x80000028, 24, main_vaddr - TEXT_VM_BASE, 0x10000000)
    out += dylib("/usr/lib/libSystem.B.dylib", 0x054C0000)
    if lay.nx:
        out += dylib("/usr/lib/libsqlite3.dylib", 0x017C0000)
    out += struct.pack("<IIII", 0x1D, 16, le.cs_off, le.sig_total)
    assert len(out) == LC_END + LC_DYLIB * lay.nx
    return out


# ---------------------------------------------------------------------------------------------
# Section 6: the ad-hoc signature
# ---------------------------------------------------------------------------------------------

def sign(buf: bytearray, le: LinkEdit, text_limit: int) -> None:
    code_limit = le.cs_off
    n_code = (code_limit + PAGE - 1) // PAGE
    cd_size = le.cd_size
    off_req = 28 + cd_size
    sig = le.cs_off
    req = struct.pack(">III", 0xFADE0C01, 12, 0)
    buf[sig + off_req:sig + off_req + 12] = req
    buf[sig:sig + 28] = struct.pack(">IIIIIII", 0xFADE0CC0, cd_size + 40, 2, 0, 28, 2, off_req)
    cd = sig + 28
    hdr = struct.pack(">IIIIIIIII", 0xFADE0C02, cd_size, 0x20400, 2, 160, 88, 2, n_code, code_limit)
    hdr += bytes([32, 2, 0, 14]) + struct.pack(">IIII", 0, 0, 0, 0)
    hdr += struct.pack(">QQQQ", 0, 0, text_limit, 1)
    buf[cd:cd + 88] = hdr
    buf[cd + 88:cd + 96] = b"rail.v5\0"
    buf[cd + 96:cd + 128] = hashlib.sha256(req).digest()        # special slot -2: requirements
    # special slot -1 (Info.plist) stays 32 zero bytes
    for i in range(n_code):                                      # code slots: each 16 KB page
        start = i * PAGE
        buf[cd + 160 + 32 * i:cd + 192 + 32 * i] = hashlib.sha256(bytes(buf[start:min(start + PAGE, code_limit)])).digest()


# ---------------------------------------------------------------------------------------------
# The file
# ---------------------------------------------------------------------------------------------

def write(src_path: str, out_path: str) -> int:
    with open(src_path, encoding="utf-8") as f:
        src = Source(f.read())
    if not src.imports:
        die("the format needs at least one import (every compiler output calls libSystem)")
    if "_rail_arena_init" not in src.text_labels and "_rail_arena_init" not in src.data_syms:
        die("the module initialiser _rail_arena_init is not defined")
    if "_main" not in src.text_labels:
        die("_main is not defined")
    lay = Layout(src)
    n = len(src.imports)
    text = assemble_text(src, lay)
    data, rebs = data_image(src, lay)
    rebase = rebase_stream(lay.modinit_foff - lay.got_foff, rebs)
    bind = bind_stream(src.imports)
    strtab = string_table(src.imports)
    le = LinkEdit(lay, len(rebase), len(bind), n, len(strtab))
    main_vaddr = lay.resolve(src, "_main")
    buf = bytearray(le.file_size)
    buf[0:lay.text_foff] = load_commands(src, lay, le, main_vaddr)
    buf[lay.text_foff:lay.text_foff + src.text_size] = text
    for i in range(n):                                           # 4.3: the stubs
        pc = lay.stubs_vmaddr + 12 * i
        p21 = ((lay.got_vmaddr & ~0xFFF) - (pc & ~0xFFF)) // 4096 & 0x1FFFFF
        adrp = 0x90000010 | (p21 & 3) << 29 | (p21 >> 2 & 0x7FFFF) << 5
        struct.pack_into("<III", buf, lay.stubs_foff + 12 * i, adrp, 0xF9400210 | i << 10, 0xD61F0200)
    struct.pack_into("<Q", buf, lay.modinit_foff, lay.resolve(src, "_rail_arena_init"))
    buf[lay.data_foff:lay.data_foff + src.data_size] = data
    buf[le.rebase_off:le.rebase_off + len(rebase)] = rebase
    buf[le.bind_off:le.bind_off + len(bind)] = bind
    buf[le.sym_off:le.sym_off + 16 * le.nsyms] = symbol_table(src.imports, main_vaddr)
    struct.pack_into(f"<{2 * n}I", buf, le.ind_off, *(list(range(2, 2 + n)) * 2))
    buf[le.str_off:le.str_off + len(strtab)] = strtab
    sign(buf, le, lay.text_seg_fsz)
    with open(out_path, "wb") as f:
        f.write(buf)
    import os
    os.chmod(out_path, 0o755)
    print(f"wrote {out_path} ({len(buf)} bytes); imports={n} rebases={len(rebs)} main@0x{main_vaddr:x}")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.stderr.write("usage: seed_writer.py <in.s> <out>\n")
        sys.exit(2)
    sys.exit(write(sys.argv[1], sys.argv[2]))
