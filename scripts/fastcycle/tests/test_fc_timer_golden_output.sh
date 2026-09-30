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
#                                    as the "without timers" baseline (default: auto-discover, see
#                                    PAIRING below).
#   Env FC_TIMER_GOLDEN_LOG_WITH=<path> : real captured pre_build_verification.sh stdout log,
#                                    from a run with fc_timer instrumentation ACTIVE (FC_TIMING
#                                    unset/1), to use as the "with timers" comparison side
#                                    (default: auto-discover, see PAIRING below; -- a
#                                    DELIBERATELY DIFFERENT filename prefix
#                                    ('prebuild_with_timers_full_run_*.log') from the "without
#                                    timers" baseline's own `prebuild_full_run_*.log` glob, so a
#                                    captured "with timers" log is never mistaken for -- or
#                                    silently picked up as -- the "without timers" baseline by
#                                    the OTHER auto-discovery, and vice versa; absent -> the real
#                                    comparison below is an honest SKIP, never a fabricated PASS).
#   Env FC_TIMER_GOLDEN_LOG_NOISE=<path> : a SECOND real "without timers" capture log (see NOISE
#                                    FLOOR below), used to distinguish a genuine fc_timer-caused
#                                    mismatch from pre-existing same-window repo/host-load drift.
#
# PAIRING (T048 round-4 review finding R4-I4, 2026-09-30): "Running with no arguments currently
#   exits 1 because AUTO-DISCOVERY sorts candidate log filenames LEXICALLY, so the 'without
#   timers' baseline gets stuck on an OLD log while the 'with timers' log is picked independently
#   with NOTHING actually pairing the two logs as a genuine same-window comparison -- they're
#   just two unrelated captures from different times, and any diff between them is meaningless
#   noise, not a real signal." Independently reproduced before fixing: on this real tree, the
#   old "lexically-latest, each side independent" auto-discovery picked
#   prebuild_full_run_t029_t029_full_20260928T124322Z.log (2026-09-28 12:43) as baseline against
#   prebuild_with_timers_full_run_20260930T152954Z.log (2026-09-30 15:29) -- a ~2.3-DAY gap,
#   across which this shared multi-track checkout had dozens of intervening commits.
#   Fixed: when BOTH sides are auto-discovered (the common no-args case), every candidate on each
#   side is matched against every candidate on the other side by the ISO8601 timestamp each
#   filename already embeds (`YYYYMMDDTHHMMSSZ`), and the PAIR with the SMALLEST time delta is
#   selected -- a genuine closest-in-time, same-window match, never an independent per-side
#   "latest". When only ONE side is auto-discovered (the other pinned via its own env var), the
#   auto side picks the candidate closest in time to the pinned side's own embedded timestamp.
#   When NEITHER side's candidate filenames carry a parseable timestamp (a legacy/foreign log),
#   this degrades to the OLD per-side lexically-latest behaviour, never a crash -- logged
#   honestly via the PAIRING_NOTE line below, so a degraded pairing is visible, not silent.
#
# NOISE FLOOR (same finding, second half): "only treat a mismatch between them as meaningful when
#   compared against a SAME-WINDOW no-timer/no-timer noise floor (matching exactly the
#   methodology ... 3 concurrent runs, 2 timers-off + 1 timers-on, establishing the noise floor
#   via the 2 timers-off runs' own comparison before judging the timers-on diff as meaningful or
#   not)." When the real with-vs-without comparison below MISMATCHES, a SECOND "without timers"
#   capture close in time to the chosen with-timers log (auto-discovered the SAME way, or pinned
#   via FC_TIMER_GOLDEN_LOG_NOISE) is diffed against the SAME baseline, and each differing line in
#   the main mismatch is cross-referenced against this noise-floor diff: a line that ALSO differs
#   between two genuinely timer-FREE captures is reported as pre-existing same-window noise (not
#   attributable to fc_timer); a line that differs ONLY in the with-vs-without comparison is
#   reported as a genuine candidate fc_timer-attributable difference needing investigation. This
#   is DIAGNOSTIC classification only -- it NEVER changes the strict byte-for-byte FR-002/T-A01
#   pass/fail verdict itself (a real mismatch still FAILs regardless of noise-floor
#   classification; T-A01's own rule is unconditional identity, not "identical modulo known
#   noise") -- it exists solely so a human/agent reading a FAIL is not left guessing whether it
#   is a real fc_timer regression or inter-capture drift this project's own multi-track model
#   already produces routinely. Absent a same-window second baseline capture, this stays an
#   honest "no noise floor available" note, never a fabricated classification.
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

# _fc_ts_epoch PATH -- prints the epoch-seconds value of the LAST
# YYYYMMDDTHHMMSSZ substring in PATH's own basename (every candidate log
# this file globs for embeds exactly one), or an empty string if none is
# found or `date` cannot parse it (a foreign/legacy filename) -- never a
# guessed/default timestamp (S11.4.6).
_fc_ts_epoch() {
  local fname ts
  fname="$(basename -- "$1")"
  ts="$(printf '%s' "$fname" | grep -oE '[0-9]{8}T[0-9]{6}Z' | tail -n1)"
  [ -n "$ts" ] || { printf ''; return 0; }
  date -u -d "${ts:0:4}-${ts:4:2}-${ts:6:2}T${ts:9:2}:${ts:11:2}:${ts:13:2}Z" +%s 2>/dev/null
}

# _fc_closest_to_epoch TARGET_EPOCH CANDIDATE... -- prints the candidate
# whose OWN embedded timestamp is closest (smallest absolute delta) to
# TARGET_EPOCH; candidates with no parseable timestamp are skipped. Empty
# output if no candidate has a parseable timestamp.
_fc_closest_to_epoch() {
  local target="$1"; shift
  local best="" best_delta="" f ts delta
  for f in "$@"; do
    ts="$(_fc_ts_epoch "$f")"
    [ -n "$ts" ] || continue
    if [ "$ts" -gt "$target" ]; then delta=$((ts - target)); else delta=$((target - ts)); fi
    if [ -z "$best_delta" ] || [ "$delta" -lt "$best_delta" ]; then
      best="$f"; best_delta="$delta"
    fi
  done
  printf '%s' "$best"
}

# ---- gather every candidate on each side (used by both explicit-pinned and full-auto pairing) ----
BASELINE_CANDIDATES=()
WITH_CANDIDATES=()
if [ -d "$EVIDENCE_DEFAULT_DIR" ]; then
  while IFS= read -r -d ''; do BASELINE_CANDIDATES+=("$REPLY"); done < <(find "$EVIDENCE_DEFAULT_DIR" -maxdepth 1 -name 'prebuild_full_run_*.log' -print0 2>/dev/null | sort -z)
  while IFS= read -r -d ''; do WITH_CANDIDATES+=("$REPLY"); done < <(find "$EVIDENCE_DEFAULT_DIR" -maxdepth 1 -name 'prebuild_with_timers_full_run_*.log' -print0 2>/dev/null | sort -z)
fi

BASELINE_LOG="${FC_TIMER_GOLDEN_LOG:-}"
BASELINE_EXPLICIT=0
[ -n "$BASELINE_LOG" ] && [ -f "$BASELINE_LOG" ] && BASELINE_EXPLICIT=1
WITH_TIMERS_LOG="${FC_TIMER_GOLDEN_LOG_WITH:-}"
WITH_EXPLICIT=0
[ -n "$WITH_TIMERS_LOG" ] && [ -f "$WITH_TIMERS_LOG" ] && WITH_EXPLICIT=1
[ "$BASELINE_EXPLICIT" = 1 ] || BASELINE_LOG=""
[ "$WITH_EXPLICIT" = 1 ] || WITH_TIMERS_LOG=""

PAIRING_NOTE=""
if [ "$BASELINE_EXPLICIT" = 1 ] && [ "$WITH_EXPLICIT" = 1 ]; then
  PAIRING_NOTE="both logs explicitly provided by the caller (FC_TIMER_GOLDEN_LOG + FC_TIMER_GOLDEN_LOG_WITH) -- no auto-pairing performed"
elif [ "$BASELINE_EXPLICIT" = 1 ] && [ ${#WITH_CANDIDATES[@]} -gt 0 ]; then
  BTS="$(_fc_ts_epoch "$BASELINE_LOG")"
  if [ -n "$BTS" ]; then
    WITH_TIMERS_LOG="$(_fc_closest_to_epoch "$BTS" "${WITH_CANDIDATES[@]}")"
    [ -n "$WITH_TIMERS_LOG" ] && PAIRING_NOTE="with-timers log auto-selected as the candidate closest in time to the explicit FC_TIMER_GOLDEN_LOG baseline"
  fi
  if [ -z "$WITH_TIMERS_LOG" ]; then
    WITH_TIMERS_LOG="$(printf '%s\n' "${WITH_CANDIDATES[@]}" | sort | tail -n1)"
    PAIRING_NOTE="baseline's own timestamp unparseable -- degraded to lexically-latest with-timers pick"
  fi
elif [ "$WITH_EXPLICIT" = 1 ] && [ ${#BASELINE_CANDIDATES[@]} -gt 0 ]; then
  WTS="$(_fc_ts_epoch "$WITH_TIMERS_LOG")"
  if [ -n "$WTS" ]; then
    BASELINE_LOG="$(_fc_closest_to_epoch "$WTS" "${BASELINE_CANDIDATES[@]}")"
    [ -n "$BASELINE_LOG" ] && PAIRING_NOTE="baseline log auto-selected as the candidate closest in time to the explicit FC_TIMER_GOLDEN_LOG_WITH log"
  fi
  if [ -z "$BASELINE_LOG" ]; then
    BASELINE_LOG="$(printf '%s\n' "${BASELINE_CANDIDATES[@]}" | sort | tail -n1)"
    PAIRING_NOTE="with-timers log's own timestamp unparseable -- degraded to lexically-latest baseline pick"
  fi
elif [ ${#BASELINE_CANDIDATES[@]} -gt 0 ] && [ ${#WITH_CANDIDATES[@]} -gt 0 ]; then
  # R4-I4 core fix: the common no-args case. Find the (baseline, with-timers)
  # PAIR across the full cross-product minimizing the timestamp delta --
  # never two independent lexically-latest picks.
  PAIR_B=""; PAIR_W=""; PAIR_DELTA=""
  for _fc_b in "${BASELINE_CANDIDATES[@]}"; do
    _fc_bts="$(_fc_ts_epoch "$_fc_b")"
    [ -n "$_fc_bts" ] || continue
    for _fc_w in "${WITH_CANDIDATES[@]}"; do
      _fc_wts="$(_fc_ts_epoch "$_fc_w")"
      [ -n "$_fc_wts" ] || continue
      if [ "$_fc_bts" -gt "$_fc_wts" ]; then _fc_d=$((_fc_bts - _fc_wts)); else _fc_d=$((_fc_wts - _fc_bts)); fi
      if [ -z "$PAIR_DELTA" ] || [ "$_fc_d" -lt "$PAIR_DELTA" ]; then
        PAIR_B="$_fc_b"; PAIR_W="$_fc_w"; PAIR_DELTA="$_fc_d"
      fi
    done
  done
  if [ -n "$PAIR_B" ] && [ -n "$PAIR_W" ]; then
    BASELINE_LOG="$PAIR_B"; WITH_TIMERS_LOG="$PAIR_W"
    PAIRING_NOTE="closest-in-time pair selected across all candidates, ${PAIR_DELTA}s apart (was: independent per-side lexically-latest, which could pick captures days apart -- see R4-I4 header note)"
  else
    BASELINE_LOG="$(printf '%s\n' "${BASELINE_CANDIDATES[@]}" | sort | tail -n1)"
    WITH_TIMERS_LOG="$(printf '%s\n' "${WITH_CANDIDATES[@]}" | sort | tail -n1)"
    PAIRING_NOTE="no candidate filename on either side carried a parseable timestamp -- degraded to the OLD independent per-side lexically-latest behaviour"
  fi
elif [ ${#BASELINE_CANDIDATES[@]} -gt 0 ]; then
  BASELINE_LOG="$(printf '%s\n' "${BASELINE_CANDIDATES[@]}" | sort | tail -n1)"
fi

if [ -z "$BASELINE_LOG" ] || [ ! -f "$BASELINE_LOG" ]; then
  echo "FATAL: no real 'without timers' evidence log found (set FC_TIMER_GOLDEN_LOG=<path>," \
       "or run test_fc_timer_prebuild_red.sh first so its evidence log is auto-discoverable)."
  exit 2
fi
echo "INFO: using baseline (without-timers) log: $BASELINE_LOG"
if [ -n "$WITH_TIMERS_LOG" ] && [ -f "$WITH_TIMERS_LOG" ]; then
  echo "INFO: using with-timers comparison log: $WITH_TIMERS_LOG"
  [ -n "$PAIRING_NOTE" ] && echo "INFO: pairing -- $PAIRING_NOTE"
else
  echo "INFO: no real 'with timers' evidence log found yet (set FC_TIMER_GOLDEN_LOG_WITH=<path>," \
       "or capture one with FC_TIMING=1 bash device/rockchip/rk3588/tests/pre_build_verification.sh" \
       "> $EVIDENCE_DEFAULT_DIR/prebuild_with_timers_full_run_\$(date -u +%Y%m%dT%H%M%SZ).log" \
       "2>&1) -- the real comparison below stays an honest SKIP until then."
  WITH_TIMERS_LOG=""
fi

# ---- locate a same-window SECOND "without timers" capture for the noise floor ----
NOISE_LOG="${FC_TIMER_GOLDEN_LOG_NOISE:-}"
NOISE_NOTE=""
if [ -z "$NOISE_LOG" ] || [ ! -f "$NOISE_LOG" ]; then
  NOISE_LOG=""
  if [ -n "$WITH_TIMERS_LOG" ] && [ ${#BASELINE_CANDIDATES[@]} -ge 2 ]; then
    _fc_wts_for_noise="$(_fc_ts_epoch "$WITH_TIMERS_LOG")"
    if [ -n "$_fc_wts_for_noise" ]; then
      OTHER_BASELINE_CANDS=()
      for _fc_b in "${BASELINE_CANDIDATES[@]}"; do
        [ "$_fc_b" = "$BASELINE_LOG" ] && continue
        OTHER_BASELINE_CANDS+=("$_fc_b")
      done
      if [ ${#OTHER_BASELINE_CANDS[@]} -gt 0 ]; then
        NOISE_LOG="$(_fc_closest_to_epoch "$_fc_wts_for_noise" "${OTHER_BASELINE_CANDS[@]}")"
      fi
    fi
  fi
fi
if [ -n "$NOISE_LOG" ] && [ -f "$NOISE_LOG" ]; then
  echo "INFO: using noise-floor (second without-timers) log: $NOISE_LOG"
  NOISE_NOTE="established from $NOISE_LOG"
else
  NOISE_LOG=""
  NOISE_NOTE="no same-window second 'without timers' capture available -- set FC_TIMER_GOLDEN_LOG_NOISE=<path> to establish one; a mismatch below (if any) is reported without noise-floor classification"
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

    # ------------------------------------------------------------------
    # R4-I4 NOISE-FLOOR CLASSIFICATION (diagnostic only -- see the header
    # NOISE FLOOR note; never changes the strict chk() verdict above).
    # ------------------------------------------------------------------
    if [ -n "$NOISE_LOG" ]; then
      extract_verdicts "$NOISE_LOG" "$TMP/noise.txt"
      DIFF_NOISE="$(diff "$TMP/baseline_1.txt" "$TMP/noise.txt" 2>/dev/null || true)"
      # Compare the CHANGED-BASELINE-CONTENT ('<'-prefixed) lines each diff
      # removed -- both diffs share the SAME "before" side ($TMP/baseline_1.txt),
      # so a baseline line that differs in BOTH comparisons is unstable
      # independent of fc_timer (confirmed noise); a baseline line that
      # differs ONLY against the with-timers side is a genuine candidate.
      printf '%s\n' "$DIFF_REAL" | grep '^< ' | sed 's/^< //' > "$TMP/real_removed.txt"
      printf '%s\n' "$DIFF_NOISE" | grep '^< ' | sed 's/^< //' > "$TMP/noise_removed.txt"
      NOISE_EXPLAINED=0
      GENUINE_CANDIDATE=0
      while IFS= read -r _fc_line; do
        [ -n "$_fc_line" ] || continue
        if grep -qxF -- "$_fc_line" "$TMP/noise_removed.txt" 2>/dev/null; then
          NOISE_EXPLAINED=$((NOISE_EXPLAINED + 1))
        else
          GENUINE_CANDIDATE=$((GENUINE_CANDIDATE + 1))
        fi
      done < "$TMP/real_removed.txt"
      echo "INFO: noise-floor classification ($NOISE_NOTE, noise floor itself has $(printf '%s\n' "$DIFF_NOISE" | grep -c '^[<>]' || true) differing line(s) between two timer-free captures): of $(wc -l < "$TMP/real_removed.txt" | tr -d ' ') changed baseline verdict line(s) in the with-vs-without mismatch above, $NOISE_EXPLAINED also differ in the SAME-WINDOW no-timer/no-timer noise floor (pre-existing drift, NOT attributable to fc_timer) and $GENUINE_CANDIDATE do NOT appear in the noise floor at all (genuine candidate fc_timer-attributable difference -- investigate these specifically, never the whole mismatch)."
    else
      echo "INFO: noise-floor classification unavailable -- $NOISE_NOTE"
    fi
  fi
else
  skip "real with-timers-vs-without-timers verdict-set comparison against pre_build_verification.sh (no 'with timers' evidence log captured yet -- set FC_TIMER_GOLDEN_LOG_WITH=<path> or capture one per the usage note above; T028+T029 are landed so this is now a capture gap, not a code gap)"
fi

echo "SUMMARY: $((N - FAIL - SKIPPED)) pass / $FAIL fail / $SKIPPED skip of $N assertions (baseline: $BASELINE_LOG, $BASELINE_LINES verdict lines)"
[ "$FAIL" = 0 ]
