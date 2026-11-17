#!/usr/bin/env python3
"""class_enum.py - CON-456 round 2 class enumerator (scratch instrument, not shipped).

Class under test: "what a write accepts != what sync md-to-db reads back".
Dimensions: id shape x title shape x description shape x document (Issues/Fixed)
x operation (add, move, close, update --title, update --description, block,
reopen), then db-to-md -> md-to-db on a copy.

Every case runs on its own copy of a real tracker database with the REAL engine
binary. Verdicts (closed set):
  REFUSED        an op exited non-zero and the database dump is unchanged by it
  REFUSED_WROTE  an op exited non-zero but changed the database      (violation)
  RT_OK          md-to-db exit 0 and every Markdown-carried field of every row
                 is unchanged (description is derived by md-to-db, reported apart)
  RT_STUCK       md-to-db refused, database unchanged (accepted-then-stuck: the
                 write seam accepted what md-to-db cannot read back) (violation)
  RT_PARTIAL     md-to-db non-zero and the database changed            (violation)
  RT_LOSS / RT_REPLACED / RT_PHANTOM / RT_FIELD(...)                    (violation)

Usage: class_enum.py --bin BIN --db DB --out OUT --valcwd DIR [--block NAME ...]
       [--control-bin BIN]   (runs the positive/negative control rows with it)
"""
import argparse
import hashlib
import json
import os
import shutil
import sqlite3
import subprocess
import sys

D0 = "Class enumeration item for the round trip sweep, long enough for the floor."

CARRIED = ["type", "status", "severity", "title", "created_by", "assigned_to",
           "closure_date", "round", "commit_ref",
           "reproduction_state", "reproduction_surface", "reproduction_evidence",
           "reproduction_red_cmd", "reproduction_green_cmd", "reproduction_env",
           "reproduction_signature", "reproduction_blocker", "reproduction_updated_at",
           "reproduction_updated_by", "investigation_state", "investigation_root_cause",
           "investigation_evidence", "investigation_updated_at", "investigation_updated_by"]

# id shapes: (name, explicit id or None, prefix or None)
IDS = [
    ("canon", "CON-7{n:04d}", None),
    ("legacy", "GZ{n}", None),
    ("legacy1", "GS-9{n:04d}", None),
    ("pfx_canon", None, "CON"),
    ("pfx_legacy", None, "GS"),
]

TITLES = [
    ("plain", "plain title words for the sweep"),
    ("lead_space", "  leading space title"),
    ("trail_space", "trailing space title  "),
    ("bracket_start", "[ABC-9] bracket id at start"),
    ("bracket_mid_existing", "crash in [CON-123] path"),
    ("bracket_mid_new", "crash in [ZZQ-77] path"),
    ("bracket_alpha", "[ABC-x] not a bracket id"),
    ("status_suffix", "thing — `Fixed (→ Fixed.md)`"),
    ("status_nodash", "thing `Completed later`"),
    ("migrated", "thing [migrated from old]"),
    ("paren_dash", "(x) — y paren dash"),
    ("emdash", "a — b — c"),
    ("backticks", "uses `code` span"),
    ("nl_heading", "a\n## CON-8811 — injected"),
    ("nl_plain", "a\nsecond line"),
    ("cr", "a\rb carriage"),
    ("section_sign", "§FL section sign start"),
    ("hash_start", "# hash start"),
    ("dot_start", ". dot start"),
    ("unicode", "Ünïcödé — 日本語"),
    ("long", "x" * 300),
    ("tab", "a\tb tab"),
    ("meta_like", "**Status:** Fixed (→ Fixed.md)"),
    ("trail_backslash", "ends with \\"),
]

DESCS = [
    ("plain", D0),
    ("heading_item", "line one of the description\n## CON-8813 — injected via description\nmore words here to pass the floor"),
    ("heading_raw", "line one of the description\n## Notes\nmore words here to pass the floor ok"),
    ("status_line", "line one of the description words\n**Status:** Fixed (→ Fixed.md)\nmore words"),
    ("type_line", "line one of the description words\n**Type:** Bug\nmore words"),
    ("severity_line", "line one of the description words\n**Severity:** Critical\nmore words"),
    ("subheading", "line one of the description words\n### sub heading\n**Status:** Fixed (→ Fixed.md)\nmore"),
    ("pipe_row", "line one of the description words\n| 2026-01-01 | CON-8814: x | Bug | Fixed | r1 | abc | ev |\nmore words"),
    ("repro_line", "line one of the description words\n**Reproduction:** reproduced-live — x\nmore words"),
    ("leading_nl", "\nleading newline description words here for floor"),
    ("trail_spaces", D0 + "   "),
    ("cr_desc", "line one of the description\rmore words after a carriage return"),
]

DETAILS = [
    ("plain", "blocked on the operator decision about the sweep"),
    ("nl_heading", "blocked\n## CON-8815 — injected via details"),
    ("nl_status", "blocked\n**Status:** Fixed (→ Fixed.md)"),
]


def dump_hash(db):
    c = sqlite3.connect(db)
    try:
        h = hashlib.sha256()
        for line in c.iterdump():
            h.update(line.encode("utf-8", "surrogatepass"))
            h.update(b"\n")
        return h.hexdigest()
    finally:
        c.close()


def rows(db):
    c = sqlite3.connect(db)
    try:
        cols = ", ".join("COALESCE(%s,'')" % k for k in CARRIED)
        out = {}
        for r in c.execute("SELECT atm_id, current_location, COALESCE(representation,'section'), "
                           "COALESCE(description,''), COALESCE(body_md,''), " + cols + " FROM items"):
            out[(r[0], r[1], r[2])] = {"description": r[3], "body": r[4],
                                       "fields": dict(zip(CARRIED, r[5:]))}
        return out
    finally:
        c.close()


def run(cmd, cwd=None):
    env = dict(os.environ)
    if cwd:
        # The engine resolves relative evidence paths against $PWD, not the
        # process cwd (pathresolve.go resolveInvocationRelative).
        env["PWD"] = os.path.abspath(cwd)
    p = subprocess.run(cmd, cwd=cwd, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return p.returncode, p.stdout.decode("utf-8", "replace"), p.stderr.decode("utf-8", "replace")


BASELINE = {"fields": set(), "validate": set()}


def field_diffs(before, after):
    out = set()
    for k in before:
        if k not in after:
            continue
        for f in CARRIED:
            if before[k]["fields"][f] != after[k]["fields"][f]:
                out.add("%s.%s" % (k[0], f))
    return out


def validate_lines(text):
    return set(l.strip() for l in text.splitlines() if l.strip().startswith("- "))


def classify(before, after, m2d_rc, changed_by_m2d):
    if m2d_rc != 0:
        return ("RT_PARTIAL" if changed_by_m2d else "RT_STUCK"), ""
    lost = [k for k in before if k not in after]
    new = [k for k in after if k not in before]
    if lost and new:
        return "RT_REPLACED", "lost=%s new=%s" % (lost, new)
    if lost:
        return "RT_LOSS", "lost=%s" % lost
    if new:
        return "RT_PHANTOM", "new=%s" % new
    diffs = sorted(field_diffs(before, after) - BASELINE["fields"])
    if diffs:
        return "RT_FIELD", ",".join(diffs)
    return "RT_OK", ""


def build_cases():
    cases = []
    n = 0

    def nid(tpl):
        return None if tpl is None else tpl.format(n=n)
    # Block A: ids x titles x {Issues, Fixed via move}
    for iname, itpl, pfx in IDS:
        for tname, title in TITLES:
            for doc in ("Issues", "Fixed"):
                n += 1
                cases.append({"block": "A", "name": "A_%s_%s_%s" % (iname, tname, doc),
                              "id": nid(itpl), "prefix": pfx, "title": title, "desc": D0,
                              "ops": ["add"] + (["move"] if doc == "Fixed" else [])})
    # Block B: ids x descriptions x {Issues, Fixed via move}
    for iname, itpl, pfx in IDS:
        for dname, desc in DESCS:
            for doc in ("Issues", "Fixed"):
                n += 1
                cases.append({"block": "B", "name": "B_%s_%s_%s" % (iname, dname, doc),
                              "id": nid(itpl), "prefix": pfx, "title": "plain title words for the sweep",
                              "desc": desc, "ops": ["add"] + (["move"] if doc == "Fixed" else [])})
    # Block C: operations that write a heading or body after a plain add
    for iname, itpl, pfx in IDS[:3]:
        for tname, title in TITLES:
            n += 1
            cases.append({"block": "C", "name": "C_update_title_%s_%s" % (iname, tname),
                          "id": nid(itpl), "prefix": pfx, "title": "plain title words for the sweep",
                          "desc": D0, "ops": ["add", ("update_title", title)]})
        for dname, desc in DESCS:
            n += 1
            cases.append({"block": "C", "name": "C_update_desc_%s_%s" % (iname, dname),
                          "id": nid(itpl), "prefix": pfx, "title": "plain title words for the sweep",
                          "desc": D0, "ops": ["add", ("update_desc", desc)]})
        for dname, det in DETAILS:
            n += 1
            cases.append({"block": "C", "name": "C_block_%s_%s" % (iname, dname),
                          "id": nid(itpl), "prefix": pfx, "title": "plain title words for the sweep",
                          "desc": D0, "ops": ["add", ("block", det)]})
            n += 1
            cases.append({"block": "C", "name": "C_close_reopen_%s_%s" % (iname, dname),
                          "id": nid(itpl), "prefix": pfx, "title": "plain title words for the sweep",
                          "desc": D0, "ops": ["add", "close", ("reopen", det)]})
        n += 1
        cases.append({"block": "C", "name": "C_close_%s" % iname,
                      "id": nid(itpl), "prefix": pfx, "title": "plain title words for the sweep",
                      "desc": D0, "ops": ["add", "close"]})
    return cases


def resolve_new_id(before_keys, db):
    now = set(rows(db).keys())
    new = [k for k in now - before_keys]
    return new[0][0] if len(new) == 1 else None


def run_case(binp, base_db, out, valcwd, case):
    d = os.path.join(out, case["name"])
    os.makedirs(d, exist_ok=True)
    db = os.path.join(d, "db.sqlite")
    shutil.copyfile(base_db, db)
    ev = os.path.join(d, "evidence.txt")
    with open(ev, "w", encoding="utf-8") as f:
        f.write("class enumeration evidence file\n")
    keys0 = set(rows(db).keys())
    item_id = case["id"]
    log = []
    for op in case["ops"]:
        h0 = dump_hash(db)
        if op == "add":
            cmd = [binp, "add", "Task", "Low", "--db", db, "--title", case["title"], "--description", case["desc"]]
            cmd += ["--id", item_id] if item_id else ["--prefix", case["prefix"]]
        elif op == "move":
            cmd = [binp, "move", "--db", db, "--id", item_id, "--to", "Fixed", "--status", "Completed",
                   "--why", "class enumeration move", "--evidence", ev]
        elif op == "close":
            cmd = [binp, "close", item_id, "--db", db, "--status", "completed", "--evidence", ev]
        elif op[0] == "update_title":
            cmd = [binp, "update", "--db", db, "--id", item_id, "--title", op[1]]
        elif op[0] == "update_desc":
            cmd = [binp, "update", "--db", db, "--id", item_id, "--description", op[1]]
        elif op[0] == "block":
            cmd = [binp, "block", "--db", db, "--id", item_id, "--details", op[1],
                   "--why", "no alternative left in the sweep", "--unblock", "operator answers", "--who", "operator"]
        elif op[0] == "reopen":
            cmd = [binp, "reopen", "--db", db, "--id", item_id, "--who", "AI", "--when", "2026-11-17",
                   "--why", "test-failed", "--incident", ev]
        else:
            raise SystemExit("unknown op %r" % (op,))
        rc, so, se = run(cmd, cwd=valcwd)
        opname = op if isinstance(op, str) else op[0]
        log.append({"op": opname, "rc": rc, "stdout": so, "stderr": se})
        if opname == "add" and item_id is None and rc == 0:
            item_id = resolve_new_id(keys0, db)
        h1 = dump_hash(db)
        if rc != 0:
            verdict = "REFUSED" if h0 == h1 else "REFUSED_WROTE"
            return {"name": case["name"], "block": case["block"], "verdict": verdict,
                    "at": opname, "detail": se.strip().splitlines()[-1][:160] if se.strip() else "",
                    "desc_changed": "-", "body_same": "-", "validate_rc": "-", "id": item_id or ""}, log
    before = rows(db)
    is_md, fx_md = os.path.join(d, "Issues.md"), os.path.join(d, "Fixed.md")
    rc, so, se = run([binp, "sync", "db-to-md", "--db", db, "--out-issues", is_md, "--out-fixed", fx_md], cwd=valcwd)
    log.append({"op": "db-to-md", "rc": rc, "stdout": so, "stderr": se})
    rt = os.path.join(d, "db_rt.sqlite")
    shutil.copyfile(db, rt)
    h0 = dump_hash(rt)
    rc, so, se = run([binp, "sync", "md-to-db", "--db", rt, "--issues", is_md, "--fixed", fx_md], cwd=valcwd)
    log.append({"op": "md-to-db", "rc": rc, "stdout": so, "stderr": se})
    h1 = dump_hash(rt)
    after = rows(rt)
    verdict, detail = classify(before, after, rc, h0 != h1)
    if rc != 0 and se.strip():
        detail = (detail + " " + se.strip().splitlines()[-1][:160]).strip()
    vrc, vso, vse = run([binp, "validate", "--db", db], cwd=valcwd)
    log.append({"op": "validate", "rc": vrc, "stdout": vso[-2000:], "stderr": vse[-2000:]})
    newv = validate_lines(vso + "\n" + vse) - BASELINE["validate"]
    vrc = "%s(+%d)" % (vrc, len(newv)) if newv else "%s(=base)" % vrc
    desc_changed = body_same = "-"
    if item_id:
        k = [x for x in before if x[0] == item_id]
        if k and k[0] in after:
            desc_changed = "yes" if before[k[0]]["description"] != after[k[0]]["description"] else "no"
            body_same = "yes" if before[k[0]]["body"] == after[k[0]]["body"] else "no"
    return {"name": case["name"], "block": case["block"], "verdict": verdict, "at": "md-to-db" if rc else "",
            "detail": detail, "desc_changed": desc_changed, "body_same": body_same,
            "validate_rc": vrc, "id": item_id or ""}, log


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--bin", required=True)
    ap.add_argument("--db", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--valcwd", required=True)
    ap.add_argument("--control-bin", required=True,
                    help="engine known to lose items (positive control)")
    ap.add_argument("--block", action="append")
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    cases = build_cases()
    if a.block:
        cases = [c for c in cases if c["block"] in a.block]
    # Baseline: the unmodified database round trip and validate output. Any
    # drift found here is pre-existing and reported separately, never charged
    # to a case.
    bd = os.path.join(a.out, "BASELINE")
    os.makedirs(bd, exist_ok=True)
    bdb = os.path.join(bd, "db.sqlite")
    shutil.copyfile(a.db, bdb)
    bis, bfx = os.path.join(bd, "Issues.md"), os.path.join(bd, "Fixed.md")
    r1 = run([a.bin, "sync", "db-to-md", "--db", bdb, "--out-issues", bis, "--out-fixed", bfx], cwd=a.valcwd)
    brt = os.path.join(bd, "db_rt.sqlite")
    shutil.copyfile(bdb, brt)
    r2 = run([a.bin, "sync", "md-to-db", "--db", brt, "--issues", bis, "--fixed", bfx], cwd=a.valcwd)
    b0, b1 = rows(bdb), rows(brt)
    BASELINE["fields"] = field_diffs(b0, b1)
    r3 = run([a.bin, "validate", "--db", bdb], cwd=a.valcwd)
    BASELINE["validate"] = validate_lines(r3[1] + "\n" + r3[2])
    base_info = {"db_to_md_rc": r1[0], "md_to_db_rc": r2[0], "md_to_db_err": r2[2][-400:],
                 "lost": sorted(map(list, set(b0) - set(b1))), "new": sorted(map(list, set(b1) - set(b0))),
                 "field_drift": sorted(BASELINE["fields"]),
                 "field_drift_values": {d: [b0[[k for k in b0 if k[0] == d.split(".")[0]][0]]["fields"][d.split(".", 1)[1]],
                                            b1[[k for k in b1 if k[0] == d.split(".")[0]][0]]["fields"][d.split(".", 1)[1]]]
                                        for d in BASELINE["fields"]},
                 "validate_rc": r3[0], "validate_lines": sorted(BASELINE["validate"])}
    with open(os.path.join(a.out, "baseline.json"), "w", encoding="utf-8") as f:
        json.dump(base_info, f, indent=1, ensure_ascii=False, sort_keys=True)
    for fn in ("db.sqlite", "db_rt.sqlite"):
        os.remove(os.path.join(bd, fn))
    results = []
    # Controls first (section 11.4.273): the instrument must SEE a known loss
    # (positive, control binary) and must NOT report one on a plain item (negative).
    ctl = [
        ("CTL_pos_replaced", a.control_bin, {"block": "CTL", "name": "CTL_pos_replaced", "id": "GS-972",
                                            "prefix": None, "title": "[ABC-9] first", "desc": D0, "ops": ["add"]},
         "RT_REPLACED"),
        ("CTL_pos_phantom", a.control_bin, {"block": "CTL", "name": "CTL_pos_phantom", "id": "CON-9810",
                                           "prefix": None, "title": "a\n## CON-9811 — injected", "desc": D0,
                                           "ops": ["add"]}, "RT_PHANTOM"),
        ("CTL_pos_field", a.control_bin, {"block": "CTL", "name": "CTL_pos_field", "id": "GZ974", "prefix": None,
                                         "title": "thing — `Fixed (→ Fixed.md)` x", "desc": D0,
                                         "ops": ["add"]}, "RT_FIELD"),
        ("CTL_neg_plain", a.bin, {"block": "CTL", "name": "CTL_neg_plain", "id": "CON-9999", "prefix": None,
                                 "title": "plain control title words", "desc": D0, "ops": ["add"]}, "RT_OK"),
    ]
    ctl_ok = True
    for name, b, case, want in ctl:
        r, log = run_case(b, a.db, a.out, a.valcwd, case)
        r["control_expected"] = want
        r["control_ok"] = r["verdict"] == want
        ctl_ok &= r["control_ok"]
        results.append(r)
        with open(os.path.join(a.out, case["name"], "log.json"), "w", encoding="utf-8") as f:
            json.dump(log, f, indent=1, ensure_ascii=False)
    for case in cases:
        r, log = run_case(a.bin, a.db, a.out, a.valcwd, case)
        results.append(r)
        with open(os.path.join(a.out, case["name"], "log.json"), "w", encoding="utf-8") as f:
            json.dump(log, f, indent=1, ensure_ascii=False)
        # Keep the evidence small: drop the database copies of a case.
        for fn in ("db.sqlite", "db_rt.sqlite"):
            p = os.path.join(a.out, case["name"], fn)
            if os.path.isfile(p):
                os.remove(p)
    cols = ["name", "block", "verdict", "at", "id", "validate_rc", "desc_changed", "body_same", "detail"]
    with open(os.path.join(a.out, "table.tsv"), "w", encoding="utf-8") as f:
        f.write("\t".join(cols) + "\tcontrol\n")
        for r in results:
            c = r.get("control_ok")
            f.write("\t".join(str(r.get(k, "")).replace("\t", " ").replace("\n", " ") for k in cols))
            f.write("\t" + ("" if c is None else ("CONTROL-OK" if c else "CONTROL-FAIL(%s)" % r["control_expected"])) + "\n")
    summary = {}
    for r in results:
        if r["block"] == "CTL":
            continue
        summary[r["verdict"]] = summary.get(r["verdict"], 0) + 1
    with open(os.path.join(a.out, "summary.json"), "w", encoding="utf-8") as f:
        json.dump({"cases": len(results) - len(ctl), "verdicts": summary, "controls_ok": ctl_ok},
                  f, indent=1, sort_keys=True)
    print(json.dumps({"cases": len(results) - len(ctl), "verdicts": summary, "controls_ok": ctl_ok},
                     sort_keys=True))
    return 0 if ctl_ok else 3


if __name__ == "__main__":
    sys.exit(main())
