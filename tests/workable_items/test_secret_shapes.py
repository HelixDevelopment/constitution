#!/usr/bin/env python3
"""tests/workable_items/test_secret_shapes.py -- the shared-fixture oracle for the lint's credential rules
(round 8, review findings N1 to N3).

Documentation (section 11.4.18): docs/guides/intake_lint_guide.md, section "Credential shapes".

WHAT  Loads the lint named on the command line (a path; the mutation suites pass a mutated copy) and runs
      its secret_hits() over every row of secret_shape_fixtures.FIXTURES:
        a "hit" row must be reported with EXACTLY the rule names in EXPECT_RULES (a narrower or a renamed
        rule fails, so a mutant that only changes which rule reports a shape is killed);
        a "miss" row must be reported by no rule (negatives, and the section-B members the lint does
        not claim).
      Control needles run first (section 11.4.273): a known member must be reported and a prose line
      must not, otherwise the instrument is BLIND and the run exits 3 without judging any row. Then every
      keyed rule of the lint must be reached by at least one "hit" row, so a rule nobody tests is a
      failure, not a silent gap.
OUTPUT  One line per row with its LABEL only (never the text, section 11.4.10), then
        "RESULT: pass=N fail=M rows=R".
USAGE   test_secret_shapes.py <path-of-intake_lint.py> [--failfast]
EXIT    0 every row as expected; 1 a row failed; 2 usage or load error; 3 BLIND (a control needle failed).
EVIDENCE CLASS  gate-logic only (section 11.4.289).
"""
import importlib.util
import os
import sys


def load(path):
    spec = importlib.util.spec_from_file_location("intake_lint_under_test", path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def rules_of(mod, text):
    return tuple(sorted({name for name, _match in mod.secret_hits(text)}))


def main(argv):
    if len(argv) == 1:  # no argument: the lint of this checkout (the full-suite runner calls it this way)
        argv = [argv[0], os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..",
                                      "scripts", "workable-items", "intake_lint.py")]
    if len(argv) < 2 or argv[1].startswith("-"):
        print("usage: test_secret_shapes.py <path-of-intake_lint.py> [--failfast]", file=sys.stderr)
        return 2
    failfast = "--failfast" in argv[2:]
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    try:
        import secret_shape_fixtures as fx
        mod = load(argv[1])
    except Exception as exc:  # noqa: BLE001 - any load failure is a setup error
        print("setup: cannot load: %s" % type(exc).__name__, file=sys.stderr)
        return 2

    if not rules_of(mod, fx.CONTROL_POSITIVE) or rules_of(mod, fx.CONTROL_NEGATIVE):
        print("BLIND: a control needle failed; no row judged")
        return 3

    passed = failed = 0
    for label, text, want, detail in fx.FIXTURES:
        got = rules_of(mod, text)
        if want == "hit":
            exp = tuple(sorted(fx.EXPECT_RULES[label]))
            good = got == exp
            why = "" if good else " (got %s, want %s)" % (",".join(got) or "none", ",".join(exp))
        else:
            good = not got
            why = "" if good else " (got %s, want none; %s)" % (",".join(got), detail)
        if good:
            passed += 1
            print("PASS shape %s" % label)
        else:
            failed += 1
            print("FAIL shape %s%s" % (label, why))
            if failfast:
                print("RESULT: pass=%d fail=%d rows=%d (stopped at the first failure)" % (passed, failed, len(fx.FIXTURES)))
                return 1

    reached = {r for rs in fx.EXPECT_RULES.values() for r in rs}
    extractors = getattr(mod, "KEYED_EXTRACTORS", None)
    if extractors is None:
        failed += 1
        print("FAIL rule inventory: the lint has no KEYED_EXTRACTORS list")
        extractors = []
    keyed = [n for _fn, names in extractors for n in names]
    for name in keyed:
        if name in reached:
            passed += 1
            print("PASS rule reached %s" % name)
        else:
            failed += 1
            print("FAIL rule reached %s: no hit row reports it" % name)
            if failfast:
                break
    print("RESULT: pass=%d fail=%d rows=%d" % (passed, failed, len(fx.FIXTURES)))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
