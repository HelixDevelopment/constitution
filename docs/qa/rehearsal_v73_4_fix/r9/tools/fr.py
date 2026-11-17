import sys, sqlite3, importlib.util, re
S=sys.argv[1]; db=sys.argv[2]
def load(p,n):
    sp=importlib.util.spec_from_file_location(n,p); m=importlib.util.module_from_spec(sp); sp.loader.exec_module(m); return m
M=load(S+"/repo/scripts/validation/check_provisional_verification_lines.py","r9")
R8=load(S+"/work/ck_r8.py","r8")
con=sqlite3.connect("file:%s?mode=ro"%db, uri=True)
rows=con.execute("select atm_id,status,body_md,created_at from items").fetchall()
items={r[0]:r[1] for r in rows}
import datetime
prov=[r for r in rows if r[1] in ("Ready for testing","In testing")]
stats={"items":len(rows),"provisional":len(prov)}
kinds={}; grammar_ok_refused_by_linemodel=[]; with_line=0
for k,st,b,cr in prov:
    ctx=M.Context(S+"/repo", items, k, cr[:10] if isinstance(cr,str) else None, datetime.date(2026,11,17), 60, None)
    lines=[l for l in re.split(r"\r\n|\r|\n", b) if l.startswith(M.PREFIX)]
    cnt, probs = M.scan(b)
    kind = probs[0].split(":")[0] if probs else ("grammar" if lines else "noline")
    gl = M.check_line(lines[0], ctx) if len(lines)==1 else "n/a"
    with_line += bool(lines)
    r9=M.check_body(b, ctx=ctx); 
    ctx8=R8.Context(S+"/repo", items, k, cr[:10] if isinstance(cr,str) else None, datetime.date(2026,11,17), 60, None)
    r8=R8.check_body(b, ctx=ctx8)
    kinds[kind]=kinds.get(kind,0)+1
    flag = "FALSE-REFUSAL" if (gl is None and probs) else ""
    if flag: grammar_ok_refused_by_linemodel.append(k)
    print("%-8s r9=%-8s r8=%-8s kind=%-9s grammar=%s %s" % (k, "ACCEPT" if r9 is None else "REFUSE", "ACCEPT" if r8 is None else "REFUSE", kind, "OK" if gl is None else (gl[:70] if isinstance(gl,str) else gl), flag))
print("SUMMARY", stats, "with_prefix_line=%d" % with_line, "kinds=%s" % kinds, "grammar_valid_refused_by_line_model=%d %s" % (len(grammar_ok_refused_by_linemodel), " ".join(grammar_ok_refused_by_linemodel)))
