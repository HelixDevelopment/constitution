#!/bin/sh
# Test helper (runs ONLY inside `unshare -Urpf --mount-proc`): waits for pid $1 (a reaped timeout(1) pid)
# to die, forces pid reuse via ns_last_pid so an unrelated `setsid sleep` gets pid $1 (== its pgid),
# records it in $2/reuse.pid, then (optional $3 = pid to TERM) signals that pid.
T=$1; D=$2; SIG=$3
: >"$D/ready.$T"   # tells the launcher we are past setsid (its group can no longer kill us)
i=0; while kill -0 "$T" 2>/dev/null; do i=$((i + 1)); [ "$i" -lt 60000000 ] || exit 0; done
echo $((T - 1)) >/proc/sys/kernel/ns_last_pid 2>/dev/null || exit 0
setsid sleep 30 >/dev/null 2>&1 </dev/null &
r=$!
if [ "$r" = "$T" ]; then echo "$r" >"$D/reuse.pid"; fi
[ -z "$SIG" ] || { [ "$r" = "$T" ] && kill -s TERM "$SIG" 2>/dev/null; }
exit 0
