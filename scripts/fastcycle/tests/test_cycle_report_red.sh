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
# CYCLE_REPORT_UNDER_TEST lets the R5 paired-mutation harness (end of this
# file) re-run EVERY check below against a mutated copy of the tool.
CYCLE_REPORT="${CYCLE_REPORT_UNDER_TEST:-$FC/cycle/cycle_report.py}"
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
cp = next(s for s in actual['stages'] if s['stage'] == 'commit_push')
result = {
    'ok_item': actual['item_id'] == needle['atm_id'],
    'ok_event': ce.get('event_type') == needle['event_type'],
    'ok_date': ce.get('on_date') == needle['on_date'],
    'ok_evidence': ce.get('evidence_path') == fixed_row['evidence_path'],
    # R5 I7 (T048 restart round 1): the previous 'len(flags) > 0' could not
    # tell WHICH flag fired. Exact set, hand-derived 2026-10-08 from the live
    # DB + git: row 869 (Reopened)
    # has on_date 07-28 but created_at 08-05 -> DATE_ONLY_RESOLUTION; commit
    # f1abb59's subject names ATM-953 AND ATM-954 -> COMMIT_ATTRIBUTION_BY_GREP;
    # every other CT-005 flag is absent (Opened->Fixed gap 2h16m, no duplicate
    # rows, Fixed precedes Reopened, items.status 'Reopened' after a Reopened
    # event is not a desync).
    'ok_flagged': sorted(actual.get('data_quality_flags', [])) == ['COMMIT_ATTRIBUTION_BY_GREP', 'DATE_ONLY_RESOLUTION'],
    # commit_push: the ONLY commit whose SUBJECT names ATM-953 is
    # f1abb59eac85 (2026-07-28T14:28:49+05:00, author == committer); the
    # other five --grep hits name it in the body only.
    'ok_commit_push': {k: v for k, v in cp.items() if k != 'push_missing_instrument'} == {
        'stage': 'commit_push',
        'start': {'value': '2026-07-28T14:28:49+05:00', 'time_source': 'git_author',
                  'evidence_path': 'git_log#f1abb59eac851e560a49b9fb4465297f84d66bae'},
        'end': {'value': '2026-07-28T14:28:49+05:00', 'time_source': 'git_committer',
                'evidence_path': 'git_log#f1abb59eac851e560a49b9fb4465297f84d66bae'},
        'elapsed': 0, 'push_instant': 'UNMEASURED',
    } and 'push' in cp.get('push_missing_instrument', ''),
    'ok_reopen': actual.get('reopen_count') == 1 and actual.get('selection_reason') == 'reopened-in-window',
    'closure_event': ce,
    'flags': actual.get('data_quality_flags'),
    'commit_push': cp,
}
json.dump(result, open('$GA_CHECK', 'w'))
print(all(result[k] for k in ('ok_item', 'ok_event', 'ok_date', 'ok_evidence', 'ok_flagged', 'ok_commit_push', 'ok_reopen')))
" 2>&1)"
    if [ "$GA_ALL_OK" = "True" ]; then
      GA_EVIDENCE="$(python3 -c "import json; print(json.load(open('$GA_CHECK'))['closure_event']['evidence_path'])" 2>&1)"
      GA_FLAGS="$(python3 -c "import json; print(json.load(open('$GA_CHECK'))['flags'])" 2>&1)"
      echo "ok cycle_report.py --item ATM-953 (live tracker DB): closure_event"
      echo "   EXACTLY matches the fixture's expected_ct009_needle_default"
      echo "   (item_id=ATM-953, event_type=Fixed, on_date=2026-07-28,"
      echo "   evidence_path=$GA_EVIDENCE), the EXACT CT-005 flag set $GA_FLAGS,"
      echo "   the exact commit_push stage (f1abb59, elapsed 0, push UNMEASURED) and"
      echo "   reopen_count 1 -- the Reopened row's on_date/"
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
    # V2-9 (T048 restart round 2): this Shape-A fixture carries NO
    # item_history, so no data-quality flag was ever evaluated; asserting
    # "zero flags" here could not fail. The honest observable is that the
    # record SAYS it evaluated nothing (data_quality_flags_evaluated: false,
    # with an empty list). Flag discrimination itself is proven on the
    # reconstruction path by the R5 I7 Shape-B control below.
    NC_FLAGS="$(python3 -c "
import json, sys
r = json.load(open(sys.argv[1]))['records'][0]
print('%s|%s' % (r.get('data_quality_flags_evaluated'), len(r['data_quality_flags'])))
" "$NC_OUT" 2>&1)"
    if [ "$NC_UNMEASURED_COUNT" = 0 ] && [ "$NC_MISSING_INSTR_COUNT" = 0 ] && [ "$NC_FLAGS" = "False|0" ]; then
      echo "ok cycle_report.py --tracker-export negative_control_all_present: ZERO"
      echo "   occurrences of UNMEASURED and ZERO missing_instrument fields against a"
      echo "   fully-populated 11-stage item (expected_unmeasured_count=0, the"
      echo "   §11.4.201(1) false-positive guard); the fixture has no item_history, so"
      echo "   the record states data_quality_flags_evaluated=false (never a"
      echo "   presented-as-measured 'zero flags')."
    else
      echo "NOT ok cycle_report.py --tracker-export negative_control_all_present:"
      echo "     UNMEASURED=$NC_UNMEASURED_COUNT missing_instrument=$NC_MISSING_INSTR_COUNT"
      echo "     (both must be 0); flags evaluated|count=$NC_FLAGS (must be False|0)"
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
echo "=== R5 I7 (T048 restart round 1): check 4/4 had no negative control on the RECONSTRUCTION path ==="
# check 4/4's fixture is Shape A (pre-computed stages, no item_history), so
# its "ZERO data-quality flags" assertion could never fail: Shape A had no
# history to evaluate. This drives the Shape-B RECONSTRUCTION path (the same
# flag code --item/full mode use) with a clean, fully consistent item ->
# EXACTLY zero flags; then two single-defect variants of the SAME item must
# raise EXACTLY their one flag (discrimination: the zero is not a blind zero).
mk_shape_b() {  # $1 out, $2 status, $3 extra history row (json or empty)
  cat > "$1" <<JSON
{"item": {"atm_id": "ATM-90777", "type": "Task", "status": "$2"},
 "item_history": [
   {"event_type": "Opened", "by": "User", "on_date": "2026-08-01", "created_at": "2026-08-01T08:00:00Z"},
   {"event_type": "Completed", "by": "AI", "on_date": "2026-08-02", "created_at": "2026-08-02T09:00:00Z", "evidence_path": "qa/x/y.log"}$3
 ],
 "git_log": [{"sha": "bbbbbbb2222222222222222222222222222222b", "author_date": "2026-08-02T08:00:00Z",
              "committer_date": "2026-08-02T08:30:00Z", "message": "feat(ATM-90777): done"}]}
JSON
}
mk_shape_b "$TMP/nb_clean.json" "Completed (→ Fixed.md)" ""
mk_shape_b "$TMP/nb_dup.json" "Completed (→ Fixed.md)" ',
   {"event_type": "Completed", "by": "AI", "on_date": "2026-08-02", "created_at": "2026-08-02T09:00:00Z", "evidence_path": "qa/x/y.log"}'
mk_shape_b "$TMP/nb_desync.json" "Queued" ""
nb_res=""
for v in clean dup desync; do
  python3 "$CYCLE_REPORT" --as-of 2026-09-28 --tracker-export "$TMP/nb_$v.json" \
    --out "$TMP/nb_${v}_out.json" >"$TMP/nb_$v.err" 2>&1
  nb_res="$nb_res $v=$(python3 -c "import json,sys; print(','.join(json.load(open(sys.argv[1]))['records'][0]['data_quality_flags']) or 'NONE')" "$TMP/nb_${v}_out.json" 2>/dev/null || echo ERR)"
done
if [ "$nb_res" = " clean=NONE dup=DUPLICATE_HISTORY_ROWS desync=STATUS_DESYNC" ]; then
  ok_msg="ok R5 I7 Shape-B negative control: clean item -> zero flags; duplicate row -> exactly"
  echo "$ok_msg"
  echo "   DUPLICATE_HISTORY_ROWS; Queued status after a closure -> exactly STATUS_DESYNC"
else
  echo "NOT ok R5 I7 Shape-B negative control/discrimination: got$nb_res"
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
  # body_hash comparator is content-sensitive. R5 I7 (T048 restart round 1):
  # the previous needle compared a 90-day and a 30-day window, which differ
  # trivially because window.from is itself part of the hashed body -- it
  # could not show that the hash moves with CONTENT. Here the arguments are
  # IDENTICAL and only the DB content differs: the synthetic scenario's
  # "full" DB vs its "cut" DB (rows after 2026-08-23 removed), both read at
  # as-of 2026-09-30, a date AFTER those rows -- so the bodies must differ.
  SCEN="$TMP/scen"
  for m in full cut; do
    [ -d "$SCEN/$m" ] || python3 "$FIXDIR/build_asof_scenario.py" "$SCEN/$m" "$m" >/dev/null 2>&1
    python3 "$CYCLE_REPORT" --config x --as-of 2026-09-30 --window-days 120 --min-per-type 2 \
      --bulk-threshold 3 --needle-present-id ATM-953 --needle-fixed-on-date 2026-07-01 \
      --db-path "$SCEN/$m/db.sqlite" --repo-root "$SCEN/$m/repo" --out "$TMP/content_$m.json" >/dev/null 2>&1
  done
  if [ -f "$TMP/content_full.json" ] && [ -f "$TMP/content_cut.json" ]; then
    CONTENT_DISTINCT="$(python3 -c "
import json, sys
a = json.load(open(sys.argv[1])); b = json.load(open(sys.argv[2]))
print(a['body_hash'] != b['body_hash'] and a['window'] == b['window'])
" "$TMP/content_full.json" "$TMP/content_cut.json" 2>&1)"
    if [ "$CONTENT_DISTINCT" = "True" ]; then
      echo "ok control needle (ct_determinism comparator discrimination): identical"
      echo "   arguments + identical window, different DB content -> DIFFERENT body_hash"
      echo "   (the hash is content-sensitive, not merely window-sensitive)"
    else
      echo "NOT ok control needle (ct_determinism comparator discrimination) FAILED:"
      echo "     different DB content under identical arguments gave '$CONTENT_DISTINCT'"
      failx
    fi
  else
    echo "NOT ok control needle (ct_determinism comparator discrimination) SKIPPED:"
    echo "     one or both scenario invocations failed to produce output"
    failx
  fi
else
  echo "NOT ok ct_determinism SKIPPED: cycle_report.py/sqlite3/tracker DB not"
  echo "     available (see presence checks above)"
  failx
fi

# ===========================================================================
# R5 regression checks (T048 restart round 1, docs/qa/t048_restart_round1_
# 20261008/R5_cycle_report_sampling.md). Every check drives the REAL
# cycle_report.py CLI against the deterministic synthetic scenario built by
# fixtures/cycle_report/build_asof_scenario.py (its docstring lists every row
# and commit), except R5-C8 which repeats the reviewer's own experiment on a
# read-only snapshot of the live tracker DB.
#
# Hand-derived expectation for full-sampling mode, --as-of 2026-08-23
# --window-days 60 (=> [2026-06-24, 2026-08-23]) --min-per-type 2
# --bulk-threshold 3, only rows/commits dated <= as-of visible. Selection is
# select_sample.py's (T048 restart round 2, V2-2: ONE classifier + ONE walk;
# exclude first, then the most-recent 2 USABLE per type, excluded rows walked
# past are listed):
#   Bug   candidates by as-of closure created_at: 1003(06-25, highest row id)
#         < 300(06-30) < 953(07-01) < 1002(07-10) < 800(07-25) < 277(08-20)
#         < 310(08-23, ON the as-of day) -> sampled {ATM-310, ATM-277}
#   Task  walked most-recent first: 603/602/601 (07-20, shared dir qa/realbulk
#         -> bulk cluster of 3) listed-excluded; 504 (07-06 09:59, closure row
#         written 60 s BEFORE its Opened row -> NOT retroactive) and 503
#         (07-05 12:00) sampled
#   Feature ATM-700 retroactive (20 s) -> listed-excluded
#   reopened-in-window ATM-300 (06-24 = window.from) and ATM-800 (07-15)
#   records = 277, 300, 310, 503, 504, 601, 602, 603, 700, 800; excluded[] =
#         every excluded candidate = 601, 602, 603 (bulk), 700 (retroactive)
#   strata n (= usable taken): Bug 2, Task 2, Feature 0 (below_required)
#   ATM-277 commit_push = the ONE subject-match "fix ATM-277 part"
#           08-20T09:00Z -> 09:30Z = 1800000 ms ("ATM-2770 ..." is a token-
#           boundary trap, "chore: misc" names it only in the body, the
#           REBASED commit (author 08-22, committer 08-25) and the 09-20
#           follow-up are after as-of); reopen_count 0; flags []
#   ATM-310 commit_push 08-23T10:00Z -> 08-24T02:30+05:00 (= 08-23T21:30Z,
#           inside the as-of day in UTC) = 41400000 ms
#   ATM-800 commit_push earliest author 07-24T08:00Z -> latest COMMITTER
#           07-25T11:00Z (from the earlier-authored commit) = 97200000 ms;
#           reopen_count 1 (the duplicate Reopened row is deduplicated); flags
#           exactly [DUPLICATE_HISTORY_ROWS] -- NOT REOPEN_WITHOUT_PRIOR_CLOSURE
#   ATM-300 reopened-in-window (Reopened ON window.from), reopen_count 1, flags []
#   ATM-700 closure_event on_date 2026-08-01 (not the future 09-10 one);
#           flags exactly [RETROACTIVE_REGISTRATION]; excluded true
#   reopen block = closure/reopen_rate.py's own derivation over the WINDOW
#           population (15 items, as-of histories): Bug closed 7 / reopened 2
#           (300, 800), Task closed 7 / reopened 0, Feature ATM-700 excluded as
#           retroactive -> overall reopened 2, closed 14, rate round(2/14, 6)
#           = 0.142857, dedup_rows_removed 1, excluded_retroactive [ATM-700]
#   medians over NON-excluded records only (277, 300, 310, 503, 504, 800):
#           commit_push = median(1800000, 41400000, 97200000) = 41400000,
#           n_measured 3, n_total 6; medians_excluded_records = 601, 602,
#           603, 700
#   instrument_gaps commit_push: ONE entry, text with the item id replaced by
#           "{item_id}", items_affected [300, 503, 504, 601, 602, 603, 700]
# ===========================================================================
R5S="$TMP/r5"
R5_NEEDLE=(--needle-present-id ATM-953 --needle-fixed-event Fixed --needle-fixed-on-date 2026-07-01)
R5_COMMON=(--as-of 2026-08-23 --window-days 60 --min-per-type 2 --bulk-threshold 3)
for m in full cut; do
  python3 "$FIXDIR/build_asof_scenario.py" "$R5S/$m" "$m" >"$TMP/r5_build_$m.err" 2>&1 \
    || { echo "NOT ok R5 fixture build ($m) failed: $(cat "$TMP/r5_build_$m.err")"; failx; }
done
r5_run() {  # $1 = output tag, $2 = scenario (full|cut), rest = extra args
  local tag="$1" scen="$2"; shift 2
  python3 "$CYCLE_REPORT" "${R5_NEEDLE[@]}" --db-path "$R5S/$scen/db.sqlite" \
    --repo-root "$R5S/$scen/repo" --out "$TMP/r5_$tag.json" "$@" >"$TMP/r5_$tag.err" 2>&1
  echo $?
}

echo
echo "=== R5-C1 (B1): as-of freeze -- full vs cut scenario give the identical body (full-sampling AND --item) ==="
rc_full=$(r5_run full full --config x "${R5_COMMON[@]}")
rc_cut=$(r5_run cut cut --config x "${R5_COMMON[@]}")
rc_ifull=$(r5_run item_full full --as-of 2026-08-23 --window-days 60 --item ATM-277)
rc_icut=$(r5_run item_cut cut --as-of 2026-08-23 --window-days 60 --item ATM-277)
rc_i3full=$(r5_run item310_full full --as-of 2026-08-23 --window-days 60 --item ATM-310)
rc_i3cut=$(r5_run item310_cut cut --as-of 2026-08-23 --window-days 60 --item ATM-310)
c1="$(python3 - "$TMP" <<'PYEOF'
import json, os, sys
t = sys.argv[1]
out = []
for a, b in (("full", "cut"), ("item_full", "item_cut"), ("item310_full", "item310_cut")):
    pa, pb = (os.path.join(t, "r5_%s.json" % x) for x in (a, b))
    if not (os.path.exists(pa) and os.path.exists(pb)):
        out.append("%s/%s missing output" % (a, b))
        continue
    da, db = json.load(open(pa)), json.load(open(pb))
    if da["body_hash"] != db["body_hash"]:
        diff = [r["item_id"] for r in da.get("records", [])], [r["item_id"] for r in db.get("records", [])]
        out.append("%s!=%s (records %s vs %s)" % (a, b, diff[0], diff[1]))
print("SAME" if not out else "; ".join(out))
PYEOF
)"
if [ "$rc_full$rc_cut$rc_ifull$rc_icut$rc_i3full$rc_i3cut" = "000000" ] && [ "$c1" = "SAME" ]; then
  echo "ok R5-C1 rows and commits dated after --as-of (incl. a rebased commit) change nothing (full-sampling and --item bodies identical)"
else
  echo "NOT ok R5-C1 as-of leak: rc=$rc_full/$rc_cut/$rc_ifull/$rc_icut/$rc_i3full/$rc_i3cut $c1"
  failx
fi

echo
echo "=== R5-C2 (B1 + I3 + I6 + M8 + gaps): exact hand-derived full-sampling report ==="
c2="$(python3 - "$TMP/r5_full.json" <<'PYEOF'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception as e:
    print("no report: %s" % e)
    raise SystemExit
p = []
recs = {r["item_id"]: r for r in d.get("records", [])}
if sorted(recs) != ["ATM-277", "ATM-300", "ATM-310", "ATM-503", "ATM-504",
                    "ATM-601", "ATM-602", "ATM-603", "ATM-700", "ATM-800"]:
    p.append("records=%s" % sorted(recs))
if [e["item_id"] for e in d.get("excluded", [])] != ["ATM-601", "ATM-602", "ATM-603", "ATM-700"]:
    p.append("excluded=%s" % d.get("excluded"))
want_strata = {"Bug": (2, False), "Task": (2, False), "Feature": (0, True)}
got_strata = {t: (v.get("n"), v.get("below_required")) for t, v in d.get("strata", {}).items()}
if got_strata != want_strata:
    p.append("strata=%s expected %s" % (got_strata, want_strata))
def stage(r, name):
    return next(s for s in r["stages"] if s["stage"] == name)
def val(x):
    return x.get("value") if isinstance(x, dict) else x
want_cp = {"ATM-277": (1800000, "2026-08-20T09:00:00Z", "2026-08-20T09:30:00Z"),
           "ATM-310": (41400000, "2026-08-23T10:00:00Z", "2026-08-24T02:30:00+05:00"),
           "ATM-800": (97200000, "2026-07-24T08:00:00Z", "2026-07-25T11:00:00Z")}
for iid, exp in want_cp.items():
    r = recs.get(iid)
    if not r:
        continue
    cp = stage(r, "commit_push")
    got = (cp.get("elapsed"), val(cp.get("start")), val(cp.get("end")))
    if got != exp:
        p.append("%s commit_push=%s expected %s" % (iid, got, exp))
want = {"ATM-277": (0, "sampled-bug", [], "2026-08-20", False),
        "ATM-310": (0, "sampled-bug", [], "2026-08-23", False),
        "ATM-300": (1, "reopened-in-window", [], "2026-06-30", False),
        "ATM-800": (1, "reopened-in-window", ["DUPLICATE_HISTORY_ROWS"], "2026-07-25", False),
        "ATM-700": (0, "listed-excluded-feature", ["RETROACTIVE_REGISTRATION"], "2026-08-01", True),
        "ATM-602": (0, "listed-excluded-task", [], "2026-07-20", True),
        "ATM-504": (0, "sampled-task", [], "2026-07-06", False),
        "ATM-503": (0, "sampled-task", [], "2026-07-05", False)}
for iid, exp in want.items():
    r = recs.get(iid)
    if not r:
        continue
    got = (r.get("reopen_count"), r.get("selection_reason"), r.get("data_quality_flags"),
           (r.get("closure_event") or {}).get("on_date"), r.get("excluded"))
    if got != exp:
        p.append("%s (reopen_count, selection_reason, flags, closure on_date, excluded)=%s expected %s"
                 % (iid, got, exp))
ro = d.get("reopen", {})
want_ro = {"reopened": 2, "closed": 14, "rate": 0.142857, "dedup_rows_removed": 1}
if {k: ro.get(k) for k in want_ro} != want_ro:
    p.append("reopen=%s expected %s" % ({k: ro.get(k) for k in want_ro}, want_ro))
if [e.get("item_id") for e in ro.get("excluded_retroactive", [])] != ["ATM-700"]:
    p.append("reopen.excluded_retroactive=%s" % ro.get("excluded_retroactive"))
if ro.get("window") != {"from": "2026-06-24", "to": "2026-08-23"}:
    p.append("reopen.window=%s" % ro.get("window"))
med = d.get("medians", {}).get("overall", {}).get("commit_push", {})
if (med.get("value_ms"), med.get("n_measured"), med.get("n_total")) != (41400000, 3, 6):
    p.append("medians.overall.commit_push=%s" % med)
if d.get("medians_excluded_records") != ["ATM-601", "ATM-602", "ATM-603", "ATM-700"]:
    p.append("medians_excluded_records=%s" % d.get("medians_excluded_records"))
cp_gaps = [g for g in d.get("instrument_gaps", []) if g["stage"] == "commit_push"]
if len(cp_gaps) != 1 or cp_gaps[0]["items_affected"] != ["ATM-300", "ATM-503", "ATM-504", "ATM-601",
                                                         "ATM-602", "ATM-603", "ATM-700"] \
        or "{item_id}" not in cp_gaps[0]["missing_instrument"] or "ATM-503" in cp_gaps[0]["missing_instrument"]:
    p.append("instrument_gaps[commit_push]=%s" % cp_gaps)
print("PASS" if not p else " | ".join(p))
PYEOF
)"
if [ "$c2" = "PASS" ]; then
  echo "ok R5-C2 report equals the hand-derived expectation (shared selection, excluded, usable strata,"
  echo "   commit_push spans incl. non-UTC/as-of-day/latest-committer, flags, reopen block from"
  echo "   reopen_rate.py over the window population, medians over usable records, gaps)"
else
  echo "NOT ok R5-C2 $c2"
  failx
fi

echo
echo "=== R5-C3 (I4): CT-007 --hand-verified compares real figures and refuses an empty comparison ==="
cat > "$TMP/hv_good.json" <<'JSON'
[{"item_id": "ATM-277", "stage": "commit_push", "field": "elapsed", "expected_value": 1800000},
 {"item_id": "ATM-800", "stage": "commit_push", "field": "elapsed", "expected_value": 97200000},
 {"item_id": "ATM-503", "stage": "commit_push", "field": "elapsed", "expected_value": "UNMEASURED"}]
JSON
sed 's/1800000/1801000/' "$TMP/hv_good.json" > "$TMP/hv_bad.json"
cat > "$TMP/hv_ghost.json" <<'JSON'
[{"item_id": "ATM-1", "stage": "commit_push", "field": "elapsed", "expected_value": 1},
 {"item_id": "ATM-2", "stage": "commit_push", "field": "elapsed", "expected_value": 2},
 {"item_id": "ATM-3", "stage": "commit_push", "field": "elapsed", "expected_value": 3}]
JSON
python3 -c "
import json, sys
e = json.load(open(sys.argv[1])) + [{'item_id': 'ATM-4040', 'stage': 'commit_push', 'field': 'elapsed', 'expected_value': 1}]
json.dump(e, open(sys.argv[2], 'w'))
" "$TMP/hv_good.json" "$TMP/hv_partial.json"
printf '{"window": {"from": "2026-06-24", "to": "2026-08-23"}}\n' > "$TMP/hv_window.json"
hv_good=$(r5_run hv_good full --config x "${R5_COMMON[@]}" --hand-verified "$TMP/hv_good.json")
hv_bad=$(r5_run hv_bad full --config x "${R5_COMMON[@]}" --hand-verified "$TMP/hv_bad.json")
hv_ghost=$(r5_run hv_ghost full --config x "${R5_COMMON[@]}" --hand-verified "$TMP/hv_ghost.json")
hv_partial=$(r5_run hv_partial full --config x "${R5_COMMON[@]}" --hand-verified "$TMP/hv_partial.json")
hv_win=$(r5_run hv_win full --as-of 2026-08-23 --min-per-type 2 --window-json "$TMP/hv_window.json" --hand-verified "$TMP/hv_bad.json")
if [ "$hv_good" = 0 ] && [ "$hv_bad" = 1 ] && grep -q 'ATM-277' "$TMP/r5_hv_bad.err" \
   && grep -q 'commit_push' "$TMP/r5_hv_bad.err" && [ "$hv_ghost" = 1 ] && [ "$hv_partial" = 1 ] \
   && grep -q 'ATM-4040 is not in this report' "$TMP/r5_hv_partial.err" && [ "$hv_win" = 1 ]; then
  echo "ok R5-C3 golden-good exit 0; a 1 s mismatch exits 1 naming ATM-277/commit_push; three ids absent"
  echo "   from the report exit 1 (no empty comparison passes); 3 good + 1 absent exits 1 naming the"
  echo "   absent id; --window-json honours --hand-verified"
else
  echo "NOT ok R5-C3 rc good=$hv_good bad=$hv_bad ghost=$hv_ghost partial=$hv_partial window-json=$hv_win (want 0/1/1/1/1)"
  echo "     bad.err: $(tail -2 "$TMP/r5_hv_bad.err")"
  failx
fi

echo
echo "=== R5-C4 (I5): a failed git call is UNMEASURED-with-reason, never read as 'no commit' ==="
mkdir -p "$TMP/notarepo" "$TMP/fakegit"
printf '#!/bin/sh\necho "fatal: simulated failure" >&2\nexit 1\n' > "$TMP/fakegit/git"
chmod +x "$TMP/fakegit/git"
python3 "$CYCLE_REPORT" "${R5_NEEDLE[@]}" --db-path "$R5S/full/db.sqlite" --repo-root "$TMP/notarepo" \
  --as-of 2026-08-23 --item ATM-800 --out "$TMP/r5_norepo.json" >"$TMP/r5_norepo.err" 2>&1
PATH="$TMP/fakegit:$PATH" python3 "$CYCLE_REPORT" "${R5_NEEDLE[@]}" --db-path "$R5S/full/db.sqlite" \
  --repo-root "$R5S/full/repo" --as-of 2026-08-23 --item ATM-800 --out "$TMP/r5_fakegit.json" >"$TMP/r5_fakegit.err" 2>&1
r5_run nocommit full --as-of 2026-08-23 --item ATM-953 >/dev/null
c4="$(python3 - "$TMP" <<'PYEOF'
import json, os, sys
t = sys.argv[1]
def cp(tag):
    d = json.load(open(os.path.join(t, "r5_%s.json" % tag)))
    return next(s for s in d["records"][0]["stages"] if s["stage"] == "commit_push")
p = []
try:
    nr, fg, nc = cp("norepo"), cp("fakegit"), cp("nocommit")
except Exception as e:
    print("missing output: %s" % e)
    raise SystemExit
template = "git log author/committer timestamp for a commit whose subject references ATM-953"
if nc.get("missing_instrument") != template or "instrument_error" in nc:
    p.append("no-commit case changed: %s" % nc)
for name, s in (("not-a-repo", nr), ("git-rc=1", fg)):
    if s.get("elapsed") != "UNMEASURED" or not s.get("instrument_error") \
            or "ATM-800" not in s.get("missing_instrument", "") \
            or s.get("missing_instrument", "").startswith("git log author/committer timestamp for a commit"):
        p.append("%s not distinguished: %s" % (name, s))
if "rc=1" not in fg.get("instrument_error", ""):
    p.append("fake-git rc not reported: %s" % fg.get("instrument_error"))
print("PASS" if not p else " | ".join(p))
PYEOF
)"
if [ "$c4" = "PASS" ]; then
  echo "ok R5-C4 not-a-repo and git rc=1 each give UNMEASURED + instrument_error naming the failure;"
  echo "   a real repo with no matching commit keeps the plain 'no commit' instrument text"
else
  echo "NOT ok R5-C4 $c4"
  failx
fi

echo
echo "=== R5-C5 (I6): Shape-B fixture git_log uses the SAME subject-only, token-boundary match as live mode ==="
cat > "$TMP/r5_tok.json" <<'JSON'
{"item": {"atm_id": "ATM-95", "type": "Bug", "status": "Fixed (→ Fixed.md)"},
 "item_history": [
   {"event_type": "Opened", "by": "User", "on_date": "2026-08-01", "created_at": "2026-08-01T08:00:00Z"},
   {"event_type": "Fixed", "by": "AI", "on_date": "2026-08-02", "created_at": "2026-08-02T08:00:00Z"}],
 "git_log": [
   {"sha": "c1", "author_date": "2026-08-01T09:00:00Z", "committer_date": "2026-08-01T09:00:00Z", "message": "fix ATM-953 thing"},
   {"sha": "c2", "author_date": "2026-08-01T11:00:00Z", "committer_date": "2026-08-05T11:00:00Z", "message": "chore: x\n\nrefs ATM-9512"},
   {"sha": "c3", "author_date": "2026-07-01T11:00:00Z", "committer_date": "2026-07-01T11:00:00Z", "message": "docs: y\n\nbody-only ATM-95 mention"},
   {"sha": "c4", "author_date": "2026-08-01T10:00:00Z", "committer_date": "2026-08-01T10:10:00Z", "message": "fix(ATM-95): real"}]}
JSON
python3 "$CYCLE_REPORT" --as-of 2026-09-28 --tracker-export "$TMP/r5_tok.json" --out "$TMP/r5_tok_out.json" >"$TMP/r5_tok.err" 2>&1
c5="$(python3 -c "
import json, sys
s = next(x for x in json.load(open(sys.argv[1]))['records'][0]['stages'] if x['stage'] == 'commit_push')
print((s.get('elapsed'), s['start']['evidence_path'], s['end']['evidence_path']) if isinstance(s.get('start'), dict) else s)
" "$TMP/r5_tok_out.json" 2>&1)"
if [ "$c5" = "(600000, 'git_log#c4', 'git_log#c4')" ]; then
  echo "ok R5-C5 only 'fix(ATM-95): real' matches (ATM-953, ATM-9512 and a body-only mention do not): 600000 ms"
else
  echo "NOT ok R5-C5 fixture-path matching wrong: $c5"
  failx
fi

echo
echo "=== R5-C6 (M8 medians): a negative review_rounds elapsed is excluded from medians ==="
mkdir -p "$TMP/r5_rr"
printf '{"schema":"review-record/v1","item_id":"ATM-90810","started_at":"2026-09-02T15:00:00Z","ended_at":"2026-09-02T13:00:00Z","tokens":5}\n' > "$TMP/r5_rr/r.json"
cat > "$TMP/r5_neg.json" <<'JSON'
{"item": {"atm_id": "ATM-90810", "type": "Bug", "status": "Fixed (→ Fixed.md)"},
 "item_history": [{"event_type": "Opened", "by": "User", "on_date": "2026-09-01", "created_at": "2026-09-01T08:00:00Z"},
                  {"event_type": "Fixed", "by": "AI", "on_date": "2026-09-03", "created_at": "2026-09-03T08:00:00Z"}]}
JSON
python3 "$CYCLE_REPORT" --as-of 2026-09-28 --tracker-export "$TMP/r5_neg.json" --review-records-dir "$TMP/r5_rr" \
  --out "$TMP/r5_neg_out.json" >"$TMP/r5_neg.err" 2>&1
c6="$(python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
m = d['medians']['overall']['review_rounds']
r = d['records'][0]
st = next(s for s in r['stages'] if s['stage'] == 'review_rounds')
print(st['elapsed'] < 0 and 'REVIEW_ELAPSED_NEGATIVE' in r['data_quality_flags']
      and m['value_ms'] == 'UNMEASURED' and m['n_measured'] == 0 and m.get('n_negative_excluded') == 1)
" "$TMP/r5_neg_out.json" 2>&1)"
if [ "$c6" = "True" ]; then
  echo "ok R5-C6 a flagged negative elapsed stays visible in its record but is not a median member"
else
  echo "NOT ok R5-C6 negative elapsed handling: $c6 -- $(tail -2 "$TMP/r5_neg.err")"
  failx
fi

echo
echo "=== R5-C6b (B1): review records dated after --as-of are invisible; the same records are visible to a later as-of ==="
mkdir -p "$TMP/r5_rrc"
printf '{"schema":"review-record/v1","item_id":"ATM-90820","started_at":"2026-09-01T10:00:00Z","ended_at":"2026-09-01T11:00:00Z","tokens":7}\n' > "$TMP/r5_rrc/a.json"
printf '{"schema":"review-record/v1","item_id":"ATM-90820","started_at":"2026-09-30T10:00:00Z","ended_at":"2026-09-30T12:00:00Z","tokens":11}\n' > "$TMP/r5_rrc/b.json"
sed 's/ATM-90810/ATM-90820/' "$TMP/r5_neg.json" > "$TMP/r5_rrc.json"
for a in 2026-09-28 2026-10-01; do
  python3 "$CYCLE_REPORT" --as-of "$a" --tracker-export "$TMP/r5_rrc.json" --review-records-dir "$TMP/r5_rrc" \
    --out "$TMP/r5_rrc_$a.json" >"$TMP/r5_rrc_$a.err" 2>&1
done
c6b="$(python3 -c "
import json, sys
def rr(p):
    st = next(s for s in json.load(open(p))['records'][0]['stages'] if s['stage'] == 'review_rounds')
    return st.get('elapsed'), st.get('tokens')
print(rr(sys.argv[1]), rr(sys.argv[2]))
" "$TMP/r5_rrc_2026-09-28.json" "$TMP/r5_rrc_2026-10-01.json" 2>&1)"
# as-of 09-28: only round a (1 h, 7 tokens). as-of 10-01: span 09-01T10:00Z ->
# 09-30T12:00Z = 29 d 2 h = 2512800000 ms, tokens 7 + 11 = 18.
if [ "$c6b" = "(3600000, 7) (2512800000, 18)" ]; then
  echo "ok R5-C6b a review round dated after --as-of is ignored (1 h / 7 tokens) yet counted by a later as-of (29 d 2 h / 18 tokens)"
else
  echo "NOT ok R5-C6b review-record as-of cutoff: got $c6b, want (3600000, 7) (2512800000, 18)"
  failx
fi

echo
echo "=== R5-C7 (M10): --determinism-check writes --out and --md once ==="
python3 "$CYCLE_REPORT" "${R5_NEEDLE[@]}" --db-path "$R5S/full/db.sqlite" --repo-root "$R5S/full/repo" \
  --config x "${R5_COMMON[@]}" --determinism-check --out "$TMP/r5_dc.json" --md "$TMP/r5_dc.md" >"$TMP/r5_dc.out" 2>&1
dc=$?
if [ "$dc" = 0 ] && [ -f "$TMP/r5_dc.json" ] && [ -f "$TMP/r5_dc.md" ] && [ -f "$TMP/r5_full.json" ] && \
   [ "$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['body_hash'])" "$TMP/r5_dc.json")" = \
     "$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['body_hash'])" "$TMP/r5_full.json")" ]; then
  echo "ok R5-C7 --determinism-check rc=0 and wrote --out (same body_hash as a plain run) and --md"
else
  echo "NOT ok R5-C7 --determinism-check rc=$dc out=$([ -f "$TMP/r5_dc.json" ] && echo yes || echo no) -- $(tail -2 "$TMP/r5_dc.out")"
  failx
fi

echo
echo "=== R5-C8 (B1 + V2-7, reviewer experiment): live snapshot vs snapshot with every row after 2026-08-23 deleted ==="
# V2-7 (T048 restart round 2): final_status and STATUS_DESYNC are CURRENT-state
# observations of items.status; they are now EXCLUDED from body_hash (and named
# in the report's live_fields block), so the frozen comparison is body_hash
# itself -- no masking in the test. The masked full-body comparison is kept as
# a second, independent view.
if command -v sqlite3 >/dev/null 2>&1 && [ -f "$DB" ]; then
  sqlite3 -readonly "$DB" ".backup '$TMP/r5_live_full.db'"
  cp "$TMP/r5_live_full.db" "$TMP/r5_live_cut.db"
  n_del="$(sqlite3 "$TMP/r5_live_cut.db" "DELETE FROM item_history WHERE on_date > '2026-08-23'; SELECT changes();")"
  for v in full cut; do
    python3 "$CYCLE_REPORT" --config x --as-of 2026-08-23 --window-days 90 --db-path "$TMP/r5_live_$v.db" \
      --out "$TMP/r5_live_$v.json" >"$TMP/r5_live_$v.err" 2>&1
  done
  c8="$(python3 - "$TMP/r5_live_full.json" "$TMP/r5_live_cut.json" <<'PYEOF'
import json, sys
try:
    a, b = (json.load(open(p)) for p in sys.argv[1:3])
except Exception as e:
    print("missing output: %s" % e)
    raise SystemExit
def norm(d):
    d = dict(d)
    for k in ("body_hash", "run_meta", "schema"):
        d.pop(k, None)
    for r in d.get("records", []):
        r.pop("final_status", None)
        r["data_quality_flags"] = [f for f in r["data_quality_flags"] if f != "STATUS_DESYNC"]
    return d
if a["body_hash"] != b["body_hash"]:
    print("DIFF body_hash %s vs %s" % (a["body_hash"][:8], b["body_hash"][:8]))
elif norm(a) != norm(b):
    print("DIFF keys=%s" % [k for k in sorted(set(a) | set(b)) if norm(a).get(k) != norm(b).get(k)])
elif not a.get("live_fields", {}).get("excluded_from_body_hash"):
    print("live_fields block missing: %s" % a.get("live_fields"))
else:
    print("SAME %d" % len(a.get("records", [])))
PYEOF
)"
  case "$n_del:$c8" in
    0:*|:*) echo "NOT ok R5-C8 control: no rows after 2026-08-23 in the snapshot -- experiment proves nothing"; failx ;;
    *:SAME*) echo "ok R5-C8 deleted $n_del future rows; body_hash (frozen part) and every history-derived field unchanged (${c8#SAME } records)" ;;
    *) echo "NOT ok R5-C8 deleting $n_del future rows changed the as-of report: $c8"; failx ;;
  esac
else
  echo "NOT ok R5-C8 sqlite3 / live tracker DB unavailable"
  failx
fi

echo
echo "=== R5-C9 (V2-3 + V2-4): --item boundaries -- non-UTC commits, latest committer instant, as-of day, window.from ==="
r5_run i1002 full --as-of 2026-08-23 --window-days 60 --item ATM-1002 >/dev/null
r5_run i310 full --as-of 2026-08-23 --window-days 60 --item ATM-310 >/dev/null
r5_run i300 full --as-of 2026-08-23 --window-days 60 --item ATM-300 >/dev/null
r5_run i800 full --as-of 2026-08-23 --window-days 60 --item ATM-800 >/dev/null
c9="$(python3 - "$TMP" <<'PYEOF'
import json, os, sys
t = sys.argv[1]
def rec(tag):
    d = json.load(open(os.path.join(t, "r5_%s.json" % tag)))
    return d, d["records"][0]
def cp(r):
    s = next(x for x in r["stages"] if x["stage"] == "commit_push")
    v = lambda x: x.get("value") if isinstance(x, dict) else x
    return (s.get("elapsed"), v(s.get("start")), v(s.get("end")))
p = []
try:
    d1002, r1002 = rec("i1002"); d310, r310 = rec("i310"); d300, r300 = rec("i300"); d800, r800 = rec("i800")
except Exception as e:
    print("missing output: %s" % e)
    raise SystemExit
# tz-a author 09:00+05:00 (04:00Z) is the EARLIEST; tz-b committer 08:30+03:00
# (05:30Z) is the LATEST: 1 h 30 m. Lexical ISO order gives -3000000.
if cp(r1002) != (5400000, "2026-07-10T09:00:00+05:00", "2026-07-10T08:30:00+03:00"):
    p.append("ATM-1002 commit_push=%s" % (cp(r1002),))
if cp(r310) != (41400000, "2026-08-23T10:00:00Z", "2026-08-24T02:30:00+05:00"):
    p.append("ATM-310 commit_push=%s" % (cp(r310),))
if (r310.get("closure_event") or {}).get("on_date") != "2026-08-23" or d310["strata"]["Bug"]["n"] != 1:
    p.append("ATM-310 (closed ON the as-of day) closure=%s strata.Bug.n=%s"
             % (r310.get("closure_event"), d310["strata"]["Bug"]["n"]))
if (r300.get("selection_reason"), r300.get("reopen_count")) != ("reopened-in-window", 1):
    p.append("ATM-300 (Reopened ON window.from) selection/reopen=%s/%s"
             % (r300.get("selection_reason"), r300.get("reopen_count")))
if cp(r800) != (97200000, "2026-07-24T08:00:00Z", "2026-07-25T11:00:00Z"):
    p.append("ATM-800 commit_push=%s (end must be the latest COMMITTER instant)" % (cp(r800),))
print("PASS" if not p else " | ".join(p))
PYEOF
)"
if [ "$c9" = "PASS" ]; then
  echo "ok R5-C9 non-UTC commits ordered by instant (+5400000, not -3000000); end = latest committer instant;"
  echo "   a closure and a commit ON the as-of day count; a Reopened row ON window.from counts"
else
  echo "NOT ok R5-C9 $c9"
  failx
fi

echo
echo "=== R5-C10 (V2-4): Shape-B -- unparseable commit instant dropped; review rounds on vs straddling the as-of day ==="
mkdir -p "$TMP/r5_rrx"
printf '{"schema":"review-record/v1","item_id":"ATM-90830","started_at":"2026-08-23T10:00:00Z","ended_at":"2026-08-23T11:00:00Z","tokens":3}\n' > "$TMP/r5_rrx/a.json"
printf '{"schema":"review-record/v1","item_id":"ATM-90830","started_at":"2026-08-23T20:00:00Z","ended_at":"2026-08-24T02:00:00Z","tokens":5}\n' > "$TMP/r5_rrx/b.json"
cat > "$TMP/r5_bnd.json" <<'JSON'
{"item": {"atm_id": "ATM-90830", "type": "Bug", "status": "Fixed (→ Fixed.md)"},
 "item_history": [{"event_type": "Opened", "by": "User", "on_date": "2026-08-01", "created_at": "2026-08-01T08:00:00Z"},
                  {"event_type": "Fixed", "by": "AI", "on_date": "2026-08-23", "created_at": "2026-08-23T12:00:00Z"}],
 "git_log": [
   {"sha": "g1", "author_date": "2026-08-02T08:00:00Z", "committer_date": "2026-08-02T08:30:00Z", "message": "fix(ATM-90830): a"},
   {"sha": "g2", "author_date": "not-a-date", "committer_date": "2026-08-02T09:00:00Z", "message": "fix(ATM-90830): b"}]}
JSON
python3 "$CYCLE_REPORT" --as-of 2026-08-23 --tracker-export "$TMP/r5_bnd.json" --review-records-dir "$TMP/r5_rrx" \
  --out "$TMP/r5_bnd_out.json" >"$TMP/r5_bnd.err" 2>&1
c10="$(python3 -c "
import json, sys
r = json.load(open(sys.argv[1]))['records'][0]
st = {s['stage']: s for s in r['stages']}
print((st['commit_push'].get('elapsed'), st['review_rounds'].get('elapsed'), st['review_rounds'].get('tokens')))
" "$TMP/r5_bnd_out.json" 2>&1)"
# commit_push: g2's author instant is unparseable -> cannot be shown to precede
# the cutoff -> dropped -> g1 alone = 1800000. review_rounds: round a (on the
# as-of day) = 3600000 / 3 tokens; round b ends after the as-of day -> invisible.
if [ "$c10" = "(1800000, 3600000, 3)" ]; then
  echo "ok R5-C10 unparseable instant dropped; a round ON the as-of day counts; a round straddling the cutoff does not"
else
  echo "NOT ok R5-C10 got $c10, want (1800000, 3600000, 3) -- $(tail -2 "$TMP/r5_bnd.err")"
  failx
fi

echo
echo "=== R5-C11 (V2-2 class): cycle_report and select_sample report ONE sample -- same items, exclusions, usable counts ==="
# the select_sample.py BESIDE the cycle_report.py under test (the same tree --
# a mutant run compares the mutant pair, never the mutant against the real tool)
python3 "$(dirname "$CYCLE_REPORT")/select_sample.py" "${R5_NEEDLE[@]}" "${R5_COMMON[@]}" --db-path "$R5S/full/db.sqlite" \
  --out "$TMP/r5_ss.json" >"$TMP/r5_ss.err" 2>&1
printf '{"window": {"from": "2026-06-24", "to": "2026-08-23"}}\n' > "$TMP/r5_win.json"
r5_run winjson full --as-of 2026-08-23 --min-per-type 2 --bulk-threshold 3 --window-json "$TMP/r5_win.json" >/dev/null
c11="$(python3 - "$TMP/r5_full.json" "$TMP/r5_ss.json" "$TMP/r5_winjson.json" <<'PYEOF'
import json, sys
try:
    cr, ss, wj = (json.load(open(p)) for p in sys.argv[1:4])
except Exception as e:
    print("missing output: %s" % e)
    raise SystemExit
p = []
cr_recs = {r["item_id"]: (r["selection_reason"], r["excluded"], r["exclusion_reason"]) for r in cr["records"]}
ss_items = {i["item_id"]: (i["selection_reason"], i["excluded_from_duration"], i["exclusion_reason"]) for i in ss["items"]}
if cr_recs != ss_items:
    p.append("records %s != items %s" % (cr_recs, ss_items))
for t in ("Bug", "Feature", "Task"):
    if (cr["strata"][t]["n"], cr["strata"][t]["below_required"]) != (ss["strata"][t]["n_usable"], ss["strata"][t]["below_required"]):
        p.append("%s cycle_report n=%s select_sample n_usable=%s" % (t, cr["strata"][t], ss["strata"][t]))
# --window-json takes EVERY candidate; n must still be the USABLE count
# (Task 7 taken, 4 usable; Feature 1 taken, 0 usable) -- never a count of records.
want_wj = {"Bug": (7, 7), "Task": (4, 7), "Feature": (0, 1)}
got_wj = {t: (wj["strata"][t]["n"], wj["strata"][t]["n_selected"]) for t in want_wj}
if got_wj != want_wj:
    p.append("window-json strata (n, n_selected)=%s expected %s" % (got_wj, want_wj))
print("PASS" if not p else " | ".join(p))
PYEOF
)"
if [ "$c11" = "PASS" ]; then
  echo "ok R5-C11 full-mode records == select_sample items (reason + exclusion), strata n == n_usable per type;"
  echo "   --window-json (take-all) reports usable n, not a record count"
else
  echo "NOT ok R5-C11 $c11"
  failx
fi

echo
echo "=== R5-C12 (V2-7): a status change after the as-of moves final_status/STATUS_DESYNC but NOT body_hash ==="
cp "$R5S/full/db.sqlite" "$TMP/r5_status.sqlite"
sqlite3 "$TMP/r5_status.sqlite" "UPDATE items SET status='Queued' WHERE atm_id='ATM-277';"
python3 "$CYCLE_REPORT" "${R5_NEEDLE[@]}" --db-path "$TMP/r5_status.sqlite" --repo-root "$R5S/full/repo" \
  --config x "${R5_COMMON[@]}" --out "$TMP/r5_status.json" >"$TMP/r5_status.err" 2>&1
c12="$(python3 - "$TMP/r5_full.json" "$TMP/r5_status.json" <<'PYEOF'
import json, sys
try:
    a, b = (json.load(open(p)) for p in sys.argv[1:3])
except Exception as e:
    print("missing output: %s" % e)
    raise SystemExit
ra = next(r for r in a["records"] if r["item_id"] == "ATM-277")
rb = next(r for r in b["records"] if r["item_id"] == "ATM-277")
p = []
if (ra["final_status"], rb["final_status"]) != ("Fixed (→ Fixed.md)", "Queued"):
    p.append("final_status %r -> %r (the live value must be reported)" % (ra["final_status"], rb["final_status"]))
if "STATUS_DESYNC" not in rb["data_quality_flags"] or "STATUS_DESYNC" in ra["data_quality_flags"]:
    p.append("STATUS_DESYNC %s -> %s" % (ra["data_quality_flags"], rb["data_quality_flags"]))
if a["body_hash"] != b["body_hash"]:
    p.append("body_hash moved with a current-state field: %s vs %s" % (a["body_hash"][:8], b["body_hash"][:8]))
lf = b.get("live_fields", {})
if lf.get("paths") != ["records[].final_status", "records[].data_quality_flags[STATUS_DESYNC]"] \
        or lf.get("frozen_by_as_of") is not False:
    p.append("live_fields=%s" % lf)
if not any(c.get("field") == "items.type" for c in b.get("current_state_inputs", [])):
    p.append("current_state_inputs does not name items.type: %s" % b.get("current_state_inputs"))
print("PASS" if not p else " | ".join(p))
PYEOF
)"
if [ "$c12" = "PASS" ]; then
  echo "ok R5-C12 live status reported (Queued + STATUS_DESYNC) while body_hash stays frozen; live_fields and items.type named"
else
  echo "NOT ok R5-C12 $c12"
  failx
fi

echo
echo "=== R5-C13 (V2-8): no needle overrides + an as-of before the default needle's date -> needle derived at the as-of ==="
python3 "$CYCLE_REPORT" --db-path "$R5S/full/db.sqlite" --repo-root "$R5S/full/repo" --config x \
  --as-of 2026-07-20 --window-days 60 --min-per-type 2 --bulk-threshold 3 --out "$TMP/r5_nd.json" >"$TMP/r5_nd.err" 2>&1
nd_rc=$?
python3 "$CYCLE_REPORT" --db-path "$R5S/full/db.sqlite" --repo-root "$R5S/full/repo" --config x \
  "${R5_COMMON[@]}" --out "$TMP/r5_nd_default.json" >"$TMP/r5_nd_default.err" 2>&1
nd_default_rc=$?
nd="$(python3 -c "
import json, sys
n = json.load(open(sys.argv[1]))['run_meta']['needle']
print('%s|%s' % (n['source'], n['present_on_date']))
" "$TMP/r5_nd.json" 2>&1)"
if [ "$nd_rc" = 0 ] && [ "${nd%%|*}" = "derived-at-as-of" ] && [[ "${nd#*|}" < "2026-07-21" ]] && [ "$nd_default_rc" = 3 ]; then
  echo "ok R5-C13 as-of 07-20 derives the needle ($nd); as-of 08-23 keeps the default and fails closed when it is absent"
else
  echo "NOT ok R5-C13 rc=$nd_rc needle=$nd default_rc=$nd_default_rc -- $(tail -1 "$TMP/r5_nd.err")"
  failx
fi

echo
echo "=== R5-C14 (V2-5 / R8 C1+C2): review records -- only this item's, only schema review-record/v1 ==="
mkdir -p "$TMP/r5_rr2"
printf '{"schema":"review-record/v1","item_id":"ATM-90841","started_at":"2026-08-10T10:00:00Z","ended_at":"2026-08-10T11:00:00Z","tokens":1}\n' > "$TMP/r5_rr2/a.json"
printf '{"schema":"review-record/v1","item_id":"ATM-90842","started_at":"2026-08-11T10:00:00Z","ended_at":"2026-08-11T14:00:00Z","tokens":10}\n' > "$TMP/r5_rr2/b.json"
printf '{"item_id":"ATM-90841","started_at":"2026-08-12T10:00:00Z","ended_at":"2026-08-12T18:00:00Z","tokens":100}\n' > "$TMP/r5_rr2/c_noschema.json"
printf '{"schema":"review-record/v0","item_id":"ATM-90841","started_at":"2026-08-13T10:00:00Z","ended_at":"2026-08-13T18:00:00Z","tokens":1000}\n' > "$TMP/r5_rr2/d_wrongschema.json"
for i in 90841 90842; do
  sed "s/ATM-90810/ATM-$i/" "$TMP/r5_neg.json" > "$TMP/r5_two_$i.json"
  python3 "$CYCLE_REPORT" --as-of 2026-09-28 --tracker-export "$TMP/r5_two_$i.json" --review-records-dir "$TMP/r5_rr2" \
    --out "$TMP/r5_two_${i}_out.json" >"$TMP/r5_two_$i.err" 2>&1
done
c14="$(python3 -c "
import json, sys
def rr(p):
    st = next(s for s in json.load(open(p))['records'][0]['stages'] if s['stage'] == 'review_rounds')
    return (st.get('elapsed'), st.get('tokens'))
print(rr(sys.argv[1]), rr(sys.argv[2]))
" "$TMP/r5_two_90841_out.json" "$TMP/r5_two_90842_out.json" 2>&1)"
if [ "$c14" = "(3600000, 1) (14400000, 10)" ]; then
  echo "ok R5-C14 two items each see ONLY their own review record; schema-less and wrong-schema records are ignored"
else
  echo "NOT ok R5-C14 got $c14, want (3600000, 1) (14400000, 10)"
  failx
fi

# ---------------------------------------------------------------------------
# R5 paired mutations (§1.1). Each mutant is a COPY of lib/ closure/ cycle/
# under $TMP (V2-6: never inside the source tree; the tools' sibling imports
# are __file__-relative, so the copy is self-contained) with ONE textual
# change in ONE file -- cycle_report.py, or select_sample.py where the rule now
# lives (V2-2: one copy, so the mutation reaches both tools). This whole suite
# is re-run against the copy and MUST exit non-zero. M1/M3 (round 1) and
# CR_N1..CR_N7, R8-C1/C2 (round 2) are the reviewers' own mutations.
# ---------------------------------------------------------------------------
if [ "${FC_R5_MUTANT:-0}" != 1 ]; then
  echo
  echo "=== R5 paired mutations ==="
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
  r5_mutant() {  # name, file relative to $FC, old, new
    local name="$1" rel="$2" root="$TMP/r5_mut_$1" tree
    tree="$(mk_mutant_tree "$root")"
    if ! python3 - "$tree/$rel" "$3" "$4" <<'PYEOF'
import sys
path, old, new = sys.argv[1:4]
text = open(path, encoding="utf-8").read()
if text.count(old) != 1:
    raise SystemExit("anchor found %d times (need 1): %r" % (text.count(old), old))
open(path, "w", encoding="utf-8").write(text.replace(old, new))
PYEOF
    then
      echo "NOT ok mutation $name could not be applied (anchor drifted)"; failx; return
    fi
    if CYCLE_REPORT_UNDER_TEST="$tree/cycle/cycle_report.py" FC_R5_MUTANT=1 bash "$0" >"$TMP/r5_mut_$name.out" 2>&1; then
      echo "NOT ok mutation $name SURVIVED (suite still exits 0)"; failx
    else
      echo "ok mutation $name killed ($(grep -c '^NOT ok' "$TMP/r5_mut_$name.out") failing check(s))"
    fi
    rm -rf "$root"
  }
  CR=cycle/cycle_report.py
  SS=cycle/select_sample.py
  # Round 1 reviewer mutations.
  r5_mutant M1_subject_substring "$CR" 'return item_re.search(subject) is not None' 'return item_id in subject'
  r5_mutant M3_hand_verify_always_ok "$CR" 'def check_hand_verified(records, hand_verified_path):
' 'def check_hand_verified(records, hand_verified_path):
    return 0, "mutant"
'
  # Round 2 reviewer mutations (V2, verbatim effect; CR_N1/CR_N6 live in the one shared copy).
  r5_mutant CR_N1_asof_day_dropped "$SS" 'r["on_date"][:10] <= as_of]' 'r["on_date"][:10] < as_of]'
  r5_mutant CR_N2_cutoff_days_0 "$CR" 'datetime.date.fromisoformat(as_of) + datetime.timedelta(days=1),' 'datetime.date.fromisoformat(as_of) + datetime.timedelta(days=0),'
  r5_mutant CR_N3_rebased_commit_leaks "$CR" 'return parse_iso(author_iso) >= cutoff_end or parse_iso(committer_iso) >= cutoff_end' 'return parse_iso(author_iso) >= cutoff_end and parse_iso(committer_iso) >= cutoff_end'
  r5_mutant CR_N4_unparseable_kept "$CR" 'return True  # an unparseable instant cannot be shown to precede the cutoff' 'return False'
  r5_mutant CR_N5_review_cutoff_and "$CR" 'if cutoff_end is not None and (s_dt >= cutoff_end or e_dt >= cutoff_end):' 'if cutoff_end is not None and (s_dt >= cutoff_end and e_dt >= cutoff_end):'
  r5_mutant CR_N6_window_from_exclusive "$SS" 'r["event_type"] == "Reopened" and window["from"] <= (r.get("on_date") or "")[:10]' 'r["event_type"] == "Reopened" and window["from"] < (r.get("on_date") or "")[:10]'
  r5_mutant CR_N7_end_is_first_commit "$CR" 'end_m = max(matches, key=lambda m: _instant_key(m["committer_date"], m["sha"]))' 'end_m = matches[0]'
  r5_mutant R8_C1_schema_check_dropped "$CR" 'if not isinstance(doc, dict) or doc.get("schema") != "review-record/v1":' 'if not isinstance(doc, dict):'
  r5_mutant R8_C2_item_filter_dropped "$CR" '            if doc.get("item_id") != item_id:
                continue
' ''
  # Own (round 1).
  r5_mutant asof_history_cutoff_dropped "$SS" 'return [r for r in history if r.get("on_date") and r["on_date"][:10] <= as_of]' 'return list(history)'
  r5_mutant asof_git_cutoff_dropped "$CR" 'if cutoff_end is not None and _after_cutoff(ad, cd, cutoff_end):' 'if False:'
  r5_mutant asof_review_cutoff_dropped "$CR" 'if cutoff_end is not None and (s_dt >= cutoff_end or e_dt >= cutoff_end):' 'if False:'
  r5_mutant git_failure_read_as_no_commit "$CR" 'return unmeasured_git_failure(item_id, err), False' 'return unmeasured_stage("commit_push", item_id), False'
  r5_mutant fixture_whole_message "$CR" 'subject = (g.get("message") or "").split("\n", 1)[0]' 'subject = g.get("message") or ""'
  r5_mutant reopen_without_prior_raw_history "$CR" 'for row in dedup_history(history):
        if row["event_type"] in CLOSURE_EVENTS:
            closed_yet = True' 'for row in history:
        if row["event_type"] in CLOSURE_EVENTS:
            closed_yet = True'
  r5_mutant reopen_population_uncut "$CR" 'for r in history_upto(history or [], as_of):' 'for r in history or []:'
  r5_mutant reopen_dedup_hardcoded_zero "$CR" 'block = dict(overall)' 'block = dict(overall, dedup_rows_removed=0)'
  r5_mutant reopen_population_is_sample "$CR" 'population = [(i, type_of[i], full_hist[i]) for i in type_of]' 'population = [(i, type_of[i], full_hist[i]) for i in rows_by_id]'
  r5_mutant hand_verify_skips_absent "$CR" 'mismatches.append("item %s is not in this report" % item_id)' 'continue'
  r5_mutant gap_text_not_normalized "$CR" 'text = mi.replace(r["item_id"], "{item_id}")' 'text = mi'
  r5_mutant medians_keep_negative "$CR" 'if s["elapsed"] >= 0:' 'if True:'
  # Own (round 2).
  r5_mutant V2_3_lexical_commit_order "$CR" 'return (0, parse_iso(iso).timestamp(), sha)' 'return (0, iso, sha)'
  r5_mutant V2_2_strata_counts_records "$CR" '"n": sh["n_usable"]' '"n": sh["n_selected"]'
  r5_mutant V2_2_medians_include_excluded "$CR" '    records = [r for r in records if not r.get("excluded")]' '    records = list(records)'
  r5_mutant V2_2_record_exclusion_dropped "$CR" '        "excluded": exclusion_reason is not None,' '        "excluded": False,'
  r5_mutant V2_7_hash_over_live_fields "$CR" 'doc["body_hash"] = body_hash_of(frozen_projection(doc))' 'doc["body_hash"] = body_hash_of(doc)'
  r5_mutant V2_8_needle_never_derived "$SS" 'if default_date <= as_of:' 'if True:'
fi

exit $fail
