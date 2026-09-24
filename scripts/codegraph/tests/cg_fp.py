#!/usr/bin/env python3
# ============================================================================
# cg_fp.py — fingerprint / fixture helper for the CodeGraph read-only-MCP tests
# ============================================================================
# Purpose      (1) `fp DIR`   : deterministic fingerprint of DIR/.codegraph — every
#                file (name,size,sha256) + logical hash of the database (schema
#                text + every ordinary table row) + index-name list — so "the DB
#                did not change" is proven on CONTENT, not on mtime.
#              (2) `dropidx DIR NAME...` : drop named indexes in the FIXTURE db
#                (recreates the mid-bulk-load state whose heal-on-open is the
#                hazard the read-only runner exists to prevent).
#              (3) `indexes DIR` : print the index names present.
# Usage        cg_fp.py fp <project-dir> | dropidx <project-dir> <idx>... | indexes <project-dir>
# Inputs       a FIXTURE project dir with DIR/.codegraph/codegraph.db
# Outputs      lines on stdout; exit 0 ok, 2 usage/missing db
# Side effects `dropidx` writes the fixture db; the others open it read-only
#              (mode=ro — never creates -wal/-shm, §11.4.174)
# Dependencies python3 (sqlite3 stdlib)
# Cross-refs   test_mcp_readonly.sh, constitution §11.4.273 (control needle)
# ============================================================================
import hashlib
import os
import sqlite3
import sys


def _ro(db):
    return sqlite3.connect("file:%s?mode=ro" % db, uri=True)


def fp(proj):
    d = os.path.join(proj, ".codegraph")
    db = os.path.join(d, "codegraph.db")
    if not os.path.isfile(db):
        sys.exit(2)
    for name in sorted(os.listdir(d)):
        p = os.path.join(d, name)
        if os.path.isfile(p):
            with open(p, "rb") as fh:
                h = hashlib.sha256(fh.read()).hexdigest()[:16]
            print("file %s size=%d sha=%s" % (name, os.path.getsize(p), h))
    con = _ro(db)
    try:
        h = hashlib.sha256()
        masters = con.execute("select type,name,tbl_name,coalesce(sql,'') from sqlite_master order by name").fetchall()
        for row in masters:
            h.update(repr(row).encode())
        tables = [r[1] for r in masters if r[0] == "table" and "VIRTUAL" not in r[3].upper()
                  and not r[1].startswith("sqlite_")]
        for t in tables:
            h.update(("T:" + t).encode())
            # WITHOUT ROWID tables have no rowid column: fetch everything and sort by repr (deterministic)
            for r in sorted(repr(row) for row in con.execute('select * from "%s"' % t)):
                h.update(r.encode())
        print("logical %s tables=%d" % (h.hexdigest()[:16], len(tables)))
        print("indexes " + ",".join(sorted(r[1] for r in masters if r[0] == "index")))
    finally:
        con.close()


def dropidx(proj, names):
    db = os.path.join(proj, ".codegraph", "codegraph.db")
    if not os.path.isfile(db):
        sys.exit(2)
    con = sqlite3.connect(db)
    for n in names:
        con.execute('drop index if exists "%s"' % n)
    con.commit()
    con.close()


def indexes(proj):
    db = os.path.join(proj, ".codegraph", "codegraph.db")
    if not os.path.isfile(db):
        sys.exit(2)
    con = _ro(db)
    try:
        print(",".join(sorted(r[0] for r in con.execute("select name from sqlite_master where type='index'"))))
    finally:
        con.close()


def main(argv):
    if len(argv) >= 2 and argv[0] == "fp":
        fp(argv[1])
    elif len(argv) >= 3 and argv[0] == "dropidx":
        dropidx(argv[1], argv[2:])
    elif len(argv) == 2 and argv[0] == "indexes":
        indexes(argv[1])
    else:
        sys.stderr.write("usage: cg_fp.py fp DIR | dropidx DIR IDX... | indexes DIR\n")
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
