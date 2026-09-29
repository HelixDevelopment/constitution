#!/bin/bash
# T015 golden-output test: fc_timer wiring must not change any pre_build_verification.sh verdict.
# (spec 004-fast-dev-cycles; plan.md "Rule for every A-task" + T-A01; tasks.md T015)
#
# Purpose: pin the "instrumentation must not change any verdict" rule plan.md states for every
#          A-task: "Each A-task that touches a gate or the commit path ships a golden-output
#          test: the verdict set (or commit result) with the instrumentation equals the verdict
#          set without it, byte for byte after stripping timing columns."
#
# Honest state of this test TODAY (T028/T029 not landed -- see test_fc_timer_prebuild_red.sh's
# header for the full independent-verification trail this file shares): there is NO "with
# timers" run of pre_build_verification.sh to compare against a "without timers" run, because
# fc_timer.sh does not exist and pre_build_verification.sh is not wired to it. A true
# before/after comparison against the real script is therefore IMPOSSIBLE today, not merely
# unperformed -- this test does not pretend otherwise. What CAN be, and is, verified for real
# today:
#   (a) the REAL "without timers" verdict set, captured from an actual pre_build_verification.sh
#       run, is checked for any timing-looking noise that a stripping step would need to remove
#       (Constitution S11.4.6 -- "check", never assume; documented finding: NONE found -- see
#       FINDING note below);
#   (b) the verdict-set EXTRACTION mechanism this test (and the eventual real golden-output
#       comparison) depends on is deterministic: extracting twice from the SAME real captured
#       log produces byte-identical output (C-003 determinism spirit);
#   (c) the COMPARISON+STRIPPING logic that T029's real "with timers" vs "without timers" diff
#       will use is self-validated on synthetic fixtures mimicking the real line shape (a
#       golden-good pair that differs ONLY by a synthetic trailing timing suffix -- MUST compare
#       equal after stripping; a golden-bad pair whose ACTUAL verdict differs, not just its
#       timing suffix -- MUST compare unequal; a negative-control pair that differs in gate id
#       only -- MUST also compare unequal, so the comparator is proven to discriminate, not to
#       blindly report "equal" regardless of input).
# The genuine real-vs-real "with timers" comparison itself is an explicit, honest SKIP below,
# not a fabricated PASS -- it becomes possible, and MUST be exercised, the moment T028+T029 land.
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
# Honest boundary: the actual with-timers-vs-without-timers comparison against the real
# pre_build_verification.sh cannot be performed until T028 (fc_timer.sh) and T029 (its wiring)
# land -- there is no "with timers" run to capture. This is recorded as an explicit SKIP, never
# a fabricated PASS (S11.4.6 / S11.4.201).
# ============================================================================
skip "real with-timers-vs-without-timers verdict-set comparison against pre_build_verification.sh (requires T028 fc_timer.sh + T029 wiring, neither landed yet)"

echo "SUMMARY: $((N - FAIL - SKIPPED)) pass / $FAIL fail / $SKIPPED skip of $N assertions (baseline: $BASELINE_LOG, $BASELINE_LINES verdict lines)"
[ "$FAIL" = 0 ]
