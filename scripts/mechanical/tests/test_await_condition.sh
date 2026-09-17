#!/usr/bin/env bash
# test_await_condition.sh — tests for await_condition.sh.
#
# The one property worth testing hardest is that a TIMEOUT can never be read as
# success: it has its own exit code (3), its own outcome word, and a test that
# asserts both. Everything else about a poll loop is uninteresting; that part is
# where waiting silently becomes "it finished".
set -uo pipefail
TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$TESTS_DIR/lib/assert.sh"
AWAIT="$TESTS_DIR/../await_condition.sh"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

it "a condition that already holds is SATISFIED, exit 0"
assert_rc 0 "$AWAIT" --until 'true' --timeout 5 --interval 1 --label always --quiet
assert_contains "$LAST_OUT" "AWAIT always: SATISFIED" "outcome line"

it "a condition that never holds is TIMEOUT with its OWN exit code (3), not 0 and not 1"
assert_rc 3 "$AWAIT" --until 'false' --timeout 2 --interval 1 --label never --quiet
assert_contains "$LAST_OUT" "AWAIT never: TIMEOUT" "outcome line says TIMEOUT"
assert_contains "$LAST_OUT" "condition never held" "and says so in words"
assert_not_contains "$LAST_OUT" "SATISFIED" "a timeout never prints SATISFIED"

it "a condition that becomes true DURING the wait is SATISFIED"
( sleep 2; printf 'ready\n' > "$TMP/flag" ) &
helper=$!
assert_rc 0 "$AWAIT" --until "test -f $TMP/flag" --timeout 20 --interval 1 --label late --quiet
wait "$helper" 2>/dev/null || true
assert_contains "$LAST_OUT" "SATISFIED" "satisfied after waiting"

it "--pid-gone observes a process ending (and never signals it)"
( sleep 2 ) & target=$!
assert_rc 0 "$AWAIT" --pid-gone "$target" --timeout 20 --interval 1 --label proc --quiet
assert_contains "$LAST_OUT" "SATISFIED" "process observed gone"

it "--pid-gone on a live long process times out rather than claiming success"
( sleep 30 ) & live=$!
assert_rc 3 "$AWAIT" --pid-gone "$live" --timeout 2 --interval 1 --label busy --quiet
kill "$live" 2>/dev/null || true
wait "$live" 2>/dev/null || true
assert_contains "$LAST_OUT" "TIMEOUT" "still running is not done"

it "--log-contains matches a pattern in a growing log"
printf 'starting up\n' > "$TMP/run.log"
( sleep 2; printf 'BUILD COMPLETE\n' >> "$TMP/run.log" ) & lw=$!
assert_rc 0 "$AWAIT" --log-contains "$TMP/run.log" --pattern 'BUILD COMPLETE' --timeout 20 --interval 1 --label log --quiet
wait "$lw" 2>/dev/null || true

it "--log-contains on a file that never gets the line is TIMEOUT"
assert_rc 3 "$AWAIT" --log-contains "$TMP/run.log" --pattern 'NEVER APPEARS' --timeout 2 --interval 1 --label nolog --quiet

it "--log-contains on a missing file waits, then TIMEOUTs (it does not crash or pass)"
assert_rc 3 "$AWAIT" --log-contains "$TMP/no-such.log" --pattern 'x' --timeout 2 --interval 1 --label missing --quiet

it "--timeout 0 evaluates once without waiting"
assert_rc 0 "$AWAIT" --until 'true' --timeout 0 --interval 1 --quiet
assert_rc 3 "$AWAIT" --until 'false' --timeout 0 --interval 1 --quiet

it "the outcome line reports elapsed time and poll count"
assert_rc 3 "$AWAIT" --until 'false' --timeout 2 --interval 1 --label counted --quiet
assert_contains "$LAST_OUT" "polls=" "poll count reported"

it "argument validation is CANNOT_RUN (2), distinct from TIMEOUT (3)"
assert_rc 2 "$AWAIT" --timeout 5
assert_rc 2 "$AWAIT" --until 'true' --pid-gone 1
assert_rc 2 "$AWAIT" --until 'true' --timeout later
assert_rc 2 "$AWAIT" --until 'true' --interval 0
assert_rc 2 "$AWAIT" --pid-gone not-a-pid
assert_rc 2 "$AWAIT" --log-contains "$TMP/run.log"
assert_rc 2 "$AWAIT" --bogus

summary
