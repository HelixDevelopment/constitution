#!/usr/bin/env python3
"""tests/workable_items/remint_branch_sweep_mutations.py -- mutants of the branch sweep itself (round 5).

Documentation (section 11.4.18): docs/guides/remint_ids_guide.md, section "Branch sweep".

WHAT  Writes each mutant SW1..SW18 of tests/workable_items/remint_branch_sweep.py (one exact string
  replaced; the string must occur exactly once, or the run stops as a setup error) and runs
  tests/workable_items/test_remint_branch_sweep.sh on it (REMINT_BRANCH_SWEEP=<mutant>). A mutant is
  KILLED when the test exits 1 with a FAIL line; anything else fails the run. The unmutated copy is run
  first and must pass (the control).
USAGE  remint_branch_sweep_mutations.py [--jobs N]   (default 3; the files are found next to this one)
EXIT  0 control passes and every mutant is killed; 1 otherwise; 2 setup.
EVIDENCE CLASS  gate-logic (section 11.4.289): the sweep's own test with a fake tool and a stand-in suite.
"""
import concurrent.futures as cf
import os
import subprocess
import sys
import tempfile

MUTANTS = [
    ("SW1", "the unmutated control is never run",
     "        control(src, work, a.timeout)\n", ""),
    ("SW2", "a suite exit 1 without a FAIL line counts as KILLED",
     "    if rc == 1 and fails:\n", "    if rc == 1:\n"),
    ("SW3", "a register entry turns any verdict into EQUIVALENT",
     '            if verdict == "SURVIVED" and key in reg:\n', "            if key in reg:\n"),
    ("SW4", "a SETUP verdict does not fail the sweep",
     'bad = tally.get("SURVIVED", 0) + tally.get("SETUP", 0) +', 'bad = tally.get("SURVIVED", 0) +'),
    ("SW5", "a stale register entry fails a --only run",
     "(len(stale) if not want else 0)", "len(stale)"),
    ("SW6", "a TIMEOUT verdict fails the sweep",
     'bad = tally.get("SURVIVED", 0)', 'bad = tally.get("TIMEOUT", 0) + tally.get("SURVIVED", 0)'),
    ("SW7", "a while True loop is mutated, not skipped",
     "and ch.test.value is True:", "and ch.test.value is None:"),
    ("SW8", "comprehension filters are not walked",
     '                for f in ch.ifs:\n                    add(top, "compif", f)\n', "                pass\n"),
    ("SW9", "the span control needle is removed",
     "        if back != ast.dump(e):\n", "        if False:\n"),
    ("SW10", "--only-file takes the whole line as the key",
     'k = line.rstrip("\\n").split("\\t")[0]', 'k = line.rstrip("\\n")'),
    ("SW11", "an unknown --only key is accepted",
     "        if len(sel) != len(want):\n", "        if False:\n"),
    ("SW12", "the suite runs without REMINT_IDS_FAILFAST=1",
     'REMINT_IDS_FAILFAST="1"', 'REMINT_IDS_FAILFAST="0"'),
    ("SW13", "byte offsets are taken as character offsets",
     'return lo[lineno] + len(lines[lineno - 1].encode("utf-8")[:col].decode("utf-8"))',
     "return lo[lineno] + col"),
    ("SW14", "a setup error exits 1",
     '        print("setup: %s" % err, file=sys.stderr)\n        sys.exit(2)',
     '        print("setup: %s" % err, file=sys.stderr)\n        sys.exit(1)'),
    ("SW15", "cmd_replay is not a target",
     '"Rewriter", "cmd_replay", "cmd_verify",', '"Rewriter", "cmd_verify",'),
    ("SW16", "conditional expressions are not walked",
     "            elif isinstance(ch, ast.IfExp):\n", "            elif False:\n"),
    ("SW17", "a suite that does not finish counts as KILLED",
     '"TIMEOUT", "the suite did not finish', '"KILLED", "the suite did not finish'),
    ("SW18", "a passing suite counts as KILLED",
     '        return key, line, "SURVIVED", ""\n', '        return key, line, "KILLED", "x"\n'),
]


def run(test, sweep, env):
    e = dict(env, REMINT_BRANCH_SWEEP=sweep)
    p = subprocess.run(["bash", test], env=e, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                       timeout=600)
    fails = [x for x in p.stdout.splitlines() if x.startswith("FAIL")]
    res = [x for x in p.stdout.splitlines() if x.startswith("RESULT")]
    return p.returncode, fails, (res[-1] if res else "")


def main():
    args = sys.argv[1:]
    jobs = 3
    if len(args) == 2 and args[0] == "--jobs" and args[1].isdigit() and int(args[1]) > 0:
        jobs = int(args[1])
    elif args:
        print("usage: remint_branch_sweep_mutations.py [--jobs N]", file=sys.stderr)
        return 2
    here = os.path.dirname(os.path.abspath(__file__))
    sweep = os.path.join(here, "remint_branch_sweep.py")
    test = os.path.join(here, "test_remint_branch_sweep.sh")
    try:
        src = open(sweep, encoding="utf-8").read()
    except OSError as e:
        print("setup: %s" % e, file=sys.stderr)
        return 2
    for mid, _, old, _ in MUTANTS:
        if src.count(old) != 1:
            print("setup: %s: the string to replace occurs %d times" % (mid, src.count(old)), file=sys.stderr)
            return 2
    env = dict(os.environ)
    rc, fails, res = run(test, sweep, env)
    if rc != 0:
        print("FAIL control: the unmutated sweep does not pass its test: rc=%d %s" % (rc, res))
        return 1
    print("PASS control: the unmutated sweep passes its test (%s)" % res)
    bad = 0
    with tempfile.TemporaryDirectory(prefix="sweep_mut.") as work:
        def one(m):
            mid, what, old, new = m
            path = os.path.join(work, mid + ".py")
            with open(path, "w", encoding="utf-8") as f:
                f.write(src.replace(old, new))
            return (mid, what) + run(test, path, env)
        with cf.ThreadPoolExecutor(max_workers=jobs) as ex:
            for mid, what, mrc, fails, res in ex.map(one, MUTANTS):
                if mrc == 1 and fails:
                    print("KILLED %s (%s): %s" % (mid, what, fails[0][5:140]))
                else:
                    bad += 1
                    print("SURVIVED %s (%s): rc=%d %s" % (mid, what, mrc, res))
    print("RESULT: mutants=%d killed=%d survived=%d %s" % (len(MUTANTS), len(MUTANTS) - bad, bad,
                                                          "PASS" if not bad else "FAIL"))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
