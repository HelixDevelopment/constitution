#!/usr/bin/env bash
# =============================================================================
# test_multitrack_cwd_hook_consumer_root.sh — §11.4.177 consumer-root
#   resolution for the cwd-hook (the GLOBAL/shared entry point).
# -----------------------------------------------------------------------------
# Purpose:
#   The cwd-hook is the ONE engine entry point that runs from OUTSIDE any
#   consumer checkout (the toolkit invokes it only when cwd is NOT a git repo).
#   Its consumer-project root was derived SOLELY from the engine script's own
#   file location (multitrack_config.sh:mt_repo_root steps (b)/(c)) — so a
#   globally-installed hook ALWAYS resolved to whichever checkout physically
#   holds the engine, SHADOWING every sibling consumer on the host that ships
#   its own config/multitrack/ (§11.4.177 re-coupling: one global entry point
#   hardcoded to one checkout).
#
#   Self-location is CORRECT for a repo-local invocation and MEANINGLESS for a
#   global one. This suite pins the corrected precedence for the global path:
#
#     1. MT_REPO_ROOT env pin              (explicit override — unchanged)
#     2. invocation context: nearest ancestor of $PWD with config/multitrack/
#     3. operator-owned binding file OUTSIDE any checkout (alias key, then
#        `default` key) — the minimal artifact, since with no cwd context the
#        alias->consumer mapping is host policy that NOTHING in-tree can know
#     4. nothing resolvable -> export NOTHING; the resolver behaves EXACTLY as
#        before (self-location) so no existing consumer changes behaviour
#
# Cases:
#   C1  binding names consumer B, engine lives in A          -> B   (RED->GREEN)
#   C2  no binding, neutral cwd                              -> A   (NEG CTRL)
#   C3  MT_REPO_ROOT pin wins over everything                -> B   (NEG CTRL)
#   C4  cwd inside consumer B, no binding                    -> B   (RED->GREEN)
#   C5  binding points at a NON-consumer path -> IGNORED     -> A   (§11.4.6)
#   C6  alias-specific key beats the `default` key           -> B
#   C7  stdout purity: hook mode emits EXACTLY one line            (contract)
#   C8  cwd inside consumer A (context agrees with self-loc) -> A   (NEG CTRL)
#
# Usage:   test_multitrack_cwd_hook_consumer_root.sh
# Inputs (env): none. Hermetic — every fixture lives under fresh mktemp dirs.
# Outputs: per-case PASS/FAIL lines; exit 0 iff every case passed.
# Side-effects: writes ONLY under its own temp dirs (removed on exit, §11.4.14).
#               NEVER touches $HOME, the operator PATH, or any real checkout.
# Dependencies: bash, git, findmnt, mktemp, hostname.
#
# Cross-references:
#   constitution/scripts/multitrack/multitrack_cwd_hook.sh          (unit under test)
#   constitution/scripts/multitrack/multitrack_resolve_worktree.sh  (delegate)
#   constitution/scripts/multitrack/multitrack_config.sh            (mt_repo_root)
#
# Constitution: §11.4.177 §11.4.187 §11.4.6 §11.4.115 §11.4.201(1) §11.4.224 §11.4.67
# =============================================================================
for _ge_v in GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX; do unset "$_ge_v"; done; unset _ge_v  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
set -u

SELF_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd)"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; [ -n "${2:-}" ] && printf '        %s\n' "$2"; }

command -v git      >/dev/null 2>&1 || { echo "SKIP: git absent";      exit 0; }
command -v findmnt  >/dev/null 2>&1 || { echo "SKIP: findmnt absent";  exit 0; }
findmnt -rno FSTYPE /tmp >/dev/null 2>&1 || { echo "SKIP: /tmp is not a mountpoint — the fixture needs a real mount"; exit 0; }

TMP="$(mktemp -d)" || exit 1
# The two candidate worktrees MUST sit directly under a REAL mountpoint (/tmp)
# because the resolver's guard requires findmnt(mount) to succeed.
WT_A="$(mktemp -d -p /tmp cwhroot_aaa.XXXXXX)" || exit 1
WT_B="$(mktemp -d -p /tmp cwhroot_bbb.XXXXXX)" || exit 1
cleanup() { rm -rf "$TMP" "$WT_A" "$WT_B" 2>/dev/null; }
trap cleanup EXIT INT TERM

SUB_A="$(basename "$WT_A")"
SUB_B="$(basename "$WT_B")"
git init -q "$WT_A" >/dev/null 2>&1 || exit 1
git init -q "$WT_B" >/dev/null 2>&1 || exit 1

HOST="$(hostname 2>/dev/null | cut -d. -f1)"
[ -n "$HOST" ] || HOST="$(cut -d. -f1 < /etc/hostname 2>/dev/null)"
[ -n "$HOST" ] || { echo "SKIP: cannot resolve hostname"; exit 0; }

ALIAS="cwhtestalias"

# --- build one fake consumer project: $1 root, $2 worktree_subdir ------------
mk_consumer() {
    local root="$1" subdir="$2"
    mkdir -p "$root/config/multitrack"
    cat > "$root/config/multitrack/$HOST.yaml" <<YAML
schema_version: 1
host:
  hostname: $HOST
tracks:
  - id: track-9
    role: feature
    drive_serial: FIXTURE-SERIAL
    mount: /tmp
    fs: tmpfs
aliases:
  - name: $ALIAS
    kind: native
conductor: ""
worktree_subdir: $subdir
YAML
}

CONSUMER_A="$TMP/consumer_a"
CONSUMER_B="$TMP/consumer_b"
NEUTRAL="$TMP/neutral"
NOT_A_CONSUMER="$TMP/not_a_consumer"
mk_consumer "$CONSUMER_A" "$SUB_A"
mk_consumer "$CONSUMER_B" "$SUB_B"
mkdir -p "$NEUTRAL" "$NOT_A_CONSUMER"

# The engine COPY lives inside consumer A, so self-location (mt_repo_root step
# (b): <engine>/../.. carries config/multitrack) resolves to A — reproducing the
# real defect shape, where the globally-symlinked engine physically lives inside
# ONE checkout and answers for every invocation.
ENGINE_A="$CONSUMER_A/scripts/multitrack"
mkdir -p "$ENGINE_A"
for f in multitrack_cwd_hook.sh multitrack_resolve_worktree.sh multitrack_config.sh; do
    cp "$SELF_DIR/$f" "$ENGINE_A/$f" || exit 1
done
# Sibling side-effect scripts (orchestrator / monitor / constitution-sync /
# owner-lock) are deliberately NOT copied: every one is guarded by `[ -r ... ]`
# so the hook's detached side effects become clean no-ops. The suite therefore
# exercises the REAL hook-mode invocation path with zero side effects.
HOOK="$ENGINE_A/multitrack_cwd_hook.sh"

BINDING="$TMP/consumer_roots.conf"

# Run the hook exactly as the toolkit does: `hook <alias-label>`, capturing
# stdout only. Every env knob below is a documented resolver/testability seam.
run_hook() {  # $1 cwd ; rest: extra env assignments
    local cwd="$1"; shift
    ( cd "$cwd" 2>/dev/null || exit 1
      env -u MT_REPO_ROOT \
          MT_CHECKOUT_OWNER_POLICY=off \
          MT_ALIAS_DIR="$TMP/aliasorch" \
          MT_CONSUMER_ROOTS="$BINDING" \
          "$@" \
          bash "$HOOK" "$ALIAS" 2>/dev/null )
}

expect() {  # $1 label  $2 expected-path  $3 actual
    if [ "$3" = "$2" ]; then ok "$1"; else bad "$1" "expected [$2] got [$3]"; fi
}

echo "=== §11.4.177 cwd-hook consumer-root resolution"
echo "    engine copy : $HOOK"
echo "    consumer A  : $CONSUMER_A  (worktree $WT_A)"
echo "    consumer B  : $CONSUMER_B  (worktree $WT_B)"
echo

# --- C2 first: the UNCHANGED-BEHAVIOUR baseline (negative control) -----------
rm -f "$BINDING"
expect "C2 no binding + neutral cwd -> self-located consumer A (UNCHANGED)" \
       "$WT_A" "$(run_hook "$NEUTRAL")"

# --- C1: operator binding names consumer B ----------------------------------
printf 'default = %s\n' "$CONSUMER_B" > "$BINDING"
expect "C1 operator binding names consumer B -> B" \
       "$WT_B" "$(run_hook "$NEUTRAL")"

# --- C3: explicit MT_REPO_ROOT pin outranks everything ----------------------
printf 'default = %s\n' "$CONSUMER_A" > "$BINDING"
RES_C3="$( cd "$NEUTRAL" && env MT_REPO_ROOT="$CONSUMER_B" \
             MT_CHECKOUT_OWNER_POLICY=off MT_ALIAS_DIR="$TMP/aliasorch" \
             MT_CONSUMER_ROOTS="$BINDING" bash "$HOOK" "$ALIAS" 2>/dev/null )"
expect "C3 MT_REPO_ROOT pin outranks the binding file -> B" "$WT_B" "$RES_C3"

# --- C4: invocation context (cwd inside consumer B), no binding -------------
rm -f "$BINDING"
expect "C4 cwd inside consumer B, no binding -> B (invocation context)" \
       "$WT_B" "$(run_hook "$CONSUMER_B")"

# --- C5: a binding pointing at a NON-consumer path is IGNORED (§11.4.6) -----
printf 'default = %s\n' "$NOT_A_CONSUMER" > "$BINDING"
expect "C5 binding -> non-consumer path is IGNORED, falls back to A" \
       "$WT_A" "$(run_hook "$NEUTRAL")"

# --- C6: alias-specific key beats the default key ---------------------------
{ printf 'default = %s\n' "$CONSUMER_A"; printf '%s = %s\n' "$ALIAS" "$CONSUMER_B"; } > "$BINDING"
expect "C6 alias-specific binding key beats 'default'" \
       "$WT_B" "$(run_hook "$NEUTRAL")"

# --- C7: stdout purity — hook mode emits EXACTLY one line -------------------
printf 'default = %s\n' "$CONSUMER_B" > "$BINDING"
C7_LINES="$(run_hook "$NEUTRAL" | wc -l | tr -d ' ')"
if [ "$C7_LINES" = "1" ]; then ok "C7 hook stdout is exactly one line (cd-target contract)"
else bad "C7 hook stdout is exactly one line (cd-target contract)" "got $C7_LINES lines"; fi

# --- C8: cwd inside consumer A, no binding -> A (context agrees) ------------
rm -f "$BINDING"
expect "C8 cwd inside consumer A, no binding -> A" \
       "$WT_A" "$(run_hook "$CONSUMER_A")"

echo
printf 'TOTAL=%d PASSED=%d FAILED=%d\n' "$((PASS+FAIL))" "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
