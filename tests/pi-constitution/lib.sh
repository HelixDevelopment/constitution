#!/usr/bin/env bash
# shellcheck disable=SC2034,SC1091  # T_NAME, OUT and RC are shared with lib.sh; safe_rm.sh path is dynamic
# tests/pi-constitution/lib.sh — shared helpers for the pi-constitution plugin test suites (sourced, never executed).
#
# All tests are FULLY DETERMINISTIC: they exercise the pi-constitution audit logic by running the
# exact shell commands the plugin runs (test -d, git rev-parse HEAD, cat, grep) against sandboxed
# Constitution repos. No dependence on pi's LLM to invoke a tool — that would be non-deterministic.
# pi is only used in best-effort E2E/CLI suites where the tool is explicitly requested.
#
# Every suite sandboxes itself under mktemp -d; nothing touches $HOME or this repo.
#
# ── Safety ────────────────────────────────────────────────────────────────
#   * $HOME is never reassigned and never written; the real repository is only read.
#   * Every recursive delete goes through safe_rm_rf with SAFE_RM_ALLOWED_ROOTS set to the sandbox.
#   * Jev disabled (CONSTITUTION_JEV_HOOK=off); no LLM calls anywhere except best-effort pi e2e.
#   * Git-env-hermetic: clear the caller's repository-locating git variables first.
set -uo pipefail
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PLAYER="${PLAYER:-/mnt/DATA1TB/projects/helix/player}"
PI="${PI:-pi}"
# shellcheck source=../../scripts/lib/safe_rm.sh
. "$REPO/scripts/lib/safe_rm.sh"
export CONSTITUTION_JEV_HOOK=off
export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=pi-constitution-test GIT_AUTHOR_EMAIL=t@example.invalid
export GIT_COMMITTER_NAME=pi-constitution-test GIT_COMMITTER_EMAIL=t@example.invalid
export GIT_TERMINAL_PROMPT=0
export CONSTITUTION_EXT_NO_TTY=1
unset ANTHROPIC_API_KEY CONSTITUTION_DIR CONSTITUTION_EXT_TEST_MODE CONSTITUTION_EXT_TEST_KILL_AT 2>/dev/null || true

T_PASS=0; T_FAIL=0; T_NAME="${T_NAME:-pi-constitution-tests}"
ok()   { T_PASS=$((T_PASS+1)); printf '  ok   %s\n' "$*"; }
nok()  { T_FAIL=$((T_FAIL+1)); printf '  FAIL %s\n' "$*"; }
check() { local d="$1"; shift; if "$@"; then ok "$d"; else nok "$d"; fi; }
eq() { if [ "$2" = "$3" ]; then ok "$1"; else nok "$1 (expected [$2] got [$3])"; fi; }
has() { case "$3" in *"$2"*) ok "$1";; *) nok "$1 (missing [$2] in: $(printf '%s' "$3" | head -c 600))";; esac; }
hasnt() { case "$3" in *"$2"*) nok "$1 (unexpected [$2])";; *) ok "$1";; esac; }
finish() { printf '%s: PASS %d FAIL %d\n' "$T_NAME" "$T_PASS" "$T_FAIL"; [ "$T_FAIL" -eq 0 ]; }

new_sandbox() {
  SB="$(mktemp -d "${TMPDIR:-/tmp}/pi-constitution-test.XXXXXX")" || { echo "mktemp failed" >&2; exit 2; }
  SB="$(realpath -e "$SB")" || { echo "realpath failed" >&2; exit 2; }
  export SAFE_RM_ALLOWED_ROOTS="$SB"
  export GIT_CONFIG_GLOBAL="$SB/gitconfig"
  printf '[init]\n\tdefaultBranch = main\n[advice]\n\tdetachedHead = false\n[protocol "file"]\n\tallow = always\n' >"$GIT_CONFIG_GLOBAL"
  trap 'cleanup_sandbox' EXIT
}
cleanup_sandbox() {
  [ -n "${SB:-}" ] && [ -d "$SB" ] || return 0
  chmod -R u+w "${SB:?}" 2>/dev/null || true
  safe_rm_rf "${SB:?}"
}

# make_constitution_stub DIR — creates a real git repo at DIR with Constitution.md, CLAUDE.md, AGENTS.md
# each containing all four mandate sections (§11.4.26, §11.4.28, §11.4.31, §11.4.32), committed on main.
make_constitution_stub() {
  local d="${1:?}"
  mkdir -p "$d"
  cat >"$d/Constitution.md" <<'EOF'
# TEST FIXTURE Constitution

### §11.4.26 — Fetch + pull ALL Constitution remotes before any edit
### §11.4.28 — Commit inside the submodule first (on task/ branches, never direct to main)
### §11.4.31 — Push submodule branch to ALL remotes, merge to main via --no-ff, push main to ALL remotes
### §11.4.32 — Bump consuming project's submodule pointer in same change-window
EOF
  cat >"$d/CLAUDE.md" <<'EOF'
# CLAUDE

### §11.4.26 — fixture
### §11.4.28 — fixture
### §11.4.31 — fixture
### §11.4.32 — fixture
EOF
  cat >"$d/AGENTS.md" <<'EOF'
# AGENTS

### §11.4.26 — fixture
### §11.4.28 — fixture
### §11.4.31 — fixture
### §11.4.32 — fixture
EOF
  git -C "$d" init -q -b main \
    && git -C "$d" add -A \
    && git -C "$d" commit -q -m "fixture constitution root" \
    || return 1
  git -C "$d" rev-parse HEAD
}

# make_project DIR — a consumer git repo with one commit (the pi-constitution consuming project root).
make_project() {
  local p="${1:?}"
  mkdir -p "$p" && git -C "$p" init -q -b main && printf '# demo\n' >"$p/README.md" \
    && git -C "$p" add README.md && git -C "$p" commit -q -m init
}

# add_constitution_dir PROJECT REL_PATH — creates a Constitution git repo at PROJECT/REL_PATH
# (no git submodule registration needed; the plugin checks test -d + git rev-parse HEAD).
add_constitution_dir() {
  local proj="${1:?}" rel="${2:?}"
  local abs="$proj/$rel"
  mkdir -p "$abs"
  make_constitution_stub "$abs" >/dev/null || return 1
}

# run_audit DIR — runs the exact audit checks the pi-constitution plugin performs against
# DIR/submodules/constitution. Output is a multi-line report; AUDIT_RC is 0 iff healthy.
# Sets: AUDIT_OUT (full report), AUDIT_RC (0=healthy, 1=unhealthy), AUDIT_HEAD (submodule HEAD or empty).
run_audit() {
  local dir="${1:?}"
  local cpath="$dir/submodules/constitution"
  local out="" errors="" head=""
  # 1. Submodule presence
  if [ -d "$cpath" ]; then
    out+="- Submodule: present"$'\n'
    head="$(git -C "$cpath" rev-parse HEAD 2>/dev/null || true)"
    [ -n "$head" ] && out+="- Submodule HEAD: ${head:0:12}"$'\n'
  else
    out+="- Submodule: MISSING"$'\n'
    errors+="constitution_submodule_missing: Constitution submodule not found at $cpath"$'\n'
  fi
  # 2. Governance files + mandate sections
  local gf ms
  for gf in Constitution.md CLAUDE.md AGENTS.md; do
    local fpath="$cpath/$gf"
    if [ -f "$fpath" ]; then
      out+="- Governance $gf: present"$'\n'
      for ms in "§11.4.26" "§11.4.28" "§11.4.31" "§11.4.32"; do
        if grep -qF -- "$ms" "$fpath"; then
          out+="- Mandate $ms: present ($gf)"$'\n'
        else
          errors+="constitution_mandate_section_missing: Mandate section $ms not found in $gf"$'\n'
        fi
      done
    else
      out+="- Governance $gf: MISSING"$'\n'
      errors+="constitution_governance_file_missing: Governance file missing: $fpath"$'\n'
    fi
  done
  if [ -n "$errors" ]; then
    out+=$'\n'"### Errors ($(printf '%s\n' "$errors" | grep -c .))"$'\n'
    while IFS= read -r line; do
      [ -n "$line" ] && out+="- [$line]"$'\n'
    done <<<"$errors"
    AUDIT_RC=1
  else
    out+=$'\n'"Constitution governance is healthy."$'\n'
    AUDIT_RC=0
  fi
  AUDIT_OUT="$out"
  AUDIT_HEAD="$head"
}

# assert_healthy_audit OUTPUT — asserts the audit output reports a healthy constitution.
assert_healthy_audit() {
  local out="${1:?}"
  has "submodule present" "present" "$out"
  has "Constitution.md" "Constitution.md" "$out"
  has "CLAUDE.md" "CLAUDE.md" "$out"
  has "AGENTS.md" "AGENTS.md" "$out"
  has "mandate §11.4.26" "§11.4.26" "$out"
  has "mandate §11.4.28" "§11.4.28" "$out"
  has "mandate §11.4.31" "§11.4.31" "$out"
  has "mandate §11.4.32" "§11.4.32" "$out"
  has "healthy" "healthy" "$out"
}

# assert_unhealthy_audit OUTPUT CODE — asserts the audit output reports the given triage code.
assert_unhealthy_audit() {
  local out="${1:?}" code="${2:?}"
  has "triage code" "$code" "$out"
}

# pi_doctor [cwd] — best-effort: runs `pi --print --no-session "Run the pi-constitution-doctor tool..."`
# from the given directory (default $SB). Returns cleaned output in $PI_OUT and exit code in $PI_RC.
# NOTE: pi's LLM may or may not invoke the tool; this is best-effort only.
pi_doctor() {
  local cwd="${1:-$SB}"
  local raw rc
  raw="$(cd "$cwd" && timeout 30 "$PI" --print --no-session "Run the pi-constitution-doctor tool and report the Constitution governance audit results." </dev/null 2>&1)"
  rc=$?
  PI_RC=$rc
  PI_OUT="$raw"
}

# clean_pi_output RAW — strips pi notification noise, ANSI escapes, OSC sequences, preamble.
clean_pi_output() {
  local raw="$1"
  printf '%s\n' "$raw" | sed -e 's/\x1b\[[0-9;]*[a-zA-Z]//g' \
                              -e 's/\x1b\].*\\x07//g' \
                              -e '/^\[pi-subagents\]/d' \
                              -e '/^The pi-constitution-doctor tool has /d' \
                              -e '/^$/d'
}
