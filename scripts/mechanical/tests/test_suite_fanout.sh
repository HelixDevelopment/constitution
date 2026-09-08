#!/usr/bin/env bash
# test_suite_fanout.sh — tests for suite_fanout.sh.
#
# The load-bearing cases are the ones where a fan-out lies: a suite that could
# not be measured must not be tabulated as a pass, and a baseline comparison
# must notice a suite that vanished as well as one whose numbers moved.
set -uo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/lib/assert.sh"
FANOUT="$TESTS_DIR/../suite_fanout.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
TREE="$TMP/tree"; mkdir -p "$TREE/t"

printf 'printf "5 passed, 0 failed\\n"\n'            > "$TREE/t/a.sh"
printf 'printf "3 passed, 0 failed\\n"\n'            > "$TREE/t/b.sh"
printf 'printf "2 failed, 1 passed\\n"; exit 1\n'    > "$TREE/t/red.sh"
printf 'printf "no summary here\\n"\n'               > "$TREE/t/mute.sh"
printf 'sleep 30\n'                                  > "$TREE/t/slow.sh"

it "all-green fan-out exits 0 and tabulates each suite"
assert_rc 0 "$FANOUT" --tree "$TREE" --out "$TMP/base.tsv" t/a.sh t/b.sh
assert_contains "$LAST_OUT" "t/a.sh" "suite a listed"
assert_contains "$LAST_OUT" "failing=0" "failing count reported"

it "the results file is machine-readable and carries the counts"
assert_eq "t/a.sh	0	5	0" "$(head -1 "$TMP/base.tsv")" "TSV row for suite a"

it "a failing suite is a FINDING (exit 1), not an instrument failure"
assert_rc 1 "$FANOUT" --tree "$TREE" t/a.sh t/red.sh
assert_contains "$LAST_OUT" "failing=1" "one failing suite"

it "an unmeasurable suite CANNOT RUN (exit 2) and is never counted as a pass"
assert_rc 2 "$FANOUT" --tree "$TREE" t/a.sh t/mute.sh
assert_contains "$LAST_OUT" "UNPARSED" "the unmeasured suite is named"
assert_contains "$LAST_OUT" "INSTRUMENT FAILURE" "and called what it is"

it "a timed-out suite CANNOT RUN (exit 2), not 'failing'"
assert_rc 2 "$FANOUT" --tree "$TREE" --timeout 2 t/slow.sh
assert_contains "$LAST_OUT" "TIMEOUT" "timeout reported"

it "a baseline with nothing moved reports no deltas and exits 0"
assert_rc 0 "$FANOUT" --tree "$TREE" --baseline "$TMP/base.tsv" t/a.sh t/b.sh
assert_contains "$LAST_OUT" "no deltas" "no deltas"

it "a moved count is reported as CHANGED and is a finding"
printf 'printf "4 passed, 1 failed\\n"; exit 1\n' > "$TREE/t/a.sh"
assert_rc 1 "$FANOUT" --tree "$TREE" --baseline "$TMP/base.tsv" t/a.sh t/b.sh
assert_contains "$LAST_OUT" "CHANGED  t/a.sh" "the moved suite is named"
assert_contains "$LAST_OUT" "passed 5->4" "the movement is quantified"
printf 'printf "5 passed, 0 failed\\n"\n' > "$TREE/t/a.sh"

it "a baselined suite that was NOT run is reported MISSING, not silently dropped"
assert_rc 1 "$FANOUT" --tree "$TREE" --baseline "$TMP/base.tsv" t/a.sh
assert_contains "$LAST_OUT" "MISSING  t/b.sh" "the absent suite is named"

it "a suite absent from the baseline is reported NEW"
assert_rc 1 "$FANOUT" --tree "$TREE" --baseline "$TMP/base.tsv" t/a.sh t/b.sh t/red.sh
assert_contains "$LAST_OUT" "NEW      t/red.sh" "the new suite is named"

it "--suites-from reads a list file and ignores comments"
{ printf '# comment\n\n'; printf 't/a.sh\n'; printf 't/b.sh\n'; } > "$TMP/list.txt"
assert_rc 0 "$FANOUT" --tree "$TREE" --suites-from "$TMP/list.txt"
assert_contains "$LAST_OUT" "suites=2" "two suites read from the list"

it "argument validation is CANNOT_RUN"
assert_rc 2 "$FANOUT" --tree "$TREE"
assert_rc 2 "$FANOUT" --tree "$TMP/nope" t/a.sh
assert_rc 2 "$FANOUT" --tree "$TREE" t/does-not-exist.sh
assert_rc 2 "$FANOUT" --tree "$TREE" --baseline "$TMP/no-such-baseline" t/a.sh
assert_rc 2 "$FANOUT" --tree "$TREE" --timeout soon t/a.sh

summary
