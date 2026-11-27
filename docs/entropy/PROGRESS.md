# Entropy reduction: progress, task pool, decisions

Branch `entropy/2026-11-27`, worktree `.claude/worktrees/entropy`, based on master c21b627.
Not pushed. A human opens and merges the PR.

## Constraints that bound every round

- Seed `rail_native` must stay at its fixed point. A round that edits `tools/compile.rail`, its
  imports or `runtime/` rebuilds it and regenerates `docs/STATUS.md` in the same commit.
- `releases/`, `builds/`, `selfhost/` and `docs/history` are records. Not touched.
- `tools/fleet` waits on the owner's daemon repoint (CLAUDE.md). Not touched.
- `SHIMS.md` says the `tools/v5/*.s` fixtures and gate diffs are never deleted.

## Gate (run after every batch)

```
RAIL_ARENA_MB=4096 ./rail_native test                      # 323/323
RAIL_ARENA_MB=6000 ./rail_native self && cmp rail_native /tmp/rail_self
bash tools/verify/check.sh                                  # passed 8, failed 0
```

## Map (measured 2026-11-27)

| Area | Tracked files | Notes |
|---|---|---|
| `tools/compile.rail`, `types.rail`, `ast.rail` | 3 | 8,679 + 1,378 + 207 lines. The one compiler. |
| `tools/v5` | 18 after round 2 | Live: `link_lib`, `asm`, `arm64`. Gates and fixtures: kept. |
| `stdlib` | 61 | Each module checked alone by `tools/verify/stdlib_alone.rail`. |
| `tools/test`, `tools/fuzz`, `tools/verify` | 61, 79, 23 | Suite, differential fuzzer, gates. |
| `tools/fleet`, `tools/attest` | 23, 26 | Four fleet agent variants; fleet is deferred. |

## Rounds

1. Deleted eight unreferenced v5 prototypes (`CHANGELOG.md` Unreleased, Removed). Callers found: none.
2. `codebuf.rail` moved to `stdlib` (the layering inversion), three uncalled functions deleted, seed rebuilt (fixed point, 323/323, `stdlib_alone` 62).
3. Verify helpers deduplicated into `tools/verify/lib.rail`; stdlib `file_exists` NUL bug fixed; runtime env vars generated into STATUS.md. Scans done: stdlib has no import cycle and no stdlib-to-tools import.

## Task pool (evidence in brackets)

- `tools/fleet/fleet_agent.rail`, `fleet_agent_v3.rail`, `fleet_agent_x86.rail`: 11 to 16 shared top-level names. Deferred until the daemon repoint.
- `tools/test` (61 files, 10k lines) and `tools/fuzz` helpers: duplicate scan not yet done.
- Same-meaning one-liners repeated in stdlib: `a_trim_line` (anthropic_client), `sk_trim_line` (slack_client), `par_rstrip_nl` (parallel) and `trim` in compile.rail and four tools. Each module must compile alone, so a shared home needs a stdlib module the clients import.

## Pending confirmation (needs the owner)

- Whether the `dyld_macho.rail` reference program should go too. `link_lib.rail` cites it in comments and `docs/rail-tier3-record-plan.md` names it, so it stays for now.
- Four fleet agent variants: which is canonical is the owner's call.
