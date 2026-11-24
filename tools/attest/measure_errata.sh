#!/usr/bin/env bash
# measure_errata.sh: measure the release record's known gaps and print them as JSON.
#
# The record is honest only if its holes are written down and signed. This script
# re-measures the four gap classes of docs/RELEASES.md ("Known gaps in the record")
# against the tree it runs in, so the errata is a measurement, never a quote:
#   unsigned   : releases/*/index.json with no index.json.attestation.json, with the
#                sha256 of each index as it stands (so a later edit is visible)
#   orphan     : indexes whose git.commit is on no branch of the public remote (origin)
#   renamed    : indexes whose git.commit is not the same-named tag's commit, but the
#                attested tools/compile.rail is byte-equal at both (the 2026-10 history
#                rewrite kept the bytes and changed the names)
#   tag_split  : indexes whose git.commit is not the tag's commit AND compile.rail differs
#   sidecar    : attestation sidecars whose artifact.sha256 is not the file's hash
# Output is sorted and carries no timestamp, so two runs on one tree are byte-equal;
# the attestation sidecar carries the time. Usage: measure_errata.sh > releases/errata/<date>.json
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
sha() { shasum -a 256 "$1" | cut -c1-64; }
field() { sed -n "s/.*\"$2\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$1" | head -1; }

unsigned=(); orphan=(); renamed=(); tag_split=(); sidecar=()
for d in releases/*/; do
  idx="$d/index.json"; [ -f "$idx" ] || continue
  name=$(basename "$d")
  [ -f "$idx.attestation.json" ] || unsigned+=("    {\"release\": \"$name\", \"index_sha256\": \"$(sha "$idx")\"}")
  c=$(field "$idx" commit); [ -n "$c" ] || continue
  if [ -z "$(git branch -r --list 'origin/*' --contains "$c" 2>/dev/null)" ]; then
    orphan+=("    {\"release\": \"$name\", \"commit\": \"$c\"}")
  fi
  if t=$(git rev-parse -q --verify "refs/tags/$name^{commit}" 2>/dev/null); then
    case "$t" in "$c"*) ;; *)
      a=$(git rev-parse -q --verify "$c:tools/compile.rail" 2>/dev/null || true)
      b=$(git rev-parse -q --verify "$t:tools/compile.rail" 2>/dev/null || true)
      row="{\"release\": \"$name\", \"index_commit\": \"$c\", \"tag_commit\": \"${t:0:9}\"}"
      if [ -n "$a" ] && [ "$a" = "$b" ]; then renamed+=("    $row"); else tag_split+=("    $row"); fi;;
    esac
  fi
done
while IFS= read -r att; do
  art="${att%.attestation.json}"; [ -f "$art" ] || continue
  want=$(field "$att" sha256); have=$(sha "$art")
  [ "$want" = "$have" ] || sidecar+=("    {\"attestation\": \"$att\", \"claimed_sha256\": \"$want\", \"file_sha256\": \"$have\"}")
done < <(find releases builds -name '*.attestation.json' 2>/dev/null | sort)

join() { local IFS=$'\n'; local out=""; for x in "$@"; do out+="${out:+,$'\n'}$x"; done; printf '%s' "$out"; }
cat <<JSON
{
  "kind": "ledatic.release-errata",
  "version": 1,
  "note": "Measured gaps in this repository's release record. Each entry is a fact about a past record left as it was; none is repaired. Re-measure with tools/attest/measure_errata.sh; tools/verify/check_errata.sh diffs the two.",
  "unsigned_indexes": [
$(join "${unsigned[@]+"${unsigned[@]}"}")
  ],
  "orphan_commits": [
$(join "${orphan[@]+"${orphan[@]}"}")
  ],
  "index_names_prerewrite_commit_bytes_equal": [
$(join "${renamed[@]+"${renamed[@]}"}")
  ],
  "tag_disagrees_with_index_bytes_differ": [
$(join "${tag_split[@]+"${tag_split[@]}"}")
  ],
  "sidecar_disagrees_with_file": [
$(join "${sidecar[@]+"${sidecar[@]}"}")
  ]
}
JSON
