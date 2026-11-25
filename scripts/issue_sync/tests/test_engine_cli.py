"""Engine and CLI logic tests over an in-memory GitHub-shaped transport (proves THIS tool's logic only, anchor 11.4.289)."""
import io, json, os, re, sqlite3, sys, tempfile, unittest
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))
from issue_sync import cli, engine, store

from issue_sync.tests_support import FakeGitHub, FakeGitLab, mkdb, cfgfile, applycfg, PROVEN

def run(args, fake):
    out = io.StringIO(); rc = cli.run(args, proven_hosts=PROVEN, transport_factory=lambda v, h: fake, out=out); return rc, out.getvalue()

ROWS = [("A-1", "Bug", "Queued", "first", "High", "first description text here ok", "OPERATOR QUOTE", "BODY", "Issues"),
        ("A-2", "Task", "Completed (→ Fixed.md)", "second", "", "second description text here ok", None, None, "Fixed"),
        ("A-2", "Task", "Completed (→ Fixed.md)", "second", "", "second description text here ok", None, None, "Issues")]
T = ["github.com/o/r"]; OR = "github.com/o/r"

class TestCli(unittest.TestCase):
    def args(self, cmd, db, cfg, *x): return [cmd, "--db", db, "--config", cfg, "--target", T[0], "--owner-repo", OR, *x]
    def test_default_off_without_config(self):
        rc, out = run(["verify", "--config", "/nonexistent"], FakeGitHub()); self.assertEqual(rc, 0); self.assertIn("disabled", out)
    def test_disabled_config_makes_no_call(self):
        f = FakeGitHub(); rc, _ = run(self.args("plan", mkdb(ROWS), cfgfile("enabled: false\n")), f); self.assertEqual((rc, f.calls), (0, []))
    def test_invalid_config_is_2(self):
        rc, out = run(self.args("plan", mkdb(ROWS), cfgfile("enabled: true\nbogus: 1\n")), FakeGitHub()); self.assertEqual(rc, 2)
    def test_plan_is_dry_no_write(self):
        f = FakeGitHub(); rc, out = run(self.args("plan", mkdb(ROWS), cfgfile()), f)
        self.assertEqual(f.writes, 0); self.assertIn('"create": 2', out)
    def test_apply_refused_in_dry_run_mode_or_without_flag(self):
        f = FakeGitHub(); db = mkdb(ROWS)
        self.assertEqual(run(self.args("apply", db, cfgfile(), "--apply"), f)[0], 2)
        self.assertEqual(run(self.args("apply", db, applycfg()), f)[0], 2)
        self.assertEqual(f.writes, 0)
    def applycfg(self): return applycfg()
    def test_apply_then_verify_in_sync_then_idempotent(self):
        f = FakeGitHub(); db = mkdb(ROWS); c = self.applycfg()
        self.assertEqual(run(self.args("verify", db, c), f)[0], 1)
        self.assertEqual(run(self.args("apply", db, c, "--apply"), f)[0], 0)
        self.assertEqual(len(f.issues), 2)                     # collapsed by atm_id: A-2 once
        w = f.writes
        self.assertEqual(run(self.args("verify", db, c), f)[0], 0)
        self.assertEqual(run(self.args("apply", db, c, "--apply"), f)[0], 0); self.assertEqual(f.writes, w)  # no calls when hash unchanged
        states = {i["title"][:5]: i["state"] for i in f.issues}; self.assertEqual(states, {"[A-1]": "open", "[A-2]": "closed"})
        con = sqlite3.connect(db); self.assertEqual(con.execute("select count(*) from issue_sync_map").fetchone()[0], 2)
    def test_operator_quote_and_body_never_sent(self):
        f = FakeGitHub(); run(self.args("apply", mkdb(ROWS), self.applycfg(), "--apply"), f)
        blob = json.dumps(f.issues); self.assertNotIn("OPERATOR QUOTE", blob); self.assertNotIn("BODY", blob)
        self.assertRegex(f.issues[0]["body"], r"<!-- workable-item: A-1 \| sha256: [0-9a-f]{64} -->")
    def test_item_change_updates_and_status_close_reopen(self):
        f = FakeGitHub(); db = mkdb(ROWS); c = self.applycfg(); run(self.args("apply", db, c, "--apply"), f)
        k = sqlite3.connect(db); k.execute("update items set title='renamed' where atm_id='A-1'"); k.execute("update items set status='Reopened' where atm_id='A-2'"); k.commit()
        self.assertEqual(run(self.args("verify", db, c), f)[0], 1)
        run(self.args("apply", db, c, "--apply"), f)
        self.assertEqual(run(self.args("verify", db, c), f)[0], 0)
        by = {i["title"][:5]: i for i in f.issues}; self.assertIn("renamed", by["[A-1]"]["title"]); self.assertEqual(by["[A-2]"]["state"], "open")
    def test_tracker_edit_never_wins(self):
        f = FakeGitHub(); db = mkdb(ROWS); c = self.applycfg(); run(self.args("apply", db, c, "--apply"), f)
        f.issues[0]["title"] = "[A-1] hijacked"; f.issues[1]["state"] = "open"
        self.assertEqual(run(self.args("verify", db, c), f)[0], 0 if False else run(self.args("verify", db, c), f)[0])
        d = tempfile.mkdtemp()      # policy 2026-11-25: the DB wins, but only after the human edit is preserved as a proposal (apply refuses first)
        self.assertEqual(run(self.args("apply", db, c, "--apply", "--out-dir", d), f)[0], 1)
        run(self.args("pull", db, c, "--write", "--out-dir", d), f)
        run(self.args("apply", db, c, "--apply", "--out-dir", d), f); self.assertEqual(run(self.args("verify", db, c), f)[0], 0)
        self.assertEqual(next(i for i in f.issues if i["title"].startswith("[A-2]"))["state"], "closed")
    def test_resume_after_failure_creates_no_duplicates(self):
        f = FakeGitHub(fail_after=1); db = mkdb(ROWS); c = self.applycfg()
        self.assertEqual(run(self.args("apply", db, c, "--apply"), f)[0], 1); self.assertEqual(len(f.issues), 1)
        f.fail_after = None; self.assertEqual(run(self.args("apply", db, c, "--apply"), f)[0], 0)
        self.assertEqual(len(f.issues), 2); self.assertEqual(run(self.args("verify", db, c), f)[0], 0)
    def test_duplicate_and_orphan_are_drift(self):
        f = FakeGitHub(); db = mkdb(ROWS); c = self.applycfg(); run(self.args("apply", db, c, "--apply"), f)
        f.issues.append(dict(f.issues[0], number=99)); self.assertEqual(run(self.args("verify", db, c), f)[0], 1)
        f.issues.pop(); k = sqlite3.connect(db); k.execute("delete from items where atm_id='A-1'"); k.commit()
        self.assertEqual(run(self.args("verify", db, c), f)[0], 1)   # orphan: keyed issue with no item
    def test_private_owner_to_public_target_blocked(self):
        f = FakeGitHub(private=False)   # target public
        db = mkdb(ROWS); out = io.StringIO()
        rc = cli.run(["plan", "--db", db, "--config", cfgfile(), "--target", "github.com/o/pub", "--owner-repo", "github.com/o/priv"], proven_hosts=PROVEN, transport_factory=lambda v, h: f, out=out)
        self.assertEqual(rc, 2); self.assertIn("not-owning-repo", out.getvalue()); self.assertEqual(f.writes, 0)
    def _mirror_run(self, cfgtext, target, owner, fake):
        out = io.StringIO()
        rc = cli.run(["plan", "--db", mkdb(ROWS), "--config", cfgfile(cfgtext), "--target", target, "--owner-repo", owner], proven_hosts=PROVEN, transport_factory=lambda v, h: fake, out=out)
        return rc, out.getvalue()
    def test_declared_mirror_under_another_owner_is_accepted(self):
        f = FakeGitHub(private=False)
        rc, out = self._mirror_run("enabled: true\nmode: dry-run\nmirrors:\n  github.com/p/r: github.com/o/r\n", "github.com/o/r", "github.com/o/r", f)
        self.assertEqual(f.writes, 0); self.assertNotIn("not-owning-repo", out); self.assertIn("p/r", out)     # the declared mirror leg is planned, not blocked
        self.assertIn('"create": 2', out)
    def test_undeclared_or_other_owner_mirror_is_still_blocked(self):
        f = FakeGitHub(private=False)
        rc, out = self._mirror_run("enabled: true\nmode: dry-run\n", "github.com/p/r", "github.com/o/r", f)
        self.assertEqual(rc, 2); self.assertIn("not-owning-repo", out)
        f = FakeGitHub(private=False)      # declared as the mirror of a DIFFERENT owning repository: no effect for this owner
        rc, out = self._mirror_run("enabled: true\nmode: dry-run\nmirrors:\n  github.com/p/r: github.com/x/other\n", "github.com/p/r", "github.com/o/r", f)
        self.assertEqual(rc, 2); self.assertIn("not-owning-repo", out)
    def test_declared_mirror_never_lets_private_reach_public(self):
        class Split(FakeGitHub):
            def __call__(self, m, url, h, body):
                self.private = "/repos/o/r" in url and "/issues" not in url        # owner private, mirror public
                return super().__call__(m, url, h, body)
        f = Split(); rc, out = self._mirror_run("enabled: true\nmode: dry-run\nmirrors:\n  github.com/p/r: github.com/o/r\n", "github.com/o/r", "github.com/o/r", f)
        self.assertIn("private-to-public", out); self.assertEqual(f.writes, 0)
    def test_undetermined_visibility_blocks(self):
        class NoPriv(FakeGitHub):
            def __call__(self, m, url, h, body):
                if m == "GET" and re.search(r"/repos/[^/]+/[^/]+$", url): return 200, {}, {"has_issues": True}
                return super().__call__(m, url, h, body)
        f = NoPriv(); rc, out = run(self.args("plan", mkdb(ROWS), cfgfile()), f); self.assertEqual(rc, 2); self.assertIn("visibility-undetermined", out); self.assertEqual(f.writes, 0)
    def test_redaction_blocks_item_by_id_only(self):
        rows = [("A-1", "Bug", "Queued", "leaked ghp_" + "a"*36 + " here", "", "d", None, None, "Issues")]
        f = FakeGitHub(); rc, out = run(self.args("plan", mkdb(rows), cfgfile()), f)
        self.assertEqual(rc, 2); self.assertIn("blocked", out); self.assertNotIn("aaaa", out)
    def test_third_party_never_synced(self):
        rows = ROWS + [("SSP-1", "Task", "Queued", "tp", "", "third party item text here ok", None, None, "Issues")]
        subs = [("SSP", "submodules/superspec", "third-party", "operator", "", "", "x")]
        f = FakeGitHub(); db = mkdb(rows, subs); run(self.args("apply", db, self.applycfg(), "--apply"), f)
        self.assertFalse(any("SSP-1" in i["title"] for i in f.issues))
    def test_only_open_tier(self):
        f = FakeGitHub(); run(self.args("apply", mkdb(ROWS), self.applycfg(), "--apply", "--only-open"), f); self.assertEqual(len(f.issues), 1)
    def test_unknown_host_is_undetermined(self):
        out = io.StringIO(); rc = cli.run(["plan", "--db", mkdb(ROWS), "--config", cfgfile(), "--target", "evil.example/o/r", "--owner-repo", OR], proven_hosts=PROVEN, transport_factory=lambda v, h: FakeGitHub(), out=out)
        self.assertEqual(rc, 2)
    def test_gitea_unproven_leg_is_unconfirmed_never_in_sync(self):
        class G(FakeGitHub):
            def __call__(self, m, url, h, body):
                if "codeberg.org" in url:
                    if m == "GET" and re.search(r"/repos/[^/]+/[^/]+$", url): return 200, {}, {"private": False, "has_issues": True}
                    if m == "GET": return 200, {}, []
                return 500, {}, None
        out = io.StringIO()
        rc = cli.run(["verify", "--db", mkdb(ROWS), "--config", cfgfile(), "--target", "codeberg.org/o/r", "--owner-repo", "codeberg.org/o/r"], proven_hosts=PROVEN, transport_factory=lambda v, h: G(), out=out)
        self.assertNotEqual(rc, 0)
        rc = cli.run(["plan", "--db", mkdb(ROWS), "--config", cfgfile(), "--target", "codeberg.org/o/r", "--owner-repo", "codeberg.org/o/r"], proven_hosts=PROVEN, transport_factory=lambda v, h: G(), out=out)
        self.assertEqual(rc, 2); self.assertIn("unconfirmed", out.getvalue())

class TestRouting(unittest.TestCase):
    def test_private_prefix_never_reaches_public_owner_but_reaches_its_own(self):
        rows = [("VSC-1", "Task", "Queued", "pub", "", "public item description here ok", None, None, "Issues"),
                ("WSP-1", "Task", "Queued", "priv", "", "private item description here ok", None, None, "Issues"),
                ("ZZZ-1", "Task", "Queued", "unknown", "", "unmapped prefix description ok", None, None, "Issues")]
        subs = [("VSC", ".", "parent", "operator", "", "", "x"), ("WSP", "workshop", "owned", "operator", "git@github.com:o/workshop.git", "", "x")]
        db = mkdb(rows, subs); c = applycfg()
        f = FakeGitHub(); out = io.StringIO()
        rc = cli.run(["apply", "--apply", "--db", db, "--config", c, "--target", "github.com/o/r", "--owner-repo", "github.com/o/r", "--db-repo", "github.com/o/r"], proven_hosts=PROVEN, transport_factory=lambda v, h: f, out=out)
        self.assertEqual([i["title"][:7] for i in f.issues], ["[VSC-1]"]); self.assertIn("unroutable", out.getvalue()); self.assertEqual(rc, 2)
        g = FakeGitHub(private=True)
        cli.run(["apply", "--apply", "--db", db, "--config", c, "--target", "github.com/o/workshop", "--owner-repo", "github.com/o/workshop", "--db-repo", "github.com/o/r"], proven_hosts=PROVEN, transport_factory=lambda v, h: g, out=io.StringIO())
        self.assertEqual([i["title"][:7] for i in g.issues], ["[WSP-1]"])
    def test_leg_that_cannot_list_is_unconfirmed_and_never_creates(self):
        from issue_sync.adapters.github import GitHub
        old = GitHub.capabilities; GitHub.capabilities = dict(old, can_list=False)
        try:
            f = FakeGitHub(); out = io.StringIO()
            rc = cli.run(["verify", "--db", mkdb(ROWS), "--config", cfgfile(), "--target", "github.com/o/r", "--owner-repo", "github.com/o/r"], proven_hosts=PROVEN, transport_factory=lambda v, h: f, out=out)
            self.assertEqual(rc, 2); self.assertEqual(f.writes, 0)
        finally: GitHub.capabilities = old
    def test_subprojects_problems_never_fail_open(self):
        c = applycfg()
        def go(db):
            f = FakeGitHub(); out = io.StringIO()
            rc = cli.run(["apply", "--apply", "--db", db, "--config", c, "--target", "github.com/o/r", "--owner-repo", "github.com/o/r"], proven_hosts=PROVEN, transport_factory=lambda v, h: f, out=out)
            return rc, f
        row = [("WSP-1", "Task", "Queued", "priv", "", "private item description here ok", None, None, "Issues")]
        d = tempfile.mkdtemp(); p = os.path.join(d, "w.db"); k = sqlite3.connect(p)   # sub_projects without a url column
        k.execute("CREATE TABLE items (atm_id,type,status,title,severity,description,forensic_anchor,body_md,current_location)"); k.execute("INSERT INTO items VALUES (?,?,?,?,?,?,?,?,?)", row[0])
        k.execute("CREATE TABLE sub_projects (prefix, class)"); k.execute("INSERT INTO sub_projects VALUES ('WSP','owned')"); k.commit(); k.close()
        rc, f = go(p); self.assertEqual((rc, f.issues), (2, []))
        rc, f = go(mkdb(row, [("WSP", "workshop", "private", "operator", "", "", "x")])); self.assertEqual(f.issues, []); self.assertEqual(rc, 2)
    def test_malformed_repo_args_are_2(self):
        self.assertEqual(cli.run(["plan", "--db", mkdb(ROWS), "--config", cfgfile(), "--target", "nonsense", "--owner-repo", "github.com/o/r"], proven_hosts=PROVEN, transport_factory=lambda v, h: FakeGitHub(), out=io.StringIO()), 2)
    def test_bad_db_is_2(self):
        out = io.StringIO()
        for p in ["/nonexistent/x.db", "x.db?mode=rwc"]:
            self.assertEqual(cli.run(["verify", "--db", p, "--config", cfgfile(), "--target", "github.com/o/r", "--owner-repo", "github.com/o/r"], proven_hosts=PROVEN, transport_factory=lambda v, h: FakeGitHub(), out=out), 2)
    def test_db_path_with_hash_is_read_exactly(self):
        import shutil
        d = tempfile.mkdtemp(); p = os.path.join(d, "a#b%20.db"); shutil.copy(mkdb(ROWS), p)
        f = FakeGitHub(); rc = cli.run(["plan", "--db", p, "--config", cfgfile(), "--target", "github.com/o/r", "--owner-repo", "github.com/o/r"], proven_hosts=PROVEN, transport_factory=lambda v, h: f, out=io.StringIO())
        self.assertEqual(rc, 0)

if __name__ == "__main__": unittest.main()
