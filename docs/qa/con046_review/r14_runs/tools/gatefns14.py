"""gatefns14.py - load the skeleton functions (k, g, q, f, e) VERBATIM from the gate's IDPY block, so a measurement
runs the gate's own code, never a re-implementation. load(gate, table) -> dict of the functions; T also returned.
The block is the text from `    T={}` to the line before `    if not f(a).split(): return 3`, dedented one level."""
import re, unicodedata, hashlib
def load(gate, table):
    src = open(gate, encoding='utf-8').read()
    m = re.search(r"^IDPY='(.*?)'$", src, re.S | re.M)
    if not m: raise SystemExit('BLIND: IDPY not found')
    L = m.group(1).split('\n')
    i = L.index('    T={}'); j = next(n for n in range(i, len(L)) if L[n].startswith('    if not f(a)'))
    body = '\n'.join(x[4:] for x in L[i:j])
    ns = {'unicodedata': unicodedata, 'b': open(table, 'rb').read()}
    exec(body, ns)
    return ns
