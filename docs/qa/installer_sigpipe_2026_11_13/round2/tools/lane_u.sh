#!/usr/bin/env bash
# lane_u.sh W E — on the frozen clone E/coU of the test_round8 commit: tests/install/run_all.sh --quick twice under
# bash 5.2.37, one run at a time, in a clean environment (env -i, as in lane B), and a host-load sample every 5 minutes.
set -u
W="${1:?}"; E="${2:?}"; co="$E/coU"; out="$E/out"
stamp() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" >>"$out/lane_u.log"; }
( while :; do printf '%s %s\n' "$(date -u +%FT%TZ)" "$(cut -d' ' -f1 /proc/loadavg)" >>"$out/load.log"; sleep 300; done ) >/dev/null 2>&1 &
sampler=$!
P="$W/bashes/5.2.37/bin:/usr/bin:/bin"; B="$W/bashes/5.2.37/bin/bash"
stamp "lane U start (commit $(git -C "$co" rev-parse HEAD))"
for n in 1 2; do
  log="$out/runall_5.2.37_r$n.log"; t0=$SECONDS
  systemd-run --user --scope -q -p TasksMax=2000 nice -n 10 env -i HOME=/nonexistent-home TMPDIR="$E/tmpU" \
    PATH="$P" LC_ALL=C.UTF-8 TERM=dumb "$B" "$co/tests/install/run_all.sh" --quick >"$log" 2>&1
  rc=$?
  stamp "runall 5.2.37 r$n rc=$rc secs=$((SECONDS - t0)) bash=$("$B" -c 'echo $BASH_VERSION') $(grep -E '^RUN_ALL:' "$log")"
done
if [[ "$sampler" =~ ^[0-9]+$ ]] && [ "$sampler" -gt 1 ]; then kill "$sampler" 2>/dev/null; fi
stamp "lane U done"
