# Backends

One Rail compiler, four targets. All driven from the same `rail_native` binary.

| Backend | Verb | Output | Toolchain needed | Status (local-verified) |
|---|---|---|---|---|
| macOS ARM64 (Mach-O) | _(default)_ / `run` | `/tmp/rail_out` | none (host `as`+`ld`) | runs end-to-end |
| Linux ARM64 (ELF) | `linux` | `/tmp/rail_linux` | `aarch64-elf-as`, `aarch64-elf-ld` | needs cross-binutils |
| Linux x86_64 (ELF, source-only) | `x86` | `/tmp/rail_x86.s` | remote `gcc` (or Docker `linux/amd64`) | emits `.s`, 71/79 conformance via Docker harness |
| WebAssembly | `wasm` | `/tmp/rail_out.wasm` | `wat2wasm` (wabt) | compiles end-to-end |

---

## macOS ARM64 (Mach-O)

This is the primary target. No flags, no setup.

```bash
./rail_native run examples/hello.rail
```

```
Compiling examples/hello.rail (244 chars)...
  as: OK
  ld: OK
hello, rail
3628800
42
```

`rail_native` uses the system's `as` and `ld` directly. No libc; the runtime (allocator, GC, string ops, list ops) is ARM64 assembly emitted inline.

## Linux ARM64 (ELF)

```bash
./rail_native linux examples/hello.rail
```

If you have `aarch64-elf-as` and `aarch64-elf-ld` on `PATH` (look for `aarch64-elf-binutils` via Homebrew or your distro), this produces `/tmp/rail_linux`. `scp` it to a Pi Zero 2 W and run.

Without the cross-tools:

```
Cross-compiling examples/hello.rail for Linux ARM64...
  as: /bin/sh: /opt/homebrew/bin/aarch64-elf-as: No such file or directory
  ld: /bin/sh: /opt/homebrew/bin/aarch64-elf-ld: No such file or directory
  Binary: /tmp/rail_linux
  /tmp/rail_linux: cannot open `/tmp/rail_linux' (No such file or directory)
```

To install on macOS:

```bash
brew install aarch64-elf-binutils
```

## Linux x86_64 (source-only)

```bash
./rail_native x86 examples/hello.rail
```

```
Compiling examples/hello.rail (244 chars)...
  Assembly: /tmp/rail_x86.s (1495 chars)
  No local x86_64 assembler. scp to target and build with: gcc -o prog /tmp/rail_x86.s
  Try: scp /tmp/rail_x86.s <user>@<host>:~ && ssh <user>@<host> 'gcc -o rail_x86 rail_x86.s && ./rail_x86'
```

Rail emits the GAS assembly directly; assemble on the target with `gcc -o prog /tmp/rail_x86.s`. This is intentional — the x86_64 backend was bootstrapped for the Razer WSL test fleet rather than for cross-tools-on-mac. The x86 runtime asm lives at `tools/x86_rt.s`.

**Conformance:** `bash tools/test/x86_conformance.sh` (requires Docker + `linux/amd64` image, e.g., Colima/Rosetta) currently passes **71/79** representative tests covering ints, strings, lists, ADTs, closures, floats, FFI, TCO, and arena ops. The 8 remaining failures are 3 ELF-prefix ffi-libc tests and 5 missing str-runtime symbols, all classified in `~/.claude/projects/-Users-user/memory/x86_backend_status.md`.

## WebAssembly

```bash
./rail_native wasm examples/wasm/hello.rail
```

```
Compiling examples/wasm/hello.rail to WASM...
  WAT: 51277 bytes
  wat2wasm: OK
  Binary: /tmp/rail_out.wasm
```

Requires `wat2wasm` from the WebAssembly Binary Toolkit (`brew install wabt`). The output is `/tmp/rail_out.wasm` — drop into any WASM runtime that provides the `env.print` import. The live playground at https://ledatic.org embeds exactly this output.

Known WASM-backend limits (see CLAUDE.md): no `filter`/`map`/`fold` as WASM builtins, 1 MB linear memory. Closures, ADTs, pattern matching, and string ops all work.

---

## Adding a backend

Look at `tools/compile.rail` around line 9630 (`main`): the `cmd` dispatch table. Each backend is roughly:

1. A new "emit" pass that walks the AST.
2. A driver function (`compile_x86`, `compile_wasm`, etc.) that calls the right assembler/linker via `shell`.
3. A runtime or startup file under `tools/`.

The Cortex-M4 and RISC-V backends (about 600 lines together) were removed on 2026-10-19: no board or emulator here could test them. They are in tag `archive/tier1-precut-2026-10-19`.
