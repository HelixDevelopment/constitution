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
# verdict-affecting ambient overrides are guarded (11.4.201(6)-(8)): honoured only under HELIX_TEST_MODE=1 (+ temp path for paths)
_ge_lib="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]:-$0}")" && pwd)/../lib/gate_env_override.sh"
# shellcheck source=/dev/null
if [ -r "$_ge_lib" ]; then . "$_ge_lib"; else cm_gate_env_set() { printf -v "$1" '%s' "$3"; [ -z "${!2:-}" ] || echo "gate_env_override: ignoring $2 (guard lib missing: fail closed)" >&2; }; fi
cm_gate_env_set HOOK JEV_HOOK_FILE "$HERE/../post_update_hook.sh" path --test-root "$HERE/fixtures"
REAL_BOOT="$HERE/../jev/bootstrap.sh"
if [ -f "$REAL_BOOT" ]; then DEFAULT_STUB="$REAL_BOOT"; else DEFAULT_STUB="$HERE/fixtures/jev/bin/bootstrap.sh"; fi
cm_gate_env_set STUB JEV_BOOTSTRAP_STUB "$DEFAULT_STUB" path --test-root "$HERE/fixtures"
cm_gate_env_set DEPS JEV_FIXTURE_DEPS "$HERE/fixtures/jev/helix-deps.yaml" path --test-root "$HERE/fixtures"

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
# HERMETIC (round 4, review R3-2): the child starts from an EMPTY environment (env -i), so no key variable, no JEV_* / LLMCTL_*
# / CMA_* / CLAUDE_* setting and no tool location of the caller can reach it; PATH is the fixture stubs, a guard dir and the
# system directories only (never the caller's PATH, so a real llmctl / claude-providers in ~/.local/bin is never found);
# JEV_LLMCTL_BIN / JEV_TOOLKIT_BIN name absent files (the tools are absent whatever /usr/bin holds) and JEV_HOSTED_PROBE=0.
# The guard dir answers curl, llmctl, claude-providers and the agent CLIs with a recording refusal: any call is a FAIL
# (a gate that reaches a network or a real tool is not evidence of anything, §11.4.289(C)).
TMO="${JEV_GATE_TIMEOUT:-120}"
SBX=$(mktemp -d); trap 'rm -rf "$SBX"' EXIT
mkdir -p "$SBX/root"; cp "$DEPS" "$SBX/root/helix-deps.yaml" 2>/dev/null || err "deps: fixture helix-deps.yaml not readable: $DEPS"
STUBBIN="$HERE/fixtures/jev/bin"
GUARDBIN="$SBX/guardbin"; GUARDLOG="$SBX/guard.log"; mkdir -p "$GUARDBIN"; : > "$GUARDLOG"
for _g in curl wget llmctl claude-providers claude kimi opencode pi gemini qwen codex; do
  printf '#!/bin/sh
printf "%%s %%s\n" "%s" "$*" >> "%s"
exit 127
' "$_g" "$GUARDLOG" > "$GUARDBIN/$_g"; chmod +x "$GUARDBIN/$_g"
done
HERMETIC_PATH="$STUBBIN:$GUARDBIN:/usr/local/bin:/usr/bin:/bin"
# Pins are read STRUCTURALLY (helix_deps_field.py: parsed YAML; duplicate keys / ambiguous names / no PyYAML are
# refusals). Line patterns were fooled by bare `-`, quoted keys, `name :` and duplicate keys. A reader failure or an
# unlisted tool is CANNOT DETERMINE (rc 2), never a pass and never an empty pin.
# shellcheck disable=SC1091
. "$HERE/../deps_manifest/override_guard.sh"
FIELDPY="$(cm_hdeps_override HELIX_DEPS_FIELD_PY "$HERE/../deps_manifest/helix_deps_field.py")"
dep_field() { # dep_field <tool> <field> -> DF_OUT, or exit 2 (BLIND)
  command -v python3 >/dev/null 2>&1 || { echo "CM-JEV-BOOTSTRAP-IDEMPOTENT CANNOT DETERMINE: python3 missing; the structural manifest reader cannot run (rc 2)" >&2; exit 2; }
  DF_OUT=$(python3 -I "$FIELDPY" "$DEPS" "$1" "$2"); local frc=$?
  if [ "$frc" -ne 0 ] || [ -z "$DF_OUT" ]; then
    echo "CM-JEV-BOOTSTRAP-IDEMPOTENT CANNOT DETERMINE: structural reader failed for '$2' of '$1' in $DEPS (rc=$frc; 9 = tool not listed, empty = field absent); never a pass (rc 2)" >&2; exit 2
  fi
}
KNOWN_REFS=""
for _t in llmctl claude_toolkit; do dep_field "$_t" ref; KNOWN_REFS="$KNOWN_REFS$DF_OUT "; done
timed_out=0
run_boot() { # run_boot <home> <gitlog> [bootstrap args...]
  local home="$1" glog="$2"; shift 2
  case "$home" in "$SBX"/*) ;; *) echo "CM-JEV-BOOTSTRAP-IDEMPOTENT CANNOT DETERMINE: refusing to run bootstrap outside the sandbox ($home)" >&2; exit 2;; esac
  mkdir -p "$home"
  # jev-path-ok: the fixture sandbox lays its dirs out explicitly (the point of the fixture)
  env -i HOME="$home" JEV_FAKE_HOME="$home" USER="${USER:-gate}" LOGNAME="${LOGNAME:-gate}" LC_ALL=C TERM=dumb TMPDIR="$SBX" \
      JEV_HOSTED_PROBE=0 JEV_LLMCTL_BIN="$SBX/absent/llmctl" JEV_TOOLKIT_BIN="$SBX/absent/claude-providers" \
      JEV_STATE_DIR="$home/.local/state/jev" JEV_CONFIG_DIR="$home/.config/jev" \
      JEV_EVIDENCE_DIR="$home/.jev" JEV_BOOTSTRAP_HOME="$home/.local/share/helix" \
      CMA_PROVIDERS_DIR="$home/.local/share/cma/providers" \
      JEV_CONSTITUTION_ROOT="$SBX/root" JEV_TEST=1 JEV_NOW_EPOCH=1760000000 \
      JEV_BOOTSTRAP_NESTED=1 JEV_BOOTSTRAP_ALLOW_CLONE=1 JEV_SUBMODULES_ABSENT=1 JEV_FIXTURE_DEPS="$DEPS" \
      GIT_SSH_COMMAND=/bin/false GIT_STUB_LOG="$glog" GIT_STUB_KNOWN_REFS="$KNOWN_REFS" \
      PATH="$HERMETIC_PATH" \
      timeout --kill-after=5 "$TMO" bash "$STUB" "$@" >"$home.out" 2>&1
  local rc=$?
  if [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then timed_out=1; fi
  return "$rc"
}
digest_dir() { # state digest of the sandbox host, excluding the volatile pending stamp
  find "$1" -type f ! -name 'bootstrap.pending' -exec sha256sum {} + 2>/dev/null \
    | sed "s|$1||" | sort | sha256sum | cut -d' ' -f1
}

hermetic_check() { # every bootstrap run above: no guarded tool / network command was attempted
  if [ -s "$GUARDLOG" ]; then err "hermetic: a bootstrap run called a guarded tool (network or real tool): $(cut -d' ' -f1 "$GUARDLOG" | sort -u | paste -sd, -)"; fi
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
# jev-path-ok: asserting the documented default location inside the fixture HOME
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
  dep_field "$tool" ssh_url; want_url="$DF_OUT"
  dep_field "$tool" ref; want_ref="$DF_OUT"
  grep -Fq -- "$want_url" "$GITLOG" && grep -E -q "^git (-C [^ ]+ )?clone( --quiet)? .*$(printf '%s' "$want_url" | sed 's/[.[\*^$]/\\&/g')( |$)" "$GITLOG" \
    || err "clone-fallback: no managed clone of $want_url recorded for $tool (submodule-absent path)"
  grep -E -q "^git (-C [^ ]+ )?checkout( --quiet)? $want_ref\$" "$GITLOG" \
    || err "clone-fallback: $tool not checked out at pinned ref $want_ref - unpinned install is non-compliance (§11.4.286)"
  # jev-path-ok: asserting the documented default clone location inside the fixture HOME
  [ "$(cat "$H4/.local/share/helix/$tool/.stub_head" 2>/dev/null)" = "$want_ref" ] \
    || err "clone-fallback: $tool clone directory does not hold the pinned ref $want_ref"
done
# The real script records the outcome in its provenance file; if present, it must say the pin was reached.
# jev-path-ok: asserting the documented default provenance location inside the fixture HOME
PROV="$H4/.local/state/jev/tools.provenance.json"
if [ -f "$PROV" ]; then
  [ "$(grep -o 'pinned-checked-out' "$PROV" | wc -l)" -ge 2 ] \
    || err "clone-fallback: provenance record does not show both tools pinned-checked-out ($PROV)"
fi
ok "clause 4: submodule-absent clone fallback pinned to helix-deps.yaml refs"

clause_start
# Clause 5 (round 4, review R3-2) - the runs were hermetic: no guarded tool was called. CONTROL NEEDLE: the guard records
# a call it receives (a blind guard would make this clause a quiet zero, §11.4.273).
if PATH="$GUARDBIN" curl --version >/dev/null 2>&1; then err "hermetic: the guard curl did not refuse"; fi
if [ "$(grep -c '^curl --version$' "$GUARDLOG")" != 1 ]; then echo "CM-JEV-BOOTSTRAP-IDEMPOTENT CANNOT DETERMINE: the hermetic guard is blind (control call not recorded; rc 2)" >&2; exit 2; fi
sed -i '/^curl --version$/d' "$GUARDLOG"
hermetic_check
ok "clause 5: every bootstrap run was hermetic (no network / real-tool call; guard control needle seen)"

if [ "$fail" -ne 0 ]; then
  echo "CM-JEV-BOOTSTRAP-IDEMPOTENT: RED" >&2
  exit 1
fi
echo "CM-JEV-BOOTSTRAP-IDEMPOTENT: GREEN"
exit 0
