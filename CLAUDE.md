# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Output Discipline

- Keep responses concise to avoid hitting the 500 output token limit; chunk long outputs across multiple turns.
- Avoid verbose explanations and large code dumps in chat: prefer bullet points and structured reports.
- When delivering reports/handoffs, or pasting prompt content/artifacts, write to a file rather than dumping inline.

## Environment

Sessions run on the Mac Mini (the Studio was sold 2026-10-13). Parallel session prompts labeled for other lanes should be declined unless explicitly retargeted.

## Project Conventions

- This is a Rail-on-Rail project: write tooling and helpers in pure Rail, not Python or other languages, unless explicitly asked.

## Verification Discipline

Before declaring a hypothesis confirmed, run the falsification test (e.g., for fp16/precision claims, compare bit-identical loss across runs; for parse-pass criteria, include adversarial garbage-continuation cases). Read runtime/asm before guessing at allocator or memory-pressure causes.

## Hypothesis Discipline

- Before spending >30 min on a perf/regression hypothesis, write it down and define the falsification test.
- Read the actual runtime artifact (asm, logs, sentinel files) before theorizing about exotic causes.
- When a benchmark or measurement looks like a breakthrough, suspect a measurement bug first.

## Session Resumption

- At session start, check for a handoff doc (HANDOFF.md, NEXT_SESSION.md, or recent commit messages) before exploring.
- Verify branch state with `git log --oneline -10` and `git status` before claiming what's merged: don't trust stale memory.

## Rail Compiler

Self-hosting programming language. Compiler written in Rail, compiles itself to ARM64, x86_64, and Linux ARM64.

- **Compiler source**: `tools/compile.rail` (7,782 lines on 2026-10-29; `wc -l`; the measured line is in `docs/STATUS.md`, which CI regenerates and compares; walked in file order by `docs/COMPILER_TOUR.md`, gated by `tools/verify/tour_check.rail`), `tools/types.rail` (type inference, ~1,400) and `tools/ast.rail` (the typed syntax tree)
- **Seed binary**: `rail_native` (1,041,288 bytes ARM64, 2026-10-29): checked into repo, self-compile produces byte-identical output (fixed point); regenerate `docs/STATUS.md` in the same commit as any seed change
- **Native floats**: unboxed IEEE 754 doubles in ARM64 d-registers wherever the compiler has proved float; boxed (tag 6) only when stored into a tuple, list or ADT field or passed generically, and read back through `_rail_fval` (docs/NUMERICS.md, 2026-09-11). Float arrays, foreign float calls (`sin`/`cos`/`tanh`/`sqrt`), auto int→float promotion.
- **REPL**: `./rail_native run tools/repl.rail`: interactive, persistent definitions
- **Error messages**: `file:line:col: error: message`: parse errors halt cleanly instead of segfaulting.
- **Runtime**: Zero C dependencies. ARM64 assembly in `runtime/arm64/*.s` (the GC included); `tools/gen_runtime.rail` regenerates `tools/runtime_arm64.rail`, which the compiler imports and embeds (and `tools/decimal64_src.rail`, the text of `tools/decimal64.rail` the compiler compiles into any program that calls `parse_float`). Edit the `.s`, regenerate, bootstrap twice (`runtime/arm64/README.md`).
- **GC**: Conservative mark-sweep garbage collector in ARM64 assembly. Scans stack frames, marks reachable tagged objects, sweeps into free list. Triggered when the arena's bump allocation fails; `RAIL_GC_STRESS=N` forces one every Nth allocation.
- **Allocator**: bump arena inside a 64 GB address reservation that grows in place (`RAIL_ARENA_MB` is where the first collection happens, default 1 GB) + GC free list; no malloc spill on macOS. 256MB thread stack. `arena_mark`/`arena_reset` still work.
- **Effect handlers**: `try body handler`: setjmp/longjmp non-local error recovery. Deep unwinding, nested handlers.
- **Type checker**: Forward inference pass emits warnings (not errors) for: head/tail on non-list, arithmetic on non-numeric, wrong arity, calling non-functions.
- **Package manager**: `import math` (bare imports), `rail get github.com/...`, `rail pkg` reads `rail.toml`.
- **Tests**: `./rail_native test`: 253/253 on master (2026-10-29, t269: a missing quoted import is refused and a quoted import resolves beside the compiler; t267: a user-declared foreign float fn's raw result, t268: the binary32 builtins; before them 250 after Tier 3 step 9, a test per sentence of docs/NUMERICS.md). Count fluctuates only when concurrent sessions collide on `/tmp/rail_out`; rerun with `--out-prefix` to confirm.
- **Performance**: Tail-recursive loops match C -O2 (5 instructions/iteration). Self-loop optimization, untagged register params, bottom-test with `subs`.
- **Targets**: macOS ARM64 (native), Linux ARM64 (Pi Zero), Linux x86_64 (cross-compile)

### Key Commands

```bash
./rail_native test                    # run the suite (253/253)
RAIL_ARENA_MB=6000 ./rail_native self # self-compile: the compiler compiles tools/compile.rail and
                                      #   links it in process (tools/v5/link_lib.rail: assembler,
                                      #   Mach-O linker, ad-hoc signer). One link path since Tier 3
                                      #   step 6 (2026-10-21): every compile goes this way; no as,
                                      #   ld or codesign runs on macOS. The seed is byte-identical
                                      #   at any arena from 2000 up (CI uses 3000, 5.4 GB peak);
                                      #   below 2000 the compiler refuses (its source thrashes).
                                      #   Output /tmp/rail_self; cmp it with rail_native.
./rail_native run file.rail           # compile + execute
./rail_native file.rail               # compile only → /tmp/rail_out
./rail_native x86 file.rail           # compile to x86_64 Linux → /tmp/rail_x86.s
./rail_native linux file.rail         # cross-compile to Linux ARM64 → /tmp/rail_linux
python3 tools/fuzz/gc_stress.py      # every suite test and tree program under RAIL_GC_STRESS
                                      #   (collect every Nth allocation, poison what is freed)
./rail_native get <package>           # install package (stdlib name or github.com/user/pkg)
./rail_native pkg                     # install dependencies from rail.toml
```

### Runtime Safety

- `head []` returns 0 (not segfault). `head` on non-list returns 0.
- `tail []` returns `[]`. `tail` on non-list returns `[]`.
- Type errors on head/tail are graceful. Other type errors (arithmetic on strings, calling non-functions) may still segfault.

### Known Compiler Limitations

- **`split` is single-character**: `split "abc" s` splits on `a`, `b`, and `c` individually. Use `str_split` for multi-char delimiters.
- **Polymorphic show**: `show` works on ints, floats, strings, lists (including nested), nil, tuples `(1, 2)` and constructed values `Some (Pair 1 2)`, and prints `true`/`false` where the compiler knows the value is a bool. Closures are not supported.
- **Exhaustive match**: Non-exhaustive `match` is a compile-time error (not warning). Runtime trap on fallthrough.
- **`read_line` zero-arg**: Use `read_line 0` (pass dummy arg): zero-arg dispatch has a codegen quirk in the V-handler.
- **Float representation comes from the types** (`tools/types.rail`, `docs/TYPES.md`): a parameter or result whose type is float travels as raw bits; one that untyped data (`dyn`) can reach stays generic. `show(user_func(1.0))` still won't pick the float printer; use `show_float` explicitly.
- **Float self-loop TCO**: Deferred: `body_has_float` guard prevents int-TCO corruption but float-specific d8-d15 TCO not yet implemented.
- **Deeply-nested `match` chains**: A `match | ADT -> match | ADT -> ...` chain 5+ levels deep inside a function body with side-effecting `let`s after it triggers "expected decl" parse errors. **Workaround**: flatten multiple `match`es into a single chained form on one indent level: all ADT destructures at the top of the function body followed by a linear `let` stream (the pattern that works lived in `tools/train`, now in the private rail-lab).
- **A top-level name you define replaces a stdlib function of the same name everywhere, the stdlib's own callers included, with no warning** (2026-10-29): a program's `hex_digit` broke `hex_to_bytes`, `sha256` and `sha512`. Treat imported names as reserved; prefix your helpers.
- **A program that imports the TLS stack does not compile at the default arena** (2026-10-29, found by the examples gate): `import "stdlib/https_client.rail"` is 26 files and 269 KB of source with its imports; at the default 1 GB arena the collector thrashes (examples/life_beacon.rail ran 11 minutes of CPU without finishing), at `RAIL_ARENA_MB=1500` and above it compiles in 1.5 s (peak 2.86 GB resident at 6000). `tools/verify/examples_check.rail` compiles every example at 3000. The compiler should notice a large program at the default arena and does not yet.
- **A quoted import (`import "stdlib/x.rail"`) is read from the current directory, then from beside the compiler; a file found nowhere is a compile error** (`resolve_quoted_import`, t269, 2026-10-29). Until that day it was read from the current directory only and a missing one was a WARNING per name, so the program died at load (`dyld: Symbol not found`); `tools/verify/numerics_vs_c/run_ci.sh` was bitten.
- **Mixed float+int arithmetic (v2.1.2)**: `0.0 + int_expr` now promotes correctly even when the int operand's type can't be statically inferred. The O-handler emits a runtime `tst x, #1` path that picks scvtf or fmov based on the tag bit. Regression test: `t106 mixed_float_int_op`.

### Modifying the Compiler

Read `docs/COMPILER_TOUR.md` to find your way (eighteen banners, one section each, in file order; a renamed symbol or a moved section fails `tools/verify/tour_check.rail` until the tour catches up) and `docs/COMPILER_BOOTSTRAP.md` before editing `tools/compile.rail`: bootstrap cycles, the diagnostic pattern, the data-section and ASCII-only traps. Always: `RAIL_ARENA_MB=6000 ./rail_native self`, then `./rail_native test` (every test must pass), then self again and `cmp` for the fixed point.

## Substrate beyond compile.rail (shipped 2026-05-11)

Foundation tools that landed 2026-05-11 and are still here (the lint, trace and package tools left for `rail-lab` on 2026-09-22). **Use them. Don't redo them.**

| Tool | Path | When |
|---|---|---|
| Test runner | `./rail_native run tools/test/rail_test.rail <dir>` | New tests. Convention: exit 0 AND last-line `PASS`. Exit-code-honest (relies on the 2026-05-02 fix) |
| Diff fuzzer | `./rail_native run tools/fuzz/diff_fuzz.rail --seed=42 --n=20` | Before any compile.rail change. Catches silent miscompilation via two-path differential eval. Int-only grammar today |
| Stdlib docs | `./rail_native run tools/docs/gen_stdlib_ref.rail` | After any stdlib edit, regen `docs/site/stdlib.md` |

Public docs: **https://ledatic.org/rail/docs/**: md→html build + deploy recipe in memory entry `docs_deploy_rail.md`.

### Recent emit-class gotchas surfaced by foundations work

- **Phantom builtins**: a name the type checker knows (`tc_builtin_ret` in the CHECKS section) but `cg_bi` to `cg_bi3` do not emit links to nothing and fails at link as an undefined identifier (loud since Tier 3 step 6). `trim` is the classic: define it locally (`trim s = head (split "\n" s)`) or extend the emit.
- **`to_int "42"` silently returns 0**: `to_int` is float→int only. There is no string-to-int builtin. Write a digit-walking helper inline.
- **3-movk codegen** (FIXED 2026-05-12, `feat/c-3-movk-literals`): `emit_load_int_reg` (CODEGEN SUPPORT section) emits movz + up to 3 movk chunks (bits 0-15, 16-31, 32-47, 48-63), with zero chunks at >=#32 skipped. Both positive (`movz`+`movk`) and negative (`movn`+`movk` with inverted bits) paths handle the full 64-bit range. Regression tests: t132 (3-movk), t133 (4-movk), t134 (4-movk negative). Note: `k16/k32/k48` constants computed via `shl 1 N` so `opt` constant-folding doesn't bake them as 64-bit literals the seed can't emit.

## Related repos

Rail is the compiler + stdlib. A few things that used to live here moved out on 2026-04-20:

- **Training infrastructure** → [`Ledatic-Empire/rail-training`](https://github.com/Ledatic-Empire/rail-training) (private). Flywheel orchestrator, dataset pipeline, model cards, small corpora. Weights kept on disk, not in git. Depends on `rail_native` + stdlib from this repo.
- **Website source** → [`Ledatic-Empire/ledatic-site`](https://github.com/Ledatic-Empire/ledatic-site) (public). Hand-rolled HTML/CSS/JS/GLSL for ledatic.org, plus the Cloudflare Worker. The Rail-written generators (`daily_deploy`, `gen_site`, `gen_feed`, `gen_llms`, `cf_deploy`) live there too since 2026-10-21, under `railgen/`, run with cwd `~/projects/rail-https`.
- **UAV / AIGP** → [`Ledatic-Empire/zemog`](https://github.com/Ledatic-Empire/zemog) (private). Nested at `tools/uav/` in the working tree (gitignored).

## What left, and where it went

`tools/train`, `tools/railml`, `tools/bench`, `tools/infer`, the lint, trace and package tools: the private
`rail-lab` (2026-09-22, 2026-10-20). The entropy beacon: `Ledatic-Empire/rail-plasma` (2026-10-20). Metal,
`gpu_map`, the stdlib ML stack (`tensor`, `transformer`, `optim`, `checkpoint`, `infer_kv`, the `jit_*` modules),
`jit/`, the wasm backend with `rail safe`, `tools/{bitexact,tls,auth,audit,deploy}`: cut 2026-10-21 in Tier 3
step 5, tag `archive/tier3-step5-precut-2026-10-21` (`docs/rail-tier3-record-plan.md`). The site generators are
`ledatic-site/railgen/`. `tools/fleet` leaves once the owner repoints the `tb_autojoin` root daemon.

## Cross-compile (Linux ARM64 for Pi Zero / similar)

```bash
./rail_native linux tools/compile.rail && scp /tmp/rail_linux <host>:~/rail_native
```

Runtime libs live at `tools/linux_libc.s` and `tools/linux_data.s`.
