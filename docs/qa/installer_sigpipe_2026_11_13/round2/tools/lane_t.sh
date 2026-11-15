#!/usr/bin/env bash
# lane_t.sh W E — on the frozen clone E/coT of the test_round8 commit: tests/install/test_round8.sh alone three times
# under the host bash and three times under bash 5.2.37, then tests/install/run_all.sh --quick twice under the host
# bash; one run at a time, in a clean environment (env -i, as in lane B).
set -u
W="${1:?}"; E="${2:?}"; co="$E/coT"; out="$E/out"
stamp() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" >>"$out/lane_t.log"; }
envof() { if [ "$1" = host ]; then P=/usr/bin:/bin; B=/usr/bin/bash; else P="$W/bashes/$1/bin:/usr/bin:/bin"; B="$W/bashes/$1/bin/bash"; fi; }
stamp "lane T start (commit $(git -C "$co" rev-parse HEAD))"
for v in host 5.2.37; do
  envof "$v"
  for n in 1 2 3; do
    log="$out/round8_${v}_r$n.log"; t0=$SECONDS
    systemd-run --user --scope -q -p TasksMax=2000 nice -n 10 env -i HOME=/nonexistent-home TMPDIR="$E/tmpT" \
      PATH="$P" LC_ALL=C.UTF-8 TERM=dumb "$B" "$co/tests/install/test_round8.sh" >"$log" 2>&1
    rc=$?
    stamp "round8 $v r$n rc=$rc secs=$((SECONDS - t0)) bash=$("$B" -c 'echo $BASH_VERSION') $(grep -E '^round8:' "$log" | tail -1)"
  done
done
envof host
for n in 1 2; do
  log="$out/runall_host_r$n.log"; t0=$SECONDS
  systemd-run --user --scope -q -p TasksMax=2000 nice -n 10 env -i HOME=/nonexistent-home TMPDIR="$E/tmpT" \
    PATH="$P" LC_ALL=C.UTF-8 TERM=dumb "$B" "$co/tests/install/run_all.sh" --quick >"$log" 2>&1
  rc=$?
  stamp "runall host r$n rc=$rc secs=$((SECONDS - t0)) bash=$("$B" -c 'echo $BASH_VERSION') $(grep -E '^RUN_ALL:' "$log")"
done
stamp "lane T done"
