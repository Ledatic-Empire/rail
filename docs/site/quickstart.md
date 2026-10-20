# Quickstart: from `git clone` to a verified release

Ten numbered steps. Each one is a real command with its real captured output. If any step does not behave like this on your machine, that's a bug.

This guide assumes Apple Silicon macOS (the primary target). For other hosts, see [backends.md](backends.md).

---

## 1. Clone

```bash
git clone https://github.com/Ledatic-Empire/rail
cd rail
```

You should now have a `rail_native` binary at the repo root — it's a ~1 MB ARM64 Mach-O checked into the repo. That's the seed compiler. There is no `./configure`, no `make`, no `cargo build`.

```bash
file rail_native
```

```
rail_native: Mach-O 64-bit executable arm64
```

## 2. Run hello, world

```bash
./rail_native run examples/hello.rail
```

```
Compiling examples/hello.rail (244 chars)...
  as: OK
  ld: OK
hello, rail
3628800
42
```

`run` compiles to `/tmp/rail_out` and then executes it. The two `OK` lines are the assembler and linker; the three lines below are the program output (`"hello, rail"`, `factorial 10`, `double 21`).

## 3. Inspect the program

```bash
cat examples/hello.rail
```

```rail
-- hello.rail — first Rail program (compiles natively)

double x = x * 2
factorial n = if n <= 1 then 1 else n * factorial (n - 1)

main =
  let _ = print "hello, rail"
  let _ = print (factorial 10)
  let _ = print (double 21)
  0
```

Ten lines including the comment. Functions are `name args = body`. `main` is the entry point; its return value is the process exit code.

## 4. Run the test suite

```bash
./rail_native test
```

```
... (long test log) ...
251/251 tests passed
```

The test suite covers parser, codegen, type inference, the runtime allocator, and the standard library. The count fluctuates a little if concurrent sessions race on `/tmp/rail_out`. Every test should pass (251 on master on 2026-10-19); if the count comes up short, check `ps` for orphaned runs and re-run.

## 5. Self-compile

```bash
RAIL_ARENA_MB=6000 ./rail_native self
```

The compiler compiles itself to `/tmp/rail_self`. The arena setting is required: below 2000 MB the compiler's own source thrashes, so a bare `self` refuses with exit 2. On a clean checkout the first cycle may differ — the seed's shipped runtime asm doesn't always match what its own source emits. Install gen1 and re-run to confirm convergence at gen2:

```bash
cp /tmp/rail_self ./rail_native
RAIL_ARENA_MB=6000 ./rail_native self
cmp rail_native /tmp/rail_self && echo "byte-identical"
```

```
byte-identical
```

This is the fixed-point property: the compiler's output is its own input. The bootstrap is a 2-cycle limit cycle — gen2 == gen3 == gen4 byte-identically. If `cmp` still differs after 3 cycles, codegen is non-deterministic and wants investigation. See `docs/archive/notes/bootstrap_convergence_audit_2026-05-13.md`.

## 6. Compile a real example

```bash
./rail_native run examples/quicksort.rail
```

```
Compiling examples/quicksort.rail (1089 chars)...
  as: OK
  ld: OK
Input:
3 6 1 8 2 9 4 7 5
Sorted:
1 2 3 4 5 6 7 8 9

Larger list:
2 5 11 17 28 33 42 50 64 79 88 93
```

The source is 36 lines including comments. Cross-reference with [examples/quicksort.md](examples/quicksort.md) for the explanation.

## 7. Try the WebAssembly backend

```bash
./rail_native wasm examples/wasm/hello.rail
```

```
Compiling examples/wasm/hello.rail to WASM...
  WAT: 51277 bytes
  wat2wasm: OK
  Binary: /tmp/rail_out.wasm
```

`./rail_native wasm` emits a `.wat` file, runs the WebAssembly Binary Toolkit `wat2wasm` on it, and produces `/tmp/rail_out.wasm` (~12 KB). Load it in any WASM runtime that provides the `env.print` import (the live playground at ledatic.org does this).

You need `wat2wasm` on `PATH` for this step. On macOS: `brew install wabt`.

## 8. Regenerate the stdlib reference

```bash
./rail_native run tools/docs/gen_stdlib_ref.rail
```

```
files processed: 80
wrote: docs/site/stdlib.md (124876 bytes)
```

The reference at [stdlib.md](stdlib.md) is auto-generated from the actual stdlib source. The walker is a 250-line Rail program that reads each `stdlib/*.rail`, extracts top-level function signatures with their leading comments, and emits markdown. Read it: `tools/docs/gen_stdlib_ref.rail`.

## 9. Verify a signed release

Rail's tagged releases are signed against the Ledatic entropy beacon. Check one with the site's verifier. It needs OpenSSL 3; stock macOS LibreSSL exits 1 without a message.

```bash
curl -sfO https://ledatic.org/attest/verify.sh
curl -sfO https://ledatic.org/releases/v5.4.0/rail_native
curl -sfO https://ledatic.org/releases/v5.4.0/rail_native.attestation.json
bash verify.sh rail_native rail_native.attestation.json
```

```
ok  artifact=rail_native  pulse_id=7309035  pk_fp=cac5f21a70564aeb
```

The downloaded binary is the one committed at the tag: `git show v5.4.0:rail_native | shasum -a 256` gives the same digest. Separately, `rail_safe.sha256` pins the `rail_safe` binary for tamper detection.

---

You now have a working Rail toolchain on local hardware. Next steps:

- Skim [examples/](examples/) — 19 runnable programs with explanations.
- Skim [stdlib.md](stdlib.md), generated from the source of every stdlib module.
- Read [backends.md](backends.md) if you want to target Linux ARM64, x86_64, or WASM-in-a-browser.
