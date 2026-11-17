import sqlite3,re,sys
db=sys.argv[1]
c=sqlite3.connect('file:%s?mode=ro'%db,uri=True)
titles=dict(c.execute("select atm_id,title from items group by atm_id"))
for i,d in c.execute("select atm_id,description from items where description like '%tracker-intake vehicle 2026-11-12%' or atm_id='CON-046' group by atm_id order by atm_id"):
    for m in re.finditer(r'\bCON-\d+\b',d):
        ref=m.group(0)
        if ref=='CON-299' and 'umbrella CON-299' in d[max(0,m.start()-9):m.end()]: continue
        ctx=d[max(0,m.start()-50):m.end()+45].replace('\n',' ')
        print(f"{i}\t{ref}\t{titles.get(ref,'<<MISSING>>')[:70]}\t...{ctx}...")
