#!/usr/bin/env python3
"""scripts/validation/check_provisional_verification_lines.py -- every PROVISIONAL-DONE item names its verification job.

Usage:
  python3 -I scripts/validation/check_provisional_verification_lines.py [DB]     (default: docs/workable_items.db)

Section 11.4.290: an item counts as PROVISIONAL-DONE while its Status is `Ready for testing` or `In testing`, and
that state needs a scheduled verification job recorded on one line. The canon (section 11.4.290, the paragraph after
the state table) writes the line without colons,

  **Verification:** provisional — job <id> — checks <runtime signature> — layer <...> — target <fingerprint> — artifact <fix fingerprint> — due <ISO timestamp>

and this project writes it with colons (`-- job: ... -- checks: ...`). Both forms are accepted, field by field (the
separator is " -- " or " — "; an em dash or a "--" with white space on both sides is therefore never a field value).
This checker reads the tracker database (the single source of truth, section 11.4.93; opened read-only, never
written) and refuses an item of those two statuses whose body has no such line, more than one, a missing, repeated
or out-of-order field, or a field that is not complete.

A line counts only when it starts at column 0 with `**Verification:** provisional` and is OUTSIDE a fenced code block
(``` or ~~~ with up to 3 spaces of indent; a fence closes on a line of the same character, at least as long, with
nothing after it; an unclosed fence runs to the end of the body). A quoted, indented or fenced copy is text.

A COMPLETE field (CON-423 review r1, B1). The checks run in this order and the first one that fails is the reason:
  1. empty -- nothing but white space and . , ; : after the key.
  2. punctuation only -- no letter or digit at all (`-`, `–`, `?`).
  3. placeholder -- (a) the value starts with TBD, TBA, TODO, FIXME, XXX or UNCONFIRMED (after an opening bracket or
     quote; these never start a real value); (b) the value is only UNKNOWN, PENDING, N/A, NA, NONE, NULL, NIL or
     PLACEHOLDER, alone or followed by ":" and text, by a bracketed note, or by "yet"; (c) it starts with "to be
     decided / determined / confirmed / defined / scheduled / announced", "not yet", "not scheduled" or "not known".
     Case-insensitive, after the value is NFKC-normalised (full-width letters fold) and format characters such as
     U+200B are removed.
  4. placeholder word inside -- TBD, TBA, TODO or FIXME as a whole word anywhere (case-insensitive), or XXX in capitals.
  5. template placeholder -- `<word ...>` (the canon's own `<id>`, `<ISO timestamp>`), `{{...}}` or `${...}`.
  6. shape, per field:
     job      -- one id-like token (at least 3 characters with a digit or one of - _ : / .) or at least 2 words;
     checks   -- at least 3 letters or digits;
     layer    -- the first word is one of: user-visible, runtime, artifact, source (the section 11.4.290 classes),
                 host-only, live-target (the section 11.4.292 surfaces), gate-logic (this project's word for a test of
                 a gate's own logic, section 11.4.289(C)(2));
     target   -- at least 3 letters or digits;
     artifact -- names a fingerprint or a ref: a hex token of 7 to 64 characters with a digit, or one of the words
                 commit, main, tag, branch, merge, vehicle, image, build, sha256;
     due      -- starts with a real calendar date YYYY-MM-DD in ASCII digits, year 2000 to 2099, optionally followed by
                 an ISO time (THH:MM[:SS][Z|+HH:MM]); after the date comes the end of the value, white space or one of
                 . , ; ( . An event such as "next full-suite run" is not a due time: section 11.4.290(C) names "a due
                 time (the staleness budget)" and (E) reports an item past it as OVERDUE, which an event cannot be.

Where `UNCONFIRMED:` is legal (sections 11.4.6, 11.4.290, 11.4.292). Section 11.4.292(C) writes a field of the
REPRODUCTION record that could not be captured as `UNCONFIRMED: <reason>`, and such a record is not REPRODUCED.
Section 11.4.290(C) says a marking without a scheduled job is refused and the item stays In progress; it names no
UNCONFIRMED form for the verification line. So in a verification line a field whose value IS `UNCONFIRMED...` (check
3a) is a field that could not be captured, and the line is refused. `UNCONFIRMED` stays legal AFTER a complete value,
as an honest qualifier of it, for example `due: 2026-11-23 (UNCONFIRMED: date set by the fixer; no scheduler entry
exists)` or `target: host, repo checkout; consumer layout UNCONFIRMED here`; the qualifier never makes a field complete
by itself. This checker does not read Reproduction lines.

Known limits (stated, not fixed): look-alike letters of other scripts (a Cyrillic T in TBD) are not folded; a value
that has the right shape but is false (a job that does not exist) is not detected; it does NOT check whether a due
date is past (derive_release_facts.sh reports that), whether the job was run, or whether the named files exist.

It found the class of CON-423 (rehearsal of the v73.4 cut, D2): four Ready-for-testing items with no line, so the
release count line said 25 provisional while 29 items were Ready for testing, and two lines with no `checks` field.

Output: one `FAIL <id> <status>: <reason>` line per refused item, then `CHECKED items=N provisional_status=P
ok=K fail=F`, then `VERDICT: PASS|FAIL|BLIND`. Exit 0 PASS, 1 FAIL, 2 BLIND (the database cannot be read, has
no items table, or holds no items at all: a zero there proves nothing), 64 usage.
"""

import datetime
import re
import sqlite3
import sys
import unicodedata

STATUSES = ("Ready for testing", "In testing")
FIELDS = ("job", "checks", "layer", "target", "artifact", "due")
PREFIX = "**Verification:** provisional"
SEP = re.compile(r"\s+(?:--|—)\s+")
FIELD_PART = re.compile(r"(job|checks|layer|target|artifact|due)(?=[\s:]|\Z):?(.*)\Z", re.S)
FENCE = re.compile(r" {0,3}(`{3,}|~{3,})")

OPENERS = "([{<\"'`*"
STRONG_PLACEHOLDERS = {"tbd", "tba", "todo", "fixme", "xxx", "unconfirmed", }
WEAK_PLACEHOLDER = re.compile(r"(unknown|pending|n/a|na|none|null|nil|placeholder)\s*(:.*|\(.*\)|\[.*\]|yet)?[)\]}>\"'`*]*",
                              re.I | re.S)
PLACEHOLDER_PHRASE = re.compile(r"(to be (decided|determined|confirmed|defined|scheduled|announced)|not yet|"
                                r"not scheduled|not known)\b", re.I)
PLACEHOLDER_INSIDE = re.compile(r"(?i:\b(TBD|TBA|TODO|FIXME)\b)|\bXXX\b")
TEMPLATE = re.compile(r"<[A-Za-z][A-Za-z0-9 _-]{0,40}>|\{\{.*?\}\}|\$\{[^}]*\}")
LAYER_VOCAB = ("user-visible", "runtime", "artifact", "source", "host-only", "live-target", "gate-logic")
ARTIFACT_WORDS = re.compile(r"\b(commit|main|tag|branch|merge|vehicle|image|build|sha256)\b", re.I)
HEX = re.compile(r"\b(?=[0-9a-f]*[0-9])[0-9a-f]{7,64}\b")
DUE = re.compile(r"([0-9]{4})-([0-9]{2})-([0-9]{2})(T[0-9]{2}:[0-9]{2}(:[0-9]{2})?(Z|[+-][0-9]{2}:[0-9]{2})?)?"
                 r"(?=\Z|[\s.,;(])")
ID_TOKEN = re.compile(r"(?=.*[0-9_:/.-])\S{3,}\Z")


def blind(msg):
    print("BLIND %s" % msg)
    print("VERDICT: BLIND")
    return 2


def unfenced_lines(body):
    """Lines of the body outside fenced code blocks."""
    out, fence = [], None
    for ln in (body or "").splitlines():
        m = FENCE.match(ln)
        if fence is None:
            if m:
                fence = m.group(1)
            else:
                out.append(ln)
        elif m and m.group(1)[0] == fence[0] and len(m.group(1)) >= len(fence) and not ln[m.end():].strip():
            fence = None
    return out


def normalise(v):
    v = unicodedata.normalize("NFKC", v)
    return "".join(ch for ch in v if unicodedata.category(ch) != "Cf")


def field_problem(key, raw):
    """Return None when the value of field KEY is complete, else the reason (see the module docstring)."""
    v = normalise(raw).strip()
    core = v.strip(" \t.,;:")
    if not core:
        return "is empty"
    if not any(ch.isalnum() for ch in core):
        return "is punctuation only"
    s = core.lstrip(OPENERS)
    first = s.split(None, 1)[0].rstrip(".,;:)]}>\"'`*").lower() if s else ""
    if first in STRONG_PLACEHOLDERS or PLACEHOLDER_PHRASE.match(s):
        return "is a placeholder (%s)" % (first or s[:20])
    if WEAK_PLACEHOLDER.fullmatch(s):
        return "is a placeholder (%s)" % first
    m = PLACEHOLDER_INSIDE.search(v)
    if m:
        return "holds the placeholder word %s" % m.group(0)
    m = TEMPLATE.search(v)
    if m:
        return "holds the template placeholder %s" % m.group(0)
    words = re.findall(r"\w+", core)
    alnum = sum(1 for ch in core if ch.isalnum())
    if key == "job":
        if not (len(words) >= 2 or ID_TOKEN.match(core)):
            return "does not name a job (one id-like token or at least 2 words)"
    elif key in ("checks", "target"):
        if alnum < 3:
            return "is too short to name anything (at least 3 letters or digits)"
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


def check_body(body):
    """Return None when the body carries one complete verification line, else the reason."""
    lines = [ln for ln in unfenced_lines(body) if ln.startswith(PREFIX)]
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
        problem = field_problem(f, values[f])
        if problem:
            return "field '%s' %s" % (f, problem)
    return None


def main(argv):
    if len(argv) > 2 or (len(argv) == 2 and argv[1].startswith("-")):
        sys.stderr.write("usage: check_provisional_verification_lines.py [DB]\n")
        return 64
    db = argv[1] if len(argv) == 2 else "docs/workable_items.db"
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
        reason = check_body(body)
        if reason:
            fails += 1
            print("FAIL %s %s: %s" % (atm_id, status, reason))
    print("CHECKED items=%d provisional_status=%d ok=%d fail=%d" % (total, len(rows), len(rows) - fails, fails))
    print("VERDICT: %s" % ("FAIL" if fails else "PASS"))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
