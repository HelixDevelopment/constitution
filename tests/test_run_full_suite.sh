#!/usr/bin/env bash
# tests/test_run_full_suite.sh — self-test of scripts/run_full_suite.sh (§11.4.40 runner).
# Oracle strategy: SPECIFIED (verdict vocabulary + exit-code contract in the runner header).
# Golden-good (all PASS -> rc 0), golden-bad (a FAIL -> rc!=0), negative control
# (a SKIP must never be counted PASS and never fail the run), heavy exclusion,
# TIMEOUT, ERROR, KNOWN matching, resume. Runs the runner against a synthetic root.
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
R="$HERE/scripts/run_full_suite.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/rfs_selftest.XXXXXX") || exit 2
: "${T:?}"
pass=0; fail=0
ok(){ pass=$((pass+1)); echo "ok   $1"; }
ko(){ fail=$((fail+1)); echo "FAIL $1"; }
chk(){ if [ "$2" = "$3" ]; then ok "$1"; else ko "$1 (want '$3' got '$2')"; fi; }
mkroot(){ # $1 dir
  mkdir -p "$1/tests/a" "$1/scripts/gates" "$1/docs/design"
  printf '#!/usr/bin/env bash\necho hi\nexit 0\n' > "$1/tests/a/test_good.sh"
  git -C "$1" init -q 2>/dev/null; git -C "$1" -c user.email=a@b -c user.name=t commit -q --allow-empty -m i 2>/dev/null
}
cnt(){ grep -c "\"verdict\":\"$2\"" "$1/results.jsonl" 2>/dev/null; }

# --- golden-good
G="$T/good"; mkroot "$G"
bash "$R" --root "$G" --out "$G/out" --timeout 20 >"$T/good.log" 2>&1; rc=$?
chk "golden-good rc=0" "$rc" "0"
chk "golden-good one PASS" "$(cnt "$G/out" PASS)" "1"

# --- golden-bad + negative controls
B="$T/bad"; mkroot "$B"
printf '#!/usr/bin/env bash\nexit 1\n' > "$B/tests/a/test_bad.sh"
printf '#!/usr/bin/env bash\necho "VERDICT: SKIP reason=hardware_not_present"\nexit 77\n' > "$B/tests/a/test_skip.sh"
printf '#!/usr/bin/env bash\nsleep 30\n' > "$B/tests/a/test_slow.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$B/scripts/gates/cm_x_mutation_test.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$B/scripts/gates/cm_y_selftest.sh"
bash "$R" --root "$B" --out "$B/out" --timeout 2 >"$T/bad.log" 2>&1; rc=$?
[ "$rc" -ne 0 ] && ok "golden-bad rc!=0 ($rc)" || ko "golden-bad rc!=0"
chk "bad: FAIL=1" "$(cnt "$B/out" FAIL)" "1"
chk "bad: TIMEOUT=1" "$(cnt "$B/out" TIMEOUT)" "1"
chk "bad: SKIP=1 (not PASS)" "$(cnt "$B/out" SKIP)" "1"
chk "bad: PASS=2 (good + selftest only)" "$(cnt "$B/out" PASS)" "2"
grep -q 'cm_x_mutation_test.sh.*SKIPPED-heavy\|SKIPPED-heavy.*cm_x_mutation_test.sh' "$B/out/summary.txt" && ok "heavy listed as SKIPPED-heavy" || ko "heavy listed"
grep -q '"suite":"scripts/gates/cm_x_mutation_test.sh"' "$B/out/results.jsonl" && ok "heavy recorded in jsonl" || ko "heavy recorded"
grep -q 'hardware_not_present' "$B/out/results.jsonl" && ok "SKIP reason code kept" || ko "SKIP reason"

# --- ERROR: non-runnable (empty log + unreadable) -> ERROR
E="$T/err"; mkroot "$E"; printf '#!/usr/bin/env bash\nexit 127\n' > "$E/tests/a/test_nf.sh"
bash "$R" --root "$E" --out "$E/out" --timeout 5 >/dev/null 2>&1; rc=$?
chk "exit 127 -> ERROR" "$(cnt "$E/out" ERROR)" "1"
[ "$rc" -ne 0 ] && ok "ERROR rc!=0" || ko "ERROR rc!=0"

# --- KNOWN: FAIL listed in known-failures doc -> rc 0, counted KNOWN
K="$T/known"; mkroot "$K"; printf '#!/usr/bin/env bash\nexit 1\n' > "$K/tests/a/test_bad.sh"
printf '| tests/a/test_bad.sh | known |\n' > "$K/docs/design/known_failures_v73.md"
bash "$R" --root "$K" --out "$K/out" --timeout 5 --known "$K/docs/design/known_failures_v73.md" >"$T/k.log" 2>&1; rc=$?
chk "known FAIL rc=0" "$rc" "0"
grep -q '"known":true' "$K/out/results.jsonl" && ok "known flag in jsonl" || ko "known flag"
grep -q 'KNOWN' "$K/out/summary.txt" && ok "KNOWN in summary" || ko "KNOWN in summary"

# --- resume: second run executes nothing new
bash "$R" --root "$B" --out "$B/out" --timeout 2 >"$T/bad2.log" 2>&1
chk "resume keeps record count" "$(wc -l < "$B/out/results.jsonl")" "6"
grep -q 'resumed' "$T/bad2.log" && ok "resume reported" || ko "resume reported"

# --- --heavy includes mutation suite
bash "$R" --root "$B" --out "$B/out2" --timeout 2 --heavy >/dev/null 2>&1
chk "--heavy runs mutation suite (PASS=3)" "$(cnt "$B/out2" PASS)" "3"

# --- HOME isolation: suite must see a fresh HOME, not the caller's
H="$T/home"; mkroot "$H"; printf '#!/usr/bin/env bash\n[ "$HOME" != "%s" ] && exit 0\nexit 1\n' "$HOME" > "$H/tests/a/test_home.sh"
bash "$R" --root "$H" --out "$H/out" --timeout 5 >/dev/null 2>&1
chk "HOME isolated" "$(cnt "$H/out" FAIL)" "0"
echo "passed=$pass failed=$fail"
rm -rf "${T:?}"
[ "$fail" -eq 0 ]
