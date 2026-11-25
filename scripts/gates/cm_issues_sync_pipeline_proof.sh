#!/usr/bin/env bash
# cm_issues_sync_pipeline_proof.sh -- CM-ISSUES-SYNC-PIPELINE-PROOF gate (anchor §11.4.300, facade + inbound C7, section 1.1 paired mutations).
# Purpose: runs `scripts/issues_sync_pipeline.sh --prove-failure` (24 controls + 21 mutations over an in-memory tracker double: outbound leak, inbound
#   instruction-following, a silently applied conflict, a printed token, a copied secret, a re-imported owned issue, ignored dry-run, an overwritten
#   reviewed proposal, an unconfined proposal path, a tracker edit not classed as conflict) and the pipeline unit tests, and, when a `docs_chain`
#   binary is available (DOCS_CHAIN_BIN or PATH), that the shipped templates/docs_chain/issues-sync.yaml passes `docs_chain doctor`.
#   Without docs_chain the doctor step prints NOTE and is NOT counted as a pass of that step (the gate still reports what it ran).
# Usage: cm_issues_sync_pipeline_proof.sh [--root DIR]   Exit: 0 PASS, 1 a mutation survived / test failed / template invalid, 2 python3 or PyYAML missing.
# Side-effects: none (temp dir only). The double proves THIS tool's logic only, never a host's behaviour (§11.4.289). Classification: universal (§11.4.17).
set -u
GATE="CM-ISSUES-SYNC-PIPELINE-PROOF"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
while [ $# -gt 0 ]; do case "$1" in --root) ROOT="$2"; shift 2 ;; *) echo "$GATE: unknown argument $1" >&2; exit 2 ;; esac; done
command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' 2>/dev/null || { echo "$GATE: BLIND -- python3/PyYAML missing" >&2; exit 2; }
out=$(bash "$ROOT/scripts/issues_sync_pipeline.sh" --prove-failure 2>&1) || { echo "$GATE: FAIL -- prove-failure:"; printf '%s\n' "$out" | tail -25; exit 1; }
t=$(cd "$ROOT/scripts" && python3 -W ignore -m unittest discover -s issue_sync/tests_pipeline 2>&1) || { echo "$GATE: FAIL -- unit tests"; printf '%s\n' "$t" | tail -15; exit 1; }
dc="${DOCS_CHAIN_BIN:-$(command -v docs_chain 2>/dev/null || true)}"; note="docs_chain doctor of the template NOT RUN (no docs_chain binary)"
if [ -n "$dc" ] && [ -x "$dc" ]; then
  d=$(mktemp -d); trap 'rm -rf "$d"' EXIT
  bash "$ROOT/scripts/issues_sync_pipeline.sh" init-context --root "$d" --owner-repo github.com/o/r --write >/dev/null 2>&1
  dout=$("$dc" doctor --root "$d" issues-sync 2>&1) || { echo "$GATE: FAIL -- template is not a valid Docs Chain context:"; printf '%s\n' "$dout" | tail -10; exit 1; }
  note="docs_chain doctor of the template passes"
fi
echo "$GATE: PASS -- $(printf '%s\n' "$out" | tail -1); unit tests pass; $note"
