<h1 align="center">Rail</h1>

<p align="center">
  <em>A self-hosting language built to be a checker you can re-run yourself.</em><br>
  <sub>No C in the runtime. The collector in ARM64 assembly. HTTPS in pure Rail. Every number under a contract with a test.</sub>
</p>

<p align="center">
  <a href="#releases"><img src="https://img.shields.io/badge/v5.6.0-The%20numerics%20contract%2C%20the%20runtime%20as%20source%2C%20and%20every%20claim%20gated-ff5500?style=for-the-badge" alt="v5.6.0"></a>
</p>

<p align="center">
  <a href="#check-the-claims"><img src="https://img.shields.io/badge/tests-257%2F257-brightgreen" alt="tests 257/257"></a>
  <a href="#check-the-claims"><img src="https://img.shields.io/badge/self--hosting-fixed%20point-blue" alt="self-hosting"></a>
  <a href="#2-speaks-https-natively"><img src="https://img.shields.io/badge/HTTPS-pure%20Rail-ff5500" alt="pure-Rail HTTPS"></a>
  <a href="#how-it-works"><img src="https://img.shields.io/badge/GC-ARM64%20assembly-purple" alt="GC in ARM64 asm"></a>
  <a href="#why-rail"><img src="https://img.shields.io/badge/C%20in%20seed-0-brightgreen" alt="zero C in the seed binary"></a>
  <a href="#why-rail"><img src="https://img.shields.io/badge/backends-3-orange" alt="3 backends"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-BSL%201.1-green" alt="BSL 1.1"></a>
</p>

<p align="center">
  <b><a href="#quick-start">Quick start</a></b> ·
  <b><a href="#check-the-claims">Check the claims</a></b> ·
  <b><a href="#what-rail-does">What Rail does</a></b> ·
  <b><a href="#why-rail">Why Rail</a></b> ·
  <b><a href="CHANGELOG.md">Changelog</a></b> ·
  <b><a href="https://github.com/Ledatic-Empire/rail/releases">Releases</a></b>
</p>

---

Rail compiles itself. The compiler, 7,745 lines of Rail on 2026-10-29 (the measured line lives in
[`docs/STATUS.md`](docs/STATUS.md), which CI regenerates and compares), produces a 1,041,272-byte
ARM64 binary that compiles the compiler again and reaches a byte-identical fixed point. There is no
C in the runtime and no libc in the binary beyond the kernel interface: `otool -L rail_native`
shows `libSystem` and nothing else. The garbage collector is ARM64 assembly. The TLS 1.3 client is
Rail. The toolchain stands alone: Rail assembles, links and ad-hoc signs its own Mach-O binaries in
process, with no `as`, `ld` or `codesign`, and since 2026-10-21 that is the only link path there
is, so every CI run rebuilds the committed seed from source on a machine this project does not own
and compares the bytes.

```
RAIL_ARENA_MB=6000 ./rail_native self && cmp rail_native /tmp/rail_self   # silent: the seed is what its source builds
./rail_native test                                                        # 257/257 tests passed
```

### What the self-hosting is for

Self-compilation is not the point; it is the prerequisite. The point is that one small binary can
act as a checker a third party re-runs without trusting whoever ran it first. A claim that a
program is correct, or that a computation happened as described, is unfalsifiable on its own;
`rail_native` compiling that program, or recomputing that result to the same bits, is a fact
anyone can reproduce from the same seed. So the compiler is used as a fitness function, as a
replayer of signed records, and (2026-10-29) as the producer of a training step a GPU can be held
to bit for bit.

A reproduced computation proves it happened as claimed. It says nothing about whether the result
is any good; those are different questions, and conflating them is the most expensive mistake in
this repo's history (see [Honest limits](#honest-limits)).

## Quick start

```bash
git clone https://github.com/Ledatic-Empire/rail
cd rail
./rail_native run examples/hello.rail
```

Apple Silicon (ARM64 macOS) is the primary target; Linux ARM64 and Linux x86_64 are cross-compile
targets. Nothing to install: the seed binary is in the repo and needs no toolchain.

```bash
./rail_native <file.rail>          # compile to /tmp/rail_out (in-process assembler, linker and signer)
./rail_native run <file.rail>      # compile and execute
./rail_native test                 # the suite; the last line is 257/257 tests passed and the exit code says so
./rail_native quick                # the 15-case smoke subset, a few seconds
RAIL_ARENA_MB=6000 ./rail_native self   # self-compile to /tmp/rail_self; cmp it with rail_native
./rail_native x86 <file.rail>      # cross-compile to Linux x86_64 assembly (/tmp/rail_x86.s)
./rail_native linux <file.rail>    # cross-compile to a Linux ARM64 ELF (/tmp/rail_linux)
./rail_native types <file.rail>    # the type checker's report
./rail_native run tools/repl.rail  # a REPL
```

[`docs/getting-started.md`](docs/getting-started.md) walks the first program;
[`docs/language-reference.md`](docs/language-reference.md), [`docs/builtins.md`](docs/builtins.md)
and [`docs/stdlib.md`](docs/stdlib.md) are the surface; [`grammar/rail.ebnf`](grammar/rail.ebnf)
is the grammar in one file.

## Check the claims

Every claim this README makes is a command, and nearly every one is a job of
[the CI workflow](.github/workflows/ci.yml) on GitHub's own macOS and Linux runners. Run them
here or read them there.

| Claim | Command | CI |
|---|---|---|
| The committed seed is what its source builds, and the build is a fixed point | `RAIL_ARENA_MB=6000 ./rail_native self && cmp rail_native /tmp/rail_self` | `test`: seed reproduced, then gen1 == gen2 |
| The suite passes and the runner reports its own count | `./rail_native test` (257/257 tests passed, exit 0 only then) | `test` |
| The documents cite what exists and quote the suite's count (this badge included) | `./rail_native run tools/verify/tour_check.rail` | `test` |
| The status matrix's numbers are the tree's | `./rail_native run tools/verify/gen_status.rail && git diff docs/STATUS.md` | `test` |
| Rail's doubles are C's doubles, bit for bit, on arm64 and on x86-64 | `bash tools/verify/numerics_vs_c/run_ci.sh arm64` | `numerics`, `numerics-x86` |
| Every sentence of the numerics contract has a test | [`docs/NUMERICS.md`](docs/NUMERICS.md) names it; `./rail_native test` runs it | `test` |
| The collector survives stress | `python3 tools/fuzz/gc_stress.py` (collect every Nth allocation, poison what is freed) | `gc-stress` |
| An interpreter written outside Rail agrees with the native binary | `python3 tools/fuzz/semantic.py --seed 42 --cases 20` | `semantic` |
| Known miscompiles stay fixed, open ones stay open | `python3 tools/fuzz/known_cases.py` ([`tools/fuzz/known/`](tools/fuzz/known/)) | `semantic` |
| The runtime's source and the compiler's copy of it agree | `./rail_native run tools/gen_runtime.rail check` | `test` |
| The seed's container is derivable from its document | `bash tools/independence/seed_format_gate.sh` (a Python writer written from [`docs/SEED_FORMAT.md`](docs/SEED_FORMAT.md) builds the same bytes) | `test` |
| Every example compiles, runs and prints what it says | `./rail_native run tools/verify/examples_check.rail` | `examples` |
| Every stdlib module compiles when imported alone | `./rail_native run tools/verify/stdlib_alone.rail` | `stdlib` |
| A release is signed against a public entropy beacon | [`VERIFY.md`](VERIFY.md) section 6 | by hand |

[`VERIFY.md`](VERIFY.md) is the same list for a stranger with one afternoon, and says what each
check proves and what it does not.

## What Rail does

### 1. Compiles itself, byte-identical

```
RAIL_ARENA_MB=6000 ./rail_native self    -- the compiler and the seven modules it imports become
cmp rail_native /tmp/rail_self           --   a 1,041,272-byte ARM64 Mach-O, and it is the committed one
cp /tmp/rail_self ./rail_gen1            -- gen1 compiles the compiler again
RAIL_ARENA_MB=6000 ./rail_gen1 self
cmp rail_gen1 /tmp/rail_self             -- and the output is identical: the fixed point
```

The collector, the allocator and the runtime are ARM64 assembly embedded in the compiler
(`runtime/arm64/*.s`, carried in as a generated module and checked against its source in CI). No
`gcc`, no `libc`, no linker scripts, and no `as`, `ld` or `codesign`: Rail assembles, links and
signs every program it compiles, in process, through one path.
[`docs/COMPILER_TOUR.md`](docs/COMPILER_TOUR.md) walks the compiler section by section in file
order; a gate keeps every symbol it names and the order it claims honest.

### 2. Speaks HTTPS, natively

```rail
import "stdlib/anthropic_client.rail"

main =
  let (status, reply) = anthropic_chat "claude-haiku-5-5" "Reply with exactly: hello from pure rail" 40 "/path/to/api_key"
  let _ = print reply
  0
```

Full TLS 1.3 in Rail: x25519 key exchange, ECDSA and RSA certificate verification against the
macOS trust store, hostname and validity checks, ChaCha20-Poly1305 records. Zero OpenSSL, zero
curl. The stdlib is 61 modules in all, and the crypto in it (SHA-256/384/512, HMAC, HKDF,
ChaCha20-Poly1305, X25519, Ed25519, ECDSA P-256/P-384/P-521, RSA-PSS and PKCS1) is validated
against RFC and NIST vectors in the suite. Not constant-time; see [Honest limits](#honest-limits).

A program that imports the TLS stack is 26 files and 269 KB of source with its imports and
compiles in 1.9 s at the default arena (2026-10-29; until that day the allocator's first-fit
scan made it take minutes, and `RAIL_ARENA_MB=1500` was the workaround).
[`examples/life_beacon.rail`](examples/life_beacon.rail) is the stack in one page (HTTPS, JSON, a
SHA-256 chain, deterministic replay) and runs in CI.

### 3. Puts its numbers under a contract

[`docs/NUMERICS.md`](docs/NUMERICS.md) says, sentence by sentence, what a Rail program's numbers
are, and each sentence names the suite test that pins it and the platforms it was measured on:
63-bit integers that wrap, division that truncates, IEEE binary64 floats whose `+. -. *. /.` and
`fsqrt` are the ARM64 instructions, reductions evaluated in source order, float literals converted
at compile time by integer arithmetic (`tools/decimal64.rail`, pinned against CPython's bits) and
`parse_float` by the same code at run time, and `show_float_hex`, which derives a double's 64
bits by exact arithmetic so the same bits print the same sixteen hex digits on every platform.
One sentence is marked not claimed (host libm through FFI), and
[`tools/verify/numerics_vs_c`](tools/verify/numerics_vs_c/) measures all of it against a C
compiler on every CI run, on an arm64 Mac and on an x86-64 Linux box.

Since 2026-10-29 the contract includes binary32 on the double substrate: `round32`, `fma32` and
`f32_bits`, so a Rail program can compute exactly what a float32 program on a GPU computes.
Test t268 carries the counterexample that separates a real single-precision fma from a rounded
double one.

```rail
import "stdlib/float_hex.rail"
main =
  let _ = print (show_float_hex (0.1 +. 0.2))               -- 3fd3333333333334, every platform
  let _ = print (show_float_hex (round32 0.1))              -- 3fb99999a0000000, the nearest binary32
  let _ = print (show (f32_bits 1.0))                       -- 1065353216
  0
```

What that bought, the same day: a 138-million-parameter GPT whose twenty Adam steps land on
identical bytes on six chips (Apple M1 and M4 Pro GPUs, NVIDIA T4 and A10, an Apple CPU, an AMD
x86 CPU) from one arithmetic header; the same model's first step computed in Rail, with these
builtins, to the GPUs' bytes; and a Rail program that owns the training sequence and signs a
SHA-256 ledger of it, driving an Apple GPU and an NVIDIA GPU to the same ledger head and the same
Ed25519 signature. The lab's records and gate are in review for publication at
ledatic.org/crossvendor.

### 4. Is the oracle for attested work

```
generator (seeded) -> corpus -> rail_native verifies every program -> signed ledger
      -> training -> checkpoints -> the same oracle scores them -> the chain extends
```

The compiler as the fitness function: programs it accepts become training data, programs it
rejects are the gradient, and nothing in that path requires trusting the maintainer. The furthest
this was carried (July 2026, [CHANGELOG](CHANGELOG.md) v5.3.0) was a from-scratch 138M model that
writes Rail, trained only on oracle-verified pairs: 16/16 compile@1 on its frozen benchmark,
11/16 function-correct, and 0/10 on novel function names. The number is real and the limit is
real, and both are published, because a benchmark quoted without its failure mode is marketing.
The training stack now lives in the private lab repo; the oracle is this one.

## Why Rail

- **No C in the core.** The seed links only `libSystem`. It assembles, links and signs itself and
  every program it compiles. No glibc, no OpenSSL, no runtime C; the collector is 973 lines of
  ARM64 assembly in five files. The assembly that remains at the edges is listed, file by file,
  in [`SHIMS.md`](SHIMS.md): 31 files.
- **Byte-identical self-compile, checked by strangers.** CI rebuilds the committed seed from
  source on GitHub's runner and compares the bytes, then compiles once more for the fixed point.
- **One binary checks everything.** Tests, the docs' numbers, the numerics contract, the examples,
  the release signatures: all judged by the binary you cloned. That makes it a reproducible
  checker, not a proof of correctness. Compilation proves a program is accepted by the binary
  you run, nothing more.
- **A narrow, honest production surface.** Rail ships the crypto it uses and nothing more, every
  primitive vector-validated, none of it constant-time.
- **Three backends travel with the language.** macOS ARM64 (native), Linux ARM64 (a Pi Zero 2 W
  runs the numerics probe and the entropy beacon's replay) and Linux x86_64 (the numerics probe
  passes all seven tests on CI's x86 runner since 2026-10-29). WebAssembly and the microcontroller
  backends were cut in October 2026; their trees are tagged.

## The language

```rail
-- Functions, pattern matching, ADTs
type Expr = | Num x | Add a b | Mul a b

eval e = match e
  | Num x   -> x
  | Add a b -> eval a + eval b
  | Mul a b -> eval a * eval b

main = let _ = print (show (eval (Add (Num 3) (Mul (Num 4) (Num 5))))) in 0
-- 23
```

```rail
-- Higher-order functions, pipes, real I/O
gt3 x = x > 3
inc x = x + 1

main =
  let _ = print (show (fold (\a b -> a + b) 0 (range 101)))  -- 5050
  let _ = print (show (length (filter gt3 [1,2,3,4,5,6])))   -- 3
  let _ = write_file "/tmp/out.txt" "hello"
  let _ = print (read_file "/tmp/out.txt")                   -- hello
  0
```

Floats are unboxed IEEE 754 doubles in ARM64 d-registers wherever the types prove them float, and
boxed only when stored into a tuple, list or ADT field ([`docs/TYPES.md`](docs/TYPES.md),
[`docs/NUMERICS.md`](docs/NUMERICS.md)). `try` gives effect handlers over setjmp/longjmp.
[`examples/`](examples/) has eighteen programs, each with its expected output committed beside it
and checked in CI.

## How it works

| Component | Implementation | Detail |
|---|---|---|
| **Lexer and parser** | Rail | Tokenizer and recursive-descent builder of a typed syntax tree |
| **Type checker** | Rail | Hindley-Milner inference (`tools/types.rail`); types decide representation |
| **Codegen** | Rail | Walks the tree, emits ARM64 or x86_64 directly |
| **Assembler, linker, signer** | Rail | `tools/v5/`: AArch64 encoder, Mach-O and ELF writers, ad-hoc code signature; the container is documented in `docs/SEED_FORMAT.md` |
| **Allocator** | ARM64 assembly | Bump arena inside a 64 GB reservation that grows in place (`RAIL_ARENA_MB` sets the first collection) plus a free list |
| **GC** | ARM64 assembly | Conservative mark-sweep: scans stack frames, traces tagged objects, sweeps into the free list; `RAIL_GC_STRESS=N` collects every Nth allocation |
| **Tagged values** | Inline | Integers `(v << 1) \| 1`; heap objects by pointer; floats raw in d-registers, boxed (tag 6) at the generic boundary |

Tail-recursive loops match C `-O2` (5 instructions per iteration). The compiler is walked in
file order in [`docs/COMPILER_TOUR.md`](docs/COMPILER_TOUR.md); the history is in
[`CHANGELOG.md`](CHANGELOG.md).

## What moved out

Rail is the language: the compiler, the stdlib, the suite, the fuzz corpus, attestation and
verification, the backends. The LM experiments, the hard-bench, the inference engine and the
tool shed moved to the private `rail-lab` (2026-09-22, 2026-10-20); the entropy beacon is the
public [`rail-plasma`](https://github.com/Ledatic-Empire/rail-plasma) (2026-10-20); the Metal
JIT, the stdlib ML stack, the WebAssembly backend and the microcontroller backends were cut on
2026-10-19 and 2026-10-21 (tags `archive/tier1-precut-2026-10-19`,
`archive/tier3-step5-precut-2026-10-21`). The CHANGELOG records each move.

## Releases

**v5.6.0 (2026-10-29): the numerics contract, the runtime as source, and every claim gated.**
Every Rail double is under [`docs/NUMERICS.md`](docs/NUMERICS.md), a contract with a test per
sentence: float literals and `parse_float` decided by integer arithmetic, `show_float_hex`,
`math_exact`, the binary32 builtins, and Rail's doubles measured against C's bit for bit on
arm64 and x86-64 in every CI run. The ARM64 runtime is source files and every compile takes
one link path; the seed format and the compiler tour are written and gated. The x86-64
backend's three recorded defects fixed; the free list scanned next-fit, so a program that
imports the TLS stack compiles at the default arena; a redefined import warned; a missing
quoted import refused. The README's counts, the status page's facts and all 18 examples are
gated in CI. The Metal, WebAssembly and microcontroller surfaces cut; the beacon and the lab
moved to their own repos.

| Version | Date | Headline |
|---|---|---|
| **v5.6.0** | 2026-10-29 | The numerics contract; the runtime as source; every claim gated |
| **v5.5.0** | 2026-10-19 | The compiler type-checks; the collector under stress |
| **v5.4.0** | 2026-09-22 | Hardening: seven miscompiles fixed with minimal programs; the known-miscompile corpus runs as a suite; the beacon replays from one integer |
| **v5.3.0** | 2026-07-08 | Independence checker; self-compile 61 s to 19 s; the check-me kit (`VERIFY.md`, `docs/STATUS.md`) |
| **v5.2.0** | 2026-06-19 | Rail stands alone: assembles, links and code-signs its own Mach-O; bit-reproducible self-compile |
| **v5.1.0** | 2026-05-15 | Rail emitted its own Metal kernels (surface cut 2026-10-21) |
| **v5.0.0** | 2026-05-14 | Self-hosted toolchain: aarch64 Linux ELF with no `as` or `ld` |
| **v4.0.0** | 2026-05-13 | Substrate: 30/30 hard-bench, JIT, dual-backend parity, multi-witness attestation |
| **v3.0.0** | 2026-04-18 | Rail speaks TLS: pure-Rail HTTPS, chain validation to the macOS trust store |
| **v2.0.0** | 2026-04-06 | Native floats, effect handlers, the collector in assembly |
| **v1.0** | 2026-03-17 | Self-hosting. Rust deleted. |

Full notes for every version: [CHANGELOG.md](CHANGELOG.md). Tagged releases are Ed25519-signed
against a public entropy beacon ([`docs/RELEASES.md`](docs/RELEASES.md), [`VERIFY.md`](VERIFY.md)).

## Honest limits

Things Rail does not do, so you do not hit them as surprises:

- TLS ships one cipher suite (`TLS_CHACHA20_POLY1305_SHA256`), one key-exchange group (`x25519`)
  and three CertificateVerify algorithms. Modern CDN fronts work; legacy servers may not. No
  session resumption, no 0-RTT, no client certificates.
- No constant-time or side-channel guarantees anywhere in the crypto. This is not OpenSSL.
- An HTTPS connection costs seconds of wall time (public-key verification dominates). Fine for
  one-shot API calls, wrong for a proxy.
- The `x86_64` backend is measured, not supported: the suite does not run on it, and only the
  numerics probe and the known-case corpus do. Its three float and calling-convention defects
  found on 2026-10-29 were fixed the same day (`tools/fuzz/known/x86_cases.json`).
- A top-level name you define replaces a stdlib function of the same name everywhere, the
  stdlib's own callers included. Since 2026-10-29 the compiler says so (a `WARNING` naming the
  file); it still compiles. Treat imported names as reserved.
- Rail has Hindley-Milner inference and no soundness proof, and is standardised by nobody. Use it
  because it is small, fast and checkable, not because it is Haskell.
- The attested-training model generalizes 0/10 to unseen function names (above). Composition
  needs scale or a differently shaped corpus; it is not a corpus-tuning problem.

### The most expensive thing we've learned

In July 2026 a self-improvement loop ran for about a week: a local model proposed changes, a
deterministic executor applied them, every generation was scored on a held-out reward and signed
into a tamper-evident chain. It reported a clean climb across about eleven signed generations.
Every step was reproducible and cryptographically attested.

It was noise. Re-scoring the identical lineage on a held-out sample five times wider flattened
the entire curve: the "improved" frontier scored exactly what the base it started from scored,
672/1920 against 672/1920.

The apparatus was sound and the conclusion was worthless, because the held-out reward was itself
a tiny sample. A deterministic optimizer maximizing a small reward will fit that sample: reward
hacking one layer beneath the defense built against reward hacking.

**The lesson, which governs this repo: attestation of a computation is not validation of its
metric.** A signed chain proves the numbers were produced the way we said. Whether the numbers
mean anything is a separate question, and the signature is silent on it. Any reported gain here
is re-measured on a disjoint, much wider sample before it is believed, especially a gain that
flatters us.

It stays in the README rather than a postmortem folder because a project whose premise is "check
me, don't trust me" has no business hiding the time it fooled itself.

## License

[Business Source License 1.1](LICENSE). You may use Rail in production, including commercially;
the one carve-out is offering it to third parties on a hosted or embedded basis that competes
with the Licensor's products. It converts to MIT on 2030-03-14.

BSL rather than a permissive license from day one for a narrow reason: Rail is one person's
research surface, and the only outcome worth guarding against is someone reselling it as a hosted
service before it has established itself. Everything else, including commercial use inside your
own product, is already granted. The MIT conversion date is fixed and unconditional.

## Notes

> GitHub's language bar shows this repo as Haskell because `github-linguist` does not know Rail
> yet. This is a Rail codebase.
