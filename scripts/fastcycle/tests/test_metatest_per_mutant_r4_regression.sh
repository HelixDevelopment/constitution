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
# T048 ROUND 5 ADDITION (finding R5-I1, 2026-09-30): "R4-I1 is only partly
# closed. The Round-4 reviewer's second named mutation still survives ...
# Moving _fc_mut_run_complete=1 earlier would also go unnoticed ... The
# cause is that the W1/W2 drivers write their own _fc_mut_run_complete=1,
# so where the real file sets the flag is never tested. Fix: add a
# structural assertion that the file has exactly one
# _fc_mut_run_complete=1, placed after the final summary block and
# directly before the exit decision. Pair it with this mutation." Section
# (D) below closes this exactly: it asserts the REAL, UNMODIFIED source
# file's OWN literal `_fc_mut_run_complete=1` line's POSITION (never a
# driver-simulated flag), then proves that assertion load-bearing via the
# reviewer's OWN exact mutation (move the line to directly after the
# early `builtin trap '_mt_exit_final' EXIT` arm point, matching the
# Round-5 review's own repro verbatim).
#
# Producer≠Verifier (§11.4.240): this file is authored as an independent
# regression guard for an ALREADY-LANDED R3-I5 fix; it does not touch
# either source file's own implementation.
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
RED="$FC/tests/test_metatest_per_mutant_red.sh"
# T048 round 6: METATEST_SRC lets a caller point this WHOLE guard at a
# mutated COPY of the real file (round-6 proof that the reviewer's own R5-I1
# mutation, applied to the real file's own text, makes this file exit != 0).
# Default is the real, unmodified parent-repo file.
MT="${METATEST_SRC:-$ROOT/scripts/testing/meta_test_false_positive_proof.sh}"

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
# (A2)/(B2) T048 ROUND 5 ADDITION (finding m1, 2026-09-30): "A three-dir
# mixed-state archive is uncovered. If the newest dir is RUN_COMPLETE but has
# no TSV, the middle dir is partial, and the oldest is complete, the real
# logic correctly falls through to the oldest. Reviewer mutation M3, which
# makes the loop `break` even without a TSV, selects nothing, yet the R4-I1
# test stays rc=0." The 2-dir (A)/(B) fixture above never puts a
# RUN_COMPLETE-bearing, TSV-less directory FIRST in iteration order, so it
# never exercises the "skip this RUN_COMPLETE dir and keep looking" branch
# at all -- M3's mutation (breaking unconditionally the first time
# RUN_COMPLETE is seen, instead of continuing when that dir has no TSV) is
# therefore invisible to it. This 3-dir fixture puts exactly that shape
# first, proving the real logic correctly falls through TWO dirs (one
# RUN_COMPLETE-but-no-TSV, one genuinely partial/no-RUN_COMPLETE) to land on
# the oldest genuinely complete one, and proving the reviewer's M3 mutation
# is caught.
# =============================================================================
ARCHIVE3="$TMP/archive3"
NEWEST_ID="20260103T000000Z_newest_no_tsv"
MIDDLE_ID="20260102T000000Z_middle_partial"
OLDEST_ID="20260101T000000Z_oldest_complete"
NEWEST_DIR="$ARCHIVE3/$NEWEST_ID"
MIDDLE_DIR="$ARCHIVE3/$MIDDLE_ID"
OLDEST_DIR="$ARCHIVE3/$OLDEST_ID"
mkdir -p "$NEWEST_DIR" "$MIDDLE_DIR" "$OLDEST_DIR"
# newest: genuinely RUN_COMPLETE but carries NO *.tsv at all -- the real
# loop must skip it (via the inner `if [ -n "$_mt_cand_tsv" ]` falling
# through) WITHOUT selecting anything and WITHOUT stopping.
printf 'pass=1\nfail=0\nskip=0\nts=2026-01-03T00:00:00Z\n' > "$NEWEST_DIR/RUN_COMPLETE"
# middle: genuinely partial/interrupted -- NO RUN_COMPLETE sentinel at all
# (carries a TSV anyway, shaped like a never-finalized fragment, so the
# fixture is realistic -- but the reader loop's own selection logic must
# reject it on the RUN_COMPLETE check alone, before ever looking at the TSV).
MIDDLE_TSV="$MIDDLE_DIR/per_mutant.tsv"
printf 'label\tstart_ns\tend_ns\tduration_ms\tgate\tcmd\tverdict\tchecks\tpass\tfail\tmutation_verdict\n' > "$MIDDLE_TSV"
printf 'M_R5M1_MIDDLE\t1\t2\t1\tgate.sh\tgate.sh\tPASS\t0\t0\t0\t\n' >> "$MIDDLE_TSV"
# oldest: genuinely complete -- RUN_COMPLETE + a real finalized TSV.
OLDEST_TSV="$OLDEST_DIR/per_mutant.tsv"
printf 'label\tstart_ns\tend_ns\tduration_ms\tgate\tcmd\tverdict\tchecks\tpass\tfail\tmutation_verdict\n' > "$OLDEST_TSV"
printf 'M_R5M1_OLDEST\t1\t2\t1\tgate.sh\tgate.sh\tPASS\t1\t1\t0\tKILLED\n' >> "$OLDEST_TSV"
printf 'pass=1\nfail=0\nskip=0\nts=2026-01-01T00:00:00Z\n' > "$OLDEST_DIR/RUN_COMPLETE"

echo
echo "=== (A2) m1: real (fixed) selection logic falls through a RUN_COMPLETE-but-no-TSV newest dir AND a no-RUN_COMPLETE middle dir, landing on the oldest genuinely complete one ==="
if [ -n "$SEL_PAYLOAD" ]; then
  DRIVER_A2="$TMP/driver_a2.sh"
  {
    echo 'set -u'
    printf 'METATEST_ARCHIVE_DIR=%q\n' "$ARCHIVE3"
    cat "$SEL_PAYLOAD"
    echo 'printf "SELECTED=%s\n" "$METATEST_TSV"'
  } > "$DRIVER_A2"
  SELECTED_A2="$(bash "$DRIVER_A2" 2>"$TMP/driver_a2.err" | sed -n 's/^SELECTED=//p')"
  if [ "$SELECTED_A2" = "$OLDEST_TSV" ]; then
    echo "ok (A2) real selection logic correctly skipped the newest (RUN_COMPLETE, no"
    echo "   TSV) and middle (no RUN_COMPLETE) run-dirs and selected the oldest"
    echo "   genuinely complete one's TSV ($SELECTED_A2)"
  else
    echo "NOT ok (A2) real selection logic picked '$SELECTED_A2' (wanted the oldest"
    echo "     complete run's TSV '$OLDEST_TSV') -- $(cat "$TMP/driver_a2.err" 2>/dev/null)"
    failx
  fi
else
  echo "NOT ok (A2) SKIPPED: extraction control needle above already failed"
  failx
fi

echo
echo "=== (B2) guard-viability: the reviewer's OWN M3 mutation (the loop breaks on the FIRST RUN_COMPLETE dir even with no TSV) selects NOTHING on this exact fixture ==="
SEL_PAYLOAD_M3=""
if [ -n "$SEL_PAYLOAD" ]; then
  IF_LINE='    if [ -n "$_mt_cand_tsv" ]; then'
  FI_LINE='    fi'
  IF_HITS="$(grep -cxF "$IF_LINE" "$SEL_PAYLOAD" 2>/dev/null || true)"; : "${IF_HITS:=0}"
  if [ "$IF_HITS" != 1 ]; then
    echo "NOT ok (B2) control needle FAILED: anchor '$IF_LINE' appears $IF_HITS"
    echo "     time(s) in the extracted payload (expected exactly 1) -- M3's"
    echo "     mutation target no longer exists in this exact form"
    failx
  else
    # Drop the `if`/`fi` wrapper around the "only select+break when a TSV
    # was found" guard, leaving the body (unconditional select+break)
    # always executing -- the reviewer's M3 mutation reproduced exactly:
    # the loop now breaks the FIRST time it sees a RUN_COMPLETE dir,
    # whether or not that dir has a TSV.
    SEL_PAYLOAD_M3="$TMP/selection_payload_m3_mutated.sh"
    awk -v ifline="$IF_LINE" -v filine="$FI_LINE" '
      $0==ifline { skipping=1; next }
      skipping && $0==filine { skipping=0; next }
      { print }
    ' "$SEL_PAYLOAD" > "$SEL_PAYLOAD_M3"
    echo "ok (B2) control needle: located + will mutate the TSV-found guard into an"
    echo "   unconditional break -- the reviewer's own M3 mutation, reproduced"
  fi
fi
if [ -n "$SEL_PAYLOAD_M3" ]; then
  DRIVER_B2="$TMP/driver_b2.sh"
  {
    echo 'set -u'
    printf 'METATEST_ARCHIVE_DIR=%q\n' "$ARCHIVE3"
    cat "$SEL_PAYLOAD_M3"
    echo 'printf "SELECTED=%s\n" "$METATEST_TSV"'
  } > "$DRIVER_B2"
  SELECTED_B2="$(bash "$DRIVER_B2" 2>"$TMP/driver_b2.err" | sed -n 's/^SELECTED=//p')"
  if [ -z "$SELECTED_B2" ]; then
    echo "ok (B2) mutated (unconditional-break) selection logic selected NOTHING"
    echo "   ('$SELECTED_B2', empty) on the SAME 3-dir fixture (A2) correctly picked"
    echo "   the oldest complete run from -- reproducing M3's exact reported effect"
    echo "   ('selects nothing') end-to-end, proving the TSV-found guard this"
    echo "   fixture exercises is genuinely load-bearing"
  else
    echo "NOT ok (B2) BLIND: mutated selection logic picked '$SELECTED_B2' (wanted"
    echo "     empty/nothing, per M3's own reported effect) --"
    echo "     $(cat "$TMP/driver_b2.err" 2>/dev/null); either the mutation"
    echo "     extraction is malformed or this fixture does not genuinely exercise"
    echo "     the TSV-found guard the way M3 describes"
    failx
  fi
else
  echo "NOT ok (B2) SKIPPED: could not construct the M3 mutation above"
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
    # T048 round-5 minor m7: the earlier wording here claimed the absent
    # sentinel was "confirmed by $FC_TIMER_TSV's directory existing" as
    # proof the EXIT trap fired -- but run_writer_scenario's OWN driver
    # unconditionally `mkdir -p`s that directory before the payload even
    # runs, so its existence is circular, not evidence of anything the
    # trap did. Corrected: state plainly what THIS scenario alone proves
    # (the guard correctly refused to write on an early exit), and point
    # at (W1) -- which DOES independently prove the same unconditional
    # top-level trap arm fires, by writing a real sentinel when the
    # completion flag is set -- for the trap-firing claim itself.
    echo "ok (W2) real writer logic wrote NO RUN_COMPLETE sentinel on an early exit --"
    echo "   the completion guard correctly refused to write the marker. (This"
    echo "   scenario's own absent-sentinel result does not by itself prove the"
    echo "   EXIT trap fired -- (W1) above already proves that, via the SAME"
    echo "   unconditional top-level trap arm writing a real sentinel when the"
    echo "   completion flag IS set; (W3) below independently proves this guard"
    echo "   clause, not trap non-firing, is what prevents a sentinel here.)"
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

# =============================================================================
# (D) T048 ROUND 5 finding R5-I1: structural assertion -- the REAL source
# file's OWN `_fc_mut_run_complete=1` line is positioned AFTER genuine
# completion work (the top-level `_fc_mut_finalize_verdicts || true` call)
# and directly before the exit decision -- never merely a driver-controlled
# flag the W1/W2/W3 scenarios above set themselves (which is exactly why
# the reviewer's "move the flag earlier" mutation survived those checks:
# they never exercise the REAL file's own placement of the line at all).
# =============================================================================
D_FLAG_LINE='_fc_mut_run_complete=1'
D_FINALIZE_LINE='_fc_mut_finalize_verdicts || true'
D_ARM_LINE="builtin trap '_mt_exit_final' EXIT"

check_run_complete_placement() {
  # $1 = file to check; prints "OK" or "BAD:<reason>" on stdout.
  local f="$1"
  local flag_count flag_line finalize_last summary_last next_code_line
  flag_count="$(grep -cxF "$D_FLAG_LINE" "$f" 2>/dev/null || true)"; : "${flag_count:=0}"
  if [ "$flag_count" != 1 ]; then
    printf 'BAD:flag-count=%s (want exactly 1)\n' "$flag_count"
    return
  fi
  flag_line="$(grep -nxF "$D_FLAG_LINE" "$f" | head -n1 | cut -d: -f1)"
  finalize_last="$(grep -nxF "$D_FINALIZE_LINE" "$f" | tail -n1 | cut -d: -f1)"
  if [ -z "$finalize_last" ] || [ "$flag_line" -le "$finalize_last" ]; then
    printf 'BAD:flag-line=%s not-after-finalize-line=%s\n' "$flag_line" "${finalize_last:-MISSING}"
    return
  fi
  # T048 round 6 tightening: the flag must also sit AFTER the LAST
  # "Meta-test summary" banner (the reviewer's own wording: "after the final
  # summary block"), not merely after the finalize call.
  summary_last="$(grep -n 'echo "Meta-test summary"' "$f" | tail -n1 | cut -d: -f1)"
  if [ -z "$summary_last" ] || [ "$flag_line" -le "$summary_last" ]; then
    printf 'BAD:flag-line=%s not-after-final-summary-banner=%s\n' "$flag_line" "${summary_last:-MISSING}"
    return
  fi
  # The next non-blank, non-comment line after the flag assignment MUST be
  # the exit decision itself -- proving the flag is set DIRECTLY before it.
  # Round 6: an exact shape match, never the old "*exit*" substring test
  # (which "_mt_exit_final" or any "...exit..." word would also satisfy).
  next_code_line="$(awk -v n="$flag_line" 'NR>n{ line=$0; gsub(/^[ \t]+/,"",line); if (line=="" || substr(line,1,1)=="#") next; print line; exit }' "$f")"
  if printf '%s\n' "$next_code_line" | grep -qE '^if \[ "\$FAIL_COUNT" -gt 0 \]; then exit 1; fi$'; then
    printf 'OK\n'
  else
    printf 'BAD:next-code-line=%s (is not the exit decision)\n' "$next_code_line"
  fi
}

echo
echo "=== (D-real) R5-I1: the REAL, unmutated source file's own completion-flag placement ==="
D_REAL_RESULT="$(check_run_complete_placement "$MT")"
if [ "$D_REAL_RESULT" = "OK" ]; then
  echo "ok (D-real) the real source file's _fc_mut_run_complete=1 line is genuinely"
  echo "   positioned after the top-level completion work"
  echo "   (_fc_mut_finalize_verdicts || true) and directly before the exit decision"
else
  echo "NOT ok (D-real) real source file structural check FAILED: $D_REAL_RESULT"
  failx
fi

echo
echo "=== (D-mut) guard-viability: the reviewer's OWN R5-I1 mutation -- move the flag"
echo "    assignment to directly after the early EXIT-trap arm point ==="
D_MUT_FILE="$TMP/mt_r5i1_mutated.sh"
awk -v flag="$D_FLAG_LINE" -v arm="$D_ARM_LINE" '
  $0==flag { next }
  { print }
  $0==arm { print flag }
' "$MT" > "$D_MUT_FILE"
D_MUT_FLAG_COUNT="$(grep -cxF "$D_FLAG_LINE" "$D_MUT_FILE" 2>/dev/null || true)"; : "${D_MUT_FLAG_COUNT:=0}"
D_ARM_COUNT="$(grep -cxF "$D_ARM_LINE" "$D_MUT_FILE" 2>/dev/null || true)"; : "${D_ARM_COUNT:=0}"
if [ "$D_MUT_FLAG_COUNT" != 1 ] || [ "$D_ARM_COUNT" != 1 ]; then
  echo "NOT ok (D-mut) SKIPPED: could not construct the mutation (flag-count=$D_MUT_FLAG_COUNT,"
  echo "     arm-count=$D_ARM_COUNT) -- the file's structure changed; this assertion's"
  echo "     anchors need updating"
  failx
else
  D_MUT_RESULT="$(check_run_complete_placement "$D_MUT_FILE")"
  if [ "$D_MUT_RESULT" != "OK" ]; then
    echo "ok (D-mut) guard-viability: the reviewer's OWN mutation (flag moved to fire"
    echo "   from the start of the run, immediately after the early EXIT-trap arm) is"
    echo "   correctly REJECTED by the structural check: $D_MUT_RESULT"
  else
    echo "NOT ok (D-mut) BLIND: the structural check did not catch the reviewer's own"
    echo "     R5-I1 mutation -- moving the flag earlier still reports OK"
    failx
  fi
fi

# =============================================================================
# (E) T048 ROUND 5 ADDITION (finding m9, 2026-09-30): "The NUL-safe loop has
# no committed space-bearing-dir fixture, so reverting it to
# `for ... $(find)` would go unnoticed." The R4 minor fix converted this
# loop from a word-splitting `for _mt_cand_dir in $(find ... | sort -r)` to
# a NUL-delimited `find -print0 | sort -z` piped through
# `while IFS= read -r -d ''` specifically to handle a space (or embedded
# newline) in a run-dir's own name -- but nothing committed here actually
# EXERCISES a space-bearing directory name, so the fix's own regression
# protection was itself unguarded. This proves the REAL (fixed) selection
# logic genuinely selects a space-bearing complete run-dir, and that
# reverting to the OLD word-splitting form (reproduced verbatim from this
# fix's own header comment) WRONGLY fails to select it.
# =============================================================================
echo
echo "=== (E) m9: real (fixed) NUL-safe selection logic correctly selects a run-dir whose own name contains a SPACE ==="
ARCHIVE_SPACE="$TMP/archive_space"
SPACE_ID="20260102 run with space"
SPACE_DIR="$ARCHIVE_SPACE/$SPACE_ID"
mkdir -p "$SPACE_DIR"
SPACE_TSV="$SPACE_DIR/per_mutant.tsv"
printf 'label\tstart_ns\tend_ns\tduration_ms\tgate\tcmd\tverdict\tchecks\tpass\tfail\tmutation_verdict\n' > "$SPACE_TSV"
printf 'M_R5M9_SPACE\t1\t2\t1\tgate.sh\tgate.sh\tPASS\t1\t1\t0\tKILLED\n' >> "$SPACE_TSV"
printf 'pass=1\nfail=0\nskip=0\nts=2026-01-02T00:00:00Z\n' > "$SPACE_DIR/RUN_COMPLETE"

if [ -n "$SEL_PAYLOAD" ]; then
  DRIVER_E="$TMP/driver_e.sh"
  {
    echo 'set -u'
    printf 'METATEST_ARCHIVE_DIR=%q\n' "$ARCHIVE_SPACE"
    cat "$SEL_PAYLOAD"
    echo 'printf "SELECTED=%s\n" "$METATEST_TSV"'
  } > "$DRIVER_E"
  SELECTED_E="$(bash "$DRIVER_E" 2>"$TMP/driver_e.err" | sed -n 's/^SELECTED=//p')"
  if [ "$SELECTED_E" = "$SPACE_TSV" ]; then
    echo "ok (E-real) real selection logic correctly selected the space-bearing"
    echo "   run-dir's TSV ($SELECTED_E)"
  else
    echo "NOT ok (E-real) real selection logic picked '$SELECTED_E' (wanted the"
    echo "     space-bearing run's TSV '$SPACE_TSV') -- $(cat "$TMP/driver_e.err" 2>/dev/null)"
    failx
  fi
else
  echo "NOT ok (E-real) SKIPPED: extraction control needle above already failed"
  failx
fi

echo
echo "=== (E-mut) guard-viability: reverting to the OLD word-splitting 'for \$(find)' form WRONGLY fails to select the space-bearing run-dir ==="
WHILE_OPEN='  while IFS= read -r -d '"'"''"'"' _mt_cand_dir; do'
WHILE_CLOSE='  done < <(find "$METATEST_ARCHIVE_DIR" -mindepth 1 -maxdepth 1 -type d -print0 2>/dev/null | sort -rz)'
OPEN_HITS="$(grep -cxF "$WHILE_OPEN" "$SEL_PAYLOAD" 2>/dev/null || true)"; : "${OPEN_HITS:=0}"
CLOSE_HITS="$(grep -cxF "$WHILE_CLOSE" "$SEL_PAYLOAD" 2>/dev/null || true)"; : "${CLOSE_HITS:=0}"
SEL_PAYLOAD_E_MUT=""
if [ "$OPEN_HITS" != 1 ] || [ "$CLOSE_HITS" != 1 ]; then
  echo "NOT ok (E-mut) control needle FAILED: anchors not exactly-once (open=$OPEN_HITS,"
  echo "     close=$CLOSE_HITS) -- the NUL-safe loop's own shape changed; this"
  echo "     assertion's anchors need updating"
  failx
else
  FOR_OPEN='  for _mt_cand_dir in $(find "$METATEST_ARCHIVE_DIR" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -r); do'
  SEL_PAYLOAD_E_MUT="$TMP/selection_payload_m9_mutated.sh"
  awk -v wopen="$WHILE_OPEN" -v wclose="$WHILE_CLOSE" -v fopen="$FOR_OPEN" '
    $0==wopen { print fopen; next }
    $0==wclose { print "  done"; next }
    { print }
  ' "$SEL_PAYLOAD" > "$SEL_PAYLOAD_E_MUT"
  echo "ok (E-mut) control needle: located + reverted the NUL-safe loop to the OLD"
  echo "   word-splitting 'for \$(find ... | sort -r)' form -- this fix's own"
  echo "   documented pre-fix shape, reproduced verbatim"
fi
if [ -n "$SEL_PAYLOAD_E_MUT" ]; then
  DRIVER_E_MUT="$TMP/driver_e_mut.sh"
  {
    echo 'set -u'
    printf 'METATEST_ARCHIVE_DIR=%q\n' "$ARCHIVE_SPACE"
    cat "$SEL_PAYLOAD_E_MUT"
    echo 'printf "SELECTED=%s\n" "$METATEST_TSV"'
  } > "$DRIVER_E_MUT"
  SELECTED_E_MUT="$(bash "$DRIVER_E_MUT" 2>"$TMP/driver_e_mut.err" | sed -n 's/^SELECTED=//p')"
  if [ "$SELECTED_E_MUT" != "$SPACE_TSV" ]; then
    echo "ok (E-mut) the reverted (word-splitting) selection logic WRONGLY failed to"
    echo "   select the space-bearing run's TSV on the SAME fixture (got"
    echo "   '$SELECTED_E_MUT', wanted '$SPACE_TSV') -- proving the NUL-safe loop"
    echo "   this fixture exercises is genuinely load-bearing, and that reverting it"
    echo "   would now be caught"
  else
    echo "NOT ok (E-mut) BLIND: the reverted word-splitting logic still correctly"
    echo "     selected the space-bearing run's TSV -- either this host's find/sort"
    echo "     genuinely tolerates the embedded space in this configuration, or the"
    echo "     mutation extraction is malformed; either way this fixture does not"
    echo "     currently distinguish the two loop forms"
    failx
  fi
else
  echo "NOT ok (E-mut) SKIPPED: could not construct the mutation above"
  failx
fi

echo
if [ "$fail" = 0 ]; then
  echo "=== R4-I1/R5-I1 REGRESSION GUARD: ALL CHECKS PASS -- the real (fixed)"
  echo "    reader-side selection logic correctly picks the older, RUN_COMPLETE-"
  echo "    marked run-dir over a lexically-newer partial one, the real (fixed)"
  echo "    writer-side logic writes the sentinel only on a genuine completed run"
  echo "    and never on an early exit, both halves' own guard checks are"
  echo "    independently confirmed load-bearing via the reviewer's own mutation"
  echo "    technique, and the REAL source file's own _fc_mut_run_complete=1"
  echo "    placement is structurally verified (never merely a driver-simulated"
  echo "    flag) and proven load-bearing via the reviewer's own R5-I1 mutation. ==="
else
  echo "=== R4-I1/R5-I1 REGRESSION GUARD: FAILURES ABOVE -- see NOT ok lines. ==="
fi

exit "$fail"
