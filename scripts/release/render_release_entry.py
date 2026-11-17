#!/usr/bin/env python3
"""scripts/release/render_release_entry.py — fill a release-entry template mechanically (§11.4.274).

Usage:
  python3 -I scripts/release/render_release_entry.py [--draft] TEMPLATE FACTS MANUAL > entry.md

TEMPLATE  Markdown with {{key}} placeholders (keys of FACTS) and {{MANUAL:name}} placeholders; a
          leading HTML comment (the template's own instructions) is dropped.
FACTS     output of scripts/release/derive_release_facts.sh (KEY=VALUE lines).
MANUAL    the hand-supplied values: blocks that start with a line "@@name" and run to the next "@@"
          line or the end of the file (values may span several lines).

Derived keys built here from FACTS: states_block (one line per non-UNSET state with its ids),
unmerged_refs_block (one line per remote counted). An empty FACTS value renders as
"(none recorded in the tracker)".

Refuses (exit 3, nothing on stdout) when a placeholder has no value, a MANUAL value is empty or still
says TODO/TBD, a MANUAL block is unused (a typo would otherwise drop text silently), or a FACTS count
key open_status[...] / open_severity[...] is not rendered by the template (a status or severity value
new at cut time would otherwise drop silently; extend the template), or the MANUAL value retest_statement
does not START with a verdict word (the §11.4.40 retest sentence of an entry is conditional on a recorded verdict,
so an entry never implies a pass; the word is checked, the base, tier and log that follow it are not). Exit 2 = usage.

Verdict words (B-M1 of the v73.4 dry run): the words of RETEST_RESULTS in scripts/full_suite/run_full_suite.py (the
runner's own table, read with ast.literal_eval and never imported; a missing or malformed table is refused with exit 3)
plus NOT RUN (no run at all). A word of class "retest" (PASS-FULL) or "fail" (FAIL) and NOT RUN render as written. A
word of class "gap" (PASS-FULL-WITH-KNOWN and every PARTIAL-*) renders with the fixed note
"[gap: not a section 11.4.40 full retest; (L6) stays open]" right after it, and a word of class "gap-not-run"
(MANIFEST-MISMATCH, REFUSED-TOPOLOGY) with "[gap: nothing was run; not a section 11.4.40 retest; (L6) stays open]",
so a gap can never read as a pass. The longest word is matched first, so PASS-FULL-WITH-KNOWN is never PASS-FULL.

Placeholders (B-M4 of the v73.4 dry run): a MANUAL value is also refused (exit 3) when it still carries a lander placeholder
or draft text: an angle-bracket token that is neither an autolink <http(s)://...> nor a plain lower-case HTML tag
(<details>, <br/>, <a href="x">; every attribute written name="value") -- so <CON-NNN>, <...>, <paste ...>, <all 10 remotes> are refused --, the upper-case word
DRAFT, the token UNCONFIRMED-CUT-DATE, or a cut_date that is not a real calendar date written YYYY-MM-DD.
--draft renders such values anyway (a rehearsal) and puts the fixed line DRAFT_MARK right after the first "## " heading
(first line when there is none); scripts/release/tag_and_release.sh refuses to cut a release from notes holding that line.
--draft relaxes ONLY the placeholder check: missing values, TODO/TBD, unused blocks and unrendered facts still refuse.
Known limit: a lower-case one-word angle token such as <sha> reads as an HTML tag and is not refused.

FACTS integrity (review of f4c6e8ab, N4): every FACTS line must be KEY=VALUE with a key of the shape
derive_release_facts.sh prints (lower-case name, optionally one [..] part without [, ] or =), no key may occur
twice (so this reader, which would keep the last copy, and a reader that keeps the first copy cannot disagree), and
no key or value may hold a character of the Unicode categories Cc, Cf, Zl or Zp (controls, line separators, bidi
controls, invisible format characters) or bytes that are not UTF-8. Any violation: exit 3, nothing on stdout, and the
message names the line number, never the value.
"""
import ast
import datetime
import os
import re
import sys
import unicodedata

EMPTY = "(none recorded in the tracker)"
# B-M4: the one marker of a --draft render; tag_and_release.sh refuses notes containing "DRAFT RENDER — not a release entry".
DRAFT_MARK = ("> **DRAFT RENDER — not a release entry.** Made by render_release_entry.py --draft; it may carry placeholders, "
              "and scripts/release/tag_and_release.sh refuses to cut a release from notes that contain this line.")
ANGLE = re.compile(r"<[^<>\n]*>")
AUTOLINK = re.compile(r"<https?://[^\s<>]+>")
HTML_TAG = re.compile(r'</?[a-z][a-z0-9]*(\s+[a-z][a-z-]*="[^"<>]*")*\s*/?>')   # every attribute needs ="value"


def placeholder_reason(name, val):
    """Why a MANUAL value is still a placeholder (B-M4), or None."""
    for m in ANGLE.finditer(val):
        t = m.group(0)
        if not (AUTOLINK.fullmatch(t) or HTML_TAG.fullmatch(t)):
            return "angle-bracket placeholder %s" % t
    if re.search(r"\bDRAFT\b", val):
        return "the word DRAFT"
    if "UNCONFIRMED-CUT-DATE" in val:
        return "UNCONFIRMED-CUT-DATE"
    if name == "cut_date":
        v = val.strip()
        try:
            if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", v):
                raise ValueError
            datetime.date.fromisoformat(v)
        except ValueError:
            return "cut_date is not a calendar date YYYY-MM-DD"
    return None


def die(msg, rc):
    sys.stderr.write("render_release_entry: %s\n" % msg)
    sys.exit(rc)


# The retest sentence of a release entry is conditional on a recorded verdict (§11.4.40, §11.4.230(F.3)(1)):
# the manual value must START with a verdict word, so a claim of a pass cannot be written without it.
RUNNER = os.path.join(os.path.dirname(os.path.abspath(__file__)), os.pardir, "full_suite", "run_full_suite.py")
NOTES = {"retest": "", "fail": "", "not-run": "",
         "gap": "[gap: not a section 11.4.40 full retest; (L6) stays open]",
         "gap-not-run": "[gap: nothing was run; not a section 11.4.40 retest; (L6) stays open]"}


def verdict_words():
    """(word, class) pairs: RETEST_RESULTS of the runner (one source, B-M1) plus NOT RUN; refuses (exit 3) otherwise."""
    try:
        tree = ast.parse(open(RUNNER, encoding="utf-8").read())
        node = [n for n in tree.body if isinstance(n, ast.Assign)
                and any(getattr(t, "id", "") == "RETEST_RESULTS" for t in n.targets)]
        table = ast.literal_eval(node[0].value) if len(node) == 1 else None
        words = [(w, c) for (w, rc, c) in table
                 if isinstance(w, str) and re.fullmatch(r"[A-Z][A-Z-]*[A-Z]", w) and isinstance(rc, int) and c in NOTES]
        if len(words) != len(table) or not words or len({w for w, _ in words}) != len(words):
            raise ValueError("bad row")
    except (OSError, SyntaxError, ValueError, TypeError, IndexError):
        die("cannot read the verdict words: RETEST_RESULTS of %s is missing or malformed (B-M1: the runner's table is the one "
            "source; nothing is guessed)" % os.path.normpath(RUNNER), 3)
    return sorted(words + [("NOT RUN", "not-run")], key=lambda x: -len(x[0]))


def retest_value(val, words):
    """The rendered retest_statement, or None when it does not start with a verdict word."""
    v = val.strip()
    for w, c in words:   # longest first
        if v.startswith(w) and not re.match(r"[\w-]", v[len(w):len(w) + 1]):
            if not NOTES[c]:
                return val
            lead = val[:len(val) - len(val.lstrip())]
            return lead + w + " " + NOTES[c] + v[len(w):]
    return None


FACT_KEY = re.compile(r"[a-z][a-z0-9_]*(\[[^\[\]=]*\])?\Z")
BAD_CATEGORIES = {"Cc", "Cf", "Zl", "Zp", "Cs"}


def read_facts(path):
    """KEY=VALUE lines of derive_release_facts.sh, checked line by line (N4); exit 3 on the first bad line"""
    try:
        data = open(path, "rb").read().decode("utf-8")
    except UnicodeDecodeError:
        die("FACTS is not UTF-8", 3)
    facts = {}
    lines = data.split("\n")
    if lines and lines[-1] == "":
        lines.pop()
    for no, line in enumerate(lines, 1):
        if any(unicodedata.category(c) in BAD_CATEGORIES for c in line):
            die("FACTS line %d holds a control, line-separator, bidi or invisible format character (not shown)" % no, 3)
        if "=" not in line:
            die("FACTS line %d is not KEY=VALUE" % no, 3)
        k, v = line.split("=", 1)
        if not FACT_KEY.match(k):
            die("FACTS line %d has a malformed key (not shown)" % no, 3)
        if k in facts:
            die("FACTS key %s occurs twice (line %d); a first-match and a last-match reader would disagree" % (k, no), 3)
        facts[k] = v
    return facts


def main(argv):
    draft = len(argv) > 1 and argv[1] == "--draft"
    if draft:
        argv = argv[:1] + argv[2:]
    if len(argv) != 4 or any(a.startswith("--") for a in argv[1:]):
        die("usage: render_release_entry.py [--draft] TEMPLATE FACTS MANUAL", 2)
    tpl = open(argv[1], encoding="utf-8").read()
    tpl = re.sub(r"\A\s*<!--.*?-->\s*", "", tpl, count=1, flags=re.S)
    facts = read_facts(argv[2])
    manual, cur = {}, None
    for line in open(argv[3], encoding="utf-8"):
        if line.startswith("@@"):
            cur = line[2:].strip()
            if not cur or cur in manual:
                die("bad or duplicate manual block name: %r" % cur, 3)
            manual[cur] = []
        elif cur is not None:
            manual[cur].append(line)
    manual = {k: "".join(v).strip("\n") for k, v in manual.items()}

    states = [(k[len("open_states_ids["):-1], v) for k, v in facts.items() if k.startswith("open_states_ids[")]
    facts["states_block"] = "\n".join(
        "- %s: %s (%s)" % (s, facts.get("open_states[%s]" % s, "?"), v) for s, v in sorted(states)) or EMPTY
    refs = [(k[len("unmerged_refs_count["):-1], v) for k, v in facts.items() if k.startswith("unmerged_refs_count[")]
    facts["unmerged_refs_block"] = "\n".join(
        "- %s: %s ref(s): %s" % (r, n, facts.get("unmerged_refs[%s]" % r) or "-") for r, n in sorted(refs)) or EMPTY

    used, used_facts, missing = set(), set(), []

    def sub(m):
        key = m.group(1)
        if key.startswith("MANUAL:"):
            name = key[len("MANUAL:"):]
            val = manual.get(name)
            if val is None or not val.strip() or re.search(r"\b(TODO|TBD)\b", val):
                missing.append(key)
                return m.group(0)
            why = None if draft else placeholder_reason(name, val)
            if why:
                missing.append("%s (still a placeholder: %s; render with --draft for a rehearsal)" % (key, why))
                return m.group(0)
            if name == "retest_statement":
                words = verdict_words()
                rv = retest_value(val, words)
                if rv is None:
                    missing.append("MANUAL:retest_statement (must start with one of: %s)"
                                   % ", ".join(sorted(w for w, _ in words)))
                    return m.group(0)
                val = rv
            used.add(name)
            return val
        if key not in facts:
            missing.append(key)
            return m.group(0)
        used_facts.add(key)
        return facts[key] if facts[key] != "" else EMPTY

    out = re.sub(r"\{\{([^{}]+)\}\}", sub, tpl)
    if missing:
        die("unfilled placeholders: %s" % ", ".join(sorted(set(missing))), 3)
    unused = sorted(set(manual) - used)
    if unused:
        die("manual blocks not used by the template: %s" % ", ".join(unused), 3)
    unrendered = sorted(k for k in facts
                        if k.startswith(("open_status[", "open_severity[")) and k not in used_facts)
    if unrendered:
        die("facts the template does not render (a value new at cut time; extend the template): %s"
            % ", ".join(unrendered), 3)
    if draft:
        lines = out.split("\n")
        at = next((i + 1 for i, l in enumerate(lines) if l.startswith("## ")), 0)
        lines.insert(at, DRAFT_MARK)
        out = "\n".join(lines)
        sys.stderr.write("render_release_entry: DRAFT render (placeholders allowed; tag_and_release.sh refuses it)\n")
    sys.stdout.write(out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
