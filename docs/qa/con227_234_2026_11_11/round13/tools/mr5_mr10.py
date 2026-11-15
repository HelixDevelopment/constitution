#!/usr/bin/env python3
"""RED for MR5 and MR10 (gate logic): the reviewer's mutant text applied to a copy of the round-12 gate; the round-12
gate and the mutant are run on the reviewer's four fixtures. usage: mr5_mr10.py CEN_R12 OUTDIR"""
import os, subprocess, sys
cen, out = sys.argv[1], os.path.abspath(sys.argv[2])
os.makedirs(out, exist_ok=True)
src = open(cen).read()
M = {"MR5_LD_prefix_narrowed": ('name.startswith("LD_")', 'name.startswith("LD_PRELOAD")',
                                ["LD_LIBRARY_PATH=/x cat /dev/null", "export LD_AUDIT=/x/a.so"]),
     "MR10_extdebug_dropped": ('v in ("xtrace", "verbose", "posix", "extdebug")', 'v in ("xtrace", "verbose", "posix")',
                               ["shopt -s extdebug", "set -o extdebug"])}
for name, (old, new, fx) in M.items():
    assert src.count(old) == 1, name
    mp = os.path.join(out, name + ".py")
    open(mp, "w").write(src.replace(old, new))
    for i, line in enumerate(fx):
        f = os.path.join(out, "%s_g%d.sh" % (name, i))
        open(f, "w").write("#!/usr/bin/env bash\nrc_net git status\n" + line + "\n")
        for tag, g in (("r12", cen), ("r12-mutant", mp)):
            p = subprocess.run(["/usr/bin/python3", "-I", g, "netgate", f], env={"PATH": "/nonexistent", "LANG": "C.UTF-8"},
                               capture_output=True, text=True)
            print("%s\t%s\t%s\trc=%d\t%s" % (name, tag, line, p.returncode, p.stdout.strip().split("\n")[0][:110]))
