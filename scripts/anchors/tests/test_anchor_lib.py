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


def test_bullet_self_citation_after_definition_is_not_a_new_anchor():
    # Regression: constitution/Constitution.md legitimately cites an anchor's
    # own id again later via the `- §` bullet form (e.g. a summary/index
    # list) as a pointer, not a redefinition. This must stay inside the
    # ORIGINAL ###-form anchor's body, not open a phantom second record.
    src = (
        "### §11.4.1 — First anchor\n"
        "first anchor's real body\n"
        "more of the real body\n"
        "### §11.4.2 — Second anchor\n"
        "second anchor's body\n"
        "- §11.4.1 — First anchor short citation\n"
        "trailing prose after the citation line\n"
    )
    anchors = extract_anchors(src)
    ids = [a["id"] for a in anchors]
    assert ids == ["11.4.1", "11.4.2"], ids  # NOT ["11.4.1", "11.4.2", "11.4.1"]
    second = anchors[1]
    assert second["id"] == "11.4.2"
    # The citation line AND the trailing prose after it must both still be
    # inside §11.4.2's body (the citation never closed/reopened anything).
    assert "- §11.4.1 — First anchor short citation" in second["body"]
    assert "trailing prose after the citation line" in second["body"]


def test_bullet_self_citation_before_definition_still_resolves_to_the_real_definition():
    # Regression, the MORE dangerous ordering: a bullet citation to an id
    # appears BEFORE that id's real ###-form definition later in the same
    # document (verified real case: constitution/Constitution.md's real
    # §11.4.55 and §11.4.57). "First occurrence wins" would be WRONG here —
    # it would keep the short citation stub as if it were the canonical
    # anchor. The ### form must win regardless of document order.
    src = (
        "### §11.4.1 — First anchor\n"
        "- §11.4.9 — Ninth anchor citation, appearing before its real definition\n"
        "rest of the first anchor's body\n"
        "### §11.4.9 — Ninth anchor real definition\n"
        "the REAL body of the ninth anchor\n"
    )
    anchors = extract_anchors(src)
    ids = [a["id"] for a in anchors]
    assert ids == ["11.4.1", "11.4.9"], ids  # exactly two anchors, in document order
    ninth = anchors[1]
    # NOTE: corrected from the brief's literal ("Ninth anchor real
    # definition", no em-dash) to match extract_anchors's established,
    # pre-existing, ALREADY-CORRECT ###-form title-capture convention
    # (title includes the em-dash prefix — see the untouched, pre-existing
    # test_extracts_all_three_opener_forms's own
    # `anchors[0]["title"] == "— Heading form"` assertion above, and
    # verified directly by running this exact src through extract_anchors).
    # This task's fix targets the id/body dedup hazard the `ids ==` +
    # `body` assertions below verify; the title-capture behavior is
    # out of scope and was never broken.
    assert ninth["title"] == "— Ninth anchor real definition"
    assert "the REAL body of the ninth anchor" in ninth["body"]
    # The early citation line must have stayed inside §11.4.1's body, never
    # having spuriously "become" the ninth anchor's own (wrong, stub) body.
    first = anchors[0]
    assert "- §11.4.9 — Ninth anchor citation" in first["body"]


def test_genuine_duplicate_hash_form_heading_still_detected_downstream():
    # Negative control: this fix must NOT swallow a REAL duplicate ###-form
    # heading (an actual redefinition/typo) — that is a genuine error
    # condition build_records (T011, not this library) is responsible for
    # catching via its own duplicate-id check. extract_anchors's job here is
    # only to stop MANUFACTURING false duplicates from self-citations; two
    # genuine ###-form openers with the same id must still both appear in
    # extract_anchors's output list (unfiltered) so that check can fire.
    src = (
        "### §11.4.1 — First anchor\n"
        "body one\n"
        "### §11.4.1 — Accidentally duplicated real heading\n"
        "body two\n"
    )
    anchors = extract_anchors(src)
    ids = [a["id"] for a in anchors]
    assert ids == ["11.4.1", "11.4.1"], ids  # both genuine ###-openers present, unfiltered


if __name__ == "__main__":
    test_extracts_all_three_opener_forms()
    test_malformed_heading_raises()
    test_extracts_sub_anchor_letter_suffix_form()
    test_bold_inline_citation_is_not_mistaken_for_an_opener()
    test_genuine_bold_form_opener_still_recognized()
    test_bullet_self_citation_after_definition_is_not_a_new_anchor()
    test_bullet_self_citation_before_definition_still_resolves_to_the_real_definition()
    test_genuine_duplicate_hash_form_heading_still_detected_downstream()
    print("PASS")
