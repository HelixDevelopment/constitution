#!/bin/bash
# Purpose : T103 round-1 review remediation RED/GREEN test for
#           closure/reopen_rate.py's NO_DATA_IN_WINDOW state decision and its
#           window-bound comparison (SpecKit-004 "fast-dev-cycles" US3,
#           review finding R1-I1 + R1-M2).
#
# R1-I1 (IMPORTANT, §11.4.201(6) false-null): derive_report() declared
#   NO_DATA_IN_WINDOW whenever no item was closed in the window, even when
#   the window DID contain Reopened activity -- including the population-
#   mismatch case (an item reopened in-window with no closure anywhere in its
#   history), whose mismatched_items listing (the CT-006 "18 of 31" refusal)
#   was silently discarded behind the "no data in window" message. Its
#   converse used a NON-window-scoped is_retroactive_registration() check, so
#   a window with zero in-window events reported state OK (a zero-valued
#   statistic presented as a measurement) merely because some item had been
#   retroactively registered long before the window.
# R1-M2 (MINOR): window membership compared raw on_date strings, so an
#   export carrying a full timestamp on_date ("YYYY-MM-DDTHH:MM:SS") on the
#   window's last day sorted AFTER "YYYY-MM-DD" and fell out of the window.
#
# Cases (expected values hand-derived from CT-006/CT-008's own wording --
# §11.4.245 SPECIFIED oracle, never read back from reopen_rate.py):
#   A  mismatch-only window: MB-1 reopened in-window, never closed, nothing
#      closed in-window  => state OK, Bug.rate RATE_NOT_COMPUTABLE,
#      Bug.mismatched_items == ["MB-1"]   (was: NO_DATA_IN_WINDOW)
#   B  reopen-only window: MB-2 closed BEFORE the window, reopened in-window
#      => state OK (activity exists), closed 0, rate RATE_NOT_COMPUTABLE
#   C  retroactive-long-ago, nothing in window => NO_DATA_IN_WINDOW
#      (was: OK)
#   D  timestamp on_date on the window's last day => counted closed=1
#   E  negative control: a genuinely empty window stays NO_DATA_IN_WINDOW
#
# Usage : bash test_reopen_rate_state_red.sh   exit 0 = all cases hold.
set -u
ROOT=$(cd "$(dirname "$0")/../../../.." && pwd)
TOOL="$ROOT/constitution/scripts/fastcycle/closure/reopen_rate.py"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fail=0
chk() { if [ "$2" = 1 ]; then echo "ok $1"; else echo "NOT ok $1"; fail=1; fi; }

[ -f "$TOOL" ] || { echo "NOT ok reopen_rate.py missing at $TOOL"; exit 1; }

run() { # name json -> writes $TMP/name.out.json, echoes rc
  printf '%s' "$2" > "$TMP/$1.in.json"
  python3 "$TOOL" --as-of 2026-03-31 --window-days 30 \
    --tracker-export "$TMP/$1.in.json" --out "$TMP/$1.out.json" >/dev/null 2>"$TMP/$1.err"
  echo $?
}
# q(): eval() runs ONLY the fixed, test-authored expression literals below, never data.
q() { python3 -c "import json,sys;d=json.load(open(sys.argv[1]));print(eval(sys.argv[2]))" "$TMP/$1.out.json" "$2" 2>&1; }

# A
rc=$(run A '{"items":[{"atm_id":"MB-1","type":"Bug"}],"item_history":[
 {"atm_id":"MB-1","event_type":"Opened","on_date":"2026-01-01","created_at":"2026-01-01 10:00:00"},
 {"atm_id":"MB-1","event_type":"Reopened","on_date":"2026-03-15","created_at":"2026-03-15 10:00:00"}]}')
chk "A: exit 0 (rc=$rc)" "$([ "$rc" = 0 ] && echo 1)"
chk "A: state OK, not NO_DATA_IN_WINDOW (got $(q A 'd["state"]'))" "$([ "$(q A 'd["state"]')" = OK ] && echo 1)"
chk "A: Bug.rate refused (got $(q A 'd.get("by_type",{}).get("Bug",{}).get("rate")'))" \
  "$([ "$(q A 'd.get("by_type",{}).get("Bug",{}).get("rate")')" = RATE_NOT_COMPUTABLE ] && echo 1)"
chk "A: Bug.mismatched_items == [MB-1] (got $(q A 'd.get("by_type",{}).get("Bug",{}).get("mismatched_items")'))" \
  "$([ "$(q A 'd.get("by_type",{}).get("Bug",{}).get("mismatched_items")')" = "['MB-1']" ] && echo 1)"

# B
rc=$(run B '{"items":[{"atm_id":"MB-2","type":"Bug"}],"item_history":[
 {"atm_id":"MB-2","event_type":"Opened","on_date":"2026-01-01","created_at":"2026-01-01 10:00:00"},
 {"atm_id":"MB-2","event_type":"Fixed","on_date":"2026-01-20","created_at":"2026-01-20 10:00:00"},
 {"atm_id":"MB-2","event_type":"Reopened","on_date":"2026-03-15","created_at":"2026-03-15 10:00:00"}]}')
chk "B: state OK (in-window reopen is data) (got $(q B 'd["state"]'))" "$([ "$(q B 'd["state"]')" = OK ] && echo 1)"
chk "B: overall closed 0, rate refused (got $(q B '(d.get("overall",{}).get("closed"), d.get("overall",{}).get("rate"))'))" \
  "$([ "$(q B '(d.get("overall",{}).get("closed"), d.get("overall",{}).get("rate"))')" = "(0, 'RATE_NOT_COMPUTABLE')" ] && echo 1)"

# C
rc=$(run C '{"items":[{"atm_id":"MB-3","type":"Bug"}],"item_history":[
 {"atm_id":"MB-3","event_type":"Opened","on_date":"2025-06-01","created_at":"2025-06-01 10:00:00"},
 {"atm_id":"MB-3","event_type":"Fixed","on_date":"2025-06-01","created_at":"2025-06-01 10:00:20"}]}')
chk "C: long-ago retroactive registration, nothing in window => NO_DATA_IN_WINDOW (got $(q C 'd["state"]'))" \
  "$([ "$(q C 'd["state"]')" = NO_DATA_IN_WINDOW ] && echo 1)"

# D
rc=$(run D '{"items":[{"atm_id":"MB-4","type":"Bug"}],"item_history":[
 {"atm_id":"MB-4","event_type":"Opened","on_date":"2026-03-01","created_at":"2026-03-01 10:00:00"},
 {"atm_id":"MB-4","event_type":"Fixed","on_date":"2026-03-31T18:00:00Z","created_at":"2026-03-31 18:00:00"}]}')
chk "D: timestamp on_date on the window's last day counts as closed (got $(q D 'd.get("overall",{}).get("closed")'))" \
  "$([ "$(q D 'd.get("overall",{}).get("closed")')" = 1 ] && echo 1)"

# E (negative control)
rc=$(run E '{"items":[{"atm_id":"MB-5","type":"Bug"}],"item_history":[
 {"atm_id":"MB-5","event_type":"Opened","on_date":"2025-06-01","created_at":"2025-06-01 10:00:00"},
 {"atm_id":"MB-5","event_type":"Fixed","on_date":"2025-07-01","created_at":"2025-07-01 10:00:00"}]}')
chk "E: negative control -- nothing in window stays NO_DATA_IN_WINDOW (got $(q E 'd["state"]'))" \
  "$([ "$(q E 'd["state"]')" = NO_DATA_IN_WINDOW ] && echo 1)"

# F (R1-I10): the US3 checkpoint gate (tasks.md "Checkpoint (US3 / Phase D
# gate)") requires reopen_rate.py to pass --determinism-check; T100 never
# added the flag (argparse rejected it, exit 2). Two in-process-independent
# runs over the case-A export must yield the same body_hash.
python3 "$TOOL" --as-of 2026-03-31 --window-days 30 --tracker-export "$TMP/A.in.json" \
  --out "$TMP/F.out.json" --determinism-check >"$TMP/F.log" 2>&1
rc=$?
chk "F: --determinism-check exists and reports deterministic (rc=$rc: $(head -c 160 "$TMP/F.log"))" \
  "$([ "$rc" = 0 ] && grep -q '^reopen_rate: deterministic' "$TMP/F.log" && echo 1)"
# F negative control: the check must be able to FAIL -- an unreadable export
# yields no honest verdict (exit 4), never a vacuous "deterministic".
python3 "$TOOL" --as-of 2026-03-31 --window-days 30 --tracker-export "$TMP/does-not-exist.json" \
  --out "$TMP/F2.out.json" --determinism-check >"$TMP/F2.log" 2>&1
rc=$?
chk "F: negative control -- an unreadable export is NOT reported deterministic (rc=$rc)" \
  "$([ "$rc" != 0 ] && ! grep -q '^reopen_rate: deterministic' "$TMP/F2.log" && echo 1)"

[ "$fail" = 0 ] && echo "SUMMARY: all cases hold" || echo "SUMMARY: FAILURES present"
exit "$fail"
