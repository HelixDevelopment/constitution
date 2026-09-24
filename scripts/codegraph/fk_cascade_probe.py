#!/usr/bin/env python3
# ============================================================================
# fk_cascade_probe.py — CodeGraph bulk-window FK-cascade hazard probe
# (constitution §11.4.78 / §11.4.80 — defect tracked by the consuming project
#  that discovered it; universal: no project literal here)
# ============================================================================
#
# Purpose
#   Decide, for ONE installed CodeGraph build, whether its bulk-index windows can
#   fall into the FK-cascade full-scan trap:
#
#     * `nodes.id` is a PRIMARY KEY and the store path writes `INSERT OR REPLACE
#       INTO nodes`, so a duplicate node id is a DELETE + INSERT.
#     * `edges.source/target` and `unresolved_refs.from_node_id` are
#       `FOREIGN KEY ... REFERENCES nodes(id) ON DELETE CASCADE` and the store
#       connection runs with `PRAGMA foreign_keys = ON`.
#     * During a fresh bulk index the indexer DROPs secondary indexes (lists
#       BULK_PARSE_INDEX_NAMES / BULK_REF_INDEX_NAMES / BULK_EDGE_INDEX_NAMES).
#       If a child-key index is among them, every duplicate-id REPLACE becomes a
#       FULL SCAN of the child table (measured 2,223x slower at 1/6 scale; the
#       real 584,601-file run stalled at 52%).
#
#   Two independent layers (both must agree with "safe" for exit 0):
#     STATIC   — parse the target's own schema.sql + db/index.js, derive every
#                FK child column of nodes(id), and check, per bulk window, that
#                at least one index with that column LEFTMOST survives the window
#                (a never-dropped UNIQUE index counts).
#     MEASURED — build a scaled DB from the target's own schema, recreate exactly
#                the indexes that survive each window, and time
#                `INSERT OR REPLACE` of an EXISTING node id (foreign_keys=ON).
#
# Usage
#   fk_cascade_probe.py [--dist <codegraph lib/dist dir>] [--threshold-s 0.05]
#                       [--scale-nodes N --scale-refs N --scale-edges N]
#                       [--static-only] [--json-out FILE] [--work-dir DIR]
#   --dist defaults to the globally installed @colbymchenry/codegraph platform
#   package (resolved via `npm root -g`; nothing hardcoded).
#
# Exit codes
#   0  no hazard (static AND measured agree)
#   1  HAZARD (a window leaves an FK child column unserved and/or a measured
#      REPLACE exceeds the threshold)
#   2  cannot evaluate (missing/unparseable target, unexpected schema shape,
#      disk/DB error) — FAIL-CLOSED: never reported as safe (§11.4.201(4))
#
# Outputs
#   stdout: one JSON document (verdict, per-window static + measured evidence)
#   --json-out: the same document persisted for the evidence trail (§11.4.5)
#
# Side effects
#   Creates and deletes one scratch SQLite DB (default ~0.5 GB, tmpfs-friendly).
#
# Cross-references
#   constitution §11.4.78 / §11.4.80 (CodeGraph), §11.4.115 (RED on the broken
#   artifact), §11.4.201 (guard asserts the real condition), §11.4.273 (measured
#   result is control-needled by the static layer and vice-versa).
# ============================================================================
import argparse
import json
import os
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import time

TABLE_RE = re.compile(r"CREATE TABLE IF NOT EXISTS\s+(\w+)\s*\((.*?)\n\);", re.S)
FK_RE = re.compile(r"FOREIGN KEY\s*\(\s*(\w+)\s*\)\s*REFERENCES\s+nodes\s*\(\s*id\s*\)", re.I)
IDX_RE = re.compile(
    r"CREATE\s+(UNIQUE\s+)?INDEX\s+IF NOT EXISTS\s+(\w+)\s+ON\s+(\w+)\s*\(([^)]*)\)", re.I
)
LIST_RE = re.compile(r"static\s+(BULK_[A-Z_]+_NAMES)\s*=\s*\[(.*?)\];", re.S)


class CannotEvaluate(Exception):
    pass


def find_default_dist():
    try:
        root = subprocess.check_output(["npm", "root", "-g"], text=True, timeout=60).strip()
    except Exception as exc:  # noqa: BLE001
        raise CannotEvaluate(f"npm root -g failed: {exc}")
    base = os.path.join(root, "@colbymchenry", "codegraph", "node_modules", "@colbymchenry")
    if not os.path.isdir(base):
        raise CannotEvaluate(f"no @colbymchenry/codegraph install under {base}")
    for name in sorted(os.listdir(base)):
        cand = os.path.join(base, name, "lib", "dist")
        if os.path.isfile(os.path.join(cand, "db", "index.js")):
            return cand
    raise CannotEvaluate(f"no platform package with lib/dist/db/index.js under {base}")


def load_target(dist):
    dbdir = os.path.join(dist, "db")
    try:
        schema = open(os.path.join(dbdir, "schema.sql"), encoding="utf-8").read()
        dbjs = open(os.path.join(dbdir, "index.js"), encoding="utf-8").read()
    except OSError as exc:
        raise CannotEvaluate(f"cannot read target files: {exc}")
    lists = {m.group(1): re.findall(r"'(idx_[A-Za-z0-9_]+)'", m.group(2)) for m in LIST_RE.finditer(dbjs)}
    for need in ("BULK_PARSE_INDEX_NAMES", "BULK_REF_INDEX_NAMES", "BULK_EDGE_INDEX_NAMES"):
        if need not in lists or not lists[need]:
            raise CannotEvaluate(f"db/index.js: list {need} not found/empty (upstream shape changed)")
    fks = []
    for tm in TABLE_RE.finditer(schema):
        for col in FK_RE.findall(tm.group(2)):
            fks.append((tm.group(1), col))
    if not fks:
        raise CannotEvaluate("schema.sql: no FOREIGN KEY ... REFERENCES nodes(id) found (shape changed)")
    idxs = []
    for m in IDX_RE.finditer(schema):
        cols = [c.strip().split()[0] for c in m.group(4).split(",")]
        idxs.append({"name": m.group(2), "table": m.group(3), "unique": bool(m.group(1)), "cols": cols})
    # windows: parse window also enters the edge window (beginBulkParseLoad -> beginBulkEdgeLoad)
    edge = set(lists["BULK_EDGE_INDEX_NAMES"])
    windows = {
        "parse": set(lists["BULK_PARSE_INDEX_NAMES"]) | edge,
        "ref": set(lists["BULK_REF_INDEX_NAMES"]) | edge,
        "edge": edge,
    }
    return schema, lists, fks, idxs, windows


def static_layer(fks, idxs, windows):
    out = {}
    for wname, dropped in windows.items():
        unserved, served = [], []
        for table, col in fks:
            cands = [i["name"] for i in idxs if i["table"] == table and i["cols"] and i["cols"][0] == col]
            survivors = [c for c in cands if c not in dropped]
            (served if survivors else unserved).append(
                {"table": table, "column": col, "candidates": cands, "survivors": survivors}
            )
        out[wname] = {"unserved": unserved, "served": served, "hazard": bool(unserved)}
    return out


def build_db(path, schema, idxs, args):
    if os.path.exists(path):
        os.remove(path)
    c = sqlite3.connect(path)
    c.executescript(schema)
    for (t,) in c.execute("select name from sqlite_master where type='trigger'").fetchall():
        c.execute(f'drop trigger if exists "{t}"')
    for i in idxs:
        if not i["unique"]:  # UNIQUE indexes stay: INSERT OR IGNORE dedup conflicts on them (as in the real window)
            c.execute(f"drop index if exists {i['name']}")
    c.commit()
    # shape guard: refuse to time a DB we cannot populate correctly (fail closed)
    need = {
        "nodes": {"id", "kind", "name", "qualified_name", "file_path", "language", "start_line", "end_line",
                  "start_column", "end_column", "is_exported", "is_async", "is_static", "is_abstract", "updated_at"},
        "unresolved_refs": {"from_node_id", "reference_name", "reference_kind", "line", "col", "file_path", "language"},
        "edges": {"source", "target", "kind"},
    }
    for tbl, have in need.items():
        rows = c.execute(f"pragma table_info({tbl})").fetchall()
        if not rows:
            raise CannotEvaluate(f"table {tbl} missing after schema load")
        for _cid, name, _type, notnull, dflt, pk in rows:
            if notnull and dflt is None and not pk and name not in have:
                raise CannotEvaluate(f"{tbl}.{name} is NOT NULL without default and unknown to the probe (schema changed)")
    c.execute("pragma journal_mode=OFF")
    c.execute("pragma synchronous=OFF")
    c.execute("pragma cache_size=-64000")
    n, r, e = args.scale_nodes, args.scale_refs, args.scale_edges

    def nodes():
        for i in range(n):
            yield (f"n{i:09d}", "function", f"f{i % 50000}", f"ns::f{i % 50000}", f"src/d{i % 9000}/f{i % 30000}.c",
                   "c", 1, 2, 0, 1, 0, 0, 0, 0, 0)

    def refs():
        for i in range(r):
            yield (f"n{(i * 7919) % n:09d}", f"callee{i % 70000}", "calls", 3, 4, f"src/d{i % 9000}/f{i % 30000}.c", "c")

    def edges():
        for i in range(e):
            yield (f"n{i % n:09d}", f"n{(i * 104729 + 1) % n:09d}", "contains")

    c.execute("begin")
    c.executemany(
        "insert into nodes(id,kind,name,qualified_name,file_path,language,start_line,end_line,start_column,"
        "end_column,is_exported,is_async,is_static,is_abstract,updated_at) values(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
        nodes())
    c.executemany(
        "insert into unresolved_refs(from_node_id,reference_name,reference_kind,line,col,file_path,language) "
        "values(?,?,?,?,?,?,?)", refs())
    c.executemany("insert or ignore into edges(source,target,kind) values(?,?,?)", edges())
    c.commit()
    return c


def measured_layer(work_dir, schema, idxs, fks, windows, static, args):
    db_path = os.path.join(work_dir, "fk_probe.db")
    c = build_db(db_path, schema, idxs, args)
    c.close()
    ddl = {}
    for m in re.finditer(r"CREATE\s+(?:UNIQUE\s+)?INDEX\s+IF NOT EXISTS\s+(\w+)\b[^;]*;", schema, re.I):
        ddl[m.group(1)] = m.group(0)
    res = {}
    repl = ("insert or replace into nodes(id,kind,name,qualified_name,file_path,language,start_line,end_line,"
            "start_column,end_column,is_exported,is_async,is_static,is_abstract,updated_at) "
            "values(?,?,?,?,?,?,1,2,0,1,0,0,0,0,0)")
    picks = (10, args.scale_nodes // 2, args.scale_nodes - 100)
    for wname in ("parse", "ref"):
        c = sqlite3.connect(db_path)
        c.execute("pragma foreign_keys=ON")
        survivors = set()
        for f in static[wname]["served"]:
            if f["survivors"]:
                survivors.add(f["survivors"][0])
        created = []
        for name in sorted(survivors):
            if name in ddl:
                c.execute(ddl[name])
                created.append(name)
        c.commit()
        times = []
        for k in picks:
            t = time.perf_counter()
            c.execute(repl, (f"n{k:09d}", "function", "x", "x", "src/x.c", "c"))
            c.commit()
            times.append(round(time.perf_counter() - t, 6))
        median = sorted(times)[len(times) // 2]
        res[wname] = {"indexes_present_for_fk": created, "replace_existing_s": times,
                      "median_s": median, "hazard": median > args.threshold_s}
        for name in created:
            c.execute(f"drop index if exists {name}")
        c.commit()
        c.close()
    os.remove(db_path)
    return res


def main():
    ap = argparse.ArgumentParser(description="CodeGraph bulk-window FK-cascade hazard probe")
    ap.add_argument("--dist")
    ap.add_argument("--threshold-s", type=float, default=0.05)
    ap.add_argument("--scale-nodes", type=int, default=1_000_000)
    ap.add_argument("--scale-refs", type=int, default=4_000_000)
    ap.add_argument("--scale-edges", type=int, default=1_200_000)
    ap.add_argument("--static-only", action="store_true")
    ap.add_argument("--json-out")
    ap.add_argument("--work-dir")
    args = ap.parse_args()
    doc = {"probe": "codegraph-fk-cascade", "verdict": "CANNOT_EVALUATE"}
    try:
        dist = args.dist or find_default_dist()
        doc["dist"] = dist
        schema, lists, fks, idxs, windows = load_target(dist)
        doc["fk_children_of_nodes"] = [{"table": t, "column": c} for t, c in fks]
        doc["bulk_lists"] = lists
        static = static_layer(fks, idxs, windows)
        doc["static"] = static
        # the edge-only window is informational; parse+ref are the windows a bulk index enters
        hazard = static["parse"]["hazard"] or static["ref"]["hazard"]
        if not args.static_only:
            wd = args.work_dir or tempfile.mkdtemp(prefix="cg_fk_probe_")
            try:
                doc["measured"] = measured_layer(wd, schema, idxs, fks, windows, static, args)
            finally:
                if not args.work_dir:
                    shutil.rmtree(wd, ignore_errors=True)
            hazard = hazard or any(w["hazard"] for w in doc["measured"].values())
            doc["scale"] = {"nodes": args.scale_nodes, "refs": args.scale_refs, "edges": args.scale_edges,
                            "threshold_s": args.threshold_s}
        doc["verdict"] = "HAZARD" if hazard else "SAFE"
        code = 1 if hazard else 0
    except CannotEvaluate as exc:
        doc["error"] = str(exc)
        code = 2
    except Exception as exc:  # noqa: BLE001 — fail closed on ANY unexpected error
        doc["error"] = f"{type(exc).__name__}: {exc}"
        code = 2
    text = json.dumps(doc, indent=2)
    if args.json_out:
        with open(args.json_out, "w", encoding="utf-8") as fh:
            fh.write(text + "\n")
    print(text)
    return code


if __name__ == "__main__":
    sys.exit(main())
