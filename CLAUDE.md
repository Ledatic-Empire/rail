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

- **Compiler source**: `tools/compile.rail` (its line count is in `docs/STATUS.md`, which CI regenerates and compares; no count is written here, where two had gone stale by 2026-11-18; walked in file order by `docs/COMPILER_TOUR.md`, gated by `tools/verify/tour_check.rail`), `tools/types.rail` (type inference, ~1,400) and `tools/ast.rail` (the typed syntax tree)
- **Seed binary**: `rail_native` (ARM64; bytes and hash in `docs/STATUS.md`): checked into repo, self-compile produces byte-identical output (fixed point); regenerate `docs/STATUS.md` in the same commit as any seed change
- **Native floats**: unboxed IEEE 754 doubles in ARM64 d-registers wherever the compiler has proved float; boxed (tag 6) only when stored into a tuple, list or ADT field or passed generically, and read back through `_rail_fval` (docs/NUMERICS.md, 2026-09-11). Float arrays, foreign float calls (`sin`/`cos`/`tanh`/`sqrt`), auto int→float promotion.
- **REPL**: `./rail_native run tools/repl.rail`: interactive, persistent definitions
- **Error messages**: `file:line:col: error: message`: parse errors halt cleanly instead of segfaulting.
- **Runtime**: Zero C dependencies. ARM64 assembly in `runtime/arm64/*.s` (the GC included); `tools/gen_runtime.rail` regenerates `tools/runtime_arm64.rail`, which the compiler imports and embeds (and `tools/decimal64_src.rail`, the text of `tools/decimal64.rail` the compiler compiles into any program that calls `parse_float`). Edit the `.s`, regenerate, bootstrap twice (`runtime/arm64/README.md`).
- **GC**: Conservative mark-sweep garbage collector in ARM64 assembly. Scans stack frames, marks reachable tagged objects, sweeps into free list. Triggered when the arena's bump allocation fails; `RAIL_GC_STRESS=N` forces one every Nth allocation.
- **Allocator**: bump arena inside a 64 GB address reservation that grows in place (`RAIL_ARENA_MB` is where the first collection happens, default 1 GB) + GC free list; no malloc spill on macOS. 256MB thread stack. `arena_mark`/`arena_reset` still work.
- **Effect handlers**: `try body handler`: setjmp/longjmp non-local error recovery. Deep unwinding, nested handlers.
- **Type checker**: Forward inference pass emits warnings (not errors) for: head/tail on non-list, arithmetic on non-numeric, wrong arity, calling non-functions.
- **Package manager**: `import math` (bare imports), `rail get github.com/...`, `rail pkg` reads `rail.toml`.
- **Tests**: `./rail_native test`: 323/323 on `lowbit/asm-forms-on-master` (2026-11-24, t336 to t339: `<=.` and `>=.`, the dotted-op type, fabs refused, an import's own file named in a decl-level error, and t281 from the lowbit branch: the vector forms, `docs/handoff/2026-11-24.md`; 2026-11-19, t306 to t335: the worklist's stragglers, `docs/handoff/2026-11-19.md`; 2026-11-18, t283 to t305: the worklist's fixes, one test per repro, `docs/handoff/2026-11-18.md`; before that, 2026-11-04, t277: a one-operand branch keeps its label when a comment follows, and an undefined local label is refused; t276: the scalar forms a bf16 scale and the blk8 rounding need, each held to clang; t273: write_file names the path on stderr and returns 1 when its fopen fails; t272: a call to a name nothing defines is refused by name at link instead of dying at load; t271: a frame past 4,095 bytes is entered in legal steps and the assembler refuses an immediate it cannot hold; t270: a program that redefines an imported name is warned; t269: a missing quoted import is refused and a quoted import resolves beside the compiler; t267: a user-declared foreign float fn's raw result, t268: the binary32 builtins; before them 250 after Tier 3 step 9, a test per sentence of docs/NUMERICS.md). Count fluctuates only when concurrent sessions collide on `/tmp/rail_out`; rerun with `--out-prefix` to confirm.
- **Performance**: Tail-recursive loops match C -O2 (5 instructions/iteration). Self-loop optimization, untagged register params, bottom-test with `subs`.
- **Targets**: macOS ARM64 (native), Linux ARM64 (Pi Zero), Linux x86_64 (cross-compile)

### Key Commands

```bash
./rail_native test                    # run the suite (323/323)
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
- Type errors on head/tail are graceful. The compiler refuses the type errors a literal makes evident (`"a" - 1`, a string literal passed to a function that adds to that parameter, `let g = 5` then `g 3`; t295 to t297, 2026-11-18); other type errors (arithmetic on a string that arrives through a variable, calling a non-function parameter) still compile and may segfault. `rail types` reports more and is advice, not a gate: it also reports working programs.

### Known Compiler Limitations

- **`split` is single-character**: `split "abc" s` splits on `a`, `b`, and `c` individually. Use `str_split` for multi-char delimiters.
- **Polymorphic show**: `show` works on ints, floats, strings, lists (including nested), nil, tuples `(1, 2)` and constructed values `Some (Pair 1 2)`, and prints `true`/`false` where the compiler knows the value is a bool. Closures are not supported.
- **Exhaustive match**: Non-exhaustive `match` is a compile-time error (not warning). Runtime trap on fallthrough.
- **`read_line` zero-arg**: Use `read_line 0` (pass dummy arg): zero-arg dispatch has a codegen quirk in the V-handler.
- **Float representation comes from the types** (`tools/types.rail`, `docs/TYPES.md`): a parameter or result whose type is float travels as raw bits; one that untyped data (`dyn`) can reach stays generic. `show(user_func(1.0))` still won't pick the float printer; use `show_float` explicitly.
- **Float self-loop TCO**: Deferred: `body_has_float` guard prevents int-TCO corruption but float-specific d8-d15 TCO not yet implemented.
- **A nested `match` closes by layout** (2026-11-18, t290): an arm that starts left of the inner match's arms belongs to the enclosing match. Until then the inner match took every following arm, and the two-level case reported a false "non-exhaustive match"; the flattening workaround is no longer needed.
- **`&&` and `||` short-circuit** (2026-11-18, t293). Until then both sides always ran; a nested `if` written for the old rule means the same thing.
- **A top-level definition named like a builtin is a compile error** (2026-11-18, t292; `builtin_redefined`). It used to compile and never run: every call reached the builtin. `cat xs = join "" xs` is the one exemption. A new builtin goes in `builtin_call_names` as well as the `cg_bi` dispatch; t287 fails when the two lists differ.
- **Arrays are bounds-checked on ARM64** (2026-11-18, t299 to t301): `arr_get`/`arr_set` outside the array and `arr_new` with a negative length print a message and exit 1. Float arrays and the x86_64 backend are unchecked.
- **`error "msg"` outside `try` returns a value and the program continues** (t90 pins it); only inside `try` does it leave the body. Integers are 63-bit and wrap silently. Non-tail recursion deep enough to exhaust the stack dies with `Bus error: 10` and no Rail message.
- **A run right after a crashed run of the same path was `Killed: 9` (exit 137)** until 2026-11-19: the linker wrote the new binary into the old file and macOS judged it by the cached signature. `stdlib/macho.rail` now writes `path.new` and renames (10 of 10 crash-then-run rounds clean). A `Killed: 9` today is something else: investigate it.
- **A top-level name you define replaces a stdlib function of the same name everywhere, the stdlib's own callers included** (2026-10-29): a program's `hex_digit` broke `hex_to_bytes`, `sha256` and `sha512`. Since the same evening the compiler prints `WARNING: 'hex_digit' is defined in <file> and by an import ...` (`warn_shadowed`, t270) and compiles anyway. Treat imported names as reserved; prefix your helpers.
- **The flat free list is scanned next-fit** (runtime/arm64/gc_1.s, 2026-10-29). Until that day it was first-fit from the head, and the sweep prepends, so every request the youngest small blocks could not serve walked them all: a program that imports the TLS stack (26 files, 269 KB of source) took minutes at the default 1 GB arena (examples/life_beacon.rail ran 11 minutes of CPU without finishing) and 1.5 s at `RAIL_ARENA_MB=1500`. With the rover it compiles in 1.9 s at the default (peak 2.73 GB resident); the self-compile is unchanged at about 6 s. A large program that is slow to compile is now a finding, not a known cost.
- **A quoted import (`import "stdlib/x.rail"`) is read from the current directory, then from beside the compiler; a file found nowhere is a compile error** (`resolve_quoted_import`, t269, 2026-10-29). Until that day it was read from the current directory only and a missing one was a WARNING per name, so the program died at load (`dyld: Symbol not found`); `tools/verify/numerics_vs_c/run_ci.sh` was bitten.
- **A stdlib module imports what it uses, and CI checks each one alone** (`tools/verify/stdlib_alone.rail`, 2026-10-30). Top-level names are one flat space, so a module could lean on names its importers happened to bring; 18 of 61 did, and a program importing one alone died at load until #182 made the compiler refuse an undefined name. When you add a module or a call into another module, import that module: the gate fails by name otherwise.
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
