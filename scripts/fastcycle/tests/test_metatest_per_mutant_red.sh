#!/bin/bash
# Purpose : T017 (SpecKit-004 "fast-dev-cycles", User Story 1) RED baseline
#           proving scripts/testing/meta_test_false_positive_proof.sh has NO
#           per-mutant TSV reporting mechanism today -- every mutation's
#           verdict (KILLED / SURVIVED / ERROR-class) exists only as a
#           transient scratch-dir .rc file (or, for the top-level meta-test
#           file itself, only as three aggregate stdout counters
#           PASS_COUNT/FAIL_COUNT/SKIP_COUNT) -- never as a durable,
#           structured, one-row-per-mutation record.
#
# Root cause verified directly (2026-09-28) against the real source:
#   - scripts/testing/meta_test_false_positive_proof.sh: pass()/fail()/skip()
#     (lines 33-35) only printf to stdout + increment a counter; grepping the
#     whole 28813-line file for `.tsv` / "per-mutant" / "mutant.*report" turns
#     up ONLY unrelated references (regression_guard/registry.tsv,
#     .ws_state/streams.tsv) -- zero per-mutant reporting mechanism exists.
#   - constitution/scripts/fastcycle/tests/test_foundational_mutations.sh's own
#     mut_job() (lines 116-129) DOES already classify each mutation into
#     exactly the KILLED / SURVIVED / ERROR-class taxonomy T017 wants durable
#     (.rc file contents: "1"=KILLED, "0"=SURVIVED, "NOCHANGE"|"MARKER_MISS"=
#     ERROR-class) -- but those .rc files live in a `mktemp -d` scratch workdir
#     that is deleted on exit (trap cleanup EXIT, line 100 of that file);
#     nothing persists them anywhere.
#
# §11.4.273 control needle: before trusting "no TSV exists" as a finding, this
# file proves the underlying per-mutation KILLED verdict is a REAL, currently-
# obtainable fact today -- not merely a theoretical future capability -- by
# directly reproducing ONE already-registered, already-proven mutation
# (M12-driver-killtree-root-guard-weakened, T014 round-11/12 IMPORTANT-3
# remediation) end-to-end on a scratch copy of the real fastcycle tree, using
# the EXACT same cp+sed+run+marker-grep steps mut_job() itself uses, and
# asserting it reports KILLED. This is the same mutation independently
# reproduced by hand earlier in this session (T014 remediation); replicated
# here as a standing, scripted, re-runnable proof instead of a one-off manual
# check.
#
# Producer≠Verifier (Constitution §11.4.240): this file is authored at the RED
# step (T017); the actual per-mutant TSV generator is a LATER, SEPARATE
# implementation task (T032/T033) -- this file's author never implements it.
#
# Safety: operates ONLY on a `mktemp -d` scratch copy of the small fastcycle
# tree; the live constitution/scripts/fastcycle/ tree is never mutated. This
# file also never invokes the full scripts/testing/meta_test_false_positive_proof.sh
# sweep (§11.4.89/§12.8 -- that sweep is a long, host-exclusive mutation run;
# invoking it here would violate the very host-safety rule the RECONCILIATION
# below was performed under). Any per-mutant TSV this file reads was produced
# by a REAL, SEPARATE, already-completed run (T033) -- never simulated or
# hand-written here.
#
# ---------------------------------------------------------------------------
# RECONCILIATION (2026-09-28, applied BEFORE T032/T033 land -- Constitution
# §11.4.115 polarity-switch / §11.4.120 gate reconciliation. Unlike
# test_fc_timer_prebuild_red.sh's own post-landing RECONCILIATION, this one
# fixes a defect found in THIS file's ORIGINAL assertions independent of
# whether T032/T033 have shipped -- the defect exists today, before either
# task has landed):
#
#   Investigation (2026-09-28) found NONE of this file's original 3 chk()-
#   equivalent (ok/NOT-ok) assertions are capable of EVER flipping FAIL<->PASS
#   on T032/T033's landing status -- independently corroborated the same day
#   by a separate T032-drafting investigation (see
#   qa-results/fastcycle/us1/green/T032_draft/NOTES.md §6, which reaches the
#   identical conclusion: "Would NOT make T017 fully GREEN on its own ...
#   Whoever applies this patch will still need a follow-up step ... that
#   replaces T017's RED assertions with real GREEN assertions against the new
#   TSV ... before T017 as a whole can be called GREEN" -- this reconciliation
#   IS that follow-up step):
#
#     (a) assertion 1 ("pass()/fail()/skip() write no .tsv anywhere") and
#         assertion 2 ("no per-mutant reporting language anywhere") were
#         PERMANENT absence snapshots with no polarity switch -- the exact
#         §11.4.115 defect class test_fc_timer_prebuild_red.sh's own
#         assertion (a) had before ITS reconciliation. Left as originally
#         written they would each flip PASS->FAIL (never FAIL->PASS) the
#         moment T032 lands (the source WOULD then genuinely mention ".tsv"
#         and "per-mutant"), and this file's own prior comments only
#         instructed a human to manually DELETE them once that happens -- an
#         unenforced, easy-to-miss step that would leave this test FAILING
#         FOREVER after a fully-correct T032/T033 landing (a NEW
#         cannot-ever-pass defect, the mirror image of the cannot-ever-fail
#         one this reconciliation exists to fix).
#     (b) assertion 3 (the M12 control-needle KILLED reproduction) is genuinely
#         real and T032-independent -- it exercises
#         test_foundational_mutations_killtree_root_guard.sh directly, never
#         scripts/testing/meta_test_false_positive_proof.sh -- so it is kept
#         UNCHANGED (same steps, same expected outcome, no RED_MODE branch).
#     (c) THE CORE DEFECT: none of the 3 original assertions ever tested the
#         actual T017/T032/T033 acceptance criterion -- "one row per mutation
#         label with KILLED/SURVIVED/ERROR" archived under
#         qa-results/fastcycle/metatest/<run-id>/ (tasks.md T017 line 99 /
#         T033 line 118; plan.md T-A03 line 345: "231 mutation labels each
#         have a row with a verdict (KILLED/SURVIVED/ERROR)"). So even a
#         fully-correct T032+T033 landing gave this file NO way to observe or
#         report that success -- T032 tasks.md's own line says "until T017 is
#         GREEN", but nothing in the original file could ever turn GREEN.
#
#   Fix, per §11.4.115's polarity-switch pattern (mirroring
#   test_fc_timer_prebuild_red.sh's own RECONCILIATION):
#
#     - A `RED_MODE` env-overridable flag, `FC_METATEST_RED_MODE`, defaulting
#       (as ORIGINALLY written, 2026-09-28) to **1** (RED / pre-landing --
#       T032 and T033 were BOTH still unchecked `[ ]` at that time; this
#       differed from T015's default-0 because T015's own dependency, T028,
#       HAD already landed by the time T015 was reconciled, whereas
#       T032/T033 genuinely had not).
#
#     F7 CORRECTION (T048 round-2 review, 2026-09-30): assertions 1/2's
#     RED_MODE polarity depends on T032 ALONE (whether the per-mutant
#     reporting MECHANISM exists in the SOURCE this file inspects) -- NOT on
#     T033 (a SEPARATE, later milestone: actually EXECUTING one full run and
#     archiving its TSV, which assertion (3) below already checks
#     UNCONDITIONALLY, independent of RED_MODE). T032 landed (tasks.md now
#     marks it `[x]`; verified live, 2026-09-30) while T033 remains
#     HONESTLY BLOCKED on a separate, unrelated operator decision (2 named
#     chronic-debt gates) -- so the ORIGINAL "T032 and T033 both unchecked"
#     precondition this default cited is no longer true, and assertions 1/2
#     genuinely hold under RED_MODE=0 (superseded) today: verified live,
#     the file DOES now mention ".tsv"/"per-mutant" (T032's own added
#     comments and fc_timer wiring), so RED_MODE=1's assertion (2) FAILS
#     (a real regression class this file's own §11.4.115 design exists to
#     catch -- an un-flipped "not yet implemented" assertion left failing
#     forever after its guarded code landed, mirroring the SAME defect
#     class an earlier independent review found in sibling
#     test_dispatch_stamp_red.sh/T036, per that file's own precedent note).
#     Default flipped to **0** below; `FC_METATEST_RED_MODE=1` remains
#     available to manually re-arm the absence check (e.g. investigating a
#     suspected regression of T032's own work), matching this file's
#     already-designed polarity-switch escape hatch.
#     - Assertions 1 and 2 now flip polarity on the flag: RED_MODE=1 (default)
#       asserts absence, matching today's real state; RED_MODE=0 (set the day
#       T032 lands) treats the absence precondition as permanently
#       superseded and reports a "skip" line instead of a spurious FAIL --
#       exactly matching test_fc_timer_prebuild_red.sh's own assertion-6
#       pattern for its now-permanently-false precondition.
#     - Assertion 3 (M12 control needle) is unchanged.
#     - A NEW, UNCONDITIONAL, content-verified assertion pair is added (never
#       RED_MODE-gated -- it tracks the real repo state directly, exactly
#       like test_fc_timer_prebuild_red.sh's own assertion 7): it
#       auto-discovers any `*.tsv` archived under
#       `qa-results/fastcycle/metatest/<run-id>/` (T033's own documented
#       archive path -- tasks.md line 118 / plan.md T-A03; corroborated by
#       the independent T032-draft investigation's proposed
#       `FC_TIMER_TSV="qa-results/fastcycle/metatest/$(date ...)_$$/per_mutant.tsv"`
#       default, see NOTES.md line 202 -- but the exact TSV FILENAME is
#       nowhere COMMITTED in tasks.md, plan.md, or specs/004-fast-dev-cycles/
#       contracts/, so this deliberately does NOT hardcode one -- the same
#       "never hardcode a value the spec does not commit to" discipline
#       test_fc_timer_prebuild_red.sh's own header applies to "94") and
#       asserts (i) such a file exists and (ii) it contains at least one row
#       whose verdict field is exactly KILLED, SURVIVED, or ERROR --
#       T017/T032/T033's own literal acceptance vocabulary (tasks.md T017
#       line 99, T033 line 118; plan.md T-A03 line 345). This assertion
#       deliberately does NOT cross-check against an exact row-COUNT (e.g.
#       "231" or the T032-draft's independently-measured "1,121" -- the two
#       figures disagree with each other, exactly the kind of moving-target,
#       disputed constant test_fc_timer_prebuild_red.sh's own header warns
#       against hardcoding for its "94"); it only asserts the row's presence
#       and its verdict value are real. BOTH currently FAIL (no such
#       directory exists in this checkout today -- verified below) and are
#       designed to flip to PASS the moment T033 archives a real per-mutant
#       run -- this IS T017's real, deterministic, non-hardcoded-path,
#       content-verified done-signal for T032/T033, closing the gap both
#       investigations independently found.
#
# Usage : bash test_metatest_per_mutant_red.sh   Exit 0 (default, RED_MODE=0
#         post-T032-landing) = assertions 1/2 report superseded, the M12
#         control needle reports KILLED, the driver-path assertion (N1, see
#         below) holds, and control needle KILLED + real driver behaviour
#         are verified; the unconditional TSV-existence + verdict-row
#         assertion (T033-gated) reports its OWN real state either way.
#   Env FC_METATEST_RED_MODE=0|1 : polarity switch (§11.4.115). Default 0
#                                   (F7 fix, T048 round-2 review, 2026-09-30
#                                   -- T032 has landed; see the F7
#                                   CORRECTION note above) = GREEN/post-T032-
#                                   landing (assertions 1/2 report
#                                   superseded, not asserted). Set to 1 to
#                                   manually re-arm the pre-T032 absence
#                                   check (e.g. investigating a suspected
#                                   regression of T032's own work). The
#                                   TSV-existence + verdict-row assertion
#                                   pair (T033-gated) is unconditional
#                                   either way and needs no flag change to
#                                   start reporting PASS once T033 archives
#                                   real evidence on disk.
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
MT="$ROOT/scripts/testing/meta_test_false_positive_proof.sh"
METATEST_ARCHIVE_DIR="$ROOT/qa-results/fastcycle/metatest"

fail=0
failx() { fail=1; }

# F7 fix (T048 round-2 review, 2026-09-30): default flipped 1->0 -- T032 has
# landed (tasks.md marks it [x]; verified live, 2026-09-30); assertions 1/2's
# RED_MODE polarity depends on T032 alone, never T033 (a separate, still-
# blocked milestone the unconditional assertion (3) below already gates on
# its own). See the F7 CORRECTION note in this file's header for the full
# diagnosis: RED_MODE=1 (the old default) made assertion (2) FAIL forever
# after T032 genuinely landed, an un-flipped "not yet implemented" assertion
# left asserting a now-permanently-false precondition.
RED_MODE="${FC_METATEST_RED_MODE:-0}"
echo "INFO: RED_MODE=$RED_MODE (1=RED/pre-T032-landing [manual re-arm only], 0=GREEN/post-T032-landing [default since 2026-09-30 -- T032 [x] in tasks.md; T033 remains separately blocked, gated only by the unconditional assertion (3) below])"

# --- (1) Absence check: no per-mutant TSV mechanism in the meta-test file ---
[ -f "$MT" ] || { echo "NOT ok meta_test_false_positive_proof.sh missing at $MT"; exit 1; }

TSV_REF_IN_VERDICT_HELPERS=0
grep -qE '\.tsv' <(sed -n '/^pass()/,/^skip()/p' "$MT") && TSV_REF_IN_VERDICT_HELPERS=1
if [ "$RED_MODE" = "1" ]; then
  if [ "$TSV_REF_IN_VERDICT_HELPERS" = 0 ]; then
    echo "ok pass()/fail()/skip() (the meta-test's ONLY verdict-recording helpers) write"
    echo "   no .tsv anywhere -- confirmed absent today (2026-09-28) [RED_MODE=1]"
  else
    echo "NOT ok pass()/fail()/skip() now reference a .tsv path -- the per-mutant TSV"
    echo "     mechanism this RED baseline pins as absent may have landed. If T032 has"
    echo "     shipped it, set FC_METATEST_RED_MODE=0 (see RECONCILIATION above)."
    failx
  fi
else
  echo "ok pass()/fail()/skip() .tsv-absence precondition superseded (permanently false"
  echo "   once T032 lands; see RECONCILIATION above) -- reporting, not asserting [RED_MODE=0]"
fi

PER_MUTANT_LANG_PRESENT=0
grep -qiE 'per[-_ ]mutant|mutant.*report|report.*mutant' "$MT" && PER_MUTANT_LANG_PRESENT=1
if [ "$RED_MODE" = "1" ]; then
  if [ "$PER_MUTANT_LANG_PRESENT" = 0 ]; then
    echo "ok no per-mutant reporting language anywhere in the 28813-line meta-test file [RED_MODE=1]"
  else
    echo "NOT ok meta_test_false_positive_proof.sh now mentions per-mutant reporting --"
    echo "     re-check whether the absence this RED baseline pins still holds. If T032"
    echo "     has shipped it, set FC_METATEST_RED_MODE=0 (see RECONCILIATION above)."
    failx
  fi
else
  echo "ok per-mutant-reporting-language-absence precondition superseded (permanently"
  echo "   false once T032 lands; see RECONCILIATION above) -- reporting, not asserting [RED_MODE=0]"
fi

# --- (2) §11.4.273 control needle: prove a KILLED verdict is a real, obtainable ---
#         fact today, via M12 end-to-end on a scratch copy (never the live tree).
#         Unchanged by this reconciliation -- T032-independent (see (b) above).
tmp=$(mktemp -d) || { echo "NOT ok mktemp failed"; exit 2; }
trap 'rm -rf "$tmp"' EXIT

cp -R "$FC" "$tmp/fc_scratch"
target="$tmp/fc_scratch/tests/test_foundational_mutations.sh"
guard="$tmp/fc_scratch/tests/test_foundational_mutations_killtree_root_guard.sh"
if [ ! -f "$target" ] || [ ! -f "$guard" ]; then
  echo "NOT ok scratch copy missing test_foundational_mutations.sh or its killtree_root_guard sibling"
  failx
else
  orig_md5=$(md5sum "$target" | awk '{print $1}')
  sed -i 's/\[ "\$r" -gt 1 \] || return 0/[ "$r" -gt 0 ] || return 0/' "$target"
  mut_md5=$(md5sum "$target" | awk '{print $1}')
  if [ "$orig_md5" = "$mut_md5" ]; then
    echo "NOT ok M12 sed expression produced NO CHANGE (NOCHANGE-class, ERROR verdict) --"
    echo "     the control needle itself is broken, so no KILLED/SURVIVED verdict below"
    echo "     can be trusted (§11.4.273)"
    failx
  else
    m12_log="$tmp/m12.log"
    if bash "$guard" >"$m12_log" 2>&1; then
      echo "NOT ok M12 mutation SURVIVED (test still exited 0) -- the control needle did"
      echo "     not reproduce a KILLED verdict; every claim in this file's header about"
      echo "     KILLED verdicts being real today is unproven"
      failx
    elif grep -qF 'NOT ok kill_tree(root=1) signalled something (root guard bypassed)' "$m12_log"; then
      echo "ok M12-driver-killtree-root-guard-weakened reproduces a genuine KILLED"
      echo "   verdict end-to-end (marker matched) -- proving the underlying per-mutation"
      echo "   classification a future TSV would report is REAL and obtainable today,"
      echo "   even though nothing currently persists it (§11.4.273 control needle satisfied)"
    else
      echo "NOT ok M12 mutation FAILED but WITHOUT its expected marker (MARKER_MISS-class,"
      echo "     ERROR verdict) -- the test failed for a DIFFERENT reason than the root"
      echo "     guard bypass this control needle targets"
      sed 's/^/    /' "$m12_log"
      failx
    fi
  fi
fi

# --- (3) CORE FIX (RECONCILIATION above): the actual T017/T032/T033 target ---
#         acceptance criterion -- a per-mutant TSV archived under
#         qa-results/fastcycle/metatest/<run-id>/ (T033's documented archive
#         path) with at least one row carrying a genuine KILLED/SURVIVED/ERROR
#         verdict. Deliberately never hardcodes the TSV's filename (not
#         committed anywhere in tasks.md/plan.md/contracts/ -- see
#         RECONCILIATION above). Unconditional (no RED_MODE branch): tracks
#         the real repo state directly, so it currently FAILS (nothing
#         archived yet, confirmed by direct `find` below) and is designed to
#         flip to PASS the instant T033 archives a real run -- this is T017's
#         real, content-verified done-signal for T032/T033, independent of
#         RED_MODE.
METATEST_TSV=""
if [ -d "$METATEST_ARCHIVE_DIR" ]; then
  METATEST_TSV="$(find "$METATEST_ARCHIVE_DIR" -mindepth 2 -maxdepth 2 -name '*.tsv' -type f 2>/dev/null | sort | tail -n1)"
fi

if [ -n "$METATEST_TSV" ] && [ -f "$METATEST_TSV" ]; then
  echo "ok per-mutant TSV found: $METATEST_TSV (T032/T033 acceptance criterion; plan T-A03)"
  TAB="$(printf '\t')"
  VERDICT_ROWS="$(grep -cE "(^|${TAB})(KILLED|SURVIVED|ERROR)(${TAB}|\$)" "$METATEST_TSV" 2>/dev/null || true)"
  : "${VERDICT_ROWS:=0}"
  if [ "$VERDICT_ROWS" -ge 1 ]; then
    echo "ok per-mutant TSV contains $VERDICT_ROWS row(s) with a genuine KILLED|SURVIVED|ERROR"
    echo "   verdict value (T017/T032/T033's own acceptance vocabulary; tasks.md T017/T033,"
    echo "   plan.md T-A03)"
  else
    echo "NOT ok per-mutant TSV exists at $METATEST_TSV but contains ZERO rows with a"
    echo "     tab-delimited KILLED|SURVIVED|ERROR verdict value -- the file exists but"
    echo "     does not yet satisfy the acceptance criterion"
    failx
  fi
else
  echo "NOT ok no per-mutant TSV found under $METATEST_ARCHIVE_DIR/<run-id>/*.tsv"
  echo "     (T032/T033 acceptance criterion; plan.md T-A03; tasks.md T017 line 99 / T033"
  echo "     line 118) -- this IS the RED baseline for T017's real, content-verified"
  echo "     done-signal, and MUST flip to PASS once T033 archives a real per-mutant"
  echo "     meta-test run"
  failx
fi

echo
echo "=== future-implementer contract stub (per-mutant TSV format) ==="
echo "Assertion (3) above already checks for, and reports on, a real archived TSV under"
echo "  $METATEST_ARCHIVE_DIR/<run-id>/*.tsv -- it does NOT prescribe an exact filename"
echo "  or row count (both are disputed/moving targets today -- plan.md's \"231\" vs the"
echo "  independent T032-draft investigation's measured \"1,121\"; see RECONCILIATION"
echo "  above). Future implementer: emit one row per 'mut ...' registration in every"
echo "  mutation driver this project's meta-test orchestrates (not only"
echo "  test_foundational_mutations.sh), keyed by the mutation's own name -- the"
echo "  scratch-dir .rc file contents (0/1/NOCHANGE/MARKER_MISS) that mut_job()"
echo "  already produces map directly onto SURVIVED/KILLED/ERROR/ERROR."

# --- (4) N1 fix (T048 round-2 review): a real DRIVER-PATH runtime assertion ---
#         -- assertion (2) above only ever exercised the M_* INLINE region
#         (test_foundational_mutations_killtree_root_guard.sh, run DIRECTLY,
#         never through meta_test_false_positive_proof.sh's own mutation
#         drivers), which is exactly how the F3 remediation's regression
#         (round-2 finding N1: F3's `trap` shadow-function wrapper made the 4
#         shared drivers -- mutate_gate_direct/mutate_gate_selftest_or_red/
#         mutate_gate_via_fixture/mutate_anchor_gate -- re-leak the RETURN
#         trap, reproducing the ORIGINAL F1 bug through a different mechanism
#         -- went undetected by this file. This assertion extracts the LIVE,
#         CURRENT content of pass()/fail()/skip(), the fc_timer wiring block
#         (incl. the `trap` shadow function + _fc_mut_start/_fc_mut_end),
#         sed_i_verified(), and mutate_gate_direct() straight out of $MT via
#         content-anchored awk ranges (never hardcoded line numbers -- the
#         same extraction discipline this file's own
#         run_anchor_gate_isolated/run_les_gate_isolated already use), then
#         actually RUNS mutate_gate_direct() twice in a row against a
#         throwaway scratch gate script, followed by the exact inline-frame
#         shape (_fc_mut_start / `.` source / fail() / _fc_mut_end) that
#         exposed the original F1 bug. It sources the REAL
#         constitution/scripts/fastcycle/timing/fc_timer.sh (read-only --
#         nothing in the live tree is ever mutated; FC_TIMER_TSV is pointed
#         at a scratch path so no real archive is touched) so a leaked
#         RETURN trap produces the REAL fc_timer_end "stack is empty"
#         warning the live regression actually emits, not a hand-simulated
#         approximation. Two runtime signatures distinguish
#         golden-bad(pre-fix)/golden-good(post-fix), both independently
#         reproduced by hand before this assertion was authored: (i) zero
#         "stack is empty" warnings anywhere in stderr across the whole
#         sequence, and (ii) `builtin trap -p RETURN` reports EMPTY after
#         both driver calls (a leaked trap prints its still-armed command
#         string instead). A textual companion check further confirms all 4
#         driver call sites use `builtin trap` (not a bare `trap` that would
#         route back through the shadow function) -- cheap regression-
#         proofing against literally reintroducing the bare form, layered on
#         top of (never a substitute for) the dynamic proof above.
DRIVER_EXTRACT_TMP="$(mktemp -d)" || { echo "NOT ok mktemp failed (driver-path assertion)"; failx; DRIVER_EXTRACT_TMP=""; }
if [ -n "$DRIVER_EXTRACT_TMP" ]; then
  d="$DRIVER_EXTRACT_TMP"
  : > "$d/payload.sh"
  awk '$0 ~ "^pass\\(\\) \\{", $0 ~ "^pass\\(\\) \\{"' "$MT" >> "$d/payload.sh"
  awk '$0 ~ "^fail\\(\\) \\{", $0 ~ "^fail\\(\\) \\{"' "$MT" >> "$d/payload.sh"
  awk '$0 ~ "^skip\\(\\) \\{", $0 ~ "^skip\\(\\) \\{"' "$MT" >> "$d/payload.sh"
  awk '$0 ~ "^_FC_TIMER_LIB=", $0 ~ "^# --- end fc_timer\\.sh wiring"' "$MT" >> "$d/payload.sh"
  awk '$0 ~ "^sed_i_verified\\(\\) \\{", $0 ~ "^\\}$"' "$MT" >> "$d/payload.sh"
  awk '$0 ~ "^mutate_gate_direct\\(\\) \\{", $0 ~ "^\\}$"' "$MT" >> "$d/payload.sh"

  MISSING_BLOCK=""
  grep -q '^pass() {' "$d/payload.sh" || MISSING_BLOCK="pass()"
  grep -q '^fail() {' "$d/payload.sh" || MISSING_BLOCK="fail()"
  grep -q '^skip() {' "$d/payload.sh" || MISSING_BLOCK="skip()"
  grep -q '^_FC_TIMER_LIB=' "$d/payload.sh" || MISSING_BLOCK="fc_timer wiring block"
  grep -q '^sed_i_verified() {' "$d/payload.sh" || MISSING_BLOCK="sed_i_verified()"
  grep -q '^mutate_gate_direct() {' "$d/payload.sh" || MISSING_BLOCK="mutate_gate_direct()"

  if [ -n "$MISSING_BLOCK" ]; then
    echo "NOT ok driver-path extraction: could not find $MISSING_BLOCK in $MT -- the file's"
    echo "     structure changed; this assertion's content-anchors need updating"
    failx
  else
    cat > "$d/gate.sh" <<'GATEEOF'
#!/usr/bin/env bash
DETECT_ENABLED=1
if [ "$DETECT_ENABLED" = "1" ]; then exit 1; else exit 0; fi
GATEEOF
    chmod +x "$d/gate.sh"

    {
      echo 'set -uo pipefail'
      echo "REPO_ROOT=\"$ROOT\""
      echo "export FC_TIMER_TSV=\"$d/per_mutant.tsv\""
      echo 'PASS_COUNT=0; FAIL_COUNT=0; SKIP_COUNT=0'
      cat "$d/payload.sh"
      echo "mutate_gate_direct M_T048N1_TEST1 \"$d/gate.sh\" 's/DETECT_ENABLED=1/DETECT_ENABLED=0/' 1"
      echo "mutate_gate_direct M_T048N1_TEST2 \"$d/gate.sh\" 's/DETECT_ENABLED=1/DETECT_ENABLED=0/' 1"
      echo 'echo "__RETURN_TRAP__=[$(builtin trap -p RETURN)]"'
      echo '_fc_mut_start M_T048N1_INLINE'
      echo "echo ':' > \"$d/defs.sh\""
      echo ". \"$d/defs.sh\""
      echo 'fail "M_T048N1_INLINE surviving mutant (driver-path assertion)"'
      echo '_fc_mut_end'
      echo 'echo "__FINAL__ PASS=$PASS_COUNT FAIL=$FAIL_COUNT"'
    } > "$d/driver.sh"

    DRIVER_OUT="$d/driver.out"
    bash "$d/driver.sh" >"$DRIVER_OUT" 2>&1

    STACK_EMPTY_WARN=0
    grep -q 'stack is empty' "$DRIVER_OUT" && STACK_EMPTY_WARN=1
    RETURN_TRAP_LEAKED=0
    grep -qE '^__RETURN_TRAP__=\[.+\]$' "$DRIVER_OUT" && RETURN_TRAP_LEAKED=1

    if [ "$STACK_EMPTY_WARN" = 0 ] && [ "$RETURN_TRAP_LEAKED" = 0 ]; then
      echo "ok driver-path runtime assertion: 2 real mutate_gate_direct() calls + an inline"
      echo "   _fc_mut_start/./fail()/_fc_mut_end frame, run against the LIVE extracted"
      echo "   file content -- zero 'stack is empty' warnings, RETURN trap empty after"
      echo "   both drivers (N1 fixed; T048 round-2)"
    else
      echo "NOT ok driver-path runtime assertion FAILED against the LIVE extracted file"
      echo "     content -- stack_empty_warning=$STACK_EMPTY_WARN return_trap_leaked=$RETURN_TRAP_LEAKED"
      echo "     (N1 regression class: the 4 shared mutation drivers re-leak the RETURN trap)"
      sed 's/^/    /' "$DRIVER_OUT"
      failx
    fi
  fi
  rm -rf "$DRIVER_EXTRACT_TMP"
fi

DRIVER_SITES_NOT_BUILTIN="$(grep -cE "^\s+trap '_fc_mut_end; trap - RETURN' RETURN\s*\$" "$MT" 2>/dev/null || true)"
: "${DRIVER_SITES_NOT_BUILTIN:=0}"
DRIVER_SITES_BUILTIN="$(grep -cE "^\s+builtin trap '_fc_mut_end; builtin trap - RETURN' RETURN\s*\$" "$MT" 2>/dev/null || true)"
: "${DRIVER_SITES_BUILTIN:=0}"
if [ "$DRIVER_SITES_NOT_BUILTIN" = 0 ] && [ "$DRIVER_SITES_BUILTIN" -ge 4 ]; then
  echo "ok all $DRIVER_SITES_BUILTIN driver call sites use \`builtin trap\` (not the shadow"
  echo "   function) for both the arm and the inner self-clear -- zero bare-\`trap\`"
  echo "   driver sites remain (N1 textual companion check)"
else
  echo "NOT ok driver call sites: $DRIVER_SITES_BUILTIN using \`builtin trap\`,"
  echo "     $DRIVER_SITES_NOT_BUILTIN still using the bare, shadow-function-routed"
  echo "     \`trap\` form (expected >=4 builtin, 0 bare) -- N1 may have regressed or a"
  echo "     new driver call site was added without the fix"
  failx
fi

echo
echo "=== golden-output contract stub (verdict set identical with/without timing rows) ==="
echo "NOT YET IMPLEMENTED: T015/T016 (timing instrumentation) have not landed yet, so"
echo "  there is no timing wrapper to compare against. Future implementer: once"
echo "  fc_timer.sh wraps pre_build_verification.sh/commit-stage, assert the"
echo "  meta-test's PASS/FAIL/SKIP verdict SET (not merely the counts) is"
echo "  byte-identical whether timing instrumentation is active or disabled. This stub"
echo "  remains deliberately inert (documentation only) -- assertion (3) above is this"
echo "  file's real, flippable done-signal, so this stub being inert does not leave the"
echo "  file unable to ever flip GREEN."

exit $fail
