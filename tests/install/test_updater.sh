#!/usr/bin/env bash
# test_updater.sh — INTEGRATION tests of scripts/update_constitution.sh run from INSIDE a real consumer's
# submodule (both layouts), against a REAL local bare upstream: --check, fast-forward, already-latest,
# ahead-of-target, refusal on local changes / unpushed commits / divergence / network loss, --dry-run,
# --commit, and the post-update hook seam (cwd = project root, CONSTITUTION_JEV_HOOK=off).
# The hook used in the hook case is a labelled TEST FIXTURE committed to the test upstream.
# Usage: bash tests/install/test_updater.sh   Exit 0 all pass · 1 a case failed · 2 env error.
T_NAME=updater
# shellcheck source=lib.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
new_sandbox
mkdir -p "$SB/up"; make_upstream "$SB/up" || exit 2
UP="$SB/up/upstream.git"; V0="$(tagsha "$SB/up" helixconstitution-v999.0)"
mkproj() { # dir path-in-project
  new_project "$1"; git -C "$1" -c protocol.file.allow=always submodule add -q "$UP" "$2" >/dev/null 2>&1
  git -C "$1/$2" checkout -q --detach helixconstitution-v999.0; git -C "$1" add "$2"; git -C "$1" commit -qm add
}
upd() { local p="$1" s="$2"; shift 2; OUT="$(cd "$p" && bash "$s/scripts/update_constitution.sh" "$@" 2>&1)"; RC=$?; }

P="$SB/std"; mkproj "$P" submodules/constitution
upd "$P" submodules/constitution --check --no-hook; eq "check at latest: exit 0" 0 "$RC"
check "check at latest says no" grep -q 'UPDATE_AVAILABLE=no' <<<"$OUT"
advance_upstream "$SB/up" helixconstitution-v999.1 || exit 2; V1="$(tagsha "$SB/up" helixconstitution-v999.1)"
upd "$P" submodules/constitution --check --no-hook; check "check after advance says yes" grep -q 'UPDATE_AVAILABLE=yes' <<<"$OUT"
eq "check changed nothing" "$V0" "$(git -C "$P/submodules/constitution" rev-parse HEAD)"
s0="$(project_state "$P")"; upd "$P" submodules/constitution --dry-run --no-hook
eq "dry-run exit 0" 0 "$RC"; eq "dry-run changed nothing" "$s0" "$(project_state "$P")"
upd "$P" submodules/constitution --no-hook
eq "fast-forward exit 0" 0 "$RC"; eq "fast-forward HEAD" "$V1" "$(git -C "$P/submodules/constitution" rev-parse HEAD)"
eq "gitlink staged" "$V1" "$(gitlink "$P")"; check "not committed" eval '[ -n "$(git -C "$P" diff --cached --name-only)" ]'
check "before + after printed" eval 'grep -q "before: $V0" <<<"$OUT" && grep -q "after: $V1" <<<"$OUT"'
upd "$P" submodules/constitution --no-hook; eq "re-run exit 0" 0 "$RC"; check "re-run already up to date" grep -q 'already up to date' <<<"$OUT"
upd "$P" submodules/constitution --no-hook --ref helixconstitution-v72.1; eq "older target: exit 0" 0 "$RC"
check "older target: ahead, no change" eval 'grep -q "ahead of" <<<"$OUT" && [ "$(git -C "$P/submodules/constitution" rev-parse HEAD)" = "$V1" ]'

echo "# refusals"
printf 'local\n' >>"$P/submodules/constitution/README.md"; s0="$(project_state "$P")"
upd "$P" submodules/constitution --no-hook; eq "local changes -> exit 3" 3 "$RC"; eq "local changes: nothing changed" "$s0" "$(project_state "$P")"
git -C "$P/submodules/constitution" checkout -q -- README.md
git -C "$P/submodules/constitution" commit -q --allow-empty -m "local unpushed"
upd "$P" submodules/constitution --no-hook; eq "unpushed commit -> exit 3" 3 "$RC"
git -C "$P/submodules/constitution" checkout -q --detach "$V1"
git -C "$SB/up/upwork" checkout -q -b side "$(tagsha "$SB/up" helixconstitution-v72.1)"
git -C "$SB/up/upwork" commit -q --allow-empty -m side; git -C "$SB/up/upwork" push -q origin side
git -C "$SB/up/upwork" checkout -q main
upd "$P" submodules/constitution --no-hook --ref side; eq "diverged target -> exit 3" 3 "$RC"
eq "diverged: HEAD unchanged" "$V1" "$(git -C "$P/submodules/constitution" rev-parse HEAD)"
upd "$P" submodules/constitution --no-hook --ref '--upload-pack=x'; eq "option-like ref -> exit 2" 2 "$RC"
advance_upstream "$SB/up" helixconstitution-v999.2 || exit 2
mv "$UP" "$SB/up/gone.git"; upd "$P" submodules/constitution --no-hook; eq "network loss -> exit 3" 3 "$RC"
mv "$SB/up/gone.git" "$UP"

echo "# a tag created only locally never counts as 'pushed' (reviewer mutant E)"
git -C "$P/submodules/constitution" checkout -q --detach "$(tagsha "$SB/up" helixconstitution-v999.2)"
git -C "$P/submodules/constitution" commit -q --allow-empty -m "local unpushed"
git -C "$P/submodules/constitution" tag helixconstitution-v99999 HEAD
lt_head="$(git -C "$P/submodules/constitution" rev-parse HEAD)"
upd "$P" submodules/constitution --no-hook; eq "unpushed commit carrying a local-only tag -> exit 3" 3 "$RC"
check "refusal says unpushed" grep -q 'unpushed' <<<"$OUT"
eq "local-only tag: HEAD unchanged" "$lt_head" "$(git -C "$P/submodules/constitution" rev-parse HEAD)"
git -C "$P/submodules/constitution" tag -d helixconstitution-v99999 >/dev/null
git -C "$P/submodules/constitution" checkout -q --detach "$V1"

echo "# --commit and legacy layout"
upd "$P" submodules/constitution --no-hook --commit; eq "--commit exit 0" 0 "$RC"
eq "--commit: clean afterwards" "" "$(git -C "$P" status --porcelain)"
eq "--commit: committed gitlink" "$(tagsha "$SB/up" helixconstitution-v999.2)" "$(git -C "$P" ls-tree HEAD submodules/constitution | awk '{print $3}')"
L="$SB/leg"; mkproj "$L" constitution
upd "$L" constitution --no-hook; eq "legacy layout update exit 0" 0 "$RC"
eq "legacy layout reached newest tag" "$(tagsha "$SB/up" helixconstitution-v999.2)" "$(gitlink "$L" constitution)"

echo "# post-update hook seam (TEST FIXTURE hook committed to the upstream)"
git -C "$SB/up/upwork" pull -q --ff-only origin main
cat >"$SB/up/upwork/scripts/post_update_hook.sh" <<'EOF'
#!/usr/bin/env bash
# TEST FIXTURE post_update_hook.sh (tests/install/test_updater.sh): records how it was invoked.
printf 'cwd=%s jev=%s args=[%s]\n' "$PWD" "${CONSTITUTION_JEV_HOOK:-unset}" "$*" >"$PWD/.hook_ran"
EOF
git -C "$SB/up/upwork" add scripts/post_update_hook.sh; git -C "$SB/up/upwork" commit -qm "test: fixture hook"
git -C "$SB/up/upwork" tag -a helixconstitution-v999.3 -m t; git -C "$SB/up/upwork" push -q origin main helixconstitution-v999.3
H="$SB/hook"; mkproj "$H" submodules/constitution
unset CONSTITUTION_JEV_HOOK; upd "$H" submodules/constitution; export CONSTITUTION_JEV_HOOK=off
eq "update with hook exit 0" 0 "$RC"
eq "hook ran from the project root with Jev off, no arguments (this older hook does not parse --project-root)" \
  "cwd=$H jev=off args=[]" "$(cat "$H/.hook_ran" 2>/dev/null)"
echo "# target = newest RELEASE tag by version order: v999.9 < v999.10 < v999.100; pre-releases skipped"
for t in helixconstitution-v999.9 helixconstitution-v999.10 helixconstitution-v999.100 helixconstitution-v999.101-rc1; do
  advance_upstream "$SB/up" "$t" || exit 2; done
O="$SB/order"; mkproj "$O" submodules/constitution
upd "$O" submodules/constitution --no-hook; eq "ordering: exit 0" 0 "$RC"
eq "ordering: newest release v999.100 chosen (not v999.9 lexical, not v999.101-rc1)" \
  "$(tagsha "$SB/up" helixconstitution-v999.100)" "$(git -C "$O/submodules/constitution" rev-parse HEAD)"
upd "$O" submodules/constitution --no-hook --ref helixconstitution-v999.101-rc1; eq "a pre-release can still be pinned with --ref" 0 "$RC"
eq "pinned pre-release reached" "$(tagsha "$SB/up" helixconstitution-v999.101-rc1)" "$(git -C "$O/submodules/constitution" rev-parse HEAD)"

echo "# run lock: the updater takes the SAME lock as the installer (one of them at a time per project)"
K="$SB/lockp"; mkproj "$K" submodules/constitution
advance_upstream "$SB/up" helixconstitution-v999.200 || exit 2
KL="$K/.git/helix-constitution-install.lock"; k0="$(git -C "$K/submodules/constitution" rev-parse HEAD)"
sleep 60 & holder=$!; printf '%s\n' "$holder" >"$KL"
upd "$K" submodules/constitution --no-hook
eq "lock held by a live run -> exit 3" 3 "$RC"
check "lock held: message names the holder" grep -q "pid $holder" <<<"$OUT"
eq "lock held: HEAD unchanged" "$k0" "$(git -C "$K/submodules/constitution" rev-parse HEAD)"
eq "lock held: the other run's lock is left alone" "$holder" "$(tr -cd 0-9 <"$KL")"
kill "$holder" 2>/dev/null; wait "$holder" 2>/dev/null
upd "$K" submodules/constitution --no-hook --check
eq "stale lock (dead pid), --check: exit 0" 0 "$RC"
check "--check reports the update" grep -q 'UPDATE_AVAILABLE=yes' <<<"$OUT"
check "--check released the lock" eval '[ ! -e "$KL" ] && [ ! -L "$KL" ]'
printf '%s\n' "$holder" >"$KL"
upd "$K" submodules/constitution --no-hook
eq "stale lock (dead pid) is reclaimed: exit 0" 0 "$RC"
eq "stale lock: update applied" "$(tagsha "$SB/up" helixconstitution-v999.200)" "$(git -C "$K/submodules/constitution" rev-parse HEAD)"
check "no lock, temp or reclaim file left" eval '[ -z "$(ls -A "$K/.git" | grep -F helix-constitution-install.lock)" ]'
rm -f -- "$KL"; mkfifo "$KL"
( cd "$K" && bash "$K/submodules/constitution/scripts/update_constitution.sh" --no-hook --check >"$SB/fifo.out" 2>&1; echo "rc=$?" >>"$SB/fifo.out" ) &
fp=$!; for ((t=0; t<150; t++)); do kill -0 "$fp" 2>/dev/null || break; sleep 0.1; done
kill -9 "$fp" 2>/dev/null; wait "$fp" 2>/dev/null
check "FIFO at the lock path: updater returned (never opened it)" grep -q '^rc=' "$SB/fifo.out"
check "FIFO at the lock path: refused (rc=3)" grep -q '^rc=3$' "$SB/fifo.out"
check "FIFO at the lock path: left in place" eval '[ -p "$KL" ]'
rm -f -- "$KL"
echo "# control: a normal updater run leaves no lock behind"
upd "$K" submodules/constitution --no-hook; eq "control: re-run exit 0" 0 "$RC"
check "control: no lock files after a normal run" eval '[ -z "$(ls -A "$K/.git" | grep -F helix-constitution-install.lock)" ]'

echo "# lock hand-over: an updater started BY the installer (HELIX_CONSTITUTION_LOCK_DELEGATED=<holder pid>)"
advance_upstream "$SB/up" helixconstitution-v999.201 || exit 2
sleep 60 & holder=$!; printf '%s\n' "$holder" >"$KL"
OUT="$(cd "$K" && HELIX_CONSTITUTION_LOCK_DELEGATED="$holder" bash "$K/submodules/constitution/scripts/update_constitution.sh" --no-hook 2>&1)"; RC=$?
eq "delegated by the live holder: exit 0" 0 "$RC"
eq "delegated: update applied" "$(tagsha "$SB/up" helixconstitution-v999.201)" "$(git -C "$K/submodules/constitution" rev-parse HEAD)"
eq "delegated: the holder's lock is left in place (the updater never removes a lock it does not own)" "$holder" "$(tr -cd 0-9 <"$KL" 2>/dev/null)"
sleep 60 & other=$!
OUT="$(cd "$K" && HELIX_CONSTITUTION_LOCK_DELEGATED="$other" bash "$K/submodules/constitution/scripts/update_constitution.sh" --no-hook --check 2>&1)"; RC=$?
eq "delegation naming a pid that is NOT the holder: refused (exit 3)" 3 "$RC"
eq "wrong delegation: lock unchanged" "$holder" "$(tr -cd 0-9 <"$KL" 2>/dev/null)"
for bad in "x$holder" "$holder " "-1" ""; do
  OUT="$(cd "$K" && HELIX_CONSTITUTION_LOCK_DELEGATED="$bad" bash "$K/submodules/constitution/scripts/update_constitution.sh" --no-hook --check 2>&1)"; RC=$?
  eq "malformed delegation value [$bad] while the lock is held: refused (exit 3)" 3 "$RC"
done
check "refusal message carries no stray exit code (die prints only the message)" grep -q 'ERROR: could not take the run lock' <<<"$OUT"
kill "$holder" "$other" 2>/dev/null; wait "$holder" "$other" 2>/dev/null
OUT="$(cd "$K" && HELIX_CONSTITUTION_LOCK_DELEGATED="$holder" bash "$K/submodules/constitution/scripts/update_constitution.sh" --no-hook --check 2>&1)"; RC=$?
eq "delegation naming a DEAD holder: not honoured, the stale lock is reclaimed normally (exit 0)" 0 "$RC"
check "dead-holder delegation: lock released afterwards" eval '[ ! -e "$KL" ] && [ ! -L "$KL" ]'
OUT="$(cd "$K" && HELIX_CONSTITUTION_LOCK_DELEGATED=12345 bash "$K/submodules/constitution/scripts/update_constitution.sh" --no-hook --check 2>&1)"; RC=$?
eq "delegation set but no lock at all: takes its own lock (exit 0)" 0 "$RC"
check "no-lock delegation: its own lock released" eval '[ ! -e "$KL" ] && [ ! -L "$KL" ]'

echo "# a tag with a leading zero (v01000.0) is not a release tag: never the default target"
z_new="$(tagsha "$SB/up" helixconstitution-v999.201)"
advance_upstream "$SB/up" helixconstitution-v01000.0 || exit 2
Z="$SB/zero"; mkproj "$Z" submodules/constitution
git -C "$Z/submodules/constitution" checkout -q --detach "$z_new"; git -C "$Z" add submodules/constitution; git -C "$Z" commit -qm pin
upd "$Z" submodules/constitution --no-hook --check
eq "leading-zero tag: --check exit 0" 0 "$RC"
check "leading-zero tag is not offered as an update" grep -q 'UPDATE_AVAILABLE=no' <<<"$OUT"
check "control: target printed is the newest real release" grep -q "target: helixconstitution-v999.201" <<<"$OUT"

echo "# the post-update hook gets PROJECT_ROOT / CONST_DIR from the updater, never from a hostile ambient env"
git -C "$SB/up/upwork" pull -q --ff-only origin main
cat >"$SB/up/upwork/scripts/post_update_hook.sh" <<'EOF'
#!/usr/bin/env bash
# TEST FIXTURE post_update_hook.sh (tests/install/test_updater.sh): records the environment and arguments it was
# given. Like the real hook since W1 round 7 it parses --project-root and DECLARES that with the capability marker
# below (the updater passes --project-root only to a hook that carries it near the top).
# HELIX_HOOK_CAPABILITIES: project-root
pr=unset
while [ $# -gt 0 ]; do case "$1" in --project-root) pr="$2"; shift 2 ;; *) pr="bad:$1"; shift ;; esac; done
printf 'argroot=%s\n' "$pr" >"$PWD/.hook_args"
lk="$(git rev-parse --absolute-git-dir 2>/dev/null)/helix-constitution-install.lock"
printf 'const=%s\nproject=%s\ndlg=%s\nlockpid=%s\n' "${CONST_DIR-unset}" "${PROJECT_ROOT-unset}" \
  "${HELIX_CONSTITUTION_LOCK_DELEGATED-unset}" "$(tr -cd 0-9 <"$lk" 2>/dev/null)" >"$PWD/.hook_env"
EOF
git -C "$SB/up/upwork" add scripts/post_update_hook.sh; git -C "$SB/up/upwork" commit -qm "test: env-recording fixture hook"
git -C "$SB/up/upwork" tag -a helixconstitution-v999.300 -m t; git -C "$SB/up/upwork" push -q origin main helixconstitution-v999.300
HE="$SB/hookenv"; mkproj "$HE" submodules/constitution; mkdir -p "$SB/victim_const" "$SB/victim_proj"
OUT="$(cd "$HE" && CONST_DIR="$SB/victim_const" PROJECT_ROOT="$SB/victim_proj" CONSTITUTION_JEV_HOOK=off \
       bash "$HE/submodules/constitution/scripts/update_constitution.sh" 2>&1)"; RC=$?
eq "hostile ambient CONST_DIR/PROJECT_ROOT: update exit 0" 0 "$RC"
check "control: the env-recording hook ran" eval '[ -s "$HE/.hook_env" ]'
eq "hook got CONST_DIR = the updated submodule (not the ambient value)" "const=$HE/submodules/constitution" "$(grep '^const=' "$HE/.hook_env" 2>/dev/null)"
eq "hook got PROJECT_ROOT = the project (not the ambient value)" "project=$HE" "$(grep '^project=' "$HE/.hook_env" 2>/dev/null)"
check "hook was handed the run lock (delegation pid == pid recorded in the lock, non-empty)" eval \
  'hk_d="$(sed -n "s/^dlg=//p" "$HE/.hook_env")"; hk_l="$(sed -n "s/^lockpid=//p" "$HE/.hook_env")"; [[ "$hk_d" =~ ^[0-9]+$ ]] && [ "$hk_d" = "$hk_l" ]'
eq "hook got --project-root = the project (explicit argument, W1 round 7)" "argroot=$HE" "$(cat "$HE/.hook_args" 2>/dev/null)"
check "nothing was written to the ambient victim directories" eval '[ -z "$(ls -A "$SB/victim_const")" ] && [ -z "$(ls -A "$SB/victim_proj")" ]'   # one dir per ls: two dirs print headers
check "the lock is released after the hook" eval '[ ! -e "$HE/.git/helix-constitution-install.lock" ]'

echo "# ref resolution: a branch name means the REMOTE branch, never a stale local branch of that name (I-1)"
RR="$SB/refres"; mkproj "$RR" submodules/constitution; RS="$RR/submodules/constitution"
git -C "$SB/up/upwork" pull -q --ff-only origin main
git -C "$SB/up/upwork" commit -q --allow-empty -m "test: advance main past every tag"; git -C "$SB/up/upwork" push -q origin main
um="$(git -C "$UP" rev-parse main)"
git -C "$RS" branch -f main "$(tagsha "$SB/up" helixconstitution-v999.0)"   # a stale LOCAL main
eq "control: the local main is stale" "$(tagsha "$SB/up" helixconstitution-v999.0)" "$(git -C "$RS" rev-parse refs/heads/main)"
upd "$RR" submodules/constitution --no-hook --ref main
eq "--ref main with a stale local main: exit 0" 0 "$RC"
eq "--ref main reached the upstream main (not the stale local branch)" "$um" "$(gitlink "$RR")"
check "--ref main: the target printed is the upstream main" grep -q "target: main = $um" <<<"$OUT"
git -C "$RR" commit -qm pin
echo "# the target commit must be on a remote too, not only the current one (I-2)"
git -C "$RS" checkout -q -b localonly "$um"; git -C "$RS" commit -q --allow-empty -m "local only, never pushed"
lo="$(git -C "$RS" rev-parse HEAD)"; git -C "$RS" checkout -q --detach "$um"
for tref in localonly "$lo" "${lo:0:12}"; do
  upd "$RR" submodules/constitution --no-hook --ref "$tref"
  eq "--ref $tref (a commit no remote has) -> exit 3" 3 "$RC"
  check "--ref $tref: the refusal says the target is not on a remote" grep -q 'is not on any remote' <<<"$OUT"
  eq "--ref $tref: HEAD unchanged" "$um" "$(git -C "$RS" rev-parse HEAD)"
  eq "--ref $tref: gitlink unchanged" "$um" "$(gitlink "$RR")"
  eq "--ref $tref: nothing staged" "" "$(git -C "$RR" diff --cached --name-only)"
done
upd "$RR" submodules/constitution --no-hook --ref "$um"; eq "--ref <pushed sha>: exit 0" 0 "$RC"
git -C "$RS" branch -f pinned "$(tagsha "$SB/up" helixconstitution-v999.0)"
upd "$RR" submodules/constitution --no-hook --ref pinned
eq "a local-only ref NAME on a pushed commit: exit 0 (ahead, no change)" 0 "$RC"
check "a local-only ref is announced as LOCAL" grep -q 'using the LOCAL ref pinned' <<<"$OUT"


echo "# hook capability probe (F9): an explicit marker line near the top, never a text pattern inside the hook's code"
probe_n=400
probe() { # description expected-argroot('' = none) marker-lines... → one fixture hook, one fresh project, one update
  local d="$1" exp="$2" PH="$SB/probe$probe_n"; shift 2
  git -C "$SB/up/upwork" pull -q --ff-only origin main
  { printf '#!/usr/bin/env bash\n# TEST FIXTURE post_update_hook.sh (probe test: %s)\n' "$d"
    printf '%s\n' "$@"
    printf 'pr=unset\nwhile [ $# -gt 0 ]; do case "$1" in --project-root) pr="$2"; shift 2 ;; *) pr="bad:$1"; shift ;; esac; done\n'
    printf 'printf "argroot=%%s\\n" "$pr" >"$PWD/.hook_args"\n'
  } >"$SB/up/upwork/scripts/post_update_hook.sh"
  git -C "$SB/up/upwork" add scripts/post_update_hook.sh; git -C "$SB/up/upwork" commit -qm "test: probe hook $probe_n"
  git -C "$SB/up/upwork" tag -a "helixconstitution-v999.$probe_n" -m t; git -C "$SB/up/upwork" push -q origin main "helixconstitution-v999.$probe_n"
  mkproj "$PH" submodules/constitution; upd "$PH" submodules/constitution
  eq "$d: update exit 0" 0 "$RC"
  check "$d: the fixture hook ran" eval '[ -s "$PH/.hook_args" ]'
  if [ -n "$exp" ]; then exp="argroot=$PH"; else exp="argroot=unset"; fi
  eq "$d" "$exp" "$(cat "$PH/.hook_args" 2>/dev/null)"
  probe_n=$((probe_n + 1))
}
probe "marker line lists project-root -> the hook gets --project-root" yes "# HELIX_HOOK_CAPABILITIES: other project-root more"
probe "no marker, but the code parses --project-root -> no argument" "" 'echo "unused --project-root) text"'
probe "marker not at the start of a line -> no argument" "" 'x=1 # HELIX_HOOK_CAPABILITIES: project-root'
probe "marker names a different capability (project-rootx) -> no argument" "" "# HELIX_HOOK_CAPABILITIES: project-rootx"

finish
