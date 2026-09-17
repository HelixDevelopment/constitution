#!/usr/bin/env bash
# ============================================================================
# skill_budget_gate.sh — CM-SKILL-SURFACE-BUDGET
# ============================================================================
# Why this gate exists (the defect it is built to catch):
#   The per-turn cost of the available-skills list depends on TWO things the
#   project does not control: how many skills are active, and whether the
#   platform renders them NAME-ONLY or NAME+DESCRIPTION. Measured on this host
#   2026-09-07 (claude 2.1.263) over a 955-skill pool:
#       name-only          ~29 KB   (~7.3K tokens/turn)
#       name+description  ~423 KB  (~106K tokens/turn)   <- 14x cliff
#   An upstream change to description-eager rendering would silently cost ~100K
#   tokens EVERY TURN with nothing watching. This gate makes that break LOUDLY.
#
#   It therefore budgets BOTH render modes: a project can be safe today and one
#   upstream release away from catastrophe, and the gate refuses to certify a
#   surface that would blow up under the eager render.
#
# Usage:
#   skill_budget_gate.sh [PROJECT_ROOT]
# Env (project instantiation, §11.4.35):
#   HELIX_SKILL_BUDGET_NAME_BYTES  default 4096
#   HELIX_SKILL_BUDGET_DESC_BYTES  default 24576
# Exit: 0 PASS · 1 FAIL (explicit reason) — never silent (§11.4.201).
# ============================================================================
set -uo pipefail
SA_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SA_DIR/skill_activation_lib.sh"

root="$(sa_project_root "${1:-$PWD}")"
adir="$(sa_active_dir "$root")"
LIM_NAME="${HELIX_SKILL_BUDGET_NAME_BYTES:-4096}"
LIM_DESC="${HELIX_SKILL_BUDGET_DESC_BYTES:-24576}"

n=0; b_name=0; b_desc=0; worst=""; worst_len=0
if [ -d "$adir" ]; then
  for p in "$adir"/*/SKILL.md; do
    [ -e "$p" ] || continue
    nm="$(basename "$(dirname "$p")")"
    d="$(awk '/^description:/{sub(/^description: */,"");print;exit}' "$p" 2>/dev/null)"
    n=$((n+1))
    b_name=$((b_name + ${#nm} + 3))          # "- <name>\n"
    b_desc=$((b_desc + ${#nm} + ${#d} + 5))  # "- <name>: <description>\n"
    if [ ${#d} -gt $worst_len ]; then worst_len=${#d}; worst="$nm"; fi
  done
fi

echo "CM-SKILL-SURFACE-BUDGET"
echo "  active skills            : $n"
echo "  render name-only         : ${b_name} B  (~$((b_name/4)) tok/turn)   limit ${LIM_NAME} B"
echo "  render name+description  : ${b_desc} B  (~$((b_desc/4)) tok/turn)   limit ${LIM_DESC} B"
[ -n "$worst" ] && echo "  longest description      : ${worst} (${worst_len} B)"

rc=0
if [ "$b_name" -gt "$LIM_NAME" ]; then
  echo "  FAIL: name-only render ${b_name} B exceeds ${LIM_NAME} B — too many skills are active." >&2
  echo "        Deactivate what this project does not need every session, or raise HELIX_SKILL_BUDGET_NAME_BYTES deliberately." >&2
  rc=1
fi
if [ "$b_desc" -gt "$LIM_DESC" ]; then
  echo "  FAIL: name+description render ${b_desc} B exceeds ${LIM_DESC} B." >&2
  echo "        This is the cost you would pay if the platform switched to a description-eager render." >&2
  rc=1
fi
[ "$rc" = "0" ] && echo "  PASS"
exit $rc
