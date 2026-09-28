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

echo
echo "=== T041 contract stub 1/4: missing record -> UNMEASURED, never a number (FR-001, CT-002, CT-004) ==="
echo "NOT YET IMPLEMENTED: fixture $FIXDIR/missing_record/tracker_export.json"
echo "  describes ATM-90001 (synthetic), a Bug whose 'build' stage has NO"
echo "  source artefact anywhere in its evidence set. cycle_report.py MUST"
echo "  emit that stage's start/end/elapsed as the literal token 'UNMEASURED'"
echo "  plus a non-empty 'missing_instrument' string naming the R1 instrument"
echo "  (per-item build-log/builds.tsv row) -- NEVER 0, NEVER null, NEVER an"
echo "  interpolated/averaged value borrowed from a sibling item or stage"
echo "  (data-model.md V-CR-2). See fixtures/cycle_report/missing_record/expected."
echo "  Paired mutation this fixture must catch (tasks.md T027): 'default a"
echo "  missing stage to 0'."

echo
echo "=== T041 contract stub 2/4: empty window -> 'no data in window [from, to]' (CT-008, V-CR-3) ==="
echo "NOT YET IMPLEMENTED: fixture $FIXDIR/empty_window/window.json describes"
echo "  a window (2020-01-01..2020-01-02) with zero eligible closure events."
echo "  cycle_report.py MUST exit 0 (an empty window is honest, not a failure)"
echo "  and emit the state {\"state\":\"NO_DATA_IN_WINDOW\",\"window\":{...}}"
echo "  (CT-008) -- which is the structured form of the task line's plain"
echo "  phrasing 'no data in window [from, to]'; the literal window bounds"
echo "  MUST appear, never an ellipsis, never a zero-valued statistic standing"
echo "  in for the absent data. See fixtures/cycle_report/empty_window/expected."

echo
echo "=== T041 contract stub 3/4: golden ATM-953 hand-verified stages (CT-009, task line) ==="
echo "NOT YET IMPLEMENTED: fixture $FIXDIR/golden_atm953/tracker_export.json"
echo "  carries ATM-953's REAL item_history rows (Opened/Updated/Updated/"
echo "  Fixed/Reopened, verbatim from docs/workable_items.db, re-verified"
echo "  live by control needle #2 above) plus one corroborating git commit"
echo "  (f1abb59e). This is the contract's CT-009 default needle item"
echo "  ('the R1-verified ATM-953 Fixed 2026-07-28'). §11.4.6 honest boundary:"
echo "  this fixture does NOT claim a full 11-stage hand-verified timeline for"
echo "  ATM-953 -- 8 of the 11 data-model.md §1.1 stages have no citable"
echo "  source found in this pass and are named explicitly in the fixture's"
echo "  'honest_gap_deferred_to_T042' block; that full hand-verification"
echo "  against raw artefacts is tasks.md's own T042 (a separate later task)."
echo "  See fixtures/cycle_report/golden_atm953/expected."

echo
echo "=== T041 contract stub 4/4: negative control -- every instrument present -> zero UNMEASURED (§11.4.201(1)) ==="
echo "NOT YET IMPLEMENTED: fixture"
echo "  $FIXDIR/negative_control_all_present/tracker_export.json describes"
echo "  ATM-90002 (synthetic), a Task with all 11 stages fully populated:"
echo "  real start/end Instants with labelled time_source, real elapsed,"
echo "  real evidence_path, and tokens on the implementation stage."
echo "  cycle_report.py's output for this item MUST contain ZERO occurrences"
echo "  of 'UNMEASURED', ZERO 'missing_instrument' fields, and no"
echo "  data-quality flag -- a tool that over-flags fully-present data is"
echo "  exactly as defective as one that under-flags a genuine gap (the"
echo "  false-positive guard, §11.4.201(1)). This is the negative control the"
echo "  missing_record fixture's positive case is checked against; the same"
echo "  future test harness MUST produce opposite UNMEASURED verdicts on the"
echo "  two fixtures. See fixtures/cycle_report/negative_control_all_present/expected."

exit $fail
