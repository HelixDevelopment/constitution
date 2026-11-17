#!/usr/bin/env python3
"""survivor_search.py -- CON-423 r7: search for bodies that tell a surviving mutant apart from the checker.

Usage: python3 -I docs/qa/rehearsal_v73_4_fix/r7/tools/survivor_search.py REPO WORKDIR [ID ...]

For each mutant ID (default: the seven survivors of mutation run 1: O46 O48 O50 O58 O59 O60 RW03), the checker and the
mutated copy judge the same bodies with check_body; a body is TELLING when one accepts and the other refuses. Bodies:
  placements  11 label spellings x 14 placements (154): on the counted line, in the next line, in a later paragraph,
              before the line, in a quote, a list, a link reference definition (title and destination), a fence info
              string, indented code, a heading, a comment
  blockstate  every body of tests/release/pvl_blockstate.py (all endings, the reviewer shapes), each also with
              ` Verification:` appended to the verification line
Output: per mutant `SEARCH <id> placements=<telling>/154 blockstate=<telling>/<n>` and up to 3 examples. A mutant
with 0 telling bodies is a candidate equivalent mutant (the argument is in tests/release/pvl_mutants_equivalent.tsv);
a telling body is turned into a kill case. Evidence class: gate-logic (section 11.4.289(C)(2)).
"""
import importlib.util
import os
import sys


def main(argv):
    repo, work = os.path.abspath(argv[1]), os.path.abspath(argv[2])
    ids = argv[3:] or ["O46", "O48", "O50", "O58", "O59", "O60", "RW03"]
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
    for mid, r, old, new in M.own_mutants(repo) + M.reviewer_mutants(repo):
        table[mid] = (old, new)
    for mid, r, old, _why in M.equivalent_mutants(repo):
        rows = [ln.split("\t") for ln in open(os.path.join(repo, "tests/release/pvl_mutants_equivalent.tsv"),
                                                encoding="utf-8") if ln.startswith(mid + "\t")]
        import ast
        table[mid] = (old, ast.literal_eval(rows[0][3]))
    orig = load(src, "orig")
    mods = {}
    for mid in ids:
        old, new = table[mid]
        if src.count(old) != 1:
            print("SEARCH %s NOT-APPLIED" % mid)
            continue
        mods[mid] = load(src.replace(old, new, 1), mid)
    fx = F.make_root(os.path.join(work, "fx"))
    G = F.line()
    extras = ["<!-- Verification: x -->", "[a](u 'Verification:')", "[a](Verification: )", "<Verification:x>",
              "`Verification:`", "&#86;erification:", "Veri*fi*cation:", "![Verification:](u)", "[Verification:]",
              "\\*\\*Verification:\\*\\*", "**&#86;erification:**"]
    tpls = ["{G} {e}", "{G}\n{e}", "x\n\n{G}\n\n{e}", "{e}\n\n{G}", "x {e}\n\n{G}", "> {e}\n\n{G}", "- {e}\n\n{G}",
            "[r]: /u '{e}'\n\n{G}", "[r]: {e}\n\n{G}", "```{e}\n```\n\n{G}", "    {e}\n\n{G}", "# {e}\n\n{G}",
            "{G}\n\n[r]: /u '{e}'", "{G}\n\n<!-- {e} -->"]
    placements = [t.format(G=G, e=e) for e in extras for t in tpls]
    blockstate = []
    for _name, body in B.bodies(False):
        blockstate += [body, body.replace(G, G + " Verification:")]

    def telling(m, bodies):
        out = []
        for b in bodies:
            o = orig.check_body(b, ctx=F.checker_ctx(orig, fx))
            try:
                r = m.check_body(b, ctx=F.checker_ctx(m, fx))
            except Exception as exc:  # noqa: BLE001 -- a crash is a refusal for this comparison
                r = "EXC %r" % exc
            if (o is None) != (r is None):
                out.append(b)
        return out

    for mid, m in mods.items():
        tp, tb = telling(m, placements), telling(m, blockstate)
        print("SEARCH %s placements=%d/%d blockstate=%d/%d" % (mid, len(tp), len(placements), len(tb), len(blockstate)))
        for b in (tp + tb)[:3]:
            print("  EXAMPLE %s %r" % (mid, b[-100:]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
