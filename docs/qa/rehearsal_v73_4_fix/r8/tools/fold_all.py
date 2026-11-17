"""Compare the checker's fold() with the reference fold() for every code point (round 8 evidence).

Usage: python3 -I fold_all.py REPO

The checker's fold() reads the reading table embedded in
scripts/validation/check_provisional_verification_lines.py. The reference fold() in
scripts/validation/pvl_reading_table.py calls ICU live. This tool reads every code point
(except "&", which fold() treats as the start of a character reference) with both and prints
the number that differ.

A zero proves nothing unless the comparison can see a difference (section 11.4.273). So the
tool first runs a positive control: it changes one reading in a copy of the checker's loaded
table (U+13D9 CHEROKEE LETTER DO, read as "v", is changed to "x") and requires exactly that one
mismatch. If the control does not see exactly one mismatch, the run prints FOLD-ALL-BLIND and
exits 2.

Output, last line: FOLD-ALL code_points=N mismatches=M control=1 table_problem=None
Exit: 0 when M is 0, 1 when M is not 0, 2 when blind (control failed, ICU absent, or the
checker's table is not intact).
"""
import importlib.util
import os
import sys

CONTROL_CP = 0x13D9


def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def mismatches(ck, rt, icu, cps):
    bad = []
    for cp in cps:
        c = chr(cp)
        if ck.fold(c) != rt.fold(icu, c):
            bad.append(cp)
    return bad


def main(argv):
    if len(argv) != 2:
        print(__doc__.strip().splitlines()[2])
        return 64
    repo = argv[1]
    ck = load("pvl_ck", os.path.join(repo, "scripts/validation/check_provisional_verification_lines.py"))
    rt = load("pvl_rt", os.path.join(repo, "scripts/validation/pvl_reading_table.py"))
    problem = ck._reading()[2]
    if problem is not None:
        print("FOLD-ALL-BLIND the checker's table is not intact: %s" % problem)
        return 2
    try:
        icu = rt.ICU()
    except Exception as exc:  # ICU absent: the reference cannot be computed
        print("FOLD-ALL-BLIND ICU cannot be loaded: %s" % exc)
        return 2
    cps = [cp for cp in rt.code_points() if chr(cp) != "&"]

    # positive control: one changed reading must give exactly one mismatch
    drop, rmap, prob = ck._READING[0]
    if rmap.get(CONTROL_CP) is None:
        print("FOLD-ALL-BLIND the control code point U+%04X has no reading in the table" % CONTROL_CP)
        return 2
    changed = dict(rmap)
    changed[CONTROL_CP] = "x" if rmap[CONTROL_CP] != "x" else "y"
    ck._READING[0] = (drop, changed, prob)
    seen = mismatches(ck, rt, icu, cps)
    ck._READING[0] = (drop, rmap, prob)
    print("CONTROL changed=U+%04X mismatches=%d at=%s" % (CONTROL_CP, len(seen), ",".join("U+%04X" % c for c in seen[:5])))
    if seen != [CONTROL_CP]:
        print("FOLD-ALL-BLIND the control did not see exactly one mismatch")
        return 2

    bad = mismatches(ck, rt, icu, cps)
    for cp in bad[:20]:
        print("MISMATCH U+%04X checker=%r reference=%r" % (cp, ck.fold(chr(cp)), rt.fold(icu, chr(cp))))
    print("FOLD-ALL code_points=%d mismatches=%d control=1 table_problem=%s" % (len(cps), len(bad), ck.reader_problem()))
    return 0 if not bad else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
