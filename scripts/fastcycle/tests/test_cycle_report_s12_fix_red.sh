#!/bin/bash
# Purpose: TDD regression guard for the T048/US1 slice S12 independent-review
# remediation of `cycle/cycle_report.py` (SpecKit-004 "fast-dev-cycles"),
# three defects found against the already-landed T041 implementation:
#
#   (1) flag_status_desync() compared item_history.event_type's SHORT form
#       ("Fixed") directly against items.status's long S11.4.33 closure-
#       vocabulary form ("Fixed (-> Fixed.md)") -- two strings that are, BY
#       DESIGN, never byte-identical on a correctly-closed item, so
#       STATUS_DESYNC fired on essentially every genuinely-closed item.
#       Tracked as ATM-1055. Fix: map event_type through the SAME canonical
#       closure-vocabulary mapping the Go tracker tool already establishes
#       (parse.go normalizeStatus / crud.go's closeStatusMap) -- never a
#       third, invented definition.
#   (2) 10 of 11 StageMeasurement stages were unconditionally hardcoded to
#       UNMEASURED with stale "not yet implemented" comments, even though
#       T034 (review_record.py)/T038 (transcript_ingest.py)/T040
#       (build_deploy_qa_events.py) have since landed. Fix: review_rounds is
#       now genuinely wired to T034's review-record/v1 JSON output via an
#       explicit --review-records-dir opt-in; the other 9 stages' comments
#       are corrected to name the REAL remaining gap (verified directly
#       against the live repository, 2026-10-03), never the stale text.
#   (3) `build_found` (reconstruct_from_evidence) was computed and then
#       unconditionally discarded -- `stages["build"]` was hardcoded to
#       unmeasured_stage(...) regardless of its value. Fix: the detection
#       result is now wired into the stage's own missing_instrument text
#       (still correctly UNMEASURED -- builds.tsv genuinely has no per-item
#       JOIN -- but the dead variable's result is no longer silently thrown
#       away).
#
# S12-REMEDIATION ROUND (2026-10-03) -- a second independent (Opus-xhigh)
# review of defects (1)-(3)'s own fix found FURTHER defects in
# review_rounds_stage() and in this file's own RED/GREEN polarity +
# citations, fixed below as checks 5-8 (F1/F2/F4/F8/F9 in that review's
# numbering):
#   F1 (check 5) -- review_rounds_stage() tracked a SINGLE shared
#       `evidence_path` overwritten by whichever record os.walk visited
#       LAST, used for BOTH the start and end Instant even when the real
#       min-start and max-end come from DIFFERENT files; `dirnames` was
#       also unsorted (filesystem-dependent order). Fix: the min-start and
#       max-end are tracked INDEPENDENTLY, each with its own evidence file,
#       and `dirnames` is sorted in-place for determinism.
#   F2 (check 6) -- a record's `tokens` field was added to the running total
#       UNCONDITIONALLY, even for a record whose start/end were the honest
#       "UNKNOWN" placeholder (i.e. a record that contributes NOTHING to
#       the elapsed-time computation still inflated the token total). Fix:
#       tokens are added ONLY inside the same branch that validated the
#       record's timed span.
#   F4 (check 7) -- flag_status_desync() ALSO false-flagged a
#       REOPENED-THEN-PROGRESSING item (ATM-353: events Reopened -> Updated,
#       status="Ready for testing" -- ordinary lifecycle progress, not a
#       desync) because non-terminal statuses have no entry in
#       CLOSURE_EVENT_TO_STATUS at all. Fix: after a Reopened event, a
#       desync is flagged ONLY when items_status is ITSELF one of the
#       terminal closed-set forms (claiming done again with no new closure
#       event to justify it) -- an item that reopened and is merely
#       progressing toward resolution again is NOT flagged. This does NOT
#       suppress ATM-789 (Fixed, no Reopened event, status="Ready for
#       testing") nor the 58 SPK bulk-import rows (Fixed/Completed,
#       status="Queued") -- both remain flagged exactly as before
#       (confirmed live 2026-10-03: DB-wide sweep 60 -> 59, only ATM-353
#       drops out).
#   F8 (checks 2/4, 2/4-golden-bad, 3/4) -- this file's OWN RED_MODE
#       handling was broken: check 1b and the golden-bad case ignored
#       RED_MODE entirely, and check 2/4 only "failed" in pre-fix mode
#       because argparse rejects the (pre-fix-nonexistent) --review-
#       records-dir flag -- a crash masquerading as a RED verdict, not a
#       harness-written one (§11.4.115(F)). Fixed below: check 1b/golden-
#       bad now assert the KNOWN bare-compare bug's precise, event-type-
#       dependent polarity under RED_MODE=1; check 2/4 explicitly detects
#       and names the "flag not yet recognised by argparse" pre-fix
#       signature as its own honest RED outcome, rather than falling
#       through to the generic "invocation failed" branch by accident.
#   F9 -- this file's own header (above this point, historically) claimed
#       a "§1.1 paired mutation (mechanical, run inline below)" that did
#       not actually exist in the file. Fixed: the paired mutation now
#       genuinely runs inline, at the end of this file (mutation section),
#       mechanically reverting flag_status_desync to the bare
#       `event_type != items_status` comparison and asserting the
#       golden-good Fixed case flips from PASS to FAIL.
#
# §11.4.224 TDD: every assertion below is RED-before/GREEN-after its fix --
# RED_MODE=1 asserts the documented PRE-FIX bluff/dead-variable behaviour
# (mirrors the §11.4.115 polarity-switch convention used throughout this
# submodule's Go regression guards, e.g. atm627_status_desync_test.go).
#
# Scope discipline: this file ONLY exercises constitution/scripts/fastcycle/
# cycle/cycle_report.py; it touches no other fastcycle tool, no tracker DB
# write path, and reads docs/workable_items.db strictly read-only (sqlite3
# -readonly / cycle_report.py's own open_db_readonly).
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
CYCLE_REPORT="$FC/cycle/cycle_report.py"
DB="$ROOT/docs/workable_items.db"
RED_MODE="${RED_MODE:-0}"

fail=0
failx() { fail=1; }

TMP="$(mktemp -d)"
# MUT is declared here (not inside the mutation section below) so the single
# EXIT trap can clean up BOTH temp paths -- it MUST live alongside the real
# cycle_report.py (inside $FC/cycle/), never under $TMP, because
# cycle_report.py resolves its sibling lib/fc_common.py import RELATIVE TO
# __file__'s own directory; a copy placed anywhere else fails with
# ModuleNotFoundError before it ever reaches the mutated logic.
MUT="$FC/cycle/.s12_fix_red_mutation_tmp.$$.py"
MUT2="$FC/cycle/.s12_fix_red_mutation2_tmp.$$.py"
trap 'rm -rf "$TMP"; rm -f "$MUT" "$MUT2"' EXIT

if [ ! -f "$CYCLE_REPORT" ]; then
  echo "NOT ok cycle_report.py absent at $CYCLE_REPORT -- cannot test"
  exit 1
fi

# --- control needle: a known-present sibling resolves through this file's own path construction ---
if [ ! -f "$FC/lib/fc_common.py" ]; then
  echo "NOT ok control needle failed: lib/fc_common.py does not resolve -- this"
  echo "     test's relative-path construction is broken"
  failx
else
  echo "ok control needle: lib/fc_common.py resolves"
fi

echo
echo "=== check 1/8 (ATM-1055 fix): STATUS_DESYNC false-positive on a correctly-closed item ==="
# Live-DB check against the two real items the independent review named
# (ATM-1025, ATM-343 -- both real, currently-closed "Fixed" items). A
# synthetic fixture pair (golden-good + golden-bad, below) backs up this
# live check with a deterministic assertion independent of future DB drift.
if command -v sqlite3 >/dev/null 2>&1 && [ -f "$DB" ]; then
  for ITEM in ATM-1025 ATM-343; do
    OUT="$TMP/${ITEM}.json"
    python3 "$CYCLE_REPORT" --as-of 2026-10-03 --item "$ITEM" --out "$OUT" >"$TMP/${ITEM}.err" 2>&1
    RC=$?
    if [ "$RC" != 0 ] || [ ! -f "$OUT" ]; then
      echo "NOT ok $ITEM: cycle_report.py --item $ITEM invocation failed (rc=$RC) --"
      echo "     $(cat "$TMP/${ITEM}.err" 2>/dev/null)"
      failx
      continue
    fi
    HAS_DESYNC="$(python3 -c "
import json
r = json.load(open('$OUT'))['records'][0]
print('STATUS_DESYNC' in r.get('data_quality_flags', []))
" 2>&1)"
    if [ "$RED_MODE" = "1" ]; then
      if [ "$HAS_DESYNC" = "True" ]; then
        echo "ok (RED_MODE=1) $ITEM: STATUS_DESYNC fires on the PRE-FIX bluff (expected"
        echo "   on the unfixed function; this assertion goes FALSE on the fixed binary)"
      else
        echo "NOT ok (RED_MODE=1) $ITEM: STATUS_DESYNC did NOT fire -- fix present,"
        echo "     the pre-fix bluff is no longer reproducible against this binary"
        failx
      fi
    else
      if [ "$HAS_DESYNC" = "False" ]; then
        echo "ok $ITEM: no false-positive STATUS_DESYNC against a correctly-closed item"
        echo "   (flags: $(python3 -c "import json; print(json.load(open('$OUT'))['records'][0]['data_quality_flags'])" 2>&1))"
      else
        echo "NOT ok $ITEM: STATUS_DESYNC false-positive still fires (ATM-1055 NOT fixed)"
        failx
      fi
    fi
  done
else
  echo "NOT ok check 1/8 SKIPPED: sqlite3 or tracker DB unavailable"
  failx
fi

echo
echo "=== check 1b/8: synthetic golden-good + golden-bad for every S11.4.33 closure event ==="
# Deterministic, DB-independent coverage of all 5 STATUS_DEFINING_EVENTS
# (Fixed/Implemented/Completed/Obsolete/Reopened), proving the fix's mapping
# is complete, not merely correct for the two live items checked above.
#
# F8 fix: this loop now honours RED_MODE. The documented pre-fix bug is a
# BARE `event_type != items_status` string comparison (no S11.4.33 mapping
# at all) -- under that bug, Fixed/Implemented/Completed/Obsolete (whose
# items.status is the long "(→ Fixed.md)" form) ALWAYS mismatch the short
# event_type and so DO fire STATUS_DESYNC pre-fix, while Reopened's
# items.status ("Reopened") IS byte-identical to its own event_type and so
# does NOT fire even on the bare-compare bug -- a real, event-type-
# dependent polarity, not a blanket "always True"/"always False" guess.
# F10b fix (S12-remediation follow-up round): the atm_id below previously
# used "ATM-9${RANDOM}1" -- a FRESH, different random id generated on every
# single test run (and even once per loop iteration). Identified risk:
# NONE found currently exercises this value as a discriminator (--tracker-
# export's synthetic item is never looked up in the live DB, and no
# git_log fixture is supplied here, so commit_push_stage's ITEM_ID_RE
# matching path is never reached for this id) -- but non-deterministic test
# DATA is itself a §11.4.50 determinism violation independent of whether a
# flakiness risk is CURRENTLY reachable, and leaves the door open for a
# future edit that DOES make the id load-bearing to introduce flakiness
# silently. Fixed to a small, fixed, deterministic id per closure event.
declare -A F1B_IDS=( [Fixed]="90090" [Implemented]="90091" [Completed]="90092" [Obsolete]="90093" [Reopened]="90094" )
for PAIR in "Fixed:Fixed (→ Fixed.md)" "Implemented:Implemented (→ Fixed.md)" "Completed:Completed (→ Fixed.md)" "Obsolete:Obsolete (→ Fixed.md)" "Reopened:Reopened"; do
  EVT="${PAIR%%:*}"
  STATUS="${PAIR#*:}"
  FX="$TMP/golden_${EVT}.json"
  cat > "$FX" <<JSON
{"item": {"atm_id": "ATM-${F1B_IDS[$EVT]}", "type": "Task", "status": "${STATUS}"},
 "item_history": [
   {"event_type": "Opened", "by": "User", "on_date": "2026-08-01", "created_at": "2026-08-01T08:00:00Z"},
   {"event_type": "${EVT}", "by": "AI", "on_date": "2026-08-01", "created_at": "2026-08-01T09:00:00Z"}
 ]}
JSON
  OUT="$TMP/golden_${EVT}_out.json"
  python3 "$CYCLE_REPORT" --as-of 2026-10-03 --tracker-export "$FX" --out "$OUT" >"$TMP/golden_${EVT}.err" 2>&1
  if [ $? != 0 ] || [ ! -f "$OUT" ]; then
    echo "NOT ok golden-good $EVT: invocation failed -- $(cat "$TMP/golden_${EVT}.err" 2>/dev/null)"
    failx
    continue
  fi
  HAS_DESYNC="$(python3 -c "
import json
r = json.load(open('$OUT'))['records'][0]
print('STATUS_DESYNC' in r.get('data_quality_flags', []))
" 2>&1)"
  if [ "$EVT" = "Reopened" ]; then
    EXPECTED_RED="False"
  else
    EXPECTED_RED="True"
  fi
  if [ "$RED_MODE" = "1" ]; then
    if [ "$HAS_DESYNC" = "$EXPECTED_RED" ]; then
      echo "ok (RED_MODE=1) golden-good $EVT -> $STATUS: STATUS_DESYNC=$HAS_DESYNC"
      echo "   matches the pre-fix bare-compare bug's known polarity for this event type"
    else
      echo "NOT ok (RED_MODE=1) golden-good $EVT -> $STATUS: expected STATUS_DESYNC=$EXPECTED_RED"
      echo "     (pre-fix bare-compare polarity) but got $HAS_DESYNC -- fix present or"
      echo "     polarity assumption wrong"
      failx
    fi
  else
    if [ "$HAS_DESYNC" = "False" ]; then
      echo "ok golden-good $EVT -> $STATUS: no STATUS_DESYNC (matching S11.4.33 mapping)"
    else
      echo "NOT ok golden-good $EVT -> $STATUS: STATUS_DESYNC false-fired"
      failx
    fi
  fi
done

# golden-bad: a GENUINE desync (wrong status for the closure event) MUST
# still be caught -- the false-positive guard in check 1b above must not
# have been achieved by disabling the check entirely (§11.4.201(1)). This
# assertion is POLARITY-INVARIANT (holds on both the pre-fix bare-compare
# binary AND the fixed S11.4.33-mapping binary: "Fixed" != "In progress" is
# true under EITHER comparison) -- it is explicitly checked under BOTH
# RED_MODE values below, deliberately, not silently skipped under RED_MODE
# (the F8 finding: an assertion must be an EXPLICIT, understood decision for
# every polarity, never an accident of which branch happened to run).
BADFX="$TMP/golden_bad_desync.json"
cat > "$BADFX" <<'JSON'
{"item": {"atm_id": "ATM-90099", "type": "Task", "status": "In progress"},
 "item_history": [
   {"event_type": "Opened", "by": "User", "on_date": "2026-08-01", "created_at": "2026-08-01T08:00:00Z"},
   {"event_type": "Fixed", "by": "AI", "on_date": "2026-08-01", "created_at": "2026-08-01T09:00:00Z"}
 ]}
JSON
BADOUT="$TMP/golden_bad_out.json"
python3 "$CYCLE_REPORT" --as-of 2026-10-03 --tracker-export "$BADFX" --out "$BADOUT" >"$TMP/golden_bad.err" 2>&1
if [ $? = 0 ] && [ -f "$BADOUT" ]; then
  BAD_HAS_DESYNC="$(python3 -c "
import json
r = json.load(open('$BADOUT'))['records'][0]
print('STATUS_DESYNC' in r.get('data_quality_flags', []))
" 2>&1)"
  if [ "$BAD_HAS_DESYNC" = "True" ]; then
    if [ "$RED_MODE" = "1" ]; then
      echo "ok (RED_MODE=1, polarity-invariant) golden-bad: a genuine desync (Fixed"
      echo "   event, status=In progress) is flagged under the pre-fix bare-compare"
      echo "   binary too -- expected, this case never depended on the S11.4.33 fix"
    else
      echo "ok golden-bad: a genuine desync (Fixed event, status=In progress) IS still"
      echo "   flagged -- the ATM-1055 fix narrowed the comparison, it did not disable it"
    fi
  else
    echo "NOT ok golden-bad: a genuine desync was NOT flagged -- §11.4.201(1) false-"
    echo "     negative, the fix over-corrected into never firing"
    failx
  fi
else
  echo "NOT ok golden-bad: invocation failed -- $(cat "$TMP/golden_bad.err" 2>/dev/null)"
  failx
fi

echo
echo "=== check 2/8 (defect 2): review_rounds genuinely wired to T034 review-record/v1 ==="
RRDIR="$TMP/review_records"
mkdir -p "$RRDIR"
cat > "$RRDIR/round1.json" <<'JSON'
{"schema":"review-record/v1","item_id":"ATM-90100","started_at":"2026-08-10T12:00:00Z","ended_at":"2026-08-10T13:00:00Z","tokens":5000,"verdict":"GO","round":1}
JSON
RRFX="$TMP/rr_tracker_export.json"
cat > "$RRFX" <<'JSON'
{"item": {"atm_id": "ATM-90100", "type": "Task", "status": "Fixed (→ Fixed.md)"},
 "item_history": [
   {"event_type": "Opened", "by": "User", "on_date": "2026-08-10", "created_at": "2026-08-10T08:00:00Z"},
   {"event_type": "Fixed", "by": "AI", "on_date": "2026-08-10", "created_at": "2026-08-10T17:00:00Z"}
 ]}
JSON
RROUT_WIRED="$TMP/rr_wired.json"
RROUT_UNWIRED="$TMP/rr_unwired.json"
python3 "$CYCLE_REPORT" --as-of 2026-10-03 --tracker-export "$RRFX" \
  --review-records-dir "$RRDIR" --out "$RROUT_WIRED" >"$TMP/rr_wired.err" 2>&1
RC_WIRED=$?
python3 "$CYCLE_REPORT" --as-of 2026-10-03 --tracker-export "$RRFX" \
  --out "$RROUT_UNWIRED" >"$TMP/rr_unwired.err" 2>&1
# F8 fix: handle the "the pre-fix binary does not even recognise
# --review-records-dir yet" case EXPLICITLY, as its own named RED signature,
# rather than silently falling through to the generic
# "one or both invocations failed to produce output" branch -- the PRE-fix
# artifact for this round's defect 2 genuinely has NO such flag (it was
# introduced BY this fix), so argparse rejecting it is the real, honest,
# behaviourally-observed pre-fix signature (§11.4.115(F)), not an accident.
if [ "$RED_MODE" = "1" ] && [ "$RC_WIRED" != 0 ] && [ ! -f "$RROUT_WIRED" ] \
   && grep -qi "unrecognized arguments" "$TMP/rr_wired.err" 2>/dev/null; then
  echo "ok (RED_MODE=1) review_rounds: --review-records-dir is not yet a"
  echo "   recognised flag on the pre-fix binary -- $(grep -i 'unrecognized' "$TMP/rr_wired.err" | head -1)"
  echo "   -- this IS the pre-fix expectation, observed as real CLI behaviour"
  echo "   (argparse usage error), not an accidental crash standing in for a"
  echo "   verdict (§11.4.115(F))"
elif [ -f "$RROUT_WIRED" ] && [ -f "$RROUT_UNWIRED" ]; then
  WIRED_CHECK="$(python3 -c "
import json
w = json.load(open('$RROUT_WIRED'))['records'][0]
u = json.load(open('$RROUT_UNWIRED'))['records'][0]
ws = next(s for s in w['stages'] if s['stage'] == 'review_rounds')
us = next(s for s in u['stages'] if s['stage'] == 'review_rounds')
ok = (ws['elapsed'] == 3600000 and ws.get('tokens') == 5000
      and ws['start']['time_source'] == 'registry_ts'
      and us['elapsed'] == 'UNMEASURED' and 'review_record.py' in us.get('missing_instrument', ''))
print(ok)
" 2>&1)"
  if [ "$RED_MODE" = "1" ]; then
    if [ "$WIRED_CHECK" = "False" ]; then
      echo "ok (RED_MODE=1): review_rounds is NOT wired (pre-fix expectation --"
      echo "   the flag IS recognised here but review_rounds_stage still returns"
      echo "   None/UNMEASURED unconditionally)"
    else
      echo "NOT ok (RED_MODE=1): review_rounds IS wired -- fix present"
      failx
    fi
  else
    if [ "$WIRED_CHECK" = "True" ]; then
      echo "ok review_rounds: --review-records-dir wires a real review-record/v1 JSON"
      echo "   document into a genuinely-measured stage (elapsed=3600000ms,"
      echo "   tokens=5000, time_source=registry_ts), while the SAME item with no"
      echo "   flag stays honestly UNMEASURED naming the T034 instrument"
    else
      echo "NOT ok review_rounds wiring check FAILED (comparator result: '$WIRED_CHECK')"
      echo "     wired: $(cat "$RROUT_WIRED" 2>/dev/null)"
      echo "     unwired: $(cat "$RROUT_UNWIRED" 2>/dev/null)"
      failx
    fi
  fi
else
  echo "NOT ok check 2/8: one or both invocations failed to produce output"
  echo "     wired rc=$RC_WIRED stderr: $(cat "$TMP/rr_wired.err" 2>/dev/null)"
  failx
fi

echo
echo "=== check 3/8 (defect 3): build_found is no longer a discarded dead variable ==="
BFX_FOUND="$TMP/build_found.json"
cat > "$BFX_FOUND" <<'JSON'
{"item": {"atm_id": "ATM-90101", "type": "Task", "status": "Fixed (→ Fixed.md)"},
 "item_history": [
   {"event_type": "Opened", "by": "User", "on_date": "2026-08-10", "created_at": "2026-08-10T08:00:00Z"},
   {"event_type": "Fixed", "by": "AI", "on_date": "2026-08-10", "created_at": "2026-08-10T17:00:00Z"}
 ],
 "evidence_files_present": [
   {"path": "docs/build/resources/builds.tsv", "mtime": "2026-08-10T12:00:00Z"}
 ]}
JSON
BFX_ABSENT="$TMP/build_absent.json"
cat > "$BFX_ABSENT" <<'JSON'
{"item": {"atm_id": "ATM-90102", "type": "Task", "status": "Fixed (→ Fixed.md)"},
 "item_history": [
   {"event_type": "Opened", "by": "User", "on_date": "2026-08-10", "created_at": "2026-08-10T08:00:00Z"},
   {"event_type": "Fixed", "by": "AI", "on_date": "2026-08-10", "created_at": "2026-08-10T17:00:00Z"}
 ],
 "evidence_files_present": [
   {"path": "qa-results/fixture/GREEN.log", "mtime": "2026-08-10T12:00:00Z"}
 ]}
JSON
BOUT_FOUND="$TMP/build_found_out.json"
BOUT_ABSENT="$TMP/build_absent_out.json"
python3 "$CYCLE_REPORT" --as-of 2026-10-03 --tracker-export "$BFX_FOUND" --out "$BOUT_FOUND" >"$TMP/bf.err" 2>&1
python3 "$CYCLE_REPORT" --as-of 2026-10-03 --tracker-export "$BFX_ABSENT" --out "$BOUT_ABSENT" >"$TMP/ba.err" 2>&1
if [ -f "$BOUT_FOUND" ] && [ -f "$BOUT_ABSENT" ]; then
  BUILD_CHECK="$(python3 -c "
import json
f = json.load(open('$BOUT_FOUND'))['records'][0]
a = json.load(open('$BOUT_ABSENT'))['records'][0]
fs = next(s for s in f['stages'] if s['stage'] == 'build')
asg = next(s for s in a['stages'] if s['stage'] == 'build')
both_unmeasured = fs['elapsed'] == 'UNMEASURED' and asg['elapsed'] == 'UNMEASURED'
distinct_messages = fs['missing_instrument'] != asg['missing_instrument']
found_names_file = 'builds.tsv' in fs['missing_instrument'] and 'build_id-to-item join' in fs['missing_instrument']
print(both_unmeasured and distinct_messages and found_names_file)
" 2>&1)"
  if [ "$RED_MODE" = "1" ]; then
    if [ "$BUILD_CHECK" = "False" ]; then
      echo "ok (RED_MODE=1): build_found's detection is NOT surfaced (pre-fix: both"
      echo "   messages identical regardless of evidence_files_present content)"
    else
      echo "NOT ok (RED_MODE=1): build_found's detection IS surfaced -- fix present"
      failx
    fi
  else
    if [ "$BUILD_CHECK" = "True" ]; then
      echo "ok build_found: both stay honestly UNMEASURED (builds.tsv genuinely has"
      echo "   no per-item join) but the detection result now produces DISTINCT"
      echo "   missing_instrument text depending on whether a builds.tsv-pattern"
      echo "   evidence file was found -- no longer a dead variable, and the stated"
      echo "   reason (missing build_id-to-item join, F11.3) is now accurate"
    else
      echo "NOT ok build_found check FAILED (comparator result: '$BUILD_CHECK')"
      failx
    fi
  fi
else
  echo "NOT ok check 3/8: one or both invocations failed to produce output"
  failx
fi

echo
echo "=== check 5/8 (S12-remediation F1): review_rounds evidence-path attribution + determinism ==="
# Three review-record/v1 files across 3 directories (a, b, z -- sorted order
# a < b < z), deliberately crossing evidence-file boundaries for start vs
# end, PLUS a start-timestamp tie between rr/a and rr/b to exercise
# deterministic tie-breaking:
#   rr/a/r_tie.json   : started 10:00 (tie), ended 10:15, tokens=200
#   rr/b/r_other.json : started 10:00 (tie), ended 10:30, tokens=100
#   rr/z/r_late.json  : started 14:00,        ended 15:00, tokens=300
# Expected (post-fix): overall start=10:00 attributed to rr/a/r_tie.json
# (first-visited winner of the tie, under sorted dirnames traversal),
# overall end=15:00 attributed to rr/z/r_late.json (a DIFFERENT file than
# the start) -- the pre-fix bug shared ONE evidence_path variable, so
# start_evidence and end_evidence were ALWAYS byte-identical regardless of
# which file actually owned which instant; that equality is the honest,
# traversal-order-INDEPENDENT RED signature checked below.
F1DIR="$TMP/f1_review_records"
mkdir -p "$F1DIR/a" "$F1DIR/b" "$F1DIR/z"
cat > "$F1DIR/a/r_tie.json" <<'JSON'
{"schema":"review-record/v1","item_id":"ATM-90200","started_at":"2026-08-10T10:00:00Z","ended_at":"2026-08-10T10:15:00Z","tokens":200,"verdict":"GO","round":1}
JSON
cat > "$F1DIR/b/r_other.json" <<'JSON'
{"schema":"review-record/v1","item_id":"ATM-90200","started_at":"2026-08-10T10:00:00Z","ended_at":"2026-08-10T10:30:00Z","tokens":100,"verdict":"GO","round":2}
JSON
cat > "$F1DIR/z/r_late.json" <<'JSON'
{"schema":"review-record/v1","item_id":"ATM-90200","started_at":"2026-08-10T14:00:00Z","ended_at":"2026-08-10T15:00:00Z","tokens":300,"verdict":"GO","round":3}
JSON
F1FX="$TMP/f1_tracker_export.json"
cat > "$F1FX" <<'JSON'
{"item": {"atm_id": "ATM-90200", "type": "Task", "status": "Fixed (→ Fixed.md)"},
 "item_history": [
   {"event_type": "Opened", "by": "User", "on_date": "2026-08-10", "created_at": "2026-08-10T08:00:00Z"},
   {"event_type": "Fixed", "by": "AI", "on_date": "2026-08-10", "created_at": "2026-08-10T17:00:00Z"}
 ]}
JSON
F1_RUN1="$TMP/f1_out1.json"
F1_RUN2="$TMP/f1_out2.json"
F1_RUN3="$TMP/f1_out3.json"
for OUT in "$F1_RUN1" "$F1_RUN2" "$F1_RUN3"; do
  python3 "$CYCLE_REPORT" --as-of 2026-10-03 --tracker-export "$F1FX" \
    --review-records-dir "$F1DIR" --out "$OUT" >"$TMP/f1_$(basename "$OUT").err" 2>&1
done
# F8-class fix: a RED_MODE=1 run against a baseline that predates
# --review-records-dir entirely (e.g. true HEAD, before even the S12 fix)
# makes argparse reject the flag outright -- that is honestly consistent
# with "review_rounds is not wired" (the flag not existing implies it
# cannot be wired) and MUST be named explicitly, not fall through to the
# generic "invocation failed" branch below.
if [ "$RED_MODE" = "1" ] && [ ! -f "$F1_RUN1" ] \
   && grep -qi "unrecognized arguments" "$TMP/f1_$(basename "$F1_RUN1").err" 2>/dev/null; then
  echo "ok (RED_MODE=1): --review-records-dir is not yet a recognised flag on"
  echo "   this baseline -- $(grep -i 'unrecognized' "$TMP/f1_$(basename "$F1_RUN1").err" | head -1)"
  echo "   -- consistent with the pre-fix expectation (review_rounds cannot be"
  echo "   wired without the flag existing at all)"
elif [ -f "$F1_RUN1" ] && [ -f "$F1_RUN2" ] && [ -f "$F1_RUN3" ]; then
  F1_CHECK="$(python3 -c "
import json
r1 = json.load(open('$F1_RUN1'))['records'][0]
r2 = json.load(open('$F1_RUN2'))['records'][0]
r3 = json.load(open('$F1_RUN3'))['records'][0]
s1 = next(s for s in r1['stages'] if s['stage'] == 'review_rounds')
s2 = next(s for s in r2['stages'] if s['stage'] == 'review_rounds')
s3 = next(s for s in r3['stages'] if s['stage'] == 'review_rounds')
same_start_evidence = (s1['start']['evidence_path'] == s2['start']['evidence_path']
                        == s3['start']['evidence_path'])
same_end_evidence = (s1['end']['evidence_path'] == s2['end']['evidence_path']
                      == s3['end']['evidence_path'])
start_is_r_tie = s1['start']['evidence_path'].endswith('r_tie.json')
end_is_r_late = s1['end']['evidence_path'].endswith('r_late.json')
distinct_evidence = s1['start']['evidence_path'] != s1['end']['evidence_path']
correct_values = (s1['start']['value'] == '2026-08-10T10:00:00Z'
                   and s1['end']['value'] == '2026-08-10T15:00:00Z'
                   and s1['elapsed'] == 18000000
                   and s1.get('tokens') == 600)
print(same_start_evidence and same_end_evidence and start_is_r_tie
      and end_is_r_late and distinct_evidence and correct_values)
" 2>&1)"
  RED_SIGNATURE="$(python3 -c "
import json
r1 = json.load(open('$F1_RUN1'))['records'][0]
s1 = next(s for s in r1['stages'] if s['stage'] == 'review_rounds')
print(s1['start']['evidence_path'] == s1['end']['evidence_path'])
" 2>&1)"
  if [ "$RED_MODE" = "1" ]; then
    if [ "$RED_SIGNATURE" = "True" ]; then
      echo "ok (RED_MODE=1): start_evidence == end_evidence on the pre-fix binary"
      echo "   (the shared single-variable bug -- order-independent, always true"
      echo "   regardless of os.walk traversal order)"
    else
      echo "NOT ok (RED_MODE=1): start_evidence != end_evidence -- fix present"
      failx
    fi
  else
    if [ "$F1_CHECK" = "True" ]; then
      echo "ok review_rounds evidence-path attribution: start (10:00) correctly"
      echo "   attributed to rr/a/r_tie.json, end (15:00) correctly attributed to"
      echo "   rr/z/r_late.json -- a DIFFERENT file -- deterministically identical"
      echo "   across 3 repeated runs (dirnames.sort() fix)"
    else
      echo "NOT ok check 5/8 FAILED (comparator result: '$F1_CHECK')"
      echo "     run1: $(cat "$F1_RUN1" 2>/dev/null)"
      failx
    fi
  fi
else
  echo "NOT ok check 5/8: one or more invocations failed to produce output"
  failx
fi

echo
echo "=== check 6/8 (S12-remediation F2): review_rounds token total excludes UNKNOWN-timestamp records ==="
F2DIR="$TMP/f2_review_records"
mkdir -p "$F2DIR"
cat > "$F2DIR/good.json" <<'JSON'
{"schema":"review-record/v1","item_id":"ATM-90201","started_at":"2026-08-11T10:00:00Z","ended_at":"2026-08-11T11:00:00Z","tokens":1000,"verdict":"GO","round":1}
JSON
cat > "$F2DIR/unknown.json" <<'JSON'
{"schema":"review-record/v1","item_id":"ATM-90201","started_at":"UNKNOWN","ended_at":"UNKNOWN","tokens":99999,"verdict":"PENDING","round":2}
JSON
F2FX="$TMP/f2_tracker_export.json"
cat > "$F2FX" <<'JSON'
{"item": {"atm_id": "ATM-90201", "type": "Task", "status": "Fixed (→ Fixed.md)"},
 "item_history": [
   {"event_type": "Opened", "by": "User", "on_date": "2026-08-11", "created_at": "2026-08-11T08:00:00Z"},
   {"event_type": "Fixed", "by": "AI", "on_date": "2026-08-11", "created_at": "2026-08-11T17:00:00Z"}
 ]}
JSON
F2OUT="$TMP/f2_out.json"
python3 "$CYCLE_REPORT" --as-of 2026-10-03 --tracker-export "$F2FX" \
  --review-records-dir "$F2DIR" --out "$F2OUT" >"$TMP/f2.err" 2>&1
# F8-class fix: see check 5/8's identical comment above.
if [ "$RED_MODE" = "1" ] && [ ! -f "$F2OUT" ] \
   && grep -qi "unrecognized arguments" "$TMP/f2.err" 2>/dev/null; then
  echo "ok (RED_MODE=1): --review-records-dir is not yet a recognised flag on"
  echo "   this baseline -- $(grep -i 'unrecognized' "$TMP/f2.err" | head -1)"
  echo "   -- consistent with the pre-fix expectation"
elif [ -f "$F2OUT" ]; then
  F2_TOKENS="$(python3 -c "
import json
r = json.load(open('$F2OUT'))['records'][0]
s = next(s for s in r['stages'] if s['stage'] == 'review_rounds')
print(s.get('tokens'))
" 2>&1)"
  if [ "$RED_MODE" = "1" ]; then
    if [ "$F2_TOKENS" = "100999" ]; then
      echo "ok (RED_MODE=1): tokens=100999 on the pre-fix binary -- the UNKNOWN-"
      echo "   timestamped record's 99999 tokens were added unconditionally"
      echo "   (1000 + 99999)"
    else
      echo "NOT ok (RED_MODE=1): expected tokens=100999 (pre-fix overclaim), got"
      echo "     '$F2_TOKENS' -- fix present"
      failx
    fi
  else
    if [ "$F2_TOKENS" = "1000" ]; then
      echo "ok review_rounds tokens=1000: the UNKNOWN-timestamped record's 99999"
      echo "   tokens were correctly EXCLUDED (it contributed nothing to the elapsed"
      echo "   span either) -- only the one validly-timed record's tokens count"
    else
      echo "NOT ok check 6/8 FAILED: expected tokens=1000, got '$F2_TOKENS'"
      failx
    fi
  fi
else
  echo "NOT ok check 6/8: invocation failed -- $(cat "$TMP/f2.err" 2>/dev/null)"
  failx
fi

echo
echo "=== check 7/8 (S12-remediation F4): Reopened-then-progressed is NOT a desync; genuine post-reopen desyncs still ARE ==="
# (a) the ATM-353 pattern itself: Reopened -> Updated, status still
#     non-terminal ("Ready for testing") -- ordinary progress, must NOT be
#     flagged.
F4_A="$TMP/f4_reopened_progressing.json"
cat > "$F4_A" <<'JSON'
{"item": {"atm_id": "ATM-90300", "type": "Bug", "status": "Ready for testing"},
 "item_history": [
   {"event_type": "Opened", "by": "User", "on_date": "2026-08-01", "created_at": "2026-08-01T08:00:00Z"},
   {"event_type": "Fixed", "by": "AI", "on_date": "2026-08-01", "created_at": "2026-08-01T09:00:00Z"},
   {"event_type": "Reopened", "by": "User", "on_date": "2026-08-02", "created_at": "2026-08-02T08:00:00Z"},
   {"event_type": "Updated", "by": "AI", "on_date": "2026-08-03", "created_at": "2026-08-03T09:00:00Z"}
 ]}
JSON
# (b) a GENUINE desync after a reopen: Reopened event, but items_status
#     falsely claims the item is done again ("Fixed (→ Fixed.md)") with NO
#     new closure event in the history to justify it -- MUST still be
#     flagged (this is what distinguishes the fix from "disable the check
#     entirely after a Reopened event", §11.4.201(1)).
F4_B="$TMP/f4_reopened_false_closed.json"
cat > "$F4_B" <<'JSON'
{"item": {"atm_id": "ATM-90301", "type": "Bug", "status": "Fixed (→ Fixed.md)"},
 "item_history": [
   {"event_type": "Opened", "by": "User", "on_date": "2026-08-01", "created_at": "2026-08-01T08:00:00Z"},
   {"event_type": "Fixed", "by": "AI", "on_date": "2026-08-01", "created_at": "2026-08-01T09:00:00Z"},
   {"event_type": "Reopened", "by": "User", "on_date": "2026-08-02", "created_at": "2026-08-02T08:00:00Z"}
 ]}
JSON
# (c) the ATM-789 pattern: Fixed event, NO Reopened event at all, status
#     disagrees ("Ready for testing") -- the operator/reviewer correction:
#     this is NOT the Reopened-then-progressing pattern and MUST remain
#     flagged (do not suppress; only ATM-353-style items stop being
#     flagged).
F4_C="$TMP/f4_fixed_no_reopen_desync.json"
cat > "$F4_C" <<'JSON'
{"item": {"atm_id": "ATM-90302", "type": "Bug", "status": "Ready for testing"},
 "item_history": [
   {"event_type": "Opened", "by": "User", "on_date": "2026-08-01", "created_at": "2026-08-01T08:00:00Z"},
   {"event_type": "Fixed", "by": "AI", "on_date": "2026-08-01", "created_at": "2026-08-01T09:00:00Z"}
 ]}
JSON
declare -A F4_EXPECT_GREEN=( [a]="False" [b]="True" [c]="True" )
# Pre-fix bare-compare polarity for each case (event_type != items_status,
# no S11.4.33 mapping at all):
#   (a) event_type at the latest status-defining row is "Reopened";
#       "Reopened" != "Ready for testing" -> True (bug fires: this IS the
#       ATM-353 false positive this round fixes).
#   (b) event_type "Reopened" != "Fixed (→ Fixed.md)" -> True (fires either
#       way -- a genuine desync is caught by BOTH the bug and the fix).
#   (c) event_type "Fixed" != "Ready for testing" -> True (fires either
#       way -- ATM-789's pattern, caught by BOTH the bug and the fix).
declare -A F4_EXPECT_RED=( [a]="True" [b]="True" [c]="True" )
for CASE in a b c; do
  FX_VAR="F4_${CASE^^}"
  FX="${!FX_VAR}"
  OUT="$TMP/f4_${CASE}_out.json"
  python3 "$CYCLE_REPORT" --as-of 2026-10-03 --tracker-export "$FX" --out "$OUT" >"$TMP/f4_${CASE}.err" 2>&1
  if [ ! -f "$OUT" ]; then
    echo "NOT ok check 7/8 ($CASE): invocation failed -- $(cat "$TMP/f4_${CASE}.err" 2>/dev/null)"
    failx
    continue
  fi
  HAS_DESYNC="$(python3 -c "
import json
r = json.load(open('$OUT'))['records'][0]
print('STATUS_DESYNC' in r.get('data_quality_flags', []))
" 2>&1)"
  if [ "$RED_MODE" = "1" ]; then
    EXPECT="${F4_EXPECT_RED[$CASE]}"
    LABEL="(RED_MODE=1) "
  else
    EXPECT="${F4_EXPECT_GREEN[$CASE]}"
    LABEL=""
  fi
  if [ "$HAS_DESYNC" = "$EXPECT" ]; then
    echo "ok ${LABEL}check 7/8 ($CASE): STATUS_DESYNC=$HAS_DESYNC as expected"
  else
    echo "NOT ok ${LABEL}check 7/8 ($CASE): expected STATUS_DESYNC=$EXPECT, got $HAS_DESYNC"
    failx
  fi
done

echo
echo "=== check 9 (S12-remediation follow-up round, F5): review_rounds 'elapsed' is the FULL wall-clock span (incl. inter-round gaps, consistent with commit_push_stage's own earliest-to-latest-event convention); the NEW summed_review_duration_ms field is the separate actual-review-time figure ==="
F5DIR="$TMP/f5_review_records"
mkdir -p "$F5DIR"
cat > "$F5DIR/round1.json" <<'JSON'
{"schema":"review-record/v1","item_id":"ATM-90200","started_at":"2026-10-01T10:00:00Z","ended_at":"2026-10-01T12:00:00Z","tokens":1000}
JSON
cat > "$F5DIR/round2.json" <<'JSON'
{"schema":"review-record/v1","item_id":"ATM-90200","started_at":"2026-10-01T17:00:00Z","ended_at":"2026-10-01T18:00:00Z","tokens":500}
JSON
F5FX="$TMP/f5_tracker_export.json"
cat > "$F5FX" <<'JSON'
{"item": {"atm_id": "ATM-90200", "type": "Task", "status": "Fixed (→ Fixed.md)"},
 "item_history": [
   {"event_type": "Opened", "by": "User", "on_date": "2026-10-01", "created_at": "2026-10-01T08:00:00Z"},
   {"event_type": "Fixed", "by": "AI", "on_date": "2026-10-01", "created_at": "2026-10-01T19:00:00Z"}
 ]}
JSON
F5OUT="$TMP/f5_out.json"
python3 "$CYCLE_REPORT" --as-of 2026-10-03 --tracker-export "$F5FX" \
  --review-records-dir "$F5DIR" --out "$F5OUT" >"$TMP/f5.err" 2>&1
if [ -f "$F5OUT" ]; then
  F5_RESULT="$(python3 -c "
import json
r = json.load(open('$F5OUT'))['records'][0]
rr = next(s for s in r['stages'] if s['stage'] == 'review_rounds')
print('%s|%s' % (rr.get('elapsed'), rr.get('summed_review_duration_ms')))
" 2>&1)"
  IFS='|' read -r F5_ELAPSED F5_SUMMED <<< "$F5_RESULT"
  if [ "$RED_MODE" = "1" ]; then
    if [ "$F5_ELAPSED" = "28800000" ] && [ "$F5_SUMMED" = "None" ]; then
      echo "ok (RED_MODE=1) check 9 (F5): elapsed=28800000 (the full 10:00->18:00"
      echo "   span, unaffected -- pre-existing F1/F1-fix behaviour), and"
      echo "   summed_review_duration_ms is entirely absent (pre-fix: this field"
      echo "   does not exist yet)"
    else
      echo "NOT ok (RED_MODE=1) check 9 (F5): expected elapsed=28800000 summed=None,"
      echo "     got elapsed=$F5_ELAPSED summed=$F5_SUMMED"
      failx
    fi
  else
    if [ "$F5_ELAPSED" = "28800000" ] && [ "$F5_SUMMED" = "10800000" ]; then
      echo "ok check 9 (F5): elapsed=28800000ms is the FULL wall-clock span"
      echo "   (10:00Z round-1-start -> 18:00Z round-2-end, including the 5h gap"
      echo "   BETWEEN rounds -- consistent with commit_push_stage's own"
      echo "   earliest-start/latest-end convention for multi-occurrence"
      echo "   stages), while the NEW summed_review_duration_ms=10800000ms"
      echo "   (2h + 1h) is the SEPARATE actual-review-time figure a caller"
      echo "   asking 'how long did review itself take' wants -- both are"
      echo "   genuine, non-invented (CT-004) measurements of two different"
      echo "   things, neither replaces the other"
    else
      echo "NOT ok check 9 (F5) FAILED: expected elapsed=28800000"
      echo "     summed_review_duration_ms=10800000, got elapsed=$F5_ELAPSED"
      echo "     summed=$F5_SUMMED"
      failx
    fi
  fi
else
  echo "NOT ok check 9 (F5): invocation failed -- $(cat "$TMP/f5.err" 2>/dev/null)"
  failx
fi

echo
echo "=== check 10 (S12-remediation follow-up round, F6): a nonexistent --review-records-dir path is REFUSED (never silently read as 'zero records found'); a genuinely-empty-but-EXISTING directory is still honestly UNMEASURED (no over-refusal) ==="
F6FX="$TMP/f6_tracker_export.json"
cat > "$F6FX" <<'JSON'
{"item": {"atm_id": "ATM-90201", "type": "Task", "status": "Fixed (→ Fixed.md)"},
 "item_history": [
   {"event_type": "Opened", "by": "User", "on_date": "2026-10-01", "created_at": "2026-10-01T08:00:00Z"},
   {"event_type": "Fixed", "by": "AI", "on_date": "2026-10-01", "created_at": "2026-10-01T09:00:00Z"}
 ]}
JSON
F6_NONEXISTENT="$TMP/f6_does_not_exist_dir"
F6_OUT_NONEXISTENT="$TMP/f6_nonexistent_out.json"
python3 "$CYCLE_REPORT" --as-of 2026-10-03 --tracker-export "$F6FX" \
  --review-records-dir "$F6_NONEXISTENT" --out "$F6_OUT_NONEXISTENT" >"$TMP/f6_nonexistent.err" 2>&1
F6_RC_NONEXISTENT=$?
if [ "$RED_MODE" = "1" ]; then
  if [ "$F6_RC_NONEXISTENT" = "0" ] && [ -f "$F6_OUT_NONEXISTENT" ]; then
    echo "ok (RED_MODE=1) check 10 (F6): pre-fix silently exits 0 on a"
    echo "   nonexistent --review-records-dir path (treated identically to a"
    echo "   genuinely-empty directory, S11.4.201(6) false-null) -- the pre-fix"
    echo "   bug this round fixes"
  else
    echo "NOT ok (RED_MODE=1) check 10 (F6): expected rc=0 + output written"
    echo "     pre-fix, got rc=$F6_RC_NONEXISTENT"
    failx
  fi
else
  if [ "$F6_RC_NONEXISTENT" = "2" ] && [ ! -f "$F6_OUT_NONEXISTENT" ] \
     && grep -qi "does not exist" "$TMP/f6_nonexistent.err" 2>/dev/null; then
    echo "ok check 10 (F6): a nonexistent --review-records-dir path is"
    echo "   REFUSED (rc=2 usage error, no output written), naming the"
    echo "   nonexistent path -- never silently treated as 'zero records"
    echo "   found' (S11.4.201(6): a blind instrument and a clean artifact"
    echo "   must never return the identical quiet result)"
  else
    echo "NOT ok check 10 (F6) FAILED: expected rc=2 + no output + a"
    echo "     'does not exist' stderr message, got rc=$F6_RC_NONEXISTENT"
    echo "     stderr: $(cat "$TMP/f6_nonexistent.err" 2>/dev/null)"
    failx
  fi
fi
# (b) golden-FALSE / no over-refusal (S11.4.201(1)): a GENUINELY-empty but
# EXISTING directory is the legitimate "no review records exist yet" state
# and MUST NOT be refused, under either polarity -- this is deliberately
# NOT gated on RED_MODE, because it must hold true on both the pre-fix and
# the fixed binary (the fix narrows the refusal to the nonexistent-path
# case, it must not start over-refusing a real empty directory).
F6_EMPTY_EXISTING="$TMP/f6_empty_existing_dir"
mkdir -p "$F6_EMPTY_EXISTING"
F6_OUT_EMPTY="$TMP/f6_empty_out.json"
python3 "$CYCLE_REPORT" --as-of 2026-10-03 --tracker-export "$F6FX" \
  --review-records-dir "$F6_EMPTY_EXISTING" --out "$F6_OUT_EMPTY" >"$TMP/f6_empty.err" 2>&1
F6_RC_EMPTY=$?
if [ "$F6_RC_EMPTY" = "0" ] && [ -f "$F6_OUT_EMPTY" ]; then
  F6_EMPTY_UNMEASURED="$(python3 -c "
import json
r = json.load(open('$F6_OUT_EMPTY'))['records'][0]
rr = next(s for s in r['stages'] if s['stage'] == 'review_rounds')
print(rr.get('elapsed') == 'UNMEASURED')
" 2>&1)"
  if [ "$F6_EMPTY_UNMEASURED" = "True" ]; then
    echo "ok check 10b (F6, golden-FALSE): a genuinely-empty-but-EXISTING"
    echo "   directory is NOT refused -- rc=0, review_rounds honestly"
    echo "   UNMEASURED (the false-positive guard: this fix must not start"
    echo "   refusing a legitimate 'no records yet' state)"
  else
    echo "NOT ok check 10b (F6) FAILED: review_rounds was not UNMEASURED for a"
    echo "     genuinely-empty-but-existing directory"
    failx
  fi
else
  echo "NOT ok check 10b (F6) FAILED: a genuinely-empty-but-EXISTING directory"
  echo "     was refused (rc=$F6_RC_EMPTY) -- over-refusal (S11.4.201(1))"
  echo "     stderr: $(cat "$TMP/f6_empty.err" 2>/dev/null)"
  failx
fi

echo
echo "=== check 11 (S12-remediation follow-up round, F7): CLOSURE_EVENT_TO_STATUS (Python) stays in sync with closeStatusMap (Go, crud.go) ==="
GO_CRUD="$ROOT/constitution/scripts/workable-items/cmd/workable-items/crud.go"
if [ ! -f "$GO_CRUD" ]; then
  echo "NOT ok check 11 (F7): $GO_CRUD not found -- cannot cross-check"
  failx
else
  F7_RESULT="$(python3 - "$CYCLE_REPORT" "$GO_CRUD" <<'PYEOF'
import importlib.util
import re
import sys

cycle_report_path, go_path = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location("cycle_report_f7", cycle_report_path)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
py_map = mod.CLOSURE_EVENT_TO_STATUS

go_src = open(go_path, encoding="utf-8").read()
marker = "var closeStatusMap = map[string]struct {"
start = go_src.index(marker)
end = go_src.index("\n}\n", start)
block = go_src[start:end]
pairs = re.findall(r'"([^"]+)",\s*"([^"]+)"', block)
if not pairs:
    print("NO_PAIRS_PARSED -- regex matched nothing in crud.go's closeStatusMap block; parser drifted from the real Go source")
    sys.exit(0)
go_map = {event: status for status, event in pairs}

# Python's CLOSURE_EVENT_TO_STATUS additionally carries "Reopened" ->
# "Reopened", which has NO counterpart in Go's closeStatusMap -- Reopened is
# not a `close --status` keyword (it is not a terminal closure at all), so
# it is deliberately excluded from this comparison, not a drift.
py_closure_only = {k: v for k, v in py_map.items() if k != "Reopened"}

mismatches = []
for event, status in go_map.items():
    if event not in py_closure_only:
        mismatches.append("Go has %r -> %r, Python CLOSURE_EVENT_TO_STATUS has no entry for %r" % (event, status, event))
    elif py_closure_only[event] != status:
        mismatches.append("event=%r: Go=%r Python=%r" % (event, status, py_closure_only[event]))
for event in py_closure_only:
    if event not in go_map:
        mismatches.append("Python CLOSURE_EVENT_TO_STATUS has %r -> %r with no Go counterpart" % (event, py_closure_only[event]))

if mismatches:
    print("MISMATCH: " + " | ".join(mismatches))
else:
    print("OK %d" % len(go_map))
PYEOF
)"
  if [[ "$F7_RESULT" == OK\ * ]]; then
    F7_N="$(echo "$F7_RESULT" | awk '{print $2}')"
    echo "ok check 11 (F7): CLOSURE_EVENT_TO_STATUS agrees with crud.go's"
    echo "   closeStatusMap on all $F7_N closure keywords (Reopened excluded"
    echo "   by design -- it is not a close keyword); this test FAILS if"
    echo "   either definition is edited without the other"
  else
    echo "NOT ok check 11 (F7) FAILED: $F7_RESULT"
    failx
  fi
fi

echo
echo "=== check 12 (S12-remediation follow-up round, F10a): combined realistic scenario -- multiple review records across multiple directories, a mixed UNKNOWN-timestamp record, and cross-file min-start/max-end evidence attribution, all together ==="
F10DIR="$TMP/f10_review_records"
mkdir -p "$F10DIR/early" "$F10DIR/mid" "$F10DIR/late"
cat > "$F10DIR/early/round_a.json" <<'JSON'
{"schema":"review-record/v1","item_id":"ATM-90400","started_at":"2026-09-01T09:00:00Z","ended_at":"2026-09-01T10:00:00Z","tokens":200}
JSON
cat > "$F10DIR/mid/round_b_unknown.json" <<'JSON'
{"schema":"review-record/v1","item_id":"ATM-90400","started_at":"UNKNOWN","ended_at":"UNKNOWN","tokens":99999}
JSON
cat > "$F10DIR/late/round_c.json" <<'JSON'
{"schema":"review-record/v1","item_id":"ATM-90400","started_at":"2026-09-05T14:00:00Z","ended_at":"2026-09-05T16:30:00Z","tokens":300}
JSON
F10FX="$TMP/f10_tracker_export.json"
cat > "$F10FX" <<'JSON'
{"item": {"atm_id": "ATM-90400", "type": "Task", "status": "Fixed (→ Fixed.md)"},
 "item_history": [
   {"event_type": "Opened", "by": "User", "on_date": "2026-09-01", "created_at": "2026-09-01T08:00:00Z"},
   {"event_type": "Fixed", "by": "AI", "on_date": "2026-09-05", "created_at": "2026-09-05T17:00:00Z"}
 ]}
JSON
F10OUT="$TMP/f10_out.json"
python3 "$CYCLE_REPORT" --as-of 2026-10-03 --tracker-export "$F10FX" \
  --review-records-dir "$F10DIR" --out "$F10OUT" >"$TMP/f10.err" 2>&1
if [ -f "$F10OUT" ]; then
  F10_RESULT="$(python3 -c "
import json, os
r = json.load(open('$F10OUT'))['records'][0]
rr = next(s for s in r['stages'] if s['stage'] == 'review_rounds')
# MINOR fix (independent review): a bare substring check ('early' in path /
# 'late' in path) against an absolute temp-dir path could theoretically be
# masked by a temp-dir NAME that happens to contain 'early'/'late' as a
# substring (mktemp's output is not controlled by this test). Tightened to
# EXACT equality against the one, fully-constructed expected path for each
# fixture file -- not a substring of it.
expected_start = os.path.join('$F10DIR', 'early', 'round_a.json')
expected_end = os.path.join('$F10DIR', 'late', 'round_c.json')
ok = (
    rr.get('elapsed') == 372600000
    and rr.get('tokens') == 500
    and rr.get('summed_review_duration_ms') == 12600000
    and rr['start']['evidence_path'] == expected_start
    and rr['end']['evidence_path'] == expected_end
)
print(ok)
" 2>&1)"
  if [ "$F10_RESULT" = "True" ]; then
    echo "ok check 12 (F10a): a realistic combined scenario -- 3 review rounds"
    echo "   across 3 directories, one carrying an honest UNKNOWN placeholder"
    echo "   (its tokens=99999 correctly excluded), the earliest-start evidence"
    echo "   attributed to early/, the latest-end evidence attributed to late/"
    echo "   (a DIFFERENT file) -- elapsed=372600000ms, tokens=500,"
    echo "   summed_review_duration_ms=12600000ms, all correct together in one"
    echo "   realistic scenario (F1 + F2 + F5 combined, not merely in isolation)"
  else
    echo "NOT ok check 12 (F10a) FAILED (comparator result: '$F10_RESULT')"
    echo "     $(cat "$F10OUT" 2>/dev/null)"
    failx
  fi
else
  echo "NOT ok check 12 (F10a): invocation failed -- $(cat "$TMP/f10.err" 2>/dev/null)"
  failx
fi

echo
echo "=== check 13 (S12-remediation follow-up round, F13): an INVERTED review-record span (end before start, a reviewer data-entry error) is EXCLUDED from summed_review_duration_ms entirely -- never allowed to silently cancel out a real round's positive duration ==="
# review_record.py's own --started-at/--ended-at CLI flags carry NO
# end->=start validation (confirmed directly against its argparse
# definitions -- same instrument F5's docstring already relied on), so an
# inverted span is a structurally-possible reviewer data-entry error, not a
# hypothetical. Reviewer's exact reproduction: round a 10:00->12:00 [+2h],
# round b 15:00->13:00 [inverted, -2h] -- the PRE-fix unconditional `+=`
# let the inverted record's NEGATIVE duration cancel out round a's real
# +2h, reporting summed_review_duration_ms=0 (hiding the review that
# genuinely happened). This fixture also DELIBERATELY keeps round b's own
# end instant (13:00) later than round a's end instant (12:00), so round b
# still wins the `elapsed` field's max-end competition either way -- this
# proves the fix does NOT also accidentally exclude the inverted record
# from `elapsed`'s own min-start/max-end evidence attribution (F1, a
# SEPARATE, pre-existing concern this round's fix is explicitly scoped NOT
# to touch), nor from the token total (F2, likewise untouched).
F13DIR="$TMP/f13_review_records"
mkdir -p "$F13DIR"
cat > "$F13DIR/round_a.json" <<'JSON'
{"schema":"review-record/v1","item_id":"ATM-90500","started_at":"2026-10-02T10:00:00Z","ended_at":"2026-10-02T12:00:00Z","tokens":1000}
JSON
cat > "$F13DIR/round_b_inverted.json" <<'JSON'
{"schema":"review-record/v1","item_id":"ATM-90500","started_at":"2026-10-02T15:00:00Z","ended_at":"2026-10-02T13:00:00Z","tokens":2000}
JSON
F13FX="$TMP/f13_tracker_export.json"
cat > "$F13FX" <<'JSON'
{"item": {"atm_id": "ATM-90500", "type": "Task", "status": "Fixed (→ Fixed.md)"},
 "item_history": [
   {"event_type": "Opened", "by": "User", "on_date": "2026-10-02", "created_at": "2026-10-02T08:00:00Z"},
   {"event_type": "Fixed", "by": "AI", "on_date": "2026-10-02", "created_at": "2026-10-02T19:00:00Z"}
 ]}
JSON
F13OUT="$TMP/f13_out.json"
python3 "$CYCLE_REPORT" --as-of 2026-10-03 --tracker-export "$F13FX" \
  --review-records-dir "$F13DIR" --out "$F13OUT" >"$TMP/f13.err" 2>&1
if [ -f "$F13OUT" ]; then
  F13_RESULT="$(python3 -c "
import json, os
r = json.load(open('$F13OUT'))['records'][0]
rr = next(s for s in r['stages'] if s['stage'] == 'review_rounds')
expected_end = os.path.join('$F13DIR', 'round_b_inverted.json')
print('%s|%s|%s|%s' % (
    rr.get('elapsed'), rr.get('tokens'), rr.get('summed_review_duration_ms'),
    rr['end']['evidence_path'] == expected_end))
" 2>&1)"
  IFS='|' read -r F13_ELAPSED F13_TOKENS F13_SUMMED F13_END_IS_INVERTED <<< "$F13_RESULT"
  if [ "$RED_MODE" = "1" ]; then
    if [ "$F13_SUMMED" = "0" ] && [ "$F13_ELAPSED" = "10800000" ] && [ "$F13_TOKENS" = "3000" ] \
       && [ "$F13_END_IS_INVERTED" = "True" ]; then
      echo "ok (RED_MODE=1) check 13 (F13): summed_review_duration_ms=0 on the"
      echo "   pre-fix binary -- the inverted round's -7200000ms cancelled out"
      echo "   round a's real +7200000ms (exactly the reviewer's reproduction;"
      echo "   elapsed=10800000 and tokens=3000 are UNAFFECTED by this bug,"
      echo "   confirming it is isolated to the sum)"
    else
      echo "NOT ok (RED_MODE=1) check 13 (F13): expected summed=0"
      echo "     elapsed=10800000 tokens=3000 end-is-inverted=True, got"
      echo "     elapsed=$F13_ELAPSED tokens=$F13_TOKENS summed=$F13_SUMMED"
      echo "     end-is-inverted=$F13_END_IS_INVERTED -- fix present or"
      echo "     reproduction assumption wrong"
      failx
    fi
  else
    if [ "$F13_SUMMED" = "7200000" ] && [ "$F13_ELAPSED" = "10800000" ] && [ "$F13_TOKENS" = "3000" ] \
       && [ "$F13_END_IS_INVERTED" = "True" ]; then
      echo "ok check 13 (F13): summed_review_duration_ms=7200000 (round a's own"
      echo "   +2h ONLY -- round b's inverted span correctly EXCLUDED, matching"
      echo "   the UNKNOWN-timestamp precedent: an un-timeable round contributes"
      echo "   NOTHING, never a negative number); elapsed=10800000 and"
      echo "   tokens=3000 are UNCHANGED from the pre-fix run (this fix touches"
      echo "   ONLY the sum), and the inverted round STILL legitimately wins"
      echo "   elapsed's max-end evidence attribution (end.evidence_path =="
      echo "   round_b_inverted.json) -- confirming this fix did NOT also"
      echo "   silently hide the inverted record from elapsed's own min-"
      echo "   start/max-end selection, which stays this function's PRE-"
      echo "   EXISTING, out-of-scope-for-this-round behaviour"
    else
      echo "NOT ok check 13 (F13) FAILED: expected summed=7200000 elapsed=10800000"
      echo "     tokens=3000 end-is-inverted=True, got elapsed=$F13_ELAPSED"
      echo "     tokens=$F13_TOKENS summed=$F13_SUMMED end-is-inverted=$F13_END_IS_INVERTED"
      failx
    fi
  fi
else
  echo "NOT ok check 13 (F13): invocation failed -- $(cat "$TMP/f13.err" 2>/dev/null)"
  failx
fi

echo
echo "=== check 8/8: pre-existing T023 fixture suite + full suite still GREEN (no regression) ==="
if bash "$FC/tests/test_cycle_report_red.sh" >"$TMP/preexisting.out" 2>&1; then
  echo "ok test_cycle_report_red.sh (T023 contract suite) still exits 0 after this fix"
else
  echo "NOT ok test_cycle_report_red.sh regressed -- $(tail -20 "$TMP/preexisting.out")"
  failx
fi

echo
echo "=== §1.1 paired mutation (F9 fix: this mutation now GENUINELY runs inline, closing the false claim a prior revision of this header made) ==="
# Mechanically reverts flag_status_desync() to the ORIGINAL bare
# `event_type != items_status` comparison this guard exists to catch (the
# fix-commit's own revert, §11.4.115(F)/§11.4.227's canonical mutation
# class) and asserts the golden-good Fixed case (check 1b above) flips from
# PASS (no STATUS_DESYNC) to FAIL (STATUS_DESYNC fires) -- proving this
# guard genuinely discriminates and is not a tautology.
if [ "$RED_MODE" = "1" ]; then
  echo "skip (RED_MODE=1): the paired mutation is itself defined relative to the"
  echo "   FIXED function; it is only meaningful run against the fixed binary"
else
  cp "$CYCLE_REPORT" "$MUT"
  python3 - "$MUT" <<'PYEOF'
import sys

path = sys.argv[1]
src = open(path, encoding="utf-8").read()
marker = "def flag_status_desync(items_status, history):"
start = src.index(marker)
end = src.index("\ndef ", start + len(marker))
mutated_fn = (
    marker + "\n"
    "    # MUTATED (§1.1 paired mutation, inline, F9 fix): reverted to the\n"
    "    # pre-ATM-1055 bare comparison -- the S11.4.33 canonical mapping\n"
    "    # lookup is deliberately deleted.\n"
    "    last_status_event = next(\n"
    "        (r for r in reversed(history) if r[\"event_type\"] in STATUS_DEFINING_EVENTS), None)\n"
    "    if last_status_event is None or items_status is None:\n"
    "        return False\n"
    "    return last_status_event[\"event_type\"] != items_status\n"
)
new_src = src[:start] + mutated_fn + src[end:]
if new_src == src:
    raise SystemExit("mutation did not change the source -- marker not found correctly")
open(path, "w", encoding="utf-8").write(new_src)
PYEOF
  if [ $? != 0 ]; then
    echo "NOT ok paired mutation setup FAILED -- could not mechanically mutate"
    echo "     flag_status_desync (marker not found -- source drifted?)"
    failx
  else
    MUTFX="$TMP/golden_Fixed_for_mutation.json"
    cat > "$MUTFX" <<'JSON'
{"item": {"atm_id": "ATM-90199", "type": "Task", "status": "Fixed (→ Fixed.md)"},
 "item_history": [
   {"event_type": "Opened", "by": "User", "on_date": "2026-08-01", "created_at": "2026-08-01T08:00:00Z"},
   {"event_type": "Fixed", "by": "AI", "on_date": "2026-08-01", "created_at": "2026-08-01T09:00:00Z"}
 ]}
JSON
    MUTOUT="$TMP/mutation_out.json"
    python3 "$MUT" --as-of 2026-10-03 --tracker-export "$MUTFX" --out "$MUTOUT" >"$TMP/mutation.err" 2>&1
    if [ -f "$MUTOUT" ]; then
      MUT_HAS_DESYNC="$(python3 -c "
import json
r = json.load(open('$MUTOUT'))['records'][0]
print('STATUS_DESYNC' in r.get('data_quality_flags', []))
" 2>&1)"
      if [ "$MUT_HAS_DESYNC" = "True" ]; then
        echo "ok paired mutation: reverting to the bare event_type!=items_status"
        echo "   compare flips the golden-good Fixed case from PASS (no"
        echo "   STATUS_DESYNC, check 1b above) to FAIL (STATUS_DESYNC fires) --"
        echo "   the guard genuinely discriminates, it is not a tautology"
      else
        echo "NOT ok paired mutation: the mutated (bare-compare) binary did NOT"
        echo "     flip to STATUS_DESYNC=True on a correctly-closed item --"
        echo "     mutation is a refused tautology (§11.4.115(F))"
        failx
      fi
    else
      echo "NOT ok paired mutation: mutated binary invocation failed --"
      echo "     $(cat "$TMP/mutation.err" 2>/dev/null)"
      failx
    fi
  fi
fi

echo
echo "=== §1.1 paired mutation #2 (F13 fix): genuinely removing the e_dt >= s_dt guard flips check 13's golden-good result from PASS to FAIL ==="
# Mechanically removes ONLY the sign-check this round's F13 fix adds
# (the fix-commit's own revert, §11.4.115(F)/§11.4.227's canonical
# mutation class) and asserts the check-13 fixture's summed_review_
# duration_ms flips from the fixed value (7200000, round a's +2h only) to
# the pre-fix bug value (0, round a's +2h cancelled by round b's inverted
# -2h) -- proving check 13 genuinely discriminates on this guard and is
# not a tautology.
if [ "$RED_MODE" = "1" ]; then
  echo "skip (RED_MODE=1): this mutation is itself defined relative to the FIXED"
  echo "   function; it is only meaningful run against the fixed binary"
else
  cp "$CYCLE_REPORT" "$MUT2"
  python3 - "$MUT2" <<'PYEOF'
import sys

path = sys.argv[1]
src = open(path, encoding="utf-8").read()
old = (
    "                if e_dt >= s_dt:\n"
    "                    summed_duration_ms += to_ms((e_dt - s_dt).total_seconds())\n"
)
if old not in src:
    raise SystemExit("mutation setup FAILED -- F13 guard marker not found "
                      "(source drifted from the fix this test expects?)")
new = "                summed_duration_ms += to_ms((e_dt - s_dt).total_seconds())\n"
new_src = src.replace(old, new, 1)
if new_src == src:
    raise SystemExit("mutation did not change the source")
open(path, "w", encoding="utf-8").write(new_src)
PYEOF
  if [ $? != 0 ]; then
    echo "NOT ok paired mutation #2 setup FAILED -- could not mechanically mutate"
    echo "     review_rounds_stage's e_dt >= s_dt guard (marker not found --"
    echo "     source drifted?)"
    failx
  else
    MUT2OUT="$TMP/mutation2_out.json"
    python3 "$MUT2" --as-of 2026-10-03 --tracker-export "$F13FX" \
      --review-records-dir "$F13DIR" --out "$MUT2OUT" >"$TMP/mutation2.err" 2>&1
    if [ -f "$MUT2OUT" ]; then
      MUT2_SUMMED="$(python3 -c "
import json
r = json.load(open('$MUT2OUT'))['records'][0]
rr = next(s for s in r['stages'] if s['stage'] == 'review_rounds')
print(rr.get('summed_review_duration_ms'))
" 2>&1)"
      if [ "$MUT2_SUMMED" = "0" ]; then
        echo "ok paired mutation #2: removing the e_dt >= s_dt guard flips"
        echo "   summed_review_duration_ms from 7200000 (fixed) back to 0"
        echo "   (the pre-fix bug, exactly the reviewer's reproduction) --"
        echo "   check 13 genuinely discriminates, it is not a tautology"
      else
        echo "NOT ok paired mutation #2: the mutated (guard-removed) binary did"
        echo "     NOT flip summed_review_duration_ms back to 0 (got"
        echo "     '$MUT2_SUMMED') -- mutation is a refused tautology"
        echo "     (§11.4.115(F))"
        failx
      fi
    else
      echo "NOT ok paired mutation #2: mutated binary invocation failed --"
      echo "     $(cat "$TMP/mutation2.err" 2>/dev/null)"
      failx
    fi
  fi
fi

exit $fail
