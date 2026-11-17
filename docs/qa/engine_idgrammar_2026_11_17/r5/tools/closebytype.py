#!/usr/bin/env python3
# close every Issues section item of a tracker COPY with the closure status its
# Type allows (Bug fixed, Feature implemented, Task completed); record each
# refusal reason and the authored lines lost. Usage: closebytype.py <bin> <src_db> <outdir> <evidence>
import json, os, shutil, sqlite3, subprocess, sys, collections
b, src, out, ev = sys.argv[1:5]; os.makedirs(out, exist_ok=True)
db = os.path.join(out, "close.db"); shutil.copy(src, db); os.chmod(db, 0o644)
con = sqlite3.connect(db)
items = con.execute("select atm_id, type, body_md from items where current_location='Issues' and coalesce(representation,'section')='section' order by atm_id").fetchall()
con.close()
ST = {"Bug": "fixed", "Feature": "implemented", "Task": "completed"}
res = {"n": 0, "accepted": 0, "refused": 0, "reasons": collections.Counter(), "lost_bytes_total": 0, "items_lost": []}
for aid, typ, body in items:
    p = subprocess.run([b, "close", aid, "--db", db, "--status", ST.get(typ, "completed"), "--evidence", ev], capture_output=True, text=True)
    res["n"] += 1
    if p.returncode:
        res["refused"] += 1; res["reasons"][p.stderr.strip().split("\n")[0][:90]] += 1; continue
    res["accepted"] += 1
    c = sqlite3.connect(db); nb = c.execute("select body_md from items where atm_id=? and current_location='Fixed'", (aid,)).fetchone()[0]; c.close()
    new = set(l.strip() for l in nb.splitlines())
    lost = [l for l in body.splitlines() if l.strip() and l.strip() not in new and not l.startswith("**Status:**")
            and not l.startswith("**Operator-Block-Details") and not l.startswith("**Unblock-Choices:**") and not l.startswith("**Evidence:**")]
    if lost:
        res["items_lost"].append({"id": aid, "lost": lost[:3]}); res["lost_bytes_total"] += sum(len(l) for l in lost)
res["validate_rc"] = subprocess.run([b, "validate", "--db", db], capture_output=True).returncode
res["reasons"] = dict(res["reasons"])
json.dump(res, open(os.path.join(out, "closebytype.json"), "w"), indent=1, ensure_ascii=False)
print(json.dumps({k: res[k] for k in res if k != "items_lost"}, ensure_ascii=False)[:1500], "items_lost", len(res["items_lost"]))
