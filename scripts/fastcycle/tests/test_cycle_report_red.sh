#!/bin/bash
# Purpose : T023 (SpecKit-004 "fast-dev-cycles", User Story 1) RED baseline for
#           `cycle/cycle_report.py` per contract cycle-time-report-cli
#           (specs/004-fast-dev-cycles/contracts/cycle-time-report-cli.md) --
#           proves the tool does NOT exist today and documents, as executable
#           contract stubs plus fixture files, the four behaviours tasks.md's
#           T023 line names: (1) a missing record's stage is the literal
#           `UNMEASURED: <instrument>`, never a number; (2) an empty window
#           reports "no data in window [from, to]"; (3) a golden fixture using
#           ATM-953's REAL hand-verified item_history rows; (4) a negative
#           control -- an item with every instrument present yields zero
#           `UNMEASURED` tokens.
#
# THE GAP (verified directly, 2026-09-28 against git HEAD
# ada22d2778276b15e891e263b6243e8129d824a1): plan.md's Project Structure
# (line 174) names `cycle_report.py` under
# `constitution/scripts/fastcycle/cycle/` -- "FR-001 cycle records,
# UNMEASURED rule, touch/wait (T-A09)". `constitution/scripts/fastcycle/`
# today contains only `lib/` (fc_common.py, fc_common.sh, host_guard.sh),
# `tests/`, `run_all.sh` and `check_deps.sh` -- there is no `cycle/`
# subdirectory at all, so neither `cycle_report.py` nor its sibling
# `select_sample.py`/`baseline_replay.sh` (T043, a different later task,
# see sibling test_baseline_replay_red.sh) exist. tasks.md's own T041 line
# ("Implement `constitution/scripts/fastcycle/cycle/cycle_report.py` per
# contract cycle-time-report-cli ... until T023 is GREEN") names the
# implementer explicitly: a LATER, SEPARATE task from this one.
#
# Producer≠Verifier (§11.4.240): this file is authored at the RED step
# (T023); T041's implementation of cycle_report.py is a separate, later
# task -- this file's author never implements it.
#
# §11.4.273 control needle (this file's own absence-detection mechanism):
# before trusting "cycle/cycle_report.py is absent" as a finding, prove the
# plain `[ -f PATH ]` relative-path check genuinely resolves paths from this
# script's real location, by first confirming a KNOWN-PRESENT sibling
# (lib/fc_common.py, used throughout this suite -- see
# test_baseline_replay_red.sh, test_fc_common_red.sh) resolves true through
# the identical relative-path construction. A second, independent §11.4.273
# needle is run live against the REAL tracker DB for the golden-ATM-953
# fixture (below): it proves the DB reader sees a known-present closure
# event (ATM-953's real `Fixed` row) and does NOT see a fabricated id --
# exactly the CT-009 needle contract cycle_report.py must itself implement,
# demonstrated here as a live, re-runnable proof rather than a frozen claim.
#
# §11.4.6 (no-guessing): the golden_atm953 fixture supplies ONLY the real,
# citable item_history rows + one corroborating git commit found for ATM-953
# in this pass. It does NOT fabricate a full 11-stage hand-verified timeline
# -- that full per-stage hand-verification (git log / builds.tsv / qa-results
# mtimes / agent_registry.jsonl cross-referenced against every one of the 11
# data-model.md §1.1 stages) is tasks.md's own T042, a SEPARATE LATER task
# in this same User Story ("Hand-verify the stage figures of ≥3 items
# (ATM-953 plus two more) ... store the diff under
# qa-results/fastcycle/us1/handverify/"). The fixture's own
# "honest_gap_deferred_to_T042" block names exactly which of the 11 stages
# have no citable source in this pass.
#
# STATUS (corrected 2026-09-28, T023 functional-testing-gap remediation):
# this file's original four "NOT YET IMPLEMENTED" contract-stub blocks
# (missing_record, empty_window, golden_atm953, negative_control_all_present)
# printed prose describing what T041's implementer needed to build, but
# never actually INVOKED cycle_report.py against any of the four fixtures
# and diffed the real output against each fixture's own documented expected
# value -- a real functional-testing gap: T041 (cycle/cycle_report.py) had
# genuinely landed and been independently reviewed GO (two rounds), yet
# this test file still exited 0 without ever exercising it. This is the
# exact "stale contract-stub-left-as-prose defect class" this suite already
# fixed one level up, at the presence-check level, in the "post-T036-review
# remediation" note further below and in the SIBLING file
# test_baseline_replay_red.sh's own 2026-09-28 correction. Fixed here by
# independently re-verifying, then converting, each of the four stubs into
# a real, gating, exact-JSON-match assertion (never heuristic) against the
# tool's actual output. Two self-validation control needles
# (§11.4.107(10)/§11.4.201(1)) are woven in, mirroring T024's golden-good/
# golden-bad technique -- neither mutates any real file on disk, so nothing
# needs restoring afterward: (1) negative_control_all_present's real,
# fully-measured 'build' stage is cross-compared against missing_record's
# UNMEASURED expected 'build' stage and MUST be reported unequal, proving
# the exact-match comparator used for check 1/4 can genuinely detect a
# mismatch (this exact opposite-verdicts pairing is what
# negative_control_all_present's own fixture docstring already asks for);
# (2) a window independently confirmed (live, 2026-09-28) to contain real
# closure events is run through the same --window-json path as check 2/4
# and MUST NOT be reported NO_DATA_IN_WINDOW, proving that check can
# genuinely distinguish empty from non-empty rather than rubber-stamping
# the empty state.
#
# Usage : bash test_cycle_report_red.sh   Exit 0 = every real assertion below
#         (both original control needles, fixture presence, the four
#         exact-match contract checks against cycle_report.py's real output,
#         and the two self-validation control needles) held.
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
FIXDIR="$FC/tests/fixtures/cycle_report"
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

# --- (1) Absence check: cycle_report.py ---
# Note: `$FC/cycle/` itself MAY exist as an empty scaffold directory (a bare
# `.gitkeep` placeholder, e.g. from earlier concurrent scaffolding work on a
# SIBLING file in this same directory) without that meaning T041/T043 have
# landed -- a directory-existence check alone would be a §11.4.201
# false-positive refusal (flagging a condition that is not the real one).
# The load-bearing check is content: does the directory hold any real *.py
# file at all, and specifically cycle_report.py?
CYCLE_DIR="$FC/cycle"
CYCLE_REPORT="$FC/cycle/cycle_report.py"
# NOTE (post-T036-review remediation, 2026-09-28, §11.4.1): T041 has since
# LANDED and been independently reviewed GO (two rounds) -- these two
# precondition checks are RETAINED (never deleted outright, they still have
# real regression-detection value: a future accidental deletion of
# cycle_report.py would be a genuine defect worth catching), but their
# POLARITY is flipped to match the tool's now-permanent presence. This
# mirrors the exact defect class an independent Opus-xhigh review found in
# the SIBLING file test_dispatch_stamp_red.sh (T036): a "NOT ok ... now
# exists -- DELETE this" assertion left un-flipped after its guarded tool
# landed silently converts `constitution/scripts/fastcycle/tests/run_all.sh`
# (the project's designated test runner, tasks.md:34) into reporting FAIL
# for an otherwise fully-correct, GO-reviewed, committed tool -- exactly the
# §11.4.1 "a test that fails for a script-internal reason, not a genuine
# product defect, is as misleading as a PASS-bluff" class. Fixed here on
# discovery of the same pattern across sibling files, not merely in T036.
if [ -d "$CYCLE_DIR" ]; then
  py_count=$(find "$CYCLE_DIR" -maxdepth 1 -name '*.py' | wc -l)
  if [ "$py_count" -gt 0 ]; then
    echo "ok $CYCLE_DIR now contains $py_count *.py file(s) -- T041/T043 has"
    echo "   landed (expected, permanent state since 2026-09-28)"
  else
    echo "NOT ok $CYCLE_DIR exists but holds no *.py file -- T041 was"
    echo "     reviewed GO and committed; a regression removed cycle_report.py"
    failx
  fi
else
  echo "NOT ok $CYCLE_DIR is absent -- T041 was reviewed GO and committed;"
  echo "     a regression removed the whole cycle/ directory"
  failx
fi
if [ -f "$CYCLE_REPORT" ]; then
  echo "ok cycle/cycle_report.py exists -- T041 has landed + is GO-reviewed"
  echo "   (expected, permanent state since 2026-09-28). The four fixture"
  echo "   directories under tests/fixtures/cycle_report/ are the real"
  echo "   functional tests to run against it (see verify_t041.sh)."
else
  echo "NOT ok cycle/cycle_report.py is absent -- T041 was reviewed GO and"
  echo "     committed; a regression removed the cycle-time report generator"
  failx
fi

# --- Fixture directories present ---
for d in missing_record empty_window golden_atm953 negative_control_all_present; do
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

# --- §11.4.273 control needle #2: live proof of the CT-009 needle contract ---
# (independent of the frozen claims recorded in golden_atm953/tracker_export.json;
# re-run here, live, against the real tracker DB, so this file's own claim
# about ATM-953's real Fixed event is never a stale assertion.)
if ! command -v sqlite3 >/dev/null 2>&1; then
  echo "NOT ok sqlite3 not on PATH -- cannot run the live CT-009 needle proof;"
  echo "     this is an environment gap, not a finding about cycle_report.py"
  failx
elif [ ! -f "$DB" ]; then
  echo "NOT ok tracker DB not found at $DB -- cannot run the live CT-009 needle proof"
  failx
else
  fixed_row=$(sqlite3 -readonly "$DB" \
    "SELECT event_type || '|' || on_date FROM item_history WHERE atm_id='ATM-953' AND event_type='Fixed' AND on_date='2026-07-28';" 2>&1)
  fabricated_row=$(sqlite3 -readonly "$DB" \
    "SELECT atm_id FROM items WHERE atm_id='ATM-99999-NEGATIVE-CONTROL';" 2>&1)
  if [ "$fixed_row" = "Fixed|2026-07-28" ]; then
    echo "ok control needle #2a (known-present): the live tracker DB genuinely"
    echo "   contains ATM-953's real Fixed/2026-07-28 closure event -- this is"
    echo "   the exact CT-009 default needle item cycle_report.py must itself check"
  else
    echo "NOT ok control needle #2a (known-present) FAILED: expected"
    echo "     'Fixed|2026-07-28' for ATM-953's Fixed row, got: '$fixed_row'."
    echo "     Either the tracker DB changed, or this test's query is wrong --"
    echo "     either way the golden_atm953 fixture's claims need re-verifying."
    failx
  fi
  if [ -z "$fabricated_row" ]; then
    echo "ok control needle #2b (known-absent): a fabricated id"
    echo "   (ATM-99999-NEGATIVE-CONTROL) genuinely returns zero rows against"
    echo "   the live items table -- proving the DB-lookup mechanism does not"
    echo "   false-match on an id that was never registered"
  else
    echo "NOT ok control needle #2b (known-absent) FAILED: fabricated id"
    echo "     ATM-99999-NEGATIVE-CONTROL unexpectedly returned a row:"
    echo "     '$fabricated_row' -- an item with this id now exists for real,"
    echo "     or this test's assumption about it is stale."
    failx
  fi
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo
echo "=== T041 contract check 1/4: missing record -> UNMEASURED, never a number (FR-001, CT-002, CT-004) ==="
MR_OUT="$TMP/missing_record.json"
MR_ERR="$TMP/missing_record.err"
if [ -f "$CYCLE_REPORT" ]; then
  python3 "$CYCLE_REPORT" --as-of 2026-09-28 \
    --tracker-export "$FIXDIR/missing_record/tracker_export.json" \
    --out "$MR_OUT" >"$MR_ERR" 2>&1
  MR_RC=$?
  if [ "$MR_RC" = 0 ] && [ -f "$MR_OUT" ]; then
    MR_MATCH="$(python3 -c "
import json
actual = json.load(open('$MR_OUT'))['records'][0]
stage = next(s for s in actual['stages'] if s['stage'] == 'build')
expected = json.load(open('$FIXDIR/missing_record/tracker_export.json'))['expected_stage_ct002_ct004']
print(stage == expected)
" 2>&1)"
    if [ "$MR_MATCH" = "True" ]; then
      echo "ok cycle_report.py --tracker-export missing_record: the 'build' stage"
      echo "   EXACTLY matches the fixture's own expected_stage_ct002_ct004 (start/"
      echo "   end/elapsed all the literal token UNMEASURED, plus the exact CT-002"
      echo "   default missing_instrument string) -- never a number, never 0, never"
      echo "   interpolated (CT-004, data-model.md V-CR-2). Paired mutation T013/T027"
      echo "   ('default a missing stage to 0') is caught: this exact-match"
      echo "   assertion fails the instant elapsed/start/end stop being UNMEASURED."
    else
      echo "NOT ok cycle_report.py --tracker-export missing_record: the 'build'"
      echo "     stage did NOT exactly match the fixture's expected_stage_ct002_ct004"
      echo "     (comparator result: '$MR_MATCH'); actual: $(python3 -c "
import json
a = json.load(open('$MR_OUT'))['records'][0]
print(json.dumps(next(s for s in a['stages'] if s['stage'] == 'build')))
" 2>&1)"
      failx
    fi
  else
    echo "NOT ok cycle_report.py --tracker-export missing_record invocation failed"
    echo "     (rc=$MR_RC) or produced no output file -- $(cat "$MR_ERR" 2>/dev/null)"
    failx
  fi
else
  echo "NOT ok contract check 1/4 SKIPPED: cycle_report.py not present (see presence check above)"
  failx
fi

echo
echo "=== T041 contract check 2/4: empty window -> 'no data in window [from, to]' (CT-008, V-CR-3) ==="
EW_OUT="$TMP/empty_window.json"
EW_ERR="$TMP/empty_window.err"
if [ -f "$CYCLE_REPORT" ]; then
  python3 "$CYCLE_REPORT" --as-of 2026-09-28 \
    --window-json "$FIXDIR/empty_window/window.json" \
    --out "$EW_OUT" >"$EW_ERR" 2>&1
  EW_RC=$?
  if [ "$EW_RC" = 0 ] && [ -f "$EW_OUT" ]; then
    EW_MATCH="$(python3 -c "
import json
actual = json.load(open('$EW_OUT'))
expected = json.load(open('$FIXDIR/empty_window/window.json'))['expected_body_ct008']
print(actual.get('state') == expected['state'] and actual.get('window') == expected['window'])
" 2>&1)"
    if grep -qF "no data in window [2020-01-01, 2020-01-02]" "$EW_ERR"; then
      EW_MSG_OK=True
    else
      EW_MSG_OK=False
    fi
    if [ "$EW_MATCH" = "True" ] && [ "$EW_MSG_OK" = "True" ]; then
      echo "ok cycle_report.py --window-json empty_window: exit 0 (an honest empty"
      echo "   result is not a failure, CT-008), body {state,window} EXACTLY matches"
      echo "   fixture's expected_body_ct008 (state=NO_DATA_IN_WINDOW, literal bounds"
      echo "   [2020-01-01, 2020-01-02], never an ellipsis, never a zero-valued"
      echo "   statistic), AND the human-readable message carries the task line's"
      echo "   exact phrasing 'no data in window [2020-01-01, 2020-01-02]'."
    else
      echo "NOT ok cycle_report.py --window-json empty_window: body/message did NOT"
      echo "     exactly match CT-008 (body_match='$EW_MATCH' msg_ok='$EW_MSG_OK')"
      echo "     actual body: $(cat "$EW_OUT" 2>/dev/null)"
      echo "     stderr: $(cat "$EW_ERR" 2>/dev/null)"
      failx
    fi
  else
    echo "NOT ok cycle_report.py --window-json empty_window invocation failed"
    echo "     (rc=$EW_RC, expected 0 -- an empty window is honest, not a failure)"
    echo "     -- $(cat "$EW_ERR" 2>/dev/null)"
    failx
  fi
else
  echo "NOT ok contract check 2/4 SKIPPED: cycle_report.py not present (see presence check above)"
  failx
fi

# Self-validation control needle (§11.4.107(10)/§11.4.201(1)) for check 2/4:
# a window independently confirmed (live, 2026-09-28) to contain real
# closure events, run through the SAME --window-json code path, MUST NOT be
# reported NO_DATA_IN_WINDOW -- proving this check can genuinely distinguish
# empty from non-empty rather than rubber-stamping the empty state for any
# input (mirrors T024's golden-bad gate-cmd technique; nothing on disk is
# mutated, so nothing needs restoring).
if [ -f "$CYCLE_REPORT" ]; then
  WIDE_WINDOW="$TMP/wide_window.json"
  cat > "$WIDE_WINDOW" <<'JSON'
{"window": {"from": "2026-06-01", "to": "2026-09-28"}}
JSON
  WIDE_OUT="$TMP/wide_window_out.json"
  WIDE_ERR="$TMP/wide_window.err"
  python3 "$CYCLE_REPORT" --as-of 2026-09-28 --window-json "$WIDE_WINDOW" \
    --out "$WIDE_OUT" >"$WIDE_ERR" 2>&1
  WIDE_RC=$?
  if [ "$WIDE_RC" = 0 ] && [ -f "$WIDE_OUT" ]; then
    WIDE_STATE="$(python3 -c "import json; print(json.load(open('$WIDE_OUT')).get('state'))" 2>&1)"
    WIDE_NREC="$(python3 -c "import json; print(len(json.load(open('$WIDE_OUT')).get('records', [])))" 2>&1)"
    if [ "$WIDE_STATE" != "NO_DATA_IN_WINDOW" ] && [ "${WIDE_NREC:-0}" -gt 0 ] 2>/dev/null; then
      echo "ok control needle (empty-window discrimination): a window known to"
      echo "   contain real closure events (2026-06-01..2026-09-28, $WIDE_NREC real"
      echo "   records) is correctly NOT reported NO_DATA_IN_WINDOW -- check 2/4"
      echo "   above can therefore be trusted to genuinely distinguish empty from"
      echo "   non-empty (§11.4.201(1)/§11.4.273), not merely rubber-stamp the empty"
      echo "   state for any input."
    else
      echo "NOT ok control needle (empty-window discrimination) FAILED: a window"
      echo "     known to contain real closure events was reported state='$WIDE_STATE'"
      echo "     n_records='$WIDE_NREC' -- either the live tracker DB genuinely has no"
      echo "     closures in this range any more, or cycle_report.py's empty-window"
      echo "     detection is over-firing; either way check 2/4 above is UNTRUSTWORTHY"
      echo "     until this is resolved"
      failx
    fi
  else
    echo "NOT ok control needle (empty-window discrimination) SKIPPED: the wide-window"
    echo "     invocation itself failed (rc=$WIDE_RC) -- $(cat "$WIDE_ERR" 2>/dev/null)"
    failx
  fi
fi

echo
echo "=== T041 contract check 3/4: golden ATM-953 hand-verified stages (CT-009, task line) ==="
GA_OUT="$TMP/golden_atm953.json"
GA_ERR="$TMP/golden_atm953.err"
if [ -f "$CYCLE_REPORT" ]; then
  # This fixture is Shape-agnostic (no top-level "item"/"stages" key -- it
  # supplies REAL item_history rows for the REAL live-tracked item ATM-953,
  # not a --tracker-export synthetic fixture); the CT-009 default needle
  # item is exercised via --item against the LIVE tracker DB, matching the
  # fixture's own "_how_this_was_obtained" provenance (a live sqlite3 query
  # against the same DB, not a frozen replay).
  python3 "$CYCLE_REPORT" --as-of 2026-09-28 --item ATM-953 --out "$GA_OUT" >"$GA_ERR" 2>&1
  GA_RC=$?
  if [ "$GA_RC" = 0 ] && [ -f "$GA_OUT" ]; then
    GA_CHECK="$TMP/golden_atm953_check.json"
    GA_ALL_OK="$(python3 -c "
import json
actual = json.load(open('$GA_OUT'))['records'][0]
fx = json.load(open('$FIXDIR/golden_atm953/tracker_export.json'))
needle = fx['expected_ct009_needle_default']['known_present']
fixed_row = next(r for r in fx['item_history'] if r['event_type'] == 'Fixed')
ce = actual.get('closure_event') or {}
result = {
    'ok_item': actual['item_id'] == needle['atm_id'],
    'ok_event': ce.get('event_type') == needle['event_type'],
    'ok_date': ce.get('on_date') == needle['on_date'],
    'ok_evidence': ce.get('evidence_path') == fixed_row['evidence_path'],
    'ok_flagged': len(actual.get('data_quality_flags', [])) > 0,
    'closure_event': ce,
    'flags': actual.get('data_quality_flags'),
}
json.dump(result, open('$GA_CHECK', 'w'))
print(all(result[k] for k in ('ok_item', 'ok_event', 'ok_date', 'ok_evidence', 'ok_flagged')))
" 2>&1)"
    if [ "$GA_ALL_OK" = "True" ]; then
      GA_EVIDENCE="$(python3 -c "import json; print(json.load(open('$GA_CHECK'))['closure_event']['evidence_path'])" 2>&1)"
      GA_FLAGS="$(python3 -c "import json; print(json.load(open('$GA_CHECK'))['flags'])" 2>&1)"
      echo "ok cycle_report.py --item ATM-953 (live tracker DB): closure_event"
      echo "   EXACTLY matches the fixture's expected_ct009_needle_default"
      echo "   (item_id=ATM-953, event_type=Fixed, on_date=2026-07-28,"
      echo "   evidence_path=$GA_EVIDENCE), AND the item carries >=1 real CT-005"
      echo "   data-quality flag ($GA_FLAGS) -- the Reopened row's on_date/"
      echo "   created_at discrepancy documented in the fixture's"
      echo "   'data_quality_observation_not_fabricated' block is not silently"
      echo "   dropped. §11.4.6 honest boundary preserved: this does not assert a"
      echo "   full 11-stage hand-verified timeline (T042's own separate scope)."
    else
      echo "NOT ok cycle_report.py --item ATM-953: closure_event or data-quality"
      echo "     flags did NOT match the fixture's CT-009 needle claim -- $(cat "$GA_CHECK" 2>/dev/null)"
      failx
    fi
  else
    echo "NOT ok cycle_report.py --item ATM-953 invocation failed (rc=$GA_RC) --"
    echo "     $(cat "$GA_ERR" 2>/dev/null)"
    failx
  fi
else
  echo "NOT ok contract check 3/4 SKIPPED: cycle_report.py not present (see presence check above)"
  failx
fi

echo
echo "=== T041 contract check 4/4: negative control -- every instrument present -> zero UNMEASURED (§11.4.201(1)) ==="
NC_OUT="$TMP/negative_control.json"
NC_ERR="$TMP/negative_control.err"
if [ -f "$CYCLE_REPORT" ]; then
  python3 "$CYCLE_REPORT" --as-of 2026-09-28 \
    --tracker-export "$FIXDIR/negative_control_all_present/tracker_export.json" \
    --out "$NC_OUT" >"$NC_ERR" 2>&1
  NC_RC=$?
  if [ "$NC_RC" = 0 ] && [ -f "$NC_OUT" ]; then
    NC_UNMEASURED_COUNT=$(grep -o "UNMEASURED" "$NC_OUT" | wc -l)
    NC_MISSING_INSTR_COUNT=$(grep -o "missing_instrument" "$NC_OUT" | wc -l)
    NC_FLAG_COUNT="$(python3 -c "import json; print(len(json.load(open('$NC_OUT'))['records'][0]['data_quality_flags']))" 2>&1)"
    if [ "$NC_UNMEASURED_COUNT" = 0 ] && [ "$NC_MISSING_INSTR_COUNT" = 0 ] && [ "$NC_FLAG_COUNT" = 0 ]; then
      echo "ok cycle_report.py --tracker-export negative_control_all_present: ZERO"
      echo "   occurrences of UNMEASURED, ZERO missing_instrument fields, ZERO"
      echo "   data-quality flags against a fully-populated 11-stage item --"
      echo "   matches fixture's expected_unmeasured_count=0 exactly (the"
      echo "   §11.4.201(1) false-positive guard: over-flagging present data is"
      echo "   exactly as defective as under-flagging a genuine gap)."
    else
      echo "NOT ok cycle_report.py --tracker-export negative_control_all_present:"
      echo "     over-flagged fully-present data (UNMEASURED=$NC_UNMEASURED_COUNT"
      echo "     missing_instrument=$NC_MISSING_INSTR_COUNT flags=$NC_FLAG_COUNT, all"
      echo "     must be 0)"
      failx
    fi
  else
    echo "NOT ok cycle_report.py --tracker-export negative_control_all_present"
    echo "     invocation failed (rc=$NC_RC) -- $(cat "$NC_ERR" 2>/dev/null)"
    failx
  fi
else
  echo "NOT ok contract check 4/4 SKIPPED: cycle_report.py not present (see presence check above)"
  failx
fi

# Self-validation control needle (§11.4.107(10)/§11.4.201(1)) for check 1/4:
# fixture negative_control_all_present's own docstring states these two
# fixtures MUST produce OPPOSITE UNMEASURED verdicts on the same test
# harness. Prove the exact-match comparator used in check 1/4 above can
# genuinely detect a mismatch by cross-comparing negative_control's REAL,
# fully-measured 'build' stage against missing_record's expected (UNMEASURED)
# 'build' stage -- if the comparator reported these EQUAL, check 1/4's PASS
# would be worthless (a rubber-stamp comparator). Mirrors T024's golden-bad
# gate-cmd technique; these are two independently-generated REAL tool
# outputs being cross-compared, nothing on disk is mutated or corrupted, so
# nothing needs restoring afterward.
if [ -f "$CYCLE_REPORT" ] && [ -f "$MR_OUT" ] && [ -f "$NC_OUT" ]; then
  CROSS_MATCH="$(python3 -c "
import json
mr_expected = json.load(open('$FIXDIR/missing_record/tracker_export.json'))['expected_stage_ct002_ct004']
nc_actual = json.load(open('$NC_OUT'))['records'][0]
nc_build = next(s for s in nc_actual['stages'] if s['stage'] == 'build')
print(nc_build == mr_expected)
" 2>&1)"
  if [ "$CROSS_MATCH" = "False" ]; then
    echo "ok control needle (comparator discrimination): negative_control's REAL,"
    echo "   fully-measured 'build' stage correctly does NOT equal missing_record's"
    echo "   expected UNMEASURED 'build' stage -- the exact-match comparator used"
    echo "   in check 1/4 can genuinely detect a mismatch, so its PASS above is"
    echo "   trustworthy (the two fixtures produce the opposite verdicts their own"
    echo "   docstrings require)."
  else
    echo "NOT ok control needle (comparator discrimination) FAILED: negative_control's"
    echo "     real, fully-measured 'build' stage was reported EQUAL to"
    echo "     missing_record's UNMEASURED expected stage (comparator result:"
    echo "     '$CROSS_MATCH') -- the comparator used in check 1/4 is a rubber"
    echo "     stamp and its PASS above cannot be trusted"
    failx
  fi
else
  echo "NOT ok control needle (comparator discrimination) SKIPPED: a prerequisite"
  echo "     output is missing (cycle_report.py present=$([ -f "$CYCLE_REPORT" ] && echo yes || echo no),"
  echo "     missing_record output present=$([ -f "$MR_OUT" ] && echo yes || echo no),"
  echo "     negative_control output present=$([ -f "$NC_OUT" ] && echo yes || echo no))"
  failx
fi

echo
echo "=== N3 fix (T048 round-2 review): ct_determinism -- --determinism-check must ==="
echo "=== hold on real production-mode data (C-003) ==="
# Root cause verified directly (2026-09-30) BEFORE fixing: cycle_report.py's
# full-sampling-mode selection built its `ids`/`keep` candidate sets as
# Python `set`s and iterated them RAW -- `for atm_id in ids:` seeded
# `clusters`' dict-insertion order (and therefore `excluded[]`'s element
# order) with Python's per-process, PYTHONHASHSEED-randomised str hashing.
# Reproduced live: two direct invocations of the SAME command against the
# SAME DB state under PYTHONHASHSEED=1 vs PYTHONHASHSEED=42 produced
# DIFFERENT excluded[] orderings and DIFFERENT body_hash values. Fixed by
# sorting the base `ids` iteration (never a set's raw iteration order feeds
# output) -- this check exercises the REAL --determinism-check flag (C-003),
# which forks two real subprocesses that each pick their OWN random hash
# seed by default (no PYTHONHASHSEED override here), so a regression of this
# exact class would flip this check back to FAIL without any seed-forcing
# needed from this test.
if [ -f "$CYCLE_REPORT" ] && command -v sqlite3 >/dev/null 2>&1 && [ -f "$DB" ]; then
  DC_OUT="$TMP/ct_determinism.out"
  DC_JSON="$TMP/ct_determinism.json"
  python3 "$CYCLE_REPORT" --config x --as-of 2026-09-28 --window-days 90 \
    --determinism-check --out "$DC_JSON" >"$DC_OUT" 2>&1
  DC_RC=$?
  if [ "$DC_RC" = 0 ] && grep -qE '^cycle_report: deterministic \(body_hash=[0-9a-f]+\)$' "$DC_OUT"; then
    echo "ok ct_determinism: cycle_report.py --determinism-check (full production"
    echo "   mode, real tracker DB, real subprocess fork each with its own random"
    echo "   hash seed) exits 0 and reports a stable body_hash -- N3 fixed"
  else
    echo "NOT ok ct_determinism FAILED: --determinism-check rc=$DC_RC (expected 0)"
    echo "     -- $(cat "$DC_OUT" 2>/dev/null)"
    echo "     (N3 regression class: set-iteration-order-seeded excluded[]/body_hash"
    echo "     nondeterminism across independently-hash-seeded processes)"
    failx
  fi

  # Self-validation control needle (§11.4.107(10)/§11.4.201(1)): prove the
  # body_hash comparator is NOT a rubber-stamp that reports "equal" no
  # matter what -- two genuinely DIFFERENT selection windows run directly
  # (not through --determinism-check) MUST produce DIFFERENT body_hash
  # values. If this needle failed (hashes equal despite different real
  # content), check ct_determinism's PASS above would be worthless.
  DIFFWIN_A="$TMP/ct_determinism_diffwin_a.json"
  DIFFWIN_B="$TMP/ct_determinism_diffwin_b.json"
  python3 "$CYCLE_REPORT" --config x --as-of 2026-09-28 --window-days 90 --out "$DIFFWIN_A" >/dev/null 2>&1
  python3 "$CYCLE_REPORT" --config x --as-of 2026-09-28 --window-days 30 --out "$DIFFWIN_B" >/dev/null 2>&1
  if [ -f "$DIFFWIN_A" ] && [ -f "$DIFFWIN_B" ]; then
    DIFFWIN_DISTINCT="$(python3 -c "
import json
a = json.load(open('$DIFFWIN_A')).get('body_hash')
b = json.load(open('$DIFFWIN_B')).get('body_hash')
print(a != b)
" 2>&1)"
    if [ "$DIFFWIN_DISTINCT" = "True" ]; then
      echo "ok control needle (ct_determinism comparator discrimination): two"
      echo "   genuinely different windows (90d vs 30d) produce DIFFERENT"
      echo "   body_hash values -- the body_hash mechanism checked by"
      echo "   ct_determinism above is real content-sensitive, not a rubber stamp"
    else
      echo "NOT ok control needle (ct_determinism comparator discrimination) FAILED:"
      echo "     a 90-day and a 30-day window produced the SAME body_hash --"
      echo "     ct_determinism's PASS above cannot be trusted (comparator_result="
      echo "     '$DIFFWIN_DISTINCT')"
      failx
    fi
  else
    echo "NOT ok control needle (ct_determinism comparator discrimination) SKIPPED:"
    echo "     one or both window invocations failed to produce output"
    failx
  fi
else
  echo "NOT ok ct_determinism SKIPPED: cycle_report.py/sqlite3/tracker DB not"
  echo "     available (see presence checks above)"
  failx
fi

exit $fail
