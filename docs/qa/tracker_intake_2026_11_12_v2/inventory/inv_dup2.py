import sqlite3,re,sys
db=sys.argv[1]
c=sqlite3.connect('file:%s?mode=ro'%db,uri=True)
rows=list(c.execute("select atm_id,title,description,status from items group by atm_id"))
stop=set("the a an on in of to is after again and for with by from or not no as at be it its this that are was when section review reviewer item items vehicle umbrella tracker intake test tests fix class minor nit important main lander parent links origin acceptance criteria scope reproduction context affected manifest file what independent".split())
def tok(s): return {t for t in re.split(r'[^a-z0-9_]+',s.lower()) if t and t not in stop and len(t)>3 and not t.isdigit()}
intake=[r for r in rows if 'tracker-intake vehicle 2026-11-12' in r[2]]
ids={r[0] for r in intake}
others=[r for r in rows if r[0] not in ids]
for i,t,d,s in intake:
    a=tok(t+' '+d.split('Parent / links:')[0])
    sc=[]
    for j,u,e,st in others:
        b=tok(u+' '+e[:3000])
        jac=len(a&b)*100//max(1,len(a|b))
        sc.append((jac,j,st,u[:80],sorted(a&b)[:8]))
    sc.sort(reverse=True)
    print("==",i,t[:70]); 
    for x in sc[:2]: print("   ",x)
