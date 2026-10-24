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
# Twice-run = single registration (marker-guarded / jq-merge). Every edited
# existing file is backed up first as <file>.prejev.<epoch>.
#
# Exit codes: 0 done; 2 cannot determine (jq missing while an agent home needs a
# JSON edit, or the MCP template cannot be rendered — nothing is half-written).
#
# Env (names only; secrets are never written, only the key variable NAME):
#   JEV_HOME (target home, default $HOME), CLAUDE_TOOLKIT_DIR (default
#   $HOME/.local/share/helix/claude_toolkit), JEV_BASE_URL (default
#   https://127.0.0.1:8095, the llmctl decide gateway), JEV_MODEL,
#   JEV_KEY_VAR (default LLMCTL_API_KEY), JEV_CA_FILE (optional CA path),
#   JEV_NOW_EPOCH (clock seam).
# shellcheck disable=SC2016  # jq programs use $var references on purpose
set -uo pipefail

SKILL_DIR=$(cd "$(dirname "$0")" && pwd)
JHOME="${JEV_HOME:-$HOME}"
TOOLKIT="${CLAUDE_TOOLKIT_DIR:-$JHOME/.local/share/helix/claude_toolkit}"
BASE_URL="${JEV_BASE_URL:-https://127.0.0.1:8095}"
MODEL="${JEV_MODEL:-jev-latest}"
KEY_VAR="${JEV_KEY_VAR:-LLMCTL_API_KEY}"
CA_FILE="${JEV_CA_FILE:-}"
NOW="${JEV_NOW_EPOCH:-$(date +%s)}"

log() { printf '[jev-register] %s\n' "$*"; }

if { [ -d "$JHOME/.claude" ] || [ -d "$JHOME/.config/opencode" ]; } && ! command -v jq >/dev/null 2>&1; then
  echo "jev-register: jq is required to edit JSON agent config; cannot determine (rc 2); nothing written" >&2
  exit 2
fi

mkdir -p "$JHOME/.config/jev"

backup() { [ -f "$1" ] && cp -p "$1" "$1.prejev.$NOW" || true; }

# jq_edit <file> <jq-args...> : backup, edit into a same-dir tmp, then rename.
jq_edit() {
  local f="$1" tmp; shift
  tmp="$(mktemp "$(dirname "$f")/.jev-reg.XXXXXX")" || return 1
  if jq "$@" "$f" > "$tmp"; then backup "$f"; mv -f "$tmp" "$f"; else rm -f "$tmp"; return 1; fi
}

# ── env exports (launch path; names and non-secret values only) ─────────────
ENVF="$JHOME/.config/jev/env"
if [ ! -f "$ENVF" ]; then
  { printf 'JEV_MODE=shadow\nJEV_BASE_URL=%s\nJEV_MODEL=%s\nJEV_KEY_VAR=%s\n' "$BASE_URL" "$MODEL" "$KEY_VAR"
    [ -n "$CA_FILE" ] && printf 'JEV_CA_FILE=%s\n' "$CA_FILE"; } > "$ENVF"
fi

# render_mcp_entry : the SINGLE source of truth for the server entry is
# <constitution>/mcp/templates/jev-decisions.json.tmpl (a template, never a live
# MCP config). Substitute its ${VAR} / ${VAR:-default} placeholders, drop env
# entries that end up empty (e.g. JEV_CA_FILE unset), refuse to emit anything
# that still contains a placeholder.
MCP_TMPL="$SKILL_DIR/../../mcp/templates/jev-decisions.json.tmpl"
RENDER_FAILED=0
render_mcp_entry() {
  [ -f "$MCP_TMPL" ] || { echo "jev-register: template $MCP_TMPL missing" >&2; return 1; }
  local out
  out="$(jq -c --arg tk "$TOOLKIT" --arg url "$BASE_URL" --arg kv "$KEY_VAR" --arg ca "$CA_FILE" --arg model "$MODEL" \
    '.mcpServers.jev
     | walk(if type == "string" then
         gsub("\\$\\{CLAUDE_TOOLKIT_DIR\\}"; $tk) | gsub("\\$\\{JEV_BASE_URL\\}"; $url)
         | gsub("\\$\\{JEV_KEY_VAR\\}"; $kv) | gsub("\\$\\{JEV_CA_FILE\\}"; $ca)
         | gsub("\\$\\{JEV_MODEL:-[^}]*\\}"; $model) | gsub("\\$\\{JEV_MODE:-(?<d>[^}]*)\\}"; .d)
       else . end)
     | .env |= with_entries(select(.value != ""))' "$MCP_TMPL")" || return 1
  case "$out" in *'${'*) echo "jev-register: unexpanded placeholder left after render" >&2; return 1 ;; esac
  printf '%s' "$out"
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
  if ! jq -e '.mcpServers.jev' "$m" >/dev/null 2>&1; then
    if entry="$(render_mcp_entry)"; then
      jq_edit "$m" --argjson e "$entry" '.mcpServers.jev = $e' \
        && log "claude: MCP server 'jev' registered (rendered from mcp/templates/jev-decisions.json.tmpl)"
    else
      log "claude: MCP 'jev' NOT registered: template render failed"; RENDER_FAILED=1
    fi
  else
    log "claude: MCP 'jev' present (no-change)"
  fi
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
STAMP="$JHOME/.config/jev/registration.stamp"
[ -f "$STAMP" ] || printf 'extension=jev-decision-layer\nsource=%s\n' "$SKILL_DIR" > "$STAMP"

log "done (idempotent — re-run is a no-op)"
[ "$RENDER_FAILED" -eq 0 ] || { echo "jev-register: MCP template render failed (rc 2)" >&2; exit 2; }
exit 0
