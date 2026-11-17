#!/usr/bin/env python3
"""Round-13 enumeration of the casefold-only classes under the round-13 authoriser pipeline (gate IDPY), given the table."""
import sys, unicodedata as u
N=u.normalize; T={}
for l in open(sys.argv[1],encoding='utf-8').read().split('\n')[:-1]:
    x,y=l.split('\t'); T[chr(int(x,16))]=''.join(chr(int(z,16)) for z in y.split())
def mk(fold):
    k=lambda s:N('NFKD',fold(N('NFD',s)))
    g=lambda s:k(N('NFD',''.join(T.get(c,c) for c in N('NFD',k(s)))))
    def f(s):
        for _ in range(8):
            t=g(s)
            if t==s: return t
            s=t
        raise ValueError
    return f
F=mk(str.casefold); G=mk(str.lower)
key=lambda c:'%d/%s/%s'%(len(c.casefold()),u.category(c),u.name(c,'?').split()[0])
D=[];E=[]
for cp in range(0x110000):
    c=chr(cp)
    if 0xD800<=cp<=0xDFFF or u.category(c).startswith('C'): continue
    try:
        if F(c)==G(c): continue
        (D if G(c)!=G(F(c)) else E).append(c)
    except ValueError: print('UNSETTLED',hex(cp))
cls={}
for c in D: cls.setdefault(key(c),[]).append(c)
print('D',len(D),'E',len(E),'classes',len(cls))
for k in sorted(cls):
    a=' '.join(cls[k]); b=F(a)
    X=mk(lambda s,k=k:''.join(c.lower() if key(c)==k else c.casefold() for c in s))
    print(k,len(cls[k]),'F-eq',F(a)==F(b),'G-diff',G(a)!=G(b),'X-diff',X(a)!=X(b))
# single-character lowering mutants: which casefold-only characters make their own mutant observable
D1=[]
for c in D:
    X=mk(lambda s,c=c:''.join(x.lower() if x==c else x.casefold() for x in s))
    if X(c)!=X(F(c)): D1.append(c)
print('D1',len(D1))
c1={}
for c in D1: c1.setdefault(key(c),[]).append(c)
for k in sorted(c1):
    a=' '.join(c1[k]); b=F(a)
    X=mk(lambda s,k=k:''.join(x.lower() if key(x)==k else x.casefold() for x in s))
    print(k,len(c1[k]),'X-diff',X(a)!=X(b),' '.join('%04X'%ord(x) for x in c1[k][:6]))
