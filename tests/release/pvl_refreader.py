#!/usr/bin/env python3
"""tests/release/pvl_refreader.py -- the reference readers of the verification-line checker's line model (CON-423 r6).

Two independent CommonMark readers count the verification lines a person would see in a body:
  markdown-it   markdown-it-py (the `commonmark` preset), a Python port of markdown-it. Its normaliser splits lines
                on CR LF, a lone CR and LF (rules_core/normalize.py: NEWLINES_RE = r"\\r\\n?|\\n"), exactly the line
                endings of CommonMark section 2.1, so it SEES the lone-CR class.
  pandoc        pandoc -f commonmark -t json. Pandoc drops a lone CR before parsing, so it is BLIND to the lone-CR class
                (section 11.4.201(7)(c)); tests/release/pvl_lineend.py proves that with a control needle and never uses
                pandoc as the reference for a body holding a lone CR.
A reader's count is the list of first lines of the top-level paragraphs and level-1/2 headings whose inline content
starts with the bold `Verification:` (empty text tokens skipped), the first line taken up to the first line feed.

Usage (as a module): mdit_lines(body) -> list or None (None: markdown-it-py not importable);
pandoc_lines(exe, body) -> list.  `python3 -I tests/release/pvl_refreader.py --selftest` checks both readers on a
control needle (a visible line counted 1, a fenced line counted 0) and prints
`REFREADER-SELFTEST mdit=<ok|SKIP|WRONG> pandoc=<ok|SKIP|WRONG>`; exit 0 unless a reader that is present is WRONG.
"""
import json
import shutil
import subprocess
import sys

try:
    from markdown_it import MarkdownIt
    _MD = MarkdownIt("commonmark")
    MDIT_VERSION = __import__("markdown_it").__version__
except Exception:  # noqa: BLE001 -- the reader is optional; its absence is reported as SKIP, never as agreement
    _MD = None
    MDIT_VERSION = None


def mdit_lines(body):
    """The first lines of the top-level verification paragraphs and h1/h2 headings markdown-it shows, or None."""
    if _MD is None:
        return None
    toks = _MD.parse(body)
    out = []
    for i, t in enumerate(toks):
        if t.level != 0 or t.type not in ("paragraph_open", "heading_open"):
            continue
        if t.type == "heading_open" and t.tag not in ("h1", "h2"):
            continue
        inl = toks[i + 1]
        ch = [c for c in (inl.children or []) if not (c.type == "text" and c.content == "")]
        if (len(ch) >= 3 and ch[0].type == "strong_open" and ch[1].type == "text"
                and ch[1].content == "Verification:" and ch[2].type == "strong_close"):
            out.append(inl.content.split("\n")[0])
    return out


def _strong(c):
    return bool(c) and c[0].get("t") == "Strong" and len(c[0]["c"]) == 1 and c[0]["c"][0].get("c") == "Verification:"


def pandoc_lines(exe, body):
    """The number of top-level verification Para/Plain blocks and level-1/2 headers pandoc shows (as a list of '?')."""
    p = subprocess.run([exe, "-f", "commonmark", "-t", "json"], input=body, capture_output=True, text=True,
                       timeout=60)
    if p.returncode != 0:
        raise RuntimeError(p.stderr[:200])
    n = 0
    for b in json.loads(p.stdout)["blocks"]:
        if b["t"] in ("Para", "Plain") and _strong(b["c"]):
            n += 1
        elif b["t"] == "Header" and b["c"][0] in (1, 2) and _strong(b["c"][2]):
            n += 1
    return ["?"] * n


NEEDLE_LINE = "**Verification:** provisional -- job: x"
NEEDLE_VISIBLE = "## x\n\n" + NEEDLE_LINE + "\n"
NEEDLE_HIDDEN = "```\n" + NEEDLE_LINE + "\n```\n"


def selftest():
    res = {}
    got = mdit_lines(NEEDLE_VISIBLE)
    if got is None:
        res["mdit"] = "SKIP"
    else:
        res["mdit"] = "ok" if got == [NEEDLE_LINE] and mdit_lines(NEEDLE_HIDDEN) == [] else "WRONG"
    exe = shutil.which("pandoc")
    if exe is None:
        res["pandoc"] = "SKIP"
    else:
        res["pandoc"] = "ok" if len(pandoc_lines(exe, NEEDLE_VISIBLE)) == 1 and not pandoc_lines(exe, NEEDLE_HIDDEN) \
            else "WRONG"
    print("REFREADER-SELFTEST mdit=%s pandoc=%s" % (res["mdit"], res["pandoc"]))
    return 1 if "WRONG" in res.values() else 0


if __name__ == "__main__":
    if sys.argv[1:] == ["--selftest"]:
        sys.exit(selftest())
    sys.stderr.write("usage: pvl_refreader.py --selftest\n")
    sys.exit(64)
