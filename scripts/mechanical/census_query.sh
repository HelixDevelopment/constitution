#!/usr/bin/env bash
# census_query.sh — run a counting query that PROVES it can see (§11.4.273).
#
# WHY THIS EXISTS
#   §11.4.273 was minted from fifteen measured instrument errors in a single
#   session. Every one returned a confident, plausible, actionable number that
#   described the INSTRUMENT rather than the system: a pattern matching only one
#   of two block-opener forms; `comm` over numerically-sorted input; `$?` read
#   after a pipeline; `grep -w zai` matching `zai-coding-plan`; a two-literal
#   denylist searched with one literal, reporting a live credential eliminated
#   while it was still there.
#
#   The anchor's remedy is not vigilance, it is mechanism: a census whose answer
#   will drive a decision must carry, in the same command and through the same
#   path, a needle it MUST find and a needle it MUST NOT. This tool makes both
#   mandatory and REFUSES to emit a count when either fails.
#
# WHAT IT DOES NOT DO (§11.4.274(d))
#   It counts. It does not decide what the count means, whether the pattern was
#   the right pattern, or whether a zero is good news. A tool that rendered that
#   verdict would be the bluff gate this library exists to prevent.
#
#   AND — the honest boundary the anchor itself states — control needles prove
#   an instrument can tell PRESENT from ABSENT. They do NOT prove it measures
#   the RIGHT property. A correctly-needled census of the wrong thing is still
#   the wrong answer.
#
# USAGE
#   census_query.sh --tree DIR --pattern ERE
#                   --positive NEEDLE [--positive NEEDLE]...
#                   --negative NEEDLE [--negative NEEDLE]...
#                   [--include GLOB]... [--label NAME] [--expect-count N]
#                   [--list-files]
#
#   --tree DIR       Tree to search. Required.
#   --pattern ERE    The query. Extended regular expression, as `grep -E`.
#   --positive N     A needle that MUST be findable, in this tree, under this
#                    --include scope. Repeatable; EVERY one must hold
#                    (§11.4.273(f) — one member passing proves one member, not
#                    the criterion). Required: at least one.
#   --negative N     A needle that MUST NOT be findable. Repeatable; EVERY one
#                    must be absent. Required: at least one. This is the
#                    too-broad half — the half `residue_scan.sh` and
#                    `anchor_census.sh` do not carry.
#   --include GLOB   Restrict to matching basenames (grep --include).
#                    Repeatable. Applied identically to the query AND to both
#                    control searches, so the controls exercise the same path.
#   --label NAME     Label for the verdict line. Default: census.
#   --expect-count N Assert the match count. A mismatch is a FINDING (exit 1),
#                    which is a different fact from an instrument failure (2).
#   --list-files     Also print the matching file list, one per line, before
#                    the verdict.
#
# NEEDLES ARE ERE, NOT LITERAL — deliberately. The controls run through the
# SAME matcher as the query, because a control that took a different code path
# would not prove the query's path can see. A needle containing regex
# metacharacters must therefore be escaped by the caller.
#
# EXIT CODES (§11.4.201) — three distinct facts, never collapsed
#   0  ran; controls held; count emitted (and matched --expect-count if given)
#   1  ran; controls held; count emitted but VIOLATED --expect-count (a finding)
#   2  COULD NOT RUN — missing args, missing tree, a failed control, or a grep
#      error. No count is emitted, because an unproven instrument's zero is not
#      a clean result.
set -uo pipefail

_HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/mech_common.sh
source "$_HERE/lib/mech_common.sh"

TREE="" PATTERN="" LABEL="census" EXPECT_COUNT="" LIST_FILES=0
POSITIVE=() NEGATIVE=() INCLUDES=()

while [ $# -gt 0 ]; do
  case "$1" in
    --tree)         TREE="${2:-}"; shift 2 ;;
    --pattern)      PATTERN="${2:-}"; shift 2 ;;
    --positive)     POSITIVE+=("${2:-}"); shift 2 ;;
    --negative)     NEGATIVE+=("${2:-}"); shift 2 ;;
    --include)      INCLUDES+=("--include=${2:-}"); shift 2 ;;
    --label)        LABEL="${2:-}"; shift 2 ;;
    --expect-count) EXPECT_COUNT="${2:-}"; shift 2 ;;
    --list-files)   LIST_FILES=1; shift ;;
    -h|--help)      sed -n '1,60p' "${BASH_SOURCE[0]}"; exit "$MECH_EXIT_OK" ;;
    *)              mech_die "unknown argument: $1" ;;
  esac
done

mech_need grep

[ -n "$TREE" ]    || mech_die "--tree is required"
[ -n "$PATTERN" ] || mech_die "--pattern is required"
[ -d "$TREE" ]    || mech_die "--tree is not a directory: $TREE"

# BOTH controls are MANDATORY. Optional controls decay into a convention, and a
# convention is what §11.4.273 was minted because vigilance had already failed.
if [ "${#POSITIVE[@]}" -eq 0 ]; then
  mech_die "--positive is required: a census with no positive control cannot distinguish 'found nothing' from 'could not look'"
fi
if [ "${#NEGATIVE[@]}" -eq 0 ]; then
  mech_die "--negative is required: without it a too-broad pattern reports matches it should not have found"
fi

if [ -n "$EXPECT_COUNT" ] && ! printf '%s' "$EXPECT_COUNT" | grep -qE '^[0-9]+$'; then
  mech_die "--expect-count must be a non-negative integer, got: $EXPECT_COUNT"
fi

# _grep_lines PATTERN [scoped=1] — matching LINES. rc: 0 found, 1 none, 2 error.
# The include scope is applied only when scoped=1, so an out-of-scope control
# can be told apart from an unseeable one.
_grep_lines() {
  local pat="$1" scoped="${2:-1}"
  if [ "$scoped" = "1" ] && [ "${#INCLUDES[@]}" -gt 0 ]; then
    grep -rEnI --exclude-dir=.git "${INCLUDES[@]}" -e "$pat" -- "$TREE" 2>/dev/null
  else
    grep -rEnI --exclude-dir=.git -e "$pat" -- "$TREE" 2>/dev/null
  fi
}

_grep_files() {
  local pat="$1"
  if [ "${#INCLUDES[@]}" -gt 0 ]; then
    grep -rlEI --exclude-dir=.git "${INCLUDES[@]}" -e "$pat" -- "$TREE" 2>/dev/null
  else
    grep -rlEI --exclude-dir=.git -e "$pat" -- "$TREE" 2>/dev/null
  fi
}

# --- POSITIVE controls: every one must be findable IN SCOPE -----------------
POS_OK=0
for n in "${POSITIVE[@]}"; do
  out="$(_grep_lines "$n" 1)"; rc=$?          # §11.4.273(g): capture immediately
  if [ "$rc" -ge 2 ]; then
    mech_die "POSITIVE CONTROL could not be evaluated: grep failed on needle '$n' (rc=$rc)"
  fi
  if [ -n "$out" ]; then POS_OK=$((POS_OK + 1)); continue; fi

  # Not found in scope. Is it absent from the tree, or merely out of scope?
  # These are DIFFERENT findings and were confused during the research that
  # produced this tool: an out-of-scope control reads as a broken instrument
  # and sends the reader after a defect that is not there.
  wider="$(_grep_lines "$n" 0)"; wrc=$?
  if [ "$wrc" -lt 2 ] && [ -n "$wider" ]; then
    printf 'POSITIVE CONTROL OUT OF SCOPE: needle %s exists in %s but NOT under the --include scope.\n' \
      "'$n'" "$TREE" >&2
    printf '  The instrument is not proven blind — the CONTROL is misplaced. Choose a needle inside the scope being measured.\n' >&2
  else
    printf 'POSITIVE CONTROL FAILED: needle %s not found anywhere in %s — the instrument cannot see.\n' \
      "'$n'" "$TREE" >&2
  fi
  printf 'RESULT REFUSED: an unproven instrument reporting a count is how absence of evidence becomes a positive report.\n' >&2
  exit "$MECH_EXIT_CANNOT_RUN"
done

# --- NEGATIVE controls: every one must be ABSENT in scope -------------------
NEG_HITS=0
for n in "${NEGATIVE[@]}"; do
  out="$(_grep_lines "$n" 1)"; rc=$?
  if [ "$rc" -ge 2 ]; then
    mech_die "NEGATIVE CONTROL could not be evaluated: grep failed on needle '$n' (rc=$rc)"
  fi
  if [ -n "$out" ]; then
    NEG_HITS=$((NEG_HITS + 1))
    printf 'NEGATIVE CONTROL FAILED: needle %s WAS found in %s — the query path matches things it must not.\n' \
      "'$n'" "$TREE" >&2
    printf '%s\n' "$out" | head -5 >&2
    printf 'RESULT REFUSED: a matcher that finds a fabricated needle cannot be trusted about a real one.\n' >&2
    exit "$MECH_EXIT_CANNOT_RUN"
  fi
done

# --- the query itself -------------------------------------------------------
lines="$(_grep_lines "$PATTERN" 1)"; qrc=$?
if [ "$qrc" -ge 2 ]; then
  mech_die "QUERY could not be evaluated: grep failed on pattern '$PATTERN' (rc=$qrc)"
fi
files="$(_grep_files "$PATTERN")"; frc=$?
if [ "$frc" -ge 2 ]; then
  mech_die "QUERY could not be evaluated: grep -l failed on pattern '$PATTERN' (rc=$frc)"
fi

MATCHES=0; [ -n "$lines" ] && MATCHES="$(printf '%s\n' "$lines" | wc -l | tr -d ' ')"
FILES=0;   [ -n "$files" ] && FILES="$(printf '%s\n' "$files" | wc -l | tr -d ' ')"

if [ "$LIST_FILES" -eq 1 ] && [ -n "$files" ]; then printf '%s\n' "$files"; fi

# The controls are published as counts, not asserted in prose, so a reader can
# see the discipline ran rather than take it on trust.
VERDICT="OK"
RC="$MECH_EXIT_OK"
if [ -n "$EXPECT_COUNT" ] && [ "$MATCHES" -ne "$EXPECT_COUNT" ]; then
  VERDICT="COUNT-MISMATCH expected=$EXPECT_COUNT"
  RC="$MECH_EXIT_FINDING"
fi

printf 'CENSUS %s: matches=%s files=%s positive=%s/%s negative=%s/%s [%s]\n' \
  "$LABEL" "$MATCHES" "$FILES" \
  "$POS_OK" "${#POSITIVE[@]}" "$NEG_HITS" "${#NEGATIVE[@]}" "$VERDICT"

exit "$RC"
