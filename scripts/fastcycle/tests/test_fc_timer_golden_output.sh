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
#   Env FC_TIMER_GOLDEN_KNOWN_FLAKY_TSV=<path> : checked-in known-flaky-gate registry (T048 round 11,
#                                    R10-B1; default $HERE/known_flaky_gates.tsv). A registered gate's
#                                    verdict line is excluded from BOTH sides of the real FR-002/T-A01
#                                    comparison before it runs -- see the KNOWN-FLAKY REGISTRY note
#                                    below. A missing or empty file means no exclusions, never a
#                                    FATAL.
#
# NOISE FLOOR: when the FC0a-vs-FC1 comparison mismatches, every changed line --
#   removed (present without timers only) AND added (present with timers only; T048 round-5 R5-I3,
#   the pre-fix classifier was blind to added lines) -- is checked against the SAME-direction
#   change in FC0a-vs-FC0b. A line that also changes between two timer-free members of the same
#   run is pre-existing noise. A line that does not is reported as "not explained by this ONE noise
#   sample", never as "fc_timer-attributable": one noise pair cannot separate a timer effect from a
#   rare flake (T048 round-5 m4). T048 round 8/9 (R8-B1) made this classification LOAD-BEARING, not
#   diagnostic-only as this comment used to (wrongly) claim: a mismatch FULLY explained by this run's
#   own noise floor (not_explained=0) is an honest SKIP of the comparison (rc=0), never the
#   unconditional FAIL this file printed before round 8. (Round 11, R10-M1: the stale "NEVER changes
#   the strict verdict" claim above was corrected to match that fact.)
#
# KNOWN-FLAKY REGISTRY (T048 round 11, R10-B1): a flaky, fc_timer-UNRELATED parent-repo gate can land
#   in ANY member -- FC0a, FC0b, or FC1 (round 8's own table shows all three) -- but the noise floor
#   above can only explain a deviation confined to a change the SAME-direction FC0a-vs-FC0b noise
#   pair also shows; the SAME real flake landing in FC1 instead (never touching FC0a or FC0b) still
#   produced an unconditional FAIL even after round 8/9's fix (reproduced by the round-10 reviewer,
#   fixed this round). Before any comparison runs, every verdict line whose leading "<GATE-ID>: "
#   token (a WARN:/ERROR: prefix is stripped first) EXACTLY matches a gate id registered in
#   known_flaky_gates.tsv (Env FC_TIMER_GOLDEN_KNOWN_FLAKY_TSV=<path>, default
#   $HERE/known_flaky_gates.tsv; consumer DATA per S11.4.35, every entry tied to a tracked defect
#   report) is EXCLUDED from BOTH sides of the comparison entirely -- its own verdict is simply not
#   considered, so the REST of the comparison decides pass/fail, exactly as for every other gate.
#   This is NOT a blanket loophole: only the exact, checked-in, defect-tied gate ids on the registry
#   are ever excluded; any other gate's deviation is still handled exactly as before (noise-floor
#   SKIP if fully explained, FAIL otherwise).
#
# SUMMARY-TAIL + EXIT-CODE CASCADE (T048 round 12, R12-I1): the KNOWN-FLAKY REGISTRY above only
#   excludes a registered gate's OWN verdict line; the round-11 reviewer proved it does not reach
#   the two DERIVED surfaces the real pre_build_verification.sh also moves the moment ANY single
#   gate's status flips -- (1) that member's own EXIT CODE (0 on $ERRORS==0, else 1), and (2) the
#   final summary-verdict BLOCK: the SUCCESS branch's one-time banner
#   "  \xe2\x9c\x93 ALL MANDATORY CHECKS PASSED" followed by dozens of informational
#   "\xe2\x9c\x93 ..." lines, wholesale REPLACED in the FAILURE branch by
#   "  \xe2\x9c\x97 PRE-BUILD VERIFICATION FAILED" + a short error count (verified at
#   device/rockchip/rk3588/tests/pre_build_verification.sh:51121 and :51477, each occurring
#   EXACTLY ONCE in that file). On a parent tree that is ALREADY red (constant exit=1 + constant
#   FAILED banner everywhere) neither surface ever moves and the gap is invisible; the FIRST green
#   tree with a registered flake confined to exactly one member reproduces the R10-B1 FC1-side
#   false FAIL on these two surfaces, unchanged by round 11's own fix.
#   Fix (this round): (a) EXIT CODE -- _fc_registry_flip_ids() (below) answers "does ANY registered
#   gate's own recorded line genuinely differ between these two EXACT members" (computed from the
#   RAW, unfiltered extracted logs, independent of _fc_filter_known_flaky()'s own output files); when
#   it does, an exit-code divergence neither trivially equal nor noise-floor-explained is SKIPped as
#   registry-explained, mirroring (never replacing) the noise-floor elif immediately above it. (b)
#   SUMMARY TAIL -- the tail printed AFTER either one-time banner line is a DETERMINISTIC function of
#   that SAME exit/commit-result bit. (T048 round 14, m1 -- corrected: the banner line is the LAST
#   thing either branch prints TO STDOUT TODAY, not unconditionally the last thing either branch
#   prints at all -- pre_build_verification.sh:51474/:51482 call _fc_section_close_final() ->
#   fc_timer_end() strictly AFTER the banner, and MEASURED (every echo in fc_timer_end() checked, not
#   assumed, S11.4.6), its own output is `>&2`-only / a file-append to FC_TIMER_TSV, NEVER stdout, so it
#   never matches VERDICT_RE and has zero live effect on this truncation today. A future fc_timer
#   change that ever printed a stdout verdict-shaped line there would silently truncate it away; this
#   note exists so that change is reviewed against this truncation, not surprised by it.) Both
#   extracted+filtered verdict sets are TRUNCATED at (and excluding) the first line matching
#   SUMMARY_TAIL_RE below -- a FULL-LINE anchor against the real, unique banner text (consumer-
#   overridable, Env FC_TIMER_GOLDEN_SUMMARY_TAIL_RE=<ERE>, per S11.4.35) -- BEFORE the strict/noise-
#   floor comparison, never after. This is NOT a blanket loophole either: truncation only removes the
#   trailing, provably-redundant banner block; every PER-GATE check line (registered or not) is printed
#   strictly BEFORE that banner in the real script and is therefore NEVER truncated, so an unregistered
#   gate failing in the SAME member as a registered flake is still caught by the (untruncated,
#   unfiltered-for-its-own-id) verdict-set comparison below -- it is simply no longer ALSO drowned in
#   hundreds of now-irrelevant summary-tail diff lines.
#
# EXACT-ACCOUNTING EXIT-CODE EXPLANATION + OK/FAIL-STYLE VERDICT BLIND SPOT (T048 round 14, R14-I1 +
#   R14-I2): round 13's exit-code elif above answered "does ANY registered gate's own recorded line
#   genuinely differ between these two EXACT members" -- but it never checked that the registered
#   flip(s) actually ACCOUNT FOR the full ERRORS delta, nor their direction. Reproduced (round-14
#   reviewer, ADV1): a member carrying BOTH a registered flake AND a genuine, unrelated OK/FAIL-style
#   regression produced a false overall PASS, because (a) ANY registered-line difference, in EITHER
#   direction and of ANY magnitude, unconditionally SKIPped the whole exit-code divergence, and (b)
#   VERDICT_RE='(\xe2\x9c\x93|\xe2\x9c\x97|WARN:|ERROR:)' never matched the ~640-per-real-run
#   "<GATE-ID>: ... OK" / "<GATE-ID>: ... FAIL[:]" lines 670 direct `ERRORS=$((ERRORS+1))` sites print
#   (confirmed: a real captured log has exactly 640 such lines, zero of them extracted) nor the real
#   "WARNING:" text log_warn() prints (the old pattern's literal "WARN:" never occurs in the shipped
#   script -- confirmed by direct grep, 1 hit and it is inside an unrelated grep pattern, not a printed
#   verdict), so neither the verdict-SET comparison nor this exit-code elif could ever see those lines
#   change at all. Fix: (R14-I2) VERDICT_RE now also matches the real OK/FAIL-style shape (a line
#   containing "... " immediately followed by the word OK or FAIL, word-bounded so "OKAY"/"FAILURE"
#   never false-match -- MEASURED against a real captured log to match EXACTLY the reviewer's cited 640
#   lines, no more, no fewer) and the real "WARNING:" text (kept alongside the harmless, never-matching
#   legacy "WARN:" literal for any external caller that genuinely emits it). (R14-I1) the exit-code elif
#   no longer asks "did ANY registered line change"; it reads the real "  Failed:       N" summary line
#   (pre_build_verification.sh:51115, printed BEFORE either banner, counting every ERRORS increment of
#   EITHER style, verified to occur exactly once in that file) from BOTH raw members via
#   _fc_failed_count(), computes the registered gate(s)' own NET failure-class delta via
#   _fc_registry_failcount_delta() (gained-minus-lost, from the SAME raw files _fc_registry_lines_for_id
#   already reads), and SKIPs as registry-explained ONLY when the two deltas are EXACTLY equal (same
#   sign, same magnitude) AND nonzero -- a mismatch of either kind, or an unresolvable "Failed:" line in
#   either member (the conservative-safe default, S11.4.101/S11.4.201), falls straight through to the
#   existing hard FAIL, never silently explained away. _fc_registry_flip_ids() (any-textual-difference)
#   is kept ONLY to name which registered id(s) are implicated in the SKIP message -- it no longer gates
#   the decision.
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

# T048 round 11 (R10-B1): checked-in known-flaky-gate registry, consumer DATA
# per S11.4.35. Every entry MUST be tied to a tracked defect report -- this is
# NOT a general-purpose "ignore any gate that failed once" escape hatch. A
# missing or empty file means no exclusions (never a FATAL): a fresh checkout
# with no registry yet behaves exactly like round 9.
KNOWN_FLAKY_TSV="${FC_TIMER_GOLDEN_KNOWN_FLAKY_TSV:-$HERE/known_flaky_gates.tsv}"

# T048 round 12 (R12-I1): the real pre_build_verification.sh's ONE-TIME terminal summary banner
# (device/rockchip/rk3588/tests/pre_build_verification.sh:51121,:51477 -- each occurring exactly
# once, verified at the time of this fix) -- see the SUMMARY-TAIL + EXIT-CODE CASCADE note above.
# A full-line anchor (never a substring match, S11.4.201(7)(a)) against the post-extract_verdicts
# (ANSI-stripped, trimmed, timing-suffix-stripped) form of either banner line. Consumer DATA per
# S11.4.35: a project whose own commit-path script prints a differently-worded terminal banner
# overrides this.
SUMMARY_TAIL_RE="${FC_TIMER_GOLDEN_SUMMARY_TAIL_RE:-^(✓ ALL MANDATORY CHECKS PASSED|✗ PRE-BUILD VERIFICATION FAILED)$}"
# T048 round 14 (m3): an invalid override silently DISABLED truncation
# before this round (grep -E's own syntax error went to 2>/dev/null, and
# the resulting empty match-line is indistinguishable, downstream, from a
# genuine "no match" -- the SAME safe fallback (an exact copy, never a
# corrupted one) still applies either way, but the misconfiguration was
# invisible). MEASURED, not assumed (S11.4.6): `grep -E` exits 2 on a
# syntactically invalid ERE, 1 on a genuine no-match, 0 on a match -- a
# single early check here reports the misconfiguration ONCE, loudly,
# rather than leaving every one of _fc_truncate_before_summary_tail()'s 3
# per-run callers silently swallow it.
printf '' | grep -qE -- "$SUMMARY_TAIL_RE" >/dev/null 2>&1
_fc_summary_tail_re_rc=$?
if [ "$_fc_summary_tail_re_rc" -gt 1 ]; then
  echo "WARN: FC_TIMER_GOLDEN_SUMMARY_TAIL_RE='$SUMMARY_TAIL_RE' is not a syntactically valid extended regular expression (grep -E exit $_fc_summary_tail_re_rc) -- summary-tail truncation is DISABLED (treated as an exact copy, never a silent corruption) until a valid ERE is supplied (T048 round 14, m3)"
fi

# _fc_valid_iso_date DATE -- true (rc 0) only when DATE is BOTH shaped like
# YYYY-MM-DD AND a REAL calendar date, round-tripped through `date -u -d`
# (T048 round 14, m3: the pre-round-14 shape-only regex accepted
# calendrically-impossible values like "2026-99-99" -- MEASURED, not
# assumed, S11.4.6: `date -u -d` rejects both a malformed string and a
# shape-valid-but-impossible one, exiting 1 either way, and a VALID date's
# own `+%F` output round-trips byte-for-byte).
_fc_valid_iso_date() {
  printf '%s' "$1" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || return 1
  [ "$(date -u -d "$1" +%F 2>/dev/null)" = "$1" ]
}

# T048 round 14 (m3): FC_TIMER_GOLDEN_TODAY, when explicitly set, MUST be a
# real calendar date -- a malformed value (e.g. "0000-00-00") used to
# silently disable expiry-checking for EVERY known_flaky_gates.tsv row
# (every `[ "$expires" \< "$today" ]` comparison would then compare against
# a string no real expiry date is ever less than). FATAL, matching
# FC_TIMER_GOLDEN_MAX_WINDOW_S's own discipline above: this is a global
# knob, never silently defaulted away. The unset/default case
# ($(date -u +%F), used inside _fc_build_valid_known_flaky_tsv() below) is
# always valid and never reaches this check.
if [ -n "${FC_TIMER_GOLDEN_TODAY:-}" ] && ! _fc_valid_iso_date "$FC_TIMER_GOLDEN_TODAY"; then
  echo "FATAL: FC_TIMER_GOLDEN_TODAY='$FC_TIMER_GOLDEN_TODAY' is not a real YYYY-MM-DD calendar date"
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

# T048 round 12 (R12-M2): KNOWN_FLAKY_TSV's own header text claims "each
# entry tied to a tracked defect", but nothing used to verify that -- a row
# with an EMPTY reason/defect_doc, or one citing a defect_doc that does not
# exist, was honoured exactly like a real, documented row (reproduced by the
# round-12 reviewer, fixed this round). A permanent gate-exclusion is an
# allow-with-known-debt path; S11.4.271 (rostered authoriser + MANDATORY
# UNELAPSED EXPIRY + a tracked item) and S11.4.248(A) (flaky-test quarantine
# with a stabilisation deadline) both expect exactly this shape. This narrow,
# internal test-tooling registry implements the PART both anchors share --
# a non-empty reason, an EXISTING defect_doc, and a non-elapsed ISO expiry
# date (closed format YYYY-MM-DD; Env FC_TIMER_GOLDEN_TODAY=<date> overrides
# "today" for deterministic testing) -- never the full rostered-authoriser or
# live tracked-item-open-query machinery those anchors also require (S11.4.6
# honest boundary: this file has no DB access and does not claim to check
# whether a cited tracked item is still open, only that a date has not
# elapsed). A row failing ANY of these three checks is REFUSED -- treated
# exactly as though that gate id were never registered at all, never
# silently honoured -- and the refusal is reported (never a silent drop).
# Resolved ONCE into a validated, header-preserving subset file every other
# helper in this section reads INSTEAD OF $KNOWN_FLAKY_TSV directly, so the
# EXISTING simple column-1 awk logic in _fc_filter_known_flaky() and
# _fc_known_flaky_hits() (and _fc_registry_flip_ids() below) needs no
# file-existence/date logic of its own.
KNOWN_FLAKY_TSV_VALID="$TMP/known_flaky_valid.tsv"
_fc_build_valid_known_flaky_tsv() {
  printf 'gate_id\treason\tdefect_doc\texpires\n' > "$KNOWN_FLAKY_TSV_VALID"
  [ -s "$KNOWN_FLAKY_TSV" ] || return 0
  local today="${FC_TIMER_GOLDEN_TODAY:-$(date -u +%F)}" gid reason doc expires
  # MEASURED (never assumed, S11.4.6): `IFS=$'\t' read -r a b c d` COALESCES
  # a run of adjacent TABs into ONE delimiter and strips the field between
  # them, because TAB is classified as "IFS white space" for bash `read`
  # regardless of which characters IFS is actually set to -- a genuinely
  # EMPTY middle field (the exact R12-M2 "empty reason" shape) silently
  # SHIFTS every later field left by one (verified: piping
  # `printf 'a\t\tc\td\n'` through `IFS=$'\t' read -r f1 f2 f3 f4` gives
  # f1=a f2=c f3=d f4=(empty), NOT the f2=(empty) f3=c f4=d an honest split
  # requires). `awk -F'\t'` does NOT coalesce (confirmed on the SAME input:
  # f1=a f2=(empty) f3=c f4=d), so the TAB->awk split happens there, then is
  # re-joined on a NON-whitespace delimiter (ASCII Unit Separator, \x1f)
  # that `read` does not coalesce either (confirmed the same way) before
  # bash ever field-splits it -- a S11.4.201(7)(c) "the path is part of the
  # instrument" instance, found by actually running this fix's own tests,
  # not assumed.
  while IFS=$'\x1f' read -r gid reason doc expires; do
    [ -n "$gid" ] || continue
    if [ -z "$reason" ]; then
      echo "WARN: known_flaky_gates.tsv row '$gid' has an EMPTY reason -- refused (treated as unregistered), never silently honored (T048 round 12, R12-M2)"
      continue
    fi
    if [ -z "$doc" ] || [ ! -f "$ROOT/$doc" ]; then
      echo "WARN: known_flaky_gates.tsv row '$gid' has defect_doc='$doc', which does not exist at ${ROOT}/${doc} -- refused (treated as unregistered), never silently honored (T048 round 12, R12-M2)"
      continue
    fi
    # T048 round 14 (m3): shape-only was insufficient -- "2026-99-99" matched
    # the old regex but is not a real calendar date; _fc_valid_iso_date()
    # (defined near the top of this file) round-trips through `date -u -d`
    # to catch that, not merely its shape.
    if ! _fc_valid_iso_date "$expires"; then
      echo "WARN: known_flaky_gates.tsv row '$gid' has expires='$expires', not a YYYY-MM-DD date (checked against the real calendar -- not merely its shape -- T048 round 14, m3) -- refused (treated as unregistered), never silently honored (T048 round 12, R12-M2)"
      continue
    fi
    if [ "$expires" \< "$today" ]; then
      echo "WARN: known_flaky_gates.tsv row '$gid' expired on $expires (today is $today) -- refused (treated as unregistered) until its expiry is renewed (T048 round 12, R12-M2)"
      continue
    fi
    printf '%s\t%s\t%s\t%s\n' "$gid" "$reason" "$doc" "$expires" >> "$KNOWN_FLAKY_TSV_VALID"
  # T048 round 14 (m4): row 1 is skipped ONLY when it is the LITERAL known
  # header "gate_id" in column 1 (the exact string this function's own
  # header printf above writes) -- a registry file with NO header line,
  # whose first row is real data, used to be silently dropped
  # unconditionally (NR > 1), contradicting this file's own "never a
  # silent drop" discipline; a genuine header is still always skipped.
  done < <(awk -F'\t' 'BEGIN { OFS="\x1f" } NR == 1 && $1 == "gate_id" { next } { print $1, $2, $3, $4 }' "$KNOWN_FLAKY_TSV")
}
_fc_build_valid_known_flaky_tsv

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
# 1614, by direct grep, not a subset), immediately followed (no intervening stdout output) by a
# bare `OK` or `FAIL` token, optionally followed by `:`/a space/end-of-line and trailing detail text
# -- so "... " immediately followed by OK or FAIL, with the NEXT character (if any) NOT a letter or
# digit (the word-boundary guard so "OKAY"/"FAILURE" could never false-match, even though neither
# occurs in this script today), is the real, exact shape. MEASURED, not assumed (S11.4.6): this
# exact pattern matches 640 lines in a real captured log (qa-results/fastcycle/us1/red/T015/
# prebuild_with_timers_full_run_20260930T152954Z.log) -- precisely the round-14 reviewer's own cited
# count, confirmed by an independent re-count against the SAME log, with zero false positives (a
# "... OK Apps, Kodi, Codecs ..." SECTION-TITLE line, and two stderr-interleaving-corrupted bare
# "OK" lines with no "... " precursor at all, are all correctly excluded). Banner/section lines
# never carry any of these shapes.
VERDICT_RE='(✓|✗|WARN:|ERROR:|WARNING:|\.\.\.[[:space:]]+(OK|FAIL)([^A-Za-z0-9]|$))'

# FAIL_CLASS_RE (T048 round 14, R14-I1): the FAILING-class subset of VERDICT_RE -- a log_fail()-style
# '✗'/'ERROR:' line, or the FAIL half of the OK/FAIL-style shape above. Deliberately excludes
# 'WARNING:' (log_warn() increments WARNINGS, never ERRORS, so a WARN line can never move the real
# script's "Failed: N" count or exit code) and the OK half (never a failure). Used by
# _fc_registry_failcount_delta() below to classify a registered gate's own line as failing or not,
# from the SAME raw extracted files VERDICT_RE already produced. T048 round 16 (R16-M3): anchored to
# the VERDICT-TOKEN POSITION -- immediately after the "<description>... " check-description-prompt
# prefix every real check line uses (the SAME "\.\.\.[[:space:]]+" anchor VERDICT_RE's own OK/FAIL
# alternative already uses) -- never a bare substring match anywhere in the line
# (S11.4.201(7)(a)). The pre-round-16 unanchored form matched '✗'/'ERROR:' at ANY position, so a
# registered gate's own PASSING message whose detail text happened to CONTAIN the substring
# 'ERROR:' or '✗' (e.g. "...   ✓ ok (no ERROR: found, previously a ✗ issue)") would be misclassified
# as failing -- a carrier false-match, never observed in the two gates registered today (MEASURED,
# not assumed, S11.4.6: every real/fixture ✗/ERROR:/FAIL verdict line used anywhere in this file's
# own regression suites, T048 rounds 4-16, places the token immediately after "... ", confirmed by
# direct grep across every *_r*_regression.sh fixture constant), bounded conservative-only (a false
# FAIL, never a false explanation, per the round-16 review) but now closed at the source instead.
FAIL_CLASS_RE='\.\.\.[[:space:]]+(✗|ERROR:|FAIL([^A-Za-z0-9]|$))'

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

# _fc_failed_count LOG -- the integer value of the real pre_build_verification.sh
# "  Failed:       N" summary line (pre_build_verification.sh:51115, printed BEFORE
# either terminal banner, counting EVERY ERRORS increment of either style -- see the
# EXACT-ACCOUNTING note near the top of this file), ANSI-stripped, FULL-LINE anchored
# (never a substring match, S11.4.201(7)(a)) so a log_fail() message that happens to
# CONTAIN the substring "Failed:" as part of its own text can never be mistaken for
# the summary line. Prints nothing and returns 1 when the line is absent, malformed,
# or occurs more than once in LOG (ambiguous -- never resolved by picking one,
# mirroring _mf_get()'s own discipline); callers (T048 round 14, R14-I1) treat an
# unresolvable count as "cannot explain", the conservative-safe default
# (S11.4.101/S11.4.201), never as zero. T048 round 16 (R16-M2): the printed
# value is ALSO stripped of any leading zero(s) (down to a single "0", never
# an empty string) BEFORE it reaches the caller -- a literal "08" is SHAPE-
# valid per the capture group's own [0-9]+ above, but every caller does bash
# arithmetic on this value (e.g. "$((n1 - n0))"), and bash's $((...)) treats
# ANY numeral beginning with "0" (other than the single digit "0" itself) as
# an OCTAL literal, so "08" fails that ONE arithmetic expansion with "value
# too great for base" -- MEASURED, not assumed (S11.4.6), and precisely
# characterized (never overstated): when that failing expansion sits inside
# an enclosing `if`/compound construct (as every real caller's does), bash
# does NOT merely skip that one assignment and continue on the NEXT line --
# it silently abandons the REST of that ENTIRE enclosing compound block and
# resumes execution at the first statement AFTER its closing `fi`, with no
# further checks in between ever running (confirmed live with `bash -x` on
# this exact file: tracing a real triplet carrying an unstripped "08" jumps
# directly from the failing "$((...))" line to this script's own final
# "SUMMARY: ..." echo, skipping EVERY downstream check -- member-
# consistency, exit-code, verdict-set -- between them). The net effect is
# worse than a hard crash: the run reports a FALSE PASS (rc=0, a truncated
# "N pass / 0 fail" SUMMARY with fewer assertions than a clean run would
# have recorded) precisely BECAUSE the checks that would have caught a real
# problem never executed -- exactly the silent-skip-as-false-PASS shape the
# anti-bluff covenant forbids. The real pre_build_verification.sh prints
# $ERRORS with no leading zeros today, so this has NO live impact -- it is
# fixed at THIS single source so every caller (today's one arithmetic site
# and any future one) inherits an already-decimal-safe value, never a
# `10#$N` base-forcing discipline each call site would otherwise have to
# remember.
_fc_failed_count() {
  local hits raw
  hits="$(sed -E 's/\x1b\[[0-9;]*m//g' "$1" 2>/dev/null | grep -cE '^[[:space:]]*Failed:[[:space:]]+[0-9]+[[:space:]]*$' || true)"
  [ "${hits:-0}" = "1" ] || return 1
  raw="$(sed -E 's/\x1b\[[0-9;]*m//g' "$1" | sed -nE 's/^[[:space:]]*Failed:[[:space:]]+([0-9]+)[[:space:]]*$/\1/p')"
  printf '%s' "$raw" | sed -E 's/^0+([0-9])/\1/'
}

# _fc_filter_known_flaky IN OUT -- copies IN to OUT, dropping any verdict
# line whose leading "<GATE-ID>: " token (a WARN:/ERROR: prefix is stripped
# first, matching VERDICT_RE) is an EXACT match for a gate id registered in
# KNOWN_FLAKY_TSV_VALID (T048 round 12, R12-M2: the VALIDATED subset --
# non-empty reason, existing defect_doc, non-elapsed expiry -- see the note
# above KNOWN_FLAKY_TSV_VALID's own definition near the top of this file;
# never the raw $KNOWN_FLAKY_TSV). No registry file, or an empty one, means
# OUT is an exact copy of IN -- never a FATAL (T048 round 11, R10-B1).
_fc_filter_known_flaky() {
  local in="$1" out="$2"
  if [ -s "$KNOWN_FLAKY_TSV_VALID" ]; then
    awk -F'\t' '
      FNR == NR { if (FNR > 1 && $1 != "") ids[$1] = 1; next }
      { line = $0; gid = line
        sub(/^WARN: /, "", gid); sub(/^ERROR: /, "", gid)
        sub(/:.*/, "", gid)
        if (!(gid in ids)) print line }
    ' "$KNOWN_FLAKY_TSV_VALID" "$in" > "$out"
  else
    cp "$in" "$out"
  fi
}

# _fc_known_flaky_hits IN -- prints (one per line, de-duplicated) the
# registered gate id of every line _fc_filter_known_flaky would remove from
# IN. Used only for the honest INFO/PASS annotation below -- never for the
# filtering decision itself, which _fc_filter_known_flaky alone makes.
_fc_known_flaky_hits() {
  [ -s "$KNOWN_FLAKY_TSV_VALID" ] || return 0
  awk -F'\t' '
    FNR == NR { if (FNR > 1 && $1 != "") ids[$1] = 1; next }
    { gid = $0
      sub(/^WARN: /, "", gid); sub(/^ERROR: /, "", gid)
      sub(/:.*/, "", gid)
      if (gid in ids) print gid }
  ' "$KNOWN_FLAKY_TSV_VALID" "$1" | sort -u
}

# _fc_registry_lines_for_id FILE ID -- prints every line in FILE (a raw,
# UNFILTERED extracted verdict file) whose leading gate-id token (the same
# WARN:/ERROR:-stripped, colon-truncated extraction _fc_filter_known_flaky
# and _fc_known_flaky_hits already use) exactly equals ID. (T048 round 12,
# R12-I1.)
_fc_registry_lines_for_id() {
  awk -v id="$2" '
    { gid = $0
      sub(/^WARN: /, "", gid); sub(/^ERROR: /, "", gid)
      sub(/:.*/, "", gid)
      if (gid == id) print }
  ' "$1"
}

# _fc_registry_flip_ids FILE_A FILE_B -- prints a comma-joined, de-duplicated
# list of every KNOWN_FLAKY_TSV-registered gate id whose OWN recorded line(s)
# in FILE_A genuinely differ (by exact text -- present-vs-absent, a different
# verdict sign, or any other change) from its own recorded line(s) in FILE_B.
# Empty when the registry is missing/empty, or when every registered id that
# appears in either file is byte-identical between the two. T048 round 14
# (R14-I1): this ANY-textual-difference signal is NO LONGER what GATES the
# exit-code explanation below (see _fc_registry_failcount_delta() and the
# EXACT-ACCOUNTING note near the top of this file for why -- it could not
# tell a fully-explained divergence from a merely-coincident one). It is kept
# PURELY to name, in the SKIP message, which registered id(s) are implicated
# -- a diagnostic convenience, never a decision input; an id this function
# reports as "flipped" (even cosmetically, e.g. a detail-text-only change
# that never crosses the FAIL_CLASS_RE boundary) contributes nothing to the
# actual accounting.
_fc_registry_flip_ids() {
  [ -s "$KNOWN_FLAKY_TSV_VALID" ] || return 0
  local id a b out=""
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    a="$(_fc_registry_lines_for_id "$1" "$id")"
    b="$(_fc_registry_lines_for_id "$2" "$id")"
    [ "$a" = "$b" ] && continue
    case ",$out," in *",$id,"*) ;; *) out="${out:+$out,}$id" ;; esac
  done < <(awk -F'\t' 'FNR > 1 && $1 != "" { print $1 }' "$KNOWN_FLAKY_TSV_VALID")
  printf '%s' "$out"
}

# _fc_registry_failcount_delta FILE_A FILE_B -- the NET integer count of
# KNOWN_FLAKY_TSV-registered gate ids that GAINED a FAIL_CLASS_RE-matching
# (failing-class) verdict in FILE_B relative to FILE_A, MINUS the count that
# LOST one -- i.e. sum over every registered id of
# (1 if failing-class-in-B-but-not-A) - (1 if failing-class-in-A-but-not-B).
# An id whose own line changed WITHOUT crossing the failing-class boundary in
# EITHER direction (e.g. a cosmetic detail-text edit, or a non-failing-to-
# non-failing change) contributes 0, by construction: this is the exact
# per-id accounting _fc_registry_flip_ids() above cannot do (it reports ANY
# textual difference, with no notion of direction or magnitude -- the exact
# gap the round-14 reviewer's ADV1/ADV2 fixtures exploited). Prints 0 when
# the registry is missing/empty. Computed from the SAME raw, unfiltered
# extracted files _fc_registry_lines_for_id() already reads (T048 round 14,
# R14-I1).
_fc_registry_failcount_delta() {
  [ -s "$KNOWN_FLAKY_TSV_VALID" ] || { printf '0'; return 0; }
  local id a b a_fail b_fail delta=0
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    a="$(_fc_registry_lines_for_id "$1" "$id")"
    b="$(_fc_registry_lines_for_id "$2" "$id")"
    if printf '%s\n' "$a" | grep -qE "$FAIL_CLASS_RE"; then a_fail=1; else a_fail=0; fi
    if printf '%s\n' "$b" | grep -qE "$FAIL_CLASS_RE"; then b_fail=1; else b_fail=0; fi
    delta=$((delta + b_fail - a_fail))
  done < <(awk -F'\t' 'FNR > 1 && $1 != "" { print $1 }' "$KNOWN_FLAKY_TSV_VALID")
  printf '%s' "$delta"
}

# _fc_exit_explained N0 N1 REG_DELTA -- prints "1" if (and only if) the
# member Failed-count delta (N1 - N0, both already decimal-safe per
# _fc_failed_count()'s own R16-M2 fix) is BOTH resolvable AND NONZERO AND
# EXACTLY equal to REG_DELTA; "0" otherwise (including when either N0 or N1
# is unresolvable/empty -- the conservative-safe default, S11.4.101/
# S11.4.201, never silently treated as zero). T048 round 14 (R14-I1) /
# round 16 (R16-I2): the delta MUST be nonzero -- a genuine 0==0 "match" is
# NEVER a registry explanation, because there was no real divergence to
# explain in the first place (round-15's own golden_mutNZ.sh reviewer
# mutation, which drops only this "!= 0" requirement, reproduces exactly
# that false explanation). Deliberately ISOLATED into its own, directly-
# callable function (round 16, R16-I2) rather than left inline: once the
# member-internal-consistency precondition below (_fc_check_member_
# consistency, R16-I1) holds for both members whose Failed count is
# resolvable, a differing-exit-but-delta==0 scenario becomes structurally
# UNREACHABLE through the full three-member golden-triplet harness (proof:
# consistency forces exit = (Failed != 0), so N0 == N1 forces _ex0 == _ex1,
# contradicting the "exits differ" precondition this elif is reached
# under) -- so this clause's own removal can no longer be demonstrated via
# an end-to-end triplet fixture once R16-I1 ships alongside it, ONLY via a
# DIRECT call to this function in isolation (see the dedicated chk()
# assertions near the bottom of this file). The clause is kept regardless
# (defense-in-depth, matching round 15's original intent, option (a) of
# the round-16 ruling) since a future change to the consistency check's own
# scope could make this clause reachable again, and it costs nothing to
# retain.
_fc_exit_explained() {
  local n0="$1" n1="$2" reg="$3" delta
  [ -n "$n0" ] && [ -n "$n1" ] || { printf 0; return 0; }
  delta=$((n1 - n0))
  if [ "$delta" != 0 ] && [ "$delta" = "$reg" ]; then printf 1; else printf 0; fi
}

# _fc_truncate_before_summary_tail IN OUT -- copies IN to OUT up to (not
# including) the FIRST line that exactly matches SUMMARY_TAIL_RE. No match
# means OUT is an exact copy of IN (T048 round 12, R12-I1 -- see the
# SUMMARY-TAIL + EXIT-CODE CASCADE note near the top of this file). Resolved
# via grep -nE + head, never a dynamic awk ERE, so a multi-alternative regex
# with '|' cannot fall victim to the S11.4.201(7)(c) dialect footgun class.
_fc_truncate_before_summary_tail() {
  local in="$1" out="$2" ln
  ln="$(grep -nE -- "$SUMMARY_TAIL_RE" "$in" 2>/dev/null | head -n1 | cut -d: -f1)"
  if [ -n "$ln" ] && [ "$ln" -gt 1 ]; then
    head -n "$((ln - 1))" "$in" > "$out"
  elif [ "$ln" = 1 ]; then
    : > "$out"
  else
    cp "$in" "$out"
  fi
}

# ============================================================================
# (a) + (b): real baseline capture + determinism of the extraction mechanism
# ============================================================================
if [ -n "$BASELINE_LOG" ]; then
  extract_verdicts "$BASELINE_LOG" "$TMP/baseline_1.txt"
  extract_verdicts "$BASELINE_LOG" "$TMP/baseline_2.txt"
  BASELINE_LINES="$(wc -l < "$TMP/baseline_1.txt" | tr -d ' ')"
  chk "$BASELINE_LABEL verdict set captured from $BASELINE_LOG ($BASELINE_LINES verdict lines)" "$([ "$BASELINE_LINES" -gt 0 ] && echo 1 || echo 0)"

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

  # Round 7 (R6-M2): FR-002 says "the verdict set (or commit result)"; the
  # member exit status IS pre_build_verification.sh's commit result.
  _ex0="$(_mf_get member.FC0a.exit "$MANIFEST")"; _ex1="$(_mf_get member.FC1.exit "$MANIFEST")"
  _exn="$(_mf_get member.FC0b.exit "$MANIFEST")"
  # T048 round 11 (R10-I1): this exit-status check had no noise-floor
  # treatment at all, so a flaky gate affecting only FC0a's exit status --
  # the exact R8-B1 mechanism, applied to a member's own exit code instead
  # of a verdict LINE -- still produced a hard FAIL even on a run the
  # verdict-set check below correctly SKIPs as fully noise-explained.
  # Mirrors the SAME "explained by this run's own FC0a-vs-FC0b noise floor"
  # discipline the verdict-set comparison uses: the exit-code divergence is
  # noise-explained only when FC0b's exit ALSO differs from FC0a's AND
  # lands on the EXACT SAME value FC1 recorded -- the same "same-direction,
  # exact-match" rule _fc_classify_against() applies to verdict lines,
  # applied here to a single scalar.
  # T048 round 12 (R12-I1), SUPERSEDED this round (R14-I1 -- see the EXACT-
  # ACCOUNTING note near the top of this file): _FC_EXIT_FLIP_IDS (any
  # registered id whose own line textually differs AT ALL, in either
  # direction, of any magnitude) is now PURELY diagnostic naming for the
  # SKIP message below -- it never gates the decision. The decision reads
  # the real "Failed: N" summary count from BOTH raw members
  # (_fc_failed_count(), BEFORE the known-flaky filtering below, independent
  # of it and of _FCF_HITS further down) and the registered gate(s)' own NET
  # failing-class delta (_fc_registry_failcount_delta()), and explains the
  # exit-code divergence ONLY when the two are EXACTLY equal (same sign,
  # same magnitude) AND nonzero -- an unresolvable "Failed:" line in either
  # member, or any mismatch between the two deltas, is the conservative-safe
  # "not explained" (S11.4.101/S11.4.201), never silently assumed equal.
  _FC_EXIT_FLIP_IDS="$(_fc_registry_flip_ids "$TMP/baseline_1.txt" "$TMP/with_timers.txt")"
  _FC_FAILED_N0="$(_fc_failed_count "$BASELINE_LOG")" || _FC_FAILED_N0=""
  _FC_FAILED_N1="$(_fc_failed_count "$WITH_TIMERS_LOG")" || _FC_FAILED_N1=""
  # T048 round 16 (R16-I1): FC0b's own "Failed: N" count, needed below
  # ONLY by the new member-internal-consistency precondition -- the
  # pre-round-16 code never read it at all.
  _FC_FAILED_Nn="$(_fc_failed_count "$NOISE_LOG")" || _FC_FAILED_Nn=""
  _FC_REG_DELTA="$(_fc_registry_failcount_delta "$TMP/baseline_1.txt" "$TMP/with_timers.txt")"
  _FC_N_DELTA=""
  if [ -n "$_FC_FAILED_N0" ] && [ -n "$_FC_FAILED_N1" ]; then
    _FC_N_DELTA=$((_FC_FAILED_N1 - _FC_FAILED_N0))
  fi
  _FC_EXIT_EXPLAINED="$(_fc_exit_explained "$_FC_FAILED_N0" "$_FC_FAILED_N1" "$_FC_REG_DELTA")"

  # T048 round 16 (R16-I1): MEMBER-INTERNAL EXIT/FAILED CONSISTENCY,
  # checked BEFORE any of the exit-code branches below. What every branch
  # below actually checks is whether a DIVERGENCE BETWEEN two members'
  # exit codes is explained; none of them ever asked whether a SINGLE
  # member's own exit code is even internally consistent with that SAME
  # member's own "Failed: N" count in the first place. The real
  # pre_build_verification.sh (pre_build_verification.sh:51468-51483)
  # exits 0 if and only if ERRORS==0, and a nonzero code (1, by
  # construction) otherwise -- but `set -euo pipefail` exposes a SECOND,
  # unrelated way a member can still exit nonzero: a nounset bug inside
  # fc_timer_end() itself, called strictly AFTER the "Failed:" line and the
  # terminal banner are already printed, can escape an `|| true` guard
  # (MEASURED, not assumed, S11.4.6: `set -euo pipefail; f(){ echo
  # "$nope"; }; f || true` exits 1, confirmed live) -- so "Failed: 0"
  # printed correctly does NOT by itself prove the member's own exit code
  # was 0. Reproduced end to end (round-16 reviewer's X1/X2): a registered
  # flake's exit-code divergence in ONE member, exactly-accounted-for by
  # the registry delta below, silently masked a SECOND, genuinely
  # unexplained inconsistency in ANOTHER member whose own Failed:/exit
  # pair this file never cross-checked -- the exact-accounting comparison
  # below answers "is the DIFFERENCE between two members explained", never
  # "is EACH member's own number internally consistent", and a member
  # failing THAT is not a divergence between members at all; it is a
  # single corrupted data point silently feeding every comparison below
  # it. Any violation is a hard FAIL naming the member, its real exit
  # code, and its real Failed count -- never absorbed into any SKIP/PASS
  # branch that follows, which is why this runs unconditionally, before
  # any of them.
  _fc_check_member_consistency() {
    # $1 = member label (for the chk() message only), $2 = real exit code,
    # $3 = real "Failed: N" count (may be empty when unresolvable -- the
    # conservative-safe default is to say nothing about an unresolvable
    # member here, exactly like every OTHER use of an unresolvable Failed
    # count in this file; it is NOT read as "Failed: 0").
    local label="$1" ex="$2" failed="$3"
    [ -n "$failed" ] || return 0
    case "$ex" in
      0 | 1) ;;
      *)
        chk "T048 round-16 member-internal consistency ($label): exit code ($ex) is neither 0 nor 1 -- pre_build_verification.sh exits 0 iff Failed==0, 1 otherwise, so ANY other exit code is itself a hard FAIL, never explained by any registry/noise-floor accounting below (Failed: $failed)" "0"
        return 1
        ;;
    esac
    if [ "$failed" = 0 ] && [ "$ex" != 0 ]; then
      chk "T048 round-16 member-internal consistency ($label): exit code ($ex) with Failed: $failed -- a member reporting Failed: 0 MUST exit 0, never explained by any registry/noise-floor accounting below" "0"
      return 1
    fi
    if [ "$failed" != 0 ] && [ "$ex" != 1 ]; then
      chk "T048 round-16 member-internal consistency ($label): exit code ($ex) with Failed: $failed -- a member reporting a nonzero Failed count MUST exit nonzero (exactly 1), never explained by any registry/noise-floor accounting below" "0"
      return 1
    fi
    return 0
  }
  _fc_check_member_consistency FC0a "$_ex0" "$_FC_FAILED_N0"
  _fc_check_member_consistency FC0b "$_exn" "$_FC_FAILED_Nn"
  _fc_check_member_consistency FC1 "$_ex1" "$_FC_FAILED_N1"

  if [ "$_ex0" = "$_ex1" ]; then
    chk "FR-002 commit result: with-timers exit status ($_ex1) equals without-timers exit status ($_ex0) (noise-floor member FC0b exited $_exn)" "1"
  elif [ "$_exn" != "$_ex0" ] && [ "$_exn" = "$_ex1" ]; then
    skip "FR-002 commit result: with-timers exit status ($_ex1) differs from without-timers exit status ($_ex0), but this SAME run's own noise-floor member FC0b ALSO exited $_exn -- matching FC1, differing from FC0a -- so the exit-code divergence occurs even with timers OFF and cannot be attributed to fc_timer; this comparison is inconclusive, never a FR-002 counter-example"
  elif [ "$_FC_EXIT_EXPLAINED" = 1 ]; then
    skip "FR-002 commit result (registry-explained, exact-accounting, T048 round 14 R14-I1): the summary 'Failed: N' delta ($_FC_FAILED_N0 -> $_FC_FAILED_N1, delta=$_FC_N_DELTA) is FULLY accounted for by the registered gate(s) that crossed the failing-class boundary between these two exact members (delta=$_FC_REG_DELTA; known_flaky_gates.tsv: ${_FC_EXIT_FLIP_IDS:-none textually flipped}), so with-timers exit status ($_ex1) differing from without-timers exit status ($_ex0) is attributable to that ALREADY-EXCLUDED flake, never a FR-002 counter-example on its own; any OTHER, unregistered cause in the SAME run is still caught independently by the verdict-set check below, which this skip never replaces"
  else
    if [ -n "$_FC_FAILED_N0" ] && [ -n "$_FC_FAILED_N1" ]; then
      _FC_ACCT_NOTE="Failed: $_FC_FAILED_N0 -> $_FC_FAILED_N1 (delta=$_FC_N_DELTA), registry delta=$_FC_REG_DELTA"
    else
      _FC_ACCT_NOTE="Failed: N unresolvable in one or both members"
    fi
    chk "FR-002 commit result: with-timers exit status ($_ex1) equals without-timers exit status ($_ex0) (noise-floor member FC0b exited $_exn) -- MISMATCH, not explained by this run's own noise floor nor by an exact registry accounting ($_FC_ACCT_NOTE)" "0"
  fi

  # T048 round 11 (R10-B1): exclude every KNOWN-FLAKY registered gate's
  # verdict line from BOTH sides before any comparison -- see the KNOWN-FLAKY
  # REGISTRY note near the top of this file. Filtering happens BEFORE the
  # strict byte-for-byte comparison, never after, so it is symmetric: a
  # registered gate's line disappears whether it landed in FC0a, FC0b or
  # FC1 -- unlike the noise floor below, which can only explain a deviation
  # the SAME-direction FC0a-vs-FC0b pair also shows.
  _fc_filter_known_flaky "$TMP/baseline_1.txt" "$TMP/baseline_1_fcf.txt"
  _fc_filter_known_flaky "$TMP/with_timers.txt" "$TMP/with_timers_fcf.txt"
  _FCF_HITS="$( { _fc_known_flaky_hits "$TMP/baseline_1.txt"; _fc_known_flaky_hits "$TMP/with_timers.txt"; } | sort -u | tr '\n' ',' | sed 's/,$//')"
  if [ -n "$_FCF_HITS" ]; then
    echo "INFO: excluded known-flaky registered gate line(s) from the FR-002/T-A01 comparison (known_flaky_gates.tsv, each entry tied to a tracked defect): $_FCF_HITS"
  fi

  # T048 round 12 (R12-I1): truncate the post-summary-banner tail (see the
  # SUMMARY-TAIL + EXIT-CODE CASCADE note near the top of this file) from
  # BOTH sides, AFTER the known-flaky filter above, BEFORE the strict/
  # noise-floor comparison below. In-place on the SAME *_fcf.txt files the
  # rest of this block already uses, so no downstream reference changes.
  cp "$TMP/baseline_1_fcf.txt" "$TMP/baseline_1_fcf_pretrunc.txt"
  cp "$TMP/with_timers_fcf.txt" "$TMP/with_timers_fcf_pretrunc.txt"
  _fc_truncate_before_summary_tail "$TMP/baseline_1_fcf_pretrunc.txt" "$TMP/baseline_1_fcf.txt"
  _fc_truncate_before_summary_tail "$TMP/with_timers_fcf_pretrunc.txt" "$TMP/with_timers_fcf.txt"
  _FCF_TRUNC_B="$(( $(wc -l < "$TMP/baseline_1_fcf_pretrunc.txt") - $(wc -l < "$TMP/baseline_1_fcf.txt") ))"
  _FCF_TRUNC_W="$(( $(wc -l < "$TMP/with_timers_fcf_pretrunc.txt") - $(wc -l < "$TMP/with_timers_fcf.txt") ))"
  if [ "$_FCF_TRUNC_B" -gt 0 ] || [ "$_FCF_TRUNC_W" -gt 0 ]; then
    echo "INFO: excluded the post-summary-banner tail ($_FCF_TRUNC_B without-timers line(s), $_FCF_TRUNC_W with-timers line(s)) from the FR-002/T-A01 comparison -- that tail is a deterministic function of the member's own exit/commit-result bit, already checked above, carrying zero additional per-gate information"
  fi

  if cmp -s "$TMP/baseline_1_fcf.txt" "$TMP/with_timers_fcf.txt"; then
    if [ -n "$_FCF_HITS" ]; then
      chk "FR-002/T-A01: with-timers verdict set is IDENTICAL to the without-timers verdict set, byte-for-byte after stripping timing suffixes AND excluding known-flaky registered gate line(s) ($_FCF_HITS; $TRIPLET_REASON)" "1"
    else
      chk "FR-002/T-A01: with-timers verdict set is IDENTICAL to the without-timers verdict set, byte-for-byte after stripping timing suffixes ($TRIPLET_REASON)" "1"
    fi
  else
    DIFF_REAL="$(diff "$TMP/baseline_1_fcf.txt" "$TMP/with_timers_fcf.txt" 2>/dev/null || true)"
    DIFF_REAL_LINES="$(printf '%s\n' "$DIFF_REAL" | grep -c '^[<>]' || true)"

    # Noise-floor classification -- round 8 (R8-B1): computed BEFORE the
    # pass/fail/skip decision below (it used to be diagnostic-only, logged
    # AFTER an unconditional FAIL had already been recorded; a deviation
    # fully explained by this run's own noise floor was then reported but
    # never turned into anything but a FAIL -- a flaky, fc_timer-unrelated
    # parent-repo gate flipping in exactly ONE timers-OFF member made the
    # verifier FAIL a sizeable fraction of genuinely-GREEN runs). Both
    # directions are classified (R5-I3), each against the SAME direction in
    # FC0a-vs-FC0b. Round 11 (R10-B1): the noise floor itself is also
    # computed on the FILTERED files -- a registered gate's own deviation
    # was already excluded above; this classifies whatever remains.
    extract_verdicts "$NOISE_LOG" "$TMP/noise.txt"
    _fc_filter_known_flaky "$TMP/noise.txt" "$TMP/noise_fcf.txt"
    # T048 round 12 (R12-I1): the SAME summary-tail truncation applied to the
    # real pair above, applied here too -- otherwise the noise floor's own
    # multiset match could be inflated (or, in principle, falsely
    # "explain" something) by the wholly-redundant tail text rather than by
    # a genuine same-direction per-gate deviation.
    cp "$TMP/noise_fcf.txt" "$TMP/noise_fcf_pretrunc.txt"
    _fc_truncate_before_summary_tail "$TMP/noise_fcf_pretrunc.txt" "$TMP/noise_fcf.txt"
    DIFF_NOISE="$(diff "$TMP/baseline_1_fcf.txt" "$TMP/noise_fcf.txt" 2>/dev/null || true)"
    printf '%s\n' "$DIFF_REAL"  | sed -n 's/^< //p' > "$TMP/real_removed.txt"
    printf '%s\n' "$DIFF_REAL"  | sed -n 's/^> //p' > "$TMP/real_added.txt"
    printf '%s\n' "$DIFF_NOISE" | sed -n 's/^< //p' > "$TMP/noise_removed.txt"
    printf '%s\n' "$DIFF_NOISE" | sed -n 's/^> //p' > "$TMP/noise_added.txt"
    NOISE_EXPLAINED=0
    UNEXPLAINED=0
    _fc_classify_against() {
      # $1 = changed lines on the real side, $2 = the noise side, SAME direction.
      # MULTISET match (round 7, R6-M4): each noise-side occurrence explains at
      # most ONE real-side occurrence, so a line removed twice on the real side
      # but once in the noise floor counts 1 explained + 1 not explained.
      local _fc_counts
      # (FILENAME, not NR==FNR: the noise side is often EMPTY, and NR==FNR
      # would then mis-read the real side as the noise side.)
      _fc_counts="$(awk 'FILENAME == ARGV[1] { if ($0 != "") n[$0]++; next }
                         $0 == "" { next }
                         { if (n[$0] > 0) { n[$0]--; e++ } else u++ }
                         END { print e+0, u+0 }' "$2" "$1")"
      NOISE_EXPLAINED=$((NOISE_EXPLAINED + ${_fc_counts% *}))
      UNEXPLAINED=$((UNEXPLAINED + ${_fc_counts#* }))
    }
    _fc_classify_against "$TMP/real_removed.txt" "$TMP/noise_removed.txt"
    _fc_classify_against "$TMP/real_added.txt" "$TMP/noise_added.txt"
    TOTAL_CHANGED="$(( $(wc -l < "$TMP/real_removed.txt") + $(wc -l < "$TMP/real_added.txt") ))"
    echo "NOISE-FLOOR: changed=$TOTAL_CHANGED noise_explained=$NOISE_EXPLAINED not_explained=$UNEXPLAINED (noise floor FC0a-vs-FC0b of the same triplet has $(printf '%s\n' "$DIFF_NOISE" | grep -c '^[<>]' || true) differing line(s))"

    if [ "$TOTAL_CHANGED" -gt 0 ] && [ "$UNEXPLAINED" = 0 ]; then
      # Round 8 (R8-B1): EVERY differing line is also present, in the SAME
      # direction, between this SAME run's own two timers-OFF members
      # (FC0a-vs-FC0b) -- by construction it cannot be attributed to
      # fc_timer, since it demonstrably occurs even with timers OFF. A FAIL
      # here would be testing something OTHER than FR-002/T-A01's own claim
      # (fc_timer causes no verdict change). Honestly SKIP, never a silent
      # PASS and never a FAIL: this ONE noise sample still cannot positively
      # CONFIRM fc_timer causes zero change on every other line (that is
      # exactly this file's own long-standing "never asserted fc_timer-
      # caused here" discipline, below) -- it only shows this SPECIFIC
      # deviation is not evidence against FR-002.
      printf '%s\n' "$DIFF_REAL" | head -n 60
      skip "FR-002/T-A01: with-timers verdict set differs from the without-timers verdict set ($DIFF_REAL_LINES differing line(s)), but the deviation is FULLY explained by this SAME run's own FC0a-vs-FC0b noise floor (changed=$TOTAL_CHANGED noise_explained=$NOISE_EXPLAINED not_explained=0) -- it occurs even with timers OFF, so it cannot be attributed to fc_timer; this comparison is inconclusive, never a FR-002 counter-example ($TRIPLET_REASON)"
    else
      chk "FR-002/T-A01: with-timers verdict set is IDENTICAL to the without-timers verdict set, byte-for-byte after stripping timing suffixes ($TRIPLET_REASON) -- MISMATCH, $DIFF_REAL_LINES differing line(s), diff below" "0"
      printf '%s\n' "$DIFF_REAL" | head -n 60
    fi
    echo "INFO: of $TOTAL_CHANGED changed verdict line(s) (removed + added), $NOISE_EXPLAINED also change the same way between the two timer-free members of this run (pre-existing noise, not attributable to fc_timer) and $UNEXPLAINED are not explained by this ONE noise sample -- investigate those; one noise pair cannot tell a timer effect from a rare flake, so they are NEVER asserted fc_timer-caused here."
  fi
else
  skip "FR-002/T-A01 real with-timers-vs-without-timers comparison: no valid same-run triplet -- ${TRIPLET_REASON:-none found}. Two unrelated captures are never compared."
fi

echo "SUMMARY: $((N - FAIL - SKIPPED)) pass / $FAIL fail / $SKIPPED skip of $N assertions (baseline: $BASELINE_LOG, $BASELINE_LINES verdict lines)"
[ "$FAIL" = 0 ]
