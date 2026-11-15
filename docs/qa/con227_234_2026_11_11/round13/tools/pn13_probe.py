#!/usr/bin/env python3
"""Round 13, the probe behind the meq line of PN13: pin_regen checks for a written name of DANGER_NAMES after it has
refused on every analyser finding, and the analyser already reports every such write (IFS only with a closed
value). The probe writes one fixture per dangerous name (and IFS with a value off IFS_VALUES), runs pin-regen with
the gate and with the PN13 mutant (mut13.py apply PN13), and prints both results; the mutant is equivalent when
every pair is the same REFUSED line with rc 1 and no table is written.
usage: pn13_probe.py REPO TOOLSDIR OUTDIR   (OUTDIR must not exist; everything is written under it)"""
import os, subprocess, sys

repo, tools, out = sys.argv[1:4]
os.makedirs(out)
cen = os.path.join(repo, "tests/release/channel_census.py")
mut = os.path.join(out, "cen_pn13.py")
sys.path.insert(0, tools)
import mut13  # noqa: E402
(_, _, old, new, _), = [x for x in mut13.MEQ if x[0] == "PN13"]
text = open(cen, encoding="utf-8").read()
assert text.count(old) == 1, "PN13 is stale"
with open(mut, "w", encoding="utf-8") as fh:
    fh.write(text.replace(old, new))
names = ["PATH", "BASH_ENV", "ENV", "LD_PRELOAD", "LD_LIBRARY_PATH", "GCONV_PATH", "CDPATH", "EXECIGNORE", "BASHOPTS",
         "IFS"]
same = 0
written = 0
for n in names:
    f = os.path.join(out, "w_%s.sh" % n)
    with open(f, "w") as fh:
        fh.write("#!/usr/bin/env bash\nrc_net git status\n%s=%s\n" % (n, '"$x"' if n == "IFS" else "/x"))
    res = []
    for label, gate in (("gate", cen), ("PN13", mut)):
        tab = os.path.join(out, "table_%s_%s.tsv" % (label, n))
        r = subprocess.run(["/usr/bin/python3", "-I", gate, "pin-regen", tab, f], env={"PATH": "/nonexistent", "LANG": "C.UTF-8"},
                           capture_output=True, text=True)
        first = (r.stdout.splitlines() or [""])[0]
        written += os.path.exists(tab)
        res.append((r.returncode, first))
        print("%s\t%s\trc=%d\t%s" % (n, label, r.returncode, first))
    same += res[0] == res[1] and res[0][0] == 1 and res[0][1].startswith("REFUSED ")
print("pairs=%d same_refusal=%d tables_written=%d" % (len(names), same, written))
sys.exit(0 if same == len(names) and written == 0 else 1)
