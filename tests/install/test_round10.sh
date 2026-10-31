#!/usr/bin/env bash
# test_round10.sh — round-10 class fixes (W2 installer stream), REAL git, real bare upstreams, real clones:
#   F4  the H-1 refusal names the recorded gitlink as NEWER than the checkout (updater, delegated installer re-run).
#   F5  a STAGED gitlink that differs from both the committed one and the checkout (a change the user staged) is
#       never overwritten: updater (every mode), delegated installer re-run and the installer's built-in updater
#       refuse (exit 3, nothing changed). Positive control: a REAL interrupted double update (the first update
#       staged, the second one cut off by a held .git/index.lock after its checkout) is still finished.
#   F3  helix-deps.yaml: a DANGLING symlink counts as present (never written through, never replaced); the
#       created manifest's mode follows a 077 umask (600).
#   F2  push detection fails CLOSED when a remote (or a url/pushurl) that answered before the agent run cannot be
#       asked after it: insteadOf to a dead path, protocol.file.allow=never, chmod 000 of the bare remote, mv of
#       the bare remote, an unaskable pushurl; controls: plain tag push detected, no push not flagged, a remote
#       that could not be asked BEFORE the run is still skipped (and named), --help states the rule.
# Usage: bash tests/install/test_round10.sh   Exit 0 all pass · 1 a case failed · 2 env error.
# Set R10_SKIP_SETUP=1 to skip the (slow) cases that run the real setup.sh.
T_NAME=round10
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
new_sandbox
mkdir -p "$SB/up"; make_upstream "$SB/up" || exit 2
UP="$SB/up/upstream.git"; V0="$(tagsha "$SB/up" helixconstitution-v999.0)"
BASE=(--non-interactive --agent none --run-setup off --upstream-url "$UP")
upd() { local p="$1"; shift; OUT="$(cd "$p" && bash submodules/constitution/scripts/update_constitution.sh "$@" 2>&1)"; RC=$?; }
mkinstalled() { new_project "$1"; run_installer "$1" "${BASE[@]}" --ref helixconstitution-v999.0; git -C "$1" commit -qm add; }
record_gitlink() { git -C "$1" update-index --cacheinfo "160000,$2,submodules/constitution" && git -C "$1" commit -qm "teammate: bump constitution"; }
stage_gitlink() { git -C "$1" update-index --cacheinfo "160000,$2,submodules/constitution"; }
committed() { git -C "${1:?}" ls-tree HEAD submodules/constitution | awk '{print $3}'; }
pending() { printf '%s/helix-update-pending' "$(git -C "${1:?}" rev-parse --absolute-git-dir)"; }

echo "# F4 the H-1 message says NEWER (not only 'git submodule update', which every refusal says)"
advance_upstream "$SB/up" helixconstitution-v999.1 || exit 2; V1="$(tagsha "$SB/up" helixconstitution-v999.1)"
P="$SB/f4"; mkinstalled "$P"; record_gitlink "$P" "$V1"
upd "$P" --no-hook; eq "recorded newer: exit 3" 3 "$RC"
check "updater message: the recorded gitlink is NEWER than the checkout" grep -q "which is NEWER than the checked-out" <<<"$OUT"
check "updater message: not the diverged wording" eval '! grep -q "DIVERGED" <<<"$OUT"'
run_installer "$P" "${BASE[@]}"; eq "installer re-run: exit 3" 3 "$RC"
check "installer re-run (delegated): NEWER wording" grep -q "which is NEWER than the checked-out" <<<"$OUT"

echo "# F5 a hand-staged gitlink (committed V0 < staged V1 < checkout V2) is never overwritten"
advance_upstream "$SB/up" helixconstitution-v999.2 || exit 2; V2="$(tagsha "$SB/up" helixconstitution-v999.2)"
P="$SB/f5"; mkinstalled "$P"; git -C "$P/submodules/constitution" fetch -q --tags origin
git -C "$P/submodules/constitution" checkout -q --detach "$V2"; stage_gitlink "$P" "$V1"
eq "precondition: committed V0" "$V0" "$(committed "$P")"; eq "precondition: staged V1" "$V1" "$(gitlink "$P")"
check "precondition: no update-pending marker" eval '[ ! -e "$(pending "$P")" ]'
h0="$(git -C "$P" rev-parse HEAD)"
for mode in "" --check --dry-run --commit; do
  upd "$P" --no-hook $mode; eq "updater ${mode:-(plain)}: staged differs from committed and checkout -> exit 3" 3 "$RC"
  eq "updater ${mode:-(plain)}: staged gitlink kept" "$V1" "$(gitlink "$P")"
done
check "message names the staged gitlink and says it is not overwritten" grep -q "staged gitlink .*it is not overwritten" <<<"$OUT"
check "message gives the way out (git add or git restore --staged)" eval 'grep -q "git add" <<<"$OUT" && grep -q "restore --staged" <<<"$OUT"'
eq "no commit made" "$h0" "$(git -C "$P" rev-parse HEAD)"
upd "$P" --no-hook --check; check "--check does not say UPDATE_AVAILABLE=yes" eval '! grep -q "UPDATE_AVAILABLE=yes" <<<"$OUT"'
run_installer "$P" "${BASE[@]}"; eq "installer re-run (delegated): exit 3" 3 "$RC"; eq "installer re-run: staged gitlink kept" "$V1" "$(gitlink "$P")"
advance_upstream "$SB/up" helixconstitution-v999.3 || exit 2; V3="$(tagsha "$SB/up" helixconstitution-v999.3)"
upd "$P" --no-hook; eq "with a newer target (fast-forward path): exit 3" 3 "$RC"; eq "fast-forward path: staged kept" "$V1" "$(gitlink "$P")"
eq "fast-forward path: checkout not moved" "$V2" "$(git -C "$P/submodules/constitution" rev-parse HEAD)"
echo "# F5 controls: staged == checkout, or staged == committed, still update"
git -C "$P" add submodules/constitution; upd "$P" --no-hook; eq "staged == checkout: exit 0" 0 "$RC"; eq "staged the target" "$V3" "$(gitlink "$P")"
P="$SB/f5b"; mkinstalled "$P"; upd "$P" --no-hook; eq "staged == committed: exit 0" 0 "$RC"; eq "staged the target (v999.3)" "$V3" "$(gitlink "$P")"

echo "# F5 positive control: a REAL interrupted double update (--no-hook) is finished"
P="$SB/f5i"; new_project "$P"; run_installer "$P" "${BASE[@]}" --ref helixconstitution-v999.0; git -C "$P" commit -qm add
upd "$P" --no-hook --ref helixconstitution-v999.1; eq "first update (staged, not committed): exit 0" 0 "$RC"; eq "first update staged V1" "$V1" "$(gitlink "$P")"
: >"$(git -C "$P" rev-parse --absolute-git-dir)/index.lock"
upd "$P" --no-hook --ref helixconstitution-v999.2; eq "second update cut off by a held index.lock: exit 1" 1 "$RC"
rm -f -- "$(git -C "$P" rev-parse --absolute-git-dir)/index.lock"
eq "cut-off state: checkout moved to V2" "$V2" "$(git -C "$P/submodules/constitution" rev-parse HEAD)"
eq "cut-off state: staged still V1" "$V1" "$(gitlink "$P")"; eq "cut-off state: committed still V0" "$V0" "$(committed "$P")"
upd "$P" --no-hook --ref helixconstitution-v999.2; eq "re-run finishes the interrupted update: exit 0" 0 "$RC"
eq "re-run staged V2" "$V2" "$(gitlink "$P")"; check "says it finished an interrupted update" grep -qi interrupted <<<"$OUT"
check "marker gone after the finished update" eval '[ ! -e "$(pending "$P")" ]'
echo "# F5 the same with the hook enabled (the hook never runs: the add is what fails)"
P="$SB/f5h"; new_project "$P"; run_installer "$P" "${BASE[@]}" --ref helixconstitution-v999.0; git -C "$P" commit -qm add
upd "$P" --no-hook --ref helixconstitution-v999.1; eq "hook case: first update exit 0" 0 "$RC"
: >"$(git -C "$P" rev-parse --absolute-git-dir)/index.lock"
upd "$P" --ref helixconstitution-v999.2; eq "hook case: cut off exit 1" 1 "$RC"
rm -f -- "$(git -C "$P" rev-parse --absolute-git-dir)/index.lock"
check "hook case: the marker names the cut-off target" eval '[ "$(head -n 1 "$(pending "$P")" | cut -d" " -f1)" = "$V2" ]'
upd "$P" --no-hook --ref helixconstitution-v999.2; eq "hook case: re-run (--no-hook) finishes: exit 0" 0 "$RC"; eq "hook case: staged V2" "$V2" "$(gitlink "$P")"
echo "# F5 a marker naming ANOTHER commit does not license the overwrite"
P="$SB/f5m"; mkinstalled "$P"; git -C "$P/submodules/constitution" fetch -q --tags origin
git -C "$P/submodules/constitution" checkout -q --detach "$V2"; stage_gitlink "$P" "$V1"
printf '%s\n' "$V3" >"$(pending "$P")"   # CONSTRUCTED marker (labelled): names a commit that is not the checkout
upd "$P" --no-hook; eq "foreign marker: exit 3" 3 "$RC"; eq "foreign marker: staged kept" "$V1" "$(gitlink "$P")"

echo "# F5 built-in updater (checkout without update_constitution.sh): committed v71 < staged v72 < checkout v72.1"
C71="$(tagsha "$SB/up" helixconstitution-v71)"; C72="$(tagsha "$SB/up" helixconstitution-v72)"; C721="$(tagsha "$SB/up" helixconstitution-v72.1)"
P="$SB/f5bi"; new_project "$P"
run_installer "$P" --non-interactive --agent none --run-setup off --upstream-url "$UP" --ref helixconstitution-v71; eq "install at v71 exit 0" 0 "$RC"
git -C "$P" commit -qm add; git -C "$P/submodules/constitution" checkout -q --detach "$C721"; stage_gitlink "$P" "$C72"
check "control: the checkout has no updater script (built-in path)" eval '[ ! -f "$P/submodules/constitution/scripts/update_constitution.sh" ]'
run_installer "$P" "${BASE[@]}"; eq "built-in: staged differs -> exit 3" 3 "$RC"
check "built-in path really used (control needle)" grep -q 'built-in updater' <<<"$OUT"
eq "built-in: staged kept" "$C72" "$(gitlink "$P")"; eq "built-in: checkout not moved" "$C721" "$(git -C "$P/submodules/constitution" rev-parse HEAD)"
check "built-in: message names the staged gitlink" grep -q "staged gitlink .*it is not overwritten" <<<"$OUT"
run_installer "$P" "${BASE[@]}" --ref helixconstitution-v72.1; eq "built-in, target == checkout (finish path): exit 3 too" 3 "$RC"; eq "built-in finish path: staged kept" "$C72" "$(gitlink "$P")"
git -C "$P" add submodules/constitution
run_installer "$P" "${BASE[@]}" --ref helixconstitution-v72.1; eq "built-in control: staged == checkout -> exit 0" 0 "$RC"
echo "# F5 built-in: a REAL interrupted double update (v71 -> v72 staged, v72 -> v72.1 cut off by index.lock) is finished"
P="$SB/f5bj"; new_project "$P"
run_installer "$P" --non-interactive --agent none --run-setup off --upstream-url "$UP" --ref helixconstitution-v71; git -C "$P" commit -qm add
run_installer "$P" "${BASE[@]}" --ref helixconstitution-v72; eq "built-in first update: exit 0" 0 "$RC"; eq "built-in first update staged v72" "$C72" "$(gitlink "$P")"
check "built-in first update really built-in (control needle)" grep -q 'built-in updater' <<<"$OUT"
: >"$(git -C "$P" rev-parse --absolute-git-dir)/index.lock"
run_installer "$P" "${BASE[@]}" --ref helixconstitution-v72.1; check "built-in second update cut off: non-zero exit" eval '[ "$RC" != 0 ]'
rm -f -- "$(git -C "$P" rev-parse --absolute-git-dir)/index.lock"
eq "built-in cut-off: checkout at v72.1" "$C721" "$(git -C "$P/submodules/constitution" rev-parse HEAD)"; eq "built-in cut-off: staged still v72" "$C72" "$(gitlink "$P")"
run_installer "$P" "${BASE[@]}" --ref helixconstitution-v72.1; eq "built-in re-run finishes it: exit 0" 0 "$RC"; eq "built-in re-run staged v72.1" "$C721" "$(gitlink "$P")"
check "built-in marker gone after the finish" eval '[ ! -e "$(pending "$P")" ]'

if [ "${R10_SKIP_SETUP:-0}" != 1 ]; then
mkdir -p "${SB:?}/fakehome"
inst_default() { # umask project extra-args... → the REAL setup.sh runs, fake HOME inside the sandbox
  local um="$1" p="$2"; shift 2
  OUT="$(cd "$p" && umask "$um" && HOME="${SB:?}/fakehome" timeout 600 nice -n 15 bash "$INSTALLER" --non-interactive --agent none --decision-layer off --ref helixconstitution-v999.0 --upstream-url "$UP" "$@" 2>&1)"; RC=$?
}
lastreport() { ls -d "$1"/.constitution-install-backup/*/report.json 2>/dev/null | tail -n 1; }
echo "# F3 a DANGLING helix-deps.yaml symlink counts as present: never written through, never replaced"
P="$SB/f3l"; new_project "$P"; ln -s "$SB/f3target/helix-deps.yaml" "$P/helix-deps.yaml"
inst_default 022 "$P"
eq "dangling symlink: report manifest=present" present "$(report_field "$(lastreport "$P")" manifest)"
check "dangling symlink: still a symlink" eval '[ -L "$P/helix-deps.yaml" ]'
eq "dangling symlink: target unchanged" "$SB/f3target/helix-deps.yaml" "$(readlink "$P/helix-deps.yaml")"
check "dangling symlink: nothing written through it" eval '[ ! -e "$SB/f3target" ]'
check "dangling symlink: no 'created helix-deps.yaml'" eval '! grep -q "created helix-deps.yaml" <<<"$OUT"'
echo "# F3 umask 077: the created manifest is 600"
P="$SB/f3u"; new_project "$P"; inst_default 077 "$P"
eq "umask 077: report manifest=created" created "$(report_field "$(lastreport "$P")" manifest)" || printf '%s\n' "$OUT" | tail -8
eq "umask 077: helix-deps.yaml is 600" 600 "$(stat -c %a "$P/helix-deps.yaml" 2>/dev/null)"
fi

echo "# F2 push detection fails closed on a remote that answered before and cannot be asked after"
HELIX_INSTALLER_LIB_MODE=1 . "$INSTALLER"
RB="$SB/rb10"; mkdir -p "$RB"
git init -q --bare "$RB/proj.git"; git init -q --bare "$RB/sub.git"; git init -q --bare "$RB/pushurl.git"
git clone -q "$RB/proj.git" "$RB/seed"; git -C "$RB/seed" commit -q --allow-empty -m s; git -C "$RB/seed" push -q origin HEAD:refs/heads/main
git clone -q "$RB/sub.git" "$RB/sseed"; git -C "$RB/sseed" commit -q --allow-empty -m s; git -C "$RB/sseed" push -q origin HEAD:refs/heads/main
PC="$RB/clone proj"; git clone -q "$RB/proj.git" "$PC"; git clone -q "$RB/sub.git" "$PC/submodules/constitution"
SC="$PC/submodules/constitution"
marks() { O_ROOT="$PC" S_SUBREL=submodules/constitution hi_push_marks; }
pcase() { # name dir command... → PUSHED 0/1, ERRS = what the check printed
  local name="$1" d="$2"; shift 2; local b a
  b="$(marks)"; ( cd "$d" && "$@" ) >/dev/null 2>&1; a="$(marks)"
  if ERRS="$(O_ROOT="$PC" S_SUBREL=submodules/constitution hi_push_changed "$b" "$a" 2>&1)"; then PUSHED=1; else PUSHED=0; fi
}
pcase none "$PC" true; eq "no push (control)" 0 "$PUSHED"
pcase plain "$PC" sh -c 'git tag r10x0 && git push -q origin refs/tags/r10x0'; eq "plain tag push detected (control)" 1 "$PUSHED"
pcase insteadof "$PC" sh -c 'git tag r10x1 && git push -q origin refs/tags/r10x1 && git config "url.$1/nonexistent/dead.git.insteadOf" "$1/proj.git"' _ "$RB"
eq "tag push then insteadOf to a dead path detected" 1 "$PUSHED"
check "insteadOf control: the tag reached the remote" eval '[ -n "$(git -C "$RB/proj.git" for-each-ref refs/tags/r10x1)" ]'
git -C "$PC" config --remove-section "url.$RB/nonexistent/dead.git"
pcase protofile "$PC" sh -c 'git tag r10x2 && git push -q origin refs/tags/r10x2 && git config protocol.file.allow never'
eq "tag push then protocol.file.allow=never detected" 1 "$PUSHED"
check "protocol control: the tag reached the remote" eval '[ -n "$(git -C "$RB/proj.git" for-each-ref refs/tags/r10x2)" ]'
git -C "$PC" config --unset protocol.file.allow
pcase chmod "$PC" sh -c 'git tag r10x3 && git push -q origin refs/tags/r10x3 && chmod 000 "$1/proj.git"' _ "$RB"
chmod 755 "$RB/proj.git"
eq "tag push then chmod 000 of the bare remote detected" 1 "$PUSHED"
check "chmod control: the tag reached the remote" eval '[ -n "$(git -C "$RB/proj.git" for-each-ref refs/tags/r10x3)" ]'
pcase mv "$PC" sh -c 'git tag r10x4 && git push -q origin refs/tags/r10x4 && mv "$1/proj.git" "$1/proj.moved.git"' _ "$RB"
mv "$RB/proj.moved.git" "$RB/proj.git"
eq "tag push then mv of the bare remote detected" 1 "$PUSHED"
check "mv control: the tag reached the remote" eval '[ -n "$(git -C "$RB/proj.git" for-each-ref refs/tags/r10x4)" ]'
pcase none2 "$PC" true; eq "no push after the restores (control)" 0 "$PUSHED"
pcase uploadpack "$PC" git config remote.origin.uploadpack /nonexistent/upload-pack
eq "no push, but the remote answered before and cannot be asked BY NAME after (url still answers): fails closed" 1 "$PUSHED"
git -C "$PC" config --unset remote.origin.uploadpack
pcase none3 "$PC" true; eq "no push after restoring uploadpack (control)" 0 "$PUSHED"
echo "# F2 index 1 (the constitution checkout) and the pushurl"
git -C "$SC" commit -q --allow-empty -m s10
pcase sub_chmod "$SC" sh -c 'git tag r10s1 && git push -q origin refs/tags/r10s1 && chmod 000 "$1/sub.git"' _ "$RB"
chmod 755 "$RB/sub.git"
eq "index 1: tag push then chmod 000 detected" 1 "$PUSHED"
git -C "$PC" remote set-url --push origin "$RB/pushurl.git"
pcase pushurl_chmod "$PC" sh -c 'git tag r10p1 && git push -q origin refs/tags/r10p1 && chmod 000 "$1/pushurl.git"' _ "$RB"
chmod 755 "$RB/pushurl.git"
eq "push to the PUSHURL, then the pushurl repository made unaskable: detected" 1 "$PUSHED"
check "pushurl control: the tag landed in the pushurl repository" eval '[ -n "$(git -C "$RB/pushurl.git" for-each-ref refs/tags/r10p1)" ]'
git -C "$PC" config --unset remote.origin.pushurl
echo "# F2 the fingerprint tool: cksum absent (sha256sum used, the test_agent sandbox shape), and no tool at all (fail closed)"
mkdir -p "$SB/p_sha" "$SB/p_none"
for t in awk bash cat cut env git grep head sed sort tail timeout tr wc mktemp rm sh basename dirname readlink id date printf; do
  x="$(command -v "$t" 2>/dev/null)"; case "$x" in /*) ln -s "$x" "$SB/p_sha/$t"; ln -s "$x" "$SB/p_none/$t" ;; esac
done
ln -s "$(command -v sha256sum)" "$SB/p_sha/sha256sum"
check "control needle: no cksum in the sha256sum-only PATH" eval '! PATH="$SB/p_sha" command -v cksum >/dev/null'
check "control needle: no hasher at all in the bare PATH" eval '! PATH="$SB/p_none" command -v cksum >/dev/null && ! PATH="$SB/p_none" command -v sha256sum >/dev/null'
pathcase() { # PATH name dir command... → PUSHED (marks taken under that PATH)
  local pp="$1" name="$2" d="$3"; shift 3; local b a
  b="$(PATH="$pp" marks)"; ( cd "$d" && "$@" ) >/dev/null 2>&1; a="$(PATH="$pp" marks)"
  if ERRS="$(PATH="$pp" O_ROOT="$PC" S_SUBREL=submodules/constitution hi_push_changed "$b" "$a" 2>&1)"; then PUSHED=1; else PUSHED=0; fi
  MARKS_B="$b"
}
pathcase "$SB/p_sha" sha_none "$PC" true; eq "sha256sum only, no push: not flagged" 0 "$PUSHED"
check "sha256sum only: L lines carry a non-empty fingerprint" grep -qE '^L 0 origin sha256sum:[0-9a-f]{64}' <<<"$MARKS_B"
pathcase "$SB/p_sha" sha_push "$PC" sh -c 'git tag r10h1 && git push -q origin refs/tags/r10h1'; eq "sha256sum only: tag push detected" 1 "$PUSHED"
pathcase "$SB/p_none" nohash "$PC" true; eq "no fingerprint tool at all: fails closed" 1 "$PUSHED"
check "no fingerprint tool: says so" grep -q 'no cksum or sha256sum' <<<"$ERRS"
check "no fingerprint tool: Z lines written, never an empty hash" eval 'grep -q "^Z 0 origin$" <<<"$MARKS_B" && ! grep -qE "^L [0-9]+ [^ ]+ ?$" <<<"$MARKS_B"'
echo "# F2 a remote that could NOT be asked before the run is skipped (not trusted) and named"
git -C "$PC" remote add deadremote "$RB/never-there.git"
b0="$(marks)"; check "control needle: marks record deadremote as unaskable (U)" grep -q '^U 0 deadremote$' <<<"$b0"
check "control needle: marks record its url as unaskable (X)" grep -qF "X 0 $RB/never-there.git" <<<"$b0"
pcase dead_none "$PC" true; eq "unaskable both times, no push: not flagged" 0 "$PUSHED"
check "the skipped remote is named" grep -q 'deadremote' <<<"$ERRS"
pcase dead_push "$PC" sh -c 'git tag r10d1 && git push -q origin refs/tags/r10d1'; eq "a push to origin with deadremote present: still detected" 1 "$PUSHED"
git -C "$PC" remote remove deadremote
HELP="$(bash "$INSTALLER" --help 2>&1 | tr '\n' ' ' | tr -s ' ')"
check "--help: a remote that answered before and not after fails the run" grep -qi "answered before the run and cannot be asked after it" <<<"$HELP"
check "--help: only a remote that could not be asked before the run either is skipped" grep -qi "could not be asked before the run either is skipped" <<<"$HELP"
check "--help: the old blanket 'a remote that cannot be asked is skipped' is gone" eval '! grep -qi "a remote that cannot be asked is skipped" <<<"$HELP"'
finish
