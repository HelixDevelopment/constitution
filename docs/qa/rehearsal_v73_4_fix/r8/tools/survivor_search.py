#!/usr/bin/env python3
"""survivor_search.py -- CON-PENDINGpvl8 r8: search for bodies that tell a surviving mutant apart from the checker.

Usage: python3 -I docs/qa/rehearsal_v73_4_fix/r8/tools/survivor_search.py REPO WORKDIR [ID ...]

Round 8 compares REASONS, not only accept or refuse (the r7 tool compared accept or refuse). For each mutant ID
(default: the survivor O59 of mutation run 1 and the three equivalent rows O48 O88 O89), the checker and the
mutated copy judge the same bodies with check_body. A body is TELLING when the two return different results (a
different reason string counts). The checker's result is computed once per body.

Bodies:
  placements  21 label spellings x 16 placements: the r7 placements plus link titles, link and image targets,
              percent and backslash escapes, a punycode host, and a reference link whose definition carries the label
  blockstate  every body of tests/release/pvl_blockstate.py (quick set: no lone CR), each also with
              ` Verification:` appended to the verification line
Control (section 11.4.273): the own mutant O77 (comments accepted again) is searched too and must have telling
bodies; if it has none the search is blind and the run exits 2 (SEARCH-BLIND).

Output: per mutant `SEARCH <id> placements=<telling>/<n> blockstate=<telling>/<n>` and up to 3 examples, then
`SEARCH-DONE`. A mutant with 0 telling bodies is a candidate equivalent mutant; the argument is in
tests/release/pvl_mutants_equivalent.tsv. The search covers the listed bodies only; it does not prove equivalence
over every document. Evidence class: gate-logic (section 11.4.289(C)(2)).
"""
import ast
import importlib.util
import os
import sys

CONTROL = "O77"


def main(argv):
    if len(argv) < 3:
        sys.stderr.write("usage: survivor_search.py REPO WORKDIR [ID ...]\n")
        return 64
    repo, work = os.path.abspath(argv[1]), os.path.abspath(argv[2])
    ids = argv[3:] or ["O59", "O48", "O88", "O89"]
    if CONTROL not in ids:
        ids = ids + [CONTROL]
    sys.path.insert(0, os.path.join(repo, "tests/release"))
    import pvl_blockstate as B
    import pvl_fixture as F
    import pvl_mutate as M
    os.makedirs(work, exist_ok=True)
    rel = "scripts/validation/check_provisional_verification_lines.py"
    src = open(os.path.join(repo, rel), encoding="utf-8").read()

    def load(text, name):
        p = os.path.join(work, name + ".py")
        with open(p, "w", encoding="utf-8") as fh:
            fh.write(text)
        spec = importlib.util.spec_from_file_location("ss_" + name, p)
        m = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(m)
        return m

    table = {}
    for mid, _r, old, new in M.own_mutants(repo) + M.reviewer_mutants(repo):
        table[mid] = (old, new)
    for ln in open(os.path.join(repo, "tests/release/pvl_mutants_equivalent.tsv"), encoding="utf-8"):
        f = ln.rstrip("\n").split("\t")
        if len(f) >= 4 and not ln.startswith("#"):
            table[f[0]] = (ast.literal_eval(f[2]), ast.literal_eval(f[3]))
    orig = load(src, "orig")
    mods = {}
    for mid in ids:
        if mid not in table or src.count(table[mid][0]) != 1:
            print("SEARCH %s NOT-APPLIED" % mid)
            continue
        old, new = table[mid]
        mods[mid] = load(src.replace(old, new, 1), mid)
    fx = F.make_root(os.path.join(work, "fx"))
    G = F.line()
    puny = "xn--" + "verifiсation".encode("punycode").decode("ascii")
    extras = ["<!-- Verification: x -->", "[a](u 'Verification:')", "[a](Verification: )", "<Verification:x>",
              "`Verification:`", "&#86;erification:", "Veri*fi*cation:", "![Verification:](u)", "[Verification:]",
              "\\*\\*Verification:\\*\\*", "**&#86;erification:**",
              "[a](u \"&#86;erification:\")", "[a](u 'Verification\\:')", "[a](<Verification: x>)",
              "[a](%56erification:)", "![a](u 'Verification:')", "![a](Verification:)", "[a](u (Verification:))",
              "<http://%s:80/>" % puny, "[a](http://%s:80/)" % puny, "[a][r]"]
    tpls = ["{G} {e}", "{G}\n{e}", "x\n\n{G}\n\n{e}", "{e}\n\n{G}", "x {e}\n\n{G}", "> {e}\n\n{G}", "- {e}\n\n{G}",
            "[r]: /u '{e}'\n\n{G}", "[r]: {e}\n\n{G}", "```{e}\n```\n\n{G}", "    {e}\n\n{G}", "# {e}\n\n{G}",
            "{G}\n\n[r]: /u '{e}'", "{G}\n\n<!-- {e} -->",
            "x [a][r]\n\n{G}\n\n[r]: /u 'Verification: {e}'", "{G}\n\nx {e}\n\n[r]: /u\n  'Verification:'"]
    placements = [t.format(G=G, e=e) for e in extras for t in tpls]
    blockstate = []
    for _name, body in B.bodies(True):
        blockstate += [body, body.replace(G, G + " Verification:")]

    def judge(m, b):
        try:
            return m.check_body(b, ctx=F.checker_ctx(m, fx))
        except Exception as exc:  # noqa: BLE001 -- a crash is a result of its own for this comparison
            return "EXC %r" % exc

    base_p = [judge(orig, b) for b in placements]
    base_b = [judge(orig, b) for b in blockstate]
    found = {}
    for mid, m in mods.items():
        tp = [b for b, o in zip(placements, base_p) if judge(m, b) != o]
        tb = [b for b, o in zip(blockstate, base_b) if judge(m, b) != o]
        found[mid] = len(tp) + len(tb)
        print("SEARCH %s placements=%d/%d blockstate=%d/%d" % (mid, len(tp), len(placements), len(tb),
                                                              len(blockstate)))
        for b in (tp + tb)[:3]:
            print("  EXAMPLE %s %r" % (mid, b[-100:]))
    if not found.get(CONTROL):
        print("SEARCH-BLIND the control mutant %s has no telling body" % CONTROL)
        return 2
    print("SEARCH-DONE control %s telling=%d" % (CONTROL, found[CONTROL]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
