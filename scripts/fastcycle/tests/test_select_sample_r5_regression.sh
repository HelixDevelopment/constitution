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
#   Round 3 (docs/qa/t048_restart_round3_20261008/V2_sampling.md):
#   V3-1/V3-8 (class: an inclusive bound, or a first-vs-latest choice, with
#          no row on it -- patched one instance at a time in rounds 1 and 2):
#          S9 runs the GENERATED boundary matrix (build_asof_scenario.py
#          matrix-full|matrix-cut) against an independent in-test oracle, with
#          a meta-check that fails on any cell without an assertion. Every
#          surviving round-3 mutation is a paired mutation below.
#   V3-6   S7b: reopen_rate.py's closed/reopened-in-window and retroactive
#          rules cross-checked against select_sample on every matrix history;
#          collect_baseline.py's SQL copies are measured and REPORTED only.
#   V3-3   S10: the recorded operator decision's other setting is specified.
#   V3-4   S11: a missing/broken lib/fc_common.py is BLIND (exit 4).
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

echo "=== S9 (V3-1/V3-8 class, round 3): GENERATED boundary matrix -- every cell vs an independent oracle ==="
# The matrix (build_asof_scenario.py matrix-full|matrix-cut) is generated from
# declarative tables; manifest.json carries every cell's RAW rows and NO
# expected outcome. The oracle below is a deliberately small, straightforward
# re-statement of the DEC-03 rules written for this test (it imports nothing
# from the tool): day = on_date[:10]; cut = rows with day <= as-of; closed /
# reopened in window = a row of that class with window.from <= day <= as-of;
# retroactive = first Opened -> LAST closure created_at gap in [0, 60) s;
# bulk = >= threshold candidates sharing (dirname(evidence), on_date) of their
# LAST closure, over EVERY candidate (closed or reopened); the derived needle =
# the closure row with the greatest (day, insert order) among day <= as-of.
# A meta-check fails if any manifest cell received no assertion, if the
# manifest is missing a cell the test independently expects, or if the meta-
# check itself cannot see a phantom cell (control needle).
MX="$TMP/mx"
mx_ok=1
for mode in matrix-full matrix-cut; do
  if ! python3 "$BUILDER" "$MX/$mode" "$mode" >"$TMP/mx_build_$mode.err" 2>&1; then
    bad "S9 matrix build ($mode) failed: $(tail -2 "$TMP/mx_build_$mode.err")"; mx_ok=0
  fi
done
MX_ARGS=(--as-of 2026-05-20 --window-days 30 --min-per-type 1000 --bulk-threshold 3)
if [ "$mx_ok" = 1 ]; then
  for mode in matrix-full matrix-cut; do
    python3 "$TOOL" "${MX_ARGS[@]}" --db-path "$MX/$mode/db.sqlite" --out "$TMP/mx_ss_$mode.json" \
      >"$TMP/mx_ss_$mode.err" 2>&1 || bad "S9 select_sample on $mode rc=$? -- $(tail -2 "$TMP/mx_ss_$mode.err")"
  done
  verdict="$(python3 - "$MX/matrix-full/manifest.json" "$TMP/mx_ss_matrix-full.json" "$TMP/mx_ss_matrix-cut.json" <<'PY'
import datetime, json, os, sys

def load(p):
    try:
        return json.load(open(p))
    except Exception as e:
        print("missing output %s: %s" % (p, e))
        raise SystemExit

man, full, cut = (load(p) for p in sys.argv[1:4])
AS_OF = man["as_of"]
FROM = (datetime.date.fromisoformat(AS_OF) - datetime.timedelta(days=man["window_days"])).isoformat()
THRESH = man["bulk_threshold"]
CLOSE = ("Fixed", "Implemented", "Completed")

# ---- independent reference oracle -------------------------------------------
def day(s):
    return (s or "")[:10]

def ts(s):  # tracker created_at: "YYYY-MM-DD HH:MM:SS", UTC
    return datetime.datetime.strptime(s, "%Y-%m-%d %H:%M:%S").replace(tzinfo=datetime.timezone.utc)

items, order = {}, []
for c in man["cells"]:
    for it in c["items"]:
        items[it["atm_id"]] = it
        order += [(it["atm_id"], r) for r in it["rows"]]
cut_rows = {i: [r for r in it["rows"] if day(r["on_date"]) <= AS_OF] for i, it in items.items()}

def in_win(r, ev):
    hit = r["event_type"] in CLOSE if ev == "closure" else r["event_type"] == "Reopened"
    return hit and FROM <= day(r["on_date"]) <= AS_OF

def closed(i):
    return any(in_win(r, "closure") for r in cut_rows[i])

def reopened(i):
    return any(in_win(r, "reopened") for r in cut_rows[i])

def last_closure(i):
    cl = [r for r in cut_rows[i] if r["event_type"] in CLOSE]
    return cl[-1] if cl else None

def retro(i):
    op = next((r for r in cut_rows[i] if r["event_type"] == "Opened"), None)
    cl = last_closure(i)
    if not op or not cl:
        return False
    return 0 <= (ts(cl["created_at"]) - ts(op["created_at"])).total_seconds() < 60

cands = sorted(i for i in items if closed(i) or reopened(i))
groups = {}
for i in cands:
    cl = last_closure(i)
    if cl and cl["evidence_path"]:
        groups.setdefault((os.path.dirname(cl["evidence_path"]), cl["on_date"]), []).append(i)
bulk = {i for g in groups.values() if len(g) >= THRESH for i in g}

def expect(i):
    if i not in cands:
        return None
    excl = "bulk" if i in bulk else ("retro" if retro(i) else None)
    t = items[i]["type"].lower()
    reason = "reopened-in-window" if reopened(i) else ("listed-excluded-" if excl else "sampled-") + t
    return (reason, excl)

needle_rows = [(day(r["on_date"]), k, i, r) for k, (i, r) in enumerate(order)
               if r["event_type"] in CLOSE and day(r["on_date"]) <= AS_OF]
_, _, n_id, n_row = max(needle_rows)
want_needle = ("derived-at-as-of", n_id, n_row["event_type"], n_row["on_date"])

# ---- assertions, one per cell -------------------------------------------------
def tool_view(doc):
    return {it["item_id"]: (it["selection_reason"],
                            None if not it["excluded_from_duration"] else
                            ("bulk" if (it["exclusion_reason"] or "").startswith("bulk-import-cluster") else
                             "retro" if (it["exclusion_reason"] or "").startswith("retroactive-registration") else
                             "other:%s" % it["exclusion_reason"]))
            for it in doc.get("items", [])}

def assert_cells(cells, doc):
    got = tool_view(doc)
    asserted, problems = set(), []
    for c in cells:
        if c["kind"] in ("window", "commit", "review", "rule") and c["cell_id"] != "rule/needle_derived":
            if not c["items"]:
                continue  # no item => no assertion => the meta-check reports it
            for it in c["items"]:
                if got.get(it["atm_id"]) != expect(it["atm_id"]):
                    problems.append("%s %s: tool=%s oracle=%s" % (c["cell_id"], it["atm_id"],
                                                                 got.get(it["atm_id"]), expect(it["atm_id"])))
            asserted.add(c["cell_id"])
        elif c["cell_id"] == "rule/needle_derived":
            n = doc.get("run_meta", {}).get("needle", {})
            got_n = (n.get("source"), n.get("present_id"), n.get("present_event"), n.get("present_on_date"))
            if got_n != want_needle:
                problems.append("%s: tool=%s oracle=%s" % (c["cell_id"], got_n, want_needle))
            asserted.add(c["cell_id"])
    return asserted, problems

def meta(cells, asserted):
    ids = [c["cell_id"] for c in cells]
    want = {"window/%s/%s/%+d/%s" % (e, b, o, f) for e in ("closure", "reopened") for b in ("from", "to")
            for o in (-1, 0, 1) for f in ("date", "datetime")}
    want |= {"commit/%s/%+ds/%s" % (w, o, z) for w in ("author", "committer") for o in (-1, 0, 1)
             for z in ("Z", "+05:00")}
    want |= {"review/%s/%+ds" % (w, o) for w in ("end", "start") for o in (-1, 0, 1)} | {"review/straddle"}
    want |= {"rule/" + r for r in ("retro_terminal_not_first", "retro_terminal_is_retro", "bulk_latest_shared",
                                   "bulk_first_shared", "pop_retro_reopen_only", "pop_bulk_reopen_only",
                                   "needle_derived")}
    p = []
    if len(ids) != len(set(ids)):
        p.append("duplicate cell ids")
    if set(ids) != want:
        p.append("manifest cells != expected matrix: missing %s extra %s"
                 % (sorted(want - set(ids)), sorted(set(ids) - want)))
    unasserted = sorted(set(ids) - asserted)
    if unasserted:
        p.append("cells with NO assertion: %s" % unasserted)
    return p

problems = []
for label, doc in (("full", full), ("cut", cut)):
    asserted, p = assert_cells(man["cells"], doc)
    problems += ["%s: %s" % (label, x) for x in p + meta(man["cells"], asserted)]
# strata vs the oracle (per type)
for t in ("Bug", "Feature", "Task"):
    cl = [i for i in cands if closed(i) and items[i]["type"] == t]
    usable = [i for i in cl if expect(i)[1] is None]
    want_s = {"n_available": len(cl), "n_usable_available": len(usable), "n_selected": len(usable),
              "n_usable": len(usable), "n_listed_excluded": len(cl) - len(usable)}
    got_s = {k: full.get("strata", {}).get(t, {}).get(k) for k in want_s}
    if got_s != want_s:
        problems.append("strata[%s]=%s oracle %s" % (t, got_s, want_s))
if sorted(full.get("reopened_in_window", [])) != sorted(i for i in cands if reopened(i)):
    problems.append("reopened_in_window=%s" % full.get("reopened_in_window"))
if full.get("body_hash") != cut.get("body_hash"):
    problems.append("matrix full vs cut body_hash differ (future rows leak)")
# control needles: the meta-check must SEE a phantom cell (no assertion), and
# the per-cell comparison must SEE a wrong outcome.
phantom = man["cells"] + [{"cell_id": "phantom/x", "kind": "phantom", "dims": {}, "items": []}]
a_ph, _ = assert_cells(phantom, full)
if not any("NO assertion" in x for x in meta(phantom, a_ph)):
    problems.append("control: meta-check did not report a cell with no assertion")
bad_doc = dict(full, items=[dict(it, selection_reason="x") for it in full.get("items", [])])
if not assert_cells(man["cells"], bad_doc)[1]:
    problems.append("control: per-cell comparison accepted a corrupted report")
n_present = sum(1 for i in items if expect(i) is not None)
n_absent = len(items) - n_present
print("PASS %d cells, %d items (%d in sample, %d outside)" % (len(man["cells"]), len(items), n_present, n_absent)
      if not problems else " | ".join(problems))
PY
)"
  case "$verdict" in
    PASS*) ok "S9 boundary matrix: ${verdict#PASS } -- every cell matches the oracle in full and cut DBs; full==cut; meta-check and comparison controls fire" ;;
    *) bad "S9 $verdict" ;;
  esac
fi

echo "=== S7b (V3-6, round 3): reopen_rate.py's window functions agree with select_sample's on the matrix ==="
# Every matrix item's history (full AND as-of cut) through both tools' own
# closed_in_window / reopened_in_window and retroactive rules. collect_baseline.
# py's SQL copies are measured too but only REPORTED (owned by another area:
# its raw `on_date BETWEEN` lacks the day rule -- a '# note' line, not a check).
if [ -f "$MX/matrix-full/manifest.json" ]; then
  verdict="$(python3 - "$TOOL" "$FC/closure/reopen_rate.py" "$MX/matrix-full/manifest.json" <<'PY'
import datetime, importlib.util, json, sys
def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m
ss, rr = load("ss_ut7", sys.argv[1]), load("rr_ut7", sys.argv[2])
man = json.load(open(sys.argv[3]))
AS_OF = man["as_of"]
FROM = (datetime.date.fromisoformat(AS_OF) - datetime.timedelta(days=man["window_days"])).isoformat()
div, n = [], 0
for c in man["cells"]:
    for it in c["items"]:
        for label, h in (("full", it["rows"]), ("cut", [r for r in it["rows"] if r["on_date"][:10] <= AS_OF])):
            n += 1
            a = (ss.closed_in_window(h, FROM, AS_OF), ss.reopened_in_window(h, {"from": FROM, "to": AS_OF}),
                 ss.detect_retroactive_registration(h))
            b = (rr.closed_in_window(h, FROM, AS_OF), rr.reopened_in_window(h, FROM, AS_OF),
                 rr.is_retroactive_registration(h))
            if a != b:
                div.append("%s %s %s select_sample=%s reopen_rate=%s" % (c["cell_id"], it["atm_id"], label, a, b))
print("PASS %d histories" % n if not div else "DIVERGE " + " | ".join(div))
PY
)"
  case "$verdict" in
    PASS*) ok "S7b reopen_rate closed/reopened-in-window + retroactive == select_sample on ${verdict#PASS } (every matrix cell, full and cut)" ;;
    *) bad "S7b $verdict" ;;
  esac
  cb_note="$(python3 - "$FC/cycle/collect_baseline.py" "$TOOL" "$MX/matrix-full/db.sqlite" <<'PY' 2>&1
import importlib.util, sqlite3, sys
def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m
cb, ss = load("cb_ut7", sys.argv[1]), load("ss_ut7b", sys.argv[2])
conn = sqlite3.connect("file:%s?mode=ro" % sys.argv[3], uri=True)
out = []
for fn in ("db_closures_in_window", "db_reopened_in_window"):
    a = set(getattr(ss, fn)(conn, "2026-04-20", "2026-05-20"))
    b = set(getattr(cb, fn)(conn, "2026-04-20", "2026-05-20"))
    if a != b:
        out.append("%s: select_sample-only %s collect_baseline-only %s" % (fn, sorted(a - b), sorted(b - a)))
print("; ".join(out) or "no divergence")
PY
)"
  echo "# note S7b (not a check, collect_baseline.py is out of this area): $cb_note"
else
  bad "S7b matrix manifest unavailable"
fi

echo "=== S10 (V3-3): the recorded operator decision's OTHER setting (EXCLUDED_ROWS_COUNT_TOWARD_N = True) is positively specified ==="
# A VARIANT tree (not a mutant: this is the documented 'one constant away'
# alternative) is run through the real CLI on the hand-derived fixture.
# Expected (min 2): Bug unchanged {310, 277}; Task takes the most-recent 2 rows
# usable or not = {603, 602}, both bulk -> n_selected 2, n_usable 0, nothing
# listed, below_required true; Feature takes ATM-700 (retroactive) -> n_usable
# 0; ATM-601/503/504 are not in the sample; excluded rows carry
# excluded_from_duration and selection_reason sampled-*; the output states the
# rule it applied.
VAR_SRC="$(cd "$(dirname "$TOOL")/.." && pwd)"   # the tree under test (a mutant run builds its variant from the mutant)
VT="$TMP/variant_true/constitution/scripts/fastcycle"
mkdir -p "$VT" && cp -r "$VAR_SRC/lib" "$VAR_SRC/cycle" "$VAR_SRC/closure" "$VT/" 2>/dev/null
if python3 - "$VT/cycle/select_sample.py" <<'PY'
import sys
p = sys.argv[1]; t = open(p).read()
old = "EXCLUDED_ROWS_COUNT_TOWARD_N = False"
if t.count(old) != 1:
    raise SystemExit("anchor count %d" % t.count(old))
open(p, "w").write(t.replace(old, "EXCLUDED_ROWS_COUNT_TOWARD_N = True"))
PY
then
  python3 "$VT/cycle/select_sample.py" "${COMMON[@]}" "${NEEDLE[@]}" --db-path "$TMP/full/db.sqlite" \
    --out "$TMP/ss_true.json" >"$TMP/ss_true.err" 2>&1
  verdict="$(python3 - "$TMP/ss_true.json" <<'PY'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception as e:
    print("no output: %s" % e); raise SystemExit
p = []
want_strata = {
    "Bug": {"n_available": 7, "n_usable_available": 7, "n_selected": 2, "n_usable": 2, "n_listed_excluded": 0, "below_required": False},
    "Task": {"n_available": 7, "n_usable_available": 4, "n_selected": 2, "n_usable": 0, "n_listed_excluded": 0, "below_required": True},
    "Feature": {"n_available": 1, "n_usable_available": 0, "n_selected": 1, "n_usable": 0, "n_listed_excluded": 0, "below_required": True}}
for t, w in want_strata.items():
    g = {k: d["strata"][t].get(k) for k in w}
    if g != w:
        p.append("strata[%s]=%s want %s" % (t, g, w))
want_items = {"ATM-277": ("sampled-bug", False), "ATM-310": ("sampled-bug", False),
              "ATM-300": ("reopened-in-window", False), "ATM-800": ("reopened-in-window", False),
              "ATM-602": ("sampled-task", True), "ATM-603": ("sampled-task", True),
              "ATM-700": ("sampled-feature", True)}
got = {i["item_id"]: (i["selection_reason"], i["excluded_from_duration"]) for i in d.get("items", [])}
if got != want_items:
    p.append("items=%s want %s" % (got, want_items))
if d.get("selection_rule", {}).get("excluded_rows_count_toward_n") is not True:
    p.append("selection_rule=%s" % d.get("selection_rule"))
print("PASS" if not p else " | ".join(p))
PY
)"
  if [ "$verdict" = PASS ]; then
    ok "S10 EXCLUDED_ROWS_COUNT_TOWARD_N=True: most-recent N rows usable or not; Task 2 selected / 0 usable / below_required; excluded rows sampled and flagged"
  else
    bad "S10 $verdict -- $(tail -2 "$TMP/ss_true.err")"
  fi
else
  bad "S10 could not build the True variant (anchor drifted)"
fi

echo "=== S11 (V3-4): a broken or missing sibling module is BLIND (exit 4), never exit 1 -- plain and --determinism-check ==="
s11=""
for breakage in missing syntax; do
  BT="$TMP/broken_$breakage/constitution/scripts/fastcycle"
  mkdir -p "$BT" && cp -r "$(cd "$(dirname "$TOOL")/.." && pwd)/lib" "$(cd "$(dirname "$TOOL")/.." && pwd)/cycle" "$BT/"
  if [ "$breakage" = missing ]; then rm -f "${BT:?}/lib/fc_common.py"; else printf 'def broken(:\n' > "$BT/lib/fc_common.py"; fi
  rm -rf "${BT:?}/lib/__pycache__"
  for dc in "" --determinism-check; do
    rm -f "$TMP/s11.json"
    python3 "$BT/cycle/select_sample.py" "${COMMON[@]}" "${NEEDLE[@]}" --db-path "$TMP/full/db.sqlite" $dc \
      --out "$TMP/s11.json" >"$TMP/s11.err" 2>&1
    rc=$?
    if [ "$rc" != 4 ] || [ -f "$TMP/s11.json" ] || ! grep -q 'BLIND' "$TMP/s11.err"; then
      s11="$s11 fc_common-$breakage${dc:+ $dc}: rc=$rc out=$([ -f "$TMP/s11.json" ] && echo yes || echo no) $(tail -1 "$TMP/s11.err")"
    fi
  done
done
if [ -z "$s11" ]; then
  ok "S11 missing or broken fc_common.py: select_sample exits 4 with a BLIND message and writes no --out (plain and --determinism-check)"
else
  bad "S11$s11"
fi

echo "=== S12 (bound class, round 3): an --as-of EQUAL to the default needle's date keeps the default needle ==="
# The default row (ATM-953 Fixed 2026-07-28) is not in the fixture: at as-of
# 07-28 the default is NOT postdating (<=), so it is used and the run fails
# closed (exit 3, NOT FOUND); a strict '<' would derive a needle and exit 0.
python3 "$TOOL" --as-of 2026-07-28 --window-days 60 --min-per-type 2 --bulk-threshold 3 \
  --db-path "$TMP/full/db.sqlite" --out "$TMP/nd_eq.json" >"$TMP/nd_eq.err" 2>&1
nd_eq_rc=$?
if [ "$nd_eq_rc" = 3 ] && grep -q 'NOT FOUND' "$TMP/nd_eq.err" && [ ! -f "$TMP/nd_eq.json" ]; then
  ok "S12 as-of 2026-07-28 (= default needle date) uses the default needle and fails closed (exit 3)"
else
  bad "S12 as-of = default needle date: rc=$nd_eq_rc -- $(tail -1 "$TMP/nd_eq.err")"
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
  # Round 3 reviewer mutations (V2_sampling.md round 3, verbatim diffs from the
  # reviewer's own mutant trees) -- the window-boundary / first-vs-latest /
  # classifier-population / derived-needle class, killed by S9 (the generated
  # boundary matrix + its independent oracle).
  run_mutant R3_closed_from_exclusive "$SS" 'return any(r["event_type"] in CLOSURE_EVENTS and frm <= (r.get("on_date") or "")[:10] <= to' 'return any(r["event_type"] in CLOSURE_EVENTS and frm < (r.get("on_date") or "")[:10] <= to'
  run_mutant R3_sql_discovery_from_strict "$SS" '"AND substr(ih.on_date, 1, 10) BETWEEN ? AND ?",' '"AND substr(ih.on_date, 1, 10) > ? AND substr(ih.on_date, 1, 10) <= ?",'
  run_mutant R3_reopen_to_exclusive "$SS" 'window["from"] <= (r.get("on_date") or "")[:10] <= window["to"]' 'window["from"] <= (r.get("on_date") or "")[:10] < window["to"]'
  run_mutant R3_sql_reopen_to_strict "$SS" "\"WHERE ih.event_type = 'Reopened' AND substr(ih.on_date, 1, 10) BETWEEN ? AND ?\"," "\"WHERE ih.event_type = 'Reopened' AND substr(ih.on_date, 1, 10) >= ? AND substr(ih.on_date, 1, 10) < ?\","
  run_mutant R3_retro_first_closure "$SS" 'closed = next((r for r in reversed(history) if r["event_type"] in CLOSURE_EVENTS), None)' 'closed = next((r for r in history if r["event_type"] in CLOSURE_EVENTS), None)'
  run_mutant R3_bulk_uses_first_closure "$SS" 'closure = latest_closure_event(hist)' 'closure = next((r for r in hist if r["event_type"] in CLOSURE_EVENTS), None)'
  run_mutant R3_exclusion_per_candidate_only_closed "$SS" 'exclusion_by_id = classify_exclusions(history_by_id, set(type_of), bulk_threshold)' 'exclusion_by_id = classify_exclusions(history_by_id, set().union(*by_type.values()) if by_type else set(), bulk_threshold); exclusion_by_id.update({i: None for i in type_of if i not in exclusion_by_id})'
  run_mutant R3_needle_derived_strict "$SS" "AND substr(on_date, 1, 10) <= ? \"" "AND substr(on_date, 1, 10) < ? \""
  # Own (round 3): the rest of the bound class, and the V3-4 guard.
  run_mutant R3_sql_closure_to_strict "$SS" '"AND substr(ih.on_date, 1, 10) BETWEEN ? AND ?",' '"AND substr(ih.on_date, 1, 10) >= ? AND substr(ih.on_date, 1, 10) < ?",'
  run_mutant R3_closed_to_exclusive "$SS" 'frm <= (r.get("on_date") or "")[:10] <= to' 'frm <= (r.get("on_date") or "")[:10] < to'
  run_mutant R3_sql_reopen_from_strict "$SS" "\"WHERE ih.event_type = 'Reopened' AND substr(ih.on_date, 1, 10) BETWEEN ? AND ?\"," "\"WHERE ih.event_type = 'Reopened' AND substr(ih.on_date, 1, 10) > ? AND substr(ih.on_date, 1, 10) <= ?\","
  run_mutant R3_sql_closure_raw_on_date "$SS" '"AND substr(ih.on_date, 1, 10) BETWEEN ? AND ?",' '"AND ih.on_date BETWEEN ? AND ?",'
  run_mutant R3_sql_reopen_raw_on_date "$SS" "AND substr(ih.on_date, 1, 10) BETWEEN ? AND ?\",
        (frm, to),
    )
    return cur.fetchall()


def window_for" "AND ih.on_date BETWEEN ? AND ?\",
        (frm, to),
    )
    return cur.fetchall()


def window_for"
  run_mutant R3_cutoff_raw_on_date "$SS" 'r["on_date"][:10] <= as_of]' 'r["on_date"] <= as_of]'
  run_mutant R3_bulk_threshold_strict "$SS" 'if ekey is not None and len(members) >= bulk_threshold:' 'if ekey is not None and len(members) > bulk_threshold:'
  run_mutant R3_window_from_off_by_one "$SS" 'datetime.timedelta(days=window_days)).isoformat(),' 'datetime.timedelta(days=window_days - 1)).isoformat(),'
  run_mutant R3_needle_default_strict "$SS" 'if default_date <= as_of:' 'if default_date < as_of:'
  run_mutant R3_blind_guard_import_error_only "$SS" 'except Exception as _exc:  # noqa: BLE001 -- any load failure (ImportError, SyntaxError, ...) is BLIND' 'except ImportError as _exc:  # mutant'
fi

exit $fail
