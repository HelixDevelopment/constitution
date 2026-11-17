# mkreadme14.py <out> <runs_table.md>: assembles the round-14 README from the notes (header table, findings and fixes,
# the diagram, the kill-point argument and honest limits, the runs table, open questions). Mechanical concatenation only
# (section 11.4.274); every sentence is in the notes files, every number in the runs table comes from the run files.
import sys
W = "/mnt/DATA1TB/claude-work/scratch/jev_r14.R5N6"
out, runs = sys.argv[1], sys.argv[2]
parts = []
parts.append(open(W + "/notes/readme14_draft.md").read().rstrip("\n"))
parts.append(open(W + "/notes/readme14_body.md").read().rstrip("\n"))
parts.append("""## The start sequence (diagram)

![Start sequence of an acquire with the gated start process](start_intent.svg)

Source: `start_intent.mmd` (rendered with mermaid-cli, `mmdc.log`).""")
parts.append(open(W + "/notes/readme14_limits.md").read().rstrip("\n"))
parts.append(open(runs).read().rstrip("\n"))
# mutant counts, computed from runs/mut_summary.txt (the table and the survivor arguments are in mutants.md)
import re, os
kill, surv, other = [], [], []
for line in open(W + "/runs/mut_summary.txt"):
    m = re.match(r"^(MUT|CMUT) (\S+) (KILLED|SURVIVED|NO-RESULT)", line)
    if not m:
        continue
    # a timeout recorded as a kill by mutrun.sh before its fix is NO-RESULT (the rule of tools/test_mutrun.sh)
    if re.search(r" KILLED-by \S+ rc=(124|137) \(no FAIL line\)$", line.strip()):
        other.append(m.group(2) + " (timeout)")
        continue
    (kill if m.group(3) == "KILLED" else surv if m.group(3) == "SURVIVED" else other).append(m.group(2))
done = any(l.strip() == "CHAIN14 DONE" for l in open(W + "/runs/mut_summary.txt"))
mp = ["## Mutants", "",
      "%d mutant runs (`mutants.md`, raw `runs/mut_summary.txt`; chain %s): %d killed, %d survived%s." % (
          len(kill) + len(surv) + len(other), "complete" if done else "NOT complete", len(kill), len(surv),
          (", %d without a result (%s)" % (len(other), ", ".join(other))) if other else ""),
      "", "Survived: %s. RCTRL and RCTRL2 are the control (no change), expected to survive (RCTRL's sweep was cut by the" % ", ".join(surv),
      "runner's timeout and RCTRL2 re-ran it; `mutants.md`); every other survivor has its argument in `mutants.md`."]
parts.append("\n".join(mp))
# gate outputs (two runs on the final tree, copied verbatim into runs/)
gp = ["## Gates", "", "Each gate ran twice on the final tree (`tools/gates.sh.txt` and the extra checks it lists); the outputs are copied verbatim:", ""]
for f in ("gates_final1.txt", "gates_final2.txt"):
    gp.append("- `runs/%s`%s" % (f, "" if os.path.exists(W + "/runs/" + f) else ": MISSING"))
parts.append("\n".join(gp))
parts.append(open(W + "/notes/readme14_tail.md").read().rstrip("\n"))
open(out, "w").write("\n\n".join(parts) + "\n")
