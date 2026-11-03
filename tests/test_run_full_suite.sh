#!/usr/bin/env bash
# tests/test_run_full_suite.sh -- self-test of scripts/run_full_suite.sh (section 11.4.40 runner).
# Oracle strategy: SPECIFIED (the verdict vocabulary, exit-code contract and manifest rules in the
# runner header). Every case builds a synthetic git root under a mktemp dir, writes a manifest
# with the runner's own --generate-manifest, runs the runner against it and asserts the recorded
# verdicts, the exit code and the RESULT line. Golden-good, golden-bad and negative controls
# (golden-FALSE) are marked. Paired mutations: tests/test_run_full_suite_mutations.sh (runs this
# file against mutated copies of the engine; FSR_RUNNER selects the runner under test).
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
R=${FSR_RUNNER:-$HERE/scripts/run_full_suite.sh}
T=$(mktemp -d "${TMPDIR:-/tmp}/rfs_selftest.XXXXXX") || exit 2
: "${T:?}"
export FULL_SUITE_TMPDIR="$T"
. "$HERE/scripts/lib/safe_rm.sh" || exit 2
cleanup() { TMPDIR="$(dirname "$T")" safe_rm_rf "${T:?}" >/dev/null 2>&1; }
trap cleanup EXIT
pass=0; fail=0
ok(){ pass=$((pass+1)); echo "ok   $1"; }
ko(){ fail=$((fail+1)); echo "FAIL $1"; }
chk(){ if [ "$2" = "$3" ]; then ok "$1"; else ko "$1 (want '$3' got '$2')"; fi; }
has(){ if grep -qE -- "$2" "$3" 2>/dev/null; then ok "$1"; else ko "$1 (no /$2/ in $3)"; fi; }
hasnt(){ if grep -qE -- "$2" "$3" 2>/dev/null; then ko "$1 (unexpected /$2/ in $3)"; else ok "$1"; fi; }
gitc(){ git -C "$1" -c user.email=a@b -c user.name=t "${@:2}"; }
mkroot(){ # $1 dir: empty git repo with one commit
  mkdir -p "$1/tests/a" "$1/config"
  git init -q "$1" && gitc "$1" commit -q --allow-empty -m init
}
sut(){ # $1 root $2 rel path, rest: body lines
  local f="$1/$2"; mkdir -p "$(dirname "$f")"; shift 2
  { echo '#!/usr/bin/env bash'; printf '%s\n' "$@"; } > "$f"
}
gen(){ bash "$R" --root "$1" --generate-manifest --write >/dev/null 2>&1; }
run(){ # $1 root $2 out, rest: args -> sets RC, log in $2.log
  local r=$1 o=$2; shift 2
  bash "$R" --root "$r" --out "$o" "$@" >"$o.log" 2>&1; RC=$?
}
verdict(){ # $1 out $2 unit-path -> last verdict|reason|source of that unit
  python3 -I -c 'import json,sys
v=""
for l in open(sys.argv[1]+"/results.jsonl"):
    o=json.loads(l)
    if o["path"]==sys.argv[2]: v="%s|%s|%s" % (o["verdict"],o["reason"],o["verdict_source"])
print(v)' "$1" "$2" 2>/dev/null
}

# --- 1 golden-good: full mode, summary-recognised PASS -> rc 0, OK-FULL
G="$T/good"; mkroot "$G"; sut "$G" tests/a/test_good.sh 'echo "passed=2 failed=0"'
gen "$G"; run "$G" "$T/o_good" --include-heavy
chk "golden-good rc=0" "$RC" "0"
has "golden-good RESULT: OK-FULL" '^RESULT: OK-FULL' "$T/o_good.log"
chk "golden-good verdict from summary" "$(verdict "$T/o_good" tests/a/test_good.sh)" "PASS||summary"

# --- 2 exit-code-only PASS is labelled
sut "$G" tests/a/test_quiet.sh 'echo hello'
gen "$G"; run "$G" "$T/o_quiet" --include-heavy
chk "no summary -> PASS exit-code-only" "$(verdict "$T/o_quiet" tests/a/test_quiet.sh)" "PASS||exit-code-only"
has "exit-code-only counted in RESULT" 'exit-code-only-PASS=1' "$T/o_quiet.log"

# --- 3 rc-0 lies (F2/F10): FAIL lines, zero checks, all skipped, early SKIP lines
B="$T/lie"; mkroot "$B"
sut "$B" tests/a/test_lie_fail.sh 'echo "RESULT: FAIL passed=0 failed=3"'
sut "$B" tests/a/test_lie_counts.sh 'echo "== 1 passed, 2 failed =="'
sut "$B" tests/a/test_zero.sh 'echo "ran 0 tests"'
sut "$B" tests/a/test_zero_kv.sh 'echo "passed=0 failed=0"'
sut "$B" tests/a/test_allskip.sh 'echo "passed=0 failed=0 skipped=3"'
sut "$B" tests/a/test_early_skip.sh 'echo "RESULT: SKIP (one subcase)"' 'echo "RESULT: SKIPPED subcase x"' 'echo "passed=3 failed=0"'
sut "$B" tests/a/test_skipping.sh 'echo "RESULT: SKIPPING"'
sut "$B" tests/a/test_term_skip.sh 'echo "noise"' 'echo "VERDICT: SKIP reason=hardware_not_present"'
sut "$B" tests/a/test_fail_count0.sh 'echo "TOTAL: failed_suites=0"'
gen "$B"; run "$B" "$T/o_lie" --include-heavy --timeout 20
chk "exit0 + RESULT: FAIL -> FAIL" "$(verdict "$T/o_lie" tests/a/test_lie_fail.sh | cut -d'|' -f1)" "FAIL"
chk "exit0 + '2 failed' -> FAIL" "$(verdict "$T/o_lie" tests/a/test_lie_counts.sh)" "FAIL|summary_reports_failures|summary"
chk "exit0 + ran 0 tests -> FAIL zero_checks" "$(verdict "$T/o_lie" tests/a/test_zero.sh)" "FAIL|zero_checks_run|summary"
chk "exit0 + passed=0 failed=0 -> FAIL zero_checks" "$(verdict "$T/o_lie" tests/a/test_zero_kv.sh)" "FAIL|zero_checks_run|summary"
chk "exit0 + all skipped -> SKIP" "$(verdict "$T/o_lie" tests/a/test_allskip.sh)" "SKIP|all_skipped|summary"
chk "golden-FALSE: early SKIP lines, terminal passed=3 -> PASS" "$(verdict "$T/o_lie" tests/a/test_early_skip.sh)" "PASS||summary"
chk "golden-FALSE: terminal SKIPPING is not SKIP" "$(verdict "$T/o_lie" tests/a/test_skipping.sh | cut -d'|' -f1)" "PASS"
chk "exit0 + terminal VERDICT: SKIP -> SKIP with reason" "$(verdict "$T/o_lie" tests/a/test_term_skip.sh)" "SKIP|hardware_not_present|terminal-line"
chk "golden-FALSE: failed_suites=0 only -> PASS" "$(verdict "$T/o_lie" tests/a/test_fail_count0.sh | cut -d'|' -f1)" "PASS"
chk "lies run rc=1" "$RC" "1"

# --- 4 exit codes (F8): SIGKILL at 0 s, own exit 137 / 124 are ERROR, not TIMEOUT; 77 SKIP; 127 ERROR
X="$T/rc"; mkroot "$X"
sut "$X" tests/a/test_sigkill.sh 'kill -9 $$'
sut "$X" tests/a/test_e137.sh 'exit 137'
sut "$X" tests/a/test_e124.sh 'exit 124'
sut "$X" tests/a/test_e77.sh 'echo "VERDICT: SKIP reason=topology_unsupported"' 'exit 77'
sut "$X" tests/a/test_e127.sh 'exit 127'
sut "$X" tests/a/test_e1.sh 'echo "ALL PASS"' 'exit 1'
gen "$X"; run "$X" "$T/o_rc" --include-heavy --timeout 20
chk "SIGKILL at 0 s -> ERROR" "$(verdict "$T/o_rc" tests/a/test_sigkill.sh | cut -d'|' -f1,2)" "ERROR|killed_by_signal_9"
chk "exit 137 without timer -> ERROR" "$(verdict "$T/o_rc" tests/a/test_e137.sh | cut -d'|' -f1,2)" "ERROR|rc_137_without_runner_timeout"
chk "exit 124 without timer -> ERROR" "$(verdict "$T/o_rc" tests/a/test_e124.sh | cut -d'|' -f1,2)" "ERROR|rc_124_without_runner_timeout"
chk "exit 77 -> SKIP reason" "$(verdict "$T/o_rc" tests/a/test_e77.sh | cut -d'|' -f1,2)" "SKIP|topology_unsupported"
chk "exit 127 -> ERROR" "$(verdict "$T/o_rc" tests/a/test_e127.sh | cut -d'|' -f1)" "ERROR"
chk "ALL PASS then exit 1 -> FAIL" "$(verdict "$T/o_rc" tests/a/test_e1.sh | cut -d'|' -f1)" "FAIL"

# --- 5 TIMEOUT only from the timer; a TIMEOUT-only run fails; TERM-ignoring grandchild reaped
TO="$T/to"; mkroot "$TO"; M1="fsrleakT_$$_$RANDOM"
sut "$TO" tests/a/test_slow.sh "bash -c 'trap \"\" TERM; exec -a $M1 sleep 300' </dev/null >/dev/null 2>&1 &" 'sleep 60'
gen "$TO"; run "$TO" "$T/o_to" --include-heavy --timeout 2
chk "sleep past timer -> TIMEOUT" "$(verdict "$T/o_to" tests/a/test_slow.sh | cut -d'|' -f1)" "TIMEOUT"
chk "TIMEOUT-only run rc=1" "$RC" "1"
has "TIMEOUT-only RESULT: FAIL" '^RESULT: FAIL' "$T/o_to.log"
if pgrep -f "$M1" >/dev/null; then ko "TERM-ignoring grandchild survived the timeout"; pkill -9 -f "$M1"; else ok "TERM-ignoring grandchild reaped"; fi

# --- 6 leaks after a normal exit (F11): background child and a setsid escapee are killed and counted
L="$T/leak"; mkroot "$L"; M2="fsrleakA_$$_$RANDOM"; M3="fsrleakB_$$_$RANDOM"
sut "$L" tests/a/test_leak.sh "bash -c 'exec -a $M2 sleep 300' </dev/null >/dev/null 2>&1 &" \
  "setsid bash -c 'trap \"\" TERM; exec -a $M3 sleep 300' </dev/null >/dev/null 2>&1 &" 'echo "passed=1 failed=0"'
gen "$L"; run "$L" "$T/o_leak" --include-heavy --timeout 20
if pgrep -f "$M2" >/dev/null || pgrep -f "$M3" >/dev/null; then ko "leaked processes survived"; pkill -9 -f "$M2"; pkill -9 -f "$M3"; else ok "leaked processes killed"; fi
has "leaks counted in record" '"leaked": [1-9]' "$T/o_leak/results.jsonl"

# --- 7 environment allowlist (F7): ambient variables do not reach the suite; HOME/XDG fresh
E="$T/env"; mkroot "$E"
sut "$E" tests/a/test_env.sh '[ -z "${FSR_PROBE_LEAK+x}" ] || { echo "leak FSR_PROBE_LEAK"; exit 1; }' \
  "[ \"\$HOME\" != \"$HOME\" ] || { echo same-home; exit 1; }" \
  "[ \"\${XDG_CONFIG_HOME:-}\" = \"\$HOME/.config\" ] || { echo xdg; exit 1; }" \
  '[ -n "${FULL_SUITE_UNIT_TOKEN:-}" ] || exit 1' 'echo "passed=4 failed=0"'
gen "$E"; FSR_PROBE_LEAK=1 XDG_CONFIG_HOME=/nonexistent/cfg run "$E" "$T/o_env" --include-heavy --timeout 20
chk "ambient env not passed, fresh HOME/XDG" "$(verdict "$T/o_env" tests/a/test_env.sh | cut -d'|' -f1)" "PASS"
hasnt "variable values are never logged" 'nonexistent/cfg' "$T/o_env.log"
sut "$E" tests/a/test_env2.sh '[ "${FSR_PROBE_LEAK:-}" = 1 ] || exit 1' 'echo "passed=1 failed=0"'
gen "$E"; FSR_PROBE_LEAK=1 run "$E" "$T/o_env2" --include-heavy --timeout 20 --env-extra FSR_PROBE_LEAK
chk "--env-extra passes a named variable" "$(verdict "$T/o_env2" tests/a/test_env2.sh | cut -d'|' -f1)" "PASS"

# --- 8 manifest fail-closed (F1): unlisted file, stale row, unclassifiable go, malformed, heavy rule
M="$T/man"; mkroot "$M"; sut "$M" tests/a/test_one.sh 'echo "passed=1 failed=0"'; gen "$M"
sut "$M" scripts/test_new.sh 'echo "passed=1 failed=0"'
run "$M" "$T/o_man1" --include-heavy
chk "unlisted test file -> exit 3" "$RC" "3"
has "unlisted test file named" 'census file without manifest row: scripts/test_new.sh' "$T/o_man1.log"
if [ -e "$T/o_man1/results.jsonl" ]; then ko "nothing runs on mismatch"; else ok "nothing runs on mismatch"; fi
gen "$M"; rm -f "$M/scripts/test_new.sh"
run "$M" "$T/o_man2" --include-heavy
chk "stale manifest row -> exit 3" "$RC" "3"
gen "$M"; mkdir -p "$M/nomod"; echo 'package x' > "$M/nomod/x_test.go"
run "$M" "$T/o_man3" --include-heavy
chk "Go test file without go.mod -> exit 3" "$RC" "3"
rm -f "$M/nomod/x_test.go"; gen "$M"
printf 'extra\n' >> "$M/config/full_suite_manifest.tsv"
run "$M" "$T/o_man4" --include-heavy
chk "malformed manifest -> exit 3" "$RC" "3"
rm -f "$M/config/full_suite_manifest.tsv"; gen "$M"
sut "$M" tests/a/test_big_mutation.sh 'echo "passed=1 failed=0"'; gen "$M"
python3 -I -c 'import sys
p=sys.argv[1]; L=open(p).read().split("\n")
L=[l.replace("\theavy\t","\tdefault\t") if l.startswith("tests/a/test_big_mutation.sh\t") else l for l in L]
open(p,"w").write("\n".join(L))' "$M/config/full_suite_manifest.tsv"
run "$M" "$T/o_man5" --include-heavy
chk "heavy-looking name declared default -> exit 3" "$RC" "3"
rm -f "$M/tests/a/test_big_mutation.sh" "$M/config/full_suite_manifest.tsv"
sut "$M" tests/q2/test_qd.sh 'echo "passed=1 failed=0"'
sut "$M" tests/q2/run_all.sh 'quick=0; [ "${1:-}" = "--quick" ] && quick=1' 'suites=()' '[ "$quick" = 1 ] || suites+=(test_qd)' 'echo "RUN_ALL: PASS"'
gen "$M"
python3 -I -c 'import sys
p=sys.argv[1]; L=open(p).read().split("\n")
L=[l.replace("\trunall-whole\t-\t","\trunall-quick\t-\t") if l.startswith("tests/q2/run_all.sh\t") else l for l in L]
open(p,"w").write("\n".join(L))' "$M/config/full_suite_manifest.tsv"
run "$M" "$T/o_man6" --include-heavy
chk "runall-quick whose --quick drops a default member -> exit 3" "$RC" "3"
has "quick-dropped default member named" 'default member test_qd.sh is named only inside' "$T/o_man6.log"

# --- 9 run_all policies (F9): whole runs members once; quick passes --quick only in default; members
W="$T/ra"; mkroot "$W"; C="$T/counts"; mkdir -p "$C"
for n in m1 m2; do sut "$W" tests/w/test_$n.sh "echo x >> $C/w_$n" 'echo "passed=1 failed=0"'; done
sut "$W" tests/w/run_all.sh 'h=$(cd "$(dirname "$0")" && pwd)' 'for t in "$h"/test_*.sh; do bash "$t" || exit 1; done' 'echo "ran 2, failed 0"'
sut "$W" tests/q/test_light.sh "echo x >> $C/q_light" 'echo "passed=1 failed=0"'
sut "$W" tests/q/test_q_chaos.sh "echo x >> $C/q_chaos" 'echo "passed=1 failed=0"'
sut "$W" tests/q/run_all.sh "echo \"\$*\" >> $C/q_args" 'quick=0; [ "${1:-}" = "--quick" ] && quick=1' 'suites=(test_light)' \
  '[ "$quick" = 1 ] || suites+=(test_q_chaos)' 'h=$(cd "$(dirname "$0")" && pwd)' 'for s in "${suites[@]}"; do bash "$h/$s.sh" || exit 1; done' 'echo "RUN_ALL: PASS"'
sut "$W" tests/m/test_ml.sh "echo x >> $C/m_light" 'echo "passed=1 failed=0"'
sut "$W" tests/m/test_m_mutants.sh "echo x >> $C/m_heavy" 'echo "passed=1 failed=0"'
sut "$W" tests/m/run_all.sh "echo x >> $C/m_runall" 'h=$(cd "$(dirname "$0")" && pwd)' 'bash "$h/test_ml.sh" && bash "$h/test_m_mutants.sh"' 'echo "RESULT: PASS=2 FAIL=0"'
sut "$W" tests/h/test_h_stress.sh "echo x >> $C/h_stress" 'echo "passed=1 failed=0"'
gen "$W"
python3 -I -c 'import sys
p=sys.argv[1]; L=open(p).read().split("\n")
L=[l.replace("\trunall-members\t-\t","\trunall-quick\t-\t") if l.startswith("tests/q/run_all.sh\t") else l for l in L]
open(p,"w").write("\n".join(L))' "$W/config/full_suite_manifest.tsv"
run "$W" "$T/o_ra_def"
chk "default mode rc=5 (heavy not run)" "$RC" "5"
has "default RESULT: OK-DEFAULT-SET-ONLY" '^RESULT: OK-DEFAULT-SET-ONLY .*not a section 11.4.40 full retest' "$T/o_ra_def.log"
chk "whole run_all: member m1 ran once" "$(wc -l < "$C/w_m1" 2>/dev/null)" "1"
chk "quick run_all got --quick in default mode" "$(cat "$C/q_args" 2>/dev/null)" "--quick"
if [ -e "$C/q_chaos" ]; then ko "heavy quick member not run in default"; else ok "heavy quick member not run in default"; fi
chk "members run_all: light member ran alone once" "$(wc -l < "$C/m_light" 2>/dev/null)" "1"
if [ -e "$C/m_heavy" ] || [ -e "$C/m_runall" ]; then ko "members run_all / heavy member not run in default"; else ok "members run_all / heavy member not run in default"; fi
if [ -e "$C/h_stress" ]; then ko "heavy entry not run in default"; else ok "heavy entry not run in default"; fi
has "heavy entry recorded SKIPPED-heavy" 'SKIPPED-heavy tests/h/test_h_stress.sh' "$T/o_ra_def.log"
run "$W" "$T/o_ra_full" --include-heavy
chk "full mode rc=0" "$RC" "0"
chk "quick run_all without --quick in full mode" "$(sed -n 2p "$C/q_args" 2>/dev/null)x" "x"
chk "full mode heavy quick member ran once" "$(wc -l < "$C/q_chaos" 2>/dev/null)" "1"
chk "full mode members run_all ran once" "$(wc -l < "$C/m_runall" 2>/dev/null)" "1"
chk "full mode light member ran once more (through the run_all)" "$(wc -l < "$C/m_light" 2>/dev/null)" "2"
chk "whole member once per run" "$(wc -l < "$C/w_m1" 2>/dev/null)" "2"

# --- 10 resume (F4/F5): same tree resumes; dirty tree, new sha, corrupt line re-run; --rerun-nonpass
S="$T/res"; mkroot "$S"; CS="$T/cnt_res"
sut "$S" tests/a/test_r.sh "echo x >> $CS" 'echo "passed=1 failed=0"'
sut "$S" tests/a/test_rf.sh "echo x >> $CS.f" 'exit 1'
gen "$S"; gitc "$S" add -A; gitc "$S" commit -q -m s
run "$S" "$T/o_res" --include-heavy
run "$S" "$T/o_res" --include-heavy
chk "resume: second run executes nothing" "$(wc -l < "$CS")" "1"
has "resume reported" 'resumed tests/a/test_r.sh \(PASS\)' "$T/o_res.log"
run "$S" "$T/o_res" --include-heavy --rerun-nonpass
chk "--rerun-nonpass re-executes the FAIL" "$(wc -l < "$CS.f")" "2"
chk "--rerun-nonpass keeps the PASS" "$(wc -l < "$CS")" "1"
echo "# dirty" >> "$S/tests/a/test_r.sh"
run "$S" "$T/o_res" --include-heavy
chk "dirty tree re-runs (same --out)" "$(wc -l < "$CS")" "2"
gitc "$S" commit -q -am dirty2
run "$S" "$T/o_res" --include-heavy
chk "new sha re-runs (same --out)" "$(wc -l < "$CS")" "3"
python3 -I -c 'import sys
p=sys.argv[1]+"/results.jsonl"; L=open(p).read().splitlines()
L=[l for l in L if "\"tests/a/test_r.sh\"" not in l]
L.append("{\"schema\": \"fsr/2\", \"unit\": \"tests/a/test_r.sh\", \"verd")
open(p,"w").write("\n".join(L)+"\n")' "$T/o_res"
run "$S" "$T/o_res" --include-heavy
chk "corrupt record re-runs its unit" "$(wc -l < "$CS")" "4"
has "corrupt record reported" 'invalid result lines ignored=1' "$T/o_res.log"

# --- 11 KNOWN (F3): exact path + signature; golden-FALSE substring path, other signature, doc-only
K="$T/known"; mkroot "$K"
sut "$K" tests/a/test_bad.sh 'echo "boom: lock timeout"' 'exit 1'
sut "$K" tests/b/test_other.sh 'echo "different cause"' 'exit 1'
sut "$K" tests/c/test_docref.sh 'exit 1'
gen "$K"
printf '# path\tsignature\ttracked_id\tnote\ntests/a/test_bad.sh\tlock timeout\tATM-1\topen\nb/test_other.sh\tdifferent cause\tATM-2\tsubstring path\ntests/b/test_other.sh\tlock timeout\tATM-3\tother signature\n' > "$K/config/full_suite_known_failures.tsv"
mkdir -p "$K/docs/design"; printf 'evidence: tests/c/test_docref.sh passed=25 failed=0\n' > "$K/docs/design/known_failures_v73.md"
run "$K" "$T/o_known" --include-heavy
has "exact path + signature -> KNOWN with id" '"known_id": "ATM-1"' "$T/o_known/results.jsonl"
chk "known run rc=1 (two unexplained)" "$RC" "1"
has "golden-FALSE: substring path / other signature not KNOWN" '^FAIL  tests/b/test_other.sh' "$T/o_known/summary.txt"
has "golden-FALSE: path cited only in the markdown doc fails" '^FAIL  tests/c/test_docref.sh' "$T/o_known/summary.txt"
printf 'bad row\n' > "$K/config/full_suite_known_failures.tsv"
run "$K" "$T/o_known2" --include-heavy
chk "malformed known table -> exit 2" "$RC" "2"

# --- 12 partial and usage (F6, F12, F15)
run "$G" "$T/o_only" --include-heavy --only 'test_good'
chk "--only run -> PARTIAL rc=4" "$RC" "4"
has "PARTIAL RESULT line" '^RESULT: PARTIAL' "$T/o_only.log"
run "$G" "$T/o_t0" --timeout 0
chk "--timeout 0 refused" "$RC" "2"
run "$G" "$G/inside_out"
chk "--out inside the root refused" "$RC" "2"
if [ -e "$G/inside_out" ]; then ko "inside --out not created"; else ok "inside --out not created"; fi

# --- 13 Go module unit
if command -v go >/dev/null 2>&1; then
  Gm="$T/gomod"; mkroot "$Gm"; mkdir -p "$Gm/m"
  printf 'module example.com/m\n\ngo 1.21\n' > "$Gm/m/go.mod"
  printf 'package m\nfunc Add(a, b int) int { return a + b }\n' > "$Gm/m/m.go"
  printf 'package m\nimport "testing"\nfunc TestAdd(t *testing.T) { if Add(1, 2) != 3 { t.Fatal("bad") } }\n' > "$Gm/m/m_test.go"
  gen "$Gm"; run "$Gm" "$T/o_go" --include-heavy --timeout 300
  chk "go module unit PASS from ok line" "$(verdict "$T/o_go" m)" "PASS||summary"
else
  echo "SKIP go module unit (go not installed)"
fi

echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
