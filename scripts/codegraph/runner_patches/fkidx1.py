"""fkidx1 — keep the FK child-key indexes through the bulk-index windows.

The stock bulk index drops the secondary indexes serving the `ON DELETE
CASCADE` lookups of `nodes(id)` children, then runs `INSERT OR REPLACE INTO
nodes` under `foreign_keys=ON`; every duplicate node id becomes a full scan.
The keep-set is DERIVED from the target's own schema.sql (see
fk_cascade_probe.py for the RED/GREEN oracle). Logic unchanged from the
original single-patch fk_index_patch.py (moved here verbatim in behaviour).
"""
import re

from .common import NotNeeded, Refuse

PATCH_ID = "fkidx1"
SUMMARY = "keep FK child-key indexes during bulk windows (no cascade full scans)"
DBJS = "lib/dist/db/index.js"
SCHEMA = "lib/dist/db/schema.sql"
QUERIES = "lib/dist/db/queries.js"

TABLE_RE = re.compile(r"CREATE TABLE IF NOT EXISTS\s+(\w+)\s*\((.*?)\n\);", re.S)
FK_RE = re.compile(r"FOREIGN KEY\s*\(\s*(\w+)\s*\)\s*REFERENCES\s+nodes\s*\(\s*id\s*\)", re.I)
IDX_RE = re.compile(r"CREATE\s+(UNIQUE\s+)?INDEX\s+IF NOT EXISTS\s+(\w+)\s+ON\s+(\w+)\s*\(([^)]*)\)", re.I)
LIST_RE = re.compile(r"(static\s+BULK_[A-Z_]+_NAMES\s*=\s*\[)(.*?)(\];)", re.S)


def derive_keep_set(schema):
    fks = []
    for tm in TABLE_RE.finditer(schema):
        for col in FK_RE.findall(tm.group(2)):
            fks.append((tm.group(1), col))
    if not fks:
        raise NotNeeded("schema.sql has no FOREIGN KEY ... REFERENCES nodes(id)")
    idxs = []
    for m in IDX_RE.finditer(schema):
        cols = [c.strip().split()[0] for c in m.group(4).split(",")]
        idxs.append({"name": m.group(2), "table": m.group(3), "unique": bool(m.group(1)), "cols": cols})
    return fks, idxs


def parse_lists(dbjs):
    lists = {}
    for m in LIST_RE.finditer(dbjs):
        nm = re.search(r"BULK_[A-Z_]+_NAMES", m.group(1)).group(0)
        lists[nm] = re.findall(r"'(idx_[A-Za-z0-9_]+)'", m.group(2))
    for need in ("BULK_PARSE_INDEX_NAMES", "BULK_REF_INDEX_NAMES", "BULK_EDGE_INDEX_NAMES"):
        if not lists.get(need):
            raise Refuse(f"db/index.js: {need} not found/empty — upstream shape changed")
    return lists


def compute_patch(schema, dbjs, queries_js):
    if not re.search(r"INSERT OR REPLACE INTO nodes", queries_js):
        raise NotNeeded("queries.js no longer uses INSERT OR REPLACE INTO nodes")
    if not re.search(r"foreign_keys\s*=\s*ON", dbjs):
        raise NotNeeded("db/index.js no longer enables foreign_keys")
    fks, idxs = derive_keep_set(schema)
    lists = parse_lists(dbjs)
    dropped_anywhere = set().union(*[set(v) for v in lists.values()])
    keep = []
    for table, col in fks:
        cands = [i for i in idxs if i["table"] == table and i["cols"] and i["cols"][0] == col]
        if any(i["name"] not in dropped_anywhere for i in cands):
            continue  # already served by a never-dropped index (e.g. UNIQUE identity)
        if not cands:
            raise Refuse(f"FK child {table}.{col} has NO index candidate in schema.sql — cannot serve it")
        cands.sort(key=lambda i: (len(i["cols"]), i["name"]))
        keep.append(cands[0]["name"])
    keep = sorted(set(keep))
    if not keep:
        raise NotNeeded("every FK child column is already served by a never-dropped index")
    return keep, lists


def patch_text(dbjs, keep, lists):
    out = dbjs
    after = {k: list(v) for k, v in lists.items()}
    for name in keep:
        holders = [k for k, v in lists.items() if name in v]
        if not holders:
            raise Refuse(f"{name} is in no drop list — derivation inconsistent")
        for lname in holders:
            pat = re.compile(rf"(static\s+{lname}\s*=\s*\[)(.*?)(\];)", re.S)
            m = pat.search(out)
            body = m.group(2)
            occ = len(re.findall(rf"'{name}'\s*,?", body))
            if occ != 1:
                raise Refuse(f"{name} appears {occ}x in {lname} (expected exactly once)")
            new_body = re.sub(rf"[ \t]*'{name}'\s*,?[ \t]*\n?", "", body, count=1)
            out = out[: m.start(2)] + new_body + out[m.end(2):]
            after[lname] = [x for x in after[lname] if x != name]
    for lname, v in after.items():
        if not v:
            raise Refuse(f"{lname} became empty after patch — refusing (would alter window semantics)")
    return out, after


def plan(view):
    from .common import PatchPlan
    dbjs = view.read(DBJS)
    keep, lists = compute_patch(view.read(SCHEMA), dbjs, view.read(QUERIES))
    patched, after = patch_text(dbjs, keep, lists)
    p = PatchPlan(PATCH_ID)
    p.new_text[DBJS] = patched
    for lname in sorted({k for k, v in lists.items() if set(v) & set(keep)}):
        p.anchors.append({"file": DBJS, "anchor": f"static {lname} = [...]", "occurrences": 1})
    p.detail = {"kept_indexes": keep, "lists_before": lists, "lists_after": after}
    return p
