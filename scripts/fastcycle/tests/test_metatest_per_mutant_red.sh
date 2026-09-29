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
#       to **1** (RED / pre-landing -- T032 and T033 are BOTH still unchecked
#       `[ ]` in specs/004-fast-dev-cycles/tasks.md as of 2026-09-28; this
#       differs from T015's default-0 because T015's own dependency, T028,
#       HAD already landed by the time T015 was reconciled, whereas
#       T032/T033 genuinely have not).
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
# Usage : bash test_metatest_per_mutant_red.sh   Exit 0 = RED baseline holds
#         (absence proven under RED_MODE=1 + control needle KILLED + no
#         per-mutant TSV evidence found yet) and contract stub printed.
#   Env FC_METATEST_RED_MODE=0|1 : polarity switch (§11.4.115). Default 1 =
#                                   RED/pre-landing (T032+T033 not landed;
#                                   assert absence). Set to 0 the day
#                                   T032/T033 land (assertions 1/2 become
#                                   skip-lines instead of chk()s). The new
#                                   TSV-existence + verdict-row assertion pair
#                                   is unconditional either way and needs no
#                                   flag change to start reporting PASS once
#                                   real evidence exists on disk.
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
MT="$ROOT/scripts/testing/meta_test_false_positive_proof.sh"
METATEST_ARCHIVE_DIR="$ROOT/qa-results/fastcycle/metatest"

fail=0
failx() { fail=1; }

RED_MODE="${FC_METATEST_RED_MODE:-1}"
echo "INFO: RED_MODE=$RED_MODE (1=RED/pre-landing [default; T032+T033 both unchecked in tasks.md], 0=GREEN/post-landing [set the day T032+T033 land])"

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
