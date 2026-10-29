#!/bin/bash
# run_ci.sh: the probe on the machine running it, then the gate over every record.
#   bash tools/verify/numerics_vs_c/run_ci.sh arm64   C (cc) and Rail (./rail_native) on this Mac
#   bash tools/verify/numerics_vs_c/run_ci.sh x86     C (gcc) and the Rail probe's x86-64 assembly on
#                                                      Linux; probe64_x86.s must sit in this directory
#                                                      (emitted on a Mac by `./rail_native x86 probe64.rail`,
#                                                      it is /tmp/rail_x86.s)
# New records are written as records/{c,rail}_<mode>_ci.txt (gitignored) and judged together with
# the committed ones against records/c_arm64_mini.txt by gate.sh. Exit 0 only on GATE PASS.
# Runs from the repo root: a quoted import such as "stdlib/float_hex.rail" is read relative to the
# current directory, and an import that is not found is a warning, not an error, so a probe
# compiled from inside this directory would die at load.
set -uo pipefail
cd "$(dirname "$0")/../../.." || exit 2
D=tools/verify/numerics_vs_c
mode=${1:?arm64 or x86}
stamp=$(date -u '+%Y-%m-%d %H:%MZ')
run=${GITHUB_RUN_ID:-local}
case "$mode" in
  arm64)
    chip="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || uname -m)"
    cc -O2 -ffp-contract=off "$D/probe64.c" -o /tmp/nvc_probe64_c -lm || exit 2
    { echo "# probe64.c on $chip ($(cc --version | head -1)), $stamp, run $run"
      /tmp/nvc_probe64_c; } > "$D/records/c_arm64_ci.txt"
    seed=$(shasum -a 256 rail_native | cut -c1-12)
    { echo "# probe64.rail on $chip (rail_native $seed), $stamp, run $run"
      ./rail_native --out-prefix /tmp/nvc_probe64_rail run "$D/probe64.rail" 2>/dev/null | grep -E '^(T[1-8] |done$)'; } > "$D/records/rail_arm64_ci.txt"
    ;;
  x86)
    chip="$(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2 | xargs)"
    libc="glibc $(getconf GNU_LIBC_VERSION | awk '{print $2}')"
    [ -s "$D/probe64_x86.s" ] || { echo "no $D/probe64_x86.s: emit it on a Mac with ./rail_native x86 $D/probe64.rail"; exit 2; }
    gcc -O2 -ffp-contract=off "$D/probe64.c" -o /tmp/nvc_probe64_c -lm || exit 2
    { echo "# probe64.c on $chip ($(gcc --version | head -1), $libc), $stamp, run $run"
      /tmp/nvc_probe64_c; } > "$D/records/c_x86_ci.txt"
    gcc -no-pie -o /tmp/nvc_probe64_rail "$D/probe64_x86.s" -lc -lm -lpthread || exit 2
    { echo "# probe64.rail as the x86-64 assembly rail_native emitted, on $chip ($libc), $stamp, run $run"
      /tmp/nvc_probe64_rail; echo "EXIT $?"; } > "$D/records/rail_x86_ci.txt"
    ;;
  *) echo "mode: arm64 or x86"; exit 2 ;;
esac
for f in "$D"/records/*_"$mode"_ci.txt; do echo "== $f: $(head -1 "$f")"; done
"$D/gate.sh"
