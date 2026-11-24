#!/usr/bin/env bash
# cm_issue_sync_template_default_off_mutation_test.sh -- §1.1 paired mutation for CM-ISSUE-SYNC-TEMPLATE-DEFAULT-OFF (§11.4.300).
# Plants, in a THROWAWAY copy, each defect and asserts the gate FAILs (or rc 2 for a missing template); asserts the clean copy PASSes.
#   M1 template enabled: true   M2 template mode: apply   M3 unknown key   M4 token value in token_vars   M5 template removed (rc 2)
#   M6 a config.py that stops rejecting unknown keys (a unit test must fail)
# Usage: cm_issue_sync_template_default_off_mutation_test.sh   Exit 0 META PASS, 1 a mutation survived, 2 environment.
# Side-effects: temp dir only.  Classification: universal (§11.4.17).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; SRC="$(cd "$HERE/../.." && pwd)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
fresh() { rm -rf "$W/r"; mkdir -p "$W/r/templates" "$W/r/scripts"; cp "$SRC/templates/workable-items-sync.yaml.template" "$W/r/templates/"; cp -r "$SRC/scripts/issue_sync" "$W/r/scripts/"; find "$W/r" -name __pycache__ -prune -exec rm -rf {} +; }
G="$HERE/cm_issue_sync_template_default_off.sh"; T="$W/r/templates/workable-items-sync.yaml.template"; bad=0
want() { # name expected-rc
  bash "$G" --root "$W/r" >/dev/null 2>&1; rc=$?
  if [ "$rc" -eq "$2" ]; then echo "META OK:   $1 (rc $rc)"; else echo "META FAIL: $1 expected rc $2 got $rc"; bad=1; fi; }
fresh; want "CLEAN passes" 0
fresh; sed -i 's/^enabled: false/enabled: true/' "$T"; want "M1 enabled true" 1
fresh; sed -i 's/^mode: dry-run/mode: apply/' "$T"; want "M2 mode apply" 1
fresh; echo "bogus: 1" >> "$T"; want "M3 unknown key" 1
fresh; sed -i 's/^token_vars: {}/token_vars: {github.com: [ghp_abcdefghijklmnopqrstuvwxyz0123456789]}/' "$T"; want "M4 token value" 1
fresh; rm "$T"; want "M5 template missing" 2
fresh; sed -i 's/if k not in _KEYS:/if False:/' "$W/r/scripts/issue_sync/config.py"; want "M6 validator neutered" 1
if [ "$bad" -eq 0 ]; then echo "META PASS: CM-ISSUE-SYNC-TEMPLATE-DEFAULT-OFF is a genuine gate"; exit 0; fi
exit 1
