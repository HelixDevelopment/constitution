#!/usr/bin/env python3
"""docs/qa/tracker_intake_2026_11_14_v7/tools/ref_integrity.py -- referential-integrity census of a
workable-items database: the checks of the round-4 review's probe p07. Round 6 adds the corrupt-file
needle (owed item 4 of the round-5 review).

usage: ref_integrity.py NAME=PATH [NAME=PATH ...]
  Each PATH is opened read-only through a quoted URI (a non-empty `-wal` sidecar is refused: BLIND).
  One line per database:
    items        rows of `items`
    hist         (max id, row count, min id) of `item_history`; gaps = ids missing between min and max
    seq          the `sqlite_sequence` value of `item_history`
    orphan_hist  history rows whose atm_id has no `items` row; orphan_od / orphan_obd the same for
                 `obsolete_details` / `operator_block_details`
    obsolete_without_od  items whose status starts with `Obsolete` and have no `obsolete_details` row
    od_on_open   `obsolete_details` rows of an item whose status does not start with `Obsolete`
    no_opened_row  items with no `Opened` history row
    dup_ids      (atm_id, current_location, representation) held by more than one row
    segs         `doc_segments` rows of kind `item`; seg_mismatch = items with no item segment plus
                 item segments with no item
    fk           PRAGMA foreign_key_check rows; integrity = PRAGMA integrity_check
  A line ends with `CLEAN` when every count above is 0, fk is empty and integrity is ok, else `DIRTY`.
Before any database is read the census runs on three fixtures: a clean one and a dirty one (one of each
defect) built in memory, and a corrupt file built in a temporary directory (an index entry overwritten
after the commit, so PRAGMA integrity_check reports a row missing from the index). The clean one must
read CLEAN, the dirty one must report every defect and the corrupt one must read integrity != ok and
DIRTY (control needles, section 11.4.273); a needle that fails exits 3. Mutation check:
tools/ref_integrity_mutations.py.
Exit: 0 every database CLEAN; 1 a database DIRTY; 2 usage or BLIND (unreadable, non-empty -wal);
3 a control needle failed.
Evidence class: gate-logic only (section 11.4.289).
"""
import os
import sqlite3
import sys
import tempfile
import urllib.parse

KEYS = ("gaps", "orphan_hist", "orphan_od", "orphan_obd", "obsolete_without_od", "od_on_open",
        "no_opened_row", "dup_ids", "seg_mismatch")


def census(c):
    q = lambda sql: c.execute(sql).fetchone()[0]  # noqa: E731 -- one scalar per query
    r = {"items": q("select count(*) from items")}
    mx, n, mn = c.execute("select max(id), count(*), min(id) from item_history").fetchone()
    r["hist"] = (mx, n, mn)
    r["gaps"] = (mx - mn + 1 - n) if n else 0
    s = c.execute("select seq from sqlite_sequence where name='item_history'").fetchone()
    r["seq"] = s[0] if s else None
    r["orphan_hist"] = q("select count(*) from item_history h where not exists (select 1 from items i where i.atm_id=h.atm_id)")
    r["orphan_od"] = q("select count(*) from obsolete_details o where not exists (select 1 from items i where i.atm_id=o.atm_id)")
    r["orphan_obd"] = q("select count(*) from operator_block_details o where not exists (select 1 from items i where i.atm_id=o.atm_id)")
    r["obsolete_without_od"] = q("select count(*) from items i where i.status like 'Obsolete%' and not exists (select 1 from obsolete_details o where o.atm_id=i.atm_id)")
    r["od_on_open"] = q("select count(*) from obsolete_details o join items i on i.atm_id=o.atm_id where i.status not like 'Obsolete%'")
    r["no_opened_row"] = q("select count(*) from items i where not exists (select 1 from item_history h where h.atm_id=i.atm_id and h.event_type='Opened')")
    r["dup_ids"] = q("select count(*) from (select 1 from items group by atm_id, current_location, representation having count(*) > 1)")
    r["segs"] = q("select count(*) from doc_segments where kind='item'")
    r["seg_mismatch"] = (q("select count(*) from items i where not exists (select 1 from doc_segments d where d.kind='item' and d.atm_id=i.atm_id)")
                         + q("select count(*) from doc_segments d where d.kind='item' and not exists (select 1 from items i where i.atm_id=d.atm_id)"))
    r["fk"] = c.execute("pragma foreign_key_check").fetchall()
    r["integrity"] = c.execute("pragma integrity_check").fetchone()[0]
    r["clean"] = all(r[k] == 0 for k in KEYS) and not r["fk"] and r["integrity"] == "ok"
    return r


def line(name, r):
    return ("%s items=%d hist(max,count,min)=%s seq=%s %s segs=%d fk=%s integrity=%s %s"
            % (name, r["items"], r["hist"], r["seq"], " ".join("%s=%d" % (k, r[k]) for k in KEYS),
               r["segs"], r["fk"], r["integrity"], "CLEAN" if r["clean"] else "DIRTY"))


FIXTURE = """
create table items (atm_id text, status text, current_location text, representation text);
create table item_history (id integer primary key autoincrement, atm_id text, event_type text);
create table obsolete_details (atm_id text primary key);
create table operator_block_details (atm_id text primary key);
create table doc_segments (id integer primary key autoincrement, kind text, atm_id text);
insert into items values ('P-1', 'Queued', 'Issues', 'section'), ('P-2', 'Obsolete (x)', 'Fixed', 'section');
insert into item_history (atm_id, event_type) values ('P-1', 'Opened'), ('P-2', 'Opened');
insert into obsolete_details values ('P-2');
insert into doc_segments (kind, atm_id) values ('item', 'P-1'), ('item', 'P-2'), ('raw', null);
"""
DIRTY = """
insert into items values ('P-3', 'Obsolete (x)', 'Fixed', 'section'), ('P-1', 'Queued', 'Issues', 'section'),
  ('P-4', 'Queued', 'Issues', 'section');
insert into item_history (atm_id, event_type) values ('P-9', 'Updated'), ('P-1', 'Updated'), ('P-4', 'Opened');
delete from item_history where id = 4;
insert into obsolete_details values ('P-4'), ('P-8');
insert into operator_block_details values ('P-7');
insert into doc_segments (kind, atm_id) values ('item', 'P-4'), ('item', 'P-6');
"""
# the dirty fixture holds exactly these defects: history id 4 missing; a history row of P-9 (no item);
# obsolete_details of P-8 (no item) and of the open P-4; operator_block_details of P-7 (no item); P-3
# Obsolete with no obsolete_details row, no Opened row and no segment; P-1 twice in one location; a
# segment of P-6 (no item)
WANT_DIRTY = {"gaps": 1, "orphan_hist": 1, "orphan_od": 1, "orphan_obd": 1, "obsolete_without_od": 1,
              "od_on_open": 1, "no_opened_row": 1, "dup_ids": 1, "seg_mismatch": 2}


def needles():
    clean = sqlite3.connect(":memory:")
    clean.executescript(FIXTURE)
    rc = census(clean)
    dirty = sqlite3.connect(":memory:")
    dirty.executescript(FIXTURE + DIRTY)
    rd = census(dirty)
    got = {k: rd[k] for k in KEYS}
    if not rc["clean"]:
        return "the clean fixture reads DIRTY: %s" % line("clean", rc)
    if got != WANT_DIRTY or rd["clean"]:
        return "the dirty fixture: got %s want %s" % (got, WANT_DIRTY)
    bad = corrupt_needle()
    if bad:
        return "the corrupt fixture: " + bad
    return ""


def corrupt_needle():
    """Build the clean fixture in a file, plus a side table the census never queries with 50 rows and an
    index; it must read CLEAN. Then overwrite one key of that index on disk: the reopened file must read
    DIRTY with every count 0 and integrity != ok, so the DIRTY verdict comes from the integrity check
    alone (the census's own queries do not touch the corrupted index). Return '' or the reason."""
    with tempfile.TemporaryDirectory() as d:
        p = os.path.join(d, "corrupt.db")
        c = sqlite3.connect(p)
        c.execute("pragma page_size=4096")
        c.executescript(FIXTURE + "create table side (k text); create index ix_side_k on side(k);")
        c.executemany("insert into side values (?)", [("Q-%03d" % i,) for i in range(50)])
        c.commit()
        r0 = census(c)
        if not r0["clean"]:
            return "it reads DIRTY before the corruption: " + line("corrupt-before", r0)
        root = c.execute("select rootpage from sqlite_master where name='ix_side_k'").fetchone()[0]
        c.close()
        with open(p, "rb") as f:
            b = bytearray(f.read())
        off = (root - 1) * 4096
        i = b.find(b"Q-010", off, off + 4096)
        if i < 0:
            return "the index key Q-010 is not on the index root page"
        b[i:i + 5] = b"Q-999"
        with open(p, "wb") as f:
            f.write(bytes(b))
        c = sqlite3.connect("file:%s?mode=ro" % urllib.parse.quote(p), uri=True)
        try:
            r = census(c)
        finally:
            c.close()
        if r["clean"] or r["integrity"] == "ok" or any(r[k] for k in KEYS):
            return "it did not read DIRTY by integrity alone: " + line("corrupt-after", r)
        return ""


def main(argv):
    if not argv or any("=" not in a or a.startswith("=") for a in argv):
        print((__doc__ or "").split("\n\n")[1], file=sys.stderr)
        return 2
    bad = needles()
    if bad:
        print("control needle FAILED: " + bad)
        return 3
    print("control needles: PASS (a clean fixture reads CLEAN; a dirty fixture reports each of its %d defects; a corrupt file reads integrity != ok)"
          % sum(WANT_DIRTY.values()))
    worst = 0
    for a in argv:
        name, path = a.split("=", 1)
        wal = path + "-wal"
        if not os.path.isfile(path) or (os.path.exists(wal) and os.path.getsize(wal) > 0):
            print("%s BLIND: missing, or a non-empty -wal sidecar" % name)
            worst = 2
            continue
        try:
            c = sqlite3.connect("file:%s?mode=ro" % urllib.parse.quote(os.path.abspath(path)), uri=True)
            r = census(c)
        except sqlite3.Error as e:
            print("%s BLIND: %s" % (name, e))
            worst = 2
            continue
        print(line(name, r))
        if not r["clean"] and worst == 0:
            worst = 1
    print("RESULT: %s databases=%d" % ({0: "CLEAN", 1: "DIRTY", 2: "BLIND"}[worst], len(argv)))
    return worst


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
