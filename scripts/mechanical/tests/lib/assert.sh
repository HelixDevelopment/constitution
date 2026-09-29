#!/usr/bin/env bash
# assert.sh — minimal assertion helpers for the mechanical-tools test suites.
#
# Deliberately self-contained (§11.4.28): these tools are inherited by reference
# into projects that have their own, different test harnesses, so their tests
# may not depend on any consumer project's harness.
#
# Emits [PASS]/[FAIL] lines and a summary in the order-independent shape the
# tools themselves parse — which also makes the suites their own smoke test for
# mech_parse_summary.
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_FAILURES=()
CURRENT_TEST="(none)"

it() { CURRENT_TEST="$*"; printf '\n  • %s\n' "$CURRENT_TEST"; }

_pass() { TESTS_PASSED=$((TESTS_PASSED+1)); printf '    [PASS] %s\n' "$1"; }
_fail() {
  TESTS_FAILED=$((TESTS_FAILED+1))
  TESTS_FAILURES+=("$CURRENT_TEST :: $1")
  printf '    [FAIL] %s\n' "$1"
  [ -n "${2:-}" ] && printf '           %s\n' "$2"
  return 0
}

assert_eq() {
  local want="$1" got="$2" msg="${3:-equality}"
  if [ "$want" = "$got" ]; then _pass "$msg ($want)"; else _fail "$msg" "want=$want got=$got"; fi
}

assert_contains() {
  local hay="$1" needle="$2" msg="${3:-contains}"
  case "$hay" in *"$needle"*) _pass "$msg: '$needle'" ;;
                 *) _fail "$msg" "'$needle' not in: $hay" ;; esac
}

assert_not_contains() {
  local hay="$1" needle="$2" msg="${3:-does not contain}"
  case "$hay" in *"$needle"*) _fail "$msg" "'$needle' unexpectedly present in: $hay" ;;
                 *) _pass "$msg: '$needle' absent" ;; esac
}

# assert_rc EXPECTED CMD... — run CMD, compare exit code. Captures output into
# $LAST_OUT so a test can assert on both the code and what was printed.
LAST_OUT=""
assert_rc() {
  local want="$1"; shift
  LAST_OUT="$("$@" 2>&1)"; local rc=$?
  if [ "$rc" -eq "$want" ]; then _pass "exit $want: $1"
  else _fail "exit code" "want=$want got=$rc cmd=$* out=$LAST_OUT"; fi
}

summary() {
  echo
  if [ "$TESTS_FAILED" -eq 0 ]; then
    printf '%d passed, 0 failed\n' "$TESTS_PASSED"
    return 0
  fi
  printf '%d failed, %d passed\n' "$TESTS_FAILED" "$TESTS_PASSED"
  printf 'Failures:\n'
  local f
  for f in "${TESTS_FAILURES[@]}"; do printf '  - %s\n' "$f"; done
  return 1
}
