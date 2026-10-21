#!/usr/bin/env python3
"""Float literals through the real path, judged against CPython's bits.

Generates decimal literals in every form Rail's lexer admits (W.F, W.FeX, WeX, upper or lower
E, signed exponents), including decimals placed just above, at and just below the midpoint
between two neighbouring doubles and decimals around the subnormal floor and the overflow
line, writes them into Rail programs as literals, compiles and runs the programs with the
compiler under test, and compares the hex that stdlib/float_hex.rail prints for each (the 64
bits, by exact arithmetic) with the bits CPython's float() gives the same text. Both are
correctly rounded, ties to even, so a difference is a defect in tools/decimal64.rail, the
compiler's literal emitter, or float_hex. Nothing from the compiler is imported.

    python3 tools/fuzz/float_literals.py --seed 42 --cases 600
    python3 tools/fuzz/float_literals.py --compiler /tmp/rail_self --cases 3000

Exit 0 when every literal agrees; 1 with the first differences printed; 2 when a program
did not compile or run (the literals of that chunk are listed).
"""
from __future__ import annotations

import argparse
import math
import os
import random
import struct
import subprocess
import sys
import tempfile
from decimal import Decimal, getcontext
from pathlib import Path

CHUNK = 300  # literals per generated program


def bits_of(text: str) -> str:
    return format(struct.unpack(">Q", struct.pack(">d", float(text)))[0], "016x")


def plain(dec: Decimal) -> str:
    """A Decimal as a literal the lexer admits: digits, one dot, optional e and sign."""
    s = format(dec, "e")
    mant, _, exp = s.partition("e")
    if "." not in mant:
        mant += ".0"
    return f"{mant}e{int(exp)}"


def gen(rng: random.Random, n: int) -> list[str]:
    getcontext().prec = 1200
    out: list[str] = []
    while len(out) < n:
        r = rng.random()
        if r < 0.25:
            w = str(rng.randint(0, 10 ** rng.randint(1, 18)))
            f = "".join(rng.choice("0123456789") for _ in range(rng.randint(1, 20)))
            out.append(f"{w}.{f}")
        elif r < 0.45:
            w = str(rng.randint(0, 10 ** rng.randint(1, 17)))
            f = "".join(rng.choice("0123456789") for _ in range(rng.randint(1, 17)))
            e = rng.randint(-330, 310)
            sign = "" if e < 0 else rng.choice(["", "+"])
            out.append(f"{w}.{f}{rng.choice('eE')}{sign}{e}")
        elif r < 0.55:
            w = str(rng.randint(1, 10 ** rng.randint(1, 17)))
            e = rng.randint(-330, 310)
            out.append(f"{w}e{e}")
        elif r < 0.85:
            # the midpoint between two neighbouring doubles, exactly, and one part in 10^d
            # of its magnitude above and below it
            b = rng.getrandbits(63)
            x = struct.unpack(">d", struct.pack(">Q", b))[0]
            y = struct.unpack(">d", struct.pack(">Q", b + 1))[0]
            if math.isnan(x) or math.isnan(y) or math.isinf(y) or x == 0.0:
                continue
            mid = (Decimal(x) + Decimal(y)) / 2
            d = Decimal(rng.randint(1, 9)) * Decimal(10) ** (-rng.randint(1, 30))
            out.append(plain(mid))
            out.append(plain(mid * (1 + d)))
            out.append(plain(mid * (1 - d)))
        elif r < 0.93:
            # around the subnormal floor: 10^-326 to 10^-305
            w = "".join(rng.choice("123456789") for _ in range(rng.randint(1, 17)))
            out.append(f"{w}e{rng.randint(-326, -305)}")
        else:
            # around the overflow line and far past the format either way
            w = "".join(rng.choice("123456789") for _ in range(rng.randint(1, 17)))
            out.append(f"{w}e{rng.choice([rng.randint(290, 310), rng.randint(311, 5000), -rng.randint(331, 5000)])}")
    return out[:n]


def program(lits: list[str]) -> str:
    lines = ['import "stdlib/float_hex.rail"', "main ="]
    for lit in lits:
        lines.append(f'  let _ = print (cat ["{lit} ", show_float_hex {lit}])')
    lines.append("  0")
    return "\n".join(lines) + "\n"


def run_chunk(compiler: str, repo: str, lits: list[str], work: Path, idx: int, timeout: int) -> tuple[dict[str, str], str]:
    src = work / f"lits_{idx}.rail"
    src.write_text(program(lits))
    proc = subprocess.run(
        [compiler, "--out-prefix", str(work / f"lits_{idx}"), "run", str(src)],
        cwd=repo, capture_output=True, text=True, timeout=timeout, check=False,
    )
    got: dict[str, str] = {}
    for line in proc.stdout.splitlines():
        parts = line.split()
        if len(parts) == 2 and len(parts[1]) == 16:
            got[parts[0]] = parts[1]
    err = "" if len(got) == len(lits) else (proc.stderr or proc.stdout)[-1500:]
    return got, err


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--compiler", default=None, help="rail_native to test (default: the repo's)")
    ap.add_argument("--repo", default=None, help="the Rail checkout (default: this file's)")
    ap.add_argument("--seed", type=int, default=42)
    ap.add_argument("--cases", type=int, default=600)
    ap.add_argument("--timeout", type=int, default=300, help="seconds per generated program")
    args = ap.parse_args()

    repo = args.repo or str(Path(__file__).resolve().parents[2])
    compiler = args.compiler or os.path.join(repo, "rail_native")
    rng = random.Random(args.seed)
    lits = gen(rng, args.cases)
    fixed = ["0.0", "1.0", "0.1", "0.3", "2.77777777777778", "0.04908738521234052", "5.0e-324",
             "2.4703282292062327e-324", "2.4703282292062328e-324", "1.7976931348623157e308",
             "1.7976931348623159e308", "1e999", "1e-400", "9007199254740993.0", "1e23",
             "2.2250738585072011e-308", "2.2250738585072012e-308", "1E5", "1.5E-3",
             "1.000000000000000111022302462515654042363166809082031251"]
    lits = fixed + lits

    bad = 0
    shown = 0
    checked = 0
    with tempfile.TemporaryDirectory(prefix="rail_float_lits_") as tmp:
        work = Path(tmp)
        for i in range(0, len(lits), CHUNK):
            chunk = lits[i:i + CHUNK]
            try:
                got, err = run_chunk(compiler, repo, chunk, work, i // CHUNK, args.timeout)
            except subprocess.TimeoutExpired:
                print(f"TIMEOUT: program {i // CHUNK} ({len(chunk)} literals) after {args.timeout}s")
                return 2
            if err:
                print(f"ERROR: program {i // CHUNK} printed {len(got)} of {len(chunk)} literals")
                print(err)
                missing = [l for l in chunk if l not in got]
                print("missing:", " ".join(m[:60] for m in missing[:10]))
                return 2
            for lit in chunk:
                checked += 1
                exp = bits_of(lit)
                if got[lit] != exp:
                    bad += 1
                    if shown < 12:
                        shown += 1
                        print(f"DIFF {lit[:70]}  rail={got[lit]}  cpython={exp}")
    verdict = "PASS" if bad == 0 else "FAIL"
    print(f"{verdict} {checked} literals, {bad} differ from CPython (seed={args.seed}, compiler={compiler})")
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
