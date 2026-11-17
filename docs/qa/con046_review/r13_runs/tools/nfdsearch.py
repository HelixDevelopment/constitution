import unicodedata as u, itertools, collections
C=lambda s:u.normalize("NFC",s); D=lambda s:u.normalize("NFD",s)
fC=lambda s:C(C(s).casefold()); fD=lambda s:D(D(s).casefold())
alpha=[chr(c) for c in list(range(0x370,0x400))+list(range(0x1F00,0x2000))+list(range(0x300,0x370))+[0x41,0x49,0x69,0x130,0x131,0xDF,0x1E9E,0x17F]]
alpha=[c for c in alpha if not u.category(c).startswith('C')]
a=collections.defaultdict(set); b=collections.defaultdict(set)
n=0
for L in (1,2):
    for t in itertools.product(alpha,repeat=L):
        s=''.join(t); x=fC(s); y=fD(s); a[x].add(y); b[y].add(x); n+=1
bad1=[(k,v) for k,v in a.items() if len(v)>1]; bad2=[(k,v) for k,v in b.items() if len(v)>1]
print(n,len(alpha),len(bad1),len(bad2))
for k,v in (bad1+bad2)[:5]: print([hex(ord(c)) for c in k],[[hex(ord(c)) for c in z] for z in v])
# explicit witnesses
src=collections.defaultdict(list)
for L in (1,2):
    for t in itertools.product(alpha,repeat=L):
        s=''.join(t); src[(fC(s),fD(s))].append(s)
def show(s): return ' '.join('U+%04X'%ord(c) for c in s)
k,v=bad1[0]; ys=list(v); x=src[(k,ys[0])][0]; y=src[(k,ys[1])][0]
print('bad1 x',show(x),'| y',show(y),'fC eq',fC(x)==fC(y),'fD eq',fD(x)==fD(y))
k,v=bad2[0]; xs=list(v); x=src[(xs[0],k)][0]; y=src[(xs[1],k)][0]
print('bad2 x',show(x),'| y',show(y),'fC eq',fC(x)==fC(y),'fD eq',fD(x)==fD(y))
# prefer shortest
cands=[]
for k,v in bad1:
    v=list(v)
    for i in range(len(v)):
        for j in range(i+1,len(v)):
            x=min(src[(k,v[i])],key=len); y=min(src[(k,v[j])],key=len); cands.append((len(x)+len(y),x,y))
cands.sort(); print('shortest bad1', show(cands[0][1]),'|',show(cands[0][2]))
