# Rail numerics contract

What a Rail program's numbers are, sentence by sentence, each with the test that pins it and
the platforms it was measured on. "Bit-exact" is a checkable claim only when the contract is
written and each line of it can fail; this is that contract (Tier 3, step 9, 2026-10-22). A
sentence without a test is marked so.

**Platforms.** Each claim names where it was measured:

| Triple | Machine | How |
|---|---|---|
| `arm64-apple-darwin25.6` | the Mini and the Air (macOS 26.6.2, build 25G83) and GitHub's `macos-latest` runner | the suite (`./rail_native test`) |
| `aarch64-linux` | Pi Zero 2 W (Debian 12, kernel 6.6.51); built on the Mini by `./rail_native linux`, assembled by GNU `aarch64-elf-as`, statically linked against `tools/linux_libc.s` (no glibc on the path) | `tools/verify/numerics_probe.rail` cross-compiled and run there, 2026-10-22 |
| `x86_64-linux` | the `x86` backend | nothing below is claimed; nothing was measured |

The Linux column is also an assembler cross-check: a different assembler encoded the same
instructions and the bits agree.

The probe is the suite's numerics tests in one program; `tools/verify/numerics_probe.expected`
is its output on macOS, and the Linux run differed only on the two lines sentence 16 names:

```
./rail_native run tools/verify/numerics_probe.rail | diff - tools/verify/numerics_probe.expected
./rail_native linux tools/verify/numerics_probe.rail && scp /tmp/rail_linux pi:probe && ssh pi ./probe
```

## Integers

1. An int is a 63-bit two's complement value in [-2^62, 2^62); `+`, `-` and `*` past either end
   wrap modulo 2^63 and nothing traps.
   Test t262. Measured `arm64-apple-darwin25.6`, `aarch64-linux`.
2. An integer literal anywhere in that range denotes that integer. (Until 2026-10-22 a literal
   at or past 2^61 in either direction was emitted with its tag overflowed inside the
   compiler: 2^61 read as -2^61 and 2^62 - 1 as -1, while the same values computed at run
   time were right. `emit_load_tagged_reg` in `tools/compile.rail`.)
   Test t262. Measured `arm64-apple-darwin25.6`, `aarch64-linux`.
3. `/` truncates toward zero and `%` carries the dividend's sign, so `a == (a / b) * b + a % b`;
   a zero divisor gives `a / 0 == 0` and `a % 0 == a` (ARM64 `sdiv` and `msub`; no trap).
   Test t261. Measured `arm64-apple-darwin25.6`, `aarch64-linux`.
4. The compiler's constant folder agrees with the run-time path on sentences 1 to 3: a folded
   `(0 - 7) / 2` and a folded literal give what a function call gives.
   Tests t261 (the folded pair), t262 (the folded literals). Measured `arm64-apple-darwin25.6`,
   `aarch64-linux`.
5. `mul_shr a b s` is `(a * b) >> s` with the product kept in 128 bits (`mul` and `smulh`), so a
   fixed-point multiply never overflows the 63-bit int.
   Test t173. Measured `arm64-apple-darwin25.6`, `aarch64-linux`.
6. `stdlib/math_exact.rail` computes sin, cos, exp, tanh, sqrt and gelu as fixed-point integer
   algorithms (F = 24), integer add, subtract, multiply and truncating divide only, so the same
   input gives the same integer on any machine with these semantics; the result is a
   deterministic approximation within about 1e-7 of libm, not libm's value.
   Test t258 (eleven integer known answers, two doubles by their bits, and a line that says the
   result is near libm, not equal). Measured `arm64-apple-darwin25.6`; `aarch64-linux` through
   the entropy beacon's known-answer test and the 38-frame replay, which uses `sin_fixed`
   (rail-plasma `docs/REPLAY.md`, 2026-10-21).

## Floats

7. A float is an IEEE 754 binary64, raw in a d-register or a frame slot wherever the types prove
   it float (`docs/TYPES.md`); `+.`, `-.`, `*.`, `/.` and `fsqrt` are the ARM64 instructions
   `fadd`, `fsub`, `fmul`, `fdiv`, `fsqrt`, round to nearest, ties to even: 1/3 is
   `3fd5555555555555`, 0.1 * 3 is one ulp above 0.3, 1e308 * 10 is +inf, 0 * -1 is -0, x - x is
   +0, sqrt 2 is `3ff6a09e667f3bcd`. (The assembler had no encoding for `fsqrt` until this test
   was written; a program that called it was refused at link.)
   Test t266. Measured `arm64-apple-darwin25.6`, `aarch64-linux`.
8. The undotted `+ - * /` on floats are the same operations (0.1 + 0.2 is `3fd3333333333334`),
   and an int that meets a float is promoted to float.
   Tests t257, t106. Measured `arm64-apple-darwin25.6`, `aarch64-linux`.
9. A float literal's 64 bits are decided when the program is compiled, correctly rounded, ties
   to even, by integer arithmetic (`tools/decimal64.rail`); no platform conversion runs.
   Test t259 (seventeen literals against CPython's bits); `tools/fuzz/float_literals.py`
   (generated literals at and around midpoints, the subnormal floor and the overflow line,
   against CPython). Measured `arm64-apple-darwin25.6`; `aarch64-linux` by a 38-literal probe
   on 2026-10-21 (rail-plasma `docs/REPLAY.md`).
10. `parse_float` at run time is the same conversion compiled into the program: what C's `atof`
    reads (blanks, a sign, digits with an optional fraction and exponent, `inf`, `infinity`,
    `nan` in any case; text after the number ignored; no number is 0.0; a hex float is not
    read), the double built from its fields by exact arithmetic.
    Test t260 (nineteen texts); `float_literals.py` sends every literal through this door too.
    Measured `arm64-apple-darwin25.6`; `aarch64-linux` by a 26-text probe on 2026-10-22.
11. `show_float_hex` (`stdlib/float_hex.rail`) derives a double's 64 bits by exact arithmetic
    alone (comparisons, doubling, halving, subtracting 1, converting an integer-valued double),
    so the same bits print the same sixteen hex digits on every IEEE 754 platform; every NaN
    prints as `7ff8000000000000`. This is the judge every other float sentence uses.
    Test t257. Measured `arm64-apple-darwin25.6`, `aarch64-linux` (every hex line of the probe
    identical).
12. A float reduction is evaluated in source order, left to right, never reassociated or
    vectorised: 1e16 + 1 + 1 - 1e16 is 0 (each 1 is lost at 1e16's spacing of 2) through a list
    and through a float array, and would be 2 in any other order.
    Test t263. Measured `arm64-apple-darwin25.6`, `aarch64-linux`.
13. `to_int` truncates toward zero (`fcvtzs`): 2.7 is 2, -2.7 is -2, -0.5 is 0.
    Test t264. Measured `arm64-apple-darwin25.6`, `aarch64-linux`.
14. A float stored into a tuple, a list or an ADT field, or passed where untyped data can reach,
    is boxed (a tag-6 object) and read back through `_rail_fval` with the same 64 bits, a
    subnormal and a NaN included (the boundary of 2026-09-11; before it a float taken out of a
    tuple was dereferenced as a pointer).
    Test t265. Measured `arm64-apple-darwin25.6`, `aarch64-linux`.
15. A `float_arr` holds raw doubles; `f32_write`/`f32_read` round each double to the nearest
    float32 on the way to the file and back.
    Test t104. Measured `arm64-apple-darwin25.6`; `aarch64-linux` by the beacon's planes file,
    byte-identical to the Mini's for the 38-frame record (2026-10-21).
16. Float text is not a cross-platform judge. `show_float` (12 significant digits) and
    `show_float_exact` (`%.17g`, which round-trips the double) go through the platform's
    `snprintf`: on macOS `show_float_exact (0.1 + 0.2)` is `0.30000000000000004`; on the Linux
    build the runtime's `snprintf` in `tools/linux_libc.s` ignores the precision and prints
    `0.3` and `0.333333`. Judge by bits (sentence 11), not by text.
    Test t196 pins the macOS text. Measured `arm64-apple-darwin25.6`; `aarch64-linux` measured
    different on 2026-10-22 and claimed as such.

## Not claimed

17. Host libm through FFI (`sqrt sin cos tanh exp log pow fabs floor ceil atan2`,
    `stdlib/math.rail`) returns whatever the platform's libm returns: not correctly rounded, not
    the same across libcs, not pinned here. A program on the replay path uses sentence 6 instead.
    No test pins libm's bits, by design; t258's last line is the only reference to it.
    Measured 2026-10-29 (crossvendor raillane R1, `probe64.rail` against `probe64.c`): libm `fma`
    through `foreign fma a b c -> float` agrees with C's `fma` bit for bit on the Mini and the Air
    (IEEE 754-2008 requires fma correctly rounded, so this is the one libm name that may be
    relied on; still not pinned by a test), and libm `exp` agreed between Apple's libm and glibc
    2.39 on the eight values probed, which proves nothing. A user-declared foreign float fn's
    raw result reached `_rail_fval` until 2026-10-29 (t267).
18. The `x86_64` backend's float lowering is not claimed to match ARM64. First measurement,
    2026-10-29 (crossvendor raillane R1: `probe64.rail` cross-compiled on the Mini, assembled and
    run on a GitHub x86-64 runner, bits against `probe64.c` built with gcc `-ffp-contract=off`):
    `+. *. /.`, `fsqrt`, `to_float` and integer-made inputs agree bit for bit (eight 1024-term plain
    dot products, eight divisions, eight 1/sqrt); a foreign float call (`floor`, `fma`) returns
    garbage, and a float comparison inside a clamp takes the wrong branch (`tools/fuzz/known/
    x86_foreign_float_call.rail`, `x86_float_compare.rail`, both live). No test.

## What "bit-exact" is scoped to

The integer sentences (1 to 6) and the float sentences 7 to 15 are the substrate the attestation
claims rest on, on `arm64-apple-darwin25.6` by the suite and on `aarch64-linux` by the probe and
the beacon's replay. The entropy beacon's record (rail-plasma) replays on both: the 38-frame
record of 2026-10-21 reproduces the Mini's digest on the Pi, with no libm, no `atof` and no
`snprintf` on its path.

Provenance, not correctness: a bit-identical result proves the same computation ran, not that
the computation is right. See [THREAT_MODEL.md](THREAT_MODEL.md). The seed the record names is
itself a documented object: [SEED_FORMAT.md](SEED_FORMAT.md).
