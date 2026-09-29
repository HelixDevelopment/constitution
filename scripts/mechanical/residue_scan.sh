#!/usr/bin/env bash
# residue_scan.sh — scan a tree for paired-mutation residue (§11.4.84) without
# drowning in the self-references that make a naive scan useless.
#
# WHY THIS EXISTS (§11.4.274)
#   "Grep the working tree for mutation markers before committing" is a fixed
#   recipe run before every commit, and every time it is run by hand it produces
#   the same two false positives — the governance document that DEFINES the
#   marker strings, and the scanner itself, which must contain them to search for
#   them. A scan whose output is permanently noisy gets ignored, and then gets
#   disabled, and then the one real residue lands in a commit.
#
# THE SELF-REFERENCE PROBLEM, AND WHY THE FIX IS AN ALLOWLIST
#   A file can legitimately contain a marker string for exactly two reasons: it
#   defines the marker (a rule, a manual, this scanner) or it plants one on
#   purpose (a mutation test's fixtures). Both are project facts, not universal
#   ones, so they are supplied as DATA — an allowlist of path globs — rather than
#   hardcoded here (§11.4.35 / §11.4.177). Only this tool's own directory is
#   auto-excluded, because that is a fact about the tool itself.
#   The allowlist is audited in turn: patterns that match nothing are reported as
#   stale, so an allowlist cannot quietly grow into a disabled scanner.
#
# WHAT IT DOES NOT DO (§11.4.274(d))
#   It does not decide whether a hit is real residue or an intentional fixture.
#   It prints file, line number and the matching line. A human or agent reads it.
#
# USAGE
#   residue_scan.sh --tree DIR [--marker STR]... [--markers-from FILE]
#                   [--allow GLOB]... [--allow-from FILE] [--strict-allow]
#                   [--control-needle STR] [--no-default-markers]
#
#   --tree DIR           Tree to scan.
#   --marker STR         Extra literal marker to search for. Repeatable.
#   --markers-from FILE  Read markers from FILE, one per line ('#' comments).
#   --allow GLOB         Path glob (relative to --tree) exempt from the scan.
#                        Repeatable. Also read from <tree>/.mech-residue-allow
#                        when that file exists.
#   --allow-from FILE    Read allow globs from FILE.
#   --strict-allow       Treat a stale (never-matching) allow pattern as a
#                        finding rather than a warning.
#   --control-needle STR A string that MUST be findable in the tree. If the scan
#                        cannot find it, the scan is broken and exits CANNOT_RUN
#                        rather than reporting a reassuring "no residue"
#                        (§11.4.273 — an empty result is only meaningful from an
#                        instrument proven able to produce a non-empty one).
#   --no-default-markers Use only the markers given on the command line.
#
# DEFAULT MARKERS
#   MUTATED for paired | // always pass | # always pass | MUTATION-MARKER
#   _mutated_ | XXX-MUTATION
#
# EXIT CODES (§11.4.201)
#   0  the scan RAN and found no residue outside the allowlist
#   1  residue found (or, with --strict-allow, a stale allow pattern)
#   2  the scan COULD NOT RUN: missing tree, unreadable list file, no markers, or
#      a --control-needle the scan failed to find
set -uo pipefail

MECH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/mech_common.sh
source "$MECH_DIR/lib/mech_common.sh"

TREE="" STRICT_ALLOW=0 CONTROL="" USE_DEFAULTS=1
MARKERS=() ALLOWS=()

usage() { sed -n '2,55p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

read_list_into() {
  local file="$1" __arr="$2" l
  [ -r "$file" ] || mech_die "list file not readable: $file"
  while IFS= read -r l; do
    l="${l%%#*}"
    l="$(printf '%s' "$l" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [ -n "$l" ] && eval "$__arr+=(\"\$l\")"
  done < "$file"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --tree)               TREE="${2:-}"; shift 2 ;;
    --marker)             MARKERS+=("${2:-}"); shift 2 ;;
    --markers-from)       read_list_into "${2:-}" MARKERS; shift 2 ;;
    --allow)              ALLOWS+=("${2:-}"); shift 2 ;;
    --allow-from)         read_list_into "${2:-}" ALLOWS; shift 2 ;;
    --strict-allow)       STRICT_ALLOW=1; shift ;;
    --control-needle)     CONTROL="${2:-}"; shift 2 ;;
    --no-default-markers) USE_DEFAULTS=0; shift ;;
    -h|--help)            usage; exit "$MECH_EXIT_OK" ;;
    *)                    mech_die "unknown argument: $1 (try --help)" ;;
  esac
done

[ -n "$TREE" ] || mech_die "--tree is required"
[ -d "$TREE" ] || mech_die "--tree is not a directory: $TREE"
TREE="$(cd "$TREE" && pwd)"

if [ "$USE_DEFAULTS" -eq 1 ]; then
  MARKERS+=("MUTATED for paired" "// always pass" "# always pass" "MUTATION-MARKER" "_mutated_" "XXX-MUTATION")
fi
[ "${#MARKERS[@]}" -gt 0 ] || mech_die "no markers to scan for (--no-default-markers with no --marker)"

[ -r "$TREE/.mech-residue-allow" ] && read_list_into "$TREE/.mech-residue-allow" ALLOWS

# The tool's own directory is the one exclusion that is a fact about the tool
# rather than a fact about the project: this scanner cannot search for marker
# strings without containing them. Handles both "the tool lives inside the tree"
# and "the tree IS the tool directory".
SELF_REL=""
if [ "$MECH_DIR" = "$TREE" ]; then
  SELF_REL="."
else
  case "$MECH_DIR/" in
    "$TREE"/*) SELF_REL="${MECH_DIR#"$TREE"/}" ;;
  esac
fi

SELF_EXCLUDED=0
path_allowed() {
  local rel="$1" g
  if [ "$SELF_REL" = "." ]; then SELF_EXCLUDED=$((SELF_EXCLUDED+1)); return 0; fi
  if [ -n "$SELF_REL" ]; then
    case "$rel" in "$SELF_REL"/*|"$SELF_REL") SELF_EXCLUDED=$((SELF_EXCLUDED+1)); return 0 ;; esac
  fi
  for g in "${ALLOWS[@]+"${ALLOWS[@]}"}"; do
    # shellcheck disable=SC2254
    case "$rel" in $g) ALLOW_HIT[$g]=1; return 0 ;; esac
  done
  return 1
}

declare -A ALLOW_HIT=()

FILES="$(mktemp "${TMPDIR:-/tmp}/mech-residue.XXXXXX")" || mech_die "cannot create temp file"
trap 'rm -f "$FILES"' EXIT
( cd "$TREE" && find . -type f -not -path '*/.git/*' -print | sed 's|^\./||' | LC_ALL=C sort ) > "$FILES"

HITS=0
CONTROL_FOUND=0
EXAMINED=0
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  abs="$TREE/$rel"
  # Skip binaries: a marker inside a compiled artifact is not source residue.
  if ! LC_ALL=C grep -Iq . "$abs" 2>/dev/null; then continue; fi
  if [ -n "$CONTROL" ] && [ "$CONTROL_FOUND" -eq 0 ]; then
    LC_ALL=C grep -F -q -- "$CONTROL" "$abs" 2>/dev/null && CONTROL_FOUND=1
  fi
  path_allowed "$rel" && continue
  EXAMINED=$((EXAMINED+1))
  for m in "${MARKERS[@]}"; do
    while IFS= read -r hit; do
      [ -n "$hit" ] || continue
      printf 'RESIDUE %s:%s\n' "$rel" "$hit"
      HITS=$((HITS+1))
    done < <(LC_ALL=C grep -F -n -- "$m" "$abs" 2>/dev/null)
  done
done < "$FILES"

if [ -n "$CONTROL" ] && [ "$CONTROL_FOUND" -eq 0 ]; then
  printf 'CONTROL-NEEDLE NOT FOUND: %s\n' "$CONTROL"
  mech_die "the control needle was not found anywhere in the tree — this scan cannot be trusted to find anything, so its empty result means nothing"
fi

STALE=0
for g in "${ALLOWS[@]+"${ALLOWS[@]}"}"; do
  if [ -z "${ALLOW_HIT[$g]:-}" ]; then
    printf 'STALE-ALLOW %s (matched no scanned file)\n' "$g"
    STALE=$((STALE+1))
  fi
done

if [ -n "$CONTROL" ]; then CONTROL_STATE="found"; else CONTROL_STATE="none-given"; fi
printf 'scanned=%s examined=%s self_excluded=%s markers=%s allow_patterns=%s residue=%s stale_allow=%s control=%s\n' \
  "$(wc -l < "$FILES" | tr -d ' ')" "$EXAMINED" "$SELF_EXCLUDED" "${#MARKERS[@]}" "${#ALLOWS[@]}" "$HITS" "$STALE" \
  "$CONTROL_STATE"

# A scan that examined nothing is a false null (§11.4.273): "residue=0" out of
# zero examined files reads identically to a clean tree and means nothing.
if [ "$EXAMINED" -eq 0 ]; then
  mech_die "every file was excluded (self=$SELF_EXCLUDED, allow patterns=${#ALLOWS[@]}) — the scan examined nothing, so its empty result is not a clean result"
fi

[ "$HITS" -gt 0 ] && exit "$MECH_EXIT_FINDING"
[ "$STRICT_ALLOW" -eq 1 ] && [ "$STALE" -gt 0 ] && exit "$MECH_EXIT_FINDING"
exit "$MECH_EXIT_OK"
