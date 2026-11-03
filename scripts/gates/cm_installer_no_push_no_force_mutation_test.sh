#!/usr/bin/env bash
# cm_installer_no_push_no_force_mutation_test.sh — §1.1 paired-mutation meta-test for CM-INSTALLER-NO-PUSH-NO-FORCE.
#
# Each case is a scratch copy of BOTH scripts (same basenames, so the gate's exact exemptions apply) under a
# mktemp -d directory; the real files are never touched. Golden: the real pair PASSES (exit 0). Golden-FALSE
# (§11.4.201(1)): push / --force / reset --hard only in a comment, a message carrier, a quoted data heredoc or a
# [[ =~ ]] regex still PASS. Mutants MUST FAIL (exit 1):
#   S*  one executable line injected into hi_builtin_update (raw git, hidden git, dynamic execution, shells,
#       obfuscated spellings: ${P}ush, $'\x70ush', p\ush, x=pu; ${x}sh, printf | bash, here-strings, wrappers)
#   W*  edits of the hi_gx wrapper, applied to BOTH copies so the block stays identical (a push label, a default
#       branch that allows, a checkout that allows any ref, no option loop, config writes allowed, -c anything …)
#   B*  the block made different between the two files; HI_GX_COMMIT_OK=1 set a second time
#   The S list ends with the 20 reviewer-authored mutants of round 3 (forced fetch refspecs, --refmap, switch
#   writes via prefix/printf -v/declare/nameref/read/for/(( )), PATH and GIT_CONFIG_*/GIT_EXEC_PATH exports,
#   traps, rm -R/--recursive, chmod -R, truncate, submodule --recursive, set-url ext::) and file-writing
#   redirections; W18-W24 remove the transport-helper, --refmap, fetch-shape, env-sanitising, ssh, one-time git
#   resolution and set-url checks. The last S mutants (round 5) run code from a path (python FILE, -m) and
#   replace user files (cp/ln/mv/touch outside their sanctioned places, rsync, curl, ssh). G7: python -c LITERAL
#   and the push-mark count literal still PASS. Golden-FALSE G5/G6: /dev/null and fd redirections, IFS prefix, the exact
#   fetch shape, a literal trap and arithmetic reads still PASS.
# The table printed at the end says, per mutant, which check killed it: static (a)/(b)/(c) or runtime (d).
# Usage: cm_installer_no_push_no_force_mutation_test.sh   Exit 0 proof holds · 1 survivor/misclassified · 2 env.
# Classification: universal (§11.4.17).
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
gate="$here/cm_installer_no_push_no_force.sh"; inst="$here/../install_constitution.sh"; upd="$here/../update_constitution.sh"
[ -r "$gate" ] && [ -r "$inst" ] && [ -r "$upd" ] && [ -r "$here/../lib/safe_rm.sh" ] || { echo "META: gate or scripts missing" >&2; exit 2; }
# shellcheck source=../lib/safe_rm.sh
. "$here/../lib/safe_rm.sh"
command -v python3 >/dev/null 2>&1 || { echo "META: python3 missing" >&2; exit 2; }
tmp="$(mktemp -d "${TMPDIR:-/tmp}/cm_nopush_meta.XXXXXX")" || exit 2
trap 'SAFE_RM_ALLOWED_ROOTS="$(dirname "${tmp:?}")" safe_rm_rf "${tmp:?}"' EXIT
bad=0; n=0
TABLE="$tmp/table.txt"; : >"$TABLE"
mkcase() { local d="$tmp/c$n"; mkdir -p "$d"; cp "$inst" "$d/install_constitution.sh"; cp "$upd" "$d/update_constitution.sh"; printf '%s' "$d"; }
run() { # name want-rc dir → records the result and which check(s) fired
  local name="$1" want="$2" d="$3" out rc checks
  out="$(bash "$gate" --file "$d/install_constitution.sh" --file "$d/update_constitution.sh" 2>&1)"; rc=$?
  checks="$(printf '%s\n' "$out" | grep -oE ':[0-9]+ \([a-d]\)' | grep -oE '[a-d]' | sort -u | tr '\n' ',' | sed 's/,$//')"
  if [ "$rc" = "$want" ]; then printf '  ok   %-6s rc=%s %-8s %s\n' "$n" "$rc" "${checks:--}" "$name" | tee -a "$TABLE"
  else printf '  FAIL %-6s want=%s got=%s %s\n' "$n" "$want" "$rc" "$name" | tee -a "$TABLE"; printf '%s\n' "$out" | tail -4; bad=$((bad+1)); fi
}
inject() { # file line → line inserted (verbatim, via ENVIRON) as the first line of hi_builtin_update
  local f="$1" l="$2"
  INJ="$l" awk '{ print } /^hi_builtin_update\(\) \{/ { print "  " ENVIRON["INJ"] }' "$f" >"$f.new" && mv "$f.new" "$f"
}
edit_both() { # python-literal old new → replaced exactly once in BOTH copies (keeps the block identical)
  local d="$1" old="$2" new="$3" f
  for f in "$d/install_constitution.sh" "$d/update_constitution.sh"; do
    OLD="$old" NEW="$new" python3 -I -c 'import os,sys
p=sys.argv[1]; s=open(p).read(); o=os.environ["OLD"]; assert s.count(o)==1, (p, s.count(o)); open(p,"w").write(s.replace(o, os.environ["NEW"]))' "$f" \
      || { echo "META: mutant $n did not apply" >&2; exit 2; }
  done
}

edit_in_fn() { # dir file func old new → old replaced once, within the body of func (round 11: variable-source mutants)
  local d="$1" f="$2" fn="$3" old="$4" new="$5"
  FN="$fn" OLD="$old" NEW="$new" python3 -I -c 'import os,sys
p=sys.argv[1]; s=open(p).read(); fn=os.environ["FN"]; o=os.environ["OLD"]
i=s.index("\n"+fn+"() {") if ("\n"+fn+"() {") in s else -1
assert i>=0, "function not found"
j=s.index("\n}\n", i) if ("\n"+fn+"() {{") not in s else i
body=s[i:j+3]; assert body.count(o)==1, (fn, body.count(o)); open(p,"w").write(s[:i]+body.replace(o, os.environ["NEW"])+s[j+3:])' "$d/$f" \
    || { echo "META: mutant $n did not apply" >&2; exit 2; }
}

echo "# golden"
n=G0; d="$(mkcase)"; run "real installer + updater" 0 "$d"
n=G1; d="$(mkcase)"; inject "$d/install_constitution.sh" '# git push origin main --force; git reset --hard'; run "golden-FALSE: comment" 0 "$d"
n=G2; d="$(mkcase)"
inject "$d/install_constitution.sh" 'hi_say "never git push --force"; hi_warn "no reset --hard"; printf '"'"'run git push yourself\n'"'"' >&2'
run "golden-FALSE: message carriers" 0 "$d"
n=G3; d="$(mkcase)"; inject "$d/install_constitution.sh" '[[ "$x" =~ ^git\ push$ ]] && hi_say "data"'; run "golden-FALSE: [[ =~ ]] regex" 0 "$d"
n=G4; d="$(mkcase)"; inject "$d/install_constitution.sh" 'hi_gx -C "$sub" rev-parse HEAD >/dev/null || return 1'; run "golden-FALSE: allowed wrapper call" 0 "$d"
n=G5; d="$(mkcase)"; inject "$d/install_constitution.sh" 'printf x >/dev/null 2>&1; echo y >&2; IFS=/ read -r -a parts <<<"a/b"; export GIT_TERMINAL_PROMPT=0'
run "golden-FALSE: /dev/null + fd dup redirections, IFS prefix, GIT_TERMINAL_PROMPT" 0 "$d"
n=G6; d="$(mkcase)"; inject "$d/install_constitution.sh" 'hi_gx -C "$sub" fetch --quiet --tags "$r" || return 1; trap '"'"'hi_on_signal INT'"'"' INT; n=$((n+1))'
run "golden-FALSE: exact fetch shape, literal trap, arithmetic read" 0 "$d"
# the claude deny-list literal is exempt only as the exact whole assignment
n=G7; d="$(mkcase)"; inject "$d/install_constitution.sh" "python3 -I -c 'print(1)' >/dev/null; n=\"\$(printf x | grep -c '^update by push')\""
run "golden-FALSE: python -c LITERAL, the push-mark count literal" 0 "$d"
n=P1; d="$(mkcase)"; inject "$d/install_constitution.sh" "HI_CLAUDE_DENY='WebFetch,WebSearch,Bash(git push *),Bash(git push),Bash(git * push *),Bash(git * push),Bash(*git push*),Bash(*git * push*),Bash(env git*),Bash(command git*),Bash(*send-pack*),Bash(gh *),Bash(glab *),Bash(curl *),Bash(wget *)'; git -C \"\$sub\" push origin main"
run "exempt deny literal followed by a real push" 1 "$d"
n=P2; d="$(mkcase)"; inject "$d/install_constitution.sh" "HI_CLAUDE_DENY='WebFetch,Bash(git push *)'"
run "a different deny literal is not exempt" 1 "$d"
n=P3; d="$(mkcase)"; inject "$d/install_constitution.sh" "X='WebFetch,WebSearch,Bash(git push *),Bash(git push)'"
run "the deny text under another name is not exempt" 1 "$d"

echo "# static mutants (one line injected into hi_builtin_update)"
i=0
while IFS= read -r line; do
  [ -n "$line" ] || continue
  i=$((i+1)); n="S$i"; d="$(mkcase)"; inject "$d/install_constitution.sh" "$line"; run "$line" 1 "$d"
done <<'MUTANTS'
git -C "$O_ROOT" push origin main
git -C "$sub" send-pack origin HEAD
git -C "$sub" checkout -qf main
git -C "$sub" checkout --force "$tsha"
git -C "$sub" reset -q --hard
git -C "$sub" reset --har
rm -f -r "$O_ROOT/$HI_SUB"
rm -rf "$O_ROOT/$HI_SUB"
find "$sub" -delete
find "$sub" -name x -exec rm {} +
git -C "$sub" branch -Df main
git -C "$sub" update-ref -m x -d refs/heads/main
git -C "$sub" update-ref refs/heads/main HEAD~3
git -C "$sub" switch --discard-changes main
git -C "$sub" checkout -B main
git -C "$sub" tag -f v1
git -C "$sub" commit --amend -m x
git -C "$sub" clean -fdx
P=p; git -C "$sub" ${P}ush
git -C "$sub" $'\x70ush'
git -C "$sub" p\ush
x=pu; git -C "$sub" ${x}sh
printf 'git push\n' | bash
bash <<<"git push"
gg() { git "$@"; }; gg push
command git -C "$sub" push
timeout 5 git -C "$sub" push
env A=1 git -C "$sub" push
hi_user_umask git -C "$sub" status
xargs git push </dev/null
cmd=(git push --force); "${cmd[@]}"
cmd=(git "push" "--force-with-lease"); "${cmd[@]}"
git -C "$sub" "push" origin HEAD
sh -c "git -C $sub reset --hard"
bash -c "hi_gx push"
op=push; git -C "$sub" "$op"
op=push; hi_gx -C "$sub" "$op"
hi_gx -C "$sub" ${P}ush
hi_gx -C "$sub" push
hi_git push origin main
hi_git_url "$u" fetch --force origin
hi_gx -c core.hooksPath=/tmp status
eval "$O_AGENT"
. "$O_ROOT/x.sh"
source "$O_ROOT/x.sh"
"$G" push
$G push
printf 'x' >&2; git push
hi_say "$(git -C "$sub" push origin HEAD)"
die 3 "`git push`"
alias g=git
perl -e 'system("git push")'
python3 -c "$code"
awk 'BEGIN { system("git push") }'
v="$(git -C "$sub" rev-parse HEAD)"
hi_gx -C "$sub" fetch --quiet -- origin +refs/heads/main:refs/heads/main
hi_gx -C "$sub" fetch --quiet origin main --refmap=+refs/heads/*:refs/heads/*
HI_GX_COMMIT_OK=1 hi_gx -C "$O_ROOT" commit -qm x
printf -v HI_GX_COMMIT_OK 1
declare -g HI_GX_COMMIT_OK=1
HI_GX_INIT_OK=1
PATH="$sub:$PATH"
export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.fsmonitor GIT_CONFIG_VALUE_0="sh $sub/x"
export GIT_CONFIG_PARAMETERS="'core.hooksPath'='/tmp'"
trap 'hi_gx -C "$sub" push' EXIT
trap "$O_AGENT" EXIT
rm -R -- "$O_ROOT/$HI_SUB"
rm --recursive "$O_ROOT/$HI_SUB"
chmod -R 777 "$O_ROOT"
truncate -s 0 "$O_ROOT/CLAUDE.md"
hi_gx -C "$sub" submodule update --init --recursive
hi_gx -C "$sub" remote set-url origin "ext::sh -c touch% /tmp/p"
export GIT_EXEC_PATH="$sub"
git=hi_gx; $git push
mapfile -t c <<<"push"; hi_gx -C "$sub" "${c[0]}"
: >"$O_ROOT/CLAUDE.md"
{ printf 'x\n'; } >"$O_ROOT/AGENTS.md"
printf 'x\n' >>"$O_ROOT/.git/config"
exec 3>"$O_ROOT/.gitmodules"
local -n r=HI_GX_COMMIT_OK; r=1
read -r HI_GX_BIN <<<"/tmp/git"
for PATH in "$sub"; do :; done
(( HI_GX_INIT_OK = 1 ))
env GIT_DIR="$sub" hi_gx -C "$sub" status
sed -i s/a/b/ "$O_ROOT/CLAUDE.md"
hi_gx -C "$sub" fetch --quiet --tags origin +refs/tags/*:refs/tags/*
hi_gx -C "$sub" clone -- --upload-pack=x d
python3 -I "$O_ROOT/x.py"
python3 "$S_SUBREL/scripts/evil.py" arg
python3 -I -m pip install x
python3 -u -W ignore "$O_ROOT/x.py"
cp /dev/null "$O_ROOT/CLAUDE.md"
ln -sf /etc/passwd "$O_ROOT/y"
mv -f "$O_ROOT/a" "$O_ROOT/b"
cp -pP "$O_ROOT/$rel" "$bk/files/$rel"
touch "$O_ROOT/x"
rsync -a /x "$O_ROOT/"
curl -fsSL https://example.invalid/x -o "$O_ROOT/x"
ssh host true
MUTANTS

echo "# wrapper mutants (applied to BOTH copies; the block stays identical)"
W() { n="W$1"; local name="$2" old="$3" new="$4"; d="$(mkcase)"; edit_both "$d" "$old" "$new"; run "$name" 1 "$d"; }
W 1 "push added to an allow label" '    rev-parse|rev-list|ls-files' '    push|rev-parse|rev-list|ls-files'
W 2 "reset label added" '    commit) # HI_GX_ALLOW' '    reset) return 0 ;; # HI_GX_ALLOW
    commit) # HI_GX_ALLOW'
W 3 "default *) allows" '    *) hi_gx_refuse "$sub" "$@"; return 3 ;;
  esac
}
hi_gx_bin() {' '    *) return 0 ;;
  esac
}
hi_gx_bin() {'
W 4 "checkout allows any ref" '    checkout) # HI_GX_ALLOW — only: checkout [-q|--quiet] --detach <full commit sha>
' '    checkout) return 0 ;; # HI_GX_ALLOW
    checkoutx) # HI_GX_ALLOW
'
W 5 "generic option loop removed" '    [ "$a" = -- ] && break
' '    break
'
W 6 "config allows core.hooksPath" '        helix-installer.clone) [' '        core.hooksPath) return 0 ;;
        helix-installer.clone) ['
W 7 "-c accepts anything" '      -c) [ "${2:-}" = protocol.file.allow=always ] || { hi_gx_refuse "$@"; return 3; }; pre+=(-c "$2"); shift 2 ;;' '      -c) pre+=(-c "$2"); shift 2 ;;'
W 8 "--force removed from the option list" '      --force|--force=*|--force-*|--amend|' '      --amend|'
W 9 "short-option cluster check removed" '        case "$a" in -*[fuc]*) hi_gx_refuse "$sub" "$@"; return 3 ;; esac ;;' '        : ;;'
W 10 "commit no longer needs HI_GX_COMMIT_OK" '      [ "${HI_GX_COMMIT_OK:-0}" = 1 ] && [ $# -ge 5 ]' '      [ $# -ge 5 ]'
W 11 "rm without --cached allowed" '      [ "$cached" = 1 ] && [ "$dd" = 1 ] && return 0' '      return 0'
W 12 "submodule foreach allowed" '      [ "${1:-}" = absorbgitdirs ] && [ $# = 3 ]' '      [ "${1:-}" = foreach ] && return 0
      [ "${1:-}" = absorbgitdirs ] && [ $# = 3 ]'
W 13 "remote add allowed" '      [ "$1" = get-url ] && [ $# = 2 ] && hi_gx_name_ok "$2" && return 0' '      return 0'
W 14 "check skipped in hi_gx" '  hi_gx_check "$@" || return 3' '  true'
W 15 "hi_gx runs git although the check refused" '  hi_gx_check "$@" || return 3' '  hi_gx_check "$@"'
W 16 "+refspec accepted" '    case "$a" in +*|*::*) hi_gx_refuse "$sub" "$@"; return 3 ;; esac' '    case "$a" in *::*) hi_gx_refuse "$sub" "$@"; return 3 ;; esac'
W 17 "submodule update --recursive allowed" '      --recurse-submodules*|--recursive|--refmap*' '      --recurse-submodules*|--refmap*'
W 18 "ext:: transport helper accepted" '    case "$a" in +*|*::*) hi_gx_refuse "$sub" "$@"; return 3 ;; esac' '    case "$a" in +*) hi_gx_refuse "$sub" "$@"; return 3 ;; esac'
W 19 "--refmap accepted" '|--refmap*|--update-head-ok|' '|--update-head-ok|'
W 20 "fetch takes any arguments" '      [ $# = 3 ] && [ "$1" = --quiet ] && [ "$2" = --tags ] && hi_gx_name_ok "$3" && return 0' '      return 0'
W 21 "environment not sanitised" '        *) unset "$v" ;;' '        *) : ;;'
W 22 "GIT_SSH_COMMAND inherited" '    export GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=10"' '    export GIT_TERMINAL_PROMPT=0'
W 23 "git looked up on PATH at every call" '  [ -n "${HI_GX_BIN:-}" ] && return 0' '  :'
W 24 "remote set-url accepts any URL" '[ "$2" = origin ] && [[ "$3" == /* ]] && hi_gx_repo_ok "$3"' '[ "$2" = origin ]'

echo "# block / commit-flag mutants"
n=B1; d="$(mkcase)"
OLD='    rev-parse|rev-list|ls-files' NEW='    push|rev-parse|rev-list|ls-files' python3 -I -c 'import os,sys
p=sys.argv[1]; s=open(p).read(); assert s.count(os.environ["OLD"])==1; open(p,"w").write(s.replace(os.environ["OLD"], os.environ["NEW"], 1))' "$d/update_constitution.sh" || exit 2
run "updater block differs (push label only there)" 1 "$d"
n=B2; d="$(mkcase)"; inject "$d/install_constitution.sh" 'HI_GX_COMMIT_OK=1'; run "HI_GX_COMMIT_OK=1 set a second time" 1 "$d"

echo "# round-6 reviewer mutants (allow-list): one line injected after the hi_write_docs staging add; each MUST fail"
RM="r""m"; U='"$O_ROOT/README.md"'
inject_after() { # file anchor-literal line → line inserted verbatim after the anchor line (via ENVIRON)
  local f="$1" l="$2"
  INJ="$l" awk '{ print } $0 == "    hi_git add -- \"$f\" >/dev/null 2>&1" { print "    " ENVIRON["INJ"] }' "$f" >"$f.new" && mv "$f.new" "$f"
}
i=0
while IFS= read -r line; do
  i=$((i+1)); n="R$i"; d="$(mkcase)"; inject_after "$d/install_constitution.sh" "$line"
  cnt="$(grep -cF -- "$line" "$d/install_constitution.sh")"; [ "$cnt" = 1 ] || { echo "META: R$i did not apply" >&2; exit 2; }
  run "reviewer mutant: $line" 1 "$d"
done <<EOF
$RM -f -- $U
chmod 000 $U
awk -v f=$U 'BEGIN { printf "" > f }'
sed -n "w \$O_ROOT/README.md" /dev/null
python3 -I -c 'import sys; open(sys.argv[1], "w")' $U
tar -xf "\$S_BK/x.tar" -C "\$O_ROOT"
patch -s $U "\$S_BK/x.diff"
unlink $U
cat /dev/null >$U
$RM -f -r -- "\$O_ROOT/docs"
printf "%s\n" $U | xargs $RM -f
find "\$O_ROOT" -name README.md -delete
hi_gx -C "\$O_ROOT" submodule add --quiet -- "\$S_URL" ../../outside
mkdir -p "\$O_ROOT/.git/hooks" && ln -s /bin/true "\$O_ROOT/.git/hooks/pre-commit"
ex -sc "%d|wq" $U
cp /dev/null $U
hi_gx -C "\$O_ROOT" config --unset helix-installer.clone
perl -e 'unlink shift' $U
install -m 755 /bin/true $U
dd if=/dev/zero of=$U count=1
EOF
n=U1; d="$(mkcase)"
UANCH='rc=0
if [ "$HOOK" = 1 ]; then'
OLD="$UANCH" NEW="$RM -f -- \"\$ROOT/README.md\"
$UANCH" python3 -I -c 'import os,sys
p=sys.argv[1]; s=open(p).read(); assert s.count(os.environ["OLD"])==1; open(p,"w").write(s.replace(os.environ["OLD"], os.environ["NEW"], 1))' "$d/update_constitution.sh" || exit 2
run "reviewer mutant U1: a delete in the updater" 1 "$d"

# W2 round 8: the updater's resume marker is the only file it may write besides the lock; a changed target, or another
# delete beside the marker's, is a finding
n=W1; d="$(mkcase)"
OLD='printf '"'"'%s %s\n'"'"' "$TSHA" "${GL_CUR:--}" >"$PEND"' NEW='printf '"'"'%s %s\n'"'"' "$TSHA" "${GL_CUR:--}" >"$ROOT/README.md"' python3 -I -c 'import os,sys
p=sys.argv[1]; s=open(p).read(); assert s.count(os.environ["OLD"])==1; open(p,"w").write(s.replace(os.environ["OLD"], os.environ["NEW"], 1))' "$d/update_constitution.sh" || exit 2
run "W2 mutant W1: the resume marker written over a project file" 1 "$d"
n=W2; d="$(mkcase)"
OLD='up_marker_clear() { [ -n "$PEND" ] && rm -f -- "$PEND"; return 0; }' NEW='up_marker_clear() { [ -n "$PEND" ] && rm -f -- "$PEND" "$ROOT/README.md"; return 0; }' python3 -I -c 'import os,sys
p=sys.argv[1]; s=open(p).read(); assert s.count(os.environ["OLD"])==1; open(p,"w").write(s.replace(os.environ["OLD"], os.environ["NEW"], 1))' "$d/update_constitution.sh" || exit 2
run "W2 mutant W2: the marker clear also deletes a project file" 1 "$d"
# W2 round 10: the installer's built-in updater keeps the same marker through two sanctioned helpers; a changed
# target, or another delete beside the marker's, is a finding
n=W3; d="$(mkcase)"
OLD='printf '"'"'%s %s\n'"'"' "$1" "${2:--}" >"$pend"' NEW='printf '"'"'%s %s\n'"'"' "$1" "${2:--}" >"$O_ROOT/README.md"' python3 -I -c 'import os,sys
p=sys.argv[1]; s=open(p).read(); assert s.count(os.environ["OLD"])==1; open(p,"w").write(s.replace(os.environ["OLD"], os.environ["NEW"], 1))' "$d/install_constitution.sh" || exit 2
run "W2 mutant W3: the installer marker written over a project file" 1 "$d"
n=W4; d="$(mkcase)"
OLD='  rm -f -- "$pend"' NEW='  rm -f -- "$pend" "$O_ROOT/README.md"' python3 -I -c 'import os,sys
p=sys.argv[1]; s=open(p).read(); assert s.count(os.environ["OLD"])==1; open(p,"w").write(s.replace(os.environ["OLD"], os.environ["NEW"], 1))' "$d/install_constitution.sh" || exit 2
run "W2 mutant W4: the installer marker clear also deletes a project file" 1 "$d"

# W2 round 11: the marker variable's SOURCE is pinned too (not only the command text that uses it): re-pointing
# $pend / $PEND at a file the user owns keeps the sanctioned command text identical, so only the pinned
# assignment can catch it
n=M6; d="$(mkcase)"
edit_in_fn "$d" install_constitution.sh hi_marker_clear 'pend="$(hi_marker_path)" || return 0' 'pend="$O_ROOT/.gitmodules"'
run "R11 mutant M6: hi_marker_clear re-pointed at .gitmodules" 1 "$d"
n=M7; d="$(mkcase)"
edit_in_fn "$d" install_constitution.sh hi_marker_set 'pend="$(hi_marker_path)" || return 0' 'pend="$O_ROOT/.git/config"'
run "R11 mutant M7: hi_marker_set re-pointed at .git/config" 1 "$d"
n=M8; d="$(mkcase)"
OLD='PEND="$(hi_gx -C "$ROOT" rev-parse --git-path helix-update-pending 2>/dev/null)"' NEW='PEND="$ROOT/.gitmodules"' python3 -I -c 'import os,sys
p=sys.argv[1]; s=open(p).read(); assert s.count(os.environ["OLD"])==1; open(p,"w").write(s.replace(os.environ["OLD"], os.environ["NEW"], 1))' "$d/update_constitution.sh" || exit 2
run "R11 mutant M8: updater PEND re-pointed at .gitmodules" 1 "$d"
n=M10; d="$(mkcase)"
edit_in_fn "$d" install_constitution.sh hi_marker_path 'p="$O_ROOT/$p"' 'p="$O_ROOT/.gitmodules"'
run "R11 mutant M10: hi_marker_path returns .gitmodules" 1 "$d"

# W2 round 11, class-wide: EVERY pinned target variable (the census the gate prints with CM_NOPUSH_SPECS=1: each
# variable that is the target of a sanctioned redirection / file command / rm / chmod / mkdir / rmdir entry, plus the
# marker-path helper) is re-pointed at a file the user owns by one extra binding in its function; each MUST fail (a).
# Control needles: the census is not empty, and it contains the marker variables the reviewer's M6-M10 re-pointed.
specs="$(CM_NOPUSH_INVENTORY=1 CM_NOPUSH_SPECS=1 bash "$gate" --file "$inst" --file "$upd" 2>/dev/null | grep '^SPEC ')"
nspec="$(printf '%s\n' "$specs" | grep -c '^SPEC ')"
[ "$nspec" -ge 40 ] && printf '%s\n' "$specs" | grep -q '^SPEC install_constitution.sh hi_marker_set pend$' \
  && printf '%s\n' "$specs" | grep -q '^SPEC update_constitution.sh - PEND$' || { echo "META: variable census blind ($nspec specs)" >&2; exit 2; }
while read -r _ sbase sfn svar; do
  n="V-$svar-${sfn}"; d="$(mkcase)"
  SBASE="$sbase" SFN="$sfn" SVAR="$svar" python3 -I -c 'import os,re,sys
p=sys.argv[1]+"/"+os.environ["SBASE"]; s=open(p).read().split("\n"); fn=os.environ["SFN"]; v=os.environ["SVAR"]
new=v+"=\"$HOME/.gitmodules\""
if fn=="-":
    ix=[i for i,l in enumerate(s) if re.match(r"^\s*"+re.escape(v)+r"=", l)]; assert ix, v
    s.insert(ix[0], new)
else:
    ix=[i for i,l in enumerate(s) if re.match(r"^"+re.escape(fn)+r"\(\) \{", l)]; assert ix, fn
    i=ix[0]
    if s[i].rstrip().endswith("{"): s.insert(i+1, "  "+new)
    else: s[i]=s[i].replace("() {", "() { "+new+";", 1)
open(p,"w").write("\n".join(s))' "$d" || { echo "META: census mutant $n did not apply" >&2; exit 2; }
  run "R11 census mutant: $svar re-pointed in ${sfn} ($sbase)" 1 "$d"
done < <(printf '%s\n' "$specs")

# W2 round 12 (operator decision 2026-10-31: the gate is a documented BEST-EFFORT TRIPWIRE, not a proof). Cheap
# additions: array-element binding, ${NAME:=v}, duplicate function definitions. R12-G2 (a command-substitution /
# printf producer inside a pinned helper) is a KNOWN LIMIT: it is expected to SURVIVE (rc 0) and is listed in the
# gate header and the guide; the runtime tests (ls-remote hashes before/after) are the real protection.
n=R12-G1; d="$(mkcase)"
edit_in_fn "$d" install_constitution.sh hi_marker_set '  [ -L "$pend" ] && return 0' '  pend[0]="$O_ROOT/.gitmodules"; [ -L "$pend" ] && return 0'
run "R12 mutant G1: array-element binding pend[0]= in hi_marker_set" 1 "$d"
n=R12-G2; d="$(mkcase)"
edit_in_fn "$d" install_constitution.sh hi_marker_path "  printf '%s' \"\$p\"" "  printf '%s' \"\$O_ROOT/.gitmodules\""
run "R12 KNOWN LIMIT G2: hi_marker_path printf of .gitmodules (producer text) survives" 0 "$d"
n=R12-G3; d="$(mkcase)"
python3 -I -c 'import sys
p=sys.argv[1]; s=open(p).read(); i=s.index("\nmain() {"); open(p,"w").write(s[:i]+"\nhi_marker_path() { printf \"%s\" \"$O_ROOT/.gitmodules\"; }"+s[i:])' "$d/install_constitution.sh" || exit 2
run "R12 mutant G3: second definition of hi_marker_path before main()" 1 "$d"
n=R12-G4; d="$(mkcase)"
OLD='PEND="$(hi_gx -C "$ROOT" rev-parse --git-path helix-update-pending 2>/dev/null)"' NEW=': "${PEND:=$ROOT/.gitmodules}"; PEND="$(hi_gx -C "$ROOT" rev-parse --git-path helix-update-pending 2>/dev/null)"' python3 -I -c 'import os,sys
p=sys.argv[1]; s=open(p).read(); assert s.count(os.environ["OLD"])==1; open(p,"w").write(s.replace(os.environ["OLD"], os.environ["NEW"], 1))' "$d/update_constitution.sh" || exit 2
run "R12 mutant G4: \${PEND:=...} binding in up_marker_set" 1 "$d"

n=R12-A8; d="$(mkcase)"
edit_in_fn "$d" install_constitution.sh hi_marker_set '  [ -L "$pend" ] && return 0' '  hi_marker_path() { printf "%s" "$O_ROOT/.gitmodules"; }
  [ -L "$pend" ] && return 0'
run "R12 mutant A8: hi_marker_path redefined NESTED inside hi_marker_set" 1 "$d"

total="$(grep -c . "$TABLE")"
echo "# $total cases; table: rc / checks that fired (a structure, b allow-list, c raw denylist, d runtime) / mutant"
[ "$bad" = 0 ] && echo "META PASS: CM-INSTALLER-NO-PUSH-NO-FORCE kills every mutant ($total cases)" || echo "META FAIL: $bad case(s)"
[ "$bad" = 0 ]
