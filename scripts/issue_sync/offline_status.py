"""Offline pending-change report (no network): compares each item's current content hash with issue_sync_map. Used by the pre-commit hook.
pending = item not mapped on a recorded leg, or its mapped hash differs. Counts only; ids are listed only when --ids is given."""
import sys

from . import payload as pl, store


def status(db_path, ids=False):
    con = store.open_db(db_path)
    items = store.load_items(con)
    try:
        rows = con.execute("SELECT atm_id, tracker, content_hash FROM issue_sync_map").fetchall()
    except Exception:
        rows = []
    legs = sorted({r["tracker"] for r in rows})
    mapped = {}
    for r in rows:
        mapped.setdefault(r["atm_id"], {})[r["tracker"]] = r["content_hash"]
    pending = []
    for it in items:
        res = pl.prepare(it)
        h = res.get("hash")
        m = mapped.get(it["atm_id"], {})
        if not legs or any(m.get(l) != h for l in legs):
            pending.append(it["atm_id"])
    return {"items": len(items), "legs": len(legs), "pending": len(pending), **({"ids": pending} if ids else {})}


def main(argv):
    import json
    db = argv[0] if argv else "docs/workable_items.db"
    r = status(db, ids="--ids" in argv)
    print(json.dumps(r))
    return 1 if r["pending"] else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
