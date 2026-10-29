# Rail's doubles against C's, bit for bit

`docs/NUMERICS.md` says what a Rail float is: an IEEE 754 binary64, `+. -. *. /.` and `fsqrt`
the ARM64 instructions, round to nearest, ties to even (sentence 7). This directory measures that
sentence against a C compiler on every run of CI, and measures the two sentences the contract
does not claim (17, host libm through FFI; 18, the `x86_64` backend's floats).

`probe64.c` and `probe64.rail` are the same seven computations in IEEE doubles from the same
integer-made inputs (no float is parsed anywhere), every result printed as its 64 bits, in Rail
by `show_float_hex` (sentence 11, the judge). `gate.sh` compares records line by line against
`records/c_arm64_mini.txt`, the C probe on the maintainer's Mac Mini M4 Pro (Apple clang 17,
`-ffp-contract=off`).

| Test | What | Rail's instruction or call |
|---|---|---|
| T1 `dot_plain` | eight 1024-term dot products, multiply then add as two operations | `fmul`, `fadd` |
| T2 `div` | eight divisions | `fdiv` |
| T3 `one_over_sqrt` | eight 1/sqrt | `fsqrt`, `fdiv` |
| T4 `floor` | libm `floor` of a scaled value | FFI `floor` |
| T5 `exp_poly` | exp as 2^(x log2 e), Horner with separate multiply and add, 2^k by exact doubling | `fmul`, `fadd`, `fsub`, FFI `floor` |
| T6 `tanh_poly` | the Pade (27 + x^2) x / (27 + 9 x^2), clamped to [-5, 5] | `fmul`, `fadd`, `fdiv`, float compare |
| T7 `dot_fma_libm` | the same eight dot products through libm `fma` | FFI `fma` (`foreign fma a b c -> float`) |
| T8 `exp_libm_noclaim` | libm `exp` | FFI `exp`: printed, never judged |

## What CI runs

- **`numerics`** (macOS arm64 runner): `run_ci.sh arm64` builds the C probe with the runner's
  clang, runs the Rail probe with the committed `rail_native`, writes both as
  `records/{c,rail}_arm64_ci.txt` and runs the gate over every record. It then emits the Rail
  probe as x86-64 assembly (`./rail_native x86 probe64.rail`) for the next job.
- **`numerics-x86`** (Linux x86-64 runner): `run_ci.sh x86` builds the C probe with gcc, assembles
  and links the seed's x86-64 output with gcc, writes `records/{c,rail}_x86_ci.txt` and runs the
  gate. The `x86_64` backend has two open float defects (`tools/fuzz/known/x86_foreign_float_call.rail`,
  `x86_float_compare.rail`); `known_live.txt` names the tests they break, the gate prints those
  as `KNOWN`, and it fails if one of them starts passing before the list is updated.

The committed records (2026-10-29, the night the lane was built in the lab):

| Record | Machine | Toolchain | T1 to T7 |
|---|---|---|---|
| `c_arm64_mini` (reference) | Mac Mini M4 Pro | Apple clang 17, `-ffp-contract=off` | |
| `c_arm64_air` | MacBook Air M1 | Apple clang 15, `-ffp-contract=off` | 7 PASS |
| `c_x86_gh` | GitHub runner, AMD EPYC 7763, glibc 2.39 | gcc 13, `-ffp-contract=off` | 7 PASS |
| `rail_arm64_mini` | Mac Mini M4 Pro | `rail_native` at `b8e26fa` | 7 PASS |
| `rail_arm64_air` | MacBook Air M1 | the same binary | 7 PASS |
| `rail_x86_gh` | GitHub runner, AMD EPYC 7763 | the seed's x86-64 assembly, gcc-linked | 3 PASS, 4 KNOWN |

So on arm64 Rail's own arithmetic, its float comparison, its `to_float` and its FFI `floor` and
`fma` give C's bits on two Macs and on GitHub's runner; libm `fma` through FFI equals C's `fma`
(IEEE 754-2008 requires `fma` correctly rounded, which is why this one libm name agrees and
sentence 17 still pins none of the others). On x86-64, `+. *. /.`, `fsqrt` and `to_float` agree
with C; a foreign float call and a float comparison inside a clamp do not, and are recorded.

## What it found

The first Rail run of T7 failed on both Macs with the same wrong bits. A user-declared
`foreign f ... -> float` returned raw float bits that the compiler then read through the
generic-to-float reader, which treats raw bits with an odd mantissa as a tagged int, so about
half of all such results were garbage. Fixed the same night (`foreign_float_ret_markers` in
`tools/compile.rail`, test t267, PR #173); `tools/fuzz/known/foreign_float_result_raw.rail` is
the known case.

## Rerun

```
bash tools/verify/numerics_vs_c/run_ci.sh arm64        # on any Apple Silicon Mac with clang
./rail_native x86 tools/verify/numerics_vs_c/probe64.rail && cp /tmp/rail_x86.s tools/verify/numerics_vs_c/
bash tools/verify/numerics_vs_c/run_ci.sh x86          # on an x86-64 Linux box with gcc, after the line above
tools/verify/numerics_vs_c/gate.sh                     # the committed records alone
```

A record is a text file: anyone can produce one on another chip or compiler and compare it with
`gate.sh REF OTHER`. T8 is printed in every record and never judged: libm `exp` agreed between
Apple's libm and glibc 2.39 on the eight values probed, which proves nothing about other values.
