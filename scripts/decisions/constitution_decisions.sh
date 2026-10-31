#!/usr/bin/env bash
# constitution_decisions.sh — decisions wizard for the Jev decision layer and other decision models.
#
# Records decision-model choices as LOCAL PROJECT OVERRIDES that inherit from the constitution
# (§11.4.35, §11.4.279-§11.4.286): <project>/.constitution/decisions.yml plus a marker-delimited
# block in the project's CLAUDE.md / AGENTS.md / GEMINI.md / QWEN.md (only files that exist).
# A locked constitution rule can only be kept or tightened; a weakening override is refused.
#
# Usage:
#   constitution_decisions.sh [--project-root DIR] [--scope project|user]
#       [--show [--json]] [--check] [--plan [--probe]] [--export FILE|-]
#       [--set KEY=VALUE]... [--unset KEY]... [--reset] [--answers FILE] [--import FILE]
#       [--doc FILE]... [--dry-run] [--non-interactive] [--accept-external-edits]
#       [--accept-env] [--force-export] [--inherits PATH] [--version]
#   With no action flag on a TTY it asks every decision (answers read from /dev/tty).
#   --inherits PATH  record/accept an inherited constitution path (explicit confirmation for a project without
#                   submodules/constitution or ./constitution, or for the HOME directory). Writes otherwise need a git
#                   repository root that holds an inherited constitution.
#   --accept-env    take decisions (consents and layer mode) from JEV_BOOTSTRAP_* env (ignored, with a note,
#                   without it).
#   CONSTITUTION_DECISIONS_BACKUP_KEEP  number of wizard backups kept per location (default 20).
#   --force-export  let --export replace an existing file (a backup is taken first); --export never
#                   writes into .git/ or .constitution/ or outside the project.
#
# Env (names only; values never printed): CONSTITUTION_DECISIONS_NON_INTERACTIVE, CONSTITUTION_DECISIONS_USER_FILE,
#   JEV_BOOTSTRAP_NON_INTERACTIVE, JEV_BOOTSTRAP_MODE, JEV_BOOTSTRAP_AGENTS, JEV_BOOTSTRAP_CONSENT,
#   JEV_BOOTSTRAP_ALLOW_CLONE, JEV_BOOTSTRAP_INSTALL_TOOLS, JEV_BOOTSTRAP_DOWNLOAD_PROFILE, LLMCTL_BIN, XDG_CONFIG_HOME.
#
# Exit codes: 0 done (incl. no-change) · 1 internal failure · 2 usage / no TTY without --non-interactive ·
#   3 precondition (bad project root, python3/PyYAML missing, path outside project, symlinked target, write target in a
#   submodule/another repository/the inherited constitution, no inherited constitution) ·
#   4 refused (unknown key, weakening, NEW contradiction, secret-like value, tampered file, broken markers) ·
#   5 another run holds the lock.
#
# Side effects: writes only inside the project (and, with --scope user, the user file, its lock and its .decisions-backup/); never edits
# settings.json; never runs bootstrap.sh (it prints the command); no network; no LLM.
# Plan and catalogue: docs/design/decisions_wizard_plan.md. Classification: universal (§11.4.17).
set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
case "${1:-}" in -h|--help) sed -n '2,/^set -u/p' "${BASH_SOURCE[0]:-$0}" | sed '$d; s/^# \{0,1\}//'; exit 0 ;; esac
command -v python3 >/dev/null 2>&1 || { echo "constitution_decisions: blocked: python3 is required" >&2; exit 3; }
python3 -I -c 'import yaml' 2>/dev/null || { echo "constitution_decisions: blocked: PyYAML (python3-yaml) is required" >&2; exit 3; }
exec python3 -I "$here/decisions_engine.py" "$@"
