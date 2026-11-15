#!/usr/bin/env bash
# lane_c.sh W E — evidence lane C on the frozen clone E/coA, started after lane A: the twin mutants (the same
# mutation in every copy of a shared block, so the "identical block" check cannot kill them and only behaviour can),
# N26 run to the end, then the short suites three times under the host bash and under bash 5.2.37, one at a time.
set -u
W="${1:?}"; E="${2:?}"; co="$E/coA"; out="$E/out"
export TMPDIR="$E/tmpC"
mkdir -p "$TMPDIR"
stamp() { printf '%s %s\n' "$(date -u +%FT%TZ)" "$*" >>"$out/lane_c.log"; }
stamp "lane C start (commit $(git -C "$co" rev-parse HEAD))"
python3 -I "$W/tools/kill_table_runner.py" "$co" "$TMPDIR" "$out/kill_table_twins.tsv" --twins --no-stop --jobs 1 \
  >"$out/kill_table_twins.log" 2>&1
stamp "twins host rc=$?"
python3 -I "$W/tools/kill_table_runner.py" "$co" "$TMPDIR" "$out/kill_table_twins_5.0.17.tsv" --twins --no-stop --jobs 1 \
  --only N04t,N05t,N27t --bash "5.0.17=$W/bashes/5.0.17" >"$out/kill_table_twins_5.0.17.log" 2>&1
stamp "twins 5.0.17 rc=$?"
python3 -I "$W/tools/kill_table_runner.py" "$co" "$TMPDIR" "$out/kill_table_nostop.tsv" --no-stop --jobs 1 \
  --only N04,N05,N26 >"$out/kill_table_nostop.log" 2>&1
stamp "no-stop N04 N05 N26 rc=$?"
suites=(tests/test_cli_agent_plugins.sh tests/constitution_cmd/test_install_cli_agent_plugins_ownership.sh
        tests/action_prefix/test_action_prefix_grammar.sh tests/action_prefix/meta_test_action_prefix_grammar.sh
        tests/prompts/test_setup_prompt_round4.sh)
for n in 1 2 3; do
  for v in host 5.2.37; do
    if [ "$v" = host ]; then P=/usr/bin:/bin; B=/usr/bin/bash; else P="$W/bashes/$v/bin:/usr/bin:/bin"; B="$W/bashes/$v/bin/bash"; fi
    for s in "${suites[@]}"; do
      name="$(basename "$s" .sh)"; log="$out/short_${name}__${v}__r$n.txt"; t0=$SECONDS
      ( cd "$co" && env -i HOME=/nonexistent-home TMPDIR="$TMPDIR" PATH="$P" LC_ALL=C.UTF-8 TERM=dumb \
          nice -n 10 "$B" "$s" ) >"$log" 2>&1
      rc=$?
      printf 'rc=%s secs=%s bash=%s\n' "$rc" "$((SECONDS - t0))" "$("$B" -c 'echo $BASH_VERSION')" >>"$log"
      stamp "short $name $v r$n rc=$rc secs=$((SECONDS - t0))"
    done
    stamp "coA status after $v r$n: $(git -C "$co" status --porcelain | wc -l) changed path(s)"
  done
done
# bash 5.2.26 was copied after lane A started, so its three test_sigpipe runs are here, the same command as lane A.
for n in 1 2 3; do
  v=5.2.26; P="$W/bashes/$v/bin:$PATH"; log="$out/sigpipe_${v}_r$n.txt"
  ( cd "$co" && env -u LD_PRELOAD -u LD_LIBRARY_PATH PATH="$P" bash -c \
      'echo "bash=$BASH_VERSION"; t0=$SECONDS; nice -n 10 bash tests/install/test_sigpipe.sh; rc=$?; echo "rc=$rc secs=$((SECONDS-t0))"' ) >"$log" 2>&1
  stamp "sigpipe $v r$n $(tail -1 "$log")"
done
stamp "lane C done"
