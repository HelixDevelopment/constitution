#!/usr/bin/env python3
"""Round-5 META cases for CM-KILLPG-PGID-GUARD (§11.4.263), built in Python so no destructive
payload ever sits in a shell heredoc or string (§11.4.287(D)).

Usage:  killpg_round5_cases.py <outdir>      writes <outdir>/<id>/<path> and <outdir>/MANIFEST.tsv
        MANIFEST.tsv rows: id <TAB> expected_rc <TAB> required output substrings joined by '|'
        (an empty field means "no output assertion"; '!x' means the output must NOT contain x).

Every case asserts the exit status. Cases that exercise the audited marker, the heredoc rule
or the gate's own bookkeeping also assert the gate's OUTPUT (ALLOWED / IGNORED lines and the
suppressed-site count), so deleting an echo is detected (reviewer mutation R3).
"""
import os
import sys

CASES = []  # (id, relpath, text, rc, out_requirements)


def add(i, rel, text, rc, out=''):
    CASES.append((i, rel, text, rc, out))


def bold(s):
    return ''.join(chr(0x1d41a + ord(c) - ord('a')) for c in s)


# ---- (a) output integrity ------------------------------------------------------------
# F1/F2: the marker file has NO trailing newline; the last marker must still be honoured
# and counted, and both ALLOWED lines plus the count line must be printed.
add('o01', 'tests/a.py',
    'import os\nos.killpg(1, 9)  # killpg-gate:allow fixture one\n'
    'os.killpg(1, 9)  # killpg-gate:allow fixture two',
    0, 'ALLOWED|fixture one|fixture two|2 call site(s) suppressed')
add('o02', 'tests/a.py',
    'import os\nos.killpg(1, 9)  # killpg-gate:allow only one',
    0, 'ALLOWED|only one|1 call site(s) suppressed')
add('o03', 'tests/a.sh', '# killpg-gate:allow no code under this\nkill -9 -1  # killpg-gate:allow shell fixture',
    0, 'ALLOWED|shell fixture')
# the marker on a NON-test path is ignored AND said so
add('o04', 'src/a.py',
    'import os\nos.killpg(1, 9)  # killpg-gate:allow reason here\n',
    1, 'IGNORED|UNGUARDABLE')

# ---- (b) shell operand grammar -------------------------------------------------------
for i, t in [
    ('h01', 'kill -9 -$1\n'), ('h02', 'kill -9 -$!\n'), ('h03', 'kill -- -$@\n'),
    ('h04', 'kill -9 -$*\n'), ('h05', 'kill -9 -$((pg))\n'), ('h06', 'kill -9 -\\1\n'),
    ('h07', "kill -9 -$'1'\n"), ('h08', 'kill -9 -$(echo 1)\n'), ('h09', 'kill -9 -`echo 1`\n'),
    ('h10', 'kill -s TERM -- -"$pg"\n'), ('h11', 'kill -TERM -- "-$pg"\n'),
    ('g03', 'kill -s "$sg" -- "-$BPG"\n'),
    ('j04', 'kill -9 \\\n  -1\n'), ('j05', 'kill -9 \\\n  -"$pg"\n'),
]:
    add(i, 'a.sh', t, 1)
add('k01', 'a.py', 'import subprocess\nsubprocess.run(["kill", "-9", f"-{pg}"])\n', 1)
add('k02', 'a.py', 'import subprocess\nsubprocess.run(["kill", "-9", "-%d" % pg])\n', 1)
add('k03', 'a.py', 'import subprocess\nsubprocess.run(["kill", "-9", "-{}".format(pg)])\n', 1)
add('k05', 'a.py', 'import subprocess\nsubprocess.run(["kill", "-s", "9", "--", f"-{pg}"])\n', 1)
add('k06', 'a.py', 'import subprocess\nsubprocess.run([\n  "kill",\n  "-9",\n  f"-{pg}",\n])\n', 1)
add('n04', 'a.go', 'package m\nfunc f(pg int){ syscall.Kill(pg * -1, 9) }\n', 1)
add('n05', 'a.go', 'package m\nfunc f(pg int){ syscall.Kill(-1 * pg, 9) }\n', 1)
add('n06', 'a.c', 'void f(int pg){ kill(pg * -1, 9); }\n', 1)
add('n07', 'a.py', 'import os\nos.kill(pg * -1, 9)\n', 1)
add('n08', 'a.py', 'import os\nos.kill(-1 * pg, 9)\n', 1)
add('n09', 'a.c', 'void f(int pg){ kill(-1*pg, 9); }\n', 1)
add('j01', 'a.py', 'import os\nos.system("kill -9 " "-1")\n', 1)
add('j02', 'a.py', 'import os\nos.system("kill -9 " + "-1")\n', 1)
add('j03', 'a.py', 'import os\nk = getattr(os, "kill" + "pg")\n', 1)

# F8: a signal operand followed by a pid is NOT a group kill (false positives must stay quiet)
for i, t in [
    ('f01', 'kill -"$sig" "$pid"\n'), ('f02', 'kill -$s "$p"\n'),
    ('f03', 'kill -"${sig}" "$pid" 2>/dev/null || true\n'), ('f04', 'kill -0 "$pid"\n'),
    ('f05', 'kill -s "$sig" "$pid"\n'), ('f06', 'kill -TERM "$pid"\n'),
    ('f07', 'if kill -"$sig" "$pid" 2>/dev/null; then echo ok; fi\n'),
    ('g01', 'pg=$1\n[ "$pg" -gt 1 ] || exit 1\nkill -s "$sg" -- "-$pg"\n'),
    ('g02', 'BPG=$1\n[ "$BPG" -gt 1 ] || exit 1\nkill -s TERM -- "-$BPG"\n'),
    ('g04', '[ "$1" -gt 1 ] || return 0\nkill -s KILL -- "-$1"\n'),
    ('j06', 'pg=$1\n[ "$pg" -gt 1 ] || exit 1\nkill -9 \\\n  -"$pg"\n'),
]:
    add(i, 'a.sh', t, 0)

# ---- (c) python decoding -------------------------------------------------------------
add('d01', 'a.py', 'import os\nｏｓ.ｋｉｌｌｐｇ(pg, 9)\n', 1)
add('d02', 'a.py', 'import os\nos.ｋｉｌｌｐｇ(pg, 9)\n', 1)
add('d03', 'a.py', 'import os\nos.' + bold('killpg') + '(pg, 9)\n', 1)
add('d04', 'a.py', '# coding: utf-7\nimport os\nos.killpg(1, 9)\n', 1)

# ---- (e) META cases F3/F4 ------------------------------------------------------------
# a string that fakes a guard must not clear a call (reviewer mutation R2)
add('a01', 'a.py', 'import os\nG = "pgid > 1"\nos.killpg(pgid, 9)\n', 1)
add('a05', 'a.py', 'import os\n# pgid > 1\nos.killpg(pgid, 9)\n', 1)
# a file that does not tokenize must FAIL, not pass
add('a02', 'a.py', 'import os\nx = """unterminated\nos.killpg(pg, 9)\n', 1)
# a production path merely containing "test" is not a test path (reviewer mutation R8)
add('a03', 'contest/a.py', 'import os\nos.killpg(1, 9)  # killpg-gate:allow reason\n', 1, 'IGNORED')
add('a04', 'latest_run.py', 'import os\nos.killpg(1, 9)  # killpg-gate:allow reason\n', 1, 'IGNORED')
# a real test directory component IS a test path
add('a06', 'tests/unit/a.py', 'import os\nos.killpg(1, 9)  # killpg-gate:allow reason\n', 0, 'ALLOWED')

# ---- F9 / F10 -------------------------------------------------------------------------
# F9: a marker inside a shell heredoc body is data, not a comment: not honoured, and said so
add('m02', 'tests/a.sh', 'cat <<EOF\n# killpg-gate:allow reason here\nEOF\nkill -9 -1\n', 1,
    'IGNORED|heredoc')
# F10: python heredoc inside .sh gets the same code_ns comparison: a string cannot fake a guard
add('m03', 'tests/a.sh',
    "python3 - <<'PYX'\nimport os\ns = 'pg > 1'\nos.killpg(pg, 9)\nPYX\n", 1)
# ... and a real comment marker inside the python heredoc on a test path is honoured
add('m04', 'tests/a.sh',
    "python3 - <<'PYX'\nimport os\nos.killpg(1, 9)  # killpg-gate:allow fixture\nPYX\n", 0, 'ALLOWED')
# clean control: a guarded python call stays quiet
add('c01', 'a.py', 'import os\nif pgid <= 1:\n    raise ValueError("x")\nos.killpg(pgid, 9)\n', 0)


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
