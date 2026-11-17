#!/usr/bin/env python3
"""tests/release/pvl_inventory.py -- the member inventory of the complement of the verification-line grammar
(CON-423 r5; docs/qa/rehearsal_v73_4_fix/r5/class_inventory.md section 3, classes G01 to G12).

Usage: python3 -I tests/release/pvl_inventory.py CHECKER WORKDIR [--classes]
Each class is GENERATED from the grammar, never listed by hand: G02 and G03 put every code point (U+0000 to U+10FFFF,
the whole code space, so no Unicode version changes the count) into the middle of every field value and of a note;
the other classes put every member of a generated set into the field it belongs to. Every case's expectation comes
from the grammar: a code point outside printable ASCII is refused in any field and in a note, a printable ASCII code
point is judged by the independent oracle tests/release/pvl_oracle.py, a G01 placeholder alone is refused and
before or after a value is judged by the oracle (printed as G01-ACCEPTED), a G10 date is accepted exactly when it lies in
the window, a G12 field sequence only when it is the grammar's own order. There are no floors: a class passes when it
has members and no mismatch. --classes prints the class ids, one per line.
Output: `G01-ACCEPTED N <members>`, `CLASS Gnn members=M mismatches=K <title>` per class, INV-FAIL lines (at most
30), then
`INVENTORY classes=12 members=N mismatches=K code_points=1114112`. Exit 0 when K is 0 and every class has members, 1
otherwise, 2 when the checker cannot be loaded.
"""
import datetime
import importlib.util
import itertools
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import pvl_fixture as F  # noqa: E402
import pvl_oracle  # noqa: E402

CLASSES = [
    ("G01", "placeholder words and phrases, every field"),
    ("G02", "every code point in the middle of every field value"),
    ("G03", "every code point in the middle of a note"),
    ("G04", "references that do not resolve under the root"),
    ("G05", "a directory or a non-runnable file as the script"),
    ("G06", "a command that runs no script"),
    ("G07", "checks with no count or naming no test of the job"),
    ("G08", "target words that name nothing"),
    ("G09", "artifact words and prose"),
    ("G10", "every due day from 400 days before creation to 400 days after the window"),
    ("G11", "text after due that is not a note"),
    ("G12", "every order, omission and repetition of the six fields"),
]
PLACEHOLDERS = ["TBD", "TBA", "TBC", "TODO", "TO DO", "TO-DO", "FIXME", "FIX ME", "FIX_ME", "XXX", "N/A", "n/a", "none",
                "pending", "later", "unknown", "to be determined", "to be decided", "not yet", "nobody", "?", "-", ".",
                "...", "lorem ipsum", "T.B.D", "T8D", "70D0", "F1XM3", "tbd", "ask the operator", "same as above",
                "UNCONFIRMED:", "<job>", "{{job}}", "${JOB}", "%s", "none yet", "will check later", "see later"]


def load(path):
    spec = importlib.util.spec_from_file_location("pvl_checker", path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def main(argv):
    if "--classes" in argv:
        for cid, _ in CLASSES:
            print(cid)
        return 0
    if len(argv) != 3:
        sys.stderr.write("usage: pvl_inventory.py CHECKER WORKDIR [--classes]\n")
        return 2
    try:
        m = load(argv[1])
    except Exception as exc:  # noqa: BLE001
        print("INVENTORY-BLIND cannot load the checker: %s" % exc)
        return 2
    os.makedirs(argv[2], exist_ok=True)
    fx = F.make_root(argv[2])
    ctx = F.checker_ctx(m, fx)
    stats = {cid: [0, 0] for cid, _ in CLASSES}
    shown = [0]

    def miss(cid, msg):
        stats[cid][1] += 1
        if shown[0] < 30:
            print("INV-FAIL %s %s" % (cid, msg))
        shown[0] += 1

    def judge(cid, ln, want_ok, label):
        got = m.check_line(ln, ctx)
        stats[cid][0] += 1
        if (got is None) != want_ok:
            miss(cid, "%s: want %s, got %s" % (label, "OK" if want_ok else "REJ", got))

    def oracle(ln):
        return pvl_oracle.accepts(ln, fx)

    # G01 placeholders: a placeholder in place of a field value is refused outright; before or after a value the
    # grammar decides (the oracle): "." is a path argument (the root), so "... tests/p.py ." is a real sentence. The
    # accepted members are counted (G01-ACCEPTED) so a widening shows.
    g01_ok = []
    for f, p in itertools.product(F.ORDER, PLACEHOLDERS):
        judge("G01", F.line(**{f: p}), False, "%s=%r" % (f, p))
        for v in (p + " " + F.BASE[f], F.BASE[f] + " " + p):
            ln = F.line(**{f: v})
            want = oracle(ln)
            judge("G01", ln, want, "%s=%r" % (f, v))
            if want:
                g01_ok.append("%s=%r" % (f, v))
    print("G01-ACCEPTED %d %s" % (len(g01_ok), "; ".join(g01_ok)))
    # G02 every code point in the middle of every field; G03 in the middle of a note
    for c in range(0x110000):
        ch = chr(c)
        printable = 0x20 <= c <= 0x7E
        for f in F.ORDER:
            base = F.BASE[f]
            v = base[:len(base) // 2] + ch + base[len(base) // 2:]
            if printable:
                ln = F.line(**{f: v})
                judge("G02", ln, oracle(ln), "U+%04X in %s" % (c, f))
            else:
                # outside printable ASCII the grammar refuses by its alphabet; field_problem and note_problem are the
                # paths check_line takes for a field value and a note (checked against check_line on the sample below)
                stats["G02"][0] += 1
                if m.field_problem(f, v, ctx=ctx) is None:
                    miss("G02", "U+%04X in %s accepted" % (c, f))
        if printable:
            ln = F.line(note="sched" + ch + "uled")
            judge("G03", ln, oracle(ln), "U+%04X in note" % c)
        else:
            stats["G03"][0] += 1
            if m.note_problem("sched" + ch + "uled") is None:
                miss("G03", "U+%04X in note accepted" % c)
    # the field_problem shortcut agrees with check_line: a sample of code points through the whole line
    for c in list(range(0x80, 0x800, 7)) + [0x2014, 0x2013, 0x00A0, 0x200B, 0x3164, 0xFEFF, 0x10FFFF, 0xD800, 0x1C, 0x7F]:
        for f in F.ORDER:
            base = F.BASE[f]
            ln = F.line(**{f: base[:len(base) // 2] + chr(c) + base[len(base) // 2:]})
            judge("G02", ln, False, "U+%04X in %s (whole line)" % (c, f))
        judge("G03", F.line(note="sched" + chr(c) + "uled"), False, "U+%04X in note (whole line)" % c)
    # G04 references that do not resolve
    for v in ["bash tests/x.sh", "bash tests/t.sh --nope", "bash tests/t.sh case99", "bash tests/t.sh no/such",
              "NOPE=1 bash tests/t.sh", "MODE=off bash tests/t.sh", "bash tests/t.sh --out=no/such",
              "python3 tests/p.py --seed=absentword", "bash tests/esc.sh", "CON-999", "CON-778", "CON-779"]:
        judge("G04", F.line(job=v, checks="tests/t.sh pass=1"), False, "job=%r" % v)
    for v in ["remote nowhere", "board T9", "device SER43", "container c1", "vm vm2", "runner r:8"]:
        judge("G04", F.line(target=v), False, "target=%r" % v)
    # G05 directories and non-runnable files as the script, for each runner (the oracle decides the two real scripts)
    for runner, path in itertools.product(("bash", "sh", "python3", "python3 -I"),
                                          ("tests", "tests/", "scripts", ".", "README.md", "docs/Issues.md",
                                           "config/verification_targets.tsv", "upstreams", "tests/dir.sh", "tests/p.py", "tests/t.sh")):
        v = "%s %s" % (runner, path)
        ln = F.line(job=v, checks="%s pass=1" % path)
        judge("G05", ln, oracle(ln), "job=%r" % v)
    # G06 commands that run no script
    for v in ["go test ./...", "make check", "make -", "git -x", "npm test", "pytest", "cargo test", "./tests/t.sh",
              "tests/t.sh", "env bash tests/t.sh", "nice bash tests/t.sh", "sudo bash tests/t.sh", "exec bash tests/t.sh",
              "bash -c tests/t.sh", "zsh tests/t.sh", "python tests/p.py", "python3.12 tests/p.py", "perl tests/t.sh"]:
        judge("G06", F.line(job=v, checks="tests/t.sh pass=1"), False, "job=%r" % v)
    # G07 checks: every subject with every term shape (the oracle decides; most are refused)
    subj = ["tests/t.sh", "case12", "tests/p.py", "tests/x.sh", "case7", "CON-777", "3", "all"]
    terms = ["", "rc=0", "verdict=PASS", "rc=0 verdict=PASS", "pass=1", "passed=1", "pass=1 pass=2", "pass=a", "pass="]
    for s_, t in itertools.product(subj, terms):
        v = (s_ + " " + t).strip()
        ln = F.line(checks=v)
        judge("G07", ln, oracle(ln), "checks=%r" % v)
    # G08 target words that name nothing
    for v in ["board", "device", "board target", "host checkout", "host or whichever", "the host", "localhost",
              "any host", "hosts", "Host", "HOST", "host,", ", host", "host, ", "repo", "checkout", "scratch",
              "clone", "remote", "remote ", "board T1 T2", "board: T1"]:
        judge("G08", F.line(target=v), False, "target=%r" % v)
    # G09 artifact words
    for v in ["build", "image", "the build", "main branch", "HEAD", "head", "master", "commit", "merge", "tag",
              "commit abcdefg", "sha256 0123456789abcdef", "main containing 3b958793", "latest", "release", "v73.4"]:
        judge("G09", F.line(artifact=v), False, "artifact=%r" % v)
    # G10 every day around the window
    last = F.TODAY + datetime.timedelta(days=F.WINDOW)
    d = F.CREATED - datetime.timedelta(days=400)
    while d <= last + datetime.timedelta(days=400):
        judge("G10", F.line(due=d.isoformat()), F.CREATED <= d <= last, "due=%s" % d)
        d += datetime.timedelta(days=1)
    # G11 text after due
    for t in [".", ". Not VERIFIED-DONE", " (UNCONFIRMED)", " approx", ", maybe", ";", " TBD", " -- ", " -- x",
              " -- note", " -- note: ", " -- remark: x", " — x"]:
        judge("G11", F.line() + t, False, "after due %r" % t)
    # G12 every order of the six fields, every omission of one, every repetition of one
    vals = dict(F.BASE)

    def seq_line(seq):
        return "**Verification:** provisional -- " + " -- ".join("%s: %s" % (k, vals[k]) for k in seq)
    for perm in itertools.permutations(F.ORDER):
        judge("G12", seq_line(perm), perm == F.ORDER, "order %s" % ",".join(perm))
    for i in range(6):
        judge("G12", seq_line(F.ORDER[:i] + F.ORDER[i + 1:]), False, "without %s" % F.ORDER[i])
        judge("G12", seq_line(F.ORDER[:i + 1] + (F.ORDER[i],) + F.ORDER[i + 1:]), False, "%s twice" % F.ORDER[i])
    total = bad = 0
    empty = False
    for cid, title in CLASSES:
        n, k = stats[cid]
        total += n
        bad += k
        empty |= n == 0
        print("CLASS %s members=%d mismatches=%d %s" % (cid, n, k, title))
    print("INVENTORY classes=%d members=%d mismatches=%d code_points=%d" % (len(CLASSES), total, bad, 0x110000))
    return 0 if bad == 0 and not empty else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
