#!/usr/bin/env bash
# ============================================================================
# skill-activate — host-level, PROJECT-AGNOSTIC entry point (§11.4.177).
# ============================================================================
# Works in BOTH modes (operator mandate REQ-NOTE-0001):
#   mode A  project vendors constitution/           -> full dynamic activation
#   mode B  project does not, host checkout found   -> full dynamic activation
#   mode C  engine genuinely unreachable            -> HONEST, LOUD degradation
#
# It operates on the INVOCATION DIRECTORY (cwd) and hardcodes no project path;
# the host fallback is configurable (HELIX_CONSTITUTION_DIR, or
# ~/.claude-shared/constitution-path), so nothing project-specific is wired
# into shared tooling.
#
# CANONICAL SOURCE (root-caused 2026-09-22, §11.4.272 CM-CLI-AGENT-PLUGINS-WIRED
# invariant 6/skills): this file IS the single source of truth for the
# host-level wrapper. register.sh (../../skills/skill-catalog/register.sh)
# installs a byte-identical copy to ~/.claude-shared/bin/skill-activate on
# every constitution pull that touches constitution/skills/skill-catalog/** —
# the SAME belt-and-suspenders auto-wiring pattern multitrack/register.sh
# already uses for its own mechanism. Before this file existed, the deployed
# wrapper had NO tracked source anywhere in this repository — it worked on
# this one host only because someone had hand-installed it once, which
# directly contradicted this mechanism's own documented promise ("a project
# WITHOUT the submodule still gets a working command", §11.4.272 clause G) —
# a fresh host pulling this constitution for the first time got nothing.
# Edit THIS file to change the wrapper's behaviour; never hand-edit the
# installed copy directly, it will be overwritten on the next constitution
# pull that touches this skill.
# ============================================================================
set -uo pipefail

# Self-contained resolution: this shim CANNOT depend on the constitution to
# find the constitution.
_resolve() {
  _t() { [ -r "$1/skill_activate.sh" ] && { printf '%s\n' "$1"; return 0; }; return 1; }
  [ -n "${HELIX_SKILL_ENGINE:-}" ] && _t "$HELIX_SKILL_ENGINE" && return 0
  local d; d="$(pwd)"
  while :; do
    _t "$d/constitution/scripts/skill_activation" && return 0
    [ "$d" = "/" ] && break
    d="$(dirname "$d")"
  done
  [ -n "${HELIX_CONSTITUTION_DIR:-}" ] && _t "$HELIX_CONSTITUTION_DIR/scripts/skill_activation" && return 0
  if [ -r "$HOME/.claude-shared/constitution-path" ]; then
    local p; p="$(head -1 "$HOME/.claude-shared/constitution-path" 2>/dev/null)"
    [ -n "$p" ] && _t "${p/#\~/$HOME}/scripts/skill_activation" && return 0
  fi
  _t "$HOME/Projects/helix_code/constitution/scripts/skill_activation" && return 0
  return 3
}

if engine="$(_resolve)"; then
  exec "$engine/skill_activate.sh" "$@"
fi

# ---- mode C: degrade LOUDLY, never silently (§11.4.201) --------------------
cat >&2 <<MSG
SKILL-ACTIVATION-UNAVAILABLE: dynamic skill activation is NOT active here.

  WHAT is unavailable : dynamic activate/deactivate of skills on demand.
  WHY                 : the skill-activation engine could not be located.
  WHERE I looked      : \$HELIX_SKILL_ENGINE; ./constitution/... and every
                        parent directory of $(pwd); \$HELIX_CONSTITUTION_DIR;
                        ~/.claude-shared/constitution-path;
                        ~/Projects/helix_code/constitution/...

  WHAT STILL WORKS    : your EXISTING skills are untouched and fully usable.
                        This command manages which skills are loaded; it does
                        not provide them. Nothing was added and nothing was
                        removed. You have exactly the static skill set this
                        project already had.

  DO NOT assume a skill is available because this command was run. It was not
  able to activate anything.

  TO FIX (either one):
    export HELIX_CONSTITUTION_DIR=/path/to/a/constitution/checkout
    echo /path/to/a/constitution/checkout > ~/.claude-shared/constitution-path
MSG
exit 3
