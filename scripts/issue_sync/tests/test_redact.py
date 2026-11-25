import os, unittest, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))
from issue_sync import redact as r, payload as p

class T(unittest.TestCase):
    def kinds(self, text): return {h["kind"] for h in r.scan({"title": text})}
    def test_secret_shapes(self):
        self.assertIn("github-token", self.kinds("x ghp_" + "a"*36))
        self.assertIn("github-token", self.kinds("github_pat_" + "A"*30))
        self.assertIn("gitlab-token", self.kinds("glpat-" + "b"*20))
        self.assertIn("aws-key", self.kinds("AKIA" + "A"*16))
        self.assertIn("private-key", self.kinds("-----BEGIN RSA PRIVATE KEY-----"))
        self.assertIn("assignment-secret", self.kinds("password = hunter2hunter2"))
        self.assertIn("bearer", self.kinds("Authorization: Bearer abcdefghijklmnop12345"))
    def test_more_secret_shapes(self):
        for kind, text in [("slack-token", "xoxb-" + "1"*12 + "-abcdef"), ("jwt", "eyJhbGciOiJI.eyJzdWIiOiIx.abcd1234"), ("stripe-key", "sk_live_" + "a"*20),
                           ("google-key", "AIza" + "B"*35), ("sendgrid-key", "SG." + "a"*22 + "." + "b"*22),
                           ("url-credentials", "https://user:pass@host.example/x"), ("url-credentials", "postgres://u:pw@db/x")]:
            self.assertIn(kind, self.kinds(text), kind)
    def test_json_quoted_and_llm_keys(self):
        for kind, text in [("assignment-secret", '{"password": "hunter2hunter2"}'), ("assignment-secret", '"api_key": "abcdefgh12345"'),
                           ("assignment-secret", "'token': 'abcdefgh12345'"), ("llm-key", "sk-ant-" + "a"*30), ("llm-key", "sk-" + "b"*30),
                           ("npm-token", "npm_" + "c"*36), ("aws-key", "ASIA" + "D"*16)]:
            self.assertIn(kind, self.kinds(text), text)
    def test_personal_data(self):
        self.assertIn("email", self.kinds("mail someone@example.org now"))
        self.assertIn("phone", self.kinds("call +7 495 123-45-67"))
    def test_operator_quote_markers(self):
        self.assertIn("operator-quote", self.kinds("Forensic anchor: verbatim operator text"))
    def test_clean(self):
        self.assertEqual(r.scan({"title": "Fix flaky test in parser", "description": "see docs/x.md"}), [])
    def test_hits_never_carry_text(self):
        hits = r.scan({"description": "ghp_" + "z"*36})
        self.assertEqual(set(hits[0]), {"field", "kind"})
        self.assertNotIn("z"*10, repr(hits))
    def test_fingerprint_corpus(self):
        corpus = "the private roadmap says we will acquire the competitor in march after the board vote"
        fps = r.fingerprints(corpus, k=6)
        hits = r.scan({"description": "note: we will acquire the competitor in march after the board vote ok"}, fingerprint_set=fps, k=6)
        self.assertEqual([h["kind"] for h in hits], ["private-corpus"])
        self.assertEqual(r.scan({"description": "totally unrelated text about parsers and lexers in general use"}, fingerprint_set=fps, k=6), [])
    def test_payload_allowlist(self):
        item = {"atm_id": "VSC-1", "type": "Bug", "status": "Queued", "title": "T", "severity": "High", "description": "D",
                "body_md": "SECRET LONG", "forensic_anchor": "quote", "test_diary": "x"}
        pl = p.build(item)
        self.assertEqual(set(pl), {"atm_id", "type", "status", "title", "severity", "description"})
        self.assertNotIn("SECRET", repr(pl))
    def test_payload_requires_id(self):
        with self.assertRaises(ValueError): p.build({"title": "x"})
    def test_hash_stable_and_sensitive(self):
        a = {"atm_id": "A-1", "type": "Task", "status": "Queued", "title": "t", "severity": "", "description": "d"}
        self.assertEqual(p.content_hash(p.build(a)), p.content_hash(p.build(dict(a))))
        b = dict(a); b["status"] = "Completed"
        self.assertNotEqual(p.content_hash(p.build(a)), p.content_hash(p.build(b)))
        c = dict(a); c["body_md"] = "ignored"
        self.assertEqual(p.content_hash(p.build(a)), p.content_hash(p.build(c)))
    def test_gate_blocks_on_hit(self):
        item = {"atm_id": "A-2", "type": "Task", "status": "Queued", "title": "token ghp_" + "q"*36, "severity": "", "description": "d"}
        res = p.prepare(item)
        self.assertEqual(res["verdict"], "BLOCKED"); self.assertEqual(res["item"], "A-2"); self.assertNotIn("qqqq", repr(res))
        ok = p.prepare({**item, "title": "fine"}); self.assertEqual(ok["verdict"], "OK"); self.assertIn("hash", ok)

if __name__ == "__main__": unittest.main()
