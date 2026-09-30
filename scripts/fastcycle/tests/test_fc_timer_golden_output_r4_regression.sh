#!/bin/bash
# T048 Round 4 (independent Opus-xhigh review of SpecKit-004 "fast-dev-cycles"
# User Story 1's own round-3 remediation trail) finding R4-I4 regression
# guard for test_fc_timer_golden_output.sh's own baseline/with-timers
# PAIRING + NOISE-FLOOR logic.
#
# R4-I4 (verbatim finding, 2026-09-30): "the golden-output test fails BY
# DEFAULT for a reason unrelated to fc_timer -- a real log-pairing bug.
# Running with no arguments currently exits 1 (9/1) because AUTO-DISCOVERY
# sorts candidate log filenames LEXICALLY, so the 'without timers' baseline
# gets stuck on an OLD (2026-09-28) log while the 'with timers' log is
# picked independently with NOTHING actually pairing the two logs as a
# genuine same-window comparison -- they're just two unrelated captures
# from different times, and any diff between them is meaningless noise,
# not a real signal." Fix: "pick the paired logs by TIMESTAMP proximity ...
# and only treat a mismatch between them as meaningful when compared
# against a SAME-WINDOW no-timer/no-timer noise floor."
#
# This file is an ISOLATED unit test of the PAIRING + NOISE-FLOOR logic
# itself (the `_fc_ts_epoch`/`_fc_closest_to_epoch` helpers + the candidate-
# gathering + selection block in test_fc_timer_golden_output.sh), driven
# against purely SYNTHETIC filename fixtures whose embedded timestamps are
# chosen specifically to distinguish "pick the genuinely closest pair" from
# "pick each side's own lexically-latest independently" -- a distinction
# this real repo's OWN currently-available evidence logs happen NOT to
# exercise today (there is only one real 'with timers' capture on disk, so
# the two algorithms coincide on this host's live data; a synthetic fixture
# with >=2 candidates per side is required to prove the fix genuinely
# changed behaviour, not merely that it runs without crashing).
#
# Extraction discipline (§11.4.6/§11.4.115(F)): the pairing block is pulled
# LIVE out of test_fc_timer_golden_output.sh via a content-anchored `awk`
# line range (its own preceding comment through the verdict-line-shape
# comment immediately after the NOISE_LOG block) -- never hand-copied. A
# control needle fails loudly if a future structural edit removes an
# anchor. Fixture files are EMPTY (zero bytes) -- the pairing logic under
# test inspects only FILENAMES (via `_fc_ts_epoch`), never file content, so
# empty fixtures are a faithful, minimal, honest stand-in for a real
# multi-hundred-KB prebuild log in this specific test's scope.
set -u

repo_root() { cd "$(dirname "$0")/../../../.." && pwd; }
ROOT=$(repo_root)
SRC="$ROOT/constitution/scripts/fastcycle/tests/test_fc_timer_golden_output.sh"

fail=0
failx() { fail=1; }

TMP="$(mktemp -d)" || { echo "NOT ok mktemp -d failed"; exit 1; }
trap 'rm -rf "$TMP"' EXIT

# Never let an ambient copy of these leak into scenarios that do not
# intend to set them -- each scenario below exports exactly what it needs.
unset FC_TIMER_GOLDEN_LOG FC_TIMER_GOLDEN_LOG_WITH FC_TIMER_GOLDEN_LOG_NOISE 2>/dev/null || true

echo "=== control needle: source file resolves ==="
if [ -f "$SRC" ]; then
  echo "ok control needle: $SRC resolves"
else
  echo "NOT ok control needle FAILED: $SRC not found"
  failx
fi

PAIR_START='# _fc_ts_epoch PATH -- prints the epoch-seconds value of the LAST'
PAIR_END='# verdict-line shape used throughout pre_build_verification.sh: PASS/FAIL/WARN lines carry a'
PAYLOAD="$TMP/pairing_payload.sh"

echo
echo "=== control needle: pairing-block extraction anchors found + unique ==="
START_HITS="$(grep -cxF "$PAIR_START" "$SRC" 2>/dev/null || true)"; : "${START_HITS:=0}"
END_HITS="$(grep -cxF "$PAIR_END" "$SRC" 2>/dev/null || true)"; : "${END_HITS:=0}"
if [ "$START_HITS" != 1 ] || [ "$END_HITS" != 1 ]; then
  echo "NOT ok control needle FAILED: extraction anchors not exactly-once (start=$START_HITS,"
  echo "     end=$END_HITS) -- $SRC's structure changed; this file's anchors need updating"
  failx
  PAYLOAD=""
else
  awk -v s="$PAIR_START" -v e="$PAIR_END" '$0==s,$0==e' "$SRC" > "$PAYLOAD" 2>/dev/null
  if [ -s "$PAYLOAD" ] \
     && grep -qF '_fc_ts_epoch() {' "$PAYLOAD" \
     && grep -qF '_fc_closest_to_epoch() {' "$PAYLOAD" \
     && grep -qF 'PAIRING_NOTE=' "$PAYLOAD" \
     && grep -qF 'NOISE_LOG=' "$PAYLOAD"; then
    echo "ok control needle: pairing block extracted ($(wc -l < "$PAYLOAD" | tr -d ' ') lines),"
    echo "   contains both helper functions + the pairing/noise-log selection logic"
  else
    echo "NOT ok control needle FAILED: extraction is incomplete -- $SRC's structure changed;"
    echo "     this file's anchors/fragment-checks need updating"
    failx
    PAYLOAD=""
  fi
fi

if [ -z "${PAYLOAD:-}" ]; then
  echo
  echo "=== R4-I4 REGRESSION GUARD: SKIPPED -- extraction control needle failed above ==="
  exit 1
fi

run_pairing() {
  # $1 = scratch EVIDENCE_DEFAULT_DIR ; remaining env overrides already
  # exported by the caller (FC_TIMER_GOLDEN_LOG / _WITH / _NOISE).
  local evdir="$1" out="$2"
  local driver="$TMP/driver_$$_$RANDOM.sh"
  {
    echo 'set -u'
    printf 'EVIDENCE_DEFAULT_DIR=%q\n' "$evdir"
    cat "$PAYLOAD"
    echo 'printf "BASELINE_LOG=%s\n" "$BASELINE_LOG"'
    echo 'printf "WITH_TIMERS_LOG=%s\n" "$WITH_TIMERS_LOG"'
    echo 'printf "NOISE_LOG=%s\n" "$NOISE_LOG"'
    echo 'printf "PAIRING_NOTE=%s\n" "$PAIRING_NOTE"'
  } > "$driver"
  bash "$driver" > "$out" 2>"${out}.err"
}

# =============================================================================
# (1) The CORE R4-I4 bug: two candidates per side, chosen so the OLD
#     "independent per-side lexically-latest" algorithm picks a WRONG,
#     far-apart pair, while the NEW closest-pair algorithm picks the
#     correct, genuinely-close pair. Filenames embed real ISO8601
#     timestamps the pairing logic parses; content is irrelevant (empty).
# =============================================================================
EVDIR1="$TMP/scn1"
mkdir -p "$EVDIR1"
# Baseline candidates: an OLD one (lexically-latest among baselines, since
# its filename's extra "z_late" text sorts after a bare timestamp) and a
# NEW one captured close to the with-timers run.
touch "$EVDIR1/prebuild_full_run_20260101T000000Z.log"                      # OLD, far from everything
touch "$EVDIR1/prebuild_full_run_z_late_20260105T000100Z.log"               # lexically LATEST, but still far from the with-timers log below
# With-timers candidates: one close to the OLD baseline, one far away.
touch "$EVDIR1/prebuild_with_timers_full_run_20260101T000200Z.log"          # 120s after the OLD baseline -- the CORRECT pair
touch "$EVDIR1/prebuild_with_timers_full_run_20260201T000000Z.log"          # lexically LATEST, but ~27 days from anything

run_pairing "$EVDIR1" "$TMP/out1.txt"
GOT_B1="$(sed -n 's/^BASELINE_LOG=//p' "$TMP/out1.txt")"
GOT_W1="$(sed -n 's/^WITH_TIMERS_LOG=//p' "$TMP/out1.txt")"
WANT_B1="$EVDIR1/prebuild_full_run_20260101T000000Z.log"
WANT_W1="$EVDIR1/prebuild_with_timers_full_run_20260101T000200Z.log"
# What the OLD (pre-R4-I4) "independent lexically-latest per side" logic
# would have picked, computed independently here (never by re-invoking the
# fixed code) as the negative comparison point:
OLD_B1="$(printf '%s\n' "$EVDIR1"/prebuild_full_run_*.log | sort | tail -n1)"
OLD_W1="$(printf '%s\n' "$EVDIR1"/prebuild_with_timers_full_run_*.log | sort | tail -n1)"

echo
echo "=== (1) closest-in-time PAIRING selects the genuinely close pair, not each side's own lexically-latest ==="
if [ "$GOT_B1" = "$WANT_B1" ] && [ "$GOT_W1" = "$WANT_W1" ]; then
  echo "ok (1) real (fixed) pairing selected the CORRECT, close-in-time pair"
  echo "   (baseline=$GOT_B1, with-timers=$GOT_W1)"
else
  echo "NOT ok (1) real (fixed) pairing selected baseline='$GOT_B1' with-timers='$GOT_W1'"
  echo "     (wanted baseline='$WANT_B1' with-timers='$WANT_W1') --"
  echo "     $(cat "$TMP/out1.txt.err" 2>/dev/null)"
  failx
fi
if [ "$OLD_B1" != "$WANT_B1" ] || [ "$OLD_W1" != "$WANT_W1" ]; then
  echo "ok (1) guard-viability: the OLD independent-per-side-lexically-latest algorithm"
  echo "   (computed here independently, never via the fixed code) would have picked a"
  echo "   DIFFERENT, genuinely wrong pair (baseline=$OLD_B1, with-timers=$OLD_W1) --"
  echo "   proving this fixture genuinely distinguishes the fix from its absence, not"
  echo "   merely exercising a code path that happens to produce the same answer either"
  echo "   way (R4-I4's own root cause: the real repo's current live data does not"
  echo "   distinguish the two algorithms, since only one real with-timers log exists"
  echo "   today -- this synthetic fixture is what makes the distinction provable)"
else
  echo "NOT ok (1) guard-viability BLIND: the OLD algorithm would have picked the SAME"
  echo "     pair as the fix -- this fixture does not actually distinguish old-vs-new"
  echo "     behaviour and needs redesigning"
  failx
fi

# =============================================================================
# (2) An explicit FC_TIMER_GOLDEN_LOG pin still auto-selects the CLOSEST
#     with-timers candidate to IT (never independently lexically-latest).
# =============================================================================
EVDIR2="$TMP/scn2"
mkdir -p "$EVDIR2"
touch "$EVDIR2/prebuild_with_timers_full_run_20260101T000200Z.log"   # close to the pin below
touch "$EVDIR2/prebuild_with_timers_full_run_20260201T000000Z.log"   # lexically latest, far away
PIN_BASELINE="$EVDIR2/pinned_baseline_20260101T000000Z.log"
touch "$PIN_BASELINE"

echo
echo "=== (2) an explicit FC_TIMER_GOLDEN_LOG pin auto-selects the closest with-timers candidate to IT ==="
( export FC_TIMER_GOLDEN_LOG="$PIN_BASELINE"
  run_pairing "$EVDIR2" "$TMP/out2.txt" )
GOT_W2="$(sed -n 's/^WITH_TIMERS_LOG=//p' "$TMP/out2.txt")"
WANT_W2="$EVDIR2/prebuild_with_timers_full_run_20260101T000200Z.log"
if [ "$GOT_W2" = "$WANT_W2" ]; then
  echo "ok (2) with FC_TIMER_GOLDEN_LOG pinned, the auto-discovered with-timers log is the"
  echo "   one genuinely closest in time to the pin ($GOT_W2), not the lexically-latest"
  echo "   candidate"
else
  echo "NOT ok (2) with FC_TIMER_GOLDEN_LOG pinned, got with-timers='$GOT_W2' (wanted"
  echo "     '$WANT_W2') -- $(cat "$TMP/out2.txt.err" 2>/dev/null)"
  failx
fi

# =============================================================================
# (3) NOISE-FLOOR auto-discovery: a second baseline candidate close in time
#     to the with-timers log (excluding the one already chosen as
#     BASELINE_LOG) is selected as NOISE_LOG.
# =============================================================================
EVDIR3="$TMP/scn3"
mkdir -p "$EVDIR3"
# with-timers log is at 00:02:00; deltas below are unambiguous (10s / 70s / 8min)
# so the intended BASELINE_LOG (closest) / NOISE_LOG (2nd-closest) / far
# (must-not-be-chosen) roles are never accidentally swapped.
touch "$EVDIR3/prebuild_full_run_20260101T000150Z.log"           # delta 10s  -> chosen as BASELINE_LOG (closest to the with-timers log below)
touch "$EVDIR3/prebuild_full_run_20260101T000050Z.log"           # delta 70s  -> chosen as NOISE_LOG (2nd-closest, same window)
touch "$EVDIR3/prebuild_full_run_20260101T001000Z.log"           # delta 480s -> far away, must NOT be chosen as noise
touch "$EVDIR3/prebuild_with_timers_full_run_20260101T000200Z.log"

run_pairing "$EVDIR3" "$TMP/out3.txt"
GOT_N3="$(sed -n 's/^NOISE_LOG=//p' "$TMP/out3.txt")"
GOT_B3="$(sed -n 's/^BASELINE_LOG=//p' "$TMP/out3.txt")"
WANT_B3="$EVDIR3/prebuild_full_run_20260101T000150Z.log"
WANT_N3="$EVDIR3/prebuild_full_run_20260101T000050Z.log"

echo
echo "=== (3) noise-floor auto-discovery selects a same-window SECOND baseline, excluding the one already chosen as BASELINE_LOG ==="
if [ "$GOT_B3" = "$WANT_B3" ] && [ "$GOT_N3" = "$WANT_N3" ] && [ "$GOT_N3" != "$GOT_B3" ]; then
  echo "ok (3) real (fixed) BASELINE_LOG picked the genuinely closest candidate"
  echo "   ($GOT_B3) and noise-log auto-discovery independently selected the genuinely"
  echo "   same-window SECOND-closest baseline ($GOT_N3), distinct from BASELINE_LOG,"
  echo "   never the far-away third candidate"
else
  echo "NOT ok (3) got BASELINE_LOG='$GOT_B3' NOISE_LOG='$GOT_N3' (wanted"
  echo "     BASELINE_LOG='$WANT_B3' NOISE_LOG='$WANT_N3', distinct from each other) --"
  echo "     $(cat "$TMP/out3.txt.err" 2>/dev/null)"
  failx
fi

# =============================================================================
# (4) honest degradation: candidate filenames with NO parseable timestamp
#     never crash the pairing logic, and are reported via PAIRING_NOTE as a
#     degraded pick rather than silently claimed as a genuine pairing.
# =============================================================================
EVDIR4="$TMP/scn4"
mkdir -p "$EVDIR4"
touch "$EVDIR4/prebuild_full_run_legacy_no_timestamp.log"
touch "$EVDIR4/prebuild_with_timers_full_run_also_legacy.log"

echo
echo "=== (4) unparseable-timestamp candidates degrade honestly (never crash, never silently claim a real pairing) ==="
run_pairing "$EVDIR4" "$TMP/out4.txt"
RC4=$?
GOT_B4="$(sed -n 's/^BASELINE_LOG=//p' "$TMP/out4.txt")"
GOT_NOTE4="$(sed -n 's/^PAIRING_NOTE=//p' "$TMP/out4.txt")"
if [ "$RC4" = 0 ] && [ -n "$GOT_B4" ] && printf '%s' "$GOT_NOTE4" | grep -qi "degraded\|unparseable"; then
  echo "ok (4) with no parseable timestamps anywhere, the pairing logic did NOT crash,"
  echo "   still picked a usable baseline ($GOT_B4), and honestly reported the"
  echo "   degradation in PAIRING_NOTE ('$GOT_NOTE4')"
else
  echo "NOT ok (4) rc=$RC4 baseline='$GOT_B4' note='$GOT_NOTE4' -- expected a clean exit,"
  echo "     a non-empty baseline pick, and an honest degradation note --"
  echo "     $(cat "$TMP/out4.txt.err" 2>/dev/null)"
  failx
fi

echo
if [ "$fail" = 0 ]; then
  echo "=== R4-I4 REGRESSION GUARD: ALL CHECKS PASS -- the real (fixed) pairing logic"
  echo "    genuinely selects the closest-in-time (baseline, with-timers) pair rather than"
  echo "    each side's own independent lexically-latest pick (proven to differ from the"
  echo "    old algorithm on a fixture the real repo's own live data does not currently"
  echo "    exercise), an explicit single-side pin still auto-pairs correctly, noise-floor"
  echo "    auto-discovery picks a genuinely same-window second baseline, and unparseable"
  echo "    timestamps degrade honestly without crashing. ==="
else
  echo "=== R4-I4 REGRESSION GUARD: FAILURES ABOVE -- see NOT ok lines. ==="
fi

exit "$fail"
