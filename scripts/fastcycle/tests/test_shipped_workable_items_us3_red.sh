#!/bin/bash
# Purpose : T103 round-1 review remediation test (SpecKit-004 US3, finding
#           R1-I8, §11.4.108 SOURCE-green / ARTIFACT-absent). The US3 seam
#           subcommands `intake-match` (T098) and `closure-check` (T095/T097)
#           landed in Go SOURCE and every Go test passed -- but every one of
#           those tests builds a FRESH binary (the BOB-188 lesson applied to
#           the tests), so none of them exercises the SHIPPED, tracked,
#           canonical binary `constitution/scripts/workable-items/bin/
#           workable-items` that production callers resolve FIRST
#           (constitution/scripts/reporting/report_item.sh's own resolution
#           order: env -> config -> $WI_SRC/bin/workable-items -> ...). The
#           shipped binary was last rebuilt at T044, BEFORE T095/T097/T098, so
#           `intake-match` answered "unknown subcommand" and report_item.sh
#           SILENTLY fell back to a direct `add` for every Bug report --
#           minting a new id for every recurrence, the exact defect T098
#           exists to close, with nothing in the log saying dedup was skipped.
#
# Asserts: (1) the shipped binary recognises `intake-match` and
#   `closure-check` (a usage refusal naming the required flags, never
#   "unknown subcommand"); (2) report_item.sh logs an explicit, greppable
#   notice when intake-match is unavailable/fails for a Bug report instead of
#   falling back silently. Control needle (§11.4.273): a genuinely unknown
#   subcommand DOES produce "unknown subcommand" through the same binary, so
#   the absence of that text in (1) is evidence, not blindness.
# Usage : bash test_shipped_workable_items_us3_red.sh   exit 0 = all hold.
set -u
ROOT=$(cd "$(dirname "$0")/../../../.." && pwd)
BIN="$ROOT/constitution/scripts/workable-items/bin/workable-items"
RI="$ROOT/constitution/scripts/reporting/report_item.sh"
fail=0
chk() { if [ "$2" = 1 ]; then echo "ok $1"; else echo "NOT ok $1"; fail=1; fi; }

[ -x "$BIN" ] || { echo "NOT ok shipped binary missing/not executable: $BIN"; exit 1; }

needle=$("$BIN" t103-no-such-subcommand-needle 2>&1)
chk "control needle: an unknown subcommand yields 'unknown subcommand' through the shipped binary" \
  "$(printf '%s' "$needle" | grep -q 'unknown subcommand' && echo 1)"

im=$("$BIN" intake-match 2>&1)
chk "shipped binary recognises intake-match (got: $(printf '%s' "$im" | head -1))" \
  "$(printf '%s' "$im" | grep -q 'unknown subcommand' || { printf '%s' "$im" | grep -q -- '--report' && echo 1; })"

cc=$("$BIN" closure-check 2>&1)
chk "shipped binary recognises closure-check (got: $(printf '%s' "$cc" | head -1))" \
  "$(printf '%s' "$cc" | grep -q 'unknown subcommand' || { printf '%s' "$cc" | grep -q -- '--attempt' && echo 1; })"

chk "report_item.sh logs a greppable notice when intake-match is unavailable/fails for a Bug (no silent fallback)" \
  "$(grep -q 'INTAKE-MATCH UNAVAILABLE' "$RI" && echo 1)"

# (3) R1-I9 -- end-to-end through report_item.sh + the SHIPPED binary on a
# throwaway DB: a Bug report recurring after its original was closed must
# REOPEN the original (no new id) AND the Reopened row's evidence_path must
# still resolve AFTER report_item.sh exits (it previously pointed into
# report_item.sh's own mktemp dir, deleted by its own `rm -rf "$TMP_EVID"`).
if command -v sqlite3 >/dev/null 2>&1; then
  E2E=$(mktemp -d); trap 'rm -rf "$E2E"' EXIT
  sqlite3 "$E2E/w.db" < "$ROOT/constitution/scripts/workable-items/schema.sql" >/dev/null
  printf 'schema_version: 1\ndb: %s\nid_prefix: E2E\nsync_command: ""\nevidence_dir: %s/ev\ntrackers: []\nworkable_items_bin: %s\n' \
    "$E2E/w.db" "$E2E" "$BIN" > "$E2E/cfg.yaml"
  bash "$RI" --kind bug --title "Subtitle overlay missing on second display after seek" \
    --report "After seeking in the player the subtitle overlay disappears from the second display entirely" \
    --scope "presenter subtitle overlay" --config "$E2E/cfg.yaml" --no-sync --no-tracker --autonomous >"$E2E/r1.log" 2>&1
  orig=$(sqlite3 "$E2E/w.db" "select atm_id from items limit 1")
  echo evidence > "$E2E/close_ev.txt"
  "$BIN" close --db "$E2E/w.db" --status fixed --evidence "$E2E/close_ev.txt" "$orig" >/dev/null 2>&1
  bash "$RI" --kind bug --title "Subtitle overlay disappears from second display after a seek" \
    --report "Seeking in the player makes the subtitle overlay disappear from the second display entirely again" \
    --scope "presenter subtitle overlay" --config "$E2E/cfg.yaml" --no-sync --no-tracker --autonomous >"$E2E/r2.log" 2>&1
  n=$(sqlite3 "$E2E/w.db" "select count(distinct atm_id) from items")
  st=$(sqlite3 "$E2E/w.db" "select status from items where atm_id='$orig'")
  ev=$(sqlite3 "$E2E/w.db" "select evidence_path from item_history where atm_id='$orig' and event_type='Reopened' order by id desc limit 1")
  chk "e2e: recurrence reopened the original $orig, no new id minted (items=$n, status=$st)" \
    "$([ "$n" = 1 ] && [ "$st" = Reopened ] && echo 1)"
  chk "e2e: the Reopened row's evidence_path still resolves after report_item.sh exits ($ev)" \
    "$([ -n "$ev" ] && [ -s "$ev" ] && echo 1)"
else
  echo "NOT ok e2e SKIPPED: sqlite3 unavailable (environment gap, not a finding)"; fail=1
fi

[ "$fail" = 0 ] && echo "SUMMARY: all hold" || echo "SUMMARY: FAILURES present"
exit "$fail"
