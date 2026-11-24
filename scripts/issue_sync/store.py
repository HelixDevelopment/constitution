"""Workable-items DB access (anchor 11.4.93 DB is truth). Read-only on items; writes only the sync-state table issue_sync_map, created on demand
(IF NOT EXISTS, lossless; the consumer's own store may bump schema_version separately). Items collapse by atm_id: an open (Issues) row wins over a Fixed row."""
import sqlite3

MAP_DDL = """CREATE TABLE IF NOT EXISTS issue_sync_map (
  atm_id TEXT NOT NULL, tracker TEXT NOT NULL, host TEXT NOT NULL, repo TEXT NOT NULL, issue_number INTEGER, issue_url TEXT,
  content_hash TEXT, last_synced_at TEXT, state TEXT, last_error TEXT, PRIMARY KEY (atm_id, tracker, host, repo))"""
FIELDS = "atm_id, type, status, title, severity, description, current_location"


def open_db(path, write=False):
    import pathlib
    uri = pathlib.Path(path).resolve().as_uri() + "?mode=" + ("rw" if write else "ro")   # escaped; a missing DB is an error, never created here
    con = sqlite3.connect(uri, uri=True)
    con.row_factory = sqlite3.Row
    return con


def load_items(con):
    rows = con.execute("SELECT %s FROM items" % FIELDS).fetchall()
    best = {}
    for r in rows:
        d = dict(r)
        cur = best.get(d["atm_id"])
        if cur is None or (cur["current_location"] == "Fixed" and d["current_location"] != "Fixed"):
            best[d["atm_id"]] = d
    return [best[k] for k in sorted(best)]


def load_sub_projects(con):
    """-> (prefix -> url for prefixes with their own repo, third-party prefixes, parent prefixes, table_present). Only a MISSING table is tolerated;
    any other error (missing column, lock, I/O) propagates so routing can never fail open."""
    has = con.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='sub_projects'").fetchone()
    if not has:
        return {}, set(), set(), False
    rows = con.execute("SELECT prefix, class, url FROM sub_projects").fetchall()
    if not rows:                      # an empty map carries no routing information: same as no table (the DB's own repo owns everything)
        return {}, set(), set(), False
    return ({r["prefix"]: r["url"] for r in rows if r["url"]}, {r["prefix"] for r in rows if r["class"] == "third-party"},
            {r["prefix"] for r in rows if r["class"] == "parent" and not r["url"]}, True)


def ensure_map(con):
    con.execute(MAP_DDL)
    con.commit()


def record(con, atm_id, leg_id, host, repo, issue, content_hash, now, error=None):
    con.execute("INSERT OR REPLACE INTO issue_sync_map VALUES (?,?,?,?,?,?,?,?,?,?)",
                (atm_id, leg_id, host, repo, issue["number"] if issue else None, issue["url"] if issue else None, content_hash, now,
                 issue["state"] if issue else None, error))
    con.commit()
