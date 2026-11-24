#!/usr/bin/env bash
# cm_issue_sync_template_default_off_mutation_test.sh -- §1.1 paired mutation for CM-ISSUE-SYNC-TEMPLATE-DEFAULT-OFF (§11.4.300).
# Plants, in a THROWAWAY copy, each defect and asserts the gate FAILs (or rc 2 for a missing template); asserts the clean copy PASSes.
#   M1 template enabled: true   M2 template mode: apply   M3 unknown key   M4 token value in token_vars   M5 template removed (rc 2)
#   M6 a config.py that stops rejecting unknown keys (a unit test must fail)   M7 duplicate key   M8 YAML 1.1 bare boolean
# Usage: cm_issue_sync_template_default_off_mutation_test.sh   Exit 0 META PASS, 1 a mutation survived, 2 environment.
# Side-effects: temp dir only.  Classification: universal (§11.4.17).
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; SRC="$(cd "$HERE/../.." && pwd)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
fresh() { rm -rf "$W/r"; mkdir -p "$W/r/templates" "$W/r/scripts" "$W/r/config"; cp "$SRC/templates/workable-items-sync.yaml.template" "$W/r/templates/"; cp -r "$SRC/config/forge" "$W/r/config/"; cp -r "$SRC/scripts/issue_sync" "$W/r/scripts/"; find "$W/r" -name __pycache__ -prune -exec rm -rf {} +; }
G="$HERE/cm_issue_sync_template_default_off.sh"; T="$W/r/templates/workable-items-sync.yaml.template"; bad=0
want() { # name expected-rc [expected message fragment]: the gate must fail for the RIGHT reason, not merely exit non-zero
  out=$(bash "$G" --root "$W/r" 2>&1); rc=$?
  if [ "$rc" -ne "$2" ]; then echo "META FAIL: $1 expected rc $2 got $rc: $(printf '%s' "$out" | tail -3)"; bad=1
  elif [ -n "${3:-}" ] && ! printf '%s' "$out" | grep -qF -- "$3"; then echo "META FAIL: $1 rc $rc but message lacks '$3': $(printf '%s' "$out" | tail -3)"; bad=1
  else echo "META OK:   $1 (rc $rc${3:+, message has '$3'})"; fi; }
fresh; want "CLEAN passes" 0 "PASS --"
fresh; sed -i 's/^enabled: false/enabled: true/' "$T"; want "M1 enabled true" 1 "template ships enabled != false"
fresh; sed -i 's/^mode: dry-run/mode: apply/' "$T"; want "M2 mode apply" 1 "template ships mode != dry-run"
fresh; echo "bogus: 1" >> "$T"; want "M3 unknown key" 1 "unknown key: bogus"
fresh; sed -i 's/^token_vars: {}/token_vars: {github.com: [ghp_abcdefghijklmnopqrstuvwxyz0123456789]}/' "$T"; want "M4 token value" 1 "not a variable NAME"
fresh; rm "$T"; want "M5 template missing" 2 "template missing"
fresh; sed -i 's/if k not in _KEYS:/if False:/' "$W/r/scripts/issue_sync/config.py"; want "M6 validator neutered" 1 "unit tests"
fresh; printf 'enabled: true\n' >> "$T"; want "M7 duplicate key (last wins) in template" 1 "duplicate key"
fresh; sed -i 's/^enabled: false/enabled: yes/' "$T"; want "M8 YAML 1.1 boolean in template" 1 "enabled must be a boolean"
if [ "$bad" -eq 0 ]; then echo "META PASS: CM-ISSUE-SYNC-TEMPLATE-DEFAULT-OFF is a genuine gate"; exit 0; fi
exit 1
