#!/usr/bin/env python3
"""tests/release/pvl_blockstate.py -- enumeration of the container and paragraph-state transitions a verification
line can follow (CON-423 r7, section 11.4.276(C), section 11.4.201(7)). It covers the members listed below and their
cross product only; it is not a proof over every CommonMark document (review r6 M-5: say what is enumerated). The
checker no longer models these states itself (it reads the markdown-it-py parse), so the harness checks the decision
against two readers rather than against a hand model.

Usage: python3 -I tests/release/pvl_blockstate.py CHECKER WORKDIR [--no-pandoc] [--quick]

THE CLASS (review r6 I-1, M-5): the state a CommonMark reader is in when the verification line arrives decides whether
the line starts a top-level paragraph, continues one (top level, block quote, list item, lazily), sits in code or an
HTML block, or is hidden by raw HTML. Rounds 5 and 6 enumerated line endings and start-of-line characters only; this
harness enumerates the STATE before the line:
  CONTEXTS  the block that precedes the line (top-level paragraph, ATX and setext headings, thematic breaks, block
            quotes and nested quotes, every list marker, empty list items after a paragraph, list items with a blank and
            an indented paragraph (spaces and tabs), nested lists, quotes in lists and lists in quotes, indented code,
            open and closed fences of both characters, HTML blocks of kinds 1 to 7 open and closed, hiding elements
            (`hidden`, `display:none`, `<details>`), link reference definitions and their titles, inline constructs left
            open (code span, comment, tag, emphasis, link, backslash), GFM tables, front matter, extension syntax
            (fenced div, attribute list), hard breaks; round 8, review r7 F1-F6: HTML5 comment ends `--!>`, `<!-->`,
            `<!--->`, a second label hidden by variation selectors, a combining grapheme joiner, a Hangul filler, a
            character reference, a Cyrillic look-alike, a ratio colon, a Cherokee letter, a combining mark or a code
            span, a GFM footnote definition, raw HTML in image text, a setext heading GFM reads as a table header, a
            U+3000 line)
  JOINS     how the line is attached (one, two, three line feeds; a quote marker; an empty quote line; 2, 3, 4 spaces; a
            tab; a list marker; a blank and then 2 or 4 spaces or a tab)
  SUFFIXES  what follows the line (nothing, a line feed, a fence, `-->`, `</div>`, setext underlines, text, a blank and
            `</div>`; round 8: a continuation that adds a field, a second label with a variation selector, an HTML5
            comment end that opens a hiding element, a GFM table delimiter row)
  ENDINGS   LF, a lone CR, CR LF (every line feed of the body replaced)
plus the r6 reviewer's shapes verbatim (review r6 probe_r6, probe_hide), the r7 reviewer's shapes (review r7
probe_bang, probe_near, probe_shapes, probe_nested_html) and the round-8 class members (text the reader shows in the
counted paragraph after the line: a continuation, a comment spanning lines, a hard break). Every verification line is the fixture's
grammar sentence (tests/release/pvl_fixture.py line()) resolved under a fixture root, so the checker's real verdict
check_body(body, ctx) is computed, never inferred.

THE ORACLE (independent of the checker's code): a body the checker ACCEPTS is rendered to HTML by every reader present
-- markdown-it-py `commonmark`, pandoc `-f commonmark`, pandoc `-f gfm` and pandoc `-f markdown-yaml_metadata_block`
(the tracker export reader; its smart extension maps -- and ... so the expected text is mapped the same way) (pandoc only for a body without a lone CR:
pandoc drops a lone CR and is blind to it, the needle below proves it) -- and the HTML is read with html.parser. A
render is CLEAN when (a) it holds only the elements Markdown itself generates, with only their generated attributes
(no raw HTML element, so nothing can hide or wrap the line), (b) exactly one top-level <p> starts with
<strong>Verification:</strong>, and its text is exactly the line's text (round 8, review r7 R7M13: "starts with"
let a continuation through), and (c) no other text of the document (text outside that paragraph, comments, attribute
values) reads as the label once it is read with the reference reading (scripts/validation/pvl_reading_table.py, live
from ICU: default-ignorable code points, marks and format characters read as nothing, NFKD, the UTS #39 skeleton, case
folding) and every character that is not a letter or a colon is removed. The checker reads with a table generated
from the same reading; the oracle calls ICU itself, so a table that misreads a character is a DANGER here. An accepted body
whose render is not clean in any reader is a DANGER (a FAIL). A refused body is the safe direction; the bodies
markdown-it renders clean but the checker refuses are counted as false refusals (informational).

Control needles (section 11.4.201(7)(b)): the oracle must call NEEDLE_CLEAN clean and each NEEDLE_DIRTY not clean in
markdown-it (and in pandoc when present), and pandoc must be blind to a lone CR (it renders `x<CR>```...` with the line
visible). Round 8 (review r7 F7: R7M13 and R7M14 weakened the oracle unnoticed): ORACLE_SELFTEST gives every check of
clean() a rendered page that only that check refuses, with the reason it must give, and the clean page must pass; a
self-test failure, or ICU missing, makes the run BLIND (exit 2).
Output: per DANGER `BS-DANGER <name> <reader>: <why>`, then `BLOCKSTATE bodies=N accepted=A refused=R danger=D
false_refusals=F contexts=C joins=J suffixes=S endings=E reviewer=K mdit=<version> pandoc=<checked|SKIP> readers=<1|4>
oracle_selftest=T icu=<version>`.
Exit 0 when D is 0 and every needle holds, 1 otherwise, 2 BLIND. --quick: LF and CR LF only, no pandoc (for mutants).
Section 11.4.289(C)(2): gate-logic.
"""
import html.parser
import importlib.util
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import pvl_fixture as F  # noqa: E402

# the reference reading (scripts/validation/pvl_reading_table.py), live from ICU: the oracle reads a label with it, the
# checker with its embedded table, so a table that misreads a character is caught here (round 8, review r7 F6)
try:
    _spec = importlib.util.spec_from_file_location(
        "pvl_reading_ref", os.path.join(HERE, "..", "..", "scripts", "validation", "pvl_reading_table.py"))
    _RT = importlib.util.module_from_spec(_spec)
    _spec.loader.exec_module(_RT)
    _ICU = _RT.ICU()
except Exception as _exc:  # noqa: BLE001 -- reported as BLIND, never as agreement
    _ICU = None
    _ICU_ERROR = str(_exc)[:120]

try:
    from markdown_it import MarkdownIt
    _MD = MarkdownIt("commonmark")
    MDIT_VERSION = __import__("markdown_it").__version__
except Exception:  # noqa: BLE001 -- reported as BLIND, never as agreement
    _MD = None
    MDIT_VERSION = None

G = F.line()
GTEXT = " ".join(G.replace("**", "").split())

CONTEXTS = [
    # top level
    ("start", ""), ("para", "text"), ("atx", "## h"), ("setext1", "h\n==="), ("setext2", "h\n---"),
    ("hr-star", "***"), ("hr-dash", "---"), ("hr-under", "___"), ("hr-spaced", "* * *"), ("hr-dspaced", "- - -"),
    ("hardbreak-sp", "x  "), ("hardbreak-bs", "x\\"), ("frontmatter", "---\ntitle: a\n---"),
    # block quotes
    ("q-para", "> text"), ("q-nested", "> > text"), ("q-empty", ">"), ("q-empty-sp", "> "), ("q-list", "> - a"),
    ("q-olist", "> 1. a"), ("q-fence-open", "> ```"), ("q-fence-closed", "> ```\n> x\n> ```"), ("q-kind7", "> <span>"),
    ("q-kind6", "> <div>"), ("q-para-kind7", "> text\n> <span>"), ("q-para-kind7-close", "> text\n> </span>"),
    ("q-para-empty-bullet", "> text\n> *"), ("q-para-empty-ordered", "> text\n> 1."), ("q-atx", "> # h"),
    ("q-setext", "> text\n> ==="), ("q-setext2", "> text\n> ---"), ("q-hide", '> x\n> <span style="display:none">'),
    ("q-list-blank-indent", "> - a\n>\n>     b"),
    # list items
    ("l-dash", "- text"), ("l-star", "* text"), ("l-plus", "+ text"), ("l-dot", "1. text"), ("l-paren", "1) text"),
    ("l-blank-indent4", "- foo\n\n    bar"), ("l-blank-indent5", "- foo\n\n     bar"), ("l-blank-tab", "- foo\n\n\tbar"),
    ("l-blank-indent4-ord", "1. foo\n\n    bar"), ("l-blank-code6", "- foo\n\n      code"), ("l-blank-indent2", "- foo\n\n  bar"),
    ("l-nested", "- a\n  - b"), ("l-nested-code", "- a\n  - b\n\n        c"), ("l-quote", "- > a"), ("l-fence", "- ```"),
    ("l-kind7", "- <span>"), ("l-para-kind7", "- text\n  <span>"), ("l-empty-dash", "-"), ("l-empty-dash-sp", "- "),
    ("l-empty-ord", "1."), ("l-atx", "- # h"), ("l-hide-lazy", "- x\n\n    <span hidden>y"),
    # empty list items after a paragraph (they cannot interrupt it)
    ("p-empty-star", "text\n*"), ("p-empty-plus", "text\n+"), ("p-empty-dash", "text\n-"), ("p-empty-dot", "text\n1."),
    ("p-empty-paren", "text\n1)"), ("p-empty-dot2", "text\n2."), ("p-empty-star-sp", "text\n* "), ("p-empty-10", "text\n10."),
    # code
    ("indented-code", "    code"), ("tab-code", "\tcode"), ("fence-bt", "```"), ("fence-tl", "~~~"), ("fence-4-3", "````\n```"),
    ("fence-closed", "```\nx\n```"), ("fence-tl-closed", "~~~\nx\n~~~"), ("fence-bt-info-bt", "``` a`b"),
    ("fence-indent2", "  ```"),
    # HTML blocks, kinds 1 to 7, open and closed, and hiding elements
    ("h1-pre", "<pre>"), ("h1-pre-closed", "<pre>\n</pre>"), ("h1-script", "<script>"), ("h1-style", "<style>"),
    ("h1-textarea", "<textarea>"), ("h2-comment", "<!--"), ("h2-comment-closed", "<!-- x -->"), ("h2-selfclose", "<!-->"),
    ("h2-selfclose3", "<!--->"), ("h3-pi", "<?php"), ("h3-pi-empty", "<?>"), ("h4-decl", "<!DOCTYPE x"),
    ("h5-cdata", "<![CDATA["), ("h6-div", "<div>"), ("h6-div-hidden", "<div hidden>"),
    ("h6-div-none", '<div style="display:none">'), ("h6-details", "<details>"), ("h6-close", "</div>"),
    ("h6-search", "<search>"), ("h7-span", "<span>"), ("h7-span-hidden", "<span hidden>"), ("h7-custom", "<custom-tag>"),
    ("h7-after-para", "text\n<span>"), ("h7-attr-newline", "<a\nhref=x>"), ("x-span-hidden", "x <span hidden>"),
    ("x-span-hidden-bullet", "x <span hidden>\n*"),
    # link reference definitions
    ("lref", "[x]: /u"), ("lref-split", "[x]:\n/u"), ("lref-title-open", "[x]: /u\n'title"),
    ("lref-title", "[x]: /u 'title'"),
    # inline constructs left open
    ("i-code", "x `"), ("i-comment", "x <!--"), ("i-comment-bullet", "x <!--\n*"), ("i-tag", "x <span hidden>"),
    ("i-emph", "x *"), ("i-link", "x ["), ("i-autolink", "<http://a>"),
    # GitHub and extension syntax
    ("gfm-table", "| a |\n| - |"), ("fenced-div", "::: {.hidden}"), ("ial", "{: .hidden}"),
    # round 8 (review r7 F1, F2, F5, F6): HTML5 comment ends, a second label hidden by invisible or look-alike
    # characters, character references, a colon look-alike, a GFM footnote definition, raw HTML in image text
    ("c-bang-div", "<!-- a --!><div hidden>\n-->"), ("c-bang-inline", "x <!-- --!><span hidden> -->"),
    ("c-empty3", "<!--->"), ("c-dashdash", "<!-- a -- b -->"),
    ("lbl-vs16", "**Verif\ufe0fication:** provisional -- checks: FAKE pass=999"),
    ("lbl-cgj", "Verifi\u034fcation: x"), ("lbl-hangul", "Verifi\u3164cation: x"),
    ("lbl-ref", "Verif&#xFE0F;ication: x"), ("lbl-cyr", "V\u0435rification: x"), ("lbl-ratio", "Verification\u2236 x"),
    ("lbl-cherokee", "\u13d9erification: x"), ("lbl-mark", "Verificat\u0323ion: x"),
    ("lbl-code", "`Verif\ufe0fication:`"), ("fn-def", "[^1]: x"), ("img-alt-html", "![<span hidden>x</span>](u)"),
    ("gfm-setext-table", "| x |\n---"), ("u3000-line", "\u3000"),
]
JOINS = [("lf", "\n"), ("blank", "\n\n"), ("blank2", "\n\n\n"), ("quote", "\n> "), ("quote-empty", "\n>\n"),
         ("sp2", "\n  "), ("sp3", "\n   "), ("sp4", "\n    "), ("tab", "\n\t"), ("dash", "\n- "),
         ("blank-sp2", "\n\n  "), ("blank-sp4", "\n\n    "), ("blank-tab", "\n\n\t")]
SUFFIXES = [("none", ""), ("lf", "\n"), ("fence", "\n```"), ("comment-end", "\n-->"), ("div-end", "\n</div>"),
            ("setext1", "\n==="), ("setext2", "\n---"), ("text", "\ntext"), ("blank-div-end", "\n\n</div>"),
            # round 8: a continuation that adds a field the reader sees, a second label hidden by a variation selector,
            # an HTML5 comment end that opens a hiding element, a GFM table delimiter row
            ("cont-fake", "\n-- checks: FAKE pass=999"), ("lbl-after", "\n\n**Verif\ufe0fication:** x"),
            ("bang-after", "\n\n<!-- --!><style>p{display:none}</style> -->"), ("table-delim", "\n|---|")]
ENDINGS = [("LF", "\n"), ("CR", "\r"), ("CRLF", "\r\n")]

# the r6 reviewer's shapes (review r6 probe_r6.txt, probe_hide.txt; @ marks the verification line)
REVIEWER = [
    ("rv6-empty_bullet_star", "text\n*\n@"), ("rv6-empty_bullet_plus", "text\n+\n@"), ("rv6-empty_ordered_1", "text\n1.\n@"),
    ("rv6-empty_ordered_paren", "text\n1)\n@"), ("rv6-list_blank_indent4", "- foo\n\n    bar\n@"),
    ("rv6-list_blank_indent4_ord", "1. foo\n\n    bar\n@"), ("rv6-list_blank_indent5", "- foo\n\n     bar\n@"),
    ("rv6-list_blank_tab", "- foo\n\n\tbar\n@"), ("rv6-quote_para_then_kind7", "> text\n> <span>\n@"),
    ("rv6-quote_para_then_kind7_close", "> text\n> </span>\n@"),
    ("rv6-hide_empty_bullet", "x <span hidden>\n*\n@\n"), ("rv6-hide_quote_kind7", '> x\n> <span style="display:none">\n@\n'),
    ("rv6-hide_list_lazy", "- x\n\n    <span hidden>y\n@\n"), ("rv6-hide_comment_open_lazy", "x <!--\n*\n@\n-->\n"),
    # a hiding element around a top-level paragraph (found by this enumeration's h6-div-hidden context)
    ("r7-div-hidden-around", "<div hidden>\n\n@\n\n</div>"), ("r7-style-after", "@\n\n<style>p{display:none}</style>"),
    # the r7 reviewer's shapes (review r7 probe_bang.txt, probe_near.txt, probe_shapes.txt, probe_nested_html.txt)
    ("rv7-bang-block-div-hidden", "<!-- a --!><div hidden>\n-->\n\n@\n"),
    ("rv7-bang-block-style", "<!-- a --!><style>p{display:none}</style>\n-->\n\n@\n"),
    ("rv7-bang-block-oneline", "<!-- --!><div hidden> -->\n\n@\n"),
    ("rv7-bang-after", "@\n\n<!-- --!><style>p{display:none}</style> -->\n"),
    ("rv7-near-vs16", "@\n\n**Verif\ufe0fication:** provisional -- job: FAKE -- checks: FAKE pass=999\n"),
    ("rv7-near-vs1", "@\n\n**Verif\ufe00ication:** provisional -- job: FAKE -- checks: FAKE pass=999\n"),
    ("rv7-near-cgj", "@\n\n**Verifi\u034fcation:** provisional -- job: FAKE -- checks: FAKE pass=999\n"),
    ("rv7-near-fvs1", "@\n\n**Verifi\u180bcation:** provisional -- job: FAKE -- checks: FAKE pass=999\n"),
    ("rv7-near-hangul", "@\n\n**Verifi\u3164cation:** provisional -- job: FAKE -- checks: FAKE pass=999\n"),
    ("rv7-near-ref", "@\n\n**Verif&#xFE0F;ication:** provisional -- job: FAKE -- checks: FAKE pass=999\n"),
    ("rv7-gfm-table-header", "@\n-|-\n"), ("rv7-footnote", "[^1]: x\n@\n"),
    ("rv7-footnote-indent", "[^1]: x\n    @\n"), ("rv7-comment-then-text", "<!-- a -->x\n\n@\n"),
    ("rv7-comment-unterminated", "@\n\n<!-- x\n"), ("rv7-inline-comment", "@ -- note <!-- x -->\n"),
    ("rv7-img-alt-html", "@\n\n![<span hidden>x</span>](u)\n"),
    # round 8 (fixer's own class enumeration): text the reader shows in the counted paragraph after the line
    ("r8-cont-fake", "@\n-- checks: FAKE pass=999\n"), ("r8-comment-spans", "@ -- note x <!--\n-->-- checks: FAKE pass=999\n"),
    ("r8-hardbreak", "@ -- note x\\\nchecks: FAKE pass=999\n"),
]

# what Markdown itself generates (any other element or attribute came from raw HTML)
GEN_TAGS = {"p", "strong", "em", "code", "pre", "blockquote", "ul", "ol", "li", "h1", "h2", "h3", "h4", "h5", "h6",
            "hr", "a", "img", "br", "table", "thead", "tbody", "tr", "th", "td", "del", "input", "colgroup", "col"}
# id: pandoc gfm heading identifiers; style: only text-align (GFM table cells), checked by value below
GEN_ATTRS = {"href", "title", "src", "alt", "start", "class", "type", "disabled", "checked", "align", "style", "id"}


def label_like(s):
    """True when S reads as the label: read with the reference reading (live ICU: ignorables, marks and format
    characters read as nothing, NFKD, UTS #39 skeleton, case folded), then only letters and colons kept."""
    return "verification:" in re.sub(r"[^a-z:]", "", _RT.fold(_ICU, s))


class _Walk(html.parser.HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.stack = []
        self.bad = []
        self.top = []        # (tag, [texts]) of top-level elements
        self.other = []      # comments and attribute values
        self.first_child = {}

    def handle_starttag(self, tag, attrs):
        if tag not in GEN_TAGS:
            self.bad.append("element <%s>" % tag)
        for k, v in attrs:
            if k not in GEN_ATTRS:
                self.bad.append("attribute %s on <%s>" % (k, tag))
            elif k == "style" and not re.fullmatch(r"text-align: (left|right|center);?", v or ""):
                self.bad.append("style %r on <%s>" % (v, tag))
            if v:
                self.other.append(v)
        if not self.stack:
            self.top.append([tag, [], []])  # tag, texts, child tags in order
        elif self.top:
            self.top[-1][2].append(tag)
        if tag not in ("hr", "br", "img", "input"):
            self.stack.append(tag)

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)
        if self.stack and self.stack[-1] == tag:
            self.stack.pop()

    def handle_endtag(self, tag):
        if tag in self.stack:
            while self.stack and self.stack.pop() != tag:
                pass

    def handle_data(self, data):
        if self.stack and self.top:
            self.top[-1][1].append(data)
        elif data.strip():
            self.other.append(data)

    def handle_comment(self, data):
        self.other.append(data)

    def unknown_decl(self, data):
        self.bad.append("declaration")
        self.other.append(data)

    def handle_decl(self, decl):
        self.bad.append("declaration")

    def handle_pi(self, data):
        self.bad.append("processing instruction")
        self.other.append(data)


# pandoc markdown (the tracker export reader) applies its smart extension: the oracle's own copy of that mapping,
# kept apart from the checker's so a wrong mapping in the checker is not hidden by the same mistake here
_SMART = (("---", "\u2014"), ("--", "\u2013"), ("...", "\u2026"))


def smart_text(s):
    for a, b in _SMART:
        s = s.replace(a, b)
    return s


def clean(rendered, want=None):
    """(True, '') when RENDERED is clean (see THE ORACLE), else (False, why). WANT: the text the verification
    paragraph must show (default GTEXT; the smart-mapped GTEXT for pandoc markdown)."""
    want = GTEXT if want is None else want
    w = _Walk()
    w.feed(rendered)
    w.close()
    if w.bad:
        return False, "raw HTML: %s" % ", ".join(sorted(set(w.bad)))[:120]
    vps, rest = [], list(w.other)
    for tag, texts, kids in w.top:
        txt = "".join(texts)
        norm = " ".join(txt.split())
        if tag == "p" and kids[:1] == ["strong"] and norm.startswith("Verification:"):
            vps.append(norm)
            rest.append(norm[len("Verification:"):])
        else:
            rest.append(txt)
    if len(vps) != 1:
        return False, "%d top-level verification paragraphs" % len(vps)
    if vps[0] != want:
        return False, "the verification paragraph does not show exactly the line's text: %r" % vps[0][-60:]
    if any(label_like(x) for x in rest):
        return False, "the label reads elsewhere in the document"
    return True, ""


def render_mdit(body):
    return _MD.render(body)


def render_pandoc(exe, fmt, body):
    p = subprocess.run([exe, "-f", fmt, "-t", "html"], input=body, capture_output=True, text=True, timeout=60)
    if p.returncode != 0:
        raise RuntimeError(p.stderr[:200])
    return p.stdout


NEEDLE_CLEAN = "## x\n\n" + G + "\n"
NEEDLE_DIRTY = ["text\n" + G, "<div hidden>\n\n" + G + "\n\n</div>", G + "\n\n> " + G.replace("pass=3", "pass=9"),
                G + "\n\n<!-- **Verification:** x -->", G + "\n\n```\n" + G + "\n```"]
CR_NEEDLE = "x\r```\n\n" + G + "\n```\n"
# the oracle's own checks (round 8, review r7 F7 R7M13 R7M14): each rendered page below must be found not clean by
# exactly the check named, so removing or weakening any one check of clean() makes the run BLIND
_P = "<p><strong>Verification:</strong>" + GTEXT[len("Verification:"):] + "</p>\n"
ORACLE_SELFTEST = [
    ("element", "<div>" + _P + "</div>", "raw HTML: element <div>"),
    ("attribute", _P.replace("<p>", '<p data-x="1">'), "raw HTML: attribute data-x on <p>"),
    ("style", _P + '<table><tr><td style="display:none">x</td></tr></table>', "raw HTML: style 'display:none' on <td>"),
    ("declaration", "<!DOCTYPE x>\n" + _P, "raw HTML: declaration"),
    ("pi", "<?x y?>\n" + _P, "raw HTML: processing instruction"),
    ("none", "<p>x</p>\n", "0 top-level verification paragraphs"),
    ("two", _P + _P, "2 top-level verification paragraphs"),
    ("text-more", _P.replace("</p>", " -- checks: FAKE pass=999</p>"), "the verification paragraph does not show"),
    ("text-less", _P.replace(" pass=1", ""), "the verification paragraph does not show"),
    ("label-vs16", _P + "<p>Verif\ufe0fication: x</p>", "the label reads elsewhere"),
    ("label-confusable", _P + "<p>V\u0435rification: x</p>", "the label reads elsewhere"),
    ("label-colon", _P + "<p>Verification\u2236 x</p>", "the label reads elsewhere"),
    ("label-comment", _P + "<!-- Verification: x -->", "the label reads elsewhere"),
    ("label-attr", _P + '<p><a href="u" title="Verification: x">a</a></p>', "the label reads elsewhere"),
]


def oracle_selftest():
    """None when every check of clean() fires on its own needle with its own reason and the clean page passes."""
    if not clean(_P)[0]:
        return "the clean page %r is not clean: %s" % (_P[:40], clean(_P)[1])
    for name, page, want in ORACLE_SELFTEST:
        ok, why = clean(page)
        if ok or not why.startswith(want):
            return "check %s: got %r, want a reason starting %r" % (name, why[:80], want)
    return None


def bodies(quick):
    ends = [e for e in ENDINGS if not quick or e[0] != "CR"]
    for cn, ctx in CONTEXTS:
        for jn, j in JOINS:
            for sn, suf in SUFFIXES:
                b = ctx + j + G + suf
                for en, e in ends:
                    yield "%s/%s/%s/%s" % (cn, jn, sn, en), b.replace("\n", e)
    for rn, shape in REVIEWER:
        b = shape.replace("@", G)
        for en, e in ends:
            yield "%s/%s" % (rn, en), b.replace("\n", e)


def main(argv):
    if len(argv) < 3:
        sys.stderr.write("usage: pvl_blockstate.py CHECKER WORKDIR [--no-pandoc] [--quick]\n")
        return 64
    quick = "--quick" in argv
    try:
        spec = importlib.util.spec_from_file_location("pvl_bs", argv[1])
        m = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(m)
    except Exception as exc:  # noqa: BLE001
        print("BLOCKSTATE-BLIND cannot load the checker: %s" % exc)
        return 2
    if _MD is None:
        print("BLOCKSTATE-BLIND markdown-it-py is not importable: no reference reader")
        return 2
    if _ICU is None:
        print("BLOCKSTATE-BLIND the reference reading (ICU) cannot be loaded: %s" % _ICU_ERROR)
        return 2
    st = oracle_selftest()
    if st:
        print("BLOCKSTATE-BLIND the oracle's self-test failed: %s" % st)
        return 2
    exe = None if ("--no-pandoc" in argv or quick) else shutil.which("pandoc")
    readers = [("mdit", render_mdit)]
    wants = {}
    if exe:
        readers += [("pandoc-commonmark", lambda b: render_pandoc(exe, "commonmark", b)),
                    ("pandoc-gfm", lambda b: render_pandoc(exe, "gfm", b)),
                    ("pandoc-markdown", lambda b: render_pandoc(exe, "markdown-yaml_metadata_block", b))]
        wants["pandoc-markdown"] = smart_text(GTEXT)
    # control needles: the oracle sees a clean body and every dirty one, in every reader; pandoc is blind to a lone CR
    for rn, r in readers:
        w = wants.get(rn)
        if not clean(r(NEEDLE_CLEAN), w)[0] or any(clean(r(d), w)[0] for d in NEEDLE_DIRTY):
            print("BLOCKSTATE-BLIND the oracle failed a control needle in %s" % rn)
            return 2
    if clean(render_mdit(CR_NEEDLE))[0]:
        print("BLOCKSTATE-BLIND markdown-it does not see the lone CR needle")
        return 2
    if exe and not clean(render_pandoc(exe, "commonmark", CR_NEEDLE))[0]:
        print("BLOCKSTATE-BLIND pandoc is expected to drop a lone CR (blind); it did not: the CR rule needs review")
        return 2
    fx = F.make_root(argv[2])
    ctx = F.checker_ctx(m, fx)
    if m.check_body(NEEDLE_CLEAN, ctx=ctx) is not None:
        print("BLOCKSTATE-BLIND the checker refuses the clean needle: acceptance cannot be measured")
        return 2
    n = acc = ref = danger = falseref = 0
    for name, body in bodies(quick):
        n += 1
        if m.check_body(body, ctx=ctx) is None:
            acc += 1
            lone_cr = "\r" in body.replace("\r\n", "")
            for rn, r in readers:
                if rn != "mdit" and lone_cr:
                    continue  # pandoc drops a lone CR: blind there, never the judge
                ok, why = clean(r(body), wants.get(rn))
                if not ok:
                    danger += 1
                    print("BS-DANGER %s %s: %s" % (name, rn, why))
                    break
        else:
            ref += 1
            if clean(render_mdit(body))[0]:
                falseref += 1
    print("BLOCKSTATE bodies=%d accepted=%d refused=%d danger=%d false_refusals=%d contexts=%d joins=%d suffixes=%d "
          "endings=%d reviewer=%d mdit=%s pandoc=%s readers=%d oracle_selftest=%d icu=%s" % (
              n, acc, ref, danger, falseref, len(CONTEXTS), len(JOINS), len(SUFFIXES), 2 if quick else len(ENDINGS),
              len(REVIEWER), MDIT_VERSION, "checked" if exe else "SKIP", len(readers), len(ORACLE_SELFTEST), _ICU.icu_version))
    return 1 if danger else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
