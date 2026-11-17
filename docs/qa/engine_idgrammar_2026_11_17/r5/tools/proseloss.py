#!/usr/bin/env python3
# Reviewer sweep: per real-tracker item, apply one body writer on a shared COPY and
# measure authored content lost. Usage: proseloss.py <bin> <src_db> <outdir> <writer> <evidence_file>
import sqlite3, subprocess, sys, os, shutil, json, re
b, src, out, writer, ev = sys.argv[1:6]
os.makedirs(out, exist_ok=True)
db = os.path.join(out, writer + ".db"); shutil.copy(src, db)
con = sqlite3.connect(db)
items = con.execute("select atm_id, description, body_md from items where current_location='Issues' and coalesce(representation,'section')='section' and status not in ('Operator-blocked') order by atm_id").fetchall()
con.close()
META = re.compile(r'^\*\*([A-Za-z][A-Za-z-]*):\*\*', re.M)
res = {"writer": writer, "n": 0, "rc_nonzero": 0, "lost_bytes_total": 0, "items_lost_gt100": 0, "lost_meta_keys": {}, "examples": []}
for aid, desc, body in items:
    if writer == "block":
        cmd = [b, "block", "--id", aid, "--db", db, "--details", "reviewer probe", "--why", "probe", "--unblock", "[A] keep · [B] drop", "--who", "reviewer"]
    elif writer == "update-same-desc":
        cmd = [b, "update", "--id", aid, "--db", db, "--description", desc]
    elif writer == "neg-same-title":
        c0 = sqlite3.connect(db); t = c0.execute("select title from items where atm_id=? order by rowid desc limit 1", (aid,)).fetchone()[0]; c0.close()
        cmd = [b, "update", "--id", aid, "--db", db, "--title", t]
    elif writer == "update-severity":  # round-5 addition (class sweep finding a)
        cmd = [b, "update", "--id", aid, "--db", db, "--severity", "High"]
    elif writer == "close":
        cmd = [b, "close", aid, "--db", db, "--status", "completed", "--evidence", ev]
    p = subprocess.run(cmd, capture_output=True, text=True)
    res["n"] += 1
    if p.returncode != 0:
        res["rc_nonzero"] += 1; continue
    c = sqlite3.connect(db)
    nb = c.execute("select body_md from items where atm_id=? order by rowid desc limit 1", (aid,)).fetchone()[0]
    c.close()
    old_lines = [l for l in body.splitlines() if l.strip()]
    new_set = set(l.strip() for l in nb.splitlines())
    lost = [l for l in old_lines if l.strip() not in new_set and not l.startswith("**Status:**")
            and not (writer == "update-severity" and l.startswith("**Severity:**"))]
    lb = sum(len(l) for l in lost)
    res["lost_bytes_total"] += lb
    if lb > 100: res["items_lost_gt100"] += 1
    for l in lost:
        m = META.match(l.strip())
        if m: res["lost_meta_keys"][m.group(1)] = res["lost_meta_keys"].get(m.group(1), 0) + 1
    if lb > 100 and len(res["examples"]) < 3: res["examples"].append({"id": aid, "lost_bytes": lb, "first_lost": lost[:3]})
v = subprocess.run([b, "validate", "--db", db], capture_output=True, text=True)
res["validate_rc"] = v.returncode
json.dump(res, open(os.path.join(out, writer + ".json"), "w"), indent=1, ensure_ascii=False)
print(json.dumps({k: res[k] for k in res if k != "examples"}, ensure_ascii=False))
