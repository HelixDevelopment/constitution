#!/usr/bin/env python3
"""scripts/validation/check_provisional_verification_lines.py -- every PROVISIONAL-DONE item names its verification job.

Usage:
  python3 -I scripts/validation/check_provisional_verification_lines.py [--root DIR] [DB]
                                                            (default DB: docs/workable_items.db)

Section 11.4.290: an item counts as PROVISIONAL-DONE while its Status is `Ready for testing` or `In testing`, and
that state needs a scheduled verification job recorded on one line. The canon (section 11.4.290, the paragraph after
the state table) writes the line without colons,

  **Verification:** provisional — job <id> — checks <runtime signature> — layer <...> — target <fingerprint> — artifact <fix fingerprint> — due <ISO timestamp>

and this project writes it with colons (`-- job: ... -- checks: ...`). Both forms are accepted, field by field (the
separator is " -- " or " — "; an em dash or a "--" with white space on both sides is therefore never a field value).
This checker reads the tracker database (the single source of truth, section 11.4.93; opened read-only, never
written) and refuses an item of those two statuses whose body has no such line, more than one, a line longer than
4096 characters, a missing, repeated or out-of-order field, or a field that is not complete.

A line counts only when it starts at column 0 with `**Verification:** provisional` followed by white space, `(` or
the end of the line (so `provisionalXYZ` is not the prefix), and is OUTSIDE a fenced code block (``` or ~~~ with up to
3 spaces of indent; a fence closes on a line of the same character, at least as long, with nothing after it; an
unclosed fence runs to the end of the body) and OUTSIDE an HTML comment block (a line that starts, after up to 3
spaces, with `<!--` opens one unless `-->` follows on the same line; the block ends with the line that holds `-->`; an
unclosed comment runs to the end of the body; a comment is not visible text). A quoted, indented, fenced or commented
copy is text.

A COMPLETE field (CON-423; rebuilt in review round 4 as a structural round, section 11.4.276(E)(3): ONE scan of the
value feeds every word rule). The class and every member are listed in docs/qa/rehearsal_v73_4_fix/r4/class_inventory.md
and tests/release/pvl_inventory.py builds a probe grid from that inventory and from the Unicode database itself.

THE SCAN (function scan). The value is cleaned: every INVISIBLE or NON-TEXT character is removed and recorded (a
Default_Ignorable_Code_Point of Unicode, such as U+200B, U+3164 HANGUL FILLER, the variation selectors and the tag
block; and every character of the general categories Cc (except TAB), Cf, Cs, Co, Cn, Zl, Zp); then NFKD, every
combining mark (Mn, Mc, Me) removed, NFKC (full-width, mathematical, enclosed and Roman-numeral letters fold to ASCII).
The cleaned value is cut into TOKENS: maximal runs of letters and digits (str.isalnum); every
other character is a separator. Each token gets a SKELETON for the word rules: a decimal digit of any script becomes its
ASCII digit, a Latin letter outside ASCII becomes the base letter its Unicode name gives (LATIN LETTER SMALL CAPITAL T
is T, LATIN CAPITAL LETTER D WITH STROKE is D, a Latin ligature or digraph its letters), and the closed CONFUSABLES map turns Cyrillic and Greek letters that look
like Latin ones into those letters. A token is read as its skeleton, its 0->o and 1->i reading (T0D0, F1XME) and its
letter and digit parts (TBD1). A RUN of single letters (consecutive tokens, or letter parts, of one letter each, in any
separators: T.B.D, T/B/D, T·B·D, T B D, t_b_d) is read as the joined letters.

THE RULES, in this order; the first that fails is the reason:
  1. empty -- nothing but white space and . , ; : once the invisible characters are removed.
  2. punctuation only -- no letter or digit at all (`-`, `–`, `?`).
  3. placeholder at the start (the LEADING-WORD rule, on the tokens; openers and punctuation are separators):
     (a) every field: the first token, one of the first three tokens of the first word, or a prefix of a leading run
         of single letters is a STRONG word: TBD, TBA, TBC, TODO, FIXME, XXX, UNCONFIRMED or LOREM;
     (b) job, target, artifact, layer, due: the first token (or the joined leading run of single letters) is a WEAK
         word (unknown, pending, none, n/a, na, null, nil, placeholder, dummy, later, soon, eventually, someday, asap)
         or a LEAD-ONLY word (nobody, nothing, nope, noone, never, maybe), when that token stands alone as the first
         word or the first word is the whole value apart from a bracketed note (so `none/yet`, `pending.sh`,
         `n.a/n.a` and `none-yet (x)` are refused and `pending-lock check passes` is a statement); or the first token
         is "not" or "no" and more tokens follow; or the value starts with "to / will / shall / should / would be";
     (c) checks the same, except: the lead-only words do not apply, "none of ..." is a statement, "no ..." is a
         statement (golden: none of the mutants survives, no pending lock remains), and "not" is refused only before
         one of applicable, available, assigned, known, scheduled, yet, set, defined, decided, determined, run, done,
         started, planned, or as the first part of a whole-value compound (not-applicable).
  4. starts with no word -- the first word after the openers holds no letter or digit (`??? later`, `--- later`).
  5. placeholder word inside -- a token (any reading, any part) TBD, TBA, TBC, TODO or FIXME in any case, or XXX in
     capitals; or a run of single letters anywhere that holds one of them (every suite T/B/D).
  6. template placeholder -- `<word ...>` (the canon's own `<id>`, `<ISO timestamp>`), `{{...}}` or `${...}`.
  7. placeholder at the end -- the last token is later, pending, soon, eventually, someday, asap, unknown,
     placeholder or dummy ("yet" is not one: "no review yet" is a statement; in every field but checks also none, na, n/a, null, nil): `host later`, `host (pending)`,
     `host? none`; or a bracketed note starts with a weak word (`host (pending scheduler)`; in checks "none" excepted).
  8. shape, per field (POSITIVE: the value must name something of its kind; every shape reads ASCII only, without
     the look-alike map, so a look-alike letter never satisfies a shape):
     job      -- at least one ANCHOR: a PATH (a whole word of ASCII letters, digits and _ . + - with at least one /, or
                 a file name ending in .sh .bash .py .go .js .ts .mjs .bats .mk .yaml .yml .json .toml); a COMMAND
                 (bash, sh, python3, python, go, make, node, npm, npx, pytest, git) with an option (-x or --word), a
                 path or ./... among the next two words (go test ./...); or a JOB ID <KEY>-<digits> (KEY 2 to 16
                 capital letters or digits starting with a letter, digits not all zero; for example JOB-42). With
                 --root DIR a path counts only when it exists under DIR: no `..` part, and its real path lies inside
                 the real DIR and is not DIR itself (an absolute path outside DIR, such as /etc/passwd, is refused).
                 Without --root a path counts by its shape only (the output says `PATHS: shape-only`), and a path
                 whose words hold a weak or lead-only word (none/yet, pending.sh, sometime/maybe) is not an anchor;
                 run with --root wherever the checkout is at hand (CON-423's own job does);
     checks   -- at least 3 letters or digits, and an OUTCOME: a digit, or one of the OUTCOME_WORDS (passed, failed,
                 killed, survives, rc, verdict, identical, refused, remains, three, every, ...): a runtime signature
                 names what was observed;
     layer    -- the first word is one of: user-visible, runtime, artifact, source (the section 11.4.290 classes),
                 host-only, live-target (the section 11.4.292 surfaces), gate-logic (this project's word for a test of
                 a gate's own logic, section 11.4.289(C)(2));
     target   -- at least 3 letters or digits, and at least one TARGET word: host, hosts, board, boards, device,
                 devices, container, containers, runner, runners, vm, emulator, image, sandbox, scratch, server,
                 machine, checkout, clone, worktree, repo, repository, remote, remotes, cluster, ci;
     artifact -- names a fingerprint or a ref: a hex token of 7 to 64 characters with a digit, or one of the words
                 commit, main, tag, branch, merge, vehicle, image, build, sha256;
     due      -- starts with a real calendar date YYYY-MM-DD in ASCII digits, year 2000 to 2099, optionally followed by
                 an ISO time (THH:MM[:SS][Z|+HH:MM]); after the date comes the end of the value, white space or one of
                 . , ; ( . An event such as "next full-suite run" is not a due time: section 11.4.290(C) names "a due
                 time (the staleness budget)" and (E) reports an item past it as OVERDUE, which an event cannot be.
  9. text class -- (a) an invisible or non-text character (rule of THE SCAN; `artifactㅤ`, `ㅤ host`, a soft hyphen,
     a bidi control) is refused even when the rest is complete; (b) a letter or digit outside the DECLARED SCRIPTS
     (Latin, Cyrillic, Greek; the Unicode name gives the script) is refused (Armenian, Cherokee, Hangul, Bengali
     digits, CJK): look-alikes of those scripts are therefore never read; (c) a token that mixes letters of two of
     the declared scripts (`раssed`, Cyrillic р and a) is refused.

Where `UNCONFIRMED:` is legal (sections 11.4.6, 11.4.290, 11.4.292). Section 11.4.292(C) writes a field of the
REPRODUCTION record that could not be captured as `UNCONFIRMED: <reason>`, and such a record is not REPRODUCED.
Section 11.4.290(C) says a marking without a scheduled job is refused and the item stays In progress; it names no
UNCONFIRMED form for the verification line. So in a verification line a field whose value IS `UNCONFIRMED...` (rule
3a) is a field that could not be captured, and the line is refused. `UNCONFIRMED` stays legal AFTER a complete value,
as an honest qualifier of it, for example `due: 2026-11-23 (UNCONFIRMED: date set by the fixer; no scheduler entry
exists)` or `target: host, repo checkout; consumer layout UNCONFIRMED here`; the qualifier never makes a field complete
by itself. This checker does not read Reproduction lines.

Known limits (stated, not fixed): a value that has the right shape but is false (a path that exists but is not the
job, `git -x`, a job id no scheduler knows, a target word that is not where the job runs, `board target`, a checks
sentence with an outcome word that is not what was observed) is not detected; without --root an absent path of a good
shape (scripts/nonexistent.sh) is accepted; Cyrillic and Greek look-alikes outside the closed map in a token of one
script (lower-case Cyrillic т, в, к, м, н) are not folded; the outcome, target and layer words are English, so a Serbian
or Russian value is refused (the conservative direction); a <KEY>-<digits> job id cannot be told from a tracker id. It
does NOT check whether a due date is past (derive_release_facts.sh reports that) or whether the job was run.

It found the class of CON-423 (rehearsal of the v73.4 cut, D2): four Ready-for-testing items with no line, so the
release count line said 25 provisional while 29 items were Ready for testing, and two lines with no `checks` field.

Output: one `FAIL <id> <status>: <reason>` line per refused item, then `PATHS: exist-under <DIR>` or `PATHS:
shape-only`, then `CHECKED items=N provisional_status=P ok=K fail=F`, then `VERDICT: PASS|FAIL|BLIND`. Exit 0 PASS,
1 FAIL, 2 BLIND (the database cannot be read, has no items table, or holds no items at all: a zero there proves
nothing), 64 usage (also a --root that is not a directory).
"""

import datetime
import os
import re
import sqlite3
import sys
import unicodedata

STATUSES = ("Ready for testing", "In testing")
FIELDS = ("job", "checks", "layer", "target", "artifact", "due")
MAX_LINE = 4096
PREFIX_RE = re.compile(r"\*\*Verification:\*\* provisional(?=[\s(]|\Z)")
# the look-behind makes the split linear: a run of white space is tried once, at its first character (CON-423 r4 F1)
SEP = re.compile(r"(?<!\s)\s+(?:--|—)\s+")
FIELD_PART = re.compile(r"(job|checks|layer|target|artifact|due)(?=[\s:]|\Z):?(.*)\Z", re.S)
FENCE = re.compile(r" {0,3}(`{3,}|~{3,})")
COMMENT_OPEN = re.compile(r" {0,3}<!--")

OPENERS = "([{<\"'`*"
EDGE_PUNCT = ".,;:)]}>\"'`*!?"
# Cyrillic and Greek letters that look like ASCII letters: a closed map (the Latin-looking subset of the Unicode
# confusables data); a look-alike outside it is a stated limit. scripts/release/render_release_entry.py holds the same
# map (tests/release/test_render_release_entry.sh compares them).
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
# Default_Ignorable_Code_Point (Unicode DerivedCoreProperties.txt, unchanged from Unicode 6 to 16): Python's
# unicodedata has no such property, so the ranges are written out; tests/release/pvl_inventory.py checks each one.
DEFAULT_IGNORABLE = ((0x00AD, 0x00AD), (0x034F, 0x034F), (0x061C, 0x061C), (0x115F, 0x1160), (0x17B4, 0x17B5),
                     (0x180B, 0x180F), (0x200B, 0x200F), (0x202A, 0x202E), (0x2060, 0x206F), (0x3164, 0x3164),
                     (0xFE00, 0xFE0F), (0xFEFF, 0xFEFF), (0xFFA0, 0xFFA0), (0xFFF0, 0xFFF8), (0x1BCA0, 0x1BCA3),
                     (0x1D173, 0x1D17A), (0xE0000, 0xE0FFF))
NONTEXT_CATEGORIES = frozenset(("Cc", "Cf", "Cs", "Co", "Cn", "Zl", "Zp"))
MARK_CATEGORIES = frozenset(("Mn", "Mc", "Me"))
DECLARED_SCRIPTS = ("LATIN", "CYRILLIC", "GREEK")
STRONG_WORDS = frozenset(("tbd", "tba", "tbc", "todo", "fixme", "xxx", "unconfirmed", "lorem"))
INSIDE_ANY_CASE = frozenset(("tbd", "tba", "tbc", "todo", "fixme"))
INSIDE_CAPITALS = frozenset(("XXX",))
WEAK_WORDS = frozenset(("unknown", "pending", "none", "n/a", "na", "null", "nil", "placeholder", "dummy", "later",
                        "soon", "eventually", "someday", "asap"))
LEAD_ONLY_WORDS = frozenset(("nobody", "nothing", "nope", "noone", "never", "maybe"))
TRAIL_WORDS = frozenset(("later", "pending", "soon", "eventually", "someday", "asap", "unknown", "placeholder",
                         "dummy"))
TRAIL_WORDS_NOT_CHECKS = frozenset(("none", "na", "null", "nil"))
BE_LEADS = frozenset(("to", "will", "shall", "should", "would"))
CHECKS_NOT_WORDS = frozenset(("applicable", "available", "assigned", "known", "scheduled", "yet", "set", "defined",
                              "decided", "determined", "run", "done", "started", "planned"))
OUTCOME_WORDS = frozenset((
    "pass", "passes", "passed", "passing", "fail", "fails", "failed", "failing", "failure", "failures", "kill", "kills",
    "killed", "survive", "survives", "survived", "surviving", "ok", "okay", "rc", "exit", "exits", "exited", "verdict",
    "green", "red", "identical", "equal", "equals", "agree", "agrees", "agreed", "match", "matches", "matched", "fire",
    "fires", "fired", "quiet", "refuse", "refuses", "refused", "accept", "accepts", "accepted", "print", "prints",
    "printed", "report", "reports", "reported", "give", "gives", "return", "returns", "returned", "remain", "remains",
    "error", "errors", "warning", "warnings", "clean", "absent", "present", "found", "missing", "detected", "caught",
    "blocked", "stale", "fresh", "sync", "valid", "invalid", "blind", "skip", "skips", "skipped", "count", "counts",
    "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve", "all",
    "every", "each", "both"))
TEMPLATE = re.compile(r"<[A-Za-z][A-Za-z0-9 _-]{0,40}>|\{\{.*?\}\}|\$\{[^}]*\}")
LAYER_VOCAB = ("user-visible", "runtime", "artifact", "source", "host-only", "live-target", "gate-logic")
ARTIFACT_WORDS = re.compile(r"\b(commit|main|tag|branch|merge|vehicle|image|build|sha256)\b", re.I)
HEX = re.compile(r"\b(?=[0-9a-f]*[0-9])[0-9a-f]{7,64}\b")
DUE = re.compile(r"([0-9]{4})-([0-9]{2})-([0-9]{2})(T[0-9]{2}:[0-9]{2}(:[0-9]{2})?(Z|[+-][0-9]{2}:[0-9]{2})?)?"
                 r"(?=\Z|[\s.,;(])")
PATH_TOKEN = re.compile(r"(?:\./|/)?[A-Za-z0-9_][A-Za-z0-9_.+-]*(?:/[A-Za-z0-9_.+-]+)+/?\Z")
FILE_TOKEN = re.compile(r"[A-Za-z0-9_][A-Za-z0-9_.+-]*\.(?:sh|bash|py|go|js|ts|mjs|bats|mk|yaml|yml|json|toml)\Z")
COMMANDS = frozenset(("bash", "sh", "python3", "python", "go", "make", "node", "npm", "npx", "pytest", "git"))
OPTION = re.compile(r"--?[A-Za-z][A-Za-z0-9_-]*(?:=\S*)?\Z")
JOB_ID = re.compile(r"[A-Z][A-Z0-9]{1,15}-(?=[0-9]*[1-9])[0-9]+\Z")
TARGET_WORDS = frozenset(("host", "hosts", "board", "boards", "device", "devices", "container", "containers", "runner",
                          "runners", "vm", "emulator", "image", "sandbox", "scratch", "server", "machine", "checkout",
                          "clone", "worktree", "repo", "repository", "remote", "remotes", "cluster", "ci"))


def blind(msg):
    print("BLIND %s" % msg)
    print("VERDICT: BLIND")
    return 2


def unfenced_lines(body):
    """Lines of the body outside fenced code blocks and outside HTML comment blocks."""
    out, fence, comment = [], None, False
    for ln in (body or "").splitlines():
        if comment:
            if "-->" in ln:
                comment = False
            continue
        m = FENCE.match(ln)
        if fence is None:
            if m:
                fence = m.group(1)
            elif COMMENT_OPEN.match(ln):
                comment = "-->" not in ln[ln.index("<!--") + 4:]
            else:
                out.append(ln)
        elif m and m.group(1)[0] == fence[0] and len(m.group(1)) >= len(fence) and not ln[m.end():].strip():
            fence = None
    return out


def is_invisible(ch):
    """True for a Default_Ignorable_Code_Point or a character of a non-text category (TAB excepted)."""
    o = ord(ch)
    if any(lo <= o <= hi for lo, hi in DEFAULT_IGNORABLE):
        return True
    return ch != "\t" and unicodedata.category(ch) in NONTEXT_CATEGORIES


def script_of(ch):
    """LATIN, CYRILLIC, GREEK, another script word of the Unicode name, or COMMON for an ASCII digit."""
    if ch.isascii():
        return "COMMON" if ch.isdigit() else "LATIN"
    return unicodedata.name(ch, "UNNAMED").split(" ", 1)[0]


def skeleton_char(ch):
    """The character the word rules read: an ASCII digit, a Latin base letter, or a look-alike mapped to Latin."""
    if ch.isascii():
        return ch
    if unicodedata.decimal(ch, None) is not None:
        return str(unicodedata.decimal(ch))
    if ch in CONFUSABLES:
        return CONFUSABLES[ch]
    words = unicodedata.name(ch, "").split()
    key = next((w for w in ("LETTER", "LIGATURE") if w in words), None)
    if words[:1] == ["LATIN"] and key:
        before, after = words[:words.index(key)], words[words.index(key) + 1:]
        small = "SMALL" in before
        if key == "LIGATURE" or "DIGRAPH" in after or (after[:1] and after[0] in ("AE", "OE", "IJ")):
            base = next((w for w in after if 2 <= len(w) <= 3 and w.isalpha() and w.isascii()), None)
        else:
            base = next((w for w in after if len(w) == 1 and "A" <= w <= "Z"), None)
        if base:
            return base.lower() if small else base
    return ch


def compat_char(ch):
    """A character whose NFKC form holds exactly one letter or digit and otherwise punctuation (PARENTHESIZED LATIN
    SMALL LETTER T is "(t)", DIGIT ONE FULL STOP is "1.") becomes that letter or digit: one character, one letter."""
    if ch.isascii():
        return ch
    n = unicodedata.normalize("NFKC", ch)
    al = [c for c in n if c.isalnum()]
    return al[0] if n != ch and len(al) == 1 else ch


def clean(raw):
    """(the cleaned value, the invisible and non-text characters removed from it); see THE SCAN."""
    gone = [ch for ch in raw if is_invisible(ch)]
    v = "".join(compat_char(ch) for ch in raw if not is_invisible(ch))
    v = "".join(ch for ch in unicodedata.normalize("NFKD", v) if unicodedata.category(ch) not in MARK_CATEGORIES)
    # no character's fold holds an invisible character (tests/release/pvl_inventory.py checks every code point: the
    # FOLD-CLOSURE line), so the removal is not repeated after NFKC
    return unicodedata.normalize("NFKC", v), gone


def scan(v):
    """The tokens of the cleaned value V: a list of (start, end, raw text, skeleton)."""
    out, start = [], None
    for i, ch in enumerate(v + " "):
        if ch.isalnum() and i < len(v):
            if start is None:
                start = i
        elif start is not None:
            raw = v[start:i]
            out.append((start, i, raw, "".join(skeleton_char(c) for c in raw)))
            start = None
    return out


def readings(skel):
    """The readings of one skeleton token: itself (lower case), its 0->o 1->i reading, its letter and digit parts."""
    low = skel.lower()
    return {low, low.replace("0", "o").replace("1", "i")} | {p.lower() for p in re.findall(r"[^\W\d_]+|\d+", skel)}


def letter_parts(toks):
    """The letter parts of the tokens in order, as (token index, part): the stream single-letter runs are read from."""
    return [(k, p) for k, (_, _, _, s) in enumerate(toks) for p in re.findall(r"[^\W\d_]+", s)]


def single_runs(toks):
    """Every maximal run of single-letter parts: a list of (first token index, joined letters)."""
    runs, cur = [], []
    for k, p in letter_parts(toks) + [(None, "")]:
        if len(p) == 1:
            cur.append((k, p))
            continue
        if len(cur) >= 2:
            runs.append((cur[0][0], "".join(x for _, x in cur)))
        cur = []
    return runs


WORD_MAX = 12  # longer than every word of the word lists (placeholder, unconfirmed: 11)


def prefixes(s):
    """The prefixes of 2 to WORD_MAX letters of a run of single letters, lower case."""
    return {s[:n].lower() for n in range(2, min(len(s), WORD_MAX) + 1)}


def lead_letters(toks):
    """The number of leading tokens that are one letter each (T.B.D, n.a, N/A), and their joined letters."""
    n = 0
    while n < len(toks) and len(toks[n][3]) == 1 and toks[n][3].isalpha():
        n += 1
    return n, "".join(t[3] for t in toks[:n])


def placeholder_lead(key, v, toks):
    """The reason when the cleaned value V (tokens TOKS) starts with a placeholder (rule 3), else None."""
    s = v.lstrip(OPENERS + " \t")
    parts = s.split(None, 1)
    first_word = parts[0] if parts else ""
    rest = parts[1] if len(parts) > 1 else ""
    w_end = len(v) - len(s) + len(first_word)
    in_word = [t for t in toks if t[0] < w_end]
    if not in_word:
        return None
    n, letters = lead_letters(toks)
    run = letters if n >= 2 else ""
    runs = single_runs(toks)
    if not run and runs and runs[0][0] == 0:
        run = runs[0][1]  # T.B.D1: the run reaches into the letter part of a token
    cands = set().union(*(readings(t[3]) for t in in_word[:3]))
    if run:
        cands |= prefixes(run)
    strong = sorted(cands & STRONG_WORDS)
    if strong:
        return "is a placeholder (%s)" % strong[0]
    heads = prefixes(run) if run else readings(toks[0][3])
    head = toks[0][3].lower()
    rest_toks = toks[max(n, 1):] if run else toks[1:]
    nxt = rest_toks[0][3].lower() if rest_toks else ""
    # the lead stands alone as the first word, or the first word (a compound such as none-yet, pending.sh, n.a/n.a)
    # is the whole value apart from a bracketed note
    alone = all(len(t[3]) == 1 for t in in_word) if run else len(in_word) == 1
    whole = not rest.strip() or rest.lstrip().startswith(("(", "["))
    weak = sorted(heads & WEAK_WORDS)
    if key == "checks":
        if weak and (alone or whole) and not (head == "none" and nxt == "of"):
            return "is a placeholder (%s)" % weak[0]
        if head == "not" and (nxt in CHECKS_NOT_WORDS or (whole and len(in_word) > 1)):
            return "is a placeholder (not %s)" % nxt
    else:
        lead_only = sorted(heads & LEAD_ONLY_WORDS)
        if (weak or lead_only) and (alone or whole):
            return "is a placeholder (%s)" % (weak or lead_only)[0]
        if head in ("not", "no") and len(toks) > 1:
            return "is a placeholder (%s %s)" % (head, nxt)
    if head in BE_LEADS and len(toks) > 1 and toks[1][3].lower() == "be":
        return "is a placeholder (%s be)" % head
    return None


def placeholder_inside(toks):
    """The placeholder word anywhere in the tokens (rule 5), else None."""
    for _, _, _, s in toks:
        if readings(s) & INSIDE_ANY_CASE or s in INSIDE_CAPITALS or INSIDE_CAPITALS.intersection(
                re.findall(r"[^\W\d_]+", s)):
            return s
    for _, run in single_runs(toks):
        if any(w in run.lower() for w in INSIDE_ANY_CASE) or any(w in run for w in INSIDE_CAPITALS):
            return run
    return None


def placeholder_end(key, v, toks):
    """The reason when the value ends with a placeholder or holds a placeholder note (rule 7), else None."""
    if len(toks) < 2:
        return None
    trail = TRAIL_WORDS if key == "checks" else TRAIL_WORDS | TRAIL_WORDS_NOT_CHECKS
    last = readings(toks[-1][3]) & trail
    m = 0
    while m < len(toks) and len(toks[-1 - m][3]) == 1 and toks[-1 - m][3].isalpha():
        m += 1
    if m >= 2:
        last |= {"".join(t[3] for t in toks[-m:]).lower()} & trail
    if last:
        return "ends with a placeholder (%s)" % sorted(last)[0]
    note_words = WEAK_WORDS - {"none"} if key == "checks" else WEAK_WORDS
    j = 0
    for k, ch in enumerate(v):
        if ch not in "([":
            continue
        while j < len(toks) and toks[j][0] <= k:
            j += 1
        if j < len(toks):
            n, letters = lead_letters(toks[j:j + WORD_MAX])
            head = readings(toks[j][3]) | (prefixes(letters) if n >= 2 else set())
            hit = sorted(head & note_words)
            if hit:
                return "holds a placeholder note (%s)" % hit[0]
    return None


def text_problem(v, toks, gone):
    """Rule 9: invisible or non-text characters, letters outside the declared scripts, a token of mixed scripts."""
    if gone:
        ch = gone[0]
        return "holds an invisible or non-text character (U+%04X %s)" % (ord(ch), unicodedata.name(ch, "unnamed"))
    for _, _, raw, _ in toks:
        scripts = set()
        for ch in raw:
            sc = script_of(ch)
            if sc != "COMMON" and sc not in DECLARED_SCRIPTS:
                return "uses a letter or digit outside the declared scripts %s (U+%04X %s)" % (
                    ", ".join(DECLARED_SCRIPTS), ord(ch), unicodedata.name(ch, "unnamed"))
            if ch.isalpha():
                scripts.add(sc)
        if len(scripts) > 1:
            return "mixes scripts in one word (%s: %s)" % (raw, ", ".join(sorted(scripts)))
    return None


def path_ok(t, root):
    """Under --root: the path T has no .. part and its real path lies inside the real ROOT and is not ROOT itself."""
    if ".." in t.split("/"):
        return False
    real_root = os.path.realpath(root)
    p = os.path.realpath(t if os.path.isabs(t) else os.path.join(root, t))
    return os.path.exists(p) and p != real_root and os.path.commonpath([real_root, p]) == real_root


def weak_path(t):
    """True when a path-shaped word holds a weak word (shape-only mode: none/yet, pending.sh)."""
    return any(readings(s) & (WEAK_WORDS | LEAD_ONLY_WORDS) for _, _, _, s in scan(t))


def path_anchor(t, root):
    if not (PATH_TOKEN.match(t) or FILE_TOKEN.match(t)):
        return False
    return path_ok(t, root) if root is not None else not weak_path(t)


def job_anchor(core, root):
    """True when the job value (ASCII, no look-alike map) names a path, a command with an argument, or a job id."""
    raw = core.split()
    toks = [t.strip(EDGE_PUNCT).lstrip(OPENERS) for t in raw]
    for i, t in enumerate(toks):
        if JOB_ID.match(t):
            return True
        if path_anchor(t, root):
            return True
        if t in COMMANDS:
            for a, r in list(zip(toks, raw))[i + 1:i + 3]:
                if OPTION.match(a) or r.startswith("./...") or path_anchor(a, root):
                    return True
    return False


def shape_problem(key, v, raw, root):
    """Rule 8 for field KEY (V the value read by the shapes: NFKC, invisible characters removed)."""
    core = v.strip(" \t.,;:")
    alnum = sum(1 for ch in core if ch.isalnum())
    ascii_words = [w.lower() for w in re.findall(r"[A-Za-z0-9]+", core) if w.isascii()]
    if key == "job":
        if not job_anchor(v, root):
            return "does not name a job (a path, a command with a path or option, or a job id <KEY>-<digits>)"
    elif key in ("checks", "target"):
        if alnum < 3:
            return "is too short to name anything (at least 3 letters or digits)"
        if key == "target" and not TARGET_WORDS.intersection(ascii_words):
            return "names no target (one of %s)" % ", ".join(sorted(TARGET_WORDS))
        if key == "checks" and not (re.search(r"[0-9]", core) or OUTCOME_WORDS.intersection(ascii_words)):
            return "names no outcome (a number, or a word such as passed, failed, killed, rc, verdict, identical)"
    elif key == "layer":
        lw = core.split(None, 1)[0].rstrip(".,;:()").lower()
        if lw not in LAYER_VOCAB:
            return "does not start with a known layer (%s)" % ", ".join(LAYER_VOCAB)
    elif key == "artifact":
        if not (HEX.search(core.lower()) or ARTIFACT_WORDS.search(core)):
            return ("names no fingerprint or ref (a hex id, or commit, main, tag, branch, merge, vehicle, image, build, "
                    "sha256)")
    elif key == "due":
        d = DUE.match(raw.strip())
        if not d:
            return "is not a date (YYYY-MM-DD at the start, ASCII digits)"
        y, mo, da = int(d.group(1)), int(d.group(2)), int(d.group(3))
        try:
            datetime.date(y, mo, da)
        except ValueError:
            return "is not a real calendar date (%s)" % d.group(0)
        if not 2000 <= y <= 2099:
            return "has a year outside 2000 to 2099 (%d)" % y
        if d.group(4):
            try:
                datetime.datetime.fromisoformat(d.group(0).replace("Z", "+00:00"))
            except ValueError:
                return "has an invalid time (%s)" % d.group(0)
    return None


def field_problem(key, raw, root=None):
    """Return None when the value of field KEY is complete, else the reason (see the module docstring)."""
    v, gone = clean(raw)
    v = v.strip()
    core = v.strip(" \t.,;:")
    if not core:
        return "is empty"
    if not any(ch.isalnum() for ch in core):
        return "is punctuation only"
    toks = scan(core)
    problem = placeholder_lead(key, core, toks)
    if problem:
        return problem
    first = core.lstrip(OPENERS + " \t").split(None, 1)[0]
    if not any(ch.isalnum() for ch in first):
        return "starts with no word (%s)" % first[:12]
    hit = placeholder_inside(toks)
    if hit:
        return "holds the placeholder word %s" % hit
    m = TEMPLATE.search(core)
    if m:
        return "holds the template placeholder %s" % m.group(0)
    problem = placeholder_end(key, core, toks) or shape_problem(key, v, raw, root) or text_problem(core, toks, gone)
    return problem


def check_body(body, root=None):
    """Return None when the body carries one complete verification line, else the reason."""
    lines = [ln for ln in unfenced_lines(body) if PREFIX_RE.match(ln)]
    if not lines:
        return "no '**Verification:** provisional' line"
    if len(lines) > 1:
        return "%d verification lines (one expected)" % len(lines)
    if len(lines[0]) > MAX_LINE:
        return "the verification line is longer than %d characters (%d)" % (MAX_LINE, len(lines[0]))
    parts = SEP.split(lines[0])[1:]
    found, values = [], {}
    for part in parts:
        m = FIELD_PART.match(part)
        if not m:
            continue
        found.append(m.group(1))
        values.setdefault(m.group(1), m.group(2))
    missing = [f for f in FIELDS if f not in found]
    if missing:
        return "missing field(s): %s" % ", ".join(missing)
    if len(found) != len(set(found)):
        return "a field is repeated: %s" % ", ".join(found)
    if tuple(found) != FIELDS:
        return "fields out of order: %s (expected %s)" % (", ".join(found), ", ".join(FIELDS))
    for f in FIELDS:
        problem = field_problem(f, values[f], root)
        if problem:
            return "field '%s' %s" % (f, problem)
    return None


def main(argv):
    args, root = list(argv[1:]), None
    if len(args) >= 2 and args[0] == "--root":
        root, args = args[1], args[2:]
        if not os.path.isdir(root):
            sys.stderr.write("check_provisional_verification_lines.py: --root %s is not a directory\n" % root)
            return 64
    if len(args) > 1 or (args and args[0].startswith("-")):
        sys.stderr.write("usage: check_provisional_verification_lines.py [--root DIR] [DB]\n")
        return 64
    db = args[0] if args else "docs/workable_items.db"
    try:
        con = sqlite3.connect("file:%s?mode=ro" % db, uri=True)
        total = con.execute("select count(*) from items").fetchone()[0]
        rows = con.execute(
            "select atm_id, status, body_md from items where status in (?, ?) order by atm_id", STATUSES).fetchall()
    except sqlite3.Error as exc:
        return blind("the database cannot be read (%s)" % exc.__class__.__name__)
    if total == 0:
        return blind("the items table holds no items")
    fails = 0
    for atm_id, status, body in rows:
        reason = check_body(body, root)
        if reason:
            fails += 1
            print("FAIL %s %s: %s" % (atm_id, status, reason))
    print("PATHS: %s" % ("exist-under %s" % root if root is not None else "shape-only"))
    print("CHECKED items=%d provisional_status=%d ok=%d fail=%d" % (total, len(rows), len(rows) - fails, fails))
    print("VERDICT: %s" % ("FAIL" if fails else "PASS"))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
