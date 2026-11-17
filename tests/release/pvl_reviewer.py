#!/usr/bin/env python3
"""tests/release/pvl_reviewer.py -- runs the independent reviewers' probes and lists their mutants against the
round-5 checker (CON-423 r5). The reviewer files under tests/release/pvl_reviewer/ are copied VERBATIM from the review
rounds (their sha256 sums are in pvl_reviewer/SHA256SUMS and are checked first); they hold FAKE values only.
They are stored as .py.txt so the full-suite census does not run them as tests; python3 runs them by path.

Usage:
  python3 -I tests/release/pvl_reviewer.py probes REPO WORKDIR [--write-changes]
  python3 -I tests/release/pvl_reviewer.py mutants REPO
probes: runs probe_r3.py.txt (field values and a DoS timing), probe_r3b.py.txt (separator classes, shape-only jobs) and
  probe_r4.py.txt (field values with --root, line-model bodies) with REPO's checker. Every case whose expectation was REJ
  must still be refused. A case whose expectation was OK may be refused ONLY when it is listed in
  pvl_reviewer/changes.tsv (probe, field, value) with the reason the grammar refuses it (the deliberate narrowing of
  docs/qa/rehearsal_v73_4_fix/r5/class_inventory.md section 5); a listed row that no longer differs is STALE, a refused
  OK case that is not listed is UNEXPLAINED, a REJ case accepted is REVERSED. probe_r3b must report "accepted 0" and no
  shape-only job accepted; every DoS timing of probe_r3 must be under 1 s. Prints
  `REVIEWER probes cases=N kept=K narrowed=C unexplained=U stale=S reversed=R dos_worst=<s>`; exit 0 when U, S and R
  are 0, the r3b checks hold and the DoS is in bound, else 1; 2 when a reviewer file's sum differs.
  --write-changes prints the rows of the narrowed cases (to review by hand before they go into changes.tsv).
mutants: reads the mutant tables of mutants_r2.py.txt, mutants_r3.py.txt, mutants_r4.py.txt and (round 6) the TSV
  mutants_r5.tsv, and for each prints
  `REV-MUT <id> APPLIES <file>` (its OLD text occurs exactly once in REPO's file: the suite applies it verbatim) or
  `REV-MUT <id> NOT-APPLICABLE <file> covered-by <cases>` (the mechanism was removed; pvl_reviewer/mutants_map.tsv
  must name the cases covering the removed class). A mutant of a release-tooling file applies there and is run by
  that file's own suite: its map row is `OTHER-SUITE <suite>` and the suite must name the id. A not-applicable mutant
  without a map row, or a map row for a mutant of this suite that applies, is a FAIL. Then `REVIEWER mutants total=N applies=A not_applicable=K fail=F`; exit 0 when F is 0.
  `REV-MUT-SPEC <id>\\t<file>\\t<old>\\t<new>` lines (old and new as Python literals) let the suite apply the ones that
  apply. Round 8 adds the r7 reviewer's table mutants_r7.tsv (R7M01-R7M15).
probes, round 8: the r7 reviewer's probes probe_bang_r7.py.txt (HTML5 comment ends, review r7 F1), probe_near_r7.py.txt
  (a second label written with invisible or look-alike characters, review r7 F2) and probe_shapes_r7.py.txt (GFM and
  other shapes, review r7 F3), verbatim. Every row the checker ACCEPTS while a reader's rendering is not clean, and
  every row it REFUSES while every reader's rendering is clean (a false refusal), must be listed in
  pvl_reviewer/changes_r7.tsv (probe, name, kind, reason); a listed row that no longer occurs is STALE. Every
  probe_near row must be refused. Prints `REVIEWER probes_r7 rows=N refused=R listed=L unlisted=U stale=S PASS|FAIL`;
  pandoc missing: `REVIEWER probes_r7 SKIP pandoc not found` and exit 1 (the r7 probes call pandoc).
"""
import ast
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
RD = os.path.join(HERE, "pvl_reviewer")
# files of this suite; a mutant of any other file (release tooling) is run by the suite its map row names
OWN_PREFIXES = ("scripts/validation/check_provisional_verification_lines.py", "tests/release/pvl_")


def sums_ok():
    bad = []
    with open(os.path.join(RD, "SHA256SUMS"), encoding="utf-8") as fh:
        for ln in fh:
            h, name = ln.split()
            with open(os.path.join(RD, name), "rb") as f:
                if hashlib.sha256(f.read()).hexdigest() != h:
                    bad.append(name)
    return bad


def load_tsv(name):
    rows = []
    with open(os.path.join(RD, name), encoding="utf-8") as fh:
        for ln in fh:
            if ln.startswith("#") or not ln.strip():
                continue
            rows.append(ln.rstrip("\n").split("\t"))
    return rows


def probes(repo, work, write):
    os.makedirs(work, exist_ok=True)
    py = [sys.executable, "-I"]
    got = {}  # (probe, field, value-repr) -> (expect, verdict, reason)
    p = subprocess.run(py + [os.path.join(RD, "probe_r3.py.txt"), repo, os.path.join(work, "r3.json")], capture_output=True,
                       text=True)
    head = json.loads(p.stdout.splitlines()[0])
    dos_worst = max(v[0] for v in head["dos"].values())
    for x in json.load(open(os.path.join(work, "r3.json"), encoding="utf-8")):
        got[("r3", x["field"], repr(x["value"]))] = (x["expect"], x["got"], x["reason"] or "")
    p = subprocess.run(py + [os.path.join(RD, "probe_r3b.py.txt"), repo], capture_output=True, text=True)
    m3b = re.search(r"^separator-class cases (\d+) accepted (\d+)$", p.stdout, re.M)
    shape = [ln for ln in p.stdout.split("--- shape-only job", 1)[-1].splitlines()[1:] if ln.strip()]
    r3b_ok = bool(m3b) and m3b.group(2) == "0" and shape and not any(ln.rstrip().endswith(" None") for ln in shape)
    p = subprocess.run(py + [os.path.join(RD, "probe_r4.py.txt"), repo, repo], capture_output=True, text=True)
    for ln in p.stdout.splitlines():
        if ln.startswith(("MATCH\t", "MISMATCH\t")):
            _, cls, f, exp, g, reason, val = ln.split("\t", 6)
            got[("r4", f, val)] = (exp, g, reason)
    changes = {(r[0], r[1], r[2]): r[3] for r in load_tsv("changes.tsv")}
    kept = narrowed = unexpl = stale = rev = 0
    for key, (exp, g, reason) in sorted(got.items()):
        if exp == g:
            kept += 1
            if key in changes:
                stale += 1
                print("REV-STALE %s %s %s: listed as narrowed but %s" % (key[0], key[1], key[2], g))
        elif exp == "REJ":
            rev += 1
            print("REV-REVERSED %s %s %s: the reviewer refused it, the checker accepts it" % key)
        elif key in changes:
            narrowed += 1
            print("REV-NARROWED %s %s %s: %s" % (key[0], key[1], key[2], changes[key]))
        else:
            unexpl += 1
            print("REV-UNEXPLAINED %s %s %s: %s" % (key[0], key[1], key[2], reason))
            if write:
                print("ROW\t%s\t%s\t%s\t%s" % (key[0], key[1], key[2], reason))
    for key in changes:
        if key not in got:
            stale += 1
            print("REV-STALE %s %s %s: not a case of the probe" % key)
    print("REV-R3B %s %s" % ("PASS" if r3b_ok else "FAIL", m3b.group(0) if m3b else "no summary"))
    print("REVIEWER probes cases=%d kept=%d narrowed=%d unexplained=%d stale=%d reversed=%d dos_worst=%.3f" % (
        len(got), kept, narrowed, unexpl, stale, rev, dos_worst))
    return 0 if unexpl == stale == rev == 0 and r3b_ok and dos_worst < 1.0 else 1


def mutant_tables():
    out = []
    for name in ("mutants_r2.py.txt", "mutants_r3.py.txt", "mutants_r4.py.txt"):
        tree = ast.parse(open(os.path.join(RD, name), encoding="utf-8").read())
        env = {}
        for node in tree.body:
            if isinstance(node, ast.Assign) and isinstance(node.targets[0], ast.Name):
                tgt = node.targets[0].id
                if isinstance(node.value, ast.Constant) and isinstance(node.value.value, str):
                    env[tgt] = node.value.value
                elif tgt == "M":
                    for elt in node.value.elts:
                        vals = [env[e.id] if isinstance(e, ast.Name) else ast.literal_eval(e) for e in elt.elts]
                        out.append((vals[0].split()[0], vals[1], vals[2], vals[3]))
    # round 6: the r5 table is a TSV (ID, FILE, OLD, NEW, WHY; OLD and NEW Python string literals), vendored verbatim
    with open(os.path.join(RD, "mutants_r5.tsv"), encoding="utf-8") as fh:
        for ln in fh:
            if ln.startswith("#") or not ln.strip():
                continue
            mid, rel, old, new, _why = ln.rstrip("\n").split("\t", 4)
            out.append((mid, rel, ast.literal_eval(old), ast.literal_eval(new)))
    # round 7: the r6 reviewer's table, vendored verbatim; it is the whole own table of r6 with RW01-RW10 appended, so
    # only the RW rows are reviewer mutants (the O rows are tests/release/pvl_mutants.tsv and its retired table)
    with open(os.path.join(RD, "mutants_r6.tsv"), encoding="utf-8") as fh:
        for ln in fh:
            if not ln.startswith("RW"):
                continue
            mid, rel, old, new, _why = ln.rstrip("\n").split("\t", 4)
            out.append((mid, rel, ast.literal_eval(old), ast.literal_eval(new)))
    # round 8: the r7 reviewer's table, vendored verbatim (every row is a reviewer mutant)
    with open(os.path.join(RD, "mutants_r7.tsv"), encoding="utf-8") as fh:
        for ln in fh:
            if not ln.startswith("R7M"):
                continue
            mid, rel, old, new, _why = ln.rstrip("\n").split("\t", 4)
            out.append((mid, rel, ast.literal_eval(old), ast.literal_eval(new)))
    return out


def probes_r7(repo, work):
    """Round 8: the r7 reviewer's probes, verbatim (see the module docstring)."""
    if not shutil.which("pandoc"):
        print("REVIEWER probes_r7 SKIP pandoc not found")
        return 1
    py = [sys.executable, "-I"]
    env = dict(os.environ, TMPDIR=work)
    listed = {(r[0], r[1], r[2]): r[3] for r in load_tsv("changes_r7.tsv")}
    seen, rows, refused, unlisted, bad = set(), 0, 0, 0, 0
    for probe in ("bang", "near", "shapes"):
        wd = os.path.join(work, probe)
        os.makedirs(wd, exist_ok=True)
        p = subprocess.run(py + [os.path.join(RD, "probe_%s_r7.py.txt" % probe), repo, wd], capture_output=True,
                           text=True, env=env, timeout=600)
        if p.returncode != 0:
            bad += 1
            print("REV-R7-FAIL probe_%s rc=%d %s" % (probe, p.returncode, (p.stderr or p.stdout)[-200:]))
            continue
        for ln in p.stdout.splitlines():
            if probe == "bang":
                m = re.match(r"^(\S+) checker=(ACCEPT|REFUSE)\S* .*oracle_mdit=(True|False).*oracle_pandoc=(True|False)", ln)
                if not m:
                    continue
                name, acc, clean = m.group(1), m.group(2) == "ACCEPT", m.group(3) == m.group(4) == "True"
            elif probe == "near":
                m = re.match(r"^(.*?)\s+checker=(ACCEPT|REFUSE)\s+oracle_clean=(True|False)", ln)
                if not m:
                    continue
                name, acc, clean = m.group(1).strip(), m.group(2) == "ACCEPT", None
            else:
                m = re.match(r"^(\S+)\s+(ACCEPT|REFUSE)\s+(mdit=.*)$", ln)
                if not m:
                    continue
                name, acc, clean = m.group(1), m.group(2) == "ACCEPT", "DIRTY" not in m.group(3)
            rows += 1
            refused += not acc
            if probe == "near" and acc:
                bad += 1
                print("REV-R7-ACCEPTED near %s: a second label is accepted" % name)
                continue
            kind = "accepted-dirty" if acc and clean is False else "false-refusal" if not acc and clean else None
            if kind is None:
                continue
            key = (probe, name, kind)
            seen.add(key)
            if key in listed:
                print("REV-R7-LISTED %s %s %s: %s" % (probe, name, kind, listed[key]))
            else:
                unlisted += 1
                print("REV-R7-UNLISTED %s %s %s" % key)
    stale = [k for k in listed if k not in seen]
    for k in stale:
        print("REV-R7-STALE %s %s %s: listed but not seen" % k)
    ok = bad == 0 and unlisted == 0 and not stale and rows > 0
    print("REVIEWER probes_r7 rows=%d refused=%d listed=%d unlisted=%d stale=%d %s" % (
        rows, refused, len(seen) - unlisted, unlisted, len(stale), "PASS" if ok else "FAIL"))
    return 0 if ok else 1


def probes_r6(repo, work):
    """Round 7: the r6 reviewer's probes, verbatim. probe_r6 prints one line per body; a line marked DANGER (the
    checker accepts a body markdown-it does not show as the one line) is a FAIL. probe_hide prints `== <name>
    accept=<bool> ...` per hiding body; every one must be refused."""
    py = [sys.executable, "-I"]
    env = dict(os.environ, TMPDIR=work)
    os.makedirs(work, exist_ok=True)
    p = subprocess.run(py + [os.path.join(RD, "probe_r6.py.txt"), repo], capture_output=True, text=True, env=env,
                       timeout=600)
    rows = [ln for ln in p.stdout.splitlines() if " accept=" in ln]
    danger = [ln for ln in rows if " DANGER " in ln]
    for ln in danger:
        print("REV-R6-DANGER %s" % ln)
    q = subprocess.run(py + [os.path.join(RD, "probe_hide.py.txt"), repo], capture_output=True, text=True, env=env,
                       timeout=600)
    hide = [ln for ln in q.stdout.splitlines() if ln.startswith("== ")]
    hacc = [ln for ln in hide if " accept=True " in ln]
    for ln in hacc:
        print("REV-HIDE-ACCEPTED %s" % ln)
    ok = p.returncode == 0 and q.returncode == 0 and rows and len(hide) == 4 and not danger and not hacc
    print("REVIEWER probes_r6 rc=%d,%d bodies=%d danger=%d hide=%d hide_accepted=%d %s" % (
        p.returncode, q.returncode, len(rows), len(danger), len(hide), len(hacc), "PASS" if ok else "FAIL"))
    return 0 if ok else 1


def mutants(repo):
    cover = {r[0]: r[1] for r in load_tsv("mutants_map.tsv")}
    total = app = na = fail = 0
    for mid, rel, old, new in mutant_tables():
        total += 1
        path = os.path.join(repo, rel)
        src = open(path, encoding="utf-8").read() if os.path.isfile(path) else ""
        n = src.count(old)
        if n == 1 and not rel.startswith(OWN_PREFIXES):
            # a release-tooling mutant: the map names the suite that runs it, and that suite must name the id
            app += 1
            suite = cover.get(mid, "")
            ok = suite.startswith("OTHER-SUITE ") and os.path.isfile(os.path.join(repo, suite[12:])) and re.search(
                r"\b%s\b" % re.escape(mid), open(os.path.join(repo, suite[12:]), encoding="utf-8").read())
            if ok:
                print("REV-MUT %s APPLIES %s run-by %s" % (mid, rel, suite[12:]))
            else:
                fail += 1
                print("REV-MUT-FAIL %s applies to %s but no suite that names it is mapped" % (mid, rel))
        elif n == 1:
            app += 1
            print("REV-MUT %s APPLIES %s" % (mid, rel))
            print("REV-MUT-SPEC %s\t%s\t%r\t%r" % (mid, rel, old, new))
            if mid in cover:
                fail += 1
                print("REV-MUT-FAIL %s applies but has a not-applicable map row" % mid)
        else:
            na += 1
            if mid in cover:
                print("REV-MUT %s NOT-APPLICABLE %s (old text occurs %d times) covered-by %s" % (mid, rel, n, cover[mid]))
            else:
                fail += 1
                print("REV-MUT-FAIL %s NOT-APPLICABLE %s with no covering cases in mutants_map.tsv" % (mid, rel))
    print("REVIEWER mutants total=%d applies=%d not_applicable=%d fail=%d" % (total, app, na, fail))
    return 0 if fail == 0 else 1


def main(argv):
    bad = sums_ok()
    if bad:
        print("REVIEWER-BLIND a reviewer file differs from its recorded sum: %s" % ", ".join(bad))
        return 2
    if len(argv) >= 4 and argv[1] == "probes":
        rc = probes(os.path.abspath(argv[2]), argv[3], "--write-changes" in argv)
        rc = probes_r6(os.path.abspath(argv[2]), os.path.join(argv[3], "r6")) or rc
        return probes_r7(os.path.abspath(argv[2]), os.path.join(argv[3], "r7")) or rc
    if len(argv) == 3 and argv[1] == "mutants":
        return mutants(os.path.abspath(argv[2]))
    sys.stderr.write("usage: pvl_reviewer.py probes REPO WORKDIR [--write-changes] | mutants REPO\n")
    return 64


if __name__ == "__main__":
    sys.exit(main(sys.argv))
