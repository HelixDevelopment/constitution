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
written) and refuses an item of those two statuses whose body has no such line, more than one, a missing, repeated
or out-of-order field, or a field that is not complete.

A line counts only when it starts at column 0 with `**Verification:** provisional` followed by white space, `(` or
the end of the line (so `provisionalXYZ` is not the prefix), and is OUTSIDE a fenced code block (``` or ~~~ with up to
3 spaces of indent; a fence closes on a line of the same character, at least as long, with nothing after it; an
unclosed fence runs to the end of the body) and OUTSIDE an HTML comment block (a line that starts, after up to 3
spaces, with `<!--` opens one unless `-->` follows on the same line; the block ends with the line that holds `-->`; an
unclosed comment runs to the end of the body; a comment is not visible text). A quoted, indented, fenced or commented
copy is text.

A COMPLETE field (CON-423 review r1, B1; rebuilt after review r2, B2, as a structural round, section 11.4.276(E)(3):
positive shapes and a leading-word rule instead of a growing list of whole values). Every value is first FOLDED for
the word checks: NFKD, combining marks removed, NFKC (full-width letters fold), format characters such as U+200B
removed, and a small closed map of Cyrillic and Greek letters that look like ASCII letters (Cyrillic T, O, E, P, X,
...) turned into those ASCII letters. The folded value is then cut into TOKENS at every character that is not an
ASCII letter or digit and at every letter/digit boundary (TBD_1, TBD1 and MY_TODO hold the token TBD or TODO), a
run of single letters is joined (T.B.D., T B D and t_b_d hold TBD), and a token whose 0 and 1 read as O and I (T0D0,
F1XME) counts as that word. The positive shapes of step 7 read the value WITHOUT the look-alike map and in ASCII
only, so a look-alike letter never satisfies a shape. The checks run in this order; the first that fails is the
reason:
  1. empty -- nothing but white space and . , ; : after the key.
  2. punctuation only -- no letter or digit at all (`-`, `–`, `?`).
  3. placeholder at the start (the LEADING-WORD rule; the openers ( [ { < " ' ` * are skipped first):
     (a) in every field: the first token is a STRONG word: TBD, TBA, TBC, TODO, FIXME, XXX, UNCONFIRMED or LOREM;
     (b) in job, target and artifact: the first word (or the first part of an all-letter compound such as none-yet
         or pending_scheduling when that compound is the whole value, a bracketed note aside) is a WEAK word: unknown, pending, none, n/a, na, null, nil, placeholder, dummy,
         later, soon, eventually, someday, asap; or the value starts with "not ..." or "no ..." (more than one word),
         or with "to / will / shall / should / would be";
     (c) in checks the same, except that "none of ..." and "no ..." are statements (golden: none of the mutants
         survives, no pending lock remains), and "not" is refused only before one of: applicable, available,
         assigned, known, scheduled, yet, set, defined, decided, determined, run, done, started, planned, so a
         signature such as "NOT ok tool docstring ..." stays a signature;
     (d) layer and due as (b) (their own shapes of step 7 refuse the rest anyway; this names the reason).
  4. starts with no word -- the first word after the openers holds no letter or digit (`??? later`, `--- later`).
  5. placeholder word inside -- a token TBD, TBA, TBC, TODO or FIXME anywhere (any case), or XXX in capitals.
  6. template placeholder -- `<word ...>` (the canon's own `<id>`, `<ISO timestamp>`), `{{...}}` or `${...}`.
  7. shape, per field (POSITIVE: the value must name something of its kind):
     job      -- at least one of: a PATH (a whole word of ASCII letters, digits and _ . + - with at least one /, or a
                 file name ending in .sh .bash .py .go .js .ts .mjs .bats .mk .yaml .yml .json .toml); a COMMAND
                 (bash, sh, python3, python, go, make, node, npm, npx, pytest, git) with an option (-x), a path or
                 ./... among the next two words (go test ./...); or a JOB ID <KEY>-<digits> (KEY 2 to 16 capital letters or digits starting with a
                 letter, for example JOB-42). With --root DIR a path counts only when it exists (a relative path
                 under DIR); without --root its shape is enough, and the output says `PATHS: shape-only`;
     checks   -- at least 3 letters or digits (no positive shape: a runtime signature is prose; stated limit);
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
The class and its members are listed in docs/qa/rehearsal_v73_4_fix/r3/class_inventory.md.

Where `UNCONFIRMED:` is legal (sections 11.4.6, 11.4.290, 11.4.292). Section 11.4.292(C) writes a field of the
REPRODUCTION record that could not be captured as `UNCONFIRMED: <reason>`, and such a record is not REPRODUCED.
Section 11.4.290(C) says a marking without a scheduled job is refused and the item stays In progress; it names no
UNCONFIRMED form for the verification line. So in a verification line a field whose value IS `UNCONFIRMED...` (check
3a) is a field that could not be captured, and the line is refused. `UNCONFIRMED` stays legal AFTER a complete value,
as an honest qualifier of it, for example `due: 2026-11-23 (UNCONFIRMED: date set by the fixer; no scheduler entry
exists)` or `target: host, repo checkout; consumer layout UNCONFIRMED here`; the qualifier never makes a field complete
by itself. This checker does not read Reproduction lines.

Known limits (stated, not fixed): a value that has the right shape but is false (a path that exists but is not the
job, a job id no scheduler knows, a target word that is not where the job runs) is not detected; checks has no
positive shape, so prose with no placeholder word (`foo bar baz`) is accepted there; look-alikes outside the closed
map (other scripts, digits other than 0 and 1) are not folded; a <KEY>-<digits> job id cannot be told from a tracker
id; target words are English, so a Serbian or Russian word is refused (the conservative direction). It does NOT check
whether a due date is past (derive_release_facts.sh reports that) or whether the job was run.

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
PREFIX_RE = re.compile(r"\*\*Verification:\*\* provisional(?=[\s(]|\Z)")
SEP = re.compile(r"\s+(?:--|—)\s+")
FIELD_PART = re.compile(r"(job|checks|layer|target|artifact|due)(?=[\s:]|\Z):?(.*)\Z", re.S)
FENCE = re.compile(r" {0,3}(`{3,}|~{3,})")
COMMENT_OPEN = re.compile(r" {0,3}<!--")

OPENERS = "([{<\"'`*"
EDGE_PUNCT = ".,;:)]}>\"'`*!?"
# Cyrillic and Greek letters that look like ASCII letters: a closed map (the Latin-looking subset of the Unicode
# confusables data); a look-alike outside it is a stated limit.
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
STRONG_WORDS = frozenset(("tbd", "tba", "tbc", "todo", "fixme", "xxx", "unconfirmed", "lorem"))
INSIDE_ANY_CASE = frozenset(("tbd", "tba", "tbc", "todo", "fixme"))
INSIDE_CAPITALS = frozenset(("XXX",))
WEAK_WORDS = frozenset(("unknown", "pending", "none", "n/a", "na", "null", "nil", "placeholder", "dummy", "later",
                        "soon", "eventually", "someday", "asap"))
BE_PHRASE = re.compile(r"(to|will|shall|should|would) be\b", re.I)
CHECKS_NOT_WORDS = frozenset(("applicable", "available", "assigned", "known", "scheduled", "yet", "set", "defined",
                              "decided", "determined", "run", "done", "started", "planned"))
SINGLE_RUN = re.compile(r"(?<![A-Za-z0-9])[A-Za-z](?:[._\s-]{1,2}[A-Za-z](?![A-Za-z0-9]))+")
TEMPLATE = re.compile(r"<[A-Za-z][A-Za-z0-9 _-]{0,40}>|\{\{.*?\}\}|\$\{[^}]*\}")
LAYER_VOCAB = ("user-visible", "runtime", "artifact", "source", "host-only", "live-target", "gate-logic")
ARTIFACT_WORDS = re.compile(r"\b(commit|main|tag|branch|merge|vehicle|image|build|sha256)\b", re.I)
HEX = re.compile(r"\b(?=[0-9a-f]*[0-9])[0-9a-f]{7,64}\b")
DUE = re.compile(r"([0-9]{4})-([0-9]{2})-([0-9]{2})(T[0-9]{2}:[0-9]{2}(:[0-9]{2})?(Z|[+-][0-9]{2}:[0-9]{2})?)?"
                 r"(?=\Z|[\s.,;(])")
PATH_TOKEN = re.compile(r"(?:\./|/)?[A-Za-z0-9_][A-Za-z0-9_.+-]*(?:/[A-Za-z0-9_.+-]+)+/?\Z")
FILE_TOKEN = re.compile(r"[A-Za-z0-9_][A-Za-z0-9_.+-]*\.(?:sh|bash|py|go|js|ts|mjs|bats|mk|yaml|yml|json|toml)\Z")
COMMANDS = frozenset(("bash", "sh", "python3", "python", "go", "make", "node", "npm", "npx", "pytest", "git"))
JOB_ID = re.compile(r"[A-Z][A-Z0-9]{1,15}-[0-9]+\Z")
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


def normalise(v):
    """NFKC with format characters removed: what the positive shapes read (no look-alike map)."""
    v = unicodedata.normalize("NFKC", v)
    return "".join(ch for ch in v if unicodedata.category(ch) != "Cf")


def fold(v):
    """The skeleton the placeholder words see: NFKD, combining marks removed, NFKC, Cf removed, look-alikes mapped."""
    v = "".join(ch for ch in unicodedata.normalize("NFKD", v) if unicodedata.category(ch) != "Mn")
    return "".join(CONFUSABLES.get(ch, ch) for ch in normalise(v))


def tokens(v):
    """(token, digit reading) pairs of the folded value V: every run of ASCII letters and digits (its 0 read as o and
    its 1 as i), every letter part and digit part of it, and every joined run of single letters (T.B.D. -> TBD)."""
    out = []
    for t in re.findall(r"[A-Za-z0-9]+", v):
        out.append((t, t.lower().replace("0", "o").replace("1", "i")))
        out.extend((p, p.lower()) for p in re.findall(r"[A-Za-z]+|[0-9]+", t))
    for run in SINGLE_RUN.findall(v):
        j = re.sub(r"[^A-Za-z]", "", run)
        out.append((j, j.lower()))
    return out


def is_word(pairs, words):
    return next((t for t, read in pairs if t.lower() in words or read in words), None)


def leading(v):
    """(V after the openers, its first word with edge punctuation stripped, the words after it)."""
    s = v.lstrip(OPENERS + " \t")
    parts = s.split(None, 1)
    first = parts[0].rstrip(EDGE_PUNCT).lstrip(OPENERS) if parts else ""
    return s, first, parts[1] if len(parts) > 1 else ""


def placeholder_lead(key, folded):
    """The reason when the folded value starts with a placeholder (step 3), else None."""
    s, first, rest = leading(folded)
    low = first.lower()
    run = SINGLE_RUN.match(s)
    lead_pairs = tokens(first)[:3] + (tokens(run.group(0))[-1:] if run else [])
    strong = is_word(lead_pairs, STRONG_WORDS)
    if strong:
        return "is a placeholder (%s)" % strong.lower()
    # an all-letter compound (none-yet, pending_scheduling, not-applicable) counts by its first part only when it is
    # the whole value (a bracketed note may follow): "unknown-id-only table gives rc 1" is a statement (CON-189)
    compound = re.fullmatch(r"([A-Za-z]+)(?:[_-][A-Za-z]+)+", first)
    if compound and rest.strip() and not rest.lstrip().startswith(("(", "[")):
        compound = None
    head = compound.group(1).lower() if compound else low
    nxt = rest.split(None, 1)[0].strip(EDGE_PUNCT).lower() if rest.split() else ""
    if key == "checks":
        if (low in WEAK_WORDS or head in WEAK_WORDS) and not (low == "none" and nxt == "of"):
            return "is a placeholder (%s)" % (low if low in WEAK_WORDS else head)
        if (low == "not" and nxt in CHECKS_NOT_WORDS) or (compound and head == "not"):
            return "is a placeholder (not %s)" % (nxt or first)
    else:
        if low in WEAK_WORDS or head in WEAK_WORDS:
            return "is a placeholder (%s)" % (low if low in WEAK_WORDS else head)
        if (low in ("not", "no") and rest.strip()) or (compound and head in ("not", "no")):
            return "is a placeholder (%s %s)" % (head, nxt)
    m = BE_PHRASE.match(s)
    if m:
        return "is a placeholder (%s)" % m.group(0).lower()
    return None


def job_anchor(core, root):
    """True when the job value (ASCII, no look-alike map) names a path, a command with an argument, or a job id."""
    raw = core.split()
    toks = [t.strip(EDGE_PUNCT).lstrip(OPENERS) for t in raw]
    for i, t in enumerate(toks):
        if JOB_ID.match(t):
            return True
        if PATH_TOKEN.match(t) or FILE_TOKEN.match(t):
            if root is None or os.path.exists(t if os.path.isabs(t) else os.path.join(root, t)):
                return True
        if t in COMMANDS:
            for a, r in list(zip(toks, raw))[i + 1:i + 3]:
                if a.startswith("-") or r.startswith("./...") or PATH_TOKEN.match(a) or FILE_TOKEN.match(a):
                    return True
    return False


def field_problem(key, raw, root=None):
    """Return None when the value of field KEY is complete, else the reason (see the module docstring)."""
    v = normalise(raw).strip()
    core = v.strip(" \t.,;:")
    if not core:
        return "is empty"
    if not any(ch.isalnum() for ch in core):
        return "is punctuation only"
    folded = fold(raw).strip().strip(" \t.,;:")
    problem = placeholder_lead(key, folded)
    if problem:
        return problem
    first = folded.lstrip(OPENERS + " \t").split(None, 1)[0]
    if not any(ch.isalnum() for ch in first):
        return "starts with no word (%s)" % first[:12]
    for tok, read in tokens(folded):
        if tok.lower() in INSIDE_ANY_CASE or read in INSIDE_ANY_CASE or tok in INSIDE_CAPITALS:
            return "holds the placeholder word %s" % tok
    m = TEMPLATE.search(v)
    if m:
        return "holds the template placeholder %s" % m.group(0)
    alnum = sum(1 for ch in core if ch.isalnum())
    if key == "job":
        if not job_anchor(v, root):
            return "does not name a job (a path, a command with a path or option, or a job id <KEY>-<digits>)"
    elif key in ("checks", "target"):
        if alnum < 3:
            return "is too short to name anything (at least 3 letters or digits)"
        if key == "target" and not TARGET_WORDS.intersection(
                w.lower() for w in re.findall(r"[A-Za-z0-9]+", core) if w.isascii()):
            return "names no target (one of %s)" % ", ".join(sorted(TARGET_WORDS))
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


def check_body(body, root=None):
    """Return None when the body carries one complete verification line, else the reason."""
    lines = [ln for ln in unfenced_lines(body) if PREFIX_RE.match(ln)]
    if not lines:
        return "no '**Verification:** provisional' line"
    if len(lines) > 1:
        return "%d verification lines (one expected)" % len(lines)
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
