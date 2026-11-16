#!/usr/bin/env python3
"""write_census.py - round 11 (review N-1, R10-1), round 12 (review R11-D): a static census of every lease-registry
write in jev-place.sh.

GATE-LOGIC instrument (section 11.4.289(C)(2)). For each function of the producer it lists the lease_save call sites,
the set deletions (del(.sets...), with_entries(select ...)), the whole-set replacements (.sets[$p] = ...) and the
lease-adding writes (+ [$l], leases += ...); round 12 adds the lease removals (leases |= map(select(.holder != ...)),
leases = [... select(.holder != ...)]), the lease clears (leases = []), the lease refreshes (heartbeat_at = ...) and the
read-only projections (the trace_ev map_values, the status text line). Round 12 also makes the census CLOSED-WORLD: every code line that writes a
lease list (leases |=, leases +=, leases =) or uses map_values must fall in one of those categories, else the line is
reported UNCATEGORISED and the exit is 1. Every occurrence of the token `leases_save` is classified as one of:
comment (the token appears only after a '#'), definition (`leases_save() {`) or call (code). A control needle is run
first: the instrument must find the definition line and at least one call in finish_stop_locked, else it reports BLIND
(exit 2) and no count is printed as a finding.

Usage: write_census.py <jev-place.sh> [--json]
Exit 0 ok, 1 an uncategorised lease write or map_values line, 2 blind (a needle was not found).
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
        "remove_lease": re.compile(r"leases\s*\|=\s*map\(select\(\.holder\s*!=|leases\s*=\s*\(?\[.*select\(\.holder\s*!="),
        "clear_leases": re.compile(r"\.leases\s*=\s*\[\]"),
        "refresh_lease": re.compile(r"\.heartbeat_at\s*=\s*\$n"),
        "read_only": re.compile(r"trace_ev\b.*map_values|jq -r '\.sets \| to_entries\[\] \| \""),
    }
    world = re.compile(r"map_values|leases\s*(\|=|\+=|=(?!=))")
    uncat = []
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
        hit = False
        for k, rx in pats.items():
            if rx.search(code):
                per.setdefault(func, {}).setdefault(k, []).append(n)
                hit = True
        if world.search(code) and not hit:
            uncat.append(n)
    needle = bool(occ["definition"]) and bool(per.get("finish_stop_locked", {}).get("leases_save"))
    if not needle:
        print("BLIND: control needle not found (no leases_save definition, or no call in finish_stop_locked)")
        return 2
    # round 12 needles: the release's lease removal and the heartbeat's lease refresh must be found by the new categories
    if not per.get("release_locked", {}).get("remove_lease") or not per.get("hb_locked", {}).get("refresh_lease"):
        print("BLIND: round-12 needle not found (no remove_lease in release_locked, or no refresh_lease in hb_locked)")
        return 2
    if "--json" in sys.argv:
        print(json.dumps({"occurrences": occ, "per_function": per, "uncategorised": uncat}, indent=1, sort_keys=True))
        return 1 if uncat else 0
    print("needle: OK (definition line %s; finish_stop_locked calls %s)" % (occ["definition"], per["finish_stop_locked"]["leases_save"]))
    print("leases_save token lines: %d = %d call sites + %d definition + %d comment lines"
          % (sum(len(v) for v in occ.values()), len(occ["call"]), len(occ["definition"]), len(occ["comment"])))
    cols = ["leases_save", "delete_set", "replace_set", "add_lease", "remove_lease", "clear_leases", "refresh_lease", "read_only"]
    print("function | " + " | ".join(cols))
    for f in sorted(per, key=lambda x: min(min(v) for v in per[x].values())):
        d = per[f]
        print("%s | %s" % (f, " | ".join(str(d.get(c, [])) for c in cols)))
    if uncat:
        print("UNCATEGORISED lease-write or map_values lines: %s" % uncat)
        return 1
    print("closed world: every lease-write and map_values line is categorised")
    return 0


if __name__ == "__main__":
    sys.exit(main())
