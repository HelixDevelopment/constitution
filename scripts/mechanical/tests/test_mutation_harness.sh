#!/usr/bin/env bash
# test_mutation_harness.sh — tests for mutation_harness.sh.
#
# Hermetic: builds its own miniature source tree and its own suites, so it makes
# no claim about, and has no dependency on, any real project's test harness.
#
# The tests are organised around the harness's failure paths, because those are
# where a mutation loop bluffs: a mutation that did not apply, a suite that could
# not be parsed, a suite that timed out, and an env knob the suite never reads
# all produce confident, wrong greens when the loop is run by hand.
set -uo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/lib/assert.sh"
source "$TESTS_DIR/../lib/mech_common.sh"
HARNESS="$TESTS_DIR/../mutation_harness.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TREE="$TMP/tree"
mkdir -p "$TREE/tests"

printf 'VALUE=1\n' > "$TREE/code.sh"

# A suite with teeth: it reads the tree it lives in and grades VALUE.
cat > "$TREE/tests/suite.sh" <<'S'
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$DIR/../code.sh"
if [ "$VALUE" = "1" ]; then printf '2 passed, 0 failed\n'; exit 0
else printf '1 failed, 1 passed\n'; exit 1; fi
S

# A blind suite: green no matter what the code says. This is the shape §1.1
# exists to expose, and the harness must report it as a VIOLATION.
cat > "$TREE/tests/blind.sh" <<'S'
printf '2 passed, 0 failed\n'
S

# A suite that prints no summary at all.
cat > "$TREE/tests/mute.sh" <<'S'
printf 'I ran. I will not tell you how it went.\n'
S

# A suite that never finishes.
cat > "$TREE/tests/slow.sh" <<'S'
sleep 30
printf '1 passed, 0 failed\n'
S

# A suite that honours an env knob redirecting it at another tree.
cat > "$TREE/tests/knobbed.sh" <<'S'
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${FAKE_TREE_DIR:-$DIR/..}"
. "$ROOT/code.sh"
if [ "$VALUE" = "1" ]; then printf '2 passed, 0 failed\n'; exit 0
else printf '1 failed, 1 passed\n'; exit 1; fi
S

TREE_FP_START="$(mech_fingerprint_tree "$TREE")"

it "baseline: an unmutated tree reports EXPECTED-PASS and exits 0"
assert_rc 0 "$HARNESS" --tree "$TREE" --suite tests/suite.sh --name BASE --expect pass
assert_contains "$LAST_OUT" "EXPECTED-PASS got 0 failed / 2 passed [OK]" "baseline verdict line"
assert_contains "$LAST_OUT" "replacements=0" "no mutation applied on a baseline run"

it "a mutation the suite catches is OK and exits 0"
assert_rc 0 "$HARNESS" --tree "$TREE" --suite tests/suite.sh --name M1 \
  --file code.sh --from 'VALUE=1' --to 'VALUE=999'
assert_contains "$LAST_OUT" "MUTATION M1: EXPECTED-FAIL got 1 failed / 1 passed [OK]" "verdict line"
assert_contains "$LAST_OUT" "replacements=1" "the mutation applied exactly once"

it "counts are read by LABEL, so the swapped failure order is not transposed"
assert_contains "$LAST_OUT" "1 failed / 1 passed" "failed count first, as the tool prints it"
assert_contains "$LAST_OUT" "parsed_line=1 failed, 1 passed" "the audited source line"

it "a mutation the suite does NOT catch is a VIOLATION and exits 1"
assert_rc 1 "$HARNESS" --tree "$TREE" --suite tests/blind.sh --name M2 \
  --file code.sh --from 'VALUE=1' --to 'VALUE=999'
assert_contains "$LAST_OUT" "[VIOLATION]" "blind suite is reported, not excused"

it "a mutation whose --from is absent CANNOT RUN (never reported as a green suite)"
assert_rc 2 "$HARNESS" --tree "$TREE" --suite tests/suite.sh --name M3 \
  --file code.sh --from 'THIS_TEXT_IS_NOT_THERE' --to 'x'
assert_contains "$LAST_OUT" "did not apply" "the harness says why"
assert_not_contains "$LAST_OUT" "[OK]" "no verdict is emitted for an unapplied mutation"

it "a suite with no parseable summary CANNOT RUN (exit 2, not 0)"
assert_rc 2 "$HARNESS" --tree "$TREE" --suite tests/mute.sh --name M4 --expect pass
assert_contains "$LAST_OUT" "UNPARSEABLE" "the harness names the instrument failure"

it "a suite that exceeds --timeout CANNOT RUN (exit 2, not a failure result)"
assert_rc 2 "$HARNESS" --tree "$TREE" --suite tests/slow.sh --name M5 --timeout 2
assert_contains "$LAST_OUT" "TIMEOUT" "a timeout is reported as a timeout"
assert_not_contains "$LAST_OUT" "EXPECTED-FAIL got" "a timeout is not counted as a caught mutation"

it "THE SILENT-GREEN TRAP: an env knob the suite never reads is REFUSED"
assert_rc 2 "$HARNESS" --tree "$TREE" --suite tests/suite.sh --name M6 \
  --file code.sh --from 'VALUE=1' --to 'VALUE=999' --env-knob WRONG_KNOB_NAME
assert_contains "$LAST_OUT" "does not read" "the harness refuses rather than testing the real tree"

it "an env knob the suite DOES read is accepted and redirects the suite"
assert_rc 0 "$HARNESS" --tree "$TREE" --suite tests/knobbed.sh --name M7 \
  --file code.sh --from 'VALUE=1' --to 'VALUE=999' --env-knob FAKE_TREE_DIR
assert_contains "$LAST_OUT" "mode=env-knob:FAKE_TREE_DIR" "mode is reported"
assert_contains "$LAST_OUT" "EXPECTED-FAIL got 1 failed / 1 passed [OK]" "the mutated copy was graded"

it "argument validation is CANNOT_RUN, never a silent default"
assert_rc 2 "$HARNESS" --tree "$TMP/no-such-tree" --suite tests/suite.sh
assert_rc 2 "$HARNESS" --tree "$TREE" --suite tests/no-such-suite.sh
assert_rc 2 "$HARNESS" --tree "$TREE" --suite tests/suite.sh --file no-such-file.sh --from a --to b
assert_rc 2 "$HARNESS" --tree "$TREE" --suite tests/suite.sh --expect maybe
assert_rc 2 "$HARNESS" --suite tests/suite.sh
assert_rc 2 "$HARNESS" --tree "$TREE" --suite tests/suite.sh --timeout later
assert_rc 2 "$HARNESS" --tree "$TREE" --suite tests/suite.sh --bogus-flag

it "a suite that WRITES into the original tree is caught, and the paths are named"
# env-knob mode runs the suite where it lives, so a suite that writes an artifact
# beside itself modifies the ORIGINAL tree. The harness must refuse to report a
# result AND say which files to put back — a bare "something changed" is not
# actionable when the tree belongs to someone else.
cat > "$TREE/tests/writer.sh" <<'S'
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${FAKE_TREE_DIR:-$DIR/..}"
printf 'artifact written at run time
' > "$DIR/../generated-proof.txt"
. "$ROOT/code.sh"
if [ "$VALUE" = "1" ]; then printf '2 passed, 0 failed
'; exit 0
else printf '1 failed, 1 passed
'; exit 1; fi
S
assert_rc 2 "$HARNESS" --tree "$TREE" --suite tests/writer.sh --name W1   --file code.sh --from 'VALUE=1' --to 'VALUE=999' --env-knob FAKE_TREE_DIR
assert_contains "$LAST_OUT" "SOURCE-TREE MODIFIED" "the write is detected"
assert_contains "$LAST_OUT" "CHANGED PATHS" "and the paths are listed"
assert_contains "$LAST_OUT" "generated-proof.txt" "the specific file is named"
assert_not_contains "$LAST_OUT" "EXPECTED-FAIL got" "no result is reported from a run that dirtied the tree"
rm -f "$TREE/tests/writer.sh" "$TREE/generated-proof.txt"

it "env-knob mode warns UP FRONT that the suite executes in the original tree"
assert_rc 0 "$HARNESS" --tree "$TREE" --suite tests/knobbed.sh --name W2   --file code.sh --from 'VALUE=1' --to 'VALUE=999' --env-knob FAKE_TREE_DIR
assert_contains "$LAST_OUT" "executes the suite inside" "the warning is emitted before the run"

it "the SOURCE TREE is byte-identical after every run above (§11.4.119)"
assert_eq "$TREE_FP_START" "$(mech_fingerprint_tree "$TREE")" "tree fingerprint unchanged"

it "the harness reports the fingerprint it verified"
assert_rc 0 "$HARNESS" --tree "$TREE" --suite tests/suite.sh --name BASE2
assert_contains "$LAST_OUT" "tree_fingerprint_unchanged=$TREE_FP_START" "fingerprint is published, not just checked"

summary
