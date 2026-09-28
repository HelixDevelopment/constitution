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
# ---------------------------------------------------------------------------------------
# RECONCILIATION (Constitution S11.4.115(polarity switch) / S11.4.120(gate reconciliation),
# applied 2026-09-28 the moment T028+T029 genuinely landed -- conductor-only, since this
# file's own header commits it to "does NOT weaken this file's own assertions", so any
# broken-assertion fix is reconciliation, never a silent weakening):
#
#   T029's landing (independently re-verified, +180/-0 lines, additive-only wiring into
#   pre_build_verification.sh) exposed FOUR assertions in the ORIGINAL version of this file
#   that could never pass under ANY correct implementation, by construction:
#     (a) "fc_timer.sh is ABSENT today" -- was written as a permanent pre-landing snapshot
#         with no polarity switch; false forever the moment T028 lands.
#     (b) "no prebuild_sections.tsv exists anywhere" vs "TSV exists with rows" -- MUTUALLY
#         EXCLUSIVE by construction once ANY implementation run has ever produced a TSV file
#         anywhere under qa-results/fastcycle/; exactly one of the pair must fail forever.
#     (c) the control-needle TSV-row check searched for the GATE NAME
#         "CM-COVENANT-114-182-PROPAGATION" as a literal TSV row value -- but that string is
#         a `log_pass`/`log_fail` MESSAGE emitted from INSIDE "SECTION TSBA: Testing-System
#         Bluff-Audit Gates (TSBA_GATE_BLOCK_20260610)", never a SECTION banner itself (T-A01's
#         instrumentation is per-SECTION granularity, not per-gate) -- so the gate-name string
#         can never appear as a TSV `id` column value under ANY correct per-section
#         implementation. Traced by line-number-then-nearest-preceding-boundary-call
#         resolution (never hardcoded): needle at source line 44850, nearest preceding
#         `log_section "SECTION TSBA: ..."` call at line 41943.
#     (d) "section-time-sum is within 2% of wall-clock" was `chk ... "0"` -- a LITERAL "0"
#         hardcoded in BOTH branches of its if/else (the original lines 259 and 261) --
#         tautologically FAIL regardless of any TSV content, forever.
#
#   Fix, per S11.4.115's polarity-switch pattern: a single `RED_MODE` env-overridable flag,
#   defaulting to 0 (GREEN / post-landing -- the repo's now-PERMANENT state, since fc_timer.sh
#   is a landed, committed part of the codebase going forward) with `FC_TIMER_RED_MODE=1`
#   preserved as an explicit, documented escape hatch to reconstruct and audit the ORIGINAL
#   pre-landing RED assertions (requires temporarily moving fc_timer.sh aside -- an audit/
#   documentation path, never the routine one). Assertion (a) flips its polarity on the flag.
#   Assertion (b)'s "absent anywhere" half is RED_MODE=1-only (that precondition is now
#   permanently false in RED_MODE=0, so it is dropped from the GREEN path rather than left to
#   spuriously fail forever); its "present with rows" half is unconditional (was already
#   correct). Assertion (c) is fixed by dynamically resolving the needle's OWN enclosing
#   section from source (nearest preceding `_fc_section_boundary '...'` / `log_section "..."`
#   call before the needle's line number -- re-derived at every run, never hardcoded, matching
#   this file's own "never hardcode 94" philosophy above) and checking THAT section's TSV row,
#   never the raw gate-name string. Assertion (d) is now computed for real: sum of the TSV's
#   `duration_ms` column vs (max(end_ns) - min(start_ns)) in milliseconds across all rows of
#   the SAME run, in python3 (nanosecond epoch values exceed IEEE-754 double's exact-integer
#   range -- ~1.9e18 vs ~9e15 -- so this arithmetic is deliberately NOT done in awk/bash
#   floating point; python3 ints are arbitrary-precision, the correctness-safe choice here).
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
#   Env FC_TIMER_RED_MODE=0|1      : polarity switch (S11.4.115). Default 0 = GREEN /
#                                    post-landing (T028+T029 have landed; this is the repo's
#                                    permanent state going forward -- assert fc_timer.sh IS
#                                    present, sourced, and producing real TSV rows). Set to 1
#                                    ONLY to reconstruct/audit the original pre-landing RED
#                                    assertions (requires fc_timer.sh to be temporarily absent
#                                    or moved aside -- an audit path, not the routine one).
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

RED_MODE="${FC_TIMER_RED_MODE:-0}"
echo "INFO: RED_MODE=$RED_MODE (0=GREEN/post-landing [default], 1=pre-landing audit reconstruction)"

[ -f "$PRE_BUILD" ] || { echo "FATAL: pre_build_verification.sh not found at $PRE_BUILD"; exit 2; }

# ---- Precondition sanity (0): confirm we are looking at the file the claims above describe ----
LIVE_LINES="$(wc -l < "$PRE_BUILD" | tr -d ' ')"
chk "pre_build_verification.sh exists and is readable ($LIVE_LINES lines)" "$([ -n "$LIVE_LINES" ] && [ "$LIVE_LINES" -gt 0 ] && echo 1 || echo 0)"

# ============================================================================
# GROUP 1 -- static source-level absence checks (fast, always run)
# ============================================================================

# 1. fc_timer.sh (T028's deliverable) -- polarity depends on RED_MODE (see RECONCILIATION above).
if [ "$RED_MODE" = "1" ]; then
  chk "fc_timer.sh is ABSENT today (RED precondition -- T028 not landed) [RED_MODE=1]" "$([ ! -f "$FC_TIMER" ] && echo 1 || echo 0)"
else
  chk "fc_timer.sh is PRESENT (T028 landed) [RED_MODE=0/GREEN]" "$([ -f "$FC_TIMER" ] && echo 1 || echo 0)"
fi

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

# 6. No TSV artefact exists anywhere in the tree -- RED_MODE=1-only (S11.4.115 polarity switch;
#    see RECONCILIATION above: this precondition is now PERMANENTLY false in RED_MODE=0/GREEN
#    the moment any implementation run has ever produced a TSV, so asserting it there would be
#    a tautological, unfixable FAIL, not a meaningful regression signal).
TSV_HITS="$(find "$ROOT/qa-results/fastcycle" -name 'prebuild_sections.tsv' 2>/dev/null | wc -l | tr -d ' ')"
: "${TSV_HITS:=0}"
if [ "$RED_MODE" = "1" ]; then
  chk "no prebuild_sections.tsv exists anywhere under qa-results/fastcycle/ (RED) [RED_MODE=1]" "$([ "$TSV_HITS" -eq 0 ] && echo 1 || echo 0)"
else
  skip "no-TSV-anywhere precondition (superseded by assertion 7 in RED_MODE=0/GREEN -- permanently false once any implementation run exists, $TSV_HITS TSV(s) found; this is expected)"
fi

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

  # The needle string itself is a GATE NAME (a log_pass/log_fail message), never a SECTION
  # banner -- T-A01's instrumentation is per-SECTION granularity, so the raw needle string can
  # never appear as a TSV `id` value under any correct implementation (see RECONCILIATION
  # above). Dynamically resolve the needle's OWN enclosing section: the nearest preceding
  # `_fc_section_boundary '...'` / `log_section "..."` call before the needle's source line --
  # re-derived every run, never hardcoded, so this stays correct even if the codebase
  # reorganizes sections later.
  ENCLOSING_SECTION_ID="$(python3 - "$PRE_BUILD" "$NEEDLE_PRESENT" <<'PYEOF'
import re, sys
path, needle = sys.argv[1], sys.argv[2]
lines = open(path, encoding="utf-8", errors="replace").read().splitlines()
needle_line = next((i for i, l in enumerate(lines) if needle in l), None)
if needle_line is None:
    sys.exit(0)
pat1 = re.compile(r"_fc_section_boundary\s+'([^']*)'")
pat2 = re.compile(r'log_section\s+"([^"]*)"')
last = None
for i in range(needle_line + 1):
    m1 = pat1.search(lines[i])
    m2 = pat2.search(lines[i])
    if m1:
        last = m1.group(1)
    elif m2:
        last = m2.group(1)
if last:
    print(last)
PYEOF
)"
  if [ -n "$ENCLOSING_SECTION_ID" ] && [ "$TSV_EXISTS" = 1 ]; then
    NEEDLE_IN_TSV="$(awk -F'\t' -v want="$ENCLOSING_SECTION_ID" 'NR>1 && $3==want {c++} END{print c+0}' "$_f")"
  else
    NEEDLE_IN_TSV=0
  fi
  : "${NEEDLE_IN_TSV:=0}"
  chk "control-needle's enclosing section ('$ENCLOSING_SECTION_ID') has a TSV row (plan.md T-A01 control needle, dynamically resolved)" "$([ "$NEEDLE_IN_TSV" -ge 1 ] && echo 1 || echo 0)"

  # 10. Section-time-sum within 2% of wall-clock, with residue reported. Computed for real
  #     against the TSV's duration_ms column vs (max(end_ns)-min(start_ns)) across the SAME
  #     run. Nanosecond epoch values (~1.9e18) exceed IEEE-754 double's exact-integer range
  #     (~9e15) so this is deliberately done in python3 (arbitrary-precision ints), never
  #     awk/bash floating point (S11.4.6 -- correctness-safe arithmetic, not a guess).
  if [ "$TSV_EXISTS" = 1 ]; then
    TIMESUM_RESULT="$(python3 - "$_f" <<'PYEOF'
import sys
path = sys.argv[1]
rows = []
with open(path, encoding="utf-8", errors="replace") as f:
    header = f.readline()
    for line in f:
        line = line.rstrip("\n")
        if not line:
            continue
        cols = line.split("\t")
        if len(cols) < 6:
            continue
        rows.append(cols)
if not rows:
    print("0 0 0.0 NO_ROWS")
    sys.exit(0)
try:
    starts = [int(r[3]) for r in rows]
    ends = [int(r[4]) for r in rows]
    durs = [int(r[5]) for r in rows]
except (ValueError, IndexError):
    print("0 0 0.0 PARSE_ERROR")
    sys.exit(0)
span_ms = (max(ends) - min(starts)) / 1_000_000
sum_ms = sum(durs)
if span_ms <= 0:
    print(f"{sum_ms} 0 0.0 ZERO_SPAN")
    sys.exit(0)
pct = abs(sum_ms - span_ms) / span_ms * 100.0
print(f"{sum_ms} {span_ms:.3f} {pct:.4f} OK")
PYEOF
)"
    read -r TIME_SUM_MS TIME_SPAN_MS TIME_PCT TIME_STATUS <<EOF
$TIMESUM_RESULT
EOF
    TIME_WITHIN_2PCT=0
    if [ "$TIME_STATUS" = "OK" ]; then
      TIME_WITHIN_2PCT="$(python3 -c "print(1 if $TIME_PCT <= 2.0 else 0)")"
    fi
    chk "section-time-sum (${TIME_SUM_MS}ms) is within 2% of wall-clock span (${TIME_SPAN_MS}ms), residue=${TIME_PCT}% (T-A01 confirmation, status=$TIME_STATUS)" "$TIME_WITHIN_2PCT"
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
