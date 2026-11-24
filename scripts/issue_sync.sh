#!/usr/bin/env bash
# scripts/issue_sync.sh -- entry point of the workable-items Issues mirror (anchor §11.4.300).
# Usage: issue_sync.sh {plan|apply|verify|status} [--config F] [--db F] --owner-repo HOST/OWNER/REPO --target HOST/OWNER/REPO ... [--apply] [--only-open] [--limit N] [--json]
#   plan    dry-run (default): the actions each leg would take; NO write
#   apply   writes ONLY with --apply AND config mode: apply (+ apply_decision); never in dry-run
#   verify  read-only; exit 0 every leg matches the DB, 1 drift (item ids named), 2 cannot determine (never a pass)
# Default OFF: with no config, or enabled:false, it prints "disabled" and exits 0. Tokens are read by variable NAME, never printed.
# Side-effects: apply writes Issues on the target trackers and issue_sync_map in the DB. Dependencies: bash, python3, PyYAML.
# Classification: universal (§11.4.17).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PYTHONPATH="$HERE${PYTHONPATH:+:$PYTHONPATH}"
exec python3 -W ignore -m issue_sync.cli "$@"
