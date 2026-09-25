"""Shared anchor extraction + group-classification library.
Consumed by constitution_generate.py, constitution_link_check.py and
constitution_wiring_audit.py — the SINGLE parser for this feature
(research.md R2.4: extends, never duplicates, the existing
constitution/scripts/mechanical/anchor_census.sh opener forms).
"""
import re

# The `(?:\.[A-Z]|\([A-Z]+\))?` suffix on every id pattern below recognizes
# a real sub-anchor form — EITHER of two real-corpus punctuation conventions
# for the same underlying concept (a numbered extension of an existing
# anchor id):
#   - `.LETTER` (regression fix, real-corpus crash at Constitution.md:753,
#     heading "### §11.4.10.A — Pre-store credential leak audit") — a
#     trailing single-uppercase-letter suffix on the normal 3-component
#     dotted id.
#   - `(LETTER+)` (fix round 1 on the fourth regression, real-corpus crash
#     at Constitution.md:10279, heading "**§11.4.184(I) — HawkScan (DAST)
#     + OWASP ZAP + gitleaks + Trivy: mandatory local security-tooling
#     extension (operator mandate, 2026-09-18).**") — a parenthesized
#     one-or-more-uppercase-letter suffix, the SAME underlying "numbered
#     extension" concept as `.LETTER`, just a different real-corpus
#     punctuation convention; `[A-Z]+` (not just one letter) is deliberate,
#     accepting the obvious Roman-numeral continuation (`(II)`, `(III)`,
#     ...) the naming convention itself implies, even though only `(I)`
#     exists in the corpus today — a justified generalisation of an
#     established convention actually present in the document, not an
#     unevidenced guess.
# Either way, a sub-anchor id is distinct from and never truncated down to
# its parent id (§11.4.10 and §11.4.10.A are two separate, real anchors;
# likewise §11.4.184 and §11.4.184(I)).
# PER-FORM id-core width (fix round 2, real-corpus silent drop of 13
# genuine 2-component anchors, e.g. §9.2, §12.6, §12.10, §11.4, §7.1 —
# Constitution.md:400, :10097, :10127, :454, :282): the `### §` form's
# id-core is widened from EXACTLY 3 dot-separated numeric components
# (`\d+\.\d+\.\d+`) to a MANDATORY 2 with an OPTIONAL 3rd
# (`\d+\.\d+(?:\.\d+)?`) — every one of the 13 real 2-component ids uses
# `### §`-form exclusively, zero exceptions. The bold (`**§`) and bullet
# (`- §`) forms deliberately KEEP their existing 3-component-minimum
# id-core, UNCHANGED — widening those too would create a phantom anchor
# from Constitution.md:7305's `- §1.1 (paired mutation): ...`, a bullet
# citing the general mutation-testing convention (276 body-text citations
# throughout the document) that has ZERO heading-form definition anywhere;
# neither canonical_ids nor opened_ids (both require the id to be seen
# DEFINED somewhere first) can protect against that, since "1.1" is never
# defined. `_ATTEMPTED_OPENER_RE` (the loose gate) and `_STRICT_OPENER_RE`
# (the strict parser) must stay in agreement about what each form is
# allowed to match, so both are restructured the SAME way: from one
# id-core pattern shared across all three prefix forms into a per-form
# alternation, each form's id-core matching exactly what that form's
# `_STRICT_OPENER_RE` branch now requires.
_ATTEMPTED_OPENER_RE = re.compile(
    r'^(?:'
    r'### §\d+\.\d+(?:\.\d+)?(?:\.[A-Z]|\([A-Z]+\))?|'
    r'\*\*§\d+\.\d+\.\d+(?:\.[A-Z]|\([A-Z]+\))?|'
    r'- §\d+\.\d+\.\d+(?:\.[A-Z]|\([A-Z]+\))?'
    r')'
)
_STRICT_OPENER_RE = re.compile(
    r'^(?:'
    r'### §(?P<id1>\d+\.\d+(?:\.\d+)?(?:\.[A-Z]|\([A-Z]+\))?) (?P<title1>.+)$|'
    # Bold-form branch (regression fix #4, real-corpus silent drop of 26
    # real anchors, e.g. the real §11.4.170 and §11.4.202): unlike the
    # ### and - branches above/below, this branch has NO trailing `$` —
    # a genuine bold-form anchor's own body routinely starts on the SAME
    # physical line as its closing `**` (e.g. "**§11.4.170 — Title
    # (details).** Body text starts here immediately..."), which has the
    # IDENTICAL surface shape ("bold title, then more text on the same
    # line") as a false-positive inline citation to a DIFFERENT anchor
    # embedded in body prose. The whole-line-bold heuristic this fix
    # replaces could not tell these two cases apart. The real
    # discriminator is not "does the line end right after the closing
    # **" but "is this id ALREADY defined via a ### §-form heading
    # elsewhere in the document" (canonical_ids, checked in the main scan
    # loop below) — so this branch matches and captures id2/title2 up to
    # the FIRST closing ** regardless of what, if anything, follows it on
    # the same line; canonical_ids is what decides whether the match is a
    # genuine opener or an inline self-citation.
    r'\*\*§(?P<id2>\d+\.\d+\.\d+(?:\.[A-Z]|\([A-Z]+\))?) (?P<title2>.+?)\*\*|'
    r'- §(?P<id3>\d+\.\d+\.\d+(?:\.[A-Z]|\([A-Z]+\))?) (?P<title3>.+)$'
    r')'
)


class MalformedHeadingError(ValueError):
    """Raised when a line looks like an anchor opener (starts with one of the
    three known prefixes followed by a dotted id) but fails strict parsing —
    per contracts/generator-cli.md G-004, this MUST fail loud, never be
    silently skipped as ordinary prose."""


def extract_anchors(source_text: str) -> list[dict]:
    lines = source_text.splitlines()
    anchors: list[dict] = []
    current: dict | None = None

    # First pass (regression fix, real-corpus over-count 344->243): collect
    # the SET of ids that have at least one canonical `### §`-form occurrence
    # anywhere in the document, BEFORE the main scan begins. constitution/
    # Constitution.md legitimately re-cites an anchor's own id via the
    # `- §`/`**§` forms elsewhere (a short summary/index pointer TO an anchor
    # fully defined elsewhere via `###`, never a redefinition) — including,
    # verified against the real corpus, 2 of 40 such ids (§11.4.55,
    # §11.4.57) where the bullet-form citation appears BEFORE the real `###`
    # definition later in the file. Scanning the whole document up front
    # (rather than "first occurrence wins" during the single scan) is what
    # lets the fix recognize that early citation correctly: the `###` form
    # is always canonical regardless of document order. This same
    # canonical_ids set (regression fix #4) is now ALSO the discriminator
    # for `**§` matches, replacing the earlier whole-line-bold heuristic:
    # a `**§` match whose id is NOT in canonical_ids is a genuine opener
    # (the id has no ###-form definition anywhere else), regardless of
    # whether its own body starts on the same physical line.
    canonical_ids: set[str] = set()
    for line in lines:
        m = _STRICT_OPENER_RE.match(line)
        if m and m.group("id1") is not None:
            canonical_ids.add(m.group("id1"))

    # Second, DYNAMIC id-tracking set (fix round 1, Finding B — real-corpus
    # content-misattribution defect: §11.4.214, a genuine ###-form anchor at
    # Constitution.md:10654, was losing its own clauses (1)-(6) + Honest
    # boundary + Classification line to a spurious second "11.4.202" record,
    # because a bold-form self-citation to §11.4.202 — embedded 10 lines
    # into §11.4.214's OWN body at Constitution.md:10664 — was misread as a
    # new opener. canonical_ids alone cannot protect this: §11.4.202's real
    # definition is bold-form-ONLY (it has no ### §-form heading anywhere),
    # so it is never added to canonical_ids by the pre-scan above. opened_ids
    # closes that gap: it starts empty and is populated, DURING the main
    # scan below, with the id of every anchor actually opened so far (by ANY
    # of the three forms) — so a later bold/bullet-form self-citation to an
    # id this SAME scan has already opened (regardless of which form opened
    # it) is correctly recognized as ordinary body text, not a new anchor.
    # canonical_ids and opened_ids are complementary, not redundant:
    # canonical_ids protects a ###-form id's citations regardless of
    # document order (including cited-BEFORE-defined, per the third
    # regression fix's real §11.4.55/§11.4.57 case, since it is built from a
    # full-document pre-scan before the main loop even starts); opened_ids
    # additionally protects a bold/bullet-form-ONLY id's citations, but only
    # for those appearing AFTER that id's own opening (it is populated
    # during the single forward scan, so it structurally cannot "see
    # ahead").
    opened_ids: set[str] = set()

    def _close(end_line: int) -> None:
        current["end_line"] = end_line
        current["body"] = "\n".join(lines[current["start_line"] - 1:end_line])
        anchors.append(current)

    for lineno, line in enumerate(lines, start=1):
        if _ATTEMPTED_OPENER_RE.match(line):
            m = _STRICT_OPENER_RE.match(line)
            if not m:
                raise MalformedHeadingError(
                    f"line {lineno}: looks like an anchor opener but does not "
                    f"strictly parse: {line!r}"
                )
            anchor_id = m.group("id1") or m.group("id2") or m.group("id3")
            if m.group("id1") is None and anchor_id in (canonical_ids | opened_ids):
                # A `**§`/`- §` self-citation to an id that is ALSO defined
                # via `### §` elsewhere in the document (canonical_ids), OR
                # that this SAME scan has already opened earlier via ANY
                # form (opened_ids, fix round 1 Finding B), is ordinary body
                # text, not a new anchor opener — do not close the
                # currently-open anchor, do not open a new one. Every `### §`
                # match (id1 is not None) is exempt from this check and
                # continues to open a new anchor unconditionally, including
                # when it duplicates an already-seen id — that is a genuine
                # error condition build_records (not this function) is
                # responsible for catching.
                continue
            title = (m.group("title1") or m.group("title2") or m.group("title3")).strip()
            if current is not None:
                _close(lineno - 1)
            current = {"id": anchor_id, "title": title, "start_line": lineno}
            opened_ids.add(anchor_id)
    if current is not None:
        _close(len(lines))
    return anchors


# --- appended to constitution/scripts/anchors/anchor_lib.py ---
# Taxonomy source: research pass preserved at
# .superpowers/sdd/tasks-003-reorganize-constitution-yaml/
# foundational-phase-taxonomy-completion.md ("Complete, ready-to-paste
# updated Python structures" section) — pasted verbatim, including its own
# explanatory header comment below. That pass ran the real extract_anchors()
# + a faithful re-implementation of this same assign_group() against the
# live corpus as it stood at that time (243 anchors) and self-verified 0
# unclassified / 0 collisions / 0 gaps. T006/T007 (this task) additionally
# verified it against the CURRENT corpus (283 anchors, after a fourth
# regression fix taught extract_anchors to recognize 26 more same-line-bold
# real anchors) and widened/added entries as needed — see this task's
# report for the itemized list and rationale.

# Ranges are inclusive on the anchor's numeric TAIL within the "11.4" family
# (e.g. id "11.4.209" -> tail 209). Anchors outside that family (bare "9",
# "9.2", "12", "12.6".."12.12") are matched by EXPLICIT_ID_GROUPS below.
# Twelve groups total — satisfies FR-001's "small number of thematic /
# principle-bound documents" clarification (never one-file-per-anchor,
# never a monolith).
ID_RANGE_GROUPS = [
    ("anti-bluff-and-evidence", [(1, 7), (13, 13), (38, 38), (68, 69),  # 68 added, was (69,69) # WIDENED
                                  (83, 83), (105, 105), (107, 108), (110, 110),
                                  (123, 123), (139, 139), (146, 146), (158, 160),
                                  (163, 163), (193, 193),  # 193 added — T006/T007 283-corpus widening (see report)
                                  (201, 201), (226, 226), (262, 262),
                                  (268, 271)]),
    ("code-review-and-quality", [(124, 125),  # 124 added, was (125,125) # WIDENED
                                  (134, 134), (142, 142), (145, 145), (165, 165),
                                  (194, 194), (209, 209), (240, 241),  # 240 added, was (241,241) # WIDENED
                                  (251, 251)]),
    ("testing-and-tdd", [(14, 14), (25, 25), (27, 27), (39, 39), (43, 43),
                          (48, 51), (67, 67), (81, 81), (85, 85), (98, 98),
                          (114, 114), (115, 115), (116, 118), (120, 120),
                          (135, 135), (136, 138), (143, 143), (169, 169),
                          (199, 199), (224, 224), (238, 239),
                          (242, 250)]),  # 250 added, was (242,249) # WIDENED
    ("workable-items-and-tracking", [(15, 16), (21, 21), (33, 34), (54, 55),
                                      (90, 93), (95, 95), (104, 104), (112, 112),
                                      (148, 149), (171, 171), (202, 202), (214, 214)]),
    ("documentation-and-export", [(12, 12), (18, 19),  # 19 added, was (18,18) # WIDENED
                                   (22, 23), (44, 45),  # 45 added, was (44,44) # WIDENED
                                   (53, 53), (56, 57), (59, 61),  # 61 added, was (59,60) # WIDENED
                                   (63, 63), (65, 65), (73, 73), (86, 86), (99, 99),
                                   (106, 106), (153, 153), (168, 168), (212, 212),
                                   (215, 215), (257, 259)]),
    ("git-and-data-safety", [(10, 10), (30, 30), (36, 37), (41, 41), (71, 71),
                              (84, 84), (88, 88), (113, 113), (121, 121),
                              (176, 182), (188, 188), (191, 191), (195, 195),
                              (206, 206), (234, 234), (252, 253)]),
    ("host-and-resource-safety", [(24, 24), (58, 58), (96, 96), (111, 111),
                                   (119, 119), (128, 128), (144, 144), (147, 147),
                                   (154, 155), (174, 174),  # 174 added — T006/T007 283-corpus widening (see report)
                                   (225, 225), (254, 254), (263, 263)]),
    ("multi-track-and-parallelism", [(103, 103), (167, 167), (176, 192), (230, 233)]),
    ("translation-and-localization", [(237, 237), (255, 256)]),
    ("design-system-and-ui", [(162, 162), (170, 170), (190, 190), (216, 223)]),
    ("governance-and-constitution-meta", [(11, 11), (17, 17), (26, 26), (28, 29),
                                           (31, 31), (32, 32), (35, 35), (74, 74),
                                           (75, 75), (76, 80), (100, 100),  # 100 added — T006/T007 283-corpus widening (see report)
                                           (109, 109), (140, 141),
                                           (156, 157),  # 156 added, was (157,157) # WIDENED
                                           (161, 161), (164, 164), (166, 166),
                                           (173, 173),  # 173 added — T006/T007 283-corpus widening (see report)
                                           (184, 184), (196, 198), (227, 227),
                                           (228, 228), (272, 275)]),
    ("project-lifecycle-and-release", [(8, 9), (20, 20), (40, 40), (42, 42),
                                        (46, 47), (52, 52), (66, 66), (70, 70),
                                        (72, 72), (82, 82), (87, 87), (89, 89),
                                        (94, 94), (97, 97), (101, 102), (122, 122),
                                        (126, 127),  # 127 added, was (126,126) # WIDENED
                                        (129, 133), (150, 152), (172, 172),  # 172 added — T006/T007 283-corpus widening (see report)
                                        (185, 185), (200, 200),
                                        (207, 207), (208, 208), (210, 211), (213, 213),
                                        (229, 229), (235, 236), (260, 261), (264, 267)]),
]

EXPLICIT_ID_GROUPS = {
    "9": "git-and-data-safety",
    "9.2": "git-and-data-safety",
    "12": "host-and-resource-safety",
    "12.6": "host-and-resource-safety",
    "12.7": "host-and-resource-safety",
    "12.8": "host-and-resource-safety",
    "12.9": "host-and-resource-safety",
    "12.10": "host-and-resource-safety",
    "12.11": "host-and-resource-safety",
    "12.12": "host-and-resource-safety",
    # --- added — T006/T007 283-corpus widening (see report for rationale) ---
    # Ids outside the "11.4" family entirely, and the "11.4.184(I)" sub-anchor
    # whose parenthesized tail does not convert cleanly to int — none of
    # these can be reached by the range mechanism above, per assign_group's
    # own gating condition (len(parts) >= 3 and parts[0] == "11" and
    # parts[1] == "4"), so EXPLICIT_ID_GROUPS is the only correct mechanism.
    "7.1": "anti-bluff-and-evidence",
    "9.1": "git-and-data-safety",
    "9.3": "git-and-data-safety",
    "9.4": "git-and-data-safety",
    "11.4": "anti-bluff-and-evidence",
    "12.1": "host-and-resource-safety",
    "12.2": "host-and-resource-safety",
    "12.3": "host-and-resource-safety",
    "11.4.184(I)": "governance-and-constitution-meta",
}


class UnclassifiedAnchorError(ValueError):
    """Raised when an anchor id matches no range and no explicit mapping —
    per contracts/generator-cli.md, this is a FATAL generation error, never
    a silently-dropped anchor (FR-005 zero-content-loss)."""


def assign_group(anchor_id: str) -> str:
    if anchor_id in EXPLICIT_ID_GROUPS:
        return EXPLICIT_ID_GROUPS[anchor_id]
    parts = anchor_id.split(".")
    if len(parts) >= 3 and parts[0] == "11" and parts[1] == "4":
        try:
            tail = int(parts[2])
        except ValueError:
            raise UnclassifiedAnchorError(anchor_id)
        for group_name, ranges in ID_RANGE_GROUPS:
            for lo, hi in ranges:
                if lo <= tail <= hi:
                    return group_name
    raise UnclassifiedAnchorError(anchor_id)
