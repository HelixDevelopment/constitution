#!/usr/bin/env python3
"""scripts/release/render_release_entry.py — fill a release-entry template mechanically (§11.4.274).

Usage:
  python3 -I scripts/release/render_release_entry.py TEMPLATE FACTS MANUAL > entry.md

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

FACTS integrity (review of f4c6e8ab, N4): every FACTS line must be KEY=VALUE with a key of the shape
derive_release_facts.sh prints (lower-case name, optionally one [..] part without [, ] or =), no key may occur
twice (so this reader, which would keep the last copy, and a reader that keeps the first copy cannot disagree), and
no key or value may hold a character of the Unicode categories Cc, Cf, Zl or Zp (controls, line separators, bidi
controls, invisible format characters) or bytes that are not UTF-8. Any violation: exit 3, nothing on stdout, and the
message names the line number, never the value.
"""
import re
import sys
import unicodedata

EMPTY = "(none recorded in the tracker)"


def die(msg, rc):
    sys.stderr.write("render_release_entry: %s\n" % msg)
    sys.exit(rc)


# The retest sentence of a release entry is conditional on a recorded verdict (§11.4.40, §11.4.230(F.3)(1)):
# the manual value must START with one of these tokens, so a claim of a pass cannot be written without it.
RETEST_VERDICT = re.compile(r"(PASS-FULL|PARTIAL-TOPOLOGY|FAIL|NOT RUN)(?![\w-])")
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
    if len(argv) != 4:
        die("usage: render_release_entry.py TEMPLATE FACTS MANUAL", 2)
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
    sys.stdout.write(out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
