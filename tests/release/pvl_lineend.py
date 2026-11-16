#!/usr/bin/env python3
"""tests/release/pvl_lineend.py -- enumeration of the line-ending and start-of-line class for the verification-line
checker (CON-423 r6, extended in r7, section 11.4.276(C), section 11.4.201(7)). It is exhaustive for the 30 members
below only, at the places listed; it does not cover container or paragraph state (that class is enumerated by
tests/release/pvl_blockstate.py, round 7, after review r6 M-5 found the r6 wording overstated).

Usage: python3 -I tests/release/pvl_lineend.py CHECKER WORKDIR [--no-pandoc]

The class: a character or character pair that one reader treats as a line ending and another does not. CommonMark
section 2.1 defines a line ending as LF, CR LF, or a CR not followed by LF; every other character (NEL U+0085, VT, FF,
U+2028, U+2029, U+001C..U+001F, NUL, BOM, DEL) is a character of a line. The members enumerated here:
  SEPS     LF, CR, CR LF, LF CR, CR CR, CR CR LF, NEL, VT, FF, LS U+2028, PS U+2029, NUL, BOM U+FEFF, FS, GS, RS,
           US, DEL (18), and the start-of-line class this enumeration found in round 6 (a character a reader skips
           or shows as blank before the label): one, three and four spaces, TAB, NBSP, ZWSP, ZWJ, WJ, soft hyphen,
           ideographic space, LRM, RLO (12); 30 members
  bodies   the 65 bodies of tests/release/pvl_linemodel.py plus the 24 shapes below
  places   for every LF of a body: the LF replaced by the member, the member inserted before it, inserted after it;
           every LF replaced; the member at the start and at the end of the body
Every verification line in the bodies is the fixture's grammar sentence (tests/release/pvl_fixture.py line(),
resolved against a fixture root under WORKDIR), so the checker's real verdict check_body(body, ctx) is computed, never
inferred. For each variant the checker's lines (CommonMark reading) are compared with markdown-it-py
(tests/release/pvl_refreader.py; it splits on CR LF, CR and LF like CommonMark), the primary reference for this class:
  AGREE      the checker's lines equal markdown-it's
  REFUSED    the checker refuses the body (check_body returns a reason) while markdown-it shows other lines: a false
             refusal, the safe direction
  DANGER     the checker ACCEPTS the body (check_body returns None) and markdown-it shows anything but that one line
A DANGER case is a FAIL. pandoc is run on the 24 shapes only, as a second reader (a shape where pandoc, markdown-it
and the checker do not all count the same is listed; the checker must refuse it, else it is a FAIL too), and is BLIND to a lone CR: the needle
`x<CR>```<LF><LF>G<LF>```` must count 0 in markdown-it and 1 in pandoc (pandoc drops the CR); bodies with a lone CR are
never judged by pandoc.
Control needles (section 11.4.201(7)(b)): markdown-it must count NEEDLE_VISIBLE 1 and NEEDLE_HIDDEN 0, and it must see
the lone-CR member (the needle above counts 0); a reader that fails a needle makes the run BLIND (exit 2).
Output: per DANGER `LE-DANGER <body> <place> <member>: checker <lines> mdit <lines>`, per refusal class a count, then
`LINEEND variants=N agree=A refused=R danger=D members=30 mdit=<version> pandoc=<checked|SKIP> pandoc_cr_blind=<yes|no|SKIP>
pandoc_danger=<N|SKIP>`.
Exit 0 when D and pandoc_danger are 0 and every needle holds, 1 otherwise, 2 BLIND (markdown-it absent or a needle fails).
Section 11.4.289(C)(2): gate-logic.
"""
import importlib.util
import os
import shutil
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import pvl_fixture as F  # noqa: E402
import pvl_linemodel  # noqa: E402
import pvl_refreader as R  # noqa: E402

SEPS = [("LF", "\n"), ("CR", "\r"), ("CRLF", "\r\n"), ("LFCR", "\n\r"), ("CRCR", "\r\r"), ("CRCRLF", "\r\r\n"),
        ("NEL", "\x85"), ("VT", "\x0b"), ("FF", "\x0c"), ("LS", "\u2028"), ("PS", "\u2029"), ("NUL", "\x00"),
        ("BOM", "\ufeff"), ("FS", "\x1c"), ("GS", "\x1d"), ("RS", "\x1e"), ("US", "\x1f"), ("DEL", "\x7f"),
        # r6: the start-of-line class found by this enumeration (a character a reader skips before the label)
        ("SP", " "), ("SP3", "   "), ("SP4", "    "), ("TAB", "\t"), ("NBSP", "\u00a0"), ("ZWSP", "\u200b"),
        ("ZWJ", "\u200d"), ("WJ", "\u2060"), ("SHY", "\u00ad"), ("IDSP", "\u3000"), ("LRM", "\u200e"),
        ("RLO", "\u202e")]
G = F.line()  # a sentence of the grammar under the fixture root (the line model's own G names a script it lacks)
B = G.replace("pass=3", "pass=TBD")
P = "**Verification:** provisional -- job: not scheduled yet"
# "@@" marks where the member goes
SHAPES = [
    ("S01 fence after the member", "x@@```\n\n" + G + "\n```\n"),
    ("S02 comment after the member", "x@@<!--\n\n" + G + "\n-->\n"),
    ("S03 visible prose, hidden grammar line", "x@@" + P + "@@```\n\n" + G + "\n```\n"),
    ("S04 member at the start", "@@" + G),
    ("S05 member between text and the line", "x@@" + G),
    ("S06 member as a blank line", "x\n@@\n" + G),
    ("S07 heading then the member", "# h@@" + G),
    ("S08 fence around the member", "```@@" + G + "@@```\n\n" + G),
    ("S09 quote then the member", "> q@@" + G),
    ("S10 list then the member", "- i@@" + G),
    ("S11 html kind 6 then the member", "<div>@@" + G + "\n\n" + G),
    ("S12 indented code then the member", "    code@@" + G),
    ("S13 two members", "x@@@@" + G),
    ("S14 the line then a fence", G + "@@```\n" + B + "\n```"),
    ("S15 tilde fence around the member", "~~~@@" + G + "@@~~~\n"),
    ("S16 comment around the member", "<!--@@" + G + "@@-->\n\n" + G),
    ("S17 setext underline after the member", G + "@@==="),
    ("S18 self-closing comment opener", "x@@<!-->@@" + G),
    # r6: the label written through a character reference (a reader decodes it; found while writing the M-6 notes)
    ("S19 decimal reference label then the line", "**&#86;erification:** provisional -- job: x@@@@" + G),
    ("S20 hex reference label then the line", "**&#x56;erification:** provisional -- job: x@@@@" + G),
    ("S21 named reference label then the line", "**&Vopf;erification:** provisional -- job: x@@@@" + G),
    # r7: the three container / paragraph-state shapes of review r6 I-1 (each RED on the r6 checker)
    ("R01 empty list item cannot interrupt a paragraph", "text@@*@@" + G),
    ("R02 list item, blank, line indented 4 is lazy text", "- foo@@@@    bar@@" + G),
    ("R03 quote paragraph then kind-7 HTML", "> text@@> <span>@@" + G),
]
CR_BLIND_NEEDLE = "x\r```\n\n" + G + "\n```\n"


def variants(body):
    """(place, function member -> body) for every place of the class in BODY."""
    out = [("start", lambda s: s + body), ("end", lambda s: body + s)]
    idx = [i for i, ch in enumerate(body) if ch == "\n"]
    for n, i in enumerate(idx):
        out.append(("lf%d-replaced" % n, lambda s, i=i: body[:i] + s + body[i + 1:]))
        out.append(("lf%d-before" % n, lambda s, i=i: body[:i] + s + body[i:]))
        out.append(("lf%d-after" % n, lambda s, i=i: body[:i + 1] + s + body[i + 1:]))
    if idx:
        out.append(("every-lf", lambda s: body.replace("\n", s)))
    return out


def main(argv):
    if len(argv) < 3:
        sys.stderr.write("usage: pvl_lineend.py CHECKER WORKDIR [--no-pandoc]\n")
        return 64
    try:
        spec = importlib.util.spec_from_file_location("pvl_le", argv[1])
        m = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(m)
    except Exception as exc:  # noqa: BLE001
        print("LINEEND-BLIND cannot load the checker: %s" % exc)
        return 2
    if R.MDIT_VERSION is None:
        print("LINEEND-BLIND markdown-it-py is not importable: the lone-CR class has no reference reader here")
        return 2
    # control needles: the reference sees a visible line, hides a fenced one, and sees the lone CR
    if R.mdit_lines(R.NEEDLE_VISIBLE) != [R.NEEDLE_LINE] or R.mdit_lines(R.NEEDLE_HIDDEN) != [] \
            or R.mdit_lines(CR_BLIND_NEEDLE) != []:
        print("LINEEND-BLIND markdown-it failed a control needle")
        return 2
    fx = F.make_root(argv[2])
    ctx = F.checker_ctx(m, fx)
    if m.check_body("## x\n\n" + G, ctx=ctx) is not None:
        print("LINEEND-BLIND the checker refuses the fixture's golden body: acceptance cannot be measured")
        return 2
    bodies = [(c[0], c[1].replace(pvl_linemodel.G, G).replace(pvl_linemodel.B, B)) for c in pvl_linemodel.CASES] + [
        (s, b) for s, b in SHAPES]
    n = agree = refused = danger = 0
    for name, body in bodies:
        if "@@" in body:
            places = [("member", lambda s, b=body: b.replace("@@", s))]
        else:
            places = variants(body)
        for place, make in places:
            for sname, sep in SEPS:
                v = make(sep)
                n += 1
                cm = m.visible_lines(v)
                ref = R.mdit_lines(v)
                if cm == ref:
                    agree += 1
                elif m.check_body(v, ctx=ctx) is None:
                    danger += 1
                    print("LE-DANGER %s %s %s: checker %r mdit %r" % (name, place, sname, [x[:40] for x in cm],
                                                                    [x[:40] for x in ref]))
                else:
                    refused += 1
    exe = None if "--no-pandoc" in argv else shutil.which("pandoc")
    pmode, blind, pdanger = "SKIP", "SKIP", 0
    if exe is not None:
        pmode = "checked"
        blind = "yes" if len(R.pandoc_lines(exe, CR_BLIND_NEEDLE)) == 1 else "no"
        diff = pdanger = 0
        for name, body in SHAPES:
            for sname, sep in SEPS:
                v = body.replace("@@", sep)
                if "\r" in v.replace("\r\n", ""):
                    continue  # pandoc drops a lone CR: blind for this member, never judged by it
                np, nm = len(R.pandoc_lines(exe, v)), len(R.mdit_lines(v))
                if np != nm or np != len(m.visible_lines(v)):
                    acc = m.check_body(v, ctx=ctx) is None
                    diff += 1
                    pdanger += acc
                    print("LE-READERS-DIFFER %s %s: pandoc %d mdit %d checker %d %s" % (
                        name, sname, np, nm, len(m.visible_lines(v)), "ACCEPTED (danger)" if acc else "refused"))
        print("LE-PANDOC shapes without a lone CR where a reader differs: %d, accepted by the checker: %d" % (
            diff, pdanger))
    print("LINEEND variants=%d agree=%d refused=%d danger=%d members=%d mdit=%s pandoc=%s pandoc_cr_blind=%s "
          "pandoc_danger=%s" % (n, agree, refused, danger, len(SEPS), R.MDIT_VERSION, pmode, blind,
                                pdanger if exe is not None else "SKIP"))
    return 1 if danger or pdanger else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
