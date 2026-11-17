#!/bin/bash
# run_probe.sh E TAG: runs p5.sh exactly as test_redact_cut.sh line 294, samples this cgroup's pids.current
E="${1:?}"; tag="${2:?}"
cg="/sys/fs/cgroup$(cut -d: -f3 /proc/self/cgroup)"
echo "cgroup=$cg pids.max=$(cat "$cg/pids.max" 2>/dev/null)"
( while :; do printf '%s %s\n' "$(date +%s.%N | cut -c1-14)" "$(cat "$cg/pids.current" 2>/dev/null)"; sleep 0.5; done ) >"$E/samples_$tag.txt" 2>&1 &
sp=$!
t0=$(date +%s.%N)
o8="$(env -i PATH="$PATH" HOME=/h timeout 30 bash "$E/p5.sh" 2>&1)"; r8=$?
t1=$(date +%s.%N)
kill "$sp" 2>/dev/null; wait "$sp" 2>/dev/null
printf 'r8=%s elapsed=%s\n' "$r8" "$(echo "$t1 - $t0" | bc)"
printf '%s\n' "$o8" | head -n 8
printf '%s\n' "$o8" | grep -c . | sed 's/^/output_lines=/'
case "$r8:$o8" in 0:*"rc=4"*"a0=rc-clean-env"*) echo "K8_N2=ok (the mutant passes K8 N2)";; *) echo "K8_N2=bad (the mutant is caught by K8 N2)";; esac
echo "max_pids=$(awk '{print $2}' "$E/samples_$tag.txt" | sort -n | tail -1)"
