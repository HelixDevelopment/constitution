#!/usr/bin/env python3
"""remint_ids.py -- move the items a vehicle minted to the next free id range of a target tracker.

Documentation (section 11.4.18): docs/guides/remint_ids_guide.md.

WHY   Two vehicles that branch from one base both mint ids from the base's maximum, so their ids
      collide when the second lands (round-2 review R2-7: this vehicle's CON-299..CON-342 against
      fix227's CON-300..CON-311). The engine has no rename command and the binary database cannot
      be merged, so this tool (a) computes the mapping, (b) rewrites every text that names an own
      id, and (c) replays the own items onto the target database through the workable-items engine.
      It never opens a tracker database for writing itself (section 11.4.93: the engine is the only
      writer); the replay runs the engine.

USAGE
  remint_ids.py plan    --vehicle-db V --base-db B --target-db T [--prefix CON] [--out map.tsv]
      own ids = the ids with the prefix in V and not in B; they keep their order and get
      max(T)+1, max(T)+2, ...  Read-only. Refuses (exit 1) when a new id already exists in T, or in
      V as an item that is not itself being moved.
  remint_ids.py rewrite --map map.tsv [--write] [--foreign ID[,ID]] FILE...
      Rewrites ids and ranges `P-a..P-b` in text files. Dry run by default: prints, per file, the
      number of replaced tokens; --write writes the files in place. A line that starts with
      "Foreign ids" is left alone, and the ids it declares are not rewritten anywhere in that file
      (they belong to another tracker). A range is rewritten only when every id in it is mapped and
      the new ids are again a range; a range that is partly mapped, or whose new ids are not
      contiguous, is an error (exit 1), never a guess. Refuses binary files and .db files.
  remint_ids.py replay  --map map.tsv --vehicle-db V [--apply --engine BIN --db TARGET]
      Prints the engine command plan (one JSON argv per line, the database path as "{DB}") that
      re-creates every own item under its new id: add (type, severity, title, description, the
      handles, every reproduction and investigation field), then the closure, Obsolete-Details and
      reopen steps its status needs. With --apply it runs the plan against TARGET (a copy: the
      caller lands the copy). The working directory must be the target repository root, with the
      rewritten text files in place, because the engine resolves evidence paths from there.
  remint_ids.py verify  --map map.tsv --vehicle-db V --db R [--require-segments]
      Checks that every own item exists in R under its new id with the rewritten text and the same
      type, severity, status, location, handles and state fields; that its obsolete_details row (if
      any) matches with the superseding id rewritten; that it has an Opened history row; and with
      --require-segments that doc_segments names it (after an export). Read-only.

NOT CARRIED  item_history rows of the vehicle (the engine writes a new history on replay; the old
      rows stay in the vehicle bundle), created_at (the engine stamps the replay time), and
      reproduction/investigation updated_at (replayed with --states-updated-at from the source row).

EXIT  0 done (or no difference); 1 a refusal or a verify mismatch; 2 usage error; 3 BLIND (a
      database or a file that cannot be read, an empty own set, a mapping that does not parse).
EVIDENCE CLASS  gate-logic (section 11.4.289): the tests drive the real engine on fixture copies.
"""
import argparse
import json
import os
import re
import sqlite3
import subprocess
import sys

TEXT_COLUMNS = [
    "title", "description", "reproduction_evidence", "reproduction_red_cmd", "reproduction_green_cmd",
    "reproduction_env", "reproduction_signature", "reproduction_blocker", "investigation_root_cause",
    "investigation_evidence",
]
STATE_FLAGS = [
    ("reproduction_state", "--reproduction-state"), ("reproduction_surface", "--reproduction-surface"),
    ("reproduction_evidence", "--reproduction-evidence"), ("reproduction_red_cmd", "--reproduction-red-cmd"),
    ("reproduction_green_cmd", "--reproduction-green-cmd"), ("reproduction_env", "--reproduction-env"),
    ("reproduction_signature", "--reproduction-signature"), ("reproduction_blocker", "--reproduction-blocker"),
    ("investigation_state", "--investigation-state"), ("investigation_root_cause", "--investigation-root-cause"),
    ("investigation_evidence", "--investigation-evidence"),
]
CLOSE_STATUS = {"Fixed": "fixed", "Implemented": "implemented", "Completed": "completed", "Obsolete": "obsolete"}
FOREIGN_LINE = re.compile(r"^Foreign ids\b[^:]*:(.*)$", re.M)


class Refusal(Exception):
    pass


class Blind(Exception):
    pass


def num(iid):
    return int(iid.rsplit("-", 1)[1])


def ro(path):
    if not os.path.isfile(path):
        raise Blind("database not found: %s" % path)
    try:
        c = sqlite3.connect("file:%s?mode=ro" % path, uri=True)
        c.row_factory = sqlite3.Row
        c.execute("select count(*) from items").fetchone()
        return c
    except sqlite3.Error as e:
        raise Blind("database unreadable: %s: %s" % (path, e))


def ids_of(c, prefix):
    rx = re.compile(re.escape(prefix) + r"-\d+")
    return {r[0] for r in c.execute("select atm_id from items") if rx.fullmatch(r[0])}


def make_plan(vehicle, base, target, prefix):
    v, b, t = (ids_of(ro(p), prefix) for p in (vehicle, base, target))
    own = sorted(v - b, key=num)
    if not own:
        raise Blind("no own id: every %s id of the vehicle is in the base" % prefix)
    if not t:
        raise Blind("the target holds no %s id: the next free number cannot be known" % prefix)
    width = len(own[0].rsplit("-", 1)[1])
    start = max(num(i) for i in t) + 1
    mapping = [(o, "%s-%0*d" % (prefix, width, start + k)) for k, o in enumerate(own)]
    stay = v - set(own)
    for old, new in mapping:
        if new in t:
            raise Refusal("new id %s already exists in the target" % new)
        if new in stay:
            raise Refusal("new id %s is an item of the vehicle that is not moved" % new)
    return mapping


def read_map(path):
    try:
        lines = open(path, encoding="utf-8").read().splitlines()
    except OSError as e:
        raise Blind("map unreadable: %s" % e)
    if not lines or lines[0] != "old\tnew":
        raise Blind("map has no `old<TAB>new` header: %s" % path)
    m = {}
    for n, line in enumerate(lines[1:], 2):
        f = line.split("\t")
        if len(f) != 2 or not re.fullmatch(r"[A-Z]+-\d+", f[0]) or not re.fullmatch(r"[A-Z]+-\d+", f[1]):
            raise Blind("map line %d does not parse: %r" % (n, line))
        if f[0] in m:
            raise Blind("map names %s twice" % f[0])
        m[f[0]] = f[1]
    if not m:
        raise Blind("map is empty: %s" % path)
    if len(set(m.values())) != len(m):
        raise Blind("map gives two old ids one new id")
    prefixes = {k.rsplit("-", 1)[0] for k in m} | {v.rsplit("-", 1)[0] for v in m.values()}
    if len(prefixes) != 1:
        raise Blind("map mixes prefixes: %s" % ",".join(sorted(prefixes)))
    return m, prefixes.pop()


def rewrite_text(text, m, prefix, extra_foreign=()):
    """Returns (new text, replaced count). Raises Refusal on a range it must not guess."""
    if not text:
        return text, 0
    p = re.escape(prefix)
    tok = re.compile(r"(?<![\w-])" + p + r"-(\d+)\b(?!-)")
    rng = re.compile(r"(?<![\w-])" + p + r"-(\d+)\.\." + p + r"-(\d+)\b(?!-)")
    foreign = set(extra_foreign)
    for fl in FOREIGN_LINE.finditer(text):
        foreign |= {mm.group(0) for mm in tok.finditer(fl.group(1))}
        for r in rng.finditer(fl.group(1)):
            w = len(r.group(1))
            foreign |= {"%s-%0*d" % (prefix, w, n) for n in range(int(r.group(1)), int(r.group(2)) + 1)}
    count = 0
    out = []
    for line in text.split("\n"):
        if FOREIGN_LINE.match(line):
            out.append(line)
            continue

        def range_sub(r):
            nonlocal count
            w = len(r.group(1))
            ids = ["%s-%0*d" % (prefix, w, n) for n in range(int(r.group(1)), int(r.group(2)) + 1)]
            ids = [i for i in ids if i not in foreign]
            hit = [i for i in ids if i in m]
            if not hit:
                return r.group(0)
            if len(hit) != len(ids):
                raise Refusal("range %s is partly mapped (%d of %d ids)" % (r.group(0), len(hit), len(ids)))
            new = [num(m[i]) for i in ids]
            if new != list(range(new[0], new[0] + len(new))):
                raise Refusal("range %s maps to ids that are not contiguous" % r.group(0))
            count += 1
            return "%s..%s" % (m[ids[0]], m[ids[-1]])

        def tok_sub(t):
            nonlocal count
            iid = t.group(0)
            if iid in m and iid not in foreign:
                count += 1
                return m[iid]
            return iid

        # ranges first, then the tokens outside the rewritten ranges (one pass each, no chaining)
        parts, last = [], 0
        for r in rng.finditer(line):
            parts.append(tok.sub(tok_sub, line[last:r.start()]))
            parts.append(range_sub(r))
            last = r.end()
        parts.append(tok.sub(tok_sub, line[last:]))
        out.append("".join(parts))
    return "\n".join(out), count


def cmd_rewrite(a):
    m, prefix = read_map(a.map)
    extra = {x.strip() for f in a.foreign for x in f.split(",") if x.strip()}
    total = 0
    results = []
    for f in a.files:
        if f.endswith(".db") or f.endswith(".bundle"):
            raise Refusal("refusing a database or bundle file: %s" % f)
        try:
            raw = open(f, "rb").read()
        except OSError as e:
            raise Blind("file unreadable: %s" % e)
        if b"\0" in raw:
            raise Refusal("refusing a binary file: %s" % f)
        text = raw.decode("utf-8")
        new, n = rewrite_text(text, m, prefix, extra)
        results.append((f, n, new, text))
        total += n
    for f, n, new, text in results:  # every file is checked before the first one is written
        print("%s\t%d" % (f, n))
        if a.write and new != text:
            with open(f, "w", encoding="utf-8") as h:
                h.write(new)
    print("RESULT: %s files=%d replaced=%d" % ("WRITTEN" if a.write else "DRY-RUN", len(results), total))
    return 0


def own_rows(c, m):
    rows = []
    for old in sorted(m, key=num):
        r = c.execute("select * from items where atm_id=? order by current_location='Fixed'", (old,)).fetchall()
        if len(r) != 1:
            raise Refusal("%s has %d rows in the vehicle database (one expected)" % (old, len(r)))
        rows.append(r[0])
    return rows


def replay_plan(vehicle, m, prefix):
    c = ro(vehicle)
    plan = []
    for r in own_rows(c, m):
        old, new = r["atm_id"], m[r["atm_id"]]
        rw = {k: rewrite_text(r[k] or "", m, prefix)[0] for k in TEXT_COLUMNS}
        add = ["add", r["type"], r["severity"], "--db", "{DB}", "--id", new, "--title", rw["title"],
               "--description", rw["description"]]
        if r["created_by"]:
            add += ["--created-by", r["created_by"]]
        if r["assigned_to"]:
            add += ["--assigned-to", r["assigned_to"]]
        states = []
        for col, flag in STATE_FLAGS:
            val = rw[col] if col in rw else r[col]
            if val and val != "UNSET":
                states += [flag, val]
        if states:
            who = r["reproduction_updated_by"] or r["investigation_updated_by"] or "remint_ids.py"
            at = r["reproduction_updated_at"] or r["investigation_updated_at"]
            states += ["--states-updated-by", who] + (["--states-updated-at", at] if at else [])
        plan.append({"id": new, "from": old, "argv": add + states})
        od = c.execute("select * from obsolete_details where atm_id=?", (old,)).fetchone()
        hist = c.execute("select * from item_history where atm_id=? order by id", (old,)).fetchall()
        status = r["status"]
        base = status.split(" ")[0]
        closed = [h for h in hist if h["event_type"] in ("Fixed", "Implemented", "Completed", "Obsolete") and h["evidence_path"]]
        if base in CLOSE_STATUS or od is not None:
            if not closed:
                raise Refusal("%s: no closure history row with evidence to replay" % old)
            ev = rewrite_text(closed[-1]["evidence_path"], m, prefix)[0]
            st = CLOSE_STATUS.get(base, "obsolete")
            plan.append({"id": new, "from": old, "argv": ["close", new, "--db", "{DB}", "--status", st, "--evidence", ev]})
        if od is not None:
            sup = rewrite_text(od["superseding_item"] or "none", m, prefix)[0]
            plan.append({"id": new, "from": old, "argv": [
                "obsolete-details", new, "--db", "{DB}", "--since", od["since"], "--reason", od["reason"],
                "--superseding", sup, "--evidence", rewrite_text(od["triple_check_evidence"], m, prefix)[0]]})
        if status == "Reopened":
            ro_rows = [h for h in hist if h["event_type"] == "Reopened"]
            if not ro_rows:
                raise Refusal("%s is Reopened with no Reopened history row" % old)
            h = ro_rows[-1]
            plan.append({"id": new, "from": old, "argv": [
                "reopen", "--id", new, "--db", "{DB}", "--why", h["reason"], "--who", h["by"] or "AI",
                "--when", h["on_date"], "--incident", rewrite_text(h["evidence_path"] or "", m, prefix)[0]]})
        elif base not in CLOSE_STATUS and status != "Queued":
            raise Refusal("%s: status %r has no replay rule" % (old, status))
    return plan


def cmd_replay(a):
    m, prefix = read_map(a.map)
    plan = replay_plan(a.vehicle_db, m, prefix)
    if not a.apply:
        for p in plan:
            print(json.dumps(p["argv"], ensure_ascii=False))
        print("RESULT: DRY-RUN steps=%d items=%d" % (len(plan), len(m)))
        return 0
    if not a.engine or not a.db:
        print("remint_ids: --apply needs --engine and --db", file=sys.stderr)
        return 2
    held = ids_of(ro(a.db), prefix) & set(m.values())
    if held:
        raise Refusal("the target already holds new id(s) %s: replay only once, onto the database the map was planned against" % ",".join(sorted(held, key=num)[:5]))
    for k, p in enumerate(plan, 1):
        argv = [a.engine] + [x.replace("{DB}", a.db) for x in p["argv"]]
        r = subprocess.run(argv, capture_output=True, text=True)
        print("step %d %s %s rc=%d" % (k, p["argv"][0], p["id"], r.returncode))
        if r.returncode != 0:
            sys.stderr.write(r.stdout[-400:] + r.stderr[-400:])
            print("RESULT: STOPPED at step %d of %d (the target copy is partly replayed: discard it)" % (k, len(plan)))
            return 1
    print("RESULT: APPLIED steps=%d items=%d" % (len(plan), len(m)))
    return 0


def cmd_verify(a):
    m, prefix = read_map(a.map)
    v, t = ro(a.vehicle_db), ro(a.db)
    bad = []
    for r in own_rows(v, m):
        old, new = r["atm_id"], m[r["atm_id"]]
        g = t.execute("select * from items where atm_id=?", (new,)).fetchall()
        if len(g) != 1:
            bad.append("%s: %d rows in the result" % (new, len(g)))
            continue
        g = g[0]
        for k in TEXT_COLUMNS:
            want = rewrite_text(r[k] or "", m, prefix)[0]
            if (g[k] or "") != want:
                bad.append("%s: %s differs from the rewritten %s" % (new, k, old))
        for k in ("type", "severity", "status", "current_location", "created_by", "assigned_to",
                  "reproduction_state", "reproduction_surface", "investigation_state"):
            if (g[k] or "") != (r[k] or "") and not (k.endswith("_state") and (g[k] or "UNSET") == (r[k] or "UNSET")):
                bad.append("%s: %s %r, vehicle %r" % (new, k, g[k], r[k]))
        vo = v.execute("select reason, superseding_item, since from obsolete_details where atm_id=?", (old,)).fetchone()
        go = t.execute("select reason, superseding_item, since from obsolete_details where atm_id=?", (new,)).fetchone()
        if (vo is None) != (go is None):
            bad.append("%s: obsolete_details row present in one database only" % new)
        elif vo is not None:
            want = (vo[0], rewrite_text(vo[1] or "", m, prefix)[0], vo[2])
            if tuple(go) != want:
                bad.append("%s: obsolete_details %r, want %r" % (new, tuple(go), want))
        if not t.execute("select 1 from item_history where atm_id=? and event_type='Opened'", (new,)).fetchone():
            bad.append("%s: no Opened history row" % new)
        if a.require_segments and not t.execute("select 1 from doc_segments where atm_id=?", (new,)).fetchone():
            bad.append("%s: not in doc_segments (export not run?)" % new)
    for b in bad:
        print("MISMATCH " + b)
    print("RESULT: %s items=%d mismatches=%d" % ("PASS" if not bad else "FAIL", len(m), len(bad)))
    return 1 if bad else 0


def cmd_plan(a):
    mapping = make_plan(a.vehicle_db, a.base_db, a.target_db, a.prefix)
    text = "old\tnew\n" + "".join("%s\t%s\n" % x for x in mapping)
    if a.out:
        with open(a.out, "w", encoding="utf-8") as h:
            h.write(text)
    sys.stdout.write(text)
    print("RESULT: PLAN own=%d first=%s last=%s" % (len(mapping), mapping[0][1], mapping[-1][1]))
    return 0


def main(argv):
    ap = argparse.ArgumentParser(prog="remint_ids.py")
    sub = ap.add_subparsers(dest="cmd")
    p = sub.add_parser("plan")
    p.add_argument("--vehicle-db", required=True)
    p.add_argument("--base-db", required=True)
    p.add_argument("--target-db", required=True)
    p.add_argument("--prefix", default="CON")
    p.add_argument("--out")
    p = sub.add_parser("rewrite")
    p.add_argument("--map", required=True)
    p.add_argument("--write", action="store_true")
    p.add_argument("--foreign", action="append", default=[])
    p.add_argument("files", nargs="+")
    p = sub.add_parser("replay")
    p.add_argument("--map", required=True)
    p.add_argument("--vehicle-db", required=True)
    p.add_argument("--apply", action="store_true")
    p.add_argument("--engine")
    p.add_argument("--db")
    p = sub.add_parser("verify")
    p.add_argument("--map", required=True)
    p.add_argument("--vehicle-db", required=True)
    p.add_argument("--db", required=True)
    p.add_argument("--require-segments", action="store_true")
    try:
        a = ap.parse_args(argv)
    except SystemExit as e:
        return 2 if e.code else 0
    if not a.cmd:
        ap.print_usage(sys.stderr)
        return 2
    try:
        return {"plan": cmd_plan, "rewrite": cmd_rewrite, "replay": cmd_replay, "verify": cmd_verify}[a.cmd](a)
    except Refusal as e:
        print("REFUSED: %s" % e, file=sys.stderr)
        return 1
    except Blind as e:
        print("BLIND: %s" % e, file=sys.stderr)
        return 3


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
