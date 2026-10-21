#!/usr/bin/env bash
# skills/label-sync/register.sh
#
# Purpose:   Register the 'label-sync' skill in a consuming project by linking it
#            into <project>/.claude/skills/ (the native project-scoped Agent-Skills
#            discovery path). Called by post_update_hook.sh on every constitution
#            pull (§11.4.164) and by install_cli_agent_plugins.sh (§11.4.228(D)).
# Usage:     bash register.sh [PROJECT_ROOT]        (default: $PWD)
# Inputs:    $1 — consuming project root
# Outputs:   <project>/.claude/skills/label-sync -> this directory. Exit 0 on success.
# Side-effects: creates <project>/.claude/skills/ and one symlink (never a copy —
#            the constitution is inherited BY REFERENCE per §11.4.28 / §11.4.80).
# Dependencies: bash, ../../scripts/install_cli_agent_plugins.sh
# Cross-references: §11.4.164, §11.4.182, §11.4.228, §11.4.28.
# Classification: universal (§11.4.17)
# Last verified: 2026-10-12
set -euo pipefail
skill_dir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" >/dev/null 2>&1 && pwd)"
const_root="$(cd "$skill_dir/../.." >/dev/null 2>&1 && pwd)"
exec bash "$const_root/scripts/install_cli_agent_plugins.sh" "${1:-$PWD}" --skill "label-sync"
