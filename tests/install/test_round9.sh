#!/usr/bin/env bash
# test_round9.sh — round-9 class fixes (W2 installer stream), all with REAL git, real bare upstreams, real clones:
#   H-1  the project RECORDS a newer (or diverged) constitution than the checkout has (a teammate bumped the
#        gitlink, the user ran `git pull` but not `git submodule update`): the updater, its --check/--commit/
#        --dry-run modes, the installer re-run (delegated updater) and the installer's built-in updater must refuse
#        (exit 3, "git submodule update"), stage nothing, commit nothing, never replace the newer gitlink with an
#        older one. Positive controls: an interrupted update (recorded gitlink OLDER than HEAD) is still finished.
#   M-2  --commit never commits a staged gitlink that moves the project's committed gitlink backwards.
#   M-1  a dirty submodule with the update-pending marker gets a message that names the interrupted update.
#   H-2  a fresh project with no helix-deps.yaml installs under DEFAULTS (setup.sh on): the manifest is scaffolded,
#        validated and staged (exit 0); with --commit it is committed; a scaffold that needs human input is left
#        untracked with exact next steps and a distinct status; an existing manifest is never touched.
#   H-3  the shipped installer/updater scripts are recorded executable (no chmod masking in the fixture).
#   I-1  push detection: a push followed by `git remote remove` (C1), a tag push followed by remote removal (C5),
#        pushes from the constitution checkout (index 1: tag push, removal), a tag push to a remote's PUSHURL.
#   I-2  the constitution submodule's remote (index 1) with reflogs off: branch, tag, notes and deletion pushes.
# Usage: bash tests/install/test_round9.sh   Exit 0 all pass · 1 a case failed · 2 env error.
# Set R9_SKIP_SETUP=1 to skip the (slow) cases that run the real setup.sh.
T_NAME=round9
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
new_sandbox
mkdir -p "$SB/up"; make_upstream "$SB/up" || exit 2
UP="$SB/up/upstream.git"; V0="$(tagsha "$SB/up" helixconstitution-v999.0)"
BASE=(--non-interactive --agent none --run-setup off --upstream-url "$UP")
upd() { local p="$1"; shift; OUT="$(cd "$p" && bash submodules/constitution/scripts/update_constitution.sh "$@" 2>&1)"; RC=$?; }
mkinstalled() { new_project "$1"; run_installer "$1" "${BASE[@]}"; git -C "$1" commit -qm add; }
untagged_commit() { # one more commit on upstream main WITHOUT a tag → its sha
  git -C "$SB/up/upwork" pull -q --ff-only origin main || return 1
  printf 'untagged %s\n' "$1" >>"$SB/up/upwork/docs/prompts/setup/advance_marker.txt"
  git -C "$SB/up/upwork" add -f docs/prompts/setup/advance_marker.txt
  git -C "$SB/up/upwork" commit -q -m "test: untagged $1" && git -C "$SB/up/upwork" push -q origin main || return 1
  git -C "$SB/up/upwork" rev-parse HEAD
}
record_gitlink() { # project sha → commit a gitlink the submodule checkout does not have checked out (state after git pull)
  git -C "$1" update-index --cacheinfo "160000,$2,submodules/constitution" && git -C "$1" commit -qm "teammate: bump constitution"
}
nothing_staged() { git -C "${1:?}" diff --cached --quiet; }

echo "# H-1 real teammate flow: teammate bumps the gitlink to main (beyond the newest tag), user git pull, no submodule update"
P="$SB/h1"; mkinstalled "$P"
git init -q --bare "$SB/h1remote.git"; git -C "$P" remote add origin "$SB/h1remote.git"; git -C "$P" push -q origin HEAD:refs/heads/main
git -C "$P" branch -q --set-upstream-to=origin/main 2>/dev/null
advance_upstream "$SB/up" helixconstitution-v999.1 || exit 2; V1="$(tagsha "$SB/up" helixconstitution-v999.1)"
VM="$(untagged_commit h1)" || exit 2
git clone -q "$SB/h1remote.git" "$SB/h1mate"
git -C "$SB/h1mate" -c protocol.file.allow=always submodule update --init -q -- submodules/constitution
git -C "$SB/h1mate/submodules/constitution" fetch -q origin; git -C "$SB/h1mate/submodules/constitution" checkout -q --detach "$VM"
git -C "$SB/h1mate" add submodules/constitution; git -C "$SB/h1mate" commit -qm "teammate: constitution to main"; git -C "$SB/h1mate" push -q origin HEAD:refs/heads/main
git -C "$P" pull -q --ff-only origin main
eq "precondition: the project records the teammate's commit" "$VM" "$(gitlink "$P")"
eq "precondition: the checkout is still the old commit (pull did not update it)" "$V0" "$(git -C "$P/submodules/constitution" rev-parse HEAD)"
h0="$(git -C "$P" rev-parse HEAD)"
upd "$P" --no-hook; eq "updater: recorded gitlink AHEAD of HEAD -> exit 3" 3 "$RC"
check "updater: tells to run git submodule update" grep -q 'git submodule update' <<<"$OUT"
eq "updater: the newer gitlink is kept" "$VM" "$(gitlink "$P")"
check "updater: nothing staged" nothing_staged "$P"
eq "updater: checkout not moved" "$V0" "$(git -C "$P/submodules/constitution" rev-parse HEAD)"
upd "$P" --no-hook --check; eq "--check: exit 3" 3 "$RC"
check "--check does NOT say UPDATE_AVAILABLE=yes" eval '! grep -q "UPDATE_AVAILABLE=yes" <<<"$OUT"'
upd "$P" --no-hook --dry-run; eq "--dry-run: exit 3" 3 "$RC"
upd "$P" --no-hook --commit; eq "--commit: exit 3" 3 "$RC"; eq "--commit: no commit made" "$h0" "$(git -C "$P" rev-parse HEAD)"
eq "--commit: gitlink kept" "$VM" "$(gitlink "$P")"
upd "$P" --no-hook --ref helixconstitution-v999.1; eq "--ref older than the recorded gitlink: exit 3" 3 "$RC"
eq "--ref older: gitlink kept" "$VM" "$(gitlink "$P")"
run_installer "$P" "${BASE[@]}" --report-json "$SB/h1report.json"; eq "installer re-run (delegated updater): exit 3" 3 "$RC"
eq "installer re-run: gitlink kept" "$VM" "$(gitlink "$P")"; check "installer re-run: nothing staged" nothing_staged "$P"
eq "installer re-run: report status blocked" blocked "$(report_field "$SB/h1report.json" status)"
echo "# H-1 the fix the message names converges"
git -C "$P" -c protocol.file.allow=always submodule update -q -- submodules/constitution
upd "$P" --no-hook; eq "after git submodule update: updater exit 0" 0 "$RC"
eq "after git submodule update: gitlink still the newer commit (never moved back)" "$VM" "$(gitlink "$P")"

echo "# H-1 recorded gitlink ahead, newest tag == the recorded gitlink"
P="$SB/h1t"; mkinstalled "$P"; advance_upstream "$SB/up" helixconstitution-v999.2 || exit 2; V2="$(tagsha "$SB/up" helixconstitution-v999.2)"
record_gitlink "$P" "$V2"; upd "$P" --no-hook; eq "ahead (== newest tag): exit 3" 3 "$RC"; check "nothing staged" nothing_staged "$P"
upd "$P" --no-hook --check; check "--check not yes" eval '! grep -q "UPDATE_AVAILABLE=yes" <<<"$OUT"'

echo "# H-1 DIVERGED: recorded gitlink on a side branch, checkout at the newest tag (old code: 'finished an interrupted update')"
git -C "$SB/up/upwork" checkout -q -b side9 "$V0"; git -C "$SB/up/upwork" commit -q --allow-empty -m side9
VS="$(git -C "$SB/up/upwork" rev-parse HEAD)"; git -C "$SB/up/upwork" push -q origin side9; git -C "$SB/up/upwork" checkout -q main
P="$SB/h1d"; mkinstalled "$P"; git -C "$P/submodules/constitution" fetch -q --tags origin
git -C "$P/submodules/constitution" checkout -q --detach "$V2"; record_gitlink "$P" "$VS"
upd "$P" --no-hook; eq "diverged: exit 3" 3 "$RC"; eq "diverged: recorded gitlink kept" "$VS" "$(gitlink "$P")"; check "diverged: nothing staged" nothing_staged "$P"
upd "$P" --no-hook --check; eq "diverged --check: exit 3" 3 "$RC"; check "diverged --check not yes" eval '! grep -q "UPDATE_AVAILABLE=yes" <<<"$OUT"'
run_installer "$P" "${BASE[@]}"; eq "diverged: installer re-run exit 3" 3 "$RC"; eq "diverged: installer kept the gitlink" "$VS" "$(gitlink "$P")"

echo "# H-1 recorded gitlink unknown to the checkout (never fetched): refused, not treated as interrupted"
P="$SB/h1u"; mkinstalled "$P"; record_gitlink "$P" "0123456789abcdef0123456789abcdef01234567"
upd "$P" --no-hook; eq "unknown recorded commit: exit 3" 3 "$RC"; eq "unknown: gitlink kept" "0123456789abcdef0123456789abcdef01234567" "$(gitlink "$P")"

echo "# H-1 positive controls: the recorded gitlink OLDER than HEAD (an interrupted update) is still finished"
P="$SB/h1c"; mkinstalled "$P"; git -C "$P/submodules/constitution" fetch -q --tags origin
VN="$(tagsha "$SB/up" helixconstitution-v999.2)"; git -C "$P/submodules/constitution" checkout -q --detach "$VN"
record_gitlink "$P" "$V0"   # the cut-off shape: checkout moved to the target, the recorded gitlink still the OLD commit
eq "precondition: recorded gitlink is the older v999.0" "$V0" "$(gitlink "$P")"
upd "$P" --no-hook; eq "older recorded, HEAD == target: exit 0" 0 "$RC"; eq "staged the HEAD commit" "$VN" "$(gitlink "$P")"
check "says it finished an interrupted update" grep -qi 'interrupted' <<<"$OUT"

echo "# M-2 --commit never commits a staged gitlink that moves the committed one backwards"
P="$SB/m2"; mkinstalled "$P"; VM2="$(untagged_commit m2)" || exit 2
git -C "$P/submodules/constitution" fetch -q --tags origin; git -C "$P/submodules/constitution" checkout -q --detach "$VN"
record_gitlink "$P" "$VM2"   # committed: main tip (newer than the newest tag)
git -C "$P" update-index --cacheinfo "160000,$VN,submodules/constitution"   # staged by hand: the OLDER newest tag (== HEAD == target)
h0="$(git -C "$P" rev-parse HEAD)"
upd "$P" --no-hook --commit; eq "staged downgrade + --commit: exit 3" 3 "$RC"; eq "no commit made" "$h0" "$(git -C "$P" rev-parse HEAD)"
eq "committed gitlink unchanged" "$VM2" "$(git -C "$P" ls-tree HEAD submodules/constitution | awk '{print $3}')"
upd "$P" --no-hook; eq "staged downgrade without --commit: exit 3 too" 3 "$RC"
git -C "$P" update-index --cacheinfo "160000,$VM2,submodules/constitution"

echo "# H-1 built-in updater (constitution version without update_constitution.sh)"
P="$SB/h1b"; new_project "$P"
run_installer "$P" --non-interactive --agent none --run-setup off --upstream-url "$UP" --ref helixconstitution-v71; eq "install at v71 exit 0" 0 "$RC"
git -C "$P" commit -qm add; check "control: v71 has no updater script" eval '[ ! -f "$P/submodules/constitution/scripts/update_constitution.sh" ]'
record_gitlink "$P" "$V0"   # the teammate recorded v999.0; the checkout stays at v71
h0="$(git -C "$P" rev-parse HEAD)"
run_installer "$P" "${BASE[@]}" --ref helixconstitution-v72.1
eq "built-in: recorded gitlink ahead, older --ref: exit 3" 3 "$RC"; eq "built-in: gitlink kept" "$V0" "$(gitlink "$P")"
check "built-in: nothing staged" nothing_staged "$P"; check "built-in: names git submodule update" grep -q 'git submodule update' <<<"$OUT"
check "built-in path was really used (control needle)" grep -q 'built-in updater' <<<"$OUT"
run_installer "$P" "${BASE[@]}"; eq "built-in: default target: exit 3 too" 3 "$RC"; eq "built-in default: gitlink kept" "$V0" "$(gitlink "$P")"
eq "built-in: no commit" "$h0" "$(git -C "$P" rev-parse HEAD)"
# M-2 class in the built-in path: committed gitlink NEWER (v999.0), staged gitlink moved back to the checkout (v71)
C71="$(git -C "$P/submodules/constitution" rev-parse HEAD)"
git -C "$P" update-index --cacheinfo "160000,$C71,submodules/constitution"
run_installer "$P" "${BASE[@]}"; eq "built-in: staged downgrade, committed newer: exit 3" 3 "$RC"
eq "built-in: committed gitlink unchanged" "$V0" "$(git -C "$P" ls-tree HEAD submodules/constitution | awk '{print $3}')"
eq "built-in: the staged gitlink was not moved" "$C71" "$(gitlink "$P")"
eq "built-in: still no commit" "$h0" "$(git -C "$P" rev-parse HEAD)"

echo "# M-1 dirty submodule while the update-pending marker names an interrupted update"
P="$SB/m1"; mkinstalled "$P"
printf '%s\n' "$V2" >"$(git -C "$P" rev-parse --absolute-git-dir)/helix-update-pending"   # CONSTRUCTED marker (labelled)
printf 'half\n' >>"$P/submodules/constitution/README.md"
upd "$P"; eq "dirty + marker: exit 3" 3 "$RC"
check "message names the interrupted update (not only 'your local changes')" grep -qi 'interrupted' <<<"$OUT"
rm -f -- "$(git -C "$P" rev-parse --absolute-git-dir)/helix-update-pending"
upd "$P"; check "dirty without marker: the plain local-changes message" grep -q 'has local changes' <<<"$OUT"
check "dirty without marker: no interrupted claim" eval '! grep -qi "interrupted" <<<"$OUT"'

echo "# H-3 shipped scripts are executable; the fixture records them 100755 without any chmod in lib.sh"
eq "fixture commit records the installer 100755" 100755 "$(git -C "$SB/up/upwork" ls-files -s scripts/install_constitution.sh | cut -d' ' -f1)"
eq "fixture commit records the updater 100755" 100755 "$(git -C "$SB/up/upwork" ls-files -s scripts/update_constitution.sh | cut -d' ' -f1)"
check "lib.sh carries no chmod of the shipped scripts" eval '! grep -E "chmod [0-7]+ .*(install|update)_constitution" "$REPO/tests/install/lib.sh"'
P="$SB/h3"; mkinstalled "$P"; advance_upstream "$SB/up" helixconstitution-v999.3 || exit 2
mkdir -p "$SB/up/upwork/scripts"; cat >"$SB/up/upwork/scripts/post_update_hook.sh" <<'EOS'
#!/usr/bin/env bash
# TEST FIXTURE hook: does what the real hook's STEP 5 does to the changed scripts/*.sh (chmod +x); the changed
# shipped scripts of this fixture are the installer and the updater
for f in "${CONST_DIR:?}"/scripts/install_constitution.sh "${CONST_DIR:?}"/scripts/update_constitution.sh; do chmod +x "$f"; done
EOS
git -C "$SB/up/upwork" add -f scripts/post_update_hook.sh; git -C "$SB/up/upwork" commit -qm "fixture chmod hook"
git -C "$SB/up/upwork" tag -a helixconstitution-v999.4 -m t; git -C "$SB/up/upwork" push -q origin main helixconstitution-v999.4
upd "$P"; eq "update with a chmod +x hook: exit 0" 0 "$RC"
eq "the submodule is clean after the hook chmod-ed every script (shipped modes)" "" "$(git -C "$P/submodules/constitution" status --porcelain)"
advance_upstream "$SB/up" helixconstitution-v999.5 || exit 2
upd "$P" --no-hook; eq "the next update is not blocked by a dirty submodule" 0 "$RC"

echo "# I-1 push detection (REAL clones and bare remotes; clone-based fixture, never push-seeded)"
HELIX_INSTALLER_LIB_MODE=1 . "$INSTALLER"
RB="$SB/rb9"; mkdir -p "$RB"
git init -q --bare "$RB/proj.git"; git init -q --bare "$RB/sub.git"; git init -q --bare "$RB/pushurl.git"
git clone -q "$RB/proj.git" "$RB/seed"; git -C "$RB/seed" commit -q --allow-empty -m s; git -C "$RB/seed" push -q origin HEAD:refs/heads/main
git clone -q "$RB/sub.git" "$RB/sseed"; git -C "$RB/sseed" commit -q --allow-empty -m s; git -C "$RB/sseed" push -q origin HEAD:refs/heads/main
PC="$RB/clone proj"; git clone -q "$RB/proj.git" "$PC"; git clone -q "$RB/sub.git" "$PC/submodules/constitution"
marks() { O_ROOT="$PC" S_SUBREL=submodules/constitution hi_push_marks; }
pcase() { # name dir command... → PUSHED 0/1
  local name="$1" d="$2"; shift 2; local b a
  b="$(marks)"; ( cd "$d" && "$@" ) >/dev/null 2>&1; a="$(marks)"
  if O_ROOT="$PC" S_SUBREL=submodules/constitution hi_push_changed "$b" "$a"; then PUSHED=1; else PUSHED=0; fi
}
readd() { git -C "$1" remote add origin "$2" 2>/dev/null; git -C "$1" fetch -q origin; }
b0="$(marks)"
check "control needle: the clone has no 'update by push' reflog (not push-seeded)" eval '! grep -q "^M " <<<"$b0"'
check "control needle: marks name the project's remote" grep -q '^N 0 origin$' <<<"$b0"
check "control needle: marks name the constitution's remote (index 1)" grep -q '^N 1 origin$' <<<"$b0"
pcase none "$PC" true; eq "no push (control)" 0 "$PUSHED"
pcase none1 "$PC/submodules/constitution" true; eq "no push in the constitution (control)" 0 "$PUSHED"
git -C "$PC" commit -q --allow-empty -m c1
pcase C1 "$PC" sh -c 'git push -q origin HEAD:refs/heads/c1 && git remote remove origin'; eq "C1 push then 'git remote remove origin' detected" 1 "$PUSHED"
check "C1 control: the push really reached the remote" eval '[ -n "$(git -C "$RB/proj.git" for-each-ref refs/heads/c1)" ]'
readd "$PC" "$RB/proj.git"
pcase C5 "$PC" sh -c 'git tag t5 && git push -q origin refs/tags/t5 && git remote remove origin'; eq "C5 tag push then remote removal detected" 1 "$PUSHED"
readd "$PC" "$RB/proj.git"
pcase rmonly "$PC" git remote remove origin; eq "a remote removed during the run fails closed (no push needed)" 1 "$PUSHED"
readd "$PC" "$RB/proj.git"
git -C "$PC/submodules/constitution" commit -q --allow-empty -m s1
pcase sub_tag "$PC/submodules/constitution" sh -c 'git tag st1 && git push -q origin refs/tags/st1'; eq "index 1: tag push from the constitution detected" 1 "$PUSHED"
pcase sub_C1 "$PC/submodules/constitution" sh -c 'git push -q origin HEAD:refs/heads/s1 && git remote remove origin'; eq "index 1: push then remote removal detected" 1 "$PUSHED"
readd "$PC/submodules/constitution" "$RB/sub.git"
pcase sub_nolog "$PC/submodules/constitution" git -c core.logAllRefUpdates=false push -q origin HEAD:refs/heads/s2; eq "index 1: branch push with reflogs off detected" 1 "$PUSHED"
echo "# I-2 the constitution submodule's remote (index 1): every advertised-ref change, reflogs OFF (no M/R evidence)"
SC="$PC/submodules/constitution"; NOLOG=(git -c core.logAllRefUpdates=false)
git -C "$SC" commit -q --allow-empty -m s3
pcase sub_branch "$SC" "${NOLOG[@]}" push -q origin HEAD:refs/heads/s3; eq "index 1: branch push (reflogs off) detected" 1 "$PUSHED"
check "index 1 branch control: the branch reached the remote" eval '[ -n "$(git -C "$RB/sub.git" for-each-ref refs/heads/s3)" ]'
"${NOLOG[@]}" -C "$SC" tag st3
pcase sub_tag_nolog "$SC" "${NOLOG[@]}" push -q origin refs/tags/st3; eq "index 1: tag push (reflogs off) detected" 1 "$PUSHED"
check "index 1 tag control: the tag reached the remote" eval '[ -n "$(git -C "$RB/sub.git" for-each-ref refs/tags/st3)" ]'
"${NOLOG[@]}" -C "$SC" notes add -m n3 HEAD
pcase sub_notes "$SC" "${NOLOG[@]}" push -q origin refs/notes/commits; eq "index 1: notes push (reflogs off) detected" 1 "$PUSHED"
check "index 1 notes control: the notes ref reached the remote" eval '[ -n "$(git -C "$RB/sub.git" for-each-ref refs/notes/commits)" ]'
pcase sub_deltag "$SC" "${NOLOG[@]}" push -q origin :refs/tags/st3; eq "index 1: tag DELETION push detected" 1 "$PUSHED"
check "index 1 deletion control: the tag is gone from the remote" eval '[ -z "$(git -C "$RB/sub.git" for-each-ref refs/tags/st3)" ]'
pcase sub_delbranch "$SC" "${NOLOG[@]}" push -q origin :refs/heads/s3; eq "index 1: branch DELETION push detected" 1 "$PUSHED"
check "index 1 branch-deletion control: the branch is gone from the remote" eval '[ -z "$(git -C "$RB/sub.git" for-each-ref refs/heads/s3)" ]'
pcase sub_none2 "$SC" true; eq "index 1: no push after the cases (control)" 0 "$PUSHED"
git -C "$PC" remote set-url --push origin "$RB/pushurl.git"
b1="$(marks)"; check "control needle: marks carry the pushurl as its own V line" eval 'grep -q "^V 0 [a-z0-9]*:[0-9a-f-]* $RB/pushurl.git$" <<<"$b1"'
pcase pushurl "$PC" sh -c 'git tag tp && git push -q origin refs/tags/tp'; eq "tag push to the remote's PUSHURL detected" 1 "$PUSHED"
check "pushurl control: the tag landed in the pushurl repository" eval '[ -n "$(git -C "$RB/pushurl.git" for-each-ref refs/tags/tp)" ]'
pcase seturl "$PC" sh -c 'git tag tq && git push -q origin refs/tags/tq && git remote set-url origin "$1/nowhere.git" && git remote set-url --push origin "$1/nowhere.git"' _ "$RB"
eq "tag push then set-url (url and pushurl) to a dead path detected" 1 "$PUSHED"
check "--help LIMITS still list the unconfigured-URL push" eval 'bash "$INSTALLER" --help 2>&1 | tr "\n" " " | tr -s " " | grep -q "push by URL to a remote"'
check "--help names remote removal as detected" eval 'bash "$INSTALLER" --help 2>&1 | tr "\n" " " | tr -s " " | grep -qi "removed during the run"'

if [ "${R9_SKIP_SETUP:-0}" != 1 ]; then
mkdir -p "${SB:?}/fakehome"
inst_default() { # project extra-args... → the REAL setup.sh runs (default --run-setup on), fake HOME inside the sandbox
  local p="$1"; shift
  OUT="$(cd "$p" && umask 022 && HOME="${SB:?}/fakehome" timeout 600 nice -n 15 bash "$INSTALLER" --non-interactive --agent none --decision-layer off --ref helixconstitution-v999.0 --upstream-url "$UP" "$@" 2>&1)"; RC=$?
}
echo "# H-2 fresh project, NO helix-deps.yaml, DEFAULTS (setup.sh runs): exit 0, manifest scaffolded, valid, staged"
P="$SB/h2"; new_project "$P"
inst_default "$P"; eq "fresh project, defaults: exit 0" 0 "$RC"; [ "$RC" = 0 ] || printf '%s\n' "$OUT" | tail -12
check "setup.sh really ran (control needle)" grep -q 'running submodules/constitution/scripts/setup.sh' <<<"$OUT"
check "helix-deps.yaml created" eval '[ -f "$P/helix-deps.yaml" ]'
check "helix-deps.yaml staged (tracked)" eval '[ -n "$(git -C "$P" ls-files -- helix-deps.yaml)" ]'
eq "helix-deps.yaml mode follows the user's umask (022 -> 644)" 644 "$(stat -c %a "$P/helix-deps.yaml")"
check "the manifest validates" bash "$P/submodules/constitution/scripts/deps_manifest/verify_helix_deps_manifests.sh" --validate-file "$P/helix-deps.yaml"
R="$(ls -d "$P"/.constitution-install-backup/*/report.json | tail -n 1)"
check "report lists helix-deps.yaml among written_files" python3 -I -c 'import json,sys; sys.exit(0 if "helix-deps.yaml" in json.load(open(sys.argv[1]))["written_files"] else 1)' "$R"
check "backup records helix-deps.yaml as created" eval 'grep -qx helix-deps.yaml "$(dirname "$R")/created.txt"'
echo "# H-2 same with --commit on: the manifest is committed with the constitution"
P="$SB/h2c"; new_project "$P"
inst_default "$P" --commit on; eq "--commit on, no manifest: exit 0" 0 "$RC"; [ "$RC" = 0 ] || printf '%s\n' "$OUT" | tail -12
check "--commit on: helix-deps.yaml is in the commit" eval 'git -C "$P" cat-file -e HEAD:helix-deps.yaml'
check "--commit on: submodule in the commit" eval '[ "$(git -C "$P" ls-tree HEAD submodules/constitution | cut -d" " -f1)" = 160000 ]'
echo "# H-2 a scaffold that needs human input (an own-org submodule): untracked, exact steps, distinct status"
P="$SB/h2n"; new_project "$P"
printf '[submodule "submodules/foo"]\n\tpath = submodules/foo\n\turl = git@github.com:vasic-digital/foo.git\n' >"$P/.gitmodules"
git -C "$P" update-index --add --cacheinfo "160000,0123456789abcdef0123456789abcdef01234567,submodules/foo"
git -C "$P" add .gitmodules; git -C "$P" commit -qm "own-org submodule (not checked out)"
inst_default "$P"; eq "needs completion: exit 1" 1 "$RC"
R="$(ls -d "$P"/.constitution-install-backup/*/report.json | tail -n 1)"
eq "needs completion: distinct report status" manifest-needs-completion "$(report_field "$R" status)"
check "needs completion: file left untracked" eval '[ -f "$P/helix-deps.yaml" ] && [ -z "$(git -C "$P" ls-files -- helix-deps.yaml)" ]'
check "needs completion: prints the validate step" grep -q -- '--validate-file' <<<"$OUT"
check "needs completion: prints the git add step" grep -q 'git add helix-deps.yaml' <<<"$OUT"
check "needs completion: says the manifest needs completion" grep -q 'helix-deps.yaml needs completion' <<<"$OUT"
check "needs completion: not reported as a bare setup failure" eval '! grep -q "ERROR: setup.sh failed (exit" <<<"$OUT"'
echo "# H-2 an existing manifest is never touched (manifest-present path)"
P="$SB/h2p"; new_project "$P"
printf 'schema_version: 1\ndeps: []\ntransitive_handling:\n  recursive: true\n  conflict_resolution: operator-required\nlanguage_specific_subtree: false\n' >"$P/helix-deps.yaml"
git -C "$P" add helix-deps.yaml; git -C "$P" commit -qm manifest; s="$(sha256sum <"$P/helix-deps.yaml")"
inst_default "$P"; eq "manifest present: exit 0" 0 "$RC"; eq "manifest present: content unchanged" "$s" "$(sha256sum <"$P/helix-deps.yaml")"
check "manifest present: not listed as written" eval '! python3 -I -c "import json,sys; sys.exit(0 if \"helix-deps.yaml\" in json.load(open(sys.argv[1]))[\"written_files\"] else 1)" "$(ls -d "$P"/.constitution-install-backup/*/report.json | tail -n 1)"'
echo "# H-2 dry run names the manifest step and writes nothing"
P="$SB/h2d"; new_project "$P"; s0="$(project_state "$P")"
OUT="$(cd "$P" && bash "$INSTALLER" --non-interactive --agent none --dry-run --upstream-url "$UP" 2>&1)"; RC=$?
eq "dry run exit 0" 0 "$RC"; check "plan names helix-deps.yaml" grep -q 'helix-deps.yaml' <<<"$OUT"; eq "dry run changed nothing" "$s0" "$(project_state "$P")"
fi
finish
