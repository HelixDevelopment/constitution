#!/usr/bin/env python3
# ============================================================================
# test_patch_machinery.py — RED/GREEN cases for the runner-patch MACHINERY of
# fk_index_patch.py (anchor uniqueness, reuse validation, default patch set).
# ============================================================================
# Purpose   Reproduces three review findings against a TINY fake platform
#           package (a few KiB, built under a temp dir), so no real CodeGraph
#           bundle is copied:
#             P1  fkidx1 anchors must be UNIQUE: a commented duplicate or a
#                 duplicated list declaration must refuse (exit 2, no runner)
#             P2  the reuse (REUSED) path must verify the WHOLE runner tree and
#                 an executable launcher, not only the edited files
#             P3  the default patch set is EXACTLY the tested subset
#             P4  minor: stale <dst>.partial removed on REUSED; a corrupt
#                 receipt refusal names --force
# Usage     python3 test_patch_machinery.py            (exit 0 = all PASS)
#           PATCH_TOOL_ROOT=<dir> python3 ...          (test a copied/mutated tool)
# Inputs    PATCH_TOOL_ROOT (default: this file's parent's parent)
# Outputs   one PASS/FAIL line per case on stdout; exit 1 on any FAIL
# Side effects  temp dirs only (removed on exit)
# Dependencies  python3 stdlib
# ============================================================================
import json
import os
import shutil
import subprocess
import sys
import tempfile

ROOT = os.environ.get("PATCH_TOOL_ROOT") or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOOL = os.path.join(ROOT, "fk_index_patch.py")

SCHEMA = """CREATE TABLE IF NOT EXISTS nodes (
  id TEXT PRIMARY KEY
);
CREATE TABLE IF NOT EXISTS edges (
  source TEXT,
  other TEXT,
  FOREIGN KEY (source) REFERENCES nodes(id)
);
CREATE INDEX IF NOT EXISTS idx_edges_source ON edges(source);
CREATE INDEX IF NOT EXISTS idx_edges_other ON edges(other);
"""
PARSE_LIST = """  static BULK_PARSE_INDEX_NAMES = [
    'idx_edges_source',
    'idx_edges_other',
  ];
"""
DBJS_TMPL = """db.pragma('foreign_keys = ON');
{pre}class Db {{
{parse}  static BULK_REF_INDEX_NAMES = [
    'idx_edges_other',
  ];
  static BULK_EDGE_INDEX_NAMES = [
    'idx_edges_other',
  ];
}}
"""

FAILS = []


def check(cid, ok, msg):
    print(f"{'PASS' if ok else 'FAIL'} {cid}: {msg}")
    if not ok:
        FAILS.append(cid)


def make_pkg(base, pre="", parse=PARSE_LIST):
    src = os.path.join(base, "pkg")
    os.makedirs(os.path.join(src, "lib", "dist", "db"))
    os.makedirs(os.path.join(src, "bin"))
    files = {
        "package.json": json.dumps({"version": "9.9.9"}),
        "lib/dist/db/schema.sql": SCHEMA,
        "lib/dist/db/index.js": DBJS_TMPL.format(pre=pre, parse=parse),
        "lib/dist/db/queries.js": "const q = 'INSERT OR REPLACE INTO nodes (id) VALUES (?)';\n",
        "lib/dist/other.js": "module.exports = 42;\n" * 20,
        "bin/codegraph": "#!/bin/sh\necho stub\n",
    }
    for rel, text in files.items():
        with open(os.path.join(src, rel), "w") as fh:
            fh.write(text)
    os.chmod(os.path.join(src, "bin", "codegraph"), 0o755)
    return src


def run(src, dst, *extra):
    p = subprocess.run([sys.executable, TOOL, "--src", src, "--dst", dst, "--patches", "fkidx1", *extra],
                       capture_output=True, text=True, timeout=120)
    return p.returncode, p.stdout, p.stderr


def status(out):
    try:
        return json.loads(out).get("status")
    except Exception:  # noqa: BLE001
        return None


def case_p1(base):
    # baseline: a clean package builds and the keep-index leaves the parse list
    src = make_pkg(os.path.join(base, "p1a"))
    dst = os.path.join(base, "p1a", "run")
    rc, out, err = run(src, dst)
    txt = open(os.path.join(dst, "lib/dist/db/index.js")).read() if rc == 0 else ""
    check("P1a", rc == 0 and "'idx_edges_source'" not in txt.split("BULK_REF")[0],
          f"clean package builds and drops idx_edges_source from the parse list (rc={rc})")
    # commented duplicate of the list anchor BEFORE the real one
    src = make_pkg(os.path.join(base, "p1b"),
                   pre="// static BULK_PARSE_INDEX_NAMES = ['idx_edges_source', 'idx_edges_other'];\n")
    dst = os.path.join(base, "p1b", "run")
    rc, out, err = run(src, dst)
    check("P1b", rc == 2 and not os.path.exists(dst),
          f"commented duplicate list anchor refuses with no runner (rc={rc}, dst_exists={os.path.exists(dst)})")
    # duplicated real declaration
    src = make_pkg(os.path.join(base, "p1c"), parse=PARSE_LIST + PARSE_LIST)
    dst = os.path.join(base, "p1c", "run")
    rc, out, err = run(src, dst)
    check("P1c", rc == 2 and not os.path.exists(dst),
          f"duplicated list declaration refuses with no runner (rc={rc}, dst_exists={os.path.exists(dst)})")


def case_p2(base):
    src = make_pkg(os.path.join(base, "p2"))
    dst = os.path.join(base, "p2", "run")
    rc, out, _ = run(src, dst)
    check("P2a", rc == 0 and status(out) == "CREATED", f"first build CREATED (rc={rc})")
    rc, out, _ = run(src, dst)
    check("P2b", rc == 0 and status(out) == "REUSED", f"untouched runner is REUSED (status={status(out)})")
    # truncate a NON-edited file in the runner
    other = os.path.join(dst, "lib/dist/other.js")
    open(other, "w").close()
    rc, out, _ = run(src, dst)
    check("P2c", rc == 0 and status(out) != "REUSED" and os.path.getsize(other) > 0,
          f"truncated non-edited file is NOT reused and gets rebuilt (status={status(out)}, size={os.path.getsize(other)})")
    # delete the launcher
    os.remove(os.path.join(dst, "bin", "codegraph"))
    rc, out, _ = run(src, dst, "--print-bin")
    path = out.strip()
    check("P2d", rc == 0 and os.path.isfile(path) and os.access(path, os.X_OK),
          f"--print-bin never prints a missing launcher (rc={rc}, exists={os.path.isfile(path)})")
    # an EXTRA file planted in the runner
    open(os.path.join(dst, "lib/dist/planted.js"), "w").write("x")
    rc, out, _ = run(src, dst)
    check("P2e", rc == 0 and status(out) != "REUSED" and not os.path.exists(os.path.join(dst, "lib/dist/planted.js")),
          f"a planted extra file is NOT reused (status={status(out)})")
    # legacy receipt (no 'patches') with a deleted launcher
    rcp = os.path.join(dst, "RUNNER_RECEIPT.json")
    rj = json.load(open(rcp))
    legacy = {k: rj[k] for k in ("patch_id", "source_dbjs_sha256", "patched_dbjs_sha256") if k in rj}
    json.dump(legacy, open(rcp, "w"))
    if os.path.lexists(os.path.join(dst, "bin", "codegraph")):
        os.remove(os.path.join(dst, "bin", "codegraph"))
    rc, out, _ = run(src, dst, "--print-bin")
    path = out.strip()
    check("P2f", rc == 0 and os.path.isfile(path) and os.access(path, os.X_OK),
          f"legacy receipt + missing launcher is not reused (rc={rc}, exists={os.path.isfile(path)})")


def case_p3():
    code = ("import sys; sys.dont_write_bytecode=True; sys.path.insert(0, sys.argv[1]); import runner_patches as r;"
            "print(','.join(m.PATCH_ID for m in r.load()))")
    p = subprocess.run([sys.executable, "-c", code, ROOT], capture_output=True, text=True)
    got = p.stdout.strip()
    check("P3", got == "fkidx1,resolve1,resolve2", f"default patch set is exactly fkidx1,resolve1,resolve2 (got '{got}')")


def case_p4(base):
    src = make_pkg(os.path.join(base, "p4"))
    dst = os.path.join(base, "p4", "run")
    run(src, dst)
    os.makedirs(dst + ".partial")
    rc, out, _ = run(src, dst)
    check("P4a", rc == 0 and status(out) == "REUSED" and not os.path.exists(dst + ".partial"),
          f"stale .partial removed on REUSED (status={status(out)}, partial={os.path.exists(dst + '.partial')})")
    open(os.path.join(dst, "RUNNER_RECEIPT.json"), "w").write("{corrupt")
    rc, out, err = run(src, dst)
    check("P4b", rc == 2 and "--force" in err, f"corrupt receipt refuses and names --force (rc={rc})")
    rc, out, err = run(src, dst, "--force")
    check("P4c", rc == 0 and status(out) == "CREATED", f"--force rebuilds over a corrupt receipt (rc={rc})")


def main():
    base = tempfile.mkdtemp(prefix="cg_patch_mach.")
    try:
        for name, fn in (("P1", lambda: case_p1(base)), ("P2", lambda: case_p2(base)),
                         ("P3", case_p3), ("P4", lambda: case_p4(base))):
            try:
                fn()
            except Exception as exc:  # noqa: BLE001  a crashing case is a FAIL, never a silent skip
                check(name + "-crash", False, f"{type(exc).__name__}: {exc}")
    finally:
        shutil.rmtree(base, ignore_errors=True)
    print(f"SUMMARY fails={len(FAILS)} {' '.join(FAILS)}")
    return 1 if FAILS else 0


if __name__ == "__main__":
    sys.exit(main())
