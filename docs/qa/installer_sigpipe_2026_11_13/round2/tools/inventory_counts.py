"""inventory_counts.py DIR — the counts table of README section 5 from DIR/shenum_base.tsv and DIR/shenum_new.tsv:
one row per file, one column per row kind; "b -> n" when base and head differ, one value when they are equal."""
import collections, sys
d = sys.argv[1]
files = ["scripts/install_constitution.sh", "scripts/update_constitution.sh", "scripts/install_cli_agent_plugins.sh",
         "scripts/install_action_prefix.sh", "scripts/portable_symlink_lib.sh", "scripts/lib/constitution_layout.sh"]
kinds = ["HERESTR", "HEREDOC", "PIPE", "EARLY", "READER", "PROCSUB", "SETOPT", "VERS", "PATMATCH", "FUNCCOND", "DECLSUB", "PARSEERR"]
c = {}
for side in ("base", "new"):
    c[side] = collections.Counter()
    for row in open("%s/shenum_%s.tsv" % (d, side), encoding="utf-8"):
        p = row.rstrip("\n").split("\t")
        c[side][(p[0], p[3])] += 1
print("| file | " + " | ".join(kinds) + " |")
print("|---|" + "---|" * len(kinds))
for f in files:
    cells = []
    for k in kinds:
        b, n = c["base"][(f, k)], c["new"][(f, k)]
        cells.append(str(n) if b == n else "%d -> %d" % (b, n))
    print("| `%s` | %s |" % (f, " | ".join(cells)))
