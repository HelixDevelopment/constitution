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
    def test_gitflic_writes_unverified_until_proven(self):
        a = GitFlic(Fake())
        self.assertTrue(a.capabilities["can_list"]); self.assertFalse(a.capabilities["can_create"] or a.capabilities["can_close"] or a.capabilities["can_label"])
        for fn in (lambda: a.create_issue("o", "r", "t", "b", []), lambda: a.update_issue("o", "r", 1, "t", "b", []), lambda: a.set_state("o", "r", 1, "closed")):
            with self.assertRaises(AdapterError) as c: fn()
            self.assertTrue(c.exception.code.startswith("capability_unverified"))
    def test_gitflic_request_shapes_when_proven(self):
        iss = {"localId": 3, "title": "T", "description": "B", "status": {"id": "OPEN"}, "labels": []}
        f = Fake((200, {}, iss), (200, {}, dict(iss, status={"id": "COMPLETED"})), (200, {}, iss), (200, {}, iss))
        a = GitFlic(f, proven=True)
        self.assertEqual(a.create_issue("o", "r", "T", "B", [])["state"], "open")
        self.assertEqual(f.calls[0][0:2], ("POST", "https://api.gitflic.ru/project/o/r/issue")); self.assertEqual(f.calls[0][2]["assignedUsers"], [])
        f2 = Fake((200, {}, iss), (200, {}, dict(iss, status={"id": "COMPLETED"})))
        r = GitFlic(f2, proven=True).set_state("o", "r", 3, "closed")
        self.assertEqual(r["state"], "closed")
        self.assertEqual(f2.calls[1][0:2], ("PUT", "https://api.gitflic.ru/project/o/r/issue/3/edit"))
        self.assertEqual(f2.calls[1][2]["status"], {"id": "COMPLETED"}); self.assertEqual(f2.calls[1][2]["title"], "T")
        f3 = Fake((200, {}, iss), (200, {}, dict(iss, status={"id": "CLOSED"})))
        GitFlic(f3, proven=True).set_state("o", "r", 3, "closed", not_planned=True); self.assertEqual(f3.calls[1][2]["status"], {"id": "CLOSED"})
    def test_gitflic_list_pages_and_repo_info(self):
        page = lambda n, tp: {"_embedded": {"issueModelList": [{"localId": n, "title": "t", "description": None, "status": {"id": "IN_PROGRESS"}, "labels": []}]}, "page": {"totalPages": tp}}
        out = GitFlic(Fake((200, {}, page(1, 2)), (200, {}, page(2, 2)))).list_issues("o", "r")
        self.assertEqual([i["number"] for i in out], [1, 2]); self.assertEqual(out[0]["state"], "open")
        self.assertEqual(GitFlic(Fake((404, {}, None))).repo_info("o", "r")["exists"], False)
        self.assertTrue(GitFlic(Fake((200, {}, {"private": True}))).repo_info("o", "r")["private"])
        with self.assertRaises(AdapterError): GitFlic(Fake((200, {}, {"name": "x"}))).repo_info("o", "r")   # visibility missing: never guessed
    def test_gitflic_uses_token_scheme_not_bearer(self):
        from issue_sync.adapters import base
        self.assertEqual(registry.transport_auth("gitflic.ru"), GitFlic.transport_auth)
        self.assertIsNone(registry.transport_auth("codeberg.org"))
        self.assertEqual(base.HttpTransport("tok-abcdefgh", auth_header=GitFlic.transport_auth).auth_header("x"), {"Authorization": "token x"})
        self.assertEqual(base.HttpTransport("tok-abcdefgh").auth_header("x"), {"Authorization": "Bearer x"})
    def test_registry_unknown_host_and_known(self):
        hosts = registry.load_hosts()
        self.assertIn("github.com", hosts); self.assertEqual(hosts["gitflic.ru"]["provider"], "gitflic")
        self.assertIsNone(registry.make("evil.example", lambda v, h: Fake(), hosts))
        self.assertIsInstance(registry.make("github.com", lambda v, h: Fake(), hosts), GitHub)

class TestTransport(unittest.TestCase):
    def mk(self, outcomes):
        from issue_sync.adapters import base
        import urllib.error, io
        tr = base.HttpTransport("tok-abcdefgh", min_interval=0, sleep=lambda s: None)
        calls = []
        class Op:
            def open(_, req, timeout=None):
                calls.append(req.full_url); o = outcomes.pop(0)
                if isinstance(o, Exception): raise o
                return o
        tr._opener = Op(); return tr, calls
    def test_https_only(self):
        from issue_sync.adapters import base
        tr, _ = self.mk([])
        with self.assertRaises(base.AdapterError): tr("GET", "http://api.github.com/x", {}, None)
    def test_redirect_refused(self):
        from issue_sync.adapters import base
        import urllib.error, io
        tr, calls = self.mk([urllib.error.HTTPError("https://a/x", 302, "f", {"Location": "https://evil/"}, io.BytesIO(b""))])
        with self.assertRaises(base.AdapterError) as c: tr("GET", "https://api.github.com/x", {}, None)
        self.assertEqual(c.exception.code, "redirect_refused")
    def test_redirect_handler_returns_none(self):
        from issue_sync.adapters import base
        self.assertIsNone(base._NoRedirect().redirect_request(None, None, 302, "m", {}, "https://evil/"))
    def test_post_not_retried_on_ambiguous_network_error(self):
        from issue_sync.adapters import base
        import urllib.error
        tr, calls = self.mk([urllib.error.URLError(TimeoutError("t"))])
        with self.assertRaises(base.AdapterError) as c: tr("POST", "https://api.github.com/x", {}, {})
        self.assertEqual(c.exception.code, "network_ambiguous_write"); self.assertEqual(len(calls), 1)
    def test_get_retried_and_post_retried_when_pre_send(self):
        from issue_sync.adapters import base
        import urllib.error, io
        class R:
            status = 200; headers = {}
            def read(self): return b"{}"
            def __enter__(self): return self
            def __exit__(self, *a): return False
        tr, calls = self.mk([urllib.error.URLError(TimeoutError("t")), R()]); self.assertEqual(tr("GET", "https://x/a", {}, None)[0], 200); self.assertEqual(len(calls), 2)
        tr, calls = self.mk([urllib.error.URLError(ConnectionRefusedError()), R()]); self.assertEqual(tr("POST", "https://x/a", {}, {})[0], 200); self.assertEqual(len(calls), 2)
    def test_retry_after_forms(self):
        from issue_sync.adapters.base import retry_after_seconds as r
        self.assertEqual(r("5", 0), 5.0); self.assertEqual(r(None, 3), 8.0); self.assertEqual(r("garbage", 2), 4.0); self.assertEqual(r("999", 0), 120.0)
        self.assertEqual(r("Wed, 21 Oct 2015 07:28:00 GMT", 0), 0.0)

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
