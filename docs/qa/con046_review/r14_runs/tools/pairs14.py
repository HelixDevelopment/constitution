#!/usr/bin/env python3
"""pairs14.py <gate> <table> - two-character extension of rounds14.py: for each map h in (g, q), every ordered pair
(x, y) and (y, x) with x among the code points needing the most calls on their own and y among every code point that
needs 2 or more calls or is a combining mark (Mn/Mc/Me), count the calls to the fixpoint and look for a call that
shrank the string followed by a call that still changed it. Prints the histogram, any pair needing more calls than the
single maximum, and the shrink-then-change witnesses (first 20). Exit 0; 2 if BLIND (the single-code-point needle `%`
needs fewer than 3 calls)."""
import sys, os, collections, unicodedata as u
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gatefns14 as G
ns = G.load(sys.argv[1], sys.argv[2])
def calls(h, s):
    n = 0; shr = False; w = False
    while True:
        t = h(s); n += 1
        if t == s: return n, w
        if shr: w = True
        shr = len(t) < len(s); s = t
        if n > 20: return n, w
for nm in ('g', 'q'):
    h = ns[nm]; one = {}
    for cp in range(0x110000):
        if 0xD800 <= cp <= 0xDFFF: continue
        one[cp] = calls(h, chr(cp))[0]
    mx = max(one.values())
    X = [cp for cp, n in one.items() if n == mx]
    Y = [cp for cp, n in one.items() if n >= 2 or u.category(chr(cp)) in ('Mn', 'Mc', 'Me')]
    Hh = collections.Counter(); over = []; stc = []
    for x in X:
        for y in Y:
            for s in (chr(x) + chr(y), chr(y) + chr(x)):
                n, w = calls(h, s); Hh[n] += 1
                if n > mx: over.append(s)
                if w: stc.append(s)
    print('map %s: single max %d (%d code points), pair partners %d, pairs %d, histogram %s' % (nm, mx, len(X), len(Y), sum(Hh.values()), dict(sorted(Hh.items()))))
    print('map %s: pairs above the single max %d: %s' % (nm, len(over), ' '.join('/'.join('U+%04X' % ord(c) for c in s) for s in over[:20])))
    print('map %s: shrink-then-change pairs %d: %s' % (nm, len(stc), ' '.join('/'.join('U+%04X' % ord(c) for c in s) for s in stc[:20])))
    if nm == 'g' and calls(h, '%')[0] < 3: print('BLIND: needle'); sys.exit(2)
