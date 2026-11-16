#!/usr/bin/env python3
"""tests/sync/test_unit.py -- UNIT tests of scripts/sync/sync_all_upstreams.py (pure functions only).

Run: python3 -I tests/sync/test_unit.py   (exit 0 all pass, 1 a failure). SYNC_ENGINE_PY overrides the
engine file (used by the mutation harness). No git repository is created here; the git-backed layers are
covered by tests/sync/test_integration.sh and the other suites.
"""
import importlib.util
import json
import os
import sys
import unittest
from typing import Any
import os as _ge_os  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
for _ge_v in "GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX".split(): _ge_os.environ.pop(_ge_v, None)

HERE = os.path.dirname(os.path.abspath(__file__))
ENGINE = os.environ.get("SYNC_ENGINE_PY") or os.path.join(HERE, "..", "..", "scripts", "sync", "sync_all_upstreams.py")
spec = importlib.util.spec_from_file_location("sync_engine", ENGINE)
E = importlib.util.module_from_spec(spec)
spec.loader.exec_module(E)
SHA = "a" * 40


def fake_runner(result):
    """A real Runner whose ONE spawn point (proc_run_git) is replaced by a canned (kind, code, out, err)."""
    E.proc_run_git = lambda git_bin, repo, args, env, limit, level=1, _r=result: (E.check_git_args(args) and _r)
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
        self.ok("symbolic-ref", "-q", "HEAD")
        self.bad("symbolic-ref", "--short", "-q", "HEAD")  # round 11 (RV10-1): --short disambiguates (heads/dev)
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
                 E.EXIT_BLIND, E.EXIT_LOCKED, E.EXIT_INTERRUPTED]
        self.assertEqual(len(set(codes)), len(codes))

    def test_has_update(self):
        self.assertTrue(E.has_update({"initialised": True, "branch": "main", "local_vs_target": "behind"}))
        self.assertTrue(E.has_update({"initialised": True, "own_org": True, "pin": {"state": "behind-main"}}))
        self.assertFalse(E.has_update({"initialised": True, "own_org": False, "pin": {"state": "behind-main"}}))
        self.assertFalse(E.has_update({"initialised": False}))

    def test_git_env_scrub(self):
        env = E.git_env({"GIT_DIR": "/x", "GIT_CONFIG_KEY_0": "a", "GIT_CONFIG_VALUE_0": "b", "PATH": "/bin",
                         "GIT_CONFIG_GLOBAL": "/g", "GIT_ASKPASS": "/p"})
        for k in ("GIT_DIR", "GIT_CONFIG_KEY_0", "GIT_CONFIG_VALUE_0"):
            self.assertNotIn(k, env)
        self.assertEqual(env["GIT_ASKPASS"], "")  # empty: no askpass program, and it beats core.askPass (D9, D10)
        self.assertEqual(env["SSH_ASKPASS_REQUIRE"], "never")
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
        E.fs_write_atomic(p, "x")
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


# ───────────────────────────── review round 3 findings (round 4 tests) ─────────────────────────────
def scripted_runner(script):
    """A real Runner whose ONE spawn point answers from SCRIPT(repo, args) -> (kind, code, out, err). Every call
    passes the real allow-list first and is recorded in ``runner.seen`` as (repo, tuple(args))."""
    seen = []

    def spawn(git_bin, repo, args, env, limit, level=1):
        E.check_git_args(args)
        seen.append((repo, tuple(args)))
        return script(repo, list(args))
    setattr(E, "proc_run_git", spawn)  # the one spawn point, replaced for this Runner
    r = E.Runner("/nonexistent/git", 10, E.time.monotonic() + 600)
    r.seen = seen
    return r


def fresh_engine(name) -> Any:
    sp = importlib.util.spec_from_file_location(name, ENGINE)
    assert sp is not None and sp.loader is not None, ENGINE
    m = importlib.util.module_from_spec(sp)
    sp.loader.exec_module(m)
    return m


def read_bytes(path):
    with open(path, "rb") as f:
        return f.read()


def live_token(test, F, r, op="fast-forward"):
    """A live WriteToken of ``r`` (review round 8): its marker created in a fresh temporary git dir and the dir's
    state moved to GD_WRITING, exactly as begin_write leaves it, without begin_write's refusal checks (so a test can
    hold a token while a stop or the deadline is in force). The directory is removed by the test's cleanup."""
    import tempfile
    d = tempfile.mkdtemp(prefix="sync_unit_tok.")

    def gone():
        for n in os.listdir(d):
            os.unlink(os.path.join(d, n))
        os.rmdir(d)
    test.addCleanup(gone)
    test.assertEqual(F.write_marker(d, op, SHA, "t", "t:1:1"), F.MARKER_WRITTEN)
    test.assertTrue(r.gd_move(d, F.GD_WRITING))
    return F.WriteToken(d, op, "t:1:1")


class TempDir(unittest.TestCase):
    def setUp(self):
        import tempfile
        self.d = tempfile.mkdtemp(prefix="sync_unit.")
        self.locked = []

    def tearDown(self):
        import shutil
        for p in self.locked:  # a directory a test made unreadable is made readable again before removal
            os.chmod(p, 0o700)
        shutil.rmtree(self.d)  # made by mkdtemp in setUp

    def lock(self, p):
        """Make P unreadable (mode 000); refused when this test runs as root (permissions would not apply)."""
        if os.geteuid() == 0:
            self.fail("the permission tests cannot run as root (mode 000 does not stop root)")
        os.chmod(p, 0)
        self.locked.append(p)


class KillGroup(unittest.TestCase):  # review round 3, F5 / X04 (§11.4.263): no test called proc_kill_group
    def patched(self, getpgid, child_pid=None):
        """A fresh engine copy whose ``os`` is a stand-in: ``getpgid`` as given and a killpg that RECORDS every
        call. It forwards a real SIGKILL only to the group of CHILD_PID, our own child in its own session, so a
        mutated guard (pgid 1, 0, -1, a foreign group) is recorded and fails the test, and is never sent."""
        import types
        F = fresh_engine("sync_engine_killgroup")
        calls = []

        def killpg(pg, sig):
            calls.append((pg, sig))
            if (child_pid is not None and type(pg) is int and pg == child_pid and pg > 1
                    and sig in (E.signal.SIGTERM, E.signal.SIGKILL) and os.getpgid(child_pid) == child_pid):
                os.killpg(pg, sig)

        def waitid(idtype, pid, options):  # a real child is asked for real; a made-up pid counts as ended
            if child_pid is not None and pid == child_pid:
                return os.waitid(idtype, pid, options)
            return object()
        ns = types.SimpleNamespace(getpgid=getpgid, killpg=killpg, waitid=waitid, P_PID=os.P_PID, WEXITED=os.WEXITED,
                                   WNOHANG=os.WNOHANG, WNOWAIT=os.WNOWAIT)
        F.os = ns
        self.assertIs(F.proc_kill_group.__globals__["os"], ns)  # the patch took before it is used
        return F, calls

    def test_never_signals_a_pgid_that_is_not_the_childs_own(self):
        import types
        child = types.SimpleNamespace(pid=4242)
        for value in (1, 0, -1, "4242", True, False, None, 4243, 4242.0, 2 ** 70):
            F, calls = self.patched(lambda pid, v=value: v)
            F.proc_kill_group(child, 1)
            self.assertEqual(calls, [], "getpgid -> %r" % (value,))

    def test_pid_one_is_never_signalled(self):
        import types
        F, calls = self.patched(lambda pid: 1)
        F.proc_kill_group(types.SimpleNamespace(pid=1), 1)
        self.assertEqual(calls, [])

    def test_getpgid_error_sends_nothing(self):
        import types

        def boom(pid):
            raise ProcessLookupError("gone")
        F, calls = self.patched(boom)
        F.proc_kill_group(types.SimpleNamespace(pid=4242), 1)
        self.assertEqual(calls, [])

    def test_own_group_gets_sigterm_then_sigkill(self):  # the positive case of the patched copy (review round 6)
        import types
        F, calls = self.patched(lambda pid: pid)
        self.assertEqual(F.proc_kill_group(types.SimpleNamespace(pid=4242), 1), "SIGTERM")
        self.assertEqual(calls, [(4242, E.signal.SIGTERM), (4242, E.signal.SIGKILL)])

    def test_killpg_error_is_swallowed(self):
        import types
        F = fresh_engine("sync_engine_killgroup_err")

        def killpg(pg, sig):
            raise ProcessLookupError("already gone")
        F.os = types.SimpleNamespace(getpgid=lambda pid: pid, killpg=killpg, waitid=lambda *a: None, P_PID=os.P_PID,
                                     WEXITED=os.WEXITED, WNOHANG=os.WNOHANG, WNOWAIT=os.WNOWAIT)
        self.assertIsNone(F.proc_kill_group(types.SimpleNamespace(pid=4242), 1))  # must not raise

    def test_real_child_in_its_own_session_ends_with_sigterm(self):  # real positive control (review round 6)
        import subprocess
        p = subprocess.Popen(["sleep", "30"], start_new_session=True, stdin=subprocess.DEVNULL,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            self.assertGreater(p.pid, 1)
            self.assertEqual(os.getpgid(p.pid), p.pid)  # its own group, which this test owns
            F, calls = self.patched(os.getpgid, child_pid=p.pid)
            self.assertEqual(F.proc_kill_group(p, 5), "SIGTERM")
            self.assertEqual(calls, [(p.pid, E.signal.SIGTERM), (p.pid, E.signal.SIGKILL)])
            # never reaped by proc_kill_group (WNOWAIT): the exit status is still there, and it is SIGTERM's
            self.assertEqual(p.wait(timeout=10), -E.signal.SIGTERM)
        finally:
            if p.poll() is None:
                p.kill()  # our own child, by pid
                p.wait(timeout=10)

    def test_real_child_that_ignores_sigterm_ends_with_sigkill_after_grace(self):  # review round 6, RV5-1
        import subprocess
        import time as t_
        p = subprocess.Popen(["sh", "-c", "trap '' TERM; exec sleep 30"], start_new_session=True,
                             stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        try:
            t_.sleep(0.3)  # the trap is installed
            F, calls = self.patched(os.getpgid, child_pid=p.pid)
            t0 = t_.monotonic()
            self.assertEqual(F.proc_kill_group(p, 1), "SIGKILL")
            self.assertGreaterEqual(t_.monotonic() - t0, 0.9)  # the grace period was waited
            self.assertEqual(calls, [(p.pid, E.signal.SIGTERM), (p.pid, E.signal.SIGKILL)])
            self.assertEqual(p.wait(timeout=10), -E.signal.SIGKILL)
        finally:
            if p.poll() is None:
                p.kill()  # our own child, by pid
                p.wait(timeout=10)

    def test_real_child_in_our_group_is_never_signalled(self):  # real negative control
        import subprocess
        p = subprocess.Popen(["sleep", "30"], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                             stderr=subprocess.DEVNULL)  # NOT a new session: its group is this test's group
        try:
            self.assertNotEqual(os.getpgid(p.pid), p.pid)
            F, calls = self.patched(os.getpgid, child_pid=p.pid)
            F.proc_kill_group(p, 5)
            self.assertEqual(calls, [])
            self.assertIsNone(p.poll())  # still running: nothing was sent
        finally:
            p.kill()  # our own child, by pid
            p.wait(timeout=10)


class ProbeChild(TempDir):  # review round 3, F1 and class B: an unread path is never "absent" / "not initialised"
    def test_path_kind(self):
        f = os.path.join(self.d, "f")
        open(f, "w").close()
        os.symlink(self.d, os.path.join(self.d, "ln"))
        os.symlink("/nonexistent/x", os.path.join(self.d, "dangling"))
        self.assertEqual(E.path_kind(os.path.join(self.d, "nope")), "absent")
        self.assertEqual(E.path_kind(os.path.join(f, "below-a-file")), "absent")  # ENOTDIR
        self.assertEqual(E.path_kind(self.d), "dir")
        self.assertEqual(E.path_kind(f), "regular")
        self.assertEqual(E.path_kind(os.path.join(self.d, "ln")), "symlink")  # the last component is not followed
        self.assertEqual(E.path_kind(os.path.join(self.d, "dangling")), "symlink")
        os.mkfifo(os.path.join(self.d, "fifo"))  # review round 9: every kind is named, none is "other"
        self.assertEqual(E.path_kind(os.path.join(self.d, "fifo")), "fifo")
        self.assertEqual(E.path_kind("/dev/null"), "char-device")
        self.assertEqual(E.path_kind(os.path.join(self.d, "x" * 5000)), "unreadable")  # ENAMETOOLONG

    def test_path_kind_permission_denied_is_unreadable(self):
        box = os.path.join(self.d, "box")
        os.mkdir(box)
        self.assertEqual(E.path_kind(os.path.join(box, "child")), "absent")  # control: readable box, no child
        self.lock(box)
        self.assertEqual(E.path_kind(os.path.join(box, "child")), "unreadable")
        self.assertFalse(os.path.exists(os.path.join(box, "child")))  # what os.path.exists says instead

    def test_in_progress(self):
        g = os.path.join(self.d, "gitdir")
        os.mkdir(g)
        self.assertEqual(E.in_progress(g), [])
        open(os.path.join(g, "MERGE_HEAD"), "w").close()
        os.mkdir(os.path.join(g, "rebase-merge"))
        self.assertEqual(E.in_progress(g), ["MERGE_HEAD", "rebase-merge"])
        self.lock(g)
        # review round 9 (RV8-1): every lock any engine write takes is checked, not only index.lock
        self.assertEqual(E.in_progress(g), [n + "?unreadable" for n in ("MERGE_HEAD", "CHERRY_PICK_HEAD",
                         "REVERT_HEAD", "BISECT_LOG", "rebase-merge", "rebase-apply", "index.lock", "HEAD.lock",
                         "AUTO_MERGE.lock", "packed-refs.lock", "reftable/tables.list.lock", "ORIG_HEAD.lock")])
        self.assertIn("refs/heads/main.lock?unreadable", E.in_progress(g, g, "main"))

    def probe(self, path, answer):
        r = scripted_runner(lambda repo, a: answer)
        return E.probe_child(r, path), r

    def test_probe_child_kinds(self):
        sub = os.path.join(self.d, "sub")
        self.assertEqual(self.probe(sub, ("exit", 0, sub + "\n", ""))[0], "absent")
        open(sub, "w").close()
        self.assertEqual(self.probe(sub, ("exit", 0, sub + "\n", ""))[0], "not-a-directory")
        os.unlink(sub)
        os.symlink(self.d, sub)
        self.assertEqual(self.probe(sub, ("exit", 0, sub + "\n", ""))[0], "not-a-directory")
        os.unlink(sub)
        os.mkdir(sub)
        kind, r = self.probe(sub, ("exit", 0, sub + "\n", ""))
        self.assertEqual(kind, "uninitialised")
        self.assertEqual(r.seen, [])  # no .git: git is not asked
        with open(os.path.join(sub, ".git"), "w") as fh:
            fh.write("gitdir: /nonexistent/broken\n")
        kind, r = self.probe(sub, ("exit", 0, sub + "\n", ""))
        self.assertEqual((kind, r.unresolved_for(sub)), ("repo", []))  # control: git answers with this path

    def test_probe_child_exit_128_is_unreadable_not_uninitialised(self):  # F1 (X01's class at this site)
        sub = os.path.join(self.d, "sub")
        os.mkdir(sub)
        with open(os.path.join(sub, ".git"), "w") as fh:
            fh.write("gitdir: /nonexistent/broken\n")
        kind, r = self.probe(sub, ("exit", 128, "", "fatal: not a git repository: /nonexistent/broken"))
        self.assertEqual(kind, "unreadable")
        self.assertEqual(r.unresolved_for(sub), ["rev-parse:rc:128"])

    def test_probe_child_foreign_toplevel_is_unreadable(self):  # a .git git ignores: rev-parse walks up
        sub = os.path.join(self.d, "sub")
        os.makedirs(os.path.join(sub, ".git"))
        kind, r = self.probe(sub, ("exit", 0, self.d + "\n", ""))
        self.assertEqual(kind, "unreadable")
        self.assertEqual(r.unresolved_for(sub), ["rev-parse:not-own-toplevel"])

    def test_probe_child_unreadable_parent(self):
        box = os.path.join(self.d, "box")
        os.mkdir(box)
        sub = os.path.join(box, "sub")
        self.lock(box)
        kind, r = self.probe(sub, ("exit", 0, sub + "\n", ""))
        self.assertEqual(kind, "unreadable")
        self.assertEqual(r.unresolved_for(sub), ["lstat:unreadable"])
        self.assertEqual(r.seen, [])

    def main_quiet(self, argv):
        import contextlib
        import io
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = E.main(argv)
        return code, out.getvalue(), err.getvalue()

    def test_start_directory_exit_128(self):  # class A "start-dir": 128 is "not a work tree" only without .git
        scripted_runner(lambda repo, a: ("exit", 128, "", "fatal: not a git repository"))
        code, out, err = self.main_quiet(["--check", "--root", self.d])
        self.assertEqual(code, E.EXIT_USAGE)
        self.assertIn("not inside a git work tree", err)
        with open(os.path.join(self.d, ".git"), "w") as fh:
            fh.write("gitdir: /nonexistent/broken\n")
        code, out, err = self.main_quiet(["--check", "--root", self.d])
        self.assertEqual(code, E.EXIT_BLIND)
        self.assertIn("RESULT: BLIND exit=6", out)


class Integrate(unittest.TestCase):  # review round 3, F3: --advance-pins never detaches a branch
    def tree(self, branch):
        import tempfile
        root = E.Repo("/nonexistent/root", ".", 0, None)
        self.root_gitdir = tempfile.mkdtemp(prefix="sync_unit_rootgitdir.")
        root.rec.update(initialised=True, branch="main", local_vs_target="equal", upstream_state="same",
                        head_before=SHA, _gitdir=self.root_gitdir)
        c = E.Repo("/nonexistent/root/libs/a", "libs/a", 1, root)
        self.gitdir = tempfile.mkdtemp(prefix="sync_unit_gitdir.")
        c.rec.update(initialised=True, branch=branch, own_org=True, head_before=SHA, target="b" * 40,
                     path_in_parent="libs/a", recorded_gitlink=SHA, _gitdir=self.gitdir,
                     pin={"state": "behind-main", "checkout": "at-pin", "gitlink": SHA})
        return root, c

    def tearDown(self):
        # made by mkdtemp in tree(); empty again: every write-in-progress marker was removed (review round 6, RV5-1)
        os.rmdir(self.gitdir)
        os.rmdir(self.root_gitdir)

    @staticmethod
    def make_answer(branch):
        """A stateful model of the two repositories, close to real git (round 5): symbolic-ref -q exits 1 on a
        detached HEAD, the parent's HEAD tree records the gitlink, and a checkout moves the submodule's HEAD."""
        head = {"/nonexistent/root": SHA, "/nonexistent/root/libs/a": SHA}

        def answer(repo, a):
            if a[:2] == ["ls-files", "-s"]:
                return "exit", 0, "160000 %s 0\tlibs/a\0" % SHA, ""
            if a[:4] == ["ls-tree", "-r", "-z", "HEAD"]:
                return "exit", 0, "160000 commit %s\tlibs/a\0" % SHA, ""
            if a[:1] == ["symbolic-ref"]:
                b = "main" if repo == "/nonexistent/root" else branch
                return ("exit", 0, "refs/heads/" + b + "\n", "") if b else ("exit", 1, "", "")
            if a[:3] == ["checkout", "--quiet", "--detach"]:
                head[repo] = a[3]
            if a[0] == "rev-parse":
                return "exit", 0, head.get(repo, SHA) + "\n", ""
            return "exit", 0, "", ""
        return answer

    @staticmethod
    def register(r, *repos):
        """What inspect_local does for each repository (review round 9: a git dir this run did not inspect is never
        written)."""
        for x in repos:
            r.register_site(x.rec["_gitdir"], x.rec.get("_common_dir"), x.rec.get("branch"))

    def run_integrate(self, branch):
        r = scripted_runner(self.make_answer(branch))
        root, c = self.tree(branch)
        self.register(r, root, c)
        E.integrate(r, [root, c], "main", True, False, False, {"integrate": True, "pins": True})
        return r, c

    def test_submodule_on_a_branch_is_kept(self):
        r, c = self.run_integrate("topic")
        self.assertIn({"op": "none", "why": "advance-skipped:submodule-on-branch"}, c.rec["actions"])
        self.assertEqual(c.rec.get("kept_on_branch"), "advance-pin")
        self.assertIn("kept-on-branch:advance-pin", E.reasons_for(c.rec, False, "main"))
        self.assertEqual([a for _, a in r.seen if a[0] in E.WRITE_SUBCOMMANDS], [])

    def test_detached_submodule_is_advanced(self):  # control: the same tree, detached, reaches the writer
        r, c = self.run_integrate(None)
        writes = [a for _, a in r.seen if a[0] in E.WRITE_SUBCOMMANDS]
        self.assertEqual(writes, [("checkout", "--quiet", "--detach", "b" * 40), ("add", "--", "libs/a")])
        self.assertNotIn("kept_on_branch", c.rec)

    def test_marker_unwritable_blocks_the_write(self):  # RV5-1 (round 6): no marker, no write
        r = scripted_runner(self.make_answer(None))
        root, c = self.tree(None)
        self.register(r, root, c)
        os.chmod(self.gitdir, 0o555)
        try:
            E.integrate(r, [root, c], "main", True, False, False, {"integrate": True, "pins": True})
        finally:
            os.chmod(self.gitdir, 0o755)
        self.assertIn({"op": "none", "why": "blocked:write-marker-unwritable", "for": "advance-pin"}, c.rec["actions"])
        self.assertEqual([a for _, a in r.seen if a[0] in E.WRITE_SUBCOMMANDS], [])

    def test_stage_pin_ended_by_its_limit_is_write_killed(self):  # RV5-1 (round 6): the parent's 'add' half
        inner = self.make_answer(None)

        def answer(repo, a):
            if a[:1] == ["add"]:
                return "timeout", None, "", ""  # what proc_run_git returns when the write's own limit ended it
            return inner(repo, a)
        r = scripted_runner(answer)
        root, c = self.tree(None)
        self.register(r, root, c)
        E.integrate(r, [root, c], "main", True, False, False, {"integrate": True, "pins": True})
        pin = [x for x in c.rec["actions"] if x.get("op") == "advance-pin"]
        self.assertEqual(pin[-1].get("why"), "write-killed:stage-pin")
        self.assertEqual((root.rec.get("write_killed"), root.rec.get("failed"), c.rec.get("failed")),
                         ("stage-pin", True, True))
        self.assertIn("write-killed:stage-pin", E.reasons_for(root.rec, False, "main"))
        self.assertEqual(E.read_marker(self.root_gitdir), "stage-pin")  # kept: the next run attributes leftovers
        self.assertIsNone(E.read_marker(self.gitdir))  # the child's checkout answered: its marker is gone
        E.clear_marker(self.root_gitdir)

    def test_a_stop_starts_no_write(self):  # RR40 (round 6): after a stop integrate starts no write, says why
        r = scripted_runner(self.make_answer(None))
        root, c = self.tree(None)
        self.register(r, root, c)
        E.STOP_REQUESTED.set()
        try:
            E.integrate(r, [root, c], "main", True, False, False, {"integrate": True, "pins": True})
        finally:
            E.STOP_REQUESTED.clear()
        self.assertIn({"op": "none", "why": "interrupted"}, c.rec["actions"])
        self.assertIn({"op": "none", "why": "interrupted"}, root.rec["actions"])
        self.assertEqual([a for _, a in r.seen if a[0] in E.WRITE_SUBCOMMANDS], [])
        self.assertEqual([a for _, a in r.seen if a[:1] == ("status",)], [])  # not even the pre-write re-read

    def test_head_after_is_read_for_every_repository(self):  # F2: never a copy of head_before
        r, c = self.run_integrate("topic")
        heads = [repo for repo, a in r.seen if a[:2] == ("rev-parse", "--verify")]
        self.assertEqual(sorted(heads), ["/nonexistent/root", "/nonexistent/root/libs/a"])
        self.assertEqual(c.rec["head_after"], SHA)


class TraceScrub(unittest.TestCase):  # review round 3, F7
    def test_every_trace_and_curl_verbose_variable_is_dropped(self):
        bad = {k: "1" for k in ("GIT_TRACE", "GIT_TRACE2", "GIT_TRACE2_EVENT", "GIT_TRACE2_PERF",
                                 "GIT_TRACE2_EVENT_NESTING", "GIT_TRACE2_CONFIG_PARAMS", "GIT_TRACE2_ENV_VARS",
                                 "GIT_TRACE_CURL", "GIT_TRACE_CURL_NO_DATA", "GIT_TRACE_PACKET", "GIT_TRACE_PACKFILE",
                                 "GIT_TRACE_PACK_ACCESS", "GIT_TRACE_PERFORMANCE", "GIT_TRACE_SETUP",
                                 "GIT_TRACE_SHALLOW", "GIT_TRACE_REFS", "GIT_TRACE_FSMONITOR", "GIT_TRACE_REDACT",
                                 "GIT_CURL_VERBOSE", "GIT_REDACT_COOKIES")}
        keep = {"PATH": "/bin", "MY_GIT_TRACE": "x", "XGIT_CURL_VERBOSE": "y", "GIT_CONFIG_GLOBAL": "/g"}
        env = E.git_env(dict(bad, **keep))
        self.assertEqual(sorted(k for k in bad if k in env), [])
        for k, v in keep.items():  # negative control: the scrub drops what it names, not everything
            self.assertEqual(env.get(k), v, k)


class LongSecrets(unittest.TestCase):  # review round 3, F9 / X05: no fixed-width cut, any length, any character
    def setUp(self):  # each test starts with an empty known-secret registry (an engine without one has nothing)
        if hasattr(E, "_KNOWN"):
            with E._KNOWN_LOCK:
                E._KNOWN.clear()

    tearDown = setUp
    LINE = "fatal: unable to access 'https://user:%s@host/o/r.git/': The requested URL returned error: 403"
    CLEAN = "fatal: unable to access 'https://host/o/r.git/': The requested URL returned error: 403"

    def test_long_secrets(self):
        for n in (1, 7, 8, 47, 48, 49, 64, 255, 256, 1000, 4096, 65536):
            secret = ("p4ss-w0rd." * (n // 10 + 1))[:n]
            self.assertIn(secret, self.LINE % secret)  # the needle is in the input
            self.assertEqual(E.redact(self.LINE % secret), self.CLEAN, n)
            # control needle: a string as long in the PATH (no userinfo) survives intact, so the check above is
            # not met by an engine that blanks long input
            path = "https://host/%s/r.git" % secret
            self.assertEqual(E.redact(path), path, n)

    def test_secret_holding_scheme_marks_and_at_signs(self):
        for secret in ("a://b", "x@y@z", "https://evil@host", "pa ss://w@rd", "%40:%2F%2F", "é日本@x://y"):
            self.assertEqual(E.redact(self.LINE % secret), self.CLEAN, secret)

    def test_fuzz(self):
        import random
        rnd = random.Random(20261113)  # fixed seed: the same cases on every run
        alphabet = ("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789" + "@:/ %#?!$&'()*+,;=~-._[]" +
                    "éß日本")
        for i in range(3000):
            n = rnd.choice((1, 2, 5, 8, 16, 47, 48, 49, 50, 100, 300, 2000))
            secret = "".join(rnd.choice(alphabet) for _ in range(n))
            for line, clean in ((self.LINE % secret, self.CLEAN),
                                ("ssh://git:%s@host:22/o/r" % secret, "ssh://host:22/o/r"),
                                ("a https://h/x\nfetch https://u:%s@h2/y\nb" % secret,
                                 "a https://h/x\nfetch https://h2/y\nb")):
                self.assertEqual(E.redact(line), clean, (i, secret))
        for clean in (self.CLEAN, "ssh://host:22/o/r", "git@host:o/r.git"):  # control: clean input is untouched
            self.assertEqual(E.redact(clean), clean)

    def test_known_secret_quoted_without_its_url(self):
        E.register_secret("https://user:hunter2hunter2@host/r")
        self.assertEqual(E.redact("remote said: bad password hunter2hunter2."),
                         "remote said: bad password [REDACTED].")
        self.assertEqual(E.redact("remote said: bad password."), "remote said: bad password.")  # control

    def test_register_secret_pieces(self):
        E.register_secret("https://u:aaaaaaaaaa\nbbbbbbbbbbbb@host/r")  # a value holding a newline
        self.assertEqual(E.redact("x bbbbbbbbbbbb y aaaaaaaaaa"), "x [REDACTED] y [REDACTED]")
        E.register_secret("https://git:short@host/r")
        with E._KNOWN_LOCK:
            known = set(E._KNOWN)
        self.assertIn("git:short", known)
        self.assertNotIn("short", known)  # under 8 characters: never registered, ordinary words survive
        self.assertEqual(E.redact("a short word"), "a short word")
        E.register_secret("git@host:o/r.git")  # no scheme: nothing to register
        with E._KNOWN_LOCK:
            self.assertEqual(set(E._KNOWN), known)

    def test_redact_url_whole_value(self):
        self.assertEqual(E.redact_url("https://u:p\nq@host/r"), "https://host/r")
        self.assertEqual(E.redact_url("https://u:%s@host/r" % ("z" * 5000)), "https://host/r")
        self.assertEqual(E.redact_url("git@host:o/r.git"), "git@host:o/r.git")

    def test_report_keys(self):
        hits = []
        rep = E.redact_report({"https://u:topsecretpw@h/r": "v"}, "report", hits)
        self.assertEqual(rep, {"https://h/r": "v"})
        self.assertEqual(hits, ["report.https://h/r"])

    def test_argparse_error_is_redacted(self):
        import contextlib
        import io
        err = io.StringIO()
        with contextlib.redirect_stderr(err), contextlib.redirect_stdout(io.StringIO()):
            code = E.main(["--check", "--frob=https://u:hunter2hunter2@host/r"])
        self.assertEqual(code, E.EXIT_USAGE)
        self.assertIn("unrecognized arguments", err.getvalue())  # the message was printed, not swallowed
        self.assertNotIn("hunter2", err.getvalue())

    def test_internal_error_is_redacted(self):
        import contextlib
        import io
        F = fresh_engine("sync_engine_entry")

        def boom(argv):
            raise RuntimeError("boom https://u:topsecret99@host/r")
        F.main = boom
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = F.entry([])
        self.assertEqual(code, F.EXIT_FAIL)
        self.assertIn("RESULT: FAILED exit=1", out.getvalue())
        self.assertIn("internal error", err.getvalue())
        self.assertNotIn("topsecret99", err.getvalue())


# ───────────────────────────── review round 4 findings (round 5 tests) ─────────────────────────────
def old_strip_userinfo(text):
    """The round-4 algorithm (regex finditer + rfind per match), kept here as the equivalence oracle."""
    import re
    out, pos = [], 0
    for m in re.finditer(r"[A-Za-z][A-Za-z0-9+.-]*://", text):
        if m.start() < pos:
            continue
        start = m.end()
        nl = text.find("\n", start)
        end = nl if nl != -1 else len(text)
        at = text.rfind("@", start, end)
        if at == -1:
            continue
        out.append(text[pos:start])
        pos = at + 1
    out.append(text[pos:])
    return "".join(out)


class RoundFive(unittest.TestCase):
    def test_strip_userinfo_equals_round4_on_random_text(self):  # RV4-3: same output, linear time
        import random
        rnd = random.Random(20261113)
        alphabet = ["a", "Z", "9", "+", ".", "-", ":", "/", "@", " ", "\n", "://", "h://", "1://", "x@y"]
        for _ in range(4000):
            t = "".join(rnd.choice(alphabet) for _ in range(rnd.randint(0, 40)))
            self.assertEqual(E.strip_userinfo(t), old_strip_userinfo(t), repr(t))

    def test_strip_userinfo_is_linear(self):
        import time as t_
        for text in ("remote: " + "abc" * 300000, ("https://" + "a" * 50 + " ") * 20000 + "@x", "a://" * 200000):
            t0 = t_.monotonic()
            E.strip_userinfo(text)
            self.assertLess(t_.monotonic() - t0, 2.0, len(text))

    def _fake_git(self, body):
        import tempfile
        d = tempfile.mkdtemp(prefix="sync_unit_r5.")
        fake = os.path.join(d, "git")
        with open(fake, "w", encoding="utf-8") as fh:
            fh.write("#!%s -I\nimport os, sys\n%s\n" % (sys.executable, body))
        os.chmod(fake, 0o700)
        return d, fake

    def test_stdout_cap_is_no_answer(self):  # RV4-4: stdout beyond OUT_CAP is "output-too-large", never kept
        import shutil
        F = fresh_engine("sync_engine_cap")
        F.OUT_CAP = 1 << 20
        d, fake = self._fake_git("c = b'x' * 65536\nfor _ in range(64):\n    os.write(1, c)")
        try:
            kind, code, out, _ = F.proc_run_git(fake, d, ["status"], {"PATH": "/usr/bin:/bin"}, 30)
            self.assertEqual((kind, code, out), ("output-too-large", None, ""))
        finally:
            shutil.rmtree(d)  # made by mkdtemp in _fake_git

    def test_stderr_tail_drops_partial_first_line(self):  # RV4-3/4: only the tail is kept, no half URL
        import shutil
        F = fresh_engine("sync_engine_tail")
        body = ("os.write(2, b'https://user:SECRETpw@h.example/x ' + b'y' * (300 * 1024) + b'\\n')\n"
                "os.write(2, b'last line\\n')\nsys.exit(1)")
        d, fake = self._fake_git(body)
        try:
            kind, code, _, err = F.proc_run_git(fake, d, ["status"], {"PATH": "/usr/bin:/bin"}, 30)
            self.assertEqual((kind, code), ("exit", 1))
            self.assertLessEqual(len(err), F.ERR_TAIL + 64)
            self.assertTrue(err.startswith("[earlier stderr dropped]"), err[:60])
            self.assertIn("last line", err)
            self.assertNotIn("yyyy", err)  # the partial first line of the tail is dropped
        finally:
            shutil.rmtree(d)  # made by mkdtemp in _fake_git

    def test_stop_interrupts_a_read_never_a_write(self):  # RV4-5
        import shutil
        import threading
        F = fresh_engine("sync_engine_stop")
        d, fake = self._fake_git("import time\ntime.sleep(3)\nsys.exit(0)")
        try:
            threading.Timer(0.3, F.STOP_REQUESTED.set).start()
            t0 = F.time.monotonic()
            kind = F.proc_run_git(fake, d, ["status"], {"PATH": "/usr/bin:/bin"}, 30, 1)[0]
            self.assertEqual(kind, "interrupted")
            self.assertLess(F.time.monotonic() - t0, 2.5)
            kind, code = F.proc_run_git(fake, d, ["merge", "--ff-only", SHA], {"PATH": "/usr/bin:/bin"}, 30, 0)[:2]
            self.assertEqual((kind, code), ("exit", 0))  # a write runs to its end
            r = F.Runner(fake, 10, F.time.monotonic() + 600)
            res = r.run(d, ["status"], ok=(0,))
            self.assertEqual(res.why, "interrupted")  # refused before spawning after a stop
        finally:
            shutil.rmtree(d)  # made by mkdtemp in _fake_git

    def test_read_branch_three_states(self):  # RV4-1: detached and unread are told apart
        r = fake_runner(("exit", 0, "refs/heads/main\n", ""))  # the FULL ref since round 11 (RV10-1)
        self.assertEqual(E.read_branch(r, "/r"), ("branch", "main"))
        r = fake_runner(("exit", 1, "", ""))
        self.assertEqual(E.read_branch(r, "/r"), ("detached", None))
        r = fake_runner(("exit", 128, "", "fatal"))
        self.assertEqual(E.read_branch(r, "/r"), ("unknown", None))
        r = fake_runner(("exit", 0, "\n", ""))
        self.assertEqual(E.read_branch(r, "/r"), ("unknown", None))
        self.assertTrue(r.unresolved_for("/r"))

    def integrate_with(self, tweak):
        """The Integrate fixture (detached submodule, advance-pins) with one answer of the git model replaced."""
        fx = Integrate("test_detached_submodule_is_advanced")
        base = Integrate.make_answer(None)

        def answer(repo, a):
            got = tweak(repo, a)
            return got if got is not None else base(repo, a)
        r = scripted_runner(answer)
        root, c = fx.tree(None)
        Integrate.register(r, root, c)
        try:
            E.integrate(r, [root, c], "main", True, False, False, {"integrate": True, "pins": True})
        finally:
            fx.tearDown()
        writes = [a for _, a in r.seen if a[0] in E.WRITE_SUBCOMMANDS]
        return r, c, writes

    def test_unread_branch_at_write_time_blocks(self):  # RV4-1: an unread symbolic ref is never "detached"
        r, c, writes = self.integrate_with(
            lambda repo, a: ("exit", 128, "", "fatal") if a[:1] == ["symbolic-ref"] and repo.endswith("libs/a")
            else None)
        self.assertEqual(writes, [])
        self.assertIn("unresolved:branch-recheck", json.dumps(c.rec["actions"]))

    def test_branch_at_write_time_blocks_a_pin_write(self):  # RV4-1: a user checked out a branch: never detached
        r, c, writes = self.integrate_with(
            lambda repo, a: ("exit", 0, "refs/heads/user-branch\n", "") if a[:1] == ["symbolic-ref"] and repo.endswith("libs/a")
            else None)
        self.assertEqual(writes, [])
        self.assertIn("blocked:branch-changed-before-write", json.dumps(c.rec["actions"]))

    def test_moved_head_at_write_time_blocks(self):  # RV4-1: a user commit after inspection is never overwritten
        r, c, writes = self.integrate_with(
            lambda repo, a: ("exit", 0, "c" * 40 + "\n", "") if a[:2] == ["rev-parse", "--verify"]
            and repo.endswith("libs/a") else None)
        self.assertEqual(writes, [])
        self.assertIn("blocked:head-changed-before-write", json.dumps(c.rec["actions"]))

    def test_parent_head_tree_changed_blocks(self):  # RV4-2: a commit in the parent moved the gitlink
        r, c, writes = self.integrate_with(
            lambda repo, a: ("exit", 0, "160000 commit %s\tlibs/a\0" % ("d" * 40), "")
            if a[:4] == ["ls-tree", "-r", "-z", "HEAD"] else None)
        self.assertEqual(writes, [])
        self.assertIn("blocked:parent-index-changed", json.dumps(c.rec["actions"]))

    def test_head_not_at_target_after_write_is_a_failure(self):  # RV4-1 step 6: the write is verified
        r, c, writes = self.integrate_with(
            lambda repo, a: ("exit", 0, SHA + "\n", "") if a[:1] == ["rev-parse"] else None)
        self.assertEqual(writes, [("checkout", "--quiet", "--detach", "b" * 40)])  # never staged after a bad write
        self.assertTrue(c.rec.get("failed"))
        self.assertIn("head-not-at-target-after-write", json.dumps(c.rec["actions"]))

    def test_second_signal_is_a_hard_stop(self):  # RV4-5: the second signal also ends the final reads
        F = fresh_engine("sync_engine_sig")
        F.on_stop_signal(15, None)
        self.assertTrue(F.STOP_REQUESTED.is_set())
        self.assertFalse(F.HARD_STOP.is_set())
        F.on_stop_signal(15, None)
        self.assertTrue(F.HARD_STOP.is_set())

    def test_round5_environment_scrub(self):  # RV4-6/7: variables that weaken the call are dropped
        bad = {"GIT_ALLOW_PROTOCOL": "ext", "GIT_PROTOCOL_FROM_USER": "1", "SSH_ASKPASS_REQUIRE": "force",
               "GIT_SSL_NO_VERIFY": "1", "GIT_ASKPASS": "/x/ask", "PATH": "/bin"}
        env = E.git_env(bad)
        for k in ("GIT_ALLOW_PROTOCOL", "GIT_PROTOCOL_FROM_USER", "GIT_SSL_NO_VERIFY"):
            self.assertNotIn(k, env)
        self.assertEqual((env["GIT_ASKPASS"], env["SSH_ASKPASS_REQUIRE"], env["PATH"]), ("", "never", "/bin"))

    def test_scp_like_org_segments(self):  # the linear rewrite of the scp-like test keeps its meaning
        self.assertEqual(E.url_org_segments("git@github.com:HelixDevelopment/x.git"), ["HelixDevelopment"])
        self.assertEqual(E.url_org_segments("host:org/x"), ["org"])
        self.assertEqual(E.url_org_segments("/abs/org/x"), ["abs", "org"])


class RoundSix(unittest.TestCase):  # review round 6 (RV5-1 .. RV5-7)
    def limits_runner(self, deadline_in, F=None):
        """A real Runner whose spawn point records (args, limit, level) and answers exit 0."""
        F = F or fresh_engine("sync_engine_r6_limits")
        seen = []

        def spawn(git_bin, repo, args, env, limit, level=1):
            F.check_git_args(args)
            seen.append((tuple(args), limit, level))
            return "exit", 0, "", ""
        F.proc_run_git = spawn
        r = F.Runner("/nonexistent/git", 7, F.time.monotonic() + deadline_in, 1234)
        return F, r, seen

    def test_write_has_its_own_limit_not_the_deadline(self):  # RV5-1: a write never gets min(timeout, deadline)
        F, r, seen = self.limits_runner(2)
        res = r.run("/r", ["merge", "--ff-only", SHA], ok=(0,), write=True, token=live_token(self, F, r))
        self.assertTrue(res.answered)
        self.assertEqual(seen[-1], (("merge", "--ff-only", SHA), 1234, 0))

    def test_no_process_starts_after_a_second_signal(self):  # RR39 (round 6): a final read is refused BEFORE spawn
        F, r, seen = self.limits_runner(10)
        F.STOP_REQUESTED.set()
        F.HARD_STOP.set()
        res = r.run("/r", ["rev-parse", "--verify", "-q", "HEAD^{commit}"], ok=(0, 1), final=True)
        self.assertEqual((res.answered, res.why, seen, r.calls), (False, "interrupted", [], 0))
        F.HARD_STOP.clear()  # control: after the FIRST signal only, a final read still runs
        res = r.run("/r", ["rev-parse", "--verify", "-q", "HEAD^{commit}"], ok=(0, 1), final=True)
        self.assertEqual((res.answered, len(seen)), (True, 1))

    def test_write_never_starts_after_the_deadline(self):
        F, r, seen = self.limits_runner(-1)
        res = r.run("/r", ["merge", "--ff-only", SHA], ok=(0,), write=True, token=live_token(self, F, r))
        self.assertEqual((res.answered, res.why, seen), (False, "deadline", []))

    def test_second_half_of_a_write_and_final_reads_run_after_the_deadline(self):
        F, r, seen = self.limits_runner(-1)
        self.assertTrue(r.run("/p", ["add", "--", "libs/a"], ok=(0,), write=True, final=True,
                              token=live_token(self, F, r, "stage-pin")).answered)
        self.assertEqual(seen[-1][1:], (1234, 0))
        self.assertTrue(r.run("/p", ["rev-parse", "--verify", "-q", "HEAD^{commit}"], ok=(0, 1), final=True).answered)
        self.assertEqual(seen[-1][1:], (10, 2))  # at most 10 seconds once the deadline has passed
        self.assertFalse(r.run("/p", ["remote"], ok=(0,)).answered)  # an ordinary read is still refused

    def test_ordinary_read_keeps_the_deadline_bound(self):
        F, r, seen = self.limits_runner(30)
        r.run("/p", ["remote"], ok=(0,))
        self.assertLessEqual(seen[-1][1], 30)
        self.assertGreater(seen[-1][1], 20)

    def test_write_killed_by_its_limit_is_a_known_failure(self):
        F = fresh_engine("sync_engine_r6_wk")
        F.proc_run_git = lambda *a, **k: ("timeout", None, "", "timeout after 3s; ended by SIGTERM")
        r = F.Runner("/nonexistent/git", 7, F.time.monotonic() + 600, 3)
        res = r.run("/r", ["merge", "--ff-only", SHA], ok=(0, 1, 128), write=True, token=live_token(self, F, r))
        self.assertEqual((res.answered, res.why), (False, "write-killed"))
        self.assertEqual(r.unresolved_for("/r"), [])  # never an unknown state: the write's end is known
        res = r.run("/r", ["remote"], ok=(0,))  # a READ timeout stays a no-answer (control)
        self.assertEqual(r.unresolved_for("/r"), ["remote:timeout"])

    def fake_git(self, body):
        import tempfile
        d = tempfile.mkdtemp(prefix="sync_unit_r6.")
        fake = os.path.join(d, "git")
        with open(fake, "w", encoding="utf-8") as fh:
            fh.write("#!/bin/sh\n" + body + "\n")
        os.chmod(fake, 0o700)
        self.addCleanup(self.rm_fake, d, fake)
        return d, fake

    @staticmethod
    def rm_fake(d, fake):
        os.unlink(fake)
        os.rmdir(d)

    def test_a_stop_signal_never_ends_a_write(self):  # level 0 ignores STOP_REQUESTED and HARD_STOP
        F = fresh_engine("sync_engine_r6_stop")
        d, fake = self.fake_git("sleep 1; exit 0")
        F.STOP_REQUESTED.set()
        F.HARD_STOP.set()
        self.assertEqual(F.proc_run_git(fake, d, ["status"], {"PATH": "/usr/bin:/bin"}, 30, 0)[:2], ("exit", 0))
        self.assertEqual(F.proc_run_git(fake, d, ["status"], {"PATH": "/usr/bin:/bin"}, 30, 1)[0], "interrupted")

    def test_write_limit_ends_the_call_with_sigterm_first(self):  # a real child: SIGTERM ends `sleep`
        F = fresh_engine("sync_engine_r6_term")
        d, fake = self.fake_git("exec sleep 30")
        kind, code, out, err = F.proc_run_git(fake, d, ["status"], {"PATH": "/usr/bin:/bin"}, 1, 0)
        self.assertEqual(kind, "timeout")
        self.assertIn("ended by SIGTERM", err)

    def test_write_gets_the_long_grace_a_read_the_short_one(self):  # RV5-1 (Q17): grace per level
        F = fresh_engine("sync_engine_r6_grace")
        d, fake = self.fake_git("exec sleep 30")
        real, graces = F.proc_kill_group, []

        def recorder(p, grace):
            graces.append(grace)
            return real(p, grace)
        F.proc_kill_group = recorder
        F.proc_run_git(fake, d, ["status"], {"PATH": "/usr/bin:/bin"}, 1, 0)   # level 0: a write
        F.proc_run_git(fake, d, ["status"], {"PATH": "/usr/bin:/bin"}, 1, 1)   # level 1: a read
        self.assertEqual(graces, [F.WRITE_KILL_GRACE, F.KILL_GRACE])
        self.assertGreater(F.WRITE_KILL_GRACE, F.KILL_GRACE)

    def test_config_read_shapes(self):  # RV5-7: exactly two new read-only shapes
        ok = (["config", "-z", "--get-regexp", "^submodule\\\\..*\\\\.update$"],
              ["config", "--file", ".gitmodules", "-z", "--get-regexp", "x"])
        for a in ok:
            E.check_git_args(a)
        for a in (["config", "--file", "/etc/passwd", "-z", "--get-regexp", "x"],
                  ["config", "-z", "--get-regexp", "x", "y"], ["config", "-z", "core.x", "v"],
                  ["config", "--file", ".gitmodules", "-z", "submodule.a.url", "x"],
                  ["config", "--file", ".gitmodules", "-z", "--get-regexp", "x", "y"]):
            with self.assertRaises(E.GitRefused, msg=a):
                E.check_git_args(a)

    def test_update_strategies(self):
        gm = ("submodule.libs/a.path\nlibs/a\0submodule.libs/a.update\nnone\0submodule.b.path\nb\0"
              "submodule.c.path\nc\0submodule.c.update\n!true\0submodule.d.path\nd\0")
        cf = "submodule.b.update\nRebase\0submodule.libs/a.update\ncheckout\0"

        def answer(repo, a):
            return "exit", 0, gm if "--file" in a else cf, ""
        r = scripted_runner(answer)
        self.assertEqual(E.update_strategies(r, "/p"),
                         {"libs/a": "checkout", "b": "rebase", "c": "command", "d": "checkout"})
        r = scripted_runner(lambda repo, a: ("exit", 1, "", ""))  # no .gitmodules, nothing configured
        self.assertEqual(E.update_strategies(r, "/p"), {})
        r = scripted_runner(lambda repo, a: ("signal", 9, "", ""))  # no answer: never "checkout"
        self.assertIsNone(E.update_strategies(r, "/p"))

    def test_write_marker_round_trip(self):
        import tempfile
        d = tempfile.mkdtemp(prefix="sync_unit_marker.")
        try:
            self.assertIsNone(E.read_marker(d))
            self.assertEqual(E.write_marker(d, "fast-forward", SHA, "r1", "r1:1:1"), E.MARKER_WRITTEN)
            self.assertEqual(E.read_marker(d), "fast-forward")
            self.assertEqual(E.marker_write_id(d), "r1:1:1")
            before = read_bytes(os.path.join(d, E.WRITE_MARKER))  # round 8 (RV7-1): never overwritten
            self.assertEqual(E.write_marker(d, "advance-pin", SHA, "r2", "r2:1:1"), E.MARKER_EXISTS)
            self.assertEqual(read_bytes(os.path.join(d, E.WRITE_MARKER)), before)
            E.clear_marker(d)
            self.assertIsNone(E.read_marker(d))
            E.clear_marker(d)  # absent: no error
            with open(os.path.join(d, E.WRITE_MARKER), "w") as fh:
                fh.write("{garbage")
            self.assertEqual(E.read_marker(d), "unknown")  # unreadable is never "no marker"
            os.unlink(os.path.join(d, E.WRITE_MARKER))
            os.symlink("/nonexistent/x", os.path.join(d, E.WRITE_MARKER))
            # never written through a link (O_EXCL: the link itself is "already there")
            self.assertEqual(E.write_marker(d, "fast-forward", SHA, "r1"), E.MARKER_EXISTS)
            # review round 9: a link at the marker path is no marker (never opened); in_progress reports it
            self.assertIsNone(E.read_marker(d))
            self.assertIn("write-marker-path-not-a-file:symlink", E.in_progress(d))
            self.assertIsNone(E.marker_write_id(d))
            os.unlink(os.path.join(d, E.WRITE_MARKER))
            self.assertEqual(E.write_marker("", "fast-forward", SHA, "r1"), E.MARKER_UNWRITABLE)  # no git dir
            open(os.path.join(d, "index.lock"), "w").close()
            self.assertEqual(E.locks_left(d, "main"), ["index.lock"])
            os.unlink(os.path.join(d, "index.lock"))
        finally:
            os.rmdir(d)

    def test_marker_attribution_reasons(self):
        rec = {"initialised": True, "kind": "root", "branch": "main", "dirty": True, "in_progress": ["index.lock"],
               "write_interrupted_earlier": "fast-forward", "upstream_state": "linear"}
        reasons = E.reasons_for(rec, False, "main")
        self.assertIn("write-interrupted-earlier:fast-forward", reasons)
        self.assertIn("dirty-tree-since-write-interrupted", reasons)
        self.assertIn("in-progress-since-write-interrupted:index.lock", reasons)
        self.assertNotIn("dirty-tree", reasons)
        rec.update(dirty=False, in_progress=[])  # a marker that left nothing is not a reason
        self.assertEqual([x for x in E.reasons_for(rec, False, "main") if "write" in x], [])

    def test_prompt_ends_on_a_stop_signal(self):  # RV5-5: the wait is never a blocking read
        import time as t_
        F = fresh_engine("sync_engine_r6_tty")
        master, slave = os.openpty()
        try:
            tty = object.__new__(F.Tty)
            tty.fd = slave
            F.STOP_REQUESTED.set()
            import threading as th_
            got = []
            w = th_.Thread(target=lambda: got.append(tty.ask("Proceed?")), daemon=True)
            t0 = t_.monotonic()
            w.start()
            w.join(3)  # bounded: an engine that waits for Enter fails this ASSERTION, never by the suite timeout (Q12)
            ended = not w.is_alive()
            if not ended:
                os.write(master, b"\n")  # release the waiting prompt so the test process can end
                w.join(5)
            self.assertTrue(ended, "the prompt did not end on the stop signal")
            self.assertEqual(got, [False])
            self.assertLess(t_.monotonic() - t0, 2)
            F.STOP_REQUESTED.clear()
            os.write(master, b"y\n")  # control: an answer is still read
            self.assertTrue(tty.ask("Proceed?"))
        finally:
            os.close(master)
            os.close(slave)


class RoundSeven(unittest.TestCase):  # review round 7 (RV6-1 .. RV6-3)
    def runner(self, F, deadline_in):
        seen = []

        def spawn(git_bin, repo, args, env, limit, level=1):
            F.check_git_args(args)
            seen.append(tuple(args))
            return "exit", 0, "", ""
        F.proc_run_git = spawn
        return F.Runner("/nonexistent/git", 7, F.time.monotonic() + deadline_in, 1234), seen

    def test_write_refused_now_is_runs_own_refusal(self):  # RV6-1: the pre-check and r.run never disagree
        for stop in (False, True):
            for hard in (False, True):
                for left in (30, -1):
                    for final in (False, True):
                        F = fresh_engine("sync_engine_r7_pred")
                        r, seen = self.runner(F, left)
                        if stop:
                            F.STOP_REQUESTED.set()
                        if stop and hard:
                            F.HARD_STOP.set()
                        tok = live_token(self, F, r)
                        pred = r.write_refused_now(final=final)
                        res = r.run("/r", ["merge", "--ff-only", SHA], ok=(0,), write=True, final=final, token=tok)
                        self.assertEqual(pred, not res.started, (stop, hard, left, final))
                        self.assertEqual(pred, seen == [], (stop, hard, left, final))

    def test_started_is_false_only_without_a_process(self):
        F = fresh_engine("sync_engine_r7_started")
        r, seen = self.runner(F, 30)
        # refused by the allow-list (round 8: with a live token, else the token check would refuse it first)
        pushed = r.run("/r", ["push", "origin"], ok=(0,), write=True, token=live_token(self, F, r))
        self.assertEqual((pushed.why, pushed.started), ("refused", False))
        for kind, code, started in (("not-runnable", None, False), ("exit", 0, True), ("exit", 5, True),
                                    ("signal", 9, True), ("timeout", None, True), ("output-too-large", None, True)):
            F.proc_run_git = lambda *a, _k=kind, _c=code, **kw: (_k, _c, "", "")
            res = r.run("/r", ["merge", "--ff-only", SHA], ok=(0, 1, 128), write=True, token=live_token(self, F, r))
            self.assertEqual(res.started, started, kind)
        F.STOP_REQUESTED.set()
        self.assertFalse(r.run("/r", ["remote"], ok=(0,)).started)  # interrupted before spawn
        F.STOP_REQUESTED.clear()
        r2, _ = self.runner(F, -1)
        self.assertFalse(r2.run("/r", ["remote"], ok=(0,)).started)  # deadline before spawn

    def test_half_written_marker_is_removed(self):  # a created but unwritten marker would read 'unknown' later
        import tempfile
        F = fresh_engine("sync_engine_r7_half")
        d = tempfile.mkdtemp(prefix="sync_unit_r7.")
        real_os = F.os

        class FailingWrite:
            def __getattr__(self, name):
                if name in ("write", "fsync"):
                    def boom(*a):
                        raise OSError(28, "No space left on device")
                    return boom
                return getattr(real_os, name)
        try:
            F.os = FailingWrite()
            self.assertEqual(F.write_marker(d, "fast-forward", SHA, "r1"), F.MARKER_UNWRITABLE)
            F.os = real_os
            self.assertFalse(os.path.exists(os.path.join(d, F.WRITE_MARKER)))
            self.assertIsNone(F.read_marker(d))
            with open(os.path.join(d, F.WRITE_MARKER), "w") as fh:  # an EARLIER marker is never removed by a failure
                fh.write(json.dumps({"op": "advance-pin"}))
            F.os = FailingWrite()
            self.assertEqual(F.write_marker(d, "fast-forward", SHA, "r1"), F.MARKER_EXISTS)
            F.os = real_os
            self.assertTrue(os.path.exists(os.path.join(d, F.WRITE_MARKER)))
            self.assertEqual(F.read_marker(d), "advance-pin")  # its content too
        finally:
            F.os = real_os
            for n in os.listdir(d):
                os.unlink(os.path.join(d, n))
            os.rmdir(d)

    def test_lock_only_leftover_is_attributed(self):  # RV6-2 (mutant RV6B): an in-progress-only leftover
        rec = {"initialised": True, "kind": "root", "branch": "main", "dirty": False, "in_progress": ["index.lock"],
               "write_interrupted_earlier": "fast-forward", "upstream_state": "linear"}
        reasons = E.reasons_for(rec, False, "main")
        self.assertIn("write-interrupted-earlier:fast-forward", reasons)
        self.assertIn("in-progress-since-write-interrupted:index.lock", reasons)
        self.assertNotIn("in-progress:index.lock", reasons)

    def test_flock_error_is_not_another_run(self):  # RV6-3 (mutant RV6E): ENOLCK is not EWOULDBLOCK
        import errno
        import tempfile
        F = fresh_engine("sync_engine_r7_flock")
        d = tempfile.mkdtemp(prefix="sync_unit_r7l.")
        real = F.fcntl

        class Flock:
            def __init__(self, exc):
                self.exc = exc

            def flock(self, fd, how):
                raise self.exc

            def __getattr__(self, name):
                return getattr(real, name)
        x = type("X", (), {})()
        x.rec = {"_common_dir": d}
        try:
            for exc, held in ((OSError(errno.ENOLCK, "No locks available"), False),
                              (BlockingIOError(errno.EWOULDBLOCK, "busy"), True)):
                fds = []
                F.fcntl = Flock(exc)
                got = F.lock_repositories([x], "/nonexistent-root-common", fds)
                F.fcntl = real
                for fd_ in fds:
                    os.close(fd_)
                self.assertEqual((got[0], got[1]), (os.path.join(os.path.realpath(d), "helix-sync-upstreams.lock"),
                                                    held), exc)
        finally:
            F.fcntl = real
            for n in os.listdir(d):
                os.unlink(os.path.join(d, n))
            os.rmdir(d)


class RoundEight(unittest.TestCase):  # review round 8 (RV7-1): the per-git-dir marker state machine
    def setUp(self):
        import tempfile
        self.d = tempfile.mkdtemp(prefix="sync_unit_r8.")
        self.r = E.Runner("/nonexistent/git", 10, E.time.monotonic() + 600, 4321)
        self.r.run_id = "r8"
        self.r.register_site(self.d, self.d, "main")

    def tearDown(self):
        for n in os.listdir(self.d):
            os.unlink(os.path.join(self.d, n))
        os.rmdir(self.d)

    def test_transition_table_is_exactly_the_declared_one(self):
        states = (E.GD_NONE, E.GD_EARLIER, E.GD_WRITING, E.GD_KILLED, E.GD_INTERRUPTED, E.GD_CLEARED)
        allowed = {(E.GD_NONE, E.GD_WRITING), (E.GD_NONE, E.GD_EARLIER), (E.GD_NONE, E.GD_CLEARED),
                   (E.GD_CLEARED, E.GD_WRITING), (E.GD_WRITING, E.GD_CLEARED), (E.GD_WRITING, E.GD_KILLED),
                   (E.GD_WRITING, E.GD_INTERRUPTED)}
        for a in states:
            for b in states:
                r = E.Runner("/nonexistent/git", 10, E.time.monotonic() + 600)
                if a != E.GD_NONE:
                    r.gitdirs[os.path.realpath(self.d)] = a
                self.assertEqual(r.gd_move(self.d, b), (a, b) in allowed, (a, b))
                self.assertEqual(r.gd_state(self.d), b if (a, b) in allowed else a, (a, b))
        self.assertEqual(set(E.GD_UNRESOLVED), {E.GD_EARLIER, E.GD_WRITING, E.GD_KILLED, E.GD_INTERRUPTED})

    def test_every_unresolved_state_blocks_a_write(self):
        self.assertIsNone(E.gitdir_write_block(self.r, self.d))
        self.assertEqual(E.gitdir_write_block(self.r, ""), "unknown-git-dir")
        for st in E.GD_UNRESOLVED:
            self.r.gitdirs[os.path.realpath(self.d)] = st
            self.assertEqual(E.gitdir_write_block(self.r, self.d), "earlier-write-unresolved:" + st)
        self.r.gitdirs[os.path.realpath(self.d)] = E.GD_CLEARED
        self.assertIsNone(E.gitdir_write_block(self.r, self.d))
        open(os.path.join(self.d, "index.lock"), "w").close()
        self.assertEqual(E.gitdir_write_block(self.r, self.d), "in-progress:index.lock")
        os.unlink(os.path.join(self.d, "index.lock"))
        open(os.path.join(self.d, E.WRITE_MARKER), "w").close()
        self.assertEqual(E.gitdir_write_block(self.r, self.d), "write-marker-present")

    def test_token_refusals(self):
        self.assertEqual(self.r.token_refusal(None), "no-write-token")
        tok, why = E.begin_write(self.r, self.d, "fast-forward", SHA)
        self.assertIsNone(why)
        self.assertIsNone(self.r.token_refusal(tok))
        self.assertTrue(tok.write_id.startswith("r8:"))
        self.assertEqual(E.marker_write_id(self.d), tok.write_id)
        os.unlink(os.path.join(self.d, E.WRITE_MARKER))
        E.write_marker(self.d, "fast-forward", SHA, "other", "other:1:1")
        self.assertEqual(self.r.token_refusal(tok), "write-marker-not-ours")
        E.end_write(self.r, tok, E.GitResult(False, None, "", "", "write-marker-not-ours", started=False))
        self.assertEqual(E.marker_write_id(self.d), "other:1:1")  # a foreign marker is never removed
        self.assertEqual(self.r.gd_state(self.d), E.GD_INTERRUPTED)
        self.assertEqual(self.r.token_refusal(tok), "write-token-stale")

    def test_end_write_transitions(self):
        cases = ((E.GitResult(True, 0, "", "", None), E.GD_CLEARED, False, True),
                 (E.GitResult(True, 1, "", "", None), E.GD_CLEARED, False, True),  # RV7E: answered, settled: clears
                 # review round 9 (RV8-1): answered, but the repository shows a half-done write: marker kept
                 (E.GitResult(True, 128, "", "", None), E.GD_INTERRUPTED, True, False),
                 (E.GitResult(False, None, "", "", "refused", started=False), E.GD_CLEARED, False, True),
                 (E.GitResult(False, None, "", "", "refused", started=False), E.GD_CLEARED, False, False),
                 (E.GitResult(False, None, "", "", "write-killed"), E.GD_KILLED, True, True),
                 (E.GitResult(False, 9, "", "", "signal"), E.GD_INTERRUPTED, True, True))
        for res, state, kept, settled in cases:
            r = E.Runner("/nonexistent/git", 10, E.time.monotonic() + 600)
            r.run_id = "r8"
            r.register_site(self.d, self.d, None)
            tok, why = E.begin_write(r, self.d, "advance-pin", SHA)
            self.assertIsNone(why)
            E.end_write(r, tok, res, settled)
            self.assertEqual(r.gd_state(self.d), state, res.why)
            self.assertEqual(os.path.exists(os.path.join(self.d, E.WRITE_MARKER)), kept, res.why)
            if kept:
                os.unlink(os.path.join(self.d, E.WRITE_MARKER))
        E.end_write(self.r, None, E.GitResult(True, 0, "", "", None))  # no token: nothing to end, no error

    def test_begin_write_never_overwrites_and_reports_unwritable(self):
        E.write_marker(self.d, "fast-forward", SHA, "earlier", "earlier:1:1")
        tok, why = E.begin_write(self.r, self.d, "fast-forward", SHA)
        self.assertEqual((tok, why), (None, "blocked:write-marker-present"))
        self.assertEqual(E.marker_write_id(self.d), "earlier:1:1")
        os.unlink(os.path.join(self.d, E.WRITE_MARKER))
        gone = os.path.join(self.d, "no-such-dir")
        self.r.register_site(gone, gone, "main")
        tok, why = E.begin_write(self.r, gone, "fast-forward", SHA)
        self.assertEqual((tok, why), (None, "blocked:write-marker-unwritable"))
        self.assertEqual(self.r.gd_state(gone), E.GD_NONE)


class RoundNine(unittest.TestCase):  # review round 9: the path access layer and the lock sets (RV8-1 .. RV8-4)
    def setUp(self):
        import tempfile
        self.d = tempfile.mkdtemp(prefix="sync_unit_r9.")
        self.r = E.Runner("/nonexistent/git", 10, E.time.monotonic() + 600, 4321)
        self.r.run_id = "r9"
        self.r.register_site(self.d, self.d, "main")

    def tearDown(self):
        import shutil
        shutil.rmtree(self.d)  # a mkdtemp directory of this test, never anything else

    def kinds(self):
        """{kind: path} with one object of every kind the engine may meet at a path it reads."""
        import socket
        k = {}
        k["fifo"] = os.path.join(self.d, "fifo")
        os.mkfifo(k["fifo"])
        k["dir"] = os.path.join(self.d, "dir")
        os.mkdir(k["dir"])
        k["symlink"] = os.path.join(self.d, "ln")
        os.symlink("/dev/zero", k["symlink"])
        k["socket"] = os.path.join(self.d, "s")
        old = os.getcwd()
        os.chdir(self.d)
        try:
            so = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            so.bind("s")
            so.close()
        finally:
            os.chdir(old)
        k["char-device"] = "/dev/null"
        return k

    def test_fs_read_never_opens_a_non_regular_file(self):
        import signal as sig
        sig.signal(sig.SIGALRM, lambda *a: (_ for _ in ()).throw(AssertionError("fs_read blocked")))
        sig.alarm(10)  # a blocking open on the FIFO (the r8 defect, RV8-2) would end here, never hang the suite
        try:
            for kind, path in self.kinds().items():
                self.assertEqual(E.fs_read(path, 4096), ("not-regular:" + kind, b""), kind)
        finally:
            sig.alarm(0)
        f = os.path.join(self.d, "f")
        with open(f, "wb") as fh:
            fh.write(b"abc")
        self.assertEqual(E.fs_read(f, 3), ("ok", b"abc"))
        self.assertEqual(E.fs_read(f, 2), ("too-large", b""))  # never half-read
        self.assertEqual(E.fs_read(os.path.join(self.d, "nope"), 9), ("absent", b""))

    def test_fs_read_refuses_a_fifo_swapped_in_after_the_lstat(self):
        f = os.path.join(self.d, "f")
        fifo = os.path.join(self.d, "fifo")
        os.mkfifo(fifo)
        open(f, "w").close()
        real = E.path_kind

        def swap(path):
            k = real(path)
            if path == f:
                os.unlink(f)
                os.rename(fifo, f)
            return k
        E.path_kind = swap
        import signal as sig
        sig.signal(sig.SIGALRM, lambda *a: (_ for _ in ()).throw(AssertionError("fs_read blocked")))
        sig.alarm(10)
        try:
            self.assertEqual(E.fs_read(f, 9), ("not-regular:fifo", b""))  # fstat on the open descriptor
        finally:
            sig.alarm(0)
            E.path_kind = real

    def test_fs_remove_removes_regular_files_only_and_never_raises(self):
        for kind, path in self.kinds().items():
            self.assertEqual(E.fs_remove(path), "not-regular:" + kind, kind)
            self.assertNotEqual(E.path_kind(path), "absent", kind)  # left untouched
        f = os.path.join(self.d, "f")
        open(f, "w").close()
        self.assertEqual(E.fs_remove(f), "removed")
        self.assertEqual(E.fs_remove(f), "absent")
        box = os.path.join(self.d, "box")
        os.mkdir(box)
        open(os.path.join(box, "g"), "w").close()
        os.chmod(box, 0o500)
        try:
            if os.geteuid() != 0:
                self.assertEqual(E.fs_remove(os.path.join(box, "g")), "failed:EACCES")
        finally:
            os.chmod(box, 0o700)

    def test_clear_marker_on_every_kind_reports_and_keeps_it(self):  # RV8-4
        mp = os.path.join(self.d, E.WRITE_MARKER)
        os.mkdir(mp)
        self.assertEqual(E.clear_marker(self.d), "not-regular:dir")
        self.assertEqual(E.path_kind(mp), "dir")
        self.assertIsNone(E.read_marker(self.d))
        self.assertIn("write-marker-path-not-a-file:dir", E.in_progress(self.d))
        self.assertEqual(E.gitdir_write_block(self.r, self.d), "write-marker-present")
        os.rmdir(mp)
        os.mkfifo(mp)
        import signal as sig
        sig.signal(sig.SIGALRM, lambda *a: (_ for _ in ()).throw(AssertionError("marker read blocked")))
        sig.alarm(10)
        try:  # RV8-2: every marker reader on a FIFO answers at once
            self.assertIsNone(E.read_marker(self.d))
            self.assertIsNone(E.marker_write_id(self.d))
            self.assertIn("write-marker-path-not-a-file:fifo", E.in_progress(self.d))
            self.assertEqual(E.clear_marker(self.d), "not-regular:fifo")
        finally:
            sig.alarm(0)
        self.assertEqual(E.path_kind(mp), "fifo")

    def test_fs_open_lock_refuses_non_regular_objects(self):
        import signal as sig
        sig.signal(sig.SIGALRM, lambda *a: (_ for _ in ()).throw(AssertionError("lock open blocked")))
        sig.alarm(10)
        try:
            for kind, path in self.kinds().items():
                if kind == "char-device":
                    continue  # /dev/null is not ours to open read-write here
                fd, why = E.fs_open_lock(path)
                self.assertIsNone(fd, kind)
                self.assertTrue(why, kind)
        finally:
            sig.alarm(0)
        fd, why = E.fs_open_lock(os.path.join(self.d, "lock"))
        self.assertIsNone(why)
        os.close(fd)
        self.assertEqual(E.path_kind(os.path.join(self.d, "lock")), "regular")

    def test_fetched_branches_on_a_fifo_answers_at_once(self):
        fifo = os.path.join(self.d, "FETCH_HEAD")
        os.mkfifo(fifo)
        import signal as sig
        sig.signal(sig.SIGALRM, lambda *a: (_ for _ in ()).throw(AssertionError("FETCH_HEAD read blocked")))
        sig.alarm(10)
        try:
            self.assertIsNone(E.fetched_branches(fifo))
        finally:
            sig.alarm(0)

    def test_lock_sets_follow_the_measured_ground_truth(self):
        g = self.d
        labels = lambda sub, common=None, branch="main": [n for n, _ in E.lock_paths(g, common or g, branch, sub)]
        self.assertEqual(labels("merge"), ["index.lock", "HEAD.lock", "ORIG_HEAD.lock", "AUTO_MERGE.lock",
                                           "packed-refs.lock", "refs/heads/main.lock", "reftable/tables.list.lock"])
        self.assertEqual(labels("checkout"), ["index.lock", "HEAD.lock", "AUTO_MERGE.lock", "packed-refs.lock",
                                              "reftable/tables.list.lock"])
        self.assertEqual(labels("add"), ["index.lock"])
        wt = os.path.join(g, "worktrees", "w")
        os.makedirs(wt)
        got = dict(E.lock_paths(wt, g, "main", "merge"))
        self.assertEqual(got["HEAD.lock"], os.path.join(wt, "HEAD.lock"))  # per worktree
        self.assertEqual(got["common:refs/heads/main.lock"], os.path.join(g, "refs/heads/main.lock"))
        self.assertNotIn(os.path.join(g, "HEAD.lock"), got.values())  # the main worktree's HEAD.lock: not taken
        for name in ("HEAD.lock", "ORIG_HEAD.lock", "AUTO_MERGE.lock", "packed-refs.lock"):
            open(os.path.join(g, name), "w").close()
            self.assertEqual(E.gitdir_write_block(self.r, g), "in-progress:" + name, name)
            os.unlink(os.path.join(g, name))
        os.makedirs(os.path.join(g, "refs", "heads"))
        open(os.path.join(g, "refs", "heads", "main.lock"), "w").close()
        self.assertEqual(E.gitdir_write_block(self.r, g), "in-progress:refs/heads/main.lock")
        os.unlink(os.path.join(g, "refs", "heads", "main.lock"))
        open(os.path.join(g, "refs", "heads", "other.lock"), "w").close()  # golden-FALSE: not taken for main
        self.assertIsNone(E.gitdir_write_block(self.r, g))
        open(os.path.join(g, "config.lock"), "w").close()  # golden-FALSE: measured, no effect on a write
        self.assertIsNone(E.gitdir_write_block(self.r, g))

    def test_an_uninspected_git_dir_is_never_written(self):
        other = os.path.join(self.d, "other")
        os.mkdir(other)
        self.assertEqual(E.gitdir_write_block(self.r, other), "unknown-git-dir")
        self.assertEqual(E.begin_write(self.r, other, "fast-forward", SHA), (None, "blocked:unknown-git-dir"))
        self.assertEqual(os.listdir(other), [])

    def settle(self, head_now, index_now, rc=128, op="fast-forward"):
        def answer(repo, a):
            if a[:2] == ["ls-files", "-s"]:
                return "exit", 0, index_now, ""
            if a[0] == "rev-parse":
                return "exit", 0, head_now + "\n", ""
            return "exit", 0, "", ""
        r = scripted_runner(answer)
        repo = E.Repo("/nonexistent/w", ".", 0, None)
        repo.rec.update(head_before=SHA, branch="main", _gitdir=self.d)
        return E.write_settled(r, repo, op, "b" * 40, E.GitResult(True, rc, "", "", None), "I0")

    def test_write_settled(self):  # RV8-1: an answered failure that changed the index or HEAD is NOT settled
        self.assertTrue(self.settle(SHA, "I0"))  # refused cleanly: settled, the marker may go
        self.assertFalse(self.settle(SHA, "I1"))  # the index changed (git's half-applied merge)
        self.assertFalse(self.settle("c" * 40, "I0"))  # HEAD moved although git failed
        self.assertTrue(self.settle("c" * 40, "I1", rc=0))  # exit 0: git completed; step 6 checks HEAD
        r = scripted_runner(lambda repo, a: ("signal", 9, "", ""))  # a read that does not answer: not settled
        repo = E.Repo("/nonexistent/w", ".", 0, None)
        repo.rec.update(head_before=SHA, branch="main", _gitdir=self.d)
        self.assertFalse(E.write_settled(r, repo, "follow-pin", SHA, E.GitResult(True, 1, "", "", None), "I0"))

    def test_end_write_never_removes_a_marker_that_is_not_its_own(self):
        tok, why = E.begin_write(self.r, self.d, "fast-forward", SHA)
        self.assertIsNone(why)
        os.unlink(os.path.join(self.d, E.WRITE_MARKER))
        E.write_marker(self.d, "fast-forward", SHA, "other", "other:1:1")  # replaced while git ran
        E.end_write(self.r, tok, E.GitResult(True, 0, "", "", None), True)
        self.assertEqual(E.marker_write_id(self.d), "other:1:1")


class RoundTen(unittest.TestCase):  # review round 10 (RV9-1 .. RV9-6)
    def setUp(self):
        import tempfile
        self.d = tempfile.mkdtemp(prefix="sync_unit_r10.")

    def tearDown(self):
        import shutil
        shutil.rmtree(self.d)  # a mkdtemp directory of this test, never anything else

    def test_branch_parameter_of_the_lock_path(self):  # RV9-1 / Z04: the branch is substituted, never assumed
        g = self.d
        for br in ("main", "dev", "feature/x", "a.b-c/d_e"):
            got = dict(E.lock_paths(g, g, br, "merge"))
            self.assertEqual(got["refs/heads/%s.lock" % br], os.path.join(g, "refs", "heads", *(br + ".lock").split("/")))
            self.assertEqual([n for n in got if n.startswith("refs/heads/")], ["refs/heads/%s.lock" % br], br)
        self.assertEqual([n for n, _ in E.lock_paths(g, g, None, "merge") if "refs/heads" in n], [])  # unknown: none
        r = E.Runner("/nonexistent/git", 10, E.time.monotonic() + 600, 4321)
        r.register_site(g, g, "feature/x")
        os.makedirs(os.path.join(g, "refs", "heads", "feature"))
        for other in ("refs/heads/main.lock", "refs/heads/x.lock", "refs/heads/feature.lock"):  # golden-FALSE
            open(os.path.join(g, other), "w").close()
            self.assertIsNone(E.gitdir_write_block(r, g), other)
            os.unlink(os.path.join(g, other))
        open(os.path.join(g, "refs/heads/feature/x.lock"), "w").close()
        self.assertEqual(E.gitdir_write_block(r, g), "in-progress:refs/heads/feature/x.lock")

    def test_git_dir_and_common_dir_parameters(self):  # RV9-1: per-worktree names in the git dir, ref locks in common
        common = self.d
        wt = os.path.join(common, "worktrees", "id1")
        other = os.path.join(common, "worktrees", "id2")
        os.makedirs(wt)
        os.makedirs(other)
        got = dict(E.lock_paths(wt, common, "dev"))
        for n in E.WRITE_LOCKS:
            self.assertEqual(got[n], os.path.join(wt, n), n)
        for n in ("packed-refs.lock", "refs/heads/dev.lock", "reftable/tables.list.lock"):
            self.assertEqual(got["common:" + n], os.path.join(common, n), n)
        self.assertFalse([p for p in got.values() if p.startswith(other + os.sep)])  # another worktree id: never
        for name in ("MERGE_HEAD", "HEAD.lock"):
            for base, busy in ((wt, True), (other, False), (common, False)):
                open(os.path.join(base, name), "w").close()
                self.assertEqual(bool(E.in_progress(wt, common, "dev")), busy, (name, base))
                os.unlink(os.path.join(base, name))
        for base, busy in ((wt, True), (other, False), (common, False)):  # the marker path: this git dir only
            os.mkfifo(os.path.join(base, E.WRITE_MARKER))
            self.assertEqual("write-marker-path-not-a-file:fifo" in E.in_progress(wt, common, "dev"), busy, base)
            os.unlink(os.path.join(base, E.WRITE_MARKER))
        self.assertEqual(E.marker_path(wt), os.path.join(wt, E.WRITE_MARKER))
        r = E.Runner("/nonexistent/git", 10, E.time.monotonic() + 600, 4321)
        r.register_site(wt, common, "dev")
        self.assertEqual(r.site(wt), (common, "dev"))
        open(os.path.join(common, "packed-refs.lock"), "w").close()
        self.assertEqual(E.gitdir_write_block(r, wt), "in-progress:common:packed-refs.lock")

    def test_marker_read_statuses(self):  # RV9-2 / Z11: a too-large or unreadable marker is 'unknown', never None
        mp = os.path.join(self.d, E.WRITE_MARKER)
        with open(mp, "w") as f:
            f.write(json.dumps({"op": "fast-forward", "pad": "x" * 5000}))
        self.assertEqual(E.fs_read(mp, 4096)[0], "too-large")
        self.assertEqual(E.read_marker(self.d), "unknown")
        os.unlink(mp)
        with open(mp, "w") as f:
            f.write(json.dumps({"op": "fast-forward"}))
        self.assertEqual(E.read_marker(self.d), "fast-forward")
        if os.geteuid() != 0:
            os.chmod(mp, 0)
            self.assertEqual(E.read_marker(self.d), "unknown")
            os.chmod(mp, 0o600)
        os.unlink(mp)
        self.assertIsNone(E.read_marker(self.d))

    def staged(self, links_now, rc=128, answer=True):
        child_gitlink = SHA
        parent = E.Repo("/nonexistent/p", ".", 0, None)
        repo = E.Repo("/nonexistent/p/libs/a", "libs/a", 1, parent)
        repo.rec.update(path_in_parent="libs/a", recorded_gitlink=child_gitlink, head_before=SHA, branch=None)

        def answer_(repo_, a):
            if not answer:
                return "signal", 9, "", ""
            if a[:2] == ["ls-files", "-s"] and repo_ == parent.abspath:
                return "exit", 0, "".join("160000 %s 0\t%s\0" % (s, p) for p, s in links_now.items()), ""
            return "exit", 0, "", ""
        r = scripted_runner(answer_)
        return E.write_settled(r, repo, "stage-pin", "b" * 40, E.GitResult(True, rc, "", "", None), None)

    def test_failed_stage_pin_settled_only_when_the_gitlink_is_unchanged(self):  # RV9-3 / Z01
        self.assertTrue(self.staged({"libs/a": SHA}))  # git refused before writing: the recorded gitlink is still there
        self.assertFalse(self.staged({"libs/a": "c" * 40}))  # the failed add changed the gitlink: NOT settled
        self.assertFalse(self.staged({}))  # the gitlink is gone from the index: NOT settled
        self.assertFalse(self.staged({"libs/a": SHA}, answer=False))  # an unanswered read: NOT settled
        self.assertTrue(self.staged({"libs/a": "c" * 40}, rc=0))  # exit 0: git completed the stage-pin

    def test_failed_write_settled_check_reads_head_and_index_only(self):  # RV9-6: the stated limit, pinned
        def answer(repo, a):
            if a[:2] == ["ls-files", "-s"]:
                return "exit", 0, "I0", ""
            if a[0] == "rev-parse":
                return "exit", 0, SHA + "\n", ""
            return "exit", 0, "?? stray_by_write.txt\n", ""
        r = scripted_runner(answer)
        repo = E.Repo("/nonexistent/w", ".", 0, None)
        repo.rec.update(head_before=SHA, branch="main", _gitdir=self.d)
        self.assertTrue(E.write_settled(r, repo, "fast-forward", "b" * 40, E.GitResult(True, 128, "", "", None), "I0"))
        self.assertEqual(sorted({a[0] for _, a in r.seen}), ["ls-files", "rev-parse"])  # no work-tree read (limit)


class RoundEleven(unittest.TestCase):  # review round 11 (RV10-1 .. RV10-8)
    def setUp(self):
        import tempfile
        self.d = tempfile.mkdtemp(prefix="sync_unit_r11.")

    def tearDown(self):
        import shutil
        shutil.rmtree(self.d)  # a mkdtemp directory of this test, never anything else

    def test_read_branch_reads_the_full_ref(self):  # RV10-1: --short answers heads/dev beside a tag dev
        seen = []
        def answer(out, rc=0):
            def f(git_bin, repo, args, env, limit, level=1):
                seen.append(list(args))
                E.check_git_args(args)
                return ("exit", rc, out, "")
            return f
        cases = (("refs/heads/dev\n", ("branch", "dev")), ("refs/heads/heads/dev\n", ("branch", "heads/dev")),
                 ("refs/heads/Dev\n", ("branch", "Dev")), ("refs/heads/Feature/X\n", ("branch", "Feature/X")),
                 ("refs/heads/feature/x\n", ("branch", "feature/x")), ("refs/heads/café\n", ("branch", "café")),
                 ("refs/heads/origin/dev\n", ("branch", "origin/dev")),
                 ("refs/remotes/origin/dev\n", ("other", None)), ("refs/tags/dev\n", ("other", None)),
                 ("dev\n", ("unknown", None)), ("heads/dev\n", ("unknown", None)),  # a short name: never trusted
                 ("refs/heads/dev\nrefs/heads/x\n", ("unknown", None)), ("refs/heads/../x\n", ("unknown", None)),
                 ("refs/heads/a/../b\n", ("unknown", None)), ("refs/heads/x.lock\n", ("unknown", None)),
                 ("refs/heads/\n", ("unknown", None)), ("refs/heads/-x\n", ("unknown", None)),
                 ("refs/heads/a b\n", ("unknown", None)), ("refs/heads/.x\n", ("unknown", None)))
        for out, want in cases:
            E.proc_run_git = answer(out)
            r = E.Runner("/nonexistent/git", 10, E.time.monotonic() + 600)
            self.assertEqual(E.read_branch(r, "/r"), want, out)
            self.assertEqual(bool(r.unresolved_for("/r")), want[0] == "unknown", out)
        self.assertTrue(seen and all(a == ["symbolic-ref", "-q", "HEAD"] for a in seen), seen)

    def test_symbolic_ref_short_is_refused(self):  # RV10-1: the disambiguating form can never come back
        with self.assertRaises(E.GitRefused):
            E.check_git_args(["symbolic-ref", "--short", "-q", "HEAD"])
        self.assertTrue(E.check_git_args(["symbolic-ref", "-q", "HEAD"]))

    def test_branch_case_is_kept_in_every_lock_path(self):  # RV10-2 / AA01: Dev.lock is not dev.lock
        g = self.d
        for br in ("Dev", "DEV", "Feature/X", "mIxEd/CaSe/Br", "heads/dev", "café"):
            names = [n for n, _ in E.lock_paths(g, g, br, "merge") if n.startswith("refs/heads/")]
            self.assertEqual(names, ["refs/heads/%s.lock" % br], br)
            self.assertEqual(dict(E.lock_paths(g, g, br, "merge"))[names[0]],
                             os.path.join(g, "refs", "heads", *(br + ".lock").split("/")))
            self.assertEqual([n for n in E.in_progress(g, g, br)], [])
        os.makedirs(os.path.join(g, "refs", "heads"))
        r = E.Runner("/nonexistent/git", 10, E.time.monotonic() + 600, 4321)
        r.register_site(g, g, "Dev")
        open(os.path.join(g, "refs/heads/dev.lock"), "w").close()  # golden-FALSE: another branch's lock
        self.assertIsNone(E.gitdir_write_block(r, g))
        self.assertEqual(E.locks_left(g, "Dev", g, "merge"), [])
        open(os.path.join(g, "refs/heads/Dev.lock"), "w").close()
        self.assertEqual(E.gitdir_write_block(r, g), "in-progress:refs/heads/Dev.lock")
        self.assertEqual(E.locks_left(g, "Dev", g, "merge"), ["refs/heads/Dev.lock"])
        self.assertIn("refs/heads/Dev.lock", E.in_progress(g, g, "Dev"))
        os.unlink(os.path.join(g, "refs/heads/dev.lock"))
        self.assertNotIn("refs/heads/dev.lock", E.in_progress(g, g, "Dev"))

    def test_valid_branch_name(self):  # RV10-1 class: one rule for a name read from git and for --branch
        good = ("main", "dev", "Dev", "feature/x", "heads/dev", "origin/dev", "a.b-c/d_e", "café", "v1.2")
        bad = ("", "-x", "/x", "x/", "x.", "x..y", "x//y", "x/.y", ".x", "x.lock", "x/y.lock/z", "HEAD", "@",
               "x@{1}", "a b", "a\tb", "a\nb", "x~1", "x^", "x:y", "x?", "x*", "x[y", "x\\y", "x\x7f")
        for n in good:
            self.assertTrue(E.valid_branch_name(n), n)
        for n in bad:
            self.assertFalse(E.valid_branch_name(n), repr(n))
        self.assertEqual(E.branch_of_ref("refs/heads/heads/dev"), "heads/dev")
        self.assertIsNone(E.branch_of_ref("refs/tags/dev"))
        self.assertIsNone(E.branch_of_ref("heads/dev"))

    def test_invalid_branch_parameter_is_a_usage_error(self):  # RV10-1 class: refused before any git call
        E.proc_run_git = lambda *a, **k: self.fail("git must not run for an invalid --branch")
        for br in ("dev/", "dev.lock", "dev..x", "dev/.x", "HEAD", "dev//x", "-x", "café", "a@{1}"):
            self.assertEqual(E.main(["--check", "--no-fetch", "--branch=" + br, "--root", self.d]), E.EXIT_USAGE, br)

    def test_engine_scrub_covers_the_canonical_list(self):  # RV10-3: git_env drops every repository-locating name
        lib = os.path.join(HERE, "..", "..", "scripts", "lib", "constitution_layout.sh")
        line = [x for x in open(lib, encoding="utf-8") if x.startswith("CL_GIT_SCRUB_VARS=")]
        self.assertEqual(len(line), 1)
        names = line[0].split("=", 1)[1].strip().strip('"').split()
        self.assertEqual(len(names), 14, names)  # control needle: the list was really read
        self.assertEqual(sorted(set(names) - set(E._SCRUB)), [])
        env = E.git_env({n: "/elsewhere" for n in names} | {"PATH": "/usr/bin"})
        self.assertEqual(sorted(n for n in names if n in env), [])
        self.assertEqual(env["PATH"], "/usr/bin")  # golden-FALSE: an unrelated variable is kept

    def test_marker_op_outside_the_vocabulary_is_unknown(self):  # RV10-7 / AA10
        g = self.d
        path = E.marker_path(g)
        for op, want in (("fast-forward", "fast-forward"), ("stage-pin", "stage-pin"),
                         ("fast-forward\tCURRENT\n[sync-upstreams] . current -", "unknown"), ("reset", "unknown"),
                         ("", "unknown"), (["fast-forward"], "unknown"), (7, "unknown"), (None, "unknown")):
            with open(path, "w") as fh:
                json.dump({"op": op, "write_id": "w"}, fh)
            self.assertEqual(E.read_marker(g), want, repr(op))
        os.unlink(path)
        self.assertIsNone(E.read_marker(g))


if __name__ == "__main__":
    r = unittest.main(exit=False, verbosity=1).result
    n, f, s = r.testsRun, len(r.failures) + len(r.errors), len(r.skipped)
    print("sync-unit: PASS %d FAIL %d SKIP %d" % (n - f - s, f, s))
    sys.exit(0 if f == 0 and s == 0 and n > 0 else 1)  # a skipped test is never a pass
