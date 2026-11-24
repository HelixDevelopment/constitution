#!/usr/bin/env bash
# cm_issue_sync_template_default_off.sh -- CM-ISSUE-SYNC-TEMPLATE-DEFAULT-OFF gate (anchor §11.4.300(A)).
#
# Purpose: the shipped consumer template templates/workable-items-sync.yaml.template MUST parse, validate against the
#   scripts/issue_sync config schema, and ship `enabled: false` and `mode: dry-run` (the mechanism is OFF for every project
#   until a project turns it on in its own tracked copy). Also runs the issue_sync unit tests (config, visibility, redaction).
# Usage:   cm_issue_sync_template_default_off.sh [--root DIR]
# Side-effects: none (read-only).  Dependencies: bash, python3, PyYAML.
# Exit: 0 PASS, 1 FAIL (template on, invalid, or a unit test fails), 2 cannot determine (python3/PyYAML/template missing).
# Paired mutation: cm_issue_sync_template_default_off_mutation_test.sh.  Classification: universal (§11.4.17).
set -u
GATE="CM-ISSUE-SYNC-TEMPLATE-DEFAULT-OFF"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
while [ $# -gt 0 ]; do case "$1" in --root) ROOT="$2"; shift 2 ;; *) echo "$GATE: unknown argument $1" >&2; exit 2 ;; esac; done
T="$ROOT/templates/workable-items-sync.yaml.template"
command -v python3 >/dev/null 2>&1 || { echo "$GATE: BLIND -- python3 missing" >&2; exit 2; }
python3 -c 'import yaml' 2>/dev/null || { echo "$GATE: BLIND -- PyYAML missing" >&2; exit 2; }
[ -f "$T" ] || { echo "$GATE: BLIND -- template missing: $T" >&2; exit 2; }
out=$(cd "$ROOT/scripts" && python3 - "$T" <<'PY'
import sys
from issue_sync import config
cfg, errs = config.load(sys.argv[1])
if errs: print("INVALID: " + "; ".join(errs)); sys.exit(1)
if cfg["enabled"] is not False: print("ON: template ships enabled != false"); sys.exit(1)
if cfg["mode"] != "dry-run": print("MODE: template ships mode != dry-run"); sys.exit(1)
print("OK")
PY
) || { echo "$GATE: FAIL -- $out"; exit 1; }
tests=$(cd "$ROOT/scripts" && python3 -W ignore -m unittest discover -s issue_sync/tests 2>&1) || { echo "$GATE: FAIL -- issue_sync unit tests:"; printf '%s\n' "$tests" | tail -15; exit 1; }
echo "$GATE: PASS -- template ships enabled:false mode:dry-run and validates; issue_sync unit tests pass"
exit 0
