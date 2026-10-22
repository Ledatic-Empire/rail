# Contributing to Rail

Rail is a real project with a narrow but honest feature set. Contributions are welcome: this file covers build, test, and the practical bar for a patch that lands.

## Build + test in 30 seconds

```bash
git clone https://github.com/Ledatic-Empire/rail
cd rail

./rail_native test                          # the suite: the last line is N/N tests passed, exit 0 only then
RAIL_ARENA_MB=6000 ./rail_native self       # self-compile -> /tmp/rail_self (about 6 s)
cmp rail_native /tmp/rail_self              # silent: the committed seed is what its own source builds
```

The `cmp` is silent on a clean tree. Since Tier 3 step 6 (2026-10-21) CI rebuilds the committed
seed from source on a GitHub runner and compares the bytes; a difference there is a bug.

If any of those three fails on `master`, that is a bug: please open an issue.

## Prerequisites

- Apple Silicon Mac (ARM64 macOS) is the primary development target.
- No other dependencies. The compiler assembles, links and code-signs itself in
  process (`tools/v5/link_lib.rail`); no Xcode `as`, `ld` or `codesign` runs, and
  since Tier 3 step 6 there is no other link path. Below `RAIL_ARENA_MB=2000` the
  self-compile refuses (the compiler's own source thrashes there); 6000 is the usual
  setting, CI uses 3000.

Linux ARM64 and Linux x86_64 work as cross-compile targets. See `./rail_native linux` and `./rail_native x86`.

## The bar for a compiler patch

The compiler is `tools/compile.rail` (one file; the measured line count is in `docs/STATUS.md`). It compiles itself. Read [`docs/COMPILER_TOUR.md`](docs/COMPILER_TOUR.md) first: it walks the file section by section in file order, and a gate keeps it honest. Every change goes through this loop:

```bash
# 1. Edit tools/compile.rail.

# 2. Compile the compiler with the OLD binary.
RAIL_ARENA_MB=6000 ./rail_native self                        # → /tmp/rail_self

# 3. Install the new binary.
cp /tmp/rail_self ./rail_native

# 4. Verify the test suite still passes.
./rail_native test                        # every case: N/N tests passed, exit 0

# 5. Verify the fixed-point property (≥2 cycles).
RAIL_ARENA_MB=6000 ./rail_native self && cp /tmp/rail_self ./rail_native
RAIL_ARENA_MB=6000 ./rail_native self
cmp rail_native /tmp/rail_self            # must be silent
```

Step 5 is the hard part. The bootstrap is a 2-cycle limit cycle: gen0's shipped runtime asm does not necessarily match what gen0's source emits, so cycle 1 typically produces a different binary. Cycle 2 always lands the byte-identical fixed point (gen2 == gen3 == gen4). If `cmp` is silent after running `self` twice in a row from an already-installed binary, you have converged. If cycle 3 still differs from cycle 2, something in your codegen is non-deterministic and wants investigation (the 2026-05-13 convergence audit falsified the claim that the bootstrap does not converge; its note left with the tool shed in #80).

If you change the runtime (`runtime/arm64/*.s`: equality, lists, strings, the collector), run `./rail_native run tools/gen_runtime.rail` first, then remember the old binary generates the old runtime. You have to bootstrap twice: compile, install, compile again with the new binary. `runtime/arm64/README.md` has the file format.

## The bar for an stdlib patch

Adding or modifying `stdlib/*.rail`:

- **Test it.** Put it in the suite (`run_tests` in `tools/compile.rail`) or as a standalone program under `tools/test/`. "Standalone" means `./rail_native run tools/whatever/my_test.rail` prints `PASS` when it works. That's the assertion contract.
- **Crypto code validates against an RFC or NIST vector.** Hand-derived expected values introduced bugs twice on the TLS branch; canonical data is load-bearing.
- **Respect the import graph.** Rail imports don't dedupe. Two textual imports of the same module cause duplicate-symbol link errors. When in doubt, imitate existing modules: leaf modules import nothing and rely on the caller's chain to provide `hex_to_bytes`, `sha_copy_bytes`, etc.

## Parser quirks you will hit

The full list lives in `CLAUDE.md`. The top five:

1. **No hex literals.** `0xFF` silently parses as `0`. Use `hex_to_bytes "ff"` for crypto constants.
2. **Leading `+` on a continuation line is a parse error.** Keep multi-line arithmetic on one physical line or parenthesise: `(a + b)\n(+ c)` fails, `(a + b) + c` on one line works.
3. **Deeply-nested `if / else` with side-effecting `let`s** between them can trigger an "expected decl" parse error or a multi-minute compile hang. Factor the deep arms into separate helper functions.
4. **`split` is single-character.** `split "abc" s` splits on `a`, `b`, `c` individually. Use `str_split` for multi-char delimiters.
5. **`to_int` is float-only.** For string → int use `parse_int` (walks `chars` via `char_to_int`).

## Code style (soft)

Rail codebases tend to use a terse functional style:

- Short, lowercase function names: `add`, `fib`, `eval`, not `addTwoNumbers`.
- Named functions defined before `main =`.
- `let _ = print "..."` for side-effect expressions.
- `show n` for int-to-string; `show_float` for floats.
- Single-line comments with `-- ` prefix.
- Named predicates preferred over lambdas in `filter` (lambdas in filter have segfault history).

## Submitting changes

1. Fork and make a feature branch.
2. Run `./rail_native test` and, if you touched the compiler, the fixed-point dance.
3. Open a PR with a clear description of what changed and why.
4. If you added crypto, point at the RFC section your test vector is from.

For bigger changes, opening an issue first to talk about the approach saves time.

## Reporting security issues

See [SECURITY.md](SECURITY.md). Rail's crypto is **not** constant-time and has no side-channel-resistance guarantees. Don't deploy the crypto to side-channel-sensitive environments; that's not what it's for.

## License

By contributing, you agree your contributions are licensed under the same terms as Rail (Business Source License 1.1, converts to MIT on 2030-03-14). See [LICENSE](LICENSE).
