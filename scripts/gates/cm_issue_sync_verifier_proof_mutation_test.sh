#!/usr/bin/env bash
# cm_issue_sync_verifier_proof_mutation_test.sh -- §1.1 paired mutation for CM-ISSUE-SYNC-VERIFIER-PROOF (§11.4.300).
# In a throwaway copy: V1 verifier that always reports in sync (engine drift list emptied) MUST FAIL the gate; V2 the verifier ignoring titles
# MUST FAIL; V3 blocked/unconfirmed legs treated as pass MUST FAIL; the clean copy MUST PASS. Exit 0 META PASS, 1 survivor.
# Side-effects: temp dir only. Classification: universal (§11.4.17).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; SRC="$(cd "$HERE/../.." && pwd)"; W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT; bad=0
fresh() { rm -rf "$W/r"; mkdir -p "$W/r/scripts/gates" "$W/r/config"; cp -r "$SRC/config/forge" "$W/r/config/"; cp -r "$SRC/scripts/issue_sync" "$SRC/scripts/verify_issues_sync.sh" "$W/r/scripts/"; cp "$SRC/scripts/gates/cm_issue_sync_verifier_proof.sh" "$W/r/scripts/gates/"; find "$W/r" -name __pycache__ -prune -exec rm -rf {} +; }
want() { bash "$W/r/scripts/gates/cm_issue_sync_verifier_proof.sh" --root "$W/r" >/dev/null 2>&1; rc=$?; if [ "$rc" -eq "$2" ]; then echo "META OK:   $1 (rc $rc)"; else echo "META FAIL: $1 expected rc $2 got rc $rc"; bad=1; fi; }
E="$W/r/scripts/issue_sync/engine.py"
fresh; want "CLEAN passes" 0
fresh; sed -i 's/    if drift:/    drift = []\n    if drift:/' "$E"; want "V1 verifier always in sync" 1
fresh; sed -i 's/cur\["title"\] != want_title or//' "$E"; want "V2 verifier ignores titles" 1
fresh; sed -i 's/    if und:\n        return 2, und/XX/; s/^    if und:$/    if False:/' "$E"; want "V3 undetermined legs pass" 1
[ "$bad" -eq 0 ] && { echo "META PASS: CM-ISSUE-SYNC-VERIFIER-PROOF is a genuine gate"; exit 0; }; exit 1
