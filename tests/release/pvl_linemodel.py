#!/usr/bin/env python3
"""tests/release/pvl_linemodel.py -- the line model of scripts/validation/check_provisional_verification_lines.py
(CON-423 r5) against a table of bodies, and against pandoc's CommonMark reader where pandoc is installed.

Usage: python3 -I tests/release/pvl_linemodel.py CHECKER [--no-pandoc]
Each body has the number of verification lines that count in the CommonMark 0.31 reading and in the older reading
(the table's expectation; they differ only for an HTML block opener that closes itself in 0.31, and such a body must
be refused by check_body). Round 7: the checker's visible_lines(body) must give the CommonMark number, and a body
whose older reading differs must be refused by check_body (it holds raw HTML). With pandoc 3 (or later) on PATH, each body is also rendered to its JSON AST (pandoc -f commonmark -t json),
and the number of top-level Para, Plain or level-1/2 Header blocks whose first inline is Strong [Str "Verification:"]
is compared with the older reading's number (pandoc reads the older way; the prefix itself, at column 0, is the body's
line start). Bodies marked pandoc=False hold a case where the checker is deliberately stricter than CommonMark.
Round 6: markdown-it-py (commonmark preset, tests/release/pvl_refreader.py) is a second reader; it splits lines on
CR LF, a lone CR and LF exactly like CommonMark, while pandoc drops a lone CR, so a case marked "cr-blind" is judged by
markdown-it only (pandoc is blind there, section 11.4.201(7)(c)).
Output: LM-PASS / LM-FAIL per case, PANDOC-PASS / PANDOC-FAIL / PANDOC-BLIND per case or `PANDOC: SKIP <reason>`,
MDIT-PASS / MDIT-FAIL per case or `MDIT: SKIP <reason>`, then
`LINEMODEL cases=N mismatches=M pandoc=<checked|SKIP> pandoc_mismatches=K mdit=<checked|SKIP> mdit_mismatches=J`.
Exit 0 when M, K and J are 0, else 1; 2 when the checker cannot be loaded.
"""
import importlib.util
import json
import re
import shutil
import subprocess
import sys

G = "**Verification:** provisional -- job: bash t.sh -- checks: t.sh pass=1 -- layer: host-only -- target: host -- artifact: main -- due: 2026-11-20"
B = G.replace("pass=1", "pass=TBD")
P = "**Verification:** provisional -- job: not scheduled yet"

# (id, body, expected count, compare with pandoc[, expected count of the older reading when it differs])
CASES = [
    ("M01 plain line", G, 1, True),
    ("M01 heading then the line", "## x\n" + G, 1, True),
    ("M01 CRLF", "## x\r\n\r\n" + G + "\r\n", 1, True),
    ("M01 U+001C stays inside a quoted line (review r4 L1)", "## x\n> quote\x1c" + G, 0, True),
    ("M01 U+2028 stays inside a quoted line (review r4 L2)", "## x\n> quote " + G, 0, True),
    ("M01 U+0085 stays inside a quoted line", "## x\n> quote\u0085" + G, 0, True),
    ("M01 two lines", G + "\n\n" + B, 2, True),
    ("M02 backtick fence hides", "```\n" + B + "\n```\n\n" + G, 1, True),
    ("M02 tilde fence hides", "~~~\n" + B + "\n~~~\n\n" + G, 1, True),
    ("M02 backtick info string with a backtick is not a fence (review r4 L4; the next ``` opens a real fence)",
     "```a`b\n" + B + "\n```\n" + G + "\n", 0, True),
    ("M02 tilde fence may hold a backtick in its info string", "~~~a`b\n" + B + "\n~~~\n\n" + G, 1, True),
    ("M02 a shorter close does not close", "````\n" + B + "\n```\n" + G + "\n````\n", 0, True),
    ("M02 the other character does not close", "```\n" + B + "\n~~~\n" + G + "\n```\n", 0, True),
    ("M02 a close with text after it does not close", "```\n" + B + "\n``` x\n" + G + "\n```\n", 0, True),
    ("M02 four-space indented fence is not a fence", "    ```\n\n" + G + "\n\n    ```", 1, True),
    ("M02 unclosed fence runs to the end", "```\n" + G, 0, True),
    ("M02 three-space fence", "   ```\n" + B + "\n   ```\n\n" + G, 1, True),
    ("M03 comment block hides", "<!--\n" + B + "\n-->\n\n" + G, 1, True),
    ("M03 <!--> ends at once in 0.31, not in the older reading (review r4 L3)", "<!-->\n" + B + "\n-->\n\n" + G, 2, True, 1),
    ("M03 <!---> ends at once in 0.31, not in the older reading", "<!--->\n\n" + G, 1, True, 0),
    ("M03 <?> ends at once in 0.31, not in the older reading", "<?>\n\n" + G, 1, True, 0),
    ("M03 comment that ends on its start line", "<!-- x -->\n" + G, 1, True),
    ("M03 script block", "<script>\n" + B + "\n</script>\n\n" + G, 1, True),
    ("M03 processing instruction", "<?php\n" + B + "\n?>\n\n" + G, 1, True),
    ("M03 declaration", "<!DOCTYPE x\n" + B + "\n>\n\n" + G, 1, True),
    ("M03 CDATA", "<![CDATA[\n" + B + "\n]]>\n\n" + G, 1, True),
    ("M03 div block ends at a blank line", "<div>\n" + B + "\n\n" + G, 1, True),
    ("M03 kind 7 tag alone", "<custom-tag>\n" + B + "\n\n" + G, 1, True),
    ("M03 kind 7 cannot interrupt a paragraph", "text\n<custom-tag>\n" + B + "\n\n" + G, 1, True),
    ("M04 lazy quote continuation", "> quote\n" + G, 0, True),
    ("M04 lazy list continuation", "- item\n" + G, 0, True),
    ("M04 ordered list lazy continuation", "1. item\n" + G, 0, True),
    ("M04 after a blank line the quote ends", "> quote\n\n" + G, 1, True),
    ("M04 a heading in a quote ends its paragraph", "> # h\n" + G, 1, True),
    ("M04 an ATX heading after a quote paragraph is not lazy (r5 own mutant O25)", "> quote\n# h\n" + G, 1, True),
    ("M04 a thematic break after a list paragraph is not lazy", "- item\n***\n" + G, 1, True),
    ("M03 kind 7 cannot interrupt a paragraph, a fence can (r5 own mutant O26)",
     "text\n<x-y>\n```\n\n" + G + "\n```\n", 0, True),
    ("M04 fence inside a quote", "> ```\n> " + B + "\n> ```\n\n" + G, 1, True),
    ("M05 indented line does not count", "   " + G, 0, False),
    ("M05 tab-indented line does not count", "\t" + G, 0, True),
    ("M06 continuation of a paragraph does not count", "text\n" + G, 0, True),
    ("M06 code span reaching into the line", "x `a\n" + G + " `", 0, True),
    ("M06 inline comment reaching into the line", "x <!--\n" + G + "\n-->", 0, True),
    ("M06 after a thematic break", "---\n" + G, 1, True),
    ("M06 after an indented code block", "    code\n" + G, 1, True),
    ("M06 a setext heading of the line: stricter since round 7 (only a top-level paragraph counts; refused)",
     G + "\n===", 0, False),
    ("M06 prefix glued to text (visible, but not the prefix)", G.replace("provisional ", "provisionalx "), 0, False),
    # r6: a lone CR is a line ending (CommonMark 2.1); pandoc drops a lone CR, so markdown-it is the reference here
    ("M07 lone CR ends a line: a fence opened after it hides the line (review r5 I-1)", "x\r```\n\n" + G + "\n```\n", 0,
     "cr-blind"),
    ("M07 lone CR ends a line: a comment opened after it hides the line (review r5 I-1)",
     "x\r<!--\n\n" + G + "\n-->\n", 0, "cr-blind"),
    ("M07 lone CR: a prose line continues the paragraph, the grammar line is fenced (review r5 I-1)",
     "x\r" + P + "\r```\n\n" + G + "\n```\n", 0, "cr-blind"),
    ("M07 lone CR after a heading: the line starts a paragraph", "## h\r" + G, 1, "cr-blind"),
    ("M07 CR CR is a blank line", "x\r\r" + G, 1, "cr-blind"),
    ("M07 CR LF then CR: two line endings, a blank line", "x\r\n\r" + G, 1, "cr-blind"),
    ("M07 a body with CR line endings only", "## x\r\r" + G + "\r", 1, "cr-blind"),
    ("M07 lone CR line endings open and close a fence", "```\r" + B + "\r```\r\r" + G, 1, "cr-blind"),
    ("M07 lone CR inside a paragraph: the line continues it", "x\r" + G, 0, "cr-blind"),
    ("M08 an inner fence of a quote does not close on a shorter run (review r5 RV07)",
     "> ````\n> ```\n> text\n" + G, 1, True),
    ("M09 a thematic break of spaced stars is not a list item (review r5 M-6)", "* * *\n" + G, 1, True),
    ("M09 a thematic break of spaced dashes is not a list item (review r5 M-6)", "- - -\n" + G, 1, True),
    ("M09 a setext === underline ends a top-level paragraph (review r5 M-6)", "Title\n===\n" + G, 1, True),
    ("M09 a setext === after a quote is lazy text, not an underline", "> q\n===\n" + G, 0, True),
    ("M10 a tab-indented line is indented code, so === after it is no underline (r6 enumeration)",
     "\tTitle\n===\n" + G, 0, True),
    ("M10 a space then a tab is four columns: indented code", "  \tTitle\n===\n" + G, 0, True),
    ("M09 a link reference definition before the line: counted as CommonMark counts it (round 7; was stricter)",
     "[a]: /u\n" + G, 1, True),
    ("M09 a fence in a list item after a blank: counted as CommonMark counts it (round 7; was stricter)",
     "- item\n\n  ```\n" + G + "\n", 1, True),
]


def first_strong(inlines):
    """True when a block's inlines start with Strong [Str "Verification:"]."""
    if not inlines or inlines[0].get("t") != "Strong":
        return False
    c = inlines[0].get("c") or []
    return len(c) == 1 and c[0].get("t") == "Str" and c[0].get("c") == "Verification:"


def pandoc_count(exe, body):
    """Top-level Para or Plain blocks, and level 1 or 2 Header blocks, whose first inline is the bold prefix."""
    p = subprocess.run([exe, "-f", "commonmark", "-t", "json"], input=body, capture_output=True, text=True,
                       timeout=60)
    if p.returncode != 0:
        raise RuntimeError(p.stderr[:200])
    n = 0
    for blk in json.loads(p.stdout)["blocks"]:
        t, c = blk.get("t"), blk.get("c")
        if t in ("Para", "Plain") and first_strong(c):
            n += 1
        elif t == "Header" and c[0] in (1, 2) and first_strong(c[2]):
            n += 1
    return n


def main(argv):
    if len(argv) < 2:
        sys.stderr.write("usage: pvl_linemodel.py CHECKER [--no-pandoc]\n")
        return 2
    try:
        spec = importlib.util.spec_from_file_location("pvl", argv[1])
        m = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(m)
    except Exception as exc:  # noqa: BLE001
        print("LINEMODEL-BLIND cannot load the checker: %s" % exc)
        return 2
    mism = 0
    for case in CASES:
        cid, body, want = case[:3]
        old = case[4] if len(case) > 4 else want
        # round 7: the checker reads CommonMark with markdown-it-py; a body the older reading counts differently must be
        # refused (it holds raw HTML that is not a complete comment, e.g. `<!-->`)
        got = len(m.visible_lines(body))
        refused = m.check_body(body) or ""
        amb_ok = (old == want) or refused.startswith("the body holds raw HTML")
        if got == want and amb_ok:
            print("LM-PASS %s" % cid)
        else:
            mism += 1
            print("LM-FAIL %s: counted %d, want %d (older reading %d); check_body: %s" % (
                cid, got, want, old, refused[:80]))
    exe = None if "--no-pandoc" in argv else shutil.which("pandoc")
    pmode, pm = "SKIP", 0
    if exe is None:
        print("PANDOC: SKIP %s" % ("--no-pandoc" if "--no-pandoc" in argv else "pandoc not on PATH"))
    else:
        ver = subprocess.run([exe, "--version"], capture_output=True, text=True).stdout.split("\n")[0]
        mv = re.match(r"pandoc(?:\.exe)? ([0-9]+)", ver)
        if not mv or int(mv.group(1)) < 3:
            print("PANDOC: SKIP not pandoc 3 or later (%s)" % ver)
        else:
            pmode = "checked"
            print("PANDOC: %s" % ver)
            for case in CASES:
                cid, body, cmp = case[0], case[1], case[3]
                want = case[4] if len(case) > 4 else case[2]
                if cmp is False:
                    print("PANDOC-STRICTER %s (the checker is stricter than CommonMark here, by design)" % cid)
                    continue
                if cmp == "cr-blind":
                    print("PANDOC-BLIND %s (pandoc drops a lone CR; markdown-it is the reference)" % cid)
                    continue
                got = pandoc_count(exe, body)
                if got == want:
                    print("PANDOC-PASS %s" % cid)
                else:
                    pm += 1
                    print("PANDOC-FAIL %s: pandoc %d, table %d" % (cid, got, want))
    # markdown-it-py (CommonMark preset): a second reader that splits on CR LF, CR and LF (tests/release/pvl_refreader.py)
    import os
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import pvl_refreader as R
    mmode, mm = "SKIP", 0
    if R.MDIT_VERSION is None:
        print("MDIT: SKIP markdown-it-py not importable")
    elif R.mdit_lines(R.NEEDLE_VISIBLE) != [R.NEEDLE_LINE] or R.mdit_lines(R.NEEDLE_HIDDEN) != []:
        print("MDIT-BLIND markdown-it failed its control needle")
        mm = 1
    else:
        mmode = "checked"
        print("MDIT: markdown-it-py %s commonmark" % R.MDIT_VERSION)
        for case in CASES:
            cid, body, cmp, want = case[0], case[1], case[3], case[2]
            if cmp is False:
                print("MDIT-STRICTER %s (the checker is stricter than CommonMark here, by design)" % cid)
                continue
            got = len(R.mdit_lines(body))
            if got == want:
                print("MDIT-PASS %s" % cid)
            else:
                mm += 1
                print("MDIT-FAIL %s: markdown-it %d, table %d" % (cid, got, want))
    print("LINEMODEL cases=%d mismatches=%d pandoc=%s pandoc_mismatches=%d mdit=%s mdit_mismatches=%d" % (
        len(CASES), mism, pmode, pm, mmode, mm))
    return 0 if mism == 0 and pm == 0 and mm == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
