"""Regression tests for the independent-review findings on the issue-sync engine (anchor 11.4.300). Test doubles prove THIS tool's logic only
(anchor 11.4.289); nothing here is evidence about any host."""
import io, json, os, re, sqlite3, subprocess, sys, tempfile, unittest
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))
from issue_sync import cli, config, credentials, engine, mode, payload, redact, registry, store, visibility as vis
from issue_sync.adapters.base import AdapterError, HttpTransport
from issue_sync.adapters.github import GitHub
from issue_sync.adapters.gitlab import GitLab
from issue_sync.tests_support import FakeGitHub, FakeGitLab, mkdb, cfgfile, applycfg, PROVEN

ROWS = [("A-1", "Bug", "Queued", "first", "High", "first description text here ok", "Q", "B", "Issues"),
        ("A-2", "Task", "Completed (→ Fixed.md)", "second", "", "second description text here ok", None, None, "Fixed")]
OR = "github.com/o/r"


def go(args, fake, proven=PROVEN, env=None):
    out = io.StringIO()
    old = dict(os.environ)
    try:
        if env: os.environ.update(env)
        rc = cli.run(args, proven_hosts=proven, transport_factory=lambda v, h: fake, out=out)
    finally:
        os.environ.clear(); os.environ.update(old)
    return rc, out.getvalue()


def base(cmd, db, cfg, *x, owner=OR, target=OR):
    return [cmd, "--db", db, "--config", cfg, "--target", target, "--owner-repo", owner, *x]


class TestB1CapabilitiesUnconfirmed(unittest.TestCase):
    def test_adapters_declare_no_write_verb_until_proven(self):
        for cls in (GitHub, GitLab):
            a = cls(lambda *x: None)
            self.assertTrue(a.capabilities["can_list"])
            self.assertFalse(any(v for k, v in a.capabilities.items() if k != "can_list"), cls.__name__)
            self.assertTrue(cls(lambda *x: None, proven=True).capabilities["can_create"])
    def test_default_registry_proves_no_host(self):
        self.assertEqual(registry.load_proven(), set())
    def test_proven_row_needs_existing_evidence_file(self):
        d = tempfile.mkdtemp(); t = os.path.join(d, "p.tsv")
        open(t, "w").write("github.com\tdocs/qa/none.txt\ngitlab.com\n")
        self.assertEqual(registry.load_proven(t, root=d), set())
        os.makedirs(os.path.join(d, "docs/qa")); open(os.path.join(d, "docs/qa/none.txt"), "w").write("a read-only probe, no write")
        self.assertEqual(registry.load_proven(t, root=d), set())            # an existing file without the recorded create+read-back marker proves nothing
        open(os.path.join(d, "docs/qa/none.txt"), "w").write("notes\n" + registry.EVIDENCE_MARKER + " gitlab.com 2026-11-25\n")
        self.assertEqual(registry.load_proven(t, root=d), set())            # a marker line for ANOTHER host proves nothing for this one
        open(os.path.join(d, "docs/qa/none.txt"), "w").write("notes\n" + registry.EVIDENCE_MARKER + " github.com 2026-11-25\n")
        self.assertEqual(registry.load_proven(t, root=d), {"github.com"})
        open(t, "w").write("unknown.example\tdocs/qa/none.txt\n")
        self.assertEqual(registry.load_proven(t, root=d), set())            # host must be a declared forge host
        open(t, "w").write("github.com\tdocs/qa/none.txt\n")
        open(t, "w").write("github.com\t../outside.txt\n")
        self.assertEqual(registry.load_proven(t, root=d), set())
    def test_github_leg_is_unconfirmed_and_apply_writes_nothing_by_default(self):
        f = FakeGitHub(); db = mkdb(ROWS)
        rc, out = go(base("plan", db, cfgfile()), f, proven=set())
        self.assertEqual(rc, 2); self.assertIn("capability-unverified:can_create", out)
        rc, out = go(base("apply", db, applycfg(), "--apply"), f, proven=set())
        self.assertEqual((f.writes, len(f.issues)), (0, 0)); self.assertEqual(rc, 2)
    def test_cli_default_proven_set_is_the_shipped_empty_file(self):
        f = FakeGitHub(); out = io.StringIO()
        rc = cli.run(base("apply", mkdb(ROWS), applycfg(), "--apply"), transport_factory=lambda v, h: f, out=out)
        self.assertEqual((f.writes, rc), (0, 2))


class TestB2ApplyDecision(unittest.TestCase):
    def cfg_in_repo(self, decision, create=None, track=False):
        d = tempfile.mkdtemp(); subprocess.run(["git", "init", "-q", d], check=True)
        if create:
            os.makedirs(os.path.dirname(os.path.join(d, create)), exist_ok=True); open(os.path.join(d, create), "w").write("decision\n")
            if track: subprocess.run(["git", "-C", d, "add", create], check=True)
        p = os.path.join(d, ".workable-items-sync.yaml"); open(p, "w").write("enabled: true\nmode: apply\napply_decision: %s\n" % decision); return p
    def attempt(self, cfg):
        f = FakeGitHub(); rc, out = go(base("apply", mkdb(ROWS), cfg, "--apply"), f); return rc, out, f
    def test_nonexistent_decision_refuses_and_writes_nothing(self):
        rc, out, f = self.attempt(self.cfg_in_repo("docs/NOPE.md")); self.assertEqual((rc, f.writes), (2, 0)); self.assertIn("apply refused", out)
    def test_untracked_decision_refuses(self):
        rc, out, f = self.attempt(self.cfg_in_repo("d.md", create="d.md", track=False)); self.assertEqual((rc, f.writes), (2, 0)); self.assertIn("not tracked", out)
    def test_tracked_decision_allows(self):
        rc, out, f = self.attempt(self.cfg_in_repo("docs/d.md", create="docs/d.md", track=True)); self.assertEqual(rc, 0); self.assertGreater(f.writes, 0)
    def test_config_outside_any_repo_refuses(self):
        p = cfgfile("enabled: true\nmode: apply\napply_decision: d.md\n"); rc, out, f = self.attempt(p); self.assertEqual((rc, f.writes), (2, 0))
    def test_absolute_and_dotdot_paths_are_invalid_config(self):
        for bad in ("/etc/passwd", "../x.md", "a/../../x.md"):
            _, errs = config.validate({"enabled": True, "mode": "apply", "apply_decision": bad}); self.assertTrue(errs, bad)
    def test_type_checked_in_every_mode(self):
        for bad in (5, ["x"], "", {"a": 1}):
            _, errs = config.validate({"enabled": False, "mode": "dry-run", "apply_decision": bad}); self.assertTrue(errs, repr(bad))
        _, errs = config.validate({"enabled": False, "apply_decision": "docs/x.md"}); self.assertEqual(errs, [])
    def test_symlink_out_of_repo_refuses(self):
        d = tempfile.mkdtemp(); subprocess.run(["git", "init", "-q", d], check=True)
        outside = os.path.join(tempfile.mkdtemp(), "x.md"); open(outside, "w").write("x")
        os.symlink(outside, os.path.join(d, "d.md")); subprocess.run(["git", "-C", d, "add", "d.md"], check=True)
        p = os.path.join(d, ".workable-items-sync.yaml"); open(p, "w").write("enabled: true\nmode: apply\napply_decision: d.md\n")
        rc, out, f = self.attempt(p); self.assertEqual((rc, f.writes), (2, 0))


class TestB3RoutingFailsClosed(unittest.TestCase):
    PRIV = [("VSC-1", "Task", "Queued", "pub", "", "public item description here ok", None, None, "Issues"),
            ("WSP-1", "Task", "Queued", "priv", "", "private item description here ok", None, None, "Issues"),
            ("AII-1", "Task", "Queued", "priv2", "", "another private description ok", None, None, "Issues")]
    def titles(self, db):
        f = FakeGitHub(); rc, out = go(base("apply", db, applycfg(), "--apply"), f); return rc, sorted(i["title"][:7] for i in f.issues), out
    def test_missing_subprojects_table_with_many_prefixes_routes_nothing(self):
        db = mkdb(self.PRIV); sqlite3.connect(db).execute("DROP TABLE sub_projects").connection.commit()
        rc, t, out = self.titles(db); self.assertEqual(t, []); self.assertEqual(rc, 2); self.assertIn("unroutable", out)
    def test_empty_subprojects_table_with_many_prefixes_routes_nothing(self):
        rc, t, out = self.titles(mkdb(self.PRIV)); self.assertEqual(t, []); self.assertEqual(rc, 2)
    def test_single_prefix_db_without_routing_data_still_works(self):
        rc, t, _ = self.titles(mkdb(ROWS)); self.assertEqual((rc, len(t)), (0, 2))
    def test_real_routing_table_still_isolates_private_prefixes(self):
        subs = [("VSC", ".", "parent", "operator", "", "", "x"), ("WSP", "w", "owned", "operator", "git@github.com:o/workshop.git", "", "x"),
                ("AII", "a", "owned", "operator", "git@github.com:o/ai.git", "", "x")]
        f = FakeGitHub(); rc, out = go(base("apply", mkdb(self.PRIV, subs), applycfg(), "--apply", "--db-repo", OR), f)
        self.assertEqual([i["title"][:7] for i in f.issues], ["[VSC-1]"])


class TestB4VisibilityLevels(unittest.TestCase):
    def test_gitlab_internal_and_unknown_are_undetermined_not_private(self):
        for v in ("internal", "weird", None):
            body = {"issues_access_level": "enabled"}; 
            if v: body["visibility"] = v
            self.assertIsNone(GitLab(lambda *a, b=body: (200, {}, b)).repo_info("o", "r")["private"], v)
        self.assertTrue(GitLab(lambda *a: (200, {}, {"visibility": "private"})).repo_info("o", "r")["private"])
        self.assertFalse(GitLab(lambda *a: (200, {}, {"visibility": "public"})).repo_info("o", "r")["private"])
    def test_github_internal_is_undetermined(self):
        self.assertIsNone(GitHub(lambda *a: (200, {}, {"private": True, "visibility": "internal", "has_issues": True})).repo_info("o", "r")["private"])
    def test_private_owner_never_reaches_internal_gitlab_mirror(self):
        gh, gl = FakeGitHub(private=True), FakeGitLab(visibility="internal")
        out = io.StringIO()
        rc = cli.run(base("apply", mkdb(ROWS), applycfg(), "--apply", target="gitlab.com/o/r"), proven_hosts=PROVEN,
                     transport_factory=lambda v, h: gl if h == "gitlab.com" else gh, out=out)
        self.assertEqual((gl.writes, rc), (0, 2)); self.assertIn("visibility-undetermined", out.getvalue())


class TestVisibilityMatrix(unittest.TestCase):
    """Every (owner visibility, target visibility, same/different repo) case through the real decision function."""
    def test_matrix(self):
        o = ("github.com", "a", "r")
        for ov in ("public", "private", "undetermined"):
            for tv in ("public", "private", "undetermined"):
                for same in (True, False):
                    t = ("gitlab.com", "a", "r") if same else ("gitlab.com", "a", "other")
                    ok, why = vis.allowed_target(o, t, ov, tv)
                    expect = same and "undetermined" not in (ov, tv) and not (ov == "private" and tv == "public")
                    self.assertEqual(ok, expect, (ov, tv, same, why))


class TestR2ParentNeedsDbRepo(unittest.TestCase):
    def test_parent_prefix_without_db_repo_is_2_and_sends_nothing(self):
        subs = [("VSC", ".", "parent", "operator", "", "", "x")]; rows = [("VSC-1", "Task", "Queued", "t", "", "a description long enough", None, None, "Issues")]
        f = FakeGitHub(); rc, out = go(base("plan", mkdb(rows, subs), cfgfile()), f); self.assertEqual(rc, 2); self.assertIn("--db-repo", out); self.assertEqual(f.calls, [])
        rc, _ = go(base("plan", mkdb(rows, subs), cfgfile(), "--db-repo", OR), FakeGitHub()); self.assertIn(rc, (0, 2))


class TestR3EmptyVerifyIsNotAPass(unittest.TestCase):
    def test_verify_with_nothing_routed_is_2(self):
        f = FakeGitHub(); rc, out = go(base("verify", mkdb(ROWS), cfgfile(), owner="github.com/x/y", target="github.com/x/y", ), f, env={})
        rc2, out2 = go(["verify", "--db", mkdb(ROWS, [("A", ".", "owned", "o", "git@github.com:z/z.git", "", "x")]), "--config", cfgfile(), "--target", OR, "--owner-repo", OR], FakeGitHub())
        self.assertEqual(rc2, 2); self.assertIn("no-items-routed", out2)


class TestR4PrivateCorpusLive(unittest.TestCase):
    CORPUS = "the private roadmap says we will acquire the competitor in march after the board vote and then announce it"
    ROW = [("A-1", "Bug", "Queued", "note we will acquire the competitor in march after the board vote ok", "", "d", None, None, "Issues")]
    def corpus(self):
        p = os.path.join(tempfile.mkdtemp(), "c.txt"); open(p, "w").write(self.CORPUS); return p
    def test_plan_apply_verify_block_a_corpus_overlap(self):
        c = self.corpus(); db = mkdb(self.ROW)
        f = FakeGitHub(); rc, out = go(base("plan", db, cfgfile(), "--private-corpus", c), f); self.assertEqual(rc, 2); self.assertIn("private-corpus", out)
        rc, out = go(base("apply", db, applycfg(), "--apply", "--private-corpus", c), f); self.assertEqual((rc, f.writes), (2, 0))
        rc, out = go(base("verify", db, cfgfile(), "--private-corpus", c), f); self.assertEqual(rc, 2)
    def test_env_var_corpus_and_no_corpus_control(self):
        db = mkdb(self.ROW); f = FakeGitHub()
        rc, _ = go(base("apply", db, applycfg(), "--apply"), f); self.assertEqual(rc, 0)   # control: without the corpus the same item is sent
        f2 = FakeGitHub(); rc, out = go(base("apply", db, applycfg(), "--apply"), f2, env={"ISSUE_SYNC_PRIVATE_CORPUS": self.corpus()}); self.assertEqual((rc, f2.writes), (2, 0))
    def test_unreadable_or_empty_corpus_fails_closed(self):
        f = FakeGitHub(); db = mkdb(self.ROW)
        rc, out = go(base("plan", db, cfgfile(), "--private-corpus", "/nonexistent/c.txt"), f); self.assertEqual((rc, f.calls), (2, []))
        e = os.path.join(tempfile.mkdtemp(), "e.txt"); open(e, "w").write("short")
        rc, out = go(base("plan", db, cfgfile(), "--private-corpus", e), f); self.assertEqual((rc, f.calls), (2, []))
    def test_item_own_forensic_anchor_overlap_blocks_the_title(self):
        quote = "operator said never ship the unreleased pricing table before the quarterly board meeting"
        rows = [("A-1", "Bug", "Queued", "we must never ship the unreleased pricing table before the quarterly board meeting", "", "d", quote, None, "Issues"),
                ("A-2", "Bug", "Queued", "plain parser bug", "", "d", quote, None, "Issues")]
        f = FakeGitHub(); rc, out = go(base("plan", mkdb(rows), cfgfile()), f)
        self.assertEqual(rc, 2); self.assertIn('"blocked": 1', out); self.assertIn('"create": 1', out)
    def test_title_splicing_seven_words_of_the_body_is_blocked_but_a_restated_title_passes(self):
        body = "## A-1 heading\n\nThe private rollout plan moves the vendor contract to the second quarter after legal sign off.\n"
        spliced = {"atm_id": "A-1", "type": "Bug", "status": "Queued", "title": "fix: moves the vendor contract to the second quarter after legal", "severity": "", "description": "d", "body_md": body}
        self.assertEqual(payload.prepare(spliced)["verdict"], "BLOCKED")
        restated_title = "Only 5 of 42 areas carry a test"
        ok = {"atm_id": "A-2", "type": "Bug", "status": "Queued", "title": restated_title, "severity": "", "description": "d",
              "body_md": "## A-2 - " + restated_title + "\n\nThe question put to the operator was: " + restated_title + "\n"}
        self.assertEqual(payload.prepare(ok)["verdict"], "OK")
        # the allowance never covers the verbatim operator quote
        q = dict(ok, forensic_anchor="Only 5 of 42 areas carry a test")
        self.assertEqual(payload.prepare(q)["verdict"], "BLOCKED")


class TestR5MalformedBody(unittest.TestCase):
    def test_2xx_with_non_json_body_is_adapter_error(self):
        class R:
            status = 201; headers = {}
            def read(self): return b"<html>gateway</html>"
            def __enter__(self): return self
            def __exit__(self, *a): return False
        class O:
            def open(self, req, timeout=None): return R()
        t = HttpTransport("tok", min_interval=0, sleep=lambda s: None); t._opener = O()
        with self.assertRaises(AdapterError) as c: t("POST", "https://api.github.com/x", {}, {"a": 1})
        self.assertEqual(c.exception.code, "malformed_body")


class TestR6UnkeyedTitleMatch(unittest.TestCase):
    def test_human_issue_with_matching_title_is_reported_not_overwritten(self):
        f = FakeGitHub(); db = mkdb(ROWS[:1])
        f.issues.append({"number": 5, "title": "[A-1] hand made", "body": "mine", "state": "open", "labels": []})
        rc, out = go(base("apply", db, applycfg(), "--apply"), f)
        self.assertEqual(rc, 2); self.assertIn("unkeyed-title-match", out)
        self.assertEqual((f.issues[0]["title"], f.issues[0]["body"], f.writes), ("[A-1] hand made", "mine", 0))
        rc, out = go(base("verify", db, cfgfile()), f); self.assertEqual(rc, 1)   # an unmanaged issue squatting the key is drift, never in sync
    def test_keyed_issue_wins_over_unkeyed_title_match(self):
        f = FakeGitHub(); db = mkdb(ROWS[:1]); go(base("apply", db, applycfg(), "--apply"), f)
        f.issues.insert(0, {"number": 0, "title": "[A-1] decoy", "body": "x", "state": "open", "labels": []})
        idx = engine.index_issues([engine_issue for engine_issue in [dict(i, labels=[]) for i in f.issues]])
        self.assertTrue(engine.FOOTER.search(idx["A-1"][0]["body"]))


class TestUnkeyableIds(unittest.TestCase):
    def test_id_the_footer_cannot_carry_is_blocked_not_recreated(self):
        rows = [("CON 1/x", "Bug", "Queued", "t", "", "a description long enough", None, None, "Issues")]
        f = FakeGitHub(); rc, out = go(base("apply", mkdb(rows), applycfg(), "--apply"), f)
        self.assertEqual((rc, f.writes), (2, 0)); self.assertIn("unkeyable-id", out)


class TestR7FilteredRunsNoFalseDrift(unittest.TestCase):
    def test_only_open_and_limit_do_not_create_orphans(self):
        f = FakeGitHub(); db = mkdb(ROWS); go(base("apply", db, applycfg(), "--apply"), f)
        rc, out = go(base("verify", db, cfgfile(), "--only-open"), f); self.assertEqual(rc, 0, out)
        rc, out = go(base("verify", db, cfgfile(), "--limit", "1"), f); self.assertEqual(rc, 0, out)
    def test_real_orphan_is_still_found_when_filtered(self):
        f = FakeGitHub(); db = mkdb(ROWS); go(base("apply", db, applycfg(), "--apply"), f)
        k = sqlite3.connect(db); k.execute("delete from items where atm_id='A-2'"); k.commit()
        rc, _ = go(base("verify", db, cfgfile(), "--only-open"), f); self.assertEqual(rc, 1)


class TestConfigStrictness(unittest.TestCase):
    def load(self, text): return config.load(cfgfile(text))
    def test_duplicate_keys_are_rejected(self):
        _, errs = self.load("enabled: false\nenabled: true\n"); self.assertTrue(any("duplicate" in e for e in errs))
        _, errs = self.load("enabled: true\nscope:\n  recursive: true\n  recursive: false\n"); self.assertTrue(errs)
        c, _ = self.load("enabled: true\nenabled: false\n"); self.assertFalse(c["enabled"])
    def test_yaml11_booleans_are_not_booleans(self):
        for v in ("yes", "on", "Yes", "y", "off", "no"):
            c, errs = self.load("enabled: %s\n" % v); self.assertTrue(errs, v); self.assertFalse(c["enabled"])
        c, errs = self.load("enabled: true\n"); self.assertEqual((c["enabled"], errs), (True, []))
        c, errs = self.load("enabled: False\n"); self.assertEqual((c["enabled"], errs), (False, []))
    def test_trackers_must_be_bare_hosts(self):
        for bad in ("https://user:pw@host.example/x", "host.example/path", "git@host:x"):
            _, errs = config.validate({"enabled": False, "trackers": [bad]}); self.assertTrue(errs, bad)
        _, errs = config.validate({"enabled": False, "trackers": ["github.com", "git.m3w.org"]}); self.assertEqual(errs, [])
    def test_mode_helper_uses_the_validator(self):
        for text, want in [("", "off"), ("enabled: true\n", "dry-run"), ("enabled: yes\nmode: apply\n", "invalid"), ("enabled: true\nenabled: false\n", "invalid"),
                           ("enabled: true\nmode: apply\napply_decision: d.md\n", "apply"), ("enabled: false\nmode: apply\n", "off"), ("enabled: true\nbogus: 1\n", "invalid")]:
            self.assertEqual(mode.effective(cfgfile(text))[0], want, text)


class TestRedactionHardening(unittest.TestCase):
    def kinds(self, t): return {h["kind"] for h in redact.scan({"description": t})}
    def test_spaced_and_short_assignments(self):
        for t in ("api key = abcdefgh12", "password: hunter2", "the passphrase is hunter22", "Access Key: ABCDEF123456"):
            self.assertIn("assignment-secret", self.kinds(t), t)
    def test_normalisation_defeats_homoglyphs_and_zero_width(self):
        self.assertIn("github-token", self.kinds("gh​p_" + "a" * 36))
        self.assertIn("github-token", self.kinds("ｇhp_" + "a" * 36))          # fullwidth g
        self.assertIn("aws-key", self.kinds("AKIA" + "‍" + "A" * 16))
    def test_atm_id_that_is_a_secret_is_masked(self):
        res = payload.prepare({"atm_id": "ghp_" + "z" * 36, "type": "Bug", "status": "Queued", "title": "t", "severity": "", "description": "d"})
        self.assertEqual(res["verdict"], "BLOCKED"); self.assertEqual(res["item"], "[redacted-id]"); self.assertNotIn("zzzz", repr(res))
        rows = [("ghp_" + "z" * 36, "Bug", "Queued", "t", "", "a description long enough", None, None, "Issues")]
        rc, out = go(base("verify", mkdb(rows), cfgfile()), FakeGitHub()); self.assertNotIn("zzzz", out)
    def test_no_new_false_positive_on_plain_prose(self):
        self.assertEqual(redact.scan({"description": "Fix flaky test in parser; tokens are counted per line; passes on retry"}), [])


class TestR6CanonicalRepo(unittest.TestCase):
    def test_flat_hosts_reject_extra_path_and_keep_exact_pair(self):
        self.assertIsNone(vis.canonical_repo("https://github.com/org/repo/issues"))
        self.assertEqual(vis.canonical_repo("https://github.com/org/repo"), ("github.com", "org", "repo"))
    def test_gitlab_keeps_group_path_and_strips_web_suffix(self):
        self.assertEqual(vis.canonical_repo("git@gitlab.com:grp/sub/proj.git"), ("gitlab.com", "grp/sub", "proj"))
        self.assertEqual(vis.canonical_repo("https://gitlab.com/grp/sub/proj/-/issues"), ("gitlab.com", "grp/sub", "proj"))
        self.assertNotEqual(vis.canonical_repo("git@gitlab.com:a/b/proj.git"), vis.canonical_repo("git@gitlab.com:c/b/proj.git"))
    def test_nested_target_matches_nested_owner_in_cli(self):
        gl = FakeGitLab(visibility="public"); f = FakeGitHub()
        out = io.StringIO()
        rc = cli.run(base("plan", mkdb(ROWS), cfgfile(), owner="gitlab.com/grp/sub/proj", target="gitlab.com/grp/sub/proj"), proven_hosts=PROVEN, transport_factory=lambda v, h: gl, out=out)
        self.assertEqual(rc, 0, out.getvalue())


if __name__ == "__main__":
    unittest.main()


class TestGeneratedPublicSummary(unittest.TestCase):
    """Operator decision 2026-11-25: issue text is a GENERATED public summary; no DB description or body is ever mirrored."""
    SECRET_DESC = "UNIQUE-DB-DESCRIPTION-MARKER should never be mirrored anywhere in a tracker"
    ROWS = [("A-1", "Bug", "Queued", "first title", "High", SECRET_DESC, "Q", "BODYTEXT-MARKER body", "Issues")]
    def test_db_description_and_body_are_never_sent(self):
        f = FakeGitHub(); go(base("apply", mkdb(self.ROWS), applycfg(), "--apply"), f)
        blob = json.dumps(f.issues); self.assertEqual(len(f.issues), 1)
        for m in ("UNIQUE-DB-DESCRIPTION-MARKER", "BODYTEXT-MARKER", "should never be mirrored"): self.assertNotIn(m, blob)
    def test_fixed_template_shape(self):
        f = FakeGitHub(); go(base("apply", mkdb(self.ROWS), applycfg(), "--apply"), f)
        i = f.issues[0]
        self.assertEqual(i["title"], "[A-1] first title")
        self.assertIn(payload.GENERATED_DESCRIPTION, i["body"]); self.assertIn("Severity: High", i["body"]); self.assertIn("Status: Queued | Type: Bug", i["body"])
        self.assertIn("Repository: https://github.com/o/r", i["body"]); self.assertIn("`docs/workable_items.db`, item `A-1`", i["body"])
        self.assertRegex(i["body"], r"<!-- workable-item: A-1 \| sha256: [0-9a-f]{64} -->")
    def test_description_edit_alone_changes_nothing_in_the_mirror(self):
        f = FakeGitHub(); db = mkdb(self.ROWS); c = applycfg(); go(base("apply", db, c, "--apply"), f)
        k = sqlite3.connect(db); k.execute("update items set description='something else entirely'"); k.commit()
        rc, _ = go(base("verify", db, cfgfile()), f); self.assertEqual(rc, 0)
        w = f.writes; go(base("apply", db, c, "--apply"), f); self.assertEqual(f.writes, w)
    def test_allowlist_and_generated_fields(self):
        self.assertEqual(payload.ALLOWED_FIELDS, ("atm_id", "type", "status", "title", "severity")); self.assertEqual(payload.GENERATED_FIELDS, ("description",))
        pl = payload.build({"atm_id": "A-1", "title": "t", "description": "DB TEXT", "body_md": "B"}); self.assertEqual(pl["description"], payload.GENERATED_DESCRIPTION)
    def test_secret_in_the_db_description_cannot_leak_and_does_not_block(self):
        rows = [("A-1", "Bug", "Queued", "t", "", "token ghp_" + "a" * 36, None, None, "Issues")]
        f = FakeGitHub(); rc, out = go(base("apply", mkdb(rows), applycfg(), "--apply"), f); self.assertEqual(rc, 0); self.assertNotIn("ghp_", json.dumps(f.issues))
    def test_real_shaped_umbrella_rows_route_unblocked_and_private_prefixes_never_sent(self):
        body = lambda t: "## %s - %s\n\n**Status:** Queued\n\nWHAT - the question put to the operator was: %s\n" % ("VSC-1", t, t)
        t1 = "operator decision 2026-09-07 #3 - Only 5 of 42 areas carry a test"
        rows = [("VSC-1", "Task", "Queued", t1, "", "WHAT - " + t1, "docs/OPERATOR-DECISIONS.md row 3", body(t1), "Issues"),
                ("VSC-2", "Task", "Queued", "second title", "", "d", None, "b", "Issues"),
                ("WSP-1", "Task", "Queued", "private", "", "private description", None, "b", "Issues"),
                ("AII-1", "Task", "Queued", "private2", "", "private description", None, "b", "Issues"),
                ("MON-1", "Task", "Queued", "private3", "", "private description", None, "b", "Issues")]
        subs = [("VSC", ".", "parent", "operator", "", "", "x")] + [(p, p.lower(), "owned", "operator", "git@github.com:z/%s.git" % p.lower(), "", "x") for p in ("WSP", "AII", "MON")]
        f = FakeGitHub(); out = io.StringIO()
        rc = cli.run(base("plan", mkdb(rows, subs), cfgfile(), "--db-repo", OR, "--json"), proven_hosts=PROVEN, transport_factory=lambda v, h: f, out=out)
        r = json.loads(out.getvalue()); self.assertEqual(rc, 0)
        self.assertEqual(r[0]["counts"], {"create": 2}); self.assertEqual(r[1]["routing"]["not-owned-by-this-repo (never sent)"], 3)


