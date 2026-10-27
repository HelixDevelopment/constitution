#!/usr/bin/env bash
# skills/jev-decision-layer/register.sh — standalone per-agent installer (§11.4.280(A)).
#
# FALLBACK ONLY. The canonical installer is claude_toolkit scripts/jev-setup.sh
# (consent-gated, backup-first, per-account homes). scripts/jev/bootstrap.sh
# runs that one. This script exists for hosts where the toolkit checkout is
# unavailable, and it writes to DIFFERENT locations than jev-setup.sh (user-level
# ~/.mcp.json, ~/.kimi-code/config.toml), so do not run both against one home.
#
# Idempotently installs into a sandboxable HOME:
#   - claude:   .claude/settings.json PreToolUse entry (jq-merge) + .mcp.json jev server
#               (rendered from mcp/templates/jev-decisions.json.tmpl, the single source)
#   - kimi:     .kimi-code/config.toml [[hooks]] marker block + mcp_servers.jev
#   - opencode: plugin copy + opencode.json entries + coverage-gap note
#   - pi:       package note (documented fallback)
# plus .config/jev/env defaults and a registration stamp (§11.4.228).
# Twice-run = single registration (marker-guarded / jq-merge). An edited existing
# file is backed up ONCE as <file>.prejev.<epoch> (mode 0600), and a file that
# holds key material is never backed up at all (review r6 I6-1: no copies of secrets).
#
# Exit codes: 0 done; 2 refused/cannot determine (jq missing while an agent home
# needs a JSON edit, an invalid input value, or the MCP template cannot be
# rendered). Every rc-2 path happens BEFORE the first write: inputs are validated
# and the MCP entry is rendered first, so nothing is half-written (tested by
# comparing a checksum of the whole target tree before/after).
#
# Repair (review I-1): helixconstitution-v71 shipped a live mcp/jev-decisions.json
# whose literal ${CLAUDE_TOOLKIT_DIR} placeholders were merged verbatim into
# consumers' .mcp.json. A `jev` server entry that still holds an unexpanded
# ${...} placeholder is removed (backup first, other servers kept) and re-rendered.
#
# Env (names only; secrets are never written, only the key variable NAME):
#   JEV_HOME (target home, default $HOME), CLAUDE_TOOLKIT_DIR (default
#   <home>/.local/share/helix/claude_toolkit, via lib_decide.sh's resolver), JEV_BASE_URL (default
#   https://127.0.0.1:8095, the llmctl decide gateway), JEV_MODEL,
#   JEV_KEY_VAR (default LLMCTL_API_KEY; must be a shell variable NAME),
#   JEV_CA_FILE (optional CA path), JEV_MODE (shadow|enforce, default shadow),
#   JEV_NOW_EPOCH (clock seam, honoured ONLY with JEV_TEST=1).
# shellcheck disable=SC2016  # jq programs use $var references on purpose
set -uo pipefail

SKILL_DIR=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../../scripts/jev/lib_decide.sh
. "$SKILL_DIR/../../scripts/jev/lib_decide.sh"   # THE path resolver (review r5 I5-2, r6 I6-2): no independent derivation below
JHOME="$(jev_home)"
TOOLKIT="$(jev_toolkit_dir)"
BASE_URL="${JEV_BASE_URL:-https://127.0.0.1:8095}"
MODEL="${JEV_MODEL:-jev-latest}"
KEY_VAR="${JEV_KEY_VAR:-LLMCTL_API_KEY}"
CA_FILE="${JEV_CA_FILE:-}"
MODE="${JEV_MODE:-shadow}"
NOW="$(date +%s)"; [ "${JEV_TEST:-}" != "1" ] || NOW="${JEV_NOW_EPOCH:-$NOW}"   # clock seam is test-only (review r6 n6-1)
CFGDIR="$(jev_config_dir)"

log() { printf '[jev-register] %s\n' "$*"; }

if { [ -d "$JHOME/.claude" ] || [ -d "$JHOME/.config/opencode" ]; } && ! command -v jq >/dev/null 2>&1; then
  echo "jev-register: jq is required to edit JSON agent config; cannot determine (rc 2); nothing written" >&2
  exit 2
fi

# ── validate EVERYTHING before the first write (rc 2 = nothing changed) ─────
refuse() { echo "jev-register: $* (rc 2); nothing written" >&2; exit 2; }
# Values are never echoed: only the variable NAME is reported.
check_value() { # check_value <ENV-NAME> <value>
  case "$2" in *'${'*) refuse "$1 contains a placeholder-shaped \${...} sequence" ;; esac
  case "$2" in *[[:cntrl:]]*) refuse "$1 contains a control character or newline" ;; esac
}
check_value JEV_HOME "$JHOME"
check_value CLAUDE_TOOLKIT_DIR "$TOOLKIT"
check_value JEV_BASE_URL "$BASE_URL"
check_value JEV_MODEL "$MODEL"
check_value JEV_CA_FILE "$CA_FILE"
check_value JEV_KEY_VAR "$KEY_VAR"
check_value JEV_MODE "$MODE"
# whitelists (review r6 m6-5): these values are written unquoted into an env file that shells source and into a TOML command
# line, so the character class is closed, not merely "no ${ and no control characters"
jev_check_path "$JHOME" || refuse "JEV_HOME has characters outside [A-Za-z0-9._/~+@%:=,-]"
jev_check_path "$TOOLKIT" || refuse "CLAUDE_TOOLKIT_DIR has characters outside [A-Za-z0-9._/~+@%:=,-]"
jev_check_url "$BASE_URL" || refuse "JEV_BASE_URL is not a plain http(s) URL (scheme, host[:port], optional simple path)"
jev_check_model "$MODEL" || refuse "JEV_MODEL has characters outside [A-Za-z0-9._:/@+-]"
[ -z "$CA_FILE" ] || jev_check_path "$CA_FILE" || refuse "JEV_CA_FILE has characters outside [A-Za-z0-9._/~+@%:=,-]"
[[ "$KEY_VAR" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] \
  || refuse "JEV_KEY_VAR must be the NAME of a shell variable (letters, digits, underscore), not a value"
case "$MODE" in shadow|enforce) ;; *) refuse "JEV_MODE must be shadow or enforce" ;; esac
# Enforce without calibration / validation / a local endpoint is non-compliance (§11.4.279(C)(D)(F)). The decision is
# the SHARED jev_effective_mode (the same function bootstrap stage 5 and jev-status call): enforce only for a loopback
# base URL, a detection record with a local-llmctl endpoint, a PROMOTED numeric threshold and a STRICT
# `llmctl require-validated` PASS per decision profile; a hosted / non-loopback JEV_BASE_URL is ALWAYS shadow. It is
# re-derived on EVERY run and the result is written everywhere (env file, MCP entry), a stored `enforce` is downgraded.
# Test-only overrides (honoured only with JEV_TEST=1): JEV_REQUIRE_VALIDATED_CMD, JEV_DECISION_PROFILES.
_det="$(jev_detection_file)"
REQ_MODE="$MODE"
IFS=$'\t' read -r MODE MODE_WHY < <(jev_effective_mode "$REQ_MODE" "" "$_det" "$CFGDIR/jev-thresholds.json") || true
[ "$MODE" = "enforce" ] || MODE="shadow"
# (No separate stored-base-URL check: the shared jev_effective_mode resolves JEV_BASE_URL from the process env, the env
# file, the MCP entry and the ranked cache itself, review r4 I4-1; one hosted value anywhere forces shadow.)
if [ "$REQ_MODE" = "enforce" ] && [ "$MODE" != "enforce" ]; then
  echo "jev register: JEV_MODE=enforce requested but not honoured ($MODE_WHY) - registering in shadow mode" >&2
fi

# render_mcp_entry : the SINGLE source of truth for the server entry is
# <constitution>/mcp/templates/jev-decisions.json.tmpl (a template, never a live
# MCP config). ONE substitution pass over ${VAR} / ${VAR:-default} (a value that
# itself looks like a placeholder is never re-expanded), drop env entries that
# end up empty (e.g. JEV_CA_FILE unset), refuse to emit anything unexpanded.
MCP_TMPL="$SKILL_DIR/../../mcp/templates/jev-decisions.json.tmpl"
render_mcp_entry() {
  [ -f "$MCP_TMPL" ] || { echo "jev-register: template $MCP_TMPL missing" >&2; return 1; }
  local out
  out="$(jq -c --arg tk "$TOOLKIT" --arg url "$BASE_URL" --arg kv "$KEY_VAR" --arg ca "$CA_FILE" --arg model "$MODEL" --arg mode "$MODE" \
    '{CLAUDE_TOOLKIT_DIR:$tk, JEV_BASE_URL:$url, JEV_KEY_VAR:$kv, JEV_CA_FILE:$ca, JEV_MODEL:$model, JEV_MODE:$mode} as $v
     | .mcpServers.jev
     | walk(if type == "string" then
         gsub("\\$\\{(?<n>[A-Z_]+)(:-(?<d>[^}]*))?\\}"; ($v[.n] // .d // "@@JEV_UNEXPANDED@@"))
       else . end)
     | .env |= with_entries(select(.value != ""))' "$MCP_TMPL")" || return 1
  case "$out" in *'${'*|*'@@JEV_UNEXPANDED@@'*) echo "jev-register: unexpanded placeholder left after render" >&2; return 1 ;; esac
  printf '%s' "$out"
}
MCP_ENTRY=""
if [ -d "$JHOME/.claude" ]; then
  MCP_ENTRY="$(render_mcp_entry)" || refuse "MCP template cannot be rendered"
fi

mkdir -p "$CFGDIR"

# ONE backup per file ever (the first holds the ORIGINAL content) and NEVER of a file holding key material: the toolkit's
# jev-setup writes the key value into the agent MCP config, and a timestamped plaintext copy per run would multiply it
# (review r6 I6-1). The edits below are jq-preserving rewrites, so nothing else is lost by not copying.
backup() { jev_backup_once "$1" "$NOW"; }

# jq_edit <file> <jq-args...> : backup, edit into a temp beside the RESOLVED target, then rename onto it (a symlinked
# config stays a symlink and keeps its mode; review r6 m6-4).
jq_edit() {
  local f="$1" out; shift
  out="$(jq "$@" "$f")" || return 1
  backup "$f"
  printf '%s\n' "$out" | jev_write_atomic "$f"
}

# ── env exports (launch path; names and non-secret values only) ─────────────
ENVF="$CFGDIR/env"
if [ ! -f "$ENVF" ]; then
  { printf 'JEV_MODE=%s\nJEV_BASE_URL=%s\nJEV_MODEL=%s\nJEV_KEY_VAR=%s\n' "$MODE" "$BASE_URL" "$MODEL" "$KEY_VAR"
    [ -z "$CA_FILE" ] || printf 'JEV_CA_FILE=%s\n' "$CA_FILE"; } | jev_write_atomic "$ENVF"
elif [ "$(jev_env_get "$ENVF" JEV_MODE)" != "$MODE" ] || [ "$(jev_env_values "$ENVF" JEV_MODE | sort -u | wc -l)" -gt 1 ]; then
  # an existing env file keeps the operator's other lines but its JEV_MODE is ALWAYS re-derived (review r3 I3-2)
  backup "$ENVF"
  if [ -n "$(jev_env_values "$ENVF" JEV_MODE)" ]; then sed -E "s/^[[:space:]]*(export[[:space:]]+)?JEV_MODE=.*/JEV_MODE=$MODE/" "$ENVF" | jev_write_atomic "$ENVF"
  else { cat "$ENVF"; printf 'JEV_MODE=%s\n' "$MODE"; } | jev_write_atomic "$ENVF"; fi
fi

# repair_stale_jev <mcp-file> : drop a `jev` entry that still holds an unexpanded
# ${...} placeholder (shipped by v71). Unparseable file or clean entry: untouched.
repair_stale_jev() {
  local f="$1"
  [ -f "$f" ] || return 0
  jq -e '(.mcpServers.jev? // empty) | tojson | contains("${")' "$f" >/dev/null 2>&1 || return 0
  jq_edit "$f" 'del(.mcpServers.jev)' && log "repaired: removed stale 'jev' entry (unexpanded placeholder) from $f"
}

# ── claude ──
if [ -d "$JHOME/.claude" ]; then
  s="$JHOME/.claude/settings.json"
  [ -f "$s" ] || printf '{}\n' > "$s"
  if ! jq -e '.hooks.PreToolUse[]? | .. | .command? // empty | select(test("jev-gate\\.sh"))' "$s" >/dev/null 2>&1; then
    jq_edit "$s" --arg tk "$TOOLKIT" '.hooks.PreToolUse = ((.hooks.PreToolUse // []) + [{
        "matcher": "*",
        "hooks": [{"type": "command", "command": ("bash " + $tk + "/scripts/jev-gate.sh")}]
      }])' && log "claude: PreToolUse hook entry added"
  else
    log "claude: hook entry present (no-change)"
  fi
  m="$JHOME/.mcp.json"
  [ -f "$m" ] || printf '{"mcpServers":{}}\n' > "$m"
  repair_stale_jev "$m"
  if ! jq -e '.mcpServers.jev' "$m" >/dev/null 2>&1; then
    jq_edit "$m" --argjson e "$MCP_ENTRY" '.mcpServers.jev = $e' \
      && log "claude: MCP server 'jev' registered (rendered from mcp/templates/jev-decisions.json.tmpl)"
  elif [ "$(jq -r '.mcpServers.jev.env.JEV_MODE // ""' "$m" 2>/dev/null)" != "$MODE" ]; then
    jq_edit "$m" --arg mode "$MODE" '.mcpServers.jev.env.JEV_MODE = $mode' \
      && log "claude: MCP 'jev' env.JEV_MODE re-derived -> $MODE ($MODE_WHY)"
  else
    log "claude: MCP 'jev' present (no-change)"
  fi
  # every OTHER covered config with a jev entry that carries a JEV_MODE agrees with this run too (r7 n7-3; bootstrap does the
  # same, so jev-status never reports a mismatch after register alone). Optimistic write, skipped with a warning on a race.
  while IFS=$'\t' read -r _mf _mm; do
    [ -n "${_mf:-}" ] && [ "$_mm" != "$MODE" ] || continue
    [ "$(jev_real_target "$_mf")" != "$(jev_real_target "$m")" ] || continue
    jev_mcp_mode_rewrite "$_mf" "$MODE" && log "claude: MCP 'jev' env.JEV_MODE re-derived -> $MODE ($_mf)"
  done < <(jev_mcp_modes)
fi

# ── kimi ──
if [ -d "$JHOME/.kimi-code" ]; then
  c="$JHOME/.kimi-code/config.toml"
  [ -f "$c" ] || : > "$c"
  if grep -q '# >>> helix-jev >>>' "$c"; then
    log "kimi: marker block present (no-change)"
  else
    backup "$c"
    cat >> "$c" <<EOF

# >>> helix-jev >>>
[[hooks]]
event = "PreToolUse"
command = "bash $TOOLKIT/scripts/jev-gate.sh"

[mcp_servers.jev]
command = "python3"
args = ["$TOOLKIT/scripts/jev_mcp.py"]
# <<< helix-jev <<<
EOF
    log "kimi: [[hooks]] + mcp_servers.jev marker block appended"
  fi
fi

# ── opencode (honest partial coverage) ──────────────────────────────────────
OC="$JHOME/.config/opencode"
if [ -d "$OC" ]; then
  mkdir -p "$OC/plugin"
  [ -f "$OC/plugin/jev.js" ] || cat > "$OC/plugin/jev.js" <<'EOF'
// jev decision-layer gate plugin — intercepts direct tool calls only.
// COVERAGE GAP: does not intercept MCP-tool or subagent calls (see jev-coverage-gaps.md).
// Placeholder: it does not itself call the decide endpoint; the claude_toolkit
// plugin (scripts/jev-setup.sh --agents opencode) installs the working one.
export const JevGate = async () => ({
  "tool.execute.before": async (input, output) => {},
})
EOF
  cfg="$OC/opencode.json"
  [ -f "$cfg" ] || printf '{}\n' > "$cfg"
  if ! jq -e '.mcp.jev' "$cfg" >/dev/null 2>&1; then
    jq_edit "$cfg" --arg tk "$TOOLKIT" --arg plug "file://$OC/plugin/jev.js" \
      '.plugin = (((.plugin // []) + [$plug]) | unique)
       | .mcp.jev = {"type":"local","command":["python3", ($tk+"/scripts/jev_mcp.py")]}' \
      && log "opencode: plugin + mcp.jev entries added"
  else
    log "opencode: config entries present (no-change)"
  fi
  [ -f "$OC/jev-coverage-gaps.md" ] || cat > "$OC/jev-coverage-gaps.md" <<'EOF'
# opencode decision-layer coverage gaps (honest record, §11.4.280(C))

The opencode plugin hook (`tool.execute.before`) intercepts direct tool calls only.
It does NOT intercept MCP-tool calls invoked through other MCP servers, nor
subagent/task calls. Those classes bypass the decision-layer gate on this platform.
EOF
fi

# ── pi (documented fallback) ────────────────────────────────────────────────
if [ -d "$JHOME/.pi" ]; then
  [ -f "$JHOME/.pi/jev-package.md" ] || cat > "$JHOME/.pi/jev-package.md" <<EOF
# pi decision-layer integration (documented fallback, §11.4.280)

No verified PreToolUse hook mechanism on this host. The MCP server 'jev'
(python3 $TOOLKIT/scripts/jev_mcp.py) is the integration path; register it in
pi's MCP config. Coverage gap: free-form tool invocations are not gated.
EOF
  log "pi: package note present"
fi

# ── provenance (§11.4.228) ──────────────────────────────────────────────────
[ -f "$SKILL_DIR/EXTENSION_SOURCE.yaml" ] \
  || log "WARNING: EXTENSION_SOURCE.yaml missing from $SKILL_DIR"
STAMP="$CFGDIR/registration.stamp"
[ -f "$STAMP" ] || printf 'extension=jev-decision-layer\nsource=%s\n' "$SKILL_DIR" > "$STAMP"

log "done (idempotent — re-run is a no-op)"
exit 0
