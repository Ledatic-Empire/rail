#!/usr/bin/env python3
"""The x86_64 known cases (tools/fuzz/known/x86_cases.json), through the x86 backend and run.

known_cases.py drives the arm64 compiler and never reads x86_cases.json; until 2026-11-05 those
cases were a record, run by nobody. Two halves, since no Mac assembles or runs x86-64 here:

  emit DIR   on a Mac: `rail_native x86 tools/fuzz/known/<name>.rail` for every case, the emitted
             assembly saved as DIR/<name>.s (the backend's own link step fails on a Mac; the .s is
             what matters)
  run DIR    on x86-64 Linux: gcc assembles and links DIR/<name>.s, the binary runs, and its stdout
             must equal the case's expected text (a `live` case must still fail, and is reported
             loudly when it starts passing). Exit 0 iff every case behaves as its status says.

CI: the numerics job emits (macos), the numerics-x86 job runs (ubuntu), the same artifact between.
"""
import json
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent.parent
KNOWN = HERE / "known"


def cases():
    return json.load(open(KNOWN / "x86_cases.json"))


def emit(out):
    out.mkdir(parents=True, exist_ok=True)
    bad = 0
    for name in cases():
        emitted = Path("/tmp/rail_x86.s")
        if emitted.exists():
            emitted.unlink()
        p = subprocess.run([str(REPO / "rail_native"), "x86", str(KNOWN / f"{name}.rail")],
                           cwd=REPO, capture_output=True, text=True, timeout=120, check=False)
        if not emitted.exists():
            bad += 1
            print(f"  NO       {name}: nothing emitted\n{p.stdout[-400:]}{p.stderr[-400:]}")
            continue
        shutil.copy(emitted, out / f"{name}.s")
        print(f"  emitted  {name}: {(out / (name + '.s')).stat().st_size} bytes")
    print(f"{'ok' if bad == 0 else 'NO'}: {len(cases())} cases emitted to {out}, {bad} missing")
    return 1 if bad else 0


def observe(out, name):
    src, binary = out / f"{name}.s", out / name
    if not src.exists():
        return "no assembly emitted"
    p = subprocess.run(["gcc", "-no-pie", "-o", str(binary), str(src), "-lc", "-lm", "-lpthread"],
                       capture_output=True, text=True, timeout=120, check=False)
    if p.returncode != 0:
        return "link error: " + (p.stderr.strip().splitlines() or ["?"])[-1][:120]
    try:
        p = subprocess.run([str(binary)], cwd=REPO, capture_output=True, text=True, timeout=30, check=False)
    except subprocess.TimeoutExpired:
        return "runtime timeout"
    if p.returncode != 0:
        return f"exit {p.returncode}: {p.stdout.strip()}"
    return p.stdout.rstrip("\n")


def run(out):
    bad = 0
    for name, (status, expected, note) in cases().items():
        got = observe(out, name)
        passed = got == expected
        if status == "live":
            if passed:
                bad += 1
                print(f"  PROMOTE  {name}: live case now PASSES on x86-64; set its status to fixed")
            else:
                print(f"  live     {name}: still fails ({(got.splitlines() or ['no output'])[0][:60]})")
        elif passed:
            print(f"  ok       {name}")
        else:
            bad += 1
            print(f"  NO       {name} [{status}]: expected {expected!r}, got {got!r}\n           {note}")
    print(f"{'ok' if bad == 0 else 'NO'}: {len(cases())} x86 cases, {bad} unexpected")
    return 1 if bad else 0


def main():
    if len(sys.argv) != 3 or sys.argv[1] not in ("emit", "run"):
        sys.exit(__doc__)
    out = Path(sys.argv[2]).resolve()
    sys.exit(emit(out) if sys.argv[1] == "emit" else run(out))


if __name__ == "__main__":
    main()
