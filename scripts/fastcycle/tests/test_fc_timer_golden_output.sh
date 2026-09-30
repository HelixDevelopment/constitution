#!/bin/bash
# T015 golden-output test: fc_timer wiring must not change any pre_build_verification.sh verdict.
# (spec 004-fast-dev-cycles; plan.md "Rule for every A-task" + T-A01; tasks.md T015)
#
# Purpose: pin the "instrumentation must not change any verdict" rule plan.md states for every
#          A-task: "Each A-task that touches a gate or the commit path ships a golden-output
#          test: the verdict set (or commit result) with the instrumentation equals the verdict
#          set without it, byte for byte after stripping timing columns."
#
# Honest state of this test as of T048 round-3 review finding R3-I6 (2026-09-30): T028
# (fc_timer.sh) and T029 (its wiring into pre_build_verification.sh) ARE landed (both `[x]` in
# tasks.md) -- the STALE claim that used to sit here ("T028/T029 not landed... a true
# before/after comparison is IMPOSSIBLE today") was corrected as part of R3-I6, independently
# re-checked against tasks.md's own live checkbox state before writing this paragraph, per
# S11.4.199. A genuine "with timers" run of pre_build_verification.sh IS now possible, and this
# file performs the real comparison the moment BOTH a "without timers" and a "with timers" real
# evidence log exist on disk (see the Usage section below for how each is located). What is
# ALWAYS verified for real, independent of whether the "with timers" log exists yet:
#   (a) the REAL "without timers" verdict set, captured from an actual pre_build_verification.sh
#       run, is checked for any timing-looking noise that a stripping step would need to remove
#       (Constitution S11.4.6 -- "check", never assume; documented finding: NONE found -- see
#       FINDING note below);
#   (b) the verdict-set EXTRACTION mechanism this test (and the real golden-output comparison
#       below) depends on is deterministic: extracting twice from the SAME real captured log
#       produces byte-identical output (C-003 determinism spirit);
#   (c) the COMPARISON+STRIPPING logic the real "with timers" vs "without timers" diff below
#       uses is self-validated on synthetic fixtures mimicking the real line shape (a
#       golden-good pair that differs ONLY by a synthetic trailing timing suffix -- MUST compare
#       equal after stripping; a golden-bad pair whose ACTUAL verdict differs, not just its
#       timing suffix -- MUST compare unequal; a negative-control pair that differs in gate id
#       only -- MUST also compare unequal, so the comparator is proven to discriminate, not to
#       blindly report "equal" regardless of input).
# The genuine real-vs-real "with timers" comparison itself remains an explicit, honest SKIP
# ONLY when no "with timers" evidence log is present on disk (a fresh checkout, or a run that
# has not been captured yet) -- never a fabricated PASS, and never silently skipped once a real
# log exists (that would be exactly the R3-I6 bug this fix closes: an unconditional SKIP that
# never flips to a real assertion even after the precondition it names is satisfied).
#
# FINDING (checked, not assumed): scanning the real captured evidence log for a
# verdict-line trailing duration suffix ("[N.NNs]"/"(N.NNs)"/"N ms") found exactly one
# superficial match -- "  BT3: bcmdhd keep_alive_period=20000 (20s)...   \xe2\x9c\x93 Keep-alive
# period 20s" (qa-results/fastcycle/us1/red/T015/prebuild_full_run_20260928T050150Z.log line
# 1302) -- which on inspection is the SUBSTANTIVE content of that check (a WiFi/BT keep-alive
# interval configuration value of 20 seconds), not a timing-instrumentation suffix. No genuine
# fc_timer-style trailing duration suffix exists on any verdict line in the current tree.
#
# Usage: bash test_fc_timer_golden_output.sh
#   Env FC_TIMER_GOLDEN_LOG=<path> : real captured pre_build_verification.sh stdout log to use
#                                    as the "without timers" baseline (default: auto-discover
#                                    the most recent
#                                    qa-results/fastcycle/us1/red/T015/prebuild_full_run_*.log,
#                                    the same evidence test_fc_timer_prebuild_red.sh uses).
#   Env FC_TIMER_GOLDEN_LOG_WITH=<path> : real captured pre_build_verification.sh stdout log,
#                                    from a run with fc_timer instrumentation ACTIVE (FC_TIMING
#                                    unset/1), to use as the "with timers" comparison side
#                                    (default: auto-discover the most recent
#                                    qa-results/fastcycle/us1/red/T015/prebuild_with_timers_full_run_*.log
#                                    -- a DELIBERATELY DIFFERENT filename prefix from the
#                                    "without timers" baseline's own `prebuild_full_run_*.log`
#                                    glob above, so a captured "with timers" log is never
#                                    mistaken for -- or silently picked up as -- the "without
#                                    timers" baseline by the OTHER auto-discovery above, and vice
#                                    versa; absent -> the real comparison below is an honest SKIP,
#                                    never a fabricated PASS).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../../.." && pwd)"
EVIDENCE_DEFAULT_DIR="$ROOT/qa-results/fastcycle/us1/red/T015"

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

FAIL=0; N=0; SKIPPED=0
chk() { N=$((N + 1)); if [ "$2" = "1" ]; then echo "PASS[$N]: $1"; else echo "FAIL[$N]: $1"; FAIL=$((FAIL + 1)); fi; }
skip() { N=$((N + 1)); SKIPPED=$((SKIPPED + 1)); echo "SKIP[$N]: $1"; }

# ---- locate the real "without timers" baseline log ----
BASELINE_LOG="${FC_TIMER_GOLDEN_LOG:-}"
if [ -z "$BASELINE_LOG" ] || [ ! -f "$BASELINE_LOG" ]; then
  BASELINE_LOG=""
  if [ -d "$EVIDENCE_DEFAULT_DIR" ]; then
    BASELINE_LOG="$(find "$EVIDENCE_DEFAULT_DIR" -maxdepth 1 -name 'prebuild_full_run_*.log' 2>/dev/null | sort | tail -n1)"
  fi
fi
if [ -z "$BASELINE_LOG" ] || [ ! -f "$BASELINE_LOG" ]; then
  echo "FATAL: no real 'without timers' evidence log found (set FC_TIMER_GOLDEN_LOG=<path>," \
       "or run test_fc_timer_prebuild_red.sh first so its evidence log is auto-discoverable)."
  exit 2
fi
echo "INFO: using baseline (without-timers) log: $BASELINE_LOG"

# ---- locate the real "with timers" comparison log (R3-I6) ----
# Deliberately a DIFFERENT filename prefix ('prebuild_with_timers_full_run_*.log') from the
# baseline's own 'prebuild_full_run_*.log' glob above, so neither auto-discovery step can ever
# pick up the other side's log.
WITH_TIMERS_LOG="${FC_TIMER_GOLDEN_LOG_WITH:-}"
if [ -z "$WITH_TIMERS_LOG" ] || [ ! -f "$WITH_TIMERS_LOG" ]; then
  WITH_TIMERS_LOG=""
  if [ -d "$EVIDENCE_DEFAULT_DIR" ]; then
    WITH_TIMERS_LOG="$(find "$EVIDENCE_DEFAULT_DIR" -maxdepth 1 -name 'prebuild_with_timers_full_run_*.log' 2>/dev/null | sort | tail -n1)"
  fi
fi
if [ -n "$WITH_TIMERS_LOG" ] && [ -f "$WITH_TIMERS_LOG" ]; then
  echo "INFO: using with-timers comparison log: $WITH_TIMERS_LOG"
else
  echo "INFO: no real 'with timers' evidence log found yet (set FC_TIMER_GOLDEN_LOG_WITH=<path>," \
       "or capture one with FC_TIMING=1 bash device/rockchip/rk3588/tests/pre_build_verification.sh" \
       "> $EVIDENCE_DEFAULT_DIR/prebuild_with_timers_full_run_\$(date -u +%Y%m%dT%H%M%SZ).log" \
       "2>&1) -- the real comparison below stays an honest SKIP until then."
  WITH_TIMERS_LOG=""
fi

# verdict-line shape used throughout pre_build_verification.sh: PASS/FAIL/WARN lines carry a
# UTF-8 checkmark/cross or the literal 'WARN'/'ERROR'. Banner/section lines never carry these.
VERDICT_RE='(✓|✗|WARN:|ERROR:)'

# extract_verdicts <log> <out> : one stable verdict line per matched input line, ANSI-stripped,
# leading/trailing whitespace trimmed, any trailing BRACKET/PAREN-WRAPPED "[N.NNs]"/"(N.NNs)"/
# "[N ms]" TIMING SUFFIX removed (none exist in the real baseline today per the FINDING above;
# this is the stripping step T029's real comparison will need once fc_timer adds one). The
# wrapping requirement is deliberate, not incidental -- see the golden-good fixture comment
# below for the real false-positive ("... Keep-alive period 20s", a bare unbracketed suffix
# that is genuine check content, not a timing suffix) that a bare-suffix strip would corrupt.
extract_verdicts() {
  sed -E 's/\x1b\[[0-9;]*m//g' "$1" \
    | grep -E "$VERDICT_RE" \
    | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' \
    | sed -E 's/[[:space:]]*[[(][0-9]+(\.[0-9]+)?[[:space:]]*(s|ms|sec)[])][[:space:]]*$//' \
    > "$2"
}

# ============================================================================
# (a) + (b): real baseline capture + determinism of the extraction mechanism
# ============================================================================
extract_verdicts "$BASELINE_LOG" "$TMP/baseline_1.txt"
extract_verdicts "$BASELINE_LOG" "$TMP/baseline_2.txt"
BASELINE_LINES="$(wc -l < "$TMP/baseline_1.txt" | tr -d ' ')"
chk "real 'without timers' verdict set captured from $BASELINE_LOG ($BASELINE_LINES verdict lines)" "$([ "$BASELINE_LINES" -gt 0 ] && echo 1 || echo 0)"

HASH_1="$(sha256sum "$TMP/baseline_1.txt" | awk '{print $1}')"
HASH_2="$(sha256sum "$TMP/baseline_2.txt" | awk '{print $1}')"
chk "verdict-set extraction is deterministic (two extractions of the same real log hash identically: $HASH_1)" "$([ "$HASH_1" = "$HASH_2" ] && [ -n "$HASH_1" ] && echo 1 || echo 0)"

# Persist the baseline for future re-use / comparison once T029 lands (this file is evidence,
# not a fixture the pass/fail logic below depends on).
cp "$TMP/baseline_1.txt" "$TMP/without_timers_baseline.txt"
chk "baseline verdict set is non-empty and free of ANSI escape sequences" "$(grep -qc $'\x1b' "$TMP/without_timers_baseline.txt" 2>/dev/null && echo 0 || echo 1)"

# ============================================================================
# (c) self-validation triple for the comparison+stripping logic T029's real
# with-timers-vs-without-timers diff will reuse (C-005 spirit; this file is not itself one of
# the 12 C-002 contract tools, so the triple is inlined rather than driven through
# tests/lib/triple_harness.sh -- there is no packaged CLI here to hand it).
# ============================================================================
cat > "$TMP/sample_without_timers.txt" <<'EOF'
  ✓ CM-EXAMPLE-ONE: first gate passes cleanly
  ✗ CM-EXAMPLE-TWO: second gate fails for a real reason
  ✓ CM-EXAMPLE-THREE: third gate passes cleanly too
WARN: CM-EXAMPLE-FOUR: fourth gate warns about something
EOF

# golden-good: SAME verdicts, EACH line carries a synthetic trailing timing suffix a real
# fc_timer wiring would append. MUST compare equal to the baseline after stripping.
#
# Every suffix is bracket/paren-WRAPPED -- deliberately, not merely a style choice: the real
# baseline log contains at least one verdict line whose legitimate, non-timing content ends in
# a BARE "<number><unit>" ("... Keep-alive period 20s", from a WiFi/BT keep-alive interval
# CONFIGURATION VALUE, unrelated to how long the check took -- see the FINDING note above). A
# stripping rule permissive enough to eat a bare trailing "<number><unit>" would silently
# corrupt that real content; requiring an enclosing [ ] or ( ) is the evidenced, conservative
# fix, and is a reasonable constraint for T029's implementer to honour once fc_timer.sh exists.
cat > "$TMP/sample_with_timers_good.txt" <<'EOF'
  ✓ CM-EXAMPLE-ONE: first gate passes cleanly [0.03s]
  ✗ CM-EXAMPLE-TWO: second gate fails for a real reason (1.204s)
  ✓ CM-EXAMPLE-THREE: third gate passes cleanly too [12ms]
WARN: CM-EXAMPLE-FOUR: fourth gate warns about something [0.9 s]
EOF

# golden-bad: same timing-suffix shape as golden-good, but ONE line's ACTUAL VERDICT differs
# (FAIL where the baseline says PASS). MUST compare UNEQUAL -- the comparator must not be
# fooled into reporting "equal" just because it strips a timing suffix.
cat > "$TMP/sample_with_timers_bad.txt" <<'EOF'
  ✓ CM-EXAMPLE-ONE: first gate passes cleanly [0.03s]
  ✗ CM-EXAMPLE-TWO: second gate fails for a real reason (1.204s)
  ✗ CM-EXAMPLE-THREE: third gate passes cleanly too [12ms]
WARN: CM-EXAMPLE-FOUR: fourth gate warns about something [0.9 s]
EOF

# negative-control: differs by gate identity (not a timing suffix, not a verdict flip) -- a
# comparator that ignores this difference is broken in a different, equally-disqualifying way.
cat > "$TMP/sample_negative_control.txt" <<'EOF'
  ✓ CM-EXAMPLE-ONE: first gate passes cleanly [0.03s]
  ✗ CM-EXAMPLE-TWO: second gate fails for a real reason (1.204s)
  ✓ CM-EXAMPLE-THREE-RENAMED: third gate passes cleanly too [12ms]
WARN: CM-EXAMPLE-FOUR: fourth gate warns about something [0.9 s]
EOF

extract_verdicts "$TMP/sample_without_timers.txt" "$TMP/e_without.txt"
extract_verdicts "$TMP/sample_with_timers_good.txt" "$TMP/e_good.txt"
extract_verdicts "$TMP/sample_with_timers_bad.txt" "$TMP/e_bad.txt"
extract_verdicts "$TMP/sample_negative_control.txt" "$TMP/e_negctrl.txt"

H_WITHOUT="$(sha256sum "$TMP/e_without.txt" | awk '{print $1}')"
H_GOOD="$(sha256sum "$TMP/e_good.txt" | awk '{print $1}')"
H_BAD="$(sha256sum "$TMP/e_bad.txt" | awk '{print $1}')"
H_NEGCTRL="$(sha256sum "$TMP/e_negctrl.txt" | awk '{print $1}')"

chk "golden-good: verdict set identical with vs without a synthetic timing suffix (T-A01 rule)" "$([ "$H_WITHOUT" = "$H_GOOD" ] && echo 1 || echo 0)"
chk "golden-bad: a real verdict flip (PASS->FAIL) is NOT hidden by timing-suffix stripping" "$([ "$H_WITHOUT" != "$H_BAD" ] && echo 1 || echo 0)"
chk "negative-control: a gate-identity change (not a timing suffix) is also detected as different" "$([ "$H_WITHOUT" != "$H_NEGCTRL" ] && echo 1 || echo 0)"

DIFF_OUT="$(diff "$TMP/e_without.txt" "$TMP/e_bad.txt" 2>/dev/null || true)"
chk "on mismatch, a byte-level diff is producible (never a bare hash-mismatch with no detail)" "$([ -n "$DIFF_OUT" ] && echo 1 || echo 0)"

# Regression check tied to the FINDING above: the real baseline's one bare-trailing-"<n><unit>"
# line ("... Keep-alive period 20s", genuine check content, not a timing suffix) MUST survive
# extraction byte-for-byte -- the bracket/paren-wrapping requirement in extract_verdicts()
# exists precisely so this real content is never mistaken for a strippable timing suffix. The
# line below is copied byte-for-byte from the real evidence log (line 1302 of
# qa-results/fastcycle/us1/red/T015/prebuild_full_run_20260928T050150Z.log), not reconstructed
# from memory.
BT3_LINE='  BT3: bcmdhd keep_alive_period=20000 (20s)...   ✓ Keep-alive period 20s'
printf '%s\n' "$BT3_LINE" > "$TMP/bt3_input.txt"
extract_verdicts "$TMP/bt3_input.txt" "$TMP/bt3_output.txt"
BT3_OUTPUT="$(cat "$TMP/bt3_output.txt")"
BT3_EXPECTED="$(printf '%s' "$BT3_LINE" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
chk "real bare-suffix content ('... Keep-alive period 20s') is NOT corrupted by suffix-stripping" "$([ "$BT3_OUTPUT" = "$BT3_EXPECTED" ] && echo 1 || echo 0)"

# ============================================================================
# (d) R3-I6: the REAL with-timers-vs-without-timers verdict-set comparison, the actual FR-002
# assertion this whole file exists to perform, run the moment a real "with timers" log is on
# disk. An honest SKIP (never a fabricated PASS) when one is not yet captured -- T028/T029 being
# `[x]` in tasks.md means the COMPARISON IS NOW POSSIBLE, not that a "with timers" log always
# exists on every invocation of this file (capturing one is a separate, ~15-20 minute real
# pre_build_verification.sh run -- see the FC_TIMER_GOLDEN_LOG_WITH usage note above).
# ============================================================================
if [ -n "$WITH_TIMERS_LOG" ]; then
  extract_verdicts "$WITH_TIMERS_LOG" "$TMP/with_timers.txt"
  WITH_LINES="$(wc -l < "$TMP/with_timers.txt" | tr -d ' ')"
  chk "real 'with timers' verdict set captured from $WITH_TIMERS_LOG ($WITH_LINES verdict lines)" "$([ "$WITH_LINES" -gt 0 ] && echo 1 || echo 0)"

  HASH_WITHOUT_REAL="$(sha256sum "$TMP/baseline_1.txt" | awk '{print $1}')"
  HASH_WITH_REAL="$(sha256sum "$TMP/with_timers.txt" | awk '{print $1}')"
  REAL_MATCH=0
  [ "$HASH_WITHOUT_REAL" = "$HASH_WITH_REAL" ] && REAL_MATCH=1

  if [ "$REAL_MATCH" = "1" ]; then
    chk "FR-002/T-A01: real with-timers verdict set is IDENTICAL to the real without-timers verdict set, byte-for-byte after stripping timing suffixes ($BASELINE_LOG vs $WITH_TIMERS_LOG)" "1"
  else
    # Two genuinely SEPARATE pre_build_verification.sh invocations (not one process with
    # FC_TIMING toggled inline) can legitimately diverge in verdict-set CONTENT for reasons that
    # have nothing to do with fc_timer instrumentation: the live repo tree can change between
    # the two captures (a concurrent commit landing on a shared checkout, exactly the kind of
    # activity this project's own multi-track model produces routinely -- see CONTINUATION.md).
    # A raw hash mismatch is therefore reported WITH its full line-level diff, never silently
    # swallowed and never silently upgraded to a PASS -- the honest FAIL below states exactly
    # which lines differ so a human/agent can distinguish a genuine fc_timer-caused verdict
    # change (an FR-002 regression) from unrelated inter-capture repo drift.
    DIFF_REAL="$(diff "$TMP/baseline_1.txt" "$TMP/with_timers.txt" 2>/dev/null || true)"
    DIFF_REAL_LINES="$(printf '%s\n' "$DIFF_REAL" | grep -c '^[<>]' || true)"
    chk "FR-002/T-A01: real with-timers verdict set is IDENTICAL to the real without-timers verdict set, byte-for-byte after stripping timing suffixes ($BASELINE_LOG vs $WITH_TIMERS_LOG) -- MISMATCH, $DIFF_REAL_LINES differing line(s), see diff below (may be genuine inter-capture repo drift on this shared multi-track checkout rather than an fc_timer regression -- re-run both captures back-to-back with no intervening commits to isolate)" "0"
    printf '%s\n' "$DIFF_REAL" | head -n 60
  fi
else
  skip "real with-timers-vs-without-timers verdict-set comparison against pre_build_verification.sh (no 'with timers' evidence log captured yet -- set FC_TIMER_GOLDEN_LOG_WITH=<path> or capture one per the usage note above; T028+T029 are landed so this is now a capture gap, not a code gap)"
fi

echo "SUMMARY: $((N - FAIL - SKIPPED)) pass / $FAIL fail / $SKIPPED skip of $N assertions (baseline: $BASELINE_LOG, $BASELINE_LINES verdict lines)"
[ "$FAIL" = 0 ]
