# Architecture decisions (entropy reduction)

## ADR-1: stdlib depends on nothing in tools/ (2026-11-27)
Context: `stdlib/macho.rail` imported `tools/v5/codebuf.rail`; the assembler and linker used its
functions only through that chain.
Decision: dependencies run tools to stdlib. `codebuf.rail` is a stdlib module; users import it
directly. `tools/verify/stdlib_alone.rail` fails any stdlib file with an `import "tools/` line.
Consequence: the seed was rebuilt once (imports changed). Review trigger: a stdlib module that
truly needs a tool-side file moves the shared part into stdlib instead.

## ADR-2: one copy of a helper, in the lowest layer that can hold it (2026-11-27)
Context: four verify programs each carried the same string helpers; stdlib already had
`starts_with` and `file_exists`.
Decision: stdlib is canonical where it has the function; `tools/verify/lib.rail` holds the rest.
Different semantics stay separate (`tour_check`'s `rstrip_nl` takes a character list).
Consequence: adopting the stdlib `file_exists` exposed a real bug (no NUL terminator on a
`str_sub` path), fixed in `stat.rail`.

## ADR-3: generated facts, not hand-written lists (2026-11-27)
Context: the runtime's environment variables were named in prose in many docs.
Decision: `docs/STATUS.md` generates the list from `runtime/arm64/data.s`; `check.sh` already
fails on drift.

## ADR-4: prototypes with no caller are deleted, gates and fixtures are not (2026-11-27)
Eight unreferenced v5 programs went. `SHIMS.md` keeps the assembler gates and `.s` fixtures.
`dyld_macho.rail` stays while `link_lib.rail` and the tier 3 plan cite it.
