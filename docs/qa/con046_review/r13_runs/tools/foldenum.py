import unicodedata as u, collections, sys
N=lambda s:u.normalize("NFC",s)
f=lambda s:N(N(s).casefold())
g=lambda s:N(N(s).lower())
D=[]
for cp in range(0x110000):
    c=chr(cp)
    if 0xD800<=cp<=0xDFFF: continue
    if u.category(c).startswith('C'): continue
    if f(c)!=g(c): D.append(c)
print(len(D), u.unidata_version)
cls=collections.Counter()
ex={}
for c in D:
    k=(len(f(c)), u.category(c), u.name(c,'?').split()[0])
    cls[k]+=1; ex.setdefault(k,c)
for k,v in sorted(cls.items(), key=lambda x:-x[1]): print(k,v,'U+%04X'%ord(ex[k]),u.name(ex[k]))
# concatenation check
a=' '.join(D); cmt=f(a)
print('f equal', f(a)==f(cmt), 'g differs', g(a)!=g(cmt), 'strip ok', a==a.strip())
segA=a.split(' '); segC=cmt.split(' ')
print('segs', len(segA), len(segC))
