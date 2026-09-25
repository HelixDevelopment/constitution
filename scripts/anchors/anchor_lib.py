"""Shared anchor extraction + group-classification library.
Consumed by constitution_generate.py, constitution_link_check.py and
constitution_wiring_audit.py — the SINGLE parser for this feature
(research.md R2.4: extends, never duplicates, the existing
constitution/scripts/mechanical/anchor_census.sh opener forms).
"""
import re

# The `(?:\.[A-Z])?` suffix on every id pattern below recognizes a real
# sub-anchor form (regression fix, real-corpus crash at Constitution.md:753,
# heading "### §11.4.10.A — Pre-store credential leak audit") — a trailing
# single-uppercase-letter suffix on the normal 3-component dotted id,
# distinct from and never truncated down to its parent id (§11.4.10 and
# §11.4.10.A are two separate, real anchors).
_ATTEMPTED_OPENER_RE = re.compile(r'^(?:### §|\*\*§|- §)(\d+\.\d+\.\d+(?:\.[A-Z])?)')
# Bold-form-only additional gate (regression fix, real-corpus crash at
# Constitution.md:7949): a bold-form ("**§") match from _ATTEMPTED_OPENER_RE
# above only counts as a genuine attempt to open a heading if the WHOLE
# line is the bolded title (ends in ** at end-of-line, optionally trailing
# whitespace) — the same end-of-line shape _STRICT_OPENER_RE already
# requires for this form. A line that starts "**§<id> ..." but keeps going
# as ordinary (unbolded) prose after the closing ** — e.g. a bolded inline
# citation to another anchor embedded in body text — was never attempting
# to be a bold-form opener at all and must not be routed into the
# strict-parse-or-raise path below.
_BOLD_WHOLE_LINE_RE = re.compile(r'^\*\*§\d+\.\d+\.\d+(?:\.[A-Z])?.*\*\*\s*$')
_STRICT_OPENER_RE = re.compile(
    r'^(?:'
    r'### §(?P<id1>\d+\.\d+\.\d+(?:\.[A-Z])?) (?P<title1>.+)|'
    r'\*\*§(?P<id2>\d+\.\d+\.\d+(?:\.[A-Z])?) (?P<title2>.+?)\*\*|'
    r'- §(?P<id3>\d+\.\d+\.\d+(?:\.[A-Z])?) (?P<title3>.+)'
    r')$'
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
    # is always canonical regardless of document order.
    canonical_ids: set[str] = set()
    for line in lines:
        m = _STRICT_OPENER_RE.match(line)
        if m and m.group("id1") is not None:
            canonical_ids.add(m.group("id1"))

    def _close(end_line: int) -> None:
        current["end_line"] = end_line
        current["body"] = "\n".join(lines[current["start_line"] - 1:end_line])
        anchors.append(current)

    for lineno, line in enumerate(lines, start=1):
        if _ATTEMPTED_OPENER_RE.match(line):
            if line.startswith('**§') and not _BOLD_WHOLE_LINE_RE.match(line):
                continue  # bold-form loose match, but not a whole-line bold title —
                          # ordinary body prose (a bolded inline citation), not an
                          # attempted opener; never routes into MalformedHeadingError.
            m = _STRICT_OPENER_RE.match(line)
            if not m:
                raise MalformedHeadingError(
                    f"line {lineno}: looks like an anchor opener but does not "
                    f"strictly parse: {line!r}"
                )
            anchor_id = m.group("id1") or m.group("id2") or m.group("id3")
            if m.group("id1") is None and anchor_id in canonical_ids:
                # A `**§`/`- §` self-citation to an id that is ALSO defined
                # via `### §` elsewhere in the document is ordinary body
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
    if current is not None:
        _close(len(lines))
    return anchors
