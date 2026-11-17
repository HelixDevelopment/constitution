#!/usr/bin/env python3
"""Measure how many rounds the gate's skeleton fixpoint needs: every single code point, then random strings."""
import sys, random, unicodedata as u
N=u.normalize; T={}
for l in open(sys.argv[1],encoding='utf-8').read().split('\n')[:-1]:
    x,y=l.split('\t'); T[chr(int(x,16))]=''.join(chr(int(z,16)) for z in y.split())
k=lambda s:N('NFKD',N('NFD',s).casefold()); g=lambda s:k(N('NFD',''.join(T.get(c,c) for c in N('NFD',k(s)))))
def rounds(s):
    for n in range(1,9):
        t=g(s)
        if t==s: return n
        s=t
    return 99
P=[chr(c) for c in range(0x110000) if not (0xD800<=c<=0xDFFF) and not u.category(chr(c)).startswith('C')]
m1=max(rounds(c) for c in P)
random.seed(int(sys.argv[2])); m2=0; pool=P+list(T)*3
for _ in range(int(sys.argv[3])):
    m2=max(m2,rounds(''.join(random.choice(pool) for _ in range(random.randint(2,12)))))
print('max rounds: single code points %d, random strings %d (seed %s, n %s); 99 = not settled in 8' % (m1,m2,sys.argv[2],sys.argv[3]))
