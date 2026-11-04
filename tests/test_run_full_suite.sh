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
        "leaked": 0, "log": "logs/000000.log", "log_sha256": "x"}
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
    ("bash t/a.sh; rc=$?\nbash t/b.sh | tee x; echo ${PIPESTATUS[0]}", set()),
    ("set -e\nbash t/a.sh\nbash t/b.sh || true\necho ok", {"t/b.sh"}),
    ("if bash t/a.sh; then :; fi\nfor x in 1; do bash t/b.sh; done\nbash t/c.sh &\nwait\nout=$(bash t/d.sh)\nrc=$?\n"
     "echo $(bash t/e.sh)\nbash t/f.sh | cat\nexit 0", {"t/b.sh", "t/c.sh", "t/e.sh", "t/f.sh"}),
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
gen "$G"; run "$G" "$T/o_good" --include-heavy
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
run "$W" "$T/o_ra_full" --include-heavy
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
P4="$T/p4"; mkroot "$P4"
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

echo "passed=$pass failed=$fail"
[ "$fail" -eq 0 ]
