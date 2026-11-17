#!/usr/bin/env python3
"""docs/qa/tracker_intake_2026_11_16_v11/tools/leak_scan_test.py -- run the independent leak scan
(leak_scan.py in this directory) over the shared fixture rows tests/workable_items/secret_shape_fixtures.py.

Every "hit" row (a shape the lint must report) must be found by the leak scan too: the scan is the
backstop for the lint, so it may be broader, never narrower. "miss" rows are counted, not judged (a
lead the scan reports on a lookalike is a line for a person to read, not a defect). Labels only.
usage: leak_scan_test.py [--scan PATH]   (default: leak_scan.py next to this file; mutants pass a copy)
Round 11: also the round-10 reviewer's rows (tests/workable_items/secret_shape_fixtures_r11.py, adopted
verbatim): every positive must be reported and every negative must NOT be (here a negative is judged:
bypass=... and secretary=... were the round-10 false positives).
exit 0 every hit row found; 1 a hit row missed; 2 load error; 3 BLIND (a control needle failed).
Evidence class: gate-logic only (section 11.4.289).
"""
import importlib.util
import os
import sys

# the scan's own specification beyond the shared rows: positives it must report and lookalikes it must not
# (fragment-built; the lint is not asked about these)
_V = "Zq7" + "Zq7Zq"
SCAN_POSITIVE = [
    ("scan-pos-key-digit-suffix", "db_pass" + "word2: " + _V),
    ("scan-pos-special-no-digit", "pass" + "word=Qzkw!Rmt@x"),
    ("scan-pos-quoted-letters", "pass" + 'word = "rotationword"'),
    # round 9: a key word with one letter replaced by a decomposable non-Latin letter (BENGALI VOWEL SIGN O
    # is two characters after NFKD and one again after NFKC; the lint does not read it, section B18)
    ("scan-pos-recomposed-odd-letter", "p\u09cb" + "ssword=" + _V),
    # round 10: the whole key word as \xNN escapes (the hex escape is the only reading of it), and a
    # glued key word after set (only the set-command reading sees "mykey")
    ("scan-pos-all-hex-escape", "".join("\\x%02x" % ord(c) for c in "pass" + "word") + "=" + _V),
    ("scan-pos-set-glued-key", "set my" + "key " + _V),
]
SCAN_NEGATIVE = [
    # round 11: two shapes of the landed tracker (CON-330 and CON-333 of the vehicle) the round-11 code first
    # reported: a URL user-info placeholder and a list of kind names with counts
    ("r11-url-placeholder", "the shape '  https://<user>:<pass" + "word>@<host>/<path>' placeholders only"),
    ("r11-kind-counts", "rows by kind: gcp-api-" + "key 24, private-" + "key 12, curl-auth-user 8, github-pat 1."),
    ("scan-neg-letters-only", "tok" + "en: rotationword"),
    ("scan-neg-digits-only", "tok" + "en: 123456789"),
    ("scan-neg-upper-ref", "pass" + "word=$DB_PASS" + "WORD"),
    ("scan-neg-placeholder", "pass" + "word=changeme"),
    ("scan-neg-path", "pass" + "word=/run/secrets/db1"),
    ("scan-neg-call", "pass" + "word = getpass()"),
    # round 10: a property of the credential (a digest of it), not the credential
    ("scan-neg-digest-tail", "pass" + "word_sha256=" + "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08"),
    ("scan-neg-hash-tail", "tok" + "en_hash: 5d41402abc4b2a76b9719d911017c592"),
]
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", "..", ".."))


def main(argv):
    scan = os.path.join(HERE, "leak_scan.py")
    if len(argv) >= 3 and argv[1] == "--scan":
        scan = argv[2]
    sys.path.insert(0, os.path.join(ROOT, "tests", "workable_items"))
    try:
        import secret_shape_fixtures as fx
        import secret_shape_fixtures_r11 as fr
        sp = importlib.util.spec_from_file_location("leak_scan_under_test", scan)
        ls = importlib.util.module_from_spec(sp)
        sp.loader.exec_module(ls)
    except Exception as exc:  # noqa: BLE001
        print("setup: cannot load: %s" % type(exc).__name__)
        return 2
    if not list(ls.scan_line(fx.CONTROL_POSITIVE)) or list(ls.scan_line(fx.CONTROL_NEGATIVE)):
        print("BLIND: a control needle failed")
        return 3
    missed = flagged_miss = hit_rows = 0
    for label, text, want, _detail in fx.FIXTURES:
        got = bool(list(ls.scan_line(text)))
        if want == "hit":
            hit_rows += 1
            if got:
                print("PASS leak found %s" % label)
            else:
                missed += 1
                print("FAIL leak missed %s" % label)
        elif got:
            flagged_miss += 1
            print("LEAD leak broader %s" % label)
    wrong = 0
    for label, text in SCAN_POSITIVE:
        if list(ls.scan_line(text)):
            print("PASS scan positive %s" % label)
        else:
            wrong += 1
            print("FAIL scan positive %s: not reported" % label)
    for label, text in SCAN_NEGATIVE:
        if list(ls.scan_line(text)):
            wrong += 1
            print("FAIL scan negative %s: reported" % label)
        else:
            print("PASS scan negative %s" % label)
    r11_wrong = 0
    for label, text in fr.POS + fr.EXTRA_POS:
        if list(ls.scan_line(text)):
            print("PASS r11 positive %s" % label)
        else:
            r11_wrong += 1
            print("FAIL r11 positive %s: not reported" % label)
    for label, text in fr.NEG:
        if list(ls.scan_line(text)):
            r11_wrong += 1
            print("FAIL r11 negative %s: reported" % label)
        else:
            print("PASS r11 negative %s" % label)
    print("RESULT: hit_rows=%d missed=%d broader_leads=%d own_spec_wrong=%d r11_wrong=%d"
          % (hit_rows, missed, flagged_miss, wrong, r11_wrong))
    return 1 if missed or wrong or r11_wrong else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
