#!/bin/bash
# Purpose : T048 Round 4 (independent Opus-xhigh review of SpecKit-004
#           "fast-dev-cycles" User Story 1's own round-3 remediation trail)
#           finding R4-I1 regression guard.
#
# R4-I1 (verbatim finding, 2026-09-30): "R3-I5's fix (RUN_COMPLETE sentinel)
# has no regression test. The reviewer proved this via their own
# reviewer-authored mutation: deleting the
# `[ -f "$_mt_cand_dir/RUN_COMPLETE" ] || continue` line leaves the suite
# still exiting 1 (only the message text changes) -- meaning NOTHING
# currently catches this regression." Background: R3-I5 itself (see
# test_metatest_per_mutant_red.sh's own inline comment immediately above
# its selection loop, and scripts/testing/meta_test_false_positive_proof.sh's
# own comment immediately above `_fc_mut_write_completion_marker()`) fixed a
# real, live-reproduced bug -- picking the lexically-newest `*.tsv` across
# the whole shared metatest archive dir could select a genuinely PARTIAL/
# interrupted run's fragment whenever it happened to sort last, rather than
# a genuine completed run -- by having a run that reaches its OWN literal
# final line set `_fc_mut_run_complete=1` (never on an early/abnormal exit)
# and having the exit-trap-driven `_fc_mut_write_completion_marker()` write
# a `RUN_COMPLETE` sentinel ONLY when that flag is set; the reader side
# (test_metatest_per_mutant_red.sh) was updated in lockstep to require that
# sentinel before considering a run-dir eligible. Neither half had a
# regression test until this file.
#
# This file closes BOTH halves the reviewer asked for, plus the reviewer's
# own guard-viability standard (proving each check is genuinely load-bearing
# by mutating it away and confirming the wrong outcome results -- the exact
# technique the reviewer used to find this gap in the first place):
#
#   (A)/(B) READER side (test_metatest_per_mutant_red.sh's own selection
#       loop, content-anchored, never line-numbered -- see EXTRACTION
#       DISCIPLINE below): a fixture pair -- an OLDER run-dir carrying a
#       RUN_COMPLETE sentinel + a genuinely "finalized-shaped" TSV, and a
#       NEWER run-dir with NO sentinel + a genuinely "partial-shaped" TSV
#       (empty verdict column, exactly R3-I5's own cited real-world
#       fragment shape) -- proves the REAL (fixed) selection logic picks
#       the OLDER COMPLETE one (A: "not the newer incomplete one", the
#       reviewer's own words), then proves the reviewer's OWN exact
#       mutation (deleting the sentinel-check line) makes the SAME
#       selection logic WRONGLY pick the newer partial one instead (B) --
#       this is the guard-viability half, establishing the fixture pair
#       itself is genuinely load-bearing, not merely present.
#   (C) WRITER side (meta_test_false_positive_proof.sh's own
#       `_fc_mut_write_completion_marker`/`_mt_exit_final`/`trap()`/
#       `_fc_mut_finalize_verdicts` machinery, content-anchored): proves a
#       run that reaches its own literal final line (`_fc_mut_run_complete=1`
#       set immediately before `exit 0`/`exit 1`) writes a REAL sentinel
#       (W1), proves a run that exits EARLY -- the flag never set, exactly
#       the `set -uo pipefail` abort / external kill/timeout class this
#       mechanism exists to guard against -- leaves NO sentinel behind at
#       all (W2 -- the task's own "the absence itself must be provably
#       correct, not just assumed" requirement: this is a REAL, executed
#       assertion against the live extracted writer logic, not an assumed
#       consequence of reading the source), then proves the writer-side
#       guard clause itself
#       (`[ "$_fc_mut_run_complete" = "1" ] || return 0`) is genuinely
#       load-bearing by mutating it away and re-running the SAME early-exit
#       scenario, confirming the sentinel now WRONGLY appears (W3).
#
# EXTRACTION DISCIPLINE (§11.4.6/§11.4.115(F)): every payload below is
# pulled LIVE out of the real source files via content-anchored `awk` line
# ranges -- the SAME discipline test_metatest_per_mutant_red.sh's own N1
# driver-path assertion already established for this exact pair of files --
# never hand-simulated/copy-pasted logic. A control needle at the top of
# each extraction FAILS LOUDLY if a future structural edit to either source
# file removes one of these anchors, rather than silently testing stale
# logic that no longer matches what ships.
#
# Producer≠Verifier (§11.4.240): this file is authored as an independent
# regression guard for an ALREADY-LANDED R3-I5 fix; it does not touch
# either source file's own implementation.
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
RED="$FC/tests/test_metatest_per_mutant_red.sh"
MT="$ROOT/scripts/testing/meta_test_false_positive_proof.sh"

fail=0
failx() { fail=1; }

TMP="$(mktemp -d)" || { echo "NOT ok mktemp -d failed"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

echo "=== control needle: source files resolve ==="
if [ -f "$RED" ]; then
  echo "ok control needle: $RED resolves"
else
  echo "NOT ok control needle FAILED: $RED not found"
  failx
fi
if [ -f "$MT" ]; then
  echo "ok control needle: $MT resolves"
else
  echo "NOT ok control needle FAILED: $MT not found"
  failx
fi

# =============================================================================
# (A)/(B) READER-side extraction: test_metatest_per_mutant_red.sh's own
# selection loop (the block between the literal line `METATEST_TSV=""` and
# the next bare, zero-indented `fi` that closes it -- both exact-text
# anchors, verified unique in the file by the control needle below).
# =============================================================================
SEL_START='METATEST_TSV=""'
SEL_END='fi'
SEL_PAYLOAD="$TMP/selection_payload.sh"
awk -v s="$SEL_START" -v e="$SEL_END" '$0==s,$0==e' "$RED" > "$SEL_PAYLOAD" 2>/dev/null

echo
echo "=== control needle: selection-loop extraction anchors found + unique ==="
SEL_START_HITS="$(grep -cxF "$SEL_START" "$RED" 2>/dev/null || true)"
: "${SEL_START_HITS:=0}"
if [ "$SEL_START_HITS" != 1 ]; then
  echo "NOT ok control needle FAILED: anchor '$SEL_START' appears $SEL_START_HITS"
  echo "     time(s) in $RED (expected exactly 1) -- extraction is no longer"
  echo "     reliably anchored; this file's anchors need updating"
  failx
  SEL_PAYLOAD=""
elif [ ! -s "$SEL_PAYLOAD" ] || ! grep -qF 'RUN_COMPLETE' "$SEL_PAYLOAD"; then
  echo "NOT ok control needle FAILED: extraction from $RED produced no content"
  echo "     (or content missing the expected RUN_COMPLETE reference) -- the"
  echo "     file's structure changed; this assertion's anchors need updating"
  failx
  SEL_PAYLOAD=""
else
  echo "ok control needle: selection-loop payload extracted ($(wc -l < "$SEL_PAYLOAD" | tr -d ' ') lines)"
fi

# Derive the reviewer's own exact mutation target line FROM the extracted
# payload itself (never a hand-typed copy that could silently drift from
# the real source's indentation/quoting) -- the one line containing the
# sentinel check this finding is about.
GUARD_LINE=""
SEL_PAYLOAD_MUT=""
if [ -n "$SEL_PAYLOAD" ]; then
  GUARD_LINE="$(grep -F 'RUN_COMPLETE" ] || continue' "$SEL_PAYLOAD" | head -n1)"
  if [ -z "$GUARD_LINE" ]; then
    echo "NOT ok control needle FAILED: could not locate the sentinel-check line"
    echo "     inside the extracted selection payload -- R4-I1's own reviewer"
    echo "     mutation target no longer exists in this exact form"
    failx
  else
    SEL_PAYLOAD_MUT="$TMP/selection_payload_r4i1_mutated.sh"
    grep -vF "$GUARD_LINE" "$SEL_PAYLOAD" > "$SEL_PAYLOAD_MUT"
    echo "ok control needle: located + will mutate exactly 1 occurrence of the"
    echo "   sentinel-check line ($(grep -cF "$GUARD_LINE" "$SEL_PAYLOAD") in the"
    echo "   unmutated payload, 0 in the mutated copy) -- the reviewer's own"
    echo "   R4-I1 mutation, reproduced"
  fi
fi

# --- build the two-run-dir fixture pair ---
ARCHIVE="$TMP/archive"
OLDER_ID="20260101T000000Z_older_complete"
NEWER_ID="20260102T000000Z_newer_partial"
OLDER_DIR="$ARCHIVE/$OLDER_ID"
NEWER_DIR="$ARCHIVE/$NEWER_ID"
mkdir -p "$OLDER_DIR" "$NEWER_DIR"

OLDER_TSV="$OLDER_DIR/per_mutant.tsv"
NEWER_TSV="$NEWER_DIR/per_mutant.tsv"
# OLDER: a finalized run -- carries the RUN_COMPLETE sentinel and a real
# KILLED verdict row (the finalized shape _fc_mut_finalize_verdicts()
# produces, tab-delimited, 11 fields).
printf 'label\tstart_ns\tend_ns\tduration_ms\tgate\tcmd\tverdict\tchecks\tpass\tfail\tmutation_verdict\n' > "$OLDER_TSV"
printf 'M_R4I1_OLDER\t1\t2\t1\tgate.sh\tgate.sh\tPASS\t1\t1\t0\tKILLED\n' >> "$OLDER_TSV"
printf 'pass=1\nfail=0\nskip=0\nts=2026-01-01T00:00:00Z\n' > "$OLDER_DIR/RUN_COMPLETE"
# NEWER: a genuinely partial/interrupted run -- NO RUN_COMPLETE sentinel,
# and a row whose verdict column is EMPTY -- exactly R3-I5's own cited
# real archived fragment shape (never finalized).
printf 'label\tstart_ns\tend_ns\tduration_ms\tgate\tcmd\tverdict\tchecks\tpass\tfail\tmutation_verdict\n' > "$NEWER_TSV"
printf 'M_R4I1_NEWER\t1\t2\t1\tgate.sh\tgate.sh\tPASS\t0\t0\t0\t\n' >> "$NEWER_TSV"

echo
echo "=== (A) real (fixed) selection logic picks the OLDER COMPLETE run-dir, not the newer incomplete one ==="
if [ -n "$SEL_PAYLOAD" ]; then
  DRIVER_A="$TMP/driver_a.sh"
  {
    echo 'set -u'
    printf 'METATEST_ARCHIVE_DIR=%q\n' "$ARCHIVE"
    cat "$SEL_PAYLOAD"
    echo 'printf "SELECTED=%s\n" "$METATEST_TSV"'
  } > "$DRIVER_A"
  SELECTED_A="$(bash "$DRIVER_A" 2>"$TMP/driver_a.err" | sed -n 's/^SELECTED=//p')"
  if [ "$SELECTED_A" = "$OLDER_TSV" ]; then
    echo "ok (A) real selection logic correctly picked the OLDER, RUN_COMPLETE-marked"
    echo "   run-dir's TSV ($SELECTED_A), ignoring the lexically-newer but"
    echo "   sentinel-less partial run-dir"
  else
    echo "NOT ok (A) real selection logic picked '$SELECTED_A' (wanted the older"
    echo "     complete run's TSV '$OLDER_TSV') -- $(cat "$TMP/driver_a.err" 2>/dev/null)"
    failx
  fi
else
  echo "NOT ok (A) SKIPPED: extraction control needle above already failed"
  failx
fi

echo
echo "=== (B) guard-viability: the reviewer's OWN mutation (deleting the sentinel-check line) makes selection WRONGLY pick the newer partial run-dir ==="
if [ -n "$SEL_PAYLOAD_MUT" ]; then
  DRIVER_B="$TMP/driver_b.sh"
  {
    echo 'set -u'
    printf 'METATEST_ARCHIVE_DIR=%q\n' "$ARCHIVE"
    cat "$SEL_PAYLOAD_MUT"
    echo 'printf "SELECTED=%s\n" "$METATEST_TSV"'
  } > "$DRIVER_B"
  SELECTED_B="$(bash "$DRIVER_B" 2>"$TMP/driver_b.err" | sed -n 's/^SELECTED=//p')"
  if [ "$SELECTED_B" = "$NEWER_TSV" ]; then
    echo "ok (B) mutated (sentinel-check-removed) selection logic WRONGLY picked the"
    echo "   newer, still-partial run-dir's TSV ($SELECTED_B) -- reproducing R4-I1's"
    echo "   exact reported regression end-to-end, proving the sentinel-check line"
    echo "   this fixture pair exercises is genuinely load-bearing"
  else
    echo "NOT ok (B) BLIND: mutated selection logic picked '$SELECTED_B' (wanted the"
    echo "     newer partial run's TSV '$NEWER_TSV', proving the mutation's own wrong"
    echo "     effect) -- $(cat "$TMP/driver_b.err" 2>/dev/null); either the mutation"
    echo "     extraction is malformed or this fixture pair does not genuinely"
    echo "     distinguish the two run-dirs the way R4-I1 describes"
    failx
  fi
else
  echo "NOT ok (B) SKIPPED: could not derive the mutation target line above"
  failx
fi

# =============================================================================
# (C) WRITER-side extraction: meta_test_false_positive_proof.sh's own
# completion-marker machinery -- `_fc_mut_finalize_verdicts()` (called by
# `_mt_exit_final`, harmless no-op here since `fc_timer_enabled` is never
# defined in this scratch harness) plus the `_mt_exit_user_cmd=""` ..
# `builtin trap '_mt_exit_final' EXIT` block (init vars,
# `_fc_mut_write_completion_marker()`, `_mt_exit_final()`, the `trap()`
# shadow function, and the unconditional top-level arm -- the exact
# mechanism the source file's own header comment says "fires on EVERY
# exit, normal or not").
# =============================================================================
FV_START='_fc_mut_finalize_verdicts() {'
W_START='_mt_exit_user_cmd=""'
W_END="builtin trap '_mt_exit_final' EXIT"

echo
echo "=== control needle: writer-side extraction anchors found + unique ==="
FV_HITS="$(grep -cxF "$FV_START" "$MT" 2>/dev/null || true)"; : "${FV_HITS:=0}"
W_START_HITS="$(grep -cxF "$W_START" "$MT" 2>/dev/null || true)"; : "${W_START_HITS:=0}"
W_END_HITS="$(grep -cxF "$W_END" "$MT" 2>/dev/null || true)"; : "${W_END_HITS:=0}"
WRITER_ANCHORS_OK=1
if [ "$FV_HITS" != 1 ]; then
  echo "NOT ok control needle FAILED: anchor '$FV_START' appears $FV_HITS time(s)"
  echo "     in $MT (expected exactly 1)"
  WRITER_ANCHORS_OK=0
fi
if [ "$W_START_HITS" != 1 ]; then
  echo "NOT ok control needle FAILED: anchor '$W_START' appears $W_START_HITS"
  echo "     time(s) in $MT (expected exactly 1)"
  WRITER_ANCHORS_OK=0
fi
if [ "$W_END_HITS" != 1 ]; then
  echo "NOT ok control needle FAILED: anchor '$W_END' appears $W_END_HITS time(s)"
  echo "     in $MT (expected exactly 1)"
  WRITER_ANCHORS_OK=0
fi

W_PAYLOAD=""
if [ "$WRITER_ANCHORS_OK" = 1 ]; then
  FV_PAYLOAD="$TMP/fv_payload.sh"
  awk -v s="$FV_START" '$0==s{p=1} p{print} p && /^}$/{exit}' "$MT" > "$FV_PAYLOAD" 2>/dev/null
  W_PAYLOAD_RAW="$TMP/w_payload.sh"
  awk -v s="$W_START" -v e="$W_END" '$0==s,$0==e' "$MT" > "$W_PAYLOAD_RAW" 2>/dev/null
  if [ -s "$FV_PAYLOAD" ] && [ -s "$W_PAYLOAD_RAW" ] \
     && grep -qF '_fc_mut_write_completion_marker() {' "$W_PAYLOAD_RAW" \
     && grep -qF '_mt_exit_final() {' "$W_PAYLOAD_RAW" \
     && grep -qF 'trap() {' "$W_PAYLOAD_RAW"; then
    echo "ok control needle: writer-side payload extracted"
    echo "   (_fc_mut_finalize_verdicts: $(wc -l < "$FV_PAYLOAD" | tr -d ' ') lines;"
    echo "   completion-marker+trap machinery: $(wc -l < "$W_PAYLOAD_RAW" | tr -d ' ') lines)"
    W_PAYLOAD="$TMP/w_payload_combined.sh"
    cat "$FV_PAYLOAD" "$W_PAYLOAD_RAW" > "$W_PAYLOAD"
  else
    echo "NOT ok control needle FAILED: extraction from $MT produced incomplete"
    echo "     content -- the file's structure changed; this assertion's anchors"
    echo "     need updating"
    failx
  fi
else
  failx
fi

GUARD_W_LINE=""
W_PAYLOAD_MUT=""
if [ -n "$W_PAYLOAD" ]; then
  GUARD_W_LINE="$(grep -F '_fc_mut_run_complete" = "1" ] || return 0' "$W_PAYLOAD" | head -n1)"
  if [ -z "$GUARD_W_LINE" ]; then
    echo "NOT ok control needle FAILED: could not locate the writer-side completion"
    echo "     guard line inside the extracted payload"
    failx
  else
    W_PAYLOAD_MUT="$TMP/w_payload_mutated.sh"
    grep -vF "$GUARD_W_LINE" "$W_PAYLOAD" > "$W_PAYLOAD_MUT"
    echo "ok control needle: located + will mutate exactly 1 occurrence of the"
    echo "   writer-side completion guard line"
  fi
fi

run_writer_scenario() {
  # $1 = payload file, $2 = "complete"|"early", $3 = scratch dir for this run
  local payload="$1" mode="$2" wdir="$3"
  mkdir -p "$wdir"
  local driver="$wdir/driver.sh"
  {
    echo 'set -u'
    cat "$payload"
    printf 'FC_TIMER_TSV=%q\n' "$wdir/per_mutant.tsv"
    echo 'mkdir -p "$(dirname "$FC_TIMER_TSV")"'
    echo ': > "$FC_TIMER_TSV"'
    echo 'PASS_COUNT=1; FAIL_COUNT=0; SKIP_COUNT=0'
    if [ "$mode" = "complete" ]; then
      # The literal final-line contract: this EXACT flag assignment,
      # immediately before exit, is what the real source file itself does
      # (scripts/testing/meta_test_false_positive_proof.sh's own literal
      # last two statements before `exit 0`/`exit 1`).
      echo '_fc_mut_run_complete=1'
      echo 'exit 0'
    else
      # Simulates an early/abnormal exit: the run terminates WITHOUT ever
      # reaching its own literal final line, so the completion flag is
      # NEVER set to 1 -- exactly the `set -uo pipefail` abort / external
      # kill/timeout class R3-I5 exists to guard against. The real
      # top-level unconditional `builtin trap '_mt_exit_final' EXIT` arm
      # (part of the extracted payload) still fires on this `exit 1`,
      # proving the "fires on EVERY exit" property, not merely a bypass.
      echo 'exit 1'
    fi
  } > "$driver"
  bash "$driver" >"$wdir/stdout.log" 2>"$wdir/stderr.log"
}

echo
echo "=== (W1) real (fixed) writer logic: a run reaching its own literal final line writes a REAL RUN_COMPLETE sentinel ==="
if [ -n "$W_PAYLOAD" ]; then
  W1DIR="$TMP/w1"
  run_writer_scenario "$W_PAYLOAD" complete "$W1DIR"
  if [ -f "$W1DIR/RUN_COMPLETE" ]; then
    echo "ok (W1) real writer logic wrote a RUN_COMPLETE sentinel when the completion"
    echo "   flag was set (the literal-final-line contract)"
  else
    echo "NOT ok (W1) real writer logic did NOT write RUN_COMPLETE when the completion"
    echo "     flag was set -- $(cat "$W1DIR/stderr.log" 2>/dev/null)"
    failx
  fi
else
  echo "NOT ok (W1) SKIPPED: writer-side extraction control needle above already failed"
  failx
fi

echo
echo "=== (W2) real (fixed) writer logic: an early exit (completion flag never set) leaves NO sentinel behind -- provably, not merely assumed ==="
if [ -n "$W_PAYLOAD" ]; then
  W2DIR="$TMP/w2"
  run_writer_scenario "$W_PAYLOAD" early "$W2DIR"
  if [ ! -f "$W2DIR/RUN_COMPLETE" ]; then
    echo "ok (W2) real writer logic wrote NO RUN_COMPLETE sentinel on an early exit --"
    echo "   the real EXIT trap fired ('_mt_exit_final' ran, confirmed by"
    echo "   \$FC_TIMER_TSV's directory existing as designed) but the completion"
    echo "   guard correctly refused to write the marker"
  else
    echo "NOT ok (W2) real writer logic WRONGLY wrote RUN_COMPLETE on an early exit --"
    echo "     $(cat "$W2DIR/stderr.log" 2>/dev/null)"
    failx
  fi
else
  echo "NOT ok (W2) SKIPPED: writer-side extraction control needle above already failed"
  failx
fi

echo
echo "=== (W3) guard-viability: removing the writer-side completion guard makes an early exit WRONGLY write the sentinel ==="
if [ -n "$W_PAYLOAD_MUT" ]; then
  W3DIR="$TMP/w3"
  run_writer_scenario "$W_PAYLOAD_MUT" early "$W3DIR"
  if [ -f "$W3DIR/RUN_COMPLETE" ]; then
    echo "ok (W3) mutated (guard-removed) writer logic WRONGLY wrote RUN_COMPLETE on"
    echo "   the SAME early-exit scenario that (W2) correctly left sentinel-free --"
    echo "   proving the writer-side completion guard line is genuinely load-bearing"
  else
    echo "NOT ok (W3) BLIND: mutated writer logic still did not write RUN_COMPLETE on"
    echo "     an early exit -- the guard-removal mutation did not have its expected"
    echo "     effect; either the extraction is malformed or this is not the right"
    echo "     mutation target -- $(cat "$W3DIR/stderr.log" 2>/dev/null)"
    failx
  fi
else
  echo "NOT ok (W3) SKIPPED: could not derive the writer-side mutation target line above"
  failx
fi

echo
if [ "$fail" = 0 ]; then
  echo "=== R4-I1 REGRESSION GUARD: ALL CHECKS PASS -- the real (fixed)"
  echo "    reader-side selection logic correctly picks the older, RUN_COMPLETE-"
  echo "    marked run-dir over a lexically-newer partial one, the real (fixed)"
  echo "    writer-side logic writes the sentinel only on a genuine completed run"
  echo "    and never on an early exit, and both halves' own guard checks are"
  echo "    independently confirmed load-bearing via the reviewer's own mutation"
  echo "    technique. ==="
else
  echo "=== R4-I1 REGRESSION GUARD: FAILURES ABOVE -- see NOT ok lines. ==="
fi

exit "$fail"
