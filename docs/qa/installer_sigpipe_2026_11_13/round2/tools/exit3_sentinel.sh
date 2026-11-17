#!/usr/bin/env bash
# exit3_sentinel.sh W E — runs beside lane B while it works, to catch the exit-3 cluster seen in the superseded runs
# (every installer run of a suite exited 3 for a few minutes, and the suites do not keep the installer's output).
#   * every 60 s: one host sample (UTC time, load, free space of the file system that holds E, the user's processes
#     and threads, MemAvailable) to E/out/host_samples.tsv;
#   * every 60 s: the installer of the frozen clone E/coS, --dry-run, in a fresh project against a local upstream
#     made once from that clone (tests/install/lib.sh helpers); every 5th probe is a real install instead. rc and
#     time go to E/out/sentinel.tsv; any probe with rc != 0 keeps its whole output in E/out/sentinel_fail_<n>.txt.
# The first probe of each kind is the control needle: it must exit 0, otherwise the sentinel stops and says so.
# Stops when lane B writes "lane B done" (or E/out/sentinel.stop exists). Exit 0 always; the files are the result.
set -u
W="${1:?W}"; E="${2:?E}"; co="$E/coS"; out="$E/out"
export TMPDIR="$E/tmpS"; mkdir -p "$TMPDIR"
# shellcheck source=/dev/null
. "$co/tests/install/lib.sh" || { echo "cannot source lib.sh" >"$out/sentinel.err"; exit 0; }
new_sandbox
make_upstream "$SB" || { echo "make_upstream failed" >"$out/sentinel.err"; exit 0; }
UP="$SB/upstream.git"
printf 'time\tn\tkind\trc\tsecs\n' >"$out/sentinel.tsv"
printf 'time\tload1\tavail_kb\tprocs\tthreads\tmem_avail_kb\n' >"$out/host_samples.tsv"
n=0; ctl_dry=""; ctl_real=""
while :; do
  if grep -q 'lane B done' "$out/lane_b.log" 2>/dev/null || [ -e "$out/sentinel.stop" ]; then break; fi
  t="$(date -u +%FT%TZ)"
  read -r l1 _ </proc/loadavg
  av="$(df -Pk -- "$E" | awk 'NR == 2 { print $4 }')"
  pr="$(ps -u "$(id -u)" --no-headers | wc -l)"; th="$(ps -L -u "$(id -u)" --no-headers | wc -l)"
  ma="$(awk '/^MemAvailable:/ { print $2 }' /proc/meminfo)"
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$t" "$l1" "$av" "$pr" "$th" "$ma" >>"$out/host_samples.tsv"
  n=$((n+1)); P="$SB/p$n"; new_project "$P"
  if [ $((n % 5)) = 0 ]; then kind=install; extra=(); else kind=dry-run; extra=(--dry-run); fi
  s0=$SECONDS
  o="$(cd "$P" && bash "$INSTALLER" --non-interactive --run-setup off --upstream-url "$UP" \
        --report-json "$SB/r$n.json" "${extra[@]}" 2>&1)"
  rc=$?
  printf '%s\t%s\t%s\t%s\t%s\n' "$t" "$n" "$kind" "$rc" "$((SECONDS - s0))" >>"$out/sentinel.tsv"
  [ "$rc" = 0 ] || printf '%s\n' "$o" >"$out/sentinel_fail_$n.txt"
  if [ "$kind" = dry-run ] && [ -z "$ctl_dry" ]; then ctl_dry="$rc"; fi
  if [ "$kind" = install ] && [ -z "$ctl_real" ]; then ctl_real="$rc"; fi
  if [ "${ctl_dry:-0}" != 0 ] || [ "${ctl_real:-0}" != 0 ]; then
    echo "control needle failed (first dry-run rc=$ctl_dry, first install rc=${ctl_real:-not yet}); sentinel stopped" \
      >"$out/sentinel.err"; break
  fi
  chmod -R u+w "${P:?}" 2>/dev/null; safe_rm_rf "${P:?}"; rm -f -- "${SB:?}/r$n.json"
  sleep 60
done
echo "sentinel done: $n probes" >>"$out/sentinel.tsv.done"
exit 0
