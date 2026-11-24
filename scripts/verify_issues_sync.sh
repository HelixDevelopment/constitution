#!/usr/bin/env bash
# scripts/verify_issues_sync.sh -- verifier of the workable-items Issues mirror (anchor §11.4.300(E)).
# Usage: verify_issues_sync.sh [issue_sync verify args: --config F --db F --owner-repo H/O/R --target H/O/R ...]
#        verify_issues_sync.sh --prove-failure     paired mutations over an in-memory tracker double (tool logic, not host evidence)
# Exit: 0 every enabled leg matches the DB (also: mechanism disabled = default OFF), 1 drift (item ids and trackers named),
#       2 cannot determine (no token, host unreachable, capability unverified, visibility undetermined, redaction hard stop, quota); 2 is never a pass.
# Precedence 1 over 2 over 0. Read-only: it never writes to a tracker or to the DB. Tokens are read by variable NAME and never printed.
# Side-effects: none. Dependencies: bash, python3, PyYAML. Classification: universal (§11.4.17).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PYTHONPATH="$HERE${PYTHONPATH:+:$PYTHONPATH}"
if [ "${1:-}" = "--prove-failure" ]; then exec python3 -W ignore -m issue_sync.prove_failure; fi
exec python3 -W ignore -m issue_sync.cli verify "$@"
