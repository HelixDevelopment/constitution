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
#   (a) the REAL verdict set, captured from an actual pre_build_verification.sh run (labelled
#       "without timers" ONLY when it is a validated triplet's FC0a; a fallback log's timer
#       state is not verified and it is labelled so -- T048 round 7, R6-I3), is checked for any timing-looking noise that a stripping step would need to remove
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
#     * window (T048 round-5 R5-I2): finished_epoch - started_epoch must be <= (inclusive: a span
#                   EXACTLY equal to the maximum is accepted -- pinned by the round-7 R6-M1 boundary cases)
#                   FC_TIMER_GOLDEN_MAX_WINDOW_S (default 3600 s, consumer data per S11.4.35). A
#                   triplet outside the window is REFUSED with an honest SKIP of the comparison.
#   Only the NEWEST manifest is considered. If it fails validation this file does not quietly
#   fall back to an older one; it reports why the newest is unusable. (Round 7, R6-I1: "newest"
#   now includes MALFORMED manifests -- ranked by their own run_id, else by the run-id in their
#   filename -- so a broken newest manifest is a FAIL, never skipped in favour of an older one.
#   Only a well-formed mode=stand-in manifest is excluded from discovery.)
#     * isolation (round 7, R6-B1 root cause): a CONCURRENT triplet must record
#                   tmpdir_isolation=per-member. Concurrent members sharing one TMPDIR were
#                   MEASURED to clobber each other's fixed ${TMPDIR}/<name> evidence directories;
#                   the two identical twins FC0a/FC0b collide identically, which their noise floor
#                   cannot see. A concurrent triplet without the key is REFUSED (honest SKIP).
#     * members   (round 7, R6-M2): every member exit code and start/finish epoch must be a
#                   recorded integer (a MISSING exit is a killed/crashed member -> FAIL), the epochs
#                   must lie inside the manifest window, and the FC0a vs FC1 EXIT CODE (the
#                   "commit result" of FR-002) is compared alongside the verdict set.
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
# T048 ROUND 21 (R20-I1, S11.4.124): the KNOWN-FLAKY REGISTRY, the
# SUMMARY-TAIL truncation and the registry exact-accounting exit-code
# explanation that used to live in this comment block are REMOVED. Each
# compensated for a single primitive defect -- two registered flaky
# gates (CM-SPK512-BRIDGE-SECLABEL-SHELL's SIGPIPE race,
# CM-OPEN-CRITICAL-BLOCKER-REGISTRY's CRITIC_IGNORED textual
# nondeterminism) -- that is now genuinely fixed at its own source (see
# docs/requests/t048_round4_defect1_spk512_bridge_report.md and
# .../t048_round4_defect3_cbg_critic_ignored_report.md). See the
# ROUND-21 ARCHITECTURE note above section (d) below for the strict
# 3-way rule that replaced the whole cascade.
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
# T048 round 12 (R12-M2): FC_TIMER_GOLDEN_ROOT overrides the parent-repo-
# root default (measured, not assumed, S11.4.6: the default is derived from
# "$0"'s OWN location, which is CORRECT when this file runs in place but
# WRONG for a copy run by a mutation-testing harness from a temp directory
# -- found running this round's OWN (M-I1b) mutation guard, which ran a
# mutated copy exercising the R12-M2 defect_doc-exists check for the first
# time; every OTHER existing use of $ROOT was either EVIDENCE_DIR, always
# overridden explicitly by every mutated-copy caller to date, or an INFO-
# only git-HEAD comparison, so this was latent and undetected until now). A
# mutated-copy regression test MUST pass FC_TIMER_GOLDEN_ROOT explicitly
# whenever its fixture content references a real, registered gate id.
ROOT="${FC_TIMER_GOLDEN_ROOT:-$(cd "$HERE/../../../.." && pwd)}"
EVIDENCE_DIR="${FC_TIMER_GOLDEN_EVIDENCE_DIR:-$ROOT/qa-results/fastcycle/us1/red/T015}"
MAX_WINDOW_S="${FC_TIMER_GOLDEN_MAX_WINDOW_S:-3600}"
if ! printf '%s' "$MAX_WINDOW_S" | grep -qE '^[1-9][0-9]*$'; then
  echo "FATAL: FC_TIMER_GOLDEN_MAX_WINDOW_S='$MAX_WINDOW_S' is not a positive integer"
  exit 2
fi

# T048 round 21 (R20-I1/S11.4.124): the KNOWN_FLAKY_TSV registry loader,
# its SUMMARY_TAIL_RE truncation, and the FC_TIMER_GOLDEN_TODAY /
# _fc_valid_iso_date() expiry machinery that validated it are REMOVED --
# see the T048 ROUND 21 note near the top of this file and the ROUND-21
# ARCHITECTURE note above section (d) below.
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
  # T048 restart round-1 R2-M2: the KEY is matched as an exact literal prefix "KEY=" (awk
  # index()==1), never placed into a regex -- "member.FC0a.log" used to match the near-miss
  # "memberXFC0aXlog=" too ('.' is a regex metachar), so a decoy line could make a real key
  # look duplicated (or supply its value).
  local n
  n="$(awk -v k="$1=" 'index($0, k) == 1 {c++} END {print c+0}' "$2" 2>/dev/null)"
  [ "${n:-0}" = 1 ] || return 1
  awk -v k="$1=" 'index($0, k) == 1 {print substr($0, length(k) + 1)}' "$2"
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
MANIFEST=""; DISCOVERY_PROBLEM=""
if [ -n "${FC_TIMER_GOLDEN_TRIPLET:-}" ]; then
  MANIFEST="$FC_TIMER_GOLDEN_TRIPLET"
  if [ ! -f "$MANIFEST" ]; then
    echo "FATAL: FC_TIMER_GOLDEN_TRIPLET=$MANIFEST does not exist"
    exit 2
  fi
elif [ -d "$EVIDENCE_DIR" ]; then
  # T048 round 7 (finding R6-I1): EVERY *.triplet is a candidate unless it is
  # a WELL-FORMED stand-in (exactly one mode=stand-in line). Round 6 skipped
  # any manifest whose mode/run_id key was missing or duplicated with a bare
  # `continue`, so a malformed NEWEST manifest silently handed the comparison
  # to an OLDER one (reviewer repro A1: a newer triplet with a real FC1
  # verdict flip and `mode=real` written twice -> rc=0, 12 PASS, the older
  # SAME triplet compared instead). A candidate is now ranked by its own
  # run_id when that is readable, else by the run-id in its filename
  # (<prefix>_<run-id>.triplet) -- used ONLY to rank, so a broken manifest can
  # never hide behind an older good one; validate_triplet then FAILs it. A
  # candidate with no recoverable run-id at all, or two candidates sharing
  # the newest run-id, is a FAIL: the newest evidence cannot be identified.
  _best_id=""; _best_n=0; DISCOVERY_PROBLEM=""
  while IFS= read -r -d '' _mf; do
    _mode="$(_mf_get mode "$_mf")" || _mode=""
    [ "$_mode" = stand-in ] && continue
    _id="$(_mf_get run_id "$_mf")" || _id=""
    if ! printf '%s' "$_id" | grep -qE '^[0-9]{8}T[0-9]{6}Z$'; then
      _id="$(basename -- "$_mf" .triplet)"; _id="${_id##*_}"
      if ! printf '%s' "$_id" | grep -qE '^[0-9]{8}T[0-9]{6}Z$'; then
        DISCOVERY_PROBLEM="$DISCOVERY_PROBLEM manifest $_mf has no readable run_id (neither in its content nor its filename), so it cannot be ruled out as the newest;"
        continue
      fi
    fi
    if [ -z "$_best_id" ] || [ "$_id" \> "$_best_id" ]; then
      _best_id="$_id"; MANIFEST="$_mf"; _best_n=1
    elif [ "$_id" = "$_best_id" ]; then
      _best_n=$((_best_n + 1))
    fi
  done < <(find "$EVIDENCE_DIR" -maxdepth 1 -name '*.triplet' -print0 2>/dev/null)
  if [ "$_best_n" -gt 1 ]; then
    DISCOVERY_PROBLEM="$DISCOVERY_PROBLEM $_best_n manifests share the newest run-id $_best_id, so which one is the newest evidence is ambiguous;"
  fi
fi

# _fc_ranges_overlap S1 F1 S2 F2 -- true if the epoch ranges [S1,F1] and
# [S2,F2] GENUINELY overlap (STRICT: a shared boundary second -- one
# member's finished_epoch equal to the other's started_epoch -- is NOT
# overlap, it is exactly what "ran one after another" looks like at
# 1-second epoch granularity; a fast stand-in/host can legitimately finish
# member N and start member N+1 inside the SAME wall-clock second, or even
# have every member's own started_epoch == finished_epoch, so an inclusive
# test would false-refuse genuinely-sequential captures -- the S11.4.201(1)
# false-positive this strict form avoids). All 4 arguments must already be
# validated non-negative integers (T048 round 8, R8-M2); a non-integer
# argument is treated as "cannot determine" (never overlapping, never a
# false refusal) since this check is defense-in-depth on an
# already-trusted producer, not a load-bearing refusal of untrusted input.
_fc_ranges_overlap() {
  for _r in "$1" "$2" "$3" "$4"; do
    printf '%s' "$_r" | grep -qE '^[0-9]+$' || return 1
  done
  [ "$1" -lt "$4" ] && [ "$3" -lt "$2" ]
}

# validate_triplet MANIFEST -- sets TRIPLET_STATE to one of:
#   valid    : usable; BASELINE_LOG / WITH_TIMERS_LOG / NOISE_LOG are set
#   refused  : genuine but not usable for a same-window comparison (window
#              exceeded, or a stand-in capture) -- an honest SKIP
#   invalid  : the evidence contradicts itself or its own manifest -- a FAIL
# and TRIPLET_REASON to a one-line explanation. Records one chk() per
# provenance/integrity property it verifies, so every PASS cites what was
# actually checked.
validate_triplet() {
  local mf="$1" dir fmt run_id mode prefix s f span m log sha want_sha timing want_timing tsv rows recount
  local ex ms mf_ep absent=0 concurrency_mode
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
  # T048 round 11 (R10-M4): `concurrency` is read and validated against its
  # own closed set {concurrent, sequential} HERE, once, before anything
  # downstream relies on its value. Round 10's own code read the raw
  # manifest value TWICE independently and never validated it: a MISSING
  # key (duplicated, so _mf_get returns empty) or a GARBLED value made the
  # per-member-isolation refusal below never fire (empty/garbage != sequential
  # is true, so the "concurrent-without-isolation" refusal was skipped) AND
  # made the sequential-tree-changed refusal never fire either (empty/garbage
  # != sequential), letting a tree-changed capture with an unreadable
  # concurrency value sail through to TRIPLET_STATE=valid printing the false
  # "all three members ran concurrently" claim on a value that was never
  # actually proven concurrent. A conservative-safe REFUSE on an unresolvable
  # value (S11.4.101/S11.4.201) closes this.
  concurrency_mode="$(_mf_get concurrency "$mf")" || concurrency_mode=""
  case "$concurrency_mode" in
    concurrent|sequential) : ;;
    *)
      TRIPLET_REASON="manifest $mf has concurrency='$concurrency_mode', not one of the closed set {concurrent, sequential}"
      return
      ;;
  esac
  # Round 7 (R6-I1/M3): the manifest is bound to its own filename, and the
  # member TSV paths are bound to run_id+prefix+member below.
  prefix="$(_mf_get prefix "$mf")" || prefix=""
  if ! printf '%s' "$prefix" | grep -qE '^[A-Za-z0-9-]+$' || [ "$(basename -- "$mf")" != "${prefix}_${run_id}.triplet" ]; then
    TRIPLET_REASON="manifest $mf is not named <prefix>_<run_id>.triplet for its own prefix='$prefix' run_id='$run_id'"
    return
  fi
  s="$(_mf_get started_epoch "$mf")" || s=""
  f="$(_mf_get finished_epoch "$mf")" || f=""
  if ! printf '%s' "$s" | grep -qE '^[0-9]+$' || ! printf '%s' "$f" | grep -qE '^[0-9]+$' || [ "$f" -lt "$s" ]; then
    TRIPLET_REASON="manifest $mf has no usable started_epoch/finished_epoch ('$s'/'$f')"
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
    # Round 7 (R6-M2): a member's exit and epochs are recorded evidence too.
    # A non-integer exit (the harness writes MISSING when a member was killed
    # before recording one) is a crashed member, never comparable.
    ex="$(_mf_get "member.$m.exit" "$mf")" || ex=""
    if ! printf '%s' "$ex" | grep -qE '^[0-9]+$'; then
      TRIPLET_REASON="member $m recorded exit='$ex' -- not an integer exit status (killed or crashed member)"
      return
    fi
    for mf_ep in started_epoch finished_epoch; do
      ms="$(_mf_get "member.$m.$mf_ep" "$mf")" || ms=""
      if ! printf '%s' "$ms" | grep -qE '^[0-9]+$' || [ "$ms" -lt "$s" ] || [ "$ms" -gt "$f" ]; then
        TRIPLET_REASON="member $m $mf_ep='$ms' is not an integer inside the manifest window [$s, $f]"
        return
      fi
    done
    tsv="$(_mf_get "member.$m.tsv" "$mf")" || tsv=""
    rows="$(_mf_get "member.$m.tsv_rows" "$mf")" || rows=""
    if ! printf '%s' "$rows" | grep -qE '^[0-9]+$' || [ -z "$tsv" ]; then
      TRIPLET_REASON="member $m has no usable tsv/tsv_rows provenance in $mf"
      return
    fi
    # Round 7 (R6-M3): the TSV path must be the member's OWN fc_timer run-id
    # directory (<root>/<run_id>_<prefix>_<member>/prebuild_sections.tsv), so
    # three members can never share one path, nor point at another run's.
    case "$tsv" in
      */"${run_id}_${prefix}_${m}"/prebuild_sections.tsv) : ;;
      *) TRIPLET_REASON="member $m TSV path '$tsv' is not .../${run_id}_${prefix}_${m}/prebuild_sections.tsv (not bound to this run and member)"
         return ;;
    esac
    if [ -f "$tsv" ]; then
      recount="$(_tsv_rows "$tsv")"
      if [ "$recount" != "$rows" ]; then
        TRIPLET_REASON="member $m TSV $tsv has $recount data rows now, the manifest recorded $rows"
        return
      fi
    else
      absent=$((absent + 1))
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
  span=$((f - s))
  chk "triplet $run_id integrity: all 3 member logs present and byte-identical to the manifest's sha256; every member exit + epoch recorded" "1"
  if [ "$absent" = 0 ]; then
    chk "triplet $run_id provenance (m3): FC1 ran WITH timers (its own TSV has $(_mf_get member.FC1.tsv_rows "$mf") rows, re-counted on disk), FC0a/FC0b ran WITHOUT (0 rows each) -- exact per-member TSV paths bound to run_id+member, never filename inference" "1"
  else
    chk "triplet $run_id provenance (m3): manifest-recorded TSV rows FC1=$(_mf_get member.FC1.tsv_rows "$mf"), FC0a/FC0b=0 at per-member paths bound to run_id+member ($absent of 3 TSV(s) no longer on disk, NOT re-counted)" "1"
  fi
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
  if [ "$concurrency_mode" != sequential ] && [ "$(_mf_get tmpdir_isolation "$mf")" != per-member ]; then
    TRIPLET_STATE=refused
    TRIPLET_REASON="triplet $run_id ran its members concurrently WITHOUT per-member TMPDIR isolation (no tmpdir_isolation=per-member) -- concurrent members sharing one TMPDIR were measured to clobber each other's fixed \${TMPDIR}/<name> evidence dirs (T048 round 7, R6-B1), and the identical FC0a/FC0b twins collide identically, so neither the comparison nor its noise floor is trustworthy; re-capture with the current harness"
    return
  fi
  NOISE_LOG="$dir/$(_mf_get member.FC0b.log "$mf")"
  WITH_TIMERS_LOG="$dir/$(_mf_get member.FC1.log "$mf")"
  local hs he ss se
  hs="$(_mf_get tree_head_start "$mf")"; he="$(_mf_get tree_head_end "$mf")"
  ss="$(_mf_get tree_status_sha256_start "$mf")"; se="$(_mf_get tree_status_sha256_end "$mf")"
  # concurrency_mode was already read + validated against its closed set
  # {concurrent, sequential} above (T048 round 11, R10-M4) -- never re-read
  # here, so there is exactly one source of truth for it in this function.
  # T048 round 8 (finding R8-M2, Minor, defense-in-depth): a manifest
  # CLAIMING concurrency=sequential is cheaply cross-checked against its
  # own recorded per-member epochs -- the harness is the trusted producer
  # of this claim today, so a mismatch here is a contradiction worth
  # surfacing, not a hardening of untrusted input. Any two members'
  # [started_epoch,finished_epoch] windows overlapping contradicts
  # "sequential" (members never overlap, by definition).
  if [ "$concurrency_mode" = sequential ]; then
    local _ep_a_s _ep_a_f _ep_b_s _ep_b_f _ep_1_s _ep_1_f
    _ep_a_s="$(_mf_get member.FC0a.started_epoch "$mf")"; _ep_a_f="$(_mf_get member.FC0a.finished_epoch "$mf")"
    _ep_b_s="$(_mf_get member.FC0b.started_epoch "$mf")"; _ep_b_f="$(_mf_get member.FC0b.finished_epoch "$mf")"
    _ep_1_s="$(_mf_get member.FC1.started_epoch "$mf")"; _ep_1_f="$(_mf_get member.FC1.finished_epoch "$mf")"
    if _fc_ranges_overlap "$_ep_a_s" "$_ep_a_f" "$_ep_b_s" "$_ep_b_f" \
       || _fc_ranges_overlap "$_ep_a_s" "$_ep_a_f" "$_ep_1_s" "$_ep_1_f" \
       || _fc_ranges_overlap "$_ep_b_s" "$_ep_b_f" "$_ep_1_s" "$_ep_1_f"; then
      TRIPLET_STATE=refused
      TRIPLET_REASON="triplet $run_id claims concurrency=sequential but two members' recorded [started_epoch,finished_epoch] windows overlap (FC0a=[$_ep_a_s,$_ep_a_f] FC0b=[$_ep_b_s,$_ep_b_f] FC1=[$_ep_1_s,$_ep_1_f]) -- the sequential claim contradicts its own recorded timing"
      return
    fi
  fi
  # T048 round 8 (finding R8-I3): a SEQUENTIAL triplet's members run one
  # after another, so a tree change DURING the capture lands DIFFERENTLY on
  # each member (FC0a and FC1 see the tree at DIFFERENT points in time) --
  # unlike a concurrent triplet, where drift affects all three members at
  # roughly the same moments. The FC0a/FC0b noise floor is itself only a
  # two-sample, same-moment comparison, so it cannot meaningfully carry an
  # ASYMMETRIC drift the way the (concurrent-only) note below claims.
  # Refuse this triplet the same way any other non-trustworthy triplet is
  # refused above, rather than comparing it under a note that is false for
  # the sequential case (S11.4.6).
  if [ "$concurrency_mode" = sequential ] && { [ "$hs" != "$he" ] || [ "$ss" != "$se" ]; }; then
    TRIPLET_STATE=refused
    TRIPLET_REASON="triplet $run_id is sequential and the tree CHANGED during the capture (HEAD $hs -> $he, status $ss -> $se) -- a sequential triplet's members see the tree at DIFFERENT moments, so the drift is not symmetric across members and the FC0a/FC0b noise floor cannot be trusted to carry it; re-capture (concurrently, or once the tree is quiescent)"
    return
  fi
  TRIPLET_STATE=valid
  TRIPLET_REASON="same-run triplet $run_id, $concurrency_mode, ${span}s span (<= ${MAX_WINDOW_S}s)"
  if [ "$hs" = "$he" ] && [ "$ss" = "$se" ]; then
    TRIPLET_TREE_NOTE="tree unchanged during the capture (HEAD $hs, status fingerprint stable)"
  else
    # Reaching here with a tree change means concurrency_mode != sequential
    # (the sequential+changed case was refused above), so this claim is now
    # always accurate.
    TRIPLET_TREE_NOTE="tree CHANGED during the capture (HEAD $hs -> $he, status $ss -> $se); all three members ran concurrently against the same changing tree, so the FC0a/FC0b noise floor carries that drift too"
  fi
}

BASELINE_LOG=""; WITH_TIMERS_LOG=""; NOISE_LOG=""
TRIPLET_STATE=none; TRIPLET_REASON=""; TRIPLET_TREE_NOTE=""
if [ -n "$DISCOVERY_PROBLEM" ]; then
  TRIPLET_STATE=invalid
  TRIPLET_REASON="triplet discovery in $EVIDENCE_DIR:$DISCOVERY_PROBLEM no triplet is compared"
  chk "triplet evidence is self-consistent: $TRIPLET_REASON" "0"
elif [ -n "$MANIFEST" ]; then
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
# BASELINE_LABEL (T048 round 7, R6-I3): only a sha-verified triplet FC0a whose
# own TSV was proven to have 0 rows is called "without timers". A fallback
# log is NOT verified timer-free -- since T029 timers are ON unless
# FC_TIMING=0, so the newest plain prebuild log is normally a WITH-timers run
# (the round-6 default path printed "real 'without timers'" for a log whose
# own TSV had 183 rows). The single-log checks (a)/(b) do not need a
# timer-free log, so the fallback is labelled neutrally instead.
BASELINE_LABEL="real 'without timers' (triplet FC0a, verified 0 TSV rows)"
if [ "$TRIPLET_STATE" = none ]; then
  BASELINE_LABEL="real pre_build_verification.sh log, timer state NOT verified"
  BASELINE_LOG="${FC_TIMER_GOLDEN_LOG:-}"
  if [ -z "$BASELINE_LOG" ] && [ -d "$EVIDENCE_DIR" ]; then
    BASELINE_LOG="$(find "$EVIDENCE_DIR" -maxdepth 1 -name 'prebuild_full_run_*.log' -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -n1 | cut -d' ' -f2-)"
  fi
  if [ -z "$BASELINE_LOG" ] || [ ! -f "$BASELINE_LOG" ]; then
    echo "FATAL: no real pre_build evidence log found (no triplet manifest, and no" \
         "FC_TIMER_GOLDEN_LOG / prebuild_full_run_*.log in $EVIDENCE_DIR)."
    exit 2
  fi
fi
[ "$TRIPLET_STATE" = invalid ] && BASELINE_LOG=""
[ -n "$BASELINE_LOG" ] && echo "INFO: baseline log ($BASELINE_LABEL): $BASELINE_LOG"

# verdict-line shape used throughout pre_build_verification.sh: PASS/FAIL/WARN lines carry a
# UTF-8 checkmark/cross, the literal 'ERROR:'/'WARNING:' (log_fail()/log_warn() -- T048 round 14,
# R14-I2: the real log_warn() text is "WARNING:", NOT "WARN:"; the pre-round-14 'WARN:' alternative
# never matched a single real printed line in this script -- confirmed by direct grep, its one hit
# is inside an UNRELATED grep pattern elsewhere, not a printed verdict -- kept harmlessly for any
# external caller whose own script genuinely emits that literal), OR the real OK/FAIL-style shape
# ~640-per-run direct `ERRORS=$((ERRORS+1))` sites print: every one of this script's 1614
# `echo -n "...description... "` check-description prompts ends in a literal "... " (verified: ALL
# 1614 at the time, by direct grep; 1620 at 2e1eb2f4b63 -- the property holds, the count drifts),
# immediately followed (no intervening stdout output) by a
# bare `OK` or `FAIL` token, optionally followed by `:`/a space/end-of-line and trailing detail text
# -- so "... " immediately followed by OK or FAIL, with the NEXT character (if any) NOT a letter or
# digit (the word-boundary guard so "OKAY"/"FAILURE" could never false-match, even though neither
# occurs in this script today), is the real, exact shape. MEASURED, not assumed (S11.4.6): this
# exact pattern matches 640 lines in a real captured log (qa-results/fastcycle/us1/red/T015/
# prebuild_with_timers_full_run_20260930T152954Z.log) -- precisely the round-14 reviewer's own cited
# count, confirmed by an independent re-count against the SAME log, with zero false positives (a
# "... OK Apps, Kodi, Codecs ..." SECTION-TITLE line is correctly excluded). CORRECTION (T048
# restart round-1, R2-B1/R2-M5): the "stderr-interleaving-corrupted bare OK lines" this comment
# used to call "correctly excluded" are NOT noise -- they are real verdicts whose gate wrote to
# stderr between its prompt and its verdict, pushing the verdict onto the NEXT line. Excluding
# them hid those gates' verdicts entirely (a displaced OK->FAIL flip passed the comparison). They
# are now PAIRED with their prompt by _pair_displaced_verdicts below. Banner/section lines never
# carry any of these shapes.
VERDICT_RE='(✓|✗|WARN:|ERROR:|WARNING:|\.\.\.[[:space:]]+(OK|FAIL)([^A-Za-z0-9]|$))'

# extract_verdicts <log> <out> : one stable verdict line per matched input line, ANSI-stripped,
# leading/trailing whitespace trimmed, any trailing BRACKET/PAREN-WRAPPED "[N.NNs]"/"(N.NNs)"/
# "[N ms]" TIMING SUFFIX removed (none exist in the real baseline today per the FINDING above;
# this is the stripping step T029's real comparison will need once fc_timer adds one). The
# wrapping requirement is deliberate, not incidental -- see the golden-good fixture comment
# below for the real false-positive ("... Keep-alive period 20s", a bare unbracketed suffix
# that is genuine check content, not a timing suffix) that a bare-suffix strip would corrupt.
# _pair_displaced_verdicts (stdin -> stdout, ANSI already stripped): T048 restart round-1
# R2-B1. A line that is ONLY a verdict token -- `OK`, `FAIL`, `OK (detail)`, `FAIL: x` -- is the
# displaced verdict of the most recent `...` prompt line that did not itself carry a verdict
# (stderr landed in between). It is re-joined as "<prompt up to and incl. '...'> <verdict line>",
# which VERDICT_RE then matches like any same-line verdict. A bare verdict with no open prompt is
# emitted as "ORPHAN-VERDICT: <line>" -- never dropped -- so it still enters the compared set
# and the real-log self-check below can report it. Every other line passes through unchanged.
_pair_displaced_verdicts() {
  # VERDICT_RE is handed over through ENVIRON, never `awk -v`: -v assignments are
  # escape-processed, which turned its `\.\.\.` into `...` (any three characters).
  VRE="$VERDICT_RE" awk 'BEGIN { vre = ENVIRON["VRE"] }

    /^[[:space:]]*(OK|FAIL)([^A-Za-z0-9]|$)/ {
      v = $0; sub(/^[[:space:]]+/, "", v)
      if (prompt != "") print prompt " " v; else print "ORPHAN-VERDICT: " v
      prompt = ""; next
    }
    {
      if ($0 ~ vre) prompt = ""
      else if (index($0, "...") > 0) prompt = substr($0, 1, index($0, "...") + 2)
      print
    }'
}

extract_verdicts() {
  sed -E 's/\x1b\[[0-9;]*m//g' "$1" \
    | _pair_displaced_verdicts \
    | grep -E "$VERDICT_RE|^ORPHAN-VERDICT: " \
    | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' \
    | sed -E 's/[[:space:]]*[[(][0-9]+(\.[0-9]+)?[[:space:]]*(s|ms|sec)[])][[:space:]]*$//' \
    > "$2"
}

# extract_counters <log> <out> : T048 restart round-1 R2-B1, the SECOND, line-independent
# channel. The pre-build summary block's own counters ("Total tests:", "Passed:", "Failed:",
# "Warnings:", each a full line "<key>: <integer>"), last occurrence of each key, one sorted
# "key=value" line per key; "NONE" when the log has none (a crash before the summary, or a
# truncated log). On the real 20261002T195009Z triplet this channel DID show the FC0b noise
# (Failed 59 vs 58) that the verdict comparison and the exit codes (all 1) could not. This is
# an EQUALITY check across members, not the round-14..20 delta/registry accounting that round
# 21 removed: no subtraction, no registry, no exception list.
extract_counters() {
  sed -E 's/\x1b\[[0-9;]*m//g' "$1" | awk '
    /^[[:space:]]*(Total tests|Passed|Failed|Warnings):[[:space:]]+[0-9]+[[:space:]]*$/ {
      line = $0; sub(/^[[:space:]]+/, "", line); sub(/[[:space:]]+$/, "", line)
      key = line; sub(/:.*/, "", key)
      val = line; sub(/^[^:]*:[[:space:]]+/, "", val)
      last[key] = val
    }
    END { n = 0; for (k in last) { print k "=" last[k]; n++ } if (n == 0) print "NONE" }' | sort > "$2"
}

# T048 round 21 (R20-I1/S11.4.124): _fc_failed_count(),
# _fc_filter_known_flaky(), _fc_known_flaky_hits(),
# _fc_registry_lines_for_id(), _fc_registry_flip_ids(),
# _fc_registry_failcount_delta(), _fc_exit_explained() and
# _fc_truncate_before_summary_tail() -- the registry exact-accounting /
# summary-tail-truncation cascade -- are REMOVED. Each existed only to
# explain away the two registered flaky gates fixed at their own source
# this round; see the ROUND-21 ARCHITECTURE note above section (d) below.

# ============================================================================
# (a) + (b): real baseline capture + determinism of the extraction mechanism
# ============================================================================
if [ -n "$BASELINE_LOG" ]; then
  extract_verdicts "$BASELINE_LOG" "$TMP/baseline_1.txt"
  BASELINE_LINES="$(wc -l < "$TMP/baseline_1.txt" | tr -d ' ')"
  chk "$BASELINE_LABEL verdict set captured from $BASELINE_LOG ($BASELINE_LINES verdict lines)" "$([ "$BASELINE_LINES" -gt 0 ] && echo 1 || echo 0)"
  # (b) used to extract the SAME file twice through a pure sed/grep pipeline and compare the
  # hashes -- a check that cannot fail (T048 restart R2-M1), removed rather than counted as a
  # PASS. In its place, a check that CAN fail: every displaced bare verdict in this real log
  # was paired with a prompt (an ORPHAN means a verdict shape the pairing does not cover).
  _orph="$(grep -c '^ORPHAN-VERDICT: ' "$TMP/baseline_1.txt" || true)"
  chk "every displaced bare verdict in the real baseline was paired with its prompt (${_orph:-0} orphan(s))" "$([ "${_orph:-0}" = 0 ] && echo 1 || echo 0)"

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

# T048 restart R2-B1 (class enumeration): one control needle per verdict SHAPE a real
# pre_build log contains -- each shape below was taken from the real 20261002T195009Z FC0a log
# (ANSI stripped). Every one must come out of extract_verdicts exactly as listed, so a shape the
# extractor silently drops (the displaced-verdict blind spot) is a FAIL here, not a hidden gap.
cat > "$TMP/shapes_in.txt" <<'SHAPES'
  ✓ CM-SHAPE-1: tick verdict line
  ✗ ERROR: CM-SHAPE-2: cross verdict line
  ⚠ WARNING: CM-SHAPE-3: warning verdict line
WARN: CM-SHAPE-4: bare WARN verdict line
  CM-SHAPE-5: same-line prompt... OK
  CM-SHAPE-6: same-line prompt with detail... FAIL (2/3 invariants)
  CM-SHAPE-7: displaced bare verdict... grep: warning: stray \ before -
OK
  CM-SHAPE-8: displaced verdict with detail after two stderr lines... grep: warning: stray \ before x
grep: warning: stray \ before x
OK (4/4 invariants)
  CM-SHAPE-9: prompt then tick on the same line...   ✓ CM-SHAPE-9: tick after prompt
── Section CN-PROBE — not a verdict ──
SHAPES
cat > "$TMP/shapes_want.txt" <<'SHAPES'
✓ CM-SHAPE-1: tick verdict line
✗ ERROR: CM-SHAPE-2: cross verdict line
⚠ WARNING: CM-SHAPE-3: warning verdict line
WARN: CM-SHAPE-4: bare WARN verdict line
CM-SHAPE-5: same-line prompt... OK
CM-SHAPE-6: same-line prompt with detail... FAIL (2/3 invariants)
CM-SHAPE-7: displaced bare verdict... OK
CM-SHAPE-8: displaced verdict with detail after two stderr lines... OK (4/4 invariants)
CM-SHAPE-9: prompt then tick on the same line...   ✓ CM-SHAPE-9: tick after prompt
SHAPES
extract_verdicts "$TMP/shapes_in.txt" "$TMP/shapes_out.txt"
chk "every real verdict shape (9: tick, cross, warning, WARN, same-line OK/FAIL, displaced bare OK, displaced OK-with-detail, prompt+tick) is extracted exactly; a non-verdict banner is not" \
  "$(cmp -s "$TMP/shapes_want.txt" "$TMP/shapes_out.txt" && echo 1 || echo 0)"
cmp -s "$TMP/shapes_want.txt" "$TMP/shapes_out.txt" || diff "$TMP/shapes_want.txt" "$TMP/shapes_out.txt" | head -n 20

# ============================================================================
# (d) the REAL FR-002/T-A01 comparison: FC0a (without timers) vs FC0b
# (without timers) vs FC1 (with timers) of ONE validated same-run triplet.
# Anything else is an honest SKIP.
#
# ROUND-21 ARCHITECTURE (T048 round-20 independent review, R20-I1 --
# S11.4.250 heuristic-tower finding, a SECOND tower found growing on top
# of the log-PAIRING tower the ROUND-6 ARCHITECTURE comment above already
# removed). Rounds 8, 10, 12, 14, 16, 18 and 19 each added ONE MORE layer
# explaining away a SINGLE primitive defect -- a noisy triplet of a flaky
# pre-build suite -- rather than fixing it: noise-floor classification ->
# known-flaky registry filter -> exit-code noise floor -> summary-tail
# truncation -> registry exact-accounting Failed:-N deltas -> nonzero-delta
# clause + member-internal consistency -> unconditional rule ordering + a
# 9-digit bound. The golden test grew 461 -> 1352 lines across those
# rounds, plus ~3300 lines of per-round regression suites -- that shape IS
# the S11.4.250 signal, by the anchor's own definition.
#
# Round 21 removes the PRIMITIVE instead of adding layer N+1: the two
# registered flaky gates this cascade existed to work around --
# CM-SPK512-BRIDGE-SECLABEL-SHELL's printf|grep -qE SIGPIPE race
# (device/rockchip/rk3588/tests/gate_cm_spk512_bridge_seclabel_shell.sh,
# docs/requests/t048_round4_defect1_spk512_bridge_report.md) and
# critical_blocker_gate.sh's CRITIC_IGNORED textual nondeterminism
# (scripts/lib/critical_blocker_gate.sh, docs/requests/
# t048_round4_defect3_cbg_critic_ignored_report.md) -- are now genuinely
# fixed at their own source, each proven via a reverted-mutation stress
# test matching its defect report's own measured flake rate, and both rows
# are removed from known_flaky_gates.tsv, which this same round DELETED
# entirely [T048 round-23 review R23-M2: an earlier revision of this
# comment called the file "now an empty, header-only registry", but the
# SAME round-22 commit that edited this comment block (M3) deleted it --
# it does not exist on disk, empty or otherwise] -- the
# FC_TIMER_GOLDEN_KNOWN_FLAKY_TSV env var, the registry loader, its
# defect-doc/expiry validation and its verdict-line filter are ALL REMOVED
# along with the rest of this cascade: with no remaining registered gate,
# the mechanism has no consumer, and a consumer-less mechanism is exactly
# the dead code S11.4.124 forbids keeping "just in case". A genuinely new,
# independently-confirmed flake would need this designed fresh against
# whatever it actually needs, never resurrected
# unread). With the primitive fixed, the whole explain-away cascade is
# deleted and replaced with the strict rule the round-20 reviewer
# prescribed:
#
#   FC0a vs FC0b (both WITHOUT timers, same run) disagree -- in EITHER
#   their stripped verdict set OR their exit code -- -> this run's OWN
#   noise floor is not clean: SKIP and re-capture. Never silently passed
#   nor failed on; "our own noise floor isn't clean, we can't draw a
#   conclusion" is an honest, explicit outcome, not an error.
#
#   FC0a == FC0b (both WITHOUT timers agree with each other) AND FC1
#   (WITH timers) is byte-identical to them (after the SAME timing-suffix
#   stripping checks (a)-(c) above already validate) AND all three exit
#   codes are equal -> PASS.
#
#   FC0a == FC0b but FC1 differs (verdict set OR exit code) -> FAIL: this
#   is the one shape this run's OWN timer-free noise floor rules out as
#   pre-existing noise -- it is NOT, by itself, proof that fc_timer
#   instrumentation CAUSED the difference (T048 round 22, R22-M2, honest
#   correction: the prior wording here claimed this was "the ONLY shape
#   that constitutes real evidence of an fc_timer-caused difference",
#   which overclaims). Real captured counter-examples: (1) the defect-2
#   report's triplet 20261001T184603Z had both twins fail IDENTICALLY
#   because they shared TMPDIR, with FC1 passing -- a shared-state defect
#   the per-member TMPDIR isolation check above exists to rule out; (2) a
#   re-extracted r4_concurrent_*_20260930T160808Z triplet had matching
#   twins (clean noise floor) while FC1 differed on two gates for reasons
#   UNRELATED to fc_timer. Per-member TMPDIR isolation covers only ONE
#   class of with/without-timers shared state; it is not a guarantee that
#   every remaining FC1-vs-twins difference is fc_timer's doing. Failing
#   is the SAFE direction when the noise floor is clean and FC1 still
#   differs (never silently passed as "probably unrelated"); blaming
#   fc_timer for the difference without debugging the differing gate
#   FIRST is not -- the FAIL message below says so explicitly.
#
# No known-flaky exclusion, no Failed:-N parsing, no summary-tail
# truncation, no registry accounting, no digit bound, no member-internal
# consistency rule, no noise-floor multiset classification: each existed
# ONLY to compensate for the primitive this round fixes, and each is
# deleted in its own commit citing this note and its target gate's defect
# report, per S11.4.124.
# ============================================================================
if [ "$TRIPLET_STATE" = valid ]; then
  extract_verdicts "$WITH_TIMERS_LOG" "$TMP/with_timers.txt"
  WITH_LINES="$(wc -l < "$TMP/with_timers.txt" | tr -d ' ')"
  chk "real 'with timers' verdict set captured from $WITH_TIMERS_LOG ($WITH_LINES verdict lines)" "$([ "$WITH_LINES" -gt 0 ] && echo 1 || echo 0)"

  extract_verdicts "$NOISE_LOG" "$TMP/fc0b.txt"
  FC0B_LINES="$(wc -l < "$TMP/fc0b.txt" | tr -d ' ')"
  chk "real second without-timers ('FC0b') verdict set captured from $NOISE_LOG ($FC0B_LINES verdict lines)" "$([ "$FC0B_LINES" -gt 0 ] && echo 1 || echo 0)"

  # Round 7 (R6-M2): FR-002 says "the verdict set (or commit result)"; the
  # member exit status IS pre_build_verification.sh's commit result.
  _ex0="$(_mf_get member.FC0a.exit "$MANIFEST")"
  _exn="$(_mf_get member.FC0b.exit "$MANIFEST")"
  _ex1="$(_mf_get member.FC1.exit "$MANIFEST")"

  # ---- T048 restart R2-B1: the line-independent summary-counter channel ----
  extract_counters "$BASELINE_LOG" "$TMP/counters_FC0a.txt"
  extract_counters "$NOISE_LOG" "$TMP/counters_FC0b.txt"
  extract_counters "$WITH_TIMERS_LOG" "$TMP/counters_FC1.txt"
  _COUNTERS_READABLE=1
  for _m in FC0a FC0b FC1; do
    if [ "$(cat "$TMP/counters_$_m.txt")" = NONE ]; then
      _COUNTERS_READABLE=0
      chk "member $_m has no readable summary counters (Total tests/Passed/Failed/Warnings) -- a crash before the summary or a truncated log; its result can never be 'equal by absence'" "0"
    fi
  done
  _COUNTERS_EQUAL_0B=1; cmp -s "$TMP/counters_FC0a.txt" "$TMP/counters_FC0b.txt" || _COUNTERS_EQUAL_0B=0
  _COUNTERS_EQUAL_01=1; cmp -s "$TMP/counters_FC0a.txt" "$TMP/counters_FC1.txt" || _COUNTERS_EQUAL_01=0

  # ---- FC0a vs FC0b: is THIS run's own noise floor clean? -----------------
  # Clean = identical verdict set AND identical exit code AND identical summary counters.
  if cmp -s "$TMP/baseline_1.txt" "$TMP/fc0b.txt" && [ "$_ex0" = "$_exn" ] && [ "$_COUNTERS_EQUAL_0B" = 1 ]; then
    _FC0_CLEAN=1
  else
    _FC0_CLEAN=0
  fi

  if [ "$_COUNTERS_READABLE" = 0 ]; then
    : # already FAILed above -- no conclusion is drawn from a member with no summary
  elif [ "$_FC0_CLEAN" -eq 0 ]; then
    DIFF_FC0="$(diff "$TMP/baseline_1.txt" "$TMP/fc0b.txt" 2>/dev/null || true)"
    DIFF_FC0_LINES="$(printf '%s\n' "$DIFF_FC0" | grep -c '^[<>]' || true)"
    skip "FR-002/T-A01: FC0a and FC0b (both WITHOUT timers, same run) disagree -- verdict set $([ -n "$DIFF_FC0" ] && echo "$DIFF_FC0_LINES differing line(s)" || echo identical), exit FC0a=$_ex0 vs FC0b=$_exn, summary counters $([ "$_COUNTERS_EQUAL_0B" = 1 ] && echo identical || echo "FC0a[$(tr '\n' ' ' < "$TMP/counters_FC0a.txt")] vs FC0b[$(tr '\n' ' ' < "$TMP/counters_FC0b.txt")]") -- this run's OWN noise floor is not clean, so no conclusion can be drawn about fc_timer; re-capture ($TRIPLET_REASON)"
    [ -n "$DIFF_FC0" ] && printf '%s\n' "$DIFF_FC0" | head -n 60
  else
    # FC0a == FC0b: this run's own noise floor is clean. The ONLY question
    # left is whether FC1 (WITH timers) is identical too -- in BOTH its
    # verdict set AND its exit code -- each checked and reported on its
    # own, both required for an overall PASS.
    if [ "$_ex0" = "$_ex1" ]; then
      chk "FR-002 commit result: with-timers exit status ($_ex1) equals without-timers exit status ($_ex0) (noise-floor member FC0b also exited $_exn)" "1"
    else
      chk "FR-002 commit result: with-timers exit status ($_ex1) equals without-timers exit status ($_ex0) (noise-floor member FC0b exited $_exn) -- MISMATCH" "0"
    fi

    if [ "$_COUNTERS_EQUAL_01" = 1 ]; then
      chk "FR-002 summary counters identical with vs without timers ($(tr '\n' ' ' < "$TMP/counters_FC1.txt"))" "1"
    else
      chk "FR-002 summary counters identical with vs without timers -- MISMATCH: FC0a[$(tr '\n' ' ' < "$TMP/counters_FC0a.txt")] vs FC1[$(tr '\n' ' ' < "$TMP/counters_FC1.txt")] (a verdict changed that the line-based set could not see -- find the gate before blaming fc_timer)" "0"
    fi

    if cmp -s "$TMP/baseline_1.txt" "$TMP/with_timers.txt"; then
      chk "FR-002/T-A01: with-timers verdict set is IDENTICAL to the without-timers verdict set, byte-for-byte after stripping timing suffixes ($TRIPLET_REASON)" "1"
    else
      DIFF_REAL="$(diff "$TMP/baseline_1.txt" "$TMP/with_timers.txt" 2>/dev/null || true)"
      DIFF_REAL_LINES="$(printf '%s\n' "$DIFF_REAL" | grep -c '^[<>]' || true)"
      chk "FR-002/T-A01: with-timers verdict set is IDENTICAL to the without-timers verdict set, byte-for-byte after stripping timing suffixes ($TRIPLET_REASON) -- MISMATCH, $DIFF_REAL_LINES differing line(s), diff below. The noise floor was clean (FC0a==FC0b), so this difference is real and must not be ignored -- but a clean noise floor does NOT by itself prove fc_timer caused it (T048 R22-M2): DEBUG THE DIFFERING GATE(S) NAMED IN THE DIFF FIRST before attributing this to fc_timer instrumentation" "0"
      printf '%s\n' "$DIFF_REAL" | head -n 60
    fi
  fi
else
  skip "FR-002/T-A01 real with-timers-vs-without-timers comparison: no valid same-run triplet -- ${TRIPLET_REASON:-none found}. Two unrelated captures are never compared."
fi

echo "SUMMARY: $((N - FAIL - SKIPPED)) pass / $FAIL fail / $SKIPPED skip of $N assertions (baseline: $BASELINE_LOG, $BASELINE_LINES verdict lines)"
[ "$FAIL" = 0 ]
