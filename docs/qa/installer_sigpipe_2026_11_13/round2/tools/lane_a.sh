#!/usr/bin/env bash
# lane_a.sh W E — evidence lane A on the frozen clone E/coA: the kill table (one mutant at a time), N23 under bash 5.0.17,
# then test_sigpipe three times under every local bash, one at a time. Logs under E/out.
set -u
W="${1:?}"; E="${2:?}"; co="$E/coA"; out="$E/out"
export TMPDIR="$E/tmpA"
stamp() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" >>"$out/lane_a.log"; }
stamp "kill table start (commit $(git -C "$co" rev-parse HEAD))"
python3 -I "$W/tools/kill_table_runner.py" --check-anchors "$co" >"$out/anchors.txt" 2>&1
python3 -I "$W/tools/kill_table_runner.py" "$co" "$E/tmpA" "$out/kill_table.tsv" --jobs 1 >"$out/kill_table.log" 2>&1
stamp "kill table rc=$?"
python3 -I "$W/tools/kill_table_runner.py" "$co" "$E/tmpA" "$out/kill_table_n23.tsv" --jobs 1 --only N23 \
  --bash "5.0.17=$W/bashes/5.0.17" >"$out/kill_table_n23.log" 2>&1
stamp "kill table N23 rc=$?"
for n in 1 2 3; do
  for v in host 5.0.17 5.1.4 5.1.16 5.2.15 5.2.37; do
    if [ "$v" = host ]; then P="$PATH"; else P="$W/bashes/$v/bin:$PATH"; fi
    log="$out/sigpipe_${v}_r$n.txt"
    ( cd "$co" && env -u LD_PRELOAD -u LD_LIBRARY_PATH PATH="$P" bash -c \
        'echo "bash=$BASH_VERSION"; t0=$SECONDS; nice -n 10 bash tests/install/test_sigpipe.sh; rc=$?; echo "rc=$rc secs=$((SECONDS-t0))"' ) >"$log" 2>&1
    stamp "sigpipe $v r$n $(tail -1 "$log")"
  done
done
stamp "lane A done"
