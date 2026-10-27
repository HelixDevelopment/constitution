#!/usr/bin/env bash
# CM-JEV-BOOTSTRAP-IDEMPOTENT (§11.4.281(E))
# Asserts:
#   1. post_update_hook.sh contains the bootstrap invocation marker block
#   2. two consecutive --non-interactive bootstrap runs in a fixture host produce
#      identical resulting-state digests (idempotency contract)
#   3. --defer writes the pending stamp and exits 0
#   4. submodule-absent bootstrap falls back to a managed clone pinned to the
#      ref recorded in helix-deps.yaml (stub-git assertion)
#
# Env overrides:
#   JEV_HOOK_FILE        hook to inspect (default: <repo>/scripts/post_update_hook.sh)
#   JEV_BOOTSTRAP_STUB   bootstrap binary for fixture runs
#                        (default: the real scripts/jev/bootstrap.sh when present, else
#                         scripts/gates/fixtures/jev/bin/bootstrap.sh with a NOTE)
#   JEV_FIXTURE_DEPS     pinned-ref source for clause 4 (default: fixture helix-deps.yaml)
set -uo pipefail

# Re-entrancy guard: real scripts/jev/bootstrap.sh runs the CM-JEV gates in its report
# stage, and this gate runs bootstrap. Without a guard that is an unbounded fork storm
# (measured 2026-10-23). Every child run below is exported JEV_BOOTSTRAP_NESTED=1; a
# gate that STARTS with it set was launched from inside a bootstrap run: rc 2, never a pass.
if [ -n "${JEV_BOOTSTRAP_NESTED:-}" ]; then
  echo "CM-JEV-BOOTSTRAP-IDEMPOTENT CANNOT DETERMINE (nested): started inside a bootstrap run (JEV_BOOTSTRAP_NESTED set); refusing to recurse (rc 2, never a pass)" >&2
  exit 2
fi
HERE=$(cd "$(dirname "$0")" && pwd)
HOOK="${JEV_HOOK_FILE:-$HERE/../post_update_hook.sh}"
REAL_BOOT="$HERE/../jev/bootstrap.sh"
if [ -f "$REAL_BOOT" ]; then DEFAULT_STUB="$REAL_BOOT"; else DEFAULT_STUB="$HERE/fixtures/jev/bin/bootstrap.sh"; fi
STUB="${JEV_BOOTSTRAP_STUB:-$DEFAULT_STUB}"
DEPS="${JEV_FIXTURE_DEPS:-$HERE/fixtures/jev/helix-deps.yaml}"

fail=0
case "$STUB" in
  "$HERE"/fixtures/jev/bin/bootstrap.sh)
    printf 'CM-JEV-BOOTSTRAP-IDEMPOTENT NOTE: clauses 2-4 exercise the FIXTURE stub, not scripts/jev/bootstrap.sh (a stub-only GREEN is not evidence about the real script)\n' >&2
    if [ "${JEV_REQUIRE_REAL_BOOTSTRAP:-0}" = "1" ]; then
      echo "CM-JEV-BOOTSTRAP-IDEMPOTENT CANNOT DETERMINE: JEV_REQUIRE_REAL_BOOTSTRAP=1 but only the fixture stub is configured (rc 2)" >&2; exit 2
    fi ;;
esac
err() { printf 'CM-JEV-BOOTSTRAP-IDEMPOTENT FAIL: %s\n' "$*" >&2; fail=1; }
_f0=0; clause_start() { _f0=$fail; }
ok()  { [ "$fail" = "$_f0" ] && printf 'CM-JEV-BOOTSTRAP-IDEMPOTENT ok: %s\n' "$*" >&2; return 0; }

clause_start
# Clause 1 — invocation marker block present in the post-update hook.
if [ -f "$HOOK" ]; then
  grep -q '# >>> helix-jev-bootstrap >>>' "$HOOK" \
    || err "hook: invocation block begin marker missing in $HOOK"
  grep -q '# <<< helix-jev-bootstrap <<<' "$HOOK" \
    || err "hook: invocation block end marker missing in $HOOK"
  block=$(awk '/# >>> helix-jev-bootstrap >>>/{f=1} f{print} /# <<< helix-jev-bootstrap <<</{f=0}' "$HOOK")
  printf '%s' "$block" | grep -q 'scripts/jev/bootstrap.sh' \
    || err "hook: marker block does not invoke scripts/jev/bootstrap.sh"
  printf '%s' "$block" | grep -q -- '--non-interactive' \
    || err "hook: marker block lacks the --non-interactive (non-TTY) path"
  printf '%s' "$block" | grep -q -- '--defer' \
    || err "hook: marker block lacks the --defer failure fallback"
  printf '%s' "$block" | grep -q 'bootstrap.disabled' \
    || err "hook: marker block lacks the .jev/bootstrap.disabled opt-out guard"
else
  err "hook: $HOOK missing"
fi
ok "clause 1: post-update hook carries the guarded bootstrap invocation block"

# Bounded, isolated runner. EVERY run (fixture stub or the real scripts/jev/bootstrap.sh):
#   - gets HOME and all state/config/clone/evidence dirs under a mktemp sandbox (the real
#     script is never run against the operator's HOME),
#   - has the fixture git stub FIRST on PATH (no network; clone/checkout of the pin emulated)
#     and GIT_SSH_COMMAND=/bin/false as a second barrier,
#   - sees a sandbox constitution root carrying only the fixture helix-deps.yaml (so the
#     real script has no submodules and must take the managed-clone fallback at the pin),
#   - runs under timeout (own process group; --kill-after) with JEV_BOOTSTRAP_NESTED=1.
# No pkill-by-pattern anywhere: timeout signals only its own child's group.
TMO="${JEV_GATE_TIMEOUT:-120}"
SBX=$(mktemp -d); trap 'rm -rf "$SBX"' EXIT
mkdir -p "$SBX/root"; cp "$DEPS" "$SBX/root/helix-deps.yaml" 2>/dev/null || err "deps: fixture helix-deps.yaml not readable: $DEPS"
STUBBIN="$HERE/fixtures/jev/bin"
KNOWN_REFS=$(awk '/^ +ref:/{print $2}' "$DEPS" | tr '\n' ' ')
timed_out=0
run_boot() { # run_boot <home> <gitlog> [bootstrap args...]
  local home="$1" glog="$2"; shift 2
  case "$home" in "$SBX"/*) ;; *) echo "CM-JEV-BOOTSTRAP-IDEMPOTENT CANNOT DETERMINE: refusing to run bootstrap outside the sandbox ($home)" >&2; exit 2;; esac
  mkdir -p "$home"
  env HOME="$home" JEV_FAKE_HOME="$home" \
      JEV_STATE_DIR="$home/.local/state/jev" JEV_CONFIG_DIR="$home/.config/jev" \
      JEV_EVIDENCE_DIR="$home/.jev" JEV_BOOTSTRAP_HOME="$home/.local/share/helix" \
      CMA_PROVIDERS_DIR="$home/.local/share/cma/providers" \
      JEV_CONSTITUTION_ROOT="$SBX/root" JEV_NOW_EPOCH=1760000000 \
      JEV_BOOTSTRAP_NESTED=1 JEV_BOOTSTRAP_ALLOW_CLONE=1 JEV_SUBMODULES_ABSENT=1 JEV_FIXTURE_DEPS="$DEPS" \
      GIT_SSH_COMMAND=/bin/false GIT_STUB_LOG="$glog" GIT_STUB_KNOWN_REFS="$KNOWN_REFS" \
      PATH="$STUBBIN:$PATH" \
      timeout --kill-after=5 "$TMO" bash "$STUB" "$@" >"$home.out" 2>&1
  local rc=$?
  if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then timed_out=1; fi
  return "$rc"
}
digest_dir() { # state digest of the sandbox host, excluding the volatile pending stamp
  find "$1" -type f ! -name 'bootstrap.pending' -exec sha256sum {} + 2>/dev/null \
    | sed "s|$1||" | sort | sha256sum | cut -d' ' -f1
}

clause_start
# Clause 2 - two-run digest identity in a fresh sandbox host (each run must also exit 0).
H1="$SBX/host1"
run_boot "$H1" "$SBX/git1.log" --non-interactive; r1=$?
d1=$(digest_dir "$H1")
run_boot "$H1" "$SBX/git1.log" --non-interactive; r2=$?
d2=$(digest_dir "$H1")
if [ "$timed_out" = "1" ]; then
  echo "CM-JEV-BOOTSTRAP-IDEMPOTENT CANNOT DETERMINE: bootstrap run timed out after ${TMO}s (rc 2, never a pass)" >&2; exit 2
fi
[ "$r1" -eq 0 ] && [ "$r2" -eq 0 ] || err "idempotency: bootstrap --non-interactive exited $r1/$r2 (must be 0/0; see $H1.out)"
[ -n "$d1" ] && [ "$d1" = "$d2" ] \
  || err "idempotency: second run digest differs ($d1 vs $d2) - second run MUST be a byte-stable no-op (§11.4.281(C))"
ok "clause 2: two-run digests identical ($d1)"

clause_start
# Clause 3 - --defer semantics.
H3="$SBX/host3"
run_boot "$H3" "$SBX/git3.log" --defer; rc=$?
[ "$rc" -eq 0 ] || err "defer: --defer exited $rc (must exit 0)"
[ -f "$H3/.local/state/jev/bootstrap.pending" ] \
  || err "defer: pending stamp not written at .local/state/jev/bootstrap.pending"
ok "clause 3: --defer writes pending stamp, exits 0"

clause_start
# Clause 4 - submodule-absent managed-clone fallback at the pinned ref, exercised through
# the (stubbed-git) real or fixture bootstrap. Accepts both fixture ("git clone URL DEST",
# "git checkout REF") and real ("git clone --quiet URL DEST", "git -C DIR checkout --quiet REF") forms.
H4="$SBX/host4"; GITLOG="$SBX/git.log"; : > "$GITLOG"
run_boot "$H4" "$GITLOG" --non-interactive
for tool in llmctl claude_toolkit; do
  want_url=$(awk -v n="$tool" '$0 ~ "name: "n {f=1} f && /ssh_url:/ {print $2; exit}' "$DEPS")
  want_ref=$(awk -v n="$tool" '$0 ~ "name: "n {f=1} f && /ref:/ {print $2; exit}' "$DEPS")
  grep -Fq -- "$want_url" "$GITLOG" && grep -E -q "^git (-C [^ ]+ )?clone( --quiet)? .*$(printf '%s' "$want_url" | sed 's/[.[\*^$]/\\&/g')( |$)" "$GITLOG" \
    || err "clone-fallback: no managed clone of $want_url recorded for $tool (submodule-absent path)"
  grep -E -q "^git (-C [^ ]+ )?checkout( --quiet)? $want_ref\$" "$GITLOG" \
    || err "clone-fallback: $tool not checked out at pinned ref $want_ref - unpinned install is non-compliance (§11.4.286)"
  [ "$(cat "$H4/.local/share/helix/$tool/.stub_head" 2>/dev/null)" = "$want_ref" ] \
    || err "clone-fallback: $tool clone directory does not hold the pinned ref $want_ref"
done
# The real script records the outcome in its provenance file; if present, it must say the pin was reached.
PROV="$H4/.local/state/jev/tools.provenance.json"
if [ -f "$PROV" ]; then
  [ "$(grep -o 'pinned-checked-out' "$PROV" | wc -l)" -ge 2 ] \
    || err "clone-fallback: provenance record does not show both tools pinned-checked-out ($PROV)"
fi
ok "clause 4: submodule-absent clone fallback pinned to helix-deps.yaml refs"

if [ "$fail" -ne 0 ]; then
  echo "CM-JEV-BOOTSTRAP-IDEMPOTENT: RED" >&2
  exit 1
fi
echo "CM-JEV-BOOTSTRAP-IDEMPOTENT: GREEN"
exit 0
