#!/usr/bin/env python3
"""docs/qa/tracker_intake_2026_11_12_v5/tools/ref_integrity_mutations.py -- paired mutation check (section
1.1) of tools/ref_integrity.py: each mutant is one exact text replacement in a copy of the census, written
to a temporary directory; the copy is run on a path that does not exist, and its built-in control needles
must stop it (exit 3) before any database is read. A replacement that does not occur exactly once is a
stale mutant and fails the check.

usage: ref_integrity_mutations.py
Exit: 0 every mutant killed except the ones listed in KNOWN (printed as KNOWN, with the reason); 1 a
mutant survived or is stale.
Evidence class: gate-logic only (section 11.4.289).
"""
import os
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
MUTANTS = [
    ("gaps", 'r["gaps"] = (mx - mn + 1 - n) if n else 0', 'r["gaps"] = 0'),
    ("orphan_hist", "from item_history h where not exists", "from item_history h where exists"),
    ("orphan_od", "from obsolete_details o where not exists", "from obsolete_details o where exists"),
    ("orphan_obd", "from operator_block_details o where not exists", "from operator_block_details o where exists"),
    ("obsolete_without_od", "i.status like 'Obsolete%' and not exists", "i.status like 'Obsolete%' and exists"),
    ("od_on_open", "where i.status not like 'Obsolete%'\")", "where i.status like 'Obsolete%'\")"),
    ("no_opened_row", "h.event_type='Opened')\")", "h.event_type='Updated')\")"),
    ("dup_ids", "having count(*) > 1)", "having count(*) > 2)"),
    ("seg_mismatch_items", "q(\"select count(*) from items i where not exists (select 1 from doc_segments d",
     "0 * q(\"select count(*) from items i where not exists (select 1 from doc_segments d"),
    ("seg_mismatch_segments", "+ q(\"select count(*) from doc_segments d where d.kind='item' and not exists",
     "+ 0 * q(\"select count(*) from doc_segments d where d.kind='item' and not exists"),
    ("clean_verdict", 'all(r[k] == 0 for k in KEYS) and not r["fk"]', 'True or not r["fk"]'),
    ("integrity_verdict", "r[\"integrity\"] == \"ok\"", "True"),
]
KNOWN = {"integrity_verdict": "no fixture holds a corrupt database, so the integrity_check verdict has no "
                              "dirty needle; its value is printed on every line"}


def main():
    src = open(os.path.join(HERE, "ref_integrity.py"), encoding="utf-8").read()
    bad = 0
    with tempfile.TemporaryDirectory() as d:
        for name, old, new in MUTANTS:
            if src.count(old) != 1:
                print("STALE %s: the text to replace occurs %d times" % (name, src.count(old)))
                bad += 1
                continue
            p = os.path.join(d, "m_%s.py" % name)
            with open(p, "w", encoding="utf-8") as f:
                f.write(src.replace(old, new))
            rc = subprocess.run([sys.executable, "-I", p, "x=" + os.path.join(d, "absent.db")],
                                capture_output=True, text=True).returncode
            if rc == 3:
                print("KILLED %s" % name)
            elif name in KNOWN:
                print("KNOWN %s rc=%d: %s" % (name, rc, KNOWN[name]))
            else:
                print("SURVIVED %s rc=%d" % (name, rc))
                bad += 1
    print("RESULT: mutants=%d bad=%d known=%d" % (len(MUTANTS), bad, len(KNOWN)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
