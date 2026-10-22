# The seed format

`rail_native`, the seed, is a Mach-O executable for arm64 macOS. `tools/v5/link_lib.rail`
(`lk_link_file`) writes it around the compiler's own assembly, and since Tier 3 step 6 every
program the compiler builds on macOS is the same container around that program's assembly.
This document is the container: every region, every field, the rules that place every byte.
It was written from the code (`stdlib/macho.rail`, `tools/v5/link_lib.rail`,
`stdlib/codesign.rail`), which was itself transcribed in 2026-06 from what Apple's `ld` emitted
for one program; the two private notes those files cited are gone, and this replaces them.

**The proof.** `tools/independence/seed_writer.py`, written from this document in another
language and importing nothing from the tree, must produce the same bytes as `lk_link_file`
for `tools/independence/exit42.s`, and the file must run and exit 42:

```
bash tools/independence/seed_format_gate.sh
PASS seed_format: 49608 bytes identical from both writers; the file runs and exits 42
```

CI runs the gate after the suite. A planted change to either writer (a stack size, one byte of
the signing identifier) fails the `cmp`; the second one still runs, which is why the gate
compares bytes and does not only run the file. Measured 2026-10-22 on the seed of that day.

**Scope.** The format is the bytes. Whether the bytes run is Apple's loader's verdict (dyld and
the kernel's code-signing check), and this document does not explain why Apple accepts them.
The instruction set is Arm's: section 8 lists the handful of encodings the proof program uses,
and nothing more. The Linux ELF the `linux` subcommand writes (GNU binutils, `tools/linux_libc.s`)
is not covered.

Numbers are decimal unless written `0x`. Multi-byte integers are little-endian everywhere
except inside the signature (section 6), which is big-endian.

## 1. The input

The input is the assembly text the compiler emits (`./rail_native asm file.rail out.s` shows
it). The linker reads it line by line with the rules below; what it does not name, it ignores.

### 1.1 Lines and the text image

A line is classified after its leading blanks:

| Line | Class |
|---|---|
| empty, or first character `;` | skip |
| `.section` naming `__TEXT,__text`, or `.text` | text on |
| any other `.section`, `.data`, `.zerofill` | text off |
| `.asciz "..."`, `.ascii "..."` | inline string (text only) |
| `.p2align N` | alignment |
| a `.`-led word ending in `:` | local label |
| any other `.`-led line (`.global`, `.quad`, `.comm`, ...) | skip |
| any line ending in `:` | label |
| anything else | instruction; a `;` starts a comment |

The text image is built from the lines while text is on: an instruction is 4 bytes; `.asciz`
is its decoded bytes plus a NUL, `.ascii` the bytes alone (escapes `\n \t \r \" \\`; a string
may contain `;`); `.p2align N` advances to the next multiple of 2^N with zero bytes up to the
next 4-byte boundary and then NOP words (`0xD503201F`); a label records the current offset
(`text_labels`). `text_size` is the offset after the last line. Lines while text is off add
nothing to the image.

### 1.2 Data, bss and the module initialiser

A second walk tracks a section number: `.section __TEXT,__text` or `.text` is 0;
`.section __DATA,__data` or `.data` is 1; `.section __DATA,__mod_init_func` is 3; any other
`.section` is 9. In section 1 a label records `(data, offset)` and a directive advances the
offset: `.quad` 8, `.long` 4, `.short` 2, `.byte a, b, ...` one per value, `.asciz` length
plus one, `.ascii` length, `.space N` N, `.p2align N` to the boundary; `data_size` is the
final offset. In section 3 the same directives advance `modinit_size` and labels are not
recorded. In any section, `.zerofill __DATA,__bss,NAME,SIZE,ALIGN` and `.comm NAME,SIZE,ALIGN`
record `NAME` as `(bss, align_up(bss_offset, 2^ALIGN))` and advance the bss offset by SIZE;
`bss_size` is the final value.

### 1.3 Imports

Every `bl` or `b` whose operand is neither a text label nor a `.`-led name is a call to an
import; the import list is the distinct names in first-encounter order (`n` of them). An import
whose name begins `_sqlite3_` binds to libsqlite3 (dylib ordinal 2); every other import binds
to libSystem (ordinal 1). `nx` is 1 when any import is a libsqlite3 one, else 0.

### 1.4 What the input must contain

A text label `_main` (the entry point), a symbol `_rail_arena_init` (the module initialiser;
the compiler's runtime defines it), and at least one import. A name the compiler could not
resolve appears as a call to `_RAIL_UNDEFINED_IDENT_<name>` and the linker refuses the file;
so does an instruction the assembler has no encoding for, and a `@PAGE` reference to an
unknown symbol.

## 2. The layout

```
page           = 16384            base = 0x100000000
alignP(x)      = round x up to a multiple of page; align4, align8, align16 likewise

text_foff      = 1208 + 56 * nx          (32-byte header + 1176 bytes of load commands, +56 per extra dylib)
text_vmaddr    = base + text_foff
stubs_foff     = align4(text_foff + text_size)
stubs_vmaddr   = base + stubs_foff
text_seg_fsz   = alignP(stubs_foff + 12 * n)
got_foff       = text_seg_fsz                     got_vmaddr     = base + got_foff
modinit_foff   = align8(got_foff + 8 * n)         modinit_vmaddr = base + modinit_foff
datac_seg_fsz  = alignP(modinit_foff + modinit_size - got_foff)
data_foff      = got_foff + datac_seg_fsz         data_vmaddr    = base + data_foff
bss_vmaddr     = align8(data_vmaddr + data_size)
data_seg_fsz   = alignP(data_size)
data_seg_vmsz  = alignP(bss_vmaddr + bss_size - data_vmaddr)
linkedit_foff  = data_foff + data_seg_fsz
linkedit_vmaddr= base + data_foff + data_seg_vmsz
```

`__LINKEDIT` is laid out after the rebase and bind streams (section 5) are built, because their
lengths come first:

```
rebase_off = linkedit_foff                      rebase_sz = length of the rebase stream
bind_off   = align8(rebase_off + rebase_sz)     bind_sz   = length of the bind stream
sym_off    = align8(bind_off + bind_sz)         nsyms     = n + 2, 16 bytes each
ind_off    = sym_off + 16 * nsyms               nind      = 2 * n, 4 bytes each
str_off    = ind_off + 4 * nind                 str_sz    = 28 + sum over imports of (length + 1)
cs_off     = align16(str_off + str_sz)
n_code     = ceil(cs_off / page)
cd_size    = 96 + 32 * (2 + n_code)
sig_total  = cd_size + 40
file_size  = cs_off + sig_total
```

A symbol's address: a data symbol is `data_vmaddr + offset`, a bss symbol `bss_vmaddr + offset`,
otherwise a text label is `text_vmaddr + offset`; data and bss names are looked up before text
labels. Every byte of the file this document does not name is zero.

## 3. The header and the load commands

The header is 32 bytes: `0xFEEDFACF` (magic), `0x0100000C` (cputype arm64), `0` (cpusubtype),
`2` (MH_EXECUTE), `14 + nx` (ncmds), `1176 + 56 * nx` (sizeofcmds), `0x00200085` (flags:
MH_NOUNDEFS 1, MH_DYLDLINK 4, MH_TWOLEVEL 0x80, MH_PIE 0x200000), `0` (reserved).

The load commands follow in this order. A segment command is 72 bytes (cmd 0x19, cmdsize,
16-byte name, vmaddr, vmsize, fileoff, filesize, maxprot, initprot, nsects, flags) followed by
80 bytes per section (16-byte section name, 16-byte segment name, addr, size, offset, align,
reloff 0, nreloc 0, flags, reserved1, reserved2, reserved3 0).

| # | Command | Bytes | Fields |
|---|---|---|---|
| 1 | `__PAGEZERO` | 72 | vmaddr 0, vmsize base, fileoff 0, filesize 0, prot 0 / 0, no sections |
| 2 | `__TEXT` | 232 | vmaddr base, vmsize text_seg_fsz, fileoff 0, filesize text_seg_fsz, prot 5 / 5, flags 0; `__text`: addr text_vmaddr, size text_size, offset text_foff, align 2, flags 0x80000400; `__stubs`: addr stubs_vmaddr, size 12 n, offset stubs_foff, align 2, flags 0x80000408, reserved1 0, reserved2 12 |
| 3 | `__DATA_CONST` | 232 | vmaddr got_vmaddr, vmsize datac_seg_fsz, fileoff got_foff, filesize datac_seg_fsz, prot 3 / 3, flags 0x10; `__got`: addr got_vmaddr, size 8 n, offset got_foff, align 3, flags 6, reserved1 n; `__mod_init_func`: addr modinit_vmaddr, size modinit_size, offset modinit_foff, align 3, flags 9 |
| 4 | `__DATA` | 232 | vmaddr data_vmaddr, vmsize data_seg_vmsz, fileoff data_foff, filesize data_seg_fsz, prot 3 / 3, flags 0; `__data`: addr data_vmaddr, size data_size, offset data_foff, align 3, flags 0; `__bss`: addr bss_vmaddr, size bss_size, offset 0, align 3, flags 1 |
| 5 | `__LINKEDIT` | 72 | vmaddr linkedit_vmaddr, vmsize alignP(le_fsz), fileoff linkedit_foff, filesize le_fsz = file_size - linkedit_foff, prot 1 / 1 |
| 6 | LC_DYLD_INFO_ONLY `0x80000022` | 48 | rebase_off, rebase_sz, bind_off, bind_sz, then weak bind, lazy bind and export offset and size all 0 |
| 7 | LC_SYMTAB `2` | 24 | sym_off, nsyms, str_off, str_sz |
| 8 | LC_DYSYMTAB `11` | 80 | ilocalsym 0, nlocalsym 0, iextdefsym 0, nextdefsym 2, iundefsym 2, nundefsym n, tocoff 0, ntoc 0, modtaboff 0, nmodtab 0, extrefsymoff 0, nextrefsyms 0, indirectsymoff ind_off, nindirectsyms 2 n, extreloff 0, nextrel 0, locreloff 0, nlocrel 0 |
| 9 | LC_LOAD_DYLINKER `14` | 32 | name offset 12, `/usr/lib/dyld` NUL, zero to 32 |
| 10 | LC_UUID `27` | 24 | 16 bytes, all zero but byte 6 = 0x40 and byte 8 = 0x80 |
| 11 | LC_BUILD_VERSION `0x32` | 32 | platform 1 (macOS), minos 0x1A0000 (26.0.0), sdk 0x1A0000, ntools 1, tool 3 (ld), version 1 |
| 12 | LC_MAIN `0x80000028` | 24 | entryoff = address(`_main`) - base, stacksize 0x10000000 (256 MB) |
| 13 | LC_LOAD_DYLIB `12` | 56 | name offset 24, timestamp 2, current version 0x054C0000 (1356.0.0), compatibility version 0x10000 (1.0.0), `/usr/lib/libSystem.B.dylib` NUL, zero to 56 |
| 13b | LC_LOAD_DYLIB `12` (only when nx = 1) | 56 | as 13 with current version 0x017C0000 (380.0.0) and `/usr/lib/libsqlite3.dylib` |
| 14 | LC_CODE_SIGNATURE `0x1D` | 16 | dataoff cs_off, datasize sig_total |

The segments are numbered 0 to 4 in this order; the rebase and bind streams name `__DATA_CONST`
as segment 2 and `__DATA` as segment 3.

## 4. The images

### 4.1 `__text` and the `@PAGE` baking

The text image (1.1) is written at `text_foff`. The assembler emits every `adrp`, `add`, `ldr`
and `str` that names `sym@PAGE` or `sym@PAGEOFF` with a zero immediate and the registers in
place; the linker then bakes the immediate into the word. With `addr` the symbol's address and
`pc = text_vmaddr + offset of the instruction`:

```
adrp    p21  = ((addr & ~0xFFF) - (pc & ~0xFFF)) / 4096, taken modulo 2^21
        word |= (p21 & 3) << 29 | ((p21 >> 2) & 0x7FFFF) << 5
add     word |= (addr & 0xFFF) << 10
ldr/str scale = 1 << ((word >> 30) & 3);   word |= ((addr & 0xFFF) / scale) << 10
```

### 4.2 Calls to imports

Every `bl` or `b` to an import (1.3) is rewritten as `bl` to the import's stub:
`word = 0x94000000 | ((stub - pc) / 4) & 0x3FFFFFF` with `stub = stubs_vmaddr + 12 * i` for the
`i`-th import.

### 4.3 `__stubs`

At `stubs_foff`, 12 bytes per import `i`, with `pc = stubs_vmaddr + 12 * i`:

```
adrp x16, page(got_vmaddr)        0x90000010 with the page immediate baked as in 4.1
ldr  x16, [x16, #8 * i]           0xF9400210 | i << 10
br   x16                          0xD61F0200
```

### 4.4 `__got`, `__mod_init_func`, `__data`, `__bss`

`__got` is `8 * n` zero bytes at `got_foff`; dyld fills slot `i` with the `i`-th import's address
from the bind stream. At `modinit_foff` the linker writes one 8-byte pointer, the address of
`_rail_arena_init`, whatever the input's `__mod_init_func` section said (the compiler's assembly
declares that section with `.p2align 3` and `.quad _rail_arena_init`, so `modinit_size` is 8
and dyld runs the initialiser before `_main`).

`__data` at `data_foff` is the directives of section 1 (1.2) in order. `.quad` with a number
writes it; `.quad SYM` or `.quad SYM + N`, where SYM begins `_` or `.`, writes the symbol's
address plus N and records the directive's offset as a rebase. `.long` writes 4 bytes (a symbol
operand is resolved but not rebased), `.short` 2, `.byte` one per value; `.asciz` and `.ascii`
as in 1.1; `.p2align N` leaves zeros to the boundary. `__bss` has no file bytes.

## 5. `__LINKEDIT`

### 5.1 The rebase stream

Classic dyld opcodes, one byte each, with ULEB128 operands:

```
0x11                       REBASE_OPCODE_SET_TYPE_IMM, pointer
0x22  uleb(modinit_foff - got_foff)   SET_SEGMENT_AND_OFFSET_ULEB, segment 2 (__DATA_CONST)
0x51                       DO_REBASE_IMM_TIMES 1            (the module initialiser pointer)
0x23  uleb(r0)             SET_SEGMENT_AND_OFFSET_ULEB, segment 3 (__DATA), r0 the first data rebase offset
0x51                       DO_REBASE_IMM_TIMES 1
for each further rebase offset r, in ascending order:
      0x30 uleb(r - previous - 8)    ADD_ADDR_ULEB, written only when the gap is not zero
      0x51                           DO_REBASE_IMM_TIMES 1
0x00                       DONE
```

### 5.2 The bind stream

```
0x10 | ordinal             BIND_OPCODE_SET_DYLIB_ORDINAL_IMM (1 libSystem, 2 libsqlite3) for the first import
0x40  name NUL             SET_SYMBOL_TRAILING_FLAGS_IMM, flags 0
0x51                       SET_TYPE_IMM, pointer
0x72  uleb(0)              SET_SEGMENT_AND_OFFSET_ULEB, segment 2, offset 0 (__got slot 0)
0x90                       DO_BIND                          (advances to the next slot)
for each further import:
      0x10 | ordinal       only when the ordinal differs from the previous import's
      0x40 name NUL
      0x90
0x00                       DONE
```

### 5.3 The symbol table

`n + 2` entries of 16 bytes (`n_strx` u32, `n_type` u8, `n_sect` u8, `n_desc` u16, `n_value` u64):

| Entry | n_strx | n_type | n_sect | n_desc | n_value |
|---|---|---|---|---|---|
| `__mh_execute_header` | 2 | 0x0F | 1 | 0x0010 | base |
| `_main` | 22 | 0x0F | 1 | 0 | address of `_main` |
| each import, in order | 28, then previous + length + 1 | 0x01 | 0 | 0x0100 | 0 |

### 5.4 The indirect symbol table

`2 * n` u32 values: `2, 3, ..., n + 1` (the imports' symbol indices, for the stubs) and then
`2, 3, ..., n + 1` again (for the GOT).

### 5.5 The string table

Bytes `0x20 0x00`, then `__mh_execute_header` NUL, `_main` NUL, then each import's name NUL, in
import order. Its size is `28 + sum of (length + 1)`.

## 6. The signature

At `cs_off`, big-endian throughout, the ad-hoc signature Apple Silicon's kernel requires:

```
SuperBlob          0xFADE0CC0, length sig_total, count 2
  index 0          type 0 (CodeDirectory), offset 28
  index 1          type 2 (Requirements),  offset 28 + cd_size
CodeDirectory      at +28:
  magic 0xFADE0C02, length cd_size, version 0x20400, flags 2 (adhoc), hashOffset 160,
  identOffset 88, nSpecialSlots 2, nCodeSlots n_code, codeLimit cs_off,
  hashSize 32, hashType 2 (SHA-256), platform 0, pageSize 14 (log2 of 16384),
  spare2 0, scatterOffset 0, teamOffset 0, spare3 0, codeLimit64 0,
  execSegBase 0, execSegLimit text_seg_fsz, execSegFlags 1 (main binary)
  identifier at +88: "rail.v5" NUL (8 bytes)
  special slot -2 at +96:  SHA-256 of the 12-byte Requirements blob
  special slot -1 at +128: 32 zero bytes (no Info.plist)
  code slot i at +160 + 32 i: SHA-256 of file bytes [16384 i, min(16384 (i + 1), cs_off))
Requirements       at +28 + cd_size: 0xFADE0C01, length 12, count 0
```

The code slots are hashed last, after every other byte, the load commands with
LC_CODE_SIGNATURE included, is in place. Apple's `codesign -dvvv` reads the result as
`Identifier=rail.v5`, `CodeDirectory v=20400 ... flags=0x2(adhoc)`, and `codesign --verify`
says `valid on disk` (measured 2026-10-22 on the proof program).

## 7. Transcription artefacts the format keeps

These are part of the bytes, so a second writer must reproduce them. None is a feature.

- Every import's `n_desc` is `0x0100` (library ordinal 1), a libsqlite3 import's included; dyld
  binds from the bind stream, where the ordinal is right.
- The module initialiser pointer is written at `modinit_foff` and rebased even when the input
  declares no `__mod_init_func` section (`modinit_size` 0, the section header says so).
- A `b` to an import is patched as `bl`.
- An input with no data pointer gets a rebase of `__DATA` offset 0 (the stream takes the head of
  an empty list, which is 0). Every compiler output has data pointers.
- `.long` and `.short` symbol operands are resolved but not rebased.
- The UUID is constant, LC_BUILD_VERSION says 26.0.0 whatever the host, LC_LOAD_DYLIB carries
  the version numbers above whatever the host's libSystem reports, and the identifier is
  `rail.v5` for every program.
- The 256 MB stack in LC_MAIN is what `ld -stack_size 0x10000000` used to set; a 0 would leave
  the 8 MB default and deep recursion would overflow it.

## 8. The proof program and the writer's assembler

`tools/independence/exit42.s` walks every region: `__text` with an inline string and alignment
padding, one libSystem import (`_exit`: a stub, a GOT slot, a bind), an `adrp`/`add` pair into
`__data` and one into `__bss`, a `__data` pointer into `__text` and one into `__data` (two
rebases), the module initialiser, and the signature over all of it. The process loads 42 from
`__data`, stores it into `__bss` and exits with it.

The writer encodes only what that program and the compiler's prologue shape need; the encodings
are Arm's (Arm Architecture Reference Manual for A-profile, C6):

| Form | Encoding |
|---|---|
| `ret` | `0xD65F03C0` |
| `nop` | `0xD503201F` |
| `svc #imm` | `0xD4000001 \| imm16 << 5` |
| `mov xD, #imm16` | `0xD2800000 \| imm16 << 5 \| D` (movz) |
| `movz` / `movk xD, #imm16, lsl #16 h` | `0xD2800000` / `0xF2800000 \| h << 21 \| imm16 << 5 \| D` |
| `bl` / `b label` | `0x94000000` / `0x14000000 \| ((target - pc) / 4) & 0x3FFFFFF` |
| `adr xD, label` | `0x10000000 \| (d & 3) << 29 \| ((d >> 2) & 0x7FFFF) << 5 \| D`, d = target - pc |
| `adrp xD, sym@PAGE` | `0x90000000 \| D`, baked as in 4.1 |
| `add xD, xN, #imm12` / `sym@PAGEOFF` / `xM` | `0x91000000 \| imm12 << 10 \| N << 5 \| D` / baked / `0x8B000000 \| M << 16 \| N << 5 \| D` |
| `ldr` / `str xD, [xN]`, `[xN, #imm]`, `[xN, sym@PAGEOFF]` | `0xF9400000` / `0xF9000000 \| (imm / 8) << 10 \| N << 5 \| D`, baked |

## 9. What this document does not claim

It does not claim the layout is minimal or canonical: `ld` packs the same program differently
(one rebase opcode per run, a third signature blob), and dyld accepts both. It does not claim
the format will outlive Apple's loader: it is one `ld` output, transcribed, and the loader is
the oracle for "runs". It does claim that the bytes are now derivable from prose by someone
who has never read the Rail linker, and the gate holds that claim to a `cmp`.
