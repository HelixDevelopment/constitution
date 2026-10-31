#!/usr/bin/env python3
"""Round-6 META cases for CM-KILLPG-PGID-GUARD (§11.4.263): F1 pkill option order / long form,
F2 python argv `"-" + str(x)` concatenation, F3 `kill 0` / `kill(0, ..)`, F4 `~pg + 1`.

Built in Python so no destructive payload sits in a shell heredoc or string (§11.4.287(D)).
Usage:  killpg_round6_cases.py <outdir>   writes <outdir>/<id>/<path> and <outdir>/MANIFEST.tsv
        MANIFEST.tsv rows: id <TAB> expected_rc <TAB> required output substrings joined by '|'
Control needles: p00 / q00 / r00 are shapes the OLD gate already caught; they prove the instrument
sees this file class before any new null is believed.
"""
import os
import sys

CASES = []


def add(i, rel, text, rc, out=''):
    CASES.append((i, rel, text, rc, out))


# ---- control needles (old gate already flagged these) -------------------------------------------
add('p00', 'a.sh', 'pkill -g "$pg"\n', 1)
add('q00', 'a.py', 'import subprocess\nsubprocess.run(["kill", "-9", f"-{pg}"])\n', 1)
add('r00', 'a.py', 'import os\nos.killpg(0, 9)\n', 1)

# ---- F1: pkill with options before -g / long form / glued value ---------------------------------
for i, t in [
    ('p01', 'pkill -9 -g "$pg"\n'),
    ('p02', 'pkill -TERM -g "$pg"\n'),
    ('p03', 'pkill -g1\n'),
    ('p04', 'pkill --pgroup "$pg"\n'),
    ('p06', 'pkill -s TERM -g "$pg"\n'),
    ('p07', 'pkill -g0\n'),
    ('p08', 'pkill --pgroup=1\n'),
    ('p09', 'pkill -9 -g 1\n'),
    ('p10', 'pkill -KILL -x -g "$pg"\n'),
]:
    add(i, 'a.sh', t, 1)
add('p05', 'a.py', 'import subprocess\nsubprocess.run(["pkill", "-9", "-g", str(pg)])\n', 1)
add('p11', 'a.py', 'import subprocess\nsubprocess.run(["pkill", "--pgroup", str(pg)])\n', 1)
# benign pkill (no group option) and a guarded group form must stay quiet
for i, t in [
    ('p20', 'pkill -9 -f myproc\n'),
    ('p21', 'pkill -TERM -x foo\n'),
    ('p22', 'pkill --signal TERM foo\n'),
    ('p23', 'pg=$1\n[ "$pg" -gt 1 ] || exit 1\npkill -9 -g "$pg"\n'),
    ('p24', 'pg=$1\n[ "$pg" -gt 1 ] || exit 1\npkill --pgroup "$pg"\n'),
]:
    add(i, 'a.sh', t, 0)

# ---- F2: python argv / string concatenation `"-" + str(x)` -------------------------------------
add('q01', 'a.py', 'import subprocess\nsubprocess.run(["kill", "-9", "-" + str(pg)])\n', 1)
add('q02', 'a.py', 'import subprocess\nsubprocess.run(["kill", "-9", "--", "-" + str(pg)])\n', 1)
add('q03', 'a.py', 'import subprocess\nsubprocess.run(["kill", "-9", "-" + str(1)])\n', 1)
add('q04', 'a.py', 'import os\nos.system("kill -9 -" + str(pg))\n', 1)
add('q05', 'a.py', 'import subprocess\nsubprocess.run(["kill", "-9", "-" + str(self.pg)])\n', 1)
add('q06', 'a.py', 'import subprocess\nsubprocess.run(["kill", "-s", "KILL", "-" + pg])\n', 1)
add('q07', 'a.py', 'import subprocess\nsubprocess.run(\n    ["kill", "-9",\n     "-" + str(pg)])\n', 1)
add('q20', 'a.py', 'import subprocess\nif pg <= 1:\n    raise ValueError("x")\n'
    'subprocess.run(["kill", "-9", "-" + str(pg)])\n', 0)
add('q21', 'a.py', 'import subprocess\nsubprocess.run(["kill", "-9", str(pid)])\n', 0)
add('q22', 'a.py', 'import subprocess\nsubprocess.run(["echo", "-" + str(n)])\n', 0)

# ---- F3: pid/pgid 0 ------------------------------------------------------------------------------
for i, t in [
    ('r01', 'kill -9 0\n'), ('r02', 'kill 0\n'), ('r03', 'kill -TERM -- 0\n'),
    ('r04', 'kill -s KILL 0\n'),
]:
    add(i, 'a.sh', t, 1)
add('r05', 'a.c', 'void f(void){ kill(0, SIGKILL); }\n', 1)
add('r06', 'a.go', 'package m\nfunc f(){ syscall.Kill(0, 9) }\n', 1)
add('r07', 'a.py', 'import os\nos.kill(0, 9)\n', 1)
add('r08', 'a.py', 'import subprocess\nsubprocess.run(["kill", "-9", "0"])\n', 1)
for i, rel, t in [
    ('r20', 'a.sh', 'kill -0 "$pid"\n'),
    ('r21', 'a.sh', 'kill -9 "$pid" 2>/dev/null; exit 0\n'),
    ('r22', 'a.sh', 'kill -s 0 "$p"\n'),
    ('r23', 'a.sh', 'kill -9 "$pid" || exit 0\n'),
    ('r24', 'a.py', 'import os\nos.kill(pid, 0)\n'),
    ('r25', 'a.c', 'void f(int p){ kill(p, 0); }\n'),
]:
    add(i, rel, t, 0)

# prose carrying the words `kill` and `0` must not fire (false-positive guard, found on real canon tests)
add('r26', 'a.sh', 'eq "re-wire after kill" 0 "$RC"\n', 0)
add('r27', 'a.py', 'import os\nos.system("kill 0")\n', 1)
add('r28', 'a.sh', 'sudo kill 0\n', 1)

# ---- round 6b: N1 quoted -f patterns are operands, not options (golden-FALSE) ---------------------
for i, t in [
    ('n101', 'pkill -f "myapp -config"\n'),
    ('n102', 'pkill -f "java -Xmx2g"\n'),
    ('n103', 'pkill -u "$USER" -f "worker -tag x"\n'),
    ('n104', 'pkill -f "app -debug 5"\n'),
    ('n105', 'pkill -f "ffmpeg -preset fast -g 60"\n'),
    # N2 prose naming pkill -g is not a command
    ('n201', 'echo "use pkill -g to target groups"\n'),
]:
    add(i, 'a.sh', t, 0)
# golden-TRUE companions: the real group option AFTER a quoted pattern / value option is still caught
for i, t in [
    ('n110', 'pkill -f "app" -g "$pg"\n'),
    ('n111', 'pkill -u "$USER" -f "worker -tag x" -g 1\n'),
    ('n112', 'pkill -f worker -g "$pg"\n'),
    ('n113', 'sudo pkill -9 -g "$pg"\n'),
    ('n114', 'x=$(pkill -TERM -g "$pg")\n'),
    ('n115', '/usr/bin/pkill -g 1\n'),
    # N3 trap
    ('n301', 'trap "kill 0" EXIT\n'),
    ('n302', "trap 'kill -9 0' INT\n"),
]:
    add(i, 'a.sh', t, 1)
# N4 parenthesised negation
add('n401', 'a.py', 'import os\nos.kill((-pg), 9)\n', 1)
add('n402', 'a.go', 'package m\nfunc f(pg int){ syscall.Kill((-pg), 9) }\n', 1)
add('n403', 'a.c', 'void f(int pg){ kill(( -1), 9); }\n', 1)

# ---- F4: complement spelling ---------------------------------------------------------------------
add('s01', 'a.py', 'import os\nos.kill(~pg + 1, 9)\n', 1)
add('s02', 'a.c', 'void f(int pg){ kill(~pg + 1, 9); }\n', 1)


def main():
    out = sys.argv[1]
    man = []
    for i, rel, text, rc, outreq in CASES:
        p = os.path.join(out, i, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, 'w', encoding='utf-8', newline='') as fh:
            fh.write(text)
        man.append('%s\t%d\t%s' % (i, rc, outreq))
    with open(os.path.join(out, 'MANIFEST.tsv'), 'w', encoding='utf-8') as fh:
        fh.write('\n'.join(man) + '\n')


if __name__ == '__main__':
    main()
