#!/bin/bash
# Purpose : T103 round-1 review remediation test for closure/escape_classify.py
#           (SpecKit-004 US3, review finding R1-M3). Malformed analyst input --
#           a non-mapping `entries` element, an unhashable item_id, or a
#           non-string evidence path -- previously crashed escape_classify.py
#           with an uncaught Python traceback whose exit status (1) is the SAME
#           code as EXIT_FINDING, so a tool crash was indistinguishable from a
#           genuine, named refusal (§11.4.1 / §11.4.201). After the fix each
#           case must be a clean, NAMED refusal: exit 1, no "Traceback" on
#           stderr, and the offending entry named.
# Window/config reuse the real project config and ATM-953's real 2026-07-28
# reopen row exactly as test_escape_classify_red.sh's golden fixture does.
# Usage : bash test_escape_classify_malformed_red.sh   exit 0 = all cases hold.
set -u
ROOT=$(cd "$(dirname "$0")/../../../.." && pwd)
TOOL="$ROOT/constitution/scripts/fastcycle/closure/escape_classify.py"
CONFIG="$ROOT/config/fastcycle/fastcycle.yaml"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail=0
chk() { if [ "$2" = 1 ]; then echo "ok $1"; else echo "NOT ok $1"; fail=1; fi; }

case_run() { # name yaml-body needle
  printf '%s\n' "$2" > "$TMP/$1.yaml"
  (cd "$ROOT" && python3 "$TOOL" --config "$CONFIG" --as-of 2026-07-28 --window-days 0 \
     --classifications "$TMP/$1.yaml" --out "$TMP/$1.json") >"$TMP/$1.out" 2>"$TMP/$1.err"
  local rc=$?
  chk "$1: exit 1 (named refusal) (rc=$rc)" "$([ "$rc" = 1 ] && echo 1)"
  chk "$1: no uncaught Python traceback on stderr" "$(grep -q Traceback "$TMP/$1.err" || echo 1)"
  chk "$1: refusal names the malformed input ('$3')" "$(grep -qF -- "$3" "$TMP/$1.err" && echo 1)"
}

case_run non_mapping_entry 'entries:
  - "just a string, not a mapping"' "entries[0] is not a mapping"
case_run unhashable_item_id 'entries:
  - item_id: [ATM-953]
    primary: E1' "entries[0] item_id"
case_run non_string_evidence_path 'entries:
  - item_id: ATM-953
    reopen_events: [869]
    primary: E1
    detection_channel: manual-testing-detected
    evidence:
      - path: 12345
        content_address: "sha256:0000000000000000000000000000000000000000000000000000000000000000"' "evidence entry"

[ "$fail" = 0 ] && echo "SUMMARY: all cases hold" || echo "SUMMARY: FAILURES present"
exit "$fail"
