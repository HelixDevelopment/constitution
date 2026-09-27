#!/usr/bin/env python3
"""test_fk_cascade_probe.py — executing tests for fk_cascade_probe.py (§11.4.224 test-first; §11.4.115 RED-capable).

Purpose      Prove the CodeGraph bulk-window FK-cascade hazard probe does what its header promises, on OBSERVABLE behaviour only
             (exit code, the JSON document on stdout, --json-out file, scratch files/dirs) against SYNTHETIC "dist" trees built in
             a temp dir. The probe decides, for one installed CodeGraph build, whether a bulk-index window can drop the only index
             serving an FK child column of nodes(id) (a duplicate-id INSERT OR REPLACE then full-scans the child table).
             Covered: (a) STATIC layer — per-window served/unserved verdicts, edge-list propagation into the parse+ref windows,
             leftmost-column / same-table / order-suffix / case-insensitive SQL rules, a never-dropped UNIQUE index counting as
             serving; (b) MEASURED layer — the recreated-index set per window, threshold knob, scaled-DB shape guard, trigger drop,
             scratch DB / temp dir lifecycle, and (relative timing, so machine speed cancels) that a REPLACE with foreign_keys=ON
             really is slower when the FK child index is missing; (c) FAIL-CLOSED exit 2 on every unevaluable target (§11.4.201(4));
             (d) default-dist resolution via `npm root -g` (a fake `npm` on PATH — the real install is never touched); (e) CLI
             surface (--help, unknown flag, bad number) and output determinism (§11.4.50).
Usage        python3 test_fk_cascade_probe.py            (TOOL=<path> selects the code under test; used by the mutation harness)
Inputs       TOOL env (default: ../fk_cascade_probe.py next to this file)
Outputs      unittest result; exit 1 on any failure
Side effects creates and removes temp dirs only; never touches a live `.codegraph/` index, the repo root, or the real npm install
Dependencies python3 (stdlib only), sh (fake npm)
Cross-refs   fk_cascade_probe.py, test_fk_cascade_probe_mutations.sh, docs/scripts/fk_cascade_probe.md,
             constitution §11.4.18 / §11.4.50 / §11.4.115 / §11.4.201 / §11.4.224 / §11.4.273 / §1.1
"""
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.path.abspath(os.environ.get("TOOL", os.path.join(HERE, "..", "fk_cascade_probe.py")))

# --------------------------------------------------------------------------------------------------------------------------
# Synthetic dist fixtures. Shaped like the real CodeGraph db/schema.sql + db/index.js (same regex-visible constructs), minus the
# FTS virtual table; each piece is a separate string so a test can swap exactly one construct.
# --------------------------------------------------------------------------------------------------------------------------
NODES = """CREATE TABLE IF NOT EXISTS nodes (
    id TEXT PRIMARY KEY,
    kind TEXT NOT NULL,
    name TEXT NOT NULL,
    qualified_name TEXT NOT NULL,
    file_path TEXT NOT NULL,
    language TEXT NOT NULL,
    start_line INTEGER NOT NULL,
    end_line INTEGER NOT NULL,
    start_column INTEGER NOT NULL,
    end_column INTEGER NOT NULL,
    docstring TEXT,
    is_exported INTEGER DEFAULT 0,
    is_async INTEGER DEFAULT 0,
    is_static INTEGER DEFAULT 0,
    is_abstract INTEGER DEFAULT 0,
    updated_at INTEGER NOT NULL
);
"""
EDGES = """CREATE TABLE IF NOT EXISTS edges (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    source TEXT NOT NULL,
    target TEXT NOT NULL,
    kind TEXT NOT NULL,
    line INTEGER,
    col INTEGER,
    FOREIGN KEY (source) REFERENCES nodes(id) ON DELETE CASCADE,
    FOREIGN KEY (target) REFERENCES nodes(id) ON DELETE CASCADE
);
"""
REFS = """CREATE TABLE IF NOT EXISTS unresolved_refs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    from_node_id TEXT NOT NULL,
    reference_name TEXT NOT NULL,
    reference_kind TEXT NOT NULL,
    line INTEGER NOT NULL,
    col INTEGER NOT NULL,
    file_path TEXT NOT NULL DEFAULT '',
    language TEXT NOT NULL DEFAULT 'unknown',
    status TEXT NOT NULL DEFAULT 'pending',
    name_tail TEXT NOT NULL DEFAULT '',
    FOREIGN KEY (from_node_id) REFERENCES nodes(id) ON DELETE CASCADE
);
"""
FILES = """CREATE TABLE IF NOT EXISTS files (
    path TEXT PRIMARY KEY,
    from_node_id TEXT
);
"""
IDX = """CREATE INDEX IF NOT EXISTS idx_nodes_kind ON nodes(kind);
CREATE INDEX IF NOT EXISTS idx_edges_source_kind ON edges(source, kind);
CREATE INDEX IF NOT EXISTS idx_edges_target_kind ON edges(target, kind);
CREATE UNIQUE INDEX IF NOT EXISTS idx_edges_identity
  ON edges(source, target, kind, IFNULL(line, -1), IFNULL(col, -1));
CREATE INDEX IF NOT EXISTS idx_unresolved_from_node ON unresolved_refs(from_node_id);
CREATE INDEX IF NOT EXISTS idx_unresolved_name ON unresolved_refs(reference_name);
"""
SAFE_PARSE = ["idx_nodes_kind", "idx_unresolved_name"]
SAFE_REF = ["idx_unresolved_name"]
SAFE_EDGE = ["idx_edges_source_kind"]  # edges.source stays served by the never-dropped UNIQUE idx_edges_identity
SMALL = ["--scale-nodes", "2000", "--scale-refs", "4000", "--scale-edges", "3000", "--threshold-s", "1000"]
FK_PAIRS = [("edges", "source"), ("edges", "target"), ("unresolved_refs", "from_node_id")]
NPM_SCRIPT = """#!/bin/sh
echo "$@" >> "$FAKE_NPM_LOG"
if [ "$FAKE_NPM_MODE" = "fail" ]; then echo "npm exploded" >&2; exit 1; fi
if [ "$1" = "root" ] && [ "$2" = "-g" ]; then echo "$FAKE_NPM_ROOT"; exit 0; fi
exit 9
"""
# In-process spy: records every tempfile.mkdtemp() the tool performs, then runs the tool unchanged (exit status passes through).
WRAP = """import os, runpy, sys, tempfile
_orig = tempfile.mkdtemp
def _spy(*a, **k):
    p = _orig(*a, **k)
    with open(os.environ["FKP_REC"], "a") as f:
        f.write(p + "\\n")
    return p
tempfile.mkdtemp = _spy
sys.argv = [os.environ["FKP_TOOL"]] + sys.argv[1:]
runpy.run_path(os.environ["FKP_TOOL"], run_name="__main__")
"""


def bulk_js(parse, ref, edge, extra=""):
    def lst(name, items):
        return "    static %s = [\n%s\n    ];\n" % (name, "\n".join("        '%s'," % i for i in items))

    return ("class DatabaseConnection {\n" + lst("BULK_PARSE_INDEX_NAMES", parse) + lst("BULK_REF_INDEX_NAMES", ref)
            + lst("BULK_EDGE_INDEX_NAMES", edge) + extra + "}\n")


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(text)


def make_dist(root, parse=SAFE_PARSE, ref=SAFE_REF, edge=SAFE_EDGE, schema=None, indexjs=None):
    """Write <root>/lib/dist/db/{schema.sql,index.js}; returns the dist dir (what --dist wants)."""
    dist = os.path.join(root, "lib", "dist")
    write(os.path.join(dist, "db", "schema.sql"), schema if schema is not None else NODES + EDGES + REFS + FILES + IDX)
    if indexjs is not False:
        write(os.path.join(dist, "db", "index.js"), indexjs if indexjs is not None else bulk_js(parse, ref, edge))
    return dist


class Base(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp(prefix="fkp_test_")
        self.tmpdir = os.path.join(self.d, "tmp")
        os.makedirs(self.tmpdir)
        self._n = 0

    def tearDown(self):
        shutil.rmtree(self.d, ignore_errors=True)

    def sub(self):
        self._n += 1
        p = os.path.join(self.d, "s%d" % self._n)
        os.makedirs(p)
        return p

    def dist(self, **kw):
        return make_dist(self.sub(), **kw)

    def env(self, **extra):
        e = dict(os.environ)
        e["TMPDIR"] = self.tmpdir
        e.update(extra)
        return e

    def run_tool(self, *args, tool=None, env=None):
        return subprocess.run([sys.executable, tool or TOOL, *args], capture_output=True, text=True, env=env or self.env())

    def run_ok(self, rc, *args, quiet=True, **kw):
        """Run, assert the exit code, stderr silence and a single parseable JSON doc on stdout; return the doc."""
        p = self.run_tool(*args, **kw)
        self.assertEqual(p.returncode, rc, "exit code: stdout=%r stderr=%r" % (p.stdout[:600], p.stderr[:600]))
        if quiet:
            self.assertEqual(p.stderr, "", "stderr must be silent on a normal/evaluated run")
        doc = json.loads(p.stdout)  # a second concatenated document or stray text would raise here
        self.assertEqual(doc["probe"], "codegraph-fk-cascade")
        return doc

    def assert_measured_shape(self, doc, n=2000, r=4000, e=3000, thr=1000.0):
        m = doc["measured"]
        self.assertEqual(sorted(m), ["parse", "ref"], "measured windows must be exactly parse+ref (edge is informational)")
        for w, v in m.items():
            self.assertEqual(sorted(v), ["hazard", "indexes_present_for_fk", "median_s", "replace_existing_s"], w)
            self.assertEqual(len(v["replace_existing_s"]), 3, "three REPLACE picks per window (early/mid/late node id)")
            self.assertTrue(all(isinstance(t, float) and t > 0 for t in v["replace_existing_s"]), (w, v))
            self.assertEqual(v["median_s"], sorted(v["replace_existing_s"])[1], "median of the three timings")
            self.assertIsInstance(v["hazard"], bool)
        self.assertEqual(doc["scale"], {"nodes": n, "refs": r, "edges": e, "threshold_s": thr})


class Static(Base):
    def test_01_safe_fixture_reports_safe_exit0_with_full_evidence(self):
        dist = self.dist()
        doc = self.run_ok(0, "--dist", dist, "--static-only")
        self.assertEqual(doc["verdict"], "SAFE")
        self.assertEqual(doc["dist"], dist)
        self.assertEqual([(f["table"], f["column"]) for f in doc["fk_children_of_nodes"]], FK_PAIRS)
        self.assertEqual(doc["bulk_lists"], {"BULK_PARSE_INDEX_NAMES": SAFE_PARSE, "BULK_REF_INDEX_NAMES": SAFE_REF,
                                             "BULK_EDGE_INDEX_NAMES": SAFE_EDGE})
        self.assertEqual(sorted(doc["static"]), ["edge", "parse", "ref"])
        for w, v in doc["static"].items():
            self.assertFalse(v["hazard"], w)
            self.assertEqual(v["unserved"], [], w)
            self.assertEqual(len(v["served"]), 3, w)

    def test_02_never_dropped_unique_index_serves_the_fk(self):
        doc = self.run_ok(0, "--dist", self.dist(), "--static-only")
        for w in ("parse", "ref", "edge"):
            served = {(f["table"], f["column"]): f for f in doc["static"][w]["served"]}
            src = served[("edges", "source")]
            self.assertEqual(src["candidates"], ["idx_edges_source_kind", "idx_edges_identity"], w)
            # idx_edges_source_kind IS in the dropped edge list; only the UNIQUE identity index survives -> still served
            self.assertEqual(src["survivors"], ["idx_edges_identity"], w)

    def test_03_hazard_in_ref_window_only(self):
        doc = self.run_ok(1, "--dist", self.dist(ref=SAFE_REF + ["idx_unresolved_from_node"]), "--static-only")
        self.assertEqual(doc["verdict"], "HAZARD")
        self.assertTrue(doc["static"]["ref"]["hazard"])
        self.assertFalse(doc["static"]["parse"]["hazard"], "the parse list does not drop it, so the parse window is clean")
        self.assertEqual(doc["static"]["ref"]["unserved"], [
            {"table": "unresolved_refs", "column": "from_node_id", "candidates": ["idx_unresolved_from_node"], "survivors": []}])

    def test_04_hazard_in_parse_window_only(self):
        doc = self.run_ok(1, "--dist", self.dist(parse=SAFE_PARSE + ["idx_unresolved_from_node"]), "--static-only")
        self.assertEqual(doc["verdict"], "HAZARD")
        self.assertTrue(doc["static"]["parse"]["hazard"])
        self.assertFalse(doc["static"]["ref"]["hazard"])

    def test_05_edge_list_hazard_reaches_parse_ref_and_edge_windows(self):
        # the parse and ref windows both ENTER the edge window, so an edge-list drop of the only edges.target index hits all three
        doc = self.run_ok(1, "--dist", self.dist(edge=SAFE_EDGE + ["idx_edges_target_kind"]), "--static-only")
        self.assertEqual(doc["verdict"], "HAZARD")
        for w in ("parse", "ref", "edge"):
            self.assertTrue(doc["static"][w]["hazard"], w)
            self.assertEqual([(f["table"], f["column"]) for f in doc["static"][w]["unserved"]], [("edges", "target")], w)

    def test_06_fk_column_must_be_the_leftmost_index_column(self):
        idx = IDX.replace("idx_unresolved_from_node ON unresolved_refs(from_node_id)",
                          "idx_unresolved_from_node ON unresolved_refs(reference_name, from_node_id)")
        dist = self.dist(schema=NODES + EDGES + REFS + FILES + idx)
        doc = self.run_ok(1, "--dist", dist, "--static-only")
        self.assertEqual([(f["table"], f["column"], f["candidates"]) for f in doc["static"]["parse"]["unserved"]],
                         [("unresolved_refs", "from_node_id", [])],
                         "an index with the FK column in second position does not serve it (not even a candidate)")

    def test_07_index_must_be_on_the_fk_table(self):
        # the only from_node_id index is on `files`, which is not the FK-child table
        idx = IDX.replace("idx_unresolved_from_node ON unresolved_refs(from_node_id)",
                          "idx_unresolved_from_node ON files(from_node_id)")
        doc = self.run_ok(1, "--dist", self.dist(schema=NODES + EDGES + REFS + FILES + idx), "--static-only")
        self.assertEqual([(f["table"], f["column"]) for f in doc["static"]["ref"]["unserved"]], [("unresolved_refs", "from_node_id")])

    def test_08_order_suffix_on_the_leftmost_column_is_ignored(self):
        idx = IDX.replace("unresolved_refs(from_node_id)", "unresolved_refs(from_node_id DESC)")
        doc = self.run_ok(0, "--dist", self.dist(schema=NODES + EDGES + REFS + FILES + idx), "--static-only")
        self.assertEqual(doc["verdict"], "SAFE")

    def test_09a_lowercase_and_spaced_foreign_key_clause_is_detected(self):
        refs = REFS.replace("FOREIGN KEY (from_node_id) REFERENCES nodes(id)", "foreign key ( from_node_id ) references nodes ( id )")
        self.assertNotEqual(refs, REFS, "fixture edit applied")
        dist = self.dist(schema=NODES + EDGES + refs + FILES + IDX, ref=SAFE_REF + ["idx_unresolved_from_node"])
        doc = self.run_ok(1, "--dist", dist, "--static-only")
        self.assertIn(("unresolved_refs", "from_node_id"), [(f["table"], f["column"]) for f in doc["fk_children_of_nodes"]])
        self.assertTrue(doc["static"]["ref"]["hazard"])

    def test_09b_lowercase_index_statement_is_parsed(self):
        idx = IDX.replace("CREATE INDEX IF NOT EXISTS idx_unresolved_from_node ON unresolved_refs(from_node_id);",
                          "create index if not exists idx_unresolved_from_node on unresolved_refs ( from_node_id );")
        self.assertNotEqual(idx, IDX, "fixture edit applied")
        doc = self.run_ok(0, "--dist", self.dist(schema=NODES + EDGES + REFS + FILES + idx), "--static-only")
        self.assertEqual(doc["verdict"], "SAFE", "the lowercase index must still be seen as serving from_node_id")

    def test_10_a_list_that_is_not_one_of_the_three_windows_changes_nothing(self):
        decoy = "    static BULK_DECOY_NAMES = [\n        'idx_unresolved_from_node',\n        'idx_edges_target_kind',\n    ];\n"
        dist = self.dist(indexjs=bulk_js(SAFE_PARSE, SAFE_REF, SAFE_EDGE, extra=decoy))
        doc = self.run_ok(0, "--dist", dist, "--static-only")
        self.assertEqual(doc["verdict"], "SAFE")
        self.assertIn("BULK_DECOY_NAMES", doc["bulk_lists"], "echoed as evidence, but never used as a window")

    def test_11_static_only_skips_the_measured_layer_entirely(self):
        doc = self.run_ok(0, "--dist", self.dist(), "--static-only")
        self.assertNotIn("measured", doc)
        self.assertNotIn("scale", doc)
        self.assertEqual(os.listdir(self.tmpdir), [], "no scratch dir may be created by a static-only run")

    def test_12_output_is_deterministic_and_json_out_equals_stdout(self):
        dist = self.dist(ref=SAFE_REF + ["idx_unresolved_from_node"])
        out = os.path.join(self.d, "evidence.json")
        a = self.run_tool("--dist", dist, "--static-only", "--json-out", out)
        b = self.run_tool("--dist", dist, "--static-only")
        self.assertEqual((a.returncode, b.returncode), (1, 1))
        self.assertEqual(a.stdout, b.stdout, "static-only output must be byte-identical across runs (§11.4.50)")
        with open(out, encoding="utf-8") as f:
            self.assertEqual(f.read(), a.stdout, "--json-out persists exactly what stdout printed")
        self.assertTrue(a.stdout.endswith("}\n"))


class CannotEvaluate(Base):
    def assert_cannot(self, doc, needle):
        self.assertEqual(doc["verdict"], "CANNOT_EVALUATE")
        self.assertIn(needle, doc["error"])

    def test_20_dist_directory_missing(self):
        gone = os.path.join(self.d, "nope", "dist")
        doc = self.run_ok(2, "--dist", gone, "--static-only")
        self.assert_cannot(doc, "cannot read target files")
        self.assertEqual(doc["dist"], gone, "dist is echoed even when the target cannot be read")

    def test_21_index_js_missing(self):
        doc = self.run_ok(2, "--dist", self.dist(indexjs=False), "--static-only")
        self.assert_cannot(doc, "cannot read target files")

    def test_22_bulk_list_absent(self):
        js = bulk_js(SAFE_PARSE, SAFE_REF, SAFE_EDGE).replace("BULK_REF_INDEX_NAMES", "BULK_RENAMED_NAMES")
        doc = self.run_ok(2, "--dist", self.dist(indexjs=js), "--static-only")
        self.assert_cannot(doc, "BULK_REF_INDEX_NAMES not found/empty (upstream shape changed)")

    def test_23_bulk_list_empty(self):
        doc = self.run_ok(2, "--dist", self.dist(indexjs=bulk_js(SAFE_PARSE, SAFE_REF, [])), "--static-only")
        self.assert_cannot(doc, "BULK_EDGE_INDEX_NAMES not found/empty")

    def test_24_schema_without_any_fk_to_nodes(self):
        schema = (NODES + EDGES + REFS + FILES + IDX).replace("REFERENCES nodes(id)", "REFERENCES elsewhere(id)")
        self.assertNotIn("REFERENCES nodes", schema)
        doc = self.run_ok(2, "--dist", self.dist(schema=schema), "--static-only")
        self.assert_cannot(doc, "no FOREIGN KEY ... REFERENCES nodes(id) found")

    def fake_npm(self, mode="ok", root=None):
        """Install a fake `npm` into a bin dir; return (env, args_log_path). Real npm and the real global install are never used."""
        bindir, log = self.sub(), os.path.join(self.d, "npm_args.log")
        p = os.path.join(bindir, "npm")
        write(p, NPM_SCRIPT)
        os.chmod(p, os.stat(p).st_mode | stat.S_IXUSR)
        env = self.env(PATH=bindir + os.pathsep + os.environ.get("PATH", ""), FAKE_NPM_MODE=mode, FAKE_NPM_LOG=log,
                       FAKE_NPM_ROOT=root or "")
        return env, log

    def test_25_npm_root_fails(self):
        env, log = self.fake_npm(mode="fail")
        p = self.run_tool("--static-only", env=env)
        self.assertEqual(p.returncode, 2)
        self.assertIn("npm exploded", p.stderr, "npm's own stderr is not captured by the probe, it passes straight through")
        doc = json.loads(p.stdout)
        self.assert_cannot(doc, "npm root -g failed")
        self.assertNotIn("dist", doc)
        with open(log, encoding="utf-8") as f:
            self.assertEqual(f.read().strip(), "root -g", "control: the fake npm WAS invoked, with exactly `root -g`")

    def test_26_npm_not_on_path(self):
        empty = self.sub()
        doc = self.run_ok(2, "--static-only", env=self.env(PATH=empty))
        self.assert_cannot(doc, "npm root -g failed")

    def test_27_no_codegraph_install_under_the_npm_root(self):
        root = self.sub()
        env, _ = self.fake_npm(root=root)
        doc = self.run_ok(2, "--static-only", env=env)
        self.assert_cannot(doc, "no @colbymchenry/codegraph install under")

    def platform_base(self, root):
        return os.path.join(root, "@colbymchenry", "codegraph", "node_modules", "@colbymchenry")

    def test_28_no_platform_package_carries_db_index_js(self):
        root = self.sub()
        os.makedirs(os.path.join(self.platform_base(root), "codegraph-linux-x64", "lib", "dist", "db"))  # dir, but no index.js
        env, _ = self.fake_npm(root=root)
        doc = self.run_ok(2, "--static-only", env=env)
        self.assert_cannot(doc, "no platform package with lib/dist/db/index.js")

    def test_29_default_dist_resolution_skips_incomplete_packages_and_uses_the_first_complete_one(self):
        root = self.sub()
        base = self.platform_base(root)
        os.makedirs(os.path.join(base, "a-incomplete", "lib", "dist", "db"))
        good = make_dist(os.path.join(base, "b-good"))
        make_dist(os.path.join(base, "c-also-good"), ref=SAFE_REF + ["idx_unresolved_from_node"])  # would flip the verdict if chosen
        env, log = self.fake_npm(root=root)
        doc = self.run_ok(0, "--static-only", env=env)
        self.assertEqual(doc["dist"], good)
        self.assertEqual(doc["verdict"], "SAFE")
        with open(log, encoding="utf-8") as f:
            self.assertEqual(f.read().strip(), "root -g")

    def test_30_explicit_dist_never_consults_npm(self):
        env, log = self.fake_npm(mode="fail")
        doc = self.run_ok(0, "--dist", self.dist(), "--static-only", env=env)
        self.assertEqual(doc["verdict"], "SAFE")
        self.assertFalse(os.path.exists(log), "npm must not run at all when --dist is given")

    def test_31_json_out_is_written_for_an_unevaluable_target_too(self):
        out = os.path.join(self.d, "evidence.json")
        p = self.run_tool("--dist", os.path.join(self.d, "gone"), "--static-only", "--json-out", out)
        self.assertEqual(p.returncode, 2)
        with open(out, encoding="utf-8") as f:
            self.assertEqual(f.read(), p.stdout)
        self.assertEqual(json.loads(p.stdout)["verdict"], "CANNOT_EVALUATE")


class Measured(Base):
    def test_40_safe_target_measured_layer_evidence(self):
        doc = self.run_ok(0, "--dist", self.dist(), *SMALL)
        self.assertEqual(doc["verdict"], "SAFE")
        self.assert_measured_shape(doc)
        for w in ("parse", "ref"):
            m = doc["measured"][w]
            self.assertEqual(m["indexes_present_for_fk"], ["idx_edges_identity", "idx_edges_target_kind", "idx_unresolved_from_node"], w)
            self.assertFalse(m["hazard"], w)
        self.assertEqual(os.listdir(self.tmpdir), [], "temp scratch dir removed after a normal run")

    def test_41_hazard_target_is_missing_the_dropped_index_in_the_measured_ref_window(self):
        doc = self.run_ok(1, "--dist", self.dist(ref=SAFE_REF + ["idx_unresolved_from_node"]), *SMALL)
        self.assertEqual(doc["verdict"], "HAZARD")
        self.assert_measured_shape(doc)
        self.assertEqual(doc["measured"]["parse"]["indexes_present_for_fk"],
                         ["idx_edges_identity", "idx_edges_target_kind", "idx_unresolved_from_node"])
        self.assertEqual(doc["measured"]["ref"]["indexes_present_for_fk"], ["idx_edges_identity", "idx_edges_target_kind"],
                         "the measured ref window must recreate exactly the indexes that SURVIVE that window")

    def test_42_negative_threshold_makes_the_measured_layer_alone_raise_hazard(self):
        doc = self.run_ok(1, "--dist", self.dist(), *SMALL[:-1], "-1")
        self.assertEqual(doc["verdict"], "HAZARD")
        for w in ("parse", "ref"):
            self.assertTrue(doc["measured"][w]["hazard"], w)
        for w in ("parse", "ref", "edge"):
            self.assertFalse(doc["static"][w]["hazard"], "static layer stays clean; only the measured layer flags: " + w)

    def test_43_huge_threshold_clears_measured_but_a_static_hazard_still_fails(self):
        doc = self.run_ok(1, "--dist", self.dist(ref=SAFE_REF + ["idx_unresolved_from_node"]), *SMALL)
        for w in ("parse", "ref"):
            self.assertFalse(doc["measured"][w]["hazard"], w)
        self.assertTrue(doc["static"]["ref"]["hazard"])
        self.assertEqual(doc["verdict"], "HAZARD", "verdict is static OR measured; a clean measured layer must not mask a static hazard")

    def test_44_scale_and_default_threshold_are_echoed(self):
        doc = self.run_tool("--dist", self.dist(), "--scale-nodes", "500", "--scale-refs", "700", "--scale-edges", "900")
        d = json.loads(doc.stdout)
        self.assertEqual(d["scale"], {"nodes": 500, "refs": 700, "edges": 900, "threshold_s": 0.05})
        self.assertEqual(len(d["measured"]["parse"]["replace_existing_s"]), 3)

    def test_45_unknown_not_null_column_fails_closed_measured_but_not_static_only(self):
        nodes = NODES.replace("docstring TEXT,", "docstring TEXT,\n    mystery TEXT NOT NULL,")
        self.assertNotEqual(nodes, NODES)
        dist = self.dist(schema=nodes + EDGES + REFS + FILES + IDX)
        static = self.run_ok(0, "--dist", dist, "--static-only")
        self.assertEqual(static["verdict"], "SAFE", "static layer does not build a DB, so the shape guard is not consulted")
        doc = self.run_ok(2, "--dist", dist, *SMALL)
        self.assertEqual(doc["verdict"], "CANNOT_EVALUATE")
        self.assertIn("nodes.mystery is NOT NULL without default and unknown to the probe (schema changed)", doc["error"],
                      "must fail via the probe's OWN shape guard, not by a downstream IntegrityError")

    def test_46_shape_guard_exempts_defaulted_and_primary_key_columns(self):
        # status/name_tail are NOT NULL DEFAULT (in the base refs table); make the primary keys explicit NOT NULL too
        nodes = NODES.replace("id TEXT PRIMARY KEY,", "id TEXT NOT NULL PRIMARY KEY,")
        edges = EDGES.replace("id INTEGER PRIMARY KEY AUTOINCREMENT,", "id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,")
        refs = REFS.replace("id INTEGER PRIMARY KEY AUTOINCREMENT,", "id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,")
        self.assertTrue(nodes != NODES and edges != EDGES and refs != REFS)
        doc = self.run_ok(0, "--dist", self.dist(schema=nodes + edges + refs + FILES + IDX), *SMALL)
        self.assertEqual(doc["verdict"], "SAFE")
        self.assert_measured_shape(doc)

    def test_47_required_table_missing_after_schema_load(self):
        # no unresolved_refs table (and no index on it): edges FKs remain, so the static layer evaluates fine
        idx = "\n".join(l for l in IDX.splitlines() if "unresolved_refs" not in l) + "\n"
        dist = self.dist(schema=NODES + EDGES + FILES + idx, ref=["idx_edges_source_kind"], parse=SAFE_PARSE[:1])
        self.assertEqual(self.run_ok(0, "--dist", dist, "--static-only")["verdict"], "SAFE")
        doc = self.run_ok(2, "--dist", dist, *SMALL)
        self.assertIn("table unresolved_refs missing after schema load", doc["error"])

    def test_48_unexpected_error_in_the_measured_layer_fails_closed_never_safe(self):
        dist = self.dist(schema=NODES + EDGES + REFS + FILES + IDX + "CREATE TABL oops;\n")
        self.assertEqual(self.run_ok(0, "--dist", dist, "--static-only")["verdict"], "SAFE")
        doc = self.run_ok(2, "--dist", dist, *SMALL)
        self.assertEqual(doc["verdict"], "CANNOT_EVALUATE")
        self.assertTrue(doc["error"].startswith("OperationalError:"), doc["error"])
        self.assertNotIn("measured", doc)

    def test_49_unusable_work_dir_fails_closed(self):
        doc = self.run_ok(2, "--dist", self.dist(), "--work-dir", os.path.join(self.d, "does", "not", "exist"), *SMALL)
        self.assertEqual(doc["verdict"], "CANNOT_EVALUATE")
        self.assertTrue(doc["error"].startswith("OperationalError:"), doc["error"])

    def test_50_triggers_are_dropped_before_the_bulk_inserts(self):
        # a trigger that would fail every INSERT INTO nodes (as the FTS sync triggers are absent in the real bulk window)
        poison = "CREATE TRIGGER poison AFTER INSERT ON nodes BEGIN INSERT INTO no_such_table VALUES (1); END;\n"
        doc = self.run_ok(0, "--dist", self.dist(schema=NODES + EDGES + REFS + FILES + IDX + poison), *SMALL)
        self.assertEqual(doc["verdict"], "SAFE")
        self.assert_measured_shape(doc)

    def test_51_work_dir_is_kept_scratch_db_is_replaced_and_removed(self):
        wd = self.sub()
        junk = os.path.join(wd, "fk_probe.db")
        write(junk, "this is not a sqlite database\n")
        doc = self.run_ok(0, "--dist", self.dist(), "--work-dir", wd, *SMALL)
        self.assertEqual(doc["verdict"], "SAFE", "a pre-existing (junk) fk_probe.db must be replaced, not opened")
        self.assertTrue(os.path.isdir(wd), "a caller-supplied --work-dir must never be deleted")
        self.assertEqual(os.listdir(wd), [], "the scratch DB fk_probe.db is removed at the end of a successful run")
        self.assertEqual(os.listdir(self.tmpdir), [], "no temp dir is created when --work-dir is given")

    def run_spied(self, *args):
        rec = os.path.join(self.sub(), "mkdtemp.rec")  # one record file per run
        p = subprocess.run([sys.executable, "-c", WRAP, *args], capture_output=True, text=True,
                           env=self.env(FKP_REC=rec, FKP_TOOL=TOOL))
        made = []
        if os.path.exists(rec):
            with open(rec, encoding="utf-8") as f:
                made = [l for l in f.read().splitlines() if l]
        return p, made

    def test_52_temp_scratch_dir_is_created_under_tmpdir_and_removed_on_success_and_failure(self):
        ok, made = self.run_spied("--dist", self.dist(), *SMALL)
        self.assertEqual(ok.returncode, 0, ok.stderr)
        self.assertEqual(len(made), 1, "control: the spy saw exactly one mkdtemp (the instrument can see the scratch dir)")
        self.assertEqual(os.path.dirname(made[0]), self.tmpdir)
        self.assertTrue(os.path.basename(made[0]).startswith("cg_fk_probe_"))
        self.assertFalse(os.path.exists(made[0]), "scratch dir must be removed after a successful run")
        nodes = NODES.replace("docstring TEXT,", "docstring TEXT,\n    mystery TEXT NOT NULL,")
        bad, made2 = self.run_spied("--dist", self.dist(schema=nodes + EDGES + REFS + FILES + IDX), *SMALL)
        self.assertEqual(bad.returncode, 2)
        self.assertEqual(len(made2), 1)
        self.assertFalse(os.path.exists(made2[0]), "scratch dir must be removed even when the measured layer fails")
        wd = self.sub()
        keep, made3 = self.run_spied("--dist", self.dist(), "--work-dir", wd, *SMALL)
        self.assertEqual((keep.returncode, made3), (0, []), "with --work-dir the tool must not create a temp dir at all")

    def test_53_replace_with_foreign_keys_on_is_measurably_slower_when_the_child_index_is_missing(self):
        big = ["--scale-nodes", "10000", "--scale-refs", "150000", "--scale-edges", "10000", "--threshold-s", "1000",
               "--work-dir", self.sub()]
        hz = self.run_ok(1, "--dist", self.dist(ref=SAFE_REF + ["idx_unresolved_from_node"]), *big)
        sf = self.run_ok(0, "--dist", self.dist(), *big)
        self.assert_measured_shape(hz, 10000, 150000, 10000)
        self.assert_measured_shape(sf, 10000, 150000, 10000)
        hp, hr = hz["measured"]["parse"]["median_s"], hz["measured"]["ref"]["median_s"]
        sr = sf["measured"]["ref"]["median_s"]
        # ratios only (machine speed cancels): the hazard ref window full-scans unresolved_refs; the same run's parse window
        # (FK index present) is the internal control, the safe target's ref window the external control. Observed at this scale:
        # hazard/indexed-parse 61-95x, hazard/safe-ref 156-325x (6 runs, host load average ~44); the assertion floor is 10x.
        self.assertGreater(hr, 10 * hp, "hazard ref window %.6fs vs same-run indexed parse window %.6fs" % (hr, hp))
        self.assertGreater(hr, 10 * sr, "hazard ref window %.6fs vs safe target ref window %.6fs" % (hr, sr))


class Cli(Base):
    def test_60_help_lists_every_flag_and_exits_zero(self):
        p = self.run_tool("--help")
        self.assertEqual(p.returncode, 0)
        for flag in ("--dist", "--threshold-s", "--scale-nodes", "--scale-refs", "--scale-edges", "--static-only", "--json-out",
                     "--work-dir"):
            self.assertIn(flag, p.stdout)

    def test_61_unknown_flag_is_a_usage_error_with_no_json_document(self):
        p = self.run_tool("--no-such-flag")
        self.assertEqual(p.returncode, 2)
        self.assertEqual(p.stdout, "")
        self.assertIn("unrecognized arguments", p.stderr)

    def test_62_non_numeric_scale_is_a_usage_error(self):
        p = self.run_tool("--dist", self.dist(), "--scale-nodes", "many")
        self.assertEqual(p.returncode, 2)
        self.assertEqual(p.stdout, "")
        self.assertIn("invalid int value", p.stderr)


if __name__ == "__main__":
    unittest.main()
