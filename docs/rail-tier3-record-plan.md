# Tier 3: the record is the inheritance (plan, 2026-10-21)

Status: a plan, not a mandate. Step 1 landed 2026-10-20 (#142) with the seed unchanged, and the
data section followed it out of the strings (#144). Step 2 landed 2026-10-21 in rail-plasma (its PR #1):
`replay.sh` replays any pulse by id to MATCH or MISMATCH, every pulse since 9166580 names its
program (`frame.rail_commit`, `frame.plasma_commit`, `frame.os_build`), and the gate replays a pinned
record. Step 3 landed 2026-10-21: the KAT judges its double by the 64 bits (`stdlib/float_hex.rail`,
exact arithmetic, no printer on the judging path); Linux ARM64 is declared non-replay until steps 4
and 8: `linux_libc.s` gained `_exit` and `_sqrt`, the kernel still needs `sin`, and a Pi showed the
hex identical for every computed value but a few ulps off for long literals, since every literal is
parsed at run time by the platform's `atof`. Step 4 landed 2026-10-21: `stdlib/math_exact.rail`
carries sin, cos, exp, tanh, sqrt and gelu as fixed integer algorithms at F = 24 (lifted unchanged
from `tools/bitexact/bx_fixed.rail`, which forwards to it), the kernel's six `sin` sites call
`sin_fixed`, and the beacon's assembly has no `bl _sin`; the KAT and the pinned record were
re-measured on the new kernel. Step 5 landed 2026-10-21 (Rail #151 to #157, ledatic-site #62,
tag `archive/tier3-step5-precut-2026-10-21`): `tools/bitexact`, `tools/tls`, `tools/auth`,
`tools/audit`, Metal with `gpu_map` and the thirteen stdlib modules only it served, `jit/`
(the encoder and code buffer kept under `tools/v5/`), the wasm backend with `rail safe`, and
`tools/deploy` (the site generators are `ledatic-site/railgen`); the suite is 242, the seed
991,800 bytes, `SHIMS.md` seven rows. `tools/fleet` stays until the owner repoints the
`tb_autojoin` root daemon on both Macs. Step 6 landed 2026-10-21 (Rail #160, #161): every macOS
compile links in process through `tools/v5/link_lib.rail`; the `as`/`ld`/`codesign` branch and
the sub-5000 MB fallback are gone; the seed is the same at any arena from 2000 up and CI rebuilds
it at 3000 on GitHub's 7 GB runner and `cmp`s it (the peak the plan feared, 8.5 GB, was 5.4 GB
once measured on the cut compiler); the first in-process link of user programs found five
defects (`\r`, `ror`/`smulh`/`fneg`, `.comm`, undefined identifiers, the `llm` grep), each now
loud; the channel and Quartz shims that only the old branch could link went with it (`SHIMS.md`
five rows). Step 7 landed 2026-10-21 (estate, no Rail change: `~/.fleet/repro_witness.sh`, its Air half `repro_witness_remote.sh`, the plist back in LaunchAgents at 04:37, a manifest row): the Mini picks the newest seeded pulse ledatic.org serves and replays it; the Air, from anonymous public clones checked out at the commits the record names, fetches and replays the same record; each box logs its verdict, and a planted digest, a seedless record and a dead address each rang through the real path before the agent was loaded. First proof: pulse 9177957 (141 frames) `match` on both boxes. Step 8 landed 2026-10-21 (Rail
`tools/decimal64.rail`, t259, `tools/fuzz/float_literals.py`): every float literal's 64 bits are
decided when the program is compiled, correctly rounded, ties to even, by integer arithmetic;
the self-compiled assembly has no `bl _atof` and the beacon's assembly none (from 133); 1,520
generated literals agree with CPython and a planted tie rule fails the gate. On the Pi all 38
probed literals, the kernel's 31 included, hold the Mini's bits. The re-measurement answered the
open question another way: the Pi's replay digest `a6619f48...` was the SHA-256 of 393,216 zero
bytes, because the runtime's float32 file writer issues raw Darwin syscalls and wrote nothing on
Linux; with Linux versions in `tools/linux_libc.s` the Pi replays the 38-frame record of step 4
to the Mini's digest `acf59368...` with a byte-identical planes file, and `replay.rail` now
refuses a planes file it did not write (`WRITE_FAILED`). The 64-frame pinned record exceeds the
Pi's memory. Step 8's run-time half landed 2026-10-22: `parse_float` is `tools/decimal64.rail`
compiled into the program that calls it (the compiler carries the file's text in the generated
`tools/decimal64_src.rail` and adds it to any program that names `parse_float`; the builtin calls
`d64_parse_float`, which builds the double from its fields by exact arithmetic), `_atof` is gone
from `tools/linux_libc.s`, and `grep -c _atof` on the self-compiled assembly is 0, the proof the
step's row asks for (it was 1). `tools/fuzz/float_literals.py` sends each literal through both
doors; t260; the suite is 244. On the Pi a 26-text probe, JSON numbers and a subnormal included,
printed the Mini's bits line for line. The rest is not implemented. The owner's frame, 2026-10-21: humans
become a spacefaring species; Ledatic is a 100-year company; what position does Rail take so
that, eventually, it is the right tool for someone? Ten positions were written, two were argued
by separate read-only crawls of this repo, a third crawl verified both and ruled. Every number
below was measured on master `97083ce` and rail-plasma `480cfdf` with the command named in the
cases; none is quoted from a doc.

## The ten positions

1. The Seed: a toolchain that bootstraps from paper.
2. Replay: bit-exact numerics as the product; the inquiry board's language.
3. The signed ledger, sold without Rail (Fieldcraft's business already).
4. The verifier of other people's builds.
5. Back to the metal: controllers (reverses the Tier 1 cut on evidence three days old).
6. Deterministic inference: AI decisions you can replay.
7. The physics lab: attested simulation.
8. The spec, not the code: a frozen core and independent implementations.
9. The clock a stranger can check: the beacon as a public witness (live, reviewed B+).
10. The compiler you can read in a weekend.

Finalists: **A, the Seed** (1 carrying 8 and 10): the inheritance is the compiler. **B, Replay**
(2 carrying 6 and 7): the inheritance is the record. The others are moves inside A or B.

## What the crawls established

**A's artifact.** `rail_native` is 1,057,896 bytes, links only libSystem, imports 11 symbols,
carries a constant UUID and an ad-hoc signature written by Rail. The self-reproducing system is
14,414 lines of Rail (`tools/compile.rail` 9,118 plus types, ast, assembler, linker, Mach-O,
signer, sha256) and a 110,079-byte ARM64 runtime held as 21 string constants at
`compile.rail:4546` to `5051`. Only `self` takes the pure path; every other compile shells `as`,
`ld` and `codesign` (`5863` to `5890`). The fixed point is checked on one machine by hand; CI
self-compiles through the `as`/`ld` fallback; the off-box witness is parked since 2026-10-15 with
the sold Studio. The seed format is written nowhere: `link_lib.rail:3` and `dyld_macho.rail:6`
cite two spec files in `~/.ledatic/` that no longer exist, and the assembler gate defines correct
as "agrees with Apple's `as`". Printed as hex the seed is 2,115,792 characters: not small.

**B's artifact.** The beacon is the only Rail numerics running in public. `rail-plasma/mhd_kernel.rail`
(804 lines, no `foreign`) rebuilds any epoch from one integer; an hourly walker replays the newest
seeded pulse and compares a SHA-256 of its f32 planes (2026-10-20T06:00:02Z: `REPLAY=match`,
46,813 signatures verified, 0 linkage failures); the KAT runs on a GitHub Mac, the only
cross-machine check either thesis has today. The weak layer is Apple's, not Rail's: the beacon's
initial condition calls libm `sin`; float literals go through `atof` (`compile.rail:1471, 1623`);
floats print through `snprintf` (`4558, 4953`); the KAT compares a string. The inference engine,
B's strongest artifact (138M hash identical on three Macs, transcripts byte-identical on two,
verified in 77 ms against 3,734 ms of production), left the public tree in #138 and was never
pulse-bound or witness-signed.

**Both cases agree** on three things: the 34,248-line Metal, bit-exact and JIT block (the open
Tier 2 step 4) is mostly deletable; the witness must return on the Air; and libm, `atof` and
`snprintf` are the layer nobody in the house wrote or pinned.

## The ruling

Scores tied at 19 each (A wins deletion and dependence; B wins truth today, survival and outside
pull). The frame decides: **B, the record, wins**, with the toolchain kept exactly as far as the
record needs it.

1. The frame's test is an outside ask, and only B has a surface where one can happen. The beacon
   runs in public hourly with a mechanical physics check behind the newest pulse. A's proof is a
   `cmp` nobody outside can run until A's own step 2 lands.
2. Survival favours a record over a binary. The Studio sale was the experiment: its hashes are
   still checkable on the Mini and the Air; its witness role died with it. A seed is as portable
   as XNU; a replay with no libm and bit comparison is 804 lines of arithmetic plus a 32-byte
   digest that any language can re-derive without Rail.
3. Dependence runs one way, but cheaply. B needs a compiler that still builds, not a printable
   seed or diverse double compilation. A's cheap steps give B everything it needs; A's expensive
   ones (the Linux seed, DDC, the small seed) are cut by the standing rule.

What B borrows from A: the runtime out of the strings, one link path, the full cut, the seed
format written. What B keeps that A would cut: `tools/attest/{attest,verify}.rail` and enough TLS
to reach the signer. B's inference steps stay in rail-lab until the beacon loop is proven.

## The tier, as the evidence orders it

About 19 sessions. This absorbs the open Tier 2 items: step 4 (Metal) is resolved as "cut, after
the exact trig is lifted out"; `tools/fleet` goes in the same cut once the daemon repoint lands.

| # | Step | Files | Sessions | Proof |
|---|---|---|---|---|
| 1 | Runtime out of the strings | `compile.rail:4546-5051` to `runtime/arm64/*.s` plus `tools/gen_runtime.rail` | 2 | seed `cmp`s before and after; gen1 == gen2 == gen3 |
| 2 | One record, one stranger's verifier | `rail-plasma/replay.rail`, `mhd_beacon.rail`, `mhd_verify_epoch.rail`, `beacon_v2.py`, `docs/REPLAY.md`; the `frame` block gains Rail commit, rail-plasma commit, OS build | 2 | a fresh clone on the Air replays pulse N with one command; `gate.yml` does the same |
| 3 | Bits judge the replay | `tests/mhd_beacon_replay_kat.rail:14` compares the hex of the double; `linux_libc.s:724` prints the same hex or is declared non-replay | 1 | KAT green on the Mini, CI and a Pi build |
| 4 | No libm on the replay path | `stdlib/math_exact.rail` from `bx4_fixed_transcendentals.rail` and `r1a_exact_trig.rail`; `mhd_kernel.rail:64-67, 136-137` | 2 | `grep -c "bl _sin"` on the beacon's `.s` is 0 |
| 5 | The cut, one PR per block | `tools/metal`, `tools/bitexact`, `jit/` (keep `arm64.rail`, `codebuf.rail` under `tools/v5/`), 3,794 stdlib GPU lines, wasm, autograd, `tools/{deploy,fleet,audit,tls,auth}`; `tools/attest` stays | 2 | suite count in the diff; three-cycle bootstrap; `SHIMS.md` under 10 rows; `STATUS.md` re-measured |
| 6 | One link path | delete `compile.rail:5863-5890` and `6913-6918`; link peak under 7 GB; `ci.yml` self-compiles at `RAIL_ARENA_MB=6000` and `cmp`s the seed | 3 | CI green on a machine the house does not own |
| 7 | The witness returns on the Air | new `~/.fleet/repro_witness.sh`, the parked plist, a manifest row | 1 plus the owner's `launchctl` | two machines log `REPLAY=match` for the same pulse |
| 8 | Float literals without `atof` | `compile.rail:1471, 1623` (x86 copy `8698`): correctly rounded decimal to binary64 at compile time | 2 | `grep -c _atof` on the self-compiled `.s` is 0; `semantic.py` agrees with CPython on every float case |
| 9 | Two contracts written | `docs/SEED_FORMAT.md` proven by a Python writer in `tools/independence/` that emits `exit42` and `cmp`s with `lk_link_file`; `NUMERICS.md` with a test per sentence and a platform triple per claim | 3 | the writer's `cmp`; the suite count |
| 10 | The reader's path | `docs/COMPILER_TOUR.md` in file order, section banners, the `v1.4.0` header, `CONTRIBUTING.md` and `tests/README.md` off 182 | 1 | a test that every cited symbol exists |

Not in the tier, on evidence: diverse double compilation, the Linux seed, the small seed, the
inference product. Each is a second century's work or a private repo's.

## The sentence to keep

The inheritance is "this number, from these inputs, by this program, signed at this pulse", and
the compiler matters exactly as far as that sentence needs it to still build. Replay proves
provenance, never correctness; the record must never say more.

The three crawls (A's case, B's case, the judgment) are kept in full, with every command, outside
this repo at `~/.ledatic/rail-century/`.
