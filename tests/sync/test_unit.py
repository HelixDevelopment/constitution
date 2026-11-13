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


def fake_runner(result):
    """A real Runner whose ONE spawn point (proc_run_git) is replaced by a canned (kind, code, out, err)."""
    E.proc_run_git = lambda git_bin, repo, args, env, limit, _r=result: (E.check_git_args(args) and _r)
    return E.Runner("/nonexistent/git", 10, E.time.monotonic() + 600)


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
        self.bad("cat-file", "-e", SHA)  # cat-file left the allow-list in round 3: presence is rev-parse --verify

    def test_check_returns_the_checked_tuple(self):  # proc_run_git builds the command from the CHECKED value
        self.assertEqual(E.check_git_args(["rev-parse", "HEAD"]), ("rev-parse", "HEAD"))

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


class TypedAnswer(unittest.TestCase):  # review round 2, I-1: no answer is never "nothing there"
    def test_declared_statuses_only(self):
        for res, ok, answered in ((("exit", 0, "x", ""), (0,), True), (("exit", 1, "", ""), (0, 1), True),
                                  (("exit", 1, "", ""), (0,), False), (("exit", 128, "", ""), (0, 1), False),
                                  (("exit", 129, "", ""), (0, 1), False), (("exit", 77, "", ""), (0,), False),
                                  (("signal", 9, "", ""), (0, 1), False), (("signal", 15, "", ""), (0,), False),
                                  (("exit", 137, "", ""), (0, 1), False), (("timeout", None, "", ""), (0,), False),
                                  (("not-runnable", None, "", "x"), (0,), False)):
            r = fake_runner(res)
            g = r.run("/r", ["status"], ok=ok)
            self.assertEqual(g.answered, answered, (res, ok))
            if not answered:
                self.assertTrue(r.unresolved_for("/r"), (res, ok))
                self.assertIsNone(g.text())
            else:
                self.assertEqual(r.unresolved_for("/r"), [])

    def test_why_classes(self):
        cases = ((("signal", 9, "", ""), "signal:9"), (("exit", 128, "", ""), "rc:128"), (("timeout", None, "", ""), "timeout"),
                 (("not-runnable", None, "", ""), "not-runnable"))
        for res, why in cases:
            r = fake_runner(res)
            self.assertEqual(r.run("/r", ["status"], ok=(0,)).why, why)
            self.assertEqual(r.unresolved_for("/r"), ["status:" + why])

    def test_shape(self):  # n-5: an rc-0 answer of the wrong shape is no answer
        r = fake_runner(("exit", 0, "", ""))
        g = r.run("/r", ["rev-parse", "--verify", "-q", "HEAD^{commit}"], ok=(0, 1), want=E.SHA_RE)
        self.assertFalse(g.answered)
        self.assertEqual(r.unresolved_for("/r"), ["rev-parse:malformed-output"])

    def test_network_timeout_is_the_remotes_state(self):
        r = fake_runner(("timeout", None, "", ""))
        g = r.run("/r", E.fetch_args("origin", False), ok=(0, 1, 128), network=True)
        self.assertEqual((g.answered, g.why), (False, "timeout"))
        self.assertEqual(r.unresolved_for("/r"), [])
        r = fake_runner(("signal", 9, "", ""))
        r.run("/r", E.fetch_args("origin", False), ok=(0, 1, 128), network=True)
        self.assertEqual(r.unresolved_for("/r"), ["fetch:signal:9"])

    def test_deadline_and_refused(self):
        r = fake_runner(("exit", 0, "", ""))
        r.deadline = E.time.monotonic() - 1
        self.assertEqual(r.run("/r", ["status"], ok=(0,)).why, "deadline")
        r = fake_runner(("exit", 0, "", ""))
        self.assertEqual(r.run("/r", ["push"], ok=(0,)).why, "refused")
        self.assertEqual(r.unresolved_for("/r"), ["push:refused"])

    def test_choke_point_refuses_before_spawning(self):
        import importlib.util as iu
        sp = iu.spec_from_file_location("sync_engine_fresh", ENGINE)
        F = iu.module_from_spec(sp)
        sp.loader.exec_module(F)
        with self.assertRaises(F.GitRefused):  # refused before any Popen, so no OSError for a missing git
            F.proc_run_git("/nonexistent/git", "/", ["push"], {}, 1)
        self.assertEqual(F.proc_run_git("/nonexistent/git", "/", ["status"], {}, 1)[0], "not-runnable")

    def test_signal_is_reported_as_a_signal(self):  # review round 3: own mutant M62 survived without this
        # a stand-in "git" that kills itself with SIGKILL (it is our own child, in its own session): the spawn
        # point must say "signal 9", never an exit status, and the Runner must name it signal:9 (no answer)
        import importlib.util as iu
        import shutil
        import tempfile
        sp = iu.spec_from_file_location("sync_engine_sig", ENGINE)
        F = iu.module_from_spec(sp)
        sp.loader.exec_module(F)
        d = tempfile.mkdtemp(prefix="sync_unit_sig.")
        try:
            fake = os.path.join(d, "git")
            with open(fake, "w", encoding="utf-8") as fh:
                fh.write("#!/bin/sh\nkill -9 $$\n")
            os.chmod(fake, 0o700)
            kind, code, _, _ = F.proc_run_git(fake, d, ["status"], {"PATH": "/usr/bin:/bin"}, 10)
            self.assertEqual((kind, code), ("signal", 9))
            r = F.Runner(fake, 10, F.time.monotonic() + 600)
            r.env = {"PATH": "/usr/bin:/bin"}
            res = r.run(d, ["status"], ok=(0,))
            self.assertFalse(res.answered)
            self.assertEqual(res.why, "signal:9")
        finally:
            shutil.rmtree(d)  # made by mkdtemp above


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
        self.assertEqual(E.redact("https://github.com/o/r.git"), "https://github.com/o/r.git")
        self.assertEqual(E.redact("plain text, no url"), "plain text, no url")

    def test_structural_userinfo(self):  # review round 2, S-1: '@' and spaces inside the userinfo
        for url, secret in (("https://u:p@ss@host/r.git", "ss@"), ("https://u:pa ss@host/r.git", "pa ss"),
                            ("https://u:a@b@c@host/r", "a@b"), ("ssh://u:x y@z@host:22/r", "x y"),
                            ("fatal: https://tok@host/r and http://u2:p2@h2/x", "p2"),
                            ("https://user:ghp_ABCDEFGHIJKLMNOP@host/o/r", "ghp_"),
                            ("HTTPS://U:P@HOST/r", "U:P"), ("git+ssh://u:p@h/r", "u:p"),
                            ("https://u:p%40q@host/r", "p%40q")):
            out = E.redact(url)
            self.assertNotIn(secret, out, url)
            self.assertNotIn("@host", out.replace("@h2", ""), url)
        self.assertEqual(E.redact("https://u:p@ss@host/r.git"), "https://host/r.git")
        self.assertEqual(E.redact("a https://h/x\nb https://u:p@h/y"), "a https://h/x\nb https://h/y")
        self.assertEqual(E.redact(E.redact("https://u:p@ss@host/r.git")), "https://host/r.git")  # idempotent

    def test_token_in_path(self):  # review round 2, K12 shape: a token in the URL PATH, not in the userinfo
        self.assertNotIn("ghp_", E.redact("fatal: unable to access 'https://host/ghp_ABCDEFGHIJKL/r.git/'"))

    def test_report_backstop(self):
        hits = []
        rep = E.redact_report({"a": "https://u:p@h/r", "_raw": "secret", "b": ["ok", "glpat-ABCDEFGH"], "c": 3},
                              "report", hits)
        self.assertEqual(rep, {"a": "https://h/r", "b": ["ok", "[REDACTED]"], "c": 3})
        self.assertEqual(hits, ["report.a", "report.b[1]"])
        hits = []
        E.redact_report({"a": "x\x1by", "b": "https://h/r"}, "report", hits)
        self.assertEqual(hits, [])  # control characters are not a credential: no backstop hit


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
        sha = "0123456789abcdef0123456789abcdef01234567"
        self.assertEqual(E.read_head(fake_runner(("exit", 0, sha + "\n", "")), "/r"), sha)
        for res in (("exit", 0, "", ""), ("exit", 0, "\n", ""), ("exit", 0, "HEAD", ""), ("exit", 0, sha[:12], ""),
                    ("exit", 1, "", ""), ("exit", 128, sha, ""), ("exit", 0, sha + "\nx", ""), ("signal", 9, sha, ""),
                    ("timeout", None, "", ""), ("not-runnable", None, "", "")):
            self.assertIsNone(E.read_head(fake_runner(res), "/r"), res)

    def test_fetch_failure_labels(self):  # F12
        self.assertEqual(E.classify_fetch_failure(1, " ! [rejected] v1 -> v1 (would clobber existing tag)"), "tag-rejected")
        self.assertEqual(E.classify_fetch_failure(128, "would clobber existing tag"), "other")  # only rc 1 (m-4)
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

    def test_git_env_scrubs_every_config_injector(self):  # review round 2, K16
        bad = {"GIT_CONFIG_PARAMETERS": "'core.sshCommand'='x'", "GIT_CONFIG_COUNT": "1", "GIT_CONFIG_KEY_7": "k",
               "GIT_CONFIG_VALUE_7": "v", "GIT_SSH": "/x", "GIT_PROXY_COMMAND": "/x", "GIT_EXEC_PATH": "/x"}
        env = E.git_env(dict(bad, PATH="/bin"))
        for k in bad:
            self.assertNotIn(k, env)


class Evidence(unittest.TestCase):  # review round 2, n-3
    def setUp(self):
        import tempfile
        self.d = tempfile.mkdtemp()

    def tearDown(self):
        for n in os.listdir(self.d):
            os.unlink(os.path.join(self.d, n))
        os.rmdir(self.d)

    def test_only_our_files(self):
        j, t = os.path.join(self.d, "sync_report.json"), os.path.join(self.d, "sync_report.tsv")
        self.assertTrue(E.evidence_file_ours(j, "json"))
        with open(j, "w") as f:
            f.write('{"mine": 1}')
        self.assertFalse(E.evidence_file_ours(j, "json"))
        with open(j, "w") as f:
            f.write('{\n  "schema": "%s"\n}' % E.SCHEMA)
        self.assertTrue(E.evidence_file_ours(j, "json"))
        with open(t, "w") as f:
            f.write("\t".join(E.TSV_COLS) + "\n")
        self.assertTrue(E.evidence_file_ours(t, "tsv"))
        os.unlink(t)
        os.symlink(j, t)
        self.assertFalse(E.evidence_file_ours(t, "tsv"))

    def test_write_atomic_unpredictable(self):
        p = os.path.join(self.d, "sync_report.json")
        trap = os.path.join(self.d, "sync_report.json.tmp")
        os.symlink("/nonexistent/target", trap)  # the round-2 predictable name: never opened
        E.write_atomic(p, "x")
        with open(p) as f:
            self.assertEqual(f.read(), "x")
        self.assertEqual(sorted(os.listdir(self.d)), ["sync_report.json", "sync_report.json.tmp"])
        self.assertTrue(os.path.islink(trap))

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
