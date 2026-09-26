# constitution/scripts/anchors/tests/test_generate_us3.py
import subprocess, tempfile, os, shutil

GEN = os.path.join(os.path.dirname(__file__), "..", "constitution_generate.py")

def _run(args):
    return subprocess.run(["python3", GEN] + args, capture_output=True, text=True)

def test_determinism_two_check_runs_agree():
    with tempfile.TemporaryDirectory() as tmp:
        groups_dir = os.path.join(tmp, "groups")
        index_out = os.path.join(tmp, "index.yaml")
        r1 = _run(["generate", "--source", "constitution/Constitution.md",
                    "--groups-dir", groups_dir, "--index-out", index_out])
        assert r1.returncode == 0, r1.stderr
        c1 = _run(["check", "--source", "constitution/Constitution.md",
                    "--groups-dir", groups_dir, "--index-out", index_out])
        c2 = _run(["check", "--source", "constitution/Constitution.md",
                    "--groups-dir", groups_dir, "--index-out", index_out])
        assert c1.returncode == 0, c1.stderr
        assert c2.returncode == 0, c2.stderr

def test_malformed_heading_exits_2_no_partial_output():
    with tempfile.TemporaryDirectory() as tmp:
        broken = os.path.join(tmp, "broken.md")
        with open("constitution/Constitution.md") as f:
            text = f.read()
        broken_text = text.replace("### §11.4.209 ", "### §11.4.209(broken ", 1)
        with open(broken, "w") as f:
            f.write(broken_text)
        groups_dir = os.path.join(tmp, "out_groups")
        r = _run(["generate", "--source", broken,
                   "--groups-dir", groups_dir, "--index-out", os.path.join(tmp, "out_index.yaml")])
        assert r.returncode == 2, r.stdout + r.stderr
        assert not os.path.isdir(groups_dir) or not os.listdir(groups_dir), \
            "no partial output allowed on fail-loud exit"

def test_hand_edit_to_grouped_doc_detected_as_drift():
    with tempfile.TemporaryDirectory() as tmp:
        groups_dir = os.path.join(tmp, "groups")
        index_out = os.path.join(tmp, "index.yaml")
        _run(["generate", "--source", "constitution/Constitution.md",
              "--groups-dir", groups_dir, "--index-out", index_out])
        # Corrupt one grouped document by hand — this is the FR-012 paired mutation.
        target = next(f for f in os.listdir(groups_dir) if f.endswith(".md"))
        with open(os.path.join(groups_dir, target), "a") as f:
            f.write("\nHAND-EDITED LINE THAT MUST BE DETECTED AS DRIFT\n")
        r = _run(["check", "--source", "constitution/Constitution.md",
                   "--groups-dir", groups_dir, "--index-out", index_out])
        assert r.returncode == 1, "hand-edit MUST be detected as drift (FR-012)"

if __name__ == "__main__":
    test_determinism_two_check_runs_agree()
    test_malformed_heading_exits_2_no_partial_output()
    test_hand_edit_to_grouped_doc_detected_as_drift()
    print("PASS")
