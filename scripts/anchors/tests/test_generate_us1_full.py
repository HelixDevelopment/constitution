# constitution/scripts/anchors/tests/test_generate_us1_full.py
# T012 [US1]: US1's own Independent Test at full scale (all live anchors,
# not the 10-sample) — structurally identical to test_generate_us1.py's
# test_sample_anchors_byte_identical_after_generate, with sample_ids =
# list(pre_anchors.keys()) (no [:10] slice), as the story's closing
# acceptance run.
import sys, os, subprocess, tempfile
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from anchor_lib import extract_anchors

GEN = os.path.join(os.path.dirname(__file__), "..", "constitution_generate.py")

def test_all_anchors_byte_identical_after_generate():
    with open("constitution/Constitution.md") as f:
        pre_text = f.read()
    pre_anchors = {a["id"]: a["body"] for a in extract_anchors(pre_text)}
    sample_ids = list(pre_anchors.keys())  # full scale — no [:10] slice

    with tempfile.TemporaryDirectory() as tmp:
        groups_dir = os.path.join(tmp, "groups")
        index_out = os.path.join(tmp, "index.yaml")
        result = subprocess.run(
            ["python3", GEN, "generate",
             "--source", "constitution/Constitution.md",
             "--groups-dir", groups_dir, "--index-out", index_out],
            capture_output=True, text=True,
        )
        assert result.returncode == 0, result.stderr

        # Scenario-1 quickstart cross-check (§11.4.6 — never assume the two
        # counts agree without measuring both): the generator's own printed
        # count ("generated: N anchors across M groups") MUST match the
        # number of anchors this test independently extracted from the
        # source and is about to verify.
        assert f"generated: {len(pre_anchors)} anchors" in result.stdout, (
            f"generator's own printed count does not match this test's "
            f"independently-extracted count ({len(pre_anchors)}): "
            f"{result.stdout!r}"
        )

        import yaml
        with open(index_out) as f:
            idx = yaml.safe_load(f)
        by_id = {a["id"]: a for a in idx["anchors"]}
        all_ids = set(pre_anchors.keys())
        group_of = {a["id"]: a["group"] for a in idx["anchors"]}
        for aid in sample_ids:
            loc = by_id[aid]["location"]
            this_group = by_id[aid]["group"]
            group_file = loc.split("#")[0].replace("constitution/groups/", groups_dir + "/")
            with open(group_file) as f:
                grouped_text = f.read()
            ids_in_this_group = {i for i, g in group_of.items() if g == this_group}
            known_ids = all_ids - ids_in_this_group
            post_anchors = {a["id"]: a["body"] for a in extract_anchors(grouped_text, known_ids=known_ids)}
            assert post_anchors[aid] == pre_anchors[aid], f"{aid} diverged"

if __name__ == "__main__":
    test_all_anchors_byte_identical_after_generate()
    print("PASS")
