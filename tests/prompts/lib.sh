#!/usr/bin/env bash
# tests/prompts/lib.sh — shared helpers for the setup-prompt test suites.
#
# Sourced (never executed) by tests/prompts/test_*.sh. Provides:
#   REPO        absolute path of the constitution repository under test
#   ROTATE      absolute path of scripts/prompts/rotate_setup_prompt.sh
#   GATE        absolute path of scripts/gates/cm_setup_prompt_latest_present.sh
#   mk_sandbox  -> creates a mktemp -d sandbox, registers it for cleanup, prints it
#   mk_setup_dir <root> -> creates <root>/docs/prompts/setup with 01_old.md,
#                  02_middle.md and a latest.md carrying a valid PROMPT block
#   prompt_doc <marker> -> prints a minimal valid prompt document whose PROMPT
#                  block contains <marker>
#   ok / no <label> / check <label> <cmd...> -> counters; summary prints
#                  "RESULT: <name> pass=N fail=M skip=K" and returns non-zero on any fail
#   skip <label>  -> an UNCONFIRMED / not-verifiable item: counted as skip, NEVER as pass
#
# Every sandbox lives under `mktemp -d` and is removed with safe_rm_rf
# (§11.4.287); nothing outside the sandbox is written. $HOME is never
# reassigned. No network, no LLM calls.
set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ROTATE="$REPO/scripts/prompts/rotate_setup_prompt.sh"
GATE="$REPO/scripts/gates/cm_setup_prompt_latest_present.sh"
# shellcheck source=../../scripts/lib/safe_rm.sh
. "$REPO/scripts/lib/safe_rm.sh"

PASS=0
FAIL=0
SKIP=0
_SANDBOXES=()

_cleanup_sandboxes() {
  local s
  for s in "${_SANDBOXES[@]:-}"; do
    [ -n "$s" ] && [ -d "$s" ] && safe_rm_rf "${s:?}" >/dev/null 2>&1
  done
  return 0
}
trap _cleanup_sandboxes EXIT

mk_sandbox() {
  local s
  s="$(mktemp -d)" || { echo "mktemp failed" >&2; return 1; }
  _SANDBOXES+=("$s")
  printf '%s\n' "$s"
}

prompt_doc() {
  local marker="${1:-default}"
  printf '# Test prompt %s\n\nIntro.\n\n## PROMPT\n\n```\nYou are a test agent. Marker: %s\nDo nothing.\n```\n\n## After\n\ntext\n' \
    "$marker" "$marker"
}

mk_setup_dir() {
  local root="${1:?root}" d
  d="$root/docs/prompts/setup"
  mkdir -p "$d"
  prompt_doc old >"$d/01_old.md"
  prompt_doc middle >"$d/02_middle.md"
  prompt_doc current >"$d/latest.md"
  printf '%s\n' "$d"
}

ok() { PASS=$((PASS + 1)); printf 'PASS %s\n' "$1"; }
no() { FAIL=$((FAIL + 1)); printf 'FAIL %s\n' "$1"; }
skip() { SKIP=$((SKIP + 1)); printf 'SKIP UNCONFIRMED: %s\n' "$1"; }

# check <label> <command...> : PASS when the command exits 0
check() {
  local label="$1"; shift
  if "$@"; then ok "$label"; else no "$label"; fi
}

# expect_rc <label> <expected-rc> <command...>
expect_rc() {
  local label="$1" want="$2" rc; shift 2
  "$@" >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq "$want" ]; then ok "$label (rc=$rc)"; else no "$label (rc=$rc want=$want)"; fi
}

# tree_digest <dir> : deterministic digest of names + contents (dotfiles included)
tree_digest() {
  ( cd "${1:?dir}" && find . -type f -print0 | LC_ALL=C sort -z | xargs -0 sha256sum ) | sha256sum | cut -d' ' -f1
}

summary() {
  printf 'RESULT: %s pass=%d fail=%d skip=%d\n' "${1:-suite}" "$PASS" "$FAIL" "$SKIP"
  [ "$FAIL" -eq 0 ]
}
