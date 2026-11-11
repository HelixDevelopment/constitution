#!/bin/sh
# Purpose: prove that case C2a of test_precheck_slicer_red.sh asserts a REAL
# shellcheck finding (CON-099 F099-2, F099-3; section 11.4.276(D): the reviewer's
# mutants adopted verbatim and shown to fail the suite). Each mutant runs the
# test on a scratch copy of scripts/fastcycle and must make C2a FAIL (rc 1), except
# the honest-skip case, which must PASS with a SKIP line.
#   M1 blind:    no user bus, so the pack's shellcheck leg lints 0 files (BLIND)
#   M2 nodefect: the planted SC2086 defect is removed from the fixture
#   M3 nosc:     shellcheck is not on PATH (pack reports an honest skip) -> PASS + SKIP
#   M4 carrier:  the pack's output holds SC2086 only in its config echo (findings
#                emptied) -> FAIL; built with a stub pack, so it is a gate-logic
#                case (section 11.4.289(C)(2)), not live evidence
#   B0 baseline: unmutated run -> PASS
# C2A_TEST_UNDER=<file> replaces the test file in the copy, to show a mutant
# surviving an older version (RED before the fix).
# Usage: test_precheck_slicer_c2a_mutants.sh   Exit: 0 all as expected, 1 not, 2 setup.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
FC=$(cd "$HERE/.." && pwd)
TEST_UNDER=${C2A_TEST_UNDER:-$HERE/test_precheck_slicer_red.sh}
[ -f "$TEST_UNDER" ] || { echo "no test file: $TEST_UNDER" >&2; exit 2; }
FAIL=0; PASS=0
ok()  { PASS=$((PASS+1)); echo "PASS: $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL: $1"; }
TMP=$(mktemp -d) || { echo "mktemp -d failed" >&2; exit 2; }
[ -n "$TMP" ] && [ -d "$TMP" ] || exit 2
cleanup() { [ -n "${TMP:-}" ] && case $TMP in /*/tmp.*|/*/*.*) rm -rf -- "${TMP:?}" ;; esac; }
trap cleanup EXIT

mk() { # mk <name> -> fresh copy at $TMP/<name>/scripts/fastcycle
  mkdir -p "$TMP/$1/scripts" && cp -R "$FC" "$TMP/$1/scripts/fastcycle" || exit 2
  cp "$TEST_UNDER" "$TMP/$1/scripts/fastcycle/tests/test_precheck_slicer_red.sh"
  echo "$TMP/$1/scripts/fastcycle"
}
run() { # run <copy> [env args...] ; output in $TMP/out
  _c=$1; shift
  env "$@" sh "$_c/tests/test_precheck_slicer_red.sh" >"$TMP/out" 2>&1
  return $?
}
c2a_line() { grep -c "^FAIL: C2a" "$TMP/out"; }

# a clean user-bus environment is needed for the real shellcheck leg to lint
BASEENV="PATH=$PATH HOME=${HOME:-/nonexistent}"
[ -n "${XDG_RUNTIME_DIR:-}" ] && BASEENV="$BASEENV XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR"
[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ] && BASEENV="$BASEENV DBUS_SESSION_BUS_ADDRESS=$DBUS_SESSION_BUS_ADDRESS"

# control needle: with shellcheck on PATH the baseline must lint (else M1/M2 prove nothing)
c=$(mk b0)
# shellcheck disable=SC2086
run "$c" $BASEENV; rc=$?
if [ "$rc" -eq 0 ] && grep -q "^PASS: C2a" "$TMP/out" && ! grep -q "^SKIP: C2a" "$TMP/out"; then
  ok "B0 baseline: C2a passes on a real finding"
elif command -v shellcheck >/dev/null 2>&1; then
  bad "B0 baseline: rc=$rc, C2a did not pass with shellcheck present (BLIND host? then M1/M2 prove nothing)"
  sed -n '/C2a/,+3p' "$TMP/out"
else
  echo "SKIP: shellcheck is not on PATH here; B0, M1, M2, M4 cannot be exercised, M3 only"
  NOSC=1
fi

if [ -z "${NOSC:-}" ]; then
  # M1 blind: no user bus
  c=$(mk m1)
  run "$c" -i "PATH=$PATH" "HOME=$TMP/m1"; rc=$?
  if [ "$rc" -ne 0 ] && [ "$(c2a_line)" -ge 1 ]; then ok "M1 blind shellcheck leg (files_linted 0): C2a FAILs"
  else bad "M1 blind: rc=$rc c2a_fail=$(c2a_line) -- the test accepted a BLIND shellcheck leg"; fi

  # M2 nodefect: quote the variable in the planted file
  c=$(mk m2)
  f="$c/tests/fixtures/precheck_slicer/case2_lint_in_pack/unquoted_var_gate.sh"
  sed 's|^cat \$STAGE_DIR/file.txt$|cat "$STAGE_DIR/file.txt"|' "$f" > "$f.new" && mv "$f.new" "$f"
  # control: the mutated fixture must no longer carry an unquoted expansion
  if shellcheck -s sh -f gcc "$f" 2>/dev/null | grep -q SC2086; then
    bad "M2 setup: the mutated fixture still has SC2086"
  else
    # shellcheck disable=SC2086
    run "$c" $BASEENV; rc=$?
    if [ "$rc" -ne 0 ] && [ "$(c2a_line)" -ge 1 ]; then ok "M2 planted defect removed: C2a FAILs"
    else bad "M2 nodefect: rc=$rc c2a_fail=$(c2a_line) -- the test accepted a pack with no SC2086 finding"; fi
  fi

  # M4 carrier: a stub pack that prints the config echo but no finding
  c=$(mk m4)
  cat > "$c/review/precheck_pack.sh" <<'STUB'
#!/bin/sh
# gate-logic stub: parse leg real-looking, shellcheck leg with config echo only
out=""; while [ $# -gt 0 ]; do [ "$1" = "--out" ] && out=$2; shift; done
cat > "$out" <<'JSON'
{"all_pass": false, "checks": [
 {"check": "parse", "verdict": "FAIL", "evidence": {"failures": [{"file": "x.sh", "message": "Syntax error: end of file"}]}},
 {"check": "shellcheck", "verdict": "FAIL", "evidence": {"counts": {"files_linted": 2, "findings": 0},
  "findings": [], "tool": {"severity_floor": {"blocking_info_rules": ["SC2086"]}}}}]}
JSON
exit 1
STUB
  run "$c" $BASEENV; rc=$?
  if [ "$rc" -ne 0 ] && [ "$(c2a_line)" -ge 1 ]; then ok "M4 SC2086 only in the config echo: C2a FAILs"
  else bad "M4 carrier: rc=$rc c2a_fail=$(c2a_line) -- the test matched the config echo"; fi
fi

# M3 nosc: shellcheck absent from PATH
if PATH=/usr/bin:/bin command -v shellcheck >/dev/null 2>&1; then
  echo "SKIP: M3 -- shellcheck exists in /usr/bin:/bin on this host, cannot hide it"
else
  c=$(mk m3)
  run "$c" -i "PATH=/usr/bin:/bin" "HOME=$TMP/m3"; rc=$?
  if [ "$rc" -eq 0 ] && grep -q "^SKIP: C2a" "$TMP/out" && [ "$(c2a_line)" -eq 0 ]; then
    ok "M3 shellcheck not on PATH: C2a SKIPs the shellcheck leg and the test passes"
  else bad "M3 nosc: rc=$rc -- expected PASS with a SKIP line (F099-3)"; sed -n '/C2a/,+3p' "$TMP/out"; fi
fi

echo "== Summary: ok $PASS / NOT ok $FAIL =="
[ "$FAIL" -eq 0 ]
