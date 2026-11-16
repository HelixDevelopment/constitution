#!/usr/bin/env python3
"""tests/release/pvl_fixture.py -- the fixture root, tracker items and dates the verification-line tests resolve
against (CON-423 r5). Imported by pvl_grid.py, pvl_property.py, pvl_inventory.py and pvl_timing.py; not a test.

make_root(dir) builds, under DIR, a root with two scripts whose text names a fixed set of options, selectors and env
names, an upstream definition, a target registry, a directory, two non-runnable files and a symlink that leaves the
root. It returns a dict: root (the real path), items, item_id, created, today, window, targets (the ctx of the
oracle) and the vocabulary the generator of the property test draws from.
Self-check: python3 -I tests/release/pvl_fixture.py --selftest WORKDIR builds the root twice (the second build must
not fail on the first) and asserts its shape: every file present, tests/dir.sh a directory, tests/esc.sh resolving
outside the root, the registry listing every target, line() giving the six fields in order. Prints
`FIXTURE-SELFTEST checks=N wrong=K` and exits 0 when K is 0, 1 otherwise, 64 on a usage error.
"""
import datetime
import os

T_SH = """#!/usr/bin/env bash
# fixture test script: the options, selectors and env names below are the vocabulary a job may use
# options: --fast -k --out --level -v
# selectors: case12 case7 suite3 alpha.2
# env: MODE STRICT LEVEL_N
# words: on 1 nightly fast1
echo "MODE=$MODE STRICT=$STRICT LEVEL_N=$LEVEL_N"
"""
P_PY = """# fixture python test: --root --db --seed -q selectors: grid1 inv2; env PVL_SEED; words: quick deep
"""
ITEMS = {"CON-777": "In progress", "CON-776": "Queued", "CON-775": "Operator-blocked", "CON-778": "Fixed",
         "CON-779": "Ready for testing", "CON-774": "In testing"}
ITEM_ID = "CON-779"
CREATED = datetime.date(2026, 11, 1)
TODAY = datetime.date(2026, 11, 16)
WINDOW = 60
TARGETS = {("board", "T1"), ("device", "SER42"), ("container", "pvl-c1"), ("vm", "vm.1"), ("runner", "r:7")}

VOCAB = {
    "scripts": {"tests/t.sh": "bash", "tests/p.py": "python3"},
    "options": {"tests/t.sh": ["--fast", "-k", "--out", "--level", "-v"], "tests/p.py": ["--root", "--db", "--seed", "-q"]},
    "selectors": {"tests/t.sh": ["case12", "case7", "suite3", "alpha.2"], "tests/p.py": ["grid1", "inv2"]},
    "env": {"tests/t.sh": ["MODE", "STRICT", "LEVEL_N"], "tests/p.py": ["PVL_SEED"]},
    "words": {"tests/t.sh": ["on", "nightly", "fast1"], "tests/p.py": ["quick", "deep"]},
    "paths": [".", "tests", "tests/t.sh", "docs/Issues.md", "README.md", "upstreams/github.sh", "scripts"],
    "trackers": ["CON-777", "CON-776", "CON-775"],
    "remotes": ["github", "gitlab"],
}


def make_root(base):
    root = os.path.join(base, "pvlroot")
    for d in ("tests", "docs", "scripts", "upstreams", "config", "tests/dir.sh"):  # dir.sh: a directory named like a script
        os.makedirs(os.path.join(root, d), exist_ok=True)
    files = {"tests/t.sh": T_SH, "tests/p.py": P_PY, "docs/Issues.md": "# issues\n", "README.md": "# readme\n",
             "upstreams/github.sh": "export UPSTREAMABLE_REPOSITORY=x\n",
             "upstreams/gitlab.sh": "export UPSTREAMABLE_REPOSITORY=y\n",
             "config/verification_targets.tsv": "# kind\tid\n" + "".join(
                 "%s\t%s\n" % t for t in sorted(TARGETS))}
    for rel, text in files.items():
        with open(os.path.join(root, rel), "w", encoding="utf-8") as fh:
            fh.write(text)
    esc = os.path.join(root, "tests", "esc.sh")
    if not os.path.lexists(esc):
        os.symlink(os.path.join(base, "outside.sh"), esc)
    with open(os.path.join(base, "outside.sh"), "w", encoding="utf-8") as fh:
        fh.write("# outside the root: --fast case12\n")
    real = os.path.realpath(root)
    return {"root": real, "items": dict(ITEMS), "item_id": ITEM_ID, "created": CREATED, "today": TODAY,
            "window": WINDOW, "targets": set(TARGETS)}


def checker_ctx(m, fx):
    """The checker's Context for the fixture."""
    return m.Context(fx["root"], fx["items"], fx["item_id"], fx["created"], fx["today"], fx["window"], fx["targets"])


BASE = {"job": "bash tests/t.sh -k case12; python3 -I tests/p.py", "checks": "tests/t.sh pass=3; tests/p.py pass=1",
        "layer": "host-only", "target": "host", "artifact": "main", "due": "2026-11-20"}
ORDER = ("job", "checks", "layer", "target", "artifact", "due")


def line(**kw):
    """A verification line from BASE with the fields in KW replaced (note=... appends a note)."""
    f = dict(BASE)
    note = kw.pop("note", None)
    f.update(kw)
    s = "**Verification:** provisional -- " + " -- ".join("%s: %s" % (k, f[k]) for k in ORDER)
    return s + (" -- note: " + note if note is not None else "")


def _selftest(work):
    fx = make_root(work)
    fx = make_root(work)
    r = fx["root"]
    checks = [os.path.isfile(os.path.join(r, f)) for f in ("tests/t.sh", "tests/p.py", "docs/Issues.md", "README.md",
                                                          "upstreams/github.sh", "upstreams/gitlab.sh",
                                                          "config/verification_targets.tsv")]
    checks.append(os.path.isdir(os.path.join(r, "tests/dir.sh")))
    esc = os.path.realpath(os.path.join(r, "tests/esc.sh"))
    checks.append(not esc.startswith(r + os.sep))
    reg = open(os.path.join(r, "config/verification_targets.tsv"), encoding="utf-8").read()
    checks.append(all("%s\t%s\n" % t in reg for t in TARGETS))
    ln = line()
    pos = [ln.find(" -- %s: " % k) for k in ORDER]
    checks.append(all(p > 0 for p in pos) and pos == sorted(pos))
    checks.append(line(note="x").endswith(" -- note: x"))
    wrong = checks.count(False)
    print("FIXTURE-SELFTEST checks=%d wrong=%d" % (len(checks), wrong))
    return 0 if wrong == 0 else 1


if __name__ == "__main__":
    import sys
    if len(sys.argv) != 3 or sys.argv[1] != "--selftest":
        sys.stderr.write("usage: pvl_fixture.py --selftest WORKDIR\n")
        sys.exit(64)
    sys.exit(_selftest(sys.argv[2]))
