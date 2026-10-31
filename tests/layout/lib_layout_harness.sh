# shellcheck shell=bash
# tests/layout/lib_layout_harness.sh — shared sandbox harness for the
# constitution-layout tests (both layouts: <project>/constitution and
# <project>/submodules/constitution).
#
# Sourced by tests/layout/test_*.sh. It never touches $HOME, the real repo or
# any real git config: every fixture is built under ONE `mktemp -d` sandbox,
# git runs with GIT_CONFIG_GLOBAL=/dev/null + GIT_CONFIG_NOSYSTEM=1, and the
# sandbox is removed with safe_rm_rf (§11.4.287) on EXIT.
#
# Inputs:
#   LAYOUT_SRC_ROOT — the constitution tree whose scripts are under test
#                     (default: this repo). The paired-mutation suite points it
#                     at a mutated copy so every test can be re-run against a
#                     tree with one fix reverted.
# Test doubles (§11.4.289): the fake constitution's scripts/post_update_hook.sh
#   is a RECORDING STUB (gate-logic/unit class). It proves only that the script
#   under test called the hook with the right paths; it is never evidence that
#   the real post-update hook works. LAYOUT_STUB_SLEEP=<s> makes the stub
#   sleep first (concurrency tests); LAYOUT_STUB_EXIT=<n> makes it exit n
#   (failure-path tests, e.g. setup.sh I1).

set -u

LAYOUT_HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LAYOUT_REAL_ROOT="$(cd "$LAYOUT_HARNESS_DIR/../.." && pwd)"
LAYOUT_SRC_ROOT="${LAYOUT_SRC_ROOT:-$LAYOUT_REAL_ROOT}"

# safe_rm_rf always comes from the REAL tree (never from a mutated copy).
# shellcheck source=/dev/null
. "$LAYOUT_REAL_ROOT/scripts/lib/safe_rm.sh"

export CONSTITUTION_JEV_HOOK=off
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
export GIT_AUTHOR_NAME=layout-test GIT_AUTHOR_EMAIL=layout-test@example.invalid
export GIT_COMMITTER_NAME=layout-test GIT_COMMITTER_EMAIL=layout-test@example.invalid
export GIT_TERMINAL_PROMPT=0
unset CONSTITUTION_DIR CLAUDE_PROJECT_DIR GESW_REGISTRY CANONICAL_ROOT_DIR \
      CONSUMER_ROOT PROJECT_ROOT CONST_DIR GIT_DIR GIT_WORK_TREE 2>/dev/null || true

PASS=0
FAIL=0
lt_ok()  { PASS=$((PASS + 1)); printf 'PASS: %s\n' "$*"; }
lt_bad() { FAIL=$((FAIL + 1)); printf 'FAIL: %s\n' "$*"; }
lt_check() { # lt_check "desc" cmd... -> PASS iff cmd exits 0
    local d="$1"; shift
    if "$@"; then lt_ok "$d"; else lt_bad "$d"; fi
}

LT_SB="$(mktemp -d "${TMPDIR:-/tmp}/layout_test.XXXXXX")" || { echo "FATAL: mktemp" >&2; exit 2; }
# LT_BG_PIDS: pids of background helpers (sleep holders) this suite started and
# recorded as `LT_BG_PIDS="${LT_BG_PIDS:-} $!"`; killed on EXIT even when the
# suite aborts between start and its own kill. Only pids we recorded.
LT_BG_PIDS=""
lt_cleanup() { local _p; for _p in ${LT_BG_PIDS:-}; do case "$_p" in ''|*[!0-9]*|0|1) ;; *) kill "$_p" 2>/dev/null ;; esac; done
    [ -n "${LT_SB:-}" ] && safe_rm_rf "${LT_SB:?}" >/dev/null 2>&1; return 0; }
trap lt_cleanup EXIT

# git with file:// submodules allowed (local bare upstreams only).
lt_git() { git -c protocol.file.allow=always -c init.defaultBranch=main -c advice.detachedHead=false "$@"; }

# lt_copy REL DEST_ROOT — copy one path of LAYOUT_SRC_ROOT into DEST_ROOT.
lt_copy() {
    mkdir -p "$(dirname "$2/$1")"
    cp -a "$LAYOUT_SRC_ROOT/$1" "$2/$1"
}

# lt_make_const_upstream NAME -> prints the bare-repo URL (file://...).
# A fake constitution: the REAL governance files + the REAL scripts under test,
# plus the recording-stub post_update_hook.sh.
lt_make_const_upstream() {
    local name="$1" w="$LT_SB/src_$1" bare="$LT_SB/$1.git"
    mkdir -p "$w"
    lt_git init -q "$w"
    local f
    for f in Constitution.md CLAUDE.md AGENTS.md \
             scripts/setup.sh scripts/lib/constitution_layout.sh scripts/lib/hook_install.sh \
             scripts/lib/safe_rm.sh scripts/lib/protected_paths.list \
             scripts/hooks/post-merge scripts/hooks/constitution-submodule-post-checkout \
             scripts/hooks/guard-evidence-store-write.sh \
             scripts/gates/cm_canonical_root_clarity.sh; do
        [ -e "$LAYOUT_SRC_ROOT/$f" ] && lt_copy "$f" "$w"
    done
    # A non-hook file in scripts/hooks (a guard + a test + a directory) — the
    # real tree has these; none may ever land in a consumer's .git/hooks.
    # The hook SOURCES are deliberately non-executable in the fake: setup.sh
    # must make every installed hook executable itself (round-2 I-5, N3).
    chmod a-x "$w/scripts/hooks/post-merge" "$w/scripts/hooks/constitution-submodule-post-checkout" 2>/dev/null || true
    mkdir -p "$w/scripts/hooks/__pycache__"
    printf 'cache\n' > "$w/scripts/hooks/__pycache__/x.pyc"
    printf '#!/bin/sh\nexit 0\n' > "$w/scripts/hooks/test_fake_suite.sh"
    cat > "$w/scripts/post_update_hook.sh" <<'STUB'
#!/usr/bin/env bash
# TEST DOUBLE (gate-logic class, §11.4.289): records how it was called.
[ -n "${LAYOUT_STUB_SLEEP:-}" ] && sleep "$LAYOUT_STUB_SLEEP"
printf 'CALLED PROJECT_ROOT=%s CONST_DIR=%s PWD=%s OLD=%s NEW=%s\n' "${PROJECT_ROOT:-<unset>}" "${CONST_DIR:-<unset>}" "$PWD" "${CONSTITUTION_UPDATE_OLD_REF:-<unset>}" "${CONSTITUTION_UPDATE_NEW_REF:-<unset>}" >> "${LAYOUT_RECORD:?LAYOUT_RECORD unset}"
exit "${LAYOUT_STUB_EXIT:-0}"
STUB
    chmod +x "$w/scripts/post_update_hook.sh"
    lt_git -C "$w" add -A >/dev/null
    lt_git -C "$w" commit -q -m "fake constitution v1"
    lt_git clone -q --bare "$w" "$bare"
    printf 'file://%s\n' "$bare"
}

# lt_bump_const_upstream NAME — add a commit to the fake constitution upstream.
lt_bump_const_upstream() {
    local w="$LT_SB/src_$1" bare="$LT_SB/$1.git"
    printf 'bump %s\n' "$(date +%s%N)" >> "$w/CHANGES.txt"
    lt_git -C "$w" add -A >/dev/null
    lt_git -C "$w" commit -q -m "fake constitution bump"
    lt_git -C "$w" push -q "$bare" HEAD:main 2>/dev/null || lt_git -C "$w" push -q "$bare" HEAD:master
}

# lt_make_project DIR URL REL — a consumer repo with the constitution at REL.
lt_make_project() {
    local dir="$1" url="$2" rel="$3"
    mkdir -p "$dir"
    lt_git init -q "$dir"
    printf '# consumer\n' > "$dir/README.md"
    lt_git -C "$dir" add README.md
    lt_git -C "$dir" commit -q -m init
    lt_git -C "$dir" submodule add -q "$url" "$rel" >/dev/null 2>&1 || return 1
    lt_git -C "$dir" commit -q -m "add constitution at $rel"
}

lt_summary() {
    printf -- '----\n%s: PASS=%d FAIL=%d\n' "${LT_SUITE:-layout}" "$PASS" "$FAIL"
    [ "$FAIL" -eq 0 ]
}
