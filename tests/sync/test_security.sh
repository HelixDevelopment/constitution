#!/usr/bin/env bash
# tests/sync/test_security.sh -- SECURITY tests of scripts/sync/sync_all_upstreams.sh (real git, sandbox):
#   * the recording shim (real git underneath) shows no push / force / reset / rebase / commit / +refspec /
#     --upload-pack / ext:: call across a full --apply --advance-pins --advance-third-party run
#   * a remote URL carrying userinfo + a token-shaped password never appears in stdout, stderr, JSON or TSV
#     (the remote is 127.0.0.1:9, which refuses at once: loopback only, no network)
#   * an ambient GIT_DIR / GIT_WORK_TREE pointing elsewhere is ignored (the engine scrubs it)
#   * git never prompts (GIT_TERMINAL_PROMPT=0 seen by a credential helper probe is not needed: no prompt hangs)
#   * a submodule path or remote name with shell metacharacters is never executed
#   * evidence directory is mode 0700
T_NAME=sync-security
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/sync/fixture_lib.sh"
sx_sandbox
echo "== $T_NAME (sandbox $SB)"
sx_std_tree
sx_commit "$U_ROOT" "r1"; sx_commit "$U_A" "a1"; sx_commit "$U_T" "t1"

# 1. no forbidden git call in a full apply
: >"$SB/git_calls.log"
sx_run --apply --advance-pins --advance-third-party --tags --root "$W"
eq "full apply: exit 0" 0 "$SX_RC"
calls="$(tr '\037' ' ' <"$SB/git_calls.log")"
n="$(wc -l <"$SB/git_calls.log" | tr -d ' ')"
[ "$n" -gt 20 ] && ok "control needle: the shim recorded $n calls" || nok "control needle: shim recorded only $n calls"
for bad in ' push ' ' reset ' ' rebase ' ' commit ' '--force' ' -f ' '--hard' ' +refs' '--upload-pack' 'ext::' ' -s ours' '--amend' ' clean ' ' update-ref ' ' gc ' ' stash '; do
  hasnt "no '$bad' in any git call" "$bad" "$calls"
done
subs="$(awk -F'\037' '{for(i=1;i<=NF;i++) if($i=="--no-optional-locks"){print $(i+1); break}}' "$SB/git_calls.log" | sort -u | tr '\n' ' ')"
for s in $subs; do
  case " add cat-file checkout config fetch for-each-ref ls-files merge merge-base remote rev-list rev-parse status symbolic-ref ls-tree " in
    *" $s "*) ok "subcommand '$s' is on the allow-list" ;;
    *) nok "subcommand '$s' is NOT on the allow-list" ;;
  esac
done
has "control needle: merge was among the recorded subcommands" "merge" "$subs"

# 2. credentials in a remote URL never leak
SECRET="ghp_TESTONLYabcdefghijklmnopqrstuvwxyz01"
git -C "$W" remote add leaky "https://alice:${SECRET}@127.0.0.1:9/never.git"
sx_run --check --timeout 20 --root "$W"
eq "leaky remote: attention (unreachable)" 4 "$SX_RC"
eq "leaky remote: reported unreachable" "unreachable" "$(sx_q '[x for x in P["."]["remotes"] if x["name"]=="leaky"][0]["state"]')"
all="$SX_OUT$SX_ERR$(cat "$SX_JSON" "$SX_TSV")"
hasnt "secret absent everywhere" "$SECRET" "$all"
hasnt "userinfo absent everywhere" "alice:" "$all"
has "control needle: the redacted URL itself is reported" "https://127.0.0.1:9/never.git" "$(cat "$SX_JSON")"
git -C "$W" remote remove leaky

# 3. ambient GIT_DIR / GIT_WORK_TREE are ignored
decoy="$SB/decoy"; git init -q "$decoy"
SX_OUT="$(GIT_DIR="$decoy/.git" GIT_WORK_TREE="$decoy" bash "$SX_ENGINE" --check --no-fetch --root "$W" --out "$SB/out/amb" 2>&1)"; rc=$?
eq "ambient GIT_DIR: exit 0" 0 "$rc"
eq "ambient GIT_DIR: the real tree was inspected (4 repos)" "4" "$(python3 -I -c 'import json,sys;print(json.load(open(sys.argv[1]))["counts"]["repos"])' "$SB/out/amb/sync_report.json")"

# 4. metacharacters in a remote name are refused, never executed
git -C "$W" config 'remote.x$(touch pwned).url' "file://$SB/remotes/HelixDevelopment/root.git"
sx_run --check --root "$W"
eq "metachar remote name: nothing executed" "no" "$([ -e "$W/pwned" ] || [ -e "$SB/pwned" ] && echo yes || echo no)"
eq "metachar remote name: flagged invalid" "True" "$(sx_q '"invalid-remote-name" in P["."]["reasons"]')"
git -C "$W" config --remove-section 'remote.x$(touch pwned)'

# 5. evidence directory permissions
eq "evidence dir mode 0700" "700" "$(stat -c '%a' "$SB/out/r$SX_N")"

# 6. no prompt: an https remote that would ask for a password fails fast instead of hanging
git -C "$W" remote add prompt "https://127.0.0.1:9/needs-auth.git"
start=$(date +%s); sx_run --check --timeout 30 --root "$W" </dev/null; dur=$(( $(date +%s) - start ))
[ "$dur" -lt 30 ] && ok "no interactive prompt (finished in ${dur}s)" || nok "run took ${dur}s"
git -C "$W" remote remove prompt

finish
