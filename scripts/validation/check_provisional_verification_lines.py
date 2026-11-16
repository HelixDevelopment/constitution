#!/usr/bin/env python3
"""scripts/validation/check_provisional_verification_lines.py -- every PROVISIONAL-DONE item names its verification job.

Usage:
  python3 -I scripts/validation/check_provisional_verification_lines.py [DB]     (default: docs/workable_items.db)

Section 11.4.290: an item counts as PROVISIONAL-DONE while its Status is `Ready for testing` or `In testing`, and
that state needs a scheduled verification job recorded on a line of the form

  **Verification:** provisional (...) -- job: ... -- checks: ... -- layer: ... -- target: ... -- artifact: ... -- due: ...

(the separator is " -- " or " — "). This checker reads the tracker database (the single source of truth,
section 11.4.93; opened read-only, never written) and refuses an item of those two statuses whose body has no such
line, more than one, a missing field, a field out of order, or an empty field value. It found the class of
CON-423 (rehearsal of the v73.4 cut, D2): four Ready-for-testing items with no line, so the release count line
said 25 provisional while 29 items were Ready for testing, and two lines with no `checks` field.

It does NOT check whether a due value is a date or overdue (derive_release_facts.sh reports that), whether the
job was run, or whether the named files exist.

Output: one `FAIL <id> <status>: <reason>` line per refused item, then `CHECKED items=N provisional_status=P
ok=K fail=F`, then `VERDICT: PASS|FAIL|BLIND`. Exit 0 PASS, 1 FAIL, 2 BLIND (the database cannot be read, has
no items table, or holds no items at all: a zero there proves nothing), 64 usage.
"""
import re
import sqlite3
import sys

STATUSES = ("Ready for testing", "In testing")
FIELDS = ("job", "checks", "layer", "target", "artifact", "due")
PREFIX = "**Verification:** provisional"
SEP = re.compile(r"\s+(?:--|—)\s+")


def blind(msg):
    print("BLIND %s" % msg)
    print("VERDICT: BLIND")
    return 2


def check_body(body):
    """Return None when the body carries one complete verification line, else the reason."""
    lines = [ln for ln in (body or "").splitlines() if ln.startswith(PREFIX)]
    if not lines:
        return "no '**Verification:** provisional' line"
    if len(lines) > 1:
        return "%d verification lines (one expected)" % len(lines)
    parts = SEP.split(lines[0])[1:]
    keys = []
    for part in parts:
        m = re.match(r"([a-z]+):(.*)\Z", part, re.S)
        if not m:
            continue
        keys.append(m.group(1))
        if m.group(1) in FIELDS and not m.group(2).strip(" .\t"):
            return "field '%s' is empty" % m.group(1)
    found = [k for k in keys if k in FIELDS]
    missing = [f for f in FIELDS if f not in found]
    if missing:
        return "missing field(s): %s" % ", ".join(missing)
    if len(found) != len(set(found)):
        return "a field is repeated: %s" % ", ".join(found)
    if tuple(found) != FIELDS:
        return "fields out of order: %s (expected %s)" % (", ".join(found), ", ".join(FIELDS))
    return None


def main(argv):
    if len(argv) > 2 or (len(argv) == 2 and argv[1].startswith("-")):
        sys.stderr.write("usage: check_provisional_verification_lines.py [DB]\n")
        return 64
    db = argv[1] if len(argv) == 2 else "docs/workable_items.db"
    try:
        con = sqlite3.connect("file:%s?mode=ro" % db, uri=True)
        total = con.execute("select count(*) from items").fetchone()[0]
        rows = con.execute(
            "select atm_id, status, body_md from items where status in (?, ?) order by atm_id", STATUSES).fetchall()
    except sqlite3.Error as exc:
        return blind("the database cannot be read (%s)" % exc.__class__.__name__)
    if total == 0:
        return blind("the items table holds no items")
    fails = 0
    for atm_id, status, body in rows:
        reason = check_body(body)
        if reason:
            fails += 1
            print("FAIL %s %s: %s" % (atm_id, status, reason))
    print("CHECKED items=%d provisional_status=%d ok=%d fail=%d" % (total, len(rows), len(rows) - fails, fails))
    print("VERDICT: %s" % ("FAIL" if fails else "PASS"))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
