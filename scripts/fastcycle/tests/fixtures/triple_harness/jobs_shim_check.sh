#!/bin/bash
# jobs_shim_check.sh <harness|deps> <tests-dir> : R7b checks of the reap_jobs pid source (the shell's
# `jobs`) with a SHIMMED `jobs` and a LOG-ONLY `kill` (nothing is ever really signalled: the values fed
# to the unit include 0, 1 and -1, so a real `kill -- -1` would be a disaster; constitution 11.4.263).
# The unit runs under a wrapper shell that sources the shims and then the unit itself; the harness gets
# a TERM while its tool runs, the deps unit reaps in its EXIT trap. Pids in the fake job lists are
# above kernel.pid_max, so they can never name a real process.
# Cases: valid (both lists) / dashjobs (`jobs -r` rejected on stderr like dash; only `jobs -p` works) /
# canary (`jobs -p` lists a stale, done job that `jobs -rp` does not: it must never be signalled, i.e.
# the pid-namespace canary) / badvals (0 1 -1 empty non-numeric multi-word backslash-line -> NO kill and
# NO stderr text, both jobs forms). Rule: every logged kill is `-s KILL N` or `-s KILL -- -N`, N > 1.
# kind `runall` runs run_all.sh the same way (its signal handler TERMs, waits, then KILLs the jobs' groups): the
# logged `-0 N` liveness probes are ignored and `-s TERM N` lines are legal (N > 1 as ever).
# Prints `FAIL ...` lines only (or `SKIP <reason>`); exit 0 always. Every child is reaped on every exit.
kind=$1; here=$2
command -v setsid >/dev/null 2>&1 || true
W=$(mktemp -d) || exit 2
trap 'rm -rf "$W"' EXIT
PM=$(cat /proc/sys/kernel/pid_max 2>/dev/null); case $PM in ''|*[!0-9]*) echo "SKIP pid_max_unreadable"; exit 0 ;; esac
F1=$((PM + 101)); F2=$((PM + 202))
cat >"$W/shim.sh" <<'EOF'
# shellcheck disable=SC2317  # the functions below are invoked by the sourced unit
jobs() {
  case "$*" in
    *r*) if [ "${JM-}" = rej ]; then echo "jobs: Illegal option -r" >&2; return 2; fi
         [ -z "${JR-}" ] || printf '%s\n' "$JR" ;;
    *)   [ -z "${JP-}" ] || printf '%s\n' "$JP" ;;
  esac
}
kill() { printf '%s\n' "$*" >>"$KL"; return 0; }
EOF
printf '#!/bin/sh\nexec sleep 1\n' >"$W/tool.sh"; chmod +x "$W/tool.sh"
mkdir "$W/ratests"; printf '#!/bin/sh\nexec sleep 1\n' >"$W/ratests/test_a.sh"
mkdir "$W/bin"; for b in mktemp head rm sh bash sleep sed timeout; do ln -s "$(command -v $b)" "$W/bin/$b"; done
BASHX=$(command -v bash)
BAD=$(printf '%s\n' 0 1 -1 '' abc '2 3' '1 5' '7 -o 7' '1\2' '   ' -5 00 01 x1 1x '!' -gt)
# run_case <name> <JR> <JP> <JM> <expected-lines|separated>
run_case() {
  name=$1; export JR=$2 JP=$3 JM=$4; want=$5
  export KL="$W/kill.log"; : >"$KL"; rm -f "$W/err"
  if [ "$kind" = harness ]; then
    env FASTCYCLE_TOOL_TIMEOUT=2 sh -c '. "$1"; u=$2; shift 2; . "$u" "$@"' sh "$W/shim.sh" "$here/lib/triple_harness.sh" \
      --tool "$W/tool.sh" --fixtures "$here/fixtures/triple_harness/sound" >/dev/null 2>"$W/err" &
    hp=$!
    i=0; hit=""
    while [ -z "$hit" ] && [ "$i" -lt 250 ]; do
      hit=$(ps -eo pid=,ppid=,args= 2>/dev/null | awk -v p="$hp" -v k="$W/tool.sh" '$2==p && index($0,k){print $1; exit}')
      [ -n "$hit" ] || { sleep 0.02; i=$((i + 1)); }
    done
    [ -n "$hit" ] || { kill -s KILL "$hp" 2>/dev/null; wait "$hp" 2>/dev/null; echo "FAIL r7b jobs shim ($kind/$name): the harness never started its tool"; return; }
    sleep 0.15; kill -s TERM "$hp" 2>/dev/null
    wait "$hp"; rc=$?
    [ "$rc" -eq 2 ] || echo "FAIL r7b jobs shim ($kind/$name): TERM must exit 2, got $rc"
  elif [ "$kind" = runall ]; then
    env FASTCYCLE_TEST_TIMEOUT=30 sh -c '. "$1"; u=$2; shift 2; . "$u" "$@"' sh "$W/shim.sh" "$here/run_all.sh" "$W/ratests" >/dev/null 2>"$W/err" &
    hp=$!
    i=0; hit=""
    while [ -z "$hit" ] && [ "$i" -lt 250 ]; do
      hit=$(ps -eo pid=,ppid=,args= 2>/dev/null | awk -v p="$hp" -v k="$W/ratests/test_a.sh" '$2==p && index($0,k){print $1; exit}')
      [ -n "$hit" ] || { sleep 0.02; i=$((i + 1)); }
    done
    [ -n "$hit" ] || { kill -s KILL "$hp" 2>/dev/null; wait "$hp" 2>/dev/null; echo "FAIL r7b jobs shim ($kind/$name): the runner never started its test"; return; }
    sleep 0.15; kill -s TERM "$hp" 2>/dev/null
    wait "$hp"; rc=$?
    [ "$rc" -eq 2 ] || echo "FAIL r7b jobs shim ($kind/$name): TERM must exit 2, got $rc"
  else
    env PATH="$W/bin" "$BASHX" -c '. "$1"; . "$2"' bash "$W/shim.sh" "$here/check_deps.sh" >/dev/null 2>"$W/err"
    rc=$?
    [ "$rc" -eq 4 ] || echo "FAIL r7b jobs shim ($kind/$name): expected the BLIND exit 4 (no tool on the scrubbed PATH), got $rc"
    sed -i '/^BLIND: missing\/unusable:/d' "$W/err"
  fi
  [ ! -s "$W/err" ] || echo "FAIL r7b jobs shim ($kind/$name): unit wrote to stderr (jobs errors / test errors must be silenced): $(head -c 200 "$W/err")"
  verdict=$(awk -v fk="$F1 $F2" -v want="$want" -v kind="$kind" '
    BEGIN { n = split(fk, F, " "); for (i = 1; i <= n; i++) isf[F[i]] = 1; m = split(want, Wn, "|"); for (i = 1; i <= m; i++) if (Wn[i] != "") w[Wn[i]] = 1 }
    { line = $0
      if (kind == "runall" && line ~ /^-0 /) next
      if (kind == "runall") sub(/^-s TERM /, "-s KILL ", line)
      if (line !~ /^-s KILL (-- -)?[0-9]+$/) { print "BADLINE[" line "]"; next }
      grp = (line ~ /^-s KILL -- -/); num = line; sub(/^-s KILL (-- -)?/, "", num)
      if (num + 0 <= 1) { print "PGID<=1[" line "]"; next }
      if (num in isf) { got[line] = 1; next }
      if (!grp) print "STRAYPID[" line "]"
    }
    END { for (k in w) if (!(k in got)) print "MISSING[" k "]"; for (k in got) if (!(k in w)) print "UNEXPECTED[" k "]" }' "$KL" | sort | tr '\n' ' ')
  [ -z "$verdict" ] || echo "FAIL r7b jobs shim ($kind/$name): $verdict"
}
V1="-s KILL $F1|-s KILL -- -$F1"; V2="-s KILL $F2|-s KILL -- -$F2"
run_case valid      "$F1
$F2" "$F1
$F2" ok "$V1|$V2"
run_case dashjobs   "" "$F1" rej "$V1"
run_case canary     "$F1" "$F1
$F2" ok "$V1"
run_case badvals-ok  "$BAD
$F1" "$BAD
$F2" ok "$V1"
# R7-F1: zsh (also as sh) prints whole job lines; the pid of a `[N] [+-] PID ...` line is taken, a line whose
# pid is <= 1 or which is anything else is not signalled.
run_case zshfmt      "[1]  + $F1 running    sleep 5
[2]  - $F2 running    sleep 6" "" ok "$V1|$V2"
run_case zshbad      "[1]  + 1 running    sleep 5
[2]  - 0 running    x
[3]  + -1 running    x
[4]+ 5x running y
[1] $F1 running" "" ok "$V1"
run_case badvals-rej "" "$BAD
$F1" rej "$V1"
# the harness tool sleeps at most 1 s: let any orphaned `timeout`/sleep finish, then prove nothing is left
sleep 1.6
left=$(ps -eo pid=,args= 2>/dev/null | awk -v k="$W/tool.sh" '$2 != "awk" && index($0,k)' | head -3)
[ -z "$left" ] || echo "FAIL r7b jobs shim ($kind): leftover process after the run: $left"
exit 0
