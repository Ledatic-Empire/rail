#!/usr/bin/env python3
"""Hold the in-tree ARM64 assembler (tools/v5/asm.rail) against the system `as`.

forms.txt is the record the suite reads (test asm_ranges): one instruction per line with the
word the system assembler gives it, or `refuse`. This script proves that record on a Mac with
the command line tools: each instruction is assembled alone, framed by nops, by both.

  python3 tools/test/asm_ranges/against_as.py            check forms.txt, exit 1 on a difference
  python3 tools/test/asm_ranges/against_as.py --write    rewrite forms.txt from what `as` says

A form the system assembler takes and ours refuses is recorded as `refuse` under its own
heading: a refusal is honest, a wrong word is not. Run from the repo root.
"""
import os, re, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
FORMS = os.path.join(HERE, "forms.txt")
RAIL = "./rail_native"
NOP = "d503201f"

def words(path):
    r = subprocess.run(["otool", "-t", path], capture_output=True, text=True, timeout=20)
    out = []
    for line in r.stdout.splitlines():
        p = line.split()
        if len(p) > 1 and re.fullmatch(r"[0-9a-f]{16}", p[0]):
            out += p[1:]
    return out

def framed(ws):
    for i in range(len(ws) - 6):
        if ws[i:i + 3] == [NOP] * 3 and ws[i + 4:i + 7] == [NOP] * 3:
            return ws[i + 3]
    return None

def both(ins, d, n):
    s = f"{d}/p{n}.s"
    open(s, "w").write(".text\n.globl _probe\n.p2align 2\n_probe:\n" + "    nop\n" * 3 + f"    {ins}\n" + "    nop\n" * 3 + "    ret\n")
    a = subprocess.run(["as", "-arch", "arm64", "-o", f"{d}/p{n}.o", s], capture_output=True, text=True, timeout=20)
    ref = framed(words(f"{d}/p{n}.o")) if a.returncode == 0 else None
    open(f"{d}/p{n}.rail", "w").write(f'link "{s}"\nforeign probe a -> int\nmain =\n  let _ = print (show (probe 1))\n  0\n')
    r = subprocess.run([RAIL, "--out-prefix", f"{d}/b{n}", f"{d}/p{n}.rail"], capture_output=True, text=True, timeout=60)
    got = framed(words(f"{d}/b{n}")) if r.returncode == 0 and os.path.exists(f"{d}/b{n}") else None
    return ref, got

def main():
    write = "--write" in sys.argv
    rows = [l.rstrip("\n").split("\t") for l in open(FORMS)]
    forms = [(r[0], r[1]) for r in rows if len(r) == 2]
    bad = 0
    counts = {}
    same, refused, ours_only = [], [], []
    with tempfile.TemporaryDirectory() as d:
        for n, (want, ins) in enumerate(forms):
            ref, got = both(ins, d, n)
            if ref and got:
                v = "same" if ref == got else "DIFFERENT-WORD"
            elif ref:
                v = "ours-refuses"
            elif got:
                v = "OURS-TAKES-WHAT-AS-REFUSES"
            else:
                v = "both-refuse"
            now = str(int(ref, 16)) if v == "same" else "refuse"
            stale = (not write) and now != want
            counts[v] = counts.get(v, 0) + 1
            if v.isupper() or stale:
                bad += 1
                print(f"{v:28} {ins:36} as={ref} ours={got}" + ("  (forms.txt says %s)" % want if stale else ""))
            (same if v == "same" else ours_only if v == "ours-refuses" else refused).append((now, ins))
    print(" ".join(f"{k}={c}" for k, c in sorted(counts.items())))
    if write and not bad:
        head = [l for l in open(FORMS) if l.startswith("# ")][:6]
        with open(FORMS, "w") as f:
            f.writelines(head)
            f.write("# the same word as the system assembler\n")
            f.writelines(f"{w}\t{i}\n" for w, i in same)
            f.write("# no encoding: both refuse\n")
            f.writelines(f"{w}\t{i}\n" for w, i in refused)
            f.write("# the system assembler takes these; ours refuses them (unimplemented, never mis-encoded)\n")
            f.writelines(f"{w}\t{i}\n" for w, i in ours_only)
    return 1 if bad else 0

if __name__ == "__main__":
    sys.exit(main())
