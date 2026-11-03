#!/bin/sh
# us2_trap_scan_red.sh — RED/GREEN driver for CM-INSTRUMENT-TRAP-SCAN, shipped with the canon (§11.4.115, §11.4.224(A)).
# Runs the REAL gate in FILE mode over every bad_* fixture (must exit 1 and emit its class) and every good_*
# fixture (must exit 0 and print nothing). One "FAIL] <fixture>" line per misclassification; rc 0 only when all hold.
# Env: US2_TRAP_SCAN (gate under test, default the tracked gate), US2_TRAP_FIXTURES (fixture dir).
set -u
HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
GATE=${US2_TRAP_SCAN:-$HERE/../../cm_instrument_trap_scan.sh}
FX=${US2_TRAP_FIXTURES:-$HERE/traps}
[ -f "$GATE" ] || { echo "BLIND gate absent: $GATE"; exit 2; }
[ -d "$FX" ] || { echo "BLIND fixtures absent: $FX"; exit 2; }
bad=0; n=0
for pair in bad_01_pipeline_exit_status.sh:trap_pipeline_exit_status bad_02_relative_date_predicate.sh:trap_relative_date_predicate \
            bad_03_inverted_match.sh:trap_inverted_match bad_04_query_class_mismatch.sh:trap_query_class_mismatch \
            bad_05_greedy_display_transform.sh:trap_greedy_display_transform; do
    f=${pair%%:*}; c=${pair#*:}; n=$((n + 1))
    out=$(sh "$GATE" --fixtures "$FX" "$FX/$f" 2>&1); rc=$?
    if [ "$rc" -eq 1 ] && printf '%s\n' "$out" | grep -q "^FINDING $c "; then echo "  [ok]   $f flagged as $c"
    else echo "  [FAIL] $f rc=$rc expected exit 1 with class $c"; bad=$((bad + 1)); fi
done
for f in good_01_pipeline_exit_status.sh good_02_relative_date_predicate.sh good_03_inverted_match.sh \
         good_04_query_class_mismatch.sh good_05_greedy_display_transform.sh; do
    n=$((n + 1))
    out=$(sh "$GATE" --fixtures "$FX" "$FX/$f" 2>&1); rc=$?
    if [ "$rc" -eq 0 ] && [ -z "$out" ]; then echo "  [ok]   $f accepted"
    else echo "  [FAIL] $f rc=$rc out=[$out] — a false refusal is as serious as a false pass"; bad=$((bad + 1)); fi
done
echo "us2_trap_scan_red: $n fixtures, $bad bad"
[ "$bad" -eq 0 ]
