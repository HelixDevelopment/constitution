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

if __name__ == "__main__":
    test_extracts_all_three_opener_forms()
    test_malformed_heading_raises()
    print("PASS")
