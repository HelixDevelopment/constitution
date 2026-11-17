#!/usr/bin/env python3
# Reviewer class sweep (own enumeration): item states x writers; oracle = engine-written detail
# lines (by marker) and side tables after the write AND after a db-to-md/md-to-db cycle.
import sqlite3, subprocess, sys, os, shutil, json, re
b, src, out, root = sys.argv[1:5]; os.makedirs(out, exist_ok=True)
EV=os.path.join(out,"ev.txt"); open(EV,"w").write("ev\n")
KINDS=["Evidence","Operator-Block-Details","Unblock-Choices","Obsolete-Details","Reopened-Details"]
def run(cmd): return subprocess.run(cmd, capture_output=True, text=True, cwd=root)
def q(db,sql,a=()):
    c=sqlite3.connect(db); r=c.execute(sql,a).fetchall(); c.close(); return r
def details(body):
    return sorted(l.strip() for l in body.splitlines() if any(l.strip().startswith("**"+k) for k in KINDS) or re.match(r'^- \*\*(By|On|Reason|Evidence):\*\*',l.strip()))
def side(db,i):
    return (q(db,"select what,why_exhausted_alternatives,unblock_condition,coalesce(who,'') from operator_block_details where atm_id=?",(i,)),
            q(db,"select since,reason,superseding_item,triple_check_evidence from obsolete_details where atm_id=?",(i,)))
I="CON-980"
BLOCK=["block","--id",I,"--details","reviewer probe decision","--why","every alternative tried","--unblock","[A] keep · [B] drop","--who","operator"]
def mk(db,state):
    s=[["add","Task","Low","--db",db,"--id",I,"--title","reviewer detail sweep probe item","--description","Reviewer detail sweep probe description text."]]
    if state in("closed_reopened","closed_reopened_blocked"):
        s+=[["close",I,"--db",db,"--status","completed","--evidence",EV],["reopen","--id",I,"--db",db,"--why","test-failed","--who","AI","--when","2026-11-17","--incident",EV]]
    if state in("blocked","closed_reopened_blocked"): s+=[BLOCK[:3]+["--db",db]+BLOCK[3:]]
    if state=="obsolete": s+=[["close",I,"--db",db,"--status","obsolete","--evidence",EV],["obsolete-details",I,"--db",db,"--since","2026-11-01","--reason","superseded-by-design-change","--superseding","CON-001","--evidence",EV]]
    for c in s:
        p=run([b]+c)
        if p.returncode: return " ".join(c[:1])+": "+p.stderr.strip()[:200]
    return None
WR={
 "upd_desc":["update","--id",I,"--description","Reviewer edited description text, long enough."],
 "upd_title":["update","--id",I,"--title","reviewer detail sweep probe item retitled"],
 "upd_sev":["update","--id",I,"--severity","High"],
 "upd_assign":["update","--id",I,"--assigned-to","reviewer"],
 "upd_type":["update","--id",I,"--type","Bug"],
 "upd_status_ip":["update","--id",I,"--status","In progress"],
 "upd_states":["update","--id",I,"--reproduction-state","UNREPRODUCED","--investigation-state","not-started","--states-updated-by","reviewer"],
 "block":BLOCK,
 "close":["close",I,"--status","completed","--evidence",EV],
 "reopen":["reopen","--id",I,"--why","test-failed","--who","AI","--when","2026-11-18","--incident",EV],
 "move_fixed":["move","--id",I,"--to","Fixed","--why","probe","--status","Completed (→ Fixed.md)","--evidence",EV],
 "repair":["repair-bodies"],
}
STATES=sys.argv[5].split(",") if len(sys.argv)>5 else ["plain","closed_reopened","blocked","closed_reopened_blocked","obsolete"]
REPLACES={"block":{"Operator-Block-Details","Unblock-Choices"},"close":{"Evidence","Operator-Block-Details","Unblock-Choices"},"reopen":{"Reopened-Details"}}
rows=[]
for st in STATES:
  for w,cmd in WR.items():
    for loc in ["Issues","Fixed"]:
        pass
    d=os.path.join(out,f"{st}__{w}"); os.makedirs(d); db=os.path.join(d,"db.sqlite"); shutil.copy(src,db)
    err=mk(db,st); r={"state":st,"writer":w}
    if err: r["setup_err"]=err; rows.append(r); continue
    body0=q(db,"select body_md from items where atm_id=? order by rowid desc limit 1",(I,))[0][0]; det0=details(body0); side0=side(db,I)
    st0=q(db,"select status from items where atm_id=?",(I,))[0][0]
    c=[b]+cmd[:1]+(["--db",db] if w!="repair" else ["--db",db])+cmd[1:]
    if w=="close": c=[b,"close",I,"--db",db]+cmd[2:]
    if st=="obsolete" and cmd[0] in ("update","block"): c=c+["--location","Fixed"]
    p=run(c); r["rc"]=p.returncode
    if p.returncode: r["stderr"]=p.stderr.strip()[:240]; rows.append(r); continue
    body1=q(db,"select body_md from items where atm_id=? order by rowid desc limit 1",(I,))[0][0]; det1=details(body1)
    st1=q(db,"select status from items where atm_id=?",(I,))[0][0]
    rep=REPLACES.get(w,set())
    lost=[l for l in det0 if l not in det1 and not any(l.startswith("**"+k) for k in rep) and not (l.startswith("- **") and "Reopened-Details" in rep)]
    r["op_lost"]=lost
    I1,F1=os.path.join(d,"I.md"),os.path.join(d,"F.md")
    e=run([b,"sync","db-to-md","--db",db,"--out-issues",I1,"--out-fixed",F1]).returncode
    db2=os.path.join(d,"db2.sqlite"); shutil.copy(db,db2)
    m=run([b,"sync","md-to-db","--db",db2,"--issues",I1,"--fixed",F1])
    body2=q(db2,"select body_md from items where atm_id=? order by rowid desc limit 1",(I,))[0][0]
    r["rt_rc"]=(e,m.returncode); r["rt_lost"]=[l for l in det1 if l not in details(body2)]
    s1=side(db,I); s2=side(db2,I); r["side_drift"]= s1!=s2
    r["blocked_without_row"]= st1=="Operator-blocked" and not s1[0]
    r["row_without_block"]= st1!="Operator-blocked" and bool(s1[0])
    v=run([b,"validate","--db",db2]); r["validate2"]=v.returncode
    r["status"]=(st0,st1); r["VIOL"]=bool(lost or r["rt_lost"] or r["side_drift"] or r["blocked_without_row"] or v.returncode or m.returncode)
    if not r["VIOL"]: shutil.rmtree(d)
    rows.append(r)
json.dump(rows,open(os.path.join(out,"detailsweep.json"),"w"),indent=1,ensure_ascii=False)
print("cases",len(rows),"setup_err",sum(1 for r in rows if "setup_err" in r),"refused",sum(1 for r in rows if r.get("rc")),"VIOL",sum(1 for r in rows if r.get("VIOL")),"row_without_block",sum(1 for r in rows if r.get("row_without_block")))
for r in rows:
    if r.get("VIOL") or "setup_err" in r or r.get("rc") or r.get("row_without_block"): print(json.dumps(r,ensure_ascii=False)[:400])
