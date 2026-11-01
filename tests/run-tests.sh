#!/bin/bash
# RDK G2 Basic regression tests.
#
#   tests/run-tests.sh            compare the clone with the golden transcripts
#   tests/run-tests.sh --real     also compare with the ORIGINAL Integer BASIC
#                                 (needs ORIG_ROM=/path/to/integer_basic.bin, never committed)
#   tests/run-tests.sh --update   rewrite the golden transcripts (after a deliberate change)
#
# Needs the "bastest" example of rdk-apple1 (crates/apple1-core/examples/bastest.rs):
#   BASTEST=/path/to/bastest   (default: built from $APPLE1_REPO, default ../apple1-emu)
#   APPLE1_EMU=/path/to/apple1-emu   (used by src/build.py to assemble)
set -u
here=$(cd "$(dirname "$0")" && pwd); root=$(dirname "$here")
repo=${APPLE1_REPO:-$root/../apple1-emu}
if [ -z "${BASTEST:-}" ]; then
  (cd "$repo" && cargo build --release -q -p apple1-core --example bastest) || exit 2
  BASTEST=$(ls "${CARGO_TARGET_DIR:-$repo/target}/release/examples/bastest")
fi
bin=$root/bin/rdk-g2basic.bin
mode=${1:-}
run() { BASIC_MAXIDLE=40000000 BASIC_ROM=$1 ${3:-} timeout 100 "$BASTEST" "$2" 2>&1 | grep -v '^pc=' | tr -d '\033' \
        | sed 's/^E000: 4CRDK G2 BASIC 1.0$/E000: 4C/;/^DEDICATED TO UNCLE/d'; }
fail=0; n=0
for s in "$here"/sessions/*.txt; do
  b=$(basename "$s" .txt); n=$((n+1)); exp=$here/expected/$b.out
  pre=""
  [ "$b" = gen2hook ] && export BASIC_PRE=0800:$here/gen2-fake-card.bin || unset BASIC_PRE
  out=$(run "$bin" "$s")
  if [ "$mode" = --update ]; then printf '%s\n' "$out" > "$exp"; continue; fi
  if [ "$out" = "$(cat "$exp")" ]; then echo "ok    $b"; else echo "FAIL  $b"; fail=$((fail+1)); fi
  if [ "$mode" = --real ] && [ "$b" != gen2hook ]; then
    unset BASIC_PRE
    real=$(run "${ORIG_ROM:?set ORIG_ROM}" "$s")
    [ "$real" = "$out" ] && echo "      same as the original BASIC" || { echo "      DIFFERS from the original BASIC"; fail=$((fail+1)); }
  fi
done
echo "$n sessions, $fail failure(s)"; [ $fail -eq 0 ]
