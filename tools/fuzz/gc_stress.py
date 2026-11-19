#!/usr/bin/env python3
"""Run programs under RAIL_GC_STRESS and compare them with their normal runs.

The collector only runs when the arena fills, and at the default 1 GB almost
no test program fills it, so a collector bug hides behind a correct answer.
RAIL_GC_STRESS=N makes the runtime collect on every Nth allocation and poison
what it frees, so a live object the collector misses crashes or changes the
output instead of passing unnoticed.

Programs: every suite test in tools/compile.rail whose source is a literal
(run_test "name" "src" "expected"), and every runnable program in the tree that stays inside its
process (the rundiff safety filter). Each is compiled once and run normally;
then under N = 1, 13, 127, 1021, taking the first N that finishes inside the
budget. Verdicts:
  ok      same exit status and output as the normal run
  DIFF    finished under stress with a different status or output
  slow    no N finished inside the budget (not a failure; say how many)
  skip    the normal run itself failed to compile, timed out or crashed

Exit 0 iff no DIFF.
Usage: python3 tools/fuzz/gc_stress.py [--compiler ./rail_native] [--jobs 8]
         [--budget 30] [--ladder 1,13,127,1021] [--only suite|tree] [--env K=V ...]
"""
import argparse
import concurrent.futures as cf
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]

DANGER = re.compile(r'\b(shell|write_file|append_file|write_bytes|tcp_\w*|socket\w*|sock_\w*|http\w*|connect|bind|listen|accept|send|recv|spawn_thread|fork|exec\w*|dlopen|llm|anthropic\w*|slack\w*|mlx\w*|fleet\w*|deploy\w*|gpu_\w*|tgl_\w*|metal\w*|args|read_line|getenv|system|popen|unlink|mkdir|rename|remove|kill|sleep|usleep|nanosleep|fopen|fwrite|open|mmap|foreign|join_thread|rc_\w*|chan\w*|mutex_\w*|quartz\w*|cg_\w*|jit\w*)\b')
IMPORT = re.compile(r'^import\s+"([^"]+)"', re.MULTILINE)


def resolve(name, frm):
    for c in (REPO / name, frm.parent / name, REPO / 'stdlib' / name, REPO / 'stdlib' / (name + '.rail')):
        if c.is_file():
            return c
    return None


def safe(path, seen):
    if path in seen:
        return True
    seen.add(path)
    try:
        src = path.read_text(errors='replace')
    except OSError:
        return False
    code = '\n'.join(l.split('--')[0] for l in src.splitlines())
    if DANGER.search(code):
        return False
    for m in IMPORT.finditer(src):
        p = resolve(m.group(1), path)
        if p is None or not safe(p, seen):
            return False
    return True


def rail_string(s, i):
    """Parse the Rail string literal starting at s[i] == '"'; return (text, next index)."""
    out, i = [], i + 1
    while s[i] != '"':
        if s[i] == '\\':
            c = s[i + 1]
            out.append({'n': '\n', 't': '\t', 'r': '\r'}.get(c, c))
            i += 2
        else:
            out.append(s[i])
            i += 1
    return ''.join(out), i + 1


def suite_programs():
    src = (REPO / 'tools' / 'compile.rail').read_text()
    progs = []
    for m in re.finditer(r'let (t\d+) = run_test "', src):
        i = m.end() - 1
        name, i = rail_string(src, i)
        while src[i] == ' ':
            i += 1
        if src[i] != '"':
            continue  # a source built at run time (t149 to t152 splice dict_src with cat)
        text, i = rail_string(src, i)
        progs.append((f'suite {m.group(1)} {name}', text))
    return progs


def tree_programs():
    files = subprocess.run(['git', 'ls-files', '*.rail'], cwd=REPO, capture_output=True, text=True, check=False).stdout.split()
    progs = []
    for f in files:
        path = REPO / f
        if not path.is_file():
            continue  # deleted or renamed in the working tree, still in the index
        src = path.read_text(errors='replace')
        if re.search(r'^main\b', src, re.MULTILINE) and safe(path, set()):
            progs.append((f, None))
    return progs


# Programs that cannot be stressed, by design. Each is named with its reason; a skip that is
# not here counts against --max-skip (default 0), so a program that stops compiling is seen.
EXPECTED_SKIP = {
    'bare_import': 'imports a module file only the suite run writes',
    'bare_import_as': 'imports a module file only the suite run writes',
    'import': 'imports a module file only the suite run writes',
    'qual_import': 'imports a module file only the suite run writes',
    'generate_ct': 'reads /tmp/rail_gen_code.rail, which only the suite run writes',
    'examples/error_test.rail': 'shows a compile error on purpose',
    'tools/fuzz/known/concat_in_let.rail': 'a known case that must not compile',
    'tools/fuzz/known/ctor_typo_in_pattern.rail': 'a known case that must not compile',
    'tools/fuzz/known/over_application.rail': 'a known case that must not compile',
    'tools/fuzz/known/under_application.rail': 'a known case that must not compile',
}


def expected_skip(label):
    return label in EXPECTED_SKIP or label.split()[-1] in EXPECTED_SKIP


def run(argv, timeout, env=None):
    try:
        p = subprocess.run(argv, cwd=REPO, capture_output=True, timeout=timeout, env=env, stdin=subprocess.DEVNULL, check=False)
        return p.returncode, p.stdout.decode(errors='replace')
    except subprocess.TimeoutExpired:
        return 'timeout', ''


def one(prog, args):
    label, text = prog
    with tempfile.TemporaryDirectory(prefix='gcs-') as d:
        if text is None:
            src = label
        else:
            src = Path(d) / 'prog.rail'
            src.write_text(text)
        binary = Path(d) / 'prog'
        rc, _ = run([args.compiler, '--out-prefix', str(binary), str(src)], 300)
        if rc != 0 or not binary.is_file():
            return label, 'skip', 'compile failed'
        base = run([str(binary)], 20)
        # A negative code is a signal. 128 to 255 is a program's own exit status (main's value):
        # until 2026-11-19 those were skipped as crashes.
        # A normal run that does not finish in 20 s is a slow program on this box, not one that
        # stopped working (CI, 2026-11-19: a hosted runner timed out tools/test/seq_crash_repro.rail).
        if base[0] == 'timeout':
            return label, 'slow', 'the normal run did not finish in 20s'
        if base[0] < 0:
            return label, 'skip', f'normal run rc={base[0]}'
        for n in args.ladder:
            env = dict(os.environ, RAIL_GC_STRESS=str(n), **args.env)
            got = run([str(binary)], args.budget, env)
            if got[0] == 'timeout':
                continue
            if got == base:
                return label, 'ok', f'N={n}'
            return label, 'DIFF', f'N={n}\n    normal rc={base[0]} out={base[1][-300:]!r}\n    stress rc={got[0]} out={got[1][-300:]!r}'
        return label, 'slow', f'no N finished in {args.budget}s'


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--compiler', default=str(REPO / 'rail_native'))
    ap.add_argument('--jobs', type=int, default=8)
    ap.add_argument('--budget', type=int, default=30)
    ap.add_argument('--ladder', default='1,13,127,1021')
    ap.add_argument('--only', choices=['suite', 'tree'])
    ap.add_argument('--env', nargs='*', default=[])
    ap.add_argument('--max-skip', type=int, default=0)
    args = ap.parse_args()
    args.compiler = str(Path(args.compiler).resolve())
    args.ladder = [int(x) for x in args.ladder.split(',')]
    args.env = dict(kv.split('=', 1) for kv in args.env)
    progs = []
    if args.only != 'tree':
        progs += suite_programs()
    if args.only != 'suite':
        progs += tree_programs()
    counts = {}
    with cf.ThreadPoolExecutor(args.jobs) as ex:
        for label, verdict, detail in ex.map(lambda p: one(p, args), progs):
            if verdict == 'skip' and expected_skip(label):
                verdict = 'expected-skip'
            counts[verdict] = counts.get(verdict, 0) + 1
            if verdict in ('DIFF', 'slow', 'skip'):
                print(f'{verdict:5} {label}  {detail}', flush=True)
    print('  '.join(f'{k} {v}' for k, v in sorted(counts.items())))
    # A program that could not be stressed is not a program that passed. Skips are listed and
    # bounded: more than --max-skip of them, or no program checked at all, fails the run
    # (until 2026-11-19 a run that skipped everything exited 0).
    if counts.get('DIFF'):
        return 1
    if not counts.get('ok'):
        print('FAIL: no program was stressed')
        return 1
    if counts.get('skip', 0) > args.max_skip:
        print(f"FAIL: {counts['skip']} skipped, --max-skip is {args.max_skip}")
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
