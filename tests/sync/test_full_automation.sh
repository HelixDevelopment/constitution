#!/usr/bin/env bash
# tests/sync/test_full_automation.sh -- FULL-AUTOMATION tests: the sync engine reached through the real
# automation seams, non-interactively, end to end:
#   A. scripts/sync/sync_step_lib.sh, every mode (off offline check apply ask, unknown, missing engine, not a repo)
#   B. the REAL scripts/post_update_hook.sh STEP 5c in a throwaway constitution copy whose §11.4.32 gate
#      scripts are recording stubs (TEST DOUBLES, gate-logic class §11.4.289: they prove only that the hook
#      reaches STEP 5c, never that those gates work); the sync engine itself is REAL
#   C. the REAL scripts/setup.sh of a fake constitution checked out as a REAL submodule of a fixture consumer
#      project, with --sync-upstreams=off|check|apply|bogus and CONSTITUTION_SYNC_UPSTREAMS; that fake
#      constitution's post_update_hook.sh is a recording stub (test double), the engine and setup.sh are real.
# Real git against real bare repositories in a sandbox; no network, no push to a real remote; $HOME untouched.
T_NAME=sync-full-automation
. "$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)/scripts/sync/fixture_lib.sh"
sx_sandbox
echo "== $T_NAME (sandbox $SB)"
export CONSTITUTION_JEV_HOOK=off
unset CONSTITUTION_DIR CLAUDE_PROJECT_DIR PROJECT_ROOT CONST_DIR CONSTITUTION_SYNC_UPSTREAMS CONSTITUTION_SYNC_CHECK 2>/dev/null || true
LIB="$SX_REPO/scripts/sync/sync_step_lib.sh"
# shellcheck source=../../scripts/sync/sync_step_lib.sh
. "$LIB"
export SYNC_STEP_EXTRA_ARGS="--out $SB/out/step"

# ── A. sync_step_lib modes (st runs sync_step in THIS shell so its variables are visible)
st() { sync_step "$@" >"$SB/st.out" 2>&1; ST_RC=$?; o="$(cat "$SB/st.out")"; }
sx_std_tree
st off "$W" "$SX_ENGINE"
eq "off: verdict OFF" OFF "$SYNC_STEP_VERDICT"
has "off: prints the command" "sync_all_upstreams.sh --check" "$o"
sx_commit "$U_ROOT" "root moves"
: >"$SB/git_calls.log"
PATH="$SB/shim:$PATH" st offline "$W" "$SX_ENGINE"
eq "offline: CURRENT (nothing fetched yet)" CURRENT "$SYNC_STEP_VERDICT"
eq "offline: no fetch" "0" "$(grep -c $'\x1ffetch\x1f' "$SB/git_calls.log")"
st check "$W" "$SX_ENGINE"
eq "check: UPDATES-AVAILABLE" UPDATES-AVAILABLE "$SYNC_STEP_VERDICT"
eq "check: rc 3" 3 "$SYNC_STEP_RC"
st offline "$W" "$SX_ENGINE"
eq "offline after a fetch: UPDATES-AVAILABLE" UPDATES-AVAILABLE "$SYNC_STEP_VERDICT"
st apply "$W" "$SX_ENGINE"
eq "apply: CURRENT verdict (exit 0)" CURRENT "$SYNC_STEP_VERDICT"
eq "apply: step returns 0" 0 "$ST_RC"
eq "apply: root fast-forwarded" "$(sx_remote_head "$SB/remotes/HelixDevelopment/root.git")" "$(sx_head "$W")"
o="$(setsid -w bash -c '. "$1"; sync_step ask "$2" "$3"; echo "V=$SYNC_STEP_VERDICT"' _ "$LIB" "$W" "$SX_ENGINE" </dev/null 2>&1)"
has "ask without a terminal: SKIP, never run unasked" "V=SKIP" "$o"
st weird "$W" "$SX_ENGINE"
eq "unknown mode: SKIP" SKIP "$SYNC_STEP_VERDICT"
st check "$W" "$SB/nope.sh"
eq "missing engine: SKIP" SKIP "$SYNC_STEP_VERDICT"
st check "$SB/seed" "$SX_ENGINE"
eq "not a work tree: SKIP" SKIP "$SYNC_STEP_VERDICT"
echo dirty >>"$W/README"; sx_commit "$U_ROOT" "root moves again"
st apply "$W" "$SX_ENGINE"
eq "apply on a dirty tree: ATTENTION, step still returns 0" "ATTENTION 0" "$SYNC_STEP_VERDICT $ST_RC"
git -C "$W" checkout -q -- README

# ── B. the real post_update_hook.sh, STEP 5c
C="$SB/hookconst"; mkdir -p "$C/scripts/gates" "$C/scripts/sync"
cp "$SX_REPO/scripts/post_update_hook.sh" "$C/scripts/"
ED="$(dirname "$SX_ENGINE")"   # the engine under test (a mutated copy under the mutation harness)
cp "$ED/sync_all_upstreams.py" "$ED/sync_all_upstreams.sh" "$LIB" "$C/scripts/sync/"
echo '# c' >"$C/Constitution.md"
for g in $(grep -o 'scripts/gates/cm_[a-z0-9_]*\.sh' "$SX_REPO/scripts/post_update_hook.sh" | sort -u); do
  printf '#!/usr/bin/env bash\nexit 0\n' >"$C/$g"; chmod +x "$C/$g"
done
git -C "$C" init -q && git -C "$C" add -A && git -C "$C" commit -q -m a && git -C "$C" commit -q --allow-empty -m b
hook() { (cd "$W" && CONST_DIR="$C" PROJECT_ROOT="$W" "$@" bash "$C/scripts/post_update_hook.sh" 2>&1); }
before_hook="$(sx_head "$W")"
o="$(hook env)"; rc=$?
has "hook: STEP 5c reached" "STEP 5c: Upstream sync check" "$o"
has "hook: default offline check ran the engine" "[sync-upstreams] offline: UPDATES-AVAILABLE" "$o"
has "hook: verdict reported, informational" "upstream sync check: UPDATES-AVAILABLE" "$o"
eq "hook: offline check changed nothing" "$before_hook" "$(sx_head "$W")"
o="$(hook env CONSTITUTION_SYNC_CHECK=off)"
has "hook: off" "upstream sync check: off" "$o"
o="$(hook env CONSTITUTION_SYNC_CHECK=bogus)"
has "hook: unknown mode is a warning" "is not offline|fetch|off" "$o"
before="$(sx_head "$W")"
o="$(hook env CONSTITUTION_SYNC_CHECK=fetch)"
has "hook: fetch mode runs --check" "[sync-upstreams] check:" "$o"
eq "hook: fetch mode never integrates" "$before" "$(sx_head "$W")"
mv "$C/scripts/sync" "$C/scripts/sync.off"
o="$(hook env)"
has "hook: constitution without scripts/sync is a SKIP" "upstream sync check: SKIP" "$o"
mv "$C/scripts/sync.off" "$C/scripts/sync"

# ── C. the real setup.sh through a fake constitution submodule of a consumer project
FC="$SB/fakeconst_src"; git init -q "$FC"
for f in Constitution.md CLAUDE.md AGENTS.md scripts/setup.sh scripts/lib/constitution_layout.sh scripts/lib/hook_install.sh \
         scripts/lib/safe_rm.sh scripts/lib/protected_paths.list scripts/hooks/post-merge \
         scripts/hooks/constitution-submodule-post-checkout scripts/hooks/guard-evidence-store-write.sh \
         scripts/gates/cm_canonical_root_clarity.sh scripts/sync/sync_step_lib.sh; do
  [ -e "$SX_REPO/$f" ] && { mkdir -p "$(dirname "$FC/$f")"; cp -a "$SX_REPO/$f" "$FC/$f"; }
done
cp "$ED/sync_all_upstreams.py" "$ED/sync_all_upstreams.sh" "$FC/scripts/sync/"
printf '#!/usr/bin/env bash\n# TEST DOUBLE (gate-logic class, §11.4.289): records that setup.sh called it.\necho called >>"%s/pu_called"\nexit 0\n' "$SB" >"$FC/scripts/post_update_hook.sh"
chmod +x "$FC/scripts/post_update_hook.sh"
git -C "$FC" add -A && git -C "$FC" commit -q -m "fake constitution"
git init -q --bare "$SB/remotes/HelixDevelopment/HelixConstitution.git"
git -C "$FC" push -q "$SB/remotes/HelixDevelopment/HelixConstitution.git" main
U_P="$(sx_bare HelixDevelopment consumer)"
sx_add_sub "$U_P" "file://$SB/remotes/HelixDevelopment/HelixConstitution.git" constitution
P="$SB/work/consumer"; sx_clone "$U_P" "$P"
# setup.sh refuses a GLOBAL core.hooksPath (the sandbox's default config sets one): give it a config without it
printf '[init]\n\tdefaultBranch = main\n[protocol "file"]\n\tallow = always\n' >"$SB/gitconfig_setup"
setup() { (cd "$P" && env GIT_CONFIG_GLOBAL="$SB/gitconfig_setup" "$@" bash "$P/constitution/scripts/setup.sh" 2>&1); }
o="$(setup SYNC_STEP_EXTRA_ARGS="--out $SB/out/s1")"; rc=$?; [ "$rc" = 0 ] || printf "%s\n" "$o" | tail -20
eq "setup default: exit 0" 0 "$rc"
has "setup default: sync off, hint printed" "[sync-upstreams] off" "$o"
sx_commit "$U_P" "consumer upstream moves"
o="$(setup SYNC_STEP_EXTRA_ARGS="--out $SB/out/s2" CONSTITUTION_SYNC_UPSTREAMS=check)"; rc=$?
has "setup env check: UPDATES-AVAILABLE reported" "[sync-upstreams] check: UPDATES-AVAILABLE" "$o"
eq "setup env check: setup still exits 0" 0 "$rc"
before="$(sx_head "$P")"
o="$(cd "$P" && GIT_CONFIG_GLOBAL="$SB/gitconfig_setup" SYNC_STEP_EXTRA_ARGS="--out $SB/out/s3" bash "$P/constitution/scripts/setup.sh" --sync-upstreams=apply 2>&1)"; rc=$?
eq "setup --sync-upstreams=apply: exit 0" 0 "$rc"
has "setup apply: engine ran" "[sync-upstreams] apply: CURRENT" "$o"
eq "setup apply: consumer fast-forwarded to its upstream main" "$(sx_remote_head "$SB/remotes/HelixDevelopment/consumer.git")" "$(sx_head "$P")"
o="$(cd "$P" && GIT_CONFIG_GLOBAL="$SB/gitconfig_setup" bash "$P/constitution/scripts/setup.sh" --sync-upstreams=bogus 2>&1)"; rc=$?
eq "setup --sync-upstreams=bogus: exit 2" 2 "$rc"
o="$(setup CONSTITUTION_SYNC_UPSTREAMS=bogus)"; rc=$?
eq "setup bad env value: exit 2" 2 "$rc"
o="$(cd "$P" && GIT_CONFIG_GLOBAL="$SB/gitconfig_setup" bash "$P/constitution/scripts/setup.sh" --check-only --sync-upstreams=check 2>&1)"
hasnt "setup --check-only never runs the sync" "[sync-upstreams]" "$o"

finish
