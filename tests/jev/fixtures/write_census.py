#!/usr/bin/env python3
"""write_census.py - round 11 (review N-1, R10-1): a static census of every lease-registry write in jev-place.sh.

GATE-LOGIC instrument (section 11.4.289(C)(2)). For each function of the producer it lists the lease_save call sites,
the set deletions (del(.sets...), with_entries(select ...)), the whole-set replacements (.sets[$p] = ...) and the
lease-adding writes (+ [$l], leases += ...). Every occurrence of the token `leases_save` is classified as one of:
comment (the token appears only after a '#'), definition (`leases_save() {`) or call (code). A control needle is run
first: the instrument must find the definition line and at least one call in finish_stop_locked, else it reports BLIND
(exit 2) and no count is printed as a finding.

Usage: write_census.py <jev-place.sh> [--json]
Exit 0 ok, 2 blind (the needle was not found).
"""
import json
import re
import sys


def strip_comment(line):
    """The code part of a bash line: text before an unquoted '#' that starts a word (good enough for this file)."""
    out, q = [], None
    for i, ch in enumerate(line):
        if q:
            if ch == q and (q == "'" or line[i - 1] != "\\"):
                q = None
            out.append(ch)
            continue
        if ch in "'\"":
            q = ch
            out.append(ch)
            continue
        if ch == "#" and (i == 0 or line[i - 1] in " \t;"):
            break
        out.append(ch)
    return "".join(out)


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 64
    src = open(sys.argv[1], encoding="utf-8").read().splitlines()
    func = None
    fdef = re.compile(r"^([a-z_][a-z0-9_]*)\(\)\s*\{")
    occ = {"comment": [], "definition": [], "call": []}
    per = {}
    pats = {
        "delete_set": re.compile(r"del\(\.sets\[|with_entries\(select"),
        "replace_set": re.compile(r"\.sets\[\$p\]\s*=\s*[\{(]"),
        "add_lease": re.compile(r"\+\s*\[\$l\]|leases\s*\+="),
    }
    for n, line in enumerate(src, 1):
        m = fdef.match(line)
        if m:
            func = m.group(1)
        code = strip_comment(line)
        if "leases_save" in line:
            if re.match(r"^leases_save\(\)\s*\{", line):
                occ["definition"].append(n)
            elif "leases_save" in code:
                occ["call"].append(n)
                per.setdefault(func, {}).setdefault("leases_save", []).append(n)
            else:
                occ["comment"].append(n)
        for k, rx in pats.items():
            if rx.search(code):
                per.setdefault(func, {}).setdefault(k, []).append(n)
    needle = bool(occ["definition"]) and bool(per.get("finish_stop_locked", {}).get("leases_save"))
    if not needle:
        print("BLIND: control needle not found (no leases_save definition, or no call in finish_stop_locked)")
        return 2
    if "--json" in sys.argv:
        print(json.dumps({"occurrences": occ, "per_function": per}, indent=1, sort_keys=True))
        return 0
    print("needle: OK (definition line %s; finish_stop_locked calls %s)" % (occ["definition"], per["finish_stop_locked"]["leases_save"]))
    print("leases_save token lines: %d = %d call sites + %d definition + %d comment lines"
          % (sum(len(v) for v in occ.values()), len(occ["call"]), len(occ["definition"]), len(occ["comment"])))
    print("function | leases_save | delete_set | replace_set | add_lease")
    for f in sorted(per, key=lambda x: min(min(v) for v in per[x].values())):
        d = per[f]
        print("%s | %s | %s | %s | %s" % (f, d.get("leases_save", []), d.get("delete_set", []), d.get("replace_set", []), d.get("add_lease", [])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
