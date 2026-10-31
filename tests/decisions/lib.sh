#!/usr/bin/env bash
# tests/decisions/lib.sh — shared helpers for the decisions-wizard tests.
# Every test runs in its own `mktemp -d` sandbox; nothing touches $HOME or the real repo.
# Deletes go through safe_rm_rf (§11.4.287). No network, no real LLM.
# unit-class tests import the engine from the repo; never write __pycache__ into the repo tree. `python3 -I`
# ignores this variable, so every import site also sets sys.dont_write_bytecode = True before importing.
export PYTHONDONTWRITEBYTECODE=1
DEC_TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEC_REPO="$(cd "$DEC_TESTS_DIR/../.." && pwd)"
DEC_CLI="${DECISIONS_CLI:-$DEC_REPO/scripts/decisions/constitution_decisions.sh}"
# shellcheck source=../../scripts/lib/safe_rm.sh
. "$DEC_REPO/scripts/lib/safe_rm.sh"
PASS=0; FAIL=0; FAILED_NAMES=()
ok()   { PASS=$((PASS+1)); printf '  PASS %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); FAILED_NAMES+=("$1"); printf '  FAIL %s\n' "$1"; }
check(){ local name="$1"; shift; if "$@"; then ok "$name"; else bad "$name"; fi; }
expect_rc() { local name="$1" want="$2"; shift 2; local got; "$@" >"$SB/last.out" 2>"$SB/last.err"; got=$?
  if [ "$got" = "$want" ]; then ok "$name (rc=$got)"; else bad "$name (want rc=$want got rc=$got)"; sed 's/^/      | /' "$SB/last.err" | head -8; fi; }
new_sandbox() {
  SB="$(mktemp -d "${TMPDIR:-/tmp}/dec_test.XXXXXX")" || exit 1
  export CONSTITUTION_DECISIONS_USER_FILE="$SB/userconf/decisions.yml"
  export JEV_HOME="$SB/jevhome" XDG_CONFIG_HOME="$SB/xdg"
  unset JEV_BOOTSTRAP_MODE JEV_BOOTSTRAP_AGENTS JEV_BOOTSTRAP_NON_INTERACTIVE JEV_BOOTSTRAP_CONSENT \
        JEV_BOOTSTRAP_ALLOW_CLONE JEV_BOOTSTRAP_INSTALL_TOOLS JEV_BOOTSTRAP_DOWNLOAD_PROFILE CONSTITUTION_DECISIONS_NON_INTERACTIVE
  export CONSTITUTION_JEV_HOOK=off
}
new_project() { # $1 = name; creates a real git project with CLAUDE.md + AGENTS.md and a submodules/constitution dir
  local p="$SB/$1"; mkdir -p "$p/submodules/constitution"
  git -C "$p" init -q -b main 2>/dev/null || git -C "$p" init -q
  printf '# Project\n\nUser text above.\n' >"$p/CLAUDE.md"
  printf '# Agents\n\nKeep me.\n' >"$p/AGENTS.md"
  printf '%s' "$p"
}
cleanup_sandbox() { [ -n "${SB:-}" ] && [ -d "$SB" ] && safe_rm_rf "${SB:?}"; }
finish() { printf '%s: pass=%d fail=%d\n' "${1:-suite}" "$PASS" "$FAIL"; [ "$FAIL" -eq 0 ]; }
sha() { sha256sum "$1" | cut -d' ' -f1; }
