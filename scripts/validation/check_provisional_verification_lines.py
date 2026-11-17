#!/usr/bin/env python3
"""scripts/validation/check_provisional_verification_lines.py -- every PROVISIONAL-DONE item names a real, scheduled
verification job in a closed grammar.

Usage:
  python3 -I scripts/validation/check_provisional_verification_lines.py [--root DIR] [--targets FILE]
          [--today YYYY-MM-DD] [--due-window-days N] [DB]
  (default DB: docs/workable_items.db; default --root: the current directory; default --targets:
   config/verification_targets.tsv under the root; default --today: the UTC date; default window: 60 days)

Section 11.4.290: an item counts as PROVISIONAL-DONE while its Status is `Ready for testing` or `In testing`, and that
state needs a scheduled verification job recorded on one line. This checker reads the tracker database and refuses an
item of those statuses whose body has no such line, more than one, or a line that is not a sentence of the grammar
below.

THE READ (round 6, review r5 M-1). SQLite creates -wal and -shm files even for a read-only open of a WAL-mode
database, so the database is never opened in place: its file and its -wal and -journal files (when present) are copied
as bytes into a private temporary directory (round 7, review r6 I-3 and M-1: the path is resolved to its real path
first, because SQLite keeps the -wal next to a symlink's TARGET; every file is opened without blocking and must be a
regular file, else BLIND; the copy is bounded by MAX_DB_BYTES, else BLIND), the copy is opened, and the copy is taken again when a file changed
during it (inode, size or modification time; five tries, then BLIND). The original is never opened by SQLite, so no
sidecar appears next to it and its bytes are unchanged. A status is matched as a person reads it (round 8: with
fold(), the reading of THE NEAR RULE below, then white space collapsed): a status that reads as
`Ready for testing` or `In testing` but is not written exactly so is refused, never skipped (review r5 M-4). A body
that is not text, a created_at that is not text, and a target registry that is not UTF-8 are refused or reported
BLIND by name (review r5 M-2); an unexpected error is reported BLIND, never a traceback.

THE PRIMITIVE (CON-423 r5, section 11.4.276(E)(3), section 11.4.250). Rounds 1 to 4 accepted a value unless a bad form
was recognised (placeholder words, then their split, folded, glued, look-alike and invisible forms); every review found
new members. Round 5 accepts a value ONLY when it is a sentence of a closed grammar whose references RESOLVE: a script
must be a regular file under the root, an option, selector or env value must occur in that script, a checks result
must name a script or selector of the job, a remote must have its upstreams/<name>.sh, a device must be in the target
registry, a due date must lie between the item's created date and today plus the window. Anything else is refused by
construction. The class, the grammar and the complement are in docs/qa/rehearsal_v73_4_fix/r5/class_inventory.md.

THE GRAMMAR (ASCII; one U+0020 space where a space is written; tests/release/pvl_oracle.py holds a second,
independent implementation of the same grammar, and the suite compares the two):

  LINE     = "**Verification:** provisional" [" (section 11.4.290)"] SEP JOB SEP CHECKS SEP LAYER SEP TARGET SEP
             ARTIFACT SEP DUE [SEP NOTE]          each field is NAME ": " VALUE or NAME " " VALUE (the canon's form)
  SEP      = " -- " | " — "                  (the em dash is the only non-ASCII character outside NOTE)
  JOB      = TRACKERREF | INVOCATION *("; " INVOCATION)
  TRACKERREF = KEY "-" DIGITS: another item of the same database whose Status is Queued, In progress or
             Operator-blocked (an open, tracked job)
  INVOCATION = *(ENV " ") RUNNER " " SCRIPT *(" " ARG);  RUNNER = bash | sh | python3 | python3 -I
  SCRIPT   = a relative path of parts [A-Za-z0-9_.+-]+ (no "." or ".." part) that is a regular file under the real
             root, ending .sh or .bash for bash and sh, .py for python3
  ARG      = INT | OPTION | PATHARG | SELECTOR;  OPTION = (-x | --word)[=VAL], the option text occurs in SCRIPT;
             PATHARG = "." or a path (as SCRIPT's parts) that exists under the root; SELECTOR = [A-Za-z][A-Za-z0-9_.-]
             {0,63} holding a digit that occurs in SCRIPT as a whole word;  ENV = NAME=VAL with NAME in SCRIPT;
             VAL = INT | PATHARG | a word [A-Za-z0-9_.:/+-]{1,64} that occurs in SCRIPT as a whole word
  CHECKS   = RESULT *("; " RESULT);  RESULT = SUBJECT 1*(" " KEY "=" VALUE), SUBJECT a SCRIPT, SELECTOR or
             TRACKERREF written in JOB; KEY once per result: pass, fail, skip, killed, survived (INT), rc (0..255),
             verdict (PASS FAIL BLIND SKIP); at least one of the five count keys
  LAYER    = LWORD *(" plus " LWORD), LWORD in user-visible runtime artifact source host-only live-target gate-logic
  TARGET   = TTERM *(", " TTERM); TTERM = host | repo checkout | scratch clone | remote NAME (upstreams/NAME.sh a
             regular file under the root) | KIND ID (KIND board device container vm runner; KIND<TAB>ID a line of
             the target registry; no registry => refused)
  ARTIFACT = ATERM *(", " ATERM); ATERM = main | main@HEX | commit HEX | merge HEX | tag TAG; HEX = [0-9a-f]{7,64},
             TAG = [A-Za-z0-9][A-Za-z0-9._-]{0,63} holding a digit
  DUE      = YYYY-MM-DD [THH:MM[:SS][Z|+HH:MM|-HH:MM]], a real date with created(item) <= date <= today + window
  NOTE     = "note" then printable ASCII to the end of the line (at least one letter or digit); never evidence
  No term may appear twice in LAYER, TARGET or ARTIFACT; the line is at most 4096 characters.

THE LINE MODEL (round 7, structural: review r6 I-1 was the third round of a hand-written CommonMark state machine
missing a container or paragraph-state transition, section 11.4.250, section 11.4.276(E)(3)). The checker does not
model CommonMark by hand: the body is parsed by a real CommonMark parser, markdown-it-py (the version must be one of
MDIT_TESTED; a missing or untested parser makes the run BLIND, never a pass), and the parser's token stream is the
only source of the decision. Round 8 (review r7 F3): the body is read TWICE, with the `commonmark` preset and with the
same preset plus the GFM table and strikethrough rules (THE READERS), and every rule below holds in both readings:
  COUNTED  a line counts when it is the first source line of a TOP-LEVEL paragraph (token paragraph_open at level 0,
           its map gives the line), the source line starts with the prefix at column 0, and the paragraph's inline
           content starts with the bold `Verification:`. Source lines are the parser's own (its line endings: LF, CR LF,
           a lone CR; NUL read as U+FFFD), so the checker and the parser cannot split a body differently. The two
           readings must count the same lines (a setext heading CommonMark reads where GFM reads a table header).
  EXACT    (round 8) the counted paragraph must be that one source line, and the text a reader renders after the label
           must equal the rest of the source line: no continuation line, hard break, emphasis, strikethrough, link,
           code span, character reference or backslash escape (review r7 F7 R7M04: text a reader shows after the line
           in the same paragraph, such as a second `checks:` field on the next line, was accepted).
  RAW HTML (round 8, review r7 F1) ANY HTML block or inline HTML token, comments included and at any depth (also in
           image and link text, review r7 F5), refuses the body: raw HTML can hide or wrap a line (`hidden`,
           `display:none`, `<details>`, a `<style>` anywhere), and an HTML5 reader ends a comment at `--!>`, `<!-->` or
           `<!--->` where CommonMark does not, so the text after it is live markup to a browser. A placeholder written
           as `<name>` is raw HTML; write it inside backticks.
  FOOTNOTE (round 8, review r7 F3) a GFM footnote definition `[^x]: ...` refuses the body: a GFM reader moves its text
           (and any line indented under it) into a footnote, CommonMark reads it as a link reference definition.
  ELSEWHERE the body is refused when the Verification label (THE NEAR RULE's reading) occurs anywhere other than at the
           start of the one counted line: in any other source line, or in the text a reader renders anywhere in the
           document (other paragraphs, headings, block quotes, list items, code spans, code blocks, fences, link titles
           and targets, image text, and the counted paragraph after its label). Such a body is refused rather than
           judged, because whether a reader shows that text as a verification line depends on the reader.
The test harnesses check this against independent readers: tests/release/pvl_blockstate.py enumerates the container
and paragraph-state class and renders every accepted body with markdown-it-py, pandoc commonmark and pandoc gfm;
tests/release/pvl_lineend.py enumerates the line-ending and start-of-line class.
THE NEAR RULE (round 8, review r7 F2 and F4: a closed list of look-alikes and a format-character filter left variation
selectors, a combining grapheme joiner, Hangul fillers and every look-alike outside the list): the label is the word
Verification and a colon, markup or spaces allowed before the colon, matched on fold() of the text. fold() decodes
character references and reads every character with THE READING TABLE at the end of this file, generated offline from
ICU 78.2 / Unicode 17.0 by scripts/validation/pvl_reading_table.py (ICU is not needed at run time; the table's sha256
is checked, a broken table makes the run BLIND): a default-ignorable code point, a mark, a format, surrogate,
private-use or unassigned code point, or a control character other than white space is read as nothing; any other
character is decomposed with NFKD and each part read through the UTS #39 confusable skeleton and case folding, so
`V`, `Ꮩ` (Cherokee) and `Ｖ` read as `v` and `∶` (ratio) reads as `:`. The status is read with the same fold().

Known limits (stated): a sentence of the grammar can still be false (a real script that is not the right job, counts
that will not be observed, a commit id that is not the fix: commit and tag ids are shape-checked, the checker runs no
process); a selector, option or env value is accepted when the script merely mentions it. It does NOT check whether a
due date is past (derive_release_facts.sh reports that) or whether the job was run. The readers are CommonMark and
CommonMark with GFM tables and strikethrough; other dialects (pandoc fenced divs and attributes, kramdown attribute
lists) are read as CommonMark text, and GFM autolinks (`www.x`) and task lists are not parsed: they change no
character a reader sees (the enumeration renders accepted bodies with pandoc gfm too). THE READING is ICU's: an ASCII
character is read as itself (so `l`, `I` and `1` stay different), a character whose skeleton is not ASCII is read as
itself, and a visible gap such as U+2800 BRAILLE PATTERN BLANK is a character, not nothing; a reader whose fonts or
rules differ from Unicode 17.0 may show a character the table reads differently. False refusals, the safe direction:
a body holding any raw HTML or comment, a counted line with markup, a character reference or an escape after its
label, a GFM footnote definition, or the label anywhere else (also inside code).

Output: one `FAIL <id> <status>: <reason>` line per refused item, then `ROOT: <real root>` and `TODAY: <date>
window=<N>d`, then `CHECKED items=N provisional_status=P ok=K fail=F`, then `VERDICT: PASS|FAIL|BLIND`. Exit 0 PASS,
1 FAIL, 2 BLIND (the database cannot be read, a database file or sidecar is not a regular file or exceeds the size
bound, it has no items table, or holds no items: a zero there proves nothing; the CommonMark parser is missing or is
not a tested version, or the reading table is not intact), 64 usage (also a root that is not a directory, a --today
that is not a date, a window that is not 0..3650).
"""

import datetime
import hashlib
import html
import os
import pathlib
import re
import sqlite3
import stat
import sys
import tempfile
import time
import unicodedata

STATUSES = ("Ready for testing", "In testing")
OPEN_STATUSES = ("Queued", "In progress", "Operator-blocked")
FIELDS = ("job", "checks", "layer", "target", "artifact", "due")
MAX_LINE = 4096
MAX_SCRIPT_BYTES = 4 * 1024 * 1024
PREFIX = "**Verification:** provisional"
SECTION = " (section 11.4.290)"
SEP = re.compile(" (?:--|—) ")
FIELD_PART = re.compile(r"(job|checks|layer|target|artifact|due|note)(?:: | )(.*)\Z", re.S)
DEFAULT_WINDOW = 60

# grammar atoms (ASCII only; every pattern is used with fullmatch)
PART = r"[A-Za-z0-9_.+-]+"
PATH_RE = re.compile(r"%s(?:/%s)*" % (PART, PART))
INT_RE = re.compile(r"0|[1-9][0-9]{0,9}")
OPTION_RE = re.compile(r"(-[A-Za-z]|--[a-z][a-z0-9-]*)(?:=(.+))?")
SELECTOR_RE = re.compile(r"(?=[^0-9]*[0-9])[A-Za-z][A-Za-z0-9_.-]{0,63}")
ENV_RE = re.compile(r"([A-Z_][A-Z0-9_]{0,63})=(.+)")
WORD_RE = re.compile(r"[A-Za-z0-9_.:/+-]{1,64}")
ID_RE = re.compile(r"[A-Z][A-Z0-9]{1,15}-[0-9]{1,9}")
RUNNERS = {"bash": (".sh", ".bash"), "sh": (".sh", ".bash"), "python3": (".py",)}
COUNT_KEYS = ("pass", "fail", "skip", "killed", "survived")
TERM_RE = re.compile(r"(pass|fail|skip|killed|survived|rc|verdict)=(.+)")
VERDICTS = ("PASS", "FAIL", "BLIND", "SKIP")
LAYER_VOCAB = ("user-visible", "runtime", "artifact", "source", "host-only", "live-target", "gate-logic")
TARGET_FIXED = ("host", "repo checkout", "scratch clone")
TARGET_KINDS = ("board", "device", "container", "vm", "runner")
REMOTE_RE = re.compile(r"remote ([a-z0-9_]{1,64})")
KIND_RE = re.compile(r"(board|device|container|vm|runner) ([A-Za-z0-9][A-Za-z0-9._:-]{0,63})")
HEX = r"[0-9a-f]{7,64}"
ATERM_RE = re.compile(r"main|main@%s|commit %s|merge %s|tag (?=[^0-9]*[0-9])[A-Za-z0-9][A-Za-z0-9._-]{0,63}" % (
    HEX, HEX, HEX))
DUE_RE = re.compile(r"([0-9]{4})-([0-9]{2})-([0-9]{2})"
                    r"(?:T([0-9]{2}):([0-9]{2})(?::([0-9]{2}))?(Z|[+-][0-9]{2}:[0-9]{2})?)?")
PRINTABLE = re.compile(r"[\x20-\x7e]*")

# Cyrillic and Greek letters that look like ASCII letters. The grammar reads ASCII only, so a look-alike is refused by
# construction; this map only NAMES the look-alike in a refusal reason and decides nothing (round 8: how a person reads
# a character is the reading table at the end of this file, fold() below). scripts/release/render_release_entry.py
# holds the same map as a reader (tests/release/test_render_release_entry.sh compares the two).
CONFUSABLES = {
    "А": "A", "В": "B", "Е": "E", "К": "K", "М": "M", "Н": "H", "О": "O",
    "Р": "P", "С": "C", "Т": "T", "Х": "X", "У": "Y", "І": "I", "Ј": "J",
    "Ѕ": "S", "Ԁ": "D", "Ү": "Y", "а": "a", "е": "e", "о": "o", "р": "p",
    "с": "c", "у": "y", "х": "x", "і": "i", "ј": "j", "ѕ": "s", "ԁ": "d",
    "ԛ": "q", "ԝ": "w", "һ": "h", "ӏ": "l", "ү": "y",
    "Α": "A", "Β": "B", "Ε": "E", "Ζ": "Z", "Η": "H", "Ι": "I", "Κ": "K",
    "Μ": "M", "Ν": "N", "Ο": "O", "Ρ": "P", "Τ": "T", "Υ": "Y", "Χ": "X",
    "α": "a", "ι": "i", "κ": "k", "ν": "v", "ο": "o", "ρ": "p", "υ": "u",
    "χ": "x",
}

# the CommonMark parser (round 7): markdown-it-py, `commonmark` preset; only a tested version is trusted (a different
# version may tokenise differently; extend MDIT_TESTED only after the line-model suites pass with it)
MDIT_TESTED = ("3.0.0",)
try:
    import markdown_it as _mdit_pkg
    from markdown_it import MarkdownIt as _MarkdownIt
    from markdown_it.rules_core.normalize import NEWLINES_RE as _MDIT_NEWLINES, NULL_RE as _MDIT_NULL
    MDIT_VERSION = _mdit_pkg.__version__
    _MDIT_ERROR = None
except Exception as _exc:  # noqa: BLE001 -- reported as BLIND by main() and as a refusal by check_body()
    _MarkdownIt = None
    MDIT_VERSION = None
    _MDIT_ERROR = "%s: %s" % (_exc.__class__.__name__, str(_exc)[:120])
_MD = {}
MAX_BODY = 1024 * 1024
# the two readings (round 8, review r7 F3): CommonMark, and CommonMark with the GFM table and strikethrough rules
READERS = ("commonmark", "gfm")

# a line ending of the target registry (and of CommonMark 2.1): LF, CR LF, or a CR not followed by LF
LINE_END = re.compile(r"\r\n|\r|\n")
# the label a person reads as a verification statement, in any case, with markup or spaces before the colon; it is
# matched on fold() of the text (THE NEAR RULE)
LABEL = re.compile(r"verification[\s*_~`\\]*(?:</?[a-z][^>]*>[\s*_~`\\]*)*:", re.I)
BOLD_LABEL = "**Verification:**"


def reader_problem():
    """None when the CommonMark parser is importable and a tested version and the reading table is intact; else the
    reason (the run is BLIND)."""
    if _MarkdownIt is None:
        return "markdown-it-py cannot be imported (%s)" % _MDIT_ERROR
    if MDIT_VERSION not in MDIT_TESTED:
        return "markdown-it-py %s is not a tested version (%s)" % (MDIT_VERSION, ", ".join(MDIT_TESTED))
    if _reading()[2] is not None:
        return "the reading table is not intact (%s)" % _reading()[2]
    return None


def _md(reader):
    if reader not in _MD:
        md = _MarkdownIt("commonmark")
        if reader == "gfm":
            md.enable(["table", "strikethrough"])
        _MD[reader] = md
    return _MD[reader]


_READING = []


def _reading():
    """(drop pattern, translate map, problem): the reading table at the end of this file, checked against its sum."""
    if not _READING:
        drop, rmap, problem = None, None, None
        text = globals().get("_READING_TABLE")
        if not isinstance(text, str):
            problem = "no table"
        elif hashlib.sha256(text.encode("utf-8")).hexdigest() != READING_TABLE_SHA256:
            problem = "its sha256 is not READING_TABLE_SHA256"
        else:
            ranges, rmap = [], {}
            try:
                for ln in text.splitlines():
                    f = ln.split("\t")
                    if ln.startswith("#"):
                        continue
                    if f[0] == "D" and len(f) == 3:
                        ranges.append("%s-%s" % (re.escape(chr(int(f[1], 16))), re.escape(chr(int(f[2], 16)))))
                    elif f[0] == "R" and len(f) == 3:
                        rmap[int(f[1], 16)] = "".join(chr(int(x, 16)) for x in f[2].split(" ") if x)
                    else:
                        raise ValueError(ln[:40])
                drop = re.compile("[%s]" % "".join(ranges))
            except ValueError as exc:
                drop, rmap, problem = None, None, "a line cannot be read: %s" % exc
        _READING.append((drop, rmap, problem))
    return _READING[0]


def fold(s):
    """S read as a person reads it (round 8, review r7 F2 and F4): character references decoded, then every character
    replaced by its reading from the reading table (scripts/validation/pvl_reading_table.py THE READING: default-
    ignorable code points, marks, format, unassigned, private-use and control characters are read as nothing; a
    character is decomposed with NFKD and its parts read through the Unicode UTS #39 confusable skeleton and case
    folding; an ASCII character is read as itself in lower case). One fold decides every "reads as": the label (THE
    NEAR RULE) and the status (status_key). Without an intact table the run is BLIND (reader_problem)."""
    drop, rmap, _problem = _reading()
    t = html.unescape(s)
    if drop is None:
        return t.casefold()
    return drop.sub("", t).translate(rmap)


def has_label(s):
    """True when S, read as fold() reads it, holds the word Verification followed by a colon (markup or spaces may
    stand before the colon)."""
    return LABEL.search(fold(s)) is not None


def _is_label_start(ch):
    """True when the inline tokens CH (empty text removed) start with strong_open, text `Verification:`, strong_close."""
    return (len(ch) >= 3 and ch[0].type == "strong_open" and ch[1].type == "text" and ch[1].content == "Verification:"
            and ch[2].type == "strong_close")


def _rendered(children):
    """The text a reader renders from inline CHILDREN (markup removed, so `Veri*fi*cation:` reads as the word), with
    every attribute value (link targets and titles, image text)."""
    out = []
    for c in children:
        if c.type in ("text", "code_inline"):
            out.append(c.content)
        elif c.type in ("softbreak", "hardbreak"):
            out.append("\n")
        for _k, v in (c.attrs or {}).items():
            out.append("\n%s\n" % v)
        if c.children:
            out.append(_rendered(c.children))
    return "".join(out)


def _raw_html(tokens, out):
    """Every raw HTML token of TOKENS, at any depth (round 8, review r7 F5: also in image text and link text)."""
    for t in tokens:
        if t.type in ("html_block", "html_inline"):
            out.append(t.content)
        if t.children:
            _raw_html(t.children, out)


def _read(body, lines, reader):
    """One reading of BODY: (counted, texts, raw, exact, footnotes). COUNTED: (source line index, line) of each top-level
    paragraph that starts with the bold label and whose first source line starts with the prefix at column 0. TEXTS:
    the text a reader renders anywhere else (and the counted line after its label). RAW: the raw HTML tokens. EXACT:
    the counted lines a reader does not show exactly as written (round 8: the paragraph must be that one source line,
    and the text the reader renders after the label must equal the rest of that source line). FOOTNOTES: link reference labels that
    start with `^` (a GFM footnote definition; CommonMark reads it as a link reference)."""
    env = {}
    toks = _md(reader).parse(body, env)
    counted, texts, raw, exact = [], [], [], []
    _raw_html(toks, raw)
    for i, t in enumerate(toks):
        if t.type == "inline":
            prev = toks[i - 1]
            ch = [c for c in t.children or [] if not (c.type == "text" and c.content == "")]
            ln = lines[prev.map[0]] if prev.map is not None else ""
            if (prev.type == "paragraph_open" and prev.level == 0 and prev.map is not None and _is_label_start(ch)
                    and ln.startswith(PREFIX) and (len(ln) == len(PREFIX) or ln[len(PREFIX)] in " (")):
                counted.append((prev.map[0], ln))
                shown = _rendered(ch[3:])
                if not (prev.map[1] == prev.map[0] + 1 and shown == ln[len(BOLD_LABEL):]):
                    exact.append((prev.map[0], prev.map[1] - prev.map[0], [c.type for c in ch[3:6]]))
                texts.append(shown)
            else:
                texts.append(_rendered(t.children or []))
        elif t.type in ("code_block", "fence"):
            texts.append(t.info + "\n" + t.content)
        for _k, v in (t.attrs or {}).items():
            texts.append(v)
    footnotes = sorted(k for k in env.get("references", {}) if k.startswith("^"))
    return counted, texts, raw, exact, footnotes


def scan(body):
    """(counted, problems): the counted lines of BODY (the CommonMark reading) and the reasons it cannot be judged,
    each `KIND: detail` with KIND raw-html, footnote, gfm, exact or label (see THE LINE MODEL). The caller checks
    reader_problem() first."""
    lines = _MDIT_NULL.sub("\ufffd", _MDIT_NEWLINES.sub("\n", body)).split("\n")
    problems = []
    readings = {r: _read(body, lines, r) for r in READERS}
    for r in READERS:
        counted, texts, raw, exact, footnotes = readings[r]
        problems += ["raw-html: %r" % x.strip()[:40] for x in raw]
        problems += ["footnote: [%s]" % k[:40] for k in footnotes]
        problems += ["exact: line %d (%s reading: %d source lines, tokens %s)" % (j + 1, r, n, ",".join(ty))
                     for j, n, ty in exact]
    c_cm = [j for j, _ in readings["commonmark"][0]]
    c_gfm = [j for j, _ in readings["gfm"][0]]
    if c_cm != c_gfm:
        problems.append("gfm: the GFM reading counts lines %s, CommonMark %s" % (
            [j + 1 for j in c_gfm][:5], [j + 1 for j in c_cm][:5]))
    keep = set(c_cm)
    if has_label("\n".join(ln for j, ln in enumerate(lines) if j not in keep)):
        problems.append("label: label in another source line")
    elif any(has_label(x) for r in READERS for x in readings[r][1]):
        problems.append("label: label in the rendered text")
    return [ln for _, ln in readings["commonmark"][0]], problems


def visible_lines(body):
    """The lines of BODY that count (see THE LINE MODEL); [] when the parser is unavailable."""
    if reader_problem() is not None or not isinstance(body, str):
        return []
    return scan(body)[0]


def char_reason(v, where):
    """The reason for the first character of V outside printable ASCII, or None."""
    for ch in v:
        if not (" " <= ch <= "~"):
            o = ord(ch)
            name = unicodedata.name(ch, "unnamed")
            extra = ", a look-alike of %s" % CONFUSABLES[ch] if ch in CONFUSABLES else ""
            return "holds U+%04X %s outside the ASCII grammar of %s%s" % (o, name, where, extra)
    return None


class Context:
    """What the grammar resolves against: the root, the database items, the item, the dates, the target registry."""

    def __init__(self, root, items=None, item_id=None, created=None, today=None, window=DEFAULT_WINDOW,
                 targets=None):
        self.root = os.path.realpath(os.path.abspath(root)) if root is not None else None
        self.items = items or {}
        self.item_id = item_id
        self.created = created
        self.today = today or datetime.datetime.now(datetime.timezone.utc).date()
        self.window = window
        self.targets = targets  # None: no registry; else a set of (kind, id)
        self._text = {}

    def resolve(self, rel, want_file):
        """The real path of REL under the root (a regular file when WANT_FILE), or None."""
        if self.root is None:
            return None
        if rel == ".":
            return None if want_file else self.root
        if not PATH_RE.fullmatch(rel) or any(p in (".", "..") for p in rel.split("/")):
            return None
        p = os.path.realpath(os.path.join(self.root, rel))
        if p == self.root or os.path.commonpath([self.root, p]) != self.root:
            return None
        if want_file:
            return p if os.path.isfile(p) else None
        return p if os.path.exists(p) else None

    def text(self, real):
        if real not in self._text:
            try:
                with open(real, "rb") as fh:
                    self._text[real] = fh.read(MAX_SCRIPT_BYTES).decode("utf-8", "replace")
            except OSError:
                self._text[real] = ""
        return self._text[real]

    def occurs(self, real, word):
        return re.search(r"(?<![A-Za-z0-9_.-])%s(?![A-Za-z0-9_.-])" % re.escape(word), self.text(real)) is not None


def val_ok(ctx, script, v):
    return bool(INT_RE.fullmatch(v) or ctx.resolve(v, False) or (WORD_RE.fullmatch(v) and ctx.occurs(script, v)))


def job_problem(v, ctx):
    """None when V is a JOB sentence; else the reason. ctx.subjects is set to the job's subjects."""
    ctx.subjects = set()
    if ID_RE.fullmatch(v):
        st = ctx.items.get(v)
        if v == ctx.item_id:
            return "names the item itself (%s), not a job" % v
        if st is None:
            return "names %s, which is not an item of this database" % v
        if st not in OPEN_STATUSES:
            return "names %s, whose Status %s is not an open job (%s)" % (v, st, ", ".join(OPEN_STATUSES))
        ctx.subjects.add(v)
        return None
    if ctx.root is None:
        return "cannot be resolved: no root"
    for inv in v.split("; "):
        toks = inv.split(" ")
        if "" in toks:
            return "holds an empty word (two spaces, or a space at an edge): %r" % inv[:60]
        env = []
        while toks and ENV_RE.fullmatch(toks[0]):
            env.append(toks.pop(0))
        if not toks or toks[0] not in RUNNERS:
            return "does not start an invocation with a runner (%s, then a script): %r" % (
                ", ".join(("bash", "sh", "python3", "python3 -I")), inv[:60])
        runner = toks.pop(0)
        if runner == "python3" and toks[:1] == ["-I"]:
            toks.pop(0)
        if not toks:
            return "names no script after %s" % runner
        script = toks.pop(0)
        real = ctx.resolve(script, True)
        if not real:
            return "names a script that is not a regular file under the root: %s" % script[:80]
        if not script.endswith(RUNNERS[runner]):
            return "runs %s with %s, which does not end %s" % (runner, script[:80], " or ".join(RUNNERS[runner]))
        ctx.subjects.add(script)
        for e in env:
            name, val = ENV_RE.fullmatch(e).groups()
            if not ctx.occurs(real, name) or not val_ok(ctx, real, val):
                return "sets %s, which %s does not use with that value" % (e[:60], script[:60])
        for a in toks:
            if INT_RE.fullmatch(a):
                continue
            if a.startswith("-"):
                m = OPTION_RE.fullmatch(a)
                if not m or not ctx.occurs(real, m.group(1)) or (m.group(2) is not None and not val_ok(ctx, real, m.group(2))):
                    return "passes %s, which is not an option of %s" % (a[:60], script[:60])
                continue
            if ctx.resolve(a, False):
                continue
            if "/" in a or a.startswith("."):
                return "passes the path %s, which does not exist under the root" % a[:80]
            if not (SELECTOR_RE.fullmatch(a) and ctx.occurs(real, a)):
                return "passes %s, which is not an integer, an option, a path or a selector %s names" % (a[:60], script[:60])
            ctx.subjects.add(a)
    return None


def checks_problem(v, ctx):
    subjects = getattr(ctx, "subjects", set())
    for res in v.split("; "):
        toks = res.split(" ")
        if "" in toks:
            return "holds an empty word: %r" % res[:60]
        if len(toks) < 2:
            return "has a result with no outcome: %r (SUBJECT KEY=VALUE ...)" % res[:60]
        if toks[0] not in subjects:
            return "names %s, which is not a script or selector of the job" % toks[0][:80]
        keys = set()
        for t in toks[1:]:
            m = TERM_RE.fullmatch(t)
            if not m:
                return "has %s, which is not KEY=VALUE with KEY in pass fail skip killed survived rc verdict" % t[:60]
            k, val = m.groups()
            if k in keys:
                return "repeats %s in one result" % k
            keys.add(k)
            if k == "verdict":
                if val not in VERDICTS:
                    return "has verdict=%s (one of %s)" % (val[:20], ", ".join(VERDICTS))
            elif not INT_RE.fullmatch(val) or (k == "rc" and int(val) > 255):
                return "has %s=%s, which is not a count%s" % (k, val[:20], " 0..255" if k == "rc" else "")
        if not keys & set(COUNT_KEYS):
            return "has a result with no count (one of %s)" % ", ".join(COUNT_KEYS)
    return None


def layer_problem(v, ctx):
    words = v.split(" plus ")
    for w in words:
        if w not in LAYER_VOCAB:
            return "has %r, which is not one of %s" % (w[:40], ", ".join(LAYER_VOCAB))
    if len(set(words)) != len(words):
        return "names a layer twice"
    return None


def target_problem(v, ctx):
    terms = v.split(", ")
    for t in terms:
        if t in TARGET_FIXED:
            continue
        m = REMOTE_RE.fullmatch(t)
        if m:
            if not ctx.resolve("upstreams/%s.sh" % m.group(1), True):
                return "names remote %s, which has no upstreams/%s.sh under the root" % (m.group(1), m.group(1))
            continue
        m = KIND_RE.fullmatch(t)
        if m:
            if ctx.targets is None:
                return "names %s, but there is no target registry to resolve it" % t[:60]
            if (m.group(1), m.group(2)) not in ctx.targets:
                return "names %s, which is not in the target registry" % t[:60]
            continue
        return "has %r, which is not a target term (%s, remote NAME, %s ID)" % (
            t[:40], ", ".join(TARGET_FIXED), "|".join(TARGET_KINDS))
    if len(set(terms)) != len(terms):
        return "names a target twice"
    return None


def artifact_problem(v, ctx):
    terms = v.split(", ")
    for t in terms:
        if not ATERM_RE.fullmatch(t):
            return "has %r, which is not main, main@HEX, commit HEX, merge HEX or tag TAG" % t[:40]
    if len(set(terms)) != len(terms):
        return "names an artifact twice"
    return None


def due_problem(v, ctx):
    m = DUE_RE.fullmatch(v)
    if not m:
        return "is not YYYY-MM-DD[THH:MM[:SS][Z|+HH:MM]]: %r" % v[:40]
    try:
        d = datetime.date(int(m.group(1)), int(m.group(2)), int(m.group(3)))
        if m.group(4) is not None:
            # the closed ranges (round 6, review r5 M-3): hour 0..23, minute and second 0..59, an offset of at most
            # 23:59. DUE_RE fixes the shape and datetime.date checks the date, so these ranges are the whole time
            # check; the r5 datetime.fromisoformat call was removed as redundant (some Python versions accept hour 24)
            off = m.group(7)
            if int(m.group(4)) > 23 or int(m.group(5)) > 59 or int(m.group(6) or 0) > 59 or (
                    off not in (None, "Z") and (int(off[1:3]) > 23 or int(off[4:6]) > 59)):
                raise ValueError(v)
    except ValueError:
        return "is not a real date and time: %s" % v[:40]
    if ctx.created is None:
        return "cannot be checked: the item has no created date"
    if d < ctx.created:
        return "is %s, before the item was created (%s)" % (d, ctx.created)
    last = ctx.today + datetime.timedelta(days=ctx.window)
    if d > last:
        return "is %s, after today plus the window (%s, %d days)" % (d, last, ctx.window)
    return None


FIELD_CHECK = {"job": job_problem, "checks": checks_problem, "layer": layer_problem, "target": target_problem,
               "artifact": artifact_problem, "due": due_problem}


def field_problem(key, raw, root=None, ctx=None):
    """Return None when the value RAW of field KEY is a sentence of its grammar, else the reason."""
    if ctx is None:
        ctx = Context(root)
    if not raw:
        return "is empty"
    bad = char_reason(raw, key)
    if bad:
        return bad
    return FIELD_CHECK[key](raw, ctx)


def note_problem(raw):
    """None when RAW is a NOTE value (printable ASCII holding a letter or digit), else the reason."""
    return char_reason(raw, "note") or (None if re.search(r"[A-Za-z0-9]", raw) else "holds no letter or digit")


def check_line(line, ctx):
    if len(line) > MAX_LINE:
        return "the verification line is longer than %d characters (%d)" % (MAX_LINE, len(line))
    if not line.startswith(PREFIX):
        return "the line does not start with %r" % PREFIX
    rest = line[len(PREFIX):]
    if rest.startswith(SECTION):
        rest = rest[len(SECTION):]
    parts = SEP.split(rest, maxsplit=7)
    if parts[0] != "":
        return "text between the prefix and the first field: %r" % parts[0][:60]
    parts = parts[1:]
    names, values = [], []
    for p in parts:
        m = FIELD_PART.match(p)
        if not m:
            return "a part is not NAME: VALUE or NAME VALUE: %r" % p[:60]
        names.append(m.group(1))
        values.append(m.group(2))
    if names[:6] != list(FIELDS):
        return "the fields are not job, checks, layer, target, artifact, due in that order: %s" % ", ".join(names)
    if len(names) == 7 and names[6] != "note":
        return "a part after due is not a note: %s" % names[6]
    for k, v in zip(FIELDS, values):
        problem = field_problem(k, v, ctx=ctx)
        if problem:
            return "field '%s' %s" % (k, problem)
    if len(names) == 7:
        problem = note_problem(values[6])
        if problem:
            return "field 'note' %s" % problem
    return None


def check_body(body, root=None, ctx=None):
    """Return None when the body carries exactly one verification line that is a sentence of the grammar."""
    if ctx is None:
        ctx = Context(root)
    if not isinstance(body, str):
        return "the body is not text (%s)" % type(body).__name__
    rp = reader_problem()
    if rp:
        return "the CommonMark reader is unavailable: %s" % rp
    if len(body) > MAX_BODY:
        return "the body is longer than %d characters (%d)" % (MAX_BODY, len(body))
    lines, problems = scan(body)
    kinds = {}
    for p in problems:
        kinds.setdefault(p.split(":", 1)[0], p.split(": ", 1)[1])
    if "raw-html" in kinds:
        return ("the body holds raw HTML (%s; HTML comments too): a reader may hide or wrap a line with it, so which "
                "lines are visible is not certain; write a placeholder such as <name> inside backticks (`<name>`) so a "
                "reader shows it as text" % kinds["raw-html"])
    if "footnote" in kinds:
        return ("the body holds a GFM footnote definition %s: a GFM reader moves text into a footnote, so which lines "
                "are visible is not certain" % kinds["footnote"])
    if "exact" in kinds:
        return ("a reader does not show the verification line exactly as written (%s): the line must be a paragraph of "
                "its own, one source line with no markup, character reference or escape after the label"
                % kinds["exact"])
    if "gfm" in kinds:
        return "the GFM reading and the CommonMark reading differ (%s)" % kinds["gfm"]
    if problems:
        return ("a line a reader shows carries the Verification label but is not the one counted line (the label "
                "occurs outside the start of the one top-level paragraph that starts with the prefix at column 0: %s)"
                % kinds.get("label", problems[0]))
    if not lines:
        return "no '**Verification:** provisional' line"
    if len(lines) > 1:
        return "%d verification lines (one expected)" % len(lines)
    return check_line(lines[0], ctx)


def parse_date(s):
    m = re.match(r"([0-9]{4})-([0-9]{2})-([0-9]{2})", s or "")
    if not m:
        return None
    try:
        return datetime.date(int(m.group(1)), int(m.group(2)), int(m.group(3)))
    except ValueError:
        return None


class RegistryError(Exception):
    """The target registry exists but cannot be read as UTF-8 text."""


def load_targets(path):
    """The target registry: a set of (kind, id) from KIND<TAB>ID lines ('#' comments); None when absent. A registry that
    cannot be read or decoded raises RegistryError (the caller reports BLIND: an unreadable registry proves nothing)."""
    if not os.path.isfile(path):
        return None
    out = set()
    try:
        with open(path, "rb") as fh:
            text = fh.read().decode("utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        raise RegistryError("%s (%s)" % (path, exc.__class__.__name__)) from None
    for ln in LINE_END.split(text):  # the line endings text mode read before (universal newlines)
        if not ln or ln.startswith("#"):
            continue
        k, _, i = ln.partition("\t")
        if k in TARGET_KINDS and KIND_RE.fullmatch("%s %s" % (k, i)):
            out.add((k, i))
    return out


DB_SUFFIXES = ("", "-wal", "-journal")
MAX_DB_BYTES = 1 << 30   # the copy bound (all files together); a larger database is reported BLIND


class NotRegular(Exception):
    """A database file or sidecar is not a regular file (a FIFO, a device, a directory): never read, BLIND."""


def _stats(db):
    out = {}
    for suf in DB_SUFFIXES:
        try:
            st = os.stat(db + suf)
            out[suf] = (st.st_ino, st.st_size, st.st_mtime_ns, stat.S_IFMT(st.st_mode))
        except FileNotFoundError:
            out[suf] = None
    return out


def _copy_regular(path, dst, budget):
    """Copy the regular file PATH to DST, reading at most BUDGET bytes; return the bytes read. The file is opened
    without blocking (a FIFO would block a plain open) and checked to be regular on the open descriptor (review r6
    M-1: a -wal symlink to /dev/zero or a FIFO -journal hung the r6 copy)."""
    fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | getattr(os, "O_NOCTTY", 0) | getattr(os, "O_CLOEXEC", 0))
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):
            raise NotRegular(path)
        n = 0
        with open(dst, "wb") as out:
            while True:
                chunk = os.read(fd, 1 << 20)
                if not chunk:
                    return n
                n += len(chunk)
                if n > budget:
                    raise OverflowError(path)
                out.write(chunk)
    finally:
        os.close(fd)


def snapshot_db(db, tmp):
    """Copy the database file and its -wal and -journal files (when present) into the private directory TMP and return
    the copy's path; the original is only read as bytes, never opened by SQLite, so no -wal or -shm is ever created next
    to it (review r5 M-1: a read-only SQLite open of a WAL database creates them). DB is resolved to its real path
    first: SQLite keeps the -wal next to a symlink's target, so copying `<link>-wal` would miss committed rows (review
    r6 I-3). A copy taken while a file changed is retried; after five tries the database is reported as changing
    (BLIND). Raises NotRegular for a file that is not regular and OverflowError past MAX_DB_BYTES."""
    db = os.path.realpath(db)
    dst = os.path.join(tmp, "items.db")
    for _ in range(5):
        before = _stats(db)
        budget = MAX_DB_BYTES
        for suf in DB_SUFFIXES:
            if os.path.exists(dst + suf):
                os.remove(dst + suf)
            if before[suf] is not None:
                budget -= _copy_regular(db + suf, dst + suf, budget)
        if _stats(db) == before:
            return dst
        time.sleep(0.1)
    return None


def status_key(st):
    """The status as a person reads it: bytes decoded, read with fold() (the same reading as the label, round 8: a
    variation selector or a combining grapheme joiner inside a status no longer hides it), runs of white space made one
    space, outer white space removed."""
    if isinstance(st, (bytes, bytearray)):
        st = bytes(st).decode("utf-8", "replace")
    if not isinstance(st, str):
        return None
    return " ".join(fold(st).split())


def blind(msg):
    print("BLIND %s" % msg)
    print("VERDICT: BLIND")
    return 2


def usage(msg):
    sys.stderr.write("check_provisional_verification_lines.py: %s\nusage: check_provisional_verification_lines.py "
                     "[--root DIR] [--targets FILE] [--today YYYY-MM-DD] [--due-window-days N] [DB]\n" % msg)
    return 64


def main(argv):
    args = list(argv[1:])
    opts = {"--root": ".", "--targets": None, "--today": None, "--due-window-days": str(DEFAULT_WINDOW)}
    db = None
    while args:
        a = args.pop(0)
        if a in opts:
            if not args:
                return usage("%s needs a value" % a)
            opts[a] = args.pop(0)
        elif a.startswith("-") or db is not None:
            return usage("unexpected argument %s" % a)
        else:
            db = a
    db = db or "docs/workable_items.db"
    if not os.path.isdir(opts["--root"]):
        return usage("--root %s is not a directory" % opts["--root"])
    today = None
    if opts["--today"] is not None:
        today = parse_date(opts["--today"])
        if today is None or opts["--today"] != str(today):
            return usage("--today %s is not a date" % opts["--today"])
    w = opts["--due-window-days"]
    if not INT_RE.fullmatch(w) or int(w) > 3650:
        return usage("--due-window-days %s is not 0..3650" % w)
    root = os.path.realpath(os.path.abspath(opts["--root"]))
    try:
        targets = load_targets(opts["--targets"] or os.path.join(root, "config", "verification_targets.tsv"))
    except RegistryError as exc:
        return blind("the target registry cannot be read as UTF-8 text: %s" % exc)
    rp = reader_problem()
    if rp:
        return blind("the CommonMark reader is unavailable: %s" % rp)
    if not os.path.exists(db):
        return blind("the database cannot be read (no such file)")
    with tempfile.TemporaryDirectory(prefix="pvl_db.") as tmp:
        try:
            copy = snapshot_db(os.path.abspath(db), tmp)
        except NotRegular as exc:
            return blind("the database cannot be read: %s is not a regular file" % exc)
        except OverflowError as exc:
            return blind("the database cannot be read: the copy passed %d bytes at %s" % (MAX_DB_BYTES, exc))
        except OSError as exc:
            return blind("the database cannot be read (%s)" % exc.__class__.__name__)
        if copy is None:
            return blind("the database changed during five copies; it cannot be read consistently")
        try:
            con = sqlite3.connect(pathlib.Path(copy).as_uri(), uri=True)
            try:
                total = con.execute("select count(*) from items").fetchone()[0]
                cols = [r[1] for r in con.execute("pragma table_info(items)")]
                created_col = "created_at" if "created_at" in cols else "NULL"
                items = dict(con.execute("select atm_id, status from items").fetchall())
                allrows = con.execute("select atm_id, status, body_md, %s from items order by atm_id"
                                      % created_col).fetchall()
            finally:
                con.close()
        except sqlite3.Error as exc:
            return blind("the database cannot be read (%s)" % exc.__class__.__name__)
    if total == 0:
        return blind("the items table holds no items")
    rows = [r for r in allrows if status_key(r[1]) in PROVISIONAL_KEYS]
    fails = 0
    for atm_id, status, body, created in rows:
        exact = PROVISIONAL_KEYS[status_key(status)]
        if status != exact:
            reason = "the Status %r is not written exactly as %r (it reads as a provisional status)" % (status, exact)
        elif created is not None and not isinstance(created, str):
            reason = "the created date is not text (%s)" % type(created).__name__
        else:
            ctx = Context(root, items, atm_id, parse_date(created), today, int(w), targets)
            reason = check_body(body, ctx=ctx)
        if reason:
            fails += 1
            print("FAIL %s %s: %s" % (atm_id, status, reason))
    ctx = Context(root, today=today)
    print("ROOT: %s" % root)
    print("TODAY: %s window=%sd" % (ctx.today, w))
    print("CHECKED items=%d provisional_status=%d ok=%d fail=%d" % (total, len(rows), len(rows) - fails, fails))
    print("VERDICT: %s" % ("FAIL" if fails else "PASS"))
    return 1 if fails else 0


def run(argv):
    """main with a last net: an unexpected error is reported as BLIND with its class, never as a traceback and never as
    a pass (section 11.4.201(4)); every expected refusal is decided before this net (review r5 M-2)."""
    try:
        return main(argv)
    except Exception as exc:  # noqa: BLE001
        return blind("internal error %s: %s" % (exc.__class__.__name__, str(exc)[:200]))


# THE READING TABLE (round 8): how a person reads a character, built from ICU by scripts/validation/pvl_reading_table.py
# (--write puts it here, --check compares it with a fresh build). Do not edit by hand: the sum is checked at every run
# and a table that does not match it makes the run BLIND. Lines: D FIRST LAST (a range read as nothing), R CP HEX...
# (the reading of CP, ASCII code points in hex).
READING_TABLE_SHA256 = "02a3ad6a0fc3ce69ca645e687d8c6da9d59e48e674dd6119df7d1d04652f47c7"
# BEGIN READING TABLE
_READING_TABLE = """\
# pvl reading table: icu 78.2 unicode 17.0; built by scripts/validation/pvl_reading_table.py; do not edit
D	0000	0008
D	000E	001F
D	007F	0084
D	0086	009F
D	00AD	00AD
D	0300	036F
D	0378	0379
D	0380	0383
D	038B	038B
D	038D	038D
D	03A2	03A2
D	0483	0489
D	0530	0530
D	0557	0558
D	058B	058C
D	0590	05BD
D	05BF	05BF
D	05C1	05C2
D	05C4	05C5
D	05C7	05CF
D	05EB	05EE
D	05F5	0605
D	0610	061A
D	061C	061C
D	064B	065F
D	0670	0670
D	06D6	06DD
D	06DF	06E4
D	06E7	06E8
D	06EA	06ED
D	070E	070F
D	0711	0711
D	0730	074C
D	07A6	07B0
D	07B2	07BF
D	07EB	07F3
D	07FB	07FD
D	0816	0819
D	081B	0823
D	0825	0827
D	0829	082F
D	083F	083F
D	0859	085D
D	085F	085F
D	086B	086F
D	0890	089F
D	08CA	0903
D	093A	093C
D	093E	094F
D	0951	0957
D	0962	0963
D	0981	0984
D	098D	098E
D	0991	0992
D	09A9	09A9
D	09B1	09B1
D	09B3	09B5
D	09BA	09BC
D	09BE	09CD
D	09CF	09DB
D	09DE	09DE
D	09E2	09E5
D	09FE	0A04
D	0A0B	0A0E
D	0A11	0A12
D	0A29	0A29
D	0A31	0A31
D	0A34	0A34
D	0A37	0A37
D	0A3A	0A58
D	0A5D	0A5D
D	0A5F	0A65
D	0A70	0A71
D	0A75	0A75
D	0A77	0A84
D	0A8E	0A8E
D	0A92	0A92
D	0AA9	0AA9
D	0AB1	0AB1
D	0AB4	0AB4
D	0ABA	0ABC
D	0ABE	0ACF
D	0AD1	0ADF
D	0AE2	0AE5
D	0AF2	0AF8
D	0AFA	0B04
D	0B0D	0B0E
D	0B11	0B12
D	0B29	0B29
D	0B31	0B31
D	0B34	0B34
D	0B3A	0B3C
D	0B3E	0B5B
D	0B5E	0B5E
D	0B62	0B65
D	0B78	0B82
D	0B84	0B84
D	0B8B	0B8D
D	0B91	0B91
D	0B96	0B98
D	0B9B	0B9B
D	0B9D	0B9D
D	0BA0	0BA2
D	0BA5	0BA7
D	0BAB	0BAD
D	0BBA	0BCF
D	0BD1	0BE5
D	0BFB	0C04
D	0C0D	0C0D
D	0C11	0C11
D	0C29	0C29
D	0C3A	0C3C
D	0C3E	0C57
D	0C5B	0C5B
D	0C5E	0C5F
D	0C62	0C65
D	0C70	0C76
D	0C81	0C83
D	0C8D	0C8D
D	0C91	0C91
D	0CA9	0CA9
D	0CB4	0CB4
D	0CBA	0CBC
D	0CBE	0CDB
D	0CDF	0CDF
D	0CE2	0CE5
D	0CF0	0CF0
D	0CF3	0D03
D	0D0D	0D0D
D	0D11	0D11
D	0D3B	0D3C
D	0D3E	0D4D
D	0D50	0D53
D	0D57	0D57
D	0D62	0D65
D	0D80	0D84
D	0D97	0D99
D	0DB2	0DB2
D	0DBC	0DBC
D	0DBE	0DBF
D	0DC7	0DE5
D	0DF0	0DF3
D	0DF5	0E00
D	0E31	0E31
D	0E34	0E3E
D	0E47	0E4E
D	0E5C	0E80
D	0E83	0E83
D	0E85	0E85
D	0E8B	0E8B
D	0EA4	0EA4
D	0EA6	0EA6
D	0EB1	0EB1
D	0EB4	0EBC
D	0EBE	0EBF
D	0EC5	0EC5
D	0EC7	0ECF
D	0EDA	0EDB
D	0EE0	0EFF
D	0F18	0F19
D	0F35	0F35
D	0F37	0F37
D	0F39	0F39
D	0F3E	0F3F
D	0F48	0F48
D	0F6D	0F84
D	0F86	0F87
D	0F8D	0FBD
D	0FC6	0FC6
D	0FCD	0FCD
D	0FDB	0FFF
D	102B	103E
D	1056	1059
D	105E	1060
D	1062	1064
D	1067	106D
D	1071	1074
D	1082	108D
D	108F	108F
D	109A	109D
D	10C6	10C6
D	10C8	10CC
D	10CE	10CF
D	115F	1160
D	1249	1249
D	124E	124F
D	1257	1257
D	1259	1259
D	125E	125F
D	1289	1289
D	128E	128F
D	12B1	12B1
D	12B6	12B7
D	12BF	12BF
D	12C1	12C1
D	12C6	12C7
D	12D7	12D7
D	1311	1311
D	1316	1317
D	135B	135F
D	137D	137F
D	139A	139F
D	13F6	13F7
D	13FE	13FF
D	169D	169F
D	16F9	16FF
D	1712	171E
D	1732	1734
D	1737	173F
D	1752	175F
D	176D	176D
D	1771	177F
D	17B4	17D3
D	17DD	17DF
D	17EA	17EF
D	17FA	17FF
D	180B	180F
D	181A	181F
D	1879	187F
D	1885	1886
D	18A9	18A9
D	18AB	18AF
D	18F6	18FF
D	191F	193F
D	1941	1943
D	196E	196F
D	1975	197F
D	19AC	19AF
D	19CA	19CF
D	19DB	19DD
D	1A17	1A1D
D	1A55	1A7F
D	1A8A	1A8F
D	1A9A	1A9F
D	1AAE	1B04
D	1B34	1B44
D	1B4D	1B4D
D	1B6B	1B73
D	1B80	1B82
D	1BA1	1BAD
D	1BE6	1BFB
D	1C24	1C3A
D	1C4A	1C4C
D	1C8B	1C8F
D	1CBB	1CBC
D	1CC8	1CD2
D	1CD4	1CE8
D	1CED	1CED
D	1CF4	1CF4
D	1CF7	1CF9
D	1CFB	1CFF
D	1DC0	1DFF
D	1F16	1F17
D	1F1E	1F1F
D	1F46	1F47
D	1F4E	1F4F
D	1F58	1F58
D	1F5A	1F5A
D	1F5C	1F5C
D	1F5E	1F5E
D	1F7E	1F7F
D	1FB5	1FB5
D	1FC5	1FC5
D	1FD4	1FD5
D	1FDC	1FDC
D	1FF0	1FF1
D	1FF5	1FF5
D	1FFF	1FFF
D	200B	200F
D	202A	202E
D	2060	206F
D	2072	2073
D	208F	208F
D	209D	209F
D	20C2	20FF
D	218C	218F
D	242A	243F
D	244B	245F
D	2B74	2B75
D	2CEF	2CF1
D	2CF4	2CF8
D	2D26	2D26
D	2D28	2D2C
D	2D2E	2D2F
D	2D68	2D6E
D	2D71	2D7F
D	2D97	2D9F
D	2DA7	2DA7
D	2DAF	2DAF
D	2DB7	2DB7
D	2DBF	2DBF
D	2DC7	2DC7
D	2DCF	2DCF
D	2DD7	2DD7
D	2DDF	2DFF
D	2E5E	2E7F
D	2E9A	2E9A
D	2EF4	2EFF
D	2FD6	2FEF
D	302A	302F
D	3040	3040
D	3097	309A
D	3100	3104
D	3130	3130
D	3164	3164
D	318F	318F
D	31E6	31EE
D	321F	321F
D	A48D	A48F
D	A4C7	A4CF
D	A62C	A63F
D	A66F	A672
D	A674	A67D
D	A69E	A69F
D	A6F0	A6F1
D	A6F8	A6FF
D	A7DD	A7F0
D	A802	A802
D	A806	A806
D	A80B	A80B
D	A823	A827
D	A82C	A82F
D	A83A	A83F
D	A878	A881
D	A8B4	A8CD
D	A8DA	A8F1
D	A8FF	A8FF
D	A926	A92D
D	A947	A95E
D	A97D	A983
D	A9B3	A9C0
D	A9CE	A9CE
D	A9DA	A9DD
D	A9E5	A9E5
D	A9FF	A9FF
D	AA29	AA3F
D	AA43	AA43
D	AA4C	AA4F
D	AA5A	AA5B
D	AA7B	AA7D
D	AAB0	AAB0
D	AAB2	AAB4
D	AAB7	AAB8
D	AABE	AABF
D	AAC1	AAC1
D	AAC3	AADA
D	AAEB	AAEF
D	AAF5	AB00
D	AB07	AB08
D	AB0F	AB10
D	AB17	AB1F
D	AB27	AB27
D	AB2F	AB2F
D	AB6C	AB6F
D	ABE3	ABEA
D	ABEC	ABEF
D	ABFA	ABFF
D	D7A4	D7AF
D	D7C7	D7CA
D	D7FC	F8FF
D	FA6E	FA6F
D	FADA	FAFF
D	FB07	FB12
D	FB18	FB1C
D	FB1E	FB1E
D	FB37	FB37
D	FB3D	FB3D
D	FB3F	FB3F
D	FB42	FB42
D	FB45	FB45
D	FDD0	FDEF
D	FE00	FE0F
D	FE1A	FE2F
D	FE53	FE53
D	FE67	FE67
D	FE6C	FE6F
D	FE75	FE75
D	FEFD	FF00
D	FFA0	FFA0
D	FFBF	FFC1
D	FFC8	FFC9
D	FFD0	FFD1
D	FFD8	FFD9
D	FFDD	FFDF
D	FFE7	FFE7
D	FFEF	FFFB
D	FFFE	FFFF
D	1000C	1000C
D	10027	10027
D	1003B	1003B
D	1003E	1003E
D	1004E	1004F
D	1005E	1007F
D	100FB	100FF
D	10103	10106
D	10134	10136
D	1018F	1018F
D	1019D	1019F
D	101A1	101CF
D	101FD	1027F
D	1029D	1029F
D	102D1	102E0
D	102FC	102FF
D	10324	1032C
D	1034B	1034F
D	10376	1037F
D	1039E	1039E
D	103C4	103C7
D	103D6	103FF
D	1049E	1049F
D	104AA	104AF
D	104D4	104D7
D	104FC	104FF
D	10528	1052F
D	10564	1056E
D	1057B	1057B
D	1058B	1058B
D	10593	10593
D	10596	10596
D	105A2	105A2
D	105B2	105B2
D	105BA	105BA
D	105BD	105BF
D	105F4	105FF
D	10737	1073F
D	10756	1075F
D	10768	1077F
D	10786	10786
D	107B1	107B1
D	107BB	107FF
D	10806	10807
D	10809	10809
D	10836	10836
D	10839	1083B
D	1083D	1083E
D	10856	10856
D	1089F	108A6
D	108B0	108DF
D	108F3	108F3
D	108F6	108FA
D	1091C	1091E
D	1093A	1093E
D	1095A	1097F
D	109B8	109BB
D	109D0	109D1
D	10A01	10A0F
D	10A14	10A14
D	10A18	10A18
D	10A36	10A3F
D	10A49	10A4F
D	10A59	10A5F
D	10AA0	10ABF
D	10AE5	10AEA
D	10AF7	10AFF
D	10B36	10B38
D	10B56	10B57
D	10B73	10B77
D	10B92	10B98
D	10B9D	10BA8
D	10BB0	10BFF
D	10C49	10C7F
D	10CB3	10CBF
D	10CF3	10CF9
D	10D24	10D2F
D	10D3A	10D3F
D	10D66	10D6D
D	10D86	10D8D
D	10D90	10E5F
D	10E7F	10E7F
D	10EAA	10EAC
D	10EAE	10EAF
D	10EB2	10EC1
D	10EC8	10ECF
D	10ED9	10EFF
D	10F28	10F2F
D	10F46	10F50
D	10F5A	10F6F
D	10F82	10F85
D	10F8A	10FAF
D	10FCC	10FDF
D	10FF7	11002
D	11038	11046
D	1104E	11051
D	11070	11070
D	11073	11074
D	11076	11082
D	110B0	110BA
D	110BD	110BD
D	110C2	110CF
D	110E9	110EF
D	110FA	11102
D	11127	11135
D	11145	11146
D	11148	1114F
D	11173	11173
D	11177	11182
D	111B3	111C0
D	111C9	111CC
D	111CE	111CF
D	111E0	111E0
D	111F5	111FF
D	11212	11212
D	1122C	11237
D	1123E	1123E
D	11241	1127F
D	11287	11287
D	11289	11289
D	1128E	1128E
D	1129E	1129E
D	112AA	112AF
D	112DF	112EF
D	112FA	11304
D	1130D	1130E
D	11311	11312
D	11329	11329
D	11331	11331
D	11334	11334
D	1133A	1133C
D	1133E	1134F
D	11351	1135C
D	11362	1137F
D	1138A	1138A
D	1138C	1138D
D	1138F	1138F
D	113B6	113B6
D	113B8	113D0
D	113D2	113D2
D	113D6	113D6
D	113D9	113FF
D	11435	11446
D	1145C	1145C
D	1145E	1145E
D	11462	1147F
D	114B0	114C3
D	114C8	114CF
D	114DA	1157F
D	115AF	115C0
D	115DC	115FF
D	11630	11640
D	11645	1164F
D	1165A	1165F
D	1166D	1167F
D	116AB	116B7
D	116BA	116BF
D	116CA	116CF
D	116E4	116FF
D	1171B	1172F
D	11747	117FF
D	1182C	1183A
D	1183C	1189F
D	118F3	118FE
D	11907	11908
D	1190A	1190B
D	11914	11914
D	11917	11917
D	11930	1193E
D	11940	11940
D	11942	11943
D	11947	1194F
D	1195A	1199F
D	119A8	119A9
D	119D1	119E0
D	119E4	119FF
D	11A01	11A0A
D	11A33	11A39
D	11A3B	11A3E
D	11A47	11A4F
D	11A51	11A5B
D	11A8A	11A99
D	11AA3	11AAF
D	11AF9	11AFF
D	11B0A	11BBF
D	11BE2	11BEF
D	11BFA	11BFF
D	11C09	11C09
D	11C2F	11C3F
D	11C46	11C4F
D	11C6D	11C6F
D	11C90	11CFF
D	11D07	11D07
D	11D0A	11D0A
D	11D31	11D45
D	11D47	11D4F
D	11D5A	11D5F
D	11D66	11D66
D	11D69	11D69
D	11D8A	11D97
D	11D99	11D9F
D	11DAA	11DAF
D	11DDC	11DDF
D	11DEA	11EDF
D	11EF3	11EF6
D	11EF9	11F01
D	11F03	11F03
D	11F11	11F11
D	11F34	11F42
D	11F5A	11FAF
D	11FB1	11FBF
D	11FF2	11FFE
D	1239A	123FF
D	1246F	1246F
D	12475	1247F
D	12544	12F8F
D	12FF3	12FFF
D	13430	13440
D	13447	1345F
D	143FB	143FF
D	14647	160FF
D	1611E	1612F
D	1613A	167FF
D	16A39	16A3F
D	16A5F	16A5F
D	16A6A	16A6D
D	16ABF	16ABF
D	16ACA	16ACF
D	16AEE	16AF4
D	16AF6	16AFF
D	16B30	16B36
D	16B46	16B4F
D	16B5A	16B5A
D	16B62	16B62
D	16B78	16B7C
D	16B90	16D3F
D	16D7A	16E3F
D	16E9B	16E9F
D	16EB9	16EBA
D	16ED4	16EFF
D	16F4B	16F4F
D	16F51	16F92
D	16FA0	16FDF
D	16FE4	16FF1
D	16FF7	16FFF
D	18CD6	18CFE
D	18D1F	18D7F
D	18DF3	1AFEF
D	1AFF4	1AFF4
D	1AFFC	1AFFC
D	1AFFF	1AFFF
D	1B123	1B131
D	1B133	1B14F
D	1B153	1B154
D	1B156	1B163
D	1B168	1B16F
D	1B2FC	1BBFF
D	1BC6B	1BC6F
D	1BC7D	1BC7F
D	1BC89	1BC8F
D	1BC9A	1BC9B
D	1BC9D	1BC9E
D	1BCA0	1CBFF
D	1CCFD	1CCFF
D	1CEB4	1CEB9
D	1CED1	1CEDF
D	1CEF1	1CF4F
D	1CFC4	1CFFF
D	1D0F6	1D0FF
D	1D127	1D128
D	1D165	1D169
D	1D16D	1D182
D	1D185	1D18B
D	1D1AA	1D1AD
D	1D1EB	1D1FF
D	1D242	1D244
D	1D246	1D2BF
D	1D2D4	1D2DF
D	1D2F4	1D2FF
D	1D357	1D35F
D	1D379	1D3FF
D	1D455	1D455
D	1D49D	1D49D
D	1D4A0	1D4A1
D	1D4A3	1D4A4
D	1D4A7	1D4A8
D	1D4AD	1D4AD
D	1D4BA	1D4BA
D	1D4BC	1D4BC
D	1D4C4	1D4C4
D	1D506	1D506
D	1D50B	1D50C
D	1D515	1D515
D	1D51D	1D51D
D	1D53A	1D53A
D	1D53F	1D53F
D	1D545	1D545
D	1D547	1D549
D	1D551	1D551
D	1D6A6	1D6A7
D	1D7CC	1D7CD
D	1DA00	1DA36
D	1DA3B	1DA6C
D	1DA75	1DA75
D	1DA84	1DA84
D	1DA8C	1DEFF
D	1DF1F	1DF24
D	1DF2B	1E02F
D	1E06E	1E0FF
D	1E12D	1E136
D	1E13E	1E13F
D	1E14A	1E14D
D	1E150	1E28F
D	1E2AE	1E2BF
D	1E2EC	1E2EF
D	1E2FA	1E2FE
D	1E300	1E4CF
D	1E4EC	1E4EF
D	1E4FA	1E5CF
D	1E5EE	1E5EF
D	1E5FB	1E5FE
D	1E600	1E6BF
D	1E6DF	1E6DF
D	1E6E3	1E6E3
D	1E6E6	1E6E6
D	1E6EE	1E6EF
D	1E6F5	1E6FD
D	1E700	1E7DF
D	1E7E7	1E7E7
D	1E7EC	1E7EC
D	1E7EF	1E7EF
D	1E7FF	1E7FF
D	1E8C5	1E8C6
D	1E8D0	1E8FF
D	1E944	1E94A
D	1E94C	1E94F
D	1E95A	1E95D
D	1E960	1EC70
D	1ECB5	1ED00
D	1ED3E	1EDFF
D	1EE04	1EE04
D	1EE20	1EE20
D	1EE23	1EE23
D	1EE25	1EE26
D	1EE28	1EE28
D	1EE33	1EE33
D	1EE38	1EE38
D	1EE3A	1EE3A
D	1EE3C	1EE41
D	1EE43	1EE46
D	1EE48	1EE48
D	1EE4A	1EE4A
D	1EE4C	1EE4C
D	1EE50	1EE50
D	1EE53	1EE53
D	1EE55	1EE56
D	1EE58	1EE58
D	1EE5A	1EE5A
D	1EE5C	1EE5C
D	1EE5E	1EE5E
D	1EE60	1EE60
D	1EE63	1EE63
D	1EE65	1EE66
D	1EE6B	1EE6B
D	1EE73	1EE73
D	1EE78	1EE78
D	1EE7D	1EE7D
D	1EE7F	1EE7F
D	1EE8A	1EE8A
D	1EE9C	1EEA0
D	1EEA4	1EEA4
D	1EEAA	1EEAA
D	1EEBC	1EEEF
D	1EEF2	1EFFF
D	1F02C	1F02F
D	1F094	1F09F
D	1F0AF	1F0B0
D	1F0C0	1F0C0
D	1F0D0	1F0D0
D	1F0F6	1F0FF
D	1F1AE	1F1E5
D	1F203	1F20F
D	1F23C	1F23F
D	1F249	1F24F
D	1F252	1F25F
D	1F266	1F2FF
D	1F6D9	1F6DB
D	1F6ED	1F6EF
D	1F6FD	1F6FF
D	1F7DA	1F7DF
D	1F7EC	1F7EF
D	1F7F1	1F7FF
D	1F80C	1F80F
D	1F848	1F84F
D	1F85A	1F85F
D	1F888	1F88F
D	1F8AE	1F8AF
D	1F8BC	1F8BF
D	1F8C2	1F8CF
D	1F8D9	1F8FF
D	1FA58	1FA5F
D	1FA6E	1FA6F
D	1FA7D	1FA7F
D	1FA8B	1FA8D
D	1FAC7	1FAC7
D	1FAC9	1FACC
D	1FADD	1FADE
D	1FAEB	1FAEE
D	1FAF9	1FAFF
D	1FB93	1FB93
D	1FBFB	1FFFF
D	2A6E0	2A6FF
D	2B81E	2B81F
D	2CEAE	2CEAF
D	2EBE1	2EBEF
D	2EE5E	2F7FF
D	2FA1E	2FFFF
D	3134B	3134F
D	3347A	10FFFF
R	0041	0061
R	0042	0062
R	0043	0063
R	0044	0064
R	0045	0065
R	0046	0066
R	0047	0067
R	0048	0068
R	0049	0069
R	004A	006A
R	004B	006B
R	004C	006C
R	004D	006D
R	004E	006E
R	004F	006F
R	0050	0070
R	0051	0071
R	0052	0072
R	0053	0073
R	0054	0074
R	0055	0075
R	0056	0076
R	0057	0077
R	0058	0078
R	0059	0079
R	005A	007A
R	00A0	0020
R	00A8	0020
R	00AA	0061
R	00AF	0020
R	00B2	0032
R	00B3	0033
R	00B4	0020
R	00B8	0020
R	00B9	0031
R	00BA	006F
R	00BC	0031 002F 0034
R	00BD	0031 002F 0032
R	00BE	0033 002F 0034
R	00C0	0061
R	00C1	0061
R	00C2	0061
R	00C3	0061
R	00C4	0061
R	00C5	0061
R	00C6	0061 0065
R	00C7	0063
R	00C8	0065
R	00C9	0065
R	00CA	0065
R	00CB	0065
R	00CC	0069
R	00CD	0069
R	00CE	0069
R	00CF	0069
R	00D1	006E
R	00D2	006F
R	00D3	006F
R	00D4	006F
R	00D5	006F
R	00D6	006F
R	00D7	0078
R	00D9	0075
R	00DA	0075
R	00DB	0075
R	00DC	0075
R	00DD	0079
R	00DE	0070
R	00DF	0073 0073
R	00E0	0061
R	00E1	0061
R	00E2	0061
R	00E3	0061
R	00E4	0061
R	00E5	0061
R	00E6	0061 0065
R	00E7	0063
R	00E8	0065
R	00E9	0065
R	00EA	0065
R	00EB	0065
R	00EC	0069
R	00ED	0069
R	00EE	0069
R	00EF	0069
R	00F1	006E
R	00F2	006F
R	00F3	006F
R	00F4	006F
R	00F5	006F
R	00F6	006F
R	00F9	0075
R	00FA	0075
R	00FB	0075
R	00FC	0075
R	00FD	0079
R	00FE	0070
R	00FF	0079
R	0100	0061
R	0101	0061
R	0102	0061
R	0103	0061
R	0104	0061
R	0105	0061
R	0106	0063
R	0107	0063
R	0108	0063
R	0109	0063
R	010A	0063
R	010B	0063
R	010C	0063
R	010D	0063
R	010E	0064
R	010F	0064
R	0112	0065
R	0113	0065
R	0114	0065
R	0115	0065
R	0116	0065
R	0117	0065
R	0118	0065
R	0119	0065
R	011A	0065
R	011B	0065
R	011C	0067
R	011D	0067
R	011E	0067
R	011F	0067
R	0120	0067
R	0121	0067
R	0122	0067
R	0123	0067
R	0124	0068
R	0125	0068
R	0128	0069
R	0129	0069
R	012A	0069
R	012B	0069
R	012C	0069
R	012D	0069
R	012E	0069
R	012F	0069
R	0130	0069
R	0131	0069
R	0132	0069 006A
R	0133	0069 006A
R	0134	006A
R	0135	006A
R	0136	006B
R	0137	006B
R	0139	006C
R	013A	006C
R	013B	006C
R	013C	006C
R	013D	006C
R	013E	006C
R	013F	006C 00B7
R	0140	006C 00B7
R	0143	006E
R	0144	006E
R	0145	006E
R	0146	006E
R	0147	006E
R	0148	006E
R	0149	0027 006E
R	014C	006F
R	014D	006F
R	014E	006F
R	014F	006F
R	0150	006F
R	0151	006F
R	0152	006F 0065
R	0153	006F 0065
R	0154	0072
R	0155	0072
R	0156	0072
R	0157	0072
R	0158	0072
R	0159	0072
R	015A	0073
R	015B	0073
R	015C	0073
R	015D	0073
R	015E	0073
R	015F	0073
R	0160	0073
R	0161	0073
R	0162	0074
R	0163	0074
R	0164	0074
R	0165	0074
R	0168	0075
R	0169	0075
R	016A	0075
R	016B	0075
R	016C	0075
R	016D	0075
R	016E	0075
R	016F	0075
R	0170	0075
R	0171	0075
R	0172	0075
R	0173	0075
R	0174	0077
R	0175	0077
R	0176	0079
R	0177	0079
R	0178	0079
R	0179	007A
R	017A	007A
R	017B	007A
R	017C	007A
R	017D	007A
R	017E	007A
R	017F	0073
R	0181	0027 0062
R	0184	0062
R	0187	0063 0027
R	018A	0027 0064
R	018D	0067
R	0191	0066
R	0192	0066
R	0193	0067 0027
R	0194	0079
R	0196	0069
R	0198	006B 0027
R	019C	0077
R	01A0	006F
R	01A1	006F
R	01A4	0027 0070
R	01A6	0072
R	01A7	0032
R	01AC	0027 0074
R	01AF	0075
R	01B0	0075
R	01B2	0075
R	01B3	0027 0079
R	01B7	0033
R	01BC	0073
R	01BD	0073
R	01BF	0070
R	01C0	006C
R	01C1	006C 006C
R	01C3	0021
R	01C4	0064 007A
R	01C5	0064 007A
R	01C6	0064 007A
R	01C7	006C 006A
R	01C8	006C 006A
R	01C9	006C 006A
R	01CA	006E 006A
R	01CB	006E 006A
R	01CC	006E 006A
R	01CD	0061
R	01CE	0061
R	01CF	0069
R	01D0	0069
R	01D1	006F
R	01D2	006F
R	01D3	0075
R	01D4	0075
R	01D5	0075
R	01D6	0075
R	01D7	0075
R	01D8	0075
R	01D9	0075
R	01DA	0075
R	01DB	0075
R	01DC	0075
R	01DE	0061
R	01DF	0061
R	01E0	0061
R	01E1	0061
R	01E2	0061 0065
R	01E3	0061 0065
R	01E6	0067
R	01E7	0067
R	01E8	006B
R	01E9	006B
R	01EA	006F
R	01EB	006F
R	01EC	006F
R	01ED	006F
R	01EE	0033
R	01F0	006A
R	01F1	0064 007A
R	01F2	0064 007A
R	01F3	0064 007A
R	01F4	0067
R	01F5	0067
R	01F7	0070
R	01F8	006E
R	01F9	006E
R	01FA	0061
R	01FB	0061
R	01FC	0061 0065
R	01FD	0061 0065
R	0200	0061
R	0201	0061
R	0202	0061
R	0203	0061
R	0204	0065
R	0205	0065
R	0206	0065
R	0207	0065
R	0208	0069
R	0209	0069
R	020A	0069
R	020B	0069
R	020C	006F
R	020D	006F
R	020E	006F
R	020F	006F
R	0210	0072
R	0211	0072
R	0212	0072
R	0213	0072
R	0214	0075
R	0215	0075
R	0216	0075
R	0217	0075
R	0218	0073
R	0219	0073
R	021A	0074
R	021B	0074
R	021C	0033
R	021E	0068
R	021F	0068
R	0222	0038
R	0223	0038
R	0226	0061
R	0227	0061
R	0228	0065
R	0229	0065
R	022A	006F
R	022B	006F
R	022C	006F
R	022D	006F
R	022E	006F
R	022F	006F
R	0230	006F
R	0231	006F
R	0232	0079
R	0233	0079
R	0241	003F
R	0251	0061
R	0261	0067
R	0263	0079
R	0269	0069
R	026A	0069
R	026F	0077
R	028B	0075
R	028F	0079
R	0294	003F
R	02A3	0064 007A
R	02A6	0074 0073
R	02AA	006C 0073
R	02AB	006C 007A
R	02B0	0068
R	02B2	006A
R	02B3	0072
R	02B7	0077
R	02B8	0079
R	02B9	0027
R	02BA	0027 0027
R	02BB	0027
R	02BC	0027
R	02BD	0027
R	02BE	0027
R	02C2	003C
R	02C3	003E
R	02C4	005E
R	02C6	005E
R	02C8	0027
R	02CA	0027
R	02CB	0027
R	02D0	003A
R	02D7	002D
R	02D8	0020
R	02D9	0020
R	02DA	0020
R	02DB	0020
R	02DC	0020
R	02DD	0020
R	02E0	0079
R	02E1	006C
R	02E2	0073
R	02E3	0078
R	02EE	0027 0027
R	02F4	0027
R	02F6	0027 0027
R	02F8	003A
R	0374	0027
R	037A	0020
R	037E	003B
R	037F	006A
R	0384	0020
R	0385	0020
R	0386	0061
R	0388	0065
R	0389	0068
R	038A	0069
R	038C	006F
R	038E	0075
R	0390	0069
R	0391	0061
R	0392	0073 0073
R	0393	0079
R	0395	0065
R	0396	007A
R	0397	0068
R	0399	0069
R	039A	006B
R	039C	006D
R	039D	0076
R	039F	006F
R	03A1	0070
R	03A3	006F
R	03A4	0074
R	03A5	0075
R	03A7	0078
R	03AA	0069
R	03AB	0075
R	03AC	0061
R	03AF	0069
R	03B0	0075
R	03B1	0061
R	03B2	0073 0073
R	03B3	0079
R	03B9	0069
R	03BD	0076
R	03BF	006F
R	03C1	0070
R	03C2	006F
R	03C3	006F
R	03C5	0075
R	03CA	0069
R	03CB	0075
R	03CC	006F
R	03CD	0075
R	03D0	0073 0073
R	03D2	0075
R	03D3	0075
R	03D4	0075
R	03DC	0066
R	03E8	0032
R	03EC	006F
R	03ED	006F
R	03F1	0070
R	03F2	006F
R	03F3	006A
R	03F7	0070
R	03F8	0070
R	03F9	006F
R	03FA	006D
R	0400	0065
R	0401	0065
R	0403	0072
R	0405	0073
R	0406	0069
R	0407	0069
R	0408	006A
R	040C	006B
R	040E	0079
R	0410	0061
R	0411	0036
R	0412	0062
R	0413	0072
R	0415	0065
R	0417	0033
R	041A	006B
R	041C	006D
R	041D	0068
R	041E	006F
R	0420	0070
R	0421	0063
R	0422	0074
R	0423	0079
R	0425	0078
R	0428	0077
R	042B	0062 006C
R	042C	0062
R	042E	006C 006F
R	0430	0061
R	0431	0036
R	0433	0072
R	0435	0065
R	043E	006F
R	0440	0070
R	0441	0063
R	0443	0079
R	0445	0078
R	0448	0077
R	0450	0065
R	0451	0065
R	0453	0072
R	0455	0073
R	0456	0069
R	0457	0069
R	0458	006A
R	045E	0079
R	0460	0077
R	0461	0077
R	0474	0076
R	0475	0076
R	0476	0076
R	0477	0076
R	0490	0072 0027
R	0491	0072 0027
R	04AE	0079
R	04AF	0079
R	04BA	0068
R	04BB	0068
R	04BC	0065
R	04BD	0065
R	04C0	006C
R	04CF	006C
R	04D0	0061
R	04D1	0061
R	04D2	0061
R	04D3	0061
R	04D4	0061 0065
R	04D5	0061 0065
R	04D6	0065
R	04D7	0065
R	04DE	0033
R	04E0	0033
R	04E6	006F
R	04E7	006F
R	04EE	0079
R	04EF	0079
R	04F0	0079
R	04F1	0079
R	04F2	0079
R	04F3	0079
R	04F8	0062 006C
R	0500	0064
R	0501	0064
R	050C	0067
R	051A	0071
R	051B	0071
R	051C	0077
R	051D	0077
R	0531	0077
R	0533	0071
R	0536	0071
R	0540	0068
R	0548	006E
R	054C	006E
R	054D	0075
R	054F	0073
R	0551	0067
R	0552	0069
R	0554	0066
R	0555	006F
R	055A	0027
R	055D	0027
R	0561	0077
R	0563	0071
R	0566	0071
R	0570	0068
R	0578	006E
R	057C	006E
R	057D	0075
R	0581	0067
R	0582	0069
R	0584	0066
R	0585	006F
R	0587	0565 0069
R	0589	003A
R	05C0	006C
R	05C3	003A
R	05D5	006C
R	05D8	0076
R	05D9	0027
R	05DF	006C
R	05E1	006F
R	05F0	006C 006C
R	05F1	006C 0027
R	05F2	0027 0027
R	05F3	0027
R	05F4	0027 0027
R	060D	002C
R	0622	006C
R	0623	006C
R	0625	006C
R	0627	006C
R	0647	006F
R	0660	002E
R	0661	006C
R	0665	006F
R	0667	0076
R	066B	002C
R	066D	002A
R	0675	006C 0674
R	06BE	006F
R	06C0	006F
R	06C1	006F
R	06C2	006F
R	06D4	002D
R	06D5	006F
R	06F0	002E
R	06F1	006C
R	06F5	006F
R	06F7	0076
R	0701	002E
R	0702	002E
R	0703	003A
R	0704	003A
R	07C0	006F
R	07CA	006C
R	07F4	0027
R	07F5	0027
R	07FA	005F
R	0966	006F
R	0969	0033
R	097D	003F
R	09E6	006F
R	09EA	0038
R	09ED	0039
R	0A66	006F
R	0A67	0039
R	0A6A	0038
R	0AE6	006F
R	0AE9	0033
R	0B20	006F
R	0B66	006F
R	0B68	0039
R	0BE6	006F
R	0C66	006F
R	0CE6	006F
R	0D1F	0073
R	0D20	006F
R	0D66	006F
R	0D6D	0039
R	0E50	006F
R	0ED0	006F
R	1004	0063
R	101D	006F
R	1040	006F
R	105A	0063
R	10E7	0079
R	10FF	006F
R	1200	0075
R	12D0	006F
R	13A0	0064
R	13A1	0072
R	13A2	0074
R	13A4	006F 0027
R	13A5	0069
R	13A9	0079
R	13AA	0061
R	13AB	006A
R	13AC	0065
R	13AE	003F
R	13B3	0077
R	13B7	006D
R	13BB	0068
R	13BD	0079
R	13C0	0067
R	13C2	0068
R	13C3	007A
R	13CE	0034
R	13CF	0062
R	13D2	0072
R	13D4	0077
R	13D5	0073
R	13D9	0076
R	13DA	0073
R	13DE	006C
R	13DF	0063
R	13E2	0070
R	13E6	006B
R	13E7	0064
R	13EE	0036
R	13F0	0073 0073
R	13F3	0067
R	13F4	0062
R	13F8	0073 0073
R	13FB	0067
R	13FC	0062
R	1400	003D
R	142F	0076
R	1433	003E
R	1438	003C
R	144A	0027
R	144C	0075
R	1467	0075 0027
R	146D	0070
R	146F	0064
R	1472	0062
R	1486	0070 0027
R	1487	0064 0027
R	1488	0062 0027
R	148D	006A
R	14AA	006C
R	14BF	0032
R	1541	0078
R	157C	0068
R	157D	0078
R	1587	0072
R	15AF	0062
R	15B4	0066
R	15C5	0061
R	15DE	0064
R	15EA	0064
R	15F0	006D
R	15F7	0062
R	166D	0078
R	166E	0078
R	1680	0020
R	16B2	003C
R	16B7	0078
R	16C1	006C
R	16CC	0027
R	16D5	006B
R	16D6	006D
R	16EC	003A
R	16ED	002B
R	1735	002F
R	17E0	006F
R	1803	003A
R	1809	003A
R	1C82	006F
R	1C83	0063
R	1CA7	0079
R	1CBF	006F
R	1CD3	0027 0027
R	1D04	0063
R	1D0F	006F
R	1D11	006F
R	1D1C	0075
R	1D20	0076
R	1D21	0077
R	1D22	007A
R	1D26	0072
R	1D2C	0061
R	1D2D	0061 0065
R	1D2E	0062
R	1D30	0064
R	1D31	0065
R	1D33	0067
R	1D34	0068
R	1D35	0069
R	1D36	006A
R	1D37	006B
R	1D38	006C
R	1D39	006D
R	1D3A	006E
R	1D3C	006F
R	1D3D	0038
R	1D3E	0070
R	1D3F	0072
R	1D40	0074
R	1D41	0075
R	1D42	0077
R	1D43	0061
R	1D45	0061
R	1D47	0062
R	1D48	0064
R	1D49	0065
R	1D4D	0067
R	1D4F	006B
R	1D50	006D
R	1D52	006F
R	1D56	0070
R	1D57	0074
R	1D58	0075
R	1D5A	0077
R	1D5B	0076
R	1D5D	0073 0073
R	1D5E	0079
R	1D62	0069
R	1D63	0072
R	1D64	0075
R	1D65	0076
R	1D66	0073 0073
R	1D67	0079
R	1D68	0070
R	1D6B	0075 0065
R	1D83	0067
R	1D8C	0079
R	1D9C	0063
R	1DA0	0066
R	1DA2	0067
R	1DA5	0069
R	1DA6	0069
R	1DB8	0075
R	1DB9	0075
R	1DBB	007A
R	1E00	0061
R	1E01	0061
R	1E02	0062
R	1E03	0062
R	1E04	0062
R	1E05	0062
R	1E06	0062
R	1E07	0062
R	1E08	0063
R	1E09	0063
R	1E0A	0064
R	1E0B	0064
R	1E0C	0064
R	1E0D	0064
R	1E0E	0064
R	1E0F	0064
R	1E10	0064
R	1E11	0064
R	1E12	0064
R	1E13	0064
R	1E14	0065
R	1E15	0065
R	1E16	0065
R	1E17	0065
R	1E18	0065
R	1E19	0065
R	1E1A	0065
R	1E1B	0065
R	1E1C	0065
R	1E1D	0065
R	1E1E	0066
R	1E1F	0066
R	1E20	0067
R	1E21	0067
R	1E22	0068
R	1E23	0068
R	1E24	0068
R	1E25	0068
R	1E26	0068
R	1E27	0068
R	1E28	0068
R	1E29	0068
R	1E2A	0068
R	1E2B	0068
R	1E2C	0069
R	1E2D	0069
R	1E2E	0069
R	1E2F	0069
R	1E30	006B
R	1E31	006B
R	1E32	006B
R	1E33	006B
R	1E34	006B
R	1E35	006B
R	1E36	006C
R	1E37	006C
R	1E38	006C
R	1E39	006C
R	1E3A	006C
R	1E3B	006C
R	1E3C	006C
R	1E3D	006C
R	1E3E	006D
R	1E3F	006D
R	1E40	006D
R	1E41	006D
R	1E42	006D
R	1E43	006D
R	1E44	006E
R	1E45	006E
R	1E46	006E
R	1E47	006E
R	1E48	006E
R	1E49	006E
R	1E4A	006E
R	1E4B	006E
R	1E4C	006F
R	1E4D	006F
R	1E4E	006F
R	1E4F	006F
R	1E50	006F
R	1E51	006F
R	1E52	006F
R	1E53	006F
R	1E54	0070
R	1E55	0070
R	1E56	0070
R	1E57	0070
R	1E58	0072
R	1E59	0072
R	1E5A	0072
R	1E5B	0072
R	1E5C	0072
R	1E5D	0072
R	1E5E	0072
R	1E5F	0072
R	1E60	0073
R	1E61	0073
R	1E62	0073
R	1E63	0073
R	1E64	0073
R	1E65	0073
R	1E66	0073
R	1E67	0073
R	1E68	0073
R	1E69	0073
R	1E6A	0074
R	1E6B	0074
R	1E6C	0074
R	1E6D	0074
R	1E6E	0074
R	1E6F	0074
R	1E70	0074
R	1E71	0074
R	1E72	0075
R	1E73	0075
R	1E74	0075
R	1E75	0075
R	1E76	0075
R	1E77	0075
R	1E78	0075
R	1E79	0075
R	1E7A	0075
R	1E7B	0075
R	1E7C	0076
R	1E7D	0076
R	1E7E	0076
R	1E7F	0076
R	1E80	0077
R	1E81	0077
R	1E82	0077
R	1E83	0077
R	1E84	0077
R	1E85	0077
R	1E86	0077
R	1E87	0077
R	1E88	0077
R	1E89	0077
R	1E8A	0078
R	1E8B	0078
R	1E8C	0078
R	1E8D	0078
R	1E8E	0079
R	1E8F	0079
R	1E90	007A
R	1E91	007A
R	1E92	007A
R	1E93	007A
R	1E94	007A
R	1E95	007A
R	1E96	0068
R	1E97	0074
R	1E98	0077
R	1E99	0079
R	1E9A	0061 0027
R	1E9B	0073
R	1E9D	0066
R	1E9E	0073 0073
R	1EA0	0061
R	1EA1	0061
R	1EA2	0061
R	1EA3	0061
R	1EA4	0061
R	1EA5	0061
R	1EA6	0061
R	1EA7	0061
R	1EA8	0061
R	1EA9	0061
R	1EAA	0061
R	1EAB	0061
R	1EAC	0061
R	1EAD	0061
R	1EAE	0061
R	1EAF	0061
R	1EB0	0061
R	1EB1	0061
R	1EB2	0061
R	1EB3	0061
R	1EB4	0061
R	1EB5	0061
R	1EB6	0061
R	1EB7	0061
R	1EB8	0065
R	1EB9	0065
R	1EBA	0065
R	1EBB	0065
R	1EBC	0065
R	1EBD	0065
R	1EBE	0065
R	1EBF	0065
R	1EC0	0065
R	1EC1	0065
R	1EC2	0065
R	1EC3	0065
R	1EC4	0065
R	1EC5	0065
R	1EC6	0065
R	1EC7	0065
R	1EC8	0069
R	1EC9	0069
R	1ECA	0069
R	1ECB	0069
R	1ECC	006F
R	1ECD	006F
R	1ECE	006F
R	1ECF	006F
R	1ED0	006F
R	1ED1	006F
R	1ED2	006F
R	1ED3	006F
R	1ED4	006F
R	1ED5	006F
R	1ED6	006F
R	1ED7	006F
R	1ED8	006F
R	1ED9	006F
R	1EDA	006F
R	1EDB	006F
R	1EDC	006F
R	1EDD	006F
R	1EDE	006F
R	1EDF	006F
R	1EE0	006F
R	1EE1	006F
R	1EE2	006F
R	1EE3	006F
R	1EE4	0075
R	1EE5	0075
R	1EE6	0075
R	1EE7	0075
R	1EE8	0075
R	1EE9	0075
R	1EEA	0075
R	1EEB	0075
R	1EEC	0075
R	1EED	0075
R	1EEE	0075
R	1EEF	0075
R	1EF0	0075
R	1EF1	0075
R	1EF2	0079
R	1EF3	0079
R	1EF4	0079
R	1EF5	0079
R	1EF6	0079
R	1EF7	0079
R	1EF8	0079
R	1EF9	0079
R	1EFE	0079
R	1EFF	0079
R	1F00	0061
R	1F01	0061
R	1F02	0061
R	1F03	0061
R	1F04	0061
R	1F05	0061
R	1F06	0061
R	1F07	0061
R	1F08	0061
R	1F09	0061
R	1F0A	0061
R	1F0B	0061
R	1F0C	0061
R	1F0D	0061
R	1F0E	0061
R	1F0F	0061
R	1F18	0065
R	1F19	0065
R	1F1A	0065
R	1F1B	0065
R	1F1C	0065
R	1F1D	0065
R	1F28	0068
R	1F29	0068
R	1F2A	0068
R	1F2B	0068
R	1F2C	0068
R	1F2D	0068
R	1F2E	0068
R	1F2F	0068
R	1F30	0069
R	1F31	0069
R	1F32	0069
R	1F33	0069
R	1F34	0069
R	1F35	0069
R	1F36	0069
R	1F37	0069
R	1F38	0069
R	1F39	0069
R	1F3A	0069
R	1F3B	0069
R	1F3C	0069
R	1F3D	0069
R	1F3E	0069
R	1F3F	0069
R	1F40	006F
R	1F41	006F
R	1F42	006F
R	1F43	006F
R	1F44	006F
R	1F45	006F
R	1F48	006F
R	1F49	006F
R	1F4A	006F
R	1F4B	006F
R	1F4C	006F
R	1F4D	006F
R	1F50	0075
R	1F51	0075
R	1F52	0075
R	1F53	0075
R	1F54	0075
R	1F55	0075
R	1F56	0075
R	1F57	0075
R	1F59	0075
R	1F5B	0075
R	1F5D	0075
R	1F5F	0075
R	1F70	0061
R	1F71	0061
R	1F76	0069
R	1F77	0069
R	1F78	006F
R	1F79	006F
R	1F7A	0075
R	1F7B	0075
R	1F80	0061
R	1F81	0061
R	1F82	0061
R	1F83	0061
R	1F84	0061
R	1F85	0061
R	1F86	0061
R	1F87	0061
R	1F88	0061
R	1F89	0061
R	1F8A	0061
R	1F8B	0061
R	1F8C	0061
R	1F8D	0061
R	1F8E	0061
R	1F8F	0061
R	1F98	0068
R	1F99	0068
R	1F9A	0068
R	1F9B	0068
R	1F9C	0068
R	1F9D	0068
R	1F9E	0068
R	1F9F	0068
R	1FB0	0061
R	1FB1	0061
R	1FB2	0061
R	1FB3	0061
R	1FB4	0061
R	1FB6	0061
R	1FB7	0061
R	1FB8	0061
R	1FB9	0061
R	1FBA	0061
R	1FBB	0061
R	1FBC	0061
R	1FBD	0020
R	1FBE	0069
R	1FBF	0020
R	1FC0	0020
R	1FC1	0020
R	1FC8	0065
R	1FC9	0065
R	1FCA	0068
R	1FCB	0068
R	1FCC	0068
R	1FCD	0020
R	1FCE	0020
R	1FCF	0020
R	1FD0	0069
R	1FD1	0069
R	1FD2	0069
R	1FD3	0069
R	1FD6	0069
R	1FD7	0069
R	1FD8	0069
R	1FD9	0069
R	1FDA	0069
R	1FDB	0069
R	1FDD	0020
R	1FDE	0020
R	1FDF	0020
R	1FE0	0075
R	1FE1	0075
R	1FE2	0075
R	1FE3	0075
R	1FE4	0070
R	1FE5	0070
R	1FE6	0075
R	1FE7	0075
R	1FE8	0075
R	1FE9	0075
R	1FEA	0075
R	1FEB	0075
R	1FEC	0070
R	1FED	0020
R	1FEE	0020
R	1FEF	0060
R	1FF8	006F
R	1FF9	006F
R	1FFD	0020
R	1FFE	0020
R	2000	0020
R	2001	0020
R	2002	0020
R	2003	0020
R	2004	0020
R	2005	0020
R	2006	0020
R	2007	0020
R	2008	0020
R	2009	0020
R	200A	0020
R	2010	002D
R	2011	002D
R	2012	002D
R	2013	002D
R	2016	006C 006C
R	2017	0020
R	2018	0027
R	2019	0027
R	201A	002C
R	201B	0027
R	201C	0027 0027
R	201D	0027 0027
R	201F	0027 0027
R	2024	002E
R	2025	002E 002E
R	2026	002E 002E 002E
R	2028	0020
R	2029	0020
R	202F	0020
R	2032	0027
R	2033	0027 0027
R	2034	0027 0027 0027
R	2035	0027
R	2036	0027 0027
R	2037	0027 0027 0027
R	2039	003C
R	203A	003E
R	203C	0021 0021
R	203E	0020
R	2041	002F
R	2043	002D
R	2044	002F
R	2047	003F 003F
R	2048	003F 0021
R	2049	0021 003F
R	204E	002A
R	2053	007E
R	2057	0027 0027 0027 0027
R	205A	003A
R	205F	0020
R	2070	0030
R	2071	0069
R	2074	0034
R	2075	0035
R	2076	0036
R	2077	0037
R	2078	0038
R	2079	0039
R	207A	002B
R	207B	002D
R	207C	003D
R	207D	0028
R	207E	0029
R	207F	006E
R	2080	0030
R	2081	0031
R	2082	0032
R	2083	0033
R	2084	0034
R	2085	0035
R	2086	0036
R	2087	0037
R	2088	0038
R	2089	0039
R	208A	002B
R	208B	002D
R	208C	003D
R	208D	0028
R	208E	0029
R	2090	0061
R	2091	0065
R	2092	006F
R	2093	0078
R	2095	0068
R	2096	006B
R	2097	006C
R	2098	006D
R	2099	006E
R	209A	0070
R	209B	0073
R	209C	0074
R	20A8	0072 0073
R	20B6	006C 0074
R	2100	0061 002F 0063
R	2101	0061 002F 0073
R	2102	0063
R	2103	00B0 0063
R	2105	0063 002F 006F
R	2106	0063 002F 0075
R	2109	00B0 0066
R	210A	0067
R	210B	0068
R	210C	0068
R	210D	0068
R	210E	0068
R	2110	0069
R	2111	0069
R	2112	006C
R	2113	006C
R	2115	006E
R	2116	006E 006F
R	2119	0070
R	211A	0071
R	211B	0072
R	211C	0072
R	211D	0072
R	2120	0073 006D
R	2121	0074 0065 006C
R	2122	0074 006D
R	2124	007A
R	2128	007A
R	212A	006B
R	212B	0061
R	212C	0062
R	212D	0063
R	212E	0065
R	212F	0065
R	2130	0065
R	2131	0066
R	2133	006D
R	2134	006F
R	2139	0069
R	213B	0066 0061 0078
R	213D	0079
R	213E	0079
R	2145	0064
R	2146	0064
R	2147	0065
R	2148	0069
R	2149	006A
R	2150	0031 002F 0037
R	2151	0031 002F 0039
R	2152	0031 002F 0031 0030
R	2153	0031 002F 0033
R	2154	0032 002F 0033
R	2155	0031 002F 0035
R	2156	0032 002F 0035
R	2157	0033 002F 0035
R	2158	0034 002F 0035
R	2159	0031 002F 0036
R	215A	0035 002F 0036
R	215B	0031 002F 0038
R	215C	0033 002F 0038
R	215D	0035 002F 0038
R	215E	0037 002F 0038
R	215F	0031 002F
R	2160	0069
R	2161	0069 0069
R	2162	0069 0069 0069
R	2163	0069 0076
R	2164	0076
R	2165	0076 0069
R	2166	0076 0069 0069
R	2167	0076 0069 0069 0069
R	2168	0069 0078
R	2169	0078
R	216A	0078 0069
R	216B	0078 0069 0069
R	216C	006C
R	216D	0063
R	216E	0064
R	216F	006D
R	2170	0069
R	2171	0069 0069
R	2172	0069 0069 0069
R	2173	0069 0076
R	2174	0076
R	2175	0076 0069
R	2176	0076 0069 0069
R	2177	0076 0069 0069 0069
R	2178	0069 0078
R	2179	0078
R	217A	0078 0069
R	217B	0078 0069 0069
R	217C	006C
R	217D	0063
R	217E	0064
R	217F	006D
R	2189	0030 002F 0033
R	2212	002D
R	2215	002F
R	2216	005C
R	2217	002A
R	221E	006F 006F
R	2223	006C
R	2224	006C
R	2225	006C 006C
R	2226	006C 006C
R	2228	0076
R	222A	0075
R	2236	003A
R	223C	007E
R	2241	007E
R	2260	003D
R	226A	003C 003C
R	226B	003E 003E
R	226E	003C
R	226F	003E
R	22A4	0074
R	22C1	0076
R	22C3	0075
R	22D8	003C 003C 003C
R	22D9	003E 003E 003E
R	22FF	0065
R	2373	0069
R	2374	0070
R	237A	0061
R	23FD	006C
R	244A	005C 005C
R	2460	0031
R	2461	0032
R	2462	0033
R	2463	0034
R	2464	0035
R	2465	0036
R	2466	0037
R	2467	0038
R	2468	0039
R	2469	0031 0030
R	246A	0031 0031
R	246B	0031 0032
R	246C	0031 0033
R	246D	0031 0034
R	246E	0031 0035
R	246F	0031 0036
R	2470	0031 0037
R	2471	0031 0038
R	2472	0031 0039
R	2473	0032 0030
R	2474	0028 0031 0029
R	2475	0028 0032 0029
R	2476	0028 0033 0029
R	2477	0028 0034 0029
R	2478	0028 0035 0029
R	2479	0028 0036 0029
R	247A	0028 0037 0029
R	247B	0028 0038 0029
R	247C	0028 0039 0029
R	247D	0028 0031 0030 0029
R	247E	0028 0031 0031 0029
R	247F	0028 0031 0032 0029
R	2480	0028 0031 0033 0029
R	2481	0028 0031 0034 0029
R	2482	0028 0031 0035 0029
R	2483	0028 0031 0036 0029
R	2484	0028 0031 0037 0029
R	2485	0028 0031 0038 0029
R	2486	0028 0031 0039 0029
R	2487	0028 0032 0030 0029
R	2488	0031 002E
R	2489	0032 002E
R	248A	0033 002E
R	248B	0034 002E
R	248C	0035 002E
R	248D	0036 002E
R	248E	0037 002E
R	248F	0038 002E
R	2490	0039 002E
R	2491	0031 0030 002E
R	2492	0031 0031 002E
R	2493	0031 0032 002E
R	2494	0031 0033 002E
R	2495	0031 0034 002E
R	2496	0031 0035 002E
R	2497	0031 0036 002E
R	2498	0031 0037 002E
R	2499	0031 0038 002E
R	249A	0031 0039 002E
R	249B	0032 0030 002E
R	249C	0028 0061 0029
R	249D	0028 0062 0029
R	249E	0028 0063 0029
R	249F	0028 0064 0029
R	24A0	0028 0065 0029
R	24A1	0028 0066 0029
R	24A2	0028 0067 0029
R	24A3	0028 0068 0029
R	24A4	0028 0069 0029
R	24A5	0028 006A 0029
R	24A6	0028 006B 0029
R	24A7	0028 006C 0029
R	24A8	0028 006D 0029
R	24A9	0028 006E 0029
R	24AA	0028 006F 0029
R	24AB	0028 0070 0029
R	24AC	0028 0071 0029
R	24AD	0028 0072 0029
R	24AE	0028 0073 0029
R	24AF	0028 0074 0029
R	24B0	0028 0075 0029
R	24B1	0028 0076 0029
R	24B2	0028 0077 0029
R	24B3	0028 0078 0029
R	24B4	0028 0079 0029
R	24B5	0028 007A 0029
R	24B6	0061
R	24B7	0062
R	24B8	0063
R	24B9	0064
R	24BA	0065
R	24BB	0066
R	24BC	0067
R	24BD	0068
R	24BE	0069
R	24BF	006A
R	24C0	006B
R	24C1	006C
R	24C2	006D
R	24C3	006E
R	24C4	006F
R	24C5	0070
R	24C6	0071
R	24C7	0072
R	24C8	0073
R	24C9	0074
R	24CA	0075
R	24CB	0076
R	24CC	0077
R	24CD	0078
R	24CE	0079
R	24CF	007A
R	24D0	0061
R	24D1	0062
R	24D2	0063
R	24D3	0064
R	24D4	0065
R	24D5	0066
R	24D6	0067
R	24D7	0068
R	24D8	0069
R	24D9	006A
R	24DA	006B
R	24DB	006C
R	24DC	006D
R	24DD	006E
R	24DE	006F
R	24DF	0070
R	24E0	0071
R	24E1	0072
R	24E2	0073
R	24E3	0074
R	24E4	0075
R	24E5	0076
R	24E6	0077
R	24E7	0078
R	24E8	0079
R	24E9	007A
R	24EA	0030
R	2571	002F
R	2573	0078
R	2768	0028
R	2769	0029
R	276E	003C
R	276F	003E
R	2772	0028
R	2773	0029
R	2774	007B
R	2775	007D
R	2795	002B
R	2796	002D
R	27CB	002F
R	27CD	005C
R	27D9	0074
R	292B	0078
R	292C	0078
R	29F5	005C
R	29F8	002F
R	29F9	005C
R	2A20	003E 003E
R	2A2F	0078
R	2A74	003A 003A 003D
R	2A75	003D 003D
R	2A76	003D 003D 003D
R	2AA5	003E 003C
R	2AFB	002F 002F 002F
R	2AFD	002F 002F
R	2C6D	0061
R	2C7C	006A
R	2C7D	0076
R	2C82	0062
R	2C84	0072
R	2C85	0072
R	2C8E	0068
R	2C92	0069
R	2C93	0069
R	2C94	006B
R	2C98	006D
R	2C9A	006E
R	2C9C	0033
R	2C9E	006F
R	2C9F	006F
R	2CA2	0070
R	2CA3	0070
R	2CA4	0063
R	2CA5	0063
R	2CA6	0074
R	2CA8	0079
R	2CA9	0079
R	2CAC	0078
R	2CBA	002D
R	2CBB	002D
R	2CBC	0077
R	2CBD	0077
R	2CC4	0033
R	2CC6	002F
R	2CC7	002F
R	2CCA	0039
R	2CCB	0039
R	2CCC	0033
R	2CCE	0070
R	2CCF	0070
R	2CD0	006C
R	2CD2	0036
R	2CD3	0036
R	2CDC	0036
R	2CF9	005C 005C
R	2D38	0076
R	2D39	0065
R	2D4F	006C
R	2D51	0021
R	2D54	006F
R	2D55	0071
R	2D5D	0078
R	2E28	0028 0028
R	2E29	0029 0029
R	2E40	003D
R	2F02	005C
R	2F03	002F
R	3000	0020
R	3003	0027 0027
R	3007	006F
R	3014	0028
R	3015	0029
R	3033	002F
R	309B	0020
R	309C	0020
R	30A0	003D
R	30CE	002F
R	31D3	002F
R	31D4	005C
R	3200	0028 1100 0029
R	3201	0028 1102 0029
R	3202	0028 1103 0029
R	3203	0028 1105 0029
R	3204	0028 1106 0029
R	3205	0028 1107 0029
R	3206	0028 1109 0029
R	3207	0028 110B 0029
R	3208	0028 110C 0029
R	3209	0028 110E 0029
R	320A	0028 110F 0029
R	320B	0028 1110 0029
R	320C	0028 1111 0029
R	320D	0028 1112 0029
R	320E	0028 1100 1161 0029
R	320F	0028 1102 1161 0029
R	3210	0028 1103 1161 0029
R	3211	0028 1105 1161 0029
R	3212	0028 1106 1161 0029
R	3213	0028 1107 1161 0029
R	3214	0028 1109 1161 0029
R	3215	0028 110B 1161 0029
R	3216	0028 110C 1161 0029
R	3217	0028 110E 1161 0029
R	3218	0028 110F 1161 0029
R	3219	0028 1110 1161 0029
R	321A	0028 1111 1161 0029
R	321B	0028 1112 1161 0029
R	321C	0028 110C 116E 0029
R	321D	0028 110B 1169 110C 1165 11AB 0029
R	321E	0028 110B 1169 1112 116E 0029
R	3220	0028 4E00 0029
R	3221	0028 4E8C 0029
R	3222	0028 4E09 0029
R	3223	0028 56DB 0029
R	3224	0028 4E94 0029
R	3225	0028 516D 0029
R	3226	0028 4E03 0029
R	3227	0028 516B 0029
R	3228	0028 4E5D 0029
R	3229	0028 5341 0029
R	322A	0028 6708 0029
R	322B	0028 706B 0029
R	322C	0028 6C34 0029
R	322D	0028 6728 0029
R	322E	0028 91D1 0029
R	322F	0028 571F 0029
R	3230	0028 65E5 0029
R	3231	0028 682A 0029
R	3232	0028 6709 0029
R	3233	0028 793E 0029
R	3234	0028 540D 0029
R	3235	0028 7279 0029
R	3236	0028 8CA1 0029
R	3237	0028 795D 0029
R	3238	0028 52B4 0029
R	3239	0028 4EE3 0029
R	323A	0028 547C 0029
R	323B	0028 5B66 0029
R	323C	0028 76E3 0029
R	323D	0028 4F01 0029
R	323E	0028 8CC7 0029
R	323F	0028 5354 0029
R	3240	0028 796D 0029
R	3241	0028 4F11 0029
R	3242	0028 81EA 0029
R	3243	0028 81F3 0029
R	3250	0070 0074 0065
R	3251	0032 0031
R	3252	0032 0032
R	3253	0032 0033
R	3254	0032 0034
R	3255	0032 0035
R	3256	0032 0036
R	3257	0032 0037
R	3258	0032 0038
R	3259	0032 0039
R	325A	0033 0030
R	325B	0033 0031
R	325C	0033 0032
R	325D	0033 0033
R	325E	0033 0034
R	325F	0033 0035
R	32B1	0033 0036
R	32B2	0033 0037
R	32B3	0033 0038
R	32B4	0033 0039
R	32B5	0034 0030
R	32B6	0034 0031
R	32B7	0034 0032
R	32B8	0034 0033
R	32B9	0034 0034
R	32BA	0034 0035
R	32BB	0034 0036
R	32BC	0034 0037
R	32BD	0034 0038
R	32BE	0034 0039
R	32BF	0035 0030
R	32C0	0031 6708
R	32C1	0032 6708
R	32C2	0033 6708
R	32C3	0034 6708
R	32C4	0035 6708
R	32C5	0036 6708
R	32C6	0037 6708
R	32C7	0038 6708
R	32C8	0039 6708
R	32C9	0031 0030 6708
R	32CA	0031 0031 6708
R	32CB	0031 0032 6708
R	32CC	0068 0067
R	32CD	0065 0072 0067
R	32CE	0065 0076
R	32CF	006C 0074 0064
R	32E8	002F
R	3328	30CA 002F
R	3329	002F 30C3 30C8
R	3358	0030 70B9
R	3359	0031 70B9
R	335A	0032 70B9
R	335B	0033 70B9
R	335C	0034 70B9
R	335D	0035 70B9
R	335E	0036 70B9
R	335F	0037 70B9
R	3360	0038 70B9
R	3361	0039 70B9
R	3362	0031 0030 70B9
R	3363	0031 0031 70B9
R	3364	0031 0032 70B9
R	3365	0031 0033 70B9
R	3366	0031 0034 70B9
R	3367	0031 0035 70B9
R	3368	0031 0036 70B9
R	3369	0031 0037 70B9
R	336A	0031 0038 70B9
R	336B	0031 0039 70B9
R	336C	0032 0030 70B9
R	336D	0032 0031 70B9
R	336E	0032 0032 70B9
R	336F	0032 0033 70B9
R	3370	0032 0034 70B9
R	3371	0068 0070 0061
R	3372	0064 0061
R	3373	0061 0075
R	3374	0062 0061 0072
R	3375	006F 0076
R	3376	0070 0063
R	3377	0064 006D
R	3378	0064 006D 0032
R	3379	0064 006D 0033
R	337A	0069 0075
R	3380	0070 0061
R	3381	006E 0061
R	3382	03BC 0061
R	3383	006D 0061
R	3384	006B 0061
R	3385	006B 0062
R	3386	006D 0062
R	3387	0067 0062
R	3388	0063 0061 006C
R	3389	006B 0063 0061 006C
R	338A	0070 0066
R	338B	006E 0066
R	338C	03BC 0066
R	338D	03BC 0067
R	338E	006D 0067
R	338F	006B 0067
R	3390	0068 007A
R	3391	006B 0068 007A
R	3392	006D 0068 007A
R	3393	0067 0068 007A
R	3394	0074 0068 007A
R	3395	03BC 006C
R	3396	006D 006C
R	3397	0064 006C
R	3398	006B 006C
R	3399	0066 006D
R	339A	006E 006D
R	339B	03BC 006D
R	339C	006D 006D
R	339D	0063 006D
R	339E	006B 006D
R	339F	006D 006D 0032
R	33A0	0063 006D 0032
R	33A1	006D 0032
R	33A2	006B 006D 0032
R	33A3	006D 006D 0033
R	33A4	0063 006D 0033
R	33A5	006D 0033
R	33A6	006B 006D 0033
R	33A7	006D 002F 0073
R	33A8	006D 002F 0073 0032
R	33A9	0070 0061
R	33AA	006B 0070 0061
R	33AB	006D 0070 0061
R	33AC	0067 0070 0061
R	33AD	0072 0061 0064
R	33AE	0072 0061 0064 002F 0073
R	33AF	0072 0061 0064 002F 0073 0032
R	33B0	0070 0073
R	33B1	006E 0073
R	33B2	03BC 0073
R	33B3	006D 0073
R	33B4	0070 0076
R	33B5	006E 0076
R	33B6	03BC 0076
R	33B7	006D 0076
R	33B8	006B 0076
R	33B9	006D 0076
R	33BA	0070 0077
R	33BB	006E 0077
R	33BC	03BC 0077
R	33BD	006D 0077
R	33BE	006B 0077
R	33BF	006D 0077
R	33C0	006B 03A9
R	33C1	006D 03A9
R	33C2	0061 002E 006D 002E
R	33C3	0062 0071
R	33C4	0063 0063
R	33C5	0063 0064
R	33C6	0063 002F 006B 0067
R	33C7	0063 006F 002E
R	33C8	0064 0062
R	33C9	0067 0079
R	33CA	0068 0061
R	33CB	0068 0070
R	33CC	0069 006E
R	33CD	006B 006B
R	33CE	006B 006D
R	33CF	006B 0074
R	33D0	006C 006D
R	33D1	006C 006E
R	33D2	006C 006F 0067
R	33D3	006C 0078
R	33D4	006D 0062
R	33D5	006D 0069 006C
R	33D6	006D 006F 006C
R	33D7	0070 0068
R	33D8	0070 002E 006D 002E
R	33D9	0070 0070 006D
R	33DA	0070 0072
R	33DB	0073 0072
R	33DC	0073 0076
R	33DD	0077 0062
R	33DE	0076 002F 006D
R	33DF	0061 002F 006D
R	33E0	0031 65E5
R	33E1	0032 65E5
R	33E2	0033 65E5
R	33E3	0034 65E5
R	33E4	0035 65E5
R	33E5	0036 65E5
R	33E6	0037 65E5
R	33E7	0038 65E5
R	33E8	0039 65E5
R	33E9	0031 0030 65E5
R	33EA	0031 0031 65E5
R	33EB	0031 0032 65E5
R	33EC	0031 0033 65E5
R	33ED	0031 0034 65E5
R	33EE	0031 0035 65E5
R	33EF	0031 0036 65E5
R	33F0	0031 0037 65E5
R	33F1	0031 0038 65E5
R	33F2	0031 0039 65E5
R	33F3	0032 0030 65E5
R	33F4	0032 0031 65E5
R	33F5	0032 0032 65E5
R	33F6	0032 0033 65E5
R	33F7	0032 0034 65E5
R	33F8	0032 0035 65E5
R	33F9	0032 0036 65E5
R	33FA	0032 0037 65E5
R	33FB	0032 0038 65E5
R	33FC	0032 0039 65E5
R	33FD	0033 0030 65E5
R	33FE	0033 0031 65E5
R	33FF	0067 0061 006C
R	4E36	005C
R	4E3F	002F
R	A4D0	0062
R	A4D1	0070
R	A4D2	0064
R	A4D3	0064
R	A4D4	0074
R	A4D6	0067
R	A4D7	006B
R	A4D9	006A
R	A4DA	0063
R	A4DC	007A
R	A4DD	0066
R	A4DF	006D
R	A4E0	006E
R	A4E1	006C
R	A4E2	0073
R	A4E3	0072
R	A4E6	0076
R	A4E7	0068
R	A4EA	0077
R	A4EB	0078
R	A4EC	0079
R	A4EE	0061
R	A4F0	0065
R	A4F2	006C
R	A4F3	006F
R	A4F4	0075
R	A4F8	002E
R	A4F9	002C
R	A4FA	002E 002E
R	A4FB	002E 002C
R	A4FD	003A
R	A4FE	002D 002E
R	A4FF	003D
R	A60E	002E
R	A644	0032
R	A646	0069
R	A647	0069
R	A698	006F 006F
R	A699	006F 006F
R	A6DF	0076
R	A6EB	003F
R	A6EF	0032
R	A728	0074 0033
R	A731	0073
R	A732	0061 0061
R	A733	0061 0061
R	A734	0061 006F
R	A735	0061 006F
R	A736	0061 0075
R	A737	0061 0075
R	A738	0061 0076
R	A739	0061 0076
R	A73A	0061 0076
R	A73B	0061 0076
R	A73C	0061 0079
R	A73D	0061 0079
R	A74E	006F 006F
R	A74F	006F 006F
R	A75A	0032
R	A76A	0033
R	A76E	0039
R	A777	0074 0066
R	A778	0026
R	A789	003A
R	A78B	0027
R	A78C	0027
R	A798	0066
R	A799	0066
R	A79E	0075
R	A79F	0075
R	A7AB	0033
R	A7AC	0067
R	A7AE	0069
R	A7B2	006A
R	A7B3	0078
R	A7B4	0073 0073
R	A7B5	0073 0073
R	A7D6	0073 0073
R	A7F1	0073
R	A7F2	0063
R	A7F3	0066
R	A7F4	0071
R	A7F9	006F 0065
R	AB32	0065
R	AB35	0066
R	AB3D	006F
R	AB47	0072
R	AB48	0072
R	AB4E	0075
R	AB52	0075
R	AB5A	0079
R	AB5F	0075
R	AB63	0075 006F
R	AB70	0064
R	AB71	0072
R	AB72	0074
R	AB74	006F 0027
R	AB75	0069
R	AB79	0079
R	AB7A	0061
R	AB7B	006A
R	AB7C	0065
R	AB7E	003F
R	AB81	0072
R	AB83	0077
R	AB87	006D
R	AB8B	0068
R	AB8D	0079
R	AB90	0067
R	AB92	0068
R	AB93	007A
R	AB9E	0034
R	AB9F	0062
R	ABA2	0072
R	ABA4	0077
R	ABA5	0073
R	ABA9	0076
R	ABAA	0073
R	ABAE	006C
R	ABAF	0063
R	ABB2	0070
R	ABB6	006B
R	ABB7	0064
R	ABBE	0036
R	FB00	0066 0066
R	FB01	0066 0069
R	FB02	0066 006C
R	FB03	0066 0066 0069
R	FB04	0066 0066 006C
R	FB05	0073 0074
R	FB06	0073 0074
R	FB1D	0027
R	FB1F	0027 0027
R	FB29	002B
R	FB35	006C
R	FB38	0076
R	FB39	0027
R	FB41	006F
R	FB4B	006C
R	FBA4	006F
R	FBA5	006F
R	FBA6	006F
R	FBA7	006F
R	FBA8	006F
R	FBA9	006F
R	FBAA	006F
R	FBAB	006F
R	FBAC	006F
R	FBAD	006F
R	FBEA	064A 006C
R	FBEB	064A 006C
R	FBEC	064A 006F
R	FBED	064A 006F
R	FC37	0643 006C
R	FC51	006F 062C
R	FC52	006F 0645
R	FC53	006F 0649
R	FC54	006F 064A
R	FC5E	0020
R	FC5F	0020
R	FC60	0020
R	FC61	0020
R	FC62	0020
R	FC63	0020
R	FC80	0643 006C
R	FC88	0645 006C
R	FC9B	064A 006F
R	FCA0	0628 006F
R	FCA5	062A 006F
R	FCCD	0644 006F
R	FCD6	0646 006F
R	FCD7	006F 062C
R	FCD8	006F 0645
R	FCD9	006F
R	FCDE	064A 006F
R	FCE0	064A 006F
R	FCE2	0628 006F
R	FCE4	062A 006F
R	FCE6	062B 006F
R	FCE8	0633 006F
R	FCEA	0634 006F
R	FCEF	0646 006F
R	FCF1	064A 006F
R	FD31	0633 006F
R	FD32	0634 006F
R	FD3C	006C
R	FD3D	006C
R	FD3E	0028
R	FD3F	0029
R	FD93	006F 0645 062C
R	FD94	006F 0645 0645
R	FDF2	006C 0644 0644 006F
R	FDF3	006C 0643 0628 0631
R	FDF7	0639 0644 064A 006F
R	FDFA	0635 0644 0649 0020 006C 0644 0644 006F 0020 0639 0644 064A 006F 0020 0648 0633 0644 0645
R	FDFB	062C 0644 0020 062C 0644 006C 0644 006F
R	FDFC	0631 06CC 006C 0644
R	FE10	002C
R	FE13	003A
R	FE14	003B
R	FE15	0021
R	FE16	003F
R	FE19	002E 002E 002E
R	FE30	002E 002E
R	FE32	002D
R	FE33	005F
R	FE34	005F
R	FE35	0028
R	FE36	0029
R	FE37	007B
R	FE38	007D
R	FE39	0028
R	FE3A	0029
R	FE47	005B
R	FE48	005D
R	FE49	0020
R	FE4A	0020
R	FE4B	0020
R	FE4C	0020
R	FE4D	005F
R	FE4E	005F
R	FE4F	005F
R	FE50	002C
R	FE52	002E
R	FE54	003B
R	FE55	003A
R	FE56	003F
R	FE57	0021
R	FE59	0028
R	FE5A	0029
R	FE5B	007B
R	FE5C	007D
R	FE5D	0028
R	FE5E	0029
R	FE5F	0023
R	FE60	0026
R	FE61	002A
R	FE62	002B
R	FE63	002D
R	FE64	003C
R	FE65	003E
R	FE66	003D
R	FE68	005C
R	FE69	0024
R	FE6A	0025
R	FE6B	0040
R	FE70	0020
R	FE72	0020
R	FE74	0020
R	FE76	0020
R	FE78	0020
R	FE7A	0020
R	FE7C	0020
R	FE7E	0020
R	FE81	006C
R	FE82	006C
R	FE83	006C
R	FE84	006C
R	FE87	006C
R	FE88	006C
R	FE8D	006C
R	FE8E	006C
R	FEE9	006F
R	FEEA	006F
R	FEEB	006F
R	FEEC	006F
R	FEF5	0644 006C
R	FEF6	0644 006C
R	FEF7	0644 006C
R	FEF8	0644 006C
R	FEF9	0644 006C
R	FEFA	0644 006C
R	FEFB	0644 006C
R	FEFC	0644 006C
R	FF01	0021
R	FF02	0022
R	FF03	0023
R	FF04	0024
R	FF05	0025
R	FF06	0026
R	FF07	0027
R	FF08	0028
R	FF09	0029
R	FF0A	002A
R	FF0B	002B
R	FF0C	002C
R	FF0D	002D
R	FF0E	002E
R	FF0F	002F
R	FF10	0030
R	FF11	0031
R	FF12	0032
R	FF13	0033
R	FF14	0034
R	FF15	0035
R	FF16	0036
R	FF17	0037
R	FF18	0038
R	FF19	0039
R	FF1A	003A
R	FF1B	003B
R	FF1C	003C
R	FF1D	003D
R	FF1E	003E
R	FF1F	003F
R	FF20	0040
R	FF21	0061
R	FF22	0062
R	FF23	0063
R	FF24	0064
R	FF25	0065
R	FF26	0066
R	FF27	0067
R	FF28	0068
R	FF29	0069
R	FF2A	006A
R	FF2B	006B
R	FF2C	006C
R	FF2D	006D
R	FF2E	006E
R	FF2F	006F
R	FF30	0070
R	FF31	0071
R	FF32	0072
R	FF33	0073
R	FF34	0074
R	FF35	0075
R	FF36	0076
R	FF37	0077
R	FF38	0078
R	FF39	0079
R	FF3A	007A
R	FF3B	005B
R	FF3C	005C
R	FF3D	005D
R	FF3E	005E
R	FF3F	005F
R	FF40	0060
R	FF41	0061
R	FF42	0062
R	FF43	0063
R	FF44	0064
R	FF45	0065
R	FF46	0066
R	FF47	0067
R	FF48	0068
R	FF49	0069
R	FF4A	006A
R	FF4B	006B
R	FF4C	006C
R	FF4D	006D
R	FF4E	006E
R	FF4F	006F
R	FF50	0070
R	FF51	0071
R	FF52	0072
R	FF53	0073
R	FF54	0074
R	FF55	0075
R	FF56	0076
R	FF57	0077
R	FF58	0078
R	FF59	0079
R	FF5A	007A
R	FF5B	007B
R	FF5C	007C
R	FF5D	007D
R	FF5E	007E
R	FF89	002F
R	FF9E	
R	FF9F	
R	FFE3	0020
R	10282	0062
R	10286	0065
R	10287	0066
R	1028A	006C
R	10290	0078
R	10292	006F
R	10295	0070
R	10296	0073
R	10297	0074
R	1029B	002B
R	102A0	0061
R	102A1	0062
R	102A2	0063
R	102A5	0066
R	102AB	006F
R	102B0	006D
R	102B1	0074
R	102B2	0079
R	102B4	0078
R	102CF	0068
R	102F5	007A
R	10301	0062
R	10302	0063
R	10309	006C
R	10311	006D
R	10315	0074
R	10317	0078
R	1031A	0038
R	1031F	002A
R	10320	006C
R	10322	0078
R	10404	006F
R	10415	0063
R	1041B	006C
R	10420	0073
R	1042C	006F
R	1043D	0063
R	10448	0073
R	104B4	0072
R	104C2	006F
R	104CE	0075
R	104D2	0037
R	104EA	006F
R	104F6	0075
R	10513	006E
R	10516	006F
R	10518	006B
R	1051C	0063
R	1051D	0076
R	10525	0066
R	10526	006C
R	10527	0078
R	10781	003A
R	10783	0061 0065
R	10787	0064 007A
R	10799	006C 0073
R	1079A	006C 007A
R	107A5	0071
R	107AC	0074 0073
R	107B2	0079
R	107B6	006C
R	107B7	006C 006C
R	10A50	002E
R	114D0	006F
R	11700	0072 006E
R	11706	0076
R	1170A	0077
R	1170E	0077
R	1170F	0077
R	118A0	0076
R	118A1	0073
R	118A2	0066
R	118A3	0069
R	118A4	007A
R	118A6	0037
R	118A8	006F
R	118A9	007A
R	118AA	0033
R	118AC	0039
R	118AE	0065
R	118AF	0034
R	118B2	006C
R	118B5	0036
R	118B6	0039
R	118B7	006F
R	118B8	0075
R	118BB	0035
R	118BC	0079
R	118C0	0076
R	118C1	0073
R	118C2	0066
R	118C3	0069
R	118C4	007A
R	118C6	0037
R	118C8	006F
R	118CA	0033
R	118CC	0039
R	118D5	0036
R	118D6	0039
R	118D7	006F
R	118D8	0075
R	118DC	0079
R	118E0	006F
R	118E3	0072 006E
R	118E5	007A
R	118E6	0077
R	118E9	0063
R	118EC	0078
R	118EF	0077
R	118F2	0063
R	11DD9	003A
R	11DDA	006C
R	11DE0	006F
R	11DE1	006C
R	16EAA	006C
R	16EB6	0062
R	16F08	0076
R	16F0A	0074
R	16F16	006C
R	16F28	006C
R	16F35	0072
R	16F3A	0073
R	16F3B	0033
R	16F3F	003E
R	16F40	0061
R	16F42	0075
R	16F43	0079
R	1CCD6	0061
R	1CCD7	0062
R	1CCD8	0063
R	1CCD9	0064
R	1CCDA	0065
R	1CCDB	0066
R	1CCDC	0067
R	1CCDD	0068
R	1CCDE	0069
R	1CCDF	006A
R	1CCE0	006B
R	1CCE1	006C
R	1CCE2	006D
R	1CCE3	006E
R	1CCE4	006F
R	1CCE5	0070
R	1CCE6	0071
R	1CCE7	0072
R	1CCE8	0073
R	1CCE9	0074
R	1CCEA	0075
R	1CCEB	0076
R	1CCEC	0077
R	1CCED	0078
R	1CCEE	0079
R	1CCEF	007A
R	1CCF0	0030
R	1CCF1	0031
R	1CCF2	0032
R	1CCF3	0033
R	1CCF4	0034
R	1CCF5	0035
R	1CCF6	0036
R	1CCF7	0037
R	1CCF8	0038
R	1CCF9	0039
R	1D114	007B
R	1D206	0033
R	1D20D	0076
R	1D20F	005C
R	1D212	0037
R	1D213	0066
R	1D216	0072
R	1D22A	006C
R	1D236	003C
R	1D237	003E
R	1D23A	002F
R	1D23B	005C
R	1D400	0061
R	1D401	0062
R	1D402	0063
R	1D403	0064
R	1D404	0065
R	1D405	0066
R	1D406	0067
R	1D407	0068
R	1D408	0069
R	1D409	006A
R	1D40A	006B
R	1D40B	006C
R	1D40C	006D
R	1D40D	006E
R	1D40E	006F
R	1D40F	0070
R	1D410	0071
R	1D411	0072
R	1D412	0073
R	1D413	0074
R	1D414	0075
R	1D415	0076
R	1D416	0077
R	1D417	0078
R	1D418	0079
R	1D419	007A
R	1D41A	0061
R	1D41B	0062
R	1D41C	0063
R	1D41D	0064
R	1D41E	0065
R	1D41F	0066
R	1D420	0067
R	1D421	0068
R	1D422	0069
R	1D423	006A
R	1D424	006B
R	1D425	006C
R	1D426	006D
R	1D427	006E
R	1D428	006F
R	1D429	0070
R	1D42A	0071
R	1D42B	0072
R	1D42C	0073
R	1D42D	0074
R	1D42E	0075
R	1D42F	0076
R	1D430	0077
R	1D431	0078
R	1D432	0079
R	1D433	007A
R	1D434	0061
R	1D435	0062
R	1D436	0063
R	1D437	0064
R	1D438	0065
R	1D439	0066
R	1D43A	0067
R	1D43B	0068
R	1D43C	0069
R	1D43D	006A
R	1D43E	006B
R	1D43F	006C
R	1D440	006D
R	1D441	006E
R	1D442	006F
R	1D443	0070
R	1D444	0071
R	1D445	0072
R	1D446	0073
R	1D447	0074
R	1D448	0075
R	1D449	0076
R	1D44A	0077
R	1D44B	0078
R	1D44C	0079
R	1D44D	007A
R	1D44E	0061
R	1D44F	0062
R	1D450	0063
R	1D451	0064
R	1D452	0065
R	1D453	0066
R	1D454	0067
R	1D456	0069
R	1D457	006A
R	1D458	006B
R	1D459	006C
R	1D45A	006D
R	1D45B	006E
R	1D45C	006F
R	1D45D	0070
R	1D45E	0071
R	1D45F	0072
R	1D460	0073
R	1D461	0074
R	1D462	0075
R	1D463	0076
R	1D464	0077
R	1D465	0078
R	1D466	0079
R	1D467	007A
R	1D468	0061
R	1D469	0062
R	1D46A	0063
R	1D46B	0064
R	1D46C	0065
R	1D46D	0066
R	1D46E	0067
R	1D46F	0068
R	1D470	0069
R	1D471	006A
R	1D472	006B
R	1D473	006C
R	1D474	006D
R	1D475	006E
R	1D476	006F
R	1D477	0070
R	1D478	0071
R	1D479	0072
R	1D47A	0073
R	1D47B	0074
R	1D47C	0075
R	1D47D	0076
R	1D47E	0077
R	1D47F	0078
R	1D480	0079
R	1D481	007A
R	1D482	0061
R	1D483	0062
R	1D484	0063
R	1D485	0064
R	1D486	0065
R	1D487	0066
R	1D488	0067
R	1D489	0068
R	1D48A	0069
R	1D48B	006A
R	1D48C	006B
R	1D48D	006C
R	1D48E	006D
R	1D48F	006E
R	1D490	006F
R	1D491	0070
R	1D492	0071
R	1D493	0072
R	1D494	0073
R	1D495	0074
R	1D496	0075
R	1D497	0076
R	1D498	0077
R	1D499	0078
R	1D49A	0079
R	1D49B	007A
R	1D49C	0061
R	1D49E	0063
R	1D49F	0064
R	1D4A2	0067
R	1D4A5	006A
R	1D4A6	006B
R	1D4A9	006E
R	1D4AA	006F
R	1D4AB	0070
R	1D4AC	0071
R	1D4AE	0073
R	1D4AF	0074
R	1D4B0	0075
R	1D4B1	0076
R	1D4B2	0077
R	1D4B3	0078
R	1D4B4	0079
R	1D4B5	007A
R	1D4B6	0061
R	1D4B7	0062
R	1D4B8	0063
R	1D4B9	0064
R	1D4BB	0066
R	1D4BD	0068
R	1D4BE	0069
R	1D4BF	006A
R	1D4C0	006B
R	1D4C1	006C
R	1D4C2	006D
R	1D4C3	006E
R	1D4C5	0070
R	1D4C6	0071
R	1D4C7	0072
R	1D4C8	0073
R	1D4C9	0074
R	1D4CA	0075
R	1D4CB	0076
R	1D4CC	0077
R	1D4CD	0078
R	1D4CE	0079
R	1D4CF	007A
R	1D4D0	0061
R	1D4D1	0062
R	1D4D2	0063
R	1D4D3	0064
R	1D4D4	0065
R	1D4D5	0066
R	1D4D6	0067
R	1D4D7	0068
R	1D4D8	0069
R	1D4D9	006A
R	1D4DA	006B
R	1D4DB	006C
R	1D4DC	006D
R	1D4DD	006E
R	1D4DE	006F
R	1D4DF	0070
R	1D4E0	0071
R	1D4E1	0072
R	1D4E2	0073
R	1D4E3	0074
R	1D4E4	0075
R	1D4E5	0076
R	1D4E6	0077
R	1D4E7	0078
R	1D4E8	0079
R	1D4E9	007A
R	1D4EA	0061
R	1D4EB	0062
R	1D4EC	0063
R	1D4ED	0064
R	1D4EE	0065
R	1D4EF	0066
R	1D4F0	0067
R	1D4F1	0068
R	1D4F2	0069
R	1D4F3	006A
R	1D4F4	006B
R	1D4F5	006C
R	1D4F6	006D
R	1D4F7	006E
R	1D4F8	006F
R	1D4F9	0070
R	1D4FA	0071
R	1D4FB	0072
R	1D4FC	0073
R	1D4FD	0074
R	1D4FE	0075
R	1D4FF	0076
R	1D500	0077
R	1D501	0078
R	1D502	0079
R	1D503	007A
R	1D504	0061
R	1D505	0062
R	1D507	0064
R	1D508	0065
R	1D509	0066
R	1D50A	0067
R	1D50D	006A
R	1D50E	006B
R	1D50F	006C
R	1D510	006D
R	1D511	006E
R	1D512	006F
R	1D513	0070
R	1D514	0071
R	1D516	0073
R	1D517	0074
R	1D518	0075
R	1D519	0076
R	1D51A	0077
R	1D51B	0078
R	1D51C	0079
R	1D51E	0061
R	1D51F	0062
R	1D520	0063
R	1D521	0064
R	1D522	0065
R	1D523	0066
R	1D524	0067
R	1D525	0068
R	1D526	0069
R	1D527	006A
R	1D528	006B
R	1D529	006C
R	1D52A	006D
R	1D52B	006E
R	1D52C	006F
R	1D52D	0070
R	1D52E	0071
R	1D52F	0072
R	1D530	0073
R	1D531	0074
R	1D532	0075
R	1D533	0076
R	1D534	0077
R	1D535	0078
R	1D536	0079
R	1D537	007A
R	1D538	0061
R	1D539	0062
R	1D53B	0064
R	1D53C	0065
R	1D53D	0066
R	1D53E	0067
R	1D540	0069
R	1D541	006A
R	1D542	006B
R	1D543	006C
R	1D544	006D
R	1D546	006F
R	1D54A	0073
R	1D54B	0074
R	1D54C	0075
R	1D54D	0076
R	1D54E	0077
R	1D54F	0078
R	1D550	0079
R	1D552	0061
R	1D553	0062
R	1D554	0063
R	1D555	0064
R	1D556	0065
R	1D557	0066
R	1D558	0067
R	1D559	0068
R	1D55A	0069
R	1D55B	006A
R	1D55C	006B
R	1D55D	006C
R	1D55E	006D
R	1D55F	006E
R	1D560	006F
R	1D561	0070
R	1D562	0071
R	1D563	0072
R	1D564	0073
R	1D565	0074
R	1D566	0075
R	1D567	0076
R	1D568	0077
R	1D569	0078
R	1D56A	0079
R	1D56B	007A
R	1D56C	0061
R	1D56D	0062
R	1D56E	0063
R	1D56F	0064
R	1D570	0065
R	1D571	0066
R	1D572	0067
R	1D573	0068
R	1D574	0069
R	1D575	006A
R	1D576	006B
R	1D577	006C
R	1D578	006D
R	1D579	006E
R	1D57A	006F
R	1D57B	0070
R	1D57C	0071
R	1D57D	0072
R	1D57E	0073
R	1D57F	0074
R	1D580	0075
R	1D581	0076
R	1D582	0077
R	1D583	0078
R	1D584	0079
R	1D585	007A
R	1D586	0061
R	1D587	0062
R	1D588	0063
R	1D589	0064
R	1D58A	0065
R	1D58B	0066
R	1D58C	0067
R	1D58D	0068
R	1D58E	0069
R	1D58F	006A
R	1D590	006B
R	1D591	006C
R	1D592	006D
R	1D593	006E
R	1D594	006F
R	1D595	0070
R	1D596	0071
R	1D597	0072
R	1D598	0073
R	1D599	0074
R	1D59A	0075
R	1D59B	0076
R	1D59C	0077
R	1D59D	0078
R	1D59E	0079
R	1D59F	007A
R	1D5A0	0061
R	1D5A1	0062
R	1D5A2	0063
R	1D5A3	0064
R	1D5A4	0065
R	1D5A5	0066
R	1D5A6	0067
R	1D5A7	0068
R	1D5A8	0069
R	1D5A9	006A
R	1D5AA	006B
R	1D5AB	006C
R	1D5AC	006D
R	1D5AD	006E
R	1D5AE	006F
R	1D5AF	0070
R	1D5B0	0071
R	1D5B1	0072
R	1D5B2	0073
R	1D5B3	0074
R	1D5B4	0075
R	1D5B5	0076
R	1D5B6	0077
R	1D5B7	0078
R	1D5B8	0079
R	1D5B9	007A
R	1D5BA	0061
R	1D5BB	0062
R	1D5BC	0063
R	1D5BD	0064
R	1D5BE	0065
R	1D5BF	0066
R	1D5C0	0067
R	1D5C1	0068
R	1D5C2	0069
R	1D5C3	006A
R	1D5C4	006B
R	1D5C5	006C
R	1D5C6	006D
R	1D5C7	006E
R	1D5C8	006F
R	1D5C9	0070
R	1D5CA	0071
R	1D5CB	0072
R	1D5CC	0073
R	1D5CD	0074
R	1D5CE	0075
R	1D5CF	0076
R	1D5D0	0077
R	1D5D1	0078
R	1D5D2	0079
R	1D5D3	007A
R	1D5D4	0061
R	1D5D5	0062
R	1D5D6	0063
R	1D5D7	0064
R	1D5D8	0065
R	1D5D9	0066
R	1D5DA	0067
R	1D5DB	0068
R	1D5DC	0069
R	1D5DD	006A
R	1D5DE	006B
R	1D5DF	006C
R	1D5E0	006D
R	1D5E1	006E
R	1D5E2	006F
R	1D5E3	0070
R	1D5E4	0071
R	1D5E5	0072
R	1D5E6	0073
R	1D5E7	0074
R	1D5E8	0075
R	1D5E9	0076
R	1D5EA	0077
R	1D5EB	0078
R	1D5EC	0079
R	1D5ED	007A
R	1D5EE	0061
R	1D5EF	0062
R	1D5F0	0063
R	1D5F1	0064
R	1D5F2	0065
R	1D5F3	0066
R	1D5F4	0067
R	1D5F5	0068
R	1D5F6	0069
R	1D5F7	006A
R	1D5F8	006B
R	1D5F9	006C
R	1D5FA	006D
R	1D5FB	006E
R	1D5FC	006F
R	1D5FD	0070
R	1D5FE	0071
R	1D5FF	0072
R	1D600	0073
R	1D601	0074
R	1D602	0075
R	1D603	0076
R	1D604	0077
R	1D605	0078
R	1D606	0079
R	1D607	007A
R	1D608	0061
R	1D609	0062
R	1D60A	0063
R	1D60B	0064
R	1D60C	0065
R	1D60D	0066
R	1D60E	0067
R	1D60F	0068
R	1D610	0069
R	1D611	006A
R	1D612	006B
R	1D613	006C
R	1D614	006D
R	1D615	006E
R	1D616	006F
R	1D617	0070
R	1D618	0071
R	1D619	0072
R	1D61A	0073
R	1D61B	0074
R	1D61C	0075
R	1D61D	0076
R	1D61E	0077
R	1D61F	0078
R	1D620	0079
R	1D621	007A
R	1D622	0061
R	1D623	0062
R	1D624	0063
R	1D625	0064
R	1D626	0065
R	1D627	0066
R	1D628	0067
R	1D629	0068
R	1D62A	0069
R	1D62B	006A
R	1D62C	006B
R	1D62D	006C
R	1D62E	006D
R	1D62F	006E
R	1D630	006F
R	1D631	0070
R	1D632	0071
R	1D633	0072
R	1D634	0073
R	1D635	0074
R	1D636	0075
R	1D637	0076
R	1D638	0077
R	1D639	0078
R	1D63A	0079
R	1D63B	007A
R	1D63C	0061
R	1D63D	0062
R	1D63E	0063
R	1D63F	0064
R	1D640	0065
R	1D641	0066
R	1D642	0067
R	1D643	0068
R	1D644	0069
R	1D645	006A
R	1D646	006B
R	1D647	006C
R	1D648	006D
R	1D649	006E
R	1D64A	006F
R	1D64B	0070
R	1D64C	0071
R	1D64D	0072
R	1D64E	0073
R	1D64F	0074
R	1D650	0075
R	1D651	0076
R	1D652	0077
R	1D653	0078
R	1D654	0079
R	1D655	007A
R	1D656	0061
R	1D657	0062
R	1D658	0063
R	1D659	0064
R	1D65A	0065
R	1D65B	0066
R	1D65C	0067
R	1D65D	0068
R	1D65E	0069
R	1D65F	006A
R	1D660	006B
R	1D661	006C
R	1D662	006D
R	1D663	006E
R	1D664	006F
R	1D665	0070
R	1D666	0071
R	1D667	0072
R	1D668	0073
R	1D669	0074
R	1D66A	0075
R	1D66B	0076
R	1D66C	0077
R	1D66D	0078
R	1D66E	0079
R	1D66F	007A
R	1D670	0061
R	1D671	0062
R	1D672	0063
R	1D673	0064
R	1D674	0065
R	1D675	0066
R	1D676	0067
R	1D677	0068
R	1D678	0069
R	1D679	006A
R	1D67A	006B
R	1D67B	006C
R	1D67C	006D
R	1D67D	006E
R	1D67E	006F
R	1D67F	0070
R	1D680	0071
R	1D681	0072
R	1D682	0073
R	1D683	0074
R	1D684	0075
R	1D685	0076
R	1D686	0077
R	1D687	0078
R	1D688	0079
R	1D689	007A
R	1D68A	0061
R	1D68B	0062
R	1D68C	0063
R	1D68D	0064
R	1D68E	0065
R	1D68F	0066
R	1D690	0067
R	1D691	0068
R	1D692	0069
R	1D693	006A
R	1D694	006B
R	1D695	006C
R	1D696	006D
R	1D697	006E
R	1D698	006F
R	1D699	0070
R	1D69A	0071
R	1D69B	0072
R	1D69C	0073
R	1D69D	0074
R	1D69E	0075
R	1D69F	0076
R	1D6A0	0077
R	1D6A1	0078
R	1D6A2	0079
R	1D6A3	007A
R	1D6A4	0069
R	1D6A8	0061
R	1D6A9	0073 0073
R	1D6AA	0079
R	1D6AC	0065
R	1D6AD	007A
R	1D6AE	0068
R	1D6B0	0069
R	1D6B1	006B
R	1D6B3	006D
R	1D6B4	0076
R	1D6B6	006F
R	1D6B8	0070
R	1D6BA	006F
R	1D6BB	0074
R	1D6BC	0075
R	1D6BE	0078
R	1D6C2	0061
R	1D6C3	0073 0073
R	1D6C4	0079
R	1D6CA	0069
R	1D6CE	0076
R	1D6D0	006F
R	1D6D2	0070
R	1D6D3	006F
R	1D6D4	006F
R	1D6D6	0075
R	1D6E0	0070
R	1D6E2	0061
R	1D6E3	0073 0073
R	1D6E4	0079
R	1D6E6	0065
R	1D6E7	007A
R	1D6E8	0068
R	1D6EA	0069
R	1D6EB	006B
R	1D6ED	006D
R	1D6EE	0076
R	1D6F0	006F
R	1D6F2	0070
R	1D6F4	006F
R	1D6F5	0074
R	1D6F6	0075
R	1D6F8	0078
R	1D6FC	0061
R	1D6FD	0073 0073
R	1D6FE	0079
R	1D704	0069
R	1D708	0076
R	1D70A	006F
R	1D70C	0070
R	1D70D	006F
R	1D70E	006F
R	1D710	0075
R	1D71A	0070
R	1D71C	0061
R	1D71D	0073 0073
R	1D71E	0079
R	1D720	0065
R	1D721	007A
R	1D722	0068
R	1D724	0069
R	1D725	006B
R	1D727	006D
R	1D728	0076
R	1D72A	006F
R	1D72C	0070
R	1D72E	006F
R	1D72F	0074
R	1D730	0075
R	1D732	0078
R	1D736	0061
R	1D737	0073 0073
R	1D738	0079
R	1D73E	0069
R	1D742	0076
R	1D744	006F
R	1D746	0070
R	1D747	006F
R	1D748	006F
R	1D74A	0075
R	1D754	0070
R	1D756	0061
R	1D757	0073 0073
R	1D758	0079
R	1D75A	0065
R	1D75B	007A
R	1D75C	0068
R	1D75E	0069
R	1D75F	006B
R	1D761	006D
R	1D762	0076
R	1D764	006F
R	1D766	0070
R	1D768	006F
R	1D769	0074
R	1D76A	0075
R	1D76C	0078
R	1D770	0061
R	1D771	0073 0073
R	1D772	0079
R	1D778	0069
R	1D77C	0076
R	1D77E	006F
R	1D780	0070
R	1D781	006F
R	1D782	006F
R	1D784	0075
R	1D78E	0070
R	1D790	0061
R	1D791	0073 0073
R	1D792	0079
R	1D794	0065
R	1D795	007A
R	1D796	0068
R	1D798	0069
R	1D799	006B
R	1D79B	006D
R	1D79C	0076
R	1D79E	006F
R	1D7A0	0070
R	1D7A2	006F
R	1D7A3	0074
R	1D7A4	0075
R	1D7A6	0078
R	1D7AA	0061
R	1D7AB	0073 0073
R	1D7AC	0079
R	1D7B2	0069
R	1D7B6	0076
R	1D7B8	006F
R	1D7BA	0070
R	1D7BB	006F
R	1D7BC	006F
R	1D7BE	0075
R	1D7C8	0070
R	1D7CA	0066
R	1D7CE	0030
R	1D7CF	0031
R	1D7D0	0032
R	1D7D1	0033
R	1D7D2	0034
R	1D7D3	0035
R	1D7D4	0036
R	1D7D5	0037
R	1D7D6	0038
R	1D7D7	0039
R	1D7D8	0030
R	1D7D9	0031
R	1D7DA	0032
R	1D7DB	0033
R	1D7DC	0034
R	1D7DD	0035
R	1D7DE	0036
R	1D7DF	0037
R	1D7E0	0038
R	1D7E1	0039
R	1D7E2	0030
R	1D7E3	0031
R	1D7E4	0032
R	1D7E5	0033
R	1D7E6	0034
R	1D7E7	0035
R	1D7E8	0036
R	1D7E9	0037
R	1D7EA	0038
R	1D7EB	0039
R	1D7EC	0030
R	1D7ED	0031
R	1D7EE	0032
R	1D7EF	0033
R	1D7F0	0034
R	1D7F1	0035
R	1D7F2	0036
R	1D7F3	0037
R	1D7F4	0038
R	1D7F5	0039
R	1D7F6	0030
R	1D7F7	0031
R	1D7F8	0032
R	1D7F9	0033
R	1D7FA	0034
R	1D7FB	0035
R	1D7FC	0036
R	1D7FD	0037
R	1D7FE	0038
R	1D7FF	0039
R	1E030	0061
R	1E031	0036
R	1E033	0072
R	1E035	0065
R	1E03C	006F
R	1E03E	0070
R	1E03F	0063
R	1E041	0079
R	1E043	0078
R	1E046	0077
R	1E04C	0069
R	1E04D	006A
R	1E04F	0079
R	1E050	006C
R	1E051	0061
R	1E052	0036
R	1E054	0072
R	1E056	0065
R	1E05C	006F
R	1E05E	0063
R	1E05F	0079
R	1E061	0078
R	1E064	0077
R	1E067	0072 0027
R	1E068	0069
R	1E069	0073
R	1E6E9	002B
R	1E8C7	006C
R	1E8CB	0038
R	1EE00	006C
R	1EE24	006F
R	1EE64	006F
R	1EE80	006C
R	1EE84	006F
R	1F100	0030 002E
R	1F101	0030 002C
R	1F102	0031 002C
R	1F103	0032 002C
R	1F104	0033 002C
R	1F105	0034 002C
R	1F106	0035 002C
R	1F107	0036 002C
R	1F108	0037 002C
R	1F109	0038 002C
R	1F10A	0039 002C
R	1F110	0028 0061 0029
R	1F111	0028 0062 0029
R	1F112	0028 0063 0029
R	1F113	0028 0064 0029
R	1F114	0028 0065 0029
R	1F115	0028 0066 0029
R	1F116	0028 0067 0029
R	1F117	0028 0068 0029
R	1F118	0028 0069 0029
R	1F119	0028 006A 0029
R	1F11A	0028 006B 0029
R	1F11B	0028 006C 0029
R	1F11C	0028 006D 0029
R	1F11D	0028 006E 0029
R	1F11E	0028 006F 0029
R	1F11F	0028 0070 0029
R	1F120	0028 0071 0029
R	1F121	0028 0072 0029
R	1F122	0028 0073 0029
R	1F123	0028 0074 0029
R	1F124	0028 0075 0029
R	1F125	0028 0076 0029
R	1F126	0028 0077 0029
R	1F127	0028 0078 0029
R	1F128	0028 0079 0029
R	1F129	0028 007A 0029
R	1F12A	0028 0073 0029
R	1F12B	0063
R	1F12C	0072
R	1F12D	0063 0064
R	1F12E	0077 007A
R	1F130	0061
R	1F131	0062
R	1F132	0063
R	1F133	0064
R	1F134	0065
R	1F135	0066
R	1F136	0067
R	1F137	0068
R	1F138	0069
R	1F139	006A
R	1F13A	006B
R	1F13B	006C
R	1F13C	006D
R	1F13D	006E
R	1F13E	006F
R	1F13F	0070
R	1F140	0071
R	1F141	0072
R	1F142	0073
R	1F143	0074
R	1F144	0075
R	1F145	0076
R	1F146	0077
R	1F147	0078
R	1F148	0079
R	1F149	007A
R	1F14A	0068 0076
R	1F14B	006D 0076
R	1F14C	0073 0064
R	1F14D	0073 0073
R	1F14E	0070 0070 0076
R	1F14F	0077 0063
R	1F16A	006D 0063
R	1F16B	006D 0064
R	1F16C	006D 0072
R	1F190	0064 006A
R	1F240	0028 672C 0029
R	1F241	0028 4E09 0029
R	1F242	0028 4E8C 0029
R	1F243	0028 5B89 0029
R	1F244	0028 70B9 0029
R	1F245	0028 6253 0029
R	1F246	0028 76D7 0029
R	1F247	0028 52DD 0029
R	1F248	0028 6557 0029
R	1F700	0071 0065
R	1F707	0061 0072
R	1F74C	0063
R	1F75C	0073 0073 0073
R	1F768	0074
R	1F76B	006D 0062
R	1F76C	0076 0062
R	1FBF0	0030
R	1FBF1	0031
R	1FBF2	0032
R	1FBF3	0033
R	1FBF4	0034
R	1FBF5	0035
R	1FBF6	0036
R	1FBF7	0037
R	1FBF8	0038
R	1FBF9	0039
"""
# END READING TABLE

PROVISIONAL_KEYS = {status_key(s): s for s in STATUSES}


if __name__ == "__main__":
    sys.exit(run(sys.argv))
