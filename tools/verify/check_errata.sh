#!/usr/bin/env bash
# check_errata.sh: the signed release errata must be what the tree measures.
#
# Re-runs tools/attest/measure_errata.sh and compares, byte for byte, with the newest
# releases/errata/<date>.json; then verifies that file's witness attestation. A record
# edited, signed or deleted after the errata was signed makes the compare fail, which is
# the point: the errata is a measurement, and the tree must still agree with it or a new
# dated errata must be written and signed. ERRATA=<path> checks one file instead; the witness pubkey is $1, PUBKEY, or the committed releases/witness-fleet0/fleet0.pub.pem.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
pub=${1:-${PUBKEY:-releases/witness-fleet0/fleet0.pub.pem}}
errata=${ERRATA:-$(ls releases/errata/*.json 2>/dev/null | grep -v attestation | sort | tail -1)}
[ -n "$errata" ] && [ -f "$errata" ] || { echo "check_errata: no releases/errata/<date>.json"; exit 2; }
tmp=$(mktemp -t errata.XXXXXX); trap 'rm -f "$tmp"' EXIT
bash tools/attest/measure_errata.sh > "$tmp" || { echo "check_errata: measure failed"; exit 2; }
if ! diff -u "$errata" "$tmp" > "$tmp.diff"; then
  echo "check_errata: FAIL, the tree no longer measures what $errata says:"
  grep '^[-+] ' "$tmp.diff" | head -12; rm -f "$tmp.diff"; exit 1
fi
rm -f "$tmp.diff"
if [ -f "$errata.attestation.json" ]; then
  bash tools/attest/verify.sh "$errata" "$errata.attestation.json" "$pub" >/dev/null || { echo "check_errata: FAIL, attestation of $errata does not verify"; exit 1; }
  echo "check_errata: ok, $errata is what the tree measures and its attestation verifies"
else
  echo "check_errata: ok on content, $errata has no attestation yet"
fi
