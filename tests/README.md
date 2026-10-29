# Tests

Rail's test suite runs inside the compiler binary. Its source is the `run_tests` function
of `tools/compile.rail` (the section banner reads TEST HARNESS; `docs/COMPILER_TOUR.md`
section 14 explains the runner). Each case is a `run_test` call: a name, a Rail program as
a string, and the expected output.

```bash
./rail_native test
```

The last line is `N/N tests passed` and the exit status is 0 only when every case passed:
`run_tests` counts its booleans and compares the total with a literal at the end of the
function, so a case that is dropped by mistake fails the run instead of shrinking it. The
count is measured, not quoted: read it off the last line, or from `~/.fleet/state` on the
house machines. `tools/verify/tour_check.rail` fails CI when this file, `CONTRIBUTING.md`
or the tour quotes a count other than that literal (since 2026-10-29 also `README.md` above its Releases
header, `docs/getting-started.md`, `VERIFY.md`, `STRUCTURE.md`, `docs/INDEPENDENCE.md` and
`docs/STATUS.md`). A run on macOS ARM64 takes about 80 s (82.7 s wall on an M4 Pro, 2026-10-29).
Concurrent runs on one host do not collide (each case builds to a `mktemp` path); a flaky
count usually means an orphan `rail_native` from an earlier run (`ps aux | grep rail_native`).

How a case is judged (`judge_test`): a program that prints nothing asserts on its exit
status (the value `main` returns); a program that prints asserts on its whole stdout and must
not have died by signal. `run_env` runs a case under an environment variable (the arena size,
the collector's stress knob). The runner tests its own judge (`runner_judges_evidence`).

## Self-hosting fixed point

After modifying codegen, also verify the byte-identical self-compile:

```bash
RAIL_ARENA_MB=6000 ./rail_native self
cmp rail_native /tmp/rail_self      # silent: the committed seed is what its source builds
```

CI does the same at `RAIL_ARENA_MB=3000` on a GitHub runner and then compiles the result
once more for the fixed point. `docs/COMPILER_BOOTSTRAP.md` has the cycle rules.

## What the cases cover

In the order they appear in `run_tests`:

- The language core: literals, arithmetic, `if`, `let`, functions, strings, lists, tuples,
  closures and lambdas, ADTs and `match`, file and shell I/O, imports (plain, qualified,
  bare, a diamond built once).
- Integer literals across the 63-bit range (the movz and movk chunking, negative constants,
  wrap at the edges) and the bit operations the crypto is built on.
- Floats: the dotted operators, mixed int and float promotion, float parameters and results
  as the types decide them, the boxing boundary into tuples, lists and ADT fields, and the
  bits of literals, `parse_float`, reductions and operations (`docs/NUMERICS.md` names the
  test behind each of its sentences).
- The collector and the arena: mark and reset, collection under a small arena, the stress
  knob, a frame's sibling slots, growth with live and with garbage data, two threads on one
  heap.
- Tail calls and self-loops: the register loop, its argument shapes, big constants in it.
- Strings, maps, buffers, arrays and bytes; `show` for every value kind; structural equality.
- Effects and concurrency: `try`, threads, channels, fibers, reference counting.
- Crypto and TLS against published vectors: SHA-256, HMAC and HKDF, ChaCha20-Poly1305,
  X25519, Ed25519 (RFC 8032), ECDSA P-256 (RFC 6979), the TLS 1.3 key schedule, record layer
  and handshake messages (RFC 8448), certificate signature and hostname checks.
- Authenticated types: the `auth` field modifier, digests, the synthesized prover and
  verifier accepting a proof and rejecting a tampered leaf, node, root or dictionary.
- Autograd: forward and reverse mode through `let`, `if` and `match`, transcendental
  functions, multiple inputs.
- Patterns and checks: guards, variable and boolean patterns, constructors as values,
  non-exhaustive matches and bad patterns as errors.
- The compiler as a command (the `driver_` cases): `run` hands back the program's exit
  code, a bare `self` refuses, `rail types` infers and reports errors, the import diamond,
  the small-arena and stressed collector runs.

## The other gates

| Gate | Command | What it proves |
|---|---|---|
| Quick smoke | `./rail_native quick` | fifteen cases across parse, codegen, GC, floats, TCO, closures, ADTs (about 5 s) |
| Collector stress | `python3 tools/fuzz/gc_stress.py` | every suite case and tree program gives the same answer with a collection every Nth allocation and freed blocks poisoned |
| Independent semantics | `python3 tools/fuzz/semantic.py --seed 42 --cases 20` | native execution agrees with an oracle written outside Rail (`tools/fuzz/SEMANTICS.md`) |
| Known miscompiles | `python3 tools/fuzz/known_cases.py` | the fixed cases of `tools/fuzz/known` still pass and the open ones still fail (`tools/fuzz/KNOWN_CASES.md`) |
| Float literals | `python3 tools/fuzz/float_literals.py --seed 7 --cases 300` | generated literals get CPython's bits through both doors (the compiler and `parse_float`) |
| Differential fuzz | `./rail_native run tools/fuzz/diff_fuzz.rail --seed=42 --n=20` | two evaluation paths agree on generated integer programs |
| Standalone programs | `./rail_native run tools/test/rail_test.rail tools/test` | every `test_*.rail` under `tools/test` exits 0 and prints PASS last |
| Runtime copy | `./rail_native run tools/gen_runtime.rail check` | `runtime/arm64/*.s` and the compiler's embedded copy agree |
| Seed format | `bash tools/independence/seed_format_gate.sh` | a Python writer written from `docs/SEED_FORMAT.md` produces the bytes the Rail linker writes |
| The reader's path | `./rail_native run tools/verify/tour_check.rail` | `docs/COMPILER_TOUR.md` cites symbols and paths that exist, in the compiler's banner order, and every quoted test count is the suite's |
| The whole kit | `tools/verify/check.sh --quick` | the quick suite, the grammar, the live status matrix (`VERIFY.md`) |

CI (`.github/workflows/ci.yml`) runs the suite, the self-compile with its `cmp`, the
runtime check, the seed format gate, the tour gate, the semantic oracle, the known cases and
the collector stress run on every push and pull request.
