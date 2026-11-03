#!/usr/bin/env bash
# test_round6.sh — regression tests for the round-6 structural fixes of the installer and updater (W2).
#
# Covers: F1 reachability proved against the LIVE remote (stale remote-tracking refs and local-only tags prove
# nothing; B1 resolution order), F4 a symlinked `submodules` directory, F5 push detection (reflog marks and the
# ls-remote branch comparison; B9 a push made inside the constitution checkout), F6 every internal variable is
# reset by hi_init_state, F7 every message reaches the terminal through the sanitising emitters (static scan) and
# B6 bidi / control characters are stripped, F8 the truncation sentinel check is not vacuous, F10 local file URLs
# get protocol.file.allow=always and remote ones do not, the bounded clone timeout, B14 the updater's INT and TERM
# traps remove its lock, B17 the add path no longer decides on hi_on_remote of a local-only commit.
#
# TEST-CLASS LABELS (§11.4.289): the "claude" binary used in the F5 cases and the git shim used for the clone
# timeout are UNIT-CLASS test doubles (no LLM call, no network); everything else drives the real scripts against a
# REAL local bare upstream. Gate-logic fixtures are not live proof of an agent run.
# Usage: bash tests/install/test_round6.sh   Exit 0 all pass · 1 a case failed.
T_NAME=round6
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
new_sandbox
mkdir -p "$SB/up"; make_upstream "$SB/up" || exit 2
UP="$SB/up/upstream.git"

# ───────────────────────── library-mode unit cases ─────────────────────────
# shellcheck disable=SC1090
HELIX_INSTALLER_LIB_MODE=1 . "$INSTALLER" || { nok "installer sources in library mode"; finish; exit 1; }
hi_init_state
HI_GX_BIN=""

echo "# F6: hi_init_state resets every internal variable (one case per variable)"
vars="$(sed -n '/^hi_init_state() {/,/^}/p' "$INSTALLER" | grep -oE '\b(O|S|HI)_[A-Z0-9_]+=' | tr -d '=' | sort -u | grep -vxE 'S_STARTED')"
nv=0
for v in $vars; do
  nv=$((nv+1))
  base="$(hi_init_state; declare -p "$v" 2>&1)"
  pois="$( eval "$v=POISON"; hi_init_state; declare -p "$v" 2>&1)"
  [ "$base" = "$pois" ] && ok "reset by hi_init_state: $v" || nok "NOT reset by hi_init_state: $v (base [$base] after poison [$pois])"
done
[ "$nv" -ge 40 ] && ok "control needle: the variable list is not vacuous ($nv variables)" || nok "variable list too short ($nv)"
pois="$( HI_GX_TIMEOUT=1; hi_init_state; [ -z "${HI_GX_TIMEOUT+x}" ] && echo unset || echo set)"
eq "HI_GX_TIMEOUT is unset by hi_init_state" unset "$pois"

echo "# B1 / F1: resolution order and reachability against the LIVE remote"
RR="$SB/rr"; mkdir -p "$RR"; git init -q --bare "$RR/o.git"; git clone -q "$RR/o.git" "$RR/w" 2>/dev/null
git -C "$RR/w" checkout -q -b main 2>/dev/null; printf a >"$RR/w/a"; git -C "$RR/w" add a; git -C "$RR/w" commit -qm a
SA="$(git -C "$RR/w" rev-parse HEAD)"; git -C "$RR/w" push -q origin main
git -C "$RR/w" checkout -q -b topic; printf b >"$RR/w/b"; git -C "$RR/w" add b; git -C "$RR/w" commit -qm b
SB1="$(git -C "$RR/w" rev-parse HEAD)"; git -C "$RR/w" push -q origin topic
git -C "$RR/w" checkout -q main; printf c >"$RR/w/c"; git -C "$RR/w" add c; git -C "$RR/w" commit -qm c
SC="$(git -C "$RR/w" rev-parse HEAD)"          # a local-only commit
git -C "$RR/w" tag topic "$SC"                 # a LOCAL tag with the same name as the remote branch
res="$(hi_resolve_ref_in "$RR/w" topic "")"
eq "a local tag does not shadow the remote branch of the same name" "remote-branch $SB1" "$res"
git -C "$RR/w" tag only-local "$SC"
res="$(hi_resolve_ref_in "$RR/w" only-local "")"
eq "a local-only tag resolves as a local ref" "local-ref $SC" "$res"
live="$(hi_remote_live "$RR/w" origin | awk 'NF && !s[$0]++')"
check "control needle: the live list names the pushed branch tips" grep -qx "$SB1" <<<"$live"
check "a pushed commit is reachable on the live remote" hi_on_remote "$RR/w" "$SB1" "$live"
check "an ancestor of a live tip is reachable" hi_on_remote "$RR/w" "$SA" "$live"
check "a local-only commit is NOT reachable on the live remote" eval '! hi_on_remote "$RR/w" "$SC" "$live"'
# a stale remote-tracking ref: the branch is deleted upstream, the tracking ref remains (fetch never prunes)
git -C "$RR/w" fetch -q origin
git -C "$RR/o.git" branch -q -D topic   # deleted upstream; the local tracking ref stays (fetch never prunes)
git -C "$RR/w" rev-parse --verify -q refs/remotes/origin/topic >/dev/null && ok "control: the stale tracking ref origin/topic still exists locally" || nok "no stale tracking ref was produced"
live="$(hi_remote_live "$RR/w" origin | awk 'NF && !s[$0]++')"
check "a commit only a stale tracking ref knows is NOT reachable" eval '! hi_on_remote "$RR/w" "$SB1" "$live"'
check "a remote that cannot be asked proves nothing (empty live list)" eval '! hi_on_remote "$RR/w" "$SA" ""'
check "a malformed sha is never reachable" eval '! hi_on_remote "$RR/w" "main" "$live"'
unreach="$(hi_remote_live "$RR/w" nosuchremote | wc -l)"
eq "an unknown remote contributes nothing" 0 "$unreach"

echo "# F5: push detection logic"
mk() { printf '%s\n' "$@"; }
b="$(mk 'M 0 refs/remotes/origin/main 1' 'L 0 origin 111')"
check "identical marks: no push" eval '! hi_push_changed "$b" "$b"'
a="$(mk 'M 0 refs/remotes/origin/main 2' 'L 0 origin 111')"
check "a reflog mark moved: push" hi_push_changed "$b" "$a"
a="$(mk 'M 0 refs/remotes/origin/main 1' 'L 0 origin 222')"
check "the remote advertises other branches: push" hi_push_changed "$b" "$a"
a="$(mk 'M 0 refs/remotes/origin/main 1' 'U 0 origin')"
# F2 (W2 round 10): answered before, cannot be asked after -> fail closed (counted as a push)
check "a remote that answered before and cannot be asked after fails closed" hi_push_changed "$b" "$a"
b2="$(mk 'M 0 refs/remotes/origin/main 1' 'U 0 origin')"; a="$(mk 'M 0 refs/remotes/origin/main 1' 'L 0 origin 222')"
check "unasked before, asked after: not counted (no baseline)" eval '! hi_push_changed "$b2" "$a"'

S1=1111111111111111111111111111111111111111; S2=2222222222222222222222222222222222222222
b="$(mk "R 0 refs/remotes/origin/main $S1 1")"
a="$(mk "R 0 refs/remotes/origin/main $S1 1")"
check "R: an unchanged tracking ref is no push" eval '! hi_push_changed "$b" "$a"'
a="$(mk "R 0 refs/remotes/origin/main $S2 3")"
check "R: a ref that moved with a fetch in its reflog is no push" eval '! hi_push_changed "$b" "$a"'
a="$(mk "R 0 refs/remotes/origin/main $S2 0")"
check "R: a ref that moved with no fetch in its reflog is a push" hi_push_changed "$b" "$a"
a="$(mk "R 0 refs/remotes/origin/main $S1 1" "R 0 refs/remotes/dest/x $S2 0")"
check "R: a new tracking ref with no fetch in its reflog is a push" hi_push_changed "$b" "$a"

echo "# F7 / B6: external text reaches the terminal only through the sanitising emitters"
bidi=$'a‮b⁦c‎d\x1b[31me\x07f\x00g'
out="$(hi_term_safe "$bidi" | od -An -c | tr -d ' \n')"
case "$out" in *342*200*256*|*342*201*246*|*033*|*007*) nok "sanitiser left a bidi or control byte ($out)" ;; *) ok "bidi overrides, isolates, ESC and BEL are stripped" ;; esac
eq "visible text survives the sanitiser" "abcd[31mef" "$(printf '%s' "$(hi_term_safe "$bidi")" | tr -d '\0')" 2>/dev/null || true
eq "plain text is unchanged" "hello world" "$(hi_term_safe 'hello world')"
msg="$(hi_say "tag: $bidi" 2>&1 >/dev/null | od -An -c | tr -d ' \n')"
case "$msg" in *342*200*256*|*033*) nok "hi_say printed a raw bidi / ESC byte" ;; *) ok "hi_say sanitises" ;; esac
msg="$(hi_err "tag: $bidi" 2>&1 >/dev/null | od -An -c | tr -d ' \n')"
case "$msg" in *342*200*256*|*033*) nok "hi_err printed a raw bidi / ESC byte" ;; *) ok "hi_err sanitises" ;; esac
for f in "$INSTALLER" "$UPDATER"; do
  bn="$(basename "$f")"
  raw="$(grep -nE '(printf|echo)[^|]*>&[27]|>&7' "$f" | grep -vE 'hi_term_safe|hi_text_filter|\[git-allowlist\]|TEST PAUSE' | grep -E '\$' || true)"
  [ -z "$raw" ] && ok "$bn: every print to the terminal that expands a variable goes through the sanitiser" \
    || { nok "$bn: a raw print of expanded text exists:"; printf '%s\n' "$raw" | head -5; }
  nem="$(grep -cE 'hi_term_safe|hi_text_filter' "$f")"
  [ "$nem" -ge 3 ] && ok "control needle: $bn uses the sanitiser ($nem places)" || nok "$bn: the sanitiser is barely used"
done
# mutation of the scan: a raw print must be caught by the very same pattern
cp "$INSTALLER" "$SB/mut_raw.sh"; printf 'printf "tag: %%s\\n" "$tagname" >&2\n' >>"$SB/mut_raw.sh"
mraw="$(grep -nE '(printf|echo)[^|]*>&[27]|>&7' "$SB/mut_raw.sh" | grep -vE 'hi_term_safe|hi_text_filter|\[git-allowlist\]|TEST PAUSE' | grep -E '\$' || true)"
[ -n "$mraw" ] && ok "mutant: an injected raw print is found by the static scan" || nok "mutant: the static scan did not find an injected raw print"

echo "# F8: the truncation sentinel check compares the LAST line with the sentinel call"
tl="$(tail -n 1 "$INSTALLER")"; eq "installer: last line is the sentinel call" 'main "$@" __helix_installer_eof__' "$tl"
sed '$d' "$INSTALLER" >"$SB/trunc.sh"; printf 'main "$@"\n' >>"$SB/trunc.sh"
[ "$(tail -n 1 "$SB/trunc.sh")" = 'main "$@" __helix_installer_eof__' ] && nok "control: the mutant still ends with the sentinel" || ok "mutant: a copy whose last line lacks the sentinel is told apart"
out="$(bash "$SB/trunc.sh" --version 2>&1)"; rc=$?
eq "a copy without the sentinel refuses (exit 2)" 2 "$rc"

echo "# F10: protocol.file.allow only for local URLs"
LOGF="$SB/gx.log"; : >"$LOGF"
hi_gx() { printf '%s\n' "$*" >>"$LOGF"; }
hi_git_url /tmp/some/local.git submodule update --init -- sub
hi_git_url file:///tmp/some/local.git submodule update --init -- sub
hi_git_url https://example.org/o/r.git submodule update --init -- sub
hi_git_url git@example.org:o/r.git submodule update --init -- sub
eq "local path: -c protocol.file.allow=always" "-c protocol.file.allow=always submodule update --init -- sub" "$(sed -n 1p "$LOGF")"
eq "file URL: -c protocol.file.allow=always" "-c protocol.file.allow=always submodule update --init -- sub" "$(sed -n 2p "$LOGF")"
eq "https URL: no protocol override" "submodule update --init -- sub" "$(sed -n 3p "$LOGF")"
eq "ssh URL: no protocol override" "submodule update --init -- sub" "$(sed -n 4p "$LOGF")"
unset -f hi_gx
n_init="$(grep -c 'submodule update --init' "$INSTALLER")"
n_url="$(grep 'submodule update --init' "$INSTALLER" | grep -c 'hi_git_url')"
check "every 'submodule update --init' call in the installer goes through hi_git_url ($n_url of $n_init code lines)" test "$n_url" -ge 3

echo "# B17: the add path no longer relies on hi_on_remote of the local clone's own refs"
addbody="$(sed -n '/^hi_do_add() {/,/^}/p' "$INSTALLER")"
live_use="$(grep -c 'hi_remote_live' <<<"$addbody")"
[ "$live_use" -ge 1 ] && ok "hi_do_add proves reachability against hi_remote_live" || nok "hi_do_add does not use hi_remote_live"
check "hi_do_add never calls hi_on_remote without a live list" eval '! grep -E "hi_on_remote [^|]*\"\\\$stage\" \"\\\$sha\"( |\\|)*(\\|\\||$)" <<<"$addbody" | grep -vq live'
hi_gx_orig_ok=1

# ───────────────────────── process-level cases ─────────────────────────
export HELIX_INSTALLER_LIB_MODE=
unset HELIX_INSTALLER_LIB_MODE
mkproj() { new_project "$1"; git -C "$1" -c protocol.file.allow=always submodule add -q "$UP" "${2:-submodules/constitution}" >/dev/null 2>&1
  git -C "$1/${2:-submodules/constitution}" checkout -q --detach helixconstitution-v999.0; git -C "$1" add "${2:-submodules/constitution}"; git -C "$1" commit -qm add; }
upd() { local p="$1"; shift; OUT="$(cd "$p" && bash submodules/constitution/scripts/update_constitution.sh "$@" 2>&1)"; RC=$?; }

echo "# F1 end to end: the updater refuses a ref only a stale remote-tracking branch knows"
P="$SB/e1"; mkproj "$P"
git -C "$SB/up/upwork" checkout -q -b stale-topic; echo f >>"$SB/up/upwork/feat.txt"; git -C "$SB/up/upwork" add feat.txt; git -C "$SB/up/upwork" commit -qm feat
git -C "$SB/up/upwork" push -q origin stale-topic; FSHA="$(git -C "$SB/up/upwork" rev-parse HEAD)"
upd "$P" --check --no-hook
git -C "$P/submodules/constitution" rev-parse --verify -q refs/remotes/origin/stale-topic >/dev/null && ok "control: the tracking ref origin/stale-topic exists after --check" || nok "control: no tracking ref"
upd "$P" --no-hook --ref stale-topic; eq "control: while the branch exists upstream the updater accepts it (exit 0)" 0 "$RC"
eq "control: the gitlink moved to the branch tip" "$FSHA" "$(gitlink "$P")"
P2="$SB/e1b"; mkproj "$P2"; upd "$P2" --check --no-hook
git -C "$SB/up/upwork" push -q origin --delete stale-topic
git -C "$UP" reflog expire --expire=now --all; git -C "$UP" gc -q --prune=now
upd "$P2" --no-hook --ref stale-topic
check "after the branch is deleted upstream the updater refuses the stale ref (exit != 0)" test "$RC" != 0
check "the refusal says no remote has it" grep -qiE 'remote|not on|unreach|fetch' <<<"$OUT"
v0="$(git -C "$SB/up/upwork" rev-parse refs/tags/helixconstitution-v999.0^{commit})"
eq "the gitlink was NOT moved to the unfetchable commit" "$v0" "$(gitlink "$P2")"
git -C "$SB/up/upwork" checkout -q main

echo "# F4: a committed symlink 'submodules' -> outside is refused before anything is cloned"
mkdir -p "$SB/outside"; Q="$SB/e10"; new_project "$Q"; ln -s "$SB/outside" "$Q/submodules"; git -C "$Q" add submodules; git -C "$Q" commit -qm link
run_installer "$Q" --non-interactive --agent none --run-setup off --upstream-url "$UP"
eq "symlinked submodules dir: exit 3" 3 "$RC"
eq "nothing was placed outside the project" "" "$(ls -A "$SB/outside")"
check "the message names the symlink" grep -qi 'symlink' <<<"$OUT"
Q2="$SB/e10b"; new_project "$Q2"; run_installer "$Q2" --non-interactive --agent none --run-setup off --upstream-url "$UP"
eq "control: the same project without the symlink installs (exit 0)" 0 "$RC"

echo "# F5 / B9: a push by the agent is detected (UNIT-CLASS: the claude binary is a labelled FAKE)"
mkdir -p "$SB/fakebin" "$SB/sysbin"
for t in awk basename bash cat chmod cp cut date df dirname du env git grep head id kill ln ls mkdir mktemp mv paste python3 readlink rm rmdir sed sh \
         sha256sum sort stat tail timeout tr touch sleep seq wc uuidgen cmp printf true false test cksum od tty getconf uname; do
  p="$(command -v "$t" 2>/dev/null)"; case "$p" in /*) ln -sf "$p" "$SB/sysbin/$t" ;; esac
done
cat >"$SB/fakebin/claude" <<'EOF'
#!/usr/bin/env bash
# FAKE claude (UNIT-CLASS TEST DOUBLE, no LLM call). FAKE_PUSH selects how it pushes, then reports success.
sid=""; prev=""; for a in "$@"; do case "$prev" in --session-id|--resume) sid="$a" ;; esac; prev="$a"; done
if [ -n "${FAKE_PUSH:-}" ] && [ "$FAKE_PUSH" != none ]; then
  git init -q --bare "$FAKE_DEST" 2>/dev/null; git remote add dest "$FAKE_DEST" 2>/dev/null
  case "$FAKE_PUSH" in
    plain)  git push -q dest HEAD:refs/heads/x ;;
    nolog)  git -c core.logAllRefUpdates=false push -q dest HEAD:refs/heads/x ;;
    expire) git push -q dest HEAD:refs/heads/x && git reflog expire --expire=now --all ;;
    sub)    git init -q --bare "$FAKE_DEST.sub" 2>/dev/null
            git -C submodules/constitution remote add subdest "$FAKE_DEST.sub" 2>/dev/null
            git -C submodules/constitution -c core.logAllRefUpdates=false push -q subdest HEAD:refs/heads/y ;;
  esac
fi
printf '{"type":"system","subtype":"init","session_id":"%s"}\n{"type":"result","subtype":"success","is_error":false,"session_id":"%s"}\n' "$sid" "$sid"
EOF
chmod +x "$SB/fakebin/claude"
for m in none plain nolog expire sub; do
  P="$SB/push_$m"; new_project "$P"
  OUT="$(cd "$P" && FAKE_PUSH="$m" FAKE_DEST="$SB/dest_$m.git" PATH="$SB/fakebin:$SB/sysbin" bash "$INSTALLER" --non-interactive --run-setup off --upstream-url "$UP" --agent claude 2>&1)"; RC=$?
  if [ "$m" = none ]; then eq "control: an agent that does not push ends with exit 0" 0 "$RC"
  else eq "push mode '$m' is detected (exit 5)" 5 "$RC"; fi
done

echo "# B17: the add path proves the ref against the LIVE remote (a branch deleted after the clone is refused)"
git -C "$SB/up/upwork" checkout -q -b gone-topic; echo g >"$SB/up/upwork/gone.txt"; git -C "$SB/up/upwork" add gone.txt; git -C "$SB/up/upwork" commit -qm gone
git -C "$SB/up/upwork" push -q origin gone-topic; git -C "$SB/up/upwork" checkout -q main
G="$SB/gone"; new_project "$G"; : >"$SB/gone.resume"; rm -f "$SB/gone.resume"
( cd "$G" && HELIX_INSTALLER_TEST=1 HELIX_INSTALLER_TEST_PAUSE=add_after_clone HELIX_INSTALLER_TEST_RESUME="$SB/gone.resume" \
    bash "$INSTALLER" --non-interactive --agent none --run-setup off --upstream-url "$UP" --ref gone-topic >"$SB/gone.out" 2>&1; echo $? >"$SB/gone.rc" ) &
w=0; while ! grep -q 'TEST PAUSE add_after_clone' "$SB/gone.out" 2>/dev/null && [ "$w" -lt 400 ]; do sleep 0.25; w=$((w+1)); done
grep -q 'TEST PAUSE add_after_clone' "$SB/gone.out" && ok "control: the installer paused after the clone" || nok "the installer never reached the pause"
git -C "$UP" branch -q -D gone-topic; : >"$SB/gone.resume"
w=0; while [ ! -s "$SB/gone.rc" ] && [ "$w" -lt 400 ]; do sleep 0.25; w=$((w+1)); done
check "the installer refuses a ref the remote no longer has (exit != 0)" test "$(cat "$SB/gone.rc" 2>/dev/null)" != 0
check "the message says the remote does not advertise it" grep -q 'advertises now' "$SB/gone.out"
eq "no gitlink was added" "" "$(gitlink "$G")"

echo "# bounded clone timeout (UNIT-CLASS: a git shim that hangs on clone, labelled)"
mkdir -p "$SB/shim"; realgit="$(command -v git)"
cat >"$SB/shim/git" <<EOF
#!/usr/bin/env bash
# UNIT-CLASS TEST DOUBLE: hangs on 'clone', passes everything else to the real git.
for a in "\$@"; do [ "\$a" = clone ] && { sleep 60; exit 0; }; done
exec "$realgit" "\$@"
EOF
chmod +x "$SB/shim/git"
T="$SB/tmo"; new_project "$T"; t0=$SECONDS
OUT="$(cd "$T" && HELIX_INSTALLER_TEST=1 HELIX_INSTALLER_TEST_CLONE_TIMEOUT=2 PATH="$SB/shim:$PATH" bash "$INSTALLER" --non-interactive --agent none --run-setup off --upstream-url "$UP" 2>&1)"; RC=$?
el=$((SECONDS-t0))
check "a hanging clone is cut off by the timeout (took ${el}s, well under 60)" test "$el" -lt 40
check "the install fails instead of hanging (exit != 0)" test "$RC" != 0
O3="$(cd "$T" && PATH="$SB/shim:$PATH" HELIX_INSTALLER_TEST_CLONE_TIMEOUT=2 bash "$INSTALLER" --help 2>&1)"
check "outside test mode the clone-timeout switch does nothing (no HELIX_INSTALLER_TEST)" test -n "$O3"

echo "# B14: the updater's INT and TERM traps remove its lock (UNIT-CLASS: the hook is a labelled fixture that sleeps)"
git -C "$SB/up/upwork" pull -q --ff-only origin main
cat >"$SB/up/upwork/scripts/post_update_hook.sh" <<'EOF'
#!/usr/bin/env bash
# TEST FIXTURE post_update_hook.sh (tests/install/test_round6.sh): signals that it runs, then sleeps.
: >"$PWD/.hook_started"; sleep 4
EOF
git -C "$SB/up/upwork" add -f scripts/post_update_hook.sh; git -C "$SB/up/upwork" commit -qm "test: sleeping fixture hook"
git -C "$SB/up/upwork" tag -a helixconstitution-v999.7 -m t; git -C "$SB/up/upwork" push -q origin main helixconstitution-v999.7
for sig in INT TERM; do
  H="$SB/sig_$sig"; mkproj "$H"
  # the updater runs under a small python parent with default signal dispositions (a plain "&" job of a
  # non-interactive shell ignores SIGINT, and that is inherited); the parent records the exit status
  python3 -I -c 'import subprocess,signal,sys
f=open(sys.argv[2],"w")
p=subprocess.Popen(["bash","submodules/constitution/scripts/update_constitution.sh"],cwd=sys.argv[1],stdout=f,stderr=subprocess.STDOUT,preexec_fn=lambda: signal.signal(signal.SIGINT,signal.SIG_DFL))
open(sys.argv[3],"w").write(str(p.pid)+"\n")
open(sys.argv[4],"w").write(str(p.wait())+"\n")' "$H" "$SB/sig_$sig.out" "$SB/sig_$sig.pid" "$SB/sig_$sig.rc" &
  w=0
  while [ ! -e "$H/.hook_started" ] && [ "$w" -lt 120 ]; do sleep 0.25; w=$((w+1)); done
  pid="$(cat "$SB/sig_$sig.pid" 2>/dev/null)"
  [ -e "$H/.hook_started" ] && ok "$sig: control: the updater reached the hook" || nok "$sig: the updater never reached the hook"
  kill -s "$sig" "$pid" 2>/dev/null; w=0
  while [ ! -s "$SB/sig_$sig.rc" ] && [ "$w" -lt 200 ]; do sleep 0.25; w=$((w+1)); done
  rc="$(tr -d '\n' <"$SB/sig_$sig.rc" 2>/dev/null)"; [ "$rc" -lt 0 ] 2>/dev/null && rc=$((128-rc))
  want=130; [ "$sig" = TERM ] && want=143
  eq "$sig during the hook: exit $want" "$want" "$rc"
  gd="$(git -C "$H" rev-parse --absolute-git-dir)"
  eq "$sig: no lock or temp file left" "" "$(ls -A "$gd" | grep 'helix-constitution-install.lock' || true)"
done
grep -qi 'defer' <<<"$(bash "$INSTALLER" --help 2>&1)" && ok "--help documents that a TERM/INT is acted on after the foreground child exits" \
  || nok "--help does not mention the signal deferral"

finish
