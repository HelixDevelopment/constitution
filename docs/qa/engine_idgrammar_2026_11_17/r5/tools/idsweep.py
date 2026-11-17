#!/usr/bin/env python3
# Reviewer id-grammar sweep: each candidate id is added to its own COPY of the tracker, then
# db-to-md -> md-to-db -> db-to-md; any accepted id must survive with the same id, body and side rows.
import sqlite3, subprocess, sys, os, shutil, json
b, src, out = sys.argv[1:4]; os.makedirs(out, exist_ok=True)
ids = ["CON-999","con-999","CON-0999","CON-99a","CON-9999999","AB-001","ABCD-001","C0N-001","CON-1.2","CON-١٢","CON-999 ","CON--999","CON_999","XYZ-001","Q-1","CON-999​","CON-９９","CO-1","G12","R7","ATM-DERIVED-abc","CON-00","CON-0","CON-+9","CON-9e9"]
prefixes = ["CON","con","Ab","ABCDEFGHIJ","C1","ÄBC","X"]
rows=[]
def run(cmd): return subprocess.run(cmd, capture_output=True, text=True)
cases=[("id",i) for i in ids]+[("prefix",p) for p in prefixes]
for n,(kind,v) in enumerate(cases):
    d=os.path.join(out,f"c{n}"); os.makedirs(d); db=os.path.join(d,"db0.sqlite"); shutil.copy(src,db)
    c=sqlite3.connect(db); before=set(r[0] for r in c.execute("select atm_id from items")); c.close()
    cmd=[b,"add","Task","Low","--db",db,"--title","reviewer id grammar probe item title","--description","Reviewer id grammar probe description long enough."]
    cmd+= ["--id",v] if kind=="id" else ["--prefix",v]
    p=run(cmd)
    c=sqlite3.connect(db); after=set(r[0] for r in c.execute("select atm_id from items")); c.close()
    new=sorted(after-before)
    r={"kind":kind,"value":v,"add_rc":p.returncode,"new":new}
    if p.returncode==0 and new:
        I1,F1=os.path.join(d,"I1.md"),os.path.join(d,"F1.md")
        r["export1"]=run([b,"sync","db-to-md","--db",db,"--out-issues",I1,"--out-fixed",F1]).returncode
        db1=os.path.join(d,"db1.sqlite"); shutil.copy(db,db1)
        r["md2db"]=run([b,"sync","md-to-db","--db",db1,"--issues",I1,"--fixed",F1]).returncode
        c=sqlite3.connect(db1); a1=set(x[0] for x in c.execute("select atm_id from items"))
        b0=sqlite3.connect(db).execute("select body_md from items where atm_id=?",(new[0],)).fetchone()
        b1=c.execute("select body_md from items where atm_id=?",(new[0],)).fetchone(); c.close()
        r["ids_equal"]=(a1==after); r["body_equal"]=(b0==b1)
        I2,F2=os.path.join(d,"I2.md"),os.path.join(d,"F2.md")
        run([b,"sync","db-to-md","--db",db1,"--out-issues",I2,"--out-fixed",F2])
        r["md_stable"]=open(I1,'rb').read()==open(I2,'rb').read() and open(F1,'rb').read()==open(F2,'rb').read()
        r["LOSS"]= not (r["ids_equal"] and r["body_equal"] and r["md_stable"])
    rows.append(r); shutil.rmtree(d) if not r.get("LOSS") else None
json.dump(rows,open(os.path.join(out,"idsweep.json"),"w"),indent=1,ensure_ascii=False)
print("cases",len(rows),"accepted",sum(1 for r in rows if r["add_rc"]==0),"LOSS",sum(1 for r in rows if r.get("LOSS")))
for r in rows: print(r["kind"],repr(r["value"]),r["add_rc"],r["new"],r.get("LOSS"))
