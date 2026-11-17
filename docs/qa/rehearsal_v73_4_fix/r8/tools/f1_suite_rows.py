#!/usr/bin/env python3
"""f1_suite_rows.py -- CON-PENDINGpvl8 r8: the review r7 F1 rows added to suite step P2, run through one checker.

Usage: python3 -I docs/qa/rehearsal_v73_4_fix/r8/tools/f1_suite_rows.py REPO CHECKER WORKDIR

The same command runs on the r7 checker (RED) and on the r8 checker (GREEN). It builds a fixture database with:
  CON-016  the clean body (control: accepted by both)
  CON-022  a complete comment before the line (r7 accepted it; r8 refuses every comment)
  CON-023  `<!-- a --!><div hidden>` then `-->`: CommonMark ends the comment at `-->`, an HTML5 reader ends it at
           `--!>`, so the `<div hidden>` is live markup and hides the line (review r7 F1)
and prints the checker's FAIL and CHECKED lines, then `F1ROWS accepted=<ids> refused=<ids>`.
Evidence class: gate-logic (section 11.4.289(C)(2)).
"""
import os
import sqlite3
import subprocess
import sys


def main(argv):
    if len(argv) != 4:
        sys.stderr.write("usage: f1_suite_rows.py REPO CHECKER WORKDIR\n")
        return 64
    repo, ck, work = (os.path.abspath(a) for a in argv[1:])
    sys.path.insert(0, os.path.join(repo, "tests/release"))
    import pvl_fixture as F
    os.makedirs(work, exist_ok=True)
    root = F.make_root(os.path.join(work, "fx"))["root"]
    good = F.line()
    rows = [("CON-016", "x\n\n" + good), ("CON-022", "x\n\n<!-- a note -->\n\n" + good),
            ("CON-023", "<!-- a --!><div hidden>\n-->\n\n" + good)]
    db = os.path.join(work, "f1.db")
    if os.path.exists(db):
        os.remove(db)
    con = sqlite3.connect(db)
    con.execute("create table items (atm_id text primary key, status text, body_md text, created_at text)")
    for i, b in rows:
        con.execute("insert into items values (?, ?, ?, ?)", (i, "Ready for testing", b, "2026-11-01"))
    con.commit()
    con.close()
    p = subprocess.run([sys.executable, "-I", ck, "--root", root, "--today", "2026-11-16", db], capture_output=True,
                       text=True, timeout=120)
    out = p.stdout.splitlines()
    for ln in out:
        if ln.startswith(("FAIL ", "CHECKED ", "VERDICT", "BLIND")):
            print(ln[:220])
    refused = [i for i, _ in rows if any(ln.startswith("FAIL %s " % i) for ln in out)]
    accepted = [i for i, _ in rows if i not in refused]
    print("F1ROWS rc=%d accepted=%s refused=%s" % (p.returncode, ",".join(accepted) or "-", ",".join(refused) or "-"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
