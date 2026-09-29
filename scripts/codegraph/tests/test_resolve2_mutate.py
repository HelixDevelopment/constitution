#!/usr/bin/env python3
"""test_resolve2_mutate.py — the single-edit mutants of runner_patches/resolve2.py.

Purpose   Give test_resolve2_mutations.sh a data table it can list and apply without
          shell escaping. Each mutant edits EXACTLY ONE place of a COPY of resolve2.py.
Usage     test_resolve2_mutate.py --list                    -> "<id>\\t<expected-red-cases>" lines
          test_resolve2_mutate.py --apply <id> <resolve2.py>  (edits the given file in place)
Exit      0 ok; 3 anchor does not occur exactly once (fail loud: a mutant that silently
          applies nothing would be a bluff); 2 usage
Cross     test_resolve2_mutations.sh, ../runner_patches/resolve2.py
"""
import sys

# id: (find, replace, expected-RED test cases in test_resolve2.sh)
MUTANTS = {
    "M1": ("for (const n of context.iterateNodesByKind('method')) {",
           "for (const n of context.getNodesByKind('method')) {", "Q1"),
    "M2": ("if (n.language === 'objc')", "if (n.language === 'objc' || n.language === 'java')", "Q2,Q3"),
    "M3": ("objcMethods.push(n);", "objcMethods.unshift(n);", "Q2,Q3"),
    "M4": ("if (n.language === 'objc')", "if (n.language === 'swift')", "Q2,Q3"),
    "M5": ("objcMethods.push(n);\n    }", "{ objcMethods.push(n); break; }\n    }", "Q2,Q3"),
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
