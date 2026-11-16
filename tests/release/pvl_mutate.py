#!/usr/bin/env python3
"""tests/release/pvl_mutate.py -- paired mutants of the verification-line checker and its harnesses (CON-423 r5).

Usage: python3 -I tests/release/pvl_mutate.py REPO WORKDIR [ID ...]
Mutants: the own mutants of tests/release/pvl_mutants.tsv (ID<TAB>FILE<TAB>OLD<TAB>NEW<TAB>WHY, OLD and NEW as Python
string literals) and every reviewer mutant tests/release/pvl_reviewer.py lists as APPLIES on a file of this suite (the
checker and tests/release/pvl_*.py; the release-tooling mutants run in their own suites). For each mutant a sandbox under
WORKDIR gets a copy of the checker, the pvl_*.py harnesses and scripts/release/render_release_entry.py; OLD must occur
exactly once (else NOT-APPLIED, a FAIL); then the kill harnesses run in order until one exits non-zero:
  api       the command line on a fixture database: golden good PASS, every golden-bad body refused with its id, the
            two-reading body refused, every look-alike of the render's map named in the refusal reason
  grid      tests/release/pvl_grid.py
  linemodel tests/release/pvl_linemodel.py --no-pandoc (pandoc is compared in the main suite)
  property  tests/release/pvl_property.py with seed 290423 and 300 sentences
  timing    tests/release/pvl_timing.py with its default limit (the output must say limit=1.00s)
  inventory tests/release/pvl_inventory.py (only when nothing earlier killed the mutant)
Output: `MUT <id> KILLED by <harness> (rc N)` / `MUT <id> SURVIVED` / `MUT <id> NOT-APPLIED`, then
`MUTATE total=N killed=K survived=S not_applied=A`. Exit 0 when S and A are 0, else 1. A harness run is bounded at 600 s.
Section 11.4.289(C)(2): gate-logic only.
"""
import ast
import os
import shutil
import sqlite3
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CHECKER = "scripts/validation/check_provisional_verification_lines.py"
RENDER = "scripts/release/render_release_entry.py"
HARNESS = ["pvl_fixture.py", "pvl_oracle.py", "pvl_grid.py", "pvl_linemodel.py", "pvl_property.py", "pvl_timing.py",
           "pvl_inventory.py"]
SUITE_FILES = {CHECKER} | {"tests/release/" + h for h in HARNESS}


def own_mutants(repo):
    out = []
    with open(os.path.join(repo, "tests/release/pvl_mutants.tsv"), encoding="utf-8") as fh:
        for ln in fh:
            if ln.startswith("#") or not ln.strip():
                continue
            mid, rel, old, new, why = ln.rstrip("\n").split("\t", 4)
            out.append((mid, rel, ast.literal_eval(old), ast.literal_eval(new)))
    return out


def reviewer_mutants(repo):
    p = subprocess.run([sys.executable, "-I", os.path.join(HERE, "pvl_reviewer.py"), "mutants", repo],
                       capture_output=True, text=True)
    out = []
    for ln in p.stdout.splitlines():
        if ln.startswith("REV-MUT-SPEC "):
            mid, rel, old, new = ln[len("REV-MUT-SPEC "):].split("\t")
            if rel in SUITE_FILES:
                out.append((mid, rel, ast.literal_eval(old), ast.literal_eval(new)))
    return out


def sandbox(repo, base):
    for rel in [CHECKER, RENDER] + ["tests/release/" + h for h in HARNESS]:
        dst = os.path.join(base, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copyfile(os.path.join(repo, rel), dst)


def api(box, work):
    """The command-line cases; 0 when the checker behaves, 1 otherwise."""
    sys.path.insert(0, os.path.join(box, "tests/release"))
    try:
        import importlib
        F = importlib.import_module("pvl_fixture")
        fx = F.make_root(os.path.join(work, "root"))
    finally:
        sys.path.pop(0)
    good = F.line()
    bodies = {
        "CON-801": ("## x\n\n" + good, True),
        "CON-802": ("## x\n\n" + good + "\n\n" + good, False),                    # two lines
        "CON-803": ("## x\n\n" + F.line(job="CON-778"), False),                    # a Fixed item is not a job
        "CON-804": ("## x\n\n" + F.line(due="2026-10-31"), False),                 # before created
        "CON-805": ("## x\n\n" + F.line(due="2027-01-16"), False),                 # after the window
        "CON-806": ("## x\n<!-->\n\n" + good, False),                              # the two readings differ
        "CON-807": ("## x\ntext\n" + good, False),                                 # continues a paragraph
        "CON-808": ("## x\n\n> q\n" + good, False),                                # lazy continuation
        "CON-809": ("## x\n\n```\n" + good + "\n```\n", False),                    # fenced
        "CON-810": ("## x\n\n" + F.line(job="CON-810"), False),                    # the item itself
    }
    db = os.path.join(work, "api.db")
    if os.path.exists(db):
        os.remove(db)
    con = sqlite3.connect(db)
    con.execute("create table items (atm_id text primary key, status text, body_md text, created_at text)")
    others = {k: st for k, st in F.ITEMS.items() if st not in ("Ready for testing", "In testing")}
    for k, st in others.items():
        con.execute("insert into items values (?,?,?,?)", (k, st, "x", "2026-11-01"))
    for k, (b, _) in bodies.items():
        con.execute("insert into items values (?,?,?,?)", (k, "Ready for testing", b, "2026-11-01T09:00:00Z"))
    con.commit()
    con.close()
    p = subprocess.run([sys.executable, "-I", os.path.join(box, CHECKER), "--root", fx["root"], "--today",
                        F.TODAY.isoformat(), db], capture_output=True, text=True)
    failed = {ln.split()[1] for ln in p.stdout.splitlines() if ln.startswith("FAIL ")}
    want = {k for k, (_, ok) in bodies.items() if not ok}
    if p.returncode != 1 or failed != want:
        return 1
    if "FAIL CON-810 Ready for testing: field 'job' names the item itself (CON-810), not a job" not in p.stdout:
        return 1
    if "CHECKED items=%d provisional_status=%d ok=1 fail=%d" % (len(others) + len(bodies), len(bodies),
                                                               len(want)) not in p.stdout:
        return 1
    # every look-alike of the render's map (an independent copy) is named in the refusal reason
    src = open(os.path.join(box, RENDER), encoding="utf-8").read()
    rmap = None
    for n in ast.parse(src).body:
        if isinstance(n, ast.Assign) and any(getattr(t, "id", "") == "CONFUSABLES" for t in n.targets):
            rmap = ast.literal_eval(n.value)
    if not rmap:
        return 1
    import importlib.util
    spec = importlib.util.spec_from_file_location("pvl_api_checker", os.path.join(box, CHECKER))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    for ch, asc in rmap.items():
        r = m.note_problem("x" + ch)
        if not r or ("a look-alike of %s" % asc) not in r:
            return 1
    return 0


def run(box, work, name):
    rl = os.path.join(box, "tests/release")
    ck = os.path.join(box, CHECKER)
    py = [sys.executable, "-I"]
    cmd = {"grid": py + [os.path.join(rl, "pvl_grid.py"), ck, os.path.join(work, "grid")],
           "linemodel": py + [os.path.join(rl, "pvl_linemodel.py"), ck, "--no-pandoc"],
           "property": py + [os.path.join(rl, "pvl_property.py"), ck, os.path.join(work, "prop"), "290423", "300"],
           "timing": py + [os.path.join(rl, "pvl_timing.py"), ck, os.path.join(work, "tim")],
           "inventory": py + [os.path.join(rl, "pvl_inventory.py"), ck, os.path.join(work, "inv")]}[name]
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
    except subprocess.TimeoutExpired:
        return 124
    if name == "timing" and p.returncode == 0 and "limit=1.00s" not in p.stdout:
        return 1
    return p.returncode


def main(argv):
    if len(argv) < 3:
        sys.stderr.write("usage: pvl_mutate.py REPO WORKDIR [ID ...]\n")
        return 64
    repo, work = os.path.abspath(argv[1]), os.path.abspath(argv[2])
    only = set(argv[3:])
    muts = own_mutants(repo) + reviewer_mutants(repo)
    # control: the unmutated copy passes every kill harness (else a kill proves nothing)
    base = os.path.join(work, "_control")
    if os.path.exists(base):
        shutil.rmtree(base)
    os.makedirs(os.path.join(base, "work"))
    sandbox(repo, os.path.join(base, "box"))
    rcs = [("api", api(os.path.join(base, "box"), os.path.join(base, "work")))] + [
        (h, run(os.path.join(base, "box"), os.path.join(base, "work"), h))
        for h in ("grid", "linemodel", "property", "timing", "inventory")]
    shutil.rmtree(base)
    bad = [h for h, rc in rcs if rc]
    if bad:
        print("MUTATE-BLIND the unmutated copy fails: %s" % ", ".join(bad))
        return 2
    print("MUT-CONTROL unmutated copy passes api grid linemodel property timing inventory")
    killed = survived = napp = 0
    for mid, rel, old, new in muts:
        if only and mid not in only:
            continue
        base = os.path.join(work, mid)
        if os.path.exists(base):
            shutil.rmtree(base)
        box, scratch = os.path.join(base, "box"), os.path.join(base, "work")
        os.makedirs(scratch)
        sandbox(repo, box)
        path = os.path.join(box, rel)
        src = open(path, encoding="utf-8").read()
        if src.count(old) != 1:
            napp += 1
            print("MUT %s NOT-APPLIED (%s: old text occurs %d times)" % (mid, rel, src.count(old)))
            continue
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(src.replace(old, new, 1))
        by = None
        try:
            rc = api(box, scratch)
        except Exception:  # noqa: BLE001 -- a mutant that breaks the module is caught
            rc = 2
        if rc:
            by = ("api", rc)
        for h in ("grid", "linemodel", "property", "timing", "inventory"):
            if by:
                break
            rc = run(box, scratch, h)
            if rc:
                by = (h, rc)
        if by:
            killed += 1
            print("MUT %s KILLED by %s (rc %d)" % (mid, by[0], by[1]))
        else:
            survived += 1
            print("MUT %s SURVIVED" % mid)
        shutil.rmtree(base)
    print("MUTATE total=%d killed=%d survived=%d not_applied=%d" % (killed + survived + napp, killed, survived, napp))
    return 0 if survived == napp == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
