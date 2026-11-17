#!/usr/bin/env python3
"""tests/release/pvl_grid.py -- the case grid of scripts/validation/check_provisional_verification_lines.py
(CON-423 r5, the closed grammar of docs/qa/rehearsal_v73_4_fix/r5/class_inventory.md).

Usage: python3 -I tests/release/pvl_grid.py CHECKER WORKDIR
Every case is one verification line built on tests/release/pvl_fixture.py (one field replaced, or the whole line) with
OK or REJ expected. A REJ case also names the part of the reason the refusal must carry (the field for a field case),
so a checker that refuses for the wrong reason is caught. Each case is checked twice: through check_line() against the
fixture context, and through the command line (one database item per case, created_at set, --root, --today) so main(),
the URI, the created date and the registry path are exercised. The second oracle tests/release/pvl_oracle.py must agree
with every case. Output: GRID-PASS / GRID-FAIL <id> lines, then
`GRID cases=N refused=R accepted=A mismatches=M cli_mismatches=C oracle_mismatches=O`. Exit 0 when M, C and O are 0,
1 otherwise, 2 when the checker cannot be loaded or the command line run gives no CHECKED line (a blind grid).
"""
import importlib.util
import os
import re
import sqlite3
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import pvl_fixture as F  # noqa: E402
import pvl_oracle  # noqa: E402

CASES = []  # (id, line, expect, reason-part)


def ok(cid, ln):
    CASES.append((cid, ln, "OK", ""))


def rej(cid, ln, why):
    CASES.append((cid, ln, "REJ", why))


def f_ok(field, v, cid=None):
    kw = {field: v}
    if field == "job":  # the checks of a job case name the job's first script
        kw["checks"] = re.search(r"tests/[a-z]+\.(?:sh|py)", v).group(0) + " pass=1"
    ok(cid or "%s:ok:%s" % (field, v), F.line(**kw))


def f_rej(field, v, cid=None):
    rej(cid or "%s:rej:%s" % (field, ascii(v)[1:-1][:60]), F.line(**{field: v}), "field '%s'" % field)


# ---- job
for v in ["bash tests/t.sh -k case12; python3 -I tests/p.py", "bash tests/t.sh", "bash tests/t.sh --fast",
          "bash tests/t.sh -k case12 --fast", "MODE=on bash tests/t.sh", "MODE=on STRICT=1 bash tests/t.sh",
          "python3 -I tests/p.py --root .", "python3 tests/p.py 3", "sh tests/t.sh case12",
          "bash tests/t.sh --out=docs/Issues.md", "bash tests/t.sh --level=3", "bash tests/t.sh tests",
          "PVL_SEED=7 python3 -I tests/p.py --seed=quick", "bash tests/t.sh -k"]:
    f_ok("job", v)
ok("job:ok:tracker CON-777 (In progress)", F.line(job="CON-777", checks="CON-777 pass=1"))
ok("job:ok:tracker CON-776 (Queued)", F.line(job="CON-776", checks="CON-776 pass=1"))
ok("job:ok:tracker CON-775 (Operator-blocked)", F.line(job="CON-775", checks="CON-775 pass=1"))
for v in ["", "TBD", "TO DO", "none yet", "pending scheduling", "re-run bash tests/t.sh", "on main, run bash tests/t.sh",
          "bash tests/absent.sh", "bash tests/", "bash tests", "bash README.md", "bash docs/Issues.md",
          "python3 tests/t.sh", "bash tests/p.py", "bash tests/t.sh --nope", "bash tests/t.sh case99",
          "bash tests/t.sh nodigit", "go test ./...", "make -", "git -x", "bash ../x.sh", "bash /etc/passwd",
          "bash tests/esc.sh", "bash tests/t.sh  --fast", "bash tests/t.sh;python3 tests/p.py", "bash tests/t.sh;",
          "NOPE=1 bash tests/t.sh", "MODE=off bash tests/t.sh", "bash tests/t.sh x/y", "bash tests/t.sh (nightly)",
          "ｂash tests/t.sh", "bash tests/t.sh​", "bash tests/t.sh --out=nowhere/x", "bash ./tests/t.sh",
          "bash tests/./t.sh", "bash tests//t.sh", "JOB-42", "JOB-42 nightly", "CON-778", "CON-779", "CON-999",
          "CON-774", "bash", "python3 -I", "bash tests/t.sh 01", "bash tests/t.sh -K",
          "BASH tests/t.sh", "bash\ttests/t.sh", " bash tests/t.sh", "bash tests/t.sh ", "bash tests/t.sh --fast=",
          "bash tests/t.sh fast", "bash tests/t.sh --Fast", "mode=on bash tests/t.sh", "bash tests/t.sh $HOME",
          "bash tests/t.sh `id`", "bash tests/t.sh | tee x", "bash tests/t.sh && x", "bash tests/T.sh"]:
    f_rej("job", v)
# r6: the refusal names its reason (RV05: the empty-word check), and a symlink to the root is refused as a path (RV09)
rej("job:rej:empty-word-reason", F.line(job="bash tests/t.sh  --fast"), "holds an empty word")
rej("job:rej:rootlink-path", F.line(job="bash tests/t.sh tests/rootlink"), "field 'job'")
# ---- checks (the base job names tests/t.sh, case12 and tests/p.py)
for v in ["tests/t.sh pass=3", "tests/t.sh pass=3 fail=0 verdict=PASS", "case12 pass=1",
          "tests/t.sh pass=3; tests/p.py killed=4 survived=0", "tests/p.py rc=0 skip=1",
          "tests/t.sh fail=1 verdict=FAIL", "tests/t.sh skip=2 verdict=SKIP", "tests/t.sh pass=0 rc=255 verdict=BLIND"]:
    f_ok("checks", v)
for v in ["3 passed", "tests/t.sh", "tests/t.sh rc=0", "tests/t.sh verdict=PASS", "tests/t.sh pass=3 pass=4",
          "tests/t.sh pass=x", "tests/t.sh rc=256 pass=1", "tests/t.sh verdict=OK pass=1", "tests/x.sh pass=1",
          "none of the mutants survives", "TBD", "tests/t.sh pass=-1", "tests/t.sh pass=01", "tests/t.sh  pass=1",
          "tests/t.sh pass=1;tests/p.py pass=1", "tests/t.sh pass=1;", "case7 pass=1", "tests/t.sh passed=3",
          "tests/t.sh pass=1 (later)", "every suite passes with 0 failed", "rc 0 and VERDICT: PASS",
          "tests/t.sh Pass=1", "tests/t.sh pass=1 verdict=pass", "tests/t.sh pass=99999999999", "тests/t.sh pass=1"]:
    f_rej("checks", v)
# ---- layer
for v in ["host-only", "gate-logic plus host-only", "runtime plus artifact plus source", "user-visible",
          "live-target plus runtime"]:
    f_ok("layer", v)
for v in ["runtime on the host", "host-only (tests)", "gate-logic plus gate-logic", "runtimeish", "ѕource",
          "Runtime", "host-only, runtime", "host-only plus", "runtime clean target", "TBD", "host-only  plus runtime"]:
    f_rej("layer", v)
# ---- target
for v in ["host", "host, repo checkout", "scratch clone", "remote github", "board T1", "device SER42, host",
          "container pvl-c1", "vm vm.1", "runner r:7", "remote github, remote gitlab"]:
    f_ok("target", v)
for v in ["host checkout", "remote nowhere", "board T9", "board serial ABC123", "host, host", "host or whichever",
          "TBD", "container c1", "board", "Host", "host,repo checkout", "remote GitHub", "host (pending)",
          "board T1 (Orange Pi)", "remote ../x"]:
    f_rej("target", v)
# ---- artifact
for v in ["main", "main@abc1234", "commit abc1234", "merge 0123456789abcdef", "tag v73.4", "main, tag v1",
          "commit " + "a" * 64]:
    f_ok("artifact", v)
for v in ["build", "commit abc123", "commit ABC1234", "tag release", "sha256 of the image", "main, main",
          "commit abc1234 (the fix)", "main containing 3b958793", "commit " + "a" * 65, "tag", "Main", "image",
          "commit 0123456g"]:
    f_rej("artifact", v)
# ---- due (created 2026-11-01, today 2026-11-16, window 60 days => last 2027-01-15)
for v in ["2026-11-20", "2026-11-01", "2027-01-15", "2026-11-20T10:00Z", "2026-11-20T10:00:00+01:00",
          "2026-11-20T23:59:59-05:30", "2026-11-16"]:
    f_ok("due", v)
for v in ["2027-01-16", "2026-10-31", "2099-12-31", "2000-01-01", "2026-02-30", "2026-11-20T25:00",
          "2026-11-20T10:00:60", "2026-11-20T10:00+25:00", "2026-1-1", "TBD", "2026-11-20 (approx)",
          "２０２６-11-20", "2026-11-20x", "2026-11-20T10", "0000-00-00", "2026-11-20.",
          "2026-11-20T10:00z", "2026-11-20T24:00", "2026-11-20T10:60", "2026-11-20T10:00+01:60",
          "2026-11-20T10:00-24:00", "2026-11-20T23:59:60Z"]:
    f_rej("due", v)
# ---- whole line
G = F.line()
ok("line:ok:base", G)
ok("line:ok:em dash separators", G.replace(" -- ", " — "))
ok("line:ok:section suffix", G.replace("provisional --", "provisional (section 11.4.290) --"))
ok("line:ok:colon-less form", re.sub(r"(job|checks|layer|target|artifact|due): ", r"\1 ", G))
ok("line:ok:note", F.line(note="scheduled by the operator; see CON-777"))
ok("line:ok:note with separators inside", F.line(note="a -- b -- c"))
rej("line:rej:note non-ASCII", F.line(note="prüfen"), "field 'note'")
rej("line:rej:note punctuation only", F.line(note="-"), "field 'note'")
rej("line:rej:note empty", F.line(note=""), "field 'note'")
rej("line:rej:trailing text after due", G + ". Not VERIFIED-DONE", "field 'due'")
rej("line:rej:a part after due that is not a note", G + " -- remark: x", "a part is not")
rej("line:rej:a named part after due that is not a note", G + " -- job: x", "not a note")
rej("line:rej:missing checks", G.replace(" -- checks: tests/t.sh pass=3; tests/p.py pass=1", ""), "not job, checks")
rej("line:rej:fields out of order",
    F.line().replace("layer: host-only -- target: host", "target: host -- layer: host-only"), "not job, checks")
rej("line:rej:too long", F.line(note="x" * 4100), "longer than 4096")
rej("line:rej:separator without spaces", G.replace(" -- ", "--", 1), "text between")
rej("line:rej:en dash separator", G.replace(" -- ", " – "), "")
rej("line:rej:text before the first field", G.replace("provisional --", "provisional (x) --"), "text between")
rej("line:rej:section suffix misspelt", G.replace("provisional --", "provisional (section 11.4.29) --"), "text between")
rej("line:rej:no fields", "**Verification:** provisional", "not job, checks")
rej("line:rej:a field twice", G.replace("-- due:", "-- job: bash tests/t.sh -- due:"), "not job, checks")
rej("line:rej:jobs colon glued", G.replace("job: ", "job:"), "a part is not")
rej("line:rej:upper-case field name", G.replace("job: ", "Job: "), "a part is not")
rej("line:rej:NBSP separator", G.replace(" -- ", " -- ", 1), "")
# ---- the target registry is needed for device-class targets (an empty registry in its own context)
NOREG = [("noreg:rej:board without a registry", F.line(target="board T1"), "REJ", "no target registry"),
         ("noreg:ok:host without a registry", F.line(target="host"), "OK", "")]


def load(path):
    spec = importlib.util.spec_from_file_location("pvl_checker", path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def main(argv):
    if len(argv) != 3:
        sys.stderr.write("usage: pvl_grid.py CHECKER WORKDIR\n")
        return 2
    checker, work = argv[1], argv[2]
    try:
        m = load(checker)
    except Exception as exc:  # noqa: BLE001
        print("GRID-BLIND cannot load the checker: %s" % exc)
        return 2
    os.makedirs(work, exist_ok=True)
    fx = F.make_root(work)
    ctx = F.checker_ctx(m, fx)
    mism = refused = 0
    api = {}
    for cid, ln, want, why in CASES:
        got = m.check_line(ln, ctx)
        api[cid] = got
        refused += got is not None
        good = (got is None) if want == "OK" else (got is not None and why in got)
        if good:
            print("GRID-PASS %s" % cid)
        else:
            mism += 1
            print("GRID-FAIL %s: want %s%s, got %s" % (cid, want, " (%s)" % why if why else "", got))
    for cid, ln, want, why in NOREG:
        nctx = m.Context(fx["root"], fx["items"], fx["item_id"], fx["created"], fx["today"], fx["window"], None)
        got = m.check_line(ln, nctx)
        good = (got is None) if want == "OK" else (got is not None and why in got)
        print("GRID-%s %s%s" % ("PASS" if good else "FAIL", cid, "" if good else ": got %s" % got))
        mism += not good
    om = 0
    for cid, ln, _, _ in CASES:
        if pvl_oracle.accepts(ln, fx) != (api[cid] is None):
            om += 1
            print("ORACLE-FAIL %s: oracle %s, checker %s" % (cid, pvl_oracle.accepts(ln, fx), api[cid]))
    # the command line: one item per case, beside the fixture items
    db = os.path.join(work, "grid.db")
    if os.path.exists(db):
        os.unlink(db)
    con = sqlite3.connect(db)
    con.execute("create table items (atm_id text primary key, status text, body_md text, created_at text)")
    for k, st in fx["items"].items():
        if k != fx["item_id"]:
            con.execute("insert into items values (?, ?, ?, ?)", (k, st, "## [%s] fixture" % k, "2026-11-01T00:00:00Z"))
    ids = {}
    for n, (cid, ln, _, _) in enumerate(CASES):
        aid = "GRD-%d" % (n + 1)
        ids[aid] = cid
        con.execute("insert into items values (?, ?, ?, ?)",
                    (aid, "Ready for testing", "## [%s] case\n\n%s\n" % (aid, ln), "2026-11-01T09:30:00Z"))
    con.commit()
    con.close()
    p = subprocess.run([sys.executable, "-I", os.path.abspath(checker), "--root", fx["root"], "--today", "2026-11-16", db],
                       capture_output=True, text=True, cwd=work)
    if not re.search(r"^CHECKED items=\d+ ", p.stdout, re.M):
        print("GRID-BLIND the command line run gave no CHECKED line (rc %d): %s" % (p.returncode, p.stdout[-300:]))
        return 2
    failed = set(re.findall(r"^FAIL (GRD-\d+) ", p.stdout, re.M))
    cm = 0
    for aid, cid in ids.items():
        if (aid in failed) != (api[cid] is not None):
            cm += 1
            print("CLI-FAIL %s (%s): command line %s, check_line %s" % (aid, cid, aid in failed, api[cid]))
    n_all = len(CASES) + len(NOREG)
    print("GRID cases=%d refused=%d accepted=%d mismatches=%d cli_mismatches=%d oracle_mismatches=%d" % (
        n_all, refused + 1, n_all - refused - 1, mism, cm, om))
    return 0 if mism == cm == om == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
