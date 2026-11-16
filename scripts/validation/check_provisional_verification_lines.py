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
sidecar appears next to it and its bytes are unchanged. A status is matched as a person reads it (NFKC folded,
look-alike letters mapped, format characters removed, white space collapsed, case folded): a status that reads as
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
missing a container or paragraph-state transition, section 11.4.250, section 11.4.276(E)(3)). The checker no longer
models CommonMark by hand: the body is parsed by a real CommonMark parser, markdown-it-py with its `commonmark` preset
(the version must be one of MDIT_TESTED; a missing or untested parser makes the run BLIND, never a pass), and the
parser's token stream is the only source of the decision:
  COUNTED  a line counts when it is the first source line of a TOP-LEVEL paragraph (token paragraph_open at level 0,
           its map gives the line), the source line starts with the prefix at column 0, and the paragraph's inline
           content starts with the bold `Verification:`. Source lines are the parser's own (its line endings: LF, CR LF,
           a lone CR; NUL read as U+FFFD), so the checker and the parser cannot split a body differently.
  RAW HTML any HTML block or inline HTML token that is not made only of complete comments refuses the body: raw HTML
           can hide or wrap a line (`hidden`, `display:none`, `<details>`, a `<style>` anywhere), and readers disagree
           on where an HTML block ends (`<!-->`), so a body with it is refused rather than judged.
  ELSEWHERE the body is refused when the Verification label (THE NEAR RULE's reading) occurs anywhere other than at the
           start of the one counted line: in any other source line, or in the text a reader renders anywhere in the
           document (other paragraphs, headings, block quotes, list items, code spans, code blocks, fences, comments,
           link titles and targets, image text, and the counted paragraph after its label). Such a body is refused
           rather than judged, because whether a reader shows that text as a verification line depends on the reader.
The test harnesses check this against independent readers: tests/release/pvl_blockstate.py enumerates the container
and paragraph-state class and renders every accepted body with markdown-it-py, pandoc commonmark and pandoc gfm;
tests/release/pvl_lineend.py enumerates the line-ending and start-of-line class.
THE NEAR RULE: the label is the word Verification and a colon, read with character references decoded, NFKC folding,
look-alike letters mapped and format characters removed, markup or spaces allowed before the colon.

Known limits (stated): a sentence of the grammar can still be false (a real script that is not the right job, counts
that will not be observed, a commit id that is not the fix: commit and tag ids are shape-checked, the checker runs no
process); a selector, option or env value is accepted when the script merely mentions it. It does NOT check whether a
due date is past (derive_release_facts.sh reports that) or whether the job was run. The reader is CommonMark: syntax of
other dialects (pandoc fenced divs and attributes, kramdown attribute lists, GFM) is read as CommonMark text; the
enumeration renders accepted bodies with pandoc gfm too, other dialects are a stated gap. False refusals, the safe
direction: a body holding any raw HTML other than complete comments, or the label anywhere else (also inside code).

Output: one `FAIL <id> <status>: <reason>` line per refused item, then `ROOT: <real root>` and `TODAY: <date>
window=<N>d`, then `CHECKED items=N provisional_status=P ok=K fail=F`, then `VERDICT: PASS|FAIL|BLIND`. Exit 0 PASS,
1 FAIL, 2 BLIND (the database cannot be read, a database file or sidecar is not a regular file or exceeds the size
bound, it has no items table, or holds no items: a zero there proves nothing; the CommonMark parser is missing or is
not a tested version), 64
usage (also a root that is not a directory, a --today that is not a date, a window that is not 0..3650).
"""

import datetime
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
# construction; this map only names the look-alike in the refusal reason. scripts/release/render_release_entry.py holds
# the same map as a reader (tests/release/test_render_release_entry.sh compares the two).
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
_MD = []
MAX_BODY = 1024 * 1024

# a line ending of the target registry (and of CommonMark 2.1): LF, CR LF, or a CR not followed by LF
LINE_END = re.compile(r"\r\n|\r|\n")
# the label a person reads as a verification statement, in any case, with markup or spaces before the colon
LABEL = re.compile(r"verification[\s*_~`\\]*(?:</?[a-z][^>]*>[\s*_~`\\]*)*:", re.I)
COMMENT = re.compile(r"<!--.*?-->", re.S)


def reader_problem():
    """None when the CommonMark parser is importable and a tested version; else the reason (the run is BLIND)."""
    if _MarkdownIt is None:
        return "markdown-it-py cannot be imported (%s)" % _MDIT_ERROR
    if MDIT_VERSION not in MDIT_TESTED:
        return "markdown-it-py %s is not a tested version (%s)" % (MDIT_VERSION, ", ".join(MDIT_TESTED))
    return None


def _md():
    if not _MD:
        _MD.append(_MarkdownIt("commonmark"))
    return _MD[0]


def has_label(s):
    """True when S, read the way a person reads it (character references decoded, NFKC folded, look-alike letters
    mapped, format characters such as ZWJ or a soft hyphen removed), holds the word Verification followed by a colon."""
    t = unicodedata.normalize("NFKC", html.unescape(s))
    t = "".join(CONFUSABLES.get(c, c) for c in t if unicodedata.category(c) != "Cf")
    return LABEL.search(t) is not None


def _is_label_start(children):
    """True when inline CHILDREN start (empty text skipped) with strong_open, text `Verification:`, strong_close."""
    ch = [c for c in children if not (c.type == "text" and c.content == "")]
    return (len(ch) >= 3 and ch[0].type == "strong_open" and ch[1].type == "text" and ch[1].content == "Verification:"
            and ch[2].type == "strong_close")


def _rendered(children, skip_label):
    """The text a reader renders from inline CHILDREN (markup removed, so `Veri*fi*cation:` reads as the word); with
    SKIP_LABEL the leading bold label of the counted line is left out."""
    out = []
    seen = 0
    for c in children:
        if skip_label and seen < 3:
            if c.type == "text" and c.content == "":
                continue
            seen += 1
            continue
        if c.type in ("text", "code_inline"):
            out.append(c.content)
        elif c.type == "html_inline":
            out.append(COMMENT.sub("", c.content))
            out.extend(COMMENT.findall(c.content))
        elif c.type in ("softbreak", "hardbreak"):
            out.append("\n")
        for _k, v in (c.attrs or {}).items():
            out.append("\n%s\n" % v)
        if c.children:
            out.append(_rendered(c.children, False))
    return "".join(out)


def scan(body):
    """(counted, problems): the counted lines of BODY and the reasons it cannot be judged (raw HTML, the label
    elsewhere); see THE LINE MODEL. The caller checks reader_problem() first."""
    toks = _md().parse(body)
    lines = _MDIT_NULL.sub("\ufffd", _MDIT_NEWLINES.sub("\n", body)).split("\n")
    counted = []    # (source line index, line)
    texts = []      # rendered text of the document outside the counted label
    problems = []
    for i, t in enumerate(toks):
        if t.type in ("html_block", "html_inline") and COMMENT.sub("", t.content).strip():
            problems.append("raw HTML %r" % t.content.strip()[:40])
        for c in t.children or []:
            if c.type == "html_inline" and COMMENT.sub("", c.content).strip():
                problems.append("raw HTML %r" % c.content.strip()[:40])
        if t.type == "inline":
            prev = toks[i - 1]
            first = None
            if (prev.type == "paragraph_open" and prev.level == 0 and prev.map is not None
                    and _is_label_start(t.children or [])):
                ln = lines[prev.map[0]]
                if ln.startswith(PREFIX) and (len(ln) == len(PREFIX) or ln[len(PREFIX)] in " ("):
                    first = prev.map[0]
                    counted.append((first, ln))
            texts.append(_rendered(t.children or [], first is not None))
        elif t.type in ("code_block", "fence", "html_block"):
            texts.append(t.info + "\n" + COMMENT.sub("", t.content))
            texts.extend(COMMENT.findall(t.content))
        for _k, v in (t.attrs or {}).items():
            texts.append(v)
    keep = {j for j, _ in counted}
    if has_label("\n".join(ln for j, ln in enumerate(lines) if j not in keep)):
        problems.append("label in another source line")
    elif any(has_label(x) for x in texts):
        problems.append("label in the rendered text")
    return [ln for _, ln in counted], problems


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
    html_p = [x for x in problems if x.startswith("raw HTML")]
    if html_p:
        return ("the body holds raw HTML other than complete comments (%s): a reader may hide or wrap a line with it, "
                "so which lines are visible is not certain" % html_p[0])
    if problems:
        return ("a line a reader shows carries the Verification label but is not the one counted line (the label "
                "occurs outside the start of the one top-level paragraph that starts with the prefix at column 0: %s)"
                % problems[0])
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
    """The status as a person reads it: bytes decoded, NFKC folded, look-alike letters mapped, format characters
    removed, runs of white space made one space, outer white space removed, case folded."""
    if isinstance(st, (bytes, bytearray)):
        st = bytes(st).decode("utf-8", "replace")
    if not isinstance(st, str):
        return None
    t = unicodedata.normalize("NFKC", st)
    t = "".join(CONFUSABLES.get(c, c) for c in t if unicodedata.category(c) != "Cf")
    return " ".join(t.split()).casefold()


PROVISIONAL_KEYS = {status_key(s): s for s in STATUSES}


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


if __name__ == "__main__":
    sys.exit(run(sys.argv))
