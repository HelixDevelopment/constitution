#!/usr/bin/env python3
"""tdiff3.py -- read-only, full-table diff tables of a landing: base B, vehicle V, target T, landed L.

Evidence tool of the round-4 tracker-intake answer (docs/qa/tracker_intake_2026_11_12_v4/README.md).
It is a reading aid for a human, independent of remint_ids.py (it imports nothing from it): for every
table it counts the rows the vehicle added, removed and changed against the base, and the rows the
landing added, removed and changed against the target; for the items table it lists every item the
vehicle changed with the columns that changed on each side, and every target item the landing changed.

USAGE  python3 -I tdiff3.py --base B --vehicle V --target T --landed L --map MAP.tsv
       MAP.tsv: the plan's map (header line, then `old<TAB>new`).
OUTPUT Markdown tables on stdout. Columns created_at and last_modified are listed but never counted as
       a change of content (the engine stamps them; remint_ids.py reports them as KNOWN).
EXIT   0 printed; 3 an input cannot be read.
"""
import argparse
import sqlite3
import sys

STAMPS = {"created_at", "last_modified"}
SKIP_ROWS = {"item_history", "doc_segments", "sqlite_sequence"}  # engine-written per event / per render


def con(p):
    c = sqlite3.connect("file:%s?mode=ro" % p, uri=True)
    c.row_factory = sqlite3.Row
    return c


def tables(c):
    return [r[0] for r in c.execute("select name from sqlite_master where type='table' order by name")]


def rows(c, t):
    info = list(c.execute("pragma table_info(%s)" % t))
    pk = [r[1] for r in sorted(info, key=lambda r: r[5]) if r[5]]
    out = {}
    for r in c.execute("select * from %s" % t):
        d = dict(r)
        key = tuple(d[k] for k in pk) if pk else tuple(sorted(d.items()))
        out[key] = d
    return out


def changed(a, b):
    return sorted(k for k in set(a) | set(b) if a.get(k) != b.get(k))


def content(cols):
    return [k for k in cols if k not in STAMPS]


def main(argv):
    ap = argparse.ArgumentParser()
    for n in ("base", "vehicle", "target", "landed", "map"):
        ap.add_argument("--" + n, required=True)
    a = ap.parse_args(argv)
    try:
        B, V, T, L = con(a.base), con(a.vehicle), con(a.target), con(a.landed)
        with open(a.map, encoding="utf-8") as f:
            m = dict(x.split("\t") for x in f.read().splitlines()[1:] if x)
        names = sorted(set(tables(B)) | set(tables(V)) | set(tables(T)) | set(tables(L)))
        data = {t: [rows(c, t) if t in tables(c) else {} for c in (B, V, T, L)] for t in names}
        # items are keyed by id alone: a close or reopen moves the row between locations (part of its
        # primary key), which is a change of the item, not a removal and an addition
        data["items"] = [{(r["atm_id"],): r for r in sorted(d.values(), key=lambda r: r["current_location"], reverse=True)}
                         for d in data["items"]]
    except (OSError, sqlite3.Error, ValueError) as e:
        print("BLIND: %s" % e)
        return 3
    print("## Table counts\n")
    print("| table | B rows | V rows | T rows | L rows | V-B added | V-B removed | V-B changed | L-T added | L-T removed | L-T changed |")
    print("|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
    for t in names:
        b, v, tt, ll = data[t]
        if t in SKIP_ROWS:
            print("| %s | %d | %d | %d | %d | %s |" % (t, len(b), len(v), len(tt), len(ll), " | ".join(["(engine-written)"] * 6)))
            continue
        vb_add, vb_rem = len(set(v) - set(b)), len(set(b) - set(v))
        vb_chg = sum(1 for k in set(v) & set(b) if content(changed(v[k], b[k])))
        lt_add, lt_rem = len(set(ll) - set(tt)), len(set(tt) - set(ll))
        lt_chg = sum(1 for k in set(ll) & set(tt) if content(changed(ll[k], tt[k])))
        print("| %s | %d | %d | %d | %d | %d | %d | %d | %d | %d | %d |" % (
            t, len(b), len(v), len(tt), len(ll), vb_add, vb_rem, vb_chg, lt_add, lt_rem, lt_chg))
    b, v, tt, ll = data["items"]
    print("\n## Items the vehicle changed or added, and where they landed\n")
    print("| vehicle id | landed id | kind | content columns changed in V (against B) | content columns of L that differ from V |")
    print("|---|---|---|---|---|")
    for k in sorted(set(v), key=lambda x: (x[0], x[1:])):
        if k in b and not content(changed(v[k], b[k])):
            continue
        kind = "base item changed" if k in b else "minted by V"
        nid = m.get(k[0], k[0])
        lk = (nid,) + k[1:]
        vb = content(changed(v[k], b[k])) if k in b else ["(new)"]
        if lk not in ll:
            ld = "MISSING in L"
        else:
            # an id the map moved differs in every text that names it; list the columns, the reader
            # follows them in verify.txt (which checks every id token)
            ld = ", ".join(c for c in content(changed(ll[lk], v[k])) if c != "atm_id") or "none"
        print("| %s | %s | %s | %s | %s |" % (k[0], nid, kind, ", ".join(vb), ld))
    print("\n## Target items the landing changed\n")
    print("| id | content columns changed (L against T) | changed in V too |")
    print("|---|---|---|")
    any_row = False
    for k in sorted(set(tt) & set(ll), key=lambda x: (x[0], x[1:])):
        lt = content(changed(ll[k], tt[k]))
        if lt:
            any_row = True
            inv = "yes" if k in b and k in v and content(changed(v[k], b[k])) else "NO"
            print("| %s | %s | %s |" % (k[0], ", ".join(lt), inv))
    if not any_row:
        print("| (none) | | |")
    removed = sorted(set(tt) - set(ll))
    print("\nTarget items removed by the landing: %s" % (", ".join(k[0] for k in removed) if removed else "none"))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
