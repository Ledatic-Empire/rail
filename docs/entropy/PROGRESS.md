# Entropy reduction: progress, task pool, decisions

Decisions: `docs/entropy/DECISIONS.md`.
Branch `entropy/2026-11-27`, worktree `.claude/worktrees/entropy`, based on master c21b627.
Not pushed. A human opens and merges the PR.

## Constraints that bound every round

- Seed `rail_native` must stay at its fixed point. A round that edits `tools/compile.rail`, its
  imports or `runtime/` rebuilds it and regenerates `docs/STATUS.md` in the same commit.
- `releases/`, `builds/`, `selfhost/` and `docs/history` are records. Not touched.
- `tools/fleet` stays (owner, 2026-11-27). Round 8 fixed its example plist and documented the agents.
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
| `stdlib` | 62 | Each module checked alone by `tools/verify/stdlib_alone.rail`. |
| `tools/test`, `tools/fuzz`, `tools/verify` | 61, 79, 23 | Suite, differential fuzzer, gates. |
| `tools/fleet`, `tools/attest` | 23, 26 | Four fleet agent variants; fleet is deferred. |

## Rounds

1. Deleted eight unreferenced v5 prototypes (`CHANGELOG.md` Unreleased, Removed). Callers found: none.
2. `codebuf.rail` moved to `stdlib` (the layering inversion), three uncalled functions deleted, seed rebuilt (fixed point, 323/323, `stdlib_alone` 62).
3. Verify helpers deduplicated into `tools/verify/lib.rail`; stdlib `file_exists` NUL bug fixed; runtime env vars generated into STATUS.md. Scans done: stdlib has no import cycle and no stdlib-to-tools import.
4. Stdlib flat-namespace collisions: `drop` (json) and `contains_char` (tokenizer) removed, gate added. Duplicate-body scan of the tree found 11 repeats (task pool).
5. `sha256_hex_file` moved to `stdlib/sha256.rail`, both attest copies deleted, seed rebuilt, check.sh 8/8 on the commit. `tools/attest` mapped: no import cycle, one other repeat (`basename`, two different bodies of one meaning, left).
6. Remaining repeated bodies classified (ADR-5): the crypto, tls13 and API-client copies are accepted, module-prefixed and explained in `chacha20.rail`; `trim`, `drop_ws_left` in `diff_fuzz` and `rail_test` are two standalone programs, and `lk_section64`, `lk_nlist` follow `dyld_macho` (pending below).

7. Import-cycle gate (`tsort`, runs first); `docs/ARCHITECTURE.md` written.

## Task pool (evidence in brackets)

- `tools/fleet` agents: closed. Not duplicates: v3 on the Macs, v2 on the Pi (v3 cannot build there). The 11 to 16 shared names are the per-platform copies; documented in `tools/fleet/README.md`, not merged.
- Nothing open that is safe to do without the owner. Deferred by evidence: `tools/fleet` (daemon repoint), `compile.rail` restructuring (seed risk, no feature behind it; the tour gate already pins its shape).

## Pending confirmation (needs the owner)

- Decided 2026-11-27: `dyld_macho.rail` stays (owner: keep if useful; it has citations). Open (superseded): whether it should go. `link_lib.rail` cites it in comments and `docs/rail-tier3-record-plan.md` names it, so it stays for now.

## Other repos under ~/projects (read-only triage, 2026-11-27)

Measured with `git ls-files`, a content hash per file and an AST hash per Python function body.

| Repo | Result |
|---|---|
| fieldcraft | 169 tests and `tools/review/pass.py` pass; 12 modules, no import cycle, no repeated function body. Left: key lookup in two places with different precedence, `free_port` twice, test setup repeated in four files. Not worth the regression risk on the revenue repo. |
| plasma-lab | 2,413 of 2,893 files are duplicate content: `tools/refute` holds about 2,600 files, snapshots of the engine tree per refutation run. They are experiment records. Deleting them is the owner's call. |
| rail-lab | 1,027 of 3,914 files duplicate; 2,658 are fuzz corpus. Research data, not code. |
| compound, lab | Patch files and notes; 14 and 2 duplicate files. No code to restructure. |
| clerk, ledatic-life, ledatic-arm, wyandottewater, pursue, ledatic-eco, rail-plasma, dns-sink, fusion-workbench, ledatic-site | 5 to 41 Python files each; no repeated function body of 4 or more statements anywhere. |
| detroitsalsa | Three-line scene helpers repeated across scene scripts (`slab` x3, `glow`, `empty`): an art project, not a system. |
| wish-you-were-here | Hands-off by the owner's rule. One test helper (`outbox`) repeated in two test files. Untouched. |

No repo in this list has a safe change whose value exceeds its risk. `plasma-lab/tools/refute` is the one
large item and needs the owner.

### Fieldcraft boundaries (measured 2026-11-27)

Business logic (`gym`, `gym_ask`, `engine`, `export`, `integrity`, `gym_reference`) contains no
`sqlite3`, no network and no `os.environ`. Storage is `store.py` (and one use in `notes.py`), the model
call is `anthropic.py`, environment reads are in `anthropic.py`, `__main__.py` and `desktop.py`.
One exception was `gym_ask.MODEL`, `APPROVED` and `SCOPE`, module globals assigned from three places.
They now have one writer, `gym_ask.configure_model`, and a test fails any other assignment (seen failing on
planted single and tuple assignments). They remain module state, read by one function; passing them down
the request chain is not done. One API key lookup since commit 9e6c701 (fieldcraft branch
`entropy/2026-11-27`, local).

## Round 8 (2026-11-27)

- Owner answers: fleet stays and the daemon is being adjusted; `dyld_macho` stays; `plasma-lab/tools/refute` archived (plasma-lab branch `entropy/2026-11-27`, 2920c29, archive on the SSD with a verified manifest, its gate passes); fieldcraft `gym_ask` settings left as module state with one writer; next repo is `ledatic-site`.
- Found: the example plist `com.ledatic.tb_autojoin.plist.example` held merge-conflict markers and another job's label. Rebuilt from the installed daemon.
- Found: deleting v2 `fleet_agent.rail` as a duplicate would have removed the only agent that runs on the Pi.
- PR 202 CI: all checks passed before this round.

## Round 9: ledatic-site (2026-11-27, branch `entropy/2026-11-27`, 5ce522c, local, not pushed)

- Measured: 307 tracked files; the only byte-duplicates are 14 repeated screenshots under `docs/plans/shots` (records, left). The 15 section links in the top nav are identical across 21 pages; drift is only in the per-page CTA link and active markers. `tios.html` has its own nav by design.
- Added `tests/nav_consistency_test.sh` (fails on a planted typo, exit 1). README drops the stale "eight pages".
- Pending, owner: two KV upload implementations, `deploy.sh` (bulk, 968 lines) and `railgen/cf_deploy.rail` (one file plus cache purge). Different callers (cron generators versus manual pushes); merging them touches the live deploy path, so left. Uncommitted `sitemap.xml` in the main checkout belongs to another session and was not touched.
- Round 10: only the Mini, Air and Pi exist (owner, 2026-11-27; Studio sold 2026-10-13). Deleted the x86/Windows agent (no node, no caller) and the Studio entries in the fleet scripts.
