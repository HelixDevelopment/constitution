#!/usr/bin/env python3
"""r7m08_hotjournal.py -- CON-PENDINGpvl8 r8: show that the hot-journal case of api_r8 kills reviewer mutant R7M08
by itself, without the FIFO case (review r7 F7 said R7M08 was killed only through the FIFO -journal).

Usage: python3 -I docs/qa/rehearsal_v73_4_fix/r8/tools/r7m08_hotjournal.py REPO WORKDIR

The case is the one in tests/release/pvl_mutate.py api_r8 ("a hot rollback journal is copied with the database"):
a rollback-journal database with an open write transaction whose pages already spilled into the database file.
The checker copies the database together with its -journal, so SQLite rolls the copy back and sees the committed
rows only (`CHECKED items=400 provisional_status=0 ok=0 fail=0`). R7M08 drops "-journal" from DB_SUFFIXES, so the
copy is the half-written database file without its journal; any result other than the expected line is a kill
(on this host, 2026-11-17, the mutant reported `BLIND the database cannot be read (DatabaseError)`).

Output: `HOTJOURNAL checker=<line>` and `HOTJOURNAL R7M08=<line>`, then `HOTJOURNAL-KILLS-R7M08` when the checker
gives the expected line and the mutant does not (exit 0), else `HOTJOURNAL-NO-KILL` (exit 1). A control (section
11.4.273): the database file alone must hold spilled rows, else the case cannot tell and the run exits 2.
Evidence class: gate-logic (section 11.4.289(C)(2)).
"""
import os
import shutil
import sqlite3
import subprocess
import sys

REL = "scripts/validation/check_provisional_verification_lines.py"
OLD = 'DB_SUFFIXES = ("", "-wal", "-journal")\n'
NEW = 'DB_SUFFIXES = ("", "-wal")\n'
WANT = "CHECKED items=400 provisional_status=0 ok=0 fail=0"


def checked(ck, db):
    p = subprocess.run([sys.executable, "-I", ck, "--today", "2026-11-17", "--root", os.path.dirname(db), db],
                       capture_output=True, text=True, timeout=120)
    lines = [ln for ln in p.stdout.splitlines() if ln.startswith("CHECKED ")]
    if lines:
        return lines[0]
    other = [ln for ln in (p.stdout + p.stderr).splitlines() if ln.strip()]
    return "rc=%d no CHECKED line; first output line: %s" % (p.returncode, other[0][:200] if other else "(none)")


def main(argv):
    if len(argv) != 3:
        sys.stderr.write("usage: r7m08_hotjournal.py REPO WORKDIR\n")
        return 64
    repo, work = os.path.abspath(argv[1]), os.path.abspath(argv[2])
    os.makedirs(work, exist_ok=True)
    src = open(os.path.join(repo, REL), encoding="utf-8").read()
    if src.count(OLD) != 1:
        print("HOTJOURNAL-NOT-APPLIED old text occurs %d times" % src.count(OLD))
        return 2
    cks = {}
    for name, text in (("checker", src), ("R7M08", src.replace(OLD, NEW, 1))):
        d = os.path.join(work, name, "scripts/validation")
        os.makedirs(d, exist_ok=True)
        for f in os.listdir(os.path.join(repo, "scripts/validation")):
            if f.startswith("pvl_") and f.endswith(".py"):
                shutil.copyfile(os.path.join(repo, "scripts/validation", f), os.path.join(d, f))
        p = os.path.join(d, os.path.basename(REL))
        with open(p, "w", encoding="utf-8") as fh:
            fh.write(text)
        cks[name] = p
    hj = os.path.join(work, "hj", "items.db")
    os.makedirs(os.path.dirname(hj), exist_ok=True)
    for suf in ("", "-journal"):
        if os.path.lexists(hj + suf):
            os.remove(hj + suf)
    ch = sqlite3.connect(hj, isolation_level=None)
    ch.execute("pragma journal_mode=delete")
    ch.execute("create table items (atm_id text primary key, status text, body_md text, created_at text)")
    ch.execute("begin")
    for k in range(400):
        ch.execute("insert into items values (?,?,?,?)", ("CON-%d" % (6000 + k), "Queued", "z" * 300, "2026-11-01"))
    ch.execute("commit")
    ch.execute("pragma cache_size=1")
    ch.execute("begin")
    ch.execute("update items set status='Ready for testing' where atm_id != 'CON-6000'")
    try:
        alone = os.path.join(work, "hj_alone.db")
        shutil.copyfile(hj, alone)
        ca = sqlite3.connect(alone)
        try:
            spilled = ca.execute("select count(*) from items where status='Ready for testing'").fetchone()[0]
        finally:
            ca.close()
            os.remove(alone)
        print("HOTJOURNAL control journal=%s spilled_rows=%d" % (os.path.exists(hj + "-journal"), spilled))
        if not spilled or not os.path.exists(hj + "-journal"):
            print("HOTJOURNAL-BLIND the database file alone holds no spilled row")
            return 2
        got = {name: checked(ck, hj) for name, ck in cks.items()}
    finally:
        ch.execute("rollback")
        ch.close()
    for name in ("checker", "R7M08"):
        print("HOTJOURNAL %s=%s" % (name, got[name]))
    if got["checker"] == WANT and got["R7M08"] != WANT:
        print("HOTJOURNAL-KILLS-R7M08")
        return 0
    print("HOTJOURNAL-NO-KILL")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
