#!/usr/bin/env python3
"""idpy14.py <gate> <table> <cases.tsv> - run the gate's embedded IDPY program on each case.
cases.tsv rows: label<TAB>want-rc<TAB>authoriser<TAB>cname<TAB>cmail<TAB>aname<TAB>amail, fields written as python
string literals (so hostile code points are spelled \\uXXXX, never typed). Prints label, want, got, verdict; exit 0
when every row matches, 1 otherwise, 2 when the IDPY block cannot be extracted (BLIND)."""
import ast, re, subprocess, sys
gate, table, cases = sys.argv[1:4]
src = open(gate, encoding='utf-8').read()
m = re.search(r"^IDPY='(.*?)'$", src, re.S | re.M)
if not m:
    print('BLIND: IDPY not found'); sys.exit(2)
prog = m.group(1); bad = 0; n = 0
for line in open(cases, encoding='utf-8').read().split('\n'):
    if not line or line.startswith('#'): continue
    f = line.split('\t'); lab, want = f[0], int(f[1]); vals = [ast.literal_eval(x) for x in f[2:7]]
    r = subprocess.run([sys.executable, '-I', '-c', prog, table], input=b'\0'.join(v.encode('utf-8') for v in vals))
    ok = r.returncode == want; bad |= not ok; n += 1
    print('%s\twant %d\tgot %d\t%s' % (lab, want, r.returncode, 'ok' if ok else 'MISMATCH'))
print('# %d cases, %s' % (n, 'all match' if not bad else 'MISMATCH'))
sys.exit(1 if bad else 0)
