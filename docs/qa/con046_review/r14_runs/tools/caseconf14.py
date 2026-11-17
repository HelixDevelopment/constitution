#!/usr/bin/env python3
"""caseconf14.py <gate> <table> - R13-2 measurement: UTS #39 single-code-point skeleton classes (case-preserving
NFD(map(NFD(NFKD(x))))) that the round-13 relation splits, and that the round-14 relation splits; empty-skeleton
counts under f and e; q with and without an outer NFKD (partition equality). Deterministic; prints one report."""
import sys, collections, unicodedata as u
import os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); import gatefns14 as GF
ns = GF.load(sys.argv[1], sys.argv[2]); T = ns['T']; N = u.normalize
f, e = ns['f'], ns['e']   # the gate's own functions, loaded verbatim
cps = [chr(c) for c in range(0x110000) if not (0xD800 <= c <= 0xDFFF) and u.category(chr(c))[0] != 'C']
sk = lambda s: N('NFD', ''.join(T.get(c, c) for c in N('NFD', N('NFKD', s))))
skr = lambda s: N('NFD', ''.join(T.get(c, c) for c in N('NFD', s)))   # the review's form (no NFKD), for comparison
# union-find over the relation "f equal or e equal" restricted to single code points
def classes(keyfns):
    par = {c: c for c in cps}
    def find(x):
        while par[x] != x: par[x] = par[par[x]]; x = par[x]
        return x
    for kf in keyfns:
        b = collections.defaultdict(list)
        for c in cps: b[kf(c)].append(c)
        for v in b.values():
            for y in v[1:]: par[find(y)] = find(v[0])
    return find
old = classes([f]); new = classes([f, e])
for label, skf in (('NFD(map(NFD(NFKD(x))))', sk), ('NFD(map(NFD(x))) [review r13]', skr)):
    grp = collections.defaultdict(list)
    for c in cps: grp[skf(c)].append(c)
    so = [v for v in grp.values() if len({old(c) for c in v}) > 1]
    sn = [v for v in grp.values() if len({new(c) for c in v}) > 1]
    print('UTS39 single-cp skeleton classes, %s, split: round-13 relation %d (chars %d); round-14 relation %d (chars %d)' % (
        label, len(so), sum(map(len, so)), len(sn), sum(map(len, sn))))
for v in sn[:20]: print('  still split:', ' '.join('U+%04X' % ord(c) for c in v[:12]))
asc = [v for v in sn if any(c.isascii() and c.isalnum() for c in v)]
print('round-14 split classes holding an ASCII letter/digit: %d' % len(asc))
ef = sum(1 for c in cps if not f(c).split()); ee = sum(1 for c in cps if not e(c).split())
both = sum(1 for c in cps if (not f(c).split()) != (not e(c).split()))
print('empty-or-blank skeleton: f %d, e %d, differ %d' % (ef, ee, both))
