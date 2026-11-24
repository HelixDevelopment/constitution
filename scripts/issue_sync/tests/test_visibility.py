import os, unittest, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))
from issue_sync import visibility as v

class T(unittest.TestCase):
    def test_canonical(self):
        for u in ["git@github.com:Vasic-Digital/Containers.git", "https://github.com/vasic-digital/containers", "ssh://git@github.com/vasic-digital/containers.git"]:
            self.assertEqual(v.canonical_repo(u), ("github.com", "vasic-digital", "containers"))
        self.assertEqual(v.canonical_repo("ssh://git@git.m3w.org:2222/Helix/constitution.git"), ("git.m3w.org", "helix", "constitution"))
        self.assertIsNone(v.canonical_repo("not a url"))
    def test_resolve_from_probe(self):
        self.assertEqual(v.resolve(lambda r: {"private": True}), "private")
        self.assertEqual(v.resolve(lambda r: {"private": False}), "public")
        self.assertEqual(v.resolve(lambda r: None), "undetermined")
        self.assertEqual(v.resolve(lambda r: {}), "undetermined")
        self.assertEqual(v.resolve(lambda r: {"private": "maybe"}), "undetermined")
        def boom(r): raise OSError("net")
        self.assertEqual(v.resolve(boom), "undetermined")
    def test_allowed_same_repo_only(self):
        o = ("github.com", "a", "priv")
        ok, _ = v.allowed_target(o, ("github.com", "a", "priv"), "private", "private"); self.assertTrue(ok)
        ok, r = v.allowed_target(o, ("github.com", "a", "pub"), "private", "public"); self.assertFalse(ok); self.assertIn("owning", r)
        ok, _ = v.allowed_target(o, ("gitlab.com", "a", "priv"), "private", "private"); self.assertTrue(ok)  # mirror host, same owning repo name
    def test_undetermined_blocks(self):
        o = ("github.com", "a", "r")
        for ov, tv in [("undetermined", "public"), ("public", "undetermined"), ("undetermined", "undetermined")]:
            ok, r = v.allowed_target(o, o, ov, tv); self.assertFalse(ok); self.assertEqual(r, "visibility-undetermined")
    def test_private_never_to_public(self):
        o = ("github.com", "a", "r")
        ok, r = v.allowed_target(o, ("gitlab.com", "a", "r"), "private", "public"); self.assertFalse(ok); self.assertEqual(r, "private-to-public")
    def test_route_by_db_location(self):
        subs = {"WSP": ("github.com", "vasic-digital", "workshop_curriculum"), "VSC": ("github.com", "milos85vasic", "vasic")}
        self.assertEqual(v.owning_repo("WSP-12", subs, db_repo=("github.com", "milos85vasic", "vasic")), ("github.com", "vasic-digital", "workshop_curriculum"))
        self.assertIsNone(v.owning_repo("ZZZ-1", subs, db_repo=None))
        self.assertEqual(v.owning_repo("CON-3", {}, db_repo=("github.com", "helixdevelopment", "constitution")), ("github.com", "helixdevelopment", "constitution"))
    def test_third_party_never(self):
        self.assertTrue(v.is_third_party("SSP-1", {"SSP"}))

if __name__ == "__main__": unittest.main()
