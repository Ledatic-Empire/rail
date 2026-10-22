#!/bin/bash
# tools/independence/seed_format_gate.sh: the proof of docs/SEED_FORMAT.md (Tier 3, step 9).
#
# The Rail linker (tools/v5/link_lib.rail, through tools/independence/link_file.rail) and the
# Python writer written from the document (tools/independence/seed_writer.py) each build
# tools/independence/exit42.s. The two files must be byte-identical, and the result must run
# and exit 42 (the kernel accepts the signature, dyld binds the import, the stores land).
# Exit 0 on PASS, 1 on any difference or refusal. RAIL_BIN selects the compiler under test
# (default ./rail_native). CI runs this after the suite.
set -u
cd "$(dirname "$0")/../.." || exit 1
RAIL="${RAIL_BIN:-./rail_native}"
OUT="${TMPDIR:-/tmp}/seed_gate_$$"
mkdir -p "$OUT"
trap 'rm -rf "$OUT"' EXIT

if ! "$RAIL" --out-prefix "$OUT/link_file" run tools/independence/link_file.rail \
      tools/independence/exit42.s "$OUT/exit42_rail" > "$OUT/rail.log" 2>&1; then
  echo "FAIL seed_format: the Rail linker refused tools/independence/exit42.s"
  cat "$OUT/rail.log"
  exit 1
fi
if ! python3 -I tools/independence/seed_writer.py tools/independence/exit42.s "$OUT/exit42_py" \
      > "$OUT/py.log" 2>&1; then
  echo "FAIL seed_format: the Python writer refused tools/independence/exit42.s"
  cat "$OUT/py.log"
  exit 1
fi
if ! cmp "$OUT/exit42_rail" "$OUT/exit42_py" > "$OUT/cmp.log" 2>&1; then
  echo "FAIL seed_format: the Rail linker and the Python writer differ"
  cat "$OUT/cmp.log"
  cmp -l "$OUT/exit42_rail" "$OUT/exit42_py" 2>/dev/null | head -5
  exit 1
fi
"$OUT/exit42_py"
rc=$?
if [ "$rc" != 42 ]; then
  echo "FAIL seed_format: the written file exited $rc, expected 42"
  exit 1
fi
echo "PASS seed_format: $(wc -c < "$OUT/exit42_py" | tr -d ' ') bytes identical from both writers; the file runs and exits 42"
