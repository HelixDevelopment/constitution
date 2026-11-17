#!/usr/bin/env python3
# docs/qa/tracker_intake_2026_11_12_v4/apply_v4.py -- one-shot data change of the tracker-intake
# vehicle, round 4: answers the round-3 review findings M-8 and M-9 for the whole class.
#
#   M-9  CON-336 and CON-337 cited docs/qa/tracker_intake_2026_11_12_v2/engine_repro.sh, which hard-codes
#        an item id. They now cite the round-4 script, which takes every id as an argument and prints it
#        as a placeholder, and its capture engine_repro.txt (sections F1-F4).
#   M-8  every reproduced-* state of the batch carries the sha256 of its evidence file in
#        reproduction_env (section 11.4.294(C)); CON-339..CON-342 did not. They now cite the round-4
#        capture (sections G1-G4) with its sha256. The round-3 capture stays cited as history.
#
# Every change goes through the workable-items engine (`update`); nothing writes the SQLite file
# directly. The script refuses to run unless the database holds the exact texts it was written against
# (each replaced text occurs exactly once) and the evidence file has the sha256 written below, so a
# second run changes nothing and exits 1.
#
# Usage: python3 -I apply_v4.py --wi <workable-items binary> --db docs/workable_items.db [--dry-run]
# Run from the repository root. Exit: 0 applied; 1 precondition failed (nothing written); 2 usage;
# 3 an engine call failed (the calls before it stay applied; the log names the failed call).
# Evidence class: gate-logic only (section 11.4.289); it records tracker text, it proves no defect.
import argparse
import hashlib
import sqlite3
import subprocess
import sys

D4 = "docs/qa/tracker_intake_2026_11_12_v4"
EVIDENCE = D4 + "/engine_repro.txt"
EVIDENCE_SHA = "42f2f3236114fbdbe93366db81a1fcaf1c7802b07c956a59b298af816cffaa72"
WHO = "Claude (tracker-intake round-4 fixer, Opus 5.5)"
RED = ("bash " + D4 + "/engine_repro.sh <workable-items binary> <scratch copy of docs/workable_items.db> "
       "<open item id> <obsolete item id> <probe item id> (sections %s)")
ENV = ("scratch copy of docs/workable_items.db at 53b6d9ed; engine built from that tree; evidence sha256 "
       + EVIDENCE_SHA)
KEEP = "the item ids print as placeholders, so the capture stays true after a re-mint"

OLD_336 = (
    "Reproduced on the host against a scratch copy of the vehicle database: "
    "docs/qa/tracker_intake_2026_11_12_v2/engine_failopen_repro.txt (section I9; script engine_repro.sh in the same "
    "directory). ")
NEW_336 = (
    "Reproduced on the host against a scratch copy of the vehicle database, every write through the engine: "
    + EVIDENCE + " sections F2 and F3 (script engine_repro.sh in the same directory; " + KEEP + "). The first "
    "capture, docs/qa/tracker_intake_2026_11_12_v2/engine_failopen_repro.txt (section I9), is kept as history; "
    "its script hard-codes an item id and is no longer the reproduction command. ")
OLD_337 = (
    "docs/qa/tracker_intake_2026_11_12_v2/engine_failopen_repro.txt, sections M4 and M5 (control: 'In progress' is "
    "accepted and changes the row; script engine_repro.sh in the same directory).")
NEW_337 = (
    EVIDENCE + ", sections F1 and F2 (control F4: 'In progress' is accepted and changes the row; script "
    "engine_repro.sh in the same directory; " + KEEP + "). The first capture, "
    "docs/qa/tracker_intake_2026_11_12_v2/engine_failopen_repro.txt (sections M4 and M5), is kept as history; its "
    "script hard-codes an item id and is no longer the reproduction command.")


def g_old(sec):
    return "docs/qa/tracker_intake_2026_11_12_v3/engine_repro.txt section %s (script engine_repro.sh in the same " \
           "directory, checksums in its SHA256SUMS)." % sec


def g_new(sec):
    return g_old(sec) + " Reproduced again at 53b6d9ed: " + EVIDENCE + " section " + sec + " (" + KEEP + ")."


# id -> (old text, new text, red-command sections)
CHANGES = {
    "CON-336": (OLD_336, NEW_336, "F2, F3"),
    "CON-337": (OLD_337, NEW_337, "F1, F2, F4"),
    "CON-339": (g_old("G1"), g_new("G1"), "G1"),
    "CON-340": (g_old("G2 and G3"), g_new("G2 and G3"), "G2, G3"),
    "CON-341": (g_old("G3"), g_new("G3"), "G3"),
    "CON-342": (g_old("G4"), g_new("G4"), "G4"),
}


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--wi", required=True)
    ap.add_argument("--db", required=True)
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args(argv)
    h = hashlib.sha256()
    try:
        with open(EVIDENCE, "rb") as f:
            h.update(f.read())
    except OSError as e:
        print("precondition: evidence file not readable from here (%s); run from the repository root" % e)
        return 1
    if h.hexdigest() != EVIDENCE_SHA:
        print("precondition: %s sha256 %s, expected %s" % (EVIDENCE, h.hexdigest(), EVIDENCE_SHA))
        return 1
    con = sqlite3.connect("file:%s?mode=ro" % a.db, uri=True)
    plan = []
    for iid, (old, new, secs) in CHANGES.items():
        rows = con.execute("select description, reproduction_state from items where atm_id=?", (iid,)).fetchall()
        if len(rows) != 1:
            print("precondition: %s has %d rows" % (iid, len(rows)))
            return 1
        desc, state = rows[0]
        if desc.count(old) != 1 or state != "reproduced-host-fixture":
            print("precondition: %s text occurs %d times, state %s (already applied?)" % (iid, desc.count(old), state))
            return 1
        plan.append((iid, desc.replace(old, new), secs))
    con.close()
    for iid, desc, secs in plan:
        cmd = [a.wi, "update", "--db", a.db, "--id", iid, "--description", desc,
               "--reproduction-evidence", EVIDENCE, "--reproduction-red-cmd", RED % secs,
               "--reproduction-env", ENV, "--states-updated-by", WHO]
        shown = " ".join("'<%d chars>'" % len(x) if len(x) > 80 else "'%s'" % x for x in cmd[1:])
        print("$ <wi> %s" % shown)
        if a.dry_run:
            continue
        p = subprocess.run(cmd, capture_output=True, text=True)
        for line in (p.stdout + p.stderr).splitlines():
            print("  | " + line)
        print("  rc=%d" % p.returncode)
        if p.returncode != 0:
            print("engine call failed for %s" % iid)
            return 3
    print("RESULT: %s items=%d" % ("DRY-RUN" if a.dry_run else "APPLIED", len(plan)))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
