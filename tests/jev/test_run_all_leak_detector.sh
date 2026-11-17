#!/usr/bin/env bash
# test_run_all_leak_detector.sh — self-test of the fixture-server leak detector in tests/jev/run_all.sh (round 3, review
# R2-6 / mutant X19). GATE-LOGIC test of the harness itself (§11.4.289(C)(2)), nothing live.
# The repo's run_all.sh is copied into a throwaway harness dir with three tests of its own:
#   L1 golden-bad: a test that leaves a "fixture server" (a process whose argv holds the harness's jev_server.py path)
#      running => run_all FAILs that test, prints LEAK naming the pid, and kills that pid
#   L2 golden-good: a test that leaves nothing => PASS
#   L3 CONTROL NEEDLE: the same harness with the detector blinded (the X19 mutation: the matched path is changed) lets
#      the leaking test PASS and the process survives, so L1 can only pass because the detector really sees the leak
# Every process started here is killed by its recorded pid (it is ours); nothing is matched by pattern.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC2034  # FIXTURES is read by lib_assert.sh
FIXTURES="$HERE/fixtures"
# shellcheck source=lib_assert.sh
source "$HERE/lib_assert.sh"
command -v python3 >/dev/null 2>&1 || { assert_skip "python3 absent"; finish; exit $?; }
[ -r /proc/self/cmdline ] || { assert_skip "/proc unavailable: the detector reads /proc/<pid>/cmdline"; finish; exit $?; }
RUN_ALL="${LEAK_SELFTEST_RUN_ALL:-$HERE/run_all.sh}"
make_fixture_env leak
H="$T/harness"; mkdir -p "$H/fixtures"
cp "$RUN_ALL" "$H/run_all.sh"
printf '# placeholder: only the path matters to the detector\n' > "$H/fixtures/jev_server.py"
SRV="$H/fixtures/jev_server.py"
PIDF="$T/leaked.pid"
# the leaking test: a background process whose argv carries the server path, left running when the test exits
cat > "$H/test_a_leak.sh" <<EOF
#!/usr/bin/env bash
python3 -I -c 'import time; time.sleep(120)' "$SRV" >/dev/null 2>&1 </dev/null &
echo \$! > "$PIDF"
exit 0
EOF
printf '#!/usr/bin/env bash\nexit 0\n' > "$H/test_b_clean.sh"
alive() { [ -n "$1" ] && [ -d "/proc/$1" ] && tr '\0' '\n' < "/proc/$1/cmdline" 2>/dev/null | grep -qxF -- "$SRV"; }
cleanup_leak() { local p; p="$(cat "$PIDF" 2>/dev/null)"; if alive "$p"; then kill "$p" 2>/dev/null; fi; rm -f -- "$PIDF"; }

# L1 + L2: the real detector
bash "$H/run_all.sh" > "$T/r1.out" 2>&1; rc=$?
assert_rc 1 "$rc" "L1 a leaking test makes run_all fail (rc 1)"
assert_contains "$T/r1.out" "FAIL test_a_leak.sh" "L1 the leaking test is reported FAIL"
assert_contains "$T/r1.out" "LEAK: fixture server pid" "L1 the LEAK line is printed"
LP="$(cat "$PIDF" 2>/dev/null)"
assert_contains "$T/r1.out" "pid(s) $LP " "L1 the LEAK line names the leaked pid"
sleep 0.3
if alive "$LP"; then fail "L1 the leaked process is still running (not killed)"; else ok "L1 the leaked process was killed by its pid"; fi
assert_contains "$T/r1.out" "PASS test_b_clean.sh" "L2 golden-good: a test that leaves nothing passes"
cleanup_leak

# L3: control needle, the detector blinded exactly like mutant X19
sed 's|^SRV_PATH="\$HERE/fixtures/jev_server.py"$|SRV_PATH="$HERE/fixtures/jev_server.py.none"|' "$RUN_ALL" > "$H/run_all.sh"
if grep -qF 'jev_server.py.none' "$H/run_all.sh"; then ok "L3 setup: the blinded copy was made"; else fail "L3 setup: the SRV_PATH line was not found (detector moved?)"; fi
bash "$H/run_all.sh" > "$T/r3.out" 2>&1; rc=$?
assert_rc 0 "$rc" "L3 CONTROL: the blinded detector passes the leaking test (so L1 is not passing for another reason)"
LP="$(cat "$PIDF" 2>/dev/null)"
if alive "$LP"; then ok "L3 CONTROL: with the blinded detector the leaked process survives"; else fail "L3 CONTROL: the leaked process is gone without a detector"; fi
cleanup_leak
finish
