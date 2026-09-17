#!/usr/bin/env bash
# ============================================================================
# resolve_engine.sh — locate the skill-activation engine, in EITHER mode.
# ============================================================================
# The Claude Toolkit must work on projects that DO vendor the constitution
# submodule and on projects that DO NOT (operator mandate, REQ-NOTE-0001). A
# project without the submodule must still get a working command, or — if the
# engine is genuinely unreachable — an HONEST, LOUD refusal. It must never get
# a silent no-op, because a command that silently does nothing is
# indistinguishable from one that ran and found nothing (§11.4.201 false-null).
#
# Resolution order (explicit, in this order, first hit wins):
#   1. $HELIX_SKILL_ENGINE            — explicit override, always wins
#   2. <cwd>/constitution/...         — in-project submodule (mode A)
#   3. any ancestor of <cwd> with constitution/... — sub-directory of mode A
#   4. $HELIX_CONSTITUTION_DIR/...    — operator-configured host checkout
#   5. ~/.claude-shared/constitution-path (a file holding one path)
#   6. host fallback, as documented in ~/.claude-shared/CLAUDE.md (mode B)
#   7. NOT FOUND -> caller degrades honestly (mode C)
#
# Emits the engine directory on stdout and exits 0; exits 3 when unresolved
# (3 is reserved for "engine absent" and is distinct from 1 = operation failed).
# ============================================================================
set -uo pipefail
_try() { [ -r "$1/skill_activate.sh" ] && { printf '%s\n' "$1"; exit 0; }; }

[ -n "${HELIX_SKILL_ENGINE:-}" ] && _try "$HELIX_SKILL_ENGINE"

d="$(pwd)"
while :; do
  _try "$d/constitution/scripts/skill_activation"
  [ "$d" = "/" ] && break
  d="$(dirname "$d")"
done

[ -n "${HELIX_CONSTITUTION_DIR:-}" ] && _try "$HELIX_CONSTITUTION_DIR/scripts/skill_activation"

if [ -r "$HOME/.claude-shared/constitution-path" ]; then
  p="$(head -1 "$HOME/.claude-shared/constitution-path" 2>/dev/null)"
  [ -n "$p" ] && _try "${p/#\~/$HOME}/scripts/skill_activation"
fi

_try "$HOME/Projects/helix_code/constitution/scripts/skill_activation"
exit 3
