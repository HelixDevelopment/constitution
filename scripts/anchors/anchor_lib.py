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
_ATTEMPTED_OPENER_RE = re.compile(r'^(?:### §|\*\*§|- §)(\d+\.\d+\.\d+(?:\.[A-Z]|\([A-Z]+\))?)')
_STRICT_OPENER_RE = re.compile(
    r'^(?:'
    r'### §(?P<id1>\d+\.\d+\.\d+(?:\.[A-Z]|\([A-Z]+\))?) (?P<title1>.+)$|'
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
