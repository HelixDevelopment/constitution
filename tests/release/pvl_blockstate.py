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
            (fenced div, attribute list), hard breaks)
  JOINS     how the line is attached (one, two, three line feeds; a quote marker; an empty quote line; 2, 3, 4 spaces; a
            tab; a list marker; a blank and then 2 or 4 spaces or a tab)
  SUFFIXES  what follows the line (nothing, a line feed, a fence, `-->`, `</div>`, setext underlines, text, a blank and
            `</div>`)
  ENDINGS   LF, a lone CR, CR LF (every line feed of the body replaced)
plus the r6 reviewer's shapes verbatim (review r6 probe_r6, probe_hide). Every verification line is the fixture's
grammar sentence (tests/release/pvl_fixture.py line()) resolved under a fixture root, so the checker's real verdict
check_body(body, ctx) is computed, never inferred.

THE ORACLE (independent of the checker's code): a body the checker ACCEPTS is rendered to HTML by every reader present
-- markdown-it-py `commonmark`, pandoc `-f commonmark` and pandoc `-f gfm` (pandoc only for a body without a lone CR:
pandoc drops a lone CR and is blind to it, the needle below proves it) -- and the HTML is read with html.parser. A
render is CLEAN when (a) it holds only the elements Markdown itself generates, with only their generated attributes
(no raw HTML element, so nothing can hide or wrap the line), (b) exactly one top-level <p> starts with
<strong>Verification:</strong>, and its text starts with the line's text, and (c) no other text of the document
(text outside that paragraph, comments, attribute values, the rest of that paragraph) reads as the label once every
character that is not a letter or a colon is removed (casefolded, NFKC, format characters removed). An accepted body
whose render is not clean in any reader is a DANGER (a FAIL). A refused body is the safe direction; the bodies
markdown-it renders clean but the checker refuses are counted as false refusals (informational).

Control needles (section 11.4.201(7)(b)): the oracle must call NEEDLE_CLEAN clean and each NEEDLE_DIRTY not clean in
markdown-it (and in pandoc when present), and pandoc must be blind to a lone CR (it renders `x<CR>```...` with the line
visible). A failed needle makes the run BLIND (exit 2).
Output: per DANGER `BS-DANGER <name> <reader>: <why>`, then `BLOCKSTATE bodies=N accepted=A refused=R danger=D
false_refusals=F contexts=C joins=J suffixes=S endings=E reviewer=K mdit=<version> pandoc=<checked|SKIP>`.
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
import unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import pvl_fixture as F  # noqa: E402

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
]
JOINS = [("lf", "\n"), ("blank", "\n\n"), ("blank2", "\n\n\n"), ("quote", "\n> "), ("quote-empty", "\n>\n"),
         ("sp2", "\n  "), ("sp3", "\n   "), ("sp4", "\n    "), ("tab", "\n\t"), ("dash", "\n- "),
         ("blank-sp2", "\n\n  "), ("blank-sp4", "\n\n    "), ("blank-tab", "\n\n\t")]
SUFFIXES = [("none", ""), ("lf", "\n"), ("fence", "\n```"), ("comment-end", "\n-->"), ("div-end", "\n</div>"),
            ("setext1", "\n==="), ("setext2", "\n---"), ("text", "\ntext"), ("blank-div-end", "\n\n</div>")]
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
]

# what Markdown itself generates (any other element or attribute came from raw HTML)
GEN_TAGS = {"p", "strong", "em", "code", "pre", "blockquote", "ul", "ol", "li", "h1", "h2", "h3", "h4", "h5", "h6",
            "hr", "a", "img", "br", "table", "thead", "tbody", "tr", "th", "td", "del", "input", "colgroup", "col"}
# id: pandoc gfm heading identifiers; style: only text-align (GFM table cells), checked by value below
GEN_ATTRS = {"href", "title", "src", "alt", "start", "class", "type", "disabled", "checked", "align", "style", "id"}


def label_like(s):
    """True when S reads as the label: casefolded, NFKC, format characters removed, then only letters and colons kept."""
    t = unicodedata.normalize("NFKC", s)
    t = "".join(c for c in t if unicodedata.category(c) != "Cf").casefold()
    return "verification:" in re.sub(r"[^a-z:]", "", t)


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


def clean(rendered):
    """(True, '') when RENDERED is clean (see THE ORACLE), else (False, why)."""
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
    if not vps[0].startswith(GTEXT):
        return False, "the verification paragraph does not start with the line's text: %r" % vps[0][:60]
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
    exe = None if ("--no-pandoc" in argv or quick) else shutil.which("pandoc")
    readers = [("mdit", render_mdit)]
    if exe:
        readers += [("pandoc-commonmark", lambda b: render_pandoc(exe, "commonmark", b)),
                    ("pandoc-gfm", lambda b: render_pandoc(exe, "gfm", b))]
    # control needles: the oracle sees a clean body and every dirty one, in every reader; pandoc is blind to a lone CR
    for rn, r in readers:
        if not clean(r(NEEDLE_CLEAN))[0] or any(clean(r(d))[0] for d in NEEDLE_DIRTY):
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
                ok, why = clean(r(body))
                if not ok:
                    danger += 1
                    print("BS-DANGER %s %s: %s" % (name, rn, why))
                    break
        else:
            ref += 1
            if clean(render_mdit(body))[0]:
                falseref += 1
    print("BLOCKSTATE bodies=%d accepted=%d refused=%d danger=%d false_refusals=%d contexts=%d joins=%d suffixes=%d "
          "endings=%d reviewer=%d mdit=%s pandoc=%s" % (n, acc, ref, danger, falseref, len(CONTEXTS), len(JOINS),
                                                       len(SUFFIXES), 2 if quick else len(ENDINGS), len(REVIEWER),
                                                       MDIT_VERSION, "checked" if exe else "SKIP"))
    return 1 if danger else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
