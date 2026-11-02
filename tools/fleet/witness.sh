#!/usr/bin/env bash
# witness.sh — entropy beacon witness daemon
#
# Polls ledatic.org/entropy/pulse.json every POLL_SEC seconds,
# verifies chain linkage, signs (pulse_id|value_hex|witnessed_at)
# with a local Ed25519 key, appends to log.jsonl + writes latest.json.
#
# Runs as systemd service; see witness.service.

set -euo pipefail

WITNESS_DIR=${WITNESS_DIR:-$HOME/.ledatic/witness}
SK=${SK:-$WITNESS_DIR/witness.sk}
LOG=${LOG:-$WITNESS_DIR/log.jsonl}
LATEST=${LATEST:-$WITNESS_DIR/latest.json}
STATE=${STATE:-$WITNESS_DIR/state}
CHAIN=${CHAIN:-$WITNESS_DIR/last_value}
BEACON_URL=${BEACON_URL:-https://ledatic.org/entropy/pulse}
ROTATE_AT=${ROTATE_AT:-104857600}   # 100 MB
ROTATE_KEEP=${ROTATE_KEEP:-50}
POLL_SEC=${POLL_SEC:-2}
RESOLVE_SEC=${RESOLVE_SEC:-300}     # look the beacon's host up at most this often
WITNESS_NAME=${WITNESS_NAME:-$(hostname)}

mkdir -p "$WITNESS_DIR"
touch "$LOG" "$STATE" "$CHAIN"

if [ ! -f "$SK" ]; then
  umask 077
  openssl genpkey -algorithm ED25519 -out "$SK"
  chmod 600 "$SK"
fi

# 16-hex fingerprint of DER-encoded SubjectPublicKeyInfo
pk_fp=$(openssl pkey -in "$SK" -pubout -outform DER 2>/dev/null \
  | sha256sum | cut -c1-16)

rotate_if_needed() {
  local sz
  sz=$(stat -c%s "$LOG" 2>/dev/null || echo 0)
  [ "$sz" -lt "$ROTATE_AT" ] && return 0
  local ts n path
  ts=$(date -u +%Y%m%dT%H%M%SZ)
  # find (not ls glob): an empty glob makes `ls` either fail under set -e
  # + pipefail (no nullglob) or silently list cwd (with nullglob). find
  # handles "no matches" cleanly. Earned 2026-05-04 after the rotation
  # bug crashed the Pi witness in a loop for 80 h.
  n=$(find "$WITNESS_DIR" -maxdepth 1 -name 'log.*.jsonl.gz' 2>/dev/null | wc -l)
  path="$WITNESS_DIR/log.${n}.${ts}.jsonl"
  mv "$LOG" "$path"
  gzip -9 "$path"
  : > "$LOG"
  # prune — keep newest ROTATE_KEEP, drop the rest. find -printf '%T@ %p'
  # gives mtime-sortable output that survives an empty match.
  find "$WITNESS_DIR" -maxdepth 1 -name 'log.*.jsonl.gz' -printf '%T@ %p\n' 2>/dev/null \
    | sort -rn \
    | tail -n +"$((ROTATE_KEEP + 1))" \
    | cut -d' ' -f2- \
    | xargs -r rm -f
}

sign_b64() {
  # Ed25519 raw message signing. OpenSSL 3's pkeyutl -rawin requires a real
  # file (oneshot operation needs a seekable input), so we stage to a tmpfile.
  local tmp
  tmp=$(mktemp)
  printf '%s' "$1" > "$tmp"
  openssl pkeyutl -sign -inkey "$SK" -rawin -in "$tmp" 2>/dev/null | base64 -w0
  rm -f "$tmp"
}

read_fields() {
  # $1=raw json. One python3 for all five fields: five per poll held 37% of
  # a Pi Zero core (measured 2026-11-01). Fields are joined by the unit
  # separator, not a tab: tabs are IFS whitespace and an empty field between
  # two of them would collapse and shift the rest.
  printf '%s' "$1" | python3 -c '
import sys, json
d = json.load(sys.stdin)
keys = ("pulse_id", "value_hex", "prev_value_hex", "timestamp_utc", "unix_timestamp")
print("\x1f".join(str(d.get(k, "")) for k in keys))'
}

# Look the beacon's host up once per RESOLVE_SEC and hand curl the address.
# A fresh lookup on every 2 s poll was 69% of all the queries the Pi's DNS
# sinkhole served (measured 2026-11-01). A failed fetch forgets the address,
# so the next poll looks it up again; a failed lookup leaves the pin empty
# and curl resolves the name itself, as it always did.
beacon_host=${BEACON_URL#*://}; beacon_host=${beacon_host%%/*}
beacon_port=443
case "$BEACON_URL" in http://*) beacon_port=80 ;; esac
pin_ip=""
pin_at=0
pin_args=()
pin_refresh() {
  if [ -z "$pin_ip" ] || [ $((EPOCHSECONDS - pin_at)) -ge "$RESOLVE_SEC" ]; then
    pin_ip=$(getent ahostsv4 "$beacon_host" 2>/dev/null | awk 'NR==1{print $1}') || pin_ip=""
    pin_at=$EPOCHSECONDS
  fi
  pin_args=()
  if [ -n "$pin_ip" ]; then
    pin_args=(--resolve "$beacon_host:$beacon_port:$pin_ip")
  fi
}

write_latest() {
  local line=$1
  printf '%s\n' "$line" > "$LATEST.tmp" && mv "$LATEST.tmp" "$LATEST"
}

last_seen=""
[ -s "$STATE" ] && last_seen=$(cat "$STATE")
prev_value=""
[ -s "$CHAIN" ] && prev_value=$(cat "$CHAIN")

echo "witness: starting (pk_fp=$pk_fp, name=$WITNESS_NAME, beacon=$BEACON_URL)"

while :; do
  pin_refresh
  raw=$(curl -sf --max-time 5 "${pin_args[@]}" "$BEACON_URL" 2>/dev/null) || { pin_ip=""; sleep "$POLL_SEC"; continue; }
  [ -n "$raw" ] || { sleep "$POLL_SEC"; continue; }

  fields=$(read_fields "$raw") || { sleep "$POLL_SEC"; continue; }
  IFS=$'\x1f' read -r pulse_id value_hex prev_hex ts_iso ts_unix <<< "$fields"

  [ -n "$pulse_id" ] && [ -n "$value_hex" ] || { sleep "$POLL_SEC"; continue; }
  [ "$pulse_id" = "$last_seen" ] && { sleep "$POLL_SEC"; continue; }

  # Chain verification is only meaningful when we saw the immediately
  # preceding pulse. Polling skips are gaps, not tamper evidence.
  #   chain_verified=true  → prev_hex matched our last value (consecutive pulses)
  #   chain_verified=false → prev_hex mismatched AND gap==1 (real break)
  #   chain_verified=null  → gap>1 or first observation (not verifiable)
  gap=0
  chain_verified=null
  if [ -n "$last_seen" ]; then
    gap=$((pulse_id - last_seen))
    if [ "$gap" -eq 1 ]; then
      if [ "$prev_hex" = "$prev_value" ]; then
        chain_verified=true
      else
        chain_verified=false
      fi
    fi
  fi

  witnessed_at=$(date -u +%s)
  msg="${pulse_id}|${value_hex}|${witnessed_at}"
  sig=$(sign_b64 "$msg")

  line=$(printf '{"pulse_id":%s,"value_hex":"%s","prev_hex":"%s","beacon_ts":"%s","beacon_unix":%s,"witnessed_at":%s,"gap":%s,"chain_verified":%s,"sig":"%s","pk_fp":"%s","witness":"%s"}' \
    "$pulse_id" "$value_hex" "$prev_hex" "$ts_iso" "$ts_unix" "$witnessed_at" "$gap" "$chain_verified" "$sig" "$pk_fp" "$WITNESS_NAME")

  rotate_if_needed
  printf '%s\n' "$line" >> "$LOG"
  write_latest "$line"
  printf '%s' "$pulse_id" > "$STATE"
  printf '%s' "$value_hex" > "$CHAIN"
  last_seen=$pulse_id
  prev_value=$value_hex

  sleep "$POLL_SEC"
done
