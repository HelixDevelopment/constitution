import io, os, sys, unittest
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))
from issue_sync import cli, offline_status
from issue_sync.tests_support import FakeGitHub, mkdb, cfgfile
ROWS = [("A-1", "Bug", "Queued", "first", "High", "first description text here ok", None, None, "Issues")]

class T(unittest.TestCase):
    def test_pending_until_applied_then_clean(self):
        db = mkdb(ROWS); self.assertEqual(offline_status.status(db)["pending"], 1)
        c = cfgfile("enabled: true\nmode: apply\napply_decision: d.md\n"); f = FakeGitHub()
        cli.run(["apply", "--apply", "--db", db, "--config", c, "--target", "github.com/o/r", "--owner-repo", "github.com/o/r"], transport_factory=lambda v, h: f, out=io.StringIO())
        self.assertEqual(offline_status.status(db), {"items": 1, "legs": 1, "pending": 0})
        import sqlite3; k = sqlite3.connect(db); k.execute("update items set title='changed'"); k.commit()
        self.assertEqual(offline_status.status(db, ids=True)["ids"], ["A-1"])
    def test_cli_status_makes_no_network_call_and_exit_codes(self):
        db = mkdb(ROWS); f = FakeGitHub(); out = io.StringIO()
        rc = cli.run(["status", "--db", db, "--config", cfgfile()], transport_factory=lambda v, h: f, out=out)
        self.assertEqual((rc, f.calls), (1, []))
if __name__ == "__main__": unittest.main()
