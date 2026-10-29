#!/bin/bash
# gate.sh: the judge. Every record in records/ (a Rail or C probe run on some chip) is compared
# line by line with the reference (the C probe on the maintainer's Mac Mini M4 Pro) on tests T1 to
# T7; T8 (libm exp) is printed as a note and never claimed. A record must end with "done". Lines in
# known_live.txt are open compiler defects: printed as KNOWN, and a FAIL if they start passing.
# Exit 0 only on GATE PASS. README.md in this directory has the tests and the committed records.
#   ./gate.sh                 every record against records/c_arm64_mini.txt
#   ./gate.sh REF OTHER       one explicit pair
set -uo pipefail
cd "$(dirname "$0")"
fail=0
claimed() { grep -E '^T[1-7] ' "$1"; }
pair() { # pair REF OTHER
  local ref=$1 oth=$2 label; label=$(basename "$oth" .txt)
  echo "== $label  vs  $(basename "$ref")"
  [ -s "$oth" ] || { echo "FAIL $label missing"; fail=1; return; }
  grep -q '^done$' "$oth" || { echo "FAIL $label did not finish (no done line)"; fail=1; }
  local n; n=$(claimed "$oth" | wc -l | tr -d ' '); [ "$n" -eq 56 ] || { echo "FAIL $label $n claimed lines (56 expected)"; fail=1; }
  for t in T1 T2 T3 T4 T5 T6 T7; do
    local a b known; a=$(grep -E "^$t " "$ref" | awk '{print $2, $3, $4}'); b=$(grep -E "^$t " "$oth" | awk '{print $2, $3, $4}')
    known=$(grep -E "^$label $t " known_live.txt 2>/dev/null | awk '{print $3}')
    if [ "$a" = "$b" ] && [ -n "$a" ]; then
      if [ -n "$known" ]; then printf 'FAIL %-28s %-3s passes but is listed as known-live (%s): update known_live.txt\n' "$label" "$t" "$known"; fail=1
      else printf 'PASS %-28s %-3s %s\n' "$label" "$t" "$(echo "$a" | head -1 | awk '{print $1}')"; fi
    elif [ -n "$known" ]; then printf 'KNOWN %-27s %-3s differs, open defect %s\n' "$label" "$t" "$known"
    else printf 'FAIL %-28s %-3s differs:\n' "$label" "$t"; diff <(echo "$a") <(echo "$b") | grep -E '^[<>]' | head -4; fail=1; fi
  done
  local ea eb; ea=$(grep -E '^T8 ' "$ref" | awk '{print $4}' | tr '\n' ' '); eb=$(grep -E '^T8 ' "$oth" | awk '{print $4}' | tr '\n' ' ')
  printf 'note %-28s T8  exp_libm %s (no claim)\n' "$label" "$([ "$ea" = "$eb" ] && echo same || echo differs)"; }
if [ $# -eq 2 ]; then pair "$1" "$2"
else
  REF=records/c_arm64_mini.txt; [ -s "$REF" ] || { echo "FAIL no reference $REF"; exit 1; }
  n=0; for f in $(ls -1 records/*.txt | sort); do [ "$f" = "$REF" ] && continue; pair "$REF" "$f"; n=$((n+1)); done
  [ "$n" -ge 1 ] || { echo "FAIL nothing to compare"; fail=1; }
fi
if [ $fail -eq 0 ]; then echo "GATE PASS"; else echo "GATE FAIL"; fi
exit $fail
