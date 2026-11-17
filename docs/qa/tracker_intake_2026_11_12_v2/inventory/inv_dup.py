import sqlite3,re,sys
db=sys.argv[1]
c=sqlite3.connect('file:%s?mode=ro'%db,uri=True)
rows=list(c.execute("select atm_id,title,description,status from items where current_location in ('Issues','Fixed') group by atm_id"))
stop=set("the a an on in of to is after again and for with by from or not no as at be it its this that are was when".split())
def tok(s): return {t for t in re.split(r'[^a-z0-9_.]+',s.lower()) if t and t not in stop and len(t)>2}
def paths(d):
    m=re.search(r'\*\*Affected scope / file-scope manifest:\*\*\n(.*?)(\n\n|$)',d,re.S)
    s=m.group(1) if m else ''
    return set(re.findall(r'[\w./-]+\.(?:sh|py|go|md|tsv|db)\b',s))
intake=[r for r in rows if 'tracker-intake vehicle 2026-11-12' in r[2]]
others=[r for r in rows if r not in intake]
print("intake",len(intake),"others",len(others))
for i,t,d,s in intake:
    ti=tok(t); pi=paths(d)
    sc=[]
    for j,u,e,st in rows:
        if j==i: continue
        tj=tok(u); jac=len(ti&tj)*100//max(1,len(ti|tj))
        pp=len(pi&paths(e))
        if jac>=20 or (pp and jac>=8):
            sc.append((jac,pp,j,st,u[:90]))
    sc.sort(reverse=True)
    if sc:
        print("==",i,t[:80])
        for x in sc[:4]: print("   ",x)
