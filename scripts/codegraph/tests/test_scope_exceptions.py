#!/usr/bin/env python3
"""test_scope_exceptions.py — executing tests for the scope-exceptions mechanism in codegraph_safe_helper.py's cmd_scope.

Purpose      Prove (a) RED: absent an exceptions file, a known-legitimate file whose basename merely
             CONTAINS the substring "secret" (e.g. a secret-SCANNING tool, an AOSP crypto-HAL source
             file) still FAILs the secret_named/secrets_dir scope classes exactly as the baseline
             heuristic is designed to (§11.4.201 — the false-positive this mechanism exists to narrow,
             reproduced first, per §11.4.224 test-first); (b) GREEN: naming that EXACT path in an
             exceptions file makes the scope check PASS for it; (c) a DIFFERENT secret-shaped path NOT
             listed in the exceptions file still correctly FAILs (excepting one path never broadens to
             others — the negative control proving this is narrowing, not loosening); (d) an exceptions
             entry naming a class outside ALLOWED_EXCEPTION_CLASSES (env_file/keystore/signing_key/
             service_account — the credential-CONTENT classes, §11.4.10) is a HARD ERROR, never silently
             accepted; (e) an exceptions entry using a glob/pattern instead of an exact path is a HARD
             ERROR; (f) a typo'd/non-matching exact path in the exceptions file changes nothing — the
             underlying FAIL persists (fail-closed, not fail-open); (g) a missing/absent exceptions file
             is fully backward-compatible with the pre-existing 2-arg `cmd_scope` call (empty exceptions,
             the strictest posture, never an error).
Usage        python3 test_scope_exceptions.py     (TOOL=<path> selects the code under test; used by the
             mutation harness)
Inputs       TOOL env (default: ../codegraph_safe_helper.py next to this file)
Outputs      unittest result; exit 1 on any failure
Side effects creates and removes temp dirs only
Dependencies python3 (stdlib only: sqlite3, subprocess, tempfile, unittest)
Cross-refs   codegraph_safe_helper.py (load_exceptions/cmd_scope), scope_baseline.txt,
             scope_exceptions.txt, docs/scripts/codegraph_safe.md,
             constitution §11.4.6 / §11.4.10 / §11.4.18 / §11.4.201 / §11.4.224 / §11.4.273
"""
import os
import sqlite3
import subprocess
import sys
import tempfile
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
TOOL = os.environ.get("TOOL", os.path.join(HERE, "..", "codegraph_safe_helper.py"))

BASELINE = """\
env_file      secret   seg:.env
secrets_dir   secret   dir:secrets
secret_named  secret   segglob:*secret*
keystore      secret   segglob:*.jks
"""


def _mkfile(root, rel):
    p = os.path.join(root, rel)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w", encoding="utf-8") as f:
        f.write("x\n")
    return p


def build_fixture(files):
    """A minimal project: real files on disk (so the control-needle check per
    §11.4.273 can resolve at least one row to a real file) + a matching
    .codegraph/codegraph.db `files` table + a scope_baseline.txt beside it.
    Returns (project_dir, baseline_path)."""
    root = tempfile.mkdtemp(prefix="t_scope_exc_")
    for rel in files:
        _mkfile(root, rel)
    cg = os.path.join(root, ".codegraph")
    os.makedirs(cg, exist_ok=True)
    db = os.path.join(cg, "codegraph.db")
    con = sqlite3.connect(db)
    con.execute("create table files (path text)")
    con.executemany("insert into files (path) values (?)", [(p,) for p in files])
    con.commit()
    con.close()
    baseline = os.path.join(root, "scope_baseline.txt")
    with open(baseline, "w", encoding="utf-8") as f:
        f.write(BASELINE)
    return root, baseline


def run_scope(root, baseline, exceptions=None):
    args = [sys.executable, TOOL, "scope", root, baseline]
    if exceptions is not None:
        args.append(exceptions)
    r = subprocess.run(args, capture_output=True, text=True)
    return r.returncode, r.stdout, r.stderr


def write_exceptions(root, lines):
    path = os.path.join(root, "scope_exceptions.txt")
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")
    return path


NEEDLE_FILES = ["src/main.c", "src/util.py"]  # ordinary, never matches any secret-ish rule


class T(unittest.TestCase):
    def test_01_red_no_exceptions_file_legit_tool_still_fails(self):
        """Reproduces the real defect: secret_scan.py-shaped path FAILs with no exceptions given at all."""
        files = NEEDLE_FILES + ["tools/secret_scan.py"]
        root, baseline = build_fixture(files)
        rc, out, err = run_scope(root, baseline)  # no 3rd arg at all — old 2-arg call
        self.assertEqual(rc, 1, (out, err))
        self.assertIn("SCOPE_CLASS secret_named kind=secret count=1 FAIL", out)
        self.assertIn("SCOPE_HIT secret_named tools/secret_scan.py", out)
        self.assertIn("SCOPE FAIL", out)

    def test_02_red_absent_exceptions_file_path_behaves_same_as_no_arg(self):
        """Passing a 3rd-arg path that does not exist on disk is NOT an error — empty exceptions, same as (1)."""
        files = NEEDLE_FILES + ["tools/secret_scan.py"]
        root, baseline = build_fixture(files)
        rc, out, err = run_scope(root, baseline, os.path.join(root, "does_not_exist.txt"))
        self.assertEqual(rc, 1, (out, err))
        self.assertIn("SCOPE_CLASS secret_named kind=secret count=1 FAIL", out)

    def test_03_green_excepted_path_passes(self):
        """Naming the EXACT hit in the exceptions file flips that class to PASS."""
        files = NEEDLE_FILES + ["tools/secret_scan.py"]
        root, baseline = build_fixture(files)
        exc = write_exceptions(root, ["secret_named tools/secret_scan.py  # a secret-SCANNING tool"])
        rc, out, err = run_scope(root, baseline, exc)
        self.assertEqual(rc, 0, (out, err))
        self.assertIn("SCOPE_CLASS secret_named kind=secret count=0 excepted=1 PASS", out)
        self.assertIn("SCOPE PASS", out)

    def test_04_negative_control_unlisted_sibling_still_fails(self):
        """A DIFFERENT secret-shaped path, not in the exceptions file, still FAILs — excepting one path
        never broadens to others (the false-positive guard proving this narrows, not loosens)."""
        files = NEEDLE_FILES + ["tools/secret_scan.py", "app/api_secret_value.py"]
        root, baseline = build_fixture(files)
        exc = write_exceptions(root, ["secret_named tools/secret_scan.py  # scanner tool"])
        rc, out, err = run_scope(root, baseline, exc)
        self.assertEqual(rc, 1, (out, err))
        self.assertIn("SCOPE_CLASS secret_named kind=secret count=1 excepted=1 FAIL", out)
        self.assertIn("SCOPE_HIT secret_named app/api_secret_value.py", out)
        self.assertNotIn("SCOPE_HIT secret_named tools/secret_scan.py", out)

    def test_05_credential_content_class_cannot_be_excepted(self):
        """env_file (a credential-CONTENT class, §11.4.10) in the exceptions file is a HARD ERROR —
        it must never be possible to except a credential-bearing class, no matter the path."""
        files = NEEDLE_FILES + [".env"]
        root, baseline = build_fixture(files)
        exc = write_exceptions(root, ["env_file .env  # pretend this is fine"])
        rc, out, err = run_scope(root, baseline, exc)
        self.assertEqual(rc, 1, (out, err))
        self.assertIn("SCOPE FAIL exceptions file invalid", out)
        self.assertIn("env_file", out)

    def test_06_keystore_class_cannot_be_excepted(self):
        """keystore (also credential-CONTENT, §11.4.10) likewise refuses."""
        files = NEEDLE_FILES + ["release.jks"]
        root, baseline = build_fixture(files)
        exc = write_exceptions(root, ["keystore release.jks  # nope"])
        rc, out, err = run_scope(root, baseline, exc)
        self.assertEqual(rc, 1, (out, err))
        self.assertIn("SCOPE FAIL exceptions file invalid", out)

    def test_07_glob_pattern_in_exceptions_is_a_hard_error(self):
        """A pattern (not an exact path) in the exceptions file is refused — exceptions narrow ONE
        verified file, they are never a general bypass mechanism."""
        files = NEEDLE_FILES + ["tools/secret_scan.py"]
        root, baseline = build_fixture(files)
        exc = write_exceptions(root, ["secret_named tools/*secret*  # too broad, must be refused"])
        rc, out, err = run_scope(root, baseline, exc)
        self.assertEqual(rc, 1, (out, err))
        self.assertIn("SCOPE FAIL exceptions file invalid", out)

    def test_08_typo_path_is_a_silent_noop_not_a_bypass(self):
        """A near-miss / typo'd exact path in the exceptions file matches nothing — the underlying
        FAIL is completely unaffected (fail-closed on a stale/mistyped exception entry)."""
        files = NEEDLE_FILES + ["tools/secret_scan.py"]
        root, baseline = build_fixture(files)
        exc = write_exceptions(root, ["secret_named tools/secret_scans.py  # typo — extra 's'"])
        rc, out, err = run_scope(root, baseline, exc)
        self.assertEqual(rc, 1, (out, err))
        self.assertIn("SCOPE_CLASS secret_named kind=secret count=1 FAIL", out)
        self.assertNotIn("excepted=1", out)

    def test_09_secrets_dir_class_exception_works(self):
        """The secrets_dir class (dir:secrets) is excepted the same way as secret_named. NOTE: by
        construction secrets_dir is ALWAYS a subset of secret_named here — segglob:*secret* scans
        EVERY path component including directory names, so a `secrets` directory component always
        ALSO satisfies segglob:*secret*; secrets_dir-only hits with no accompanying secret_named hit
        are structurally impossible under this baseline. Both classes must be excepted together for
        any real path in this shape (see test_09b for the full both-classes proof)."""
        files = NEEDLE_FILES + ["external/googleapis/secrets/v1/api.yaml"]
        root, baseline = build_fixture(files)
        exc = write_exceptions(root, [
            "secret_named external/googleapis/secrets/v1/api.yaml  # 'secrets' dir component also matches *secret*",
            "secrets_dir external/googleapis/secrets/v1/api.yaml  # public API schema dir",
        ])
        rc, out, err = run_scope(root, baseline, exc)
        self.assertEqual(rc, 0, (out, err))
        self.assertIn("SCOPE_CLASS secrets_dir kind=secret count=0 excepted=1 PASS", out)

    def test_09b_path_tripping_both_classes_needs_both_exceptions(self):
        """A file under a `secrets/` dir whose OWN basename also contains "secret" (the real shape of
        external/googleapis/google/cloud/secrets/v1beta1/secretmanager_v1beta1.yaml) trips BOTH
        secret_named and secrets_dir — excepting it in only ONE class leaves the other FAILing."""
        files = NEEDLE_FILES + ["external/googleapis/secrets/v1/secretmanager.yaml"]
        root, baseline = build_fixture(files)
        one_class = write_exceptions(root, ["secrets_dir external/googleapis/secrets/v1/secretmanager.yaml  # only secrets_dir excepted"])
        rc, out, err = run_scope(root, baseline, one_class)
        self.assertEqual(rc, 1, (out, err))  # secret_named still FAILs — proves partial exception is insufficient
        self.assertIn("SCOPE_CLASS secret_named kind=secret count=1 FAIL", out)
        self.assertIn("SCOPE_CLASS secrets_dir kind=secret count=0 excepted=1 PASS", out)
        both = write_exceptions(root, [
            "secret_named external/googleapis/secrets/v1/secretmanager.yaml  # public API schema, basename",
            "secrets_dir external/googleapis/secrets/v1/secretmanager.yaml  # public API schema, dir",
        ])
        rc, out, err = run_scope(root, baseline, both)
        self.assertEqual(rc, 0, (out, err))

    def test_10_multiple_exceptions_same_class_all_apply(self):
        files = NEEDLE_FILES + ["tools/secret_scan.py", "tools/test_secret_scan.py"]
        root, baseline = build_fixture(files)
        exc = write_exceptions(root, [
            "secret_named tools/secret_scan.py  # scanner",
            "secret_named tools/test_secret_scan.py  # its tests",
        ])
        rc, out, err = run_scope(root, baseline, exc)
        self.assertEqual(rc, 0, (out, err))
        self.assertIn("SCOPE_CLASS secret_named kind=secret count=0 excepted=2 PASS", out)

    def test_12_malformed_line_wrong_field_count_is_a_hard_error(self):
        """A line with the wrong number of whitespace-separated fields (not '<class> <path>') is
        refused, never silently skipped — a malformed exceptions file must not degrade into a
        no-op that hides its own breakage."""
        files = NEEDLE_FILES + ["tools/secret_scan.py"]
        root, baseline = build_fixture(files)
        exc = write_exceptions(root, ["secret_named"])  # missing the path field entirely
        rc, out, err = run_scope(root, baseline, exc)
        self.assertEqual(rc, 1, (out, err))
        self.assertIn("SCOPE FAIL exceptions file invalid", out)

    def test_11_real_project_exceptions_file_is_well_formed(self):
        """The checked-in constitution/scripts/codegraph/scope_exceptions.txt itself parses cleanly
        and contains only allowed classes with exact (non-glob) paths — a direct sanity check on the
        artefact this fix ships, independent of the fixtures above."""
        real = os.path.join(HERE, "..", "scope_exceptions.txt")
        self.assertTrue(os.path.isfile(real), real)
        sys.path.insert(0, os.path.dirname(TOOL))
        import importlib.util
        spec = importlib.util.spec_from_file_location("cgsh", TOOL)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        exc = mod.load_exceptions(real)
        self.assertTrue(exc, "expected at least one exception class to be loaded")
        for cls in exc:
            self.assertIn(cls, mod.ALLOWED_EXCEPTION_CLASSES)
        for cls, paths in exc.items():
            for p in paths:
                self.assertFalse(p.startswith("/"), p)
                self.assertNotIn("*", p)


if __name__ == "__main__":
    unittest.main()
