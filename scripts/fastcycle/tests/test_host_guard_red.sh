#!/bin/sh
# T011 RED test (FR-018, C-007): host_guard.sh must reduce/serialise parallelism
# with a NAMED reason; N derived from live (injected) values, never a literal.
#
# Contract for T012 implementer (UNCONFIRMED: contract C-007 is silent on the
# CLI shape and env-var names; these are defined HERE and are binding on T012):
#   Invocation : sh lib/host_guard.sh <requested_N> [--kind jobs|agents]
#                  [--per-job-mem-kb K] [--threads-per-job T]
#   Stdout     : exactly two lines:  N=<int>=1  and  REASON=<name>
#   REASON set : none | thread_headroom | memory_ceiling | agent_cap | nproc
#   Never raises any limit (no `ulimit -u <bigger>`), exit 0 on success.
#   Injectable env (when set, override the live read):
#     FC_GUARD_NPROC          logical CPU count (live: nproc)
#     FC_GUARD_ULIMIT_U       soft RLIMIT_NPROC (live: ulimit -u)
#     FC_GUARD_THREADS        current user thread count (live: ps -L -U <numeric id -ru>)
#     FC_GUARD_MEM_TOTAL_KB   MemTotal kB (live: /proc/meminfo)
#     FC_GUARD_MEM_AVAIL_KB   MemAvailable kB (live: /proc/meminfo)
#     FC_GUARD_ACTIVE_AGENTS  agents already running (live: registry)
#   Rules: mem budget = 60% of MemTotal minus used(Total-Avail) (§12.6);
#     thread budget = ulimit_u - threads (§12.12); agent cap 6 minus active
#     (§11.4.58, kind=agents only); N never exceeds nproc; floor N=1.
# shellcheck disable=SC2086 # file-wide: every flagged instance is one of the deliberately-unquoted
# fixture variables $AMPLE / $FULL / $MEMOK / $envs -- each holds a SPACE-SEPARATED list of
# `KEY=VALUE` env-var assignments (e.g. "FC_GUARD_MEM_TOTAL_KB=67108864 FC_GUARD_MEM_AVAIL_KB=67000000")
# that MUST word-split so `env $vars cmd ...` / `env $vars sh "$GUARD" ...` sees N separate assignments,
# not one malformed multi-word token; quoting any of them would collapse the whole list into a single
# unparsed string and break every rawrun/run invocation that uses it (T014 round-11 MINOR-4 sweep).
HERE=$(cd "$(dirname "$0")" && pwd)
GUARD="$HERE/../lib/host_guard.sh"
FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }

if [ ! -f "$GUARD" ]; then
  echo "RED: host_guard.sh absent at $GUARD"
  bad "host_guard.sh exists"
  echo "SUMMARY pass=$PASS fail=$FAIL"; exit 1
fi

# collect_envs <env...> -- <args...>: sets CE_ENVS (env words) and CE_SHIFT (words
# consumed incl. "--"). Returns 2 (never loops) when "--" is absent (R4-F8).
collect_envs() {
  CE_SHIFT=0; CE_ENVS=""
  while [ $# -gt 0 ] && [ "$1" != "--" ]; do CE_ENVS="$CE_ENVS $1"; CE_SHIFT=$((CE_SHIFT+1)); shift; done
  [ $# -gt 0 ] || return 2
  CE_SHIFT=$((CE_SHIFT+1)); return 0
}
# run <expected_N> <expected_reason> <label> <env assignments...> -- <args...>
run() {
  exp_n=$1; exp_r=$2; label=$3; shift 3
  collect_envs "$@" || { bad "$label: helper called without --"; return 0; }
  envs=$CE_ENVS; shift $CE_SHIFT
  out=$(env $envs sh "$GUARD" "$@" 2>/dev/null); rc=$?
  n=$(printf '%s\n' "$out" | sed -n 's/^N=//p')
  r=$(printf '%s\n' "$out" | sed -n 's/^REASON=//p')
  if [ $rc -eq 0 ] && [ "$n" = "$exp_n" ] && [ "$r" = "$exp_r" ]; then ok "$label (N=$n reason=$r)"
  else bad "$label expected N=$exp_n reason=$exp_r got rc=$rc N=$n reason=$r"; fi
  LAST_N=$n
}
AMPLE="FC_GUARD_ULIMIT_U=100000 FC_GUARD_THREADS=100 FC_GUARD_MEM_TOTAL_KB=67108864 FC_GUARD_MEM_AVAIL_KB=67000000 FC_GUARD_ACTIVE_AGENTS=0"
# I1 remediation: memory is now ALWAYS read+checked against the 60% ceiling
# (never only when --per-job-mem-kb is passed), so every live-thread/live-nproc
# test below that does NOT itself intend to exercise memory behaviour MUST pin
# an ample memory fixture -- else it is unknowingly hostage to the REAL host's
# live /proc/meminfo state and can flip to a spurious *_exhausted refusal on a
# host that is genuinely over the 60% ceiling at the moment the suite runs
# (11.4.50 deterministic consistency; 11.4.273 control-needle discipline: a
# test whose pass/fail depends on unrelated live host load is an instrument
# trap, not a check on the guard). Same literal ample values as $AMPLE/$FULL.
MEMOK="FC_GUARD_MEM_TOTAL_KB=67108864 FC_GUARD_MEM_AVAIL_KB=67000000"

run 4 none "within all limits keeps request" FC_GUARD_NPROC=8 $AMPLE -- 4 --kind jobs
run 1 thread_headroom "thread headroom 96 / 64 per job serialises" FC_GUARD_NPROC=64 FC_GUARD_ULIMIT_U=4096 FC_GUARD_THREADS=4000 FC_GUARD_MEM_TOTAL_KB=67108864 FC_GUARD_MEM_AVAIL_KB=67000000 FC_GUARD_ACTIVE_AGENTS=0 -- 8 --kind jobs --threads-per-job 64
run 2 memory_ceiling "60% ceiling: budget 23488102kB / 8388608 per job" FC_GUARD_NPROC=64 FC_GUARD_ULIMIT_U=100000 FC_GUARD_THREADS=100 FC_GUARD_MEM_TOTAL_KB=67108864 FC_GUARD_MEM_AVAIL_KB=50331648 FC_GUARD_ACTIVE_AGENTS=0 -- 8 --kind jobs --per-job-mem-kb 8388608
run 6 agent_cap "agent cap 6 with none active" FC_GUARD_NPROC=64 $AMPLE -- 10 --kind agents
run 4 agent_cap "agent cap 6 minus 2 active" FC_GUARD_NPROC=64 FC_GUARD_ULIMIT_U=100000 FC_GUARD_THREADS=100 FC_GUARD_MEM_TOTAL_KB=67108864 FC_GUARD_MEM_AVAIL_KB=67000000 FC_GUARD_ACTIVE_AGENTS=2 -- 10 --kind agents

# Derivation: two different injected nproc give two different N equal to nproc.
run 4 nproc "nproc=4 caps request 100" FC_GUARD_NPROC=4 $AMPLE -- 100 --kind jobs; a=$LAST_N
run 16 nproc "nproc=16 caps request 100" FC_GUARD_NPROC=16 $AMPLE -- 100 --kind jobs; b=$LAST_N
if [ -n "$a" ] && [ -n "$b" ] && [ "$a" != "$b" ]; then ok "N differs across injected nproc ($a vs $b): not a literal"
else bad "N identical across nproc values ($a vs $b): literal suspected"; fi

# ---- T014 remediation (F1-F5, F17): each case observed RED before the fix ----
# rawrun <label> <env...> -- <args...>: run under timeout, capture rc+stdout.
# RAW_TIMEOUT_S: operator-tunable default, no measured basis; only bounds a hang
# (rc 124 = timeout = hang) so a broken guard cannot stall the suite.
RAW_TIMEOUT_S=5
ERRF=$(mktemp); trap 'rm -f "$ERRF"' EXIT
rawrun() {
  label=$1; shift
  collect_envs "$@" || { bad "$label: helper called without --"; RAW_RC=99; RAW_OUT=""; RAW_N=""; RAW_R=""; return 0; }
  envs=$CE_ENVS; shift $CE_SHIFT
  RAW_OUT=$(env $envs timeout "$RAW_TIMEOUT_S" sh "$GUARD" "$@" 2>"$ERRF"); RAW_RC=$?
  RAW_ERR=$(cat "$ERRF")
  RAW_N=$(printf '%s\n' "$RAW_OUT" | sed -n 's/^N=//p')
  RAW_R=$(printf '%s\n' "$RAW_OUT" | sed -n 's/^REASON=//p')
}
chk() { # label expected_rc expected_n expected_reason
  if [ "$RAW_RC" = "$2" ] && { [ -z "$3" ] || [ "$RAW_N" = "$3" ]; } && { [ -z "$4" ] || [ "$RAW_R" = "$4" ]; }; then ok "$1"
  else
    tm=""; [ "$RAW_RC" = 124 ] && tm=" (rc 124 = timeout(1) fired: guard hung)"
    bad "$1 expected rc=$2 N=$3 reason=$4 got rc=$RAW_RC N=$RAW_N reason=$RAW_R$tm"
  fi
}
cke() { # label pattern: stderr of the last rawrun must contain the pattern
  case $RAW_ERR in *"$2"*) ok "$1" ;; *) bad "$1: stderr lacks '$2': '$RAW_ERR'" ;; esac
}
cke0() { # label: stderr of the last rawrun must be empty
  if [ -z "$RAW_ERR" ]; then ok "$1"; else bad "$1: unexpected stderr: '$RAW_ERR'"; fi
}
HD="$HERE/fixtures/host_guard"
FULL="FC_GUARD_NPROC=8 FC_GUARD_ULIMIT_U=100000 FC_GUARD_THREADS=100 FC_GUARD_MEM_TOTAL_KB=67108864 FC_GUARD_MEM_AVAIL_KB=67000000 FC_GUARD_ACTIVE_AGENTS=0"

# F1 dangling flag must exit 2 (not hang; rc 124 = timeout = hang)
for f in --kind --per-job-mem-kb --threads-per-job; do
  rawrun x $FULL -- 4 $f; chk "F1 dangling $f exits 2" 2 "" ""
done
# F5 unknown flag exits 2
rawrun x $FULL -- 4 --per-job-mem 500; chk "F5 unknown flag exits 2" 2 "" ""
rawrun x $FULL -- 4 --kind bogus; chk "F5 bad --kind value exits 2" 2 "" ""
# F2 huge / non-decimal request rejected exit 2
rawrun x $FULL -- 99999999999999999999; chk "F2 huge request exits 2" 2 "" ""
rawrun x $FULL -- 0; chk "F2 zero request exits 2" 2 "" ""
rawrun x $FULL -- abc; chk "F2 non-numeric request exits 2" 2 "" ""
rawrun x $FULL -- -3; chk "F2 negative request exits 2" 2 "" ""
rawrun x $FULL -- 008; chk "F2 leading-zero request handled (8)" 0 8 none
# F5 bad numeric flag values exit 2
rawrun x $FULL -- 4 --threads-per-job x; chk "F5 non-numeric threads-per-job exits 2" 2 "" ""
rawrun x $FULL -- 4 --threads-per-job 0; chk "F5 zero threads-per-job exits 2" 2 "" ""
rawrun x $FULL -- 4 --per-job-mem-kb 0; chk "F5 zero per-job-mem exits 2" 2 "" ""
# F3 ps failure => unreadable, conservative N=1 with named reason
rawrun x PATH="$HD/shim_psfail:$PATH" $MEMOK FC_GUARD_NPROC=8 FC_GUARD_ULIMIT_U=4096 -- 8
chk "F3 failed ps is unreadable_threads N=1" 0 1 unreadable_threads
# F4 active-agents validation / honesty
rawrun x $FULL FC_GUARD_ACTIVE_AGENTS=-3 -- 10 --kind agents; chk "F4 negative active exits 2" 2 "" ""
rawrun x $FULL FC_GUARD_ACTIVE_AGENTS=abc -- 10 --kind agents; chk "F4 non-numeric active exits 2" 2 "" ""
# B3 remediation: active(9) > cap(6) means the RAW cap (6-9=-3) is already
# <=0 BEFORE this request is considered -- the cap is exhausted, so the guard
# MUST refuse entirely (N=0), never let one more agent through (N=1). Requesting
# MORE than 1 at an already-exhausted limit is exactly the case the reviewer
# found: the reason was correctly named (agent_cap) but the count was wrong
# (was N=1, must be N=0 with the *_exhausted reason).
rawrun x $FULL FC_GUARD_ACTIVE_AGENTS=9 -- 10 --kind agents
chk "F4/B3 active(9)>cap(6): already exhausted, refuses entirely" 0 0 agent_cap_exhausted
rawrun x FC_GUARD_NPROC=8 FC_GUARD_ULIMIT_U=100000 FC_GUARD_THREADS=100 FC_GUARD_MEM_TOTAL_KB=67108864 FC_GUARD_MEM_AVAIL_KB=67000000 -- 10 --kind agents
chk "F4 live agent count not derivable => unreadable_active_agents N=1" 0 1 unreadable_active_agents
# F5 unreadable / inconsistent memory with a mem budget requested
rawrun x FC_GUARD_NPROC=8 FC_GUARD_ULIMIT_U=100000 FC_GUARD_THREADS=100 FC_GUARD_MEM_TOTAL_KB=abc FC_GUARD_MEM_AVAIL_KB=1000 FC_GUARD_ACTIVE_AGENTS=0 -- 8 --per-job-mem-kb 100
chk "F5 garbled MemTotal => unreadable_memory N=1" 0 1 unreadable_memory
rawrun x FC_GUARD_NPROC=8 FC_GUARD_ULIMIT_U=100000 FC_GUARD_THREADS=100 FC_GUARD_MEM_TOTAL_KB=1000 FC_GUARD_MEM_AVAIL_KB=5000 FC_GUARD_ACTIVE_AGENTS=0 -- 8 --per-job-mem-kb 100
chk "F6 avail>total => unreadable_memory N=1" 0 1 unreadable_memory
rawrun x FC_GUARD_NPROC=8 FC_GUARD_ULIMIT_U=garbage FC_GUARD_THREADS=100 FC_GUARD_MEM_TOTAL_KB=67108864 FC_GUARD_MEM_AVAIL_KB=67000000 FC_GUARD_ACTIVE_AGENTS=0 -- 8
chk "F5 garbled ulimit => unreadable_ulimit N=1" 0 1 unreadable_ulimit
rawrun x FC_GUARD_NPROC=8 FC_GUARD_ULIMIT_U=unlimited FC_GUARD_THREADS=100 FC_GUARD_MEM_TOTAL_KB=67108864 FC_GUARD_MEM_AVAIL_KB=67000000 FC_GUARD_ACTIVE_AGENTS=0 -- 8
chk "F5 ulimit unlimited is legitimately no thread clamp" 0 8 none
rawrun x $MEMOK FC_GUARD_NPROC=zz FC_GUARD_ULIMIT_U=100000 FC_GUARD_THREADS=100 -- 8
chk "F5 garbled nproc => unreadable_nproc N=1" 0 1 unreadable_nproc
# F17 (MR2/MR3): live reads, no injection. Shim nproc=3 must drive N=3.
# (I1: memory now always read -- pin it ample so this is not a live-host-load test.)
rawrun x PATH="$HD/shim_nproc3:$PATH" $MEMOK FC_GUARD_ULIMIT_U=1000000 FC_GUARD_THREADS=10 -- 100
chk "F17 live nproc read (shim nproc=3) => N=3 nproc" 0 3 nproc
# live thread read: shim ps prints 90 lines, ulimit 100 => headroom 10
rawrun x PATH="$HD/shim_ps90:$PATH" $MEMOK FC_GUARD_NPROC=64 FC_GUARD_ULIMIT_U=100 -- 50
chk "F17 live thread read (shim ps=90) => N=10 thread_headroom" 0 10 thread_headroom
# un-overridden real host NPROC only: N must not exceed real nproc and must be
# >=1. ulimit/threads/memory/active-agents are ALL pinned ample here (via
# $AMPLE) so this test exercises ONLY the live nproc() read -- on a host with
# high thread pressure an unpinned ulimit/threads pair could otherwise drive
# thread headroom to <=0 (already-exhausted, N=0), which would fail the -ge 1
# assertion below for a reason that has nothing to do with nproc capping.
RN=$(nproc); rawrun x $AMPLE -- 100000
if [ "$RAW_RC" = 0 ] && [ "$RAW_N" -ge 1 ] && [ "$RAW_N" -le "$RN" ]; then ok "F2/F17 live run N=$RAW_N <= real nproc $RN"
else bad "live run N=$RAW_N rc=$RAW_RC vs nproc $RN"; fi

# ---- T014 round-3 (R2-F1, R2-F12, R2-F13): observed RED before the fix ----
# RX2/F3: ps succeeding with EMPTY output is not "zero threads".
rawrun x PATH="$HD/shim_psempty:$PATH" $MEMOK FC_GUARD_NPROC=8 FC_GUARD_ULIMIT_U=4096 -- 8
chk "R3 empty ps output is unreadable_threads N=1" 0 1 unreadable_threads
# RX1: the live thread read must list THREADS (ps -L); shim records its argv.
PSARGS=$(mktemp); rawrun x PATH="$HD/shim_psargs:$PATH" FC_PS_ARGS_FILE="$PSARGS" $MEMOK FC_GUARD_NPROC=64 FC_GUARD_ULIMIT_U=100 -- 50
if grep -qx -- '-L' "$PSARGS"; then ok "R3 live ps invoked with -L (threads, not processes)"
else bad "R3 live ps not invoked with -L: argv=$(tr '\n' ' ' < "$PSARGS")"; fi
chk "R3 shim_psargs 5 threads / ulimit 100 => N=50 none" 0 50 none
# R4: the live read must be scoped to the CURRENT user (-u <user>), not every process.
# ROUND 6 (R5-F5, contract CHANGED - the former assertion here expected the USER env
# var's NAME after -u; it is now the NUMERIC real uid `id -ru`, never the USER var).
# ROUND 7 (R6-F6, contract CHANGED again): RLIMIT_NPROC is charged to the REAL uid, so the census is
# `ps -L --no-headers -U "$(id -ru)"` (-U = real-uid selector per ps --help; -u = EFFECTIVE, no longer used).
# CHANGED assertion: the argv word before the uid is now `-U` (was `-u`) and the uid is `id -ru` (was `id -u`).
if grep -qx -- '-U' "$PSARGS" && ! grep -qx -- '-u' "$PSARGS" && grep -qx -- "$(id -ru)" "$PSARGS" && ! grep -qx -- "${USER:-$(id -un)}" "$PSARGS"; then ok "R7 live ps scoped with -U <numeric REAL uid> (no -u)"
else bad "R7 live ps not scoped to -U real uid $(id -ru): argv=$(tr '\n' ' ' < "$PSARGS")"; fi
# R6 mutation-sweep: --no-headers is load-bearing (a header line would inflate the census by 1).
if grep -qx -- '--no-headers' "$PSARGS"; then ok "R6 live ps invoked with --no-headers"
else bad "R6 live ps lacks --no-headers: argv=$(tr '\n' ' ' < "$PSARGS")"; fi
rm -f "$PSARGS"
# RX1 end-to-end: the -L-requiring shim must yield headroom, not unreadable.
# (I1: memory now always read -- pin it ample so this is not a live-host-load test.)
rawrun x PATH="$HD/shim_ps90:$PATH" $MEMOK FC_GUARD_NPROC=64 FC_GUARD_ULIMIT_U=100 -- 50
chk "R3 -L-verifying shim_ps90 still => N=10 thread_headroom" 0 10 thread_headroom
# R6 (R5-F5): a stale/foreign USER must NOT change the result; shim_ps90 now
# answers only for `-U <real numeric uid>` (round 7: was -u/id -u) (else exit 1), so a USER-keyed census fails.
rawrun x USER=root PATH="$HD/shim_ps90:$PATH" $MEMOK FC_GUARD_NPROC=64 FC_GUARD_ULIMIT_U=100 -- 50
chk "R6 poisoned USER=root: same result N=10 thread_headroom" 0 10 thread_headroom
rawrun x USER=nosuchuser_zz PATH="$HD/shim_ps90:$PATH" $MEMOK FC_GUARD_NPROC=64 FC_GUARD_ULIMIT_U=100 -- 50
chk "R6 poisoned USER=nosuchuser_zz: same result" 0 10 thread_headroom
rawrun x USER= PATH="$HD/shim_ps90:$PATH" $MEMOK FC_GUARD_NPROC=64 FC_GUARD_ULIMIT_U=100 -- 50
chk "R6 empty USER: same result" 0 10 thread_headroom
# R2-F12: SET-BUT-EMPTY override is garbled input, treated identically for every
# variable: named unreadable_* N=1 (ACTIVE_AGENTS: exit 2, as any garbled value).
rawrun x $MEMOK FC_GUARD_NPROC= FC_GUARD_ULIMIT_U=100000 FC_GUARD_THREADS=100 -- 8
chk "R3 empty NPROC override => unreadable_nproc N=1" 0 1 unreadable_nproc
rawrun x $MEMOK FC_GUARD_NPROC=8 FC_GUARD_ULIMIT_U= FC_GUARD_THREADS=100 -- 8
chk "R3 empty ULIMIT_U override => unreadable_ulimit N=1" 0 1 unreadable_ulimit
rawrun x $MEMOK FC_GUARD_NPROC=8 FC_GUARD_ULIMIT_U=100000 FC_GUARD_THREADS= -- 8
chk "R3 empty THREADS override => unreadable_threads N=1" 0 1 unreadable_threads
rawrun x FC_GUARD_NPROC=8 FC_GUARD_ULIMIT_U=100000 FC_GUARD_THREADS=100 FC_GUARD_MEM_TOTAL_KB= FC_GUARD_MEM_AVAIL_KB=1000 -- 8 --per-job-mem-kb 100
chk "R3 empty MEM_TOTAL override => unreadable_memory N=1" 0 1 unreadable_memory
rawrun x $FULL FC_GUARD_ACTIVE_AGENTS= -- 10 --kind agents
chk "R3 empty ACTIVE_AGENTS exits 2 (garbled, per header)" 2 "" ""
# R2-F13: ulimit -u unreadable live => named unreadable_ulimit (never a mis-report).
rawrun x PATH="$HD/shim_psfail:$PATH" $MEMOK FC_GUARD_NPROC=8 FC_GUARD_ULIMIT_U=notanumber -- 8
chk "R3 unreadable ulimit value => unreadable_ulimit N=1" 0 1 unreadable_ulimit

# ---- T014 round-4 (R3-F2 MXV, MXW): live ulimit / live meminfo reads ----
# Host-independent: expectations are derived from the SAME live value read by
# the test itself, so a literal in the guard differs from the real value.
BIG=999999999999   # request and injected nproc: never the binding limit
# MXV: live `ulimit -u` (no FC_GUARD_ULIMIT_U). THREADS=0 => N = ulimit/1.
# shellcheck disable=SC3045
S=$(ulimit -u)
if [ "$S" = unlimited ]; then
  LOWA=1000000
  rawrun x $MEMOK FC_GUARD_NPROC=$BIG FC_GUARD_THREADS=0 -- $BIG
  chk "R4 live ulimit unlimited => no thread clamp N=nproc" 0 "$BIG" none
else
  LOWA=$((S - 1))
  rawrun x $MEMOK FC_GUARD_NPROC=$BIG FC_GUARD_THREADS=0 -- $BIG
  chk "R4 live ulimit -u read (=$S) => N=$S thread_headroom" 0 "$S" thread_headroom
fi
# second, different live value: lower the soft limit inside a subshell (never raises)
if [ "$S" != unlimited ] && [ "$S" -le 1 ]; then echo "SKIP: ulimit -u too small to vary"
else
  RAW_OUT=$(sh -c 'ulimit -u "$1" && FC_GUARD_NPROC=$2 FC_GUARD_THREADS=0 FC_GUARD_MEM_TOTAL_KB="$4" FC_GUARD_MEM_AVAIL_KB="$5" exec timeout '"$RAW_TIMEOUT_S"' sh "$3" "$2"' _ "$LOWA" "$BIG" "$GUARD" 67108864 67000000 2>/dev/null); RAW_RC=$?
  RAW_N=$(printf '%s\n' "$RAW_OUT" | sed -n 's/^N=//p'); RAW_R=$(printf '%s\n' "$RAW_OUT" | sed -n 's/^REASON=//p')
  chk "R4 lowered live ulimit (=$LOWA) => N=$LOWA thread_headroom" 0 "$LOWA" thread_headroom
fi
# MXW: live /proc/meminfo. Avail injected = live MemTotal so budget = 60% MemTotal
# (deterministic); only MemTotal is read live. per-job 1 kB => N = 60% MemTotal.
MT=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
EXPM=$((MT * 60 / 100))
if [ "$EXPM" -le 67108864 ] && [ "$EXPM" -ge $((67108864 * 99 / 100)) ] || [ "$MT" = 67108864 ]; then
  echo "SKIP: live MemTotal coincides with fixture literal 67108864: MXW not distinguishable on this host"
else
  rawrun x FC_GUARD_NPROC=$BIG FC_GUARD_ULIMIT_U=unlimited FC_GUARD_MEM_AVAIL_KB=$MT -- $BIG --per-job-mem-kb 1
  chk "R4 live MemTotal read (=$MT) => N=$EXPM memory_ceiling" 0 "$EXPM" memory_ceiling
fi
# live MemAvailable: total injected = live MemTotal, avail live; N within +-2% MemTotal
# of the value derived from before/after reads (avail may move between reads).
# R4-F7: on a host with MemAvailable < 40% MemTotal the budget floors to 1 and the
# assertion cannot tell a live read from a literal. Discriminating only if the derived
# N differs from what a fixed literal avail (LITAV, the fixture value used elsewhere in
# this file) would give by more than TOL; otherwise SKIP with a named reason (never a
# vacuous PASS).
A1=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
rawrun x FC_GUARD_NPROC=$BIG FC_GUARD_ULIMIT_U=unlimited FC_GUARD_MEM_TOTAL_KB=$MT -- $BIG --per-job-mem-kb 1
A2=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo)
B1=$((MT * 60 / 100 - (MT - A1))); B2=$((MT * 60 / 100 - (MT - A2)))
[ "$B1" -lt 1 ] && B1=1; [ "$B2" -lt 1 ] && B2=1
if [ "$B1" -le "$B2" ]; then LO=$B1; HI=$B2; else LO=$B2; HI=$B1; fi
TOL=$((MT * 2 / 100))
LITAV=67000000
LITN=$((MT * 60 / 100 - (MT - LITAV))); [ "$LITAV" -gt "$MT" ] && LITN=0; [ "$LITN" -lt 1 ] && LITN=1
if [ "$LO" -le 1 ]; then
  echo "SKIP: live MemAvailable $A1 kB < 40% of MemTotal $MT kB: budget floors to 1, live read not discriminating on this host (reason: memavail_floor)"
elif [ "$LITN" -ge $((LO - TOL)) ] && [ "$LITN" -le $((HI + TOL)) ]; then
  echo "SKIP: live MemAvailable $A1 kB coincides within tolerance with fixture literal $LITAV kB: not discriminating on this host (reason: memavail_literal_coincidence)"
elif [ "$RAW_RC" = 0 ] && [ "$RAW_R" = memory_ceiling ] && [ "$RAW_N" -ge $((LO - TOL)) ] && [ "$RAW_N" -le $((HI + TOL)) ]; then
  ok "R4 live MemAvailable read: N=$RAW_N within [$LO,$HI]+-$TOL"
else bad "R4 live MemAvailable read: N=$RAW_N reason=$RAW_R rc=$RAW_RC outside [$LO,$HI]+-$TOL"; fi

# ---- T014 round-5 ----
# MYG: unreadable-reason ORDER. Documented order (guard evaluation order): nproc,
# ulimit, threads, active_agents, memory; the FIRST unreadable input reports its reason.
rawrun x FC_GUARD_NPROC=zz FC_GUARD_ULIMIT_U=garbage FC_GUARD_MEM_TOTAL_KB=abc FC_GUARD_MEM_AVAIL_KB=abc -- 8 --kind agents --per-job-mem-kb 100
chk "R5 all inputs unreadable => first (nproc) reported" 0 1 unreadable_nproc
rawrun x FC_GUARD_NPROC=8 FC_GUARD_ULIMIT_U=garbage FC_GUARD_MEM_TOTAL_KB=abc FC_GUARD_MEM_AVAIL_KB=abc -- 8 --kind agents --per-job-mem-kb 100
chk "R5 ulimit+agents+memory unreadable => ulimit reported" 0 1 unreadable_ulimit
rawrun x FC_GUARD_NPROC=8 FC_GUARD_ULIMIT_U=100000 FC_GUARD_THREADS= FC_GUARD_MEM_TOTAL_KB=abc FC_GUARD_MEM_AVAIL_KB=abc -- 8 --kind agents --per-job-mem-kb 100
chk "R5 threads+agents+memory unreadable => threads reported" 0 1 unreadable_threads
rawrun x FC_GUARD_NPROC=8 FC_GUARD_ULIMIT_U=100000 FC_GUARD_THREADS=100 FC_GUARD_MEM_TOTAL_KB=abc FC_GUARD_MEM_AVAIL_KB=abc -- 8 --kind agents --per-job-mem-kb 100
chk "R5 agents+memory unreadable => active_agents reported" 0 1 unreadable_active_agents
rawrun x FC_GUARD_NPROC=8 FC_GUARD_ULIMIT_U=100000 FC_GUARD_THREADS=100 FC_GUARD_MEM_TOTAL_KB=abc FC_GUARD_MEM_AVAIL_KB=abc -- 8 --per-job-mem-kb 100
chk "R5 only memory unreadable => memory reported" 0 1 unreadable_memory
# a clamp reason set earlier is replaced by a later unreadable one; a later clamp never overrides unreadable
rawrun x $MEMOK FC_GUARD_NPROC=4 FC_GUARD_ULIMIT_U=garbage -- 8
chk "R5 nproc clamp then unreadable ulimit => unreadable_ulimit" 0 1 unreadable_ulimit
rawrun x $MEMOK FC_GUARD_NPROC=zz FC_GUARD_ULIMIT_U=100000 FC_GUARD_THREADS=99999 -- 8
chk "R5 unreadable nproc then thread clamp => still unreadable_nproc" 0 1 unreadable_nproc
# R4-F8: helper without "--" must fail fast, not spin (watchdog-bounded)
RF=$(mktemp)
( collect_envs A=1 B=2 >/dev/null 2>&1; echo $? >"$RF" ) & CP=$!
w=0; while kill -0 "$CP" 2>/dev/null && [ $w -lt 30 ]; do sleep 0.1; w=$((w+1)); done
if kill -0 "$CP" 2>/dev/null; then kill "$CP" 2>/dev/null; bad "R5 collect_envs without -- spins (helper hang)"
elif [ "$(cat "$RF")" = 2 ]; then ok "R5 collect_envs without -- returns 2 (no spin)"
else bad "R5 collect_envs without -- rc=$(cat "$RF") expected 2"; fi
rm -f "$RF"
if collect_envs A=1 B=2 -- x y && [ "$CE_SHIFT" = 3 ] && [ "$CE_ENVS" = " A=1 B=2" ]; then ok "R5 collect_envs with -- parses env words"
else bad "R5 collect_envs parse: shift=$CE_SHIFT envs=$CE_ENVS"; fi
# rawrun / chk: a call without -- is a reported failure (RAW_RC=99), never a spin
RO=$(rawrun x FC_GUARD_NPROC=4; echo "rc=$RAW_RC")   # subshell: its FAIL line is not counted
case $RO in *"helper called without --"*"rc=99") ok "R5 rawrun without -- fails fast, reports (rc=99)" ;; *) bad "R5 rawrun without -- did not report: $RO" ;; esac

# ---- T014 round-5 mutation-sweep additions (each closes a survivor of the sweep) ----
# die(): message must reach STDERR (not another fd / stdout) and name the cause.
rawrun x $FULL -- 4 --kind; cke "R5 dangling flag message on stderr" "requires a value"
[ -z "$RAW_OUT" ] && ok "R5 die writes nothing to stdout" || bad "R5 die polluted stdout: $RAW_OUT"
rawrun x $FULL --; cke "R5 missing N message" "missing requested N"
rawrun x $FULL -- 1000000000000; chk "R5 13-digit request rejected" 2 "" ""; cke "R5 13-digit message names the cap" "12 digits"
rawrun x $FULL -- 999999999999; chk "R5 12-digit request accepted" 0 8 nproc
rawrun x $FULL -- 99999999999999999999; cke "R5 20-digit request message" "12 digits"
rawrun x $FULL -- 0; cke "R5 zero request message" ">= 1"
rawrun x $FULL -- 4 --per-job-mem-kb 0; cke "R5 zero per-job-mem message" ">= 1"
rawrun x $FULL -- 4 --threads-per-job 0; cke "R5 zero threads-per-job message" ">= 1"
rawrun x $FULL -- 1; chk "R5 request 1 accepted (boundary)" 0 1 none
rawrun x $FULL -- 4 --threads-per-job 1; chk "R5 threads-per-job 1 accepted (boundary)" 0 4 none
rawrun x $FULL -- 4 --per-job-mem-kb 1; chk "R5 per-job-mem 1 accepted (boundary)" 0 4 none
rawrun x $FULL -- 4 --bogus; cke "R5 unknown-flag message" "unknown argument"
# I1 remediation: memory is now ALWAYS read+checked against the 60% ceiling,
# regardless of whether --per-job-mem-kb was passed -- garbled memory is
# therefore NEVER "irrelevant": it is unreadable_memory even without a
# per-job estimate (the ceiling itself must never be silently skipped).
rawrun x FC_GUARD_NPROC=8 FC_GUARD_ULIMIT_U=100000 FC_GUARD_THREADS=100 FC_GUARD_MEM_TOTAL_KB=abc FC_GUARD_MEM_AVAIL_KB=abc -- 4
chk "R5/I1 garbled memory is unreadable_memory even without --per-job-mem-kb" 0 1 unreadable_memory
# nproc boundaries and shape (I1: memory now always read -- pin it ample)
rawrun x $MEMOK FC_GUARD_NPROC=1 FC_GUARD_ULIMIT_U=100000 FC_GUARD_THREADS=100 -- 8; chk "R5 nproc=1 is valid (clamp nproc)" 0 1 nproc
rawrun x $MEMOK FC_GUARD_NPROC=0 FC_GUARD_ULIMIT_U=100000 FC_GUARD_THREADS=100 -- 8; chk "R5 nproc=0 unreadable_nproc" 0 1 unreadable_nproc
rawrun x $MEMOK FC_GUARD_NPROC=+5 FC_GUARD_ULIMIT_U=100000 FC_GUARD_THREADS=100 -- 8; chk "R5 signed nproc +5 unreadable_nproc" 0 1 unreadable_nproc
rawrun x FC_GUARD_NPROC=zz FC_GUARD_ULIMIT_U=100000 FC_GUARD_THREADS=100 -- 8; cke0 "R5 garbled nproc: no stderr noise"
# B3 remediation: headroom<=0 means the limit is ALREADY exhausted BEFORE this
# request -- the guard must refuse entirely (N=0 with the *_exhausted reason),
# never let one more unit through (N=1). (These were previously mis-asserted
# as "floors to 1"; that floor is reserved for genuinely POSITIVE remaining
# headroom, see the leading-zeros cases immediately below which stay N>=1.)
rawrun x FC_GUARD_NPROC=64 FC_GUARD_ULIMIT_U=50 FC_GUARD_THREADS=100 -- 8; chk "R5/B3 ulimit(50)<threads(100): raw headroom -50 already exhausted" 0 0 thread_headroom_exhausted
rawrun x FC_GUARD_NPROC=64 FC_GUARD_ULIMIT_U=100 FC_GUARD_THREADS=100 -- 8; chk "R5/B3 ulimit==threads: raw headroom 0 already exhausted" 0 0 thread_headroom_exhausted
# leading zeros are decimal (never octal) for ulimit / threads / active / memory
# (these have genuinely POSITIVE raw headroom/cap: not exhausted, floor/clamp unaffected by B3)
rawrun x $MEMOK FC_GUARD_NPROC=999 FC_GUARD_ULIMIT_U=0100 FC_GUARD_THREADS=10 -- 999; chk "R5 ulimit 0100 is decimal 100 (=>90)" 0 90 thread_headroom
rawrun x $MEMOK FC_GUARD_NPROC=9999 FC_GUARD_ULIMIT_U=1000 FC_GUARD_THREADS=0100 -- 9999; chk "R5 threads 0100 is decimal (=>900)" 0 900 thread_headroom
rawrun x FC_GUARD_NPROC=64 FC_GUARD_ULIMIT_U=100000 FC_GUARD_THREADS=100 FC_GUARD_ACTIVE_AGENTS=08 -- 10 --kind agents; chk "R5/B3 active 08 is decimal 8 (=> cap already exhausted)" 0 0 agent_cap_exhausted
# ulimit unlimited alone is the only non-numeric accepted
rawrun x $MEMOK FC_GUARD_NPROC=8 FC_GUARD_ULIMIT_U=Unlimited FC_GUARD_THREADS=100 -- 8; chk "R5 'Unlimited' (case) is garbled" 0 1 unreadable_ulimit
# memory boundaries: mtot=1/mav=1 valid but budget = 60%*1 - 0 = 0 (integer
# truncation): the ceiling is ALREADY exhausted (B3), not merely "floors to 1"
# -- 1 kB total memory with all of it "available" leaves zero real 60%-budget.
rawrun x FC_GUARD_NPROC=8 FC_GUARD_ULIMIT_U=100000 FC_GUARD_THREADS=100 FC_GUARD_MEM_TOTAL_KB=1 FC_GUARD_MEM_AVAIL_KB=1 -- 8 --per-job-mem-kb 5; chk "R5/B3 mtot=mav=1 valid but budget 0: already exhausted" 0 0 memory_ceiling_exhausted
rawrun x FC_GUARD_NPROC=8 FC_GUARD_ULIMIT_U=100000 FC_GUARD_THREADS=100 FC_GUARD_MEM_TOTAL_KB=0 FC_GUARD_MEM_AVAIL_KB=0 -- 8 --per-job-mem-kb 5; chk "R5 mtot=0 => unreadable_memory" 0 1 unreadable_memory
rawrun x FC_GUARD_NPROC=8 FC_GUARD_ULIMIT_U=100000 FC_GUARD_THREADS=100 FC_GUARD_MEM_TOTAL_KB=1000 FC_GUARD_MEM_AVAIL_KB=1000 -- 8 --per-job-mem-kb 5000; chk "R5 budget<per-job floors to exactly 1" 0 1 memory_ceiling
rawrun x FC_GUARD_NPROC=8 FC_GUARD_ULIMIT_U=100000 FC_GUARD_THREADS=100 FC_GUARD_MEM_TOTAL_KB=1000 FC_GUARD_MEM_AVAIL_KB=abc -- 8 --per-job-mem-kb 5; chk "R5 garbled MemAvail => unreadable_memory" 0 1 unreadable_memory; cke0 "R5 garbled MemAvail: no stderr noise"
rawrun x FC_GUARD_NPROC=8 FC_GUARD_ULIMIT_U=100000 FC_GUARD_THREADS=100 FC_GUARD_MEM_TOTAL_KB=abc FC_GUARD_MEM_AVAIL_KB=1000 -- 8 --per-job-mem-kb 5; cke0 "R5 garbled MemTotal: no stderr noise"
rawrun x FC_GUARD_NPROC=8 FC_GUARD_ULIMIT_U=100000 FC_GUARD_THREADS=100 FC_GUARD_MEM_TOTAL_KB=1000 FC_GUARD_MEM_AVAIL_KB=2000 -- 8 --per-job-mem-kb 5; cke0 "R5 avail>total: no stderr noise"
# failing live tools must be silent on stderr (their diagnostics are swallowed) and named unreadable
rawrun x PATH="$HD/shim_nprocfail:$PATH" $MEMOK FC_GUARD_ULIMIT_U=100000 FC_GUARD_THREADS=100 -- 8; chk "R5 failing live nproc => unreadable_nproc" 0 1 unreadable_nproc; cke0 "R5 failing live nproc: stderr swallowed"
rawrun x PATH="$HD/shim_psfail:$PATH" FC_GUARD_NPROC=8 FC_GUARD_ULIMIT_U=4096 -- 8; cke0 "R5 failing live ps: stderr swallowed"
rawrun x PATH="$HD/shim_awkfail:$PATH" FC_GUARD_NPROC=8 FC_GUARD_ULIMIT_U=100000 FC_GUARD_THREADS=100 -- 8 --per-job-mem-kb 5
chk "R5 failing live awk (MemTotal+MemAvailable) => unreadable_memory" 0 1 unreadable_memory; cke0 "R5 failing live awk: stderr swallowed"
rawrun x PATH="$HD/shim_awkfail:$PATH" FC_GUARD_NPROC=8 FC_GUARD_ULIMIT_U=100000 FC_GUARD_THREADS=100 FC_GUARD_MEM_TOTAL_KB=1000 -- 8 --per-job-mem-kb 5
cke0 "R5 failing live awk (MemAvailable only): stderr swallowed"
rawrun x PATH="$HD/shim_awkfail:$PATH" FC_GUARD_NPROC=8 FC_GUARD_ULIMIT_U=100000 FC_GUARD_THREADS=100 FC_GUARD_MEM_AVAIL_KB=1000 -- 8 --per-job-mem-kb 5
cke0 "R5 failing live awk (MemTotal only): stderr swallowed"

# ---- ROUND 5b: N=0/N=1 boundary kill tests, request==1 (B3 remediation) ----
# BLOCKING finding B3 (Opus review of the Foundational batch): the ORIGINAL
# guard clamped an already-exhausted limit to 1 BEFORE calling clamp(), so when
# the caller's own request also happened to be exactly 1, clamp()'s strict
# less-than test ("only update n/reason if the new value is < current n") never
# fired and REASON silently stayed "none" -- letting a 7th agent past a cap of
# 6, or a job past an exhausted thread/memory ceiling, with NO reason given at
# all. The fix: exhaustion (raw headroom/cap/budget <= 0) is now detected
# BEFORE any floor is applied and unconditionally reports N=0 with a named
# *_exhausted reason, regardless of what the caller requested -- even a
# request of exactly 1 must be refused when the real limit is already blown.
rawrun x FC_GUARD_NPROC=64 FC_GUARD_ULIMIT_U=100 FC_GUARD_THREADS=100 -- 1
chk "R5b/B3 N=0 thread exhaustion: headroom<=0 refuses even a request of 1" 0 0 thread_headroom_exhausted
rawrun x FC_GUARD_NPROC=64 FC_GUARD_ULIMIT_U=unlimited FC_GUARD_ACTIVE_AGENTS=6 -- 1 --kind agents
chk "R5b/B3 N=0 agent exhaustion: cap<=0 refuses even a request of 1" 0 0 agent_cap_exhausted
# memory: budget = 60%*1000 - 0 = 600 kB is GENUINELY POSITIVE headroom, merely
# smaller than the 601 kB per-job estimate -- this is NOT exhaustion (the
# ceiling itself is not yet breached), so the pre-existing floor-to-1 behaviour
# for genuine partial headroom is correct and UNCHANGED by the B3 fix.
rawrun x FC_GUARD_NPROC=64 FC_GUARD_ULIMIT_U=unlimited FC_GUARD_MEM_TOTAL_KB=1000 FC_GUARD_MEM_AVAIL_KB=1000 -- 1 --per-job-mem-kb 601
chk "R5b N=1 memory floor: budget(600)>0 but < per-job(601) is genuine partial headroom, not exhausted" 0 1 none
# ulimit diagnostics must be swallowed: a ulimit that writes stderr must not leak (bash-only, BASH_ENV shim)
if command -v bash >/dev/null 2>&1; then
  RAW_OUT=$(env BASH_ENV="$HD/be_ulimit_leak.sh" $MEMOK FC_GUARD_NPROC=4 FC_GUARD_THREADS=10 timeout "$RAW_TIMEOUT_S" bash "$GUARD" 2 2>"$ERRF"); RAW_RC=$?
  RAW_ERR=$(cat "$ERRF")
  RAW_N=$(printf '%s\n' "$RAW_OUT" | sed -n 's/^N=//p'); RAW_R=$(printf '%s\n' "$RAW_OUT" | sed -n 's/^REASON=//p')
  chk "R5b failing stderr-emitting ulimit => unreadable_ulimit" 0 1 unreadable_ulimit
  cke0 "R5b ulimit stderr swallowed (no leak)"
else
  echo "SKIP: R5b ulimit leak test (bash absent)"
fi

# ---- ROUND 6b/7: `id -ru` vs `id -u` and quoting of "$(id -ru)" (audit-proven non-equivalent mutants) ----
# ROUND 7 CHANGED ASSERTIONS (not weakened; same six mutant classes, axis moved from id -u to id -ru and
# ps -u to ps -U): the id shim values for -u / -ru are SWAPPED versus round 6b, the ps shim wants -U, and
# every "used"/"not repaired"/"one word" expectation now applies to `id -ru`. `id -u` is now the decoy.
# DECISION (11.4.201 conservative-safe): the census uid is `id -ru` output handed to ps as ONE verbatim
# argv word. Empty / non-numeric / multi-word id output is NOT split or repaired; a real ps rejects it,
# the live read fails, and the guard reports the named unreadable_threads with N=1 (never a mis-report).
SH="$HD/shim_id_ps"
# I1 remediation (T014 round-11): memory is now ALWAYS read+checked against
# the 60% ceiling, and round-10's exhaust()/unreadable() precedence fix means
# a genuinely-exhausted limit (e.g. real host memory over budget) now WINS
# over an unrelated unreadable_* finding rather than being masked by it -- so
# EVERY case below, success ("=> N=50 none") AND unreadable_threads failure
# alike, is pinned ample via $MEMOK; none of them is masked "regardless".
rawrun x PATH="$SH:$PATH" $MEMOK FC_ID_RU=1000 FC_ID_U= FC_PS_WANT_UID=1000 FC_GUARD_NPROC=64 FC_GUARD_ULIMIT_U=100 -- 50
chk "R7 id -ru=1000 id -u='' => id -ru used: N=50 none" 0 50 none
rawrun x PATH="$SH:$PATH" $MEMOK FC_ID_RU=1000 FC_ID_U=abc FC_PS_WANT_UID=1000 FC_GUARD_NPROC=64 FC_GUARD_ULIMIT_U=100 -- 50
chk "R7 id -ru=1000 id -u=abc => id -ru used: N=50 none" 0 50 none
rawrun x PATH="$SH:$PATH" $MEMOK FC_ID_RU= FC_ID_U=1000 FC_PS_WANT_UID=1000 FC_GUARD_NPROC=64 FC_GUARD_ULIMIT_U=100 -- 50
chk "R7 id -ru='' id -u=1000 => not repaired: unreadable_threads N=1" 0 1 unreadable_threads
rawrun x PATH="$SH:$PATH" $MEMOK FC_ID_RU=1000_0 FC_ID_U=1000 FC_PS_WANT_UID=1000_0 FC_GUARD_NPROC=64 FC_GUARD_ULIMIT_U=100 -- 50
chk "R7 id -ru='1000 0' passed as ONE word (quoted): N=50 none" 0 50 none
rawrun x PATH="$SH:$PATH" $MEMOK FC_ID_RU=1000_0 FC_ID_U=1000 FC_PS_WANT_UID=1000 FC_GUARD_NPROC=64 FC_GUARD_ULIMIT_U=100 -- 50
chk "R7 id -ru='1000 0' never split to '1000': unreadable_threads N=1" 0 1 unreadable_threads
# ROUND 7 NEW (R6-F6): id shim prints DIFFERENT values for -u (1111, effective) and -ru (2222, real):
# the REAL value must be the one handed to ps -U; the effective one must not be.
rawrun x PATH="$SH:$PATH" $MEMOK FC_ID_U=1111 FC_ID_RU=2222 FC_PS_WANT_UID=2222 FC_GUARD_NPROC=64 FC_GUARD_ULIMIT_U=100 -- 50
chk "R7 id -u=1111 id -ru=2222: ps -U got REAL 2222 => N=50 none" 0 50 none
rawrun x PATH="$SH:$PATH" $MEMOK FC_ID_U=1111 FC_ID_RU=2222 FC_PS_WANT_UID=1111 FC_GUARD_NPROC=64 FC_GUARD_ULIMIT_U=100 -- 50
chk "R7 id -u=1111 id -ru=2222: effective 1111 NOT passed => unreadable_threads N=1" 0 1 unreadable_threads
# `id -ru` itself failing must NOT fall back to the effective uid: named unreadable_threads, N=1.
rawrun x PATH="$SH:$PATH" $MEMOK FC_ID_RU_FAIL=1 FC_ID_U=1000 FC_PS_WANT_UID=1000 FC_GUARD_NPROC=64 FC_GUARD_ULIMIT_U=100 -- 50
chk "R7 id -ru failing => no fallback to id -u: unreadable_threads N=1" 0 1 unreadable_threads
PSARGS=$(mktemp)
rawrun x PATH="$HD/shim_psargs:$SH:$PATH" FC_PS_ARGS_FILE="$PSARGS" FC_ID_U=1111 FC_ID_RU=2222 FC_GUARD_NPROC=64 FC_GUARD_ULIMIT_U=100 -- 50
if grep -qx -- '2222' "$PSARGS" && ! grep -qx -- '1111' "$PSARGS" && grep -qx -- '-U' "$PSARGS"; then ok "R7 ps argv carries -U 2222, never 1111"
else bad "R7 ps argv wrong: $(tr '\n' ' ' < "$PSARGS")"; fi
rm -f "$PSARGS"


# ---- T-REMED (Opus review of the Foundational batch, BLOCKING B3 + IMPORTANT I1) ----
# Regression guards reproducing the reviewer's own literal scenarios verbatim,
# plus false-positive guards proving the fix does NOT over-refuse genuine
# partial headroom (11.4.201: a false-positive refusal is as forbidden as a
# false-negative pass).
#
# B3 (BLOCKING): the guard could never return N=0, even when a limit was
# already exceeded BEFORE any new work started -- it returned N=1 REASON=none.
echo "# T-REMED B3: reviewer's exact scenario 1 (agent cap already exhausted)"
rawrun x FC_GUARD_ACTIVE_AGENTS=6 FC_GUARD_ULIMIT_U=100000 FC_GUARD_THREADS=100 $MEMOK -- 1 --kind agents
chk "T-REMED/B3 6 active >= cap 6, request 1 => refuses entirely" 0 0 agent_cap_exhausted
echo "# T-REMED B3: reviewer's exact scenario 1b (40 agents active against cap 6)"
rawrun x FC_GUARD_ACTIVE_AGENTS=40 FC_GUARD_ULIMIT_U=100000 FC_GUARD_THREADS=100 $MEMOK -- 1 --kind agents
chk "T-REMED/B3 40 active agents >> cap 6, request 1 => refuses entirely" 0 0 agent_cap_exhausted
echo "# T-REMED B3: reviewer's exact scenario 2 (zero thread headroom left)"
rawrun x FC_GUARD_ULIMIT_U=100 FC_GUARD_THREADS=500 FC_GUARD_NPROC=64 $MEMOK -- 1
chk "T-REMED/B3 ulimit=100 threads=500 (zero headroom), request 1 => refuses entirely" 0 0 thread_headroom_exhausted
echo "# T-REMED B3: reviewer's exact scenario 3 (request MORE than 1 at an exhausted cap)"
rawrun x FC_GUARD_ACTIVE_AGENTS=9 FC_GUARD_ULIMIT_U=100000 FC_GUARD_THREADS=100 $MEMOK -- 10 --kind agents
chk "T-REMED/B3 active(9)>cap(6), request 10 => refuses entirely, not N=1" 0 0 agent_cap_exhausted
#
# I1 (IMPORTANT): the 60% memory ceiling was silently skipped unless the
# caller passed --per-job-mem-kb. It is now ALWAYS read and checked.
echo "# T-REMED I1: reviewer's exact scenario (99% memory used, no --per-job-mem-kb)"
rawrun x FC_GUARD_MEM_TOTAL_KB=1000 FC_GUARD_MEM_AVAIL_KB=10 FC_GUARD_ULIMIT_U=100000 FC_GUARD_THREADS=100 FC_GUARD_NPROC=64 -- 16
chk "T-REMED/I1 99% memory used, no per-job flag => ceiling checked, refuses entirely" 0 0 memory_ceiling_exhausted
echo "# T-REMED I1: same caller shape as test_foundational_mutations.sh:57 (--kind jobs --threads-per-job N, no --per-job-mem-kb)"
rawrun x FC_GUARD_MEM_TOTAL_KB=1000 FC_GUARD_MEM_AVAIL_KB=10 FC_GUARD_ULIMIT_U=100000 FC_GUARD_THREADS=100 FC_GUARD_NPROC=64 -- 9 --kind jobs --threads-per-job 8
chk "T-REMED/I1 the real (no-per-job-mem-kb) caller shape still refuses when host memory is exhausted" 0 0 memory_ceiling_exhausted
#
# False-positive guards (11.4.201): genuinely POSITIVE (if small) headroom
# must NOT be treated as exhausted -- the guard must still allow a trickle of
# progress, exactly as before B3/I1, whenever real headroom/budget remains.
echo "# T-REMED false-positive guard: 1 unit of real thread headroom remains (not exhausted)"
rawrun x FC_GUARD_ULIMIT_U=101 FC_GUARD_THREADS=100 FC_GUARD_NPROC=64 $MEMOK -- 8
chk "T-REMED genuine 1-thread headroom is NOT exhausted: floors to N=1" 0 1 thread_headroom
echo "# T-REMED false-positive guard: 1 unit of real agent-cap headroom remains (not exhausted)"
rawrun x FC_GUARD_ACTIVE_AGENTS=5 FC_GUARD_ULIMIT_U=100000 FC_GUARD_THREADS=100 $MEMOK -- 8 --kind agents
chk "T-REMED genuine 1-agent cap headroom is NOT exhausted: clamps to N=1" 0 1 agent_cap
echo "# T-REMED false-positive guard: ample memory (no --per-job-mem-kb) is unaffected by the always-check"
rawrun x $FULL -- 4 --kind jobs
chk "T-REMED ample memory, no per-job flag: unaffected, still N=4 none" 0 4 none

# ---- T014 round-10 (BLOCKING-1 + IMPORTANT-2 remediation) ----
# Opus review of the Foundational batch, round 10: a limit ALREADY confirmed
# exhausted got overridden by an unreadable input on a DIFFERENT limit, so
# N=1 came back instead of the correct N=0 (refuse). Root cause: unreadable()
# set n=1 UNCONFIRMED-ly (no guard against an already-recorded *_exhausted),
# and exhaust() deferred to ANY pre-existing unreadable_* even for an
# unrelated limit. Both temporal orderings are pinned here: (a) a limit is
# confirmed exhausted FIRST, then an UNRELATED limit turns out unreadable;
# (b) an UNRELATED limit is unreadable FIRST, then a limit is confirmed
# exhausted. Both MUST end at N=0 with the exhausted reason preserved -- an
# unreadable finding on a different limit says nothing about a limit already
# confirmed (or later confirmed) exhausted from genuinely valid data, and
# N=0 is already the most conservative answer there is.
echo "# T014/B1 order (a): thread headroom exhausted, THEN memory garbled (different limits)"
rawrun x FC_GUARD_NPROC=8 FC_GUARD_ULIMIT_U=10 FC_GUARD_THREADS=20 FC_GUARD_MEM_TOTAL_KB=abc -- 5
chk "T014/B1(a) exhausted-then-unreadable: N=0 thread_headroom_exhausted preserved" 0 0 thread_headroom_exhausted
echo "# T014/B1 order (a): reviewer's own round-9 scenario -- agent cap exhausted, THEN memory garbled"
rawrun x FC_GUARD_ACTIVE_AGENTS=9 FC_GUARD_ULIMIT_U=100000 FC_GUARD_THREADS=100 FC_GUARD_MEM_AVAIL_KB=zz -- 10 --kind agents
chk "T014/B1(a) B3's round-9 scenario replayed: a 7th agent no longer gets past cap 6" 0 0 agent_cap_exhausted
echo "# T014/B1 order (b): nproc unreadable FIRST, THEN thread headroom exhausted (different limits)"
rawrun x FC_GUARD_NPROC=x FC_GUARD_ULIMIT_U=10 FC_GUARD_THREADS=20 -- 5
chk "T014/B1(b) unreadable-then-exhausted: N=0 thread_headroom_exhausted, not unreadable_nproc" 0 0 thread_headroom_exhausted
echo "# T014/B1 order (b): ulimit unreadable FIRST, THEN agent cap exhausted (different limits)"
rawrun x FC_GUARD_NPROC=8 FC_GUARD_ULIMIT_U=garbage $MEMOK FC_GUARD_ACTIVE_AGENTS=9 -- 10 --kind agents
chk "T014/B1(b) unreadable-ulimit-then-exhausted-agent-cap: N=0 agent_cap_exhausted, not unreadable_ulimit" 0 0 agent_cap_exhausted
echo "# T014/B1 order (b): ulimit unreadable FIRST, THEN memory ceiling exhausted (different limits)"
rawrun x FC_GUARD_NPROC=8 FC_GUARD_ULIMIT_U=garbage FC_GUARD_MEM_TOTAL_KB=1 FC_GUARD_MEM_AVAIL_KB=1 -- 5
chk "T014/B1(b) unreadable-ulimit-then-exhausted-memory: N=0 memory_ceiling_exhausted, not unreadable_ulimit" 0 0 memory_ceiling_exhausted
echo "# T014/B1 insurance: TWO separate exhaustions (thread first in eval order, agent cap second) -- first exhaustion still wins, unaffected by the exhaust()/unreadable() fix"
rawrun x FC_GUARD_NPROC=64 FC_GUARD_ULIMIT_U=10 FC_GUARD_THREADS=20 FC_GUARD_ACTIVE_AGENTS=9 -- 10 --kind agents
chk "T014/B1 two exhaustions: first (thread_headroom_exhausted) stands over the later (agent_cap_exhausted)" 0 0 thread_headroom_exhausted

echo "SUMMARY pass=$PASS fail=$FAIL"
[ $FAIL -eq 0 ]
