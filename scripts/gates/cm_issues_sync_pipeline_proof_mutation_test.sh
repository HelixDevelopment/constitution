#!/usr/bin/env bash
# cm_issues_sync_pipeline_proof_mutation_test.sh -- §1.1 paired mutation for CM-ISSUES-SYNC-PIPELINE-PROOF (§11.4.300 facade + inbound C7).
# In a throwaway copy: P1 the apply conflict guard removed, P2 tracker text rendered outside a fence, P3 the secret scan removed from inbound text,
# P4 pull ignoring dry-run, P5 a footer-keyed (engine-owned) issue re-imported, P6 proposals overwritten, P7 the facade printing the token value,
# P8 the template edited into an invalid Docs Chain context (only when docs_chain is available) MUST FAIL the gate; the clean copy MUST PASS.
# Exit 0 META PASS, 1 survivor. Side-effects: temp dir only. Classification: universal (§11.4.17).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; SRC="$(cd "$HERE/../.." && pwd)"; W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT; bad=0
fresh() { rm -rf "$W/r"; mkdir -p "$W/r/scripts/gates" "$W/r/config" "$W/r/templates"; cp -r "$SRC/config/forge" "$W/r/config/"; cp -r "$SRC/templates/docs_chain" "$W/r/templates/"
  cp -r "$SRC/scripts/issue_sync" "$SRC/scripts/issues_sync_pipeline.sh" "$W/r/scripts/"; cp "$SRC/scripts/gates/cm_issues_sync_pipeline_proof.sh" "$W/r/scripts/gates/"; find "$W/r" -name __pycache__ -prune -exec rm -rf {} +; }
want() { bash "$W/r/scripts/gates/cm_issues_sync_pipeline_proof.sh" --root "$W/r" >/dev/null 2>&1; rc=$?; if [ "$rc" -eq "$2" ]; then echo "META OK:   $1 (rc $rc)"; else echo "META FAIL: $1 expected rc $2 got rc $rc"; bad=1; fi; }
mut() { python3 - "$1" "$2" "$3" <<'PY' || { echo "META FAIL: mutation needle not found in $1: $2"; bad=1; return 1; }
import sys
p, a, b = sys.argv[1:4]; s = open(p).read()
if a not in s: sys.exit(1)
open(p, "w").write(s.replace(a, b))
PY
}
I="$W/r/scripts/issue_sync"
fresh; want "CLEAN passes" 0
fresh; mut "$I/pipeline.py" '        bad = guard_conflicts(rest, **kw)' '        bad = []' && want "P1 conflict guard removed" 1
fresh; mut "$I/inbound.py" 'return "%stext\n%s\n%s" % (f, text, f)' 'return text' && want "P2 tracker text not fenced" 1
fresh; mut "$I/inbound.py" '    if hits:
        return "[withheld' '    if False:
        return "[withheld' && want "P3 secret scan removed" 1
fresh; mut "$I/inbound.py" '        if write:
            os.makedirs' '        if True:
            os.makedirs' && want "P4 pull ignores dry-run" 1
fresh; mut "$I/inbound.py" '        if footer:
            owned += 1' '        if False:
            owned += 1' && want "P5 owned issue re-imported" 1
fresh; mut "$I/inbound.py" 'with open(path, "x") as f:' 'with open(path, "w") as f:' && mut "$I/inbound.py" '        if os.path.exists(path):
            res["kept"]' '        if False:
            res["kept"]' && want "P6 reviewed proposal overwritten" 1
fresh; mut "$I/pipeline.py" '    return "%s: %s" % (name or "|".join(token_vars), st)' '    return "%s: %s %s" % (name or "|".join(token_vars), st, _)' && want "P7 token value printed" 1
if [ -n "${DOCS_CHAIN_BIN:-$(command -v docs_chain 2>/dev/null || true)}" ]; then fresh; mut "$W/r/templates/docs_chain/issues-sync.yaml" 'edges:' 'edgez:' && want "P8 template invalid as a Docs Chain context" 1; else echo "META NOTE: P8 skipped (no docs_chain binary)"; fi
[ "$bad" -eq 0 ] && echo "META PASS" || { echo "META FAIL"; exit 1; }
