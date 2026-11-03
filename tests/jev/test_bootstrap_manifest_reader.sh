#!/usr/bin/env bash
# test_bootstrap_manifest_reader.sh — bootstrap.sh manifest_field reads helix-deps.yaml STRUCTURALLY and fails closed.
# Odd list-item shapes (bare `-`, quoted key, `name :`) must yield the REAL pin; duplicate keys / ambiguous names /
# no PyYAML must STOP the bootstrap (rc 2, nothing cloned) rather than silently use an empty ref.
# BS_SCRIPT overrides the script under test (mutants). Exit 0 iff all assertions hold.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FIXTURES="$HERE/fixtures"
REPO="$(cd "$HERE/../.." && pwd)"
# shellcheck source=lib_assert.sh
source "$HERE/lib_assert.sh"
BS="${BS_SCRIPT:-$REPO/scripts/jev/bootstrap.sh}"

run_with() { # run_with <name> <manifest-text> [extra env assignments...]; sets RC, ERR
  local name="$1" text="$2"; shift 2
  make_fixture_env "$name"; make_fixture_constitution_root
  printf '%s' "$text" > "$JEV_CONSTITUTION_ROOT/helix-deps.yaml"
  env "$@" bash "$BS" --non-interactive --allow-clone >"$T/out" 2>"$T/err"; RC=$?; ERR="$T/err"
}
good_tail='  - name: claude_toolkit
    ssh_url: git@github.com:HelixDevelopment/claude_toolkit.git
    ref: toolkit-v9
    layout: grouped
'
# control: ordinary shape
run_with ctl "$(printf 'schema_version: 1\ndeps:\n  - name: llmctl\n    ssh_url: git@github.com:HelixDevelopment/llmctl.git\n    ref: llm-v9\n    layout: grouped\n%s' "$good_tail")"
assert_rc 0 "$RC" "ctl: ordinary manifest rc 0"
assert_contains "$ERR" "provision llmctl: source=clone" "ctl: llmctl provisioned"
assert_contains "$ERR" "ref=llm-v9 " "ctl: pinned ref read"

# bare dash, then the fields on following lines
run_with bare "$(printf 'schema_version: 1\ndeps:\n  -\n    name: llmctl\n    ssh_url: git@github.com:HelixDevelopment/llmctl.git\n    ref: llm-v9\n    layout: grouped\n%s' "$good_tail")"
assert_rc 0 "$RC" "bare-dash: rc 0"
assert_contains "$ERR" "ref=llm-v9 " "bare-dash: the real pin is read (old awk saw an empty ref -> unpinned)"
# quoted keys
run_with quoted "$(printf 'schema_version: 1\ndeps:\n  - "name": llmctl\n    "ssh_url": git@github.com:HelixDevelopment/llmctl.git\n    "ref": llm-v9\n    layout: grouped\n%s' "$good_tail")"
assert_contains "$ERR" "ref=llm-v9 " "quoted-key: the real pin is read"
# space before colon
run_with spc "$(printf 'schema_version: 1\ndeps:\n  - name : llmctl\n    ssh_url : git@github.com:HelixDevelopment/llmctl.git\n    ref : llm-v9\n    layout: grouped\n%s' "$good_tail")"
assert_contains "$ERR" "ref=llm-v9 " "name-space-colon: the real pin is read"
# quoted VALUES (old tr -d stripped quotes inside the value too)
run_with qval "$(printf 'schema_version: 1\ndeps:\n  - name: llmctl\n    ssh_url: git@github.com:HelixDevelopment/llmctl.git\n    ref: "llm-v9"\n    layout: grouped\n%s' "$good_tail")"
assert_contains "$ERR" "ref=llm-v9 " "quoted-value: the real pin is read"

# fail-closed: duplicate key in the llmctl entry
run_with dup "$(printf 'schema_version: 1\ndeps:\n  - name: llmctl\n    ssh_url: git@github.com:HelixDevelopment/llmctl.git\n    ref: llm-v1\n    ref: llm-v2\n    layout: grouped\n%s' "$good_tail")"
assert_rc 2 "$RC" "dup-key: bootstrap STOPS (rc 2)"
assert_contains "$ERR" "refusing to use an empty pin" "dup-key: refusal message"
assert_not_contains "$ERR" "provision llmctl:" "dup-key: nothing provisioned"
# fail-closed: two entries with the same name = ambiguous
run_with ambig "$(printf 'schema_version: 1\ndeps:\n  - name: llmctl\n    ref: a\n    layout: grouped\n  - name: llmctl\n    ref: b\n    layout: grouped\n%s' "$good_tail")"
assert_rc 2 "$RC" "ambiguous name: STOP (rc 2)"
# fail-closed: unparseable manifest
run_with junk "$(printf 'deps: [unclosed\n  - name: llmctl\n')"
assert_rc 2 "$RC" "unparseable manifest: STOP (rc 2)"
# fail-closed: no PyYAML (simulated by the helper's own test switch)
run_with noyaml "$(printf 'schema_version: 1\ndeps:\n  - name: llmctl\n    ref: llm-v9\n    layout: grouped\n%s' "$good_tail")" HELIX_TEST_MODE=1 HELIX_DEPS_FIELD_FORCE_NO_YAML=1
assert_rc 2 "$RC" "no PyYAML: STOP (rc 2), never an empty ref"
assert_not_contains "$ERR" "provision llmctl:" "no PyYAML: nothing provisioned"
# tool simply not listed: still the documented default (unpinned), NOT an error
run_with absent "$(printf 'schema_version: 1\ndeps:\n%s' "$good_tail")"
assert_rc 0 "$RC" "tool not listed: default behaviour preserved (rc 0)"
assert_contains "$ERR" "ref=unpinned" "tool not listed: unpinned"
finish
