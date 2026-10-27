#!/usr/bin/env bash
# CM-JEV-WIRING (§11.4.280(D), §11.4.284(E), §11.4.285(E))
# Per detected agent home under $JEV_HOME, asserts the decision layer is wired:
#   1. hook block present per agent's verified mechanics
#   2. MCP `jev` registration present
#   3. env exports reachable from the launch path (.config/jev/env)
#   4. opencode coverage-gap notes present (honest coverage, §11.4.280(C))
#   5. no decision endpoint appears in any chat-model/provider config (§11.4.284(D))
#   6. jev-thresholds.json schema-valid when JEV_MODE=enforce (§11.4.285(E))
#
# Env overrides:
#   JEV_HOME             agent-home root to inspect (default: $HOME)
#   JEV_DETECTION_FILE   detection record for clause 5 endpoint IDs
#                        (default: the shared resolver's detection record, <evidence>/jev-detection.json; absent = clause skipped with note)
set -uo pipefail
command -v jq >/dev/null 2>&1 || { echo "CM-JEV-WIRING CANNOT DETERMINE: jq not installed (rc 2, never a pass)" >&2; exit 2; }

# shellcheck source=../jev/lib_decide.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../jev/lib_decide.sh"   # THE path resolver (review r6 I6-2): no independent derivation here
JHOME="$(jev_home)"
DETECTION="$(jev_detection_file)"
fail=0
err() { printf 'CM-JEV-WIRING FAIL: %s\n' "$*" >&2; fail=1; }
clause_start() { _f0=$fail; }
ok()  { [ "$fail" = "$_f0" ] && printf 'CM-JEV-WIRING ok: %s\n' "$*" >&2; return 0; }
_f0=0

agents=()
clause_start

# ── claude ──
if [ -d "$JHOME/.claude" ]; then
  agents+=(claude)
  s="$JHOME/.claude/settings.json"
  { [ -f "$s" ] && jq -e '.hooks.PreToolUse[]? | .. | .command? // empty | select(test("jev-gate\\.sh"))' "$s" >/dev/null 2>&1; } \
    || err "claude: settings.json lacks a PreToolUse hook entry referencing jev-gate.sh"
  { [ -f "$JHOME/.mcp.json" ] && jq -e '.mcpServers.jev' "$JHOME/.mcp.json" >/dev/null 2>&1; } \
    || { [ -f "$s" ] && jq -e '.mcpServers.jev' "$s" >/dev/null 2>&1; } \
    || err "claude: MCP server 'jev' not registered (.mcp.json or settings.json)"
fi

# ── kimi ──
if [ -d "$JHOME/.kimi-code" ]; then
  agents+=(kimi)
  c="$JHOME/.kimi-code/config.toml"
  if [ -f "$c" ]; then
    block=$(awk '/# >>> helix-jev >>>/{f=1} f{print} /# <<< helix-jev <<</{f=0}' "$c")
    printf '%s' "$block" | grep -q '\[\[hooks\]\]' \
      || err "kimi: config.toml helix-jev marker block lacks a [[hooks]] entry"
    printf '%s' "$block" | grep -q 'jev-gate\.sh' \
      || err "kimi: [[hooks]] block does not reference jev-gate.sh"
    printf '%s' "$block" | grep -q 'mcp_servers.jev' \
      || err "kimi: MCP server 'jev' not registered in config.toml"
  else
    err "kimi: $c missing"
  fi
fi

# ── opencode ──
if [ -d "$JHOME/.config/opencode" ]; then
  agents+=(opencode)
  oc="$JHOME/.config/opencode"
  ls "$oc"/plugin/jev.* >/dev/null 2>&1 \
    || err "opencode: decision-layer plugin file missing under $oc/plugin/"
  { [ -f "$oc/opencode.json" ] && jq -e '.plugin | tostring | test("jev")' "$oc/opencode.json" >/dev/null 2>&1 \
      && jq -e '.mcp.jev' "$oc/opencode.json" >/dev/null 2>&1; } \
    || err "opencode: opencode.json lacks the jev plugin entry and/or mcp.jev registration"
  # Clause 4 — honest coverage-gap note (plugin hooks cannot intercept
  # MCP-tool or subagent calls; the gap MUST be recorded verbatim).
  { [ -f "$oc/jev-coverage-gaps.md" ] && grep -qi 'MCP' "$oc/jev-coverage-gaps.md" \
      && grep -qi 'subagent' "$oc/jev-coverage-gaps.md"; } \
    || err "opencode: coverage-gap note (MCP-tool + subagent classes not intercepted) missing — claiming full coverage is a §7.1 bluff"
fi

# ── pi ──
if [ -d "$JHOME/.pi" ]; then
  agents+=(pi)
  ls "$JHOME/.pi"/jev*.md >/dev/null 2>&1 \
    || err "pi: no jev package/integration note under .pi/ (package or documented fallback required)"
fi

[ "${#agents[@]}" -gt 0 ] || err "no agent homes detected under JEV_HOME=$JHOME — nothing wired (detection-first, §11.4.279)"
ok "clause 1/2: hook + MCP wiring present for: ${agents[*]:-none}"

# Clause 3 — env exports reachable from the launch path.
clause_start
CFGDIR="$(jev_config_dir)"   # bootstrap writes <config>/env
if [ -f "$CFGDIR/env" ]; then
  grep -q '^JEV_MODE=' "$CFGDIR/env" \
    || err "env: $CFGDIR/env lacks JEV_MODE"
  ok "clause 3: env exports present at $CFGDIR/env"
else
  err "env: $CFGDIR/env missing — provider-alias env exports not reachable from launch path"
fi

clause_start
# Clause 5 — no decision endpoint in any chat-model/provider config (§11.4.284(D)).
if [ -f "$DETECTION" ] && jq -e '.endpoints | length > 0' "$DETECTION" >/dev/null 2>&1; then
  ids=$(jq -r '.endpoints[].id' "$DETECTION")
  models=$(jq -r '.endpoints[].model' "$DETECTION")
  while IFS= read -r cfg; do
    [ -n "$cfg" ] || continue
    while IFS= read -r eid; do
      [ -n "$eid" ] || continue
      grep -qF -- "$eid" "$cfg" && err "clause5: decision endpoint id '$eid' found in chat-model config $cfg (§11.4.284(D) critical defect)"
    done <<< "$ids"
    while IFS= read -r m; do
      [ -n "$m" ] || continue
      { case "$cfg" in
          *.env) grep -qF -- "$m" "$cfg" ;;
          *) jq -e --arg m "$m" '.. | strings | select(. == $m)' "$cfg" >/dev/null 2>&1 ;;
        esac; } \
        && err "clause5: decision model '$m' wired as a chat model in $cfg (§11.4.284(D) critical defect)"
    done <<< "$models"
  # Bounded walk: only the agent config homes (and the jev config dir), shallow. The whole of $JHOME is a project
  # tree on a real machine; walking it took >100 s and hung the bootstrap report stage (2026-10-24).
  done < <( { for _d in "$JHOME/.claude" "$JHOME/.kimi-code" "$JHOME/.pi" "$JHOME/.config/opencode" "$CFGDIR"; do
             [ -d "$_d" ] && find "$_d" -maxdepth 4 \( -name 'models.json' -o -name 'providers.json' \) -type f 2>/dev/null
           done
           # plus a shallow look at the top of the home itself (provider dirs placed directly under it)
           find "$JHOME" -maxdepth 3 \( -name .cache -o -name .git -o -name node_modules -o -name .local \) -prune -o \
             \( -name 'models.json' -o -name 'providers.json' \) -type f -print 2>/dev/null
           # provider .env files: an alias launches a chat model from ANTHROPIC_MODEL & co. in these (claude_toolkit)
           _pd="$(jev_providers_dir)"
           [ -d "$_pd" ] && find "$_pd" -maxdepth 2 -name '*.env' -type f 2>/dev/null; } | sort -u )
  ok "clause 5: no decision endpoint in chat-model configs"
else
  ok "clause 5: skipped (no detection record or zero endpoints — lawful only via §11.4.279(B) reasoned record)"
fi

clause_start
# Clause 6 — thresholds schema-valid when enforce mode active.
mode=$(grep -s '^JEV_MODE=' "$CFGDIR/env" | cut -d= -f2)
if [ "$mode" = "enforce" ]; then
  t="$CFGDIR/jev-thresholds.json"
  { [ -f "$t" ] && jq -e '.per_type | type == "object" and length > 0' "$t" >/dev/null 2>&1 \
      && jq -e '[.per_type[] | select(.promoted == true and (.threshold|type=="number"))] | length > 0' "$t" >/dev/null 2>&1; } \
    || err "thresholds: JEV_MODE=enforce but jev-thresholds.json missing/schema-invalid or no type is PROMOTED — enforce-without-calibration is non-compliance (§11.4.285(C))"
  ok "clause 6: thresholds schema-valid under enforce mode"
else
  ok "clause 6: skipped (mode=${mode:-unset}, enforce not active)"
fi

if [ "$fail" -ne 0 ]; then
  echo "CM-JEV-WIRING: RED" >&2
  exit 1
fi
echo "CM-JEV-WIRING: GREEN"
exit 0
