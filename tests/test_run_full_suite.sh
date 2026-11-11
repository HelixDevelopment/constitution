#!/usr/bin/env bash
# tests/test_run_full_suite.sh -- self-test of scripts/run_full_suite.sh (section 11.4.40 runner).
# Oracle strategy: SPECIFIED (the verdict vocabulary, exit-code contract and manifest rules in the
# runner header). Every case builds a synthetic git root under a mktemp dir, writes a manifest
# with the runner's own --generate-manifest, runs the runner against it and asserts the recorded
# verdicts, the exit code and the RESULT line. Section P drives the engine's pure functions
# (verdict parser, shell-invocation model, deletion guard) directly through importlib, table
# driven, with golden-good, golden-bad and negative-control (golden-FALSE) rows. Paired
# mutations: tests/test_run_full_suite_mutations.sh (runs this file against mutated copies of
# the engine; FSR_RUNNER selects the runner under test). Every failing check prints a line that
# starts with `FAIL ` (the mutation harness counts a kill only when such a line exists).
set -u
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
R=${FSR_RUNNER:-$HERE/scripts/run_full_suite.sh}
ENGINE="$(cd "$(dirname "$R")" && pwd)/full_suite/run_full_suite.py"
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
roster(){ # $1 root, rest: operator ids -> committed config/full_suite_operators.roster
  local r=$1; shift; mkdir -p "$r/config"
  { echo '# id<TAB>who'; for i in "$@"; do printf '%s\toperator %s\n' "$i" "$i"; done; } > "$r/config/full_suite_operators.roster"
  gitc "$r" add config/full_suite_operators.roster && gitc "$r" commit -q -m roster
}
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
vfy(){ # $1 root $2 logfile -> RC of --verify-manifest
  bash "$R" --root "$1" --verify-manifest >"$2" 2>&1; RC=$?
}
setrow(){ # $1 manifest $2 path $3 replacement row (TAB separated, given with literal \t)
  python3 -I -c 'import sys
p,path,row=sys.argv[1],sys.argv[2],sys.argv[3].replace("\\t","\t")
L=open(p).read().split("\n")
L=[row if l.split("\t")[0]==path else l for l in L]
open(p,"w").write("\n".join(L))' "$@"
}
verdict(){ # $1 out $2 unit-path -> FINAL verdict|reason|source of that unit (summary.txt, else last record)
  python3 -I -c 'import json,sys
v=""
for l in open(sys.argv[1]+"/results.jsonl"):
    o=json.loads(l)
    if o.get("path")==sys.argv[2]: v="%s|%s|%s" % (o["verdict"],o["reason"],o["verdict_source"])
print(v)' "$1" "$2" 2>/dev/null
}
rec(){ # $1 out $2 unit-path $3 field -> that field of the last record of the unit
  python3 -I -c 'import json,sys
v=""
for l in open(sys.argv[1]+"/results.jsonl"):
    o=json.loads(l)
    if o.get("path")==sys.argv[2]: v=str(o.get(sys.argv[3]))
print(v)' "$1" "$2" "$3" 2>/dev/null
}

# =========================================================================== P: pure functions
python3 -I - "$ENGINE" "$T/punit" <<'PY'
import importlib.util, os, sys
spec = importlib.util.spec_from_file_location("fsr", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
scratch = sys.argv[2]; os.makedirs(scratch, exist_ok=True)
NF = [0]
def ok(n): print("ok   " + n)
def ko(n): NF[0] += 1; print("FAIL " + n)
def chk(n, got, want):
    (ok if got == want else (lambda x: ko(x + " (want %r got %r)" % (want, got))))(n)

# --- P1 verdict parser (review round 3 P1-P3/P9; round 4 replaced the line-PREFIX rule with a
# structural summary-line model). Families measured in this repository's own suite logs
# (author run of 2026-11-04, 182 rc-0 logs, every last line classified), the reviewer's
# false-PASS / false-FAIL shapes in both directions, and the common external families
# (pytest, CTest, mocha, bats, TAP). Rows: (text, verdict, reason or None = not checked, source).
J = [
 # golden-good: repository families -> PASS from the summary line
 ("RESULT: PASS=10 FAIL=0", "PASS", "", "summary"),
 ("== RESULT: 39 passed, 0 failed ==", "PASS", "", "summary"),
 ("RESULT: pass=64 fail=0", "PASS", "", "summary"),
 ("RESULT: e2e pass=21 fail=0 skip=0", "PASS", "", "summary"),
 ("SELFCHECK\tSUMMARY\tpass=8 fail=0 refusals_observed=1", "PASS", "", "summary"),
 ("== cli-agent-plugins summary: 16 passed, 0 failed, 0 finding(s) ==", "PASS", "", "summary"),
 ("== summary: PASS=2 FAIL=0 SKIP=0 (evidence: /x/y) ==", "PASS", "", "summary"),
 ("RESULT: 14 PASS / 0 FAIL   [evidence: /x/y]", "PASS", "", "summary"),
 ("twins: PASS=16 FAIL=0\nRESULT: PASS", "PASS", "", "summary"),
 ("RESULT: 10 passed, 0 failed\nOK", "PASS", "", "summary"),
 ("SUMMARY cases=91 failed=0", "PASS", "", "summary"),
 ("----\nRan 42 tests in 18.958s\n\nOK", "PASS", "", "summary"),
 ("== Summary: ok 6 / NOT ok 0 ==", "PASS", "", "summary"),
 ("== T1 RED summary: ok 3 / NOT ok 0 ==", "PASS", "", "summary"),
 ("SUMMARY mutants=26 killed=26 survivors=0 not_applicable=0", "PASS", "", "summary"),
 ("TOTAL 3 failed 0", "PASS", "", "summary"),
 ("TOTAL=5 PASSED=5 FAILED=0", "PASS", "", "summary"),
 ("ran 2, failed 0", "PASS", "", "summary"),
 ("RESULT: PASS (3 of 3)", "PASS", "", "summary"),
 ("RESULT: PASS (all 5 cases)", "PASS", "", "summary"),
 ("SUMMARY: 12 pass-lines / FAIL=0 of 12 assertions", "PASS", "", "summary"),
 ("SUMMARY: 5 pass / 0 fail / 1 skip of 6 assertions", "PASS", "", "summary"),
 ("test_real_agents: 3 passed, 0 failed, 1 skipped; kimi=1.2.3 crush=v0.1", "PASS", "", "summary"),
 ("unit: PASS 3 FAIL 0", "PASS", "", "summary"),
 ("=== R1 GUARD (R1-IN): ALL CHECKS PASS ===", "PASS", "", "summary"),
 ("TOTAL: failed_suites=0", "PASS", "", "summary"),
 ("ok   mutation detected\nRESULT: PASS", "PASS", "", "summary"),
 # golden-good: external families
 ("===== 3 passed in 0.12s =====", "PASS", "", "summary"),
 ("100% tests passed, 0 tests failed out of 5", "PASS", "", "summary"),
 ("  3 passing (5ms)", "PASS", "", "summary"),
 ("5 tests, 0 failures", "PASS", "", "summary"),
 ("1..2\nok 1 - a\nok 2 - b", "PASS", "", "summary"),
 # golden-FALSE: passing check lines quoting fail words are description, never counted (P1 false-FAIL side)
 ("PASS: B M9 shape (5 FAIL + 56 no-verdict) -> exit 1\n----\nRESULT: PASS=5 FAIL=0", "PASS", "", "summary"),
 ("ok 3 - handles (2 failed) input\nRESULT: PASS=3 FAIL=0", "PASS", "", "summary"),
 ("  PASS: indented (5 FAIL)\nRESULT: PASS=5 FAIL=0", "PASS", "", "summary"),
 ("pass: lower (5 FAIL)\nRESULT: PASS=5 FAIL=0", "PASS", "", "summary"),
 ("[PASS] bracket (5 failed)\nRESULT: PASS=5 FAIL=0", "PASS", "", "summary"),
 ("✓ tick (2 failed)\nRESULT: PASS=5 FAIL=0", "PASS", "", "summary"),
 ("ok: colon (2 failed)\nRESULT: PASS=5 FAIL=0", "PASS", "", "summary"),
 ("OK shape (2 failed)\nRESULT: PASS=5 FAIL=0", "PASS", "", "summary"),
 ("PASSED: shape (3 failures)\nRESULT: PASS=5 FAIL=0", "PASS", "", "summary"),
 ("killed M1 (5 failing check(s))\nSUMMARY mutants=1 killed=1 survivors=0 not_applicable=0", "PASS", "", "summary"),
 ("RESULT: SKIP (one subcase)\nRESULT: SKIPPED subcase x\npassed=3 failed=0", "PASS", "", "summary"),
 # golden-bad: summary shapes behind a passing-looking prefix (P1 false-PASS side)
 ("PASS: 3, FAIL: 1", "FAIL", "summary_reports_failures", "summary"),
 ("PASS: total=5 failed=2", "FAIL", "summary_reports_failures", "summary"),
 ("PASS: checks=5 fail=1", "FAIL", "summary_reports_failures", "summary"),
 ("PASS: 10 tests run, 3 failed", "FAIL", "summary_reports_failures", "summary"),
 ("ok - 3 passed, 2 failed", "FAIL", "summary_reports_failures", "summary"),
 ("PASS: B M9 shape (5 FAIL + 56 no-verdict)\nRESULT: PASS=4 FAIL=1", "FAIL", "summary_reports_failures", "summary"),
 # P2: ANSI colour, OSC titles and CR progress overwrites are stripped before parsing
 ("\x1b[31mfailed=2\x1b[0m passed=3", "FAIL", "summary_reports_failures", "summary"),
 ("\x1b]0;title\x07\x1b[1;32mpassed=3 failed=0\x1b[0m", "PASS", "", "summary"),
 ("progress 10%\rprogress 100%\rpassed=3 failed=1", "FAIL", "summary_reports_failures", "summary"),
 ("passed=3 failed=0\r", "PASS", "", "summary"),
 # P3: a fail word with no bound number, or the CTest / mocha / bats / pytest fail forms, never PASS
 ("1 tests failed out of 5", "FAIL", "summary_reports_failures", "summary"),
 ("100% tests passed, 1 tests failed out of 5", "FAIL", "summary_reports_failures", "summary"),
 ("PASS (3 checks)\nFAIL (2 checks)", "FAIL", "summary_word_FAIL", "summary"),
 ("FAIL (2 checks)", "FAIL", "summary_word_FAIL", "summary"),
 ("  1 failing", "FAIL", "summary_reports_failures", "summary"),
 ("5 tests, 1 failure", "FAIL", "summary_reports_failures", "summary"),
 ("===== 3 passed, 1 failed in 0.12s =====", "FAIL", "summary_reports_failures", "summary"),
 ("1..3\nok 1 - a\nnot ok 2 - b\nok 3", "FAIL", "tap_not_ok", "summary"),
 ("1 passed, 0 failed, a failure was logged", "ERROR", "unparsed_fail_signal", "summary"),
 ("RESULT: PASS=3 FAIL=0\nFATAL: teardown crashed", "ERROR", "fail_signal_after_summary", "summary"),
 # golden-bad: FAIL however it is spelled
 ("Failed tests: 3", "FAIL", None, "summary"),
 ("Result: FAIL", "FAIL", "summary_word_FAIL", "summary"),
 ("result: fail", "FAIL", "summary_word_FAIL", "summary"),
 ("SUMMARY cases=7 failed=1", "FAIL", "summary_reports_failures", "summary"),
 ("== Summary: ok 7 / NOT ok 1 ==", "FAIL", "summary_reports_failures", "summary"),
 ("SUMMARY: regression check FAILED -- see NOT ok lines above", "FAIL", "summary_word_FAIL", "summary"),
 ("SUMMARY: FAILURES present", "FAIL", "summary_word_FAIL", "summary"),
 ("not ok 3 - x\n1..3\n# fail 1", "FAIL", None, "summary"),
 ("== 1 passed, 2 failed ==", "FAIL", "summary_reports_failures", "summary"),
 ("Tests: 3 failed", "FAIL", None, "summary"),
 ("RESULT: FAIL passed=0 failed=3", "FAIL", None, "summary"),
 ("RESULT: PASS\nVERDICT: FAIL", "FAIL", "summary_word_FAIL", "summary"),
 ("RESULT: 3 PASS / 1 FAIL", "FAIL", "summary_reports_failures", "summary"),
 ("SUMMARY fails=9 P1b P1c", "ERROR", "unparsed_fail_signal", "summary"),
 ("PASS: widget saw 2 failed probes", "ERROR", "unparsed_fail_signal", "summary"),
 # ERROR: zero tests, inconsistent or conflicting summaries
 ("A: failed=2\nB: passed=3 failed=0", "ERROR", "conflicting_summary", "summary"),
 ("RESULT: PASS (0 of 0)", "ERROR", "zero_tests", "summary"),
 ("ran 0 tests", "ERROR", "zero_tests", "summary"),
 ("passed=0 failed=0", "ERROR", "zero_tests", "summary"),
 ("passed=3 failed=0 total=2", "ERROR", "inconsistent_counts", "summary"),
 ("passed=3 failed=0\nVERDICT: SKIP reason=x", "ERROR", "conflicting_summary", "summary"),
 ("passed=3 failed=0\nSKIP: tail case", "ERROR", "conflicting_summary", "summary"),
 # SKIP (P9: an honest skip summary is SKIP, not ERROR zero_tests)
 ("SUMMARY pass=0 fail=0 (SKIPPED, environment gap)", "SKIP", "suite_reported_skip", "summary"),
 ("passed=0 failed=0 skipped=3", "SKIP", "all_skipped", "summary"),
 ("noise\nVERDICT: SKIP reason=hardware_not_present", "SKIP", "hardware_not_present", "summary"),
 ("SKIP: systemd --user bus unreachable (reason: topology_unsupported)", "SKIP", "topology_unsupported", "summary"),
 ("SKIP - submodules not checked out (nothing to exclude)", "SKIP", "suite_reported_skip", "summary"),
 ("RESULT: SKIPPING", "PASS", "", "exit-code-only"),
 # window (X3): the summary five lines before the end still decides
 ("RESULT: PASS=0 FAIL=3\nnoise a\nnoise b\nnoise c\nnoise d", "FAIL", "summary_reports_failures", "summary"),
 # negative controls: no summary at all -> labelled exit-code-only, never hidden
 ("hello", "PASS", "", "exit-code-only"),
 ("GREEN: cold-start grace present (3/3 cases)", "PASS", "", "exit-code-only"),
 ("RESULT C01 PASS CLI exits 2 (rc=2)", "PASS", "", "exit-code-only"),
 ("ok 4 - refuses fail=1 input\nRESULT: PASS=4 FAIL=0", "PASS", "", "summary"),
 ("\x00\xff junk\npassed=1 failed=0", "PASS", "", "summary"),
 # round 5 (review r4): O2 a fail word in the trailing comment of a summary line is a FAIL
 ("5 passed -- 1 failure seen", "FAIL", "summary_word_FAIL", "summary"),
 ("pass=5; fail later", "FAIL", "summary_word_FAIL", "summary"),
 ("5 passed -- all green", "PASS", "", "summary"),
 # F5 crash text with rc 0 is never a silent PASS: no summary -> ERROR, after a summary -> ERROR
 ("AssertionError: x", "ERROR", "unparsed_fail_signal", "summary"),
 ("Segmentation fault (core dumped)", "ERROR", "unparsed_fail_signal", "summary"),
 ("t.sh: line 3: foo: command not found", "ERROR", "unparsed_fail_signal", "summary"),
 ("Killed", "ERROR", "unparsed_fail_signal", "summary"),
 ("cp: cannot create x: Permission denied", "ERROR", "unparsed_fail_signal", "summary"),
 ("passed=3 failed=0\nSegmentation fault", "ERROR", "fail_signal_after_summary", "summary"),
 # golden-FALSE: a passing check line that quotes a crash word, and a word that only contains one
 ("ok   prints 'command not found' for a bad name\nRESULT: PASS=1 FAIL=0", "PASS", "", "summary"),
 ("killed M3 (2 failing check(s))\nSUMMARY mutants=1 killed=1 survivors=0 not_applicable=0", "PASS", "", "summary"),
 # F4 a fail word overwritten by a CR progress update is still a fail signal
 ("failed=1 passed=4\rALL OK", "ERROR", None, "summary"),
 ("progress 1/3\rprogress 3/3\npassed=3 failed=0", "PASS", "", "summary"),
 # F9 TAP `# TODO` / `# SKIP` exemption also for the bare fail-signal scan
 ("1..2\nok 1 a\nnot ok 2 b # TODO later", "PASS", "", "summary"),
]
for text, v, r, s in J:
    got = m.judge(0, False, text, "bash")
    want = (v, got[1] if r is None else r, s)
    chk("parser: %r -> %s" % (text[:60], v), got[:3], want)
chk("parser: go ok line", m.judge(0, False, "ok  \tpkg\t0.003s", "go-test")[0], "PASS")
chk("parser: go FAIL line", m.judge(0, False, "ok  \tpkg\t0.1s\nFAIL\tpkg2\t0.2s\nFAIL", "go-test")[0], "FAIL")
chk("parser: rc 77 -> SKIP", m.judge(77, False, "x", "bash")[0], "SKIP")
chk("parser: rc 1 with a pass summary -> FAIL", m.judge(1, False, "passed=3 failed=0", "bash")[0], "FAIL")
chk("parser: timer -> TIMEOUT", m.judge(0, True, "passed=3 failed=0", "bash")[0], "TIMEOUT")
big = "x" * (10 << 20) + "\npassed=1 failed=0"
chk("parser: 10 MB line then a summary", m.judge(0, False, big, "bash")[:3], ("PASS", "", "summary"))

# --- P10 reviewer mutants of round 3 pinned by behaviour (X1 record verdict, X9 killpg guard)
base = {"schema": m.SCHEMA, "seq": 0, "prev": m.GENESIS, "unit": "u", "path": "u", "sha": "s", "tree": "t", "ctx": "c",
        "runner_hash": "h", "verdict": "PASS", "reason": "", "verdict_source": "summary", "rc": 0, "secs": 1.0,
        "leaked": 0, "log": "logs/000000.log", "log_sha256": "x", "ident": "head=x subs=y dirty=clean"}
chk("X1: a record with a known verdict is valid (golden-FALSE)", m.valid_record(dict(base)), True)
for bogus in ("BOGUS", "pass", "", "PASS-FULL"):
    chk("X1: a record with verdict %r is invalid" % bogus, m.valid_record(dict(base, verdict=bogus)), False)
calls = []
real_killpg = os.killpg
os.killpg = lambda g, s: calls.append((g, s))
try:
    for g in (1, 0, -5, os.getpgrp(), "7", None, True):
        try:
            m.killpg_checked(g, 0); ko("X9: killpg_checked(%r) refused" % (g,))
        except m.Fatal:
            ok("X9: killpg_checked(%r) refused" % (g,))
    chk("X9: no refused group reached os.killpg", calls, [])
    m.killpg_checked(424242, 0)
    chk("X9: a group id > 1 that is not ours is signalled (golden-FALSE)", calls, [(424242, 0)])
finally:
    os.killpg = real_killpg

# --- P2 deletion guard (R6, section 11.4.287): rm_tree refuses anything that is not a runner-made dir
m.SAFE_RM = os.path.realpath(os.path.join(os.path.dirname(sys.argv[1]), "..", "lib", "safe_rm.sh"))
out_dir = os.path.join(os.path.dirname(scratch), "fsr_victim_outside")
os.makedirs(out_dir, exist_ok=True)
for path, label in ((out_dir, "outside scratch"), (os.path.join(scratch, "notours"), "no fsr_ prefix")):
    os.makedirs(path, exist_ok=True)
    try:
        m.rm_tree(path, scratch); ko("rm_tree refuses %s" % label)
    except m.Fatal:
        ok("rm_tree refuses %s" % label)
    chk("rm_tree left %s in place" % label, os.path.isdir(path), True)
own = os.path.join(scratch, "fsr_mine"); os.makedirs(own)
m.rm_tree(own, scratch)
chk("rm_tree removes its own runner-made dir (golden-FALSE)", os.path.exists(own), False)

# --- P3 shell-invocation model (N3): membership only from code that runs
R = os.path.join(scratch, "shroot"); os.makedirs(os.path.join(R, "t"))
def w(rel, body):
    p = os.path.join(R, rel); os.makedirs(os.path.dirname(p), exist_ok=True)
    open(p, "w").write("#!/usr/bin/env bash\n" + body)
for n in ("test_a", "test_b", "test_c", "test_d", "test_e", "test_f", "test_g", "test_h", "test_x_heavy"):
    w("t/%s.sh" % n, "echo passed=1 failed=0\n")
w("t/h.py", "print(1)\n")
w("t/run_all.sh", r'''here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
quick=0; [ "${1:-}" = "--quick" ] && quick=1
# test_c is disabled for now: bash "$here/test_c.sh"
echo "test_d is printed, not run"
cat <<EOF
bash "$here/test_e.sh"
EOF
run() { "$@"; }
run bash "$here/test_a.sh"
suites=(test_b
        test_f)
[ "$quick" = 1 ] || suites+=(test_x_heavy)
for s in "${suites[@]}"; do bash "$here/$s.sh" || exit 1; done
x="$(bash "$here/test_g.sh")"
while read -r l; do :; done < <(python3 -I "$(dirname "$0")/h.py" --list)
for t in "$here"/test_h*.sh; do
  case "$(basename "$t" .sh)" in test_hz) continue ;; esac
  runner=(bash "$t"); "${runner[@]}"
done
''')
inv_full = m.invoked(R, "t/run_all.sh", [])
inv_q = m.invoked(R, "t/run_all.sh", ["--quick"])
for n, want in (("t/test_a.sh", True), ("t/test_b.sh", True), ("t/test_f.sh", True), ("t/test_g.sh", True),
                ("t/h.py", True), ("t/test_h.sh", True), ("t/test_x_heavy.sh", True),
                ("t/test_c.sh", False), ("t/test_d.sh", False), ("t/test_e.sh", False)):
    chk("shmodel full: %s invoked=%s" % (n, want), n in inv_full, want)
chk("shmodel --quick drops the guarded append", "t/test_x_heavy.sh" in inv_q, False)
chk("shmodel --quick keeps the plain array", "t/test_b.sh" in inv_q, True)
w("t/run_all2.sh", 'here=$(cd "$(dirname "$0")" && pwd)\nfor g in test_a test_b; do for f in "$g.sh"; do bash "$here/$f"; done; done\n')
chk("shmodel nested literal loops", sorted(m.invoked(R, "t/run_all2.sh", [])), ["t/test_a.sh", "t/test_b.sh"])
w("t/run_all4.sh", 'here=$(cd "$(dirname "$0")" && pwd)\nD="$(python3 "$here/h.py")"\nif [ -z "$D" ]; then exit 3; fi\nbash "$here/test_a.sh"\n')
chk("shmodel unknown command-substitution assignment keeps the later path", "t/test_a.sh" in m.invoked(R, "t/run_all4.sh", []), True)
w("t/run_all5.sh", 'here=$(cd "$(dirname "$0")" && pwd)\nD=""\nif [ -z "$D" ]; then exit 3; fi\nbash "$here/test_a.sh"\n')
chk("shmodel definite empty assignment then exit stops the path", "t/test_a.sh" in m.invoked(R, "t/run_all5.sh", []), False)
w("t/run_all3.sh", 'cat <<EOF\nunterminated\n')
try:
    m.invoked(R, "t/run_all3.sh", []); ko("shmodel: unterminated heredoc refused")
except m.ShParseError:
    ok("shmodel: unterminated heredoc refused")
# --- P5 status consumption (review r3 P5): a member whose status the cover throws away is run alone
d5 = os.path.join(scratch, "p5"); os.makedirs(d5 + "/t", exist_ok=True)
for n in "abcdef":
    open(d5 + "/t/%s.sh" % n, "w").write("x")
cases = [
    ("bash t/a.sh || true\nbash t/b.sh || rc=1\necho x\nexit $rc", {"t/a.sh"}),
    ("bash t/a.sh\nbash t/b.sh", {"t/a.sh"}),
    # round 5 (F3): a status read only into a variable that never reaches a decision, or only printed, is discarded
    ("bash t/a.sh; rc=$?\nbash t/b.sh | tee x; echo ${PIPESTATUS[0]}", {"t/a.sh", "t/b.sh"}),
    ("bash t/a.sh; rc=$?\nbash t/b.sh | tee x; st=${PIPESTATUS[0]}\n[ \"$rc\" = 0 ] && [ \"$st\" = 0 ] || exit 1", set()),
    ("set -e\nbash t/a.sh\nbash t/b.sh || true\necho ok", {"t/b.sh"}),
    ("if bash t/a.sh; then :; fi\nfor x in 1; do bash t/b.sh; done\nbash t/c.sh &\nwait\nout=$(bash t/d.sh)\nrc=$?\n"
     "echo $(bash t/e.sh)\nbash t/f.sh | cat\nexit 0", {"t/a.sh", "t/b.sh", "t/c.sh", "t/d.sh", "t/e.sh", "t/f.sh"}),
    ("! bash t/a.sh", {"t/a.sh"}),
    ("bash t/a.sh; rc=$?; exit 0", {"t/a.sh"}),
    ("bash t/a.sh; echo \"rc=$?\"; exit 0", {"t/a.sh"}),
    ("if bash t/a.sh; then echo ok; else echo bad; fi", {"t/a.sh"}),
    # golden-FALSE: the status reaches an exit decision
    ("bash t/a.sh; rc=$?; exit $rc", set()),
    ("bash t/a.sh; rc=$?\n[ $rc -eq 0 ] || exit 1", set()),
    ("fail=0\nif ! bash t/a.sh; then fail=1; fi\nexit $fail", set()),
    ("if bash t/a.sh; then :; else exit 1; fi", set()),
    ("bash t/a.sh\nexit $?", set()),
    ("f(){ bash t/a.sh; }\nf || exit 1\nbash t/b.sh && bash t/c.sh\necho", {"t/b.sh", "t/c.sh"}),
    ("set -euo pipefail\nbash t/a.sh | cat\nfor x in 1; do bash t/b.sh; done", set()),
    ("bash t/a.sh || echo failed\nexec bash t/b.sh", {"t/a.sh"}),
    ("bash t/a.sh && bash t/b.sh || exit 1\necho done", set()),
    ("bash t/a.sh && bash t/b.sh || true\necho done", {"t/a.sh", "t/b.sh"}),
]
for txt, want in cases:
    open(d5 + "/r.sh", "w").write(txt + "\n")
    chk("P5 model: discarded set of %r" % txt[:48], m.model(d5, "r.sh", []).discarded, want)
print("engine unit checks failed=%d" % NF[0])
sys.exit(1 if NF[0] else 0)
PY
[ $? -eq 0 ] || ko "engine unit section: a check failed, or the import crashed"

# =========================================================================== CLI cases
# --- 1 golden-good: full mode, summary-recognised PASS -> rc 0, PASS-FULL
G="$T/good"; mkroot "$G"; sut "$G" tests/a/test_good.sh 'echo "passed=2 failed=0"'
gen "$G"; gitc "$G" add -A; gitc "$G" commit -q -m good; run "$G" "$T/o_good" --include-heavy
chk "golden-good rc=0" "$RC" "0"
has "golden-good RESULT: PASS-FULL" '^RESULT: PASS-FULL' "$T/o_good.log"
chk "golden-good verdict from summary" "$(verdict "$T/o_good" tests/a/test_good.sh)" "PASS||summary"

# --- 2 exit-code-only PASS is labelled
sut "$G" tests/a/test_quiet.sh 'echo hello'
gen "$G"; run "$G" "$T/o_quiet" --include-heavy
chk "no summary -> PASS exit-code-only" "$(verdict "$T/o_quiet" tests/a/test_quiet.sh)" "PASS||exit-code-only"
has "exit-code-only counted in RESULT" 'exit-code-only-PASS=1' "$T/o_quiet.log"

# --- 3 rc-0 lies: FAIL lines, zero checks, all skipped
B="$T/lie"; mkroot "$B"
sut "$B" tests/a/test_lie_fail.sh 'echo "RESULT: FAIL passed=0 failed=3"'
sut "$B" tests/a/test_lie_counts.sh 'echo "== 1 passed, 2 failed =="'
sut "$B" tests/a/test_zero.sh 'echo "ran 0 tests"'
sut "$B" tests/a/test_allskip.sh 'echo "passed=0 failed=0 skipped=3"'
sut "$B" tests/a/test_term_skip.sh 'echo "noise"' 'echo "VERDICT: SKIP reason=hardware_not_present"'
gen "$B"; run "$B" "$T/o_lie" --include-heavy --timeout 20
chk "exit0 + RESULT: FAIL -> FAIL" "$(verdict "$T/o_lie" tests/a/test_lie_fail.sh | cut -d'|' -f1)" "FAIL"
chk "exit0 + '2 failed' -> FAIL" "$(verdict "$T/o_lie" tests/a/test_lie_counts.sh)" "FAIL|summary_reports_failures|summary"
chk "exit0 + ran 0 tests -> ERROR zero_tests" "$(verdict "$T/o_lie" tests/a/test_zero.sh)" "ERROR|zero_tests|summary"
chk "exit0 + all skipped -> SKIP" "$(verdict "$T/o_lie" tests/a/test_allskip.sh)" "SKIP|all_skipped|summary"
chk "exit0 + terminal VERDICT: SKIP -> SKIP with reason" "$(verdict "$T/o_lie" tests/a/test_term_skip.sh)" "SKIP|hardware_not_present|summary"
chk "lies run rc=1" "$RC" "1"

# --- 4 exit codes: SIGKILL at 0 s, own exit 137 / 124 are ERROR, not TIMEOUT; 77 SKIP; 127 ERROR
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

# --- 6 leaks after a normal exit: background child and a setsid escapee are killed and counted
L="$T/leak"; mkroot "$L"; M2="fsrleakA_$$_$RANDOM"; M3="fsrleakB_$$_$RANDOM"
sut "$L" tests/a/test_leak.sh "bash -c 'exec -a $M2 sleep 300' </dev/null >/dev/null 2>&1 &" \
  "setsid bash -c 'trap \"\" TERM; exec -a $M3 sleep 300' </dev/null >/dev/null 2>&1 &" 'echo "passed=1 failed=0"'
gen "$L"; run "$L" "$T/o_leak" --include-heavy --timeout 20
if pgrep -f "$M2" >/dev/null || pgrep -f "$M3" >/dev/null; then ko "leaked processes survived"; pkill -9 -f "$M2"; pkill -9 -f "$M3"; else ok "leaked processes killed"; fi
has "leaks counted in record" '"leaked": [1-9]' "$T/o_leak/results.jsonl"

# --- 7 environment allowlist: ambient variables do not reach the suite; HOME/XDG fresh
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

# --- 8 manifest fail-closed: unlisted file, stale row, unclassifiable go, malformed, heavy rule
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
setrow "$M/config/full_suite_manifest.tsv" tests/a/test_big_mutation.sh 'tests/a/test_big_mutation.sh\tsh\tentry\tdefault\tbash\t-\tauto'
run "$M" "$T/o_man5" --include-heavy
chk "heavy-looking name declared default -> exit 3" "$RC" "3"
rm -f "$M/tests/a/test_big_mutation.sh" "$M/config/full_suite_manifest.tsv"
sut "$M" tests/q2/test_qd.sh 'echo "passed=1 failed=0"'
sut "$M" tests/q2/run_all.sh 'here=$(cd "$(dirname "$0")" && pwd)' 'quick=0; [ "${1:-}" = "--quick" ] && quick=1' 'suites=()' '[ "$quick" = 1 ] || suites+=(test_qd)' 'for s in "${suites[@]}"; do bash "$here/$s.sh"; done' 'echo "RUN_ALL: PASS"'
gen "$M"
setrow "$M/config/full_suite_manifest.tsv" tests/q2/run_all.sh 'tests/q2/run_all.sh\trunall\tentry\tdefault\trunall-quick\t-\tauto'
setrow "$M/config/full_suite_manifest.tsv" tests/q2/test_qd.sh 'tests/q2/test_qd.sh\tsh\tmember\tdefault\t-\ttests/q2/run_all.sh\tauto'
run "$M" "$T/o_man6" --include-heavy
chk "runall-quick whose --quick drops a default member -> exit 3" "$RC" "3"
has "quick-dropped default member named" 'default member tests/q2/test_qd.sh is not run by .*--quick' "$T/o_man6.log"

# --- 9 run_all policies: whole runs members once; quick passes --quick only in default; members
W="$T/ra"; mkroot "$W"; C="$T/counts"; mkdir -p "$C"
for n in m1 m2; do sut "$W" tests/w/test_$n.sh "echo x >> $C/w_$n" 'echo "passed=1 failed=0"'; done
sut "$W" tests/w/run_all.sh 'h=$(cd "$(dirname "$0")" && pwd)' 'for t in "$h"/test_*.sh; do bash "$t" || exit 1; done' 'echo "ran 2, failed 0"'
sut "$W" tests/q/test_light.sh "echo x >> $C/q_light" 'echo "passed=1 failed=0"'
sut "$W" tests/q/test_q_chaos.sh "echo x >> $C/q_chaos" 'echo "passed=1 failed=0"'
sut "$W" tests/q/run_all.sh "echo \"\$*\" >> $C/q_args" 'quick=0; [ "${1:-}" = "--quick" ] && quick=1' 'suites=(test_light)' \
  '[ "$quick" = 1 ] || suites+=(test_q_chaos)' 'h=$(cd "$(dirname "$0")" && pwd)' 'for s in "${suites[@]}"; do bash "$h/$s.sh" || exit 1; done' 'echo "RUN_ALL: PASS"'
sut "$W" tests/m/test_ml.sh "echo x >> $C/m_light" 'echo "passed=1 failed=0"'
sut "$W" tests/m/test_m_mutants.sh "echo x >> $C/m_heavy" 'echo "passed=1 failed=0"'
sut "$W" tests/m/run_all.sh "echo x >> $C/m_runall" 'h=$(cd "$(dirname "$0")" && pwd)' 'bash "$h/test_ml.sh" && bash "$h/test_m_mutants.sh" || exit 1' 'echo "RESULT: PASS=2 FAIL=0"'
sut "$W" tests/h/test_h_stress.sh "echo x >> $C/h_stress" 'echo "passed=1 failed=0"'
gen "$W"
setrow "$W/config/full_suite_manifest.tsv" tests/q/run_all.sh 'tests/q/run_all.sh\trunall\tentry\tdefault\trunall-quick\t-\tauto'
run "$W" "$T/o_ra_def"
chk "default mode rc=5 (heavy not run)" "$RC" "5"
has "default RESULT: PARTIAL-DEFAULT-SET" '^RESULT: PARTIAL-DEFAULT-SET .*not a section 11.4.40 full retest' "$T/o_ra_def.log"
hasnt "default run never prints a RESULT: PASS line (N12)" '^RESULT: PASS' "$T/o_ra_def.log"
hasnt "default run never prints a RESULT: OK line (N12)" '^RESULT: OK' "$T/o_ra_def.log"
chk "whole run_all: member m1 ran once" "$(wc -l < "$C/w_m1" 2>/dev/null)" "1"
chk "quick run_all got --quick in default mode" "$(cat "$C/q_args" 2>/dev/null)" "--quick"
if [ -e "$C/q_chaos" ]; then ko "heavy quick member not run in default"; else ok "heavy quick member not run in default"; fi
has "N10: heavy member dropped by --quick listed SKIPPED-heavy" 'SKIPPED-heavy tests/q/test_q_chaos.sh' "$T/o_ra_def.log"
chk "members run_all: light member ran alone once" "$(wc -l < "$C/m_light" 2>/dev/null)" "1"
if [ -e "$C/m_heavy" ] || [ -e "$C/m_runall" ]; then ko "members run_all / heavy member not run in default"; else ok "members run_all / heavy member not run in default"; fi
if [ -e "$C/h_stress" ]; then ko "heavy entry not run in default"; else ok "heavy entry not run in default"; fi
has "heavy entry recorded SKIPPED-heavy" 'SKIPPED-heavy tests/h/test_h_stress.sh' "$T/o_ra_def.log"
bash "$R" --root "$W" --list > "$T/o_ra_list.log" 2>&1
has "N10: --list names the --quick drop" 'SKIPPED-heavy tests/q/test_q_chaos.sh .*dropped by --quick' "$T/o_ra_list.log"
gitc "$W" add -A; gitc "$W" commit -q -m ra; run "$W" "$T/o_ra_full" --include-heavy
chk "full mode rc=0" "$RC" "0"
chk "quick run_all without --quick in full mode" "$(sed -n 2p "$C/q_args" 2>/dev/null)x" "x"
chk "full mode heavy quick member ran once" "$(wc -l < "$C/q_chaos" 2>/dev/null)" "1"
chk "full mode members run_all ran once" "$(wc -l < "$C/m_runall" 2>/dev/null)" "1"
chk "full mode light member ran once more (through the run_all)" "$(wc -l < "$C/m_light" 2>/dev/null)" "2"
chk "whole member once per run" "$(wc -l < "$C/w_m1" 2>/dev/null)" "2"

# --- 10 resume: same tree resumes; dirty tree, new sha re-run; --rerun-nonpass; never upgrade
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
# flaky: FAIL first, PASS on --rerun-nonpass; the final verdict is never upgraded (N1)
FK="$T/flaky"; mkroot "$FK"; FC="$T/cnt_flaky"
sut "$FK" tests/a/test_flaky.sh "echo x >> $FC" "[ \$(wc -l < $FC) -ge 2 ] || exit 1" 'echo "passed=1 failed=0"'
gen "$FK"; gitc "$FK" add -A; gitc "$FK" commit -q -m f
run "$FK" "$T/o_flaky" --include-heavy
run "$FK" "$T/o_flaky" --include-heavy --rerun-nonpass
chk "flaky re-run executed" "$(wc -l < "$FC")" "2"
chk "flaky: resume never upgrades FAIL to PASS (rc 1)" "$RC" "1"
has "flaky: nondeterminism reported" 'NONDETERMINISTIC=1' "$T/o_flaky.log"
has "flaky: both verdicts named" 'NONDETERMINISTIC: (FAIL/PASS|PASS/FAIL)' "$T/o_flaky.log"

# --- 11 KNOWN: exact path + signature; golden-FALSE substring path, other signature, doc-only
K="$T/known"; mkroot "$K"
sut "$K" tests/a/test_bad.sh 'echo "boom: lock timeout"' 'exit 1'
sut "$K" tests/b/test_other.sh 'echo "different cause"' 'exit 1'
sut "$K" tests/c/test_docref.sh 'exit 1'
gen "$K"
printf '# path\tsignature\ttracked_id\tnote\ntests/a/test_bad.sh\tlock timeout\tATM-1\topen\nb/test_other.sh\tdifferent cause\tATM-2\tsubstring path\ntests/b/test_other.sh\tlock timeout\tATM-3\tother signature\n' > "$K/config/full_suite_known_failures.tsv"
mkdir -p "$K/docs/design"; printf 'evidence: tests/c/test_docref.sh passed=25 failed=0\n' > "$K/docs/design/known_failures_v73.md"
run "$K" "$T/o_known" --include-heavy
has "exact path + signature -> KNOWN with id" 'FAIL \[KNOWN ATM-1\]' "$T/o_known/summary.txt"
chk "known run rc=1 (two unexplained)" "$RC" "1"
has "golden-FALSE: substring path / other signature not KNOWN" '^FAIL  tests/b/test_other.sh' "$T/o_known/summary.txt"
has "golden-FALSE: path cited only in the markdown doc fails" '^FAIL  tests/c/test_docref.sh' "$T/o_known/summary.txt"
printf 'bad row\n' > "$K/config/full_suite_known_failures.tsv"
run "$K" "$T/o_known2" --include-heavy
chk "malformed known table -> exit 2" "$RC" "2"
# 11b F047-1 (CON-047 review): `reason:<code>+tracked` also requires every "[tracked <id>]" token in the log to name
# the row's tracked_id (at least one present), so an rc 3 owned by another item is never attributed to this row.
K3="$T/known3"; mkroot "$K3"
sut "$K3" tests/a/test_own.sh 'echo "KNOWN-FAIL K1 [tracked ATM-5]"' 'exit 3'
sut "$K3" tests/a/test_mixed.sh 'echo "KNOWN-FAIL K1 [tracked ATM-5]"' 'echo "KNOWN-FAIL K9 [tracked ATM-6]"' 'exit 3'
sut "$K3" tests/a/test_untagged.sh 'echo "no marker"' 'exit 3'
sut "$K3" tests/a/test_rc1.sh 'echo "KNOWN-FAIL K1 [tracked ATM-5]"' 'exit 1'
gen "$K3"
printf 'tests/a/test_own.sh\treason:rc_3+tracked\tATM-5\to\ntests/a/test_mixed.sh\treason:rc_3+tracked\tATM-5\to\ntests/a/test_untagged.sh\treason:rc_3+tracked\tATM-5\to\ntests/a/test_rc1.sh\treason:rc_3+tracked\tATM-5\to\n' > "$K3/config/full_suite_known_failures.tsv"
run "$K3" "$T/o_known3" --include-heavy
has "11b: rc 3 whose only tracked token is the row id -> KNOWN" 'KNOWN ATM-5\]  tests/a/test_own.sh' "$T/o_known3/summary.txt"
hasnt "11b: rc 3 that also names another item is not KNOWN" 'KNOWN ATM-5\]  tests/a/test_mixed.sh' "$T/o_known3/summary.txt"
hasnt "11b: rc 3 without any tracked token is not KNOWN" 'KNOWN ATM-5\]  tests/a/test_untagged.sh' "$T/o_known3/summary.txt"
hasnt "11b: rc 1 is never KNOWN under a reason row" 'KNOWN ATM-5\]  tests/a/test_rc1.sh' "$T/o_known3/summary.txt"
chk "11b: three unexplained units -> rc 1" "$RC" "1"
# control: the same mixed unit under a plain reason row is KNOWN (the modifier, not the fixture, makes the difference)
printf 'tests/a/test_mixed.sh\treason:rc_3\tATM-5\to\n' > "$T/known3_plain.tsv"
run "$K3" "$T/o_known3p" --include-heavy --known "$T/known3_plain.tsv"
has "11b control: plain reason row matches the mixed unit" 'KNOWN ATM-5\]  tests/a/test_mixed.sh' "$T/o_known3p/summary.txt"
# 11c F047-2 (CON-047 review): --check-known-open names a row whose tracked item is closed or unknown (exit 1),
# passes when every item is open (exit 0), and is BLIND (exit 2) on an absent or empty DB, never a clean 0.
KO="$T/known_open"; mkdir -p "$KO"
python3 -I -c 'import sqlite3,sys
c=sqlite3.connect(sys.argv[1]); c.execute("CREATE TABLE items(atm_id TEXT, status TEXT, current_location TEXT)")
c.executemany("INSERT INTO items VALUES(?,?,?)",[("ATM-5","Queued","Issues"),("ATM-6","Fixed (→ Fixed.md)","Fixed"),("ATM-8","Obsolete","Fixed"),("ATM-9","Completed","Fixed")]); c.commit()
c=sqlite3.connect(sys.argv[2]); c.execute("CREATE TABLE items(atm_id TEXT, status TEXT, current_location TEXT)"); c.commit()' "$KO/db.sqlite" "$KO/empty.sqlite"
printf 'tests/a/x.sh\treason:rc_3+tracked\tATM-5\to\n' > "$KO/open.tsv"
printf 'tests/a/x.sh\treason:rc_3+tracked\tATM-5\to\ntests/a/y.sh\treason:rc_3\tATM-6\to\ntests/a/z.sh\tsig\tATM-77\to\ntests/a/w.sh\treason:rc_3\tATM-8\to\ntests/a/v.sh\treason:rc_3\tATM-9\to\n' > "$KO/stale.tsv"
bash "$R" --root "$K3" --check-known-open --known "$KO/open.tsv" --db "$KO/db.sqlite" >"$KO/o1" 2>&1; chk "11c: every tracked item open -> rc 0" "$?" "0"
bash "$R" --root "$K3" --check-known-open --known "$KO/stale.tsv" --db "$KO/db.sqlite" >"$KO/o2" 2>&1; chk "11c: a closed and an unknown item -> rc 1" "$?" "1"
has "11c: closed item named STALE" '^STALE ATM-6  tests/a/y.sh' "$KO/o2"
has "11c: unknown item named STALE" '^STALE ATM-77  tests/a/z.sh' "$KO/o2"
has "11c: Obsolete item located in Fixed named STALE (closure is the location, not the status text; review fixu M1)" '^STALE ATM-8  tests/a/w.sh' "$KO/o2"
has "11c: Completed item located in Fixed named STALE (review fixu M1)" '^STALE ATM-9  tests/a/v.sh' "$KO/o2"
has "11c: open item still listed as open" '^open  ATM-5  tests/a/x.sh' "$KO/o2"
bash "$R" --root "$K3" --check-known-open --known "$KO/open.tsv" --db "$KO/empty.sqlite" >"$KO/o3" 2>&1; chk "11c: empty DB is BLIND -> rc 2" "$?" "2"
bash "$R" --root "$K3" --check-known-open --known "$KO/open.tsv" --db "$KO/absent.sqlite" >"$KO/o4" 2>&1; chk "11c: absent DB is BLIND -> rc 2" "$?" "2"
bash "$R" --root "$K3" --known "$KO/open.tsv" --db "$KO/db.sqlite" --list >"$KO/o5" 2>&1; chk "11c: --db without --check-known-open -> rc 2" "$?" "2"
# N1: KNOWN is recomputed from the CURRENT table; a resume without the table cannot stay green
K2="$T/known2"; mkroot "$K2"; KC="$T/cnt_known2"
sut "$K2" tests/a/test_kb.sh "echo x >> $KC" 'echo "boom: lock timeout"' 'exit 1'
gen "$K2"; gitc "$K2" add -A; gitc "$K2" commit -q -m k
printf 'tests/a/test_kb.sh\tlock timeout\tATM-9\topen\n' > "$T/known_ext.tsv"
run "$K2" "$T/o_k2" --include-heavy --known "$T/known_ext.tsv"
chk "permissive table: KNOWN failure -> rc 7 (PASS-FULL-WITH-KNOWN)" "$RC" "7"
run "$K2" "$T/o_k2" --include-heavy --known "$T/absent.tsv"
chk "N1: resume with the table absent fails (rc 1)" "$RC" "1"
hasnt "N1: no KNOWN tag without the table" 'KNOWN ATM-9' "$T/o_k2/summary.txt"
chk "N1: table hash is in the resume key (unit re-ran)" "$(wc -l < "$KC")" "2"
printf '# no rows\n' > "$T/known_ext.tsv"
run "$K2" "$T/o_k2" --include-heavy --known "$T/known_ext.tsv"
chk "N1: same path, emptied table -> re-run and FAIL" "$RC" "1"
# external --manifest is keyed too (N13)
cp "$K2/config/full_suite_manifest.tsv" "$T/man_ext.tsv"
run "$K2" "$T/o_k3" --include-heavy --manifest "$T/man_ext.tsv"
n0=$(wc -l < "$KC")
sed -i 's/\tauto$/\tauto edited/' "$T/man_ext.tsv"
run "$K2" "$T/o_k3" --include-heavy --manifest "$T/man_ext.tsv"
chk "N13: edited external manifest re-runs" "$(wc -l < "$KC")" "$((n0+1))"

# --- 12 partial and usage
run "$G" "$T/o_only" --include-heavy --only 'test_good'
chk "--only run -> PARTIAL-NOT-RUN rc=4" "$RC" "4"
has "PARTIAL-NOT-RUN RESULT line" '^RESULT: PARTIAL-NOT-RUN' "$T/o_only.log"
run "$G" "$T/o_t0" --timeout 0
chk "--timeout 0 refused" "$RC" "2"
run "$G" "$G/inside_out"
chk "--out inside the root refused" "$RC" "2"
if [ -e "$G/inside_out" ]; then ko "inside --out not created"; else ok "inside --out not created"; fi

# --- 13 N2: SKIP inside the run is never PASS-FULL; all-SKIP is never green
SK="$T/skip"; mkroot "$SK"
sut "$SK" tests/a/test_s1.sh 'exit 77'; sut "$SK" tests/a/test_s2.sh 'exit 77'; sut "$SK" tests/a/test_s3.sh 'exit 77'
sut "$SK" tests/a/test_s4.sh 'echo "passed=1 failed=0"'
gen "$SK"; run "$SK" "$T/o_skip" --include-heavy
chk "N2: 3 SKIP + 1 PASS -> rc 6" "$RC" "6"
has "N2: RESULT PARTIAL-SKIPS" '^RESULT: PARTIAL-SKIPS' "$T/o_skip.log"
hasnt "N2: never PASS-FULL with SKIPs" '^RESULT: PASS' "$T/o_skip.log"
has "N2: SKIP units listed" '^SKIP  tests/a/test_s1.sh' "$T/o_skip/summary.txt"
rm -f "$SK/tests/a/test_s4.sh"; gen "$SK"; run "$SK" "$T/o_skip2" --include-heavy
chk "N2: all-SKIP run -> rc 6, never green" "$RC" "6"

# --- 14 N3: membership by structure, not by a name in a comment or an echo
N3="$T/n3"; mkroot "$N3"
sut "$N3" tests/r/test_x1.sh 'echo "passed=1 failed=0"'
sut "$N3" tests/r/test_commented.sh 'exit 1'
sut "$N3" tests/r/test_echoed.sh 'exit 1'
sut "$N3" tests/r/test_real.sh 'echo "passed=1 failed=0"'
sut "$N3" tests/r/run_all.sh 'h=$(cd "$(dirname "$0")" && pwd)' '# test_commented is disabled for now' 'echo "test_echoed is listed"' \
  'for t in "$h"/test_x*.sh; do bash "$t"; done' 'bash "$h/test_real.sh"' 'echo "ran 2, failed 0"'
gen "$N3"
chk "N3: comment-only member is generated as an entry" "$(awk -F'\t' '$1=="tests/r/test_commented.sh"{print $3}' "$N3/config/full_suite_manifest.tsv")" "entry"
chk "N3: echo-only member is generated as an entry" "$(awk -F'\t' '$1=="tests/r/test_echoed.sh"{print $3}' "$N3/config/full_suite_manifest.tsv")" "entry"
chk "N3 control needle: real invocation is a member" "$(awk -F'\t' '$1=="tests/r/test_real.sh"{print $3}' "$N3/config/full_suite_manifest.tsv")" "member"
vfy "$N3" "$T/n3_ok.log"; chk "N3 control needle: generated manifest verifies" "$RC" "0"
setrow "$N3/config/full_suite_manifest.tsv" tests/r/test_commented.sh 'tests/r/test_commented.sh\tsh\tmember\tdefault\t-\ttests/r/run_all.sh\tauto'
vfy "$N3" "$T/n3_bad.log"
chk "N3: comment-only membership refused (exit 3)" "$RC" "3"
has "N3: refusal names the member" 'tests/r/test_commented.sh: covered_by tests/r/run_all.sh does not run it' "$T/n3_bad.log"

# --- 15 N4/N9: census completeness and broken entries fail closed
N4="$T/n4"; mkroot "$N4"; sut "$N4" tests/a/test_base.sh 'echo "passed=1 failed=0"'; gen "$N4"
for f in tests/a/meta_test_x.sh tests/a/mutation_test_y.sh tests/a/mutants_z.sh tests/a/run_scope_tests.sh \
         tests/a/t_case.py test/live_smoke.sh scripts/x/meta_mutation.sh lib/mytest_helper.sh tests/a/foo.bash \
         tests/a/UPPER.SH scripts/prove_mutations.sh tests/a/helper_noext; do
  mkdir -p "$(dirname "$N4/$f")"; printf '#!/usr/bin/env bash\necho hi\n' > "$N4/$f"
  vfy "$N4" "$T/n4.log"
  if [ "$RC" = 3 ] && grep -q "census file without manifest row: $f" "$T/n4.log"; then ok "N4: unlisted $f fails closed"; else ko "N4: unlisted $f fails closed (rc $RC)"; fi
  rm -f "$N4/$f"
done
vfy "$N4" "$T/n4c.log"; chk "N4 negative control: clean tree verifies" "$RC" "0"
sut "$N4" tests/a/lib.sh 'f() { :; }'
sut "$N4" tests/a/test_uses_lib.sh '. "$(dirname "$0")/lib.sh"' 'echo "passed=1 failed=0"'
gen "$N4"
chk "N4: sourced helper is excluded with an evidence reason" "$(awk -F'\t' '$1=="tests/a/lib.sh"{print $3"|"$7}' "$N4/config/full_suite_manifest.tsv")" "excluded|reason: helper: sourced by tests/a/test_uses_lib.sh"
roster "$N4" n4
bash "$R" --root "$N4" --verify-manifest --accept-excluded-change n4 > "$T/n4d.log" 2>&1; RC=$?; chk "N4: manifest with an evidenced exclusion verifies" "$RC" "0"
setrow "$N4/config/full_suite_manifest.tsv" tests/a/lib.sh 'tests/a/lib.sh\tsh\texcluded\t-\t-\t-\tUNREVIEWED'
vfy "$N4" "$T/n4e.log"; chk "N4: exclusion without a reason refused" "$RC" "3"
setrow "$N4/config/full_suite_manifest.tsv" tests/a/lib.sh 'tests/a/lib.sh\tsh\texcluded\t-\t-\t-\treason: helper: sourced by tests/a/test_base.sh'
vfy "$N4" "$T/n4f.log"; chk "N4: false 'sourced by' evidence refused" "$RC" "3"
gen "$N4"
ln -s nowhere "$N4/tests/a/test_dangle.sh"
vfy "$N4" "$T/n9.log"; chk "N9: dangling test symlink fails closed" "$RC" "3"
rm -f "$N4/tests/a/test_dangle.sh"
printf '#!/bin/sh\n' > "$N4/tests/a/test_nl
x.sh"
vfy "$N4" "$T/n9b.log"; chk "N9: name with a newline fails closed" "$RC" "3"
rm -f "$N4/tests/a/test_nl
x.sh"

# --- 16 N6: results.jsonl integrity (hash chain, lock, torn line)
I="$T/integ"; mkroot "$I"; sut "$I" tests/a/test_i.sh 'echo "passed=1 failed=0"'; sut "$I" tests/a/test_j.sh 'exit 1'
gen "$I"; gitc "$I" add -A; gitc "$I" commit -q -m i
run "$I" "$T/o_i" --include-heavy
cp "$T/o_i/results.jsonl" "$T/o_i.orig"
python3 -I -c 'import json,sys
p=sys.argv[1]; L=open(p).read().splitlines()
o=json.loads(L[-1]); o["verdict"]="PASS"; o["reason"]=""
L.append(json.dumps(o, sort_keys=True)); open(p,"w").write("\n".join(L)+"\n")' "$T/o_i/results.jsonl"
run "$I" "$T/o_i" --include-heavy
chk "N6: hand-appended record (chain not extended) -> exit 2" "$RC" "2"
has "N6: integrity named" 'integrity' "$T/o_i.log"
cp "$T/o_i.orig" "$T/o_i/results.jsonl"
python3 -I -c 'import sys
p=sys.argv[1]; L=open(p).read().splitlines(); del L[0]; open(p,"w").write("\n".join(L)+"\n")' "$T/o_i/results.jsonl"
run "$I" "$T/o_i" --include-heavy
chk "N6: deleted record -> exit 2" "$RC" "2"
cp "$T/o_i.orig" "$T/o_i/results.jsonl"
python3 -I - "$ENGINE" "$T/o_i/results.jsonl" <<'PY'
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("fsr", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
p = sys.argv[2]; L = open(p, "rb").read().splitlines()
o = {"schema": m.SCHEMA, "verdict": "PASS", "unit": "tests/a/test_j.sh", "seq": len(L), "prev": m.line_hash(L[-1])}
open(p, "ab").write((json.dumps(o, sort_keys=True) + "\n").encode())
PY
run "$I" "$T/o_i" --include-heavy
chk "R4: chain-valid but schema-less record -> exit 2" "$RC" "2"
cp "$T/o_i.orig" "$T/o_i/results.jsonl"
python3 -I - "$ENGINE" "$T/o_i/results.jsonl" <<'PY2'
import importlib.util, json, sys
spec = importlib.util.spec_from_file_location("fsr", sys.argv[1]); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
p = sys.argv[2]; L = open(p, "rb").read().splitlines()
o = json.loads(L[-1]); o["seq"] = len(L); o["prev"] = m.line_hash(L[-1])
open(p, "ab").write((json.dumps(o, sort_keys=True) + "\n").encode())
PY2
run "$I" "$T/o_i" --include-heavy
chk "N6: chain-valid record reusing a log path -> exit 2" "$RC" "2"
has "N6: log reuse named" 'reuses log' "$T/o_i.log"
cp "$T/o_i.orig" "$T/o_i/results.jsonl"
printf '{"schema": "fsr/3", "unit": "tests/a/te' >> "$T/o_i/results.jsonl"
run "$I" "$T/o_i" --include-heavy
chk "N6: torn last line dropped, run continues (rc 1 from test_j)" "$RC" "1"
has "N6: torn line reported honestly" 'torn last line .* dropped' "$T/o_i.log"
hasnt "N6: no false 're-run' claim" 'their units are re-run' "$T/o_i.log"
sut "$I" tests/a/test_hold.sh 'sleep 4' 'echo "passed=1 failed=0"'; gen "$I"
bash "$R" --root "$I" --out "$T/o_lock" --include-heavy >"$T/o_lock1.log" 2>&1 &
lp=$!; sleep 1.5
run "$I" "$T/o_lock" --include-heavy
chk "N6: second run on a locked --out -> exit 2" "$RC" "2"
has "N6: lock named" 'locked' "$T/o_lock.log"
wait "$lp" 2>/dev/null
rm -f "$I/tests/a/test_hold.sh"

# --- 17 N7: log size is capped; an overflowing suite is ERROR log_overflow
O="$T/ovf"; mkroot "$O"; sut "$O" tests/a/test_chatty.sh 'head -c 3000000 /dev/zero | tr "\0" "x"' 'echo; echo "passed=1 failed=0"'
gen "$O"; run "$O" "$T/o_ovf" --include-heavy --log-cap-mb 1
chk "N7: overflow -> ERROR log_overflow" "$(verdict "$T/o_ovf" tests/a/test_chatty.sh | cut -d'|' -f1,2)" "ERROR|log_overflow"
lsz=$(stat -c %s "$T/o_ovf/$(rec "$T/o_ovf" tests/a/test_chatty.sh log)" 2>/dev/null || echo 0)
if [ "$lsz" -gt 0 ] && [ "$lsz" -le 1100000 ]; then ok "N7: log file capped ($lsz bytes)"; else ko "N7: log file capped ($lsz bytes)"; fi

# --- 18 R1: a changed runner re-runs; R2: a suite writing into the tree fails the run
RH="$T/rh"; mkroot "$RH"; RHC="$T/cnt_rh"; sut "$RH" tests/a/test_rh.sh "echo x >> $RHC" 'echo "passed=1 failed=0"'
gen "$RH"; gitc "$RH" add -A; gitc "$RH" commit -q -m rh
RC2="$T/runcopy"; mkdir -p "$RC2/scripts/full_suite" "$RC2/scripts/lib"
cp "$R" "$RC2/scripts/run_full_suite.sh"; cp "$ENGINE" "$RC2/scripts/full_suite/"
cp "$(dirname "$R")/lib/safe_rm.sh" "$(dirname "$R")/lib/protected_paths.list" "$RC2/scripts/lib/"
bash "$RC2/scripts/run_full_suite.sh" --root "$RH" --out "$T/o_rh" --include-heavy > "$T/o_rh.log" 2>&1
echo "# runner edited" >> "$RC2/scripts/full_suite/run_full_suite.py"
bash "$RC2/scripts/run_full_suite.sh" --root "$RH" --out "$T/o_rh" --include-heavy > "$T/o_rh.log" 2>&1
chk "R1: changed runner hash re-runs the unit" "$(wc -l < "$RHC")" "2"
WT="$T/wt"; mkroot "$WT"; sut "$WT" tests/a/test_writer.sh 'echo junk > "$(git rev-parse --show-toplevel)/written.txt"' 'echo "passed=1 failed=0"'
gen "$WT"; gitc "$WT" add -A; gitc "$WT" commit -q -m wt
run "$WT" "$T/o_wt" --include-heavy
chk "R2: suite writing into the tree -> rc 1" "$RC" "1"
has "R2: tree change named" '^RESULT: FAIL \(repository tree changed' "$T/o_wt.log"

# --- 19 R3: a blinded census (pattern dropped by a fake git) is caught by the control needle
FG="$T/fakegit"; mkdir -p "$FG"; RG=$(command -v git)
printf '#!/bin/sh\nif [ "$3" = ls-files ]; then "%s" "$@" | tr "\\000" "\\n" | grep -v "_test\\.sh$" | tr "\\n" "\\000"; exit 0; fi\nexec "%s" "$@"\n' "$RG" "$RG" > "$FG/git"
chmod +x "$FG/git"
PATH="$FG:$PATH" bash "$R" --root "$G" --verify-manifest > "$T/r3.log" 2>&1; RC=$?
chk "R3: blinded census -> exit 3" "$RC" "3"
has "R3: instrument blindness named" 'census instrument blind' "$T/r3.log"

# --- 20 N13: dirty content inside a submodule changes the tree hash (resume re-runs)
SMR="$T/smsrc"; mkdir -p "$SMR"; git init -q "$SMR"; echo a > "$SMR/f"; gitc "$SMR" add f; gitc "$SMR" commit -q -m a
SM="$T/sm"; mkroot "$SM"; SMC="$T/cnt_sm"; sut "$SM" tests/a/test_sm.sh "echo x >> $SMC" 'echo "passed=1 failed=0"'
gitc "$SM" -c protocol.file.allow=always submodule add -q "$SMR" sub >/dev/null 2>&1
gen "$SM"; gitc "$SM" add -A; gitc "$SM" commit -q -m sm
run "$SM" "$T/o_sm" --include-heavy
echo b > "$SM/sub/f"
run "$SM" "$T/o_sm" --include-heavy
chk "N13: dirty submodule content re-runs" "$(wc -l < "$SMC")" "2"
echo c > "$SM/sub/f"
run "$SM" "$T/o_sm" --include-heavy
chk "N13: a second edit inside an already-dirty submodule re-runs" "$(wc -l < "$SMC")" "3"
printf 'data.ign\n' > "$SM/.gitignore"; gitc "$SM" add .gitignore; gitc "$SM" commit -q -m ign
echo 1 > "$SM/data.ign"
run "$SM" "$T/o_sm" --include-heavy
n0=$(wc -l < "$SMC")
echo 2 > "$SM/data.ign"
run "$SM" "$T/o_sm" --include-heavy
chk "N13: a changed ignored file re-runs" "$(wc -l < "$SMC")" "$((n0 + 1))"

# --- 21 N12: guide census block is generated, a stale block is refused by --verify-manifest
mkdir -p "$G/docs/guides"; printf 'x\n<!-- census:begin -->\ncensus: stale\n<!-- census:end -->\ny\n' > "$G/docs/guides/full_suite_runner_guide.md"
gen "$G"; vfy "$G" "$T/g1.log"
chk "N12: stale guide census block -> exit 3" "$RC" "3"
bash "$R" --root "$G" --sync-guide > /dev/null 2>&1
vfy "$G" "$T/g2.log"; chk "N12: --sync-guide makes the block current" "$RC" "0"

# --- 22 Go module unit
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

# --- 22b/22c moved: Go units offline (when a failed Go unit is an environment SKIP) are pinned in
# tests/test_run_full_suite_go.sh (one case per axis, real module graphs from a private file:// proxy) and its
# paired mutants in tests/test_run_full_suite_go_mutations.sh (review round 2 G5 / G7b, structural round 3).

# =========================================================================== round 4 (review r3 P4-P10)
# --- 23 X4: a resumed KNOWN is applied only when the recorded log still has its sha256
X4="$T/x4"; mkroot "$X4"; X4C="$T/cnt_x4"
sut "$X4" tests/a/test_xk.sh "echo x >> $X4C" 'echo "different cause"' 'exit 1'
gen "$X4"; gitc "$X4" add -A; gitc "$X4" commit -q -m x4
printf 'tests/a/test_xk.sh\tlock timeout\tATM-7\topen\n' > "$T/known_x4.tsv"
run "$X4" "$T/o_x4" --include-heavy --known "$T/known_x4.tsv"
chk "X4: unmatched signature -> rc 1" "$RC" "1"
echo "boom: lock timeout" >> "$T/o_x4/$(rec "$T/o_x4" tests/a/test_xk.sh log)"
run "$X4" "$T/o_x4" --include-heavy --known "$T/known_x4.tsv"
chk "X4: a log edited to carry the signature does not become KNOWN (rc 1)" "$RC" "1"
hasnt "X4: no KNOWN tag from an edited log" 'KNOWN ATM-7' "$T/o_x4/summary.txt"

# --- 24 X5: untracked file CONTENT is part of the tree hash (same name, new content re-runs)
X5="$T/x5"; mkroot "$X5"; X5C="$T/cnt_x5"
sut "$X5" tests/a/test_ud.sh "echo x >> $X5C" 'cat "$(dirname "$0")/data.txt" >/dev/null' 'echo "passed=1 failed=0"'
gen "$X5"; gitc "$X5" add -A; gitc "$X5" commit -q -m x5
echo one > "$X5/tests/a/data.txt"
run "$X5" "$T/o_x5" --include-heavy
echo two > "$X5/tests/a/data.txt"
run "$X5" "$T/o_x5" --include-heavy
chk "X5: edited untracked file re-runs the unit" "$(wc -l < "$X5C")" "2"
run "$X5" "$T/o_x5" --include-heavy
chk "X5: unchanged untracked file resumes (golden-FALSE)" "$(wc -l < "$X5C")" "2"

# --- 25 P4: excluded rows: closed reason list, test-named files need override, lock + acceptance
P4="$T/p4"; mkroot "$P4"; roster "$P4" alice bob carol dave
sut "$P4" tests/a/lib.sh 'f() { :; }'
sut "$P4" tests/a/test_uses_lib.sh '. "$(dirname "$0")/lib.sh"' 'echo "passed=1 failed=0"'
gen "$P4"
chk "P4: generated exclusion uses the closed category form" "$(awk -F'\t' '$1=="tests/a/lib.sh"{print $3"|"$7}' "$P4/config/full_suite_manifest.tsv")" "excluded|reason: helper: sourced by tests/a/test_uses_lib.sh"
vfy "$P4" "$T/p4a.log"; chk "P4: excluded set with no lock -> exit 3" "$RC" "3"
has "P4: missing acceptance named" 'excluded set .*not accepted' "$T/p4a.log"
bash "$R" --root "$P4" --verify-manifest --accept-excluded-change alice > "$T/p4b.log" 2>&1; RC=$?
chk "P4: --accept-excluded-change records the set -> exit 0" "$RC" "0"
has "P4: lock names the reviewer" 'accepted_by=alice' "$P4/config/full_suite_excluded.lock"
has "P4: lock lists the excluded path" 'tests/a/lib.sh' "$P4/config/full_suite_excluded.lock"
vfy "$P4" "$T/p4c.log"; chk "P4: accepted set verifies" "$RC" "0"
setrow "$P4/config/full_suite_manifest.tsv" tests/a/lib.sh 'tests/a/lib.sh\tsh\texcluded\t-\t-\t-\treason: tool: hand-run helper'
vfy "$P4" "$T/p4d.log"; chk "P4: changed exclusion note against the lock -> exit 3" "$RC" "3"
bash "$R" --root "$P4" --verify-manifest --accept-excluded-change bob > "$T/p4e.log" 2>&1
chk "P4: acceptance is appended, never replaced" "$(grep -c '^# accepted ' "$P4/config/full_suite_excluded.lock")" "2"
setrow "$P4/config/full_suite_manifest.tsv" tests/a/lib.sh 'tests/a/lib.sh\tsh\texcluded\t-\t-\t-\treason: whatever: x'
# accept attempted, so the lock is not the reason for the refusal (mutant E3 survived an rc-only check)
bash "$R" --root "$P4" --verify-manifest --accept-excluded-change dave > "$T/p4f.log" 2>&1; RC=$?
chk "P4: category outside the closed list -> exit 3 even with an acceptance attempt" "$RC" "3"
has "P4: closed-list violation named" "exclusion category 'whatever' is not one of" "$T/p4f.log"
chk "P4: refused acceptance appends no accepted line" "$(grep -c '^# accepted ' "$P4/config/full_suite_excluded.lock")" "2"
setrow "$P4/config/full_suite_manifest.tsv" tests/a/lib.sh 'tests/a/lib.sh\tsh\texcluded\t-\t-\t-\treason: helper: sourced by tests/a/test_uses_lib.sh'
setrow "$P4/config/full_suite_manifest.tsv" tests/a/test_uses_lib.sh 'tests/a/test_uses_lib.sh\tsh\texcluded\t-\t-\t-\treason: tool: not a test'
bash "$R" --root "$P4" --verify-manifest --accept-excluded-change carol > "$T/p4g.log" 2>&1; RC=$?
chk "P4: a test-named file excluded without override: -> exit 3 even when accepted" "$RC" "3"
has "P4: test-named exclusion named" 'test-named' "$T/p4g.log"
gen "$P4"; setrow "$P4/config/full_suite_manifest.tsv" tests/a/test_uses_lib.sh 'tests/a/test_uses_lib.sh\tsh\tentry\tdefault\tbash\t-\tauto'
bash "$R" --root "$P4" --verify-manifest --accept-excluded-change carol > /dev/null 2>&1
gitc "$P4" add -A; gitc "$P4" commit -q -m p4
run "$P4" "$T/o_p4" --include-heavy
chk "P4: run with an accepted exclusion -> rc 0" "$RC" "0"
has "P4: summary lists the excluded file" '^EXCLUDED  tests/a/lib.sh' "$T/o_p4/summary.txt"
has "P4: RESULT line carries the excluded count" '^RESULT: PASS-FULL .*1 excluded' "$T/o_p4.log"

# --- 26 P5: a run_all that discards a member's status: that member is also run alone
P5="$T/p5"; mkroot "$P5"; P5C="$T/cnt_p5"
sut "$P5" tests/d/test_d1.sh "echo x >> $P5C.d1" 'exit 1'
sut "$P5" tests/d/test_d2.sh "echo x >> $P5C.d2" 'echo "passed=1 failed=0"'
sut "$P5" tests/d/run_all.sh 'h=$(cd "$(dirname "$0")" && pwd)' 'rc=0' 'bash "$h/test_d1.sh" || true' 'bash "$h/test_d2.sh" || rc=1' 'echo "RESULT: PASS=2 FAIL=0"' 'exit $rc'
gen "$P5"; gitc "$P5" add -A; gitc "$P5" commit -q -m p5
vfy "$P5" "$T/p5v.log"; chk "P5: manifest verifies" "$RC" "0"
run "$P5" "$T/o_p5" --include-heavy
chk "P5: status-discarded failing member fails the run (rc 1)" "$RC" "1"
chk "P5: discarded member verdict FAIL from its own run" "$(verdict "$T/o_p5" tests/d/test_d1.sh | cut -d'|' -f1)" "FAIL"
chk "P5: discarded member ran alone once more" "$(wc -l < "$P5C.d1")" "2"
chk "P5: consumed member ran only through run_all (golden-FALSE)" "$(wc -l < "$P5C.d2")" "1"

# --- 27 P6: KNOWN failures give PASS-FULL-WITH-KNOWN, never plain PASS-FULL
printf 'tests/a/test_kb.sh\tlock timeout\tATM-9\topen\n' > "$T/known_p6.tsv"
run "$K2" "$T/o_p6" --include-heavy --known "$T/known_p6.tsv"
chk "P6: KNOWN-only run -> rc 7" "$RC" "7"
has "P6: RESULT PASS-FULL-WITH-KNOWN" '^RESULT: PASS-FULL-WITH-KNOWN' "$T/o_p6.log"
hasnt "P6: never a plain PASS-FULL" '^RESULT: PASS-FULL \(' "$T/o_p6.log"

# --- 28 P7: topology preflight: an uninitialised submodule refuses the run unless allowed
TP="$T/topo"; mkroot "$TP"; sut "$TP" tests/a/test_tp.sh 'echo "passed=1 failed=0"'
gitc "$TP" -c protocol.file.allow=always submodule add -q "$SMR" sub >/dev/null 2>&1
gen "$TP"; gitc "$TP" add -A; gitc "$TP" commit -q -m tp
run "$TP" "$T/o_tp0" --include-heavy
chk "P7: initialised submodule -> rc 0 (golden-FALSE)" "$RC" "0"
has "P7: layout reported" 'topology: ' "$T/o_tp0/summary.txt"
gitc "$TP" submodule deinit -q -f sub >/dev/null 2>&1
run "$TP" "$T/o_tp1" --include-heavy
chk "P7: uninitialised submodule -> refused, rc 9" "$RC" "9"
has "P7: gap named" 'uninitialised submodule: sub' "$T/o_tp1.log"
if [ -e "$T/o_tp1/results.jsonl" ]; then ko "P7: refused run ran nothing"; else ok "P7: refused run ran nothing"; fi
run "$TP" "$T/o_tp2" --include-heavy --allow-topology-gaps
chk "P7: --allow-topology-gaps -> rc 8" "$RC" "8"
has "P7: RESULT PARTIAL-TOPOLOGY" '^RESULT: PARTIAL-TOPOLOGY' "$T/o_tp2.log"

# --- 29 P8: census covers *.js, *.bats and extension-less shebang smoke files outside tests/
P8="$T/p8"; mkroot "$P8"; mkdir -p "$P8/tools"
printf '#!/usr/bin/env node\nconsole.log("passed=1 failed=0");\n' > "$P8/tests/a/test_x.js"
printf '#!/usr/bin/env bats\n@test "a" { true; }\n' > "$P8/tests/a/x.bats"
printf '#!/usr/bin/env bash\necho "passed=1 failed=0"\n' > "$P8/tools/smoke_check"
gen "$P8"
chk "P8: js test in the manifest" "$(awk -F'\t' '$1=="tests/a/test_x.js"{print $2"|"$5}' "$P8/config/full_suite_manifest.tsv")" "js|node"
chk "P8: bats test in the manifest" "$(awk -F'\t' '$1=="tests/a/x.bats"{print $2"|"$5}' "$P8/config/full_suite_manifest.tsv")" "bats|bats"
chk "P8: extension-less shebang smoke file in the manifest" "$(awk -F'\t' '$1=="tools/smoke_check"{print $2"|"$5}' "$P8/config/full_suite_manifest.tsv")" "sh|bash"
grep -v '^tests/a/test_x.js' "$P8/config/full_suite_manifest.tsv" > "$T/p8m"; cp "$T/p8m" "$P8/config/full_suite_manifest.tsv"
vfy "$P8" "$T/p8v.log"; chk "P8: an unlisted js test refuses -> exit 3" "$RC" "3"
gen "$P8"
if command -v node >/dev/null 2>&1; then
  run "$P8" "$T/o_p8" --include-heavy --only 'test_x'
  chk "P8: js unit runs under node" "$(verdict "$T/o_p8" tests/a/test_x.js | cut -d'|' -f1)" "PASS"
fi
if ! command -v bats >/dev/null 2>&1; then
  run "$P8" "$T/o_p8b" --include-heavy --only 'x.bats'
  chk "P8: absent runner is an honest SKIP" "$(verdict "$T/o_p8b" tests/a/x.bats | cut -d'|' -f1,2)" "SKIP|runner_not_installed"
fi

# =========================================================================== round 5 (review r4 F1 F2 F6)
# --- 30 F1: a drifted submodule is a topology gap; a dirty tree never ends PASS-FULL; identity recorded
TD="$T/tdrift"; mkroot "$TD"; sut "$TD" tests/a/test_td.sh 'echo "passed=1 failed=0"'
gitc "$TD" -c protocol.file.allow=always submodule add -q "$SMR" sub >/dev/null 2>&1
gen "$TD"; gitc "$TD" add -A; gitc "$TD" commit -q -m td
run "$TD" "$T/o_td0" --include-heavy
chk "F1: clean committed tree -> rc 0 (golden-FALSE)" "$RC" "0"
has "F1: identity in the PASS-FULL RESULT line" '^RESULT: PASS-FULL .*head=[0-9a-f]{12} subs=[0-9a-f]{16} dirty=clean' "$T/o_td0.log"
has "F1: identity in summary.txt" '^identity of the code that ran: head=' "$T/o_td0/summary.txt"
chk "F1: each record carries the identity" "$(rec "$T/o_td0" tests/a/test_td.sh ident | sed 's/head=[0-9a-f]*/H/')" "H subs=$(rec "$T/o_td0" tests/a/test_td.sh ident | sed 's/.*subs=\([0-9a-f]*\).*/\1/') dirty=clean"
echo z > "$TD/sub/g"; gitc "$TD/sub" add g; gitc "$TD/sub" commit -q -m drift
run "$TD" "$T/o_td1" --include-heavy
chk "F1: drifted submodule (+) refused -> rc 9" "$RC" "9"
has "F1: drift named" 'drifted submodule: sub' "$T/o_td1.log"
run "$TD" "$T/o_td2" --include-heavy --allow-topology-gaps
chk "F1: drift allowed -> not green (rc 8)" "$RC" "8"
hasnt "F1: drift never PASS-FULL" '^RESULT: PASS-FULL' "$T/o_td2.log"
gitc "$TD/sub" reset -q --hard HEAD~1
run "$TD" "$T/o_td3" --include-heavy
chk "F1: submodule back at the recorded commit -> rc 0" "$RC" "0"
echo "# local edit" >> "$TD/tests/a/test_td.sh"
run "$TD" "$T/o_td4" --include-heavy
chk "F1: modified tracked file -> PARTIAL-DIRTY-TREE rc 10" "$RC" "10"
has "F1: RESULT PARTIAL-DIRTY-TREE" '^RESULT: PARTIAL-DIRTY-TREE .*dirty=[0-9a-f]{16}' "$T/o_td4.log"
has "F1: dirty path listed" '^DIRTY .*tests/a/test_td.sh' "$T/o_td4/summary.txt"
gitc "$TD" checkout -q -- tests/a/test_td.sh
echo u > "$TD/untracked.txt"
run "$TD" "$T/o_td5" --include-heavy
chk "F1: untracked file -> rc 10" "$RC" "10"
rm -f "$TD/untracked.txt"
echo dirt > "$TD/sub/inner.txt"
run "$TD" "$T/o_td6" --include-heavy
chk "F1: untracked file inside a submodule -> rc 10" "$RC" "10"
has "F1: submodule dirt listed" '^DIRTY .*sub' "$T/o_td6/summary.txt"
rm -f "$TD/sub/inner.txt"

# --- 31 O9: a failing `git submodule status` is a gap (fail closed), never gaps=0
TS="$T/tsfail"; mkroot "$TS"; sut "$TS" tests/a/test_ts.sh 'echo "passed=1 failed=0"'
gitc "$TS" -c protocol.file.allow=always submodule add -q "$SMR" sub >/dev/null 2>&1
gen "$TS"; gitc "$TS" add -A; gitc "$TS" commit -q -m ts
gitc "$TS" rm -q --cached .gitmodules >/dev/null 2>&1; rm -f "$TS/.gitmodules"; gitc "$TS" commit -q -m nogm
git -C "$TS" submodule status --recursive >/dev/null 2>&1; smrc=$?
if [ "$smrc" -ne 0 ]; then
  run "$TS" "$T/o_ts" --include-heavy
  chk "O9: failing submodule status refused -> rc 9" "$RC" "9"
  has "O9: failure named" 'git submodule status failed' "$T/o_ts.log"
else
  ko "O9: fixture did not make git submodule status fail (rc $smrc): instrument blind"
fi

# --- 32 O5: a hand-edited excluded lock body is refused; F6: acceptance only by a rostered operator
cp "$P4/config/full_suite_excluded.lock" "$T/p4lock.bak"
sed -i 's/^\(tests\/a\/lib.sh\t\).*/\10123456789abcdef/' "$P4/config/full_suite_excluded.lock"
vfy "$P4" "$T/o5.log"; chk "O5: hand-edited lock body -> exit 3" "$RC" "3"
has "O5: hand edit named" 'edited by hand' "$T/o5.log"
cp "$T/p4lock.bak" "$P4/config/full_suite_excluded.lock"
vfy "$P4" "$T/o5b.log"; chk "O5: restored lock verifies (golden-FALSE)" "$RC" "0"
python3 -I - "$P4/config/full_suite_excluded.lock" <<'PYX'
import sys,re
p=sys.argv[1]; s=open(p).read()
s=re.sub(r"accepted_by=carol", "accepted_by=alice", s, count=1)
open(p,"w").write(s)
PYX
vfy "$P4" "$T/o5c.log"; chk "O5: acceptor rewritten in a chained line -> exit 3" "$RC" "3"
has "O5: broken chain named" 'acceptance chain broken' "$T/o5c.log"
cp "$T/p4lock.bak" "$P4/config/full_suite_excluded.lock"
n0=$(grep -c '^# accepted ' "$P4/config/full_suite_excluded.lock")
setrow "$P4/config/full_suite_manifest.tsv" tests/a/lib.sh 'tests/a/lib.sh\tsh\texcluded\t-\t-\t-\treason: tool: hand-run helper'
bash "$R" --root "$P4" --verify-manifest --accept-excluded-change mallory > "$T/f6a.log" 2>&1; RC=$?
chk "F6: acceptance by an id that is not on the roster -> exit 3" "$RC" "3"
has "F6: refusal names the roster" 'not an operator id' "$T/f6a.log"
chk "F6: refused acceptance appends nothing" "$(grep -c '^# accepted ' "$P4/config/full_suite_excluded.lock")" "$n0"
printf 'mallory\tself-added\n' >> "$P4/config/full_suite_operators.roster"
bash "$R" --root "$P4" --verify-manifest --accept-excluded-change mallory > "$T/f6b.log" 2>&1; RC=$?
chk "F6: id added to an uncommitted roster -> exit 3" "$RC" "3"
has "F6: uncommitted roster named" 'roster .* is not committed' "$T/f6b.log"
gitc "$P4" checkout -q -- config/full_suite_operators.roster
bash "$R" --root "$P4" --verify-manifest --accept-excluded-change bob > "$T/f6c.log" 2>&1; RC=$?
chk "F6: rostered operator accepts -> exit 0 (golden-FALSE)" "$RC" "0"
has "F6: new acceptance line is chained" 'accepted_by=bob set=[0-9a-f]{16} rows=1 chain=[0-9a-f]{16}$' "$P4/config/full_suite_excluded.lock"
gitc "$P4" add -A; gitc "$P4" commit -q -m f6
run "$P4" "$T/o_f6" --include-heavy
chk "F6: run with an operator-accepted exclusion -> rc 0" "$RC" "0"
has "F6: acceptor printed in summary.txt" '^EXCLUDED set last accepted_by: bob$' "$T/o_f6/summary.txt"
printf '# id\twho\nalice\toperator alice\n' > "$P4/config/full_suite_operators.roster"; gitc "$P4" commit -q -am "bob leaves"
run "$P4" "$T/o_f6b" --include-heavy
chk "F6: acceptor no longer on the roster -> PARTIAL-EXCLUSIONS-UNACCEPTED rc 11" "$RC" "11"
vfy "$P4" "$T/f6d.log"; chk "F6: verify still structurally OK (exit 0) and says why" "$RC" "0"
has "F6: verify note" '^NOTE: excluded set last accepted by .bob., who is not on the operator roster' "$T/f6d.log"

# --- 33 O7: KNOWN never applies to a nondeterministic unit (exit 1, never 7)
FK2="$T/flaky_known"; mkroot "$FK2"; FC2="$T/cnt_flaky_known"
sut "$FK2" tests/a/test_fk.sh "echo x >> $FC2" "[ \$(wc -l < $FC2) -ge 2 ] || { echo 'boom: lock timeout'; exit 1; }" 'echo "passed=1 failed=0"'
gen "$FK2"; gitc "$FK2" add -A; gitc "$FK2" commit -q -m fk
printf 'tests/a/test_fk.sh\tlock timeout\tATM-11\topen\n' > "$T/known_fk.tsv"
run "$FK2" "$T/o_fk" --include-heavy --known "$T/known_fk.tsv"
chk "O7: first run KNOWN-only -> rc 7" "$RC" "7"
run "$FK2" "$T/o_fk" --include-heavy --known "$T/known_fk.tsv" --rerun-nonpass
chk "O7: flipping unit with a KNOWN row -> rc 1 (never 7)" "$RC" "1"
has "O7: nondeterminism reported" 'NONDETERMINISTIC=1' "$T/o_fk.log"
hasnt "O7: no KNOWN tag on a flipping unit" 'KNOWN ATM-11' "$T/o_fk/summary.txt"

# =========================================================================== round 6 (review r5 R5-1 R5-2 R5-6)
# --- 34 R5-1: the identity (HEAD of the root and of every submodule, root status) is verified before
# every unit and at the end; any change ends FAIL, and no later unit is run or credited to the start HEAD
HM="$T/headmove"; mkroot "$HM"
sut "$HM" tests/a/test_1.sh "git -C '$HM' checkout -q bb 2>/dev/null; echo 'passed=1 failed=0'; exit 0"
sut "$HM" tests/a/test_2.sh 'echo "passed=0 failed=1"; exit 1'
gen "$HM"; gitc "$HM" add -A; gitc "$HM" commit -q -m A; HMA=$(git -C "$HM" rev-parse HEAD)
gitc "$HM" checkout -q -b bb; sut "$HM" tests/a/test_2.sh 'echo "passed=1 failed=0"'; gitc "$HM" commit -q -am B
gitc "$HM" checkout -q "$HMA"
run "$HM" "$T/o_hm" --include-heavy
chk "R5-1: HEAD moved by a unit mid-run -> rc 1" "$RC" "1"
has "R5-1: RESULT names the identity change" '^RESULT: FAIL \(identity changed during the run' "$T/o_hm.log"
has "R5-1: summary says where it changed (C02: checked after every unit too)" '^IDENTITY CHANGED after unit tests/a/test_1.sh' "$T/o_hm/summary.txt"
chk "R5-1: the unit after the move is not run (never credited to the start HEAD)" "$(verdict "$T/o_hm" tests/a/test_2.sh)" ""
hasnt "R5-1: never PASS-FULL" '^RESULT: PASS' "$T/o_hm.log"
gitc "$HM" checkout -q "$HMA"
HM2="$T/headmove_last"; mkroot "$HM2"
sut "$HM2" tests/a/test_1.sh "git -C '$HM2' checkout -q bb 2>/dev/null; echo 'passed=1 failed=0'; exit 0"
gen "$HM2"; gitc "$HM2" add -A; gitc "$HM2" commit -q -m A; HM2A=$(git -C "$HM2" rev-parse HEAD)
gitc "$HM2" checkout -q -b bb; gitc "$HM2" commit -q --allow-empty -m B; gitc "$HM2" checkout -q "$HM2A"
run "$HM2" "$T/o_hm2" --include-heavy
chk "R5-1: HEAD moved by the last unit -> rc 1 (end check)" "$RC" "1"
has "R5-1: a move by the last unit is caught after that unit" '^IDENTITY CHANGED after unit tests/a/test_1.sh' "$T/o_hm2/summary.txt"
HM3="$T/submove"; mkroot "$HM3"
gitc "$HM3" -c protocol.file.allow=always submodule add -q "$SMR" sub >/dev/null 2>&1
sut "$HM3" tests/a/test_1.sh "git -C '$HM3/sub' -c user.email=a@b -c user.name=t commit -q --allow-empty -m moved; echo 'passed=1 failed=0'"
sut "$HM3" tests/a/test_2.sh 'echo "passed=1 failed=0"'
gen "$HM3"; gitc "$HM3" add -A; gitc "$HM3" commit -q -m sm
run "$HM3" "$T/o_hm3" --include-heavy
chk "R5-1: a submodule HEAD moved mid-run -> rc 1" "$RC" "1"
has "R5-1: submodule move caught after the moving unit" '^IDENTITY CHANGED after unit tests/a/test_1.sh' "$T/o_hm3/summary.txt"
HG="$T/headread"; mkroot "$HG"
sut "$HG" tests/a/test_1.sh "git -C '$HG' log -1 --oneline >/dev/null; git -C '$HG' status --short >/dev/null; echo 'passed=1 failed=0'"
sut "$HG" tests/a/test_2.sh 'echo "passed=1 failed=0"'
gen "$HG"; gitc "$HG" add -A; gitc "$HG" commit -q -m g
run "$HG" "$T/o_hg" --include-heavy
chk "R5-1: units that only read git -> rc 0 (golden-FALSE)" "$RC" "0"
hasnt "R5-1: no identity change reported (golden-FALSE)" 'IDENTITY CHANGED' "$T/o_hg/summary.txt"

# --- 35 R5-6 (M4): a dirty tree with KNOWN failures is PARTIAL-DIRTY-TREE (10), never PASS-FULL-WITH-KNOWN (7)
DK="$T/dirtyknown"; mkroot "$DK"; sut "$DK" tests/a/test_dk.sh "echo 'boom: lock timeout'; exit 1"
gen "$DK"; gitc "$DK" add -A; gitc "$DK" commit -q -m dk
printf 'tests/a/test_dk.sh\tlock timeout\tATM-12\topen\n' > "$T/known_dk.tsv"
run "$DK" "$T/o_dk0" --include-heavy --known "$T/known_dk.tsv"
chk "M4 pin: clean tree, KNOWN-only -> rc 7 (control)" "$RC" "7"
echo u > "$DK/untracked.txt"
run "$DK" "$T/o_dk1" --include-heavy --known "$T/known_dk.tsv"
chk "M4 pin: dirty tree + KNOWN -> rc 10" "$RC" "10"
hasnt "M4 pin: never PASS-FULL-WITH-KNOWN on a dirty tree" '^RESULT: PASS-FULL' "$T/o_dk1.log"

# --- 36 R5-6 (M7): a failing git status in the identity check reads dirty=unknown and is rc 10 (fail closed)
GS="$T/gitshim"; mkdir -p "$GS"; REALGIT=$(command -v git)
{ echo '#!/usr/bin/env bash'
  echo 'z=0; p=0; for a in "$@"; do case "$a" in -z) z=1;; --porcelain=v1) p=1;; esac; done'
  echo 'if [ "$p" = 1 ] && [ "$z" = 0 ]; then echo "shim: status refused" >&2; exit 128; fi'
  echo "exec '$REALGIT' \"\$@\""; } > "$GS/git"; chmod +x "$GS/git"
GF="$T/gitfail"; mkroot "$GF"; sut "$GF" tests/a/test_gf.sh 'echo "passed=1 failed=0"'
gen "$GF"; gitc "$GF" add -A; gitc "$GF" commit -q -m gf
run "$GF" "$T/o_gf0" --include-heavy
chk "M7 pin: control without the shim -> rc 0" "$RC" "0"
PATH="$GS:$PATH" bash "$R" --root "$GF" --out "$T/o_gf" --include-heavy >"$T/o_gf.log" 2>&1; RC=$?
chk "M7 pin: failing git status -> rc 10" "$RC" "10"
has "M7 pin: identity reads dirty=unknown" 'dirty=unknown' "$T/o_gf.log"
has "M7 pin: the failure is listed" 'git status failed' "$T/o_gf/summary.txt"

# --- 37 R5-2: a roster or excluded lock that is a symlink is refused (its edits would leave no git trace)
RS="$T/rsym"; mkroot "$RS"
sut "$RS" tests/a/lib.sh 'f() { :; }'
sut "$RS" tests/a/test_uses_lib.sh '. "$(dirname "$0")/lib.sh"' 'echo "passed=1 failed=0"'
gen "$RS"; gitc "$RS" add -A; gitc "$RS" commit -q -m base
printf '# id\twho\nalice\toperator alice\n' > "$T/outside_roster"
ln -s "$T/outside_roster" "$RS/config/full_suite_operators.roster"; gitc "$RS" add -A; gitc "$RS" commit -q -m link
bash "$R" --root "$RS" --verify-manifest --accept-excluded-change alice > "$T/rs1.log" 2>&1; RC=$?
chk "R5-2: acceptance through a symlinked roster -> exit 3" "$RC" "3"
has "R5-2: symlinked roster named" 'roster .* is a symlink' "$T/rs1.log"
hasnt "R5-2: nothing accepted" 'accepted_by=alice' "$RS/config/full_suite_excluded.lock"
gitc "$RS" rm -q --cached config/full_suite_operators.roster; rm -f "$RS/config/full_suite_operators.roster"
cp "$T/outside_roster" "$RS/config/full_suite_operators.roster"; gitc "$RS" add -A; gitc "$RS" commit -q -m real
bash "$R" --root "$RS" --verify-manifest --accept-excluded-change alice > "$T/rs2.log" 2>&1; RC=$?
chk "R5-2: regular committed roster -> accepted (golden-FALSE)" "$RC" "0"
gitc "$RS" add -A; gitc "$RS" commit -q -m acc
mv "$RS/config/full_suite_excluded.lock" "$T/outside_lock"; ln -s "$T/outside_lock" "$RS/config/full_suite_excluded.lock"
gitc "$RS" add -A; gitc "$RS" commit -q -m locklink
vfy "$RS" "$T/rs3.log"; chk "R5-2: symlinked excluded lock -> exit 3" "$RC" "3"
has "R5-2: symlinked lock named" 'full_suite_excluded.lock is a symlink' "$T/rs3.log"

# --- CON-030: a submodule path with a space (or a TAB) survives sub_paths / topology / quick_ident / ident_diff
# (`git submodule status` is `<flag><sha> <path>[ (<describe>)]`; whitespace splitting truncated "sub dir" to "sub",
# so topology reported a bogus "recorded commit not in object store" gap and a clean checkout was REFUSED-TOPOLOGY)
sp="$T/spacesub"; mkdir -p "$sp"; git init -q "$sp/lib"; gitc "$sp/lib" commit -q --allow-empty -m i
for k in plain spaced tabbed; do mkroot "$sp/$k"; done
sut "$sp/spaced" tests/a/test_sp.sh 'echo "passed=1 failed=0"'
git -C "$sp/plain" -c protocol.file.allow=always submodule add -q "$sp/lib" plain >/dev/null 2>&1
git -C "$sp/spaced" -c protocol.file.allow=always submodule add -q "$sp/lib" "sub dir" >/dev/null 2>&1
git -C "$sp/tabbed" -c protocol.file.allow=always submodule add -q "$sp/lib" "$(printf 'a\tb')" >/dev/null 2>&1
gen "$sp/spaced"
for k in plain spaced tabbed; do gitc "$sp/$k" add -A; gitc "$sp/$k" commit -q -m s; done
con030() { python3 -I - "$ENGINE" "$1" <<'PY'
import sys, importlib.util
s = importlib.util.spec_from_file_location("e", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
subs = m.sub_paths(sys.argv[2]); a = m.quick_ident(sys.argv[2], subs); b = m.quick_ident(sys.argv[2], subs)
print(subs, m.topology(sys.argv[2])[2], repr(m.ident_diff(a, b)))
PY
}
chk "CON-030 control: a path without a space is read whole (sub_paths, topology gaps, ident_diff)" "$(con030 "$sp/plain")" "['plain'] [] ''"
chk "CON-030 sub_paths/topology/ident_diff keep a path with a space" "$(con030 "$sp/spaced")" "['sub dir'] [] ''"
chk "CON-030 sub_paths/topology/ident_diff keep a path with a TAB" "$(con030 "$sp/tabbed")" "['a\\tb'] [] ''"
run "$sp/spaced" "$T/o_con030" --include-heavy
chk "CON-030 end to end: a clean checkout with a spaced submodule path runs (rc 0, not REFUSED-TOPOLOGY rc 9)" "$RC" "0"
has "CON-030 end to end: topology reports 1 submodule and no gap" 'topology: .*submodules=1 gaps=0' "$T/o_con030/summary.txt"
# ident_diff must name the spaced submodule when only its HEAD moved (the identity string must round-trip a spaced path)
git -C "$sp/spaced/sub dir" -c user.email=a@b -c user.name=t commit -q --allow-empty -m moved
chk "CON-030 ident_diff names a spaced submodule whose HEAD moved (identity round-trips the path)" "$(python3 -I - "$ENGINE" "$sp/spaced" <<'PY'
import sys, importlib.util, subprocess
s = importlib.util.spec_from_file_location("e", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
root = sys.argv[2]; subs = m.sub_paths(root)
now = m.quick_ident(root, subs)
subprocess.run(["git", "-C", root + "/sub dir", "reset", "-q", "--hard", "HEAD~1"], check=True)
before = m.quick_ident(root, subs)
d = m.ident_diff(before, now)
print(d.startswith("submodule 'sub dir' "), d.count("->"))
PY
)" "True 2"
# topology: an unparseable `git submodule status` line is a gap (fail closed), never skipped silently (git shim prints one)
GB="$T/con030_gitshim"; mkdir -p "$GB"; REALGIT=$(command -v git)
printf '#!/bin/sh\ncase " $* " in *" submodule status "*) echo "not a status line"; exit 0;; esac\nexec %s "$@"\n' "$REALGIT" > "$GB/git"; chmod +x "$GB/git"
chk "CON-030 topology: an unparseable submodule status line is a gap" "$(PATH="$GB:$PATH" python3 -I - "$ENGINE" "$sp/plain" <<'PY'
import sys, importlib.util
s = importlib.util.spec_from_file_location("e", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
print(m.topology(sys.argv[2])[2])
PY
)" "[\"unparseable git submodule status line (not <flag><sha> <one known submodule path>[ (<describe>)]): 'not a status line'\"]"
# a status line that does not parse (e.g. a path fragment after a newline) is None, never a guess: topology turns it into a gap
chk "CON-030 parse_sub_status: unparseable line -> None, spaced + described + uninitialised lines parsed whole" "$(python3 -I - "$ENGINE" <<'PY'
import sys, importlib.util
s = importlib.util.spec_from_file_location("e", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
h = "0123456789abcdef0123456789abcdef01234567"; k = {"sub dir", "e (f)"}
print([m.parse_sub_status(x, k) for x in ("tail of a split path", " " + h + " sub dir (heads/main)", "-" + h + " sub dir", "+" + h + " e (f) (v1-2-gabc)")])
PY
)" "[None, (' ', '0123456789abcdef0123456789abcdef01234567', 'sub dir'), ('-', '0123456789abcdef0123456789abcdef01234567', 'sub dir'), ('+', '0123456789abcdef0123456789abcdef01234567', 'e (f)')]"

# --- CON-030 round 2 (review r1 F1 F2 F4 F6 F8 F9): submodule paths come from the machine format `git ls-files -s -z`
# (recursive); the `git submodule status` line supplies only the flag and the sha and must name exactly one of those
# paths. Round 1 stripped a trailing ` (describe)` only when it held no parenthesis, so a branch `feat(x)` or a tag
# `v1(beta)` was swallowed into the path (a valid checkout refused, rc 9). Each case below is real git output.
mp="$T/manysub"; mkroot "$mp"; git init -q "$mp.ln"; gitc "$mp.ln" commit -q --allow-empty -m i
git -C "$mp.ln" -c protocol.file.allow=always submodule add -q "$sp/lib" "in ner" >/dev/null 2>&1; gitc "$mp.ln" commit -q -m n
for p in plainb plaint plainc 'x (xyz)' ' lead' 'trail ' "$(printf 'cr\rx')" 'par(1)' 'q?' 'k=v'; do
  git -C "$mp" -c protocol.file.allow=always submodule add -q "$sp/lib" "$p" >/dev/null 2>&1
done
git -C "$mp" -c protocol.file.allow=always submodule add -q "$mp.ln" "nest ed" >/dev/null 2>&1
git -C "$mp" -c protocol.file.allow=always submodule update -q --init --recursive >/dev/null 2>&1
gitc "$mp/plainb" checkout -q -b 'feat(x)'; gitc "$mp/plainb" branch -q -D master >/dev/null 2>&1; gitc "$mp/plainb" branch -q -D main >/dev/null 2>&1
gitc "$mp/plaint" tag 'v1(beta)'; gitc "$mp/plainc" tag 'v2)'
sut "$mp" tests/a/test_mp.sh 'echo "passed=1 failed=0"'; gen "$mp"; gitc "$mp" add -A; gitc "$mp" commit -q -m s
git -C "$mp" submodule status --recursive > "$T/mp_status.txt" 2>&1
# precondition (section 11.4.199): git really printed each describe shape this case is about
for d in ' plainb (heads/feat(x))' ' plaint (v1(beta))' ' plainc (v2))' ' x (xyz) (heads/' ' nest ed/in ner (heads/'; do
  if grep -qF -- "$d" "$T/mp_status.txt"; then ok "CON-030 r2 precondition: status prints '$d'"
  else ko "CON-030 r2 precondition: status prints '$d' ($(tr '\n' '|' < "$T/mp_status.txt"))"; fi
done
con030b() { python3 -I - "$ENGINE" "$1" <<'PY'
import sys, importlib.util
s = importlib.util.spec_from_file_location("e", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
root = sys.argv[2]; subs = m.sub_paths(root); a = m.quick_ident(root, subs); b = m.quick_ident(root, subs)
print(sorted(subs), sorted(m.topology(root)[2]), repr(m.ident_diff(a, b)), m.ident_unknown(a))
PY
}
want_mp="[' lead', 'cr\\rx', 'k=v', 'nest ed', 'nest ed/in ner', 'par(1)', 'plainb', 'plainc', 'plaint', 'q?', 'trail ', 'x (xyz)'] [] '' False"
chk "CON-030 r2: describe with ( ) / a ')'-only tag / 'x (xyz)' / leading+trailing space / CR / '?' / '=' / nested paths read whole, 0 gaps" "$(con030b "$mp")" "$want_mp"
run "$mp" "$T/o_con030b" --include-heavy
chk "CON-030 r2 end to end: branch feat(x), tag v1(beta), tag v2) and the rest run (rc 0, not REFUSED-TOPOLOGY)" "$RC" "0"
has "CON-030 r2 end to end: 12 submodules, no gap" 'topology: .*submodules=12 gaps=0' "$T/o_con030b/summary.txt"
chk "CON-030 r2 submodule_paths (census exclusion): .gitmodules + gitlinks read whole (-z / --null)" "$(python3 -I - "$ENGINE" "$mp" <<'PY'
import sys, importlib.util
s = importlib.util.spec_from_file_location("e", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
print(m.submodule_paths(sys.argv[2]))
PY
)" "[' lead', 'cr\\rx', 'k=v', 'nest ed', 'par(1)', 'plainb', 'plainc', 'plaint', 'q?', 'trail ', 'x (xyz)']"
# F8: a '=' in a path keeps its own key in ident_diff (the value is after the LAST '=')
chk "CON-030 r2 ident_diff names a submodule 'k=v' whose HEAD moved" "$(python3 -I - "$ENGINE" "$mp" <<'PY'
import sys, importlib.util, subprocess
s = importlib.util.spec_from_file_location("e", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
root = sys.argv[2]; subs = m.sub_paths(root); before = m.quick_ident(root, subs)
subprocess.run(["git", "-C", root + "/k=v", "-c", "user.email=a@b", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "mv"], check=True)
d = m.ident_diff(before, m.quick_ident(root, subs))
subprocess.run(["git", "-C", root + "/k=v", "reset", "-q", "--hard", "HEAD~1"], check=True)
print(d.startswith("submodule 'k=v' "), d.count("->"))
PY
)" "True 2"
# uninitialised (fresh clone): every path whole, `x (xyz)` included (git prints no describe on a `-` line), and
# sub_paths() returns none of them (the `-` filter)
git clone -q "$mp" "$mp.fresh" >/dev/null 2>&1
chk "CON-030 r2 uninitialised: gaps name each path whole, sub_paths() is empty" "$(python3 -I - "$ENGINE" "$mp.fresh" <<'PY'
import sys, importlib.util
s = importlib.util.spec_from_file_location("e", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
print(m.sub_paths(sys.argv[2]), sorted(g.split(": ", 1)[1] for g in m.topology(sys.argv[2])[2]))
PY
)" "[] [' lead', 'cr\\rx', 'k=v', 'nest ed', 'par(1)', 'plainb', 'plainc', 'plaint', 'q?', 'trail ', 'x (xyz)']"
# F3 / F9: a path with a newline (a hand-written .gitmodules; `git submodule add` refuses it) is printed by git across
# two lines; neither fragment names a known path, so both are gaps (fail closed) -- real git output, no shim
nlr="$T/nlsub"; mkroot "$nlr"; lsha=$(git -C "$sp/lib" rev-parse HEAD)
printf '[submodule "nl"]\n\tpath = "nl\\nx"\n\turl = %s\n' "$sp/lib" > "$nlr/.gitmodules"
gitc "$nlr" update-index --add --cacheinfo "160000,$lsha,$(printf 'nl\nx')"; gitc "$nlr" add .gitmodules; gitc "$nlr" commit -q -m nl
chk "CON-030 r2 newline path: both status fragments are unparseable gaps, sub_paths() empty" "$(python3 -I - "$ENGINE" "$nlr" <<'PY'
import sys, importlib.util
s = importlib.util.spec_from_file_location("e", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
g = m.topology(sys.argv[2])[2]
print(m.sub_paths(sys.argv[2]), len(g), g[0].startswith("submodule path contains a newline"), all(x.startswith("unparseable git submodule status line") for x in g[1:]), sorted(m.known_sub_paths(sys.argv[2])))
PY
)" "[] 3 True True ['nl\\nx']"
# parse_sub_status table: SHA-256 width, ambiguity, unknown path, describe with a space, '-'/'U' never carry a describe
chk "CON-030 r2 parse_sub_status table (sha256, ambiguous, unknown, spaced describe, '-' and 'U')" "$(python3 -I - "$ENGINE" <<'PY'
import sys, importlib.util
s = importlib.util.spec_from_file_location("e", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
h = "0123456789abcdef0123456789abcdef01234567"; h2 = h + "89abcdef0123456789abcdef"
rows = [(" " + h2 + " sub dir (heads/main)", {"sub dir"}), ("+" + h2 + " sub dir", {"sub dir"}),
        (" " + h + " x (y)", {"x", "x (y)"}), (" " + h + " x (y) (heads/main)", {"x", "x (y)"}),
        (" " + h + " zz (heads/main)", {"sub dir"}), (" " + h + " a (b c)", {"a"}),
        ("-" + h + " x (xyz)", {"x", "x (xyz)"}), ("U" + "0" * 40 + " con flict", {"con flict"}),
        (" " + h.upper() + " a", {"a"}), (" " + h + "  lead (heads/main)", {" lead", "lead"}), ("", {""}),
        (" " + h + " x (yz", {"x", "x (yz"}), (" " + h + " x ()", {"x", "x ()"})]
print([None if r is None else (r[0], len(r[1]), r[2]) for r in (m.parse_sub_status(l, k) for l, k in rows)])
PY
)" "[(' ', 64, 'sub dir'), ('+', 64, 'sub dir'), None, (' ', 40, 'x (y)'), None, None, ('-', 40, 'x (xyz)'), ('U', 40, 'con flict'), None, (' ', 40, ' lead'), None, (' ', 40, 'x (yz'), (' ', 40, 'x ()')]"

# --- CON-030 round 3 (review r2 G1-G4, G12; section 11.4.276(E)(3) structural round): the quick identity is a
# structure (QuickIdent: (path, value) pairs, root path None, unknown value None), not `<path>=<value>` text whose
# `status` key and `.`/`?` markers a submodule path could collide with. Every check below drives the real engine
# against repositories made with real git.
# G3: a submodule named `status` whose HEAD does not resolve. Round 2 read the identity into a dict, the root status
# field overwrote the submodule's `?`, and the run ended PASS-FULL (rc 0). The control is the same break on `other`.
for nm in status other; do
  g3="$T/g3_$nm"; mkroot "$g3"; sut "$g3" tests/a/test_g3.sh 'echo "passed=1 failed=0"'
  for p in plain "$nm"; do git -C "$g3" -c protocol.file.allow=always submodule add -q "$sp/lib" "$p" >/dev/null 2>&1; done
  gen "$g3"; gitc "$g3" add -A; gitc "$g3" commit -q -m s
  gd=$(git -C "$g3/$nm" rev-parse --absolute-git-dir); printf 'ref: refs/heads/unborn-r3\n' > "$gd/HEAD"
  if git -C "$g3/$nm" rev-parse HEAD >/dev/null 2>&1; then ko "CON-030 r3 G3 precondition: HEAD of '$nm' does not resolve"
  else ok "CON-030 r3 G3 precondition: HEAD of '$nm' does not resolve"; fi
  run "$g3" "$T/o_g3_$nm" --include-heavy
  chk "CON-030 r3 G3: unresolvable HEAD in submodule '$nm' -> rc 1 (never PASS-FULL)" "$RC" "1"
  has "CON-030 r3 G3: RESULT FAIL names the identity ('$nm')" '^RESULT: FAIL \(identity changed during the run' "$T/o_g3_$nm.log"
  has "CON-030 r3 G3: IDENTITY CHANGED names submodule '$nm' as unknown at both ends" "^IDENTITY CHANGED before unit tests/a/test_g3.sh: submodule '$nm' \? -> \?" "$T/o_g3_$nm.log"
  hasnt "CON-030 r3 G3: the root status is not reported for '$nm' (its value did not change)" 'root status' "$T/o_g3_$nm.log"
done
# QuickIdent: unknown is per value, whatever the path; labels of the root fields cannot be produced by any path
chk "CON-030 r3 QuickIdent: unknown per value, never per path; labels distinct" "$(python3 -I - "$ENGINE" <<'PY'
import sys, importlib.util
s = importlib.util.spec_from_file_location("e", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
Q, h = m.QuickIdent, "0" * 40
good = Q(((None, h), ("status", h), ("?", h), ("status=?", h), (".", h), ("gen", h)), "abc", "def")
print(m.ident_unknown(good), m.ident_unknown(Q(((None, h), ("status", None)), "abc", "def")),
      m.ident_unknown(Q(((None, h),), None, "def")), m.ident_unknown(Q(((None, None),), "abc", "def")),
      m.ident_unknown(Q(((None, h),), "abc", None)),
      len(set(map(m.ident_label, [("head", None), ("status",), ("gen",), ("head", "status"), ("head", "root HEAD"),
                                    ("head", "root status"), ("head", "."), ("head", "gen"),
                                    ("head", "generated sets")]))),
      m.ident_diff(good, Q(((None, h), ("status", None), ("?", h), ("status=?", h), (".", h), ("gen", h)), "abc", "def")),
      "|", m.ident_diff(good, good._replace(gen=None)))
PY
)" "False True True True True 9 submodule 'status' 000000000000 -> ? | generated sets def -> ?"
# RV7 successor: a CR-class path is named exactly in IDENTITY CHANGED (repr), never cut at the CR
chk "CON-030 r3 ident_diff names a submodule 'cr\\rx' whose HEAD moved, exactly" "$(python3 -I - "$ENGINE" "$mp" <<'PY'
import sys, importlib.util, subprocess
s = importlib.util.spec_from_file_location("e", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
root = sys.argv[2]; subs = m.sub_paths(root); before = m.quick_ident(root, subs); p = root + "/cr\rx"
subprocess.run(["git", "-C", p, "-c", "user.email=a@b", "-c", "user.name=t", "commit", "-q", "--allow-empty", "-m", "mv"], check=True)
d = m.ident_diff(before, m.quick_ident(root, subs))
subprocess.run(["git", "-C", p, "reset", "-q", "--hard", "HEAD~1"], check=True)
print(d.split(" -> ")[0].rsplit(" ", 1)[0], d.count("->"))
PY
)" "submodule 'cr\\rx' 2"

# G1: a submodule path that is not UTF-8 is read as the bytes git gave (os.fsdecode, surrogateescape), so `git -C`
# finds it: round 2 decoded it to U+FFFD and refused a clean checkout (REFUSED-TOPOLOGY rc 9)
u8="$T/u8sub"; mkroot "$u8"; sut "$u8" tests/a/test_u8.sh 'echo "passed=1 failed=0"'
git -C "$u8" -c protocol.file.allow=always submodule add -q "$sp/lib" "$(printf 'bad\377name')" >/dev/null 2>&1
gen "$u8"; gitc "$u8" add -A; gitc "$u8" commit -q -m s
if [ -n "$(git -C "$u8" ls-files -s -z | tr '\0' '\n' | grep -a "$(printf 'bad\377name')")" ]; then ok "CON-030 r3 G1 precondition: git recorded the non-UTF-8 path"
else ko "CON-030 r3 G1 precondition: git recorded the non-UTF-8 path"; fi
run "$u8" "$T/o_u8" --include-heavy
chk "CON-030 r3 G1: a clean checkout with a non-UTF-8 submodule path runs (rc 0, not REFUSED-TOPOLOGY)" "$RC" "0"
has "CON-030 r3 G1: topology reports 1 submodule and no gap" 'topology: .*submodules=1 gaps=0' "$T/o_u8/summary.txt"
git clone -q "$u8" "$u8.fresh" >/dev/null 2>&1
chk "CON-030 r3 G1: an uninitialised non-UTF-8 path is named with \\xNN in its gap" "$(python3 -I - "$ENGINE" "$u8.fresh" <<'PY'
import sys, importlib.util
s = importlib.util.spec_from_file_location("e", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
print(m.topology(sys.argv[2])[2], m.known_sub_paths(sys.argv[2]) == {"bad\udcffname"})
PY
)" "['uninitialised submodule: bad\\\\xffname'] True"

# G2: a newline path whose status fragments each equal a known path (nlD: submodules `a`, `b` and `a\n <sha> b`).
# Round 2 parsed the fragments as `a` and `b` (0 gaps, `b` twice); now the newline path is a gap of its own and a
# path named by two lines is a gap, so such a checkout is REFUSED-TOPOLOGY, never silently half-read.
nld="$T/nldsub"; mkroot "$nld"; sut "$nld" tests/a/test_nl.sh 'echo "passed=1 failed=0"'
for p in a b; do git -C "$nld" -c protocol.file.allow=always submodule add -q "$sp/lib" "$p" >/dev/null 2>&1; done
gen "$nld"; lsha=$(git -C "$sp/lib" rev-parse HEAD)
printf '[submodule "nl"]\n\tpath = "a\\n %s b"\n\turl = %s\n' "$lsha" "$sp/lib" >> "$nld/.gitmodules"
gitc "$nld" add -A; gitc "$nld" update-index --add --cacheinfo "160000,$lsha,$(printf 'a\n %s b' "$lsha")"; gitc "$nld" commit -q -m nl
git -C "$nld" submodule status --recursive > "$T/nld_status.txt" 2>&1
if [ "$(grep -c "^-$lsha a\$" "$T/nld_status.txt")" = 1 ] && [ "$(grep -c "^ $lsha b\$" "$T/nld_status.txt")" = 1 ]; then
  ok "CON-030 r3 G2 precondition: git prints the newline path as fragments equal to 'a' and 'b'"
else ko "CON-030 r3 G2 precondition: git prints the newline path as fragments equal to 'a' and 'b' ($(tr '\n' '|' < "$T/nld_status.txt"))"; fi
chk "CON-030 r3 G2: newline path gap + one gap per doubly named path, sub_paths without duplicates" "$(python3 -I - "$ENGINE" "$nld" <<'PY'
import sys, importlib.util
s = importlib.util.spec_from_file_location("e", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
g = m.topology(sys.argv[2])[2]
print(m.sub_paths(sys.argv[2]), [x.split(" (", 1)[0] if x.startswith("submodule path") else x for x in g])
PY
)" "['a', 'b'] ['submodule path contains a newline', 'submodule a is named by more than one status line', 'submodule b is named by more than one status line']"
run "$nld" "$T/o_nld" --include-heavy
chk "CON-030 r3 G2 end to end: the nlD checkout is REFUSED-TOPOLOGY (rc 9), never PASS-FULL" "$RC" "9"

# class members outside the identity (section 11.4.276(C)): other in-band markers a user-controlled name can hit
# (1) Go module directory whose name starts with `?`: the census used `"?" + path` as its "no module" marker
gm="$T/gomodq"; mkroot "$gm"; mkdir -p "$gm/?mod" "$gm/plainmod"
for d in "?mod" plainmod; do printf 'module example.com/m\n\ngo 1.21\n' > "$gm/$d/go.mod"
  printf 'package m\nimport "testing"\nfunc TestX(t *testing.T) {}\n' > "$gm/$d/x_test.go"; done
gitc "$gm" add -A; gitc "$gm" commit -q -m go; gen "$gm"
chk "CON-030 r3 class: a Go module in directory '?mod' gets its go-test row (was dropped)" \
  "$(awk -F'\t' '$5=="go-test"{printf "[%s]", $1}' "$gm/config/full_suite_manifest.tsv")" "[?mod][plainmod]"
# (2) a file name that starts with `#` (the manifest comment marker): named, not "census file without manifest row"
# (CON-030 r5 K12: --generate-manifest refuses a census problem, so the manifest is written before the bad file)
hm="$T/hashname"; mkroot "$hm"; sut "$hm" tests/a/test_ok.sh 'echo "passed=1 failed=0"'; gitc "$hm" add -A; gitc "$hm" commit -q -m ok; gen "$hm"; gitc "$hm" add -A; gitc "$hm" commit -q -m m
sut "$hm" '#t/test_h.sh' 'echo "passed=1 failed=0"'; gitc "$hm" add -A; gitc "$hm" commit -q -m h; vfy "$hm" "$T/hm.log"
chk "CON-030 r3 class: a '#'-leading test path -> --verify-manifest rc 3" "$RC" "3"
has "CON-030 r3 class: the '#' path is named as such" "census: file name that starts with '#' \(the manifest comment marker\) cannot be listed in the manifest: '#t/test_h.sh'" "$T/hm.log"
hasnt "CON-030 r3 class: not misreported as a missing manifest row" 'census file without manifest row' "$T/hm.log"
# (3) a test path with a CR. Round 3 listed it; round 4 refuses it as a named census problem, like LF and TAB
# (review r3 H3: its unit id forged RESULT lines on a terminal and in summary.txt), so no table holds a CR
cr="$T/crname"; mkroot "$cr"; sut "$cr" tests/a/test_ok.sh 'echo "passed=1 failed=0"'; gitc "$cr" add -A; gitc "$cr" commit -q -m ok; gen "$cr"; gitc "$cr" add -A; gitc "$cr" commit -q -m m
sut "$cr" "$(printf 'c\rd')/test_c.sh" 'echo "passed=1 failed=0"'; gitc "$cr" add -A; gitc "$cr" commit -q -m c; vfy "$cr" "$T/cr.log"
chk "CON-030 r4 H3: a test path with a CR -> --verify-manifest rc 3" "$RC" "3"
has "CON-030 r4 H3: the CR path is named, the CR escaped" "census: file name with a newline, TAB or other control or line-separator character \(U\+000D \(CR\)\) cannot be listed in the manifest: 'c\\\\rd/test_c.sh'" "$T/cr.log"
hasnt "CON-030 r4 H3: no raw CR byte on the output" $'\r' "$T/cr.log"
# (4) a test file whose name is not UTF-8: named; round 2 decoded it to U+FFFD, did not find it and dropped it silently
nu="$T/nonutf8"; mkroot "$nu"; sut "$nu" tests/a/test_ok.sh 'echo "passed=1 failed=0"'; gitc "$nu" add -A; gitc "$nu" commit -q -m ok; gen "$nu"; gitc "$nu" add -A; gitc "$nu" commit -q -m m
sut "$nu" "tests/a/$(printf 'test_\377.sh')" 'echo "passed=1 failed=0"'; gitc "$nu" add -A; gitc "$nu" commit -q -m u; vfy "$nu" "$T/nu.log"
chk "CON-030 r3 class: a non-UTF-8 test file name -> --verify-manifest rc 3 (was MANIFEST-OK without it)" "$RC" "3"
has "CON-030 r3 class: the non-UTF-8 name is named with \\xNN" 'census: file name that is not UTF-8 cannot be listed in the manifest: tests/a/test_\\xff\.sh' "$T/nu.log"
# (5) tree_state records are length-framed: a symlink target can no longer absorb the records after it, a non-UTF-8
# target is hashed (round 2 crashed on it), and an unreadable file is not a content
chk "CON-030 r3 class: tree_state framing (no absorbed record, non-UTF-8 target hashed)" "$(python3 -I - "$ENGINE" "$T/tsframe" <<'PY'
import sys, os, importlib.util, subprocess
s = importlib.util.spec_from_file_location("e", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
root = sys.argv[2]; os.makedirs(root)
subprocess.run(["git", "init", "-q", root], check=True); open(os.path.join(root, ".gitignore"), "w").write("a\nb\n")
a, b, res = os.path.join(root, "a"), os.path.join(root, "b"), []
for t1 in ("xIbLy", "xIbDLy"):  # the two record shapes an unframed hash merges (old tags, and the D tag added here)
    os.symlink("x", a); os.symlink("y", b); s2 = m.tree_state(root); os.remove(a); os.remove(b)
    os.symlink(t1, a); s1 = m.tree_state(root); os.remove(a); res.append(s1 != s2)
os.symlink(b"t\xff", a.encode()); s3 = m.tree_state(root); os.remove(a)
os.symlink(b"t\xfe", a.encode()); res.append(s3 != m.tree_state(root)); os.remove(a)
print(res, m.file_bytes(os.path.join(root, "nope")), m.file_digest(os.path.join(root, "nope").encode()))
PY
)" "[True, True, True] None None"
chk "CON-030 r3 class: file_bytes of an absent file differs from a file holding '<absent>'" "$(python3 -I - "$ENGINE" "$T/fbabs" <<'PY'
import sys, os, importlib.util
s = importlib.util.spec_from_file_location("e", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
os.makedirs(sys.argv[2]); p = os.path.join(sys.argv[2], "k"); open(p, "wb").write(b"<absent>")
print(m.file_bytes(os.path.join(sys.argv[2], "nope")) is None, m.file_bytes(p))
PY
)" "True b'<absent>'"
# (6) the known table and the excluded lock go through the one governance reader (round 4, review r3 H2): a CRLF
# file is still read; a CR inside a line is refused by name (exit 2 / exit 3), never split into two lines
chk "CON-030 r4: known table and excluded lock: CRLF tolerated, a CR inside a line refused by name" "$(python3 -I - "$ENGINE" "$T/crtab" <<'PY'
import sys, os, importlib.util
s = importlib.util.spec_from_file_location("e", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
d = sys.argv[2]; os.makedirs(d); k, l = os.path.join(d, "known.tsv"), os.path.join(d, "lock")
open(k, "w", newline="").write("# c\r\ncd/t.sh\treason:x\tCON-1\tnote\r\nplain\treason:y\tCON-2\tn\n")
open(l, "w", newline="").write("# h\r\ncd/t.sh\t0123456789abcdef\nq\tfedcba9876543210\r\n")
res = [m.load_known(k)[0], sorted(m.read_excl_lock(l)[0].items())]
open(k, "w", newline="").write("c\rd/t.sh\treason:x\tCON-1\tnote\n")
open(l, "w", newline="").write("c\rd/t.sh\t0123456789abcdef\n")
for f, p in ((m.load_known, k), (m.read_excl_lock, l)):
    try:
        f(p); res.append("read")
    except m.Fatal as e:
        res.append((e.code, "line 1 holds the character U+000D (CR)" in str(e)))
print(res)
PY
)" "[[['cd/t.sh', 'reason:x', 'CON-1', 'note'], ['plain', 'reason:y', 'CON-2', 'n']], [('cd/t.sh', '0123456789abcdef'), ('q', 'fedcba9876543210')], (2, True), (3, True)]"

# G4 / G12 (review r2): exact known_sub_paths() sets (a runaway recursion into an empty gitlink directory adds
# bogus `./` entries), a nested uninitialised path with parentheses, a real `U` line on a spaced path, and a real
# SHA-256 superproject
chk "CON-030 r3 G4: known_sub_paths() of a fresh clone is exactly the top-level paths" "$(python3 -I - "$ENGINE" "$mp.fresh" <<'PY'
import sys, importlib.util
s = importlib.util.spec_from_file_location("e", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
print(sorted(m.known_sub_paths(sys.argv[2])))
PY
)" "[' lead', 'cr\\rx', 'k=v', 'nest ed', 'par(1)', 'plainb', 'plainc', 'plaint', 'q?', 'trail ', 'x (xyz)']"
g12="$T/g12"; git init -q "$g12.inner"; gitc "$g12.inner" commit -q --allow-empty -m i
git -C "$g12.inner" -c protocol.file.allow=always submodule add -q "$sp/lib" "in (ner)" >/dev/null 2>&1; gitc "$g12.inner" commit -q -m n
mkroot "$g12"; git -C "$g12" -c protocol.file.allow=always submodule add -q "$g12.inner" "nest (ed)" >/dev/null 2>&1
gitc "$g12" commit -q -m s; git clone -q "$g12" "$g12.c" >/dev/null 2>&1
git -C "$g12.c" -c protocol.file.allow=always submodule update -q --init >/dev/null 2>&1
chk "CON-030 r3 G12: nested uninitialised 'nest (ed)/in (ner)' is one whole gap, known set exact" "$(python3 -I - "$ENGINE" "$g12.c" <<'PY'
import sys, importlib.util
s = importlib.util.spec_from_file_location("e", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
print(m.topology(sys.argv[2])[2], sorted(m.known_sub_paths(sys.argv[2])), m.sub_paths(sys.argv[2]))
PY
)" "['uninitialised submodule: nest (ed)/in (ner)'] ['nest (ed)', 'nest (ed)/in (ner)'] ['nest (ed)']"
uc="$T/ucon"; git init -q "$uc.lib"; gitc "$uc.lib" commit -q --allow-empty -m one; gitc "$uc.lib" commit -q --allow-empty -m two
mkroot "$uc"; git -C "$uc" -c protocol.file.allow=always submodule add -q "$uc.lib" "con (flict) )" >/dev/null 2>&1
gitc "$uc" commit -q -m s; base=$(git -C "$uc" rev-parse --abbrev-ref HEAD); s1=$(git -C "$uc.lib" rev-parse HEAD~1)
gitc "$uc.lib" commit -q --allow-empty -m three; s3=$(git -C "$uc.lib" rev-parse HEAD)
gitc "$uc" checkout -q -b side; gitc "$uc" update-index --cacheinfo "160000,$s1,con (flict) )"; gitc "$uc" commit -q -m side
gitc "$uc" checkout -q "$base"; gitc "$uc" update-index --cacheinfo "160000,$s3,con (flict) )"; gitc "$uc" commit -q -m main3
gitc "$uc" merge -q side >/dev/null 2>&1
if git -C "$uc" submodule status 2>/dev/null | grep -q '^U'; then ok "CON-030 r3 G12 precondition: git prints a real U line"
else ko "CON-030 r3 G12 precondition: git prints a real U line ($(git -C "$uc" submodule status 2>&1 | tr '\n' '|'))"; fi
chk "CON-030 r3 G12: a real U line on 'con (flict) )' names the path whole" "$(python3 -I - "$ENGINE" "$uc" <<'PY'
import sys, importlib.util
s = importlib.util.spec_from_file_location("e", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
print(m.topology(sys.argv[2])[2])
PY
)" "['submodule with merge conflicts: con (flict) )']"
s256="$T/s256"
if git init -q --object-format=sha256 "$s256.lib" 2>/dev/null; then
  gitc "$s256.lib" commit -q --allow-empty -m i; git init -q --object-format=sha256 "$s256"; gitc "$s256" commit -q --allow-empty -m i
  for p in plaint 'sub dir' 'x (xyz)'; do git -C "$s256" -c protocol.file.allow=always submodule add -q "$s256.lib" "$p" >/dev/null 2>&1; done
  gitc "$s256/plaint" tag 'v1(beta)'; gitc "$s256" commit -q -m s
  if git -C "$s256" submodule status | grep -qE '^ [0-9a-f]{64} plaint \(v1\(beta\)\)$'; then ok "CON-030 r3 G12 precondition: SHA-256 status lines (64 hex, describe v1(beta))"
  else ko "CON-030 r3 G12 precondition: SHA-256 status lines ($(git -C "$s256" submodule status 2>&1 | tr '\n' '|'))"; fi
  chk "CON-030 r3 G12: a real SHA-256 superproject reads every path whole, 0 gaps" "$(python3 -I - "$ENGINE" "$s256" <<'PY'
import sys, importlib.util
s = importlib.util.spec_from_file_location("e", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
print(sorted(m.sub_paths(sys.argv[2])), m.topology(sys.argv[2])[2])
PY
)" "['plaint', 'sub dir', 'x (xyz)'] []"
else echo "SKIP CON-030 r3 G12 SHA-256 case: reason sha256_unsupported (git cannot init --object-format=sha256)"; fi

# =========================================================================== CON-030 round 4 (review r3 H1 H2 H3 H6)
# Structural round (section 11.4.276(E)(3)). (1) ONE reader for every governance file (gov_lines): split on "\n"
# only, the CR of a CRLF line end dropped, any other line-breaking character refused by name. (2) A unit's key is
# the structure (path, args); plan() refuses two units with one key and two units shown with one text. (3) ONE
# output escaping function (esc_out) on stdout, stderr and summary.txt, and the census refuses control characters.

# --- (1) the one reader: each line-breaking class refused by name, CRLF and a plain space are not (controls)
chk "CON-030 r4 gov_lines: NEL LS PS CR VT FF ESC NUL DEL C1 refused by name; CRLF, TAB and space read" "$(python3 -I - "$ENGINE" "$T/govl" <<'PY'
import sys, os, importlib.util
s = importlib.util.spec_from_file_location("e", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
d = sys.argv[2]; os.makedirs(d); p = os.path.join(d, "t"); res = []
for c in ("\x85", "\u2028", "\u2029", "\r", "\x0b", "\x0c", "\x1b", "\x00", "\x7f", "\x9b"):
    open(p, "wb").write(("# a\n# comment%seve\tx\n" % c).encode())
    try:
        m.gov_lines(p); res.append("read")
    except m.GovLineError as e:
        res.append(str(e).split(" holds the character ")[1].split(",")[0])
open(p, "wb").write(b"# a\r\nalice\tx y\r\n# comment eve\tx\n")
res.append(m.gov_lines(p))
print(res)
PY
)" "['U+0085 (NEL)', 'U+2028 (LINE SEPARATOR)', 'U+2029 (PARAGRAPH SEPARATOR)', 'U+000D (CR)', 'U+000B (VT)', 'U+000C (FF)', 'U+001B (ESC)', 'U+0000 (NUL)', 'U+007F (DEL)', 'U+009B', [(1, '# a'), (2, 'alice\tx y'), (3, '# comment eve\tx'), (4, '')]]"

# --- (1) lint: every file read in the engine is classed `# io: ...`; the governance readers use gov_lines only.
# Control needles: the lint run on a copy of the engine with an unclassed open() and with read_roster reading its
# file by itself must FAIL; on the engine it must find a known number of classed sites (positive control).
fsr_io_lint() { python3 -I - "$1" <<'PY'
import ast, sys
src = open(sys.argv[1]).read(); L = src.split("\n"); t = ast.parse(src); probs = []; sites = 0
IO = {"open", "splitlines", "readlines", "readline"}
GOV = ("read_manifest", "load_known", "read_excl_lock", "read_roster", "guide_parse")  # CON-030 r5: guide_parse is the guide reader
funcs = {n.name: n for n in ast.walk(t) if isinstance(n, ast.FunctionDef)}
def io_calls(node):
    for n in ast.walk(node):
        if isinstance(n, ast.Call):
            f = n.func
            nm = f.id if isinstance(f, ast.Name) and f.id == "open" else (f.attr if isinstance(f, ast.Attribute) and (f.attr in IO or f.attr in ("read_text", "read_bytes")) else None)
            if nm:
                yield n
for n in io_calls(t):
    sites += 1
    tag = [x.split("# io:", 1)[1].strip().split(" ")[0] for x in L[n.lineno - 1:n.end_lineno] if "# io:" in x]
    if not tag or tag[0] not in ("gov", "write", "not-gov"):
        probs.append("line %d: I/O call without an `# io: gov|write|not-gov` class" % n.lineno)
    elif tag[0] == "gov" and not (funcs["gov_lines"].lineno <= n.lineno <= funcs["gov_lines"].end_lineno):
        probs.append("line %d: `io: gov` outside gov_lines" % n.lineno)
for g in GOV:
    f = funcs.get(g)
    if f is None:
        probs.append("%s missing" % g); continue
    if not any(isinstance(c, ast.Call) and isinstance(c.func, ast.Name) and c.func.id == "gov_lines" for c in ast.walk(f)):
        probs.append("%s does not read through gov_lines" % g)
    for c in io_calls(f):
        if "# io: write" not in L[c.lineno - 1]:
            probs.append("%s reads a file itself (line %d)" % (g, c.lineno))
print("sites=%d problems=%d %s" % (sites, len(probs), probs[:3]))
PY
}
lint_real=$(fsr_io_lint "$ENGINE")
case "$lint_real" in
  "sites="*" problems=0 []") ok "CON-030 r4 io lint: every engine I/O site classed, governance readers use gov_lines ($lint_real)";;
  *) ko "CON-030 r4 io lint: $lint_real";;
esac
n_sites=${lint_real#sites=}; n_sites=${n_sites%% *}
if [ "$n_sites" -ge 25 ]; then ok "CON-030 r4 io lint positive control: $n_sites I/O sites found (>= 25)"
else ko "CON-030 r4 io lint positive control: only $n_sites I/O sites found (instrument blind?)"; fi
mkdir -p "$T/lint"
python3 -I -c 'import sys
s = open(sys.argv[1]).read()
open(sys.argv[2], "w").write(s.replace("def char_name(c):", "def char_name(c):\n    open(\"/dev/null\").read()", 1))
a = "    try:\n        lines = gov_lines(path)\n    except GovLineError as e:\n        # review r3 H2"
b = "    try:\n        lines = list(enumerate(open(path).read().splitlines(), 1))  # io: not-gov\n    except GovLineError as e:\n        # review r3 H2"
assert s.count(a) == 1
open(sys.argv[3], "w").write(s.replace(a, b))' "$ENGINE" "$T/lint/needle_open.py" "$T/lint/needle_roster.py"
case "$(fsr_io_lint "$T/lint/needle_open.py")" in *"I/O call without"*) ok "CON-030 r4 io lint control needle: an unclassed open() is caught";;
  *) ko "CON-030 r4 io lint control needle: an unclassed open() is NOT caught";; esac
case "$(fsr_io_lint "$T/lint/needle_roster.py")" in *"read_roster does not read through gov_lines"*) ok "CON-030 r4 io lint control needle: read_roster reading by itself is caught";;
  *) ko "CON-030 r4 io lint control needle: read_roster reading by itself is NOT caught";; esac

# --- (1) H2 end to end: an operator id hidden behind a NEL / LS / CR in a committed `#` comment line. git shows one
# comment line; round 3 read `eve` as an operator (accepted, then PASS-FULL accepted_by: eve). Control: a plain space.
for sep in nel ls cr none; do
  case "$sep" in nel) sc=$'\xc2\x85';; ls) sc=$'\xe2\x80\xa8';; cr) sc=$'\r';; none) sc=' ';; esac
  h2="$T/h2_$sep"; mkroot "$h2"
  printf 'f() { :; }\n' > "$h2/tests/a/lib.sh"
  sut "$h2" tests/a/test_uses_lib.sh '. "$(dirname "$0")/lib.sh"' 'echo "passed=1 failed=0"'
  gen "$h2"
  { printf '# id<TAB>who\nalice\toperator alice\n'; printf '# former operator, removed%seve\tnot an operator\n' "$sc"; } > "$h2/config/full_suite_operators.roster"
  gitc "$h2" add -A; gitc "$h2" commit -q -m roster
  bash "$R" --root "$h2" --verify-manifest --accept-excluded-change eve > "$T/h2_$sep.eve.log" 2>&1; rc_eve=$?
  bash "$R" --root "$h2" --verify-manifest --accept-excluded-change alice > "$T/h2_$sep.alice.log" 2>&1; rc_alice=$?
  if [ "$sep" = none ]; then
    chk "CON-030 r4 H2 control (plain space): eve is not an operator, refused (rc 3)" "$rc_eve" "3"
    has "CON-030 r4 H2 control: refused because eve is not on the roster" 'not on the operator roster|is not an operator|not listed' "$T/h2_$sep.eve.log"
    chk "CON-030 r4 H2 control (plain space): alice is accepted (rc 0)" "$rc_alice" "0"
  else
    chk "CON-030 r4 H2 ($sep in a comment line): --accept-excluded-change eve refused (rc 3)" "$rc_eve" "3"
    has "CON-030 r4 H2 ($sep): the refused character is named" 'operator roster .* line 3 holds the character U\+' "$T/h2_$sep.eve.log"
    chk "CON-030 r4 H2 ($sep): the whole roster is refused, alice too (rc 3)" "$rc_alice" "3"
    hasnt "CON-030 r4 H2 ($sep): no acceptance line written for eve" 'accepted_by=eve' "$h2/config/full_suite_excluded.lock"
  fi
done
chk "CON-030 r4 H2: read_roster ids per separator (NEL, LS, CR: none; space: alice)" "$(python3 -I - "$ENGINE" "$T" <<'PY'
import sys, importlib.util
s = importlib.util.spec_from_file_location("e", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
r = []
for sep in ("nel", "ls", "cr", "none"):
    root = sys.argv[2] + "/h2_" + sep; ids, prob = m.read_roster(root, root + "/config/full_suite_operators.roster")
    r.append((sep, sorted(ids), prob is None))
print(r)
PY
)" "[('nel', [], False), ('ls', [], False), ('cr', [], False), ('none', ['alice'], True)]"

# --- (2) H1: unit keys are structures. A Go module in a directory named `x/run_all.sh --quick` next to the
# runall-quick unit of x/run_all.sh: round 3 gave both the id `x/run_all.sh --quick`, resumed the failing module from
# the runall's PASS record and ended PASS-FULL rc 0. Round 4 refuses the plan (rc 3). Control: the module in x/gomod.
h1fx() { # $1 root $2 module dir under x/
  local r=$1; mkdir -p "$r/x/$2" "$r/config"; git init -q "$r"; gitc "$r" commit -q --allow-empty -m init
  printf '#!/usr/bin/env bash\n# accepts --quick\n[ "${1:-}" = --quick ] && echo quick\necho "passed=1 failed=0"\n' > "$r/x/run_all.sh"
  printf 'module example.com/m\n\ngo 1.21\n' > "$r/x/$2/go.mod"
  printf 'package m\nimport "testing"\nfunc TestFails(t *testing.T) { t.Fatal("this module FAILS") }\n' > "$r/x/$2/m_test.go"
  gitc "$r" add -A; gitc "$r" commit -q -m fx; gen "$r"
  python3 -I -c 'import sys
p = sys.argv[1]; L = open(p).read().split("\n")
L = ["\t".join(l.split("\t")[:4] + ["runall-quick"] + l.split("\t")[5:]) if l.startswith("x/run_all.sh\t") else l for l in L]
open(p, "w").write("\n".join(L))' "$r/config/full_suite_manifest.tsv"
  gitc "$r" add -A; gitc "$r" commit -q -m manifest
}
if command -v go >/dev/null 2>&1; then
  h1fx "$T/h1" "run_all.sh --quick"; h1fx "$T/h1c" "gomod"
  run "$T/h1" "$T/o_h1"
  chk "CON-030 r4 H1: module dir 'x/run_all.sh --quick' next to runall-quick x/run_all.sh -> refused (rc 3)" "$RC" "3"
  has "CON-030 r4 H1: both units named" "plan: two different units are both shown as 'x/run_all.sh --quick' \(path 'x/run_all.sh' args \['--quick'\], and path 'x/run_all.sh --quick' args \[\]\)" "$T/o_h1.log"
  hasnt "CON-030 r4 H1: never PASS-FULL, never resumed" 'PASS-FULL|resumed' "$T/o_h1.log"
  run "$T/h1" "$T/o_h1h" --include-heavy
  chk "CON-030 r4 H1 (--include-heavy, fresh out): the module runs and fails (rc 1)" "$RC" "1"
  chk "CON-030 r4 H1 (--include-heavy): the module's own record is FAIL" "$(verdict "$T/o_h1h" "x/run_all.sh --quick" | cut -d'|' -f1)" "FAIL"
  run "$T/h1c" "$T/o_h1c"
  chk "CON-030 r4 H1 control (module in x/gomod): FAIL rc 1" "$RC" "1"
else echo "SKIP CON-030 r4 H1 end-to-end cases: reason go_not_installed"; fi
chk "CON-030 r4 H1: plan() keys, display refusal (default), heavy plan, duplicate-key refusal; record matching" "$(python3 -I - "$ENGINE" <<'PY'
import sys, importlib.util
s = importlib.util.spec_from_file_location("e", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
ra = ["x/run_all.sh", "runall", "entry", "default", "runall-quick", "-", "n"]
go = ["x/run_all.sh --quick", "go", "entry", "default", "go-test", "-", "auto"]
res = []
for rows, heavy in (([ra, go], False), ([ra, go], True), ([go, go], True)):
    try:
        res.append(sorted(u["key"] for u in m.plan(rows, heavy)))
    except m.Fatal as e:
        res.append((e.code, str(e).split(" (")[0].split(" shown as")[0]))
q = {"path": "x/run_all.sh", "args": ["--quick"], "unit": "x/run_all.sh --quick", "sha": "s", "tree": "t", "runner_hash": "h", "ctx": "c"}
gom = {"key": ("x/run_all.sh --quick", ()), "id": "x/run_all.sh --quick"}
rq = {"key": ("x/run_all.sh", ("--quick",)), "id": "x/run_all.sh --quick"}
rh = {"key": ("x/run_all.sh", ()), "id": "x/run_all.sh"}
old = dict(q); del old["args"]
res.append([m.rec_matches(q, u, "s", "t", "h", "c") for u in (gom, rq, rh)])
res.append([m.rec_matches(q, rq, *k) for k in (("S", "t", "h", "c"), ("s", "T", "h", "c"), ("s", "t", "H", "c"), ("s", "t", "h", "C"))])
res.append((m.rec_key(old), m.rec_matches(old, rq, "s", "t", "h", "c")))
print(res)
PY
)" "[(3, 'plan: two different units are both'), [('x/run_all.sh', ()), ('x/run_all.sh --quick', ())], (3, 'plan: two units have one key'), [False, True, False], [False, False, False, False], (None, False)]"

# --- (2) RW6 (review r3, adopted): a runall whose --quick mode passes and whose full mode fails; a default run writes
# --out D, then an --include-heavy run reuses D. The heavy unit (path, no args) must not resume the --quick record.
rw6="$T/rw6"; mkdir -p "$rw6/x"; git init -q "$rw6"; gitc "$rw6" commit -q --allow-empty -m init
printf '#!/usr/bin/env bash\n# accepts --quick\nif [ "${1:-}" = --quick ]; then echo "passed=1 failed=0"; exit 0; fi\necho "passed=0 failed=1"; exit 1\n' > "$rw6/x/run_all.sh"
gen "$rw6"
python3 -I -c 'import sys
p = sys.argv[1]; L = open(p).read().split("\n")
L = ["\t".join(l.split("\t")[:4] + ["runall-quick"] + l.split("\t")[5:]) if l.startswith("x/run_all.sh\t") else l for l in L]
open(p, "w").write("\n".join(L))' "$rw6/config/full_suite_manifest.tsv"
gitc "$rw6" add -A; gitc "$rw6" commit -q -m s
run "$rw6" "$T/o_rw6"
chk "CON-030 r4 RW6 precondition: the default run passes (--quick)" "$RC" "0"
run "$rw6" "$T/o_rw6" --include-heavy
chk "CON-030 r4 RW6: the heavy run over the default run's --out runs the full runall and fails (rc 1)" "$RC" "1"
hasnt "CON-030 r4 RW6: the full runall is not resumed from the --quick record" 'resumed x/run_all.sh' "$T/o_rw6.log"

# --- RW3 (review r3, adopted): `git status` fails between two units on a clean tree (unit 1 makes .git/index
# unreadable, unit 2 restores it). The failing status is unknown, never the hash of its empty output: the run stops.
rw3="$T/rw3"; mkroot "$rw3"
sut "$rw3" tests/a/test_1.sh 'cd "$(dirname "$0")/../.."' 'chmod 000 .git/index' 'echo "passed=1 failed=0"'
sut "$rw3" tests/a/test_2.sh 'cd "$(dirname "$0")/../.."' 'chmod 644 .git/index' 'echo "passed=1 failed=0"'
gen "$rw3"; gitc "$rw3" add -A; gitc "$rw3" commit -q -m s
chmod 000 "$rw3/.git/index"; git -C "$rw3" status --porcelain -z >/dev/null 2>&1; pre=$?; chmod 644 "$rw3/.git/index"
if [ "$pre" -ne 0 ]; then ok "CON-030 r4 RW3 precondition: git status with an unreadable index fails (rc $pre)"
else ko "CON-030 r4 RW3 precondition: git status with an unreadable index fails (rc 0: running as root?)"; fi
run "$rw3" "$T/o_rw3" --include-heavy
chmod 644 "$rw3/.git/index" 2>/dev/null
chk "CON-030 r4 RW3: a failing git status mid-run stops the run (rc 2)" "$RC" "2"
# CON-030 round 5 (merge of WIT-C02): the identity is now also checked after every unit, so the unit that broke the
# index is named; the failing status is still unknown (None shown as `?`), never the hash of an empty output
has "CON-030 r4 RW3: named as an unknown root status after unit 1" 'IDENTITY CHANGED after unit tests/a/test_1.sh: root status [0-9a-f]+ -> \?' "$T/o_rw3.log"
hasnt "CON-030 r4 RW3: never PASS-FULL" 'PASS-FULL' "$T/o_rw3.log"

# --- RW4 (review r3): an absent record (None) and a present empty record feed different bytes into the hash
chk "CON-030 r4 RW4: hrec(None) != hrec(b''), and both differ from no record" "$(python3 -I - "$ENGINE" <<'PY'
import sys, importlib.util, hashlib
s = importlib.util.spec_from_file_location("e", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
hs = []
for d in (None, b"", "skip"):
    h = hashlib.sha256()
    if d != "skip":
        m.hrec(h, b"k", d)
    hs.append(h.hexdigest())
print(len(set(hs)))
PY
)" "3"

# --- (3) H3: one output escaping function. Unit: every line-breaking class escaped, TAB kept, a lone surrogate shown.
chk "CON-030 r4 H3 esc_out: CR LF NEL LS ESC escaped, TAB kept, surrogate as \\xNN" "$(python3 -I - "$ENGINE" <<'PY'
import sys, importlib.util
s = importlib.util.spec_from_file_location("e", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
print(repr(m.esc_out("a\rRESULT: PASS-FULL\nb\x85c\u2028d\x1be\tf\udcff")))
PY
)" "'a\\\\rRESULT: PASS-FULL\\\\nb\\\\x85c\\\\u2028d\\\\x1be\\tf\\\\xff'"
# end to end, a text the census does not control: git's submodule paths in TOPOLOGY GAP lines on stdout and in
# summary.txt. The uninitialised fresh clone of the many-path fixture has a submodule `cr<CR>x`.
run "$mp.fresh" "$T/o_mpf" --allow-topology-gaps --include-heavy
chk "CON-030 r4 H3 precondition: the fresh clone runs with gaps (PARTIAL-TOPOLOGY, rc 8)" "$RC" "8"
has "CON-030 r4 H3: the CR submodule path is printed escaped on stdout" 'TOPOLOGY GAP \(allowed\): uninitialised submodule: cr\\rx' "$T/o_mpf.log"
has "CON-030 r4 H3: ... and in summary.txt" 'TOPOLOGY GAP \(allowed\): uninitialised submodule: cr\\rx' "$T/o_mpf/summary.txt"
hasnt "CON-030 r4 H3: no raw CR on stdout/stderr" $'\r' "$T/o_mpf.log"
hasnt "CON-030 r4 H3: no raw CR in summary.txt" $'\r' "$T/o_mpf/summary.txt"
chk "CON-030 r4 H3: summary.txt read in text mode has no RESULT line and one gap line per gap" "$(python3 -I -c 'import sys
L = list(open(sys.argv[1]))
print(sum(l.startswith("RESULT") for l in L), sum(l.startswith("TOPOLOGY GAP") for l in L))' "$T/o_mpf/summary.txt")" "0 11"

# --- F11 (review r1): a suite that writes an IGNORED file into the tree changes tree_state() but not the quick
# identity (which hashes `git status`, and an ignored file is not in it), so the tree branch itself must decide.
# Old reviewer mutant R2 (`if tree_end != tree:` -> `if False:`) survived because the untracked-file case above is
# also caught by the identity check; with R2 this case ends PASS-FULL.
WI="$T/wti"; mkroot "$WI"; printf 'out.dat\n' > "$WI/.gitignore"
sut "$WI" tests/a/test_writer.sh 'echo junk > "$(git rev-parse --show-toplevel)/out.dat"' 'echo "passed=1 failed=0"'
gen "$WI"; gitc "$WI" add -A; gitc "$WI" commit -q -m wti
run "$WI" "$T/o_wti" --include-heavy
chk "R2b: suite writing an ignored file into the tree -> rc 1" "$RC" "1"
has "R2b: tree change named by the tree branch" '^RESULT: FAIL \(repository tree changed during the run; SKIP=' "$T/o_wti.log"
hasnt "R2b: not reported as an identity change" 'identity changed|IDENTITY CHANGED' "$T/o_wti.log"

# --- 38 WIT-C02 (wave 2 review r2, F5): a unit that rewrites the tracked generated command sets is caught
# even when the content is identical (new inode or new mtime); the run ends FAIL and names the unit.
genroot(){ # $1 dir: root with tracked generated sets and two units ($2 = body of unit 1)
  mkroot "$1"; mkdir -p "$1/plugins/helix/commands" "$1/actions/generated"
  echo cmd > "$1/plugins/helix/commands/x.md"; echo readme > "$1/actions/generated/README.md"
  echo top > "$1/plugins/helix/README.md"
  sut "$1" tests/a/test_1.sh "$2" 'echo "passed=1 failed=0"'
  sut "$1" tests/a/test_2.sh 'echo "passed=1 failed=0"'
  gen "$1"; gitc "$1" add -A; gitc "$1" commit -q -m g
}
G1="$T/genrw"; genroot "$G1" "f='$G1/actions/generated/README.md'; cp \"\$f\" \"\$f.t\" && mv \"\$f.t\" \"\$f\""
run "$G1" "$T/o_g1" --include-heavy
chk "C02: identical-content rewrite (new inode) -> rc 1" "$RC" "1"
has "C02: the rewriting unit is named" '^IDENTITY CHANGED after unit tests/a/test_1.sh: .*gen' "$T/o_g1/summary.txt"
chk "C02: the next unit is not run" "$(verdict "$T/o_g1" tests/a/test_2.sh)" ""
# R3c (review r2): the case above also gives the file a new mtime, so the inode field was never the only signal.
# Here only the inode changes: cp -p keeps the file mtime, the temp file is made outside the directory, and the
# directory's own mtime is put back with touch -r, so path, type, mtime, size and content are all unchanged.
G1I="$T/geninode"; genroot "$G1I" "d='$G1I/actions/generated'; f=\"\$d/README.md\"; touch -r \"\$d\" '$G1I/dref'; cp -p \"\$f\" '$G1I/f.t' && mv '$G1I/f.t' \"\$f\" && touch -r '$G1I/dref' \"\$d\"; rm -f '$G1I/dref'"
I0=$(stat -c %i "$G1I/actions/generated/README.md")
run "$G1I" "$T/o_g1i" --include-heavy
chk "C02 R3c: precondition, the unit changed the inode" "$([ "$(stat -c %i "$G1I/actions/generated/README.md")" != "$I0" ] && echo y)" "y"
chk "C02 R3c: an inode-only rewrite (same mtime, size, content) -> rc 1" "$RC" "1"
has "C02 R3c: the inode-only rewrite is named as a gen change" '^IDENTITY CHANGED after unit tests/a/test_1.sh: .*gen' "$T/o_g1i/summary.txt"
G2="$T/gentouch"; genroot "$G2" "touch -d '2001-01-01' '$G2/plugins/helix/commands/x.md'"
run "$G2" "$T/o_g2" --include-heavy
chk "C02: mtime-only change of a tracked generated file -> rc 1" "$RC" "1"
G3="$T/gendir"; genroot "$G3" "touch '$G3/plugins/helix/commands/y.md'; rm -f '$G3/plugins/helix/commands/y.md'"
run "$G3" "$T/o_g3" --include-heavy
chk "C02: a file created and removed in a generated directory -> rc 1 (directory mtime)" "$RC" "1"
G4="$T/genread"; genroot "$G4" "cat '$G4/plugins/helix/commands/x.md' '$G4/actions/generated/README.md' >/dev/null"
run "$G4" "$T/o_g4" --include-heavy
chk "C02: a unit that only reads the generated sets -> rc 0 (golden-FALSE)" "$RC" "0"
hasnt "C02: no identity change reported (golden-FALSE)" 'IDENTITY CHANGED' "$T/o_g4/summary.txt"
# R3 (review r2, reviewer mutant RMb): in a consumer project the generated sets live under the vendored
# constitution/, so the fingerprint must cover that prefix too; here the sets exist ONLY under constitution/
G5="$T/genvend"; mkroot "$G5"; mkdir -p "$G5/constitution/actions/generated" "$G5/constitution/plugins/helix/commands"
echo readme > "$G5/constitution/actions/generated/README.md"; echo cmd > "$G5/constitution/plugins/helix/commands/x.md"
sut "$G5" tests/a/test_1.sh "f='$G5/constitution/actions/generated/README.md'; cp \"\$f\" \"\$f.t\" && mv \"\$f.t\" \"\$f\"" 'echo "passed=1 failed=0"'
sut "$G5" tests/a/test_2.sh 'echo "passed=1 failed=0"'
gen "$G5"; gitc "$G5" add -A; gitc "$G5" commit -q -m g
run "$G5" "$T/o_g5" --include-heavy
chk "C02 R3: a rewrite of a generated set under constitution/ -> rc 1" "$RC" "1"
has "C02 R3: the vendored-prefix rewrite is named as a gen change" '^IDENTITY CHANGED after unit tests/a/test_1.sh: .*gen' "$T/o_g5/summary.txt"

# --- 39 R3b (review r2): the before-unit and end-of-run identity checks stay pinned now that the after-unit
# check fires first for a change a unit makes.
# (a) before-unit: a change between the start identity and the first unit (here the runner's own `go env
# GOMODCACHE` call, answered by a go shim that commits) is caught BEFORE that unit runs, never after it.
BU="$T/beforeunit"; mkroot "$BU"; sut "$BU" tests/a/test_1.sh 'echo "passed=1 failed=0"'
mkdir -p "$BU/gm"; printf 'module example.invalid/gm\n\ngo 1.21\n' > "$BU/gm/go.mod"
printf 'package gm\n\nimport "testing"\n\nfunc TestX(t *testing.T) {}\n' > "$BU/gm/x_test.go"
gen "$BU"; gitc "$BU" add -A; gitc "$BU" commit -q -m bu
GO="$T/goshim"; mkdir -p "$GO"
{ echo '#!/usr/bin/env bash'
  echo "if [ \"\$1\" = env ]; then git -C '$BU' -c user.email=a@b -c user.name=t commit -q --allow-empty -m moved-before-first-unit; echo '$T/nomodcache'; exit 0; fi"
  echo 'echo "go shim: only env is answered" >&2; exit 1'; } > "$GO/go"; chmod +x "$GO/go"
PATH="$GO:$PATH" bash "$R" --root "$BU" --out "$T/o_bu" --include-heavy >"$T/o_bu.log" 2>&1; RC=$?
chk "R3b I1: a change before the first unit -> rc 1" "$RC" "1"
has "R3b I1: summary says the change was seen before a unit" '^IDENTITY CHANGED before unit ' "$T/o_bu/summary.txt"
hasnt "R3b I1: it is not attributed to a unit that ran" '^IDENTITY CHANGED after unit' "$T/o_bu/summary.txt"
chk "R3b I1: no unit ran on the moved HEAD" "$(python3 -I -c 'import json,sys
print(sum(1 for l in open(sys.argv[1]) if json.loads(l).get("verdict") not in ("SKIPPED-heavy",)))' "$T/o_bu/results.jsonl" 2>/dev/null || echo 0)" "0"
# (b) end-of-run: a unit changes the CONTENT of a file that was already modified at the start. The quick identity
# (HEADs, `git status --porcelain`, gen) does not change; the full tree_ident (dirty diff hash) does, so only the
# end-of-run comparison names it.
ER="$T/endrun"; mkroot "$ER"; echo one > "$ER/notes.txt"
sut "$ER" tests/a/test_1.sh "echo three > '$ER/notes.txt'" 'echo "passed=1 failed=0"'
gen "$ER"; gitc "$ER" add -A; gitc "$ER" commit -q -m er
echo two > "$ER/notes.txt"
run "$ER" "$T/o_er" --include-heavy
chk "R3b I2: a dirty file rewritten by the last unit -> rc 1" "$RC" "1"
chk "R3b I2: the unit ran" "$(verdict "$T/o_er" tests/a/test_1.sh | cut -d'|' -f1)" "PASS"
hasnt "R3b I2: the quick identity did not see it (no after-unit change)" '^IDENTITY CHANGED after unit' "$T/o_er/summary.txt"
has "R3b I2: the end-of-run tree_ident comparison names it" '^IDENTITY CHANGED at the end of the run: head=.*dirty=.* -> head=' "$T/o_er/summary.txt"
has "R3b I2: RESULT names the identity change" '^RESULT: FAIL \(.*identity changed during the run at the end of the run' "$T/o_er.log"

# =========================================================================== CON-030 round 5 (review r4 K1-K12, M1-M6)
# --- (1) K5: the WIT-C02 fingerprint of the generated sets, merged from main, is a field of the structured QuickIdent.
# Unknown is None (never the in-band "?" main's text identity used), names are fed as file-system bytes, and every
# field is a length-framed record. Unreadable entry at the start: refused before the first unit (never PASS-FULL).
GU="$T/genunread"; genroot "$GU" 'echo ran'
chmod 000 "$GU/actions/generated/README.md"
if cat "$GU/actions/generated/README.md" >/dev/null 2>&1; then
  ko "CON-030 r5 K5 precondition: a mode-000 file cannot be read (running as root?)"
else ok "CON-030 r5 K5 precondition: a mode-000 file cannot be read"; fi
chk "CON-030 r5 K5: gen_fingerprint of an unreadable entry is None" "$(python3 -I - "$ENGINE" "$GU" <<'PY'
import sys, importlib.util
s = importlib.util.spec_from_file_location("e", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
print(m.gen_fingerprint(sys.argv[2]))
PY
)" "None"
run "$GU" "$T/o_gu" --include-heavy
chmod 644 "$GU/actions/generated/README.md"
chk "CON-030 r5 K5: an unreadable generated-set entry -> rc 1 (never PASS-FULL)" "$RC" "1"
has "CON-030 r5 K5: named as the unknown generated sets before the first unit" '^IDENTITY CHANGED before unit tests/a/test_1.sh: generated sets \? -> \?' "$T/o_gu.log"
hasnt "CON-030 r5 K5: the unit after the unknown identity is not run" '^\[1/[0-9]+\] PASS tests/a/test_1.sh' "$T/o_gu.log"
# a name that is not UTF-8 inside a generated set: main's text fingerprint raised UnicodeEncodeError on it
GN="$T/gennonutf"; genroot "$GN" 'echo ran'
python3 -I -c 'import os,sys; open(os.path.join(os.fsencode(sys.argv[1]), b"actions/generated/x\xff.md"), "wb").write(b"x\n")' "$GN"
gitc "$GN" add -A; gitc "$GN" commit -q -m nonutf
chk "CON-030 r5 K5: gen_fingerprint reads a non-UTF-8 entry name (16 hex, two calls equal)" "$(python3 -I - "$ENGINE" "$GN" <<'PY'
import sys, importlib.util, re
s = importlib.util.spec_from_file_location("e", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
a, b = m.gen_fingerprint(sys.argv[2]), m.gen_fingerprint(sys.argv[2])
print(bool(re.fullmatch("[0-9a-f]{16}", a or "")), a == b)
PY
)" "True True"
run "$GN" "$T/o_gn" --include-heavy
chk "CON-030 r5 K5: a non-UTF-8 name in a generated set does not break the run (rc 0)" "$RC" "0"
hasnt "CON-030 r5 K5: no traceback on a non-UTF-8 generated-set name" 'Traceback|UnicodeEncodeError' "$T/o_gn.log"
# the content record: an ignored file in a generated set changes content only (same inode, size and mtime); git status
# cannot see an ignored file, so only the fingerprint's content record names it as a gen change after the unit
GC="$T/gencontent"; genroot "$GC" "f='$GC/actions/generated/cache.txt'; touch -r \"\$f\" '$GC/../gc_ref'; printf 'B\n' > \"\$f\"; touch -r '$GC/../gc_ref' \"\$f\"; rm -f '$GC/../gc_ref'"
printf 'actions/generated/cache.txt\n' > "$GC/.gitignore"; printf 'A\n' > "$GC/actions/generated/cache.txt"
gitc "$GC" add -A; gitc "$GC" commit -q -m ign
I0=$(stat -c '%i %s %Y' "$GC/actions/generated/cache.txt")
run "$GC" "$T/o_gc" --include-heavy
chk "CON-030 r5 K5 precondition: inode, size and mtime unchanged by the unit" "$(stat -c '%i %s %Y' "$GC/actions/generated/cache.txt")" "$I0"
chk "CON-030 r5 K5: a content-only change in a generated set -> rc 1" "$RC" "1"
has "CON-030 r5 K5: named by the after-unit check as a generated-sets change" '^IDENTITY CHANGED after unit tests/a/test_1.sh: generated sets [0-9a-f]+ -> [0-9a-f]+' "$T/o_gc/summary.txt"

# --- (2) K1: the census markers of the guide are whole lines. Round 4 found them with text.index(), so a prose line
# that quoted the begin marker above the real block made --sync-guide delete everything in between (rc 0).
gd(){ # $1 root, $2 guide text with \uNNNN escapes -> root with a committed manifest and that guide
  local r=$1; mkdir -p "$r/x" "$r/config" "$r/docs/guides"; git init -q "$r"; gitc "$r" commit -q --allow-empty -m init
  printf '#!/usr/bin/env bash\necho "passed=1 failed=0"\n' > "$r/x/run_all.sh"
  gitc "$r" add -A; gitc "$r" commit -q -m fx; gen "$r"
  python3 -I -c 'import sys; open(sys.argv[1], "wb").write(sys.argv[2].encode("ascii").decode("unicode_escape").encode())' \
    "$r/docs/guides/full_suite_runner_guide.md" "$2"
  gitc "$r" add -A; gitc "$r" commit -q -m guide
}
gsum(){ sha256sum < "$1/docs/guides/full_suite_runner_guide.md"; }
sync_g(){ bash "$R" --root "$1" --sync-guide >"$2" 2>&1; RC=$?; }
GQ="$T/gq"; gd "$GQ" '# guide\n\nThe block starts at a line `<!-- census:begin -->` and ends at the end marker.\n\nIMPORTANT PROSE THAT MUST SURVIVE\n\n<!-- census:begin -->\nstale\n<!-- census:end -->\n\ntail\n'
vfy "$GQ" "$T/gq_v1.log"; chk "CON-030 r5 K1: quoted marker + stale real block: verify rc 3" "$RC" "3"
has "CON-030 r5 K1: verify names the stale block" 'census block is stale' "$T/gq_v1.log"
sync_g "$GQ" "$T/gq_s.log"; chk "CON-030 r5 K1: --sync-guide rc 0" "$RC" "0"
chk "CON-030 r5 K1: the prose between the quoted and the real marker survives" "$(grep -c 'IMPORTANT PROSE THAT MUST SURVIVE' "$GQ/docs/guides/full_suite_runner_guide.md")" "1"
chk "CON-030 r5 K1: the prose line quoting the marker survives" "$(grep -c 'The block starts at a line' "$GQ/docs/guides/full_suite_runner_guide.md")" "1"
chk "CON-030 r5 K1: only the block line changed (1 added, 1 removed)" "$(git -C "$GQ" diff --numstat | cut -f1,2)" "1	1"
vfy "$GQ" "$T/gq_v2.log"; chk "CON-030 r5 K1: verify after sync rc 0" "$RC" "0"
for c in two:'<!-- census:begin -->\nA\n<!-- census:begin -->\nstale\n<!-- census:end -->\n' \
         space:'<!-- census:begin --> \nstale\n<!-- census:end -->\n' \
         order:'<!-- census:end -->\nstale\n<!-- census:begin -->\n' \
         noend:'x\n<!-- census:begin -->\nstale\n' \
         nearplus:'  <!-- census:end -->\n\n<!-- census:begin -->\nstale\n<!-- census:end -->\n'; do
  k=${c%%:*}; g="$T/gm_$k"; gd "$g" "# guide\n\n${c#*:}"
  s0=$(gsum "$g")
  vfy "$g" "$T/gm_${k}_v.log"; chk "CON-030 r5 K1 ($k): a malformed census block -> verify rc 3" "$RC" "3"
  has "CON-030 r5 K1 ($k): verify names the marker problem" 'census block needs exactly one line|start with a census marker but are not exactly one' "$T/gm_${k}_v.log"
  sync_g "$g" "$T/gm_${k}_s.log"; chk "CON-030 r5 K1 ($k): --sync-guide refuses (rc 3)" "$RC" "3"
  has "CON-030 r5 K1 ($k): --sync-guide says nothing was written" '^RESULT: GUIDE-NOT-SYNCED' "$T/gm_${k}_s.log"
  chk "CON-030 r5 K1 ($k): the guide is unchanged" "$(gsum "$g")" "$s0"
done
# the near-marker rule names its own reason: on `space` the begin line is missing anyway, on `nearplus` a valid block
# exists and only the near-marker rule refuses (review r5 mutant K1b, `if near:` -> `if False:`)
for k in space nearplus; do
  has "CON-030 r5 K1 ($k): the refusal names the near-marker line" 'start with a census marker but are not exactly one' "$T/gm_${k}_v.log"
done

# --- (2b) CON-030 round 6 (review r5 F1-F3, structural): every guide-marker variant, enumerated, each outcome pinned.
# Block shapes with exact markers (none, current, stale, current plus a stale line before or after it (MX10), empty,
# begin only, end only (MX7), two begins, two ends, reversed, CRLF) and marker-line shapes on the begin line, the end
# line, both, or a separate line outside a current block. NEAR shapes (leading/trailing white space, NBSP, a leading
# or trailing U+200B, a leading U+FEFF, trailing text) are refused; TEXT shapes (backticked, after other text, upper
# case, a U+200B inside the marker) are prose and never a marker. Each case runs --verify-manifest and --sync-guide;
# a stale block must be rewritten and then verify rc 0; every refusal leaves the guide byte-identical.
GMX="$T/gmatrix"; gd "$GMX" '# guide\n'
python3 -I - "$R" "$GMX" > "$T/gmatrix.out" 2>&1 <<'PYGM'
import hashlib, os, subprocess, sys

R, root = sys.argv[1], sys.argv[2]
G = os.path.join(root, "docs", "guides", "full_suite_runner_guide.md")
B, E = "<!-- census:begin -->", "<!-- census:end -->"
NEAR = {"lead_space": lambda m: " " + m, "trail_space": lambda m: m + " ", "lead_tab": lambda m: "\t" + m,
        "trail_text": lambda m: m + " (generated)", "lead_zwsp": lambda m: "​" + m,
        "lead_bom": lambda m: "﻿" + m, "lead_nbsp": lambda m: " " + m,
        "trail_zwsp": lambda m: m + "​", "lead_zwsp_space": lambda m: " ​ " + m}
TEXT = {"backtick": lambda m: "`" + m + "`", "prose_lead": lambda m: "see " + m, "upper": lambda m: m.upper(),
        "inner_zwsp": lambda m: m.replace("census:", "census:​")}


def run(*a):
    p = subprocess.run(["bash", R, "--root", root] + list(a), capture_output=True)
    return p.returncode, p.stdout.decode("utf-8", "replace") + p.stderr.decode("utf-8", "replace")


def write(lines, crlf=False):
    eol = "\r\n" if crlf else "\n"
    body = ["# guide", "", "Prose quotes the marker `" + B + "` and `" + E + "` inside text.", ""] + lines + ["", "tail"]
    with open(G, "wb") as fh:
        fh.write((eol.join(body) + eol).encode("utf-8"))


def sha():
    with open(G, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def classify(rc, txt):
    if "census block is stale" in txt:
        return "stale"
    if "census block needs exactly one line" in txt or "start with a census marker" in txt:
        return "marker"
    return "ok" if rc == 0 and "MANIFEST-OK" in txt else "other"


# the current census line, from --sync-guide on an empty block
write([B, E])
rc, txt = run("--sync-guide")
lines = open(G, encoding="utf-8").read().split("\n")
CUR = lines[lines.index(B) + 1]
assert CUR.startswith("census (generated"), (rc, txt, CUR)
S = "census: stale total=99"

cases = []  # (name, lines, crlf, expected class, expected sync rc, sync changes the file)
STALE, MARK, OK, NONE = ("stale", 0, True), ("marker", 3, False), ("ok", 0, False), ("none", 0, False)
for name, ls, exp in [("none", ["no block here"], NONE), ("current", [B, CUR, E], OK), ("stale", [B, S, E], STALE),
                      ("extra_after", [B, CUR, S, E], STALE), ("extra_before", [B, S, CUR, E], STALE),
                      ("empty", [B, E], STALE), ("begin_only", [B, S], MARK), ("end_only", [S, E], MARK),
                      ("two_begin", [B, S, B, S, E], MARK), ("two_end", [B, S, E, E], MARK),
                      ("reversed", [E, S, B], MARK)]:
    cases.append(("block:" + name, ls, False, exp))
cases.append(("block:stale_crlf", [B, S, E], True, STALE))
cases.append(("block:current_crlf", [B, CUR, E], True, OK))
for kind, shapes in (("near", NEAR), ("text", TEXT)):
    for sn, f in shapes.items():
        cases.append(("%s:%s:begin" % (kind, sn), [f(B), S, E], False, MARK))
        cases.append(("%s:%s:end" % (kind, sn), [B, S, f(E)], False, MARK))
        cases.append(("%s:%s:both" % (kind, sn), [f(B), S, f(E)], False, MARK if kind == "near" else NONE))
        cases.append(("%s:%s:outside" % (kind, sn), [f(B), "", B, CUR, E], False, MARK if kind == "near" else OK))

for name, ls, crlf, (ecls, esrc, echg) in cases:
    write(ls, crlf)
    s0 = sha()
    vrc, vtxt = run("--verify-manifest")
    cls = classify(vrc, vtxt)
    src, stxt = run("--sync-guide")
    if "has no census block" in stxt and cls == "ok":
        cls = "none"
    chg = sha() != s0
    post = run("--verify-manifest")[0] if chg else vrc
    want_vrc = 0 if ecls in ("ok", "none") else 3
    good = (cls, vrc, src, chg) == (ecls, want_vrc, esrc, echg) and (not echg or post == 0)
    print("%s\t%s\tverify=%s/%d sync=%d changed=%s post=%d" % ("P" if good else "F", name, cls, vrc, src, chg, post))
print("N\t%d" % len(cases))
PYGM
while IFS=$'\t' read -r st name detail; do
  case $st in
    P) ok "CON-030 r6 guide matrix $name";;
    F) ko "CON-030 r6 guide matrix $name ($detail)";;
  esac
done < "$T/gmatrix.out"
chk "CON-030 r6 guide matrix: all 65 cases ran (control: a driver crash or a lost case is a FAIL)" "$(grep -c '^[PF]	' "$T/gmatrix.out")" "65"
has "CON-030 r6 guide matrix: the driver finished" '^N	65$' "$T/gmatrix.out"

# the proof that the reviewer's MX2 is equivalent: a full-mode key collision needs a repeated manifest path, and
# read_manifest refuses that before plan() runs
GDP="$T/gdup"; gd "$GDP" '# guide\n'
grep -v '^#' "$GDP/config/full_suite_manifest.tsv" | head -1 >> "$GDP/config/full_suite_manifest.tsv"
vfy "$GDP" "$T/gdp_v.log"; chk "CON-030 r6 F7: a repeated manifest path -> verify rc 3" "$RC" "3"
has "CON-030 r6 F7: read_manifest names the repeated path" 'duplicate path x/run_all.sh' "$T/gdp_v.log"

# --- (2c) review r5 F9: --sync-guide keeps the guide's mode and refuses a symlinked guide (a link is never replaced)
GL="$T/glink"; gd "$GL" '# guide\n\n<!-- census:begin -->\nstale\n<!-- census:end -->\n'
chmod 600 "$GL/docs/guides/full_suite_runner_guide.md"
sync_g "$GL" "$T/gl_s1.log"; chk "CON-030 r6 F9: --sync-guide on a mode-600 guide rc 0" "$RC" "0"
chk "CON-030 r6 F9: the mode is kept" "$(stat -c %a "$GL/docs/guides/full_suite_runner_guide.md")" "600"
mv "$GL/docs/guides/full_suite_runner_guide.md" "$GL/docs/guides/real.md"
python3 -I -c 'import sys; open(sys.argv[1], "w").write("# guide\n\n<!-- census:begin -->\nstale\n<!-- census:end -->\n")' "$GL/docs/guides/real.md"
ln -s real.md "$GL/docs/guides/full_suite_runner_guide.md"; s0=$(sha256sum < "$GL/docs/guides/real.md")
sync_g "$GL" "$T/gl_s2.log"; chk "CON-030 r6 F9: --sync-guide on a symlinked guide refuses (rc 3)" "$RC" "3"
has "CON-030 r6 F9: the refusal names the link" 'is a symbolic link' "$T/gl_s2.log"
chk "CON-030 r6 F9: the link is still a link" "$([ -L "$GL/docs/guides/full_suite_runner_guide.md" ] && echo link)" "link"
chk "CON-030 r6 F9: the link target is unchanged" "$(sha256sum < "$GL/docs/guides/real.md")" "$s0"

# the rewrite is byte-exact outside the block: CRLF line ends and a byte that is not UTF-8 are written back unchanged
GB="$T/gbytes"; gd "$GB" '# guide\n'
python3 -I -c 'import sys; open(sys.argv[1], "wb").write(b"# guide\r\nbad byte \xff here\r\n<!-- census:begin -->\r\nstale\r\n<!-- census:end -->\r\ntail\r\n")' "$GB/docs/guides/full_suite_runner_guide.md"
gitc "$GB" add -A; gitc "$GB" commit -q -m crlf
sync_g "$GB" "$T/gb_s.log"; chk "CON-030 r5 K1: --sync-guide on a CRLF guide with a non-UTF-8 byte: rc 0" "$RC" "0"
chk "CON-030 r5 K1: every byte outside the block is unchanged (CRLF kept, the 0xff byte kept)" "$(python3 -I -c '
import sys; d = open(sys.argv[1], "rb").read().split(b"\n")
print(d[:3] == [b"# guide\r", b"bad byte \xff here\r", b"<!-- census:begin -->\r"], d[3].endswith(b"\r"), d[3] != b"stale\r", d[4:] == [b"<!-- census:end -->\r", b"tail\r", b""])' "$GB/docs/guides/full_suite_runner_guide.md")" "True True True True"
vfy "$GB" "$T/gb_v.log"; chk "CON-030 r5 K1: verify after the CRLF sync rc 0" "$RC" "0"
GO0="$T/gnone"; gd "$GO0" '# guide\n\nno census block, but a quoted `<!-- census:end -->` marker in prose\n'
sync_g "$GO0" "$T/gnone_s.log"; chk "CON-030 r5 K1 control: a guide without a block: --sync-guide rc 0" "$RC" "0"
has "CON-030 r5 K1 control: says the guide has no block and nothing was written" 'has no census block; nothing was written' "$T/gnone_s.log"
vfy "$GO0" "$T/gnone_v.log"; chk "CON-030 r5 K1 control: a guide without a block: verify rc 0" "$RC" "0"

# --- (3) K2 and M2 (reviewer mutant RX2): a guide holding a NEL in prose with a stale block. Round 4's --sync-guide
# printed the census line, wrote nothing and returned 0; RX2 (the GovLineError path returning None) made verify say
# MANIFEST-OK on that stale guide.
GNL="$T/gnel"; gd "$GNL" '# guide\n\nprose with a NEL\u0085here\n\n<!-- census:begin -->\nstale\n<!-- census:end -->\n'
s0=$(gsum "$GNL")
vfy "$GNL" "$T/gnel_v.log"; chk "CON-030 r5 M2: NEL in the guide -> verify rc 3 (never MANIFEST-OK)" "$RC" "3"
has "CON-030 r5 M2: verify names the guide and the character" 'full_suite_runner_guide.md line 3 holds the character U\+0085 \(NEL\)' "$T/gnel_v.log"
sync_g "$GNL" "$T/gnel_s.log"; chk "CON-030 r5 K2: --sync-guide on a guide it cannot read -> rc 3" "$RC" "3"
has "CON-030 r5 K2: --sync-guide names the character" 'GUIDE: .*U\+0085 \(NEL\)' "$T/gnel_s.log"
hasnt "CON-030 r5 K2: --sync-guide does not print the census line as if it had written it" '^guide census block: census' "$T/gnel_s.log"
chk "CON-030 r5 K2: the guide is unchanged" "$(gsum "$GNL")" "$s0"

# --- (4) K3: esc_out decodes the surrogate escapes first, then escapes; surrogates holding a valid UTF-8 sequence
# of NEL or LINE SEPARATOR became a raw line breaker in round 4
chk "CON-030 r5 K3: esc_out escapes a line breaker hidden in surrogate escapes" "$(python3 -I - "$ENGINE" <<'PY'
import sys, importlib.util
s = importlib.util.spec_from_file_location("e", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
r = [m.esc_out("\udcc2\udc85"), m.esc_out("x\udce2\udc80\udca8y"), m.esc_out("a\udcff"), m.esc_out("t\tu")]
print("|".join(r), any(m.LINE_BREAKERS.search(x) for x in r))
PY
)" '\x85|x\u2028y|a\xff|t	u False'
# review r5 F8 (reviewer mutant MX5): a lone surrogate outside U+DC80..U+DCFF cannot take the surrogateescape round
# trip; the fallback escapes it as text, so the line can still be written to a UTF-8 stream
chk "CON-030 r6 F8: esc_out escapes a lone high surrogate as text" "$(python3 -I - "$ENGINE" <<'PY'
import sys, importlib.util
s = importlib.util.spec_from_file_location("e", sys.argv[1]); m = importlib.util.module_from_spec(s); s.loader.exec_module(m)
r = m.esc_out("a\ud800b")
r.encode("utf-8")
print(r)
PY
)" 'a\ud800b'

# --- (5) K12 and M6 (reviewer mutant RX6): a test file whose name holds a NEL or a LINE SEPARATOR. Round 4 wrote the
# manifest WITHOUT that file ("1 row", rc 0); RX6 (the census check narrowed to C0 + DEL) let the name through.
for k in nel ls; do
  cn="$T/cn_$k"; mkdir -p "$cn/x" "$cn/config"; git init -q "$cn"; gitc "$cn" commit -q --allow-empty -m init
  printf '#!/usr/bin/env bash\necho "passed=1 failed=0"\n' > "$cn/x/run_all.sh"; gitc "$cn" add -A; gitc "$cn" commit -q -m fx
  gen "$cn"; gitc "$cn" add -A; gitc "$cn" commit -q -m manifest
  case $k in nel) c=$'\xc2\x85'; want='U\+0085 \(NEL\)';; ls) c=$'\xe2\x80\xa8'; want='U\+2028 \(LINE SEPARATOR\)';; esac
  printf '#!/usr/bin/env bash\necho "passed=1 failed=0"\n' > "$cn/x/test_a${c}b.sh"; gitc "$cn" add -A; gitc "$cn" commit -q -m name
  m0=$(sha256sum < "$cn/config/full_suite_manifest.tsv")
  vfy "$cn" "$T/cn_${k}_v.log"; chk "CON-030 r5 M6 ($k): verify rc 3" "$RC" "3"
  has "CON-030 r5 M6 ($k): verify names the character" "census: file name with .*$want" "$T/cn_${k}_v.log"
  hasnt "CON-030 r5 M6 ($k): the name is refused, not reported as a missing row" 'census file without manifest row' "$T/cn_${k}_v.log"
  bash "$R" --root "$cn" --generate-manifest --write >"$T/cn_${k}_g.log" 2>&1; RC=$?
  chk "CON-030 r5 K12 ($k): --generate-manifest --write refuses (rc 3)" "$RC" "3"
  has "CON-030 r5 K12 ($k): it names the character" "MANIFEST: census: file name with .*$want" "$T/cn_${k}_g.log"
  has "CON-030 r5 K12 ($k): it says nothing was written" '^RESULT: MANIFEST-NOT-GENERATED \(1 census problem\(s\); nothing was written\)' "$T/cn_${k}_g.log"
  chk "CON-030 r5 K12 ($k): the manifest is unchanged" "$(sha256sum < "$cn/config/full_suite_manifest.tsv")" "$m0"
  bash "$R" --root "$cn" --generate-manifest >"$T/cn_${k}_p.log" 2>&1; RC=$?
  chk "CON-030 r5 K12 ($k): --generate-manifest (print) refuses too (rc 3)" "$RC" "3"
done

# --- (6) M1 (reviewer mutant RX1): err() escapes. An uninitialised submodule whose path holds a CR followed by a
# forged RESULT line: the TOPOLOGY line on stderr must carry the CR as \r, never raw.
ec="$T/errcr"; mkdir -p "$ec/x" "$ec/config"; git init -q "$ec"; gitc "$ec" commit -q --allow-empty -m init
printf '#!/usr/bin/env bash\necho "passed=1 failed=0"\n' > "$ec/x/run_all.sh"
git init -q "$T/errcr_src"; gitc "$T/errcr_src" commit -q --allow-empty -m s; ecs=$(git -C "$T/errcr_src" rev-parse HEAD)
ecp=$(printf 's\rRESULT: PASS-FULL (forged)')
printf '[submodule "s"]\n\tpath = %s\n\turl = %s\n' "$ecp" "$T/errcr_src" > "$ec/.gitmodules"
gitc "$ec" add -A; git -C "$ec" update-index --add --cacheinfo "160000,$ecs,$ecp"; gitc "$ec" commit -q -m fx
gen "$ec"; gitc "$ec" add config; gitc "$ec" commit -q -m manifest   # add -A would stage the gitlink as deleted
chk "CON-030 r5 M1 precondition: the gitlink is committed" "$(git -C "$ec" ls-files -s | grep -c '^160000')" "1"
bash "$R" --root "$ec" --out "$T/o_ec" >"$T/o_ec.out" 2>"$T/o_ec.err"; RC=$?
chk "CON-030 r5 M1: an uninitialised submodule is a topology gap (rc 9)" "$RC" "9"
chk "CON-030 r5 M1: no raw CR on stderr" "$(tr -cd '\r' < "$T/o_ec.err" | wc -c)" "0"
chk "CON-030 r5 M1: no raw CR on stdout" "$(tr -cd '\r' < "$T/o_ec.out" | wc -c)" "0"
has "CON-030 r5 M1: the TOPOLOGY line shows the CR as \\r" '^TOPOLOGY: .*s\\rRESULT: PASS-FULL \(forged\)' "$T/o_ec.err"

# --- (7) M5 (reviewer mutant RX5): the terminal summary is written line by line; every line of summary.txt is a whole
# line of the terminal output (one joined out() call made the summary one line with escaped \n)
chk "CON-030 r5 M5: every summary.txt line is a whole terminal line" "$(python3 -I - "$T/o_g4/summary.txt" "$T/o_g4.log" <<'PY'
import sys
s = open(sys.argv[1]).read().split("\n")[:-1]; t = set(open(sys.argv[2]).read().split("\n"))
print(len(s) > 5, [l for l in s if l not in t])
PY
)" "True []"

# --- (8) K9: --verify-manifest asks plan() too, so a manifest that a run refuses is not MANIFEST-OK
if command -v go >/dev/null 2>&1; then
  vfy "$T/h1" "$T/h1_v.log"
  chk "CON-030 r5 K9: verify on the H1 fixture -> rc 3 (the run is refused too)" "$RC" "3"
  has "CON-030 r5 K9: verify names the plan refusal" '^MANIFEST: plan \(default mode\): plan: two different units are both shown as' "$T/h1_v.log"
  vfy "$T/h1c" "$T/h1c_v.log"; chk "CON-030 r5 K9 control: verify on the x/gomod control -> rc 0" "$RC" "0"
else echo "SKIP CON-030 r5 K9 cases: reason go_not_installed"; fi

echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
