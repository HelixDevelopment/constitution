#!/usr/bin/env bash
# tests/install/lib.sh — shared helpers for the installer test suite (sourced, never executed).
#
# ── Purpose ───────────────────────────────────────────────────────────────
# Sandbox creation (explicit `mktemp -d`, cleaned with safe_rm_rf restricted to the sandbox),
# git isolation (GIT_CONFIG_GLOBAL points into the sandbox, system config ignored), assertion
# counters, and make_upstream: a REAL local bare clone of this repository acting as the upstream,
# plus one test commit that carries the CURRENT working-tree installer/updater scripts and
# clearly labelled TEST FIXTURE prompt files, tagged helixconstitution-v999.0 (newest tag).
#
# ── Safety ────────────────────────────────────────────────────────────────
#   * $HOME is never reassigned and never written; the real repository is only read
#     (git clone --bare is a read of the source repository).
#   * Every recursive delete goes through safe_rm_rf with SAFE_RM_ALLOWED_ROOTS set to the sandbox.
#   * Jev is disabled (CONSTITUTION_JEV_HOOK=off) for everything spawned here.
set -uo pipefail
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALLER="$REPO/scripts/install_constitution.sh"
UPDATER="$REPO/scripts/update_constitution.sh"
# shellcheck source=../../scripts/lib/safe_rm.sh
. "$REPO/scripts/lib/safe_rm.sh"
export CONSTITUTION_JEV_HOOK=off
export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=installer-test GIT_AUTHOR_EMAIL=t@example.invalid
export GIT_COMMITTER_NAME=installer-test GIT_COMMITTER_EMAIL=t@example.invalid
export GIT_TERMINAL_PROMPT=0
unset ANTHROPIC_API_KEY 2>/dev/null || true

T_PASS=0; T_FAIL=0; T_NAME="${T_NAME:-install-tests}"
ok()   { T_PASS=$((T_PASS+1)); printf '  ok   %s\n' "$*"; }
nok()  { T_FAIL=$((T_FAIL+1)); printf '  FAIL %s\n' "$*"; }
check() { # description command... — passes when the command exits 0
  local d="$1"; shift
  if "$@"; then ok "$d"; else nok "$d"; fi
}
eq() { # description expected actual
  if [ "$2" = "$3" ]; then ok "$1"; else nok "$1 (expected [$2] got [$3])"; fi
}
finish() {
  printf '%s: PASS %d FAIL %d\n' "$T_NAME" "$T_PASS" "$T_FAIL"
  [ "$T_FAIL" -eq 0 ]
}

new_sandbox() {
  SB="$(mktemp -d "${TMPDIR:-/tmp}/helix-install-test.XXXXXX")" || { echo "mktemp failed" >&2; exit 2; }
  export SAFE_RM_ALLOWED_ROOTS="$SB"
  export GIT_CONFIG_GLOBAL="$SB/gitconfig"
  printf '[init]\n\tdefaultBranch = main\n[advice]\n\tdetachedHead = false\n' >"$GIT_CONFIG_GLOBAL"
  trap 'cleanup_sandbox' EXIT
  # Never let a test run the installer against the repository the suite was started from: every suite
  # works from inside the sandbox, and git may not discover a repository above it.
  export GIT_CEILING_DIRECTORIES="$(dirname "$SB")"
  cd "$SB" || exit 2
}
cleanup_sandbox() {
  [ -n "${SB:-}" ] && [ -d "$SB" ] || return 0
  chmod -R u+w "${SB:?}" 2>/dev/null || true
  safe_rm_rf "${SB:?}"
}

# make_upstream DIR — DIR/upstream.git (bare, real clone of this repo) + DIR/upwork (work clone).
make_upstream() {
  local d="${1:?}"
  if [ -n "${HELIX_TEST_UPSTREAM_SEED:-}" ] && [ -d "$HELIX_TEST_UPSTREAM_SEED/upstream.git" ]; then
    git clone -q --bare "$HELIX_TEST_UPSTREAM_SEED/upstream.git" "$d/upstream.git" || return 1
  else
    git clone -q --bare --no-recurse-submodules "$REPO" "$d/upstream.git" || return 1
    git -C "$d/upstream.git" remote remove origin 2>/dev/null || true
  fi
  # serve partial clones like GitHub/GitLab do (the installer clones blobless)
  git -C "$d/upstream.git" config uploadpack.allowFilter true || return 1
  git clone -q "$d/upstream.git" "$d/upwork" || return 1
  if [ -z "${HELIX_TEST_UPSTREAM_SEED:-}" ] || [ ! -d "$HELIX_TEST_UPSTREAM_SEED/upstream.git" ]; then
    mkdir -p "$d/upwork/scripts" "$d/upwork/docs/prompts/setup/followups"
    cp "$INSTALLER" "$d/upwork/scripts/install_constitution.sh"
    cp "$UPDATER" "$d/upwork/scripts/update_constitution.sh"
    # no chmod here: cp keeps the shipped mode, and the shipped scripts MUST be 100755 (CM-INSTALLER-SCRIPT-MODES);
    # a chmod would hide a 644 regression that dirties every consumer submodule after the post-update hook
    cat >"$d/upwork/docs/prompts/setup/latest.md" <<'EOF'
# TEST FIXTURE setup prompt (written by tests/install/lib.sh; not the real prompt)

## PROMPT

```text
TEST FIXTURE PROMPT: wire this project to submodules/constitution.
```
EOF
    cat >"$d/upwork/docs/prompts/setup/followups/01_fixture_check.md" <<'EOF'
---
title: TEST FIXTURE follow-up one
requires_previous_success: true
---
TEST FIXTURE FOLLOWUP ONE
EOF
    cat >"$d/upwork/docs/prompts/setup/followups/02_fixture_second.md" <<'EOF'
---
title: TEST FIXTURE follow-up two
requires_previous_success: true
---
TEST FIXTURE FOLLOWUP TWO
EOF
    git -C "$d/upwork" add -f scripts/install_constitution.sh scripts/update_constitution.sh docs/prompts/setup || return 1
    git -C "$d/upwork" commit -q -m "test: installer under test + labelled prompt fixtures" || return 1
    git -C "$d/upwork" tag -a helixconstitution-v999.0 -m "test tag" || return 1
    git -C "$d/upwork" push -q origin main helixconstitution-v999.0 || return 1
  fi
}

# advance_upstream DIR TAG — one more commit on main, annotated tag TAG, pushed to the bare upstream.
advance_upstream() {
  local d="${1:?}" tag="${2:?}"
  git -C "$d/upwork" pull -q --ff-only origin main || return 1
  printf 'advance %s\n' "$tag" >>"$d/upwork/docs/prompts/setup/advance_marker.txt"
  git -C "$d/upwork" add -f docs/prompts/setup/advance_marker.txt
  git -C "$d/upwork" commit -q -m "test: advance $tag" || return 1
  git -C "$d/upwork" tag -a "$tag" -m "$tag" || return 1
  git -C "$d/upwork" push -q origin main "$tag" || return 1
}

# new_project DIR — a consumer git repo with one commit.
new_project() {
  local p="${1:?}"
  mkdir -p "$p" && git -C "$p" init -q && printf '# demo project\n' >"$p/README.md" \
    && git -C "$p" add README.md && git -C "$p" commit -q -m init
}

# tree_fingerprint DIR — sha256 over every path + content + mode (including .git), sorted.
tree_fingerprint() { # DIR [worktree] — "worktree" skips .git and .constitution-install-backup at top level
  python3 -I - "${1:?}" "${2:-all}" <<'PY'
import hashlib, os, stat, sys
root = sys.argv[1]; mode = sys.argv[2]; h = hashlib.sha256()
for dp, dns, fns in os.walk(root):
    if mode == "worktree" and dp == root:
        dns[:] = [d for d in dns if d not in (".git", ".constitution-install-backup")]
    dns.sort()
    for n in sorted(dns + fns):
        p = os.path.join(dp, n); rel = os.path.relpath(p, root)
        st = os.lstat(p)
        h.update(rel.encode() + b"\0" + oct(st.st_mode).encode() + b"\0")
        if stat.S_ISREG(st.st_mode):
            with open(p, "rb") as f: h.update(hashlib.sha256(f.read()).digest())
        elif stat.S_ISLNK(st.st_mode):
            h.update(os.readlink(p).encode())
print(h.hexdigest())
PY
}

# project_state DIR — logical state: worktree fingerprint + HEAD + index + porcelain status.
project_state() {
  local p="${1:?}"
  { tree_fingerprint "$p" worktree; git -C "$p" rev-parse HEAD 2>/dev/null; git -C "$p" ls-files -s 2>/dev/null;
    git -C "$p" --no-optional-locks status --porcelain 2>/dev/null; } | sha256sum | cut -c1-64
}
tagsha() { git -C "${1:?}/upstream.git" rev-parse "${2:?}^{commit}"; }
gitlink() { git -C "${1:?}" ls-files -s -- "${2:-submodules/constitution}" | awk '$1=="160000"{print $2}'; }
report_field() { python3 -I -c 'import json,sys; d=json.load(open(sys.argv[1])); v=d
for k in sys.argv[2].split("."): v=v[k]
print(v if not isinstance(v,bool) else str(v).lower())' "${1:?}" "${2:?}"; }

# run_installer PROJECT ARGS... — real installer, non-interactive, setup + Jev off; output in $OUT, rc in $RC.
run_installer() {
  local p="${1:?}"; shift
  OUT="$(cd "$p" && bash "$INSTALLER" "$@" 2>&1)"; RC=$?
}
