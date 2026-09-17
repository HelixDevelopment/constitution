#!/usr/bin/env bash
# mech_common.sh — shared primitives for the constitution mechanical-work tools.
#
# WHAT THIS IS
#   A tiny, dependency-light library sourced by every tool under
#   constitution/scripts/mechanical/. It carries three things that would
#   otherwise be re-implemented (and mis-implemented) in each tool:
#     1. the exit-code vocabulary (§11.4.201),
#     2. ANSI stripping + test-summary parsing that is order-independent,
#     3. tree fingerprinting used to prove a source tree was not modified.
#
# WHY IT EXISTS (§11.4.274)
#   These steps were being executed by hand, one tool call at a time, inside
#   agent transcripts. They are deterministic, fixed-input/fixed-output and
#   contain no judgment, so they belong in a script.
#
# EXIT-CODE VOCABULARY (§11.4.201) — every tool in this directory uses it.
#   0  MECH_EXIT_OK          the operation ran and the outcome matched expectation
#   1  MECH_EXIT_FINDING     the operation ran and found something (a real result:
#                            residue present, drift present, expectation violated)
#   2  MECH_EXIT_CANNOT_RUN  the operation COULD NOT RUN (bad arguments, missing
#                            target, missing dependency, unparseable output).
#                            NEVER conflated with 0 or 1: "found nothing" and
#                            "could not look" are different facts.
#   3  MECH_EXIT_TIMEOUT     a bounded wait expired without the condition holding.
#                            Distinct so a timeout can never read as success.
#
# THIS LIBRARY RENDERS NO VERDICT ABOUT CORRECTNESS (§11.4.274(d)). It parses,
# fingerprints and compares. Whether a measured result MEANS a fix is correct is
# a judgment for the reading agent, never for this code.

# Guard against double-sourcing.
[ -n "${MECH_COMMON_SOURCED:-}" ] && return 0
MECH_COMMON_SOURCED=1

readonly MECH_EXIT_OK=0
readonly MECH_EXIT_FINDING=1
readonly MECH_EXIT_CANNOT_RUN=2
readonly MECH_EXIT_TIMEOUT=3

# mech_die MESSAGE — report an instrument failure and exit MECH_EXIT_CANNOT_RUN.
mech_die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit "$MECH_EXIT_CANNOT_RUN"
}

# mech_need CMD... — every named command must be on PATH, else CANNOT_RUN.
mech_need() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || mech_die "required command not found on PATH: $c"
  done
}

# mech_strip_ansi — stdin -> stdout with CSI/OSC escape sequences removed.
# Test harnesses colour their summary lines; a naive grep for '0 failed' can
# miss a match that is wrapped in colour codes, so stripping is mandatory
# before any parsing.
# NOTE (measured 2026-09-08, GNU sed 4.9): `\x1b` is NOT interpreted as ESC by
# this sed in these expressions — a strip written that way is a silent no-op and
# every downstream grep then runs against still-coloured text. The ESC and BEL
# bytes are therefore built with printf and interpolated, and the library test
# carries a control needle that fails if stripping ever silently stops working.
mech_strip_ansi() {
  local esc bel
  esc="$(printf '\033')"
  bel="$(printf '\007')"
  # LC_ALL=C is load-bearing: bracket RANGES like [@-~] follow the locale's
  # collation order, so under a UTF-8 locale the CSI final-byte class does not
  # match what it looks like it matches, and the strip silently under-removes.
  LC_ALL=C sed -e "s/${esc}\[[0-9;?]*[@-~]//g" \
               -e "s/${esc}\][^${bel}]*${bel}//g" \
               -e "s/${esc}//g"
}

# mech_parse_summary FILE
#   Print "<passed> <failed>" for the LAST line of FILE that names both a
#   passed count and a failed count. Returns MECH_EXIT_CANNOT_RUN when no such
#   line exists — an unparseable run is an instrument failure, never a pass.
#
#   ORDER-INDEPENDENT BY CONSTRUCTION. Real harnesses print
#       "58 passed, 0 failed"   on success and
#       "3 failed, 55 passed"   on failure
#   — the fields swap. Positional parsing ("the first number is passes") is the
#   exact transcription trap this function exists to remove: it reads a failing
#   run as 3 passes and calls it green. Each count is located by its own label.
#
#   The label patterns are overridable for harnesses that word it differently:
#       MECH_SUMMARY_PASS_PATTERN (default '[0-9]+[[:space:]]*passed')
#       MECH_SUMMARY_FAIL_PATTERN (default '[0-9]+[[:space:]]*failed')
#
#   KNOWN LIMITATION (§11.4.6): if a suite's own output echoes a sentence that
#   contains both labels AFTER its real summary line, that sentence wins. The
#   patterns are overridable for that case; the tools print the matched line so
#   a reader can see what was parsed.
mech_parse_summary() {
  local f="$1"
  [ -r "$f" ] || return "$MECH_EXIT_CANNOT_RUN"
  local pass_re="${MECH_SUMMARY_PASS_PATTERN:-[0-9]+[[:space:]]*passed}"
  local fail_re="${MECH_SUMMARY_FAIL_PATTERN:-[0-9]+[[:space:]]*failed}"
  local line
  line="$(mech_strip_ansi < "$f" | grep -E "$pass_re" | grep -E "$fail_re" | tail -n 1)"
  [ -n "$line" ] || return "$MECH_EXIT_CANNOT_RUN"
  local p f2
  p="$(printf '%s\n' "$line"  | grep -oE "$pass_re" | head -n 1 | grep -oE '[0-9]+' | head -n 1)"
  f2="$(printf '%s\n' "$line" | grep -oE "$fail_re" | head -n 1 | grep -oE '[0-9]+' | head -n 1)"
  [ -n "$p" ] && [ -n "$f2" ] || return "$MECH_EXIT_CANNOT_RUN"
  printf '%s %s\n' "$p" "$f2"
}

# mech_summary_line FILE — print the raw (ANSI-stripped) line that
# mech_parse_summary matched, so a reader can audit the parse.
mech_summary_line() {
  local f="$1"
  [ -r "$f" ] || return "$MECH_EXIT_CANNOT_RUN"
  local pass_re="${MECH_SUMMARY_PASS_PATTERN:-[0-9]+[[:space:]]*passed}"
  local fail_re="${MECH_SUMMARY_FAIL_PATTERN:-[0-9]+[[:space:]]*failed}"
  mech_strip_ansi < "$f" | grep -E "$pass_re" | grep -E "$fail_re" | tail -n 1
}

# mech_fingerprint_tree DIR
#   Print a deterministic, order-stable manifest hash of DIR's file contents.
#   Used to PROVE a source tree under independent review was not modified
#   (§11.4.119) — the claim "we only touched a scratch copy" is asserted from
#   a before/after comparison, not from intent.
mech_fingerprint_tree() {
  local dir="$1"
  [ -d "$dir" ] || return "$MECH_EXIT_CANNOT_RUN"
  ( cd "$dir" && find . -type f -print0 \
      | LC_ALL=C sort -z \
      | xargs -0 -r md5sum \
      | md5sum | awk '{print $1}' )
}

# mech_manifest_tree DIR OUTFILE
#   Write "<md5>  <relative path>" for every file under DIR, sorted. Paired with
#   mech_manifest_diff to name EXACTLY which files changed — a fingerprint alone
#   says "something moved", which is not actionable when the tree belongs to
#   someone else and has to be put back.
mech_manifest_tree() {
  local dir="$1" out="$2"
  [ -d "$dir" ] || return "$MECH_EXIT_CANNOT_RUN"
  ( cd "$dir" && find . -type f -print0 \
      | LC_ALL=C sort -z \
      | xargs -0 -r md5sum ) > "$out"
}

# mech_manifest_diff BEFORE AFTER — print each path whose content changed,
# appeared or vanished. Empty output means the tree is byte-identical.
mech_manifest_diff() {
  local before="$1" after="$2"
  LC_ALL=C sort "$before" > "$before.s"
  LC_ALL=C sort "$after"  > "$after.s"
  comm -3 "$before.s" "$after.s" | awk '{print $NF}' | LC_ALL=C sort -u
  rm -f "$before.s" "$after.s"
}

# mech_log LEVEL MESSAGE — uniform stderr diagnostics. Never used for results;
# results go to stdout so they can be captured without diagnostics noise.
mech_log() {
  local level="$1"; shift
  printf '[%s] %s\n' "$level" "$*" >&2
}
