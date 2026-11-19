# Backends

One Rail compiler, three targets. All driven from the same `rail_native` binary.

| Backend | Verb | Output | Toolchain needed | Status (local-verified) |
|---|---|---|---|---|
| macOS ARM64 (Mach-O) | _(default)_ / `run` | `/tmp/rail_out` | none (Rail assembles, links and signs in process) | runs end-to-end |
| Linux ARM64 (ELF) | `linux` | `/tmp/rail_linux` | `aarch64-elf-as`, `aarch64-elf-ld` | needs cross-binutils |
| Linux x86_64 (ELF, source-only) | `x86` | `/tmp/rail_x86.s` | remote `gcc` (or Docker `linux/amd64`) | emits `.s`; executed only by CI (`numerics-x86`, the known-case corpus) |

---

## macOS ARM64 (Mach-O)

This is the primary target. No flags, no setup.

```bash
./rail_native run examples/hello.rail
```

```
Compiling examples/hello.rail (244 chars)...
wrote /tmp/rail_out (50104 bytes); imports=10 rebases=11 main@0x1000005ac
  link: OK
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

**What differs from macOS** (measured 2026-11-19 on a Pi Zero 2 W; there is no libc, the
runtime's C calls are `tools/linux_libc.s`):

- `spawn_thread` is not built: the program prints
  `rail: spawn_thread is not supported on Linux ARM64` and exits 1. The mutex calls succeed.
- The heap is a fixed 1 GB reservation; `RAIL_ARENA_MB` does not resize it.
- `try`, errors, array bounds and the text of floats (`show_float`, `show_float_exact`,
  `show`) are the same as on macOS. Before 2026-11-19 an error inside `try` ended the program
  with status 1 and floats printed with six decimals.

**Conformance:** no CI job executes this backend. `tools/test/linux_arm64_check.sh user@host`
runs the programs in `tools/test/linux_arm64/` on macOS and on an aarch64 Linux host and
requires the same output and exit status (16,378 float strings among them).

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

**Conformance:** CI's `numerics-x86` job (Linux x86_64) builds and runs the known-case corpus, `python3 tools/fuzz/x86_known.py run` over `tools/fuzz/known/x86_cases.json`; that is the only place this backend executes. `rail_native x86` itself reports an undefined name and a failed assemble with exit 1 (2026-11-19). The Docker script that once reported 71/79 here was removed on 2026-11-19: it copied a stub file that had left the tree, so it could not run.

## Adding a backend

Look at `tools/compile.rail` around line 9630 (`main`): the `cmd` dispatch table. Each backend is roughly:

1. A new "emit" pass that walks the AST.
2. A driver function (`compile_x86`, `dispatch_linux`, etc.) that calls the right assembler/linker via `shell`.
3. A runtime or startup file under `tools/`.

The Cortex-M4 and RISC-V backends (about 600 lines together) were removed on 2026-10-19: no board or emulator here could test them. They are in tag `archive/tier1-precut-2026-10-19`.
