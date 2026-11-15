import unicodedata as u, collections
N=lambda s:u.normalize("NFC",s)
f=lambda s:N(N(s).casefold())
g=lambda s:N(N(s).lower())
D=[];E=[]
for cp in range(0x110000):
    if 0xD800<=cp<=0xDFFF: continue
    c=chr(cp)
    if u.category(c).startswith('C'): continue
    if f(c)!=g(c):
        (D if g(c)!=g(f(c)) else E).append(c)
print('witness f(c) works:',len(D),' relation-equal (no witness via f(c)):',len(E))
print('E examples:',' '.join('U+%04X'%ord(c) for c in E[:5]), collections.Counter(u.name(c).split()[0] for c in E))
# for E, search any witness x among all chars with f(x)==f(c)
byf=collections.defaultdict(list)
for cp in range(0x110000):
    if 0xD800<=cp<=0xDFFF: continue
    c=chr(cp)
    if u.category(c).startswith('C'): continue
    byf[f(c)].append(c)
w=[c for c in E if any(g(x)!=g(c) for x in byf[f(c)]+[f(c)])]
print('E with some single-char/fold witness:',len(w))
cls=collections.Counter((len(f(c)),u.category(c),u.name(c).split()[0]) for c in D)
print(len(cls)); [print(k,v) for k,v in sorted(cls.items())]
