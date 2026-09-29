#!/usr/bin/env python3
"""test_owed_report.py — executing tests for owed_report.py (§11.4.224 test-first; the tool was written AFTER this file).

Purpose      Prove the generated owed-report (a) discovers every governed indexing tool and runner patch, (b) attributes a test
             only on a bounded, exact reference (never a substring — control needles per §11.4.273), (c) attributes a guide only
             to docs/scripts/<name>.md, (d) is informational by default and blocking under --strict, (e) REFUSES (exit 3) when
             it cannot see any tool instead of reporting "nothing owed" (§11.4.201(6) false-null), (f) is deterministic.
Usage        python3 test_owed_report.py     (TOOL=<path> selects the code under test; used by the mutation harness)
Inputs       TOOL env (default: ../owed_report.py next to this file)
Outputs      unittest result; exit 1 on any failure
Side effects creates and removes temp dirs only
Dependencies python3 (stdlib only)
Cross-refs   owed_report.py, test_owed_report_mutations.sh, docs/scripts/owed_report.md, constitution §11.4.18 / §11.4.201 / §11.4.224 / §11.4.273
"""
import json, os, subprocess, sys, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.environ.get("TOOL", os.path.join(HERE, "..", "owed_report.py"))


def w(root, rel, text="x\n"):
    p = os.path.join(root, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w", encoding="utf-8") as f:
        f.write(text)


def run(root, *extra):
    return subprocess.run([sys.executable, TOOL, "--root", root, *extra], capture_output=True, text=True)


def report(root, *extra):
    r = run(root, "--json", *extra)
    assert r.returncode in (0, 1), (r.returncode, r.stdout, r.stderr)
    return json.loads(r.stdout)


def by_path(rep):
    return {t["path"]: t for t in rep["tools"]}


class Fx:
    """Fixture constitution tree with a known tested/untested/guided/unguided mix."""

    def __init__(self, d):
        self.d = d
        cg = "scripts/codegraph"
        w(d, cg + "/a_tool.sh"); w(d, cg + "/b_tool.py"); w(d, cg + "/c_tool.js"); w(d, cg + "/d_tool.sh")
        w(d, cg + "/runner_patches/__init__.py"); w(d, cg + "/runner_patches/common.py")
        w(d, cg + "/runner_patches/p1.py"); w(d, cg + "/runner_patches/p2.py")
        w(d, cg + "/scope.example.yaml"); w(d, cg + "/scope_baseline.txt")
        w(d, cg + "/__pycache__/junk.py")
        w(d, "scripts/lumen/l_tool.py"); w(d, "scripts/lumen/l_two.sh")
        # tests: a_tool by NAME, b_tool by CONTENT (exact filename), p1 by CONTENT (patch id), l_tool by NAME under lumen/tests
        w(d, cg + "/tests/test_a_tool.sh", "echo run\n")
        w(d, cg + "/tests/misc.py", "subprocess.run(['python3', 'scripts/codegraph/b_tool.py'])\nimport runner_patches\nids = ['p1']\n")
        w(d, "scripts/lumen/tests/test_l_tool.py", "pass\n")
        # decoys that MUST NOT count: substrings / different tools / fixtures / backup file names
        w(d, cg + "/tests/decoy.sh", "xc_tool.js  c_tool.js.bak  c_tool.jsx  p11  p2x  my_d_tool.sh\n")
        w(d, cg + "/tests/fixtures/f.sh", "d_tool.sh p2 c_tool.js\n")          # a real test-extension file, but under fixtures/ -> must not count
        w(d, cg + "/tests/test_c_tool_extra.sh", "echo unrelated\n")               # name merely CONTAINS the stem -> must not count
        w(d, cg + "/tests/test_xd_tool.sh", "echo unrelated\n")                    # different tool whose name ends with the stem
        # guides: a_tool + l_tool have one; the stem-only name must be honoured for .md (a_tool.md)
        w(d, "docs/scripts/a_tool.md"); w(d, "docs/scripts/l_tool.md"); w(d, "docs/scripts/p1.md")


class T(unittest.TestCase):
    def setUp(self):
        self.d = tempfile.mkdtemp(prefix="owed_test_"); Fx(self.d)

    def tearDown(self):
        subprocess.run(["rm", "-rf", self.d])

    def test_01_discovers_exactly_the_governed_tools(self):
        got = sorted(by_path(report(self.d)))
        want = sorted(["scripts/codegraph/a_tool.sh", "scripts/codegraph/b_tool.py", "scripts/codegraph/c_tool.js",
                       "scripts/codegraph/d_tool.sh", "scripts/codegraph/runner_patches/p1.py",
                       "scripts/codegraph/runner_patches/p2.py", "scripts/lumen/l_tool.py", "scripts/lumen/l_two.sh"])
        self.assertEqual(got, want, "tests/, __pycache__, __init__/common, .yaml/.txt data files must not be listed as tools")

    def test_02_test_by_name_and_by_exact_content_reference(self):
        t = by_path(report(self.d))
        self.assertTrue(t["scripts/codegraph/a_tool.sh"]["tested"], "test_<stem>.<ext> by name")
        self.assertTrue(t["scripts/codegraph/b_tool.py"]["tested"], "exact filename mentioned in a test file")
        self.assertTrue(t["scripts/codegraph/runner_patches/p1.py"]["tested"], "patch id token in a test file")
        self.assertTrue(t["scripts/lumen/l_tool.py"]["tested"], "lumen tests dir is searched too")

    def test_03_substring_and_fixture_mentions_do_not_count_as_tests(self):
        t = by_path(report(self.d))
        self.assertFalse(t["scripts/codegraph/c_tool.js"]["tested"], "xc_tool.js / c_tool.js.bak / c_tool.jsx / fixtures are decoys")
        self.assertFalse(t["scripts/codegraph/d_tool.sh"]["tested"], "my_d_tool.sh is not d_tool.sh; fixtures/ never count")
        self.assertFalse(t["scripts/codegraph/runner_patches/p2.py"]["tested"], "p2x and a fixtures-only p2 do not count")
        self.assertEqual(t["scripts/codegraph/runner_patches/p1.py"]["tests"], ["scripts/codegraph/tests/misc.py"], "p11 in decoy.sh must not add a reference")

    def test_04_guide_attribution(self):
        t = by_path(report(self.d))
        self.assertEqual(t["scripts/codegraph/a_tool.sh"]["guide"], "docs/scripts/a_tool.md")
        self.assertEqual(t["scripts/codegraph/runner_patches/p1.py"]["guide"], "docs/scripts/p1.md")
        self.assertIsNone(t["scripts/codegraph/b_tool.py"]["guide"])
        self.assertIsNone(t["scripts/lumen/l_two.sh"]["guide"])

    def test_05_owed_lists_are_exact(self):
        t = by_path(report(self.d))
        self.assertEqual(t["scripts/codegraph/a_tool.sh"]["owed"], [])
        self.assertEqual(t["scripts/codegraph/b_tool.py"]["owed"], ["guide"])
        self.assertEqual(t["scripts/codegraph/d_tool.sh"]["owed"], ["tests", "guide"])
        self.assertEqual(t["scripts/codegraph/runner_patches/p2.py"]["owed"], ["tests", "guide"])

    def test_06_default_is_informational_strict_blocks(self):
        r = run(self.d); self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertIn("scripts/codegraph/d_tool.sh", r.stdout)
        s = run(self.d, "--strict"); self.assertEqual(s.returncode, 1, s.stdout + s.stderr)

    def test_07_strict_passes_when_nothing_is_owed(self):
        for rel in ("scripts/codegraph/b_tool.py", "scripts/codegraph/c_tool.js", "scripts/codegraph/d_tool.sh", "scripts/codegraph/runner_patches/p2.py", "scripts/lumen/l_two.sh"):
            stem = os.path.splitext(os.path.basename(rel))[0]
            w(self.d, "docs/scripts/%s.md" % stem)
            w(self.d, ("scripts/lumen/tests/test_%s.sh" if rel.startswith("scripts/lumen/") else "scripts/codegraph/tests/test_%s.sh") % stem)
        w(self.d, "docs/scripts/b_tool.md")
        s = run(self.d, "--strict"); self.assertEqual(s.returncode, 0, s.stdout + s.stderr)
        self.assertEqual(report(self.d)["owed_count"], 0)

    def test_08_blind_root_refuses_instead_of_reporting_nothing_owed(self):
        empty = tempfile.mkdtemp(prefix="owed_empty_")
        try:
            r = run(empty); self.assertEqual(r.returncode, 3, r.stdout + r.stderr); self.assertIn("REFUSED", r.stderr)
            self.assertNotIn("owed_count", r.stdout)
        finally:
            subprocess.run(["rm", "-rf", empty])

    def test_09_missing_root_refuses(self):
        r = run(os.path.join(self.d, "nope")); self.assertEqual(r.returncode, 3, r.stdout + r.stderr); self.assertIn("REFUSED", r.stderr)

    def test_10_deterministic_output(self):
        a = run(self.d, "--json").stdout; b = run(self.d, "--json").stdout
        self.assertEqual(a, b); self.assertEqual(run(self.d).stdout, run(self.d).stdout)

    def test_11_pycache_pyc_and_data_files_never_listed(self):
        w(self.d, "scripts/codegraph/tests/__pycache__/a_tool.cpython-311.pyc")
        paths = " ".join(by_path(report(self.d)))
        for bad in ("__pycache__", ".pyc", ".yaml", ".txt", "__init__", "common.py"):
            self.assertNotIn(bad, paths)

    def test_12_text_report_names_every_owed_tool_and_its_missing_parts(self):
        out = run(self.d).stdout
        line = [l for l in out.splitlines() if "d_tool.sh" in l]
        self.assertTrue(line and "tests" in line[0] and "guide" in line[0], out)


if __name__ == "__main__":
    unittest.main(verbosity=2)
