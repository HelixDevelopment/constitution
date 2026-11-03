#!/usr/bin/env bash
# scripts/run_full_suite.sh — §11.4.40 full-suite retest runner.
#
# PURPOSE   Run every test suite of this repository strictly one at a time, record a
#           closed-vocabulary verdict per suite, and refuse (non-zero exit) when any
#           suite FAILs / TIMEOUTs / ERRORs without being a documented KNOWN failure.
# ENUMERATES (paths relative to --root, sorted, de-duplicated):
#             tests/*/run_all.sh, tests/**/test_*.sh, scripts/gates/cm_*_selftest.sh,
#             scripts/gates/*_selftest.sh  (default set), and
#             scripts/gates/cm_*_mutation_test.sh  (HEAVY set: excluded by default,
#             recorded as SKIPPED-heavy with reason `heavy_excluded`, never omitted;
#             run them with --heavy).
# VERDICTS  PASS | FAIL | SKIP(reason) | TIMEOUT | ERROR | SKIPPED-heavy (heavy, not run)
#             PASS    exit 0 and no terminal "VERDICT/RESULT: SKIP" line
#             SKIP    exit 77, or exit 0 with a terminal line `VERDICT|RESULT: SKIP`
#                     (reason = `reason=<code>` on that line, else `suite_reported_skip`)
#                     SKIP is NEVER counted as PASS and never fails the run.
#             TIMEOUT per-suite timeout hit (exit 124/137)
#             ERROR   suite could not run (exit 126/127) or the runner failed to start it
#             FAIL    any other non-zero exit
#             Verdicts come from the suite's own exit code / terminal line only.
# ISOLATION each suite runs as `env HOME=<fresh mktemp dir> nice -n 15 ionice -c3
#           timeout -k 10 <T> bash <suite>` with cwd = --root; the temp HOME is deleted
#           with safe_rm_rf (§11.4.287). The environment is never printed or logged.
# OUTPUT    <out>/results.jsonl (one JSON object per suite), <out>/logs/<n>.log (own log
#           per suite), <out>/summary.txt (counts, non-PASS list, KNOWN matches).
# KNOWN     --known FILE (default docs/design/known_failures_v73.md under --root): a
#           failing suite is KNOWN when its relative path, or (for cm_* gates) its
#           CM-NAME, occurs literally in that file. KNOWN is shown, never hidden, and
#           does not make the exit status non-zero. Coarse literal match: UNCONFIRMED
#           that the documented cause is the cause of a given run; review the list.
# RESUME    results are keyed by (commit sha, suite); a re-run with the same --out and
#           HEAD skips suites already recorded. --rerun-nonpass re-executes recorded
#           FAIL/TIMEOUT/ERROR entries (the old record is superseded, last wins).
# EXIT      0 = no unexplained FAIL/TIMEOUT/ERROR; 1 = at least one; 2 = usage error.
# USAGE     run_full_suite.sh [--root DIR] [--out DIR] [--timeout SEC] [--heavy]
#                             [--known FILE] [--rerun-nonpass] [--list] [--only REGEX]
#           Defaults: root = repository containing this script, timeout 900 (run_all.sh
#           suites 1800), out = <root>/.full_suite_out/<sha>.
# SELFTEST  bash tests/test_run_full_suite.sh
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/.." && pwd); OUT=""; TMO=900; HEAVY=0; KNOWN=""; RERUN=0; LIST=0; ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) ROOT=$(cd "${2:?}" && pwd) || exit 2; shift 2;;
    --out) OUT=${2:?}; shift 2;;
    --timeout) TMO=${2:?}; shift 2;;
    --heavy) HEAVY=1; shift;;
    --known) KNOWN=${2:?}; shift 2;;
    --rerun-nonpass) RERUN=1; shift;;
    --list) LIST=1; shift;;
    --only) ONLY=${2:?}; shift 2;;
    -h|--help) sed -n '2,41p' "${BASH_SOURCE[0]}"; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done
case "$TMO" in ''|*[!0-9]*) echo "bad --timeout" >&2; exit 2;; esac
# shellcheck source=lib/safe_rm.sh
. "$HERE/lib/safe_rm.sh" || { echo "cannot source safe_rm.sh" >&2; exit 2; }
SHA=$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo nogit)
DIRTY=false; [ -n "$(git -C "$ROOT" status --porcelain 2>/dev/null | head -1)" ] && DIRTY=true
[ -n "$OUT" ] || OUT="$ROOT/.full_suite_out/$SHA"
[ -n "$KNOWN" ] || KNOWN="$ROOT/docs/design/known_failures_v73.md"
SCRATCH=${FULL_SUITE_TMPDIR:-${TMPDIR:-/tmp}}

# --- enumerate
enumerate() {
  ( cd "$ROOT" || exit 1
    { ls tests/*/run_all.sh 2>/dev/null
      find tests -type f -name 'test_*.sh' 2>/dev/null
      ls scripts/gates/*_selftest.sh 2>/dev/null
      ls scripts/gates/cm_*_mutation_test.sh 2>/dev/null
    } | LC_ALL=C sort -u )
}
is_heavy() { case "$1" in scripts/gates/cm_*_mutation_test.sh) return 0;; *) return 1;; esac; }
mapfile -t SUITES < <(enumerate)
[ -n "$ONLY" ] && { mapfile -t SUITES < <(printf '%s\n' "${SUITES[@]}" | grep -E -- "$ONLY"); }
nheavy=0; for s in "${SUITES[@]}"; do is_heavy "$s" && nheavy=$((nheavy+1)); done
if [ "$LIST" = 1 ]; then
  for s in "${SUITES[@]}"; do if is_heavy "$s" && [ "$HEAVY" = 0 ]; then echo "SKIPPED-heavy $s"; else echo "RUN $s"; fi; done
  echo "enumerated=${#SUITES[@]} heavy=$nheavy"; exit 0
fi
[ "${#SUITES[@]}" -gt 0 ] || { echo "no suites enumerated under $ROOT" >&2; exit 2; }

mkdir -p "$OUT/logs" || exit 2
RES="$OUT/results.jsonl"; touch "$RES"
jstr() { local s=${1//\\/\\\\}; s=${s//\"/\\\"}; s=${s//$'\t'/ }; s=${s//$'\n'/ }; printf '%s' "$s"; }
cm_name() { local b; b=$(basename "$1" .sh); case "$b" in cm_*) b=${b%_mutation_test}; b=${b%_selftest}; printf '%s' "$b" | tr 'a-z_' 'A-Z-';; esac; }
is_known() { # $1 suite -> 0 if matched in KNOWN file
  [ -r "$KNOWN" ] || return 1
  grep -qF -- "$1" "$KNOWN" && return 0
  local n; n=$(cm_name "$1"); [ -n "$n" ] && grep -qF -- "$n" "$KNOWN" && return 0
  return 1
}
recorded() { grep -qF "\"suite\":\"$(jstr "$1")\"" "$RES" && grep -F "\"suite\":\"$(jstr "$1")\"" "$RES" | grep -qF "\"sha\":\"$SHA\""; }
last_verdict() { grep -F "\"suite\":\"$(jstr "$1")\"" "$RES" | grep -F "\"sha\":\"$SHA\"" | tail -1 | sed 's/.*"verdict":"\([^"]*\)".*/\1/'; }
emit() { # suite verdict reason rc secs idx
  local kn=false
  case "$2" in FAIL|TIMEOUT|ERROR) is_known "$1" && kn=true;; esac
  printf '{"suite":"%s","sha":"%s","dirty":%s,"verdict":"%s","reason":"%s","rc":%s,"secs":%s,"log":"logs/%s.log","known":%s,"ts":"%s"}\n' \
    "$(jstr "$1")" "$SHA" "$DIRTY" "$2" "$(jstr "$3")" "$4" "$5" "$6" "$kn" "$(date -u +%FT%TZ)" >> "$RES"
}

n=0; total=${#SUITES[@]}
for s in "${SUITES[@]}"; do
  n=$((n+1)); idx=$(printf '%04d' "$n")
  if recorded "$s"; then
    lv=$(last_verdict "$s")
    case "$lv" in FAIL|TIMEOUT|ERROR) [ "$RERUN" = 1 ] || { echo "[$n/$total] resumed $s ($lv)"; continue; };; *) echo "[$n/$total] resumed $s ($lv)"; continue;; esac
  fi
  if is_heavy "$s" && [ "$HEAVY" = 0 ]; then
    emit "$s" SKIPPED-heavy heavy_excluded 0 0 "$idx"; echo "[$n/$total] SKIPPED-heavy $s"; continue
  fi
  t=$TMO; case "$s" in tests/*/run_all.sh) [ "$TMO" -lt 1800 ] && t=$((TMO*2));; esac
  H=$(mktemp -d "$SCRATCH/fsr_home.XXXXXX") || { emit "$s" ERROR mktemp_failed 0 0 "$idx"; continue; }
  LOG="$OUT/logs/$idx.log"; t0=$(date +%s)
  ( cd "$ROOT" && exec env HOME="$H" nice -n 15 ionice -c3 timeout -k 10 "$t" bash "$s" ) >"$LOG" 2>&1 </dev/null
  rc=$?; secs=$(( $(date +%s) - t0 ))
  safe_rm_rf "$H" || echo "WARN: could not remove temp HOME for $s" >&2
  v=FAIL; reason=""
  case "$rc" in
    0) v=PASS
       tl=$(grep -E '^[[:space:]]*(==[[:space:]]*)?(VERDICT|RESULT)[:=]?[[:space:]]*SKIP' "$LOG" | tail -1)
       if [ -n "$tl" ]; then v=SKIP; reason=$(printf '%s' "$tl" | sed -n 's/.*reason[= ]\([A-Za-z0-9_]*\).*/\1/p'); [ -n "$reason" ] || reason=suite_reported_skip; fi;;
    77) v=SKIP; reason=$(grep -E 'reason[= ][A-Za-z0-9_]+' "$LOG" | tail -1 | sed -n 's/.*reason[= ]\([A-Za-z0-9_]*\).*/\1/p'); [ -n "$reason" ] || reason=suite_reported_skip;;
    124|137) v=TIMEOUT; reason="timeout_${t}s";;
    126|127) v=ERROR; reason="exec_failed_rc_$rc";;
    *) v=FAIL; reason="rc_$rc";;
  esac
  emit "$s" "$v" "$reason" "$rc" "$secs" "$idx"
  echo "[$n/$total] $v ${reason:+($reason) }$s ${secs}s"
done

# --- summary (only records for this sha; last record per suite wins)
SUM="$OUT/summary.txt"
awk -v sha="$SHA" '
  index($0,"\"sha\":\"" sha "\"") {
    s=$0; sub(/^\{"suite":"/,"",s); sub(/".*/,"",s)
    v=$0; sub(/.*"verdict":"/,"",v); sub(/".*/,"",v)
    r=$0; sub(/.*"reason":"/,"",r); sub(/".*/,"",r)
    k=($0 ~ /"known":true/)?"K":"-"
    sec=$0; sub(/.*"secs":/,"",sec); sub(/,.*/,"",sec)
    V[s]=v; R[s]=r; K[s]=k; S[s]=sec; if(!(s in O)){O[s]=++c; N[c]=s}
  }
  END { for(i=1;i<=c;i++){ s=N[i]; print V[s] "\t" R[s] "\t" K[s] "\t" S[s] "\t" s } }' "$RES" > "$OUT/.final.tsv"
{
  echo "full-suite summary  sha=$SHA dirty=$DIRTY root=$ROOT"
  echo "enumerated=$total (heavy=$nheavy, heavy_run=$HEAVY)"
  for v in PASS FAIL TIMEOUT ERROR SKIP SKIPPED-heavy; do printf '%-14s %s\n' "$v" "$(awk -F'\t' -v v="$v" '$1==v{c++} END{print c+0}' "$OUT/.final.tsv")"; done
  echo "KNOWN (failing but listed in $KNOWN): $(awk -F'\t' '$3=="K"{c++} END{print c+0}' "$OUT/.final.tsv")"
  echo "--- non-PASS suites"
  awk -F'\t' '$1!="PASS"{printf "%s%s  %s  %s\n",$1,($3=="K"?" [KNOWN]":""),$5,($2!=""?"("$2")":"")}' "$OUT/.final.tsv"
  echo "--- total wall seconds (sum): $(awk -F'\t' '{t+=$4} END{print t+0}' "$OUT/.final.tsv")"
} > "$SUM"
cat "$SUM"
bad=$(awk -F'\t' '($1=="FAIL"||$1=="TIMEOUT"||$1=="ERROR") && $3!="K"{c++} END{print c+0}' "$OUT/.final.tsv")
if [ "$bad" -gt 0 ]; then echo "RESULT: FAIL ($bad unexplained FAIL/TIMEOUT/ERROR)"; exit 1; fi
echo "RESULT: OK (no unexplained FAIL/TIMEOUT/ERROR; SKIP is not PASS)"; exit 0
