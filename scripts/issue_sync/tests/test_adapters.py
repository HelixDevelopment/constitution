"""Offline logic tests of request shapes and response normalisation. A fake transport proves only THIS tool's own logic (anchor 11.4.289);
host behaviour is proven by the recorded live read-only probe evidence, not here."""
import os, stat, sys, tempfile, unittest
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))
from issue_sync import credentials as cr, registry
from issue_sync.adapters.base import AdapterError
from issue_sync.adapters.github import GitHub
from issue_sync.adapters.gitlab import GitLab
from issue_sync.adapters.gitea import Gitea
from issue_sync.adapters.gitverse import GitVerse
from issue_sync.adapters.gitflic import GitFlic


class Fake:
    def __init__(self, *replies): self.calls, self.replies = [], list(replies)
    def __call__(self, m, u, h, b):
        self.calls.append((m, u, b)); return self.replies.pop(0)

GH = {"number": 7, "html_url": "https://github.com/o/r/issues/7", "title": "[A-1] t", "body": "b", "state": "open", "labels": [{"name": "wi-sync"}]}

class TestAdapters(unittest.TestCase):
    def test_github_create_shape_and_norm(self):
        f = Fake((201, {}, GH)); a = GitHub(f)
        n = a.create_issue("o", "r", "[A-1] t", "b", ["wi-sync"])
        self.assertEqual(f.calls[0], ("POST", "https://api.github.com/repos/o/r/issues", {"title": "[A-1] t", "body": "b", "labels": ["wi-sync"]}))
        self.assertEqual(n["number"], 7); self.assertEqual(n["labels"], ["wi-sync"])
    def test_github_close_reasons(self):
        f = Fake((200, {}, dict(GH, state="closed")), (200, {}, dict(GH, state="closed")), (200, {}, GH)); a = GitHub(f)
        a.set_state("o", "r", 7, "closed"); a.set_state("o", "r", 7, "closed", not_planned=True); a.set_state("o", "r", 7, "open")
        self.assertEqual([c[2] for c in f.calls], [{"state": "closed", "state_reason": "completed"}, {"state": "closed", "state_reason": "not_planned"}, {"state": "open", "state_reason": "reopened"}])
    def test_github_list_skips_pull_requests_and_pages(self):
        page1 = [dict(GH, number=i) for i in range(100)]; page1[3] = dict(page1[3], pull_request={})
        f = Fake((200, {}, page1), (200, {}, [dict(GH, number=500)])); out = GitHub(f).list_issues("o", "r")
        self.assertEqual(len(out), 100); self.assertEqual(len(f.calls), 2); self.assertIn("page=2", f.calls[1][1])
    def test_github_repo_info(self):
        self.assertEqual(GitHub(Fake((200, {}, {"private": True, "has_issues": True}))).repo_info("o", "r"), {"exists": True, "private": True, "issues_enabled": True})
        self.assertFalse(GitHub(Fake((404, {}, {}))).repo_info("o", "r")["exists"])
        with self.assertRaises(AdapterError): GitHub(Fake((500, {}, {}))).repo_info("o", "r")
    def test_unexpected_status_raises(self):
        with self.assertRaises(AdapterError) as c: GitHub(Fake((422, {}, {}))).create_issue("o", "r", "t", "b", [])
        self.assertEqual(c.exception.code, "unexpected_status_422")
    def test_gitlab_encoding_iid_and_events(self):
        j = {"iid": 3, "web_url": "https://gitlab.com/o/r/-/issues/3", "title": "t", "description": "d", "state": "opened", "labels": ["b", "a"]}
        f = Fake((201, {}, j), (200, {}, dict(j, state="closed")), (200, {}, j)); a = GitLab(f)
        n = a.create_issue("o", "r", "t", "d", ["a", "b"]); self.assertEqual(n["number"], 3); self.assertEqual(n["labels"], ["a", "b"])
        self.assertTrue(f.calls[0][1].endswith("/projects/o%2Fr/issues")); self.assertEqual(f.calls[0][2]["labels"], "a,b")
        self.assertEqual(a.set_state("o", "r", 3, "closed")["state"], "closed"); a.set_state("o", "r", 3, "open")
        self.assertEqual([c[2] for c in f.calls[1:]], [{"state_event": "close"}, {"state_event": "reopen"}])
    def test_gitlab_repo_info_visibility(self):
        self.assertTrue(GitLab(Fake((200, {}, {"visibility": "private"}))).repo_info("o", "r")["private"])
        self.assertFalse(GitLab(Fake((200, {}, {"visibility": "public"}))).repo_info("o", "r")["private"])
        self.assertIsNone(GitLab(Fake((200, {}, {}))).repo_info("o", "r")["private"])
    def test_gitea_writes_refused_until_proven(self):
        a = Gitea(Fake()); 
        for fn in (lambda: a.create_issue("o", "r", "t", "b", []), lambda: a.update_issue("o", "r", 1, "t", "b", []), lambda: a.set_state("o", "r", 1, "closed")):
            with self.assertRaises(AdapterError) as c: fn()
            self.assertTrue(c.exception.code.startswith("capability_unverified"))
        j = {"number": 1, "html_url": "u", "title": "t", "body": "b", "state": "open", "labels": []}
        f = Fake((201, {}, j)); self.assertEqual(Gitea(f, proven=True).create_issue("o", "r", "t", "b", [])["number"], 1)
    def test_gitverse_never_claims_close(self):
        a = GitVerse(Fake(), proven=True)
        self.assertFalse(a.capabilities["can_close"]); self.assertTrue(a.capabilities["can_create"])
        self.assertIn("gitverse.object", a.default_headers["Accept"])
        with self.assertRaises(AdapterError): a.set_state("o", "r", 1, "closed")
    def test_gitflic_all_unverified(self):
        a = GitFlic(Fake())
        self.assertFalse(any(a.capabilities.values()))
        for fn in (lambda: a.repo_info("o", "r"), lambda: a.list_issues("o", "r"), lambda: a.create_issue("o", "r", "t", "b", [])):
            with self.assertRaises(AdapterError): fn()
    def test_registry_unknown_host_and_known(self):
        hosts = registry.load_hosts()
        self.assertIn("github.com", hosts); self.assertEqual(hosts["gitflic.ru"]["provider"], "gitflic")
        self.assertIsNone(registry.make("evil.example", lambda v, h: Fake(), hosts))
        self.assertIsInstance(registry.make("github.com", lambda v, h: Fake(), hosts), GitHub)

class TestCredentials(unittest.TestCase):
    def kf(self, text, mode=0o600):
        d = tempfile.mkdtemp(); p = os.path.join(d, "k.sh")
        with open(p, "w") as f: f.write(text)
        os.chmod(p, mode); return p
    def test_env_first_then_file(self):
        p = self.kf('export AAA_TOKEN="filevalue12345"\nBBB_TOKEN=other-value-9999\n')
        self.assertEqual(cr.resolve(["AAA_TOKEN"], env={"AAA_TOKEN": "envvalue12345"}, keys_file=p), ("found", "AAA_TOKEN", "envvalue12345"))
        self.assertEqual(cr.resolve(["AAA_TOKEN"], env={}, keys_file=p)[2], "filevalue12345")
        self.assertEqual(cr.resolve(["BBB_TOKEN"], env={}, keys_file=p)[2], "other-value-9999")
    def test_insecure_keys_file_refused(self):
        p = self.kf('AAA_TOKEN=filevalue12345\n', mode=0o644)
        self.assertEqual(cr.resolve(["AAA_TOKEN"], env={}, keys_file=p)[0], "absent")
    def test_symlink_refused(self):
        p = self.kf('AAA_TOKEN=filevalue12345\n'); l = p + ".lnk"; os.symlink(p, l)
        self.assertEqual(cr.resolve(["AAA_TOKEN"], env={}, keys_file=l)[0], "absent")
    def test_placeholder_and_invalid(self):
        self.assertEqual(cr.resolve(["T"], env={"T": "changeme-please"}, keys_file="/nonexistent")[0], "absent")
        self.assertEqual(cr.resolve(["T"], env={"T": "abc def ghi jkl"}, keys_file="/nonexistent"), ("invalid", "T", None))
    def test_never_executes_file(self):
        marker = os.path.join(tempfile.mkdtemp(), "ran")
        p = self.kf('touch %s\nAAA_TOKEN=filevalue12345\n' % marker)
        cr.resolve(["AAA_TOKEN"], env={}, keys_file=p); self.assertFalse(os.path.exists(marker))

if __name__ == "__main__": unittest.main()
