#!/usr/bin/env python3
# CON-456 round 6 class sweep: item-shaped lines inside fenced code blocks.
# Usage: fencesweep.py <engine binary> <repo root> <out dir>   (<out dir> must not exist)
# Part A (independent of the Go code): a small fence tracker written here counts, in the real
#   docs/Issues.md and docs/Fixed.md, fenced lines shaped like an item heading, a legacy row or a
#   Status line. Control needle: a synthetic document with one fenced heading must count 1;
#   negative control: the same text unfenced must count 0.
# Part B (the engine): a COPY of the real docs gets, inside the first item block, a fenced example
#   holding a heading + Status line; md-to-db into a copy of the real db must keep the item count
#   and the first item's body equal to the injected text. Reports each result as JSON.
import json, os, re, shutil, sqlite3, subprocess, sys
b, root, out = sys.argv[1:4]
if os.path.exists(out):
    sys.exit("out exists")
os.makedirs(out)
HEAD = re.compile(r"^## (\S.*)$")
ROW = re.compile(r"^\| *[0-9]{4}-[0-9]{2}-[0-9]{2} *\|")
def fenced_lines(text):
    res, openc, openn, start, lines = [], None, 0, 0, text.split("\n")
    marks = [False] * len(lines)
    for i, l in enumerate(lines):
        t = l.strip()
        m = re.match(r"^(`{3,}|~{3,})", t)
        if openc is None:
            if m:
                openc, openn, start = m.group(1)[0], len(m.group(1)), i
                marks[i] = True
            continue
        marks[i] = True
        if m and m.group(1)[0] == openc and len(m.group(1)) >= openn and t[len(m.group(1)):].strip() == "":
            openc = None
    if openc is not None:  # unterminated: not a fence
        for j in range(start, len(lines)):
            marks[j] = False
    return lines, marks
def count(text):
    lines, marks = fenced_lines(text)
    h = sum(1 for l, f in zip(lines, marks) if f and HEAD.match(l))
    r = sum(1 for l, f in zip(lines, marks) if f and ROW.match(l))
    s = sum(1 for l, f in zip(lines, marks) if f and l.startswith("**Status:**"))
    return {"fenced_headings": h, "fenced_rows": r, "fenced_status_lines": s}
res = {"engine_sha256": subprocess.run(["sha256sum", b], capture_output=True, text=True).stdout.split()[0]}
needle = "## CON-1 — a\n\n```\n## CON-2 — quoted\n\n**Status:** Queued\n```\n"
res["control_needle_fenced"] = count(needle)
res["negative_control_unfenced"] = count(needle.replace("```\n", ""))
assert res["control_needle_fenced"]["fenced_headings"] == 1 and res["negative_control_unfenced"]["fenced_headings"] == 0, "instrument blind or too broad"
for d in ("Issues", "Fixed"):
    res["real_" + d] = count(open(os.path.join(root, "docs", d + ".md")).read())
# Part B
db = os.path.join(out, "db.sqlite"); shutil.copy(os.path.join(root, "docs/workable_items.db"), db)
iss = open(os.path.join(root, "docs/Issues.md")).read()
fix = open(os.path.join(root, "docs/Fixed.md")).read()
m = re.search(r"^## [A-Z]{3}-\d+ — .*$", iss, re.M)
n0 = int(sqlite3.connect(db).execute("select count(*) from items").fetchone()[0])
inj = "\n\nQuoted example:\n\n```\n## CON-98765 — Quoted phantom\n\n**Status:** Queued\n**Type:** Task\n```\n\nafter the quote\n"
nxt = re.search(r"^## ", iss[m.end():], re.M)
at = m.end() + nxt.start() if nxt else len(iss)
iss2 = iss[:at].rstrip("\n") + inj + "\n" + iss[at:]
open(os.path.join(out, "Issues2.md"), "w").write(iss2)
open(os.path.join(out, "Fixed2.md"), "w").write(fix)
p = subprocess.run([b, "sync", "md-to-db", "--db", db, "--issues", os.path.join(out, "Issues2.md"), "--fixed", os.path.join(out, "Fixed2.md")], capture_output=True, text=True)
c = sqlite3.connect(db)
n1 = int(c.execute("select count(*) from items").fetchone()[0])
phantom = int(c.execute("select count(*) from items where atm_id='CON-98765'").fetchone()[0])
res["engine_inject"] = {"md2db_rc": p.returncode, "items_before": n0, "items_after": n1, "phantom_items": phantom, "stderr_tail": p.stderr[-300:]}
json.dump(res, open(os.path.join(out, "fencesweep.json"), "w"), indent=1)
print(json.dumps(res, indent=1))
sys.exit(0 if phantom == 0 and n1 == n0 else 1)
