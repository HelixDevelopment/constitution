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
# file performs the real comparison the moment a validated same-run
# triplet exists on disk (see the Usage section below). What is ALWAYS verified for real,
# independent of whether a triplet exists yet:
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
# The genuine real-vs-real "with timers" comparison runs ONLY on a validated same-run triplet
# (see ROUND-6 ARCHITECTURE below); without one it is an explicit, honest SKIP that names the
# reason -- never a fabricated PASS, and never a comparison of two unrelated captures.
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
#
# ROUND-6 ARCHITECTURE (T048 round-5 review, S11.4.250 heuristic-tower finding). Rounds 1-5
#   auto-discovered HISTORICAL, NON-CONCURRENT captures of a drifting, flaky suite and kept adding
#   heuristics to make them comparable: suffix stripping, with-vs-without selection, closest-
#   timestamp pairing (R4-I4), a hardcoded "SAME-WINDOW" noise-floor label, then window labels
#   (R5). Each layer compensated for the same primitive defect. Round 6 removes the primitive
#   instead of adding layer N+1 (S11.4.250 step 5): THIS FILE NO LONGER PAIRS LOGS AT ALL. The real
#   FR-002/T-A01 comparison runs ONLY on a same-run TRIPLET produced by capture_fc_timer_triplet.sh
#   -- FC0a + FC0b (without timers; their diff is the noise floor) and FC1 (with timers), launched
#   under one run-id, concurrently, against the same tree -- and described by that harness's
#   provenance manifest (<prefix>_<run-id>.triplet). The closest-timestamp pairing, the fallback
#   noise-floor search, the timestamp-proximity TSV corroboration and the filename-timestamp
#   parser are all deleted; nothing in this file reads a timestamp out of a filename any more.
#
#   No valid triplet  -> the real comparison is an honest SKIP naming why. Never a comparison of
#                        two unrelated captures, never a "SAME-WINDOW" claim that was not measured.
#   Triplet found     -> it is VALIDATED before use; every check below is a hard assertion:
#     * integrity : all three member logs exist and match the manifest's sha256 (a partial,
#                   truncated or edited capture is refused);
#     * provenance (T048 round-5 m3, fixed from real evidence, not filenames): each member ran
#                   with its OWN fc_timer run-id, so its section TSV sits at an EXACT path the
#                   manifest records. A genuine timers-ON member (FC1) must have > 0 TSV data rows,
#                   a genuine timers-OFF member (FC0a/FC0b) must have 0, and when the TSV is still
#                   on disk this file RE-COUNTS it and refuses any disagreement with the manifest.
#     * window (T048 round-5 R5-I2): finished_epoch - started_epoch must be <=
#                   FC_TIMER_GOLDEN_MAX_WINDOW_S (default 3600 s, consumer data per S11.4.35). A
#                   triplet outside the window is REFUSED with an honest SKIP of the comparison.
#   Only the NEWEST real manifest is considered. If it fails validation this file does not quietly
#   fall back to an older one; it reports why the newest is unusable.
#
#   Env FC_TIMER_GOLDEN_EVIDENCE_DIR=<dir> : where triplet manifests and the baseline log are looked
#                                    up (default qa-results/fastcycle/us1/red/T015).
#   Env FC_TIMER_GOLDEN_TRIPLET=<manifest> : pin one specific triplet manifest instead of the newest
#                                    real one. A pinned stand-in (mode=stand-in) manifest is
#                                    validated but its comparison is SKIPPED -- stand-in output is
#                                    never FR-002 evidence.
#   Env FC_TIMER_GOLDEN_MAX_WINDOW_S=<seconds> : maximum triplet span (positive integer).
#   Env FC_TIMER_GOLDEN_LOG=<path>   : without-timers log used for checks (a)/(b) when no valid
#                                    triplet exists (default: the newest prebuild_full_run_*.log by
#                                    mtime). Single-log checks only -- this log is never paired with
#                                    anything.
#
# NOISE FLOOR (diagnostic only): when the FC0a-vs-FC1 comparison mismatches, every changed line --
#   removed (present without timers only) AND added (present with timers only; T048 round-5 R5-I3,
#   the pre-fix classifier was blind to added lines) -- is checked against the SAME-direction
#   change in FC0a-vs-FC0b. A line that also changes between two timer-free members of the same
#   run is pre-existing noise. A line that does not is reported as "not explained by this ONE noise
#   sample", never as "fc_timer-attributable": one noise pair cannot separate a timer effect from a
#   rare flake (T048 round-5 m4). The classification NEVER changes the strict byte-for-byte
#   FR-002/T-A01 verdict.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../../../.." && pwd)"
EVIDENCE_DIR="${FC_TIMER_GOLDEN_EVIDENCE_DIR:-$ROOT/qa-results/fastcycle/us1/red/T015}"
MAX_WINDOW_S="${FC_TIMER_GOLDEN_MAX_WINDOW_S:-3600}"
if ! printf '%s' "$MAX_WINDOW_S" | grep -qE '^[1-9][0-9]*$'; then
  echo "FATAL: FC_TIMER_GOLDEN_MAX_WINDOW_S='$MAX_WINDOW_S' is not a positive integer"
  exit 2
fi

TMP="$(mktemp -d)"
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT
trap 'cleanup; exit 130' INT
trap 'cleanup; exit 143' TERM

FAIL=0; N=0; SKIPPED=0
chk() { N=$((N + 1)); if [ "$2" = "1" ]; then echo "PASS[$N]: $1"; else echo "FAIL[$N]: $1"; FAIL=$((FAIL + 1)); fi; }
skip() { N=$((N + 1)); SKIPPED=$((SKIPPED + 1)); echo "SKIP[$N]: $1"; }

# _mf_get KEY MANIFEST -- the value of KEY. Prints nothing, returns 1, when
# KEY is absent OR present more than once (an ambiguous manifest is malformed,
# never resolved by picking one of the duplicates).
_mf_get() {
  local n
  n="$(grep -c -- "^$1=" "$2" 2>/dev/null || true)"
  [ "${n:-0}" = 1 ] || return 1
  sed -n "s/^$1=//p" "$2"
}

# _tsv_rows PATH -- data rows (lines after the header) of a TSV, 0 if absent.
_tsv_rows() {
  if [ -f "$1" ]; then tail -n +2 "$1" | grep -c . || true; else echo 0; fi
}

# ============================================================================
# Triplet selection: the pinned manifest, else the NEWEST mode=real manifest
# (newest by its own run_id field; run_ids are YYYYMMDDTHHMMSSZ, so lexical
# order is chronological). Stand-in manifests are not candidates for
# auto-discovery. Nothing here reads a timestamp out of a log FILENAME.
# ============================================================================
MANIFEST=""
if [ -n "${FC_TIMER_GOLDEN_TRIPLET:-}" ]; then
  MANIFEST="$FC_TIMER_GOLDEN_TRIPLET"
  if [ ! -f "$MANIFEST" ]; then
    echo "FATAL: FC_TIMER_GOLDEN_TRIPLET=$MANIFEST does not exist"
    exit 2
  fi
elif [ -d "$EVIDENCE_DIR" ]; then
  _best_id=""
  while IFS= read -r -d '' _mf; do
    [ "$(_mf_get mode "$_mf")" = real ] || continue
    _id="$(_mf_get run_id "$_mf")" || continue
    if [ -z "$_best_id" ] || [ "$_id" \> "$_best_id" ]; then
      _best_id="$_id"; MANIFEST="$_mf"
    fi
  done < <(find "$EVIDENCE_DIR" -maxdepth 1 -name '*.triplet' -print0 2>/dev/null)
fi

# validate_triplet MANIFEST -- sets TRIPLET_STATE to one of:
#   valid    : usable; BASELINE_LOG / WITH_TIMERS_LOG / NOISE_LOG are set
#   refused  : genuine but not usable for a same-window comparison (window
#              exceeded, or a stand-in capture) -- an honest SKIP
#   invalid  : the evidence contradicts itself or its own manifest -- a FAIL
# and TRIPLET_REASON to a one-line explanation. Records one chk() per
# provenance/integrity property it verifies, so every PASS cites what was
# actually checked.
validate_triplet() {
  local mf="$1" dir fmt run_id mode s f span m log sha want_sha timing want_timing tsv rows recount
  dir="$(dirname -- "$mf")"
  TRIPLET_STATE=invalid
  fmt="$(_mf_get format "$mf")" || fmt=""
  run_id="$(_mf_get run_id "$mf")" || run_id=""
  mode="$(_mf_get mode "$mf")" || mode=""
  if [ "$fmt" != "fc_timer_triplet/v1" ] || ! printf '%s' "$run_id" | grep -qE '^[0-9]{8}T[0-9]{6}Z$' \
     || { [ "$mode" != real ] && [ "$mode" != stand-in ]; }; then
    TRIPLET_REASON="malformed manifest $mf (format='$fmt' run_id='$run_id' mode='$mode')"
    return
  fi
  for m in FC0a FC0b FC1; do
    log="$(_mf_get "member.$m.log" "$mf")" || log=""
    want_sha="$(_mf_get "member.$m.log_sha256" "$mf")" || want_sha=""
    if [ -z "$log" ] || [ "$(basename -- "$log")" != "$log" ] || [ ! -f "$dir/$log" ]; then
      TRIPLET_REASON="member $m log '$log' missing next to $mf"
      return
    fi
    sha="$(sha256sum "$dir/$log" | awk '{print $1}')"
    if [ "$sha" != "$want_sha" ]; then
      TRIPLET_REASON="member $m log $dir/$log sha256 $sha does not match the manifest's $want_sha (partial, truncated or edited capture)"
      return
    fi
    want_timing=0; [ "$m" = FC1 ] && want_timing=1
    timing="$(_mf_get "member.$m.fc_timing" "$mf")" || timing=""
    if [ "$timing" != "$want_timing" ]; then
      TRIPLET_REASON="member $m recorded fc_timing='$timing', a triplet requires $want_timing"
      return
    fi
    tsv="$(_mf_get "member.$m.tsv" "$mf")" || tsv=""
    rows="$(_mf_get "member.$m.tsv_rows" "$mf")" || rows=""
    if ! printf '%s' "$rows" | grep -qE '^[0-9]+$' || [ -z "$tsv" ]; then
      TRIPLET_REASON="member $m has no usable tsv/tsv_rows provenance in $mf"
      return
    fi
    if [ -f "$tsv" ]; then
      recount="$(_tsv_rows "$tsv")"
      if [ "$recount" != "$rows" ]; then
        TRIPLET_REASON="member $m TSV $tsv has $recount data rows now, the manifest recorded $rows"
        return
      fi
    fi
    if [ "$want_timing" = 1 ] && [ "$rows" -eq 0 ]; then
      TRIPLET_REASON="member $m claims timers ON but its own TSV ($tsv) has 0 data rows -- fc_timer did not actually run"
      return
    fi
    if [ "$want_timing" = 0 ] && [ "$rows" -ne 0 ]; then
      TRIPLET_REASON="member $m claims timers OFF but its own TSV ($tsv) has $rows data rows -- fc_timer DID run"
      return
    fi
  done
  s="$(_mf_get started_epoch "$mf")" || s=""
  f="$(_mf_get finished_epoch "$mf")" || f=""
  if ! printf '%s' "$s" | grep -qE '^[0-9]+$' || ! printf '%s' "$f" | grep -qE '^[0-9]+$' || [ "$f" -lt "$s" ]; then
    TRIPLET_REASON="manifest $mf has no usable started_epoch/finished_epoch ('$s'/'$f')"
    return
  fi
  span=$((f - s))
  chk "triplet $run_id integrity: all 3 member logs present and byte-identical to the manifest's sha256" "1"
  chk "triplet $run_id provenance (m3): FC1 ran WITH timers (its own TSV has $(_mf_get member.FC1.tsv_rows "$mf") rows), FC0a/FC0b ran WITHOUT (0 rows each) -- exact per-member TSV paths, never filename inference" "1"
  # From here on the members are verified genuine, so FC0a can serve the
  # single-log checks (a)/(b) even when the triplet is refused below.
  BASELINE_LOG="$dir/$(_mf_get member.FC0a.log "$mf")"
  if [ "$span" -gt "$MAX_WINDOW_S" ]; then
    TRIPLET_STATE=refused
    TRIPLET_REASON="triplet $run_id spans ${span}s, more than the ${MAX_WINDOW_S}s maximum (FC_TIMER_GOLDEN_MAX_WINDOW_S) -- NOT a same-window triplet"
    return
  fi
  if [ "$mode" != real ]; then
    TRIPLET_STATE=refused
    TRIPLET_REASON="triplet $run_id is a stand-in capture (mode=$mode) -- never FR-002 evidence"
    return
  fi
  NOISE_LOG="$dir/$(_mf_get member.FC0b.log "$mf")"
  WITH_TIMERS_LOG="$dir/$(_mf_get member.FC1.log "$mf")"
  TRIPLET_STATE=valid
  TRIPLET_REASON="same-run triplet $run_id, $(_mf_get concurrency "$mf"), ${span}s span (<= ${MAX_WINDOW_S}s)"
  local hs he ss se
  hs="$(_mf_get tree_head_start "$mf")"; he="$(_mf_get tree_head_end "$mf")"
  ss="$(_mf_get tree_status_sha256_start "$mf")"; se="$(_mf_get tree_status_sha256_end "$mf")"
  if [ "$hs" = "$he" ] && [ "$ss" = "$se" ]; then
    TRIPLET_TREE_NOTE="tree unchanged during the capture (HEAD $hs, status fingerprint stable)"
  else
    TRIPLET_TREE_NOTE="tree CHANGED during the capture (HEAD $hs -> $he, status $ss -> $se); all three members ran concurrently against the same changing tree, so the FC0a/FC0b noise floor carries that drift too"
  fi
}

BASELINE_LOG=""; WITH_TIMERS_LOG=""; NOISE_LOG=""
TRIPLET_STATE=none; TRIPLET_REASON=""; TRIPLET_TREE_NOTE=""
if [ -n "$MANIFEST" ]; then
  validate_triplet "$MANIFEST"
  case "$TRIPLET_STATE" in
    valid)   echo "INFO: using $TRIPLET_REASON ($MANIFEST)"
             echo "INFO: $TRIPLET_TREE_NOTE"
             _cur_head="$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo UNKNOWN)"
             [ "$_cur_head" = "$(_mf_get tree_head_end "$MANIFEST")" ] \
               || echo "INFO: triplet was captured at HEAD $(_mf_get tree_head_end "$MANIFEST"); current HEAD is $_cur_head -- re-capture to validate the current tree" ;;
    refused) echo "INFO: newest triplet refused: $TRIPLET_REASON" ;;
    invalid) chk "triplet evidence is self-consistent ($MANIFEST): $TRIPLET_REASON" "0" ;;
  esac
else
  _legacy="$(find "$EVIDENCE_DIR" -maxdepth 1 -name '*_FC1_*.log' 2>/dev/null | wc -l | tr -d ' ')"
  TRIPLET_REASON="no triplet manifest in $EVIDENCE_DIR (${_legacy} *_FC1_* log(s) present without a mode=real manifest are not consumed: without one their timer setting and window cannot be verified) -- run capture_fc_timer_triplet.sh"
  echo "INFO: $TRIPLET_REASON"
fi

# Baseline for the single-log checks (a)/(b): a valid or refused triplet's
# own (sha-verified) FC0a; with no triplet at all, an explicit
# FC_TIMER_GOLDEN_LOG, else the newest prebuild_full_run_*.log by mtime --
# never paired with anything. An INVALID triplet supplies no baseline: its
# members are not trustworthy, and the FAIL above already reports why.
if [ "$TRIPLET_STATE" = none ]; then
  BASELINE_LOG="${FC_TIMER_GOLDEN_LOG:-}"
  if [ -z "$BASELINE_LOG" ] && [ -d "$EVIDENCE_DIR" ]; then
    BASELINE_LOG="$(find "$EVIDENCE_DIR" -maxdepth 1 -name 'prebuild_full_run_*.log' -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -n1 | cut -d' ' -f2-)"
  fi
  if [ -z "$BASELINE_LOG" ] || [ ! -f "$BASELINE_LOG" ]; then
    echo "FATAL: no real 'without timers' evidence log found (no triplet manifest, and no" \
         "FC_TIMER_GOLDEN_LOG / prebuild_full_run_*.log in $EVIDENCE_DIR)."
    exit 2
  fi
fi
[ "$TRIPLET_STATE" = invalid ] && BASELINE_LOG=""
[ -n "$BASELINE_LOG" ] && echo "INFO: baseline (without-timers) log: $BASELINE_LOG"

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
if [ -n "$BASELINE_LOG" ]; then
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
else
  BASELINE_LINES=0
  skip "(a)/(b) real baseline checks: the only candidate baseline was a member of the invalid triplet reported above, so no trustworthy without-timers log is available"
fi

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
# (d) the REAL FR-002/T-A01 comparison: FC0a (without timers) vs FC1 (with
# timers) of ONE validated same-run triplet. Anything else is an honest SKIP.
# ============================================================================
if [ "$TRIPLET_STATE" = valid ]; then
  extract_verdicts "$WITH_TIMERS_LOG" "$TMP/with_timers.txt"
  WITH_LINES="$(wc -l < "$TMP/with_timers.txt" | tr -d ' ')"
  chk "real 'with timers' verdict set captured from $WITH_TIMERS_LOG ($WITH_LINES verdict lines)" "$([ "$WITH_LINES" -gt 0 ] && echo 1 || echo 0)"

  if cmp -s "$TMP/baseline_1.txt" "$TMP/with_timers.txt"; then
    chk "FR-002/T-A01: with-timers verdict set is IDENTICAL to the without-timers verdict set, byte-for-byte after stripping timing suffixes ($TRIPLET_REASON)" "1"
  else
    DIFF_REAL="$(diff "$TMP/baseline_1.txt" "$TMP/with_timers.txt" 2>/dev/null || true)"
    DIFF_REAL_LINES="$(printf '%s\n' "$DIFF_REAL" | grep -c '^[<>]' || true)"
    chk "FR-002/T-A01: with-timers verdict set is IDENTICAL to the without-timers verdict set, byte-for-byte after stripping timing suffixes ($TRIPLET_REASON) -- MISMATCH, $DIFF_REAL_LINES differing line(s), diff below" "0"
    printf '%s\n' "$DIFF_REAL" | head -n 60

    # Noise-floor classification (diagnostic only; never changes the verdict
    # above). Both directions are classified (R5-I3), each against the SAME
    # direction in FC0a-vs-FC0b.
    extract_verdicts "$NOISE_LOG" "$TMP/noise.txt"
    DIFF_NOISE="$(diff "$TMP/baseline_1.txt" "$TMP/noise.txt" 2>/dev/null || true)"
    printf '%s\n' "$DIFF_REAL"  | sed -n 's/^< //p' > "$TMP/real_removed.txt"
    printf '%s\n' "$DIFF_REAL"  | sed -n 's/^> //p' > "$TMP/real_added.txt"
    printf '%s\n' "$DIFF_NOISE" | sed -n 's/^< //p' > "$TMP/noise_removed.txt"
    printf '%s\n' "$DIFF_NOISE" | sed -n 's/^> //p' > "$TMP/noise_added.txt"
    NOISE_EXPLAINED=0
    UNEXPLAINED=0
    _fc_classify_against() {
      # $1 = changed lines on the real side, $2 = the noise side, SAME direction
      local _fc_line
      while IFS= read -r _fc_line; do
        [ -n "$_fc_line" ] || continue
        if grep -qxF -- "$_fc_line" "$2" 2>/dev/null; then
          NOISE_EXPLAINED=$((NOISE_EXPLAINED + 1))
        else
          UNEXPLAINED=$((UNEXPLAINED + 1))
        fi
      done < "$1"
    }
    _fc_classify_against "$TMP/real_removed.txt" "$TMP/noise_removed.txt"
    _fc_classify_against "$TMP/real_added.txt" "$TMP/noise_added.txt"
    TOTAL_CHANGED="$(( $(wc -l < "$TMP/real_removed.txt") + $(wc -l < "$TMP/real_added.txt") ))"
    echo "NOISE-FLOOR: changed=$TOTAL_CHANGED noise_explained=$NOISE_EXPLAINED not_explained=$UNEXPLAINED (noise floor FC0a-vs-FC0b of the same triplet has $(printf '%s\n' "$DIFF_NOISE" | grep -c '^[<>]' || true) differing line(s))"
    echo "INFO: of $TOTAL_CHANGED changed verdict line(s) (removed + added), $NOISE_EXPLAINED also change the same way between the two timer-free members of this run (pre-existing noise, not attributable to fc_timer) and $UNEXPLAINED are not explained by this ONE noise sample -- investigate those; one noise pair cannot tell a timer effect from a rare flake, so they are NEVER asserted fc_timer-caused here."
  fi
else
  skip "FR-002/T-A01 real with-timers-vs-without-timers comparison: no valid same-run triplet -- ${TRIPLET_REASON:-none found}. Two unrelated captures are never compared."
fi

echo "SUMMARY: $((N - FAIL - SKIPPED)) pass / $FAIL fail / $SKIPPED skip of $N assertions (baseline: $BASELINE_LOG, $BASELINE_LINES verdict lines)"
[ "$FAIL" = 0 ]
