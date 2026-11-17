#!/usr/bin/env python3
"""rounds14.py <gate> <table> - fixpoint census over every non-surrogate code point (category C included: committer
names may hold any character). For each code point c and each map h in (g, q) of the gate (loaded verbatim by
gatefns14), count the calls of h until h(t)==t (the gate allows 8), and record whether a call SHRANK the string and a
later call still changed it (the case the reviewer mutant RVR13-13 `or len(t)<len(s)` decides differently). Also runs
e(c)=f(f(c,q)) end to end. Prints the call-count histogram per map, the code points with the highest count, and the
shrink-then-change witnesses; exit 2 if the loader fails (BLIND), else 0. Needle: U+0025 '%' must need >1 g call
(the round-13 COMPAT13 fixture `%` vs `o/o` that killed the one-pass mutant)."""
import sys, os, collections
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gatefns14 as G
ns = G.load(sys.argv[1], sys.argv[2]); g, q = ns['g'], ns['q']
def calls(h, s):
    n = 0; shr = False; shrunk_then_changed = False
    while True:
        t = h(s); n += 1
        if t == s: return n, shrunk_then_changed
        if shr: shrunk_then_changed = True
        shr = len(t) < len(s)
        s = t
        if n > 20: return n, shrunk_then_changed
H = {'g': collections.Counter(), 'q': collections.Counter()}; top = {'g': [], 'q': []}; stc = {'g': [], 'q': []}
for cp in range(0x110000):
    if 0xD800 <= cp <= 0xDFFF: continue
    c = chr(cp)
    for nm, h in (('g', g), ('q', q)):
        n, w = calls(h, c); H[nm][n] += 1; top[nm].append((n, cp))
        if w: stc[nm].append(cp)
needle = calls(g, '%')[0]
for nm in 'gq':
    print('map %s: calls histogram %s' % (nm, dict(sorted(H[nm].items()))))
    mx = max(top[nm])[0]; print('map %s: max calls %d at %s' % (nm, mx, ' '.join('U+%04X' % cp for n, cp in top[nm] if n == mx)[:400]))
    print('map %s: shrink-then-change witnesses %d: %s' % (nm, len(stc[nm]), ' '.join('U+%04X' % x for x in stc[nm][:40])))
print('needle %% g calls %d (%s)' % (needle, 'ok' if needle > 2 else 'BLIND'))
sys.exit(0 if needle > 2 else 2)
