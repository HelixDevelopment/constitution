#!/usr/bin/env bash
# cm_issue_sync_verifier_proof.sh -- CM-ISSUE-SYNC-VERIFIER-PROOF gate (anchor §11.4.300(E), section 1.1 paired mutation).
# Purpose: runs `scripts/verify_issues_sync.sh --prove-failure` and the issue_sync unit tests: the control mirror must verify 0 and every mutation
#   (deleted issue, edited title, wrongly closed/reopened issue, duplicate key, stripped footer, corrupted hash, DB change without sync, orphan,
#   stripped labels, redaction canary, private-to-public target, 429 everywhere, unreadable repo) must flip the verdict to its expected non-zero code.
# Usage: cm_issue_sync_verifier_proof.sh [--root DIR]   Exit: 0 PASS, 1 a mutation survived / test failed, 2 python3 or PyYAML missing.
# Side-effects: none (temp dir only). Classification: universal (§11.4.17).
set -u
GATE="CM-ISSUE-SYNC-VERIFIER-PROOF"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
while [ $# -gt 0 ]; do case "$1" in --root) ROOT="$2"; shift 2 ;; *) echo "$GATE: unknown argument $1" >&2; exit 2 ;; esac; done
command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' 2>/dev/null || { echo "$GATE: BLIND -- python3/PyYAML missing" >&2; exit 2; }
out=$(bash "$ROOT/scripts/verify_issues_sync.sh" --prove-failure 2>&1) || { echo "$GATE: FAIL -- prove-failure:"; printf '%s\n' "$out" | tail -25; exit 1; }
t=$(cd "$ROOT/scripts" && python3 -W ignore -m unittest discover -s issue_sync/tests 2>&1) || { echo "$GATE: FAIL -- unit tests"; printf '%s\n' "$t" | tail -15; exit 1; }
echo "$GATE: PASS -- $(printf '%s\n' "$out" | tail -1); unit tests pass"
