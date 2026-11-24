#!/usr/bin/env bash
# cm_issue_sync_verifier_proof_mutation_test.sh -- §1.1 paired mutation for CM-ISSUE-SYNC-VERIFIER-PROOF (§11.4.300).
# In a throwaway copy: V1 verifier that always reports in sync (engine drift list emptied) MUST FAIL the gate; V2 the verifier ignoring titles
# MUST FAIL; V3 blocked/unconfirmed legs treated as pass MUST FAIL; V4-V14 visibility, proof, decision, routing, corpus, config and adoption mutations MUST FAIL; the clean copy MUST PASS. Exit 0 META PASS, 1 survivor.
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
# V4..V13: safety-critical engine mutations (visibility, capability proof, apply decision, routing, private corpus, strict config). Each is a python
# string replace that MUST change the file (the helper asserts the needle exists, so a refactor cannot turn a mutation into a no-op).
mut() { # file needle replacement
  python3 - "$1" "$2" "$3" <<'PY' || { echo "META FAIL: mutation needle not found in $1: $2"; bad=1; return 1; }
import sys
p, a, b = sys.argv[1:4]; s = open(p).read()
if a not in s: sys.exit(1)
open(p, "w").write(s.replace(a, b))
PY
}
I="$W/r/scripts/issue_sync"
fresh; mut "$I/visibility.py" 'if owner_vis == "private" and target_vis == "public":' 'if False:' && want "V4 private-to-public rule removed" 1
fresh; mut "$I/visibility.py" ' or tuple(owner_repo[1:]) != tuple(target_repo[1:])' '' && want "V5 owning-repo equality removed" 1
fresh; mut "$I/visibility.py" 'if owner_vis == "undetermined" or target_vis == "undetermined" or' 'if False and' && want "V6 undetermined visibility passes" 1
fresh; mut "$I/adapters/base.py" '        if proven:' '        if True:' && want "V7 write verbs enabled without proof" 1
fresh; mut "$I/cli.py" 'why = _decision_problem(a.config, cfg["apply_decision"])' 'why = None' && want "V8 apply_decision not checked" 1
fresh; mut "$I/cli.py" '(not has_table and single)' 'not has_table' && want "V9 table-less multi-prefix DB routed to the owner" 1
fresh; mut "$I/adapters/gitlab.py" '{"private": True, "public": False}.get(vis)' '(vis != "public") if vis else None' && want "V10 GitLab internal treated as private" 1
fresh; mut "$I/cli.py" 'issues, fps, all_ids)' 'issues, None, all_ids)' && want "V11 private corpus not passed to the engine" 1
fresh; mut "$I/payload.py" 'fps = set(fingerprint_set or ()) | own_private_fingerprints(item, k)' 'fps = set(fingerprint_set or ())' && want "V12 item's own private fields not fingerprinted" 1
fresh; mut "$I/config.py" '        if dup:' '        if False:' && want "V13 duplicate YAML keys accepted" 1
fresh; mut "$I/engine.py" 'if not FOOTER.search(cur.get("body") or ""):' 'if False:' && want "V14 unkeyed title match adopted and overwritten" 1
[ "$bad" -eq 0 ] && { echo "META PASS: CM-ISSUE-SYNC-VERIFIER-PROOF is a genuine gate"; exit 0; }; exit 1
