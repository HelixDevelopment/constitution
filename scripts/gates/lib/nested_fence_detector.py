#!/usr/bin/env python3
"""nested_fence_detector.py — merged, promoted CommonMark nested-fence audit.

── Provenance (§11.4.124 investigate-before-remove / promote, not reinvent) ──
This is the PROMOTED, MERGED form of two independently-authored HXC-159
T-P9.01 review instruments:

  * round-1  docs/qa/hxc159_t_p9_01_review_20260923/captures/fence_audit.py
  * round-3  docs/qa/hxc159_t_p9_01_review3_20260923/captures/fence_scan2.py

Both were control-needle-validated (golden-bad -> exit 1, golden-good ->
exit 0, per §11.4.273) and, run independently over the SAME 18-file corpus,
AGREED on 0 findings (docs/qa/hxc159_t_p9_01_review3_20260923/captures/
15_fence_two_instruments.txt). Round-1's signatures (S1/S2/S3) and doc
comments form the base of this module; round-3's mermaid open/close balance
cross-check (its N4) is folded in as signature S4 — the one genuine
capability difference between the two instruments. No detection logic in
either source instrument was found to be wrong; this promotion is a
reuse-and-formalize per specs/001-helixskills-incorporation/tasks.md F-19,
not a rewrite.

── The defect class (verified against this script's own state machine) ──────
In CommonMark, a fenced code block's CLOSING fence is any line whose fence
character matches the block's OPENING fence character, whose run-length is
>= the opening run-length, and which has EMPTY content after the closing
fence run (trimmed). If a document nests a SECOND fenced block (e.g. an
inner ```mermaid block) inside an outer fence of the SAME character with a
run-length <= the inner fence's run-length, the outer block's own eventual
closing fence — appearing later in the file, matching the OUTER run-length —
prematurely terminates whichever block is open when it is reached, and every
line between the inner opener and that closer renders as literal body text:
a raw diagram directive (mermaid/gantt/etc.) leaking into an exported
PDF/HTML as prose (§11.4.168 exported-document validation). A later,
now-unconsumed bare fence line then re-opens a stray, unintended block. This
is the exact defect class "finally fixed" four separate times across Phase
B3, T-P8.01, T-P8.04, and the F-10 regeneration pass, with no permanent
§11.4.135 regression guard until this promotion.

── Reported signatures ───────────────────────────────────────────────────────
  S1  NESTED-OPENER-PREMATURE-CLOSE
      A fence-shaped line (matching char + run-length >= the currently-OPEN
      block's) occurs INSIDE that open block WITH non-empty trailing content
      after the fence run (i.e. it carries its own info string, such as an
      inner "```mermaid" opener). CommonMark treats this line as literal
      content of the outer block, but the INNER block's own intended bare
      closer will later match-and-close the OUTER block prematurely. This is
      the recurring defect class.
  S2  LEAKED-DIAGRAM-DIRECTIVE
      A line OUTSIDE any currently-open fence starts with a recognised
      Mermaid/diagram directive keyword (graph|flowchart|sequenceDiagram|
      stateDiagram|classDiagram|erDiagram|gantt|xychart-beta|mindmap|
      timeline|pie|gitGraph) — raw diagram source rendered as document prose,
      the artifact-layer symptom S1 produces (or of content that was never
      fenced at all).
  S3  UNCLOSED-AT-EOF
      The file ends with a fence block still open (no matching closer seen).
  S4  MERMAID-FENCE-IMBALANCE
      The count of ```mermaid / ~~~mermaid fence OPENERS does not equal the
      count of mermaid blocks that CLOSED on a genuine bare fence. An
      independent sanity cross-check (round-3's N4): it can catch a leak S1
      misses when the inner and outer fence CHARACTERS differ (S1 only fires
      when the nested opener's char+length would itself be accepted as the
      outer closer).

Exit 0 = zero findings across every file given on argv. Exit 1 = one or more
findings (printed one per line to stdout, followed by a JSON summary object).
Usage: nested_fence_detector.py <file1.md> [file2.md ...]
"""
import json
import re
import sys

FENCE_RE = re.compile(r'^( {0,3})(`{3,}|~{3,})(.*)$')
DIRECTIVE_RE = re.compile(
    r'^\s*('
    r'graph\s+(TD|TB|LR|RL|BT)\b|'
    r'flowchart\s+(TD|TB|LR|RL|BT)\b|'
    r'sequenceDiagram\b|'
    r'stateDiagram(-v2)?\b|'
    r'classDiagram\b|'
    r'erDiagram\b|'
    r'gantt\b|'
    r'xychart-beta\b|'
    r'mindmap\b|'
    r'timeline\b|'
    r'pie\b|'
    r'gitGraph\b'
    r')'
)


def audit_file(path):
    """Return a list of finding dicts for a single file, per the S1-S4
    signatures documented above. Never raises on a missing/unreadable file
    at this layer — the caller (main) is responsible for surfacing that
    honestly rather than silently skipping it."""
    findings = []
    open_fence = None  # (char, length, info, line_no) or None
    mermaid_opens = 0
    mermaid_closes = 0
    with open(path, encoding='utf-8', errors='replace') as fh:
        lines = fh.read().split('\n')
    for i, line in enumerate(lines, 1):
        m = FENCE_RE.match(line)
        if open_fence is None:
            if m:
                fence_chars, info = m.group(2), m.group(3).strip()
                # A backtick fence's info string may not itself contain a
                # backtick per CommonMark -- such a line is content, not an
                # opener (mirrors both source instruments' handling of an
                # inline code span that happens to start a line).
                if fence_chars[0] == '`' and '`' in info:
                    pass
                else:
                    open_fence = (fence_chars[0], len(fence_chars), info, i)
                    if info.split()[:1] == ['mermaid']:
                        mermaid_opens += 1
                    continue
            if DIRECTIVE_RE.match(line):
                findings.append({'sig': 'S2', 'line': i,
                                  'text': line.strip()[:80]})
        else:
            ch, ln, info, start = open_fence
            if m and m.group(2)[0] == ch and len(m.group(2)) >= ln:
                if m.group(3).strip() == '':
                    if info.split()[:1] == ['mermaid']:
                        mermaid_closes += 1
                    open_fence = None
                    continue
                findings.append({
                    'sig': 'S1', 'line': i, 'outer_open': start,
                    'outer_fence': ch * ln, 'outer_info': info,
                    'text': line.strip()[:80],
                })
    if open_fence is not None:
        findings.append({'sig': 'S3', 'line': open_fence[3],
                          'text': 'fence still open at EOF'})
    if mermaid_opens != mermaid_closes:
        findings.append({
            'sig': 'S4', 'line': 0,
            'text': 'mermaid fence openers=%d closed=%d'
                    % (mermaid_opens, mermaid_closes),
        })
    return findings


def main(argv):
    total = 0
    report = {}
    for path in argv:
        findings = audit_file(path)
        report[path] = findings
        total += len(findings)
        for f in findings:
            print("%s:%s: %s %s" % (path, f['line'], f['sig'], f))
    print(json.dumps({
        'files': len(report),
        'total_findings': total,
        'per_file': {k: len(v) for k, v in report.items()},
    }, indent=1))
    return 1 if total else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
