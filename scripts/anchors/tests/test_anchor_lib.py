import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
from anchor_lib import extract_anchors, MalformedHeadingError, derive_metadata

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
    # body text. UPDATED (4th regression fix): the fixture now includes
    # §11.4.30's own ###-form definition, matching the real corpus, since
    # the discriminator is now "does this id have a ###-form definition
    # elsewhere" (canonical_ids), not "does this line fill the whole line."
    src = (
        "### §11.4.30 — Some earlier, unrelated, genuinely-canonical anchor\n"
        "§11.4.30's own real body text\n"
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
    assert ids == ["11.4.30", "11.4.95", "11.4.96"], ids
    ninetyfive = anchors[1]
    assert ninetyfive["id"] == "11.4.95"
    assert "**§11.4.30 carve-out.**" in ninetyfive["body"]
    assert "more body text for §11.4.95" in ninetyfive["body"]


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


def test_bold_anchor_whose_body_starts_on_the_same_line_is_not_silently_dropped():
    # Regression: a real anchor form (verified live in the actual
    # constitution/Constitution.md corpus, e.g. the real §11.4.170) is a
    # bold-form opener whose OWN body begins on the SAME physical line as
    # the closing ** — "**§<id> — Title (details).** Body text starts
    # immediately here..." This id has NO ###-form definition anywhere
    # else in the document (verified: it is genuinely bold-only). It MUST
    # open a new anchor — silently absorbing it into whatever anchor was
    # previously open, with no error and no warning, was the real defect:
    # 26 real anchors in the real corpus were being lost this way.
    src = (
        "### §11.4.1 — First anchor\n"
        "first anchor's body\n"
        "**§11.4.170 — A real same-line-body anchor (User mandate, 2026-06-25).** "
        "Body text for this anchor starts immediately on this same line.\n"
        "more body text for §11.4.170 on the next line\n"
        "### §11.4.171 — Next real anchor\n"
        "§11.4.171's body\n"
    )
    anchors = extract_anchors(src)
    ids = [a["id"] for a in anchors]
    assert ids == ["11.4.1", "11.4.170", "11.4.171"], ids  # NOT silently dropped
    bold_anchor = anchors[1]
    assert bold_anchor["id"] == "11.4.170"
    assert "Body text for this anchor starts immediately" in bold_anchor["body"]
    assert "more body text for §11.4.170 on the next line" in bold_anchor["body"]
    # And it did NOT get merged into §11.4.1's body:
    first_anchor = anchors[0]
    assert "Body text for this anchor starts immediately" not in first_anchor["body"]


def test_genuine_bold_form_opener_still_recognized_after_discriminator_change():
    # Re-confirmation of the pre-existing negative control (from the second
    # regression fix) under the NEW canonical_ids-based discriminator: a
    # real bold-form opener whose id has NO ###-form elsewhere (whole-line
    # OR same-line-body shape, doesn't matter which) must still be
    # recognized as an opener — the fix narrows nothing about GENUINE bold
    # anchors, it only widens what counts as "genuine."
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


def test_parenthesized_letter_suffix_form_is_recognized():
    # Regression: a real anchor form (verified live in the actual
    # constitution/Constitution.md corpus, §11.4.184(I) at line 10279) uses
    # a PARENTHESIZED letter suffix, not the earlier-recognized .LETTER
    # dotted form. Same underlying concept, different real-corpus
    # punctuation convention.
    src = (
        "### §11.4.184 — Base anchor\n"
        "base anchor's body\n"
        "### §11.4.184(I) — Extension anchor\n"
        "extension anchor's body\n"
    )
    anchors = extract_anchors(src)
    ids = [a["id"] for a in anchors]
    assert ids == ["11.4.184", "11.4.184(I)"], ids


def test_bold_only_id_self_citation_inside_another_anchor_does_not_truncate_it():
    # Regression: a real defect (verified live: Constitution.md's real
    # §11.4.214, a ###-form anchor, gets truncated by a bolded
    # self-citation to §11.4.202 embedded 10 lines into its own body,
    # because §11.4.202's real definition is bold-form-only and so never
    # enters canonical_ids). A bold-form citation to an id that was
    # ALREADY OPENED earlier in this same scan — by ANY form, not just
    # ###-form — must be recognized as self-citation, never a new opener.
    src = (
        "**§11.4.202 — Bold-only anchor, defined here first**\n"
        "11.4.202's own real body\n"
        "### §11.4.214 — A real hash-form anchor\n"
        "11.4.214's body, part 1\n"
        "**§11.4.202 precedence (a citation embedded inside 11.4.214's body).**\n"
        "This text MUST stay part of 11.4.214's body, not get split off.\n"
        "11.4.214's body, part 2 — this line proves the anchor was not truncated\n"
        "### §11.4.215 — Next real anchor\n"
        "11.4.215's body\n"
    )
    anchors = extract_anchors(src)
    ids = [a["id"] for a in anchors]
    assert ids == ["11.4.202", "11.4.214", "11.4.215"], ids
    anchor_214 = anchors[1]
    assert anchor_214["id"] == "11.4.214"
    assert "11.4.214's body, part 1" in anchor_214["body"]
    assert "This text MUST stay part of 11.4.214's body" in anchor_214["body"]
    assert "11.4.214's body, part 2 — this line proves the anchor was not truncated" in anchor_214["body"]


def test_two_component_hash_form_id_is_recognized():
    # Regression: a real anchor form (verified live: Constitution.md's real
    # §9.2, §12.6, and 11 other real anchors) uses a 2-component id
    # ("9.2", not "9.2.0" or similar) via the ### form. Previously silently
    # dropped with zero error because the id-core pattern hardcoded a
    # minimum of 3 dot-separated numeric components.
    src = (
        "### §9.1 First 2-component anchor\n"
        "9.1's body\n"
        "### §9.2 Second 2-component anchor\n"
        "9.2's body\n"
        "### §11.4.1 A normal 3-component anchor, for contrast\n"
        "11.4.1's body\n"
    )
    anchors = extract_anchors(src)
    ids = [a["id"] for a in anchors]
    assert ids == ["9.1", "9.2", "11.4.1"], ids


def test_three_component_id_is_not_truncated_by_the_2_component_widening():
    # Guard against the greedy-optional-group regression this fix could
    # introduce: a genuine 3-component id must still match in FULL, never
    # truncated to its first 2 components.
    src = "### §11.4.10 A real 3-component anchor\nbody\n"
    anchors = extract_anchors(src)
    assert anchors[0]["id"] == "11.4.10", anchors[0]["id"]


def test_two_component_bullet_citation_to_an_undefined_id_is_not_a_phantom_anchor():
    # Regression: a real defect the NAIVE version of this fix would have
    # introduced (verified live: Constitution.md:7305's "- §1.1 (paired
    # mutation): ..." bullet, citing a 2-component id with ZERO heading-form
    # definition anywhere in the real corpus, despite 276 body-text
    # citations). Because bold/bullet forms deliberately keep their
    # existing 3-component-minimum id-core, this line must NOT be
    # recognized as an anchor opener at all — it stays ordinary body prose
    # inside whichever anchor it is actually part of.
    src = (
        "### §11.4.90 Some real anchor\n"
        "body line 1\n"
        "- §1.1 (paired mutation): every validate probe added per step 5 "
        "above MUST land with a mutation pair.\n"
        "body line 2 — this MUST stay part of §11.4.90's body\n"
        "### §11.4.91 Next real anchor\n"
        "11.4.91's body\n"
    )
    anchors = extract_anchors(src)
    ids = [a["id"] for a in anchors]
    assert ids == ["11.4.90", "11.4.91"], ids  # NOT ["11.4.90", "1.1", "11.4.91"]
    anchor_90 = anchors[0]
    assert "body line 1" in anchor_90["body"]
    assert "- §1.1 (paired mutation)" in anchor_90["body"]
    assert "body line 2 — this MUST stay part of" in anchor_90["body"]


def test_two_component_bold_citation_to_a_real_defined_id_is_still_a_self_citation():
    # A bold-form citation to a REAL 2-component ###-defined id (e.g. the
    # real corpus cites "§12.10" via bold form from elsewhere) must still
    # be excluded as a self-citation via canonical_ids, exactly like the
    # existing 3-component self-citation tests — confirms the restricted
    # widening composes correctly with fix round 1's canonical_ids/
    # opened_ids mechanism for the forms that DO stay recognized.
    src = (
        "### §9.2 A real 2-component anchor, defined here via ### form\n"
        "9.2's own body\n"
        "### §11.4.90 Another real anchor\n"
        "body line 1\n"
        "**§9.2 citation (a bolded reference to the anchor above).** "
        "This text MUST stay part of §11.4.90's body.\n"
        "body line 2\n"
        "### §11.4.91 Next real anchor\n"
        "11.4.91's body\n"
    )
    anchors = extract_anchors(src)
    ids = [a["id"] for a in anchors]
    assert ids == ["9.2", "11.4.90", "11.4.91"], ids  # NOT a duplicate "9.2"
    anchor_90 = [a for a in anchors if a["id"] == "11.4.90"][0]
    assert "This text MUST stay part of §11.4.90's body" in anchor_90["body"]


# append to constitution/scripts/anchors/tests/test_anchor_lib.py
from anchor_lib import assign_group, UnclassifiedAnchorError, extract_anchors

def test_known_ids_classify_into_expected_groups():
    assert assign_group("11.4.209") == "code-review-and-quality"
    assert assign_group("11.4.6") == "anti-bluff-and-evidence"
    assert assign_group("9.2") == "git-and-data-safety"
    assert assign_group("12.6") == "host-and-resource-safety"
    # fix round 2: both were found silently misclassified into
    # multi-track-and-parallelism despite ZERO range collision (only one
    # group ever claimed either tail) — a defect class the round-1
    # structural no-overlap test cannot catch by construction, so this
    # ground-truth spot-check is the only mechanism that locks them in.
    assert assign_group("11.4.186") == "documentation-and-export"
    assert assign_group("11.4.189") == "testing-and-tdd"

def test_unknown_id_raises_unclassified():
    try:
        assign_group("99.99.99")
        assert False, "expected UnclassifiedAnchorError"
    except UnclassifiedAnchorError:
        pass

def test_zero_unclassified_against_real_corpus():
    # This is the acceptance test named in Verified Notes: the LIVE
    # constitution/Constitution.md must classify with zero misses.
    with open("constitution/Constitution.md") as f:
        anchors = extract_anchors(f.read())
    unclassified = []
    for a in anchors:
        try:
            assign_group(a["id"])
        except UnclassifiedAnchorError:
            unclassified.append(a["id"])
    assert not unclassified, f"unclassified anchors: {unclassified}"

# fix round 1 (colliding-range regression, appended to
# constitution/scripts/anchors/tests/test_anchor_lib.py)
from anchor_lib import ID_RANGE_GROUPS

def test_no_two_groups_claim_the_same_numeric_tail():
    # Regression: verified live that ID_RANGE_GROUPS's ranges silently
    # overlapped for 12 real tails (176-182, 184, 185, 188, 190, 191) across
    # 4 different groups, with the FIRST group in list order silently
    # winning regardless of whether that group's theme actually matched the
    # id's real content (e.g. §11.4.176, genuinely about multi-track work
    # coordination, was resolving to git-and-data-safety). This structural
    # invariant test ensures NO tail is ever covered by more than one
    # group's ranges anywhere in the table, so this class of defect can
    # never silently regress.
    from collections import defaultdict
    tail_to_groups = defaultdict(set)
    for group_name, ranges in ID_RANGE_GROUPS:
        for lo, hi in ranges:
            for tail in range(lo, hi + 1):
                tail_to_groups[tail].add(group_name)
    collisions = {tail: groups for tail, groups in tail_to_groups.items() if len(groups) > 1}
    assert not collisions, f"tails claimed by more than one group: {collisions}"


def test_classification_defaults_to_unstated_never_universal_when_source_is_silent():
    # Final whole-branch review finding I-4, 2026-09-26, IMPORTANT:
    # derive_metadata used to default an ABSENT Classification line to the
    # specific enum value "universal" — measured against the real corpus,
    # this silently misrepresented 108/283 anchors as stating something
    # their source text never says. A body with NO Classification line at
    # all must derive "unstated", a fourth, genuinely distinct value —
    # never silently folded into any of the three real answers.
    body_with_no_classification_line = (
        "Some rule text that never mentions the word Classification at all, "
        "just an ordinary paragraph of prose describing a mandate.\n"
    )
    meta = derive_metadata(body_with_no_classification_line)
    assert meta["classification"] == "unstated", (
        f"a body with no Classification line MUST derive 'unstated', not "
        f"a fabricated specific answer — got {meta['classification']!r}"
    )
    # The three real, stated answers must still extract correctly — this
    # fix must not regress genuine extraction, only the silent default.
    assert derive_metadata("**Classification:** universal\n")["classification"] == "universal"
    assert derive_metadata("**Classification:** project-specific\n")["classification"] == "project-specific"
    assert derive_metadata("**Classification:** mixed\n")["classification"] == "mixed"


if __name__ == "__main__":
    # T009: runner entry point wired to invoke all 20 defined test functions
    # (moved to the end of the file so every function it calls, including
    # the 4 assign_group-family tests defined after the original mid-file
    # __main__ block, is already defined by the time this block executes).
    test_extracts_all_three_opener_forms()
    test_malformed_heading_raises()
    test_extracts_sub_anchor_letter_suffix_form()
    test_bold_inline_citation_is_not_mistaken_for_an_opener()
    test_genuine_bold_form_opener_still_recognized()
    test_bold_anchor_whose_body_starts_on_the_same_line_is_not_silently_dropped()
    test_genuine_bold_form_opener_still_recognized_after_discriminator_change()
    test_bullet_self_citation_after_definition_is_not_a_new_anchor()
    test_bullet_self_citation_before_definition_still_resolves_to_the_real_definition()
    test_genuine_duplicate_hash_form_heading_still_detected_downstream()
    test_parenthesized_letter_suffix_form_is_recognized()
    test_bold_only_id_self_citation_inside_another_anchor_does_not_truncate_it()
    test_two_component_hash_form_id_is_recognized()
    test_three_component_id_is_not_truncated_by_the_2_component_widening()
    test_two_component_bullet_citation_to_an_undefined_id_is_not_a_phantom_anchor()
    test_two_component_bold_citation_to_a_real_defined_id_is_still_a_self_citation()
    test_known_ids_classify_into_expected_groups()
    test_unknown_id_raises_unclassified()
    test_zero_unclassified_against_real_corpus()
    test_no_two_groups_claim_the_same_numeric_tail()
    test_classification_defaults_to_unstated_never_universal_when_source_is_silent()
    print("PASS")
