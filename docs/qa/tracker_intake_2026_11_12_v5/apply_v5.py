#!/usr/bin/env python3
# docs/qa/tracker_intake_2026_11_12_v5/apply_v5.py -- one-shot data change of the tracker-intake
# vehicle, round 5: answers the round-4 review finding R4-8 for the whole class.
#
#   R4-8  the red commands of the six engine-gap items (CON-336, CON-337, CON-339..CON-342) named
#         engine_repro.sh without the conditions it needs: the engine mints the id of the F2 item from
#         HELIX_RELEASE_PREFIX, and the F1/F4 lines print the item Type, so <open> and <probe> must be
#         items of Type Task. The round-5 script checks each condition and exits 3 when one fails
#         (tests: engine_repro_check.sh beside this file). Each item's red command, evidence and env
#         now name the round-5 script and capture with these conditions, and its description gains one
#         sentence citing the round-5 capture. The round-3 and round-4 captures stay cited as history.
#
# Every change goes through the workable-items engine (`update`); nothing writes the SQLite file
# directly. The script refuses to run unless the database holds the exact texts it was written against
# (the round-4 sentence occurs exactly once, the round-5 sentence not at all) and the evidence file has
# the sha256 written below, so a second run changes nothing and exits 1.
#
# Usage: python3 -I apply_v5.py --wi <workable-items binary> --db docs/workable_items.db [--dry-run]
# Run from the repository root. Exit: 0 applied; 1 precondition failed (nothing written); 2 usage;
# 3 an engine call failed (the calls before it stay applied; the log names the failed call).
# Evidence class: gate-logic only (section 11.4.289); it records tracker text, it proves no defect.
import argparse
import hashlib
import os
import sqlite3
import subprocess
import sys
import urllib.parse

D4 = "docs/qa/tracker_intake_2026_11_12_v4"
D5 = "docs/qa/tracker_intake_2026_11_12_v5"
EVIDENCE = D5 + "/engine_repro.txt"
EVIDENCE_SHA = "e065b1d657a46386aee4d6bd79ed20e565c18749eeca88f2480e0031225c48c7"
WHO = "Claude (tracker-intake round-5 fixer, Opus 5.5)"
KEEP = "the item ids print as placeholders, so the capture stays true after a re-mint"
RED = ("HELIX_RELEASE_PREFIX=CON bash " + D5 + "/engine_repro.sh <workable-items binary> "
       "<scratch copy of docs/workable_items.db> <open item id: an open item of Type Task> "
       "<obsolete item id: an Obsolete item with an obsolete_details row> "
       "<probe item id: another open item of Type Task> (sections %s)")
ENV = ("scratch copy of docs/workable_items.db at b48091ea; engine built from that tree (its source is unchanged "
       "in round 5); HELIX_RELEASE_PREFIX=CON (the engine mints the F2 item's id from it); <open> and <probe> open "
       "items of Type Task (the F1 and F4 lines print the Type); <obsolete> an Obsolete item with an "
       "obsolete_details row; the script checks each condition and exits 3 when one fails; evidence sha256 "
       + EVIDENCE_SHA)
# id -> (sections named in the description, red-command sections)
ITEMS = {
    "CON-336": ("sections F2 and F3", "F2, F3"),
    "CON-337": ("sections F1 and F2 (control F4)", "F1, F2, F4"),
    "CON-339": ("section G1", "G1"),
    "CON-340": ("sections G2 and G3", "G2, G3"),
    "CON-341": ("section G3", "G3"),
    "CON-342": ("section G4", "G4"),
}


def sentence(secs):
    return (" Reproduced again at b48091ea with the script's conditions checked (HELIX_RELEASE_PREFIX set to the "
            "id prefix; <open> and <probe> of Type Task): " + EVIDENCE + " " + secs + " (" + KEEP + ").")


def new_description(desc, secs):
    """the description with the round-5 sentence after the round-4 one, or None with a reason"""
    if desc.count(D4 + "/engine_repro.txt") != 1:
        return None, "the round-4 capture is cited %d times" % desc.count(D4 + "/engine_repro.txt")
    if EVIDENCE in desc:
        return None, "the round-5 capture is already cited (already applied?)"
    start = desc.index(D4 + "/engine_repro.txt")
    end_mark = KEEP + ")."
    end = desc.find(end_mark, start)
    if end < 0:
        return None, "the round-4 sentence does not end with the placeholder note"
    cut = end + len(end_mark)
    return desc[:cut] + sentence(secs) + desc[cut:], ""


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--wi", required=True)
    ap.add_argument("--db", required=True)
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args(argv)
    try:
        with open(EVIDENCE, "rb") as f:
            got = hashlib.sha256(f.read()).hexdigest()
    except OSError as e:
        print("precondition: evidence file not readable from here (%s); run from the repository root" % e)
        return 1
    if got != EVIDENCE_SHA:
        print("precondition: %s sha256 %s, expected %s" % (EVIDENCE, got, EVIDENCE_SHA))
        return 1
    if os.path.exists(a.db + "-wal") and os.path.getsize(a.db + "-wal") > 0:
        print("precondition: %s-wal is not empty; a read-only reader would miss its pages" % a.db)
        return 1
    con = sqlite3.connect("file:%s?mode=ro" % urllib.parse.quote(os.path.abspath(a.db)), uri=True)
    plan = []
    for iid, (secs, red_secs) in ITEMS.items():
        rows = con.execute("select description, reproduction_state, reproduction_red_cmd, type from items "
                           "where atm_id=?", (iid,)).fetchall()
        if len(rows) != 1:
            print("precondition: %s has %d rows" % (iid, len(rows)))
            return 1
        desc, state, red, typ = rows[0]
        if state != "reproduced-host-fixture" or typ != "Bug" or D4 + "/engine_repro.sh" not in (red or ""):
            print("precondition: %s state %s, type %s, red command %r" % (iid, state, typ, (red or "")[:80]))
            return 1
        nd, why = new_description(desc, secs)
        if nd is None:
            print("precondition: %s: %s" % (iid, why))
            return 1
        plan.append((iid, nd, red_secs))
    con.close()
    for iid, desc, red_secs in plan:
        cmd = [a.wi, "update", "--db", a.db, "--id", iid, "--description", desc,
               "--reproduction-evidence", EVIDENCE, "--reproduction-red-cmd", RED % red_secs,
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
