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
says TODO/TBD, or a MANUAL block is unused (a typo would otherwise drop text silently). Exit 2 = usage.
"""
import re
import sys

EMPTY = "(none recorded in the tracker)"


def die(msg, rc):
    sys.stderr.write("render_release_entry: %s\n" % msg)
    sys.exit(rc)


def main(argv):
    if len(argv) != 4:
        die("usage: render_release_entry.py TEMPLATE FACTS MANUAL", 2)
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

    used, missing = set(), []

    def sub(m):
        key = m.group(1)
        if key.startswith("MANUAL:"):
            name = key[len("MANUAL:"):]
            val = manual.get(name)
            if val is None or not val.strip() or re.search(r"\b(TODO|TBD)\b", val):
                missing.append(key)
                return m.group(0)
            used.add(name)
            return val
        if key not in facts:
            missing.append(key)
            return m.group(0)
        return facts[key] if facts[key] != "" else EMPTY

    out = re.sub(r"\{\{([^{}]+)\}\}", sub, tpl)
    if missing:
        die("unfilled placeholders: %s" % ", ".join(sorted(set(missing))), 3)
    unused = sorted(set(manual) - used)
    if unused:
        die("manual blocks not used by the template: %s" % ", ".join(unused), 3)
    sys.stdout.write(out)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
