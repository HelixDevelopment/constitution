#!/usr/bin/env bash
# suite_fanout.sh — run N named test suites, tabulate exit code and pass/fail
# counts, and (optionally) report only the DELTAS against a recorded baseline.
#
# WHY THIS EXISTS (§11.4.274)
#   "Run these six suites and tell me what changed" is a fixed recipe: invoke,
#   read the summary line, write the number down, compare with last time. It was
#   being done a tool call at a time, and the comparison step — the one that
#   actually matters — was being done from memory of a previous transcript.
#
# WHAT IT DOES NOT DO (§11.4.274(d))
#   It does not decide whether a delta is acceptable, whether a newly-failing
#   suite is a regression or a corrected expectation, or whether the baseline
#   itself was right. It prints what moved. The reader decides what it means.
#
# USAGE
#   suite_fanout.sh --tree DIR [--baseline FILE] [--out FILE]
#                   [--timeout SECS] [--unset VAR]... SUITE_REL...
#   suite_fanout.sh --tree DIR --suites-from LIST_FILE ...
#
#   --tree DIR          Tree the suites live in; suite paths are relative to it.
#   SUITE_REL...        One or more suite paths relative to --tree.
#   --suites-from FILE  Read suite paths from FILE, one per line ('#' comments).
#   --baseline FILE     A previously written results file to compare against.
#   --out FILE          Write this run's results (TSV) here, for use as a future
#                       baseline. Columns: suite <TAB> rc <TAB> passed <TAB> failed
#   --timeout SECS      Per-suite ceiling. Default 600.
#   --unset VAR         Unset VAR for every suite run. Repeatable.
#
# OUTPUT
#   A per-suite line, then either "no deltas" or only the rows that moved. The
#   full table is always written to --out when given, so nothing is lost.
#
# EXIT CODES (§11.4.201)
#   0  every suite RAN and (with a baseline) nothing moved / (without one) every
#      suite reported zero failures
#   1  a finding: a suite failed, or a count moved against the baseline, or a
#      baselined suite was not run
#   2  could not run: no suites given, tree missing, a suite file missing, a
#      suite timed out, or a suite's output could not be parsed. An unparseable
#      or timed-out suite is an instrument failure and is NEVER counted as a pass.
set -uo pipefail

MECH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/mech_common.sh
source "$MECH_DIR/lib/mech_common.sh"

TREE="" BASELINE="" OUT="" TIMEOUT=600
UNSET_VARS=() SUITES=()

usage() { sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

while [ $# -gt 0 ]; do
  case "$1" in
    --tree)        TREE="${2:-}"; shift 2 ;;
    --baseline)    BASELINE="${2:-}"; shift 2 ;;
    --out)         OUT="${2:-}"; shift 2 ;;
    --timeout)     TIMEOUT="${2:-}"; shift 2 ;;
    --unset)       UNSET_VARS+=("${2:-}"); shift 2 ;;
    --suites-from) [ -r "${2:-}" ] || mech_die "--suites-from not readable: ${2:-}"
                   while IFS= read -r l; do
                     l="${l%%#*}"; l="$(printf '%s' "$l" | tr -d '[:space:]')"
                     [ -n "$l" ] && SUITES+=("$l")
                   done < "$2"; shift 2 ;;
    -h|--help)     usage; exit "$MECH_EXIT_OK" ;;
    --*)           mech_die "unknown argument: $1 (try --help)" ;;
    *)             SUITES+=("$1"); shift ;;
  esac
done

mech_need timeout
[ -n "$TREE" ] || mech_die "--tree is required"
[ -d "$TREE" ] || mech_die "--tree is not a directory: $TREE"
TREE="$(cd "$TREE" && pwd)"
[ "${#SUITES[@]}" -gt 0 ] || mech_die "no suites given (positional args or --suites-from)"
case "$TIMEOUT" in ''|*[!0-9]*) mech_die "--timeout must be a whole number of seconds: $TIMEOUT" ;; esac

for s in "${SUITES[@]}"; do
  [ -f "$TREE/$s" ] || mech_die "suite not found under tree: $TREE/$s"
done

RESULTS="$(mktemp "${TMPDIR:-/tmp}/mech-fanout.XXXXXX")" || mech_die "cannot create temp file"
LOGDIR="$(mktemp -d "${TMPDIR:-/tmp}/mech-fanout-logs.XXXXXX")" || mech_die "cannot create temp dir"
# LOGDIR joins the trap. It did not, and one run of this tool's own test suite
# left 28 orphaned `mech-fanout-logs.*` directories behind in /tmp — small
# individually, but /tmp is tmpfs here, so they are RAM, and they accumulate
# once per invocation forever (§11.4.14: a test that does not clean up is a
# defect, not a tidiness preference).
trap 'rm -f "$RESULTS"; [ -n "${KEEP_LOGS:-}" ] || rm -rf "$LOGDIR"' EXIT

INSTRUMENT_FAILED=0
printf '%-58s %5s %7s %7s\n' SUITE RC PASSED FAILED

for s in "${SUITES[@]}"; do
  log="$LOGDIR/$(printf '%s' "$s" | tr '/' '_').log"
  cmd=(env)
  for v in "${UNSET_VARS[@]+"${UNSET_VARS[@]}"}"; do cmd+=(-u "$v"); done
  cmd+=(timeout "$TIMEOUT" bash "$TREE/$s")
  "${cmd[@]}" >"$log" 2>&1
  rc=$?
  if [ "$rc" -eq 124 ]; then
    printf '%-58s %5s %7s %7s\n' "$s" "$rc" "TIMEOUT" "TIMEOUT"
    mech_log ERROR "suite timed out after ${TIMEOUT}s: $s (log: $log)"
    INSTRUMENT_FAILED=1
    printf '%s\t%s\t%s\t%s\n' "$s" "$rc" "TIMEOUT" "TIMEOUT" >> "$RESULTS"
    continue
  fi
  if counts="$(mech_parse_summary "$log")"; then
    p="${counts% *}"; f="${counts#* }"
    printf '%-58s %5s %7s %7s\n' "$s" "$rc" "$p" "$f"
    printf '%s\t%s\t%s\t%s\n' "$s" "$rc" "$p" "$f" >> "$RESULTS"
  else
    printf '%-58s %5s %7s %7s\n' "$s" "$rc" "UNPARSED" "UNPARSED"
    mech_log ERROR "no parseable summary from: $s (log: $log)"
    INSTRUMENT_FAILED=1
    printf '%s\t%s\t%s\t%s\n' "$s" "$rc" "UNPARSED" "UNPARSED" >> "$RESULTS"
  fi
done

[ -n "$OUT" ] && { cp "$RESULTS" "$OUT" || mech_die "cannot write --out: $OUT"; }

if [ "$INSTRUMENT_FAILED" -eq 1 ]; then
  printf '\nINSTRUMENT FAILURE: at least one suite could not be measured (logs: %s)\n' "$LOGDIR"
  exit "$MECH_EXIT_CANNOT_RUN"
fi

rm -rf "$LOGDIR"

DELTAS=0
if [ -n "$BASELINE" ]; then
  [ -r "$BASELINE" ] || mech_die "--baseline not readable: $BASELINE"
  printf '\nDELTAS vs %s\n' "$BASELINE"
  while IFS=$'\t' read -r bs brc bp bf; do
    [ -n "$bs" ] || continue
    line="$(awk -F'\t' -v s="$bs" '$1==s {print; exit}' "$RESULTS")"
    if [ -z "$line" ]; then
      printf '  MISSING  %s (in baseline, not run now)\n' "$bs"; DELTAS=$((DELTAS+1)); continue
    fi
    IFS=$'\t' read -r _ nrc np nf <<< "$line"
    if [ "$brc" != "$nrc" ] || [ "$bp" != "$np" ] || [ "$bf" != "$nf" ]; then
      printf '  CHANGED  %s  rc %s->%s  passed %s->%s  failed %s->%s\n' \
        "$bs" "$brc" "$nrc" "$bp" "$np" "$bf" "$nf"
      DELTAS=$((DELTAS+1))
    fi
  done < "$BASELINE"
  while IFS=$'\t' read -r ns _ _ _; do
    [ -n "$ns" ] || continue
    if ! awk -F'\t' -v s="$ns" '$1==s {found=1} END {exit !found}' "$BASELINE"; then
      printf '  NEW      %s (run now, absent from baseline)\n' "$ns"; DELTAS=$((DELTAS+1))
    fi
  done < "$RESULTS"
  [ "$DELTAS" -eq 0 ] && printf '  no deltas\n'
  [ "$DELTAS" -gt 0 ] && exit "$MECH_EXIT_FINDING"
  exit "$MECH_EXIT_OK"
fi

FAILING="$(awk -F'\t' '$4 != "0" {c++} END {print c+0}' "$RESULTS")"
printf '\nsuites=%s failing=%s\n' "${#SUITES[@]}" "$FAILING"
[ "$FAILING" -gt 0 ] && exit "$MECH_EXIT_FINDING"
exit "$MECH_EXIT_OK"
