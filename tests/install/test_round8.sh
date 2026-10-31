#!/usr/bin/env bash
# test_round8.sh — round-8 class fixes (W2 installer stream), all with REAL git:
#   I-1  an update cut off after the submodule checkout (project .git/index.lock held, so `git add` fails) is
#        RECONCILED by the re-run (updater and installer, both on the update path) instead of "already up to date"
#        with the parent gitlink still old; every mid-run interruption point of the update path is exercised.
#   I-2  hi_push_marks/hi_push_changed detect tag pushes, non-heads namespaces (refs/notes) and survive a project
#        path containing a SPACE (real bare remote, real pushes, control needles).
#   M-1..M-6 minor findings (default --run-setup on path, --recurse-submodules refusal layer, pgid==pid guard,
#        trailing dot/space strip in hi_restore_rel, deny-list note, failed blobless clone mv collision).
# Usage: bash tests/install/test_round8.sh   Exit 0 all pass · 1 a case failed · 2 env error.
T_NAME=round8
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
new_sandbox
mkdir -p "$SB/up"; make_upstream "$SB/up" || exit 2
UP="$SB/up/upstream.git"; V0="$(tagsha "$SB/up" helixconstitution-v999.0)"
BASE=(--non-interactive --agent none --run-setup off --upstream-url "$UP")
upd() { local p="$1"; shift; OUT="$(cd "$p" && bash submodules/constitution/scripts/update_constitution.sh "$@" 2>&1)"; RC=$?; }
lockidx() { : >"$1/.git/index.lock"; }
unlockidx() { rm -f -- "${1:?}/.git/index.lock"; }
mkinstalled() { # dir → project with the constitution installed + committed at V0
  new_project "$1"; run_installer "$1" "${BASE[@]}"; git -C "$1" commit -qm add
}

echo "# I-1 updater: cut off after checkout (index.lock) then re-run"
P="$SB/i1"; mkinstalled "$P"; eq "install exit 0" 0 "$RC"
advance_upstream "$SB/up" helixconstitution-v999.1 || exit 2; V1="$(tagsha "$SB/up" helixconstitution-v999.1)"
lockidx "$P"; upd "$P" --no-hook
check "locked index: updater fails (non-zero)" eval '[ "$RC" != 0 ]'
eq "locked index: submodule moved (constructed by the real checkout)" "$V1" "$(git -C "$P/submodules/constitution" rev-parse HEAD)"
eq "locked index: gitlink still old" "$V0" "$(gitlink "$P")"
check "failure message tells to re-run" grep -qi 're-run' <<<"$OUT"
unlockidx "$P"
upd "$P" --no-hook --check; check "--check on the half-done state reports UPDATE_AVAILABLE=yes" grep -q 'UPDATE_AVAILABLE=yes' <<<"$OUT"
eq "--check changed nothing" "$V0" "$(gitlink "$P")"
s0="$(project_state "$P")"; upd "$P" --no-hook --dry-run; eq "--dry-run exit 0" 0 "$RC"; eq "--dry-run changed nothing" "$s0" "$(project_state "$P")"
upd "$P" --no-hook; eq "re-run exit 0" 0 "$RC"
eq "re-run: gitlink is the new commit" "$V1" "$(gitlink "$P")"
check "re-run says it finished the interrupted update" grep -qi 'interrupted\|reconcil\|resum' <<<"$OUT"
upd "$P" --no-hook; eq "third run exit 0" 0 "$RC"; check "third run: plain already up to date" grep -q 'already up to date' <<<"$OUT"
git -C "$P" reset -q; git -C "$P" checkout -q -- . 2>/dev/null

echo "# I-1 installer (update path) on the same half-done state"
P="$SB/i1b"; mkinstalled "$P"
advance_upstream "$SB/up" helixconstitution-v999.2 || exit 2; V2="$(tagsha "$SB/up" helixconstitution-v999.2)"
G0="$(gitlink "$P")"; lockidx "$P"; run_installer "$P" "${BASE[@]}"; check "installer with locked index: non-zero" eval '[ "$RC" != 0 ]'
eq "gitlink still old" "$G0" "$(gitlink "$P")"
unlockidx "$P"; run_installer "$P" "${BASE[@]}"
eq "installer re-run converges (exit 0)" 0 "$RC"
eq "installer re-run: gitlink new" "$V2" "$(gitlink "$P")"
check "installer re-run does not claim a no-op" eval '! grep -q "nothing to do (no-op)" <<<"$OUT"'

echo "# I-1 hand-constructed half state (reviewer shape): checkout done, nothing staged, no lock"
P="$SB/i1c"; mkinstalled "$P"
git -C "$P/submodules/constitution" fetch -q --tags origin; git -C "$P/submodules/constitution" checkout -q --detach "$V2"
run_installer "$P" "${BASE[@]}"; eq "installer on half state: exit 0 (not exit 5 after 'up to date')" 0 "$RC"
eq "gitlink reconciled" "$V2" "$(gitlink "$P")"

echo "# I-1 hook-pending: cut off after staging, before the hook ran"
P="$SB/i1d"; mkinstalled "$P"
upd "$P" --no-hook; eq "update without hook exit 0" 0 "$RC"
advance_upstream "$SB/up" helixconstitution-v999.3 || exit 2
git -C "$P" commit -qm "bump"
# interrupt: stage succeeds, hook is killed by TERM to the updater right when the hook starts (simulated by a hook that kills its parent)
mkdir -p "$SB/up/upwork/scripts"
cat >"$SB/up/upwork/scripts/post_update_hook.sh" <<'EOS'
#!/usr/bin/env bash
# HELIX_HOOK_CAPABILITIES: project-root
# TEST FIXTURE hook: the first call is cut off (kills the updater), later calls record that they ran
if [ ! -e "${PROJECT_ROOT:?}/.first_done" ]; then : >"$PROJECT_ROOT/.first_done"; kill -s KILL "$PPID"; sleep 1; exit 0; fi
printf 'ran\n' >>"$PROJECT_ROOT/hook_ran.txt"
EOS
git -C "$SB/up/upwork" add -f scripts/post_update_hook.sh; git -C "$SB/up/upwork" commit -qm "fixture hook v2"
git -C "$SB/up/upwork" tag -a helixconstitution-v999.5 -m t; git -C "$SB/up/upwork" push -q origin main helixconstitution-v999.5
V5="$(tagsha "$SB/up" helixconstitution-v999.5)"
upd "$P" ; check "updater killed during the hook: non-zero" eval '[ "$RC" != 0 ]'
eq "gitlink was staged before the hook" "$V5" "$(gitlink "$P")"
upd "$P"; eq "re-run exit 0" 0 "$RC"
check "re-run ran the hook that was cut off" eval '[ -f "$P/hook_ran.txt" ]'
upd "$P"; check "next run: plain up to date, hook not re-run again" eval '[ "$(wc -l <"$P/hook_ran.txt")" = 1 ]'

echo "# I-1 built-in updater (constitution versions without update_constitution.sh): half state reconciled"
P="$SB/i1e"; new_project "$P"
run_installer "$P" --non-interactive --agent none --run-setup off --upstream-url "$UP" --ref helixconstitution-v71; eq "install at v71 exit 0" 0 "$RC"
git -C "$P" commit -qm add; GB="$(gitlink "$P")"
check "control: v71 has no updater script (built-in path in use)" eval '[ ! -f "$P/submodules/constitution/scripts/update_constitution.sh" ]'
lockidx "$P"; run_installer "$P" --non-interactive --agent none --run-setup off --upstream-url "$UP" --ref helixconstitution-v72.1
check "built-in update with locked index: non-zero" eval '[ "$RC" != 0 ]'
eq "built-in: gitlink still old" "$GB" "$(gitlink "$P")"; unlockidx "$P"
run_installer "$P" --non-interactive --agent none --run-setup off --upstream-url "$UP" --ref helixconstitution-v72.1
eq "built-in re-run exit 0" 0 "$RC"; eq "built-in re-run: gitlink is v72.1" "$(tagsha "$SB/up" helixconstitution-v72.1)" "$(gitlink "$P")"
check "built-in re-run says it finished the update" grep -q 'finishing an interrupted' <<<"$OUT"

echo "# I-1 --commit resume: gitlink staged by an earlier run, commit never made"
P="$SB/i1f"; mkinstalled "$P"; advance_upstream "$SB/up" helixconstitution-v999.6 || exit 2; V6="$(tagsha "$SB/up" helixconstitution-v999.6)"
upd "$P" --no-hook; eq "stage-only update exit 0" 0 "$RC"; h0="$(git -C "$P" rev-parse HEAD)"
upd "$P" --no-hook --commit; eq "re-run with --commit exit 0" 0 "$RC"
check "the commit was made by the resumed run" eval '[ "$(git -C "$P" rev-parse HEAD)" != "$h0" ] && [ "$(git -C "$P" rev-parse HEAD:submodules/constitution)" = "$V6" ]'
upd "$P" --no-hook --commit; check "then nothing more to do" grep -q 'already up to date' <<<"$OUT"

if [ "${R8_SKIP_CHAOS:-0}" != 1 ]; then
echo "# I-1 chaos on the UPDATE path: INT/TERM to the process group at many points of a real update, then a clean re-run converges"
j=0; cut=0
for sig in INT TERM; do
  for delay in 0.05 0.2 0.4 0.7 1.1; do
    j=$((j+1)); P="$SB/u$j"; mkinstalled "$P"
    advance_upstream "$SB/up" "helixconstitution-v999.1$j" || exit 2; VT="$(tagsha "$SB/up" "helixconstitution-v999.1$j")"
    (cd "$P" && exec python3 -I -c 'import os, signal, sys; signal.signal(signal.SIGINT, signal.SIG_DFL); os.execvp(sys.argv[1], sys.argv[1:])' \
       setsid bash "$INSTALLER" "${BASE[@]}" >"$SB/u$j.log" 2>&1) &
    pid=$!; sleep "$delay"
    pgid="$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')"
    if [[ "$pgid" =~ ^[0-9]+$ ]] && [ "$pgid" -gt 1 ]; then kill -s "$sig" -- "-$pgid" 2>/dev/null; fi
    wait "$pid" 2>/dev/null; rc1=$?; [ "$rc1" != 0 ] && cut=$((cut+1))
    run_installer "$P" "${BASE[@]}"
    if [ "$RC" = 0 ] && [ "$(gitlink "$P")" = "$VT" ] && [ "$(git -C "$P/submodules/constitution" rev-parse HEAD)" = "$VT" ]; then
      ok "update SIG$sig after ${delay}s (first rc=$rc1): re-run converged to the new gitlink"
    else nok "update SIG$sig after ${delay}s (first rc=$rc1): re-run rc=$RC gitlink=$(gitlink "$P")"; printf '%s\n' "$OUT" | tail -6; fi
  done
done
check "signals really cut off some update runs ($cut of $j)" eval '[ "$cut" -ge 3 ]'
fi

echo "# I-2 push detection: REAL bare remote, REAL pushes, project path with SPACES"
RB="$SB/rb"; mkdir -p "$RB"; git init -q --bare "$RB/remote.git"; git init -q --bare "$RB/other.git"
PS="$RB/my proj dir"; new_project "$PS"; git -C "$PS" remote add origin "$RB/remote.git"; git -C "$PS" push -q origin HEAD:refs/heads/main
git -C "$PS" fetch -q origin
pushcase() { # NAME action-command... — marks before, run the push, marks after; sets PUSHED=0/1
  local name="$1"; shift
  local b a; b="$(O_ROOT="$PS" S_SUBREL=submodules/constitution hi_push_marks)"
  ( cd "$PS" && "$@" ) >/dev/null 2>&1
  a="$(O_ROOT="$PS" S_SUBREL=submodules/constitution hi_push_marks)"
  if hi_push_changed "$b" "$a"; then PUSHED=1; else PUSHED=0; fi
  PB="$b"; PA="$a"
}
HELIX_INSTALLER_LIB_MODE=1 . "$INSTALLER"
b0="$(O_ROOT="$PS" S_SUBREL=submodules/constitution hi_push_marks)"
check "control needle: marks carry an L line for the configured remote" grep -q '^L 0 origin ' <<<"$b0"
check "control needle: marks carry R lines for the tracking ref (path with spaces parsed)" grep -q '^R 0 refs/remotes/origin/main ' <<<"$b0"
pushcase none true;                                       eq "no push (control)" 0 "$PUSHED"
git -C "$PS" commit -q --allow-empty -m c1
pushcase branch git push -q origin HEAD:refs/heads/side;  eq "branch push detected" 1 "$PUSHED"
pushcase tag sh -c 'git tag t1 && git push -q origin refs/tags/t1'; eq "TAG push to a configured remote detected (I-2a)" 1 "$PUSHED"
pushcase notes sh -c 'git notes add -m n HEAD && git push -q origin refs/notes/commits'; eq "refs/notes push detected (I-2b)" 1 "$PUSHED"
pushcase delete git push -q origin :refs/heads/side;      eq "branch deletion on the remote detected" 1 "$PUSHED"
git -C "$PS" commit -q --allow-empty -m c2
pushcase quiet git -c core.logAllRefUpdates=false push -q origin HEAD:refs/heads/main; eq "push with reflogs off detected" 1 "$PUSHED"
# the R class alone (L lines removed) in the SPACED path: a push with reflogs off moves a tracking ref no fetch explains
git -C "$PS" commit -q --allow-empty -m c3
b="$(O_ROOT="$PS" S_SUBREL=submodules/constitution hi_push_marks | grep -v '^L ')"
( cd "$PS" && git -c core.logAllRefUpdates=false push -q origin HEAD:refs/heads/main )
a="$(O_ROOT="$PS" S_SUBREL=submodules/constitution hi_push_marks | grep -v '^L ')"
check "R class works when the project path contains a space (I-2c)" hi_push_changed "$b" "$a"
# honest limit: a push by URL to a repository that is not a configured remote is NOT detected
git -C "$PS" commit -q --allow-empty -m c4
pushcase url git push -q "$RB/other.git" HEAD:refs/heads/x; eq "LIMIT (documented): push by URL to an unconfigured repository is not seen" 0 "$PUSHED"
check "the unconfigured repository really received the push (control needle)" eval '[ -n "$(git -C "$RB/other.git" for-each-ref refs/heads/x)" ]'
check "--help lists that limit" eval 'bash "$INSTALLER" --help 2>&1 | tr "\n" " " | tr -s " " | grep -q "push by URL to a remote"'
# a remote that cannot be asked is not a change
git -C "$PS" remote add dead "$RB/nonexistent.git"
pushcase dead true; eq "an unreachable remote is skipped, not a push" 0 "$PUSHED"
git -C "$PS" remote remove dead

echo "# M-2 --recurse-submodules refused by its own layer (read-only subcommands, no other layer applies)"
for src in "$INSTALLER" "$UPDATER"; do
  n="$(basename "$src")"
  for f in "status --porcelain --recurse-submodules" "ls-files --recurse-submodules" "diff --recurse-submodules" "log --recurse-submodules=yes"; do
    (HELIX_INSTALLER_LIB_MODE=1 HELIX_UPDATER_LIB_MODE=1 . "$src"; read -r -a w <<<"$f"; hi_gx_check "${w[@]}") >/dev/null 2>&1; rc=$?
    eq "$n: '$f' refused (exit 3)" 3 "$rc"
  done
  (HELIX_INSTALLER_LIB_MODE=1 HELIX_UPDATER_LIB_MODE=1 . "$src"; hi_gx_check status --porcelain) >/dev/null 2>&1; rc=$?
  eq "$n: control needle: plain 'status --porcelain' allowed (exit 0)" 0 "$rc"
done

echo "# M-3 hi_stop_agent signals the group only when pgid == agent pid (group never ours otherwise)"
out="$(setsid bash -c '
  HELIX_INSTALLER_LIB_MODE=1 . "$1"
  sleep 300 & HI_AGENT_PID=$!
  sleep 302 & SIB=$!       # same process group as the shell: must survive
  hi_stop_agent 2>/dev/null
  sleep 0.3
  if kill -0 "$SIB" 2>/dev/null; then echo SIBLING_ALIVE; kill "$SIB"; fi
  echo REACHED_END' _ "$INSTALLER" 2>&1)"; rc=$?
check "the agent job was stopped and the shell kept running (REACHED_END)" grep -q REACHED_END <<<"$out"
check "a process of the shell's own group (pgid != agent pid) survived" grep -q SIBLING_ALIVE <<<"$out"
eq "isolated shell exited normally" 0 "$rc"

echo "# M-4 trailing dot / space in a .git segment: REAL backup files exist, restore must not create them"
RP="$SB/rp4"; new_project "$RP"; RBK="$RP/.constitution-install-backup"
mkdir -p "$RBK/t1/files"; chmod 700 "$RBK" "$RBK/t1" "$RBK/t1/files"; : >"$RBK/t1/manifest.txt"
for ent in '.git./hooks/pre-commit' '.git /hooks/pre-commit' 'sub/.GIT. /hooks/x'; do
  printf '%s\n' "$ent" >>"$RBK/t1/manifest.txt"; mkdir -p "$RBK/t1/files/$(dirname "$ent")"; printf 'PLANTED\n' >"$RBK/t1/files/$ent"
done
printf 'fine.md\n' >>"$RBK/t1/manifest.txt"; printf 'fine\n' >"$RBK/t1/files/fine.md"
run_installer "$RP" --restore "$RBK/t1"; eq "restore exit 0" 0 "$RC"
check "control needle: the ordinary entry WAS restored" eval '[ "$(cat "$RP/fine.md")" = fine ]'
check "'.git.' dir not created" eval '[ ! -e "$RP/.git./hooks/pre-commit" ]'
check "'.git ' (trailing space) dir not created" eval '[ ! -e "$RP/.git /hooks/pre-commit" ]'
check "'sub/.GIT. ' not created" eval '[ ! -e "$RP/sub/.GIT. /hooks/x" ]'

echo "# M-6 failed blobless clone: the move-aside target already exists as a FILE (failure injected with a git shim)"
mkdir -p "$SB/shim"
REALGIT="$(command -v git)"
cat >"$SB/shim/git" <<EOS
#!/bin/bash
# TEST FIXTURE (failure injection only): the blobless clone fails after leaving a partial directory and a FILE where
# the installer will want to move it aside; every other git call is the real git.
for a in "\$@"; do
  if [ "\$a" = --filter=blob:none ]; then
    last="\${!#}"; mkdir -p "\$last/partial"; : >"\$(dirname "\$last")/failed-blobless-clone"; echo "fatal: injected blobless failure" >&2; exit 128
  fi
done
exec "$REALGIT" "\$@"
EOS
chmod +x "$SB/shim/git"
P="$SB/m6"; new_project "$P"
OUT="$(cd "$P" && PATH="$SB/shim:$PATH" bash "$INSTALLER" "${BASE[@]}" --ref helixconstitution-v999.5 2>&1)"; RC=$?
eq "install converges through the full-clone retry (exit 0)" 0 "$RC"
eq "gitlink recorded" "$(tagsha "$SB/up" helixconstitution-v999.5)" "$(gitlink "$P")"
check "the failure was injected (control needle)" grep -q 'blobless clone failed' <<<"$OUT"

if [ "${R8_SKIP_SETUP:-0}" != 1 ]; then
echo "# M-1 DEFAULT --run-setup (on): the committed setup.sh really runs in a sandbox project (fake HOME inside the sandbox)"
P="$SB/m1"; new_project "$P"
# MANIFEST-PRESENT path: the project already tracks its helix-deps.yaml (the installer must leave it alone). The
# fresh-project path without a manifest is covered in test_round9.sh (the installer scaffolds it).
printf 'schema_version: 1\ndeps: []\ntransitive_handling:\n  recursive: true\n  conflict_resolution: operator-required\nlanguage_specific_subtree: false\n' >"$P/helix-deps.yaml"; git -C "$P" add helix-deps.yaml; git -C "$P" commit -qm manifest
mkdir -p "${SB:?}/fakehome"
OUT="$(cd "$P" && HOME="${SB:?}/fakehome" timeout 300 nice -n 15 bash "$INSTALLER" --non-interactive --agent none --decision-layer off --ref helixconstitution-v999.0 --upstream-url "$UP" 2>&1)"; RC=$?
eq "default-setup install exit 0" 0 "$RC"; [ "$RC" = 0 ] || printf '%s\n' "$OUT" | tail -8
check "setup.sh was run by default" grep -q 'running submodules/constitution/scripts/setup.sh' <<<"$OUT"
check "setup.sh effect: git hooks installed in the project (control: not there before)" eval 'ls "$P/.git/hooks" | grep -qv "\.sample$"'
echo "# UNCONFIRMED: this used the setup.sh committed at the sandbox clone's HEAD; the working-tree setup.sh is being changed by another stream and was not exercised here."

fi
finish
