import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from anchor_lib import extract_anchors, MalformedHeadingError

def test_extracts_all_three_opener_forms():
    src = (
        "preamble text\n"
        "### §11.4.1 — Heading form\n"
        "body line 1\n"
        "body line 2\n"
        "**§11.4.2 — Bolded form**\n"
        "body line 3\n"
        "- §11.4.3 — Bullet form\n"
        "body line 4\n"
    )
    anchors = extract_anchors(src)
    assert [a["id"] for a in anchors] == ["11.4.1", "11.4.2", "11.4.3"]
    assert anchors[0]["title"] == "— Heading form"
    assert "body line 1" in anchors[0]["body"]
    assert "body line 2" in anchors[0]["body"]
    assert "body line 3" not in anchors[0]["body"]

def test_malformed_heading_raises():
    src = "### §11.4.209(broken title with no space after the number\n"
    try:
        extract_anchors(src)
        assert False, "expected MalformedHeadingError"
    except MalformedHeadingError:
        pass

def test_extracts_sub_anchor_letter_suffix_form():
    # Regression: the real constitution/Constitution.md contains a genuine
    # `§11.4.10.A` sub-anchor (a trailing `.LETTER` suffix on the normal
    # 3-component dotted id) — this is a VALID, real, currently-in-use
    # anchor form, not malformed input, and extract_anchors previously
    # raised MalformedHeadingError on it (crash reproduced against the real
    # file at line 753 before this fix).
    src = (
        "### §11.4.10 — Parent anchor\n"
        "parent body\n"
        "### §11.4.10.A — Pre-store credential leak audit (User mandate, 2026-05-17)\n"
        "sub-anchor body\n"
        "### §11.4.11 — Next anchor\n"
        "next body\n"
    )
    anchors = extract_anchors(src)
    ids = [a["id"] for a in anchors]
    assert ids == ["11.4.10", "11.4.10.A", "11.4.11"], ids
    assert anchors[0]["id"] != anchors[1]["id"]  # never truncate/collide the sub-anchor with its parent
    assert "sub-anchor body" in anchors[1]["body"]
    assert "sub-anchor body" not in anchors[0]["body"]

if __name__ == "__main__":
    test_extracts_all_three_opener_forms()
    test_malformed_heading_raises()
    test_extracts_sub_anchor_letter_suffix_form()
    print("PASS")
