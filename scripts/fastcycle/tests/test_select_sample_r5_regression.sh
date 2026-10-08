#!/usr/bin/env bash
# Purpose : T048 restart round-1 review R5 (docs/qa/t048_restart_round1_20261008/
#           R5_cycle_report_sampling.md) regression suite for
#           constitution/scripts/fastcycle/cycle/select_sample.py.
#           Every check drives the REAL select_sample.py through its real CLI
#           (python3 select_sample.py ...) against a synthetic tracker DB built
#           by tests/fixtures/cycle_report/build_asof_scenario.py, plus one
#           live-DB check (a read-only .backup snapshot; the live DB is never
#           written).
#
# Findings guarded (R5 numbering):
#   B1  the --as-of cutoff leaked future events into ranking
#       (closure_recency_key), the bulk-cluster key and the retroactive rule.
#       Guard: a "full" DB (with rows dated after as-of) and a "cut" DB (those
#       rows deleted -- the DB as it looked ON the as-of date) MUST give the
#       identical body_hash; plus the reviewer's own experiment on a snapshot
#       of the live DB (delete every row dated after 2026-08-23, compare).
#   B2  strata[*].below_required counted rows excluded_from_duration as
#       usable. Guard: exact strata (n_available/n_selected/n_usable/
#       below_required) for the synthetic scenario, hand-derived below.
#   M2  (reviewer mutation) `picked = ids[:min_per_type]` (oldest-N) survived
#       every suite. Guard: the exact sampled Bug set.
#   M10 --determinism-check never wrote --out.
#
# Hand-derived expectation (scenario documented in build_asof_scenario.py;
# as_of 2026-08-23, window 60d => [2026-06-24, 2026-08-23], min_per_type 2,
# bulk_threshold 3; only rows with on_date <= as_of count):
#   Bug candidates by latest as-of closure created_at: ATM-300 06-30 <
#     ATM-953 07-01 < ATM-1002 07-10 < ATM-800 07-25 < ATM-277 08-20
#     => most-recent 2 = {ATM-800, ATM-277}; both usable => n_usable 2,
#     below_required false. (oldest-2 would be {ATM-300, ATM-953}; atm_id
#     string order would give {ATM-800, ATM-953}; the pre-fix future leak
#     gave {ATM-300, ATM-277}.)
#   Task candidates: ATM-501..503 (07-05, distinct dirs) and ATM-601..603
#     (07-20, one shared dir => a genuine bulk cluster of 3 >= 3) => most
#     recent 2 = {ATM-602, ATM-603}, both bulk => n_usable 0,
#     below_required true. (The pre-fix leak clustered ATM-501..503 by their
#     FUTURE 09-28 closure into a fake bulk cluster.)
#   Feature: ATM-700 only, Opened->Implemented 20 s apart => retroactive =>
#     n_selected 1, n_usable 0, below_required true. (The pre-fix leak read
#     the FUTURE 09-10 closure and missed the retroactive registration.)
#   Reopened in window: ATM-800 only (07-15).
#
# Usage   : bash test_select_sample_r5_regression.sh
#           Exit 0 = every check (and every paired mutation, unless
#           FC_R5_MUTANT=1 is set because this IS a mutation run) held.
#           SELECT_SAMPLE_UNDER_TEST=<path> runs the checks against another
#           copy of the tool (used by the paired-mutation harness below).
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
REAL_TOOL="$FC/cycle/select_sample.py"
TOOL="${SELECT_SAMPLE_UNDER_TEST:-$REAL_TOOL}"
BUILDER="$FC/tests/fixtures/cycle_report/build_asof_scenario.py"
DB="$ROOT/docs/workable_items.db"

fail=0
ok()  { echo "ok $*"; }
bad() { echo "NOT ok $*"; fail=1; }

TMP="$(mktemp -d)"
MUTANTS=()
# shellcheck disable=SC2329  # invoked via the EXIT trap below
cleanup() { rm -rf "$TMP"; for m in "${MUTANTS[@]}"; do rm -f "$m"; done; }
trap cleanup EXIT

if [ ! -f "$TOOL" ] || [ ! -f "$BUILDER" ]; then
  bad "tool ($TOOL) or fixture builder ($BUILDER) missing -- nothing below can run"
  exit 1
fi

NEEDLE=(--needle-present-id ATM-953 --needle-fixed-event Fixed --needle-fixed-on-date 2026-07-01)
COMMON=(--as-of 2026-08-23 --window-days 60 --min-per-type 2 --bulk-threshold 3)

for mode in full cut; do
  if ! python3 "$BUILDER" "$TMP/$mode" "$mode" >"$TMP/build_$mode.err" 2>&1; then
    bad "fixture build ($mode) failed: $(cat "$TMP/build_$mode.err")"
    exit 1
  fi
  python3 "$TOOL" "${COMMON[@]}" "${NEEDLE[@]}" --db-path "$TMP/$mode/db.sqlite" \
    --out "$TMP/ss_$mode.json" >"$TMP/ss_$mode.err" 2>&1
  rc=$?
  if [ "$rc" != 0 ] || [ ! -f "$TMP/ss_$mode.json" ]; then
    bad "select_sample ($mode scenario) rc=$rc -- $(tail -3 "$TMP/ss_$mode.err")"
  fi
done

echo "=== S1 (R5 B1): as-of freeze -- full DB and cut DB give the identical body ==="
if [ -f "$TMP/ss_full.json" ] && [ -f "$TMP/ss_cut.json" ]; then
  verdict="$(python3 - "$TMP/ss_full.json" "$TMP/ss_cut.json" <<'PY'
import json, sys
a, b = (json.load(open(p)) for p in sys.argv[1:3])
if a["body_hash"] == b["body_hash"]:
    print("SAME")
else:
    ia = sorted(i["item_id"] for i in a.get("items", []))
    ib = sorted(i["item_id"] for i in b.get("items", []))
    print("DIFF full=%s/%s cut=%s/%s" % (a["body_hash"][:8], ia, b["body_hash"][:8], ib))
PY
)"
  if [ "$verdict" = "SAME" ]; then
    ok "S1 full-vs-cut body_hash identical: rows dated after --as-of change nothing"
  else
    bad "S1 future rows leak into the as-of selection: $verdict"
  fi
else
  bad "S1 prerequisite outputs missing"
fi

echo "=== S2 (R5 B1 + B2 + M2): exact hand-derived selection and strata ==="
if [ -f "$TMP/ss_full.json" ]; then
  verdict="$(python3 - "$TMP/ss_full.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
expected_strata = {
    "Bug": {"n_available": 5, "n_selected": 2, "n_usable": 2, "below_required": False},
    "Task": {"n_available": 6, "n_selected": 2, "n_usable": 0, "below_required": True},
    "Feature": {"n_available": 1, "n_selected": 1, "n_usable": 0, "below_required": True},
}
expected_items = {
    "ATM-277": ("Bug", "sampled-bug", False),
    "ATM-602": ("Task", "sampled-task", True),
    "ATM-603": ("Task", "sampled-task", True),
    "ATM-700": ("Feature", "sampled-feature", True),
    "ATM-800": ("Bug", "reopened-in-window", False),
}
problems = []
for t, exp in expected_strata.items():
    got = {k: d.get("strata", {}).get(t, {}).get(k) for k in exp}
    if got != exp:
        problems.append("strata[%s]=%s expected %s" % (t, got, exp))
got_items = {i["item_id"]: (i["type"], i["selection_reason"], i["excluded_from_duration"])
             for i in d.get("items", [])}
if got_items != expected_items:
    problems.append("items=%s expected %s" % (got_items, expected_items))
reasons = {i["item_id"]: i["exclusion_reason"] or "" for i in d.get("items", [])}
if "realbulk" not in reasons.get("ATM-602", "") or "retroactive" not in reasons.get("ATM-700", ""):
    problems.append("exclusion reasons wrong: %s" % reasons)
if d.get("reopened_in_window") != ["ATM-800"]:
    problems.append("reopened_in_window=%s" % d.get("reopened_in_window"))
print("PASS" if not problems else "; ".join(problems))
PY
)"
  if [ "$verdict" = "PASS" ]; then
    ok "S2 selection = most-recent-2 per type by as-of closure recency; below_required counts USABLE rows (Task 0/2 -> true, Bug 2/2 -> false)"
  else
    bad "S2 $verdict"
  fi
fi

echo "=== S3 (R5 B1, reviewer experiment): live DB snapshot vs the same snapshot with every row after 2026-08-23 deleted ==="
if command -v sqlite3 >/dev/null 2>&1 && [ -f "$DB" ]; then
  sqlite3 -readonly "$DB" ".backup '$TMP/live_full.db'" 2>"$TMP/backup.err"
  cp "$TMP/live_full.db" "$TMP/live_cut.db" 2>/dev/null
  deleted="$(sqlite3 "$TMP/live_cut.db" "DELETE FROM item_history WHERE on_date > '2026-08-23'; SELECT changes();" 2>&1)"
  for v in full cut; do
    python3 "$TOOL" --as-of 2026-08-23 --window-days 90 --db-path "$TMP/live_$v.db" \
      --out "$TMP/live_ss_$v.json" >"$TMP/live_ss_$v.err" 2>&1 || true
  done
  if [ -f "$TMP/live_ss_full.json" ] && [ -f "$TMP/live_ss_cut.json" ]; then
    h_full="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['body_hash'])" "$TMP/live_ss_full.json")"
    h_cut="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['body_hash'])" "$TMP/live_ss_cut.json")"
    case "$deleted" in
      ''|*[!0-9]*) bad "S3 could not count deleted rows: '$deleted'" ;;
      0) bad "S3 control: the live snapshot has NO rows after 2026-08-23, so this experiment proves nothing (needle failed)" ;;
      *) if [ "$h_full" = "$h_cut" ]; then
           ok "S3 live experiment: deleted $deleted future rows, selection body_hash unchanged (${h_full:0:8})"
         else
           bad "S3 live experiment: deleting $deleted future rows changed the selection (${h_full:0:8} vs ${h_cut:0:8})"
         fi ;;
    esac
  else
    bad "S3 live runs failed -- $(tail -2 "$TMP/live_ss_full.err" "$TMP/live_ss_cut.err" 2>/dev/null)"
  fi
else
  bad "S3 sqlite3 or live tracker DB unavailable -- cannot run the reviewer experiment"
fi

echo "=== S4 (R5 M10): --determinism-check writes --out (and the result equals a plain run) ==="
python3 "$TOOL" "${COMMON[@]}" "${NEEDLE[@]}" --db-path "$TMP/full/db.sqlite" \
  --determinism-check --out "$TMP/dc.json" >"$TMP/dc.out" 2>&1
dc_rc=$?
if [ "$dc_rc" = 0 ] && [ -f "$TMP/dc.json" ] && [ -f "$TMP/ss_full.json" ] && \
   [ "$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['body_hash'])" "$TMP/dc.json")" = \
     "$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['body_hash'])" "$TMP/ss_full.json")" ]; then
  ok "S4 --determinism-check rc=0 and wrote --out with the same body_hash as a plain run"
else
  bad "S4 --determinism-check rc=$dc_rc, --out present=$([ -f "$TMP/dc.json" ] && echo yes || echo no) -- $(tail -2 "$TMP/dc.out")"
fi

# ---------------------------------------------------------------------------
# Paired mutations (§1.1). Each mutant is a copy of the REAL tool placed next
# to it (its lib/fc_common.py import is __file__-relative), with ONE textual
# change; this whole suite is re-run against it and MUST exit non-zero.
# ---------------------------------------------------------------------------
if [ "${FC_R5_MUTANT:-0}" != 1 ]; then
  echo "=== paired mutations ==="
  run_mutant() {  # name, python-literal old, python-literal new
    local name="$1" mut="$FC/cycle/.r5_ss_mut_${1}.$$.py"
    MUTANTS+=("$mut")
    if ! python3 - "$REAL_TOOL" "$mut" "$2" "$3" <<'PY'
import sys
src, dst, old, new = sys.argv[1:5]
text = open(src, encoding="utf-8").read()
if text.count(old) != 1:
    raise SystemExit("mutation anchor found %d times (need exactly 1): %r" % (text.count(old), old))
open(dst, "w", encoding="utf-8").write(text.replace(old, new))
PY
    then
      bad "mutation $name could not be applied (anchor drifted)"
      return
    fi
    if SELECT_SAMPLE_UNDER_TEST="$mut" FC_R5_MUTANT=1 bash "$0" >"$TMP/mut_$name.out" 2>&1; then
      bad "mutation $name SURVIVED (suite still exits 0)"
    else
      ok "mutation $name killed ($(grep -c '^NOT ok' "$TMP/mut_$name.out") failing check(s))"
    fi
  }
  # M2 -- reviewer's verbatim mutation: oldest-N instead of most-recent-N.
  run_mutant M2_oldest_n 'picked = ids[-min_per_type:]' 'picked = ids[:min_per_type]'
  # Own: re-open the as-of leak by dropping the history cutoff.
  run_mutant asof_cutoff_dropped 'return history_upto(rows, as_of)' 'return rows'
  # Own: B2 regression -- below_required back on n_available.
  run_mutant b2_available 'n_usable < min_per_type' 'n_available < min_per_type'
  # Own: lexicographic atm_id ranking (the N2 bug class).
  run_mutant atm_id_ranking 'key=lambda i: closure_recency_key(history_by_id, i))' 'key=lambda i: i)'
fi

exit $fail
