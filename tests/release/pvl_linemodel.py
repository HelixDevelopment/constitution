#!/usr/bin/env python3
"""tests/release/pvl_linemodel.py -- the line model of scripts/validation/check_provisional_verification_lines.py
(CON-423 r5) against a table of bodies, and against pandoc's CommonMark reader where pandoc is installed.

Usage: python3 -I tests/release/pvl_linemodel.py CHECKER [--no-pandoc]
Each body has the number of verification lines that count in the CommonMark 0.31 reading and in the older reading
(the table's expectation; they differ only for an HTML block opener that closes itself in 0.31, and such a body must
be refused by check_body). The checker's visible_lines(body) and visible_lines(body, legacy=True) must give those
numbers. With pandoc 3 (or later) on PATH, each body is also rendered to its JSON AST (pandoc -f commonmark -t json),
and the number of top-level Para, Plain or level-1/2 Header blocks whose first inline is Strong [Str "Verification:"]
is compared with the older reading's number (pandoc reads the older way; the prefix itself, at column 0, is the body's
line start). Bodies marked pandoc=False hold a case where the checker is deliberately stricter than CommonMark.
Output: LM-PASS / LM-FAIL per case, PANDOC-PASS / PANDOC-FAIL per case or `PANDOC: SKIP <reason>`, then
`LINEMODEL cases=N mismatches=M pandoc=<checked|SKIP> pandoc_mismatches=K`. Exit 0 when M and K are 0, else 1;
2 when the checker cannot be loaded.
"""
import importlib.util
import json
import re
import shutil
import subprocess
import sys

G = "**Verification:** provisional -- job: bash t.sh -- checks: t.sh pass=1 -- layer: host-only -- target: host -- artifact: main -- due: 2026-11-20"
B = G.replace("pass=1", "pass=TBD")

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
    ("M06 setext heading still counts (visible)", G + "\n===", 1, True),
    ("M06 prefix glued to text (visible, but not the prefix)", G.replace("provisional ", "provisionalx "), 0, False),
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
        got, got_old = len(m.visible_lines(body)), len(m.visible_lines(body, legacy=True))
        refused = m.check_body(body) or ""
        amb_ok = (old == want) or refused.startswith("the body reads differently")
        if got == want and got_old == old and amb_ok:
            print("LM-PASS %s" % cid)
        else:
            mism += 1
            print("LM-FAIL %s: counted %d and %d (older reading), want %d and %d; check_body: %s" % (
                cid, got, got_old, want, old, refused[:80]))
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
                if not cmp:
                    print("PANDOC-STRICTER %s (the checker is stricter than CommonMark here, by design)" % cid)
                    continue
                got = pandoc_count(exe, body)
                if got == want:
                    print("PANDOC-PASS %s" % cid)
                else:
                    pm += 1
                    print("PANDOC-FAIL %s: pandoc %d, table %d" % (cid, got, want))
    print("LINEMODEL cases=%d mismatches=%d pandoc=%s pandoc_mismatches=%d" % (len(CASES), mism, pmode, pm))
    return 0 if mism == 0 and pm == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
