import unicodedata as u
N=lambda s:u.normalize("NFC",s); f=lambda s:N(N(s).casefold()); g=lambda s:N(N(s).lower())
cls={}
for cp in range(0x110000):
    c=chr(cp)
    if 0xD800<=cp<=0xDFFF or u.category(c).startswith("C") or f(c)==g(c) or g(c)==g(f(c)): continue
    cls.setdefault("%d/%s/%s"%(len(c.casefold()),u.category(c),u.name(c,"?").split()[0]),[]).append(c)
for k in sorted(cls): print(k, len(cls[k]))
