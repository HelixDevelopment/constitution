#!/usr/bin/env python3
# CON-456 round 5 class sweep: items READ BY md-to-db x every body writer x every
# line kind. Oracle (independent of the engine): every tagged line of the old
# body is in the new body, in the same order; tagged fenced lines stay fenced;
# an operator_block_details row exists iff the item is Operator-blocked; a
# db-to-md -> md-to-db cycle keeps the body and the row; validate exits 0.
# Control needles: --selfcheck proves the oracle flags a dropped, a reordered
# and an unfenced line; running the sweep with the main binary must show
# violations (the pre-existing loss).
# Usage: mdsweep.py <bin> <outdir> [--selfcheck]
import json, os, re, shutil, sqlite3, subprocess, sys

b, out = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
os.makedirs(out, exist_ok=True)
EV = os.path.join(out, "ev.txt"); open(EV, "w").write("ev\n")
I = "CON-990"
DESC = "LK sweep probe description, long enough for the description floor here."

# Line kinds, each line carries a unique tag LK-nn (closed list, README).
KINDS = [
    ("prose", "Acceptance criteria LK-01: the probe line survives every writer."),
    ("verification", "**Verification:** provisional (section 11.4.290) LK-02 job: probe."),
    ("reported_via", "**Reported-Via:** probe directive LK-03"),
    ("reported_by", "**Reported-By:** probe LK-04"),
    ("implementation", "**Implementation:** probe LK-05"),
    ("candidate_dup", "**Candidate-Duplicate-Of:** CON-001 LK-06"),
    ("indented_record", "  **Evidence:** indented quote LK-07"),
    ("table_header", "| col | LK-08 |"),
    ("table_rule", "|-----|-------|"),
    ("table_row", "| row | LK-09 |"),
    ("subheading", "### Notes LK-10"),
    ("blockquote_record", "> **Evidence:** quoted LK-11"),
    ("bullet_attr", "- **By:** bullet outside the metadata LK-12"),
    ("col0_evidence_prose", "**Evidence:** column-0 record text in prose LK-13"),
    ("col0_obsolete_prose", "**Obsolete-Details:** prose quote LK-14"),
    ("col0_reopened_prose", "**Reopened-Details:** prose quote LK-15"),
    ("col0_choices_prose", "**Unblock-Choices:** prose quote LK-16"),
    ("html_comment", "<!-- comment LK-17 -->"),
    ("plain_bullet", "- plain bullet LK-18"),
    ("numbered", "1. numbered LK-19"),
]
FENCED = [
    "```",
    "**Operator-Block-Details:** WHAT: fenced LK-20",
    "**Unblock-Choices:** fenced LK-21",
    "```",
    "",
    "~~~",
    "**Evidence:** fenced LK-22",
    "**Reopened-Details:** fenced LK-23",
    "~~~",
]
FENCED_TAGS = ["LK-20", "LK-21", "LK-22", "LK-23"]
TAG = re.compile(r"LK-\d\d")


def tagged(body):
    return [l for l in body.splitlines() if TAG.search(l)]


def unfenced_tags(body):
    found, fence = [], False
    for l in body.splitlines():
        if l.strip().startswith("```") or l.strip().startswith("~~~"):
            fence = not fence
            continue
        if not fence:
            found += [t for t in FENCED_TAGS if t in l]
    return found


def oracle(old, new):
    o, n = tagged(old), tagged(new)
    probs = []
    missing = [l for l in o if l not in n]
    if missing:
        probs.append("dropped: " + "; ".join(missing))
    elif [l for l in n if l in o] != o:
        probs.append("reordered")
    u = unfenced_tags(new)
    if u:
        probs.append("unfenced: " + ",".join(u))
    return probs


if "--selfcheck" in sys.argv:
    body = "\n".join([k[1] for k in KINDS] + FENCED) + "\n"
    drop = body.replace(KINDS[3][1] + "\n", "", 1)
    swap = body.replace(KINDS[0][1] + "\n" + KINDS[1][1], KINDS[1][1] + "\n" + KINDS[0][1], 1)
    unf = body.replace("```\n**Operator", "**Operator", 1)
    r = {"golden_false": oracle(body, body), "drop": oracle(body, drop), "reorder": oracle(body, swap), "unfence": oracle(body, unf)}
    ok = r["golden_false"] == [] and all(r[k] for k in ("drop", "reorder", "unfence"))
    json.dump(r, open(os.path.join(out, "selfcheck.json"), "w"), indent=1)
    print("SELFCHECK", "PASS" if ok else "FAIL", json.dumps(r)[:300])
    sys.exit(0 if ok else 1)


def run(cmd, cwd=None):
    return subprocess.run([b] + cmd, capture_output=True, text=True, cwd=cwd or out)


def q(db, sql, a=()):
    c = sqlite3.connect(db); r = c.execute(sql, a).fetchall(); c.close(); return r


def body_of(db):
    r = q(db, "select body_md from items where atm_id=? order by rowid desc limit 1", (I,))
    return r[0][0] if r else None


def status_of(db):
    return q(db, "select status from items where atm_id=? order by rowid desc limit 1", (I,))[0][0]


def rows(db):
    return q(db, "select what,why_exhausted_alternatives,unblock_condition,coalesce(who,'') from operator_block_details where atm_id=?", (I,))


def dump(db):
    return (q(db, "select * from items order by atm_id, current_location"), q(db, "select * from operator_block_details"),
            q(db, "select count(*) from item_history"))


def mdread(d):
    """An item read by md-to-db whose body carries every line kind."""
    db0 = os.path.join(d, "seed.db")
    p = run(["add", "Task", "Low", "--db", db0, "--id", I, "--title", "LK sweep probe item", "--description", DESC])
    if p.returncode:
        return None, "add: " + p.stderr[:200]
    iss, fix = os.path.join(d, "Issues.md"), os.path.join(d, "Fixed.md")
    run(["sync", "db-to-md", "--db", db0, "--out-issues", iss, "--out-fixed", fix])
    s = open(iss).read()
    ins = "\n\n".join([k[1] for k in KINDS[:7]]) + "\n\n" + "\n".join(k[1] for k in KINDS[7:10]) + "\n\n" + \
        "\n\n".join(k[1] for k in KINDS[10:]) + "\n\n" + "\n".join(FENCED)
    s2 = s.replace(DESC + "\n", DESC + "\n\n" + ins + "\n", 1)
    if s2 == s:
        return None, "could not place the line kinds"
    open(iss, "w").write(s2)
    db = os.path.join(d, "db.sqlite")
    p = run(["sync", "md-to-db", "--db", db, "--issues", iss, "--fixed", fix])
    if p.returncode:
        return None, "md-to-db: " + p.stderr[:200]
    missing = [k[1] for k in KINDS if k[1] not in body_of(db)]
    if missing:
        return None, "control: md-to-db body lacks " + "; ".join(missing)
    return db, None


BLOCK = ["block", "--id", I, "--details", "sweep probe decision", "--why", "every alternative tried", "--unblock", "[A] keep · [B] drop", "--who", "operator"]
SETUP = {
    "queued": [],
    "blocked": [BLOCK],
    "fixed": [["close", I, "--status", "completed", "--evidence", EV]],
    "reopened": [["close", I, "--status", "completed", "--evidence", EV],
                 ["reopen", "--id", I, "--why", "test-failed", "--who", "AI", "--when", "2026-11-17", "--incident", EV]],
}
WRITERS = {
    "upd_desc_new": lambda db, loc: ["update", "--db", db, "--id", I, "--location", loc, "--description", DESC + " Edited."],
    "upd_desc_same": lambda db, loc: ["update", "--db", db, "--id", I, "--location", loc, "--description",
                                      q(db, "select description from items where atm_id=?", (I,))[0][0]],
    "upd_title": lambda db, loc: ["update", "--db", db, "--id", I, "--location", loc, "--title", "LK sweep probe item retitled"],
    "upd_status": lambda db, loc: ["update", "--db", db, "--id", I, "--location", loc, "--status", "In progress"],
    "upd_sev": lambda db, loc: ["update", "--db", db, "--id", I, "--location", loc, "--severity", "High"],
    "upd_type": lambda db, loc: ["update", "--db", db, "--id", I, "--location", loc, "--type", "Bug"],
    "upd_assign": lambda db, loc: ["update", "--db", db, "--id", I, "--location", loc, "--assigned-to", "probe"],
    "block": lambda db, loc: BLOCK[:1] + ["--db", db, "--location", loc] + BLOCK[1:],
    "close": lambda db, loc: ["close", I, "--db", db, "--status", "completed", "--evidence", EV],
    "obsolete": lambda db, loc: ["close", I, "--db", db, "--status", "obsolete", "--evidence", EV],
    "obsolete_details": lambda db, loc: ["obsolete-details", I, "--db", db, "--since", "2026-11-01", "--reason",
                                         "superseded-by-design-change", "--superseding", "CON-001", "--evidence", EV],
    "reopen": lambda db, loc: ["reopen", "--db", db, "--id", I, "--why", "test-failed", "--who", "AI", "--when", "2026-11-18", "--incident", EV],
    "move_fixed": lambda db, loc: ["move", "--db", db, "--id", I, "--to", "Fixed", "--why", "probe", "--status", "Completed (→ Fixed.md)", "--evidence", EV],
    "move_issues": lambda db, loc: ["move", "--db", db, "--id", I, "--to", "Issues", "--why", "probe", "--status", "In progress", "--evidence", EV],
    "repair": lambda db, loc: ["repair-bodies", "--db", db],
}
res = []
for st, steps in SETUP.items():
    for w, mk in WRITERS.items():
        d = os.path.join(out, f"{st}__{w}"); os.makedirs(d)
        db, err = mdread(d)
        r = {"state": st, "writer": w}
        if err:
            r["setup_err"] = err; res.append(r); continue
        for s in steps:
            p = run(s[:1] + ["--db", db] + s[1:] if s[0] != "close" else ["close", I, "--db", db] + s[2:])
            if p.returncode:
                r["setup_err"] = " ".join(s[:1]) + ": " + p.stderr[:200]; break
        if "setup_err" in r:
            res.append(r); continue
        loc = q(db, "select current_location from items where atm_id=?", (I,))[0][0]
        old, before = body_of(db), dump(db)
        p = run(mk(db, loc))
        r["rc"] = p.returncode
        if p.returncode:
            r["stderr"] = p.stderr.strip()[:240]
            r["refusal_wrote"] = dump(db) != before
            r["VIOL"] = r["refusal_wrote"]
            res.append(r)
            if not r["VIOL"]:
                shutil.rmtree(d)
            continue
        new = body_of(db)
        r["probs"] = oracle(old, new)
        s1 = status_of(db)
        r["status"] = s1
        r["row_ok"] = (len(rows(db)) == 1) == (s1 == "Operator-blocked")
        i2, f2 = os.path.join(d, "I2.md"), os.path.join(d, "F2.md")
        e = run(["sync", "db-to-md", "--db", db, "--out-issues", i2, "--out-fixed", f2]).returncode
        db2 = os.path.join(d, "rt.db")
        m = run(["sync", "md-to-db", "--db", db2, "--issues", i2, "--fixed", f2]).returncode
        r["cycle_body_same"] = body_of(db2) == new
        r["cycle_rows_same"] = rows(db2) == rows(db)
        r["validate"] = run(["validate", "--db", db2]).returncode
        r["VIOL"] = bool(r["probs"] or not r["row_ok"] or e or m or not r["cycle_body_same"] or not r["cycle_rows_same"] or r["validate"])
        res.append(r)
        if not r["VIOL"]:
            shutil.rmtree(d)
# The add path (report_item.sh only calls add): every line kind in the
# description of a new item.
d = os.path.join(out, "add__rich"); os.makedirs(d)
db = os.path.join(d, "db.sqlite")
rich = DESC + "\n\n" + "\n\n".join(k[1] for k in KINDS[:7]) + "\n\n" + "\n".join(k[1] for k in KINDS[7:10]) + "\n\n" + \
    "\n\n".join(k[1] for k in KINDS[10:]) + "\n\n" + "\n".join(FENCED)
p = run(["add", "Task", "Low", "--db", db, "--id", I, "--title", "LK sweep probe item", "--description", rich])
r = {"state": "new", "writer": "add", "rc": p.returncode}
if p.returncode:
    r["stderr"] = p.stderr.strip()[:240]; r["VIOL"] = False
else:
    new = body_of(db)
    r["probs"] = oracle(rich, new)
    i2, f2 = os.path.join(d, "I2.md"), os.path.join(d, "F2.md")
    run(["sync", "db-to-md", "--db", db, "--out-issues", i2, "--out-fixed", f2])
    db2 = os.path.join(d, "rt.db")
    m = run(["sync", "md-to-db", "--db", db2, "--issues", i2, "--fixed", f2]).returncode
    r["cycle_body_same"] = body_of(db2) == new
    r["validate"] = run(["validate", "--db", db2]).returncode
    r["VIOL"] = bool(r["probs"] or m or not r["cycle_body_same"] or r["validate"])
res.append(r)
if not r["VIOL"]:
    shutil.rmtree(d)
json.dump(res, open(os.path.join(out, "mdsweep.json"), "w"), indent=1, ensure_ascii=False)
print("cases", len(res), "setup_err", sum(1 for r in res if "setup_err" in r), "refused", sum(1 for r in res if r.get("rc")),
      "accepted", sum(1 for r in res if r.get("rc") == 0), "VIOL", sum(1 for r in res if r.get("VIOL")))
for r in res:
    if r.get("VIOL") or "setup_err" in r:
        print(json.dumps(r, ensure_ascii=False)[:400])
