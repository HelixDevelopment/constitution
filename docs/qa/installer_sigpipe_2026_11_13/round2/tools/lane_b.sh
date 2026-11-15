#!/usr/bin/env bash
# lane_b.sh W E — evidence lane B on the frozen clone E/coB: tests/install/run_all.sh --quick three times under the
# host bash and three times under bash 5.2.37, one run at a time, in a clean environment (env -i, as in round 1).
set -u
W="${1:?}"; E="${2:?}"; co="$E/coB"; out="$E/out"
stamp() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" >>"$out/lane_b.log"; }
stamp "lane B start (commit $(git -C "$co" rev-parse HEAD))"
for n in 1 2 3; do
  for v in host 5.2.37; do
    if [ "$v" = host ]; then P=/usr/bin:/bin; B=/usr/bin/bash; else P="$W/bashes/$v/bin:/usr/bin:/bin"; B="$W/bashes/$v/bin/bash"; fi
    log="$out/runall_${v}_r$n.log"; t0=$SECONDS
    systemd-run --user --scope -q -p TasksMax=2000 nice -n 10 env -i HOME=/nonexistent-home TMPDIR="$E/tmpB" \
      PATH="$P" LC_ALL=C.UTF-8 TERM=dumb "$B" "$co/tests/install/run_all.sh" --quick >"$log" 2>&1
    rc=$?
    stamp "runall $v r$n rc=$rc secs=$((SECONDS - t0)) bash=$("$B" -c 'echo $BASH_VERSION') $(grep -E '^RUN_ALL:' "$log")"
  done
done
stamp "lane B done"
