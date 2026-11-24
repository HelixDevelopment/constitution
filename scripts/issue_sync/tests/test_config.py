import os, tempfile, unittest, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", ".."))
from issue_sync import config

def load(text):
    d = tempfile.mkdtemp()
    p = os.path.join(d, ".workable-items-sync.yaml")
    open(p, "w").write(text)
    return config.load(p)

class T(unittest.TestCase):
    def test_missing_file_is_disabled_default_off(self):
        cfg, errs = config.load("/nonexistent/.workable-items-sync.yaml")
        self.assertFalse(cfg["enabled"]); self.assertEqual(errs, [])
    def test_defaults_off(self):
        cfg, errs = load("{}\n")
        self.assertEqual(errs, []); self.assertFalse(cfg["enabled"]); self.assertEqual(cfg["mode"], "dry-run")
    def test_valid_enabled(self):
        cfg, errs = load("enabled: true\nscope: {recursive: true}\nmode: dry-run\ninterval_hours: 6\n")
        self.assertEqual(errs, []); self.assertTrue(cfg["enabled"]); self.assertTrue(cfg["scope"]["recursive"])
    def test_unknown_key_rejected(self):
        _, errs = load("enabled: true\nbogus: 1\n"); self.assertTrue(any("bogus" in e for e in errs))
    def test_bad_types(self):
        _, errs = load("enabled: 'yes'\n"); self.assertTrue(errs)
    def test_mode_enum(self):
        _, errs = load("mode: yolo\n"); self.assertTrue(errs)
    def test_apply_requires_decision(self):
        _, errs = load("enabled: true\nmode: apply\n"); self.assertTrue(any("apply_decision" in e for e in errs))
        _, errs = load("enabled: true\nmode: apply\napply_decision: docs/x.md\n"); self.assertEqual(errs, [])
    def test_interval_cap(self):
        _, errs = load("interval_hours: 25\n"); self.assertTrue(errs)
        _, errs = load("interval_hours: 0\n"); self.assertTrue(errs)
    def test_visibility_policy_only_owning_repo(self):
        _, errs = load("visibility_policy: everyone\n"); self.assertTrue(errs)
    def test_token_vars_names_only(self):
        _, errs = load("token_vars: {github.com: [GITHUB_TOKEN]}\n"); self.assertEqual(errs, [])
        _, errs = load("token_vars: {github.com: [ghp_abcdefghijklmnopqrstuvwxyz0123456789]}\n"); self.assertTrue(errs)
        _, errs = load("token_vars: {github.com: ['x y']}\n"); self.assertTrue(errs)
    def test_invalid_yaml(self):
        _, errs = load("a: [\n"); self.assertTrue(errs)
    def test_template_ships_off(self):
        t = os.path.join(os.path.dirname(__file__), "..", "..", "..", "templates", "workable-items-sync.yaml.template")
        cfg, errs = config.load(t); self.assertEqual(errs, []); self.assertFalse(cfg["enabled"])

if __name__ == "__main__": unittest.main()
