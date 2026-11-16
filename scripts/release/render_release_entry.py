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
does not START with one of the verdict tokens PASS-FULL, PARTIAL-TOPOLOGY, FAIL or NOT RUN (the §11.4.40 retest
sentence of an entry is conditional on a recorded verdict, so an entry never implies a pass; the token is
checked, the base, tier and log that follow it are not). Exit 2 = usage.

A MANUAL value that contains the word DRAFT (whole word, case-sensitive, as TODO and TBD) is refused too, unless
--draft is the first argument (CON-423, rehearsal D5: a rehearsal entry full of DRAFT values rendered with exit 0
and could have been committed as the release entry). A --draft rendering starts with the line DRAFT_MARK below and
says so on stderr, so it never passes for a release entry; TODO/TBD and every other check still apply. The MANUAL
value cut_date (the entry heading takes it whole) must be a bare calendar date YYYY-MM-DD that exists, also with
--draft (rehearsal D9).
"""
import datetime
import re
import sys

EMPTY = "(none recorded in the tracker)"


def die(msg, rc):
    sys.stderr.write("render_release_entry: %s\n" % msg)
    sys.exit(rc)


# The retest sentence of a release entry is conditional on a recorded verdict (§11.4.40, §11.4.230(F.3)(1)):
# the manual value must START with one of these tokens, so a claim of a pass cannot be written without it.
RETEST_VERDICT = re.compile(r"(PASS-FULL|PARTIAL-TOPOLOGY|FAIL|NOT RUN)(?![\w-])")
DRAFT_WORD = re.compile(r"\bDRAFT\b")
DRAFT_MARK = "<!-- DRAFT RENDERING (render_release_entry.py --draft): NOT A RELEASE ENTRY; do not commit it as one -->"
BARE_DATE = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}")


def is_bare_date(val):
    if not BARE_DATE.fullmatch(val):
        return False
    try:
        datetime.date.fromisoformat(val)
    except ValueError:
        return False
    return True


def main(argv):
    draft = len(argv) == 5 and argv[1] == "--draft"
    if draft:
        argv = argv[:1] + argv[2:]
    if len(argv) != 4 or any(a.startswith("--") for a in argv[1:]):
        die("usage: render_release_entry.py [--draft] TEMPLATE FACTS MANUAL", 2)
    tpl = open(argv[1], encoding="utf-8").read()
    tpl = re.sub(r"\A\s*<!--.*?-->\s*", "", tpl, count=1, flags=re.S)
    facts = {}
    for line in open(argv[2], encoding="utf-8"):
        line = line.rstrip("\n")
        if "=" in line:
            k, v = line.split("=", 1)
            facts[k] = v
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
            if not draft and DRAFT_WORD.search(val):
                missing.append("MANUAL:%s (still says DRAFT; use --draft for a draft rendering)" % name)
                return m.group(0)
            if name == "cut_date" and not is_bare_date(val):
                missing.append("MANUAL:cut_date (must be a bare calendar date YYYY-MM-DD)")
                return m.group(0)
            if name == "retest_statement" and not RETEST_VERDICT.match(val.strip()):
                missing.append("MANUAL:retest_statement (must start with PASS-FULL, PARTIAL-TOPOLOGY, FAIL or NOT RUN)")
                return m.group(0)
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
        sys.stderr.write("render_release_entry: draft rendering (--draft): the output starts with a DRAFT marker "
                         "line and is not a release entry\n")
        out = DRAFT_MARK + "\n" + out
    sys.stdout.write(out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
