# constitution/scripts/anchors/tests/test_generate_us1.py
import sys, os, subprocess, tempfile
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from anchor_lib import extract_anchors

GEN = os.path.join(os.path.dirname(__file__), "..", "constitution_generate.py")

def test_sample_anchors_byte_identical_after_generate():
    with open("constitution/Constitution.md") as f:
        pre_text = f.read()
    pre_anchors = {a["id"]: a["body"] for a in extract_anchors(pre_text)}
    sample_ids = list(pre_anchors.keys())[:10]

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

        import yaml
        with open(index_out) as f:
            idx = yaml.safe_load(f)
        by_id = {a["id"]: a for a in idx["anchors"]}
        # known_ids fix (proactive verification, real corpus): a regrouped
        # per-group document legitimately contains a bullet/bold-form
        # cross-reference to an anchor id whose own heading lives in a
        # DIFFERENT group's file (e.g. §11.4.48's real "**Composition.**"
        # list cites "- §11.4.3", classified elsewhere) — extract_anchors()
        # cannot see that other id's heading when parsing only THIS
        # smaller file, so without known_ids it misreads the citation as a
        # fresh anchor opener and silently truncates the body being
        # re-parsed.
        #
        # known_ids must exclude the ids genuinely ASSIGNED TO this same
        # group (never the full 283-id set unconditionally) — confirmed
        # live: seeding canonical_ids with an id BEFORE its own real
        # opening line is reached (e.g. bold-form-only §11.4.100, whose
        # designated group DOES contain its genuine definition) makes that
        # genuine opening misread as a repeat self-citation instead,
        # silently swallowing the whole anchor into whatever body preceded
        # it. Excluding same-group ids from known_ids lets a genuine local
        # definition open normally (matching the original per-document
        # behaviour, where canonical_ids/opened_ids are never seeded with
        # an id before its own first real occurrence) while still
        # protecting every cross-group citation.
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

# T011b (FR-005 fault-injection Checked-by clause, /speckit-analyze finding E2):
# build_records already implements the duplicate-id sys.exit(3) path (T011) but
# shipped with no test proving it.
def test_duplicate_anchor_id_exits_3_naming_the_duplicate():
    with tempfile.TemporaryDirectory() as tmp:
        with open("constitution/Constitution.md") as f:
            text = f.read()
        # Duplicate a real, already-present anchor heading verbatim — the
        # FR-005 fault this Checked-by clause names: "a deliberately
        # duplicated anchor id."
        duped = text + "\n\n### §11.4.209 duplicate injected by test\nbody\n"
        broken = os.path.join(tmp, "duped_constitution.md")
        with open(broken, "w") as f:
            f.write(duped)
        r = subprocess.run(
            ["python3", GEN, "generate", "--source", broken,
             "--groups-dir", os.path.join(tmp, "out_groups"),
             "--index-out", os.path.join(tmp, "out_index.yaml")],
            capture_output=True, text=True,
        )
        assert r.returncode == 3, f"expected exit 3, got {r.returncode}: {r.stderr}"
        assert "11.4.209" in r.stderr, "exit code alone is not enough — FR-005 requires naming the duplicate"

if __name__ == "__main__":
    test_sample_anchors_byte_identical_after_generate()
    test_duplicate_anchor_id_exits_3_naming_the_duplicate()
    print("PASS")
