# constitution/scripts/anchors/tests/test_generate_minors.py
# Regression tests for deferred Minor findings N-1, N-2, N-5 (hermetic temp dirs;
# run from the parent repo root like test_generate_us3.py).
import subprocess, tempfile, os, yaml

GEN = os.path.join(os.path.dirname(__file__), "..", "constitution_generate.py")
SRC = "constitution/Constitution.md"

def _run(args):
    return subprocess.run(["python3", GEN] + args, capture_output=True, text=True)

def _args(tmp):
    return ["--source", SRC, "--groups-dir", os.path.join(tmp, "groups"),
            "--index-out", os.path.join(tmp, "index.yaml")]

def _gen(tmp):
    r = _run(["generate"] + _args(tmp))
    assert r.returncode == 0, r.stderr

def test_n1_check_reports_orphaned_sibling_exports():
    with tempfile.TemporaryDirectory() as tmp:
        _gen(tmp)
        g = os.path.join(tmp, "groups")
        orphan = os.path.join(g, "vanished_group.html")
        with open(orphan, "w") as f:
            f.write("<html/>")
        r = _run(["check"] + _args(tmp))
        assert r.returncode in (1, 4), (r.returncode, r.stderr)
        assert "vanished_group.html" in r.stderr, r.stderr
        # generate must NEVER delete siblings (I-1)
        _gen(tmp)
        assert os.path.exists(orphan), "generate must not delete orphaned siblings"

def test_n1_check_ignores_siblings_of_live_groups():
    with tempfile.TemporaryDirectory() as tmp:
        _gen(tmp)
        g = os.path.join(tmp, "groups")
        live = sorted(f[:-3] for f in os.listdir(g) if f.endswith(".md"))[0]
        with open(os.path.join(g, live + ".pdf"), "w") as f:
            f.write("x")
        r = _run(["check"] + _args(tmp))
        assert r.returncode == 0, r.stderr

def test_n2_generate_removes_stale_md():
    with tempfile.TemporaryDirectory() as tmp:
        _gen(tmp)
        stale = os.path.join(tmp, "groups", "stale_group.md")
        with open(stale, "w") as f:
            f.write("old")
        _gen(tmp)
        assert not os.path.exists(stale), "stale .md must be removed by generate"

def test_n2_check_detects_stale_md():
    with tempfile.TemporaryDirectory() as tmp:
        _gen(tmp)
        with open(os.path.join(tmp, "groups", "stale_group.md"), "w") as f:
            f.write("old")
        r = _run(["check"] + _args(tmp))
        assert r.returncode in (1, 4), (r.returncode, r.stderr)
        assert "stale_group.md" in r.stderr, r.stderr

def test_n5_scalar_or_list_generated_from_is_controlled_divergence():
    for bad in ("scalar", ["a", "b"]):
        with tempfile.TemporaryDirectory() as tmp:
            _gen(tmp)
            idx = os.path.join(tmp, "index.yaml")
            with open(idx) as f:
                d = yaml.safe_load(f)
            d["generated_from"] = bad
            with open(idx, "w") as f:
                yaml.safe_dump(d, f)
            r = _run(["check"] + _args(tmp))
            assert "Traceback" not in r.stderr, r.stderr
            assert r.returncode in (1, 4), (r.returncode, r.stderr)

if __name__ == "__main__":
    test_n1_check_reports_orphaned_sibling_exports()
    test_n1_check_ignores_siblings_of_live_groups()
    test_n2_generate_removes_stale_md()
    test_n2_check_detects_stale_md()
    test_n5_scalar_or_list_generated_from_is_controlled_divergence()
    print("PASS")
