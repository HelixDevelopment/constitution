"""Shared anchor extraction + group-classification library.
Consumed by constitution_generate.py, constitution_link_check.py and
constitution_wiring_audit.py — the SINGLE parser for this feature
(research.md R2.4: extends, never duplicates, the existing
constitution/scripts/mechanical/anchor_census.sh opener forms).
"""
import re

_ATTEMPTED_OPENER_RE = re.compile(r'^(?:### §|\*\*§|- §)(\d+\.\d+\.\d+(?:\.[A-Z])?)')
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
            title = (m.group("title1") or m.group("title2") or m.group("title3")).strip()
            if current is not None:
                _close(lineno - 1)
            current = {"id": anchor_id, "title": title, "start_line": lineno}
    if current is not None:
        _close(len(lines))
    return anchors
