#!/bin/bash
# Differential check of the Linux ARM64 backend against macOS, on a real aarch64 Linux host.
#
#   tools/test/linux_arm64_check.sh user@host
#
# Each program in tools/test/linux_arm64/ is run here (macOS) and cross-built, copied to the
# host and run there; stdout, stderr and the exit status must be the same. The one exception
# is thread_refused.rail: Linux ARM64 has no threads and must say so and exit 1.
#
# Nothing in CI executes this backend, so this script is the gate; run it after any change to
# tools/linux_libc.s or build_linux. Needs aarch64-elf-as and aarch64-elf-ld, and ssh to the
# host. It writes one mktemp directory there and removes it.
# First run 2026-11-19 on a Pi Zero 2 W: try, error inside try, and float text were all wrong
# before that day (see tools/linux_libc.s).
set -u
host="${1:?usage: linux_arm64_check.sh user@host}"
cd "$(dirname "$0")/../.." || exit 2
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
remote="$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$host" 'uname -m; mktemp -d')" || { echo "FAIL: cannot reach $host"; exit 2; }
arch="$(echo "$remote" | sed -n 1p)"; rdir="$(echo "$remote" | sed -n 2p)"
[ "$arch" = "aarch64" ] || { echo "FAIL: $host is $arch, not aarch64"; exit 2; }
fail=0
for src in tools/test/linux_arm64/*.rail; do
  name="$(basename "$src" .rail)"
  ./rail_native --out-prefix "$work/$name.mac" run "$src" > "$work/$name.mac.raw" 2>&1
  mrc=$?
  grep -v -e '^Compiling' -e 'wrote' -e '^  link:' "$work/$name.mac.raw" > "$work/$name.mac.out"
  ./rail_native linux "$src" > "$work/$name.build" 2>&1
  if ! grep -q 'ld: OK' "$work/$name.build"; then echo "FAIL: $name: cross-build"; fail=1; continue; fi
  cp /tmp/rail_linux "$work/$name.elf"
  scp -q -o BatchMode=yes "$work/$name.elf" "$host:$rdir/" || { echo "FAIL: $name: copy"; fail=1; continue; }
  ssh -o BatchMode=yes "$host" "cd $rdir && timeout 60 ./$name.elf 2>&1; echo \"[rc \$?]\"" > "$work/$name.pi.raw"
  prc="$(tail -1 "$work/$name.pi.raw")"
  sed '$d' "$work/$name.pi.raw" > "$work/$name.pi.out"
  if [ "$name" = "thread_refused" ]; then
    if [ "$prc" = "[rc 1]" ] && grep -q 'spawn_thread is not supported on Linux ARM64' "$work/$name.pi.out"; then
      echo "PASS: $name (refused, exit 1)"
    else echo "FAIL: $name: wanted the refusal and exit 1, got $prc"; fail=1; fi
    continue
  fi
  if [ "$prc" = "[rc $mrc]" ] && cmp -s "$work/$name.mac.out" "$work/$name.pi.out"; then
    echo "PASS: $name ($(wc -l < "$work/$name.pi.out" | tr -d ' ') lines, exit $mrc)"
  else
    echo "FAIL: $name: macOS exit $mrc, Linux $prc, $(diff "$work/$name.mac.out" "$work/$name.pi.out" | grep -c '^[<>]') differing lines"
    diff "$work/$name.mac.out" "$work/$name.pi.out" | head -6
    fail=1
  fi
done
ssh -o BatchMode=yes "$host" "rm -rf $rdir"
[ $fail -eq 0 ] && echo "linux_arm64_check: all passed" || echo "linux_arm64_check: FAILED"
exit $fail
