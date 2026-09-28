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
# Producer≠Verifier: this file is authored at the RED step (T017); the actual
# per-mutant TSV generator is a LATER, SEPARATE implementation task -- this
# file's author never implements it.
#
# Safety: operates ONLY on a `mktemp -d` scratch copy of the small fastcycle
# tree; the live constitution/scripts/fastcycle/ tree is never mutated.
#
# Usage : bash test_metatest_per_mutant_red.sh   Exit 0 = RED baseline holds
#         (absence proven + control needle KILLED) and contract stubs printed.
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
FC="$ROOT/constitution/scripts/fastcycle"
MT="$ROOT/scripts/testing/meta_test_false_positive_proof.sh"

fail=0
failx() { fail=1; }

# --- (1) Absence check: no per-mutant TSV mechanism in the meta-test file ---
[ -f "$MT" ] || { echo "NOT ok meta_test_false_positive_proof.sh missing at $MT"; exit 1; }

if grep -qE '\.tsv' <(sed -n '/^pass()/,/^skip()/p' "$MT"); then
  echo "NOT ok pass()/fail()/skip() now reference a .tsv path -- the per-mutant TSV"
  echo "     mechanism this RED baseline pins as absent may have landed. If the"
  echo "     implementation task has shipped it, DELETE this RED-baseline assertion."
  failx
else
  echo "ok pass()/fail()/skip() (the meta-test's ONLY verdict-recording helpers) write"
  echo "   no .tsv anywhere -- confirmed absent today (2026-09-28)"
fi

if grep -qiE 'per[-_ ]mutant|mutant.*report|report.*mutant' "$MT"; then
  echo "NOT ok meta_test_false_positive_proof.sh now mentions per-mutant reporting --"
  echo "     re-check whether the absence this RED baseline pins still holds"
  failx
else
  echo "ok no per-mutant reporting language anywhere in the 28813-line meta-test file"
fi

# --- (2) §11.4.273 control needle: prove a KILLED verdict is a real, obtainable ---
#         fact today, via M12 end-to-end on a scratch copy (never the live tree).
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

echo
echo "=== future-implementer contract stub (per-mutant TSV format) ==="
echo "NOT YET IMPLEMENTED: a per-mutant TSV with one row per mutation label"
echo "  (name, KILLED|SURVIVED|ERROR, marker-matched y/n, duration) does not exist."
echo "  Future implementer: emit one row per 'mut ...' registration in every"
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
echo "  byte-identical whether timing instrumentation is active or disabled."

exit $fail
