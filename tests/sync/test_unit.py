#!/usr/bin/env python3
"""tests/sync/test_unit.py -- UNIT tests of scripts/sync/sync_all_upstreams.py (pure functions only).

Run: python3 -I tests/sync/test_unit.py   (exit 0 all pass, 1 a failure). SYNC_ENGINE_PY overrides the
engine file (used by the mutation harness). No git repository is created here; the git-backed layers are
covered by tests/sync/test_integration.sh and the other suites.
"""
import importlib.util
import os
import sys
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
ENGINE = os.environ.get("SYNC_ENGINE_PY") or os.path.join(HERE, "..", "..", "scripts", "sync", "sync_all_upstreams.py")
spec = importlib.util.spec_from_file_location("sync_engine", ENGINE)
E = importlib.util.module_from_spec(spec)
spec.loader.exec_module(E)
SHA = "a" * 40


class AllowList(unittest.TestCase):
    def ok(self, *a):
        self.assertTrue(E.check_git_args(list(a)))

    def bad(self, *a):
        with self.assertRaises(E.GitRefused):
            E.check_git_args(list(a))

    def test_fetch_shapes(self):
        # the ONE engine-owned shape (F1): explicit remote-tracking refspec, --refmap=, never prune
        self.ok(*E.fetch_args("origin", False))
        self.ok(*E.fetch_args("github_helix", True))
        self.ok(*E.fetch_args("team/mirror", False))
        base = E.fetch_args("origin", False)
        self.assertIn("--no-prune", base)
        self.assertIn("--no-prune-tags", base)
        self.assertIn("--refmap=", base)
        self.assertEqual(base[-1], "+refs/heads/*:refs/remotes/origin/*")
        self.bad("fetch", "origin")
        self.bad("fetch", "--prune", "--no-recurse-submodules", "--", "origin")  # the old, config-inheriting shape
        self.bad("fetch", "--prune", "--no-recurse-submodules", "--tags", "--", "origin")
        self.bad(*(base[:-1] + ["+refs/heads/*:refs/heads/*"]))  # a mirror refspec into the local namespace
        self.bad(*(base[:-1] + ["+refs/heads/*:refs/remotes/other/*"]))  # another remote's namespace
        self.bad(*(base[:1] + ["--prune"] + base[1:]))
        self.bad(*([x for x in base if x != "--no-prune"]))
        self.bad(*([x for x in base if x != "--refmap="]))
        self.bad(*([x for x in base if x != "--no-tags"]))
        self.bad(*(base + ["+refs/tags/*:refs/tags/*"]))  # a forced tag refspec
        self.bad(*(base[:1] + ["--force"] + base[1:]))
        self.bad(*(base[:1] + ["--depth=1"] + base[1:]))
        self.bad(*(base[:1] + ["--upload-pack=sh"] + base[1:]))
        for r in ("-oops", "ext::sh -c id", "a/..", "a/./b", "x.lock", "a//b", "", "a*"):
            self.bad(*E.fetch_args(r, False))

    def test_safe_config_on_every_call(self):
        cmd = E.git_argv("/usr/bin/git", "/r", ["status"])
        self.assertEqual(cmd[:3], ["/usr/bin/git", "-C", "/r"])
        pairs = {cmd[i + 1] for i, x in enumerate(cmd) if x == "-c"}
        for kv in ("core.hooksPath=/dev/null", "core.fsmonitor=false", "submodule.recurse=false", "gc.auto=0",
                   "maintenance.auto=false", "fetch.prune=false", "fetch.pruneTags=false"):
            self.assertIn(kv, pairs)
        self.assertEqual(cmd[-2:], ["--no-optional-locks", "status"])

    def test_transport_helper_refused_everywhere(self):
        # the "::" rule on its own: these shapes pass every other check, so only that rule refuses them
        self.ok("rev-parse", "x:y")
        self.bad("rev-parse", "x::y")
        self.bad("config", "--get", "remote.ext::sh.url")
        self.bad("cat-file", "-e", "ext::sh")

    def test_writes_exact(self):
        self.ok("merge", "--ff-only", SHA)
        self.bad("merge", SHA)
        for flag in ("--ff", "--no-ff", "--squash", "--commit", "--no-commit"):  # R1 shape: --ff is not --ff-only
            self.bad("merge", flag, SHA)
        self.bad("merge", "--ff-only", "-s", "ours", SHA)
        self.bad("merge", "--ff-only", "origin/main")
        self.ok("checkout", "--quiet", "--detach", SHA)
        self.bad("checkout", "-f", SHA)
        self.bad("checkout", "--quiet", "--detach", "--force", SHA)
        self.bad("checkout", "--quiet", "--detach", "main")
        self.ok("add", "--", "libs/a")
        self.bad("add", "-A")
        self.bad("add", "--", "../x")
        self.bad("add", "--", "/abs")
        self.bad("add", "--", "-x")

    def test_forbidden_subcommands(self):
        for s in ("push", "reset", "rebase", "commit", "clean", "update-ref", "filter-branch", "branch", "tag",
                  "switch", "submodule", "gc", "pull", "remote-ext", "send-pack", "stash", "restore", "worktree"):
            self.bad(s)

    def test_read_only_shapes(self):
        self.ok("rev-parse", "HEAD")
        self.ok("ls-files", "-s", "-z")
        self.ok("symbolic-ref", "--short", "-q", "HEAD")
        self.bad("symbolic-ref", "HEAD", "refs/heads/x")
        self.ok("config", "--get", "remote.origin.url")
        self.bad("config", "remote.origin.url", "x")
        self.bad("config", "--unset", "x")
        self.ok("remote")
        self.bad("remote", "add", "x", "y")
        self.bad("rev-parse", "--git-dir=/x")
        self.bad("status", "--force")

    def test_injection_shapes(self):
        self.bad("rev-parse", "a\nb")
        self.bad("rev-parse", "+x")
        self.bad()


class Redaction(unittest.TestCase):
    def test_userinfo(self):
        self.assertEqual(E.redact("https://user:s3cret@github.com/o/r.git"), "https://github.com/o/r.git")
        self.assertEqual(E.redact("fatal: https://x-access-token:abc@host/r"), "fatal: https://host/r")

    def test_tokens(self):
        t = E.redact("token ghp_ABCDEFGHIJKLMNOPQRSTUVWXYZ0123 and glpat-abcdEFGH1234")
        self.assertNotIn("ghp_ABC", t)
        self.assertNotIn("glpat-abcd", t)
        self.assertIn("[REDACTED]", t)

    def test_control_chars(self):
        self.assertEqual(E.redact("a\x1b[31mb"), "a?[31mb")

    def test_negative_control(self):
        self.assertEqual(E.redact("git@github.com:o/r.git"), "git@github.com:o/r.git")


class Classification(unittest.TestCase):
    def test_classify(self):
        self.assertEqual(E.classify(0, 0), "equal")
        self.assertEqual(E.classify(0, 3), "behind")
        self.assertEqual(E.classify(2, 0), "ahead")
        self.assertEqual(E.classify(1, 1), "diverged")

    def test_pick_newest_linear(self):
        order = ["a", "b", "c"]
        anc = lambda x, y: order.index(x) <= order.index(y)
        self.assertEqual(E.pick_newest(["a", "c", "b"], anc), "c")
        self.assertEqual(E.pick_newest(["b"], anc), "b")
        self.assertIsNone(E.pick_newest([], anc))

    def test_pick_newest_diverged(self):
        self.assertIsNone(E.pick_newest(["x", "y"], lambda a, b: a == b))

    def test_own_org(self):
        orgs = E.DEFAULT_OWN_ORGS
        self.assertTrue(E.is_own_org("git@github.com:HelixDevelopment/HelixConstitution.git", orgs))
        self.assertTrue(E.is_own_org("https://gitlab.com/vasic-digital/x.git", orgs))
        self.assertTrue(E.is_own_org("file:///s/remotes/helixdevelopment/a.git", orgs))
        self.assertFalse(E.is_own_org("https://github.com/ggml-org/llama.cpp.git", orgs))
        self.assertFalse(E.is_own_org("https://github.com/other/HelixDevelopment.git", orgs))

    def test_safe_relpath(self):
        self.assertTrue(E.safe_relpath("a/b"))
        for p in ("", "-a", "/a", "a/../b", "a//b", ".", "a\\b"):
            self.assertFalse(E.safe_relpath(p), p)

    def test_clamp_jobs(self):
        self.assertEqual(E.clamp_jobs(None, 16), 4)
        self.assertEqual(E.clamp_jobs(100, 64), 8)
        self.assertEqual(E.clamp_jobs(3, 1), 1)
        self.assertEqual(E.clamp_jobs(None, None), 1)

    def test_canonical_ignores_volatile(self):
        a = {"started": "1", "run_id": "x", "repos": [{"path": ".", "fetch_error": "e1"}], "v": 1}
        b = {"started": "2", "run_id": "y", "repos": [{"path": ".", "fetch_error": "e2"}], "v": 1}
        c = {"started": "2", "run_id": "y", "repos": [{"path": ".", "fetch_error": "e2"}], "v": 2}
        self.assertEqual(E.canonical_sha256(a), E.canonical_sha256(b))
        self.assertNotEqual(E.canonical_sha256(a), E.canonical_sha256(c))

    def test_reasons(self):
        rec = {"kind": "root", "initialised": True, "dirty": True, "in_progress": ["MERGE_HEAD"], "branch": "dev",
               "remotes": [{"name": "o", "state": "unreachable"}], "upstream_state": "upstreams-diverged"}
        rs = E.reasons_for(rec, False, "main")
        for want in ("dirty-tree", "in-progress:MERGE_HEAD", "unreachable:o", "upstreams-diverged", "root-not-on-main"):
            self.assertIn(want, rs)
        sub = {"kind": "submodule", "initialised": False, "pin": {"state": "uninitialised"}}
        self.assertEqual(E.reasons_for(sub, False, "main"), [])
        self.assertEqual(E.reasons_for(sub, True, "main"), ["pin-uninitialised"])

    def test_reasons_new_blockers(self):
        rec = {"kind": "submodule", "initialised": True, "ignored_clobber": ["secret.env"],
               "gitlink_modified": ["libs/a"], "remotes": []}
        rs = E.reasons_for(rec, False, "main")
        self.assertIn("ignored-file-would-be-overwritten", rs)
        self.assertIn("gitlink-modified:libs/a", rs)
        self.assertIn("head-unreadable", E.reasons_for({"kind": "submodule", "initialised": True, "remotes": [],
                                                       "head_unreadable": True}, False, "main"))

    def test_read_head_only_a_full_object_id(self):  # F3: empty, odd or failed output is never a head
        class R:
            def __init__(self, rc, out):
                self.rc, self.out = rc, out

            def run(self, repo, args):
                return self.rc, self.out, ""
        sha = "0123456789abcdef0123456789abcdef01234567"
        self.assertEqual(E.read_head(R(0, sha + "\n"), "/r"), sha)
        for rc, out in ((0, ""), (0, "\n"), (0, "HEAD"), (0, sha[:12]), (128, sha), (0, sha + "\nx")):
            self.assertIsNone(E.read_head(R(rc, out), "/r"), (rc, out))

    def test_fetch_failure_labels(self):  # F12
        self.assertEqual(E.classify_fetch_failure(124, ""), "timeout")
        self.assertEqual(E.classify_fetch_failure(126, ""), "deadline")
        self.assertEqual(E.classify_fetch_failure(128, "git@x: Permission denied (publickey).\nfatal: Could not read from remote repository."), "auth")
        self.assertEqual(E.classify_fetch_failure(128, "fatal: '/x' does not appear to be a git repository"), "not-found")
        self.assertEqual(E.classify_fetch_failure(128, "fatal: unable to access 'https://h/': Could not resolve host: h"), "network")
        self.assertEqual(E.classify_fetch_failure(1, "error: something unexpected"), "other")

    def test_fetched_branches(self):
        import tempfile
        d = tempfile.mkdtemp()
        try:
            f = os.path.join(d, "FETCH_HEAD")
            with open(f, "w") as h:
                h.write("%s\t\tbranch 'main' of /x\n%s\tnot-for-merge\tbranch 'feature/main' of /x\n" % (SHA, SHA))
            self.assertEqual(E.fetched_branches(f), {"main", "feature/main"})
            self.assertIsNone(E.fetched_branches(os.path.join(d, "absent")))
            self.assertIsNone(E.fetched_branches("relative/FETCH_HEAD"))
        finally:
            for n in os.listdir(d):
                os.unlink(os.path.join(d, n))
            os.rmdir(d)

    def test_exit_codes_distinct(self):  # N3
        codes = [E.EXIT_OK, E.EXIT_FAIL, E.EXIT_USAGE, E.EXIT_BEHIND, E.EXIT_ATTENTION, E.EXIT_INCONCLUSIVE,
                 E.EXIT_BLIND, E.EXIT_LOCKED]
        self.assertEqual(len(set(codes)), len(codes))

    def test_has_update(self):
        self.assertTrue(E.has_update({"initialised": True, "branch": "main", "local_vs_target": "behind"}))
        self.assertTrue(E.has_update({"initialised": True, "own_org": True, "pin": {"state": "behind-main"}}))
        self.assertFalse(E.has_update({"initialised": True, "own_org": False, "pin": {"state": "behind-main"}}))
        self.assertFalse(E.has_update({"initialised": False}))

    def test_git_env_scrub(self):
        env = E.git_env({"GIT_DIR": "/x", "GIT_CONFIG_KEY_0": "a", "GIT_CONFIG_VALUE_0": "b", "PATH": "/bin",
                         "GIT_CONFIG_GLOBAL": "/g", "GIT_ASKPASS": "/p"})
        for k in ("GIT_DIR", "GIT_CONFIG_KEY_0", "GIT_CONFIG_VALUE_0", "GIT_ASKPASS"):
            self.assertNotIn(k, env)
        self.assertEqual(env["GIT_TERMINAL_PROMPT"], "0")
        self.assertIn("BatchMode=yes", env["GIT_SSH_COMMAND"])
        self.assertEqual(env["GIT_CONFIG_GLOBAL"], "/g")

    def test_usage_exit_codes(self):
        self.assertEqual(E.main([]), E.EXIT_USAGE)
        self.assertEqual(E.main(["--check", "--dry-run"]), E.EXIT_USAGE)
        self.assertEqual(E.main(["--check", "--timeout", "0"]), E.EXIT_USAGE)
        self.assertEqual(E.main(["--apply", "--advance-third-party"]), E.EXIT_USAGE)
        self.assertEqual(E.main(["--check", "--branch", "-x"]), E.EXIT_USAGE)


if __name__ == "__main__":
    r = unittest.main(exit=False, verbosity=1).result
    n, f = r.testsRun, len(r.failures) + len(r.errors)
    print("sync-unit: PASS %d FAIL %d" % (n - f, f))
    sys.exit(0 if f == 0 and n > 0 else 1)
