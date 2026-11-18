#!/usr/bin/env python3
"""Round 10 kill harness of scripts/validation/check_provisional_verification_lines.py (CON-521, review r9).

Usage: pvl_r10.py CHECKER WORKDIR

Each case prints `R10 <name> PASS|FAIL <detail>`; the last line is `R10 cases=N pass=P fail=F`. Exit 0 when every
case passes, 1 when one fails, 2 when the setup cannot run (a reader is unavailable, the fixture cannot be built).

What it checks, by finding of review r9 (out/REVIEW.md):
  F1  THE BODY ALPHABET: the reviewer's look-alike and invisible labels (Greek nu, math bold, lunate sigma, long s,
      palochka, visarga, U+FE30, NEL, VT, line and paragraph separators, hair space) are refused by the character
      rule, also written as a character reference; a sample of code points (every code point of the categories Cc,
      Cf, Zs, Zl, Zp, Mn, Mc and Me, every key of the reading table, every 211th other code point) is refused; the
      alphabet itself is accepted (a control needle); every character added to the alphabet is neither a letter, a
      mark nor a control and folds to nothing a label is made of; a reader that writes a character outside the
      alphabet (pandoc gfm writes an emoji for :smile:) is refused by the output rule.
  F2  THE DOCUMENT: a tracker database with a doc_segments table, read as renderDocument joins it: an unclosed ```
      or ~~~ fence after the line (D1, D2) is refused for that item and the next item is accepted; a non-provisional
      item that ends in an open comment (D3) or HTML element is a DOC-FAIL and the next item is accepted; an open raw
      segment is a DOC-FAIL; a line that a following item turns into a setext heading is refused (SHOWN); a segment
      that names a missing item makes the run BLIND. check_document alone: a quote without a final blank line is
      refused as an open construct.
  F3  the reviewer's mutants RV9M01..RV9M10: each telling body of out/reviewer_mutant_tells.txt, with the reason
      that tells the checker from the mutant (RV9M06, RV9M07, RV9M10 are told apart by reason or by one function).
  F4  THE STRUCTURE BOUND: the reviewer's slow bodies (out/dos.txt) are refused before any reader, each within 2 s;
      a line with more than MAX_DEPTH container markers is refused; a body at every count bound is not refused by
      the bound.
  F7  a label written with a hyphen inside the word (Verifi-cation:) is refused as a label.
"""
import os
import sqlite3
import subprocess
import sys
import time
import unicodedata

HERE = os.path.dirname(os.path.abspath(__file__))
RESULTS = []


def case(name, ok, detail=""):
    RESULTS.append(ok)
    print("R10 %s %s %s" % (name, "PASS" if ok else "FAIL", detail[:300].replace("\n", "\\n")), flush=True)


def has(r, why):
    return r is not None and why in r


def load(path):
    import importlib.util
    spec = importlib.util.spec_from_file_location("pvl_r10_checker", path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


FAKE = " provisional -- job: FAKE -- checks: FAKE pass=999\n"
# the reviewer's bodies (tools/cases_fold.py, cases_fold2.py, cases_cc.py, cases_space.py); @ is the counted line
REVIEWER_F1 = [
    ("NU_caps_after", "@\n\nVERIFICATIOΝ:" + FAKE),
    ("NU_caps_bold", "@\n\n**VERIFICATIOΝ:**" + FAKE),
    ("NU_caps_before", "**VERIFICATIOΝ:**" + FAKE + "\n@\n"),
    ("NU_mathbold", "@\n\n\U0001d415\U0001d404\U0001d411\U0001d408\U0001d405\U0001d408\U0001d402\U0001d400"
                    "\U0001d413\U0001d408\U0001d40e\U0001d6b4: provisional -- job: FAKE\n"),
    ("visarga_colon", "@\n\nVerificationः job: FAKE -- checks: FAKE pass=999\n"),
    ("visarga_bold", "@\n\n**Verificationः** job: FAKE -- checks: FAKE pass=999\n"),
    ("gujarati_visarga", "@\n\nVerificationઃ job: FAKE -- checks: FAKE pass=999\n"),
    ("fe30_colon", "@\n\n**Verification︰** job: FAKE -- checks: FAKE pass=999\n"),
    ("control_omicron", "@\n\n**Verificatiοn:** job: FAKE\n"),
    ("lunate_sigma_c", "@\n\n**Verifiϲation:**" + FAKE),
    ("long_s_f", "@\n\n**Veriſication:**" + FAKE),
    ("palochka_caps_I", "@\n\n**VERӀFICATION:**" + FAKE),
    ("nu_in_list", "@\n\n- **VERIFICATIOΝ:** provisional -- job: FAKE\n"),
    ("nu_in_heading", "@\n\n## VERIFICATIOΝ: provisional -- job: FAKE\n"),
    ("nu_in_table", "@\n\n| VERIFICATIOΝ: provisional |\n|---|\n| FAKE |\n"),
    ("vt_000b", "@\n\n**Verifi\x0bcation:** provisional -- job: FAKE\n"),
    ("nel_mid_bold_heading", "@\n\n## Verifi\x85cation: provisional -- job: FAKE\n"),
    ("ls_2028", "@\n\n**Verifi cation:** provisional -- job: FAKE\n"),
    ("ps_2029", "@\n\n**Verifi cation:** provisional -- job: FAKE\n"),
    ("hair_200a", "@\n\n**Verifi cation:** provisional -- job: FAKE\n"),
    ("nel_0085", "@\n\n**Verifi\x85cation:** provisional -- job: FAKE\n"),
    ("entity_nu", "@\n\n**VERIFICATIO&#x39D;:**" + FAKE),
    ("entity_nu_dec", "@\n\n**VERIFICATIO&#925;:**" + FAKE),
    ("entity_named_nu", "@\n\n**VERIFICATIO&Nu;:**" + FAKE),
]
N = 60000
REVIEWER_F4 = {  # the reviewer's slow bodies (tools/dos.py, N = 60000), each before the line
    "nested_quote": "> " * (N // 2) + "x",
    "brackets": "[ " * (N // 2),
    "link_open": "[a]( " * (N // 5),
    "bang_brackets": "![ " * (N // 3),
    "brace": "{ a } [ " * (N // 8),
    "pipes": ("| a " * 100 + "|\n") + ("|---" * 100 + "|\n") + ("| b " * 100 + "|\n") * 140,
    "list_nest": "".join("  " * i + "- x\n" for i in range(0, 200)),
}


def f1(m, ctx, line):
    for name, body in REVIEWER_F1:
        r = m.check_body(body.replace("@", line), ctx=ctx)
        case("F1-" + name, has(r, "outside THE BODY ALPHABET"), str(r))
    # the sample: every code point of the invisible, separator, control and mark categories, every key of the
    # reading table, every 211th other code point (surrogates cannot be written to a file and are left out)
    _drop, rmap, problem = m._reading()
    keys = set()
    if not problem:
        for k in rmap:
            keys.add(chr(k) if isinstance(k, int) else k)
    wanted = {"Cc", "Cf", "Zs", "Zl", "Zp", "Mn", "Mc", "Me"}
    sample = []
    for cp in range(0x110000):
        ch = chr(cp)
        cat = unicodedata.category(ch)
        if cat == "Cs" or "\x20" <= ch <= "\x7e" or ch in "\t\n\r" or ch in m.BODY_EXTRA:
            continue
        if cat in wanted or ch in keys or cp % 211 == 0:
            sample.append(ch)
    bad = []
    for ch in sample:
        r = m.check_body("x\n\n" + line + "\n\na" + ch + "b\n", ctx=ctx)
        if not has(r, "outside THE BODY ALPHABET") and not has(r, "bidi control") and not has(r, "CR that is not"):
            bad.append("U+%04X" % ord(ch))
    case("F1-sample", not bad and len(sample) > 3000 and len(keys) > 0,
         "sampled=%d keys=%d accepted=%s" % (len(sample), len(keys), " ".join(bad[:20])))
    # a numeric reference read as CommonMark reads it, not as html.unescape (which drops a noncharacter and reads
    # &#x97; as windows-1252): the enumeration of every code point written as &#xHEX; found 68 accepted (r10 run 1)
    for ref in ("&#x7F;", "&#xFDD0;", "&#xFFFF;", "&#x10FFFF;", "&#x97;", "&#151;", "&#0;", "&#xD800;", "&#x110000;"):
        r = m.check_body("x\n\n" + line + "\n\nVerifi" + ref + "cation: x\n", ctx=ctx)
        case("F1-ref-" + ref.strip("&#;"), has(r, "the character reference " + ref), str(r))
    # control needles: the alphabet is accepted, a letter outside it is found
    alpha = "".join(chr(c) for c in range(0x20, 0x7f)) + "\t\n\r" + "".join(sorted(m.BODY_EXTRA))
    case("F1-needle-in", m.outside_alphabet(alpha, m.BODY_EXTRA) is None, "")
    case("F1-needle-out", m.outside_alphabet(alpha + "é", m.BODY_EXTRA) == "é", "")
    r = m.check_body("x\n\n" + line + "\n\nsee §1 → x · y — z\n", ctx=ctx)
    case("F1-extra-accepted", r is None, str(r))
    props = []
    for ch in sorted(m.BODY_EXTRA | m.SHOWN_EXTRA):
        f = m.fold(ch)
        if unicodedata.category(ch)[0] in "LMC" or any(c.isalnum() or c == ":" for c in f):
            props.append("U+%04X" % ord(ch))
    case("F1-extra-property", not props and len(m.BODY_EXTRA) == 4, " ".join(props))
    r = m.check_body("x\n\n" + line + "\n\nok :smile: ok\n", ctx=ctx)
    case("F1-shown-emoji", has(r, "pandoc gfm shows U+1F604"), str(r))
    r = m.check_body("x\n\n" + line + "\n\n**Verifi-cation:**" + FAKE, ctx=ctx)
    case("F7-hyphen", has(r, "label in another source line"), str(r))


def f3(m, ctx, line):
    rest = line[len(m.BOLD_LABEL):]
    refused = [("RV9M01a", '[x]{hidden=""}\n\n@\n'), ("RV9M01b", "[x]{lang=fr}\n\n@\n"),
               ("RV9M02", '[x]{style="display:none"}\n\n@\n'), ("RV9M03", "```x\n<b>\n```\n\n[a]: http://x\n\n@\n"),
               ("RV9M04", "```x\n<b>\n``` \n\n@\n"), ("RV9M05", " ```x\n<b>\n```\n\n@\n")]
    for name, body in refused:
        r = m.check_body(body.replace("@", line), ctx=ctx)
        case("F3-" + name, r is not None, str(r))
    r = m.check_body(line + "\n\n```x\n<b\n", ctx=ctx)
    case("F3-RV9M06", has(r, "fence that is not closed"), str(r))
    got = m.confirm("## " + line + "\n\n" + line + "\n", rest)
    case("F3-RV9M07", len(got) == 1 and got[0].startswith("label:"), str(got))
    # a second copy shown only as text (a quote: no heading id attribute), so only the text check can see it
    got = m.confirm(line + "\n\n> " + line + "\n", rest)
    case("F3-RV9M07-text", len(got) == 1 and got[0].startswith("label:"), str(got))
    r = m.check_body(line + "\n\nfoo ⁧bar⁩ baz\n", ctx=ctx)
    case("F3-RV9M08", has(r, "bidi control U+2067"), str(r))
    r = m.check_body("a " * 300 + "\n\n" + line + "\n", ctx=ctx)
    case("F3-RV9M09", has(r, "with no white space between them"), str(r))
    paras = m._output("<p>a<span><p>b</p></span>c</p>", "x")[0]
    case("F3-RV9M10", paras == ["a<span><p>b</p></span>c"], str(paras))


def f4(m, ctx, line):
    for name, filler in sorted(REVIEWER_F4.items()):
        t = time.time()
        r = m.check_body(filler + "\n\n" + line + "\n", ctx=ctx)
        dt = time.time() - t
        # list_nest is bounded by its length (200 levels by indentation, read in 0.1 s) and refused by a reader rule
        want = r is not None if name == "list_nest" else has(r, "the body is not read")
        case("F4-" + name, want and dt < 2.0, "%.2fs %s" % (dt, r))
    r = m.check_body("> " * (m.MAX_DEPTH + 1) + "x\n\n" + line + "\n", ctx=ctx)
    case("F4-depth", has(r, "container markers"), str(r))
    r = m.check_body("> " * m.MAX_DEPTH + "x\n\n" + line + "\n", ctx=ctx)
    case("F4-depth-bound", r is None or "container markers" not in r, str(r))
    for name, filler, bad in (("open7", "[ " * 7, True), ("open6", "[ " * 6, False), ("nested7", "[" * 7 + "x" + "]" * 7, True),
                              ("closed64", "[a] " * 64, False), ("open7-lines", "[ x\n" * 7, True),
                              ("open7-paras", "[ x\n\n" * 7, False)):
        r = m.structure_problem(filler)
        case("F4-bracket-" + name, (r is not None and "still open in its paragraph" in r) == bad, str(r))
    over = []
    for ch, most in sorted(m.STRUCT_MAX.items()):
        unit = "[] " if ch == "[" else ch + " "  # each [ closed at once: the count bound alone, not the open-[ bound
        at = m.structure_problem("x " + unit * most)
        above = m.structure_problem("x " + unit * (most + 1))
        if at is not None or above is None:
            over.append(ch)
    case("F4-count-bounds", not over, " ".join(over))


def schema(con):
    con.execute("create table items (atm_id text primary key, status text, body_md text, created_at text, "
                "current_location text, representation text)")
    con.execute("create table doc_segments (document text, seq integer, kind text, atm_id text, representation text, "
                "raw text)")


def f2(m, F, fx, ck, work, line):
    good = lambda k: "## %s — item\n\n" % k + line + "\n\n"  # noqa: E731
    items = [  # (id, status, body); every item is in document Issues in this order
        ("CON-901", "Ready for testing", "## CON-901 — a\n\n" + line + "\n\n```\n"),         # D1
        ("CON-902", "Ready for testing", good("CON-902")),
        ("CON-903", "Queued", "## CON-903 — c\n\nText.\n\n<!--\n"),                          # D3
        ("CON-904", "Ready for testing", good("CON-904")),
        ("CON-905", "Queued", "## CON-905 — e\n\n<details>\n\nhidden\n"),                    # an open element
        ("CON-906", "Ready for testing", good("CON-906")),
        ("CON-911", "Ready for testing", "## CON-911 — k\n\n" + line + "\n\n~~~\n"),         # D2
        ("CON-912", "Ready for testing", good("CON-912")),
    ]
    raws = {3: "# Issues\n\n", 100: "<!--\n"}
    tail = [("CON-913", "Ready for testing", good("CON-913"))]
    fixed = [("CON-920", "Ready for testing", "x\n\n" + line), ("CON-921", "Queued", "===\n")]
    db = os.path.join(work, "doc.db")
    if os.path.exists(db):
        os.remove(db)
    con = sqlite3.connect(db)
    schema(con)
    for k, st in F.ITEMS.items():
        if st not in ("Ready for testing", "In testing"):
            con.execute("insert into items values (?,?,?,?,?,?)", (k, st, "x", "2026-11-01", "Elsewhere", ""))
    seq = 0
    for doc, rows in (("Issues", items), ("Issues", tail), ("Fixed", fixed)):
        if rows is tail:
            con.execute("insert into doc_segments values ('Issues', 100, 'raw', null, null, ?)", (raws[100],))
            seq = 100
        if doc == "Issues" and rows is items:
            con.execute("insert into doc_segments values ('Issues', 3, 'raw', null, null, ?)", (raws[3],))
            seq = 3
        for k, st, b in rows:
            seq += 1
            con.execute("insert into items values (?,?,?,?,?,?)", (k, st, b, "2026-11-01", doc, ""))
            con.execute("insert into doc_segments values (?,?,?,?,?,?)", (doc, seq, "item", k, "", None))
    con.commit()
    con.close()
    p = subprocess.run(ck + [db], capture_output=True, text=True, timeout=900)
    out = p.stdout.splitlines()

    def fail_of(k):
        return [ln for ln in out if ln.startswith("FAIL %s " % k)]
    for k, why in (("CON-901", "leaves a construct open at its end"), ("CON-911", "leaves a construct open at its end"),
                   ("CON-920", "shows the verification line as a paragraph of its own 0 times")):  # SHOWN: setext
        case("F2-refused-" + k, any(why in ln for ln in fail_of(k)), str(fail_of(k)))
    for k in ("CON-902", "CON-904", "CON-906", "CON-912", "CON-913"):
        case("F2-accepted-" + k, not fail_of(k), str(fail_of(k)))
    for k in ("CON-903", "CON-905"):
        case("F2-docfail-" + k, any(ln.startswith("DOC-FAIL %s Queued:" % k) for ln in out), "")
    case("F2-docfail-raw", any(ln.startswith("DOC-FAIL Issues segment 100:") for ln in out), "")
    case("F2-verdict", p.returncode == 1 and "VERDICT: FAIL" in out and "Traceback" not in p.stdout + p.stderr and
         "DOCUMENT documents=2 segments=13 real=2 other_fail=3" in out, "rc=%d %s" % (p.returncode, out[-4:]))
    # a segment that names a missing item: the document cannot be built (BLIND)
    con = sqlite3.connect(db)
    con.execute("insert into doc_segments values ('Fixed', 999, 'item', 'CON-999', '', null)")
    con.commit()
    con.close()
    p = subprocess.run(ck + [db], capture_output=True, text=True, timeout=900)
    case("F2-blind-missing", p.returncode == 2 and "VERDICT: BLIND" in p.stdout.splitlines(), p.stdout[-200:])
    # check_document alone: a quote with no LF at its end keeps the next line inside it (SHOWN refuses that line)
    segs = [(("A", ""), "A", "Queued", "> quote"), (("B", ""), "B", "Ready for testing", line + "\n\n")]
    fails, problem = m.check_document("t", True, segs, {("B", ""): line})
    case("F2-lazy-quote", problem is None and list(fails) == [("B", "")] and "0 times for 1" in fails[("B", "")],
         str((fails, problem)))
    # SHOWN alone: a segment that holds the line inside a closed fence is closed, but the line is not shown
    segs = [(("B", ""), "B", "Ready for testing", "```\n" + line + "\n```\n\n")]
    fails, problem = m.check_document("t", True, segs, {("B", ""): line})
    case("F2-shown", problem is None and "shows the verification line as a paragraph of its own 0 times for 1" in
         fails.get(("B", ""), ""), str((fails, problem)))
    fails, problem = m.check_document("t", False, segs, {("B", ""): line})
    case("F2-shown-not-real", problem is None and not fails, str((fails, problem)))
    # pandoc markdown reads a < without > as the start of a raw tag that a later item's > ends (CON-112, main)
    segs = [(("P", ""), "P", "Queued", "run x </dev/null) y\n"),
            (("Q", ""), "Q", "Ready for testing", line + "\n\n"),
            (("R", ""), "R", "Queued", "see <tmp> z\n")]
    fails, problem = m.check_document("t", True, segs, {("Q", ""): line})
    case("F2-pandoc-tag-swallow", problem is None and ("P", "") in fails and ("Q", "") not in fails,
         str((fails, problem)))


def f5(m, ctx, line):
    """Round 10 mutation tells: one case per rule a mutant removes that the parts above do not reach alone."""
    rest = line[len(m.BOLD_LABEL):]
    # the status is read with fold(): a look-alike letter in a status does not hide a provisional item (O66)
    case("K-status-fold", m.status_key("R\u0435ady for testing") == "ready for testing",
         repr(m.status_key("R\u0435ady for testing")))
    # a named character reference is decoded before the alphabet is read (O112)
    r = m.check_body(line + "\n\ncaf&eacute; x\n", ctx=ctx)
    case("K-named-ref", has(r, "the body holds U+00E9"), str(r))  # the source rule, not the later shown rule
    # a bidi control written as a numeric reference is read as a bidi control (O91)
    r = m.check_body(line + "\n\nfoo &#x2067;bar baz\n", ctx=ctx)
    case("K-bidi-ref", has(r, "bidi control U+2067") or has(r, "bidi: U+2067"), str(r))
    # confirm() alone: a body that leaves a fence open after the line hides the probe (O115)
    got = m.confirm(line + "\n\n```\n", rest)
    case("K-confirm-open", len(got) == 1 and got[0].startswith("open:"), str(got))
    # top_paragraphs: an unclosed comment hides the rest (O120), a raw-text element is skipped (O121), a nested <p>
    # does not start a top-level paragraph (O122)
    for name, h, want in (("K-tp-comment", "<p>a</p><!-- <p>b</p>", ["a"]),
                          ("K-tp-rawtext", "<textarea><!--</textarea><p>c</p>", ["c"]),
                          ("K-tp-nested", "<p>x<span><p>a</span></p>", ["x<span><p>a</span>"])):
        got = m.top_paragraphs(h)
        case(name, got == want, repr(got))
    # the document check reads no segment past THE STRUCTURE BOUND (O128)
    deep = ">" * (m.MAX_DEPTH + 1) + " x\n"
    segs = [(("D", ""), "D", "Queued", deep), (("B", ""), "B", "Ready for testing", line + "\n\n")]
    fails, problem = m.check_document("t", True, segs, {("B", ""): line})
    case("K-doc-structure", problem is None and "is not read" in fails.get(("D", ""), ""), str((fails, problem)))


def main(argv):
    if len(argv) != 3:
        sys.stderr.write("usage: pvl_r10.py CHECKER WORKDIR\n")
        return 64
    ckpath, work = os.path.abspath(argv[1]), os.path.abspath(argv[2])
    os.makedirs(work, exist_ok=True)
    sys.path.insert(0, HERE)
    import pvl_fixture as F
    fx = F.make_root(os.path.join(work, "root"))
    m = load(ckpath)
    rp = m.reader_problem()
    if rp:
        print("R10 SETUP a reader is unavailable: %s" % rp)
        return 2
    ctx = F.checker_ctx(m, fx)
    line = F.line()
    ck = [sys.executable, "-I", ckpath, "--today", F.TODAY.isoformat(), "--root", fx["root"]]
    for name, run in (("F1", lambda: f1(m, ctx, line)), ("F3", lambda: f3(m, ctx, line)),
                      ("F4", lambda: f4(m, ctx, line)), ("F2", lambda: f2(m, F, fx, ck, work, line)),
                      ("K", lambda: f5(m, ctx, line))):
        try:
            run()
        except Exception as exc:  # noqa: BLE001 -- a checker without a round 10 name fails the rest of that part
            case(name + "-crash", False, "%s: %s" % (exc.__class__.__name__, exc))
    n, ok = len(RESULTS), sum(RESULTS)
    print("R10 cases=%d pass=%d fail=%d" % (n, ok, n - ok))
    return 0 if ok == n else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
