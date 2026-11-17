#!/usr/bin/env python3
"""probe_replay.py -- re-run the round-4 reviewer's probes on the round-5 tools (tracker intake).

Evidence tool of docs/qa/tracker_intake_2026_11_12_v5/README.md. The round-4 review
(docs/qa/tracker_intake_2026_11_12_v5/sources/review_tracker_intake_r4.md) built its probe inputs
through the engine on database copies; this script takes those inputs as they are and runs the
round-5 remint_ids.py and intake_lint.py on them, so each finding is answered on the reviewer's own
data, not only on the suites' fixtures:
  p02, p03, p12  landings (plan, replay, verify, validate) from the probe's land/{V,B,T}.db
  p08            the planner on land/{V,B,T}.db, whose vehicle holds own ids in non-ASCII digits
  p04            rewrite (dry run) of the seven range and id forms with the committed fix227 map
  p06            the seven lint coverage cases (each X.db with its docs/)
  p11            lv4 (a non-item heading in the rendered Issues.md) and lv6 (an item with two rows)
Every input is copied into a temporary directory first; the reviewer's files are only read (their
sha256 are printed). A copied database whose -wal sidecar is not empty is checkpointed by the
engine's own `validate` (it opens the copy and checkpoints on close), never by a raw write.

USAGE  python3 -I probe_replay.py --wi BIN --probes DIR --map MAP.tsv [--repo-root .]
       --probes  the review's probes/ directory; --map  the fix227 id map (remint/fix227/map.tsv)
OUTPUT one block per probe with the commands' RESULT lines, the values that decide the finding, and a
       line `PROBE <name>: <verdict>` where the verdict says whether the round-5 tool now answers it.
EXIT   0 every probe ran and every verdict is ANSWERED; 1 a verdict is OPEN; 3 an input is missing.
EVIDENCE CLASS  gate-logic only (section 11.4.289): host-fixture runs on database copies.
"""
import argparse
import hashlib
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import urllib.parse

REMINT = "scripts/workable-items/remint_ids.py"
LINT = "scripts/workable-items/intake_lint.py"
INTAKE = ",".join("CON-%03d" % i for i in range(299, 343))


def sha(p):
    with open(p, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def run(cmd, root):
    p = subprocess.run(cmd, cwd=root, capture_output=True, text=True)
    return p.returncode, p.stdout + p.stderr


def q(db, sql, *args):
    c = sqlite3.connect("file:%s?mode=ro" % urllib.parse.quote(os.path.abspath(db)), uri=True)
    try:
        r = c.execute(sql, args).fetchone()
    finally:
        c.close()
    return r


def copy_db(src, dst, wi, root, out):
    """copy a database (and its -wal when not empty); checkpoint the copy through the engine"""
    shutil.copy(src, dst)
    wal = src + "-wal"
    if os.path.isfile(wal) and os.path.getsize(wal) > 0:
        shutil.copy(wal, dst + "-wal")
        rc, o = run([wi, "validate", "--db", dst], root)
        left = os.path.getsize(dst + "-wal") if os.path.isfile(dst + "-wal") else 0
        out.append("  checkpoint %s through `validate`: rc=%d, -wal now %d bytes" % (os.path.basename(src), rc, left))
    os.chmod(dst, 0o644)


def result_lines(text, n=3):
    return [x for x in text.splitlines() if x.startswith(("RESULT", "REFUSED", "CONFLICT", "MERGE", "MISMATCH", "BLIND"))][:n]


def landing(name, probes, wi, root, tmp, out):
    d = os.path.join(probes, name, "land")
    for k in ("V", "B", "T"):
        if not os.path.isfile(os.path.join(d, k + ".db")):
            raise SystemExit("missing input: %s/%s.db" % (d, k))
    w = os.path.join(tmp, name)
    os.makedirs(w)
    dbs = {}
    for k in ("V", "B", "T"):
        out.append("  input %s.db sha256 %s" % (k, sha(os.path.join(d, k + ".db"))))
        dbs[k] = os.path.join(w, k + ".db")
        copy_db(os.path.join(d, k + ".db"), dbs[k], wi, root, out)
    plan = os.path.join(w, "plan.json")
    rc, o = run([sys.executable, "-I", REMINT, "plan", "--vehicle-db", dbs["V"], "--base-db", dbs["B"], "--target-db",
                 dbs["T"], "--out", plan, "--prefix", "CON", "--repo-root", "."], root)
    out.append("  plan rc=%d" % rc)
    out += ["    " + x for x in result_lines(o, 6)]
    if rc != 0:
        return rc, None
    landed = os.path.join(w, "L.db")
    shutil.copy(dbs["T"], landed)
    rc2, o2 = run([sys.executable, "-I", REMINT, "replay", "--plan", plan, "--apply", "--engine", wi, "--db", landed], root)
    out.append("  replay rc=%d %s" % (rc2, " | ".join(result_lines(o2, 1))))
    rc3, o3 = run([sys.executable, "-I", REMINT, "verify", "--plan", plan, "--vehicle-db", dbs["V"], "--base-db", dbs["B"],
                   "--target-db", dbs["T"], "--db", landed], root)
    out.append("  verify rc=%d %s" % (rc3, " | ".join(result_lines(o3, 2))))
    rc4, o4 = run([wi, "validate", "--db", landed], root)
    # validate runs in the vehicle tree, where the target's own evidence paths do not exist; a failure
    # whose every line is such an unresolved path is a property of the tree, not of the landing (the
    # round-4 review saw the same, section 4); any other failure line counts
    fails = [x.strip() for x in o4.splitlines() if x.startswith("  - ")]
    other = [x for x in fails if "does not resolve" not in x]
    out.append("  validate rc=%d: %d failure lines, %d of them an evidence path that does not resolve in this tree; "
               "other: %s" % (rc4, len(fails), len(fails) - len(other), " | ".join(x[:160] for x in other) or "none"))
    return (rc, rc2, rc3, 0 if rc4 == 0 or (fails and not other) else rc4), landed


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--wi", required=True)
    ap.add_argument("--probes", required=True)
    ap.add_argument("--map", required=True)
    ap.add_argument("--repo-root", default=".")
    a = ap.parse_args()
    root = os.path.abspath(a.repo_root)
    wi = os.path.abspath(a.wi)
    probes = os.path.abspath(a.probes)
    if not os.path.isdir(probes) or not os.path.isfile(a.map):
        print("missing input: --probes or --map", file=sys.stderr)
        return 3
    verdicts = []
    out = []
    with tempfile.TemporaryDirectory(prefix="probe_replay.") as tmp:
        # p02 (R4-1a): the target's new text must reach the landing as written
        out.append("== p02_target_desc_rewrite (R4-1 member a)")
        rcs, landed = landing("p02_target_desc_rewrite", probes, wi, root, tmp, out)
        ok = False
        if landed:
            d = q(landed, "select description from items where atm_id='CON-100'")[0]
            t = q(os.path.join(tmp, "p02_target_desc_rewrite", "T.db"), "select description from items where atm_id='CON-100'")[0]
            out.append("  landed CON-100 description equals the target's: %s" % (d == t))
            out.append("  landed CON-100 description names CON-305: %s; names CON-318: %s" % ("CON-305" in d, "CON-318" in d))
            ok = rcs == (0, 0, 0, 0) and d == t and "CON-318" not in d
        verdicts.append(("p02", ok))
        # p03 (R4-1b): one state block changed on both sides is a conflict
        out.append("== p03_block_disjoint_columns (R4-1 member b)")
        rcs, landed = landing("p03_block_disjoint_columns", probes, wi, root, tmp, out)
        log = "\n".join(out)
        verdicts.append(("p03", rcs == 1 and "CONFLICT CON-085: both changed the reproduction block" in log))
        # p12 (RV7a): a vehicle lifecycle change and a target change of the same item is a conflict
        out.append("== p12_rv7a_lifecycle_conflict (RV7a)")
        rcs, landed = landing("p12_rv7a_lifecycle_conflict", probes, wi, root, tmp, out)
        log = "\n".join(out)
        verdicts.append(("p12", rcs == 1 and "CONFLICT CON-243" in log))
        # p08 (R4-5): an own id written in non-ASCII digits must be refused by name, not mapped
        out.append("== p08_unicode_ids (R4-5)")
        mark = len(out)
        rcs, landed = landing("p08_unicode_ids", probes, wi, root, tmp, out)
        log = "\n".join(out[mark:])
        verdicts.append(("p08", rcs not in (0, (0, 0, 0, 0)) and landed is None and "non-ASCII" in log))
        # p04 (R4-4, R4-5): every range form and the non-ASCII id, on the fix227 map
        out.append("== p04_worded_ranges (R4-4, R4-5)")
        want = {"a": "REFUSED", "b": "REFUSED", "c": "REFUSED", "d": "REFUSED", "e": "replaced=2", "f": "replaced=0",
                "g": "REFUSED"}
        good = True
        for k in sorted(want):
            src = os.path.join(probes, "p04_worded_ranges", "t_%s.md" % k)
            dst = os.path.join(tmp, "t_%s.md" % k)
            shutil.copy(src, dst)
            rc, o = run([sys.executable, "-I", REMINT, "rewrite", "--map", os.path.abspath(a.map), dst], root)
            line = (result_lines(o, 1) or [o.strip()[-160:]])[0].replace(tmp + "/", "")
            hit = want[k] in o
            good = good and hit
            out.append("  %s: %s | rc=%d %s (want %s)" % (k, open(src, encoding="utf-8").read().strip(), rc, line[:200], want[k]))
        verdicts.append(("p04", good))
        # p06 (R4-3): each case must give a finding of its code
        out.append("== p06_lint_coverage_gaps (R4-3)")
        want6 = {"basic_auth": "SECRET", "bidi_override": "CONTROL-CHAR", "bom_softhyphen": "CONTROL-CHAR",
                 "control_bel": "CONTROL-CHAR", "quoted_password": "SECRET", "unquoted_password": "SECRET",
                 "zwsp_in_id": "CONTROL-CHAR"}
        good = True
        for k in sorted(want6):
            src = os.path.join(probes, "p06_lint_coverage_gaps", k)
            w = os.path.join(tmp, "p06_" + k)
            os.makedirs(w)
            db = os.path.join(w, "X.db")
            copy_db(os.path.join(src, "X.db"), db, wi, root, out)
            shutil.copytree(os.path.join(src, "docs"), os.path.join(w, "docs"))
            rc, o = run([sys.executable, "-I", LINT, "--db", db, "--ids", INTAKE, "--prefix", "CON", "--require-dup-check",
                         "--repo-root", ".", "--rendered", os.path.join(w, "docs")], root)
            f = [x for x in o.splitlines() if x.startswith("FINDING")]
            hit = any(x.split()[1] == want6[k] for x in f)
            good = good and rc == 1 and hit
            out.append("  %s: rc=%d findings=%d %s (want %s)" % (k, rc, len(f), " | ".join(x[:120] for x in f[:2]), want6[k]))
        verdicts.append(("p06", good))
        # p11 (R4-6): lv4 must stay silent (the non-item heading is not the item's); lv6 must see the second row
        out.append("== p11_lint_survivors (R4-6)")
        src = os.path.join(probes, "p11_lint_survivors")
        w = os.path.join(tmp, "p11")
        os.makedirs(w)
        db = os.path.join(w, "X.db")
        copy_db(os.path.join(src, "lv4", "X.db"), db, wi, root, out)
        shutil.copytree(os.path.join(src, "lv4", "docs"), os.path.join(w, "docs"))
        rc4, o = run([sys.executable, "-I", LINT, "--db", db, "--ids", INTAKE, "--prefix", "CON", "--rendered",
                      os.path.join(w, "docs")], root)
        out.append("  lv4: rc=%d %s" % (rc4, " | ".join(x[:140] for x in o.splitlines() if x.startswith(("FINDING", "RESULT")))[:400]))
        db6 = os.path.join(w, "X6.db")
        copy_db(os.path.join(src, "lv6", "X6.db"), db6, wi, root, out)
        rows = q(db6, "select count(*) from items where atm_id='CON-300'")[0]
        rc6, o = run([sys.executable, "-I", LINT, "--db", db6, "--ids", INTAKE, "--prefix", "CON", "--no-rendered"], root)
        f6 = [x for x in o.splitlines() if x.startswith("FINDING") and "CON-300" in x]
        out.append("  lv6: CON-300 rows in items=%d; lint rc=%d; CON-300 findings: %s" % (rows, rc6, " | ".join(x[:160] for x in f6)))
        verdicts.append(("p11", rc4 == 0 and rows == 2 and rc6 == 1 and any("home-path" in x and "row]" in x for x in f6)))
    for line in out:
        print(line)
    for name, v in verdicts:
        print("PROBE %s: %s" % (name, "ANSWERED" if v else "OPEN"))
    bad = [n for n, v in verdicts if not v]
    print("RESULT: probes=%d answered=%d open=%d" % (len(verdicts), len(verdicts) - len(bad), len(bad)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
