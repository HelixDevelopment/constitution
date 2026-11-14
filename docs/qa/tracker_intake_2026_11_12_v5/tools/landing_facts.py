#!/usr/bin/env python3
"""landing_facts.py -- the round-3 review's landing facts, asserted on a landed database.

RED/GREEN harness of the round-4 structural item (CON-PENDING-TRACKER-INTAKE); docs/qa/tracker_intake_2026_11_12_v4/README.md; round-5 copy in docs/qa/tracker_intake_2026_11_12_v5, its database path quoted
(R4-9). It reads three
read-only databases and checks the concrete facts the round-3 review measured (R3-1, R3-2). It
does not use remint_ids.py (no producer code), so the same check judges the round-3 landing (RED)
and the round-4 landing (GREEN).

USAGE  landing_facts.py --vehicle-db V --landed-db R --map map.tsv
EXIT   0 every fact holds; 1 a fact fails; 3 an input cannot be read.
"""
import argparse
import os
import sqlite3
import sys
import urllib.parse


def ro(p):
    c = sqlite3.connect("file:%s?mode=ro" % urllib.parse.quote(os.path.abspath(p)), uri=True)
    c.row_factory = sqlite3.Row
    c.execute("select count(*) from items").fetchone()
    return c


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--vehicle-db", required=True)
    ap.add_argument("--landed-db", required=True)
    ap.add_argument("--map", required=True)
    a = ap.parse_args(argv)
    try:
        v, r = ro(a.vehicle_db), ro(a.landed_db)
        lines = open(a.map, encoding="utf-8").read().splitlines()
    except (OSError, sqlite3.Error) as e:
        print("BLIND: %s" % e)
        return 3
    m = dict(x.split("\t") for x in lines[1:] if x)

    def row(c, i):
        g = c.execute("select * from items where atm_id=?", (i,)).fetchall()
        return g[0] if len(g) == 1 else None

    def od(c, i):
        return c.execute("select reason, superseding_item from obsolete_details where atm_id=?", (i,)).fetchone()

    vrow = {}
    for i in ("CON-243", "CON-262", "CON-046"):
        got = row(v, i)
        if got is None:  # the facts are about these vehicle items: without one the harness cannot judge
            print("BLIND: the vehicle database has no single row for %s" % i)
            return 3
        vrow[i] = got
    vo = od(v, "CON-243")
    if vo is None:
        print("BLIND: the vehicle database has no obsolete_details row for CON-243")
        return 3

    fails = []

    def fact(name, ok, detail):
        print("%s %s: %s" % ("HOLDS" if ok else "FAILS", name, detail))
        if not ok:
            fails.append(name)

    v243, r243 = vrow["CON-243"], row(r, "CON-243")
    fact("R3-1a CON-243 closed as in the vehicle",
         r243 is not None and r243["status"] == v243["status"] and r243["current_location"] == v243["current_location"],
         "vehicle %r/%r, landed %r/%r" % (v243["status"], v243["current_location"],
                                          r243["status"] if r243 else None, r243["current_location"] if r243 else None))
    ro_ = od(r, "CON-243")
    fact("R3-1b CON-243 obsolete_details duplicate-of CON-262",
         ro_ is not None and tuple(ro_) == tuple(vo), "vehicle %r, landed %r" % (tuple(vo), tuple(ro_) if ro_ else None))
    v262, r262 = vrow["CON-262"], row(r, "CON-262")
    fact("R3-1c CON-262 carries the vehicle's description",
         r262 is not None and len(r262["description"]) == len(v262["description"]),
         "vehicle %d characters, landed %d" % (len(v262["description"]), len(r262["description"]) if r262 else -1))
    v046, r046 = vrow["CON-046"], row(r, "CON-046")
    fact("R3-1d CON-046 carries the vehicle's description and reproduction state",
         r046 is not None and len(r046["description"]) == len(v046["description"])
         and r046["reproduction_state"] == v046["reproduction_state"],
         "vehicle %d characters %s, landed %d characters %s" % (
             len(v046["description"]), v046["reproduction_state"],
             len(r046["description"]) if r046 else -1, r046["reproduction_state"] if r046 else None))
    new330 = m.get("CON-330")
    r330 = row(r, new330) if new330 else None
    t = r330["title"] if r330 is not None else ""
    fact("R3-2 the landed CON-330 title still names fix227's CON-310",
         "fix227 CON-310 amendment" in t, "landed %s title: %r" % (new330, t[:60]))
    print("RESULT: %s facts=%d failed=%d" % ("PASS" if not fails else "FAIL", 5, len(fails)))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
