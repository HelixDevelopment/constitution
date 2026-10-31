#!/usr/bin/env bash
# lib_assert.sh — shared assertion helpers for tests/jev (source, don't exec).
# Conventions: plain counters, assert_skip for absent deps, finish exits nonzero
# on any failure.

PASS=0; FAIL=0; SKIPS=0

ok()   { PASS=$((PASS+1)); printf 'ok %d - %s\n' "$PASS" "$1"; }
fail() { FAIL=$((FAIL+1)); printf 'FAIL - %s\n' "$1"; }

assert_eq() { # assert_eq <expected> <actual> <msg>
  if [ "$1" = "$2" ]; then ok "$3"; else fail "$3 (expected [$1] got [$2])"; fi
}
assert_ne() { # assert_ne <not-expected> <actual> <msg>
  if [ "$1" != "$2" ]; then ok "$3"; else fail "$3 (both are [$1])"; fi
}
assert_file_exists() {
  if [ -f "$1" ]; then ok "$2"; else fail "$2 (missing file: $1)"; fi
}
assert_file_absent() {
  if [ ! -e "$1" ]; then ok "$2"; else fail "$2 (unexpected file: $1)"; fi
}
assert_contains() { # assert_contains <file> <fixed-string> <msg>
  if [ -f "$1" ] && grep -qF -- "$2" "$1"; then ok "$3"; else fail "$3 (no [$2] in $1)"; fi
}
assert_rc() { # assert_rc <expected-rc> <actual-rc> <msg>
  assert_eq "$1" "$2" "$3"
}
assert_not_contains() { # assert_not_contains <file> <fixed-string> <msg>  (file must exist)
  if [ ! -f "$1" ]; then fail "$3 (file missing: $1)"; return; fi
  if grep -qF -- "$2" "$1"; then fail "$3 (unexpected [$2] in $1)"; else ok "$3"; fi
}
assert_nonzero() { # assert_nonzero <rc> <msg> — a negative control: the thing MUST fail
  if [ "$1" -ne 0 ] 2>/dev/null; then ok "$2"; else fail "$2 (rc was [$1], expected nonzero)"; fi
}
# jqn <file> <jq-path-expr> — numeric-normalising read: jq >= 1.7 keeps the
# literal spelling of a number (0.9500), so a byte/string compare against 0.95
# fails for a reason that is not a defect. Arithmetic +0 forces canonical form.
jqn() {
  jq -r "($2) | if type==\"number\" then .+0 else . end" "$1"
}
assert_skip() { # assert_skip <reason>
  SKIPS=$((SKIPS+1)); printf 'skip - %s\n' "$1"
}

finish() {
  printf '# %s: pass=%d fail=%d skip=%d\n' "$(basename "$0")" "$PASS" "$FAIL" "$SKIPS"
  [ "$FAIL" -eq 0 ]
}

_JEV_FIXTURE_DIRS=()
_jev_cleanup_fixtures() { local d; for d in "${_JEV_FIXTURE_DIRS[@]}"; do [ -n "$d" ] && [ -d "$d" ] && rm -rf -- "$d"; done; }

# make_fixture_env <name> — sandboxed HOME, stubs on PATH, deterministic clock.
# Sets: T (tmp root), HOME, PATH, STUB_LOG, JEV_* dirs, JEV_NOW_EPOCH.
make_fixture_env() {
  T="$(mktemp -d)"
  # nit (r4/r5): every fixture dir this process created is removed on exit - not only the last one (a second call used to
  # replace the trap and leak the first dir). Only exact paths recorded here are removed. A test that installs its own EXIT
  # trap calls _jev_cleanup_fixtures from it.
  _JEV_FIXTURE_DIRS+=("$T")
  trap _jev_cleanup_fixtures EXIT
  export HOME="$T/home"
  case "$HOME" in /home/*/.cache/*|/tmp/*|/var/tmp/*|"${TMPDIR:-/tmp}"/*) ;; *) echo "FATAL: refusing to run outside a temp HOME ($HOME)" >&2; exit 2 ;; esac
  mkdir -p "$HOME" "$T/log"
  export STUB_LOG="$T/log"
  export PATH="$FIXTURES/bin:$PATH"
  export JEV_STATE_DIR="$HOME/.local/state/jev"
  export JEV_EVIDENCE_DIR="$T/.jev"
  export JEV_CONFIG_DIR="$HOME/.config/jev"
  export JEV_BOOTSTRAP_HOME="$HOME/.local/share/helix"
  export JEV_NOW_EPOCH=1700000000
  export CMA_PROVIDERS_DIR="$HOME/.local/share/claude-multi-account/providers"
  export GIT_SSH_COMMAND=/bin/false   # no network, ever
  unset LLMCTL_STATUS_JSON LLMCTL_CAPACITY_JSON FIXTURE_ENDPOINTS LLMCTL_DIR CLAUDE_TOOLKIT_DIR LLMCTL_ENDPOINT LLMCTL_DECIDE_PORT LLMCTL_CACERT \
        LLMCTL_API_KEY TYPESAFE_API_KEY OPENROUTER_API_KEY JEV_API_KEY JEV_API_KEYS_FILE CMA_KEYS_FILE CMA_JEV_PINS_FILE JEV_BEFORE JEV_AFTER \
        JEV_TEST JEV_REQUIRE_VALIDATED_CMD JEV_DECISION_PROFILES JEV_PINS_FILE JEV_BASE_URL JEV_DETECTION_FILE JEV_SKIP_VALIDATION JEV_DETECTION_MAX_AGE JEV_HOME JEV_STATUS_NO_VALIDATE TYPESAFE_BASE_URL CLAUDE_CONFIG_DIR   # CLAUDE_CONFIG_DIR: the operator's real alias dir must never be read (jev_mcp_files), HOME is already the sandbox
  export JEV_HOSTED_PROBE=0   # hermetic default: no hosted probe (tests that exercise probing set it to 1 and stub curl)
  mkdir -p "$CMA_PROVIDERS_DIR"
  mkdir -p "$JEV_STATE_DIR" "$JEV_EVIDENCE_DIR" "$JEV_CONFIG_DIR"
}

# jev_test_enforce_env [rv-rc] — test-only seam for the shared jev_effective_mode (review r3 m-r3-2): JEV_TEST=1 makes the
# JEV_DECISION_PROFILES / JEV_REQUIRE_VALIDATED_CMD overrides count. The stub validator exits rv-rc (default 0) and logs its
# argv to $STUB_LOG/rv.log, so a test can see HOW require-validated was called (and that STRICT was set).
jev_test_enforce_env() {
  local rc="${1:-0}"
  cat > "$T/rv_stub" <<STUB
#!/usr/bin/env bash
printf 'strict=%s args=%s\n' "\${LLMCTL_VALIDATE_STRICT:-}" "\$*" >> "$STUB_LOG/rv.log"
# imitate the pinned llmctl CLI (lib/validate.sh require_validated): EXACTLY ONE argument, no option-shaped one (usage error rc 2)
[ "\$#" -eq 1 ] && [[ "\$1" != -* ]] || { echo "ERROR: usage: llmctl require-validated <profile>" >&2; exit 2; }
exit $rc
STUB
  chmod +x "$T/rv_stub"
  export JEV_TEST=1 JEV_DECISION_PROFILES=decide JEV_REQUIRE_VALIDATED_CMD="$T/rv_stub" JEV_BASE_URL=https://127.0.0.1:8095
}

# seed_local_detection <file> [profile] — a minimal detection record with ONE local-llmctl endpoint (id llmctl-<profile>),
# the shape jev_effective_mode needs before it will even consider enforce (hosted-only / no record => shadow).
seed_local_detection() {
  jq -n --arg id "llmctl-${2:-decide}" '{version:1,generated_at:1700000000,endpoints:[{id:$id,source:"local-llmctl",reachable:true,url:"http://127.0.0.1:9"}],reason:null}' > "$1"
}

# make_fixture_constitution_root — a fake constitution root with fixture
# helix-deps.yaml; argument "with-submodules" also seeds submodules/{llmctl,
# claude_toolkit} from fixtures/tools.
make_fixture_constitution_root() {
  local root="$T/constitution"
  mkdir -p "$root"
  cp "$FIXTURES/helix-deps.yaml" "$root/helix-deps.yaml"
  if [ "${1:-}" = "with-submodules" ]; then
    mkdir -p "$root/submodules"
    cp -r "$FIXTURES/tools/llmctl" "$root/submodules/llmctl"
    cp -r "$FIXTURES/tools/claude_toolkit" "$root/submodules/claude_toolkit"
  fi
  export JEV_CONSTITUTION_ROOT="$root"
}

# make_hook_host <changed-relpath>... — a throwaway constitution git repo C (real
# scripts/post_update_hook.sh + the recording bootstrap stub) and a consuming
# project dir P. Two commits: baseline, then the listed paths created/appended,
# so `git diff HEAD~1..HEAD` (the hook's baseline when ORIG_HEAD is absent) is
# exactly the listed paths. Sets HOST_C, HOST_P. No network, no real home.
make_hook_host() {
  local base f
  base="$(mktemp -d)"; HOST_C="$base/const"; HOST_P="$base/proj"
  mkdir -p "$HOST_C/scripts/jev" "$HOST_P"
  cp "$REPO/scripts/post_update_hook.sh" "$HOST_C/scripts/post_update_hook.sh"
  cp "$HERE/fixtures-shared/jev_scripts/bootstrap.sh" "$HOST_C/scripts/jev/bootstrap.sh"
  printf 'baseline\n' > "$HOST_C/README.md"; printf '# c\n' > "$HOST_C/Constitution.md"
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  git -C "$HOST_C" init -q && git -C "$HOST_C" add -A && git -C "$HOST_C" commit -q -m base
  for f in "$@"; do
    mkdir -p "$HOST_C/$(dirname "$f")"; printf '# change\n' >> "$HOST_C/$f"
  done
  git -C "$HOST_C" add -A && git -C "$HOST_C" commit -q -m change
}
# run_hook_host [VAR=val ...] — runs the real hook; output in $HOST_P/hook.out, rc in HOOK_RC.
run_hook_host() {
  (cd "$HOST_P" && env CONST_DIR="$HOST_C" PROJECT_ROOT="$HOST_P" HOME="$HOST_P/home" \
     BOOTSTRAP_STUB_LOG="$HOST_P/bootstrap.log" JEV_STATE_DIR="$HOST_P/.jev-state" "$@" \
     bash "$HOST_C/scripts/post_update_hook.sh" </dev/null >"$HOST_P/hook.out" 2>&1)
  HOOK_RC=$?
}

# leaks_count <needle> <root> — number of files under <root> containing <needle> (the keys file, when $KEYS is set,
# is excluded). leak_scan_selftest <root> proves the scan can SEE: it plants a control needle under <root>, requires
# exactly that file to be found and a fabricated needle to be absent, then removes it; a blind scan (missing or
# unreadable root, grep unable to read) FAILS instead of reporting a quiet zero (§11.4.273).
leaks_count() {
  grep -rlF -- "$1" "$2" 2>/dev/null | { if [ -n "${KEYS:-}" ]; then grep -vF -- "$KEYS"; else cat; fi; } | grep -vE '/(keys[0-9a-z]*\.sh)$' | wc -l | tr -d ' '
}
leak_scan_selftest() {
  local root="$1" ctl needle
  [ -d "$root" ] && [ -r "$root" ] || { echo "leak_scan_selftest: root not readable: $root" >&2; return 1; }
  needle="leakctl-$$-$RANDOM-$(date +%s)"
  ctl="$root/.leakscan-control.$$"
  printf '%s\n' "$needle" > "$ctl" || return 1
  if [ "$(leaks_count "$needle" "$root")" != "1" ]; then rm -f "$ctl"; echo "leak_scan_selftest: scan is blind to a planted needle" >&2; return 1; fi
  rm -f "$ctl"
  [ "$(leaks_count "$needle" "$root")" = "0" ] || { echo "leak_scan_selftest: needle still found after removal" >&2; return 1; }
  return 0
}
