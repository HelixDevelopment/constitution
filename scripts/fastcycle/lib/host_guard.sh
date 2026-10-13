#!/bin/sh
# host_guard.sh - clamp requested parallelism to host limits (FR-018, C-007).
# Purpose : reduce/serialise fan-out with a named reason; never raises a limit.
# Usage   : sh host_guard.sh <N> [--kind jobs|agents] [--per-job-mem-kb K]
#                            [--threads-per-job T]
#           N, K, T: positive decimal integers, at most 12 digits.
# Inputs  : env overrides FC_GUARD_NPROC, FC_GUARD_ULIMIT_U, FC_GUARD_THREADS,
#           FC_GUARD_MEM_TOTAL_KB, FC_GUARD_MEM_AVAIL_KB, FC_GUARD_ACTIVE_AGENTS;
#           unset => live read (nproc, ulimit -u, ps -L, /proc/meminfo).
#           SET-BUT-EMPTY is garbled input, handled like any non-numeric value
#           of that variable (never silently a live read): unreadable_* N=1.
#           No live source exists for the active-agent count: for --kind agents
#           FC_GUARD_ACTIVE_AGENTS MUST be supplied, else unreadable_active_agents.
# Outputs : stdout "N=<int>" and "REASON=<none|thread_headroom|memory_ceiling|
#           agent_cap|nproc|thread_headroom_exhausted|memory_ceiling_exhausted|
#           agent_cap_exhausted|unreadable_nproc|unreadable_ulimit|
#           unreadable_threads|unreadable_memory|unreadable_active_agents>".
#           Exit 0.
#           EXHAUSTED (B3): when a limit's REAL, pre-floor headroom/cap/budget
#           (thread ulimit minus current threads; agent cap 6 minus active
#           agents; the 60% memory budget minus already-used memory) is AT OR
#           BELOW ZERO -- i.e. the limit is ALREADY exceeded before any new
#           work starts -- the guard MUST NOT let even one more unit of work
#           through: it reports N=0 with the matching *_exhausted reason,
#           regardless of the requested N (even a request of exactly 1).
#           Once ANY limit is confirmed exhausted this way, N=0 is FINAL and
#           IRREVERSIBLE: nothing discovered afterward relaxes it back up --
#           not a later *_exhausted finding on a different limit (first
#           exhaustion found stands) and not a later unreadable_* finding on a
#           different, unrelated limit either (an unreadable value says
#           nothing about a limit ALREADY confirmed exhausted from valid
#           data, and N=0 is already the most conservative answer there is).
#           The floor of N=1 below is reserved for the case where there is
#           genuinely at least one unit of real headroom/budget remaining (the
#           real value is POSITIVE but smaller than one job's estimated need,
#           e.g. thread headroom > 0 but < --threads-per-job, or memory budget
#           > 0 but < --per-job-mem-kb): there the guard still allows a single
#           trickle of progress and reports the plain (non-exhausted) reason
#           NAME -- but only when that partial headroom actually reduces N
#           below the caller's own requested value (clamp()'s STRICT
#           less-than test). When the request already equals (or is already
#           below) the computed floor-to-1 value, clamp() never fires -- there
#           is nothing to reduce relative to what was asked for -- and REASON
#           stays "none" (e.g. a request of exactly 1 against genuine partial
#           headroom of exactly 1): the same "reason names an actual
#           reduction, not merely a near-zero state" rule the rest of this
#           script follows everywhere.
#           Any unreadable/garbled/inconsistent input needed for a guard yields
#           N=1 with the unreadable_* reason (conservative-safe, 11.4.201) --
#           this wins over a later PLAIN clamp (nothing a clamp finds can
#           reduce N below the 1 an unreadable finding already forced), but it
#           does NOT win over an *_exhausted verdict, in EITHER temporal
#           order: an already-recorded exhaustion is never relaxed by a later,
#           unrelated unreadable finding, and a later exhaustion computed from
#           genuinely valid data for its OWN limit is never blocked from
#           taking effect just because an EARLIER, unrelated limit happened to
#           be unreadable -- that earlier finding says nothing about whether
#           THIS limit is exhausted. Symmetrically, once one exhaustion is
#           recorded the first one found stands (mirrors the "first
#           unreadable wins" rule) so a later, less-restrictive check can
#           never paper over an earlier hard refusal.
#           When several inputs are unreadable at once with no exhaustion
#           anywhere in the mix, the FIRST in evaluation order reports its
#           reason: nproc, ulimit, threads, active_agents, memory (tested; a
#           later unreadable never replaces an earlier one).
#           FC_GUARD_ACTIVE_AGENTS is the one exception, and only for --kind
#           agents (the only kind that reads it): there a garbled (non-decimal
#           or empty) value is a usage error, exit 2, and only an ABSENT value
#           yields unreadable_active_agents. For --kind jobs the variable is
#           never read, so any value of it is ignored.
#           Exit 2 (message on stderr) for bad usage: missing/non-decimal/zero/
#           over-long numbers, unknown flag, flag without value, bad --kind.
#           ulimit "unlimited" is a legitimate value (no thread clamp).
# Thread census is keyed on the NUMERIC REAL uid (`id -ru`, selected with procps
#           `ps -U`, the real-uid selector; `-u` would select the effective uid),
#           never the USER env var: RLIMIT_NPROC is charged to the real uid and
#           USER may be stale/foreign.
# Rules   : mem budget = 60% MemTotal - (MemTotal-MemAvail) (12.6), ALWAYS
#           checked against the ceiling regardless of whether --per-job-mem-kb
#           was passed (I1: the ceiling is never silently skipped; a per-job
#           estimate only adds a further per-job-sized reduction on top); thread
#           budget = ulimit_u - threads (12.12); agent cap 6 - active (11.4.58,
#           agents only); N <= nproc; floor 1 (only when real headroom/budget
#           is genuinely > 0, see EXHAUSTED above; N=0 when it is <= 0).
# Portability: NOT POSIX-only. Assumes Linux + procps: `ulimit -u` is a
#           non-POSIX shell extension and `ps -L --no-headers` is procps-only.
#           If either is unsupported the live read fails and the script emits
#           N=1 with the named unreadable_ulimit / unreadable_threads reason
#           (total serialisation, never a mis-report); the FC_GUARD_* overrides
#           make it usable on such hosts.
# See     : contracts/common-conventions.md C-007.

die() { echo "host_guard: $*" >&2; exit 2; }
# isnum: 1..12 decimal digits. norm: strip leading zeros (avoid octal), keep >=1 digit.
isnum() { case $1 in ''|*[!0-9]*) return 1 ;; esac; [ "${#1}" -le 12 ]; }
norm() { v=$1; while :; do case $v in 0?*) v=${v#0} ;; *) break ;; esac; done; printf '%s' "$v"; }

[ $# -ge 1 ] || die "missing requested N"
req=$1; shift
isnum "$req" || die "requested N must be a decimal integer of at most 12 digits: '$req'"
req=$(norm "$req"); [ "$req" -ge 1 ] || die "requested N must be >= 1"

kind="jobs"; mem_per=0; thr_per=1
while [ $# -gt 0 ]; do
  case $1 in
    --kind|--per-job-mem-kb|--threads-per-job)
      [ $# -ge 2 ] || die "flag $1 requires a value"
      flag=$1; val=$2; shift 2
      case $flag in
        --kind) case $val in jobs|agents) kind=$val ;; *) die "--kind must be jobs|agents: '$val'" ;; esac ;;
        --per-job-mem-kb) isnum "$val" || die "--per-job-mem-kb needs a decimal integer: '$val'"
          mem_per=$(norm "$val"); [ "$mem_per" -ge 1 ] || die "--per-job-mem-kb must be >= 1" ;;
        --threads-per-job) isnum "$val" || die "--threads-per-job needs a decimal integer: '$val'"
          thr_per=$(norm "$val"); [ "$thr_per" -ge 1 ] || die "--threads-per-job must be >= 1" ;;
      esac ;;
    *) die "unknown argument: $1" ;;
  esac
done

n=$req; reason=none
clamp() { # value reason -- value is >=1 here: genuine, if partial, headroom remains
  if [ "$1" -lt "$n" ]; then n=$1; reason=$2; fi
}
unreadable() { # reason: force conservative N=1 (first unreadable reason wins)
  # unless an *_exhausted verdict is ALREADY recorded: exhaustion, once
  # confirmed from valid data, is final (N=0 is already the most conservative
  # answer there is) and must never be relaxed back up to N=1 by a
  # LATER-discovered unreadable input on a DIFFERENT, unrelated limit.
  case $reason in *_exhausted) return ;; esac
  case $reason in unreadable_*) ;; *) reason=$1 ;; esac
  n=1
}
exhaust() { # reason: a limit's REAL (pre-floor) headroom/cap/budget is <= 0 --
  # already exceeded before any new work starts. Refuse entirely: N=0.
  # Never overrides an earlier *_exhausted (first one found stands, so a
  # later, less-restrictive check can never paper over an earlier hard
  # refusal). DOES override an earlier unreadable_* recorded for a DIFFERENT
  # limit: that earlier finding says nothing about THIS limit, which this
  # call has just confirmed exhausted from genuinely valid data -- N=0 is
  # already the most conservative answer there is, so nothing an unrelated
  # unreadable input could have shown would ever need to push it lower.
  case $reason in *_exhausted) return ;; esac
  n=0; reason=$1
}

# nproc
if [ -n "${FC_GUARD_NPROC+x}" ]; then nproc_v=$FC_GUARD_NPROC; else nproc_v=$(nproc 2>/dev/null); fi
if isnum "$nproc_v" && [ "$(norm "$nproc_v")" -ge 1 ]; then
  nproc_v=$(norm "$nproc_v"); clamp "$nproc_v" nproc
else unreadable unreadable_nproc; fi

# threads / ulimit
# shellcheck disable=SC3045
if [ -n "${FC_GUARD_ULIMIT_U+x}" ]; then ulim=$FC_GUARD_ULIMIT_U; else ulim=$(ulimit -u 2>/dev/null); fi
if [ "$ulim" = unlimited ]; then :
elif isnum "$ulim"; then
  ulim=$(norm "$ulim")
  if [ -n "${FC_GUARD_THREADS+x}" ]; then thr=$FC_GUARD_THREADS
  elif psout=$(ps -L --no-headers -U "$(id -ru)" 2>/dev/null); then
    thr=$(printf '%s\n' "$psout" | grep -c '')
    [ -n "$psout" ] || thr=""     # empty ps output is not "zero threads"
  else thr=""; fi
  if isnum "$thr"; then
    thr=$(norm "$thr")
    thr_raw=$(( ulim - thr ))
    if [ "$thr_raw" -le 0 ]; then
      exhaust thread_headroom_exhausted
    else
      t=$(( thr_raw / thr_per )); [ "$t" -lt 1 ] && t=1
      clamp "$t" thread_headroom
    fi
  else unreadable unreadable_threads; fi
else unreadable unreadable_ulimit; fi

# agents
if [ "$kind" = agents ]; then
  if [ -z "${FC_GUARD_ACTIVE_AGENTS+x}" ]; then unreadable unreadable_active_agents
  else
    active=$FC_GUARD_ACTIVE_AGENTS
    isnum "$active" || die "FC_GUARD_ACTIVE_AGENTS must be a non-negative decimal integer: '$active'"
    active=$(norm "$active")
    cap_raw=$((6 - active))
    if [ "$cap_raw" -le 0 ]; then
      exhaust agent_cap_exhausted
    else
      clamp "$cap_raw" agent_cap
    fi
  fi
fi

# memory (ALWAYS read and checked against the 60% ceiling -- I1: the ceiling
# must never be silently skipped just because --per-job-mem-kb was omitted.
# Without a per-job estimate the guard cannot compute a further per-job-sized
# reduction, but it still refuses outright the moment the ceiling itself is
# already breached.)
if [ -n "${FC_GUARD_MEM_TOTAL_KB+x}" ]; then mtot=$FC_GUARD_MEM_TOTAL_KB
else mtot=$(awk '/^MemTotal:/{print $2}' /proc/meminfo 2>/dev/null); fi
if [ -n "${FC_GUARD_MEM_AVAIL_KB+x}" ]; then mav=$FC_GUARD_MEM_AVAIL_KB
else mav=$(awk '/^MemAvailable:/{print $2}' /proc/meminfo 2>/dev/null); fi
if isnum "$mtot" && isnum "$mav"; then
  mtot=$(norm "$mtot"); mav=$(norm "$mav")
  if [ "$mtot" -ge 1 ] && [ "$mav" -le "$mtot" ]; then
    budget=$(( mtot * 60 / 100 - (mtot - mav) ))
    if [ "$budget" -le 0 ]; then
      exhaust memory_ceiling_exhausted
    elif [ "$mem_per" -gt 0 ]; then
      m=$(( budget / mem_per )); [ "$m" -lt 1 ] && m=1
      clamp "$m" memory_ceiling
    fi
    # else: mem_per==0 and budget>0 -- ceiling checked, not breached, but with
    # no per-job estimate no further per-job-sized reduction can be computed.
  else unreadable unreadable_memory; fi
else unreadable unreadable_memory; fi

case $reason in
  *_exhausted) : ;;   # genuine refusal stands: N=0 is the correct, final answer
  *) [ "$n" -lt 1 ] && n=1 ;;
esac
printf 'N=%s\nREASON=%s\n' "$n" "$reason"
exit 0
