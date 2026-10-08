#!/usr/bin/env bash
# Purpose : T048 restart regression suite for
#           constitution/scripts/fastcycle/cycle/select_sample.py -- round 1
#           (docs/qa/t048_restart_round1_20261008/R5_cycle_report_sampling.md)
#           and round 2 (docs/qa/t048_restart_round2_20261008/V2_sampling.md).
#           Every check drives the REAL select_sample.py through its real CLI
#           (python3 select_sample.py ...) against a synthetic tracker DB built
#           by tests/fixtures/cycle_report/build_asof_scenario.py, plus live-DB
#           checks on read-only .backup snapshots (the live DB is never written).
#
# Findings guarded:
#   R5 B1  the --as-of cutoff leaked future events (S1, S3; boundary rows S2).
#   R5 B2 / V2-1  "selected" was not "usable": below_required counted
#          excluded rows, and (V2-1) bulk/retroactive rows consumed the
#          per-type quota while usable rows of the same type existed further
#          back. Rule now (OPERATOR-DECISION-RECORDED in select_sample.py,
#          EXCLUDED_ROWS_COUNT_TOWARD_N = False): exclude first, then take the
#          most-recent N USABLE rows; every excluded row walked past is LISTED
#          (DEC-03 "excluded from duration statistics but listed"). S2 (exact
#          fixture), S5 (live: n_usable == min(N, usable available)).
#   R5 M2  oldest-N survived; S2 pins the exact sampled set.
#   R5 M10 --determinism-check never wrote --out (S4).
#   V2-4   no as-of boundary rows: the fixture now has a closure ON the as-of
#          day (ATM-310), a Reopened row ON window.from (ATM-300), a negative
#          Opened->closure gap (ATM-504) and a closure row whose created_at and
#          row id disagree on recency (ATM-1003) -- all pinned by S2.
#   V2-8   the default CT-009 needle is a row dated 2026-07-28; for an earlier
#          --as-of it is a FUTURE row. S6: with no needle overrides the needle
#          is derived from the DB at the as-of (fixture and live snapshot).
#   V2-2 (class) the retroactive rule is ONE function shared with
#          cycle_report.py; S7 cross-checks the one remaining out-of-scope copy
#          (closure/reopen_rate.py) on a boundary corpus so a drift is caught.
#   V2-6   paired mutants are built in $TMP (a copy of lib/ closure/ cycle/),
#          never inside the source tree.
#
# Hand-derived expectation (fixture docstring lists every row; as_of
# 2026-08-23, window 60d => [2026-06-24, 2026-08-23], min_per_type 2,
# bulk_threshold 3; only rows with on_date <= as_of count):
#   Bug candidates (latest as-of closure created_at): ATM-1003 06-25 (row id
#     HIGHEST -- written last), ATM-300 06-30, ATM-953 07-01, ATM-1002 07-10,
#     ATM-800 07-25, ATM-277 08-20, ATM-310 08-23 (ON the as-of day).
#     None excluded => most-recent 2 usable = {ATM-310, ATM-277}; nothing
#     listed. n_available 7, n_usable_available 7, n_selected 2, n_usable 2.
#     (SS_N1 drops the as-of day => ATM-310 loses its closure; SS_N4 ranks by
#     row id => ATM-1003 becomes "most recent".)
#   Task candidates walked most-recent-first: ATM-603/602/601 (07-20, one
#     shared dir => bulk cluster of 3) are LISTED, then ATM-504 (07-06 09:59;
#     Opened row 60 s LATER -> negative gap, NOT retroactive) and ATM-503
#     (07-05 12:00) are TAKEN. n_available 7, n_usable_available 4,
#     n_selected 2, n_usable 2, n_listed_excluded 3, below_required false.
#     (Round-1 rule: picked {602, 603}, both bulk, n_usable 0 -- the V2-1
#     starvation; SS_N3 makes ATM-504 retroactive.)
#   Feature: ATM-700 only, retroactive (20 s) => listed, n_selected 0,
#     n_usable 0, below_required true.
#   Reopened in window: ATM-300 (06-24 = window.from) and ATM-800 (07-15).
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
trap 'rm -rf "$TMP"' EXIT

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

jhash() { python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['body_hash'])" "$1" 2>/dev/null; }

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

echo "=== S2 (R5 B1/B2/M2 + V2-1 + V2-4): exact hand-derived selection, strata and listing ==="
if [ -f "$TMP/ss_full.json" ]; then
  verdict="$(python3 - "$TMP/ss_full.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
expected_strata = {
    "Bug": {"n_available": 7, "n_usable_available": 7, "n_selected": 2, "n_usable": 2,
            "n_listed_excluded": 0, "below_required": False},
    "Task": {"n_available": 7, "n_usable_available": 4, "n_selected": 2, "n_usable": 2,
             "n_listed_excluded": 3, "below_required": False},
    "Feature": {"n_available": 1, "n_usable_available": 0, "n_selected": 0, "n_usable": 0,
                "n_listed_excluded": 1, "below_required": True},
}
expected_items = {
    "ATM-277": ("Bug", "sampled-bug", False),
    "ATM-310": ("Bug", "sampled-bug", False),
    "ATM-300": ("Bug", "reopened-in-window", False),
    "ATM-800": ("Bug", "reopened-in-window", False),
    "ATM-503": ("Task", "sampled-task", False),
    "ATM-504": ("Task", "sampled-task", False),
    "ATM-601": ("Task", "listed-excluded-task", True),
    "ATM-602": ("Task", "listed-excluded-task", True),
    "ATM-603": ("Task", "listed-excluded-task", True),
    "ATM-700": ("Feature", "listed-excluded-feature", True),
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
if d.get("reopened_in_window") != ["ATM-300", "ATM-800"]:
    problems.append("reopened_in_window=%s" % d.get("reopened_in_window"))
if d.get("selection_rule", {}).get("excluded_rows_count_toward_n") is not False:
    problems.append("selection_rule=%s (the recorded operator decision is not stated in the output)"
                    % d.get("selection_rule"))
print("PASS" if not problems else "; ".join(problems))
PY
)"
  if [ "$verdict" = "PASS" ]; then
    ok "S2 exclude-first then most-recent-2 USABLE per type; walked-past excluded rows listed; boundary rows (as-of day, window.from, negative gap, row-id/created_at disagreement) counted correctly"
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
    h_full="$(jhash "$TMP/live_ss_full.json")"
    h_cut="$(jhash "$TMP/live_ss_cut.json")"
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
   [ "$(jhash "$TMP/dc.json")" = "$(jhash "$TMP/ss_full.json")" ]; then
  ok "S4 --determinism-check rc=0 and wrote --out with the same body_hash as a plain run"
else
  bad "S4 --determinism-check rc=$dc_rc, --out present=$([ -f "$TMP/dc.json" ] && echo yes || echo no) -- $(tail -2 "$TMP/dc.out")"
fi

echo "=== S5 (V2-1, live): the per-type quota is filled with USABLE rows whenever they exist ==="
# Ground truth from the SAME tool with a quota no stratum can reach
# (--min-per-type 1000 => every candidate taken, n_usable = usable available);
# then the real N=5 run must take min(5, usable available) usable rows.
if [ -f "$TMP/live_full.db" ]; then
  python3 "$TOOL" --as-of 2026-08-23 --window-days 90 --min-per-type 1000 --db-path "$TMP/live_full.db" \
    --out "$TMP/live_all.json" >"$TMP/live_all.err" 2>&1
  python3 "$TOOL" --as-of 2026-08-23 --window-days 90 --min-per-type 5 --db-path "$TMP/live_full.db" \
    --out "$TMP/live_n5.json" >"$TMP/live_n5.err" 2>&1
  verdict="$(python3 - "$TMP/live_all.json" "$TMP/live_n5.json" <<'PY'
import json, sys
try:
    a, b = (json.load(open(p)) for p in sys.argv[1:3])
except Exception as e:
    print("missing output: %s" % e)
    raise SystemExit
p, seen = [], []
for t in ("Bug", "Feature", "Task"):
    avail = a["strata"][t]["n_usable"]
    s = b["strata"][t]
    if s["n_usable_available"] != avail:
        p.append("%s n_usable_available=%s but the all-rows run found %s" % (t, s["n_usable_available"], avail))
    if s["n_usable"] != min(5, avail):
        p.append("%s n_usable=%s expected min(5, %s)" % (t, s["n_usable"], avail))
    if s["below_required"] != (min(5, avail) < 5):
        p.append("%s below_required=%s with %s usable available" % (t, s["below_required"], avail))
    seen.append("%s %s/%s" % (t, s["n_usable"], avail))
# control needle: the experiment must contain a stratum where the round-1 rule
# starved the quota (an excluded row among the most-recent rows) -- else it
# proves nothing about V2-1.
if not any(b["strata"][t]["n_listed_excluded"] > 0 and b["strata"][t]["n_usable"] == 5
           for t in ("Bug", "Feature", "Task")):
    p.append("control: no stratum both listed excluded rows and still filled 5 usable -- experiment inert")
print("PASS " + ", ".join(seen) if not p else "; ".join(p))
PY
)"
  case "$verdict" in
    PASS*) ok "S5 live as-of 2026-08-23: usable taken/available ${verdict#PASS }" ;;
    *) bad "S5 $verdict" ;;
  esac
else
  bad "S5 live snapshot unavailable"
fi

echo "=== S6 (V2-8): with no needle overrides, an as-of before the default needle's date derives the needle at the as-of ==="
python3 "$TOOL" --as-of 2026-07-20 --window-days 60 --min-per-type 2 --bulk-threshold 3 \
  --db-path "$TMP/full/db.sqlite" --out "$TMP/nd.json" >"$TMP/nd.err" 2>&1
nd_rc=$?
python3 "$TOOL" --as-of 2026-08-23 --window-days 60 --min-per-type 2 --bulk-threshold 3 \
  --db-path "$TMP/full/db.sqlite" --out "$TMP/nd_default.json" >"$TMP/nd_default.err" 2>&1
nd_default_rc=$?
nd_live_rc=skip
if [ -f "$TMP/live_full.db" ]; then
  cp "$TMP/live_full.db" "$TMP/live_0710.db"
  sqlite3 "$TMP/live_0710.db" "DELETE FROM item_history WHERE on_date > '2026-07-10';"
  python3 "$TOOL" --as-of 2026-07-10 --window-days 60 --db-path "$TMP/live_0710.db" \
    --out "$TMP/nd_live.json" >"$TMP/nd_live.err" 2>&1
  nd_live_rc=$?
fi
nd_src="$(python3 -c "
import json, sys
n = json.load(open(sys.argv[1]))['run_meta']['needle']
print('%s|%s|%s' % (n['source'], n['present_id'], n['present_on_date']))
" "$TMP/nd.json" 2>&1)"
IFS='|' read -r nd_source nd_id nd_date <<<"$nd_src"
if [ "$nd_rc" = 0 ] && [ "$nd_source" = "derived-at-as-of" ] && [ -n "$nd_id" ] && [[ "$nd_date" < "2026-07-21" ]] \
   && [ "$nd_default_rc" = 3 ] && grep -q 'NOT FOUND' "$TMP/nd_default.err" && [ "$nd_live_rc" = 0 ]; then
  ok "S6 as-of 07-20 derives the needle ($nd_id on $nd_date); as-of 08-23 keeps the default and still fails closed (exit 3) when that row is absent; live snapshot cut at 07-10 replays with defaults"
else
  bad "S6 rc=$nd_rc needle=$nd_src default_rc=$nd_default_rc live_rc=$nd_live_rc -- $(tail -2 "$TMP/nd.err") / $(tail -1 "$TMP/nd_live.err" 2>/dev/null)"
fi

echo "=== S7 (V2-2 class): the retroactive rule's one out-of-scope copy (closure/reopen_rate.py) agrees on a boundary corpus ==="
verdict="$(python3 - "$TOOL" "$FC/closure/reopen_rate.py" <<'PY'
import importlib.util, sys
def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m
ss, rr = load("ss_ut", sys.argv[1]), load("rr_ut", sys.argv[2])
def h(o, c):
    rows = []
    if o is not None:
        rows.append({"event_type": "Opened", "created_at": o})
    if c is not None:
        rows.append({"event_type": "Fixed", "created_at": c})
    return rows
corpus = [h("2026-08-01 10:00:00", "2026-08-01 10:00:00"), h("2026-08-01 10:00:00", "2026-08-01 10:00:59"),
          h("2026-08-01 10:00:00", "2026-08-01 10:01:00"), h("2026-08-01 10:00:00", "2026-08-01 09:59:00"),
          h("2026-08-01T10:00:00+05:00", "2026-08-01T05:00:30Z"), h(None, "2026-08-01 10:00:00"),
          h("2026-08-01 10:00:00", None), h("garbage", "2026-08-01 10:00:00")]
want = [True, True, False, False, True, False, False, False]
got_ss = [ss.detect_retroactive_registration(c) for c in corpus]
got_rr = [rr.is_retroactive_registration(c) for c in corpus]
print("PASS" if got_ss == want and got_rr == want else "select_sample=%s reopen_rate=%s want=%s" % (got_ss, got_rr, want))
PY
)"
if [ "$verdict" = "PASS" ]; then
  ok "S7 select_sample's rule and reopen_rate.py's copy agree on 8 boundary cases (gap 0, 59, 60, -60, offset-aware, missing rows, unparseable)"
else
  bad "S7 $verdict"
fi

echo "=== S8 (R5 B2): below_required is computed on USABLE rows -- a stratum with enough rows but none usable is below ==="
# --min-per-type 1: Feature has 1 row available (>= 1) but 0 usable (ATM-700
# is a retroactive registration) => below_required true; an available-count
# rule would say false. Bug/Task each take their single most recent usable row.
python3 "$TOOL" --as-of 2026-08-23 --window-days 60 --min-per-type 1 --bulk-threshold 3 "${NEEDLE[@]}" \
  --db-path "$TMP/full/db.sqlite" --out "$TMP/ss_min1.json" >"$TMP/ss_min1.err" 2>&1
verdict="$(python3 -c "
import json, sys
st = json.load(open(sys.argv[1]))['strata']
print(' '.join('%s:%s/%s/%s' % (t, st[t]['n_available'], st[t]['n_usable'], st[t]['below_required'])
               for t in ('Bug', 'Feature', 'Task')))
" "$TMP/ss_min1.json" 2>&1)"
if [ "$verdict" = "Bug:7/1/False Feature:1/0/True Task:7/1/False" ]; then
  ok "S8 min 1: Feature 1 available / 0 usable -> below_required true (Bug, Task 1 usable each -> false)"
else
  bad "S8 got '$verdict', want 'Bug:7/1/False Feature:1/0/True Task:7/1/False'"
fi

# ---------------------------------------------------------------------------
# Paired mutations (§1.1). Each mutant is built in a COPY of lib/ closure/
# cycle/ under $TMP (V2-6: never inside the source tree -- the tool's sibling
# imports are __file__-relative, so the copy is self-contained), with ONE
# textual change; this whole suite is re-run against it and MUST exit non-zero.
# ---------------------------------------------------------------------------
if [ "${FC_R5_MUTANT:-0}" != 1 ]; then
  echo "=== paired mutations ==="
  # The mutant tree mirrors the repository layout under $TMP so the tools'
  # __file__-relative defaults (repo root = 4 levels up -> docs/
  # workable_items.db and git log) resolve to THIS repository through two
  # symlinks; a bare copy would read no DB at all, and every mutant would be
  # "killed" by an unreadable DB instead of by the mutation (a bluff kill).
  mk_mutant_tree() {  # $1 root dir; prints the fastcycle dir inside it
    local fcd="$1/constitution/scripts/fastcycle"
    mkdir -p "$fcd"
    cp -r "$FC/lib" "$FC/closure" "$FC/cycle" "$fcd/"
    ln -s "$ROOT/docs" "$1/docs"
    ln -s "$ROOT/.git" "$1/.git"
    echo "$fcd"
  }
  run_mutant() {  # name, file relative to $FC, python-literal old, python-literal new
    local name="$1" rel="$2" root="$TMP/mut_$1" tree
    tree="$(mk_mutant_tree "$root")"
    if ! python3 - "$tree/$rel" "$3" "$4" <<'PY'
import sys
path, old, new = sys.argv[1:4]
text = open(path, encoding="utf-8").read()
if text.count(old) != 1:
    raise SystemExit("mutation anchor found %d times (need exactly 1): %r" % (text.count(old), old))
open(path, "w", encoding="utf-8").write(text.replace(old, new))
PY
    then
      bad "mutation $name could not be applied (anchor drifted)"
      return
    fi
    if SELECT_SAMPLE_UNDER_TEST="$tree/cycle/select_sample.py" FC_R5_MUTANT=1 bash "$0" >"$TMP/mut_$name.out" 2>&1; then
      bad "mutation $name SURVIVED (suite still exits 0)"
    else
      ok "mutation $name killed ($(grep -c '^NOT ok' "$TMP/mut_$name.out") failing check(s))"
    fi
    rm -rf "$root"
  }
  SS=cycle/select_sample.py
  # R5 M2 (reviewer, re-anchored on the exclude-first walk): oldest-N instead of most-recent-N.
  run_mutant M2_oldest_n "$SS" 'for atm_id in reversed(ids):' 'for atm_id in ids:'
  # V2 new mutants (reviewer, verbatim effect).
  run_mutant SS_N1_asof_day_dropped "$SS" 'r["on_date"][:10] <= as_of]' 'r["on_date"][:10] < as_of]'
  run_mutant SS_N3_negative_gap_retroactive "$SS" 'return 0 <= gap < 60' 'return gap < 60'
  run_mutant SS_N4_recency_row_id_only "$SS" 'return (created_at, hist_id, atm_id)' 'return (hist_id, atm_id)'
  # Own: the recorded operator decision flipped (excluded rows consume the quota = round-1 V2-1 bug).
  run_mutant excluded_count_toward_n "$SS" 'EXCLUDED_ROWS_COUNT_TOWARD_N = False' 'EXCLUDED_ROWS_COUNT_TOWARD_N = True'
  # Own: the shared classifier bypassed (nothing ever excluded).
  run_mutant classifier_bypassed "$SS" '        exclusion_by_id[atm_id] = reason' '        exclusion_by_id[atm_id] = None'
  # Own: re-open the as-of leak by dropping the history cutoff.
  run_mutant asof_cutoff_dropped "$SS" 'return history_upto(rows, as_of)' 'return rows'
  # Own: B2 regression -- below_required on the available count.
  run_mutant b2_available "$SS" '"below_required": n_usable < min_per_type' '"below_required": n_available < min_per_type'
  # Own: lexicographic atm_id ranking (the N2 bug class).
  run_mutant atm_id_ranking "$SS" 'key=lambda i: closure_recency_key(history_by_id, i))' 'key=lambda i: i)'
  # Own: V2-8 regression -- the default needle used even when it postdates --as-of.
  run_mutant needle_never_derived "$SS" 'if default_date <= as_of:' 'if True:'
fi

exit $fail
