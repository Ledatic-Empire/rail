# TODO — what's deferred for v0

Per the "honest backlog" discipline, here is what didn't make v0 and why.

## Examples not included in `docs/site/examples/` (with rationale)

- **`examples/native_closures.rail`** — segfaults on this machine (`/bin/sh: line 1: 70740 Segmentation fault`). Excluded until the regression is fixed; the same closure semantics are demonstrated in `examples/closures.rail` and `examples/wasm/closure.rail`.
- **`examples/tail_calls.rail`** — does 2,000,000 tail-recursive calls. Compiles and starts to run, but wall-clock exceeded the 120s timeout I budgeted for the doc-capture pass. The smaller version `examples/tco_test.rail` (1M-iter count_down + 1M-iter sum_acc) is included instead and demonstrates the same property in ~30s.

## Backend verification gaps

- **Linux ARM64**: cross-binutils (`aarch64-elf-as`, `aarch64-elf-ld`) not installed on this workstation; `./rail_native linux ...` was documented from a known-failing run rather than a known-good binary. The path is verified via `tools/compile.rail` reading the toolchain commands directly, but no Pi Zero execution result is captured here.
- **Linux x86_64**: emits `.s` only on macOS hosts. Requires a remote `gcc` to execute. Not exercised end-to-end.

## Documentation gaps deferred

- **Interactive playground**: out of scope; the wasm backend it would need left on 2026-10-21 (tag `archive/tier3-step5-precut-2026-10-21`).
- **Generated `tools/` index** — there are ~50 useful programs under `tools/` (`tools/repl.rail`, `tools/lsp.rail`, `tools/attest/*`, `tools/v5/*`). None have doc pages here; v0 prioritized `examples/`. Follow-up should auto-index `tools/*.rail` similarly to how `stdlib.md` is generated.
- **API stability commitments** — the stdlib reference is descriptive, not normative. Functions whose name starts with `_` (or whose comments mark them as helpers) are not part of any public contract. A separate `stable-api.md` should curate the actual public surface.
- **Tutorial track** — pages walk from `hello` straight to `quicksort`. No deliberate ramp through algebraic data types, type inference, error handling, or the foreign function interface.
- **Compiler internals** — there is no doc on the AST shape, how `compile_program` lays out the binary, or how the GC interacts with the bump arena. The closest existing artifact is `CHANGELOG.md` and the comment headers in `tools/compile.rail`.

## What v0 explicitly does *not* claim

- That every stdlib function listed in `stdlib.md` is robust or documented well. Many have empty docstrings — that's the actual source state, not a generator bug.
- That every example is the "best" version of its concept. They are the existing programs under `examples/` that compile and run. Some teach Rail well; others are smoke tests that happen to live there.
- That the doc site is deployed anywhere. v0 explicitly builds local files only; deploy is a separate task gated on review of these files.

## v0+1: auto-deploy shipped 2026-05-12

The site at https://ledatic.org/rail/docs/ is now auto-deployed by a post-receive hook on the bare rail repo: changes under `docs/site/` pushed to the `next` branch rebuild HTML and upload to Cloudflare KV without manual intervention.
