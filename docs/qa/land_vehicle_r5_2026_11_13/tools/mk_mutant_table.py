# mk_mutant_table.py <index.tsv> <notes.tsv> <out.md> <results.tsv>...
# Builds the round-5 mutant table from the generator index (name, sha256, description),
# the runner results (name, stage, rc, result, first_fail) and a notes file
# (name, class, note): class is one of KILL, KILL-MESSAGE, EQUIVALENT. Every mutant in the
# index must have exactly one result row; a missing or duplicated row is an error.
import sys
idx_path, notes_path, out_path = sys.argv[1:4]
res_paths = sys.argv[4:]
idx = []
for line in open(idx_path, encoding="utf-8"):
    f = line.rstrip("\n").split("\t")
    if f[0] == "name":
        continue
    idx.append((f[0], f[1], f[2]))
res = {}
for p in res_paths:
    for line in open(p, encoding="utf-8"):
        f = line.rstrip("\n").split("\t")
        if f[0] == "name":
            continue
        if f[0] in res:
            sys.exit("duplicate result row for " + f[0])
        res[f[0]] = f
notes = {}
for line in open(notes_path, encoding="utf-8"):
    if not line.strip() or line.startswith("#"):
        continue
    f = line.rstrip("\n").split("\t")
    notes[f[0]] = (f[1], f[2])
missing = [n for n, _, _ in idx if n not in res]
if missing:
    sys.exit("no result for: " + " ".join(missing))
extra = sorted(set(res) - {n for n, _, _ in idx})
if extra:
    sys.exit("results for mutants not in the index: " + " ".join(extra))
counts = {}
rows = []
for name, sha, desc in idx:
    r = res[name]
    verdict = "KILLED" if r[4].startswith("FAIL ") else ("SURVIVED" if r[4] == "SURVIVED" else "ERROR")
    cls, note = notes.get(name, ("KILL", ""))
    if verdict == "SURVIVED" and cls != "EQUIVALENT":
        sys.exit("survivor without an equivalence note: " + name)
    if verdict == "KILLED" and cls == "EQUIVALENT":
        sys.exit("killed mutant noted as equivalent: " + name)
    counts[verdict] = counts.get(verdict, 0) + 1
    by = r[4][5:].replace("|", "\\|") if verdict == "KILLED" else "-"
    rows.append("| %s | %s | %s | %s | %s |" % (name, desc.replace("|", "\\|"), verdict, by, note.replace("|", "\\|")))
with open(out_path, "w", encoding="utf-8") as o:
    o.write("| Mutant | Mutation | Verdict | Killed by (first FAIL) | Note |\n|---|---|---|---|---|\n")
    o.write("\n".join(rows) + "\n\n")
    o.write("Totals: " + ", ".join("%s %d" % (k, counts[k]) for k in sorted(counts)) + " (of %d)\n" % len(idx))
print("rows", len(rows), counts)
