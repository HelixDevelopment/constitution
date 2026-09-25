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

def test_bold_inline_citation_is_not_mistaken_for_an_opener():
    # Regression: a bolded inline citation to ANOTHER anchor, embedded in
    # ordinary body prose ("**§11.4.30 carve-out.** This anchor is..."),
    # was previously mistaken for a malformed bold-form heading attempt and
    # raised MalformedHeadingError. It must instead be treated as ordinary
    # body text — the WHOLE line is not the bolded title (more, unbolded,
    # prose follows the closing ** on the same line), which is the
    # structural signal that distinguishes it from a genuine bold-form
    # opener (verified against the real corpus: constitution/Constitution.md
    # line 7949 has this exact shape, and reproduced the real crash before
    # this fix).
    src = (
        "### §11.4.95 amendment\n"
        "some earlier body text\n"
        "**§11.4.30 carve-out.** This anchor is an explicit named exception "
        "to a different rule, continuing as ordinary prose on the same line.\n"
        "more body text for §11.4.95\n"
        "### §11.4.96 — Next real anchor\n"
        "§11.4.96's body\n"
    )
    anchors = extract_anchors(src)
    ids = [a["id"] for a in anchors]
    # The inline citation must NOT create a spurious third anchor entry.
    assert ids == ["11.4.95", "11.4.96"], ids
    assert "**§11.4.30 carve-out.**" in anchors[0]["body"]  # stayed inside §11.4.95's body
    assert "more body text for §11.4.95" in anchors[0]["body"]


def test_genuine_bold_form_opener_still_recognized():
    # Negative control for the fix above: a REAL bold-form opener (the
    # whole line IS the bolded title, nothing after the closing ** on that
    # line) must still be recognized as an opener — the fix narrows the
    # false-positive, it must not also blind the parser to the legitimate
    # bold-form convention (used in this project's overflow docs, e.g.
    # docs/PROJECT_GOVERNANCE_ANCHORS.md).
    src = (
        "preamble\n"
        "**§11.4.1 extension — Real bolded heading form**\n"
        "body of that anchor\n"
    )
    anchors = extract_anchors(src)
    assert [a["id"] for a in anchors] == ["11.4.1"]
    assert anchors[0]["title"] == "extension — Real bolded heading form"


if __name__ == "__main__":
    test_extracts_all_three_opener_forms()
    test_malformed_heading_raises()
    test_extracts_sub_anchor_letter_suffix_form()
    test_bold_inline_citation_is_not_mistaken_for_an_opener()
    test_genuine_bold_form_opener_still_recognized()
    print("PASS")
