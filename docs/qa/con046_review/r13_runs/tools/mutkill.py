#!/usr/bin/env python3
"""Find single-character fixtures (authoriser, committer) that tell pipeline variants from the gate's pipeline."""
import sys, unicodedata as u
N=u.normalize; T={}
for l in open(sys.argv[1],encoding='utf-8').read().split('\n')[:-1]:
    x,y=l.split('\t'); T[chr(int(x,16))]=''.join(chr(int(z,16)) for z in y.split())
def mk(kf=lambda s:N('NFKD',N('NFD',s).casefold()), outer=True, rounds=8, onepass=False, skel=True):
    k=kf
    def g(s):
        t=N('NFD',''.join(T.get(c,c) for c in N('NFD',k(s)))) if skel else N('NFD',k(s))
        return k(t) if outer else t
    def f(s):
        if onepass: return g(s)
        for _ in range(rounds):
            t=g(s)
            if t==s: return t
            s=t
        raise ValueError
    return f
F=mk()
V={'nfkd-to-nfd':mk(kf=lambda s:N('NFD',N('NFD',s).casefold())),
   'outer-k-dropped':mk(outer=False),
   'one-pass':mk(onepass=True),
   'outer-nfkd-dropped':mk(kf=lambda s:N('NFD',s).casefold()),
   'inner-nfd-dropped':mk(kf=lambda s:N('NFKD',s.casefold())),
   'nfkc-both':mk(kf=lambda s:N('NFKC',N('NFKC',s).casefold())),
   'nfc-both':mk(kf=lambda s:N('NFC',N('NFC',s).casefold()))}
ok=lambda c: not (0xD800<=ord(c)<=0xDFFF) and not u.category(c).startswith('C') and c.strip()==c
for name,M in V.items():
    hit=None
    for cp in list(range(0x20,0x3000))+list(range(0xFF00,0xFFF0))+list(range(0x1D400,0x1D800)):
        c=chr(cp)
        if not ok(c): continue
        for a,b in ((c,F(c)),(c,c.lower()),(c,N('NFKC',c))):
            if not b or b.strip()!=b or any(u.category(x).startswith('C') for x in b): continue
            try:
                r=F(a)==F(b); m=M(a)==M(b)
            except ValueError: r=F(a)==F(b); m='raise'
            if r!=m: hit=(a,b,r,m); break
        if hit: break
    print(name, 'KILL' if hit else 'NONE', ' '.join('U+%04X'%ord(x) for x in hit[0]) if hit else '', '|', ' '.join('U+%04X'%ord(x) for x in hit[1]) if hit else '', hit[2:] if hit else '')
