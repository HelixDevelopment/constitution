#!/usr/bin/env bash
# anchor_census.sh — count governance anchors across N carrier files, verify
# each anchor heads exactly one block, and verify the carriers hold the SAME set.
#
# WHY THIS EXISTS (§11.4.274)
#   The lockstep check (§11.4.157) and the exactly-once check (§11.4.227(B)) are
#   pure counting: extract the anchor ids each carrier declares, sort, hash,
#   compare. Done by hand it is several greps per carrier plus a mental set
#   difference — and a mental set difference over a hundred-plus ids is where
#   transcription errors come from. Two were made doing exactly this by hand.
#
# WHY IT COUNTS BLOCK-OPENERS, NOT MENTIONS
#   A carrier CITES far more anchors than it DECLARES. Counting bare occurrences
#   of an id conflates "this file defines §11.4.N" with "this file mentions
#   §11.4.N in passing", so the census must key on the shapes that open a block.
#   Two forms are in live use and both are matched by default:
#       ^### §11.4.N …       (canonical constitution heading)
#       ^**§11.4.N …         (consumer-carrier bolded opener)
#   Override with --opener-re for a corpus that uses a different shape.
#
# THE FALSE-NULL GUARD (§11.4.273)
#   A census that silently matches nothing reports "0 anchors in every carrier,
#   all sets identical" — a perfect, meaningless green. So: zero anchors in ANY
#   carrier is CANNOT_RUN, not a pass, and --control-needle names an anchor id
#   that MUST be found in every carrier, failing loudly when the pattern has
#   drifted away from the corpus.
#
# WHAT IT DOES NOT DO (§11.4.274(d))
#   It does not decide whether a missing anchor SHOULD be cascaded, whether a
#   duplicate is a mistake or a deliberate re-mint, or what a drift means for a
#   release. It reports set differences. Someone else decides.
#
# USAGE
#   anchor_census.sh [--opener-re ERE] [--id-re ERE] [--control-needle ID]
#                    [--quiet] CARRIER...
#
#   CARRIER...           Two or more files to compare (one file = census only).
#   --opener-re ERE      Extended regex matching a block-opening line. Default
#                        matches both live forms.
#   --id-re ERE          Regex extracting the id from an opener line.
#                        Default: 11\.4\.[0-9]+
#   --control-needle ID  An id (e.g. 11.4.1) that must appear as an opener in
#                        every carrier, else CANNOT_RUN.
#   --quiet              Suppress the per-carrier table; print only findings.
#
# EXIT CODES (§11.4.201)
#   0  census RAN; every carrier holds the same anchor set and no id opens two
#      blocks in the same carrier
#   1  a finding: sets differ, or an id opens more than one block
#   2  could not run: missing/unreadable carrier, no carriers, zero anchors in a
#      carrier, or a control needle not found
set -uo pipefail

MECH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/mech_common.sh
source "$MECH_DIR/lib/mech_common.sh"

OPENER_RE='^(### §|\*\*§)11\.4\.[0-9]+'
ID_RE='11\.4\.[0-9]+'
CONTROL="" QUIET=0
CARRIERS=()

usage() { sed -n '2,48p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --opener-re)      OPENER_RE="${2:-}"; shift 2 ;;
    --id-re)          ID_RE="${2:-}"; shift 2 ;;
    --control-needle) CONTROL="${2:-}"; shift 2 ;;
    --quiet)          QUIET=1; shift ;;
    -h|--help)        usage; exit "$MECH_EXIT_OK" ;;
    --*)              mech_die "unknown argument: $1 (try --help)" ;;
    *)                CARRIERS+=("$1"); shift ;;
  esac
done

[ "${#CARRIERS[@]}" -gt 0 ] || mech_die "no carrier files given"
for c in "${CARRIERS[@]}"; do
  [ -r "$c" ] || mech_die "carrier not readable: $c"
done

WORK="$(mktemp -d "${TMPDIR:-/tmp}/mech-census.XXXXXX")" || mech_die "cannot create temp dir"
trap 'rm -rf "$WORK"' EXIT

FINDINGS=0

[ "$QUIET" -eq 1 ] || printf '%-52s %8s %10s %s\n' CARRIER ANCHORS DUPLICATE SET_HASH

for c in "${CARRIERS[@]}"; do
  key="$(printf '%s' "$c" | md5sum | awk '{print $1}')"
  ids="$WORK/$key.ids"
  # Extract the id FROM THE OPENER MATCH, not from the whole line. A heading
  # routinely cites other anchors after its own ("… composes §11.4.5 / §11.4.69"),
  # so grepping ids across the matched line counts every citation as a
  # declaration — measured 2026-09-08 on the canonical constitution: 900 "anchors"
  # and a wall of phantom duplicates, from 271 real openers. This requires
  # --opener-re to CONTAIN the id, which it does by construction.
  LC_ALL=C grep -oE "$OPENER_RE" "$c" 2>/dev/null \
    | grep -oE "$ID_RE" > "$ids"

  n="$(wc -l < "$ids" | tr -d ' ')"
  if [ "$n" -eq 0 ]; then
    printf 'ZERO-ANCHORS %s\n' "$c"
    mech_die "no anchors matched in $c — an empty census is an instrument failure, not a clean result (check --opener-re)"
  fi

  dups="$(LC_ALL=C sort "$ids" | uniq -d | tr '\n' ' ')"
  LC_ALL=C sort -u "$ids" > "$ids.uniq"
  hash="$(md5sum "$ids.uniq" | awk '{print $1}')"

  if [ -n "$CONTROL" ]; then
    LC_ALL=C grep -Fxq -- "$CONTROL" "$ids.uniq" \
      || mech_die "control needle '$CONTROL' does not open a block in $c — the census cannot see what it is meant to see"
  fi

  [ "$QUIET" -eq 1 ] || printf '%-52s %8s %10s %s\n' "$(basename "$c")" "$n" "${dups:-none}" "$hash"

  if [ -n "$dups" ]; then
    printf 'DUPLICATE-OPENER %s: %s\n' "$c" "$dups"
    FINDINGS=$((FINDINGS+1))
  fi
done

if [ "${#CARRIERS[@]}" -ge 2 ]; then
  ref="${CARRIERS[0]}"
  refkey="$(printf '%s' "$ref" | md5sum | awk '{print $1}')"
  refhash="$(md5sum "$WORK/$refkey.ids.uniq" | awk '{print $1}')"
  for c in "${CARRIERS[@]:1}"; do
    key="$(printf '%s' "$c" | md5sum | awk '{print $1}')"
    h="$(md5sum "$WORK/$key.ids.uniq" | awk '{print $1}')"
    if [ "$h" != "$refhash" ]; then
      FINDINGS=$((FINDINGS+1))
      printf 'SET-DRIFT %s vs %s\n' "$ref" "$c"
      comm -23 "$WORK/$refkey.ids.uniq" "$WORK/$key.ids.uniq" | sed "s|^|  only-in $(basename "$ref"): |"
      comm -13 "$WORK/$refkey.ids.uniq" "$WORK/$key.ids.uniq" | sed "s|^|  only-in $(basename "$c"): |"
    fi
  done
fi

printf 'carriers=%s findings=%s\n' "${#CARRIERS[@]}" "$FINDINGS"
[ "$FINDINGS" -gt 0 ] && exit "$MECH_EXIT_FINDING"
exit "$MECH_EXIT_OK"
