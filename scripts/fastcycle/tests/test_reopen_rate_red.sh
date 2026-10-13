#!/bin/bash
# Purpose : T091 (SpecKit-004 "fast-dev-cycles", User Story 3) RED baseline for
#           `closure/reopen_rate.py` per plan.md T-D06 and contract
#           cycle-time-report-cli.md's CT-006 ("reopen denominator") --
#           proves the tool does NOT exist today and documents, as executable
#           contract stubs plus fixture files, the four behaviours tasks.md's
#           T091 line names: (1) a golden hand-computed window (a matched
#           population: every reopened item genuinely IS a member of the
#           same window's closed-item population); (2) a golden-bad fixture
#           reproducing R1's own real "18 of 31" mismatched-population
#           finding (research/R1_baseline_cycle_time.md:64, cited verbatim
#           by contract CT-006 as "(R1 Table D caveat)") -- an item reopened
#           in the window with NO closure event anywhere in its history MUST
#           force a REFUSED rate (RATE_NOT_COMPUTABLE), never a naive ratio
#           of two mismatched counts; (3) an empty window -> the literal
#           message "no data in window [from, to]", never a zero-valued
#           statistic; (4) the T091/CT-5 negative-control addition -- a
#           window containing a genuine retroactive registration (the EXACT
#           Opened->closure db_write gap < 60s rule already implemented,
#           identically, by cycle_report.py's flag_retroactive_registration
#           and select_sample.py's detect_retroactive_registration) must be
#           EXCLUDED from both numerator and denominator, LISTED by id and
#           reason, and the tool must still PASS (exit 0) with the
#           correctly-adjusted rate -- proving the tool discriminates a
#           routine, safely-excludable data condition (negative control)
#           from the genuinely unresolvable population mismatch fixture (2),
#           which superficially looks the same shape ("one item out of a
#           small set needs special handling") but requires the OPPOSITE
#           verdict.
#
# THE GAP (verified directly, 2026-09-29 against the current working tree):
# `constitution/scripts/fastcycle/closure/` exists ONLY as an empty scaffold
# directory holding a bare `.gitkeep` placeholder (created by concurrent
# sibling US3 work on T094/T096/T099, which land escape_classify.py/
# sibling_search_check.sh/churn_rank.py into this SAME directory in
# parallel) -- it holds NO `*.py` file of any kind, so `reopen_rate.py`
# (T100's own, separate, later implementation task) does not exist. A bare
# directory-existence check would therefore be a §11.4.201 false-positive
# refusal (the directory existing proves nothing about whether T100 has
# landed -- exactly the lesson this suite's sibling test_cycle_report_red.sh
# already documents for cycle_report.py's own `cycle/` directory); the
# load-bearing check below is CONTENT: does `closure/` hold any real *.py
# file at all, and specifically `reopen_rate.py`.
#
# Producer≠Verifier (§11.4.240): this file is authored at the RED step
# (T091); T100's implementation of `closure/reopen_rate.py` is a separate,
# later task -- this file's author never implements it. The independent
# derivation function embedded below (derive_reopen_rate, a fresh Python
# re-implementation of the CT-006 rule text written directly from plan.md
# T-D06's own wording plus the two already-reviewed, already-landed sibling
# rules it reuses verbatim -- flag_retroactive_registration /
# detect_retroactive_registration) is a DERIVED oracle per §11.4.245,
# computed independently of whatever T100 eventually writes; it is never
# imported by, shared with, or otherwise coupled to `closure/reopen_rate.py`
# so the two never collapse into one producer=verifier pair.
#
# §11.4.273 control needle (this file's own absence-detection mechanism):
# before trusting "closure/reopen_rate.py is absent" as a finding, prove the
# plain `[ -f PATH ]` relative-path check genuinely resolves paths from this
# script's real location, by first confirming a KNOWN-PRESENT sibling
# (lib/fc_common.py, used throughout this suite) resolves true through the
# identical relative-path construction.
#
# §11.4.245 (oracle-problem-first / DERIVED oracle): every one of the four
# fixtures' `expected_report` blocks below is hand-computed FIRST, in the
# fixture's own `_hand_computation` block, and independently RE-DERIVED by
# this test's own Python function (never borrowed from, or shared with, any
# implementation) BEFORE that hand-computed value is trusted -- this test
# never simply asserts a number it typed once; it recomputes each fixture's
# answer from the raw item_history rows via a from-scratch reading of
# plan.md T-D06's own rule text and prints the full derivation, so a reader
# can verify the arithmetic independently of both this script's prose AND
# of whatever T100 eventually implements.
#
# §11.4.107(10) self-validation triple (plan.md line 128's Principle IV):
# golden_window (golden-good) and golden_bad_mismatched_populations
# (golden-bad) MUST produce OPPOSITE verdicts (a real numeric Bug rate vs a
# refused RATE_NOT_COMPUTABLE Bug rate) from the SAME derivation function --
# proving the derivation function can genuinely discriminate a matched
# population from a mismatched one, not merely echo whichever fixture asks
# for what. negative_control_retroactive is the THIRD member of the triple:
# a fixture that LOOKS structurally like the golden-bad case (3 clean items
# + 1 item needing special handling) but requires the OPPOSITE verdict from
# it (exclude-and-recompute, not refuse) -- proving the derivation function
# does not conflate "needs special handling" with "must be refused".
#
# Usage : bash test_reopen_rate_red.sh   Exit 0 = every real assertion below
#         held (both control needles, fixture presence, all four
#         independently-re-derived exact-match contract checks, and the
#         self-validation triple's cross-fixture discrimination proof).
#         Exit != 0 is the CORRECT, EXPECTED state today (2026-09-29):
#         `closure/reopen_rate.py` genuinely does not exist yet (T100 is a
#         separate, later, not-yet-started task) -- this is the T091 RED
#         baseline, not a bug in this test.
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
FIXDIR="$FC/tests/fixtures/reopen_rate"
DB="$ROOT/docs/workable_items.db"

fail=0
failx() { fail=1; }

# --- §11.4.273 control needle #1: prove the relative-path mechanism itself works ---
KNOWN_PRESENT="$FC/lib/fc_common.py"
if [ ! -f "$KNOWN_PRESENT" ]; then
  echo "NOT ok control needle #1 failed: a KNOWN-PRESENT sibling file"
  echo "     ($KNOWN_PRESENT) does not resolve -- this test's relative-path"
  echo "     computation is broken, so the absence check below proves"
  echo "     nothing (§11.4.273)"
  failx
else
  echo "ok control needle #1: a known-present sibling (lib/fc_common.py) resolves"
  echo "   through this test's own path construction -- the absence check"
  echo "   below can be trusted"
fi

# --- §11.4.273 control needle #2: a fabricated id must be absent from the live DB ---
# (mirrors sibling test_cycle_report_red.sh's own live-DB control needle;
# proves the fixture family's atm_id-collision precaution -- B-/T-/F-/MB-/
# NB-/NT-/NF- prefixes distinct from the real ATM-/SPK- schemes -- is not
# merely asserted but genuinely checked against the live tracker.)
if command -v sqlite3 >/dev/null 2>&1 && [ -f "$DB" ]; then
  for fake_id in B-001 MB-004 NB-001; do
    hit=$(sqlite3 -readonly "$DB" "SELECT atm_id FROM items WHERE atm_id='$fake_id';" 2>&1)
    if [ -n "$hit" ]; then
      echo "NOT ok control needle #2 FAILED: synthetic fixture id '$fake_id' collides"
      echo "     with a REAL live-tracker item -- every fixture in this suite must use"
      echo "     ids that do not exist in docs/workable_items.db"
      failx
    fi
  done
  echo "ok control needle #2: the synthetic fixture id prefixes (B-/MB-/NB-...) do"
  echo "   not collide with any real item in the live tracker DB"
else
  echo "NOT ok control needle #2 SKIPPED: sqlite3 or the tracker DB is unavailable"
  echo "     in this environment -- this is an environment gap, not a finding"
  failx
fi

# --- (1) Absence check: closure/reopen_rate.py ---
# Note: `$FC/closure/` itself exists RIGHT NOW as an empty scaffold
# directory (a bare `.gitkeep` placeholder, from concurrent sibling US3
# work on T094/T096/T099 landing INTO this same directory in parallel)
# without that meaning T100 has landed -- a directory-existence check alone
# would be a §11.4.201 false-positive refusal (flagging a condition that is
# not the real one). The load-bearing check is content: does the directory
# hold reopen_rate.py specifically?
CLOSURE_DIR="$FC/closure"
REOPEN_RATE="$FC/closure/reopen_rate.py"
if [ -d "$CLOSURE_DIR" ]; then
  py_count=$(find "$CLOSURE_DIR" -maxdepth 1 -name '*.py' | wc -l)
  echo "-- $CLOSURE_DIR exists, holding $py_count *.py file(s) right now (sibling"
  echo "   US3 tasks T094/T096/T099 may land escape_classify.py/"
  echo "   sibling_search_check.sh/churn_rank.py here independently of this task)"
else
  echo "-- $CLOSURE_DIR does not exist at all yet"
fi
if [ -f "$REOPEN_RATE" ]; then
  echo "ok closure/reopen_rate.py now exists -- T100 has landed. The forward-"
  echo "   compatible invocation checks below will exercise it for real against"
  echo "   every fixture's expected_report block."
  TOOL_PRESENT=1
else
  echo "NOT ok closure/reopen_rate.py is absent -- T100 (plan.md T-D06's"
  echo "     implementation task, a SEPARATE later task from this RED test) has"
  echo "     not landed yet. THIS IS THE CORRECT, EXPECTED T091 RED BASELINE --"
  echo "     the fixtures + independent derivation below stand as the interim"
  echo "     contract (per contracts/common-conventions.md's own convention for"
  echo "     open-gap tools: 'their interface, output and RED fixtures are fixed"
  echo "     by the plan task text until a contract is written') T100 must satisfy."
  TOOL_PRESENT=0
  failx
fi

# --- Fixture directories present ---
for d in golden_window golden_bad_mismatched_populations empty_window negative_control_retroactive; do
  if [ ! -d "$FIXDIR/$d" ]; then
    echo "NOT ok fixture directory $FIXDIR/$d missing"
    failx
  else
    n=$(find "$FIXDIR/$d" -type f | wc -l)
    if [ "$n" -lt 2 ]; then
      echo "NOT ok fixture $d has fewer than 2 files (expected at least an input"
      echo "     JSON + an 'expected' file); found $n"
      failx
    else
      echo "ok fixture $d present ($n files)"
    fi
  fi
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------
# Independent DERIVED oracle (§11.4.245): a from-scratch Python
# re-implementation of plan.md T-D06's rule text, written directly by THIS
# test's author, never imported by nor shared with closure/reopen_rate.py.
# Reuses, VERBATIM, the two already-reviewed, already-landed sibling rules
# this task's own text cites as identical: flag_retroactive_registration
# (cycle_report.py:411) / detect_retroactive_registration
# (select_sample.py:309) -- the Opened->terminal-closure created_at
# (db-write) gap in [0, 60) seconds rule.
# ---------------------------------------------------------------------------
cat > "$TMP/derive.py" <<'PYEOF'
import datetime
import json
import sys

CLOSURE_EVENTS = ("Fixed", "Implemented", "Completed")
ITEM_TYPES = ("Bug", "Feature", "Task")


def parse_iso(value):
    v = value.strip()
    if v.endswith("Z"):
        v = v[:-1] + "+00:00"
    return datetime.datetime.fromisoformat(v)


def is_retroactive(rows):
    """Identical rule to cycle_report.py's flag_retroactive_registration /
    select_sample.py's detect_retroactive_registration: Opened -> terminal
    closure created_at (db-write) gap in [0, 60) seconds."""
    opened = next((r for r in rows if r["event_type"] == "Opened"), None)
    closed = next((r for r in reversed(rows) if r["event_type"] in CLOSURE_EVENTS), None)
    if not opened or not closed:
        return False
    try:
        gap = (parse_iso(closed["created_at"]) - parse_iso(opened["created_at"])).total_seconds()
    except Exception:
        return False
    return 0 <= gap < 60


def has_closure_ever(rows):
    return any(r["event_type"] in CLOSURE_EVENTS for r in rows)


def closed_in_window(rows, frm, to):
    return any(r["event_type"] in CLOSURE_EVENTS and frm <= r["on_date"] <= to for r in rows)


def reopened_in_window(rows, frm, to):
    return any(r["event_type"] == "Reopened" and frm <= r["on_date"] <= to for r in rows)


def derive(items, history, frm, to):
    """T-D06's own rule text, applied from scratch: 'reopened / closed per
    type per window, both counted from the SAME population (items closed
    within the window)'; retroactive registrations excluded and listed;
    a Reopened-in-window item with no closure event ANYWHERE in its history
    is a population mismatch (R1 Table D caveat) -> refuse (RATE_NOT_
    COMPUTABLE) and name it, rather than dividing two mismatched counts."""
    hist_by_item = {}
    for row in history:
        hist_by_item.setdefault(row["atm_id"], []).append(row)
    by_type = {}
    for it in items:
        by_type.setdefault(it["type"], []).append(it["atm_id"])

    result = {"by_type": {}}
    total_closed = 0
    total_reopened = 0
    total_excluded = []
    total_mismatched = []
    any_mismatch = False

    for t in ITEM_TYPES:
        ids = by_type.get(t, [])
        excluded = []
        matched_closed = []
        for aid in ids:
            rows = hist_by_item.get(aid, [])
            if closed_in_window(rows, frm, to):
                if is_retroactive(rows):
                    excluded.append(aid)
                else:
                    matched_closed.append(aid)
        mismatched = []
        for aid in ids:
            rows = hist_by_item.get(aid, [])
            if reopened_in_window(rows, frm, to) and aid not in matched_closed and aid not in excluded:
                if not has_closure_ever(rows):
                    mismatched.append(aid)

        closed_count = len(matched_closed)
        reopened_count = sum(1 for aid in matched_closed if reopened_in_window(hist_by_item.get(aid, []), frm, to))

        block = {"reopened": reopened_count, "closed": closed_count,
                 "window": {"from": frm, "to": to}, "dedup_rows_removed": 0}
        if excluded:
            block["excluded_retroactive"] = [
                {"item_id": aid, "reason": "retroactive-registration (Opened->closure db_write gap < 60s)"}
                for aid in sorted(excluded)
            ]
        if mismatched:
            block["rate"] = "RATE_NOT_COMPUTABLE"
            block["mismatched_items"] = sorted(mismatched)
            any_mismatch = True
        elif closed_count == 0:
            block["rate"] = "RATE_NOT_COMPUTABLE"
        else:
            block["rate"] = round(reopened_count / closed_count, 6)

        result["by_type"][t] = block
        total_closed += closed_count
        total_reopened += reopened_count
        total_excluded.extend(excluded)
        total_mismatched.extend(mismatched)

    overall = {"reopened": total_reopened, "closed": total_closed,
               "window": {"from": frm, "to": to}, "dedup_rows_removed": 0}
    if total_excluded:
        overall["excluded_retroactive"] = [
            {"item_id": aid, "reason": "retroactive-registration (Opened->closure db_write gap < 60s)"}
            for aid in sorted(total_excluded)
        ]
    if any_mismatch:
        overall["rate"] = "RATE_NOT_COMPUTABLE"
        overall["mismatched_items"] = sorted(total_mismatched)
    elif total_closed == 0:
        overall["rate"] = "RATE_NOT_COMPUTABLE"
    else:
        overall["rate"] = round(total_reopened / total_closed, 6)
    result["overall"] = overall

    if not items or not history:
        result["state"] = "NO_DATA_IN_WINDOW"
    elif total_closed == 0 and not any(
            closed_in_window(hist_by_item.get(aid, []), frm, to) or is_retroactive(hist_by_item.get(aid, []))
            for it in items for aid in [it["atm_id"]]):
        result["state"] = "NO_DATA_IN_WINDOW"
    else:
        result["state"] = "OK"

    # Top-level mirror fields (matching cycle_report.py's own top-level
    # report shape -- schema/as_of/window/state alongside the per-type
    # detail -- and this task's own richer fixture shape, which documents a
    # top-level `excluded_retroactive` aggregate distinct from each type's
    # own per-type excluded_retroactive list).
    result["window"] = {"from": frm, "to": to}
    if total_excluded:
        result["excluded_retroactive"] = [
            {"item_id": aid, "reason": "retroactive-registration (Opened->closure db_write gap < 60s)"}
            for aid in sorted(set(total_excluded))
        ]
    else:
        result["excluded_retroactive"] = []
    return result


def main():
    fixture_path = sys.argv[1]
    out_path = sys.argv[2]
    with open(fixture_path, encoding="utf-8") as fh:
        fx = json.load(fh)
    frm = fx["window"]["from"]
    to = fx["window"]["to"]
    derived = derive(fx.get("items", []), fx.get("item_history", []), frm, to)
    derived["schema"] = "reopen-rate/v1"
    derived["as_of"] = fx.get("as_of")
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(derived, fh, sort_keys=True, indent=2)
    print(json.dumps(derived, sort_keys=True))


if __name__ == "__main__":
    main()
PYEOF

echo
echo "=== T100 contract check 1/4: golden_window (matched population, DERIVED oracle) ==="
GW_FIX="$FIXDIR/golden_window/tracker_export.json"
GW_DERIVED_FILE="$TMP/golden_window.derived.json"
python3 "$TMP/derive.py" "$GW_FIX" "$GW_DERIVED_FILE" >/dev/null
GW_MATCH="$(python3 -c "
import json
derived = json.load(open('$GW_DERIVED_FILE'))
expected = json.load(open('$GW_FIX'))['expected_report']
def strip_state(d):
    d = dict(d)
    d.pop('state', None)
    d.pop('schema', None)
    d.pop('as_of', None)
    return d
print(strip_state(derived) == strip_state(expected))
" 2>&1)"
if [ "$GW_MATCH" = "True" ]; then
  echo "ok golden_window: the independent DERIVED oracle (§11.4.245), re-computed"
  echo "   from scratch by THIS test's own from-scratch Python function -- never"
  echo "   the fixture author simply re-typing a number -- EXACTLY matches the"
  echo "   fixture's own hand-computed expected_report: Bug reopened=1/closed=5"
  echo "   (rate=0.2), Task 0/2 (0.0), Feature 0/1 (0.0), overall 1/8 (0.125)."
  echo "   This is the golden-good member of the §11.4.107(10) self-validation"
  echo "   triple; it is compared below against golden_bad's opposite verdict."
else
  echo "NOT ok golden_window: the independent derivation did NOT match the"
  echo "     fixture's hand-computed expected_report (comparator: '$GW_MATCH')."
  echo "     Derived: $(cat "$GW_DERIVED_FILE" 2>/dev/null)"
  failx
fi

echo
echo "=== T100 contract check 2/4: golden_bad_mismatched_populations (R1 '18 of 31' class, DERIVED oracle) ==="
GB_FIX="$FIXDIR/golden_bad_mismatched_populations/tracker_export.json"
GB_DERIVED_FILE="$TMP/golden_bad.derived.json"
python3 "$TMP/derive.py" "$GB_FIX" "$GB_DERIVED_FILE" >/dev/null
GB_MATCH="$(python3 -c "
import json
derived = json.load(open('$GB_DERIVED_FILE'))
expected = json.load(open('$GB_FIX'))['expected_report']
def strip_state(d):
    d = dict(d)
    d.pop('state', None)
    d.pop('schema', None)
    d.pop('as_of', None)
    return d
print(strip_state(derived) == strip_state(expected))
" 2>&1)"
GB_BUG_REFUSED="$(python3 -c "
import json
derived = json.load(open('$GB_DERIVED_FILE'))
b = derived['by_type']['Bug']
print(b.get('rate') == 'RATE_NOT_COMPUTABLE' and b.get('mismatched_items') == ['MB-004'])
" 2>&1)"
if [ "$GB_MATCH" = "True" ] && [ "$GB_BUG_REFUSED" = "True" ]; then
  echo "ok golden_bad_mismatched_populations: the independent derivation EXACTLY"
  echo "   matches the fixture's hand-computed expected_report -- Bug's rate is"
  echo "   REFUSED (RATE_NOT_COMPUTABLE) naming MB-004 as the mismatched item"
  echo "   (MB-004 has a Reopened event in the window but ZERO closure events"
  echo "   anywhere in its history -- research/R1_baseline_cycle_time.md:64's"
  echo "   real 'so \"18 of 31 bugs\" ... is an UPPER-BOUND-style ratio with"
  echo "   mismatched populations ... do not quote as a rate' finding, cited"
  echo "   verbatim by contract CT-006). Task and Feature both compute clean,"
  echo "   real 0.0 rates -- the refusal is correctly scoped to Bug alone, not"
  echo "   a blanket whole-report failure."
else
  echo "NOT ok golden_bad_mismatched_populations: match='$GB_MATCH'"
  echo "     bug_refused_with_mb004='$GB_BUG_REFUSED'"
  echo "     Derived: $(cat "$GB_DERIVED_FILE" 2>/dev/null)"
  failx
fi

echo
echo "=== Self-validation control needle (§11.4.107(10)/§11.4.201(1)): golden vs golden-bad discriminate ==="
# The whole point of the derivation function is that it can tell a matched
# population from a mismatched one -- prove that here by cross-comparing
# the two real derived outputs' Bug blocks and requiring OPPOSITE verdicts
# (one a real number, one a refusal), mirroring sibling test_cycle_report_
# red.sh's own comparator-discrimination technique. Nothing on disk is
# mutated by either derivation, so nothing needs restoring.
DISCRIMINATE="$(python3 -c "
import json
gw = json.load(open('$GW_DERIVED_FILE'))
gb = json.load(open('$GB_DERIVED_FILE'))
gw_rate = gw['by_type']['Bug']['rate']
gb_rate = gb['by_type']['Bug']['rate']
gw_is_number = isinstance(gw_rate, (int, float))
gb_is_refused = gb_rate == 'RATE_NOT_COMPUTABLE'
print(gw_is_number and gb_is_refused and gw_rate != gb_rate)
" 2>&1)"
if [ "$DISCRIMINATE" = "True" ]; then
  echo "ok control needle (derivation discrimination): golden_window's Bug rate is"
  echo "   a REAL NUMBER (0.2) while golden_bad_mismatched_populations' Bug rate"
  echo "   is REFUSED (RATE_NOT_COMPUTABLE) from the SAME derivation function --"
  echo "   proving it genuinely discriminates a matched population from a"
  echo "   mismatched one rather than rubber-stamping every input the same way."
else
  echo "NOT ok control needle (derivation discrimination) FAILED: golden_window"
  echo "     Bug rate='$(python3 -c "import json;print(json.load(open('$GW_DERIVED_FILE'))['by_type']['Bug']['rate'])" 2>&1)'"
  echo "     golden_bad Bug rate='$(python3 -c "import json;print(json.load(open('$GB_DERIVED_FILE'))['by_type']['Bug']['rate'])" 2>&1)'"
  echo "     -- these must be a real number and RATE_NOT_COMPUTABLE respectively;"
  echo "     if they are not, the derivation function is a rubber stamp and"
  echo "     checks 1/4 and 2/4 above cannot be trusted."
  failx
fi

echo
echo "=== T100 contract check 3/4: empty_window (honest empty state, DERIVED oracle) ==="
EW_FIX="$FIXDIR/empty_window/window.json"
EW_DERIVED_FILE="$TMP/empty_window.derived.json"
python3 "$TMP/derive.py" "$EW_FIX" "$EW_DERIVED_FILE" >/dev/null
EW_STATE_OK="$(python3 -c "
import json
derived = json.load(open('$EW_DERIVED_FILE'))
print(derived.get('state') == 'NO_DATA_IN_WINDOW')
" 2>&1)"
if [ "$EW_STATE_OK" = "True" ]; then
  echo "ok empty_window: the independent derivation reports state=NO_DATA_IN_WINDOW"
  echo "   for the empty 2020-01-01..2020-01-02 window (zero items, zero history)"
  echo "   -- matching sibling test_cycle_report_red.sh's own CT-008 convention"
  echo "   ('no data in window [from, to]'), reused for cross-tool consistency"
  echo "   (§11.4.227) with the identical, already-verified-empty date range."
else
  echo "NOT ok empty_window: expected state=NO_DATA_IN_WINDOW, derived: $(cat "$EW_DERIVED_FILE" 2>/dev/null)"
  failx
fi

# Self-validation control needle for check 3/4: a window independently known
# to contain real data (golden_window's own window/items) run through the
# SAME derive() function's state field MUST NOT be NO_DATA_IN_WINDOW --
# proving this check can genuinely distinguish empty from non-empty rather
# than rubber-stamping the empty state for any input (§11.4.201(1)).
EW_DISCRIMINATE="$(python3 -c "
import json
gw = json.load(open('$GW_DERIVED_FILE'))
print(gw.get('state') != 'NO_DATA_IN_WINDOW')
" 2>&1)"
if [ "$EW_DISCRIMINATE" = "True" ]; then
  echo "ok control needle (empty-window discrimination): golden_window's own"
  echo "   non-empty data is correctly NOT reported NO_DATA_IN_WINDOW -- check"
  echo "   3/4 above can therefore be trusted to genuinely distinguish empty from"
  echo "   non-empty, not merely rubber-stamp the empty state for any input."
else
  echo "NOT ok control needle (empty-window discrimination) FAILED: golden_window's"
  echo "     real, non-empty data was reported NO_DATA_IN_WINDOW -- the derivation's"
  echo "     empty-window detection over-fires; check 3/4 above is untrustworthy."
  failx
fi

echo
echo "=== T100 contract check 4/4: negative_control_retroactive (CT-5, DERIVED oracle) ==="
NC_FIX="$FIXDIR/negative_control_retroactive/tracker_export.json"
NC_DERIVED_FILE="$TMP/negative_control.derived.json"
python3 "$TMP/derive.py" "$NC_FIX" "$NC_DERIVED_FILE" >/dev/null
NC_MATCH="$(python3 -c "
import json
derived = json.load(open('$NC_DERIVED_FILE'))
expected = json.load(open('$NC_FIX'))['expected_report']
def strip_state(d):
    d = dict(d)
    d.pop('state', None)
    d.pop('schema', None)
    d.pop('as_of', None)
    return d
print(strip_state(derived) == strip_state(expected))
" 2>&1)"
NC_PASSED_NOT_REFUSED="$(python3 -c "
import json
derived = json.load(open('$NC_DERIVED_FILE'))
b = derived['by_type']['Bug']
print(b.get('rate') == 0.0 and b.get('excluded_retroactive') == [
    {'item_id': 'NB-001', 'reason': 'retroactive-registration (Opened->closure db_write gap < 60s)'}
])
" 2>&1)"
if [ "$NC_MATCH" = "True" ] && [ "$NC_PASSED_NOT_REFUSED" = "True" ]; then
  echo "ok negative_control_retroactive: the independent derivation EXACTLY"
  echo "   matches the fixture's hand-computed expected_report -- Bug excludes"
  echo "   NB-001 (Opened->Fixed created_at gap = 30s, the identical rule"
  echo "   cycle_report.py's flag_retroactive_registration / select_sample.py's"
  echo "   detect_retroactive_registration already implement), LISTS it under"
  echo "   excluded_retroactive by id and reason, and PASSES with the correctly-"
  echo "   adjusted rate 0.0 (0 reopened / 2 closed) -- never RATE_NOT_COMPUTABLE."
  echo "   This is the T091/CT-5 negative-control member of the self-validation"
  echo "   triple: it must NOT be refused, unlike check 2/4's mismatched-"
  echo "   population fixture, even though both fixtures share the surface"
  echo "   shape 'one item out of a small set needs special handling'."
else
  echo "NOT ok negative_control_retroactive: match='$NC_MATCH'"
  echo "     bug_passed_not_refused='$NC_PASSED_NOT_REFUSED'"
  echo "     Derived: $(cat "$NC_DERIVED_FILE" 2>/dev/null)"
  failx
fi

echo
echo "=== Self-validation control needle: golden-bad refuses, negative-control passes (same shape, opposite verdicts) ==="
# The decisive proof that the derivation function does not conflate "needs
# special handling" with "must be refused": golden_bad_mismatched_
# populations' Bug rate MUST be refused while negative_control_retroactive's
# Bug rate MUST be a real, computed number, even though both fixtures have
# the identical surface shape (3 clean items + 1 item needing special
# handling).
SHAPE_DISCRIMINATE="$(python3 -c "
import json
gb = json.load(open('$GB_DERIVED_FILE'))
nc = json.load(open('$NC_DERIVED_FILE'))
gb_refused = gb['by_type']['Bug']['rate'] == 'RATE_NOT_COMPUTABLE'
nc_is_number = isinstance(nc['by_type']['Bug']['rate'], (int, float))
print(gb_refused and nc_is_number)
" 2>&1)"
if [ "$SHAPE_DISCRIMINATE" = "True" ]; then
  echo "ok control needle (shape discrimination): golden_bad_mismatched_populations'"
  echo "   Bug rate is refused while negative_control_retroactive's Bug rate is a"
  echo "   real number -- the derivation genuinely distinguishes an unresolvable"
  echo "   population mismatch from a routine, safely-excludable retroactive"
  echo "   registration, rather than treating every 'one odd item out of four'"
  echo "   fixture identically."
else
  echo "NOT ok control needle (shape discrimination) FAILED: both fixtures'"
  echo "     surface-similar 'one odd item' cases produced the same class of"
  echo "     verdict -- the derivation cannot be trusted to discriminate them."
  failx
fi

# ---------------------------------------------------------------------------
# Forward-compatible invocation (dormant today, TOOL_PRESENT=0): once
# closure/reopen_rate.py lands (T100), this block invokes it for real
# against every fixture and diffs its ACTUAL output against the SAME
# expected_report blocks the independent derivation above already verified
# are internally consistent -- mirroring the exact "post-review remediation"
# pattern sibling test_cycle_report_red.sh already applied to itself once
# cycle_report.py landed. Documented interim CLI (per contracts/common-
# conventions.md's own convention: "their interface ... fixed by the plan
# task text until a contract is written" -- this test IS that fixed
# interface until a contract file for reopen_rate.py exists):
#   reopen_rate.py --as-of <YYYY-MM-DD> --window-days <N> \
#       --tracker-export <fixture.json> --out <report.json>
# ---------------------------------------------------------------------------
if [ "$TOOL_PRESENT" = "1" ]; then
  for fx in golden_window:golden_window/tracker_export.json:2026-07-31:30 \
            golden_bad_mismatched_populations:golden_bad_mismatched_populations/tracker_export.json:2026-07-31:30 \
            empty_window:empty_window/window.json:2020-01-02:1 \
            negative_control_retroactive:negative_control_retroactive/tracker_export.json:2026-07-31:30; do
    name="${fx%%:*}"; rest="${fx#*:}"
    relpath="${rest%%:*}"; rest2="${rest#*:}"
    as_of="${rest2%%:*}"; wdays="${rest2#*:}"
    OUT="$TMP/${name}.actual.json"
    ERR="$TMP/${name}.actual.err"
    python3 "$REOPEN_RATE" --as-of "$as_of" --window-days "$wdays" \
      --tracker-export "$FIXDIR/$relpath" --out "$OUT" >"$ERR" 2>&1
    RC=$?
    if [ "$RC" = 0 ] && [ -f "$OUT" ]; then
      REAL_MATCH="$(python3 -c "
import json
actual = json.load(open('$OUT'))
expected = json.load(open('$FIXDIR/$relpath')).get('expected_report', json.load(open('$FIXDIR/$relpath')).get('expected_body_ct008_style'))
def strip(d):
    d = dict(d)
    for k in ('state','schema','as_of','body_hash','run_meta'):
        d.pop(k, None)
    return d
print(strip(actual) == strip(expected))
" 2>&1)"
      if [ "$REAL_MATCH" = "True" ]; then
        echo "ok $name: REAL reopen_rate.py invocation matches expected_report exactly"
      else
        echo "NOT ok $name: REAL reopen_rate.py invocation diverges from expected_report"
        echo "     ($REAL_MATCH); actual: $(cat "$OUT" 2>/dev/null)"
        failx
      fi
    else
      echo "NOT ok $name: real invocation failed (rc=$RC) -- $(cat "$ERR" 2>/dev/null)"
      failx
    fi
  done
else
  echo
  echo "=== Real-tool invocation checks SKIPPED: closure/reopen_rate.py not present ==="
  echo "NOT ok real-invocation checks skipped -- this contributes to the overall"
  echo "     RED exit below, which is the CORRECT state until T100 lands."
  failx
fi

echo
if [ "$fail" = 0 ]; then
  echo "=== ALL CHECKS PASS -- unexpected today (T100 not yet landed); if you see"
  echo "    this, closure/reopen_rate.py must have landed AND every fixture check"
  echo "    passed against the real tool. ==="
else
  echo "=== T091 RED BASELINE CONFIRMED: closure/reopen_rate.py does not exist yet"
  echo "    (T100 is a separate, later task). The four fixtures above + their"
  echo "    independently re-derived, self-validated expected_report blocks are"
  echo "    the interim contract T100 must satisfy to turn this GREEN. ==="
fi

exit $fail
