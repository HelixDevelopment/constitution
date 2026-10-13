#!/bin/bash
# Purpose : T110 (SpecKit-004 "fast-dev-cycles", User Story 4 / Phase E) RED
#           test for T119's own, separate, later measurement task ("Token
#           stability double-run: each frozen sample item twice on the same
#           inputs after T112..T118; compare recorded tokens per item
#           against the pre-written tolerance; results under
#           qa-results/fastcycle/tokens/stability/", tasks.md T119; plan.md
#           T-E07; SC-005, FR-021). tasks.md T110's own task line (this
#           file): "RED test ... (reads the +/-10% tolerance from
#           config/fastcycle/thresholds.yaml written in T003 before any
#           run; a run outside it FAILs the item)".
#
# spec.md US4 AS3 (the acceptance scenario T-E07 exists to verify, quoted
# verbatim): "Given the same item run on the same inputs twice, When token
# usage is compared, Then both runs are within a stated tolerance (the
# reduction is stable, not a lucky run)."
#
# ============================================================================
# THE GAP (verified directly against the current working tree, 2026-09-29).
# ============================================================================
# `qa-results/fastcycle/tokens/` does not exist at all today (confirmed
# live in Section 1 below, never assumed) -- T119 has not run, so no
# "results under qa-results/fastcycle/tokens/stability/" of any kind exist
# yet. plan.md's own "Tool map" / "Plan tools that no contract covers"
# tables (contracts/common-conventions.md) list NEITHER a dedicated T-E07
# tool file NOR T-E07 among the uncontracted-but-named tools -- T119 is a
# pure MEASUREMENT task ("Runtime proof" / "Token stability double-run"),
# reusing the already-landed `tokens/transcript_ingest.py` (T038, per-item
# recorded token sums) and `config/fastcycle/thresholds.yaml` (T003, this
# file's own tolerance source), never introducing a new tool file of its
# own. This test therefore does NOT wait on a specific T119 binary to
# exist before it can protect anything -- the load-bearing, protectable
# CONTRACT is the comparison logic itself (delta% vs. the configured
# tolerance), which this file fixes NOW, independently, exactly as
# test_governance_subset_red.sh's derive_selection function fixed T112's
# selection contract before T112 existed.
#
# Producer != Verifier (constitution 11.4.240): this file is authored at
# the RED step (T110); T119's eventual measurement run (writing real
# recorded run1/run2 token pairs and evidence under
# qa-results/fastcycle/tokens/stability/) is a separate, later task -- this
# file's author never performs that measurement. The `stability_verdict`
# function embedded below is a DERIVED oracle per constitution 11.4.245,
# computed independently from spec.md AS3's own wording and this file's
# own fixture data -- never from a not-yet-existing T119 evidence file's
# self-report, never imported by or coupled to any T119 output.
#
# ============================================================================
# THE TOLERANCE-READ INVARIANT (task text: "reads the +/-10% tolerance from
# config/fastcycle/thresholds.yaml ... before any run") -- constitution
# 11.4.6, never hardcode a copy of the number.
# ============================================================================
# The tolerance value MUST be read fresh from config/fastcycle/thresholds.yaml
# at call time, never embedded as a literal inside this test (a
# recalibration of DEC-36's +/-10% figure -- config/fastcycle/thresholds.yaml
# is the single source of truth per plan.md -- must never require editing
# this test file). Section 2 below proves this genuinely holds, not merely
# assumes it: it invokes THIS SAME SCRIPT FILE as a real child process (via
# a hidden `--single-verdict` subprocess mode, so the proof exercises the
# actual executable path, not an internal function call that could
# trivially be parameterised without proving anything) against two
# different fixture thresholds files carrying two different tolerance
# values, for the IDENTICAL borderline token-delta fixture, and confirms
# the two invocations produce two DIFFERENT pass/fail verdicts. If the
# tolerance were hardcoded anywhere in this file, both invocations would
# produce the SAME verdict regardless of which fixture config file was
# passed -- the two-verdict divergence is therefore direct, mechanical
# proof of genuine per-call config reads, not an assertion accepted on
# faith.
#
# ============================================================================
# Oracle independence (constitution 11.4.245) and exit-code convention
# (contracts/common-conventions.md C-001, reused here even though T110/T119
# have no dedicated contract file of their own -- the fleet-wide convention
# still applies).
# ============================================================================
# `stability_verdict` computes delta_pct = 100 * |run2 - run1| / run1
# independently of any tool's self-report (there is no T119 tool to trust
# or distrust yet -- this IS the independent computation) and compares it
# against the tolerance read fresh from the given thresholds file. Exit 0
# = PASS (stable, within tolerance); exit 1 = FAIL (a finding -- unstable,
# outside tolerance, matching C-001's "a run outside it FAILs the item");
# exit 2 = usage/configuration error (the thresholds file is unreadable or
# its tolerance key is unparseable) -- a fail-CLOSED default per
# constitution 11.4.201(4): an unreadable tolerance is NEVER silently
# treated as "anything goes" (which would be exit 0).
#
# ============================================================================
# constitution 11.4.273 control needles (this file's own absence/presence
# detection mechanisms, checked before they are trusted against real data).
# ============================================================================
#   #1 -- a known-present, non-empty scratch file IS found by this file's
#         plain `[ -e ... ]`/`[ -s ... ]` existence checks, and a
#         fabricated, never-created path IS reported absent, before either
#         check is trusted against config/fastcycle/thresholds.yaml or
#         qa-results/fastcycle/tokens/stability/ below.
#   #2 -- `read_tolerance_pct` genuinely reads a DIFFERENT numeric value
#         out of two syntactically-distinct fixture files (Section 2),
#         proving the extraction itself (not merely the downstream
#         verdict) tracks the file content, not a cached/hardcoded copy.
#
# ============================================================================
# Usage: bash test_token_stability_red.sh   Exit 0 = every check below held
#        (today: RED by design -- T119 has not run, Section 1 documents
#        this honestly); nonzero = FAIL count > 0.
#        bash test_token_stability_red.sh --single-verdict RUN1 RUN2 CFG
#        (hidden subprocess-mode entry point; see Section 2). Exit 0=PASS,
#        1=FAIL, 2=config error. Not part of the normal test invocation.
set -u

HERE="$(cd "$(dirname "$0")" && pwd)"
FC="$(cd "$HERE/.." && pwd)"
ROOT="$(cd "$FC/../../.." && pwd)"
SELF="$HERE/$(basename "$0")"

REAL_THRESHOLDS="$ROOT/config/fastcycle/thresholds.yaml"
STABILITY_DIR="$ROOT/qa-results/fastcycle/tokens/stability"

# ---------------------------------------------------------------------------
# Shared primitives (used both by --single-verdict subprocess mode and by
# this script's own in-process golden/golden-bad/negative-control checks
# below) -- ONE implementation, never two divergent copies of the same
# comparison logic.
# ---------------------------------------------------------------------------

read_tolerance_pct() {
  # $1 = a thresholds.yaml-shaped file. Prints the scalar
  # token_stability_tolerance_pct value on stdout; empty output + nonzero
  # rc if the file is unreadable or the key is absent/unparseable.
  local f="$1" v
  [ -r "$f" ] || return 2
  v="$(grep -E '^[[:space:]]*token_stability_tolerance_pct:[[:space:]]*[0-9]' "$f" 2>/dev/null | head -1 \
       | sed -E 's/^[[:space:]]*token_stability_tolerance_pct:[[:space:]]*([0-9]+(\.[0-9]+)?).*$/\1/')"
  [ -n "$v" ] || return 1
  printf '%s\n' "$v"
}

stability_verdict() {
  # $1=run1_tokens $2=run2_tokens $3=thresholds_file
  # Prints "delta_pct=<v> tolerance_pct=<v> verdict=PASS|FAIL" (or a
  # verdict=FAIL reason=... line on a config error) on stdout.
  # Returns 0 for PASS, 1 for FAIL (a finding), 2 for a config/read error
  # (fail-closed -- an unreadable/unparseable tolerance never PASSes).
  local run1="$1" run2="$2" cfg="$3" tol
  tol="$(read_tolerance_pct "$cfg")" || {
    echo "verdict=FAIL reason=tolerance_unreadable_or_unparseable cfg=$cfg"
    return 2
  }
  python3 - "$run1" "$run2" "$tol" <<'PY'
import sys
run1 = float(sys.argv[1])
run2 = float(sys.argv[2])
tol = float(sys.argv[3])
if run1 == 0:
    delta_pct = 0.0 if run2 == 0 else float("inf")
else:
    delta_pct = 100.0 * abs(run2 - run1) / run1
verdict = "PASS" if delta_pct <= tol else "FAIL"
print("delta_pct=%.6f tolerance_pct=%.6f verdict=%s" % (delta_pct, tol, verdict))
sys.exit(0 if verdict == "PASS" else 1)
PY
}

# Hidden subprocess-mode entry point -- exists ONLY so Section 2 below can
# invoke THIS SAME SCRIPT FILE as a genuine child process (never an
# in-process function call, which would prove nothing about the actual
# executable's behaviour) against two different fixture thresholds files
# and observe two different real exit codes.
if [ "${1:-}" = "--single-verdict" ]; then
  stability_verdict "${2:-}" "${3:-}" "${4:-}"
  exit $?
fi

# ---------------------------------------------------------------------------
# Normal RED-test entry point below.
# ---------------------------------------------------------------------------

TMP="$(mktemp -d)" || { echo "cannot create temp dir (TMPDIR unusable)" >&2; exit 2; }
reap_children() { pkill -KILL -f "$TMP" 2>/dev/null; return 0; }
trap 'reap_children; rm -rf "$TMP"' EXIT
trap 'reap_children; rm -rf "$TMP"; exit 130' INT
trap 'reap_children; rm -rf "$TMP"; exit 143' TERM

FAIL=0; N=0
chk() { N=$((N+1)); if [ "$2" = "1" ]; then echo "PASS[$N]: $1"; else echo "FAIL[$N]: $1"; FAIL=$((FAIL+1)); fi; }
info() { echo "INFO: $1"; }

if ! command -v python3 >/dev/null 2>&1; then
  echo "FAIL: python3 not on PATH -- cannot run any of the checks below"
  echo "SUMMARY pass=0 fail=1 total=1"
  exit 1
fi

# -----------------------------------------------------------------------
# constitution 11.4.273 control needles (needle set #1: this test's own
# generic file-existence/absence-detection mechanism, self-checked before
# it is trusted against config/fastcycle/thresholds.yaml or
# qa-results/fastcycle/tokens/stability/ below).
# -----------------------------------------------------------------------
NEEDLE_PRESENT="$TMP/.needle_present_marker"
printf 'x\n' > "$NEEDLE_PRESENT"
chk "control needle #1a: a known-present, non-empty file IS found by the existence+non-empty check" \
  "$([ -s "$NEEDLE_PRESENT" ] && echo 1 || echo 0)"
NEEDLE_FABRICATED="$TMP/.needle_fabricated_never_created_$$_$(date +%s 2>/dev/null || echo x)"
chk "control needle #1b: a fabricated (never-created) path IS reported absent" \
  "$([ ! -e "$NEEDLE_FABRICATED" ] && echo 1 || echo 0)"
rm -f "$NEEDLE_PRESENT"

# =========================================================================
# Section 1: TODAY's real-file RED baseline -- no frozen sample-item
# double-run data exists yet under qa-results/fastcycle/tokens/stability/
# (T119 has not run). tasks.md T119's own text: "results under
# qa-results/fastcycle/tokens/stability/".
# =========================================================================
echo
echo "=== Section 1: qa-results/fastcycle/tokens/stability/ RED baseline (live) ==="
if [ -d "$STABILITY_DIR" ] && [ -n "$(ls -A "$STABILITY_DIR" 2>/dev/null)" ]; then
  info "$STABILITY_DIR FOUND and non-empty -- T119 appears to have landed; Section 6 attempts an honest real-after note"
else
  info "$STABILITY_DIR NOT FOUND (or empty) -- T119 has not run yet; this is the EXPECTED RED-today outcome"
fi
chk "T119 has recorded a frozen sample item's double-run token comparison under qa-results/fastcycle/tokens/stability/ -- expected to FAIL today (RED)" \
  "$([ -d "$STABILITY_DIR" ] && [ -n "$(ls -A "$STABILITY_DIR" 2>/dev/null)" ] && echo 1 || echo 0)"

# =========================================================================
# Section 2: THE TOLERANCE-READ INVARIANT -- proves this test (and the
# stability_verdict primitive it protects) reads the tolerance fresh from
# a config file at call time, never hardcodes a copy of the number.
# =========================================================================
echo
echo "=== Section 2: tolerance-read invariant (config-driven, never hardcoded) ==="

chk "config/fastcycle/thresholds.yaml (T003) is readable" \
  "$([ -r "$REAL_THRESHOLDS" ] && echo 1 || echo 0)"

REAL_TOL="$(read_tolerance_pct "$REAL_THRESHOLDS" 2>/dev/null || true)"
info "config/fastcycle/thresholds.yaml token_stability_tolerance_pct read live = '$REAL_TOL'"
REAL_TOL_SANE="$(python3 -c "
import sys
try:
    v = float(sys.argv[1])
    sys.exit(0 if 0 < v <= 100 else 1)
except (ValueError, IndexError):
    sys.exit(1)
" "${REAL_TOL:-}" > /dev/null 2>&1; echo $?)"
chk "the live-read real tolerance is a sane percentage in (0, 100] -- read dynamically, never assumed to be a specific literal (constitution 11.4.6)" \
  "$([ "$REAL_TOL_SANE" = "0" ] && echo 1 || echo 0)"

# Two fixture thresholds files, syntactically identical in shape to the
# real config, differing ONLY in the tolerance value.
FIXTURE_TIGHT="$TMP/thresholds_tight.yaml"
FIXTURE_LOOSE="$TMP/thresholds_loose.yaml"
cat > "$FIXTURE_TIGHT" <<'CFG_TIGHT'
schema_version: 1
token_stability_tolerance_pct: 1   # T110 fixture: deliberately tight tolerance
CFG_TIGHT
cat > "$FIXTURE_LOOSE" <<'CFG_LOOSE'
schema_version: 1
token_stability_tolerance_pct: 95   # T110 fixture: deliberately loose tolerance
CFG_LOOSE

TIGHT_READ="$(read_tolerance_pct "$FIXTURE_TIGHT")"
LOOSE_READ="$(read_tolerance_pct "$FIXTURE_LOOSE")"
chk "control needle #2: read_tolerance_pct genuinely extracts a DIFFERENT numeric value from two syntactically-distinct fixture files ('$TIGHT_READ' vs '$LOOSE_READ') -- proves the extraction tracks file content, not a cached/hardcoded copy" \
  "$([ "$TIGHT_READ" = "1" ] && [ "$LOOSE_READ" = "95" ] && echo 1 || echo 0)"

# The identical borderline fixture pair for both invocations: run1=1000,
# run2=1100 -> delta_pct = 10.0% exactly. Under the tight (1%) fixture
# this MUST fail; under the loose (95%) fixture this MUST pass.
BORDER_RUN1=1000
BORDER_RUN2=1100

TIGHT_OUT="$("$SELF" --single-verdict "$BORDER_RUN1" "$BORDER_RUN2" "$FIXTURE_TIGHT" 2>&1)"; TIGHT_RC=$?
LOOSE_OUT="$("$SELF" --single-verdict "$BORDER_RUN1" "$BORDER_RUN2" "$FIXTURE_LOOSE" 2>&1)"; LOOSE_RC=$?
info "subprocess run against TIGHT (tol=1%): rc=$TIGHT_RC output: $TIGHT_OUT"
info "subprocess run against LOOSE (tol=95%): rc=$LOOSE_RC output: $LOOSE_OUT"

chk "THE SAME SCRIPT FILE, invoked as a real child process against the TIGHT fixture (tolerance=1%), correctly FAILs the borderline 10%-delta fixture (rc!=0)" \
  "$([ "$TIGHT_RC" != "0" ] && echo 1 || echo 0)"
chk "THE SAME SCRIPT FILE, invoked as a real child process against the LOOSE fixture (tolerance=95%), correctly PASSes the IDENTICAL borderline 10%-delta fixture (rc=0)" \
  "$([ "$LOOSE_RC" = "0" ] && echo 1 || echo 0)"
chk "the two subprocess invocations of the SAME script against the SAME borderline fixture but DIFFERENT config files produce DIFFERENT verdicts -- mechanical proof the tolerance is read fresh from the given file at run time, never hardcoded (a hardcoded copy would make both invocations agree regardless of which config was passed)" \
  "$([ "$TIGHT_RC" != "$LOOSE_RC" ] && echo 1 || echo 0)"

# =========================================================================
# Section 3: GOLDEN -- two runs of the SAME frozen sample item on the SAME
# inputs, within the REAL configured tolerance, PASS (spec.md US4 AS3;
# tasks.md T119's own contract).
# =========================================================================
echo
echo "=== Section 3: GOLDEN -- within-tolerance double-run stability ==="

if [ -z "${REAL_TOL:-}" ]; then
  chk "GOLDEN: within-tolerance double-run PASSes (skipped -- real tolerance unreadable, see Section 2)" "0"
else
  GOLDEN_RUN1=5000
  # run2 = run1 + half of the tolerance's worth of tokens -- guaranteed
  # strictly within the real configured tolerance.
  GOLDEN_RUN2="$(python3 -c "
run1 = $GOLDEN_RUN1
tol = $REAL_TOL
print(int(run1 + (run1 * tol / 100.0) * 0.5))
")"
  GOLDEN_OUT="$(stability_verdict "$GOLDEN_RUN1" "$GOLDEN_RUN2" "$REAL_THRESHOLDS")"; GOLDEN_RC=$?
  info "GOLDEN: run1=$GOLDEN_RUN1 run2=$GOLDEN_RUN2 (half the real tolerance of $REAL_TOL%) -- $GOLDEN_OUT"
  chk "GOLDEN: the SAME frozen sample item run twice on the same inputs, with a delta half the real configured tolerance, PASSes stability (rc=0)" \
    "$([ "$GOLDEN_RC" = "0" ] && echo 1 || echo 0)"
fi

# =========================================================================
# Section 4: GOLDEN-BAD -- a token-count delta EXCEEDING the real
# configured tolerance FAILs the item (tasks.md T110's own words: "a run
# outside it FAILs the item").
# =========================================================================
echo
echo "=== Section 4: GOLDEN-BAD -- outside-tolerance double-run FAILs ==="

if [ -z "${REAL_TOL:-}" ]; then
  chk "GOLDEN-BAD: outside-tolerance double-run FAILs the item (skipped -- real tolerance unreadable, see Section 2)" "0"
else
  BAD_RUN1=5000
  # run2 = run1 + DOUBLE the tolerance's worth of tokens -- guaranteed
  # strictly outside the real configured tolerance.
  BAD_RUN2="$(python3 -c "
run1 = $BAD_RUN1
tol = $REAL_TOL
print(int(run1 + (run1 * tol / 100.0) * 2.0) + 1)
")"
  BAD_OUT="$(stability_verdict "$BAD_RUN1" "$BAD_RUN2" "$REAL_THRESHOLDS")"; BAD_RC=$?
  info "GOLDEN-BAD: run1=$BAD_RUN1 run2=$BAD_RUN2 (double the real tolerance of $REAL_TOL%) -- $BAD_OUT"
  chk "GOLDEN-BAD: the SAME frozen sample item run twice on the same inputs, with a delta double the real configured tolerance, FAILs the item (rc!=0) -- token-count instability across identical runs is itself a defect" \
    "$([ "$BAD_RC" != "0" ] && echo 1 || echo 0)"
fi

# =========================================================================
# Section 5: NEGATIVE CONTROL -- the check discriminates on RELATIVE
# (percentage) delta, not raw absolute token count, so a big-token item
# with a small percentage delta is NOT mistaken for instability merely
# because its raw token delta is numerically large (constitution
# 11.4.201(1) false-positive guard).
# =========================================================================
echo
echo "=== Section 5: negative control -- percentage delta, not absolute delta ==="

# Both fixtures below use the SAME tight (1%) fixture threshold file from
# Section 2, so the comparison is apples-to-apples.
SMALL_RUN1=100
SMALL_RUN2=115          # delta_pct = 15% -> FAILs under a 1% tolerance
                          # even though the absolute delta is only 15 tokens.
BIG_RUN1=1000000
BIG_RUN2=1015000         # delta_pct = 1.5% -> also FAILs under 1%, but is
                          # included for the PASS-side check below at a
                          # looser tolerance to prove the percentage
                          # comparison, not the token count, decides it.

SMALL_OUT="$(stability_verdict "$SMALL_RUN1" "$SMALL_RUN2" "$FIXTURE_TIGHT")"; SMALL_RC=$?
info "negative control (small-absolute-delta, unstable-by-percentage): run1=$SMALL_RUN1 run2=$SMALL_RUN2 tol=1% -- $SMALL_OUT"
chk "negative control: a TINY absolute delta (15 tokens) that is a LARGE percentage delta (15%) correctly FAILs under a 1% tolerance -- the check is not fooled by a small raw number into declaring stability" \
  "$([ "$SMALL_RC" != "0" ] && echo 1 || echo 0)"

BIG_OUT="$(stability_verdict "$BIG_RUN1" "$BIG_RUN2" "$FIXTURE_LOOSE")"; BIG_RC=$?
info "negative control (huge-absolute-delta, stable-by-percentage): run1=$BIG_RUN1 run2=$BIG_RUN2 tol=95% -- $BIG_OUT"
chk "negative control: a HUGE absolute delta (15,000 tokens) that is a SMALL percentage delta (1.5%) correctly PASSes under a 95% tolerance -- proves the discrimination is genuinely RELATIVE (percentage-of-run1), never a bare 'big number = unstable' bluff" \
  "$([ "$BIG_RC" = "0" ] && echo 1 || echo 0)"

# =========================================================================
# Section 6: paired-mutation self-test (tasks.md T111's own named mutation
# for T-E07: "tolerance read after the runs"). tasks.md T110's own task
# line requires the tolerance be read "before any run" -- this section
# demonstrates WHY that ordering matters and mechanically proves a real
# meta-test built against this contract would catch a violation of it.
#
# Model: a compliant implementation freezes the tolerance value BEFORE the
# double-run happens (tol_before_runs, captured from the config file as it
# reads at that moment). A mutated implementation instead re-reads the
# config file only AFTER the runs have already produced their token
# counts -- i.e. "tolerance read after the runs" -- which is exactly the
# window in which the config file could have changed underneath it
# (whether by a concurrent writer or by any other means), producing a
# verdict against a tolerance that was never true at run time. The mutated
# behaviour is reproduced deterministically below via an explicit,
# control-needle-proven config swap between the "before" read and the
# "after" read, using the identical MUT_RUN1/MUT_RUN2 pair for both.
# =========================================================================
echo
echo "=== Section 6: paired-mutation self-test (tasks.md T111: 'tolerance read after the runs') ==="

MUT_CFG="$TMP/thresholds_mutation_swap.yaml"
cat > "$MUT_CFG" <<'CFG_MUT_BEFORE'
schema_version: 1
token_stability_tolerance_pct: 1   # T110 mutation fixture: the TRUE tolerance in force before any run
CFG_MUT_BEFORE

# Step 1: read the tolerance BEFORE any run -- this is what a compliant
# ("before any run") implementation captures and freezes.
TOL_BEFORE_RUNS="$(read_tolerance_pct "$MUT_CFG" 2>/dev/null || true)"
MUT_CFG_CONTENT_BEFORE_SWAP="$(cat "$MUT_CFG" 2>/dev/null || true)"

# Step 2: the double-run happens. Delta = |5300-5000|/5000 = 6.0% -- well
# outside the true (tight) tolerance of 1% frozen above, and well inside a
# loose tolerance chosen below for the mutated branch.
MUT_RUN1=5000
MUT_RUN2=5300

# Step 3: simulate the exact hazard "before any run" exists to foreclose --
# the SAME config path is overwritten with a much looser tolerance AFTER
# the runs already produced MUT_RUN1/MUT_RUN2.
cat > "$MUT_CFG" <<'CFG_MUT_AFTER'
schema_version: 1
token_stability_tolerance_pct: 50   # T110 mutation fixture: swapped in AFTER the runs already happened
CFG_MUT_AFTER
MUT_CFG_CONTENT_AFTER_SWAP="$(cat "$MUT_CFG" 2>/dev/null || true)"

chk "control needle: the config-swap simulation genuinely changed $MUT_CFG's on-disk content between the 'before any run' read and the 'after the runs' read (before='$MUT_CFG_CONTENT_BEFORE_SWAP' after='$MUT_CFG_CONTENT_AFTER_SWAP') -- this is a real content change, not a decorative no-op" \
  "$([ -n "$MUT_CFG_CONTENT_BEFORE_SWAP" ] && [ -n "$MUT_CFG_CONTENT_AFTER_SWAP" ] && [ "$MUT_CFG_CONTENT_BEFORE_SWAP" != "$MUT_CFG_CONTENT_AFTER_SWAP" ] && echo 1 || echo 0)"

if [ -z "${TOL_BEFORE_RUNS:-}" ]; then
  chk "paired-mutation self-test: 'tolerance read after the runs' (skipped -- the pre-run tolerance read failed, see needles above)" "0"
else
  # CORRECT: the tolerance frozen BEFORE any run (1%) is applied to the
  # identical run pair -- the true, compliant "before any run" behaviour.
  FROZEN_CFG="$TMP/thresholds_frozen_before_runs.yaml"
  printf 'schema_version: 1\ntoken_stability_tolerance_pct: %s\n' "$TOL_BEFORE_RUNS" > "$FROZEN_CFG"
  CORRECT_MUT_OUT="$(stability_verdict "$MUT_RUN1" "$MUT_RUN2" "$FROZEN_CFG")"; CORRECT_MUT_RC=$?
  info "correct (tolerance frozen BEFORE any run, tol=$TOL_BEFORE_RUNS%): run1=$MUT_RUN1 run2=$MUT_RUN2 -- $CORRECT_MUT_OUT"

  # MUTATED: the tolerance is re-read from the SAME config path only AFTER
  # the runs -- picking up the since-swapped, looser value (50%).
  MUTATED_MUT_OUT="$(stability_verdict "$MUT_RUN1" "$MUT_RUN2" "$MUT_CFG")"; MUTATED_MUT_RC=$?
  info "mutated (tolerance read AFTER the runs, from the swapped config): run1=$MUT_RUN1 run2=$MUT_RUN2 -- $MUTATED_MUT_OUT"

  chk "CORRECT ('before any run'): the SAME 6.0%-delta double-run FAILs stability (rc!=0) when the tolerance is the value that was genuinely true before any run happened (1%)" \
    "$([ "$CORRECT_MUT_RC" != "0" ] && echo 1 || echo 0)"
  chk "MUTATED ('tolerance read after the runs'): the IDENTICAL 6.0%-delta double-run wrongly PASSes stability (rc=0) once the tolerance is instead re-read only after the runs, from a config that changed in that window" \
    "$([ "$MUTATED_MUT_RC" = "0" ] && echo 1 || echo 0)"

  MUT_FLIPS="$([ "$CORRECT_MUT_RC" != "0" ] && [ "$MUTATED_MUT_RC" = "0" ] && echo 1 || echo 0)"
  if [ "$MUT_FLIPS" = "1" ]; then
    echo "ok mutation-simulation: reading the tolerance AFTER the runs (tasks.md"
    echo "   T111's own named paired mutation, 'tolerance read after the runs')"
    echo "   flips this identical 6.0%-delta double-run's verdict from FAIL"
    echo "   (correct -- tolerance frozen BEFORE any run, 1%) to PASS (wrong --"
    echo "   tolerance re-read AFTER the runs from a since-swapped config, 50%)."
    echo "   A real T119 meta-test asserting this double-run's actual verdict"
    echo "   equals its fixed expected verdict (FAIL, since 6.0% exceeds the"
    echo "   true pre-run 1% tolerance) would go from PASS (matching expected"
    echo "   under correct 'before any run' behaviour) to FAIL (mismatching,"
    echo "   actual=PASS, once the implementation is mutated to read the"
    echo "   tolerance only after the runs) -- genuinely catching this mutation."
  else
    echo "NOT ok mutation-simulation FAILED: correct_rc=$CORRECT_MUT_RC"
    echo "     mutated_rc=$MUTATED_MUT_RC (expected correct!=0, mutated=0) --"
    echo "     this fixture would not catch the 'tolerance read after the"
    echo "     runs' mutation and needs revising"
  fi
  chk "mutation-simulation (tasks.md T111: 'tolerance read after the runs'): the mutation genuinely flips the verdict from correctly-FAIL to wrongly-PASS on the identical run pair -- a real T119 meta-test would catch it" \
    "$MUT_FLIPS"
fi

# =========================================================================
# Section 7: honest real-after note (informational only -- T119 has no
# dedicated contract file or fixed evidence schema per
# contracts/common-conventions.md's Tool-map / no-contract tables, so this
# section does NOT guess a JSON shape (constitution 11.4.6); it only
# reports honestly whether T119's output directory has appeared).
# =========================================================================
echo
echo "=== Section 7: honest real-after note (informational, no schema assumed) ==="
if [ -d "$STABILITY_DIR" ] && [ -n "$(ls -A "$STABILITY_DIR" 2>/dev/null)" ]; then
  info "qa-results/fastcycle/tokens/stability/ now exists and is non-empty -- T119 appears to have landed. This test's stability_verdict function is the fixed, binding comparison contract (Producer != Verifier, constitution 11.4.240) -- T119's own per-item verdicts should agree with it; a future revision of this test (or T119 itself, per constitution 11.4.115(F) polarity switch) is where that agreement is checked against T119's actual recorded schema, never guessed here."
else
  info "qa-results/fastcycle/tokens/stability/ still absent or empty -- no schema to introspect yet; this is the EXPECTED RED-today outcome, matching Section 1"
fi

echo
echo "SUMMARY pass=$((N - FAIL)) fail=$FAIL total=$N"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
