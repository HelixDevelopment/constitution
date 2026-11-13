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
for bad in ' push ' ' reset ' ' rebase ' ' commit ' '--force' ' -f ' '--hard' '--upload-pack' 'ext::' ' -s ours' '--amend' ' clean ' ' update-ref ' ' gc ' ' stash ' ' --prune ' ' --tags '; do
  hasnt "no '$bad' in any git call" "$bad" "$calls"
done
# every '+' refspec is the engine-owned one: +refs/heads/*:refs/remotes/<the remote fetched>/*  (F1)
badplus="$(awk -F'\037' '{for(i=1;i<=NF;i++) if(substr($i,1,1)=="+"){ want="+refs/heads/*:refs/remotes/" $(i-1) "/*"; if($i!=want) print $i }}' "$SB/git_calls.log" | sort -u)"
eq "every + refspec writes only refs/remotes/<remote>/*" "" "$badplus"
nplus="$(grep -c $'\x1f+refs/heads/\*:refs/remotes/' "$SB/git_calls.log")"
[ "$nplus" -ge 4 ] && ok "control needle: $nplus engine-owned refspecs seen" || nok "control needle: only $nplus engine-owned refspecs"
eq "every git call carries core.hooksPath=/dev/null" "0" "$(grep -vc $'\x1f-c\x1fcore.hooksPath=/dev/null\x1f' "$SB/git_calls.log")"
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

# 7. fetch never deletes or rewrites a ref of ours, whatever the repo config says (F1)
U_F="$(sx_bare HelixDevelopment fone)"; F="$SB/work/fone"; sx_clone "$U_F" "$F"
git -C "$F" branch wip; git -C "$F" tag localonly
git -C "$F" update-ref refs/remotes/origin/oldbranch HEAD
git -C "$F" config remote.origin.fetch '+refs/*:refs/*'
git -C "$F" config fetch.prune true; git -C "$F" config fetch.pruneTags true; git -C "$F" config remote.origin.prune true
git -C "$F" config remote.origin.tagOpt --tags
wf="$(sx_seed "$U_F")"; git -C "$wf" tag upstreamtag; git -C "$wf" push -q origin upstreamtag
sx_commit "$U_F" "f1"
# a symbolic ref (refs/remotes/origin/HEAD) is compared by its target, not by the commit it resolves to
snap() { git -C "$F" for-each-ref --format='%(refname) %(if)%(symref)%(then)-> %(symref)%(else)%(objectname)%(end)' | grep -v '^refs/remotes/origin/main ' ; }
before="$(snap)"
sx_run --check --root "$F"
eq "mirror refspec + prune config, --check: every ref of ours identical" "$before" "$(snap)"
eq "--check: no tag auto-followed" "no" "$(git -C "$F" rev-parse -q --verify refs/tags/upstreamtag >/dev/null && echo yes || echo no)"
sx_run --apply --root "$F"
eq "--apply: exit 0" 0 "$SX_RC"
after="$(git -C "$F" for-each-ref --format='%(refname) %(objectname)')"
for ref in refs/heads/wip refs/tags/localonly refs/remotes/origin/oldbranch; do
  has "--apply: $ref kept" "$ref $(git -C "$F" rev-parse "$ref")" "$(printf '%s\n' "$before")"
  has "--apply: $ref still present" "$ref " "$after"
done
eq "--apply: main fast-forwarded" "$(sx_remote_head "$SB/remotes/HelixDevelopment/fone.git")" "$(sx_head "$F")"
# variant B: the ordinary refspec plus a forced tags refspec and pruneTags (prune would delete the
# local-only tag and the stale refs/remotes/origin/oldbranch)
git -C "$F" config --replace-all remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
git -C "$F" config --add remote.origin.fetch '+refs/tags/*:refs/tags/*'
sx_commit "$U_F" "f2"
sx_run --apply --root "$F"
eq "variant B --apply: exit 0" 0 "$SX_RC"
has "variant B: local-only tag kept" "refs/tags/localonly" "$(git -C "$F" for-each-ref refs/tags)"
has "variant B: stale remote-tracking ref kept" "refs/remotes/origin/oldbranch" "$(git -C "$F" for-each-ref refs/remotes)"
has "variant B: local branch kept" "refs/heads/wip" "$(git -C "$F" for-each-ref refs/heads)"
sx_run --apply --tags --root "$F"
eq "--tags: the new upstream tag is fetched (control needle)" "yes" "$(git -C "$F" rev-parse -q --verify refs/tags/upstreamtag >/dev/null && echo yes || echo no)"
has "--tags: local-only tag still present" "refs/tags/localonly" "$(git -C "$F" for-each-ref refs/tags)"

# 8. no hook and no fsmonitor of the repository runs (F2): tracked hooks dir + hooksPath + fsmonitor
U_H="$(sx_bare HelixDevelopment hooky)"; wh="$(sx_seed "$U_H")"; mkdir -p "$wh/.githooks"
for h in post-merge post-checkout reference-transaction pre-auto-gc; do
  printf '#!/bin/sh\necho %s >>"%s/hookran"\n' "$h" "$SB" >"$wh/.githooks/$h"; chmod +x "$wh/.githooks/$h"
done
printf '#!/bin/sh\necho fsm >>"%s/fsmran"\nexit 1\n' "$SB" >"$wh/.githooks/fsm"; chmod +x "$wh/.githooks/fsm"
git -C "$wh" add .githooks; git -C "$wh" commit -q -m hooks; git -C "$wh" push -q origin main
H="$SB/work/hooky"; sx_clone "$U_H" "$H"
git -C "$H" config core.hooksPath .githooks; git -C "$H" config core.fsmonitor "$H/.githooks/fsm"
sx_commit "$U_H" "h1"; rm -f -- "$SB/hookran" "$SB/fsmran"
sx_run --apply --root "$H"
eq "hooks: root fast-forwarded" "$(sx_remote_head "$SB/remotes/HelixDevelopment/hooky.git")" "$(sx_head "$H")"
eq "hooks: no repository hook ran" "no" "$([ -e "$SB/hookran" ] && echo yes || echo no)"
eq "hooks: fsmonitor never ran" "no" "$([ -e "$SB/fsmran" ] && echo yes || echo no)"
git -C "$H" checkout -q --detach HEAD; git -C "$H" status --porcelain >/dev/null 2>&1; git -C "$H" checkout -q main
eq "hooks: control needle: a plain git checkout DOES run the hook" "yes" "$([ -e "$SB/hookran" ] && echo yes || echo no)"
eq "hooks: control needle: a plain git status DOES run fsmonitor" "yes" "$([ -e "$SB/fsmran" ] && echo yes || echo no)"

# 9. an ignored file the fast-forward would overwrite blocks the move and is kept (F4)
U_S="$(sx_bare HelixDevelopment secr)"; ws="$(sx_seed "$U_S")"
printf 'secret.env\nbuild/\n' >"$ws/.gitignore"; git -C "$ws" add .gitignore; git -C "$ws" commit -q -m ign; git -C "$ws" push -q origin main
S="$SB/work/secr"; sx_clone "$U_S" "$S"
mkdir -p "$S/build"; echo obj >"$S/build/a.o"
mkdir -p "$ws/build"; echo x >"$ws/build/x.txt"; git -C "$ws" add -f build/x.txt; git -C "$ws" commit -q -m buildx; git -C "$ws" push -q origin main
sx_run --apply --root "$S"
eq "ignored dir whose files the target does not touch: no false refusal (exit 0)" 0 "$SX_RC"
eq "ignored dir: moved" "$(sx_remote_head "$SB/remotes/HelixDevelopment/secr.git")" "$(sx_head "$S")"
eq "ignored dir: ignored file kept" "obj" "$(cat "$S/build/a.o")"
echo "TOPSECRET-local" >"$S/secret.env"
echo "upstream" >"$ws/secret.env"; git -C "$ws" add -f secret.env; git -C "$ws" commit -q -m sec; git -C "$ws" push -q origin main
before_s="$(sx_head "$S")"
sx_run --apply --root "$S"
eq "ignored secret.env: exit 4" 4 "$SX_RC"
eq "ignored secret.env: reason" "True" "$(sx_q '"ignored-file-would-be-overwritten" in P["."]["reasons"]')"
eq "ignored secret.env: content kept" "TOPSECRET-local" "$(cat "$S/secret.env")"
eq "ignored secret.env: not moved" "$before_s" "$(sx_head "$S")"
hasnt "ignored secret.env: content never in the report" "TOPSECRET" "$(cat "$SX_JSON" "$SX_TSV")$SX_OUT$SX_ERR"

# 10. a repository's core.sshCommand is honoured for its ssh remotes (F9)
printf '#!/bin/sh\necho "$*" >>"%s/sshcmd_used"\nexit 128\n' "$SB" >"$SB/fakessh"; chmod +x "$SB/fakessh"
git -C "$S" remote add viassh "ssh://git@127.0.0.1:9/x.git"; git -C "$S" config core.sshCommand "$SB/fakessh"
rm -f -- "$SB/sshcmd_used"
sx_run --check --timeout 10 --root "$S"
eq "core.sshCommand: the repository's command was used" "yes" "$([ -e "$SB/sshcmd_used" ] && echo yes || echo no)"
eq "core.sshCommand: report names it" "core.sshCommand" "$(sx_q 'P["."]["ssh"]')"
eq "core.sshCommand: remote reported unreachable" "unreachable" "$(sx_q '[x for x in P["."]["remotes"] if x["name"]=="viassh"][0]["state"]')"

finish
