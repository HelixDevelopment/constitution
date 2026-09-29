#!/usr/bin/env python3
"""test_resolve1_mutate.py — the single-edit mutants of runner_patches/resolve1.py.

Purpose   Give test_resolve1_mutations.sh a data table it can list and apply without
          shell escaping. Each mutant edits EXACTLY ONE place of a COPY of resolve1.py.
Usage     test_resolve1_mutate.py --list                    -> "<id>\\t<expected-red-cases>" lines
          test_resolve1_mutate.py --apply <id> <resolve1.py>  (edits the given file in place)
Exit      0 ok; 3 anchor does not occur exactly once (fail loud: a mutant that silently
          applies nothing would be a bluff); 2 usage
Cross     test_resolve1_mutations.sh, ../runner_patches/resolve1.py
"""
import sys

# id: (find, replace, expected-RED test cases in test_resolve1.sh)
MUTANTS = {
    # M1 memo bypass: the memo is never trusted -> stock behaviour (a query per call)
    "M1": ("if (this.helixAllFilesMemo == null) {", "if (true) {", "R1,R4"),
    # M2 not frozen: identity is stable but the array is mutable again
    "M2": ("Object.freeze(this.queries.getAllFilePaths())", "this.queries.getAllFilePaths()", "R1"),
    # M3 clearCaches() no longer drops the memo (the line inside CLEAR_NEW)
    "M3": ("        this.helixAllFilesMemo = null; // helix-resolve1\n        this.cachesWarmed = false;",
           "        this.cachesWarmed = false;", "R2"),
    # M4 initialize() no longer drops the memo before detectFrameworks()
    "M4": ("        this.helixAllFilesMemo = null; // helix-resolve1: detect() must see the current file set\n",
           "", "R3"),
    # M5 the vue subset cache always misses (subset re-derived on every call)
    "M5": ("sub = helixVueSubsetCache.get(all);", "sub = undefined;", "R5"),
}


def main(argv):
    if len(argv) == 2 and argv[1] == "--list":
        for mid, (_, _, red) in MUTANTS.items():
            print(f"{mid}\t{red}")
        return 0
    if len(argv) == 4 and argv[1] == "--apply" and argv[2] in MUTANTS:
        find, repl, _ = MUTANTS[argv[2]]
        s = open(argv[3]).read()
        n = s.count(find)
        if n != 1:
            sys.stderr.write(f"mutant {argv[2]}: anchor occurs {n} times (need exactly 1)\n")
            return 3
        open(argv[3], "w").write(s.replace(find, repl))
        return 0
    sys.stderr.write(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
