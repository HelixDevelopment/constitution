#!/bin/bash
# T015 RED test: fc_timer wiring into pre_build_verification.sh
# (spec 004-fast-dev-cycles; contracts/common-conventions.md; plan.md T-A01;
#  spec.md FR-001, FR-002, SC-001; tasks.md T015, T028, T029)
#
# Purpose: pin the OBSERVABLE per-section-timing-TSV behaviour of
#          device/rockchip/rk3588/tests/pre_build_verification.sh BEFORE T028 (implements
#          constitution/scripts/fastcycle/timing/fc_timer.sh) and T029 (wires it into
#          pre_build_verification.sh) land. RED = today, with neither T028 nor T029 landed,
#          every acceptance-criterion assertion below FAILS because the TSV plan.md T-A01
#          describes ("qa-results/fastcycle/<run-id>/prebuild_sections.tsv") does not exist.
#
# Producer != Verifier (Constitution S11.4.240): this file only WRITES the failing test. It
# does NOT implement fc_timer.sh, does NOT wire pre_build_verification.sh, and does NOT
# weaken this file's own assertions to make them pass early.
#
# ---------------------------------------------------------------------------------------
# INDEPENDENT VERIFICATION OF THE "94" FIGURE (Constitution S11.4.6 no-guessing -- do not
# trust an unverified claim; this comment IS the record of that verification, not an
# assumption; see qa-results/fastcycle/us1/red/T015/candidate_fingerprint.json for the
# machine-readable form of the same data):
#
#   tasks.md T015/T029 and plan.md T-A01 all cite "94" ("94 SECTION banners" / "94 sections"
#   / "TSV ... 94 on a full run"). Provenance traced to
#   specs/004-fast-dev-cycles/research/R2_measured_causes.md row P-23 ("94 section banners",
#   measured 2026-09-26 over git HEAD fd5585c7fc8) -- that file states the figure as a fact
#   but records NO exact extraction command, so it cannot be mechanically reproduced from the
#   research doc alone.
#
#   Independently reproducing the count against THIS repo's pre_build_verification.sh
#   (2026-09-28, 51272 working-tree lines, HEAD 51244 lines -- the file is under active
#   parallel-track edit right now) found it uses AT LEAST SIX mutually-inconsistent
#   banner-decoration conventions accumulated over its multi-month history:
#     (1) the `log_section()` bash function (a real 3-line cyan banner): 41 call sites / 40
#         distinct labels -- label "S" is reused for two genuinely DIFFERENT sections
#         (SystemUI WiFi Toggle Audio Fix @ line 2477; Native Library Extraction @ line 2590);
#     (2) `# SECTION <ID>: ...` comment banners closed by a `# --- end SECTION <ID> ---`
#         marker: 66 blocks in plain-ASCII-hyphen style;
#     (3) the SAME closing-marker convention rendered with Unicode box-drawing dashes
#         (`# ─── end SECTION <ID> ─── `) instead of ASCII hyphens: +4 more, missed entirely
#         by a naive ASCII-only grep -- exactly the measuring-instrument trap
#         contracts/common-conventions.md C-004 / Constitution S11.4.273 exist to catch
#         (a first attempt at this count silently under-reported because of it, corrected
#         only after re-deriving the search with a class-matched control needle);
#     (4) raw `echo -e "${BLUE}--- Section <ID>: ... ---${NC}"` banners with NO log_section
#         call and NO end marker at all (sections AC, AD, AQ, AR, AS and dozens more);
#     (5) a `[SECTION <ID>]` bracket style (SECTION Z); and
#     (6) a deeply NESTED family of ~74 `── Section CN-<slug> — ... ──` sub-banners, all
#         children of ONE top-level "SECTION CN: 1.1.2-dev Release Coverage" block.
#
#   A REAL, COMPLETE run of pre_build_verification.sh was executed end-to-end on 2026-09-28
#   (git HEAD ada22d2778276b15e891e263b6243e8129d824a1; wall-clock ~1050.6s / ~17.5 min,
#   consistent with research.md's own "16-24 min" full-run measurement) and its OWN captured
#   stdout parsed for every line whose only leading characters (after stripping ANSI color
#   codes) are decoration followed by "Section"/"SECTION" + an identifier -- i.e. the REAL
#   runtime banner count, not a source-level guess. Result: 188 such lines / 185 distinct
#   labels total; 114 lines / 111 distinct labels if the 74 nested "CN-*" sub-banners are
#   folded into their single "CN" parent (the closest conceptual match to "top-level SECTION
#   banners"). That captured run is archived at
#   qa-results/fastcycle/us1/red/T015/prebuild_full_run_20260928T050150Z.log (sha256
#   a949be5b9e6f2071f040c8fd9cd810bfec8d7613578acab92226b70950aa1d26) and is auto-discovered
#   by this test (see EVIDENCE MODE below) so re-runs do not have to pay the ~17-minute cost
#   again to exercise the full-depth assertions.
#
#   NEITHER 188/185 NOR 114/111 is 94. Conclusion, per this task's own instruction ("if the
#   real number differs, use the REAL number and note the discrepancy, never silently trust
#   an unverified claim"): the file has MORE real, distinctly-labelled section banners today
#   than "94" -- and, given research.md's own measurement is only 2 real days older than this
#   one (2026-09-26 -> 2026-09-28) on a project whose own documented operating model runs many
#   parallel work-streams landing changes to this exact file continuously, the true count is
#   almost certainly a MOVING TARGET, not a fixed constant. Hardcoding either "94" or this
#   run's 188/185/114/111 into this test's PASS/FAIL logic would make the test spuriously
#   flaky against unrelated, legitimate future section additions/removals -- so this test's
#   row-count assertion (ASSERTION 8 below) instead cross-checks the eventual TSV's row count
#   against the SAME real run's OWN observed banner count, which is self-consistent and
#   immune to the file's ongoing growth. "94" and this run's 188/185/114/111 are recorded here
#   purely as dated, evidenced, cross-referenced data points -- never as a literal the
#   pass/fail logic below depends on.
# ---------------------------------------------------------------------------------------
#
# PAIRED MUTATION (T027, not implemented here -- documented so T027's author can wire it):
#   once T028/T029 land, "drop one section's end-timer" (remove exactly one fc_timer_end call
#   for one wrapped section, leaving its start-timer and its log_section/echo banner call
#   intact) MUST flip ASSERTION 8 (row-count == observed-banner-count for the SAME run) to
#   FAIL, because that section's banner still prints (raising the observed count) while its
#   TSV row never gets written (the row count stays one short) -- the dynamic cross-check
#   design above is deliberately chosen so this mutation class is caught WITHOUT needing to
#   know the section count in advance.
#
# Usage: bash test_fc_timer_prebuild_red.sh
#   Env FC_TIMER_RED_LOG=<path>    : skip auto-discovery and invoking pre_build_verification.sh
#                                    for real; analyze an already-captured real stdout log at
#                                    <path> instead (must be a REAL captured run, never
#                                    hand-written -- this test does not validate that, the
#                                    honesty burden is on the caller per S11.4.6).
#   Env FC_TIMER_RED_FULL_RUN=1    : (only when FC_TIMER_RED_LOG is unset and no evidence log
#                                    is auto-discovered) run pre_build_verification.sh to
#                                    completion for real (~17-24 min) instead of a bounded
#                                    sample.
#   Env FC_TIMER_RED_BOUND_S=N     : bound in seconds for the default bounded sample run
#                                    (default 90; used only when neither of the above applies
#                                    and no evidence log auto-discovers).
#
# Auto-discovery (default, no env vars needed): the most recent
# qa-results/fastcycle/us1/red/T015/prebuild_full_run_*.log is used automatically if present
# (this is how a plain `bash test_fc_timer_prebuild_red.sh` exercises the FULL assertion set
# today, using the dated real evidence captured above, without re-paying the ~17-minute cost).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../../.." && pwd)"
PRE_BUILD="$ROOT/device/rockchip/rk3588/tests/pre_build_verification.sh"
FC_TIMER="$HERE/../timing/fc_timer.sh"
NEEDLE_PRESENT="CM-COVENANT-114-182-PROPAGATION"
NEEDLE_FABRICATED="CM-FASTCYCLE-FABRICATED-NEEDLE-T015-DOES-NOT-EXIST"
EVIDENCE_DEFAULT_DIR="$ROOT/qa-results/fastcycle/us1/red/T015"

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

FAIL=0; N=0; SKIPPED=0
chk() { N=$((N + 1)); if [ "$2" = "1" ]; then echo "PASS[$N]: $1"; else echo "FAIL[$N]: $1"; FAIL=$((FAIL + 1)); fi; }
skip() { N=$((N + 1)); SKIPPED=$((SKIPPED + 1)); echo "SKIP[$N]: $1"; }

[ -f "$PRE_BUILD" ] || { echo "FATAL: pre_build_verification.sh not found at $PRE_BUILD"; exit 2; }

# ---- Precondition sanity (0): confirm we are looking at the file the claims above describe ----
LIVE_LINES="$(wc -l < "$PRE_BUILD" | tr -d ' ')"
chk "pre_build_verification.sh exists and is readable ($LIVE_LINES lines)" "$([ -n "$LIVE_LINES" ] && [ "$LIVE_LINES" -gt 0 ] && echo 1 || echo 0)"

# ============================================================================
# GROUP 1 -- static source-level absence checks (fast, always run)
# ============================================================================

# 1. fc_timer.sh (T028's deliverable) does not exist yet.
chk "fc_timer.sh is ABSENT today (RED precondition -- T028 not landed)" "$([ ! -f "$FC_TIMER" ] && echo 1 || echo 0)"

# 2. pre_build_verification.sh does not yet source fc_timer.sh (T029's deliverable).
grep -q 'fc_timer\.sh' "$PRE_BUILD" 2>/dev/null && SRC_LINE=1 || SRC_LINE=0
chk "pre_build_verification.sh sources fc_timer.sh (T029 acceptance criterion)" "$([ "$SRC_LINE" = 1 ] && echo 1 || echo 0)"

# 3. No FC_TIMING no-op gate referenced (T028 acceptance criterion: "no-op when FC_TIMING=0").
grep -q 'FC_TIMING' "$PRE_BUILD" 2>/dev/null && FCT_REF=1 || FCT_REF=0
chk "pre_build_verification.sh honours FC_TIMING (T028 acceptance criterion)" "$([ "$FCT_REF" = 1 ] && echo 1 || echo 0)"

# 4. No literal TSV output path referenced anywhere in source (T029 acceptance criterion).
grep -q 'prebuild_sections\.tsv' "$PRE_BUILD" 2>/dev/null && TSV_REF=1 || TSV_REF=0
chk "pre_build_verification.sh references its documented TSV output path (T029)" "$([ "$TSV_REF" = 1 ] && echo 1 || echo 0)"

# ============================================================================
# GROUP 2 -- control needle (C-004 / S11.4.273): prove the grep INSTRUMENT can see a
# known-present thing, and cannot see a fabricated thing, through the SAME code path, BEFORE
# any "absent" conclusion elsewhere in this file is trusted.
# ============================================================================
PRESENT_HITS="$(grep -c -- "$NEEDLE_PRESENT" "$PRE_BUILD" 2>/dev/null || true)"
: "${PRESENT_HITS:=0}"
chk "control needle: known-present '$NEEDLE_PRESENT' found in source ($PRESENT_HITS hits)" "$([ "$PRESENT_HITS" -ge 1 ] && echo 1 || echo 0)"
FAB_HITS="$(grep -c -- "$NEEDLE_FABRICATED" "$PRE_BUILD" 2>/dev/null || true)"
: "${FAB_HITS:=0}"
chk "negative control: fabricated needle correctly absent from source ($FAB_HITS hits)" "$([ "$FAB_HITS" -eq 0 ] && echo 1 || echo 0)"

# ============================================================================
# GROUP 3 -- real-run behavioural evidence. "The RED observation must be against REAL
# behaviour, not a guess" -- this section always exercises the REAL pre_build_verification.sh
# (or a REAL previously-captured run of it), never a simulation or a hand-written stand-in.
# ============================================================================
EVIDENCE_LOG=""
EVIDENCE_DEPTH="none"   # none | bounded | full

if [ -n "${FC_TIMER_RED_LOG:-}" ] && [ -f "${FC_TIMER_RED_LOG:-/nonexistent}" ]; then
  EVIDENCE_LOG="$FC_TIMER_RED_LOG"
  EVIDENCE_DEPTH="full"
  echo "INFO: using caller-supplied evidence log: $EVIDENCE_LOG"
else
  _auto_candidate=""
  if [ -d "$EVIDENCE_DEFAULT_DIR" ]; then
    _auto_candidate="$(find "$EVIDENCE_DEFAULT_DIR" -maxdepth 1 -name 'prebuild_full_run_*.log' 2>/dev/null | sort | tail -n1)"
  fi
  if [ -n "$_auto_candidate" ] && [ -f "$_auto_candidate" ]; then
    EVIDENCE_LOG="$_auto_candidate"
    EVIDENCE_DEPTH="full"
    echo "INFO: auto-discovered evidence log: $EVIDENCE_LOG"
  elif [ "${FC_TIMER_RED_FULL_RUN:-0}" = "1" ]; then
    echo "INFO: FC_TIMER_RED_FULL_RUN=1 -- running pre_build_verification.sh to completion for real (this takes ~17-24 minutes)."
    EVIDENCE_LOG="$TMP/full_run.log"
    bash "$PRE_BUILD" >"$EVIDENCE_LOG" 2>&1
    EVIDENCE_DEPTH="full"
  else
    BOUND="${FC_TIMER_RED_BOUND_S:-90}"
    echo "INFO: no evidence log found and FC_TIMER_RED_FULL_RUN unset -- running a bounded ${BOUND}s real sample instead."
    EVIDENCE_LOG="$TMP/bounded_run.log"
    timeout -k 5 "$BOUND" bash "$PRE_BUILD" >"$EVIDENCE_LOG" 2>&1
    EVIDENCE_DEPTH="bounded"
  fi
fi

# Strip ANSI colour codes once; every downstream check reads the clean copy.
CLEAN_LOG="$TMP/clean.log"
sed -E 's/\x1b\[[0-9;]*m//g' "$EVIDENCE_LOG" > "$CLEAN_LOG" 2>/dev/null || cp "$EVIDENCE_LOG" "$CLEAN_LOG"

CLEAN_LOG_LINES="$(wc -l < "$CLEAN_LOG" 2>/dev/null | tr -d ' ')"
: "${CLEAN_LOG_LINES:=0}"
chk "real (${EVIDENCE_DEPTH}) run produced captured output ($CLEAN_LOG_LINES lines from $EVIDENCE_LOG)" "$([ "$CLEAN_LOG_LINES" -gt 0 ] && echo 1 || echo 0)"

# 5. Real section banners genuinely print (the mechanism fc_timer.sh will wrap is alive).
BANNER_RE='^[^A-Za-z0-9]*[Ss][Ee][Cc][Tt][Ii][Oo][Nn][[:space:]]+[A-Za-z0-9][A-Za-z0-9-]*'
BANNER_COUNT="$(grep -cE "$BANNER_RE" "$CLEAN_LOG" 2>/dev/null || true)"
: "${BANNER_COUNT:=0}"
chk "real run shows genuine SECTION banner output ($BANNER_COUNT lines match the banner shape)" "$([ "$BANNER_COUNT" -ge 1 ] && echo 1 || echo 0)"

# 6. No TSV artefact exists anywhere in the tree at any documented fastcycle timing path.
TSV_HITS="$(find "$ROOT/qa-results/fastcycle" -name 'prebuild_sections.tsv' 2>/dev/null | wc -l | tr -d ' ')"
: "${TSV_HITS:=0}"
chk "no prebuild_sections.tsv exists anywhere under qa-results/fastcycle/ (RED)" "$([ "$TSV_HITS" -eq 0 ] && echo 1 || echo 0)"

TSV_EXISTS=0
_f=""
_found_tsv="$(find "$ROOT/qa-results/fastcycle" -mindepth 2 -maxdepth 2 -name 'prebuild_sections.tsv' 2>/dev/null | sort | tail -n1)"
if [ -n "$_found_tsv" ] && [ -f "$_found_tsv" ]; then TSV_EXISTS=1; _f="$_found_tsv"; fi

# 7. Acceptance criterion: "TSV exists with one row per section that ran" -- MUST currently FAIL.
chk "TSV exists with one row per section that ran (T029 acceptance criterion)" "$([ "$TSV_EXISTS" = 1 ] && echo 1 || echo 0)"

if [ "$EVIDENCE_DEPTH" = "full" ]; then
  # 8. Dynamic cross-check: TSV row count == the SAME run's observed banner count. Never a
  #    hardcoded literal (see the header investigation above) -- deliberately re-derived from
  #    THIS run's own output so the assertion tracks the file's real, changing section count.
  if [ "$TSV_EXISTS" = 1 ]; then
    TSV_ROWS="$(tail -n +2 "$_f" 2>/dev/null | grep -c . || true)"
  else
    TSV_ROWS=0
  fi
  : "${TSV_ROWS:=0}"
  chk "TSV row count ($TSV_ROWS) equals this run's observed SECTION-banner count ($BANNER_COUNT)" "$([ "$TSV_ROWS" -eq "$BANNER_COUNT" ] && [ "$TSV_EXISTS" = 1 ] && echo 1 || echo 0)"

  # 9. Control-needle section's row must appear in the TSV. First confirm the needle's own
  #    banner genuinely ran in THIS evidence (else a FAIL here would be ambiguous between
  #    "needle section didn't run" and "it ran but got no row" -- we want the latter, unambiguous
  #    signal, matching how the needle behaves once T028/T029 land).
  NEEDLE_RAN="$(grep -c -- "$NEEDLE_PRESENT" "$CLEAN_LOG" 2>/dev/null || true)"
  : "${NEEDLE_RAN:=0}"
  chk "control-needle section genuinely ran in this evidence ($NEEDLE_RAN hits in captured output)" "$([ "$NEEDLE_RAN" -ge 1 ] && echo 1 || echo 0)"
  if [ "$TSV_EXISTS" = 1 ]; then
    NEEDLE_IN_TSV="$(grep -c -- "$NEEDLE_PRESENT" "$_f" 2>/dev/null || true)"
  else
    NEEDLE_IN_TSV=0
  fi
  : "${NEEDLE_IN_TSV:=0}"
  chk "control-needle section's row appears in the TSV (plan.md T-A01 control needle)" "$([ "$NEEDLE_IN_TSV" -ge 1 ] && echo 1 || echo 0)"

  # 10. Section-time-sum within 2% of wall-clock, with residue reported. There is no timing
  #     column to sum today (no TSV), so this is a direct, meaningful FAIL, not a SKIP.
  if [ "$TSV_EXISTS" = 1 ]; then
    # Documented future column contract (T028): a duration column in milliseconds, one of
    # possibly several columns; the eventual T029 implementer's exact header decides which.
    # Until it exists there is nothing to sum -- report the absence explicitly.
    chk "section-time-sum is within 2% of wall-clock with residue reported (T-A01 confirmation)" "0"
  else
    chk "section-time-sum is within 2% of wall-clock with residue reported (T-A01 confirmation) -- TSV absent, nothing to sum" "0"
  fi
else
  skip "TSV row-count == observed-banner-count cross-check (needs full-depth evidence; got '$EVIDENCE_DEPTH' -- set FC_TIMER_RED_FULL_RUN=1 or FC_TIMER_RED_LOG=<path> for full depth)"
  skip "control-needle section's row-in-TSV check (needs full-depth evidence; got '$EVIDENCE_DEPTH')"
  skip "section-time-sum-within-2%-of-wall-clock check (needs full-depth evidence; got '$EVIDENCE_DEPTH')"
fi

echo "SUMMARY: $((N - FAIL - SKIPPED)) pass / $FAIL fail / $SKIPPED skip of $N assertions (evidence depth: $EVIDENCE_DEPTH, log: $EVIDENCE_LOG)"
[ "$FAIL" = 0 ]
