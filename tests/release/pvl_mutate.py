#!/usr/bin/env python3
"""tests/release/pvl_mutate.py -- paired mutants of the verification-line checker and its harnesses (CON-423 r5).

Usage: python3 -I tests/release/pvl_mutate.py REPO WORKDIR [ID ...]
Mutants: the own mutants of tests/release/pvl_mutants.tsv (ID<TAB>FILE<TAB>OLD<TAB>NEW<TAB>WHY, OLD and NEW as Python
string literals) and every reviewer mutant tests/release/pvl_reviewer.py lists as APPLIES on a file of this suite (the
checker and tests/release/pvl_*.py; the release-tooling mutants run in their own suites). For each mutant a sandbox under
WORKDIR gets a copy of the checker, the pvl_*.py harnesses and scripts/release/render_release_entry.py; OLD must occur
exactly once (else NOT-APPLIED, a FAIL); then the kill harnesses run in order until one exits non-zero:
  api       the command line on a fixture database: golden good PASS, every golden-bad body refused with its id, the
            two-reading body refused, every look-alike of the render's map named in the refusal reason; round 6:
            --root through a symlink prints the real ROOT, typed values and status spellings refused by name, hour 24
            refused, a lone CR hides a fenced line, a non-UTF-8 registry is BLIND, a closed WAL database is unchanged and is
            read in a directory that cannot be written
  grid      tests/release/pvl_grid.py
  linemodel tests/release/pvl_linemodel.py --no-pandoc (pandoc is compared in the main suite)
  lineend   tests/release/pvl_lineend.py --no-pandoc (round 6: the line-ending and start-of-line class)
  property  tests/release/pvl_property.py with seed 290423 and 300 sentences
  timing    tests/release/pvl_timing.py with its default limit (the output must say limit=1.00s)
  inventory tests/release/pvl_inventory.py (only when nothing earlier killed the mutant)
Output: `MUT <id> KILLED by <harness> (rc N)` / `MUT <id> SURVIVED` / `MUT <id> NOT-APPLIED`, then
`MUTATE total=N killed=K survived=S not_applied=A`. Exit 0 when S and A are 0, else 1. A harness run is bounded at 600 s.
Section 11.4.289(C)(2): gate-logic only.
"""
import ast
import os
import shutil
import sqlite3
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
CHECKER = "scripts/validation/check_provisional_verification_lines.py"
RENDER = "scripts/release/render_release_entry.py"
READING = "scripts/validation/pvl_reading_table.py"  # round 8: pvl_blockstate's oracle reads labels with it
HARNESS = ["pvl_fixture.py", "pvl_oracle.py", "pvl_grid.py", "pvl_linemodel.py", "pvl_property.py", "pvl_timing.py",
           "pvl_inventory.py", "pvl_refreader.py", "pvl_lineend.py", "pvl_blockstate.py"]
KILLERS = ("grid", "linemodel", "lineend", "blockstate", "property", "timing", "inventory")
SUITE_FILES = {CHECKER} | {"tests/release/" + h for h in HARNESS}


def own_mutants(repo):
    out = []
    with open(os.path.join(repo, "tests/release/pvl_mutants.tsv"), encoding="utf-8") as fh:
        for ln in fh:
            if ln.startswith("#") or not ln.strip():
                continue
            mid, rel, old, new, why = ln.rstrip("\n").split("\t", 4)
            out.append((mid, rel, ast.literal_eval(old), ast.literal_eval(new)))
    return out


def retired_mutants(repo):
    """Own mutants whose code was removed (tests/release/pvl_mutants_retired.tsv); proof: the old text occurs 0 times."""
    out = []
    path = os.path.join(repo, "tests/release/pvl_mutants_retired.tsv")
    if not os.path.exists(path):
        return out
    with open(path, encoding="utf-8") as fh:
        for ln in fh:
            if ln.startswith("#") or not ln.strip():
                continue
            mid, rel, old, new, why = ln.rstrip("\n").split("\t", 4)
            out.append((mid, rel, ast.literal_eval(old)))
    return out


def equivalent_mutants(repo):
    """Own mutants shown equivalent (tests/release/pvl_mutants_equivalent.tsv): each row's argument says why no body
    can tell it apart from the checker; the run checks that the mutant still applies and reports it, never counts it
    as killed. The searches that found no telling body are docs/qa/rehearsal_v73_4_fix/r7/tools/survivor_search.py
    (verdicts) and docs/qa/rehearsal_v73_4_fix/r8/tools/survivor_search.py (reasons, with a control mutant)."""
    out = []
    path = os.path.join(repo, "tests/release/pvl_mutants_equivalent.tsv")
    if not os.path.exists(path):
        return out
    with open(path, encoding="utf-8") as fh:
        for ln in fh:
            if ln.startswith("#") or not ln.strip():
                continue
            mid, rel, old, new, why = ln.rstrip("\n").split("\t", 4)
            out.append((mid, rel, ast.literal_eval(old), why))
    return out


def reviewer_mutants(repo):
    p = subprocess.run([sys.executable, "-I", os.path.join(HERE, "pvl_reviewer.py"), "mutants", repo],
                       capture_output=True, text=True)
    out = []
    for ln in p.stdout.splitlines():
        if ln.startswith("REV-MUT-SPEC "):
            mid, rel, old, new = ln[len("REV-MUT-SPEC "):].split("\t")
            if rel in SUITE_FILES:
                out.append((mid, rel, ast.literal_eval(old), ast.literal_eval(new)))
    return out


def sandbox(repo, base):
    for rel in [CHECKER, RENDER, READING] + ["tests/release/" + h for h in HARNESS]:
        dst = os.path.join(base, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copyfile(os.path.join(repo, rel), dst)


def api(box, work):
    """The command-line cases; 0 when the checker behaves, 1 otherwise."""
    sys.path.insert(0, os.path.join(box, "tests/release"))
    try:
        import importlib
        F = importlib.import_module("pvl_fixture")
        fx = F.make_root(os.path.join(work, "root"))
    finally:
        sys.path.pop(0)
    good = F.line()
    bodies = {
        "CON-801": ("## x\n\n" + good, True),
        "CON-802": ("## x\n\n" + good + "\n\n" + good, False),                    # two lines
        "CON-803": ("## x\n\n" + F.line(job="CON-778"), False),                    # a Fixed item is not a job
        "CON-804": ("## x\n\n" + F.line(due="2026-10-31"), False),                 # before created
        "CON-805": ("## x\n\n" + F.line(due="2027-01-16"), False),                 # after the window
        "CON-806": ("## x\n<!-->\n\n" + good, False),                              # the two readings differ
        "CON-807": ("## x\ntext\n" + good, False),                                 # continues a paragraph
        "CON-808": ("## x\n\n> q\n" + good, False),                                # lazy continuation
        "CON-809": ("## x\n\n```\n" + good + "\n```\n", False),                    # fenced
        "CON-810": ("## x\n\n" + F.line(job="CON-810"), False),                    # the item itself
        # r6 near rule: a labelled line a reader shows as text (an HTML kind 6 start line shows its markdown raw; a
        # soft hyphen inside the word is invisible) refuses the body
        "CON-811": ("## x\n\n<div>**Verification:** provisional -- job: x\n\n" + good, False),
        "CON-812": ("## x\n\ntext\n**Veri\u00adfication:** provisional -- job: x\n\n" + good, False),
    }
    db = os.path.join(work, "api.db")
    if os.path.exists(db):
        os.remove(db)
    con = sqlite3.connect(db)
    con.execute("create table items (atm_id text primary key, status text, body_md text, created_at text)")
    others = {k: st for k, st in F.ITEMS.items() if st not in ("Ready for testing", "In testing")}
    for k, st in others.items():
        con.execute("insert into items values (?,?,?,?)", (k, st, "x", "2026-11-01"))
    for k, (b, _) in bodies.items():
        con.execute("insert into items values (?,?,?,?)", (k, "Ready for testing", b, "2026-11-01T09:00:00Z"))
    con.commit()
    con.close()
    p = subprocess.run([sys.executable, "-I", os.path.join(box, CHECKER), "--root", fx["root"], "--today",
                        F.TODAY.isoformat(), db], capture_output=True, text=True)
    failed = {ln.split()[1] for ln in p.stdout.splitlines() if ln.startswith("FAIL ")}
    want = {k for k, (_, ok) in bodies.items() if not ok}
    if p.returncode != 1 or failed != want:
        return 1
    if "FAIL CON-810 Ready for testing: field 'job' names the item itself (CON-810), not a job" not in p.stdout:
        return 1
    if "CHECKED items=%d provisional_status=%d ok=1 fail=%d" % (len(others) + len(bodies), len(bodies),
                                                               len(want)) not in p.stdout:
        return 1
    # every look-alike of the render's map (an independent copy) is named in the refusal reason
    src = open(os.path.join(box, RENDER), encoding="utf-8").read()
    rmap = None
    for n in ast.parse(src).body:
        if isinstance(n, ast.Assign) and any(getattr(t, "id", "") == "CONFUSABLES" for t in n.targets):
            rmap = ast.literal_eval(n.value)
    if not rmap:
        return 1
    import importlib.util
    spec = importlib.util.spec_from_file_location("pvl_api_checker", os.path.join(box, CHECKER))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    for ch, asc in rmap.items():
        r = m.note_problem("x" + ch)
        if not r or ("a look-alike of %s" % asc) not in r:
            return 1
    return api_r6(box, work, F, fx, db)


def api_r6(box, work, F, fx, db):
    """Round 6 command-line cases: --root through a symlink (ROOT is the real path), typed values, status spelling,
    hour 24, the lone CR, a target registry that is not UTF-8, a closed WAL database left unchanged byte for byte."""
    ck = [sys.executable, "-I", os.path.join(box, CHECKER), "--today", F.TODAY.isoformat()]
    link = os.path.join(work, "rootsym")
    if not os.path.lexists(link):
        os.symlink(fx["root"], link)
    p = subprocess.run(ck + ["--root", link, db], capture_output=True, text=True)
    if "ROOT: %s" % fx["root"] not in p.stdout.splitlines():
        return 1
    good = "x\n\n" + F.line()
    rows = [("CON-901", "Ready for testing", good, 20261101), ("CON-902", "Ready for testing", good.encode(), "2026-11-01"),
            ("CON-903", "Ready for testing ", "x", "2026-11-01"), ("CON-904", "in testing", "x", "2026-11-01"),
            ("CON-905", "Ready for testing", good.replace("due: 2026-11-20", "due: 2026-11-20T24:00"), "2026-11-01"),
            ("CON-906", "Ready for testing", "x\r```\n\n" + F.line() + "\n```\n", "2026-11-01"),
            ("CON-907", "Ready for testing", "x\r<!--\n\n" + F.line() + "\n-->\n", "2026-11-01"),
            ("CON-908", "Ready for testing", good, "2026-11-01")]
    want = ["FAIL CON-901 Ready for testing: the created date is not text (int)",
            "FAIL CON-902 Ready for testing: the body is not text (bytes)",
            "FAIL CON-903 Ready for testing : the Status 'Ready for testing ' is not written exactly as 'Ready for testing'",
            "FAIL CON-904 in testing: the Status 'in testing' is not written exactly as 'In testing'",
            "FAIL CON-905 Ready for testing: field 'due' is not a real date and time: 2026-11-20T24:00",
            # r9: a lone CR is refused before any reader (THE BODY); r7/r8 refused these for the label and raw HTML
            "FAIL CON-906 Ready for testing: the body holds a CR that is not followed by LF",
            "FAIL CON-907 Ready for testing: the body holds a CR that is not followed by LF",
            "CHECKED items=8 provisional_status=8 ok=1 fail=7"]
    tdir = os.path.join(work, "wal")
    os.makedirs(tdir, exist_ok=True)
    tdb = os.path.join(tdir, "t.db")
    if os.path.exists(tdb):
        os.remove(tdb)
    con = sqlite3.connect(tdb)
    con.execute("pragma journal_mode=wal")
    con.execute("create table items (atm_id text primary key, status text, body_md, created_at)")
    con.executemany("insert into items values (?,?,?,?)", rows)
    con.commit()
    con.close()

    def state():
        out = []
        for n in sorted(os.listdir(tdir)):
            with open(os.path.join(tdir, n), "rb") as fh:
                out.append((n, fh.read()))
        return out
    before = state()
    p = subprocess.run(ck + ["--root", fx["root"], tdb], capture_output=True, text=True)
    if p.returncode != 1 or "Traceback" in p.stdout + p.stderr or state() != before:
        return 1
    lines = p.stdout.splitlines()
    if any(not any(ln.startswith(w) for ln in lines) for w in want) or any(ln.startswith("FAIL CON-908") for ln in lines):
        return 1
    # the same closed WAL database in a directory that cannot be written (a read-only checkout): the copy is read; an
    # in-place SQLite open would need to create -wal and -shm there and fail
    os.chmod(tdir, 0o555)
    try:
        p = subprocess.run(ck + ["--root", fx["root"], tdb], capture_output=True, text=True)
    finally:
        os.chmod(tdir, 0o755)
    if p.returncode != 1 or "CHECKED items=8 provisional_status=8 ok=1 fail=7" not in p.stdout.splitlines() \
            or state() != before:
        return 1
    reg = os.path.join(work, "bad_reg.tsv")
    with open(reg, "wb") as fh:
        fh.write(b"board\tT1\n\xff\xfe\n")
    p = subprocess.run(ck + ["--root", fx["root"], "--targets", reg, db], capture_output=True, text=True)
    if p.returncode != 2 or "VERDICT: BLIND" not in p.stdout.splitlines() or "Traceback" in p.stdout + p.stderr:
        return 1
    return api_r7(box, work, F, fx, db)


def api_r7(box, work, F, fx, db):
    """Round 7 command-line and module cases: a WAL database with a live writer (the row only in -wal is read; review
    r6 M-3, the RW01 property), the same through a symlinked path (review r6 I-3), a -wal that is a symlink to
    /dev/zero and a -journal that is a FIFO (BLIND, bounded; review r6 M-1), the copy bound, a target registry with
    lone-CR line endings, raw HTML refused, a complete comment accepted, a body over the size cap refused."""
    import importlib.util
    import threading
    ck = [sys.executable, "-I", os.path.join(box, CHECKER), "--today", F.TODAY.isoformat(), "--root", fx["root"]]
    d = os.path.join(work, "r7")
    os.makedirs(d, exist_ok=True)
    real = os.path.join(d, "real", "items.db")
    os.makedirs(os.path.dirname(real), exist_ok=True)
    for suf in ("", "-wal", "-shm", "-journal"):
        if os.path.lexists(real + suf):
            os.remove(real + suf)
    con = sqlite3.connect(real)
    con.execute("pragma journal_mode=wal")
    con.execute("create table items (atm_id text primary key, status text, body_md text, created_at text)")
    con.execute("insert into items values ('CON-777','In progress','x','2026-11-01')")
    con.commit()
    con.execute("pragma wal_checkpoint(TRUNCATE)")
    con.execute("pragma wal_autocheckpoint=0")
    con.execute("insert into items values ('CON-909','Ready for testing','x','2026-11-01')")
    con.commit()  # the live writer keeps CON-909 in -wal only (no checkpoint while it is open)
    link = os.path.join(d, "link.db")
    if os.path.lexists(link):
        os.remove(link)
    os.symlink(real, link)
    try:
        for path in (real, link):
            p = subprocess.run(ck + [path], capture_output=True, text=True, timeout=120)
            if p.returncode != 1 or "CHECKED items=2 provisional_status=1 ok=0 fail=1" not in p.stdout.splitlines() \
                    or not any(ln.startswith("FAIL CON-909 ") for ln in p.stdout.splitlines()):
                return 1
    finally:
        con.close()
    # a -wal symlink to /dev/zero and a FIFO -journal: BLIND within the bound, never a hang
    for name, make in (("zero", lambda q: os.symlink("/dev/zero", q + "-wal")), ("fifo", lambda q: os.mkfifo(q + "-journal"))):
        q = os.path.join(d, name, "items.db")
        os.makedirs(os.path.dirname(q), exist_ok=True)
        for suf in ("", "-wal", "-journal"):
            if os.path.lexists(q + suf):
                os.remove(q + suf)
        c = sqlite3.connect(q)
        c.execute("create table items (atm_id text primary key, status text, body_md text, created_at text)")
        c.execute("insert into items values ('CON-777','In progress','x','2026-11-01')")
        c.commit()
        c.close()
        make(q)
        try:
            p = subprocess.run(ck + [q], capture_output=True, text=True, timeout=60)
        except subprocess.TimeoutExpired:
            return 1
        if p.returncode != 2 or "is not a regular file" not in p.stdout or "Traceback" in p.stdout + p.stderr:
            return 1
    fifo = os.path.join(d, "fifo_db")
    if not os.path.lexists(fifo):
        os.mkfifo(fifo)
    try:
        p = subprocess.run(ck + [fifo], capture_output=True, text=True, timeout=60)
    except subprocess.TimeoutExpired:
        return 1
    if p.returncode != 2 or "is not a regular file" not in p.stdout:
        return 1
    # the copy bound, on the module (a 1 GiB file is not made for a test)
    spec = importlib.util.spec_from_file_location("pvl_api_r7", os.path.join(box, CHECKER))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    m.MAX_DB_BYTES = 1000
    tmp = os.path.join(d, "bound")
    os.makedirs(tmp, exist_ok=True)
    try:
        m.snapshot_db(db, tmp)
        return 1
    except OverflowError:
        pass
    # a registry with lone-CR line endings resolves its second term
    reg = os.path.join(d, "cr_reg.tsv")
    with open(reg, "wb") as fh:
        fh.write(b"# r\rboard\tT9\rdevice\tSER9\r")
    good = F.line(target="board T9, device SER9")
    bodies = [("CON-951", "x\n\n" + good, True),
              # round 8: every HTML comment is refused (review r7 F1: the HTML5 comment end differs)
              ("CON-952", "x\n\n<!-- a note -->\n\n" + F.line() + "\n\nend <!-- inline note -->", False),
              ("CON-953", "<div hidden>\n\n" + F.line() + "\n\n</div>", False),
              ("CON-954", F.line() + "\n\nsee <span hidden>x</span>", False),
              ("CON-955", "x\n\n" + F.line() + "\n\n" + "y" * (1024 * 1024), False),
              ("CON-956", F.line() + "\n\n> **Veri*fi*cation:** provisional -- job: x", False),
              ("CON-957", "   " + F.line(), False),
              ("CON-958", "> " + F.line(), False),
              # mutation run 1 survivors (O46, RW03, O58, O59): a label only in a link reference definition (no
              # rendered token), written with a character reference, and on the counted line in a comment or a title
              ("CON-961", "x\n\n" + F.line() + "\n\n[r]: /u 'Verification: x'", False),
              ("CON-962", "x\n\n" + F.line() + "\n\n[r]: /u '&#86;erification: x'", False),
              ("CON-963", "x\n\n" + F.line() + " <!-- Verification: x -->", False),
              ("CON-964", "x\n\n" + F.line() + " [a](u 'Verification: x')", False)]
    rdb = os.path.join(d, "r7.db")
    if os.path.exists(rdb):
        os.remove(rdb)
    c = sqlite3.connect(rdb)
    c.execute("create table items (atm_id text primary key, status text, body_md text, created_at text)")
    c.execute("insert into items values ('CON-777','In progress','x','2026-11-01')")
    for k, b, _ in bodies:
        c.execute("insert into items values (?,?,?,?)", (k, "Ready for testing", b, "2026-11-01"))
    c.commit()
    c.close()
    p = subprocess.run(ck + ["--targets", reg, rdb], capture_output=True, text=True, timeout=120)
    failed = {ln.split()[1] for ln in p.stdout.splitlines() if ln.startswith("FAIL ")}
    if failed != {k for k, _, ok in bodies if not ok}:
        return 1
    # r9: CON-956 is refused by the source label rule (both source views), CON-957/958 by the column rule, CON-964 by
    # the line alphabet (a '[' after the label), before any reader runs
    for k, why in (("CON-952", "raw HTML"), ("CON-953", "raw HTML"), ("CON-954", "raw HTML"), ("CON-955", "longer than"),
                   ("CON-956", "label in another source line"), ("CON-957", "does not start at column 0"),
                   ("CON-958", "does not start at column 0"), ("CON-961", "label in another source line"),
                   ("CON-962", "label in another source line"), ("CON-963", "raw HTML"),
                   ("CON-964", "THE LINE ALPHABET")):
        if not any(ln.startswith("FAIL %s " % k) and why in ln for ln in p.stdout.splitlines()):
            return 1
    # the parser missing or untested: the module refuses every body, the command line is BLIND (fail closed)
    m.MAX_DB_BYTES = 1 << 30
    body = "x\n\n" + F.line()
    for attr, val in (("MDIT_VERSION", "0.0.0"), ("MDIT_VERSION", "3.0.1"), ("_MarkdownIt", None)):
        keep = getattr(m, attr)
        setattr(m, attr, val)
        try:
            r = m.check_body(body, ctx=F.checker_ctx(m, fx))
        except Exception:  # noqa: BLE001 -- a crash is not a refusal
            r = None
        setattr(m, attr, keep)
        if not (isinstance(r, str) and "reader is unavailable" in r) or m.visible_lines(body) == []:
            return 1
    code = ("import runpy, sys; sys.modules['markdown_it'] = None; sys.argv = sys.argv[1:]; "
            "runpy.run_path(sys.argv[0], run_name='__main__')")
    p = subprocess.run([sys.executable, "-I", "-c", code] + ck[2:] + [rdb], capture_output=True, text=True, timeout=120)
    if p.returncode != 2 or "VERDICT: BLIND" not in p.stdout.splitlines() or "reader is unavailable" not in p.stdout:
        return 1
    return api_r8(box, work, F, fx)


def api_r8(box, work, F, fx):
    """Round 8 cases (review r7): HTML5 comment ends (F1), a second label written with invisible, look-alike or
    referenced characters (F2, F4), the counted line not shown exactly (continuation, character reference, emphasis,
    strikethrough in the GFM reading, hard break, a Unicode-space second line), a GFM footnote definition and a
    CommonMark/GFM counting difference (F3), raw HTML in image text (F5), a label in a definition BEFORE the line
    (R7M11), a status written with an invisible character read as the status, a broken reading table (BLIND), the copy
    budget shared by the database and its -wal (R7M06), a change during the copy (R7M07) and a hot rollback journal
    (R7M08)."""
    import importlib.util
    ck = [sys.executable, "-I", os.path.join(box, CHECKER), "--today", F.TODAY.isoformat(), "--root", fx["root"]]
    d = os.path.join(work, "r8")
    os.makedirs(d, exist_ok=True)
    line = F.line()

    def second(word):
        return "\n\n**" + word + ":** provisional -- job: FAKE -- checks: FAKE pass=999"
    # r9: the reasons are those of the allowlist (THE BODY, THE LINE); CON-983 (an unused definition, then the line) is
    # accepted, every reader shows the one line; CON-987 is refused by the alphabet (a '|' after the label)
    bodies = [("CON-971", "<!-- a --!><div hidden>\n-->\n\n" + line, "raw HTML"),
              ("CON-972", line + "\n\n<!-- --!><style>p{display:none}</style> -->", "raw HTML"),
              ("CON-973", line + second("Verif\ufe0fication"), "label in another source line"),
              ("CON-974", line + second("Verif&#xFE0F;ication"), "label in another source line"),
              ("CON-975", line + second("V\u0435rification"), "label in another source line"),
              ("CON-976", line + "\n\nVerification\u2236 x", "label in another source line"),
              ("CON-977", line + second("Verifi\u3164cation"), "label in another source line"),
              ("CON-978", line + second("Verificat\u0323ion"), "label in another source line"),
              ("CON-979", line + "\n-- checks: FAKE pass=999", "the line below it is not blank"),
              ("CON-980", line + " -- note a&amp;b", "THE LINE ALPHABET"),
              ("CON-981", line + " -- note *x*", "THE LINE ALPHABET"),
              ("CON-982", line + " -- note ~~x~~", "THE LINE ALPHABET"),
              ("CON-983", "[^1]: x\n\n" + line, None),
              ("CON-984", line + "\n\n![<span hidden>x</span>](u)", "raw HTML"),
              ("CON-985", line + " -- note x\\\nchecks: FAKE pass=999", "the line below it is not blank"),
              ("CON-986", "[r]: /u 'Verification: x'\n\n" + line, "label in another source line"),
              ("CON-987", line + " -- note a|b", "THE LINE ALPHABET"),
              ("CON-988", line + "\n\u3000", "the line below it is not blank"),
              ("CON-989", "| x |\n---\n" + line, "the line above it is not blank"),
              ("CON-990", line + "\n\n\u13d9erification: x", "label in another source line")]
    statuses = [("CON-991", "In\u034f testing", "is not written exactly as 'In testing'"),
                ("CON-992", "Ready\ufe0f for testing", "is not written exactly as 'Ready for testing'")]
    rdb = os.path.join(d, "r8.db")
    if os.path.exists(rdb):
        os.remove(rdb)
    c = sqlite3.connect(rdb)
    c.execute("create table items (atm_id text primary key, status text, body_md text, created_at text)")
    c.execute("insert into items values ('CON-777','In progress','x','2026-11-01')")
    for k, b, _ in bodies:
        c.execute("insert into items values (?,?,?,?)", (k, "Ready for testing", b, "2026-11-01"))
    for k, st, _ in statuses:
        c.execute("insert into items values (?,?,?,?)", (k, st, "x\n\n" + line, "2026-11-01"))
    c.commit()
    c.close()
    p = subprocess.run(ck + [rdb], capture_output=True, text=True, timeout=120)
    out = p.stdout.splitlines()
    n = len(bodies) + len(statuses)
    if p.returncode != 1 or "CHECKED items=%d provisional_status=%d ok=1 fail=%d" % (n + 1, n, n - 1) not in out:
        return 1
    for k, _, why in bodies + statuses:
        hit = [ln for ln in out if ln.startswith("FAIL %s " % k)]
        if (why is None and hit) or (why is not None and not any(why in ln for ln in hit)):
            return 1
    spec = importlib.util.spec_from_file_location("pvl_api_r8", os.path.join(box, CHECKER))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    # a reading table that differs from its recorded sum makes the run BLIND (one reading changed)
    keep = m._READING_TABLE
    i = keep.index("\nR\t")
    j = keep.index("\n", i + 1)
    m._READING_TABLE = keep[:i] + "\nR\t0041\t62" + keep[j:]
    m._READING.clear()
    prob = m.reader_problem()
    del m._READING_TABLE
    m._READING.clear()
    gone = m.reader_problem()
    m._READING_TABLE = keep
    m._READING.clear()
    if not (isinstance(prob, str) and "reading table is not intact" in prob) or m.reader_problem() is not None:
        return 1
    if not (isinstance(gone, str) and "no table" in gone):
        return 1
    # the copy budget is shared by the database and its -wal (R7M06): each file fits, the two do not
    w = os.path.join(d, "w6", "items.db")
    os.makedirs(os.path.dirname(w), exist_ok=True)
    for suf in ("", "-wal", "-shm"):
        if os.path.lexists(w + suf):
            os.remove(w + suf)
    cw = sqlite3.connect(w)
    cw.execute("pragma journal_mode=wal")
    cw.execute("create table items (atm_id text primary key, status text, body_md text, created_at text)")
    cw.commit()
    cw.execute("pragma wal_autocheckpoint=0")
    for k in range(40):
        cw.execute("insert into items values (?,?,?,?)", ("CON-%d" % (5000 + k), "Queued", "y" * 300, "2026-11-01"))
    cw.commit()
    try:
        s0, s1 = os.path.getsize(w), os.path.getsize(w + "-wal")
        if min(s0, s1) < 2:
            return 1
        m.MAX_DB_BYTES = max(s0, s1) + 1
        t6 = os.path.join(d, "t6")
        os.makedirs(t6, exist_ok=True)
        try:
            m.snapshot_db(w, t6)
            return 1
        except OverflowError:
            pass
    finally:
        cw.close()
        m.MAX_DB_BYTES = 1 << 30
    # a database that changes during every copy is reported as changing, never copied half-old (R7M07)
    w7 = os.path.join(d, "w7", "items.db")
    os.makedirs(os.path.dirname(w7), exist_ok=True)
    shutil.copyfile(rdb, w7)
    orig = m._copy_regular

    def changing(path, dst, budget):
        got = orig(path, dst, budget)
        if path == w7:
            with open(w7, "ab") as fh:
                fh.write(b"x")
        return got
    m._copy_regular = changing
    try:
        t7 = os.path.join(d, "t7")
        os.makedirs(t7, exist_ok=True)
        if m.snapshot_db(w7, t7) is not None:
            return 1
    finally:
        m._copy_regular = orig
    # a hot rollback journal is copied with the database: rows of an open transaction are not seen (R7M08)
    hj = os.path.join(d, "hj", "items.db")
    os.makedirs(os.path.dirname(hj), exist_ok=True)
    for suf in ("", "-journal"):
        if os.path.lexists(hj + suf):
            os.remove(hj + suf)
    ch = sqlite3.connect(hj, isolation_level=None)
    ch.execute("pragma journal_mode=delete")
    ch.execute("create table items (atm_id text primary key, status text, body_md text, created_at text)")
    ch.execute("begin")
    for k in range(400):
        ch.execute("insert into items values (?,?,?,?)", ("CON-%d" % (6000 + k), "Queued", "z" * 300, "2026-11-01"))
    ch.execute("commit")
    ch.execute("pragma cache_size=1")
    ch.execute("begin")
    ch.execute("update items set status='Ready for testing' where atm_id != 'CON-6000'")
    try:
        if not os.path.exists(hj + "-journal"):
            return 1
        # the case can tell: the database file alone already holds rows of the open transaction (a small cache spills)
        alone = os.path.join(d, "hj_alone.db")
        shutil.copyfile(hj, alone)
        ca = sqlite3.connect(alone)
        try:
            spilled = ca.execute("select count(*) from items where status='Ready for testing'").fetchone()[0]
        finally:
            ca.close()
            os.remove(alone)
        if not spilled:
            return 1
        p = subprocess.run(ck + [hj], capture_output=True, text=True, timeout=120)
        if "CHECKED items=400 provisional_status=0 ok=0 fail=0" not in p.stdout.splitlines():
            return 1
    finally:
        ch.execute("rollback")
        ch.close()
    return api_r9(box, work, F, fx)


def api_r9(box, work, F, fx):
    """Round 9 (allowlist-first) cases, each layer alone so a mutant of one layer is not hidden by the other (review r8
    A2: "equivalent by redundancy" was false for O59). The source layer (THE BODY, THE LINE) through check_body with the
    reason each body must get; the reader layer (THE READERS) through confirm() on bodies the source layer would stop
    first: the reviewer's A1 link split (O59's hole), RVA01 code span, RVA03 strikethrough (GFM reading only), RVA12 hard
    break, raw-HTML output and an unlisted tag (RVA05, O100), a doubled line (O101); a line a reader rewrites although its
    characters are in the alphabet (an email address: pandoc gfm links it; RVA09); fold() of a ligature and of a
    character in the last drop range (RVA10, RVA11)."""
    import importlib.util
    spec = importlib.util.spec_from_file_location("pvl_api_r9", os.path.join(box, CHECKER))
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    ctx = F.checker_ctx(m, fx)
    line = F.line()
    rest = line[len(m.BOLD_LABEL):]
    fake = " provisional -- job: FAKE -- checks: FAKE pass=999"
    source = [  # (body, a substring of check_body's reason; None: accepted)
        (line, None),
        ("x\n\n" + line + "\n\ny", None),
        ("x\n" + line, "the line above it is not blank"),                                      # O93
        (line + "\n-- checks: FAKE pass=999", "the line below it is not blank"),               # O94
        ("x\r```\n\n" + line + "\n```\n", "a CR that is not followed by LF"),                  # O90
        (line + "\n\n&#x202E;:noitacifireV**", "bidi control U+202E"),                         # O91
        (":::{style=display:none}\n\n" + line + "\n\n:::", "fenced div"),                     # O92
        (line + " -- note *x*", "THE LINE ALPHABET"),                                          # O95
        (line + " -- note _x_", "an underscore at column"),                                    # O96
        (line + "  ", "ends with white space"),                                                # O97
        (line + "\n\n**Verifi[cation](x):**" + fake, "label in another source line"),          # O98 (A1)
        (line + "\n\n**Verifi`cation`:**" + fake, "label in another source line"),             # R9A01b
        ("**Verifi[cation](x):**" + fake + "\n\n" + line, "label in another source line"),     # R7M11: a line BEFORE
        (line + "\n\n**Verification**" + fake, "label in another source line"),                # O99 (G)
        (line + "\n\n**Veriﬁcation:**" + fake, "label in another source line"),           # RVA10
        (line + "\n\n**Verif\U000E0100ication:**" + fake, "label in another source line"),     # RVA11
        ("x\n\n<!-- a note -->\n\n" + line, "raw HTML"),                                       # R9A08
        ("   " + line, "does not start at column 0"),
        ("<!x\n\n" + line + "\n\n>", "raw HTML"),                                           # CommonMark 0.30 vs 0.31.2
        ("<!doctype html\n\n" + line + "\n\n>", "raw HTML"),
        ("<search>\n\n" + line + "\n\n</search>", "raw HTML"),
        (line + "\n\n:   a definition", "pandoc markdown does not show"),                      # O105
        (line + " -- note wait... ok", None),                                                 # O106, O107
        ("x\n\n---\na: *b\n---\n\n" + line, None),                                            # O108 (export reader)
        (line + "\n\n" + line, "2 verification lines (one expected)"),                   # O61, R21
        (line + " -- note " + "a." * 10000, "with no white space between them"),               # O102 (r3 singles20k)
        (line + "\n\n" + "a." * 256, None),                                                  # a 512-character run is read
        (line + " -- note" + " a." * 1500, "longer than allowed"),                             # O103
        (line + "\n\n" + "y " * 40000, "the body is longer than 65536"),                     # O104
        (line + " -- note mail a@b.c", "pandoc gfm does not show the line"),                   # R9A09
    ]
    for body, why in source:
        r = m.check_body(body, ctx=ctx)
        if (why is None and r is not None) or (why is not None and (r is None or why not in r)):
            return 1
    readers = [  # (body, the start of confirm()'s one reason; None: no reason)
        (line, None),
        (line + "\n\n**Verifi[cation](x):**" + fake, "label: markdown-it commonmark"),          # R9A59 (O59 analog)
        (line + "\n\nVerifi`cation`:" + fake, "label: markdown-it commonmark"),                # R9A01, R9A07
        (line + "\n\nVerifi~~cation~~:" + fake, "label: markdown-it gfm"),                     # R9A03
        (line + "\n\nVeri*fi*cation\\\n:" + fake, "label: markdown-it commonmark"),            # R9A12
        ("<div hidden>\n\n" + line + "\n\n</div>", "reader: markdown-it commonmark writes the attribute hidden"),  # R9A05
        ("<script>x</script>\n\n" + line, "reader: markdown-it commonmark writes <script>"),   # O100
        (line + "\n\n" + line, "exact: markdown-it commonmark"),                               # O101
        ("<!x\n\n" + line + "\n\n>", "reader: pandoc commonmark writes"),                    # readers disagree
        ("<!doctype html\n\n" + line + "\n\n>", "reader: pandoc commonmark writes"),
        ("<search>\n\n" + line + "\n\n</search>", "reader: markdown-it commonmark writes <search>"),
        (line + "\n\n:   a definition", "exact: pandoc markdown"),                              # O105 alone
    ]
    for body, why in readers:
        got = m.confirm(body, rest)
        if (why is None and got != []) or (why is not None and not (len(got) == 1 and got[0].startswith(why))):
            return 1
    if "<table>" not in m.render("a | b\n--- | ---\n", "markdown-it gfm"):                # O75: the GFM table rule
        return 1
    if m.fold("ﬁ") != "fi" or m.fold("a\U000E0100b") != "ab":
        return 1
    return 0


def run(box, work, name):
    rl = os.path.join(box, "tests/release")
    ck = os.path.join(box, CHECKER)
    py = [sys.executable, "-I"]
    cmd = {"grid": py + [os.path.join(rl, "pvl_grid.py"), ck, os.path.join(work, "grid")],
           "linemodel": py + [os.path.join(rl, "pvl_linemodel.py"), ck, "--no-pandoc"],
           "lineend": py + [os.path.join(rl, "pvl_lineend.py"), ck, os.path.join(work, "le"), "--no-pandoc"],
           "blockstate": py + [os.path.join(rl, "pvl_blockstate.py"), ck, os.path.join(work, "bs"), "--quick"],
           "property": py + [os.path.join(rl, "pvl_property.py"), ck, os.path.join(work, "prop"), "290423", "300"],
           "timing": py + [os.path.join(rl, "pvl_timing.py"), ck, os.path.join(work, "tim")],
           "inventory": py + [os.path.join(rl, "pvl_inventory.py"), ck, os.path.join(work, "inv")]}[name]
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=600)
    except subprocess.TimeoutExpired:
        return 124
    if name == "timing" and p.returncode == 0 and "limit=1.00s" not in p.stdout:
        return 1
    return p.returncode


def main(argv):
    if len(argv) < 3:
        sys.stderr.write("usage: pvl_mutate.py REPO WORKDIR [ID ...]\n")
        return 64
    repo, work = os.path.abspath(argv[1]), os.path.abspath(argv[2])
    only = set(argv[3:])
    muts = own_mutants(repo) + reviewer_mutants(repo)
    retired_bad = 0
    for mid, rel, old, why in equivalent_mutants(repo):
        n = open(os.path.join(repo, rel), encoding="utf-8").read().count(old)
        if n != 1:
            retired_bad += 1
            print("MUT-EQUIVALENT-FAIL %s: the old text occurs %d times in %s (the row is stale)" % (mid, n, rel))
        else:
            print("MUT-EQUIVALENT %s: applies, not killed, reported as equivalent: %s" % (mid, why))
    for mid, rel, old in retired_mutants(repo):
        n = open(os.path.join(repo, rel), encoding="utf-8").read().count(old)
        if n:
            retired_bad += 1
            print("MUT-RETIRED-FAIL %s: the old text occurs %d times in %s (reinstate the mutant)" % (mid, n, rel))
        else:
            print("MUT-RETIRED %s: old text occurs 0 times in %s" % (mid, rel))
    # control: the unmutated copy passes every kill harness (else a kill proves nothing)
    base = os.path.join(work, "_control")
    if os.path.exists(base):
        shutil.rmtree(base)
    os.makedirs(os.path.join(base, "work"))
    sandbox(repo, os.path.join(base, "box"))
    rcs = [("api", api(os.path.join(base, "box"), os.path.join(base, "work")))] + [
        (h, run(os.path.join(base, "box"), os.path.join(base, "work"), h))
        for h in KILLERS]
    shutil.rmtree(base)
    bad = [h for h, rc in rcs if rc]
    if bad:
        print("MUTATE-BLIND the unmutated copy fails: %s" % ", ".join(bad))
        return 2
    print("MUT-CONTROL unmutated copy passes api %s" % " ".join(KILLERS))
    killed = survived = napp = 0
    for mid, rel, old, new in muts:
        if only and mid not in only:
            continue
        base = os.path.join(work, mid)
        if os.path.exists(base):
            shutil.rmtree(base)
        box, scratch = os.path.join(base, "box"), os.path.join(base, "work")
        os.makedirs(scratch)
        sandbox(repo, box)
        path = os.path.join(box, rel)
        src = open(path, encoding="utf-8").read()
        if src.count(old) != 1:
            napp += 1
            print("MUT %s NOT-APPLIED (%s: old text occurs %d times)" % (mid, rel, src.count(old)))
            continue
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(src.replace(old, new, 1))
        by = None
        try:
            rc = api(box, scratch)
        except Exception:  # noqa: BLE001 -- a mutant that breaks the module is caught
            rc = 2
        if rc:
            by = ("api", rc)
        for h in KILLERS:
            if by:
                break
            rc = run(box, scratch, h)
            if rc:
                by = (h, rc)
        if by:
            killed += 1
            print("MUT %s KILLED by %s (rc %d)" % (mid, by[0], by[1]))
        else:
            survived += 1
            print("MUT %s SURVIVED" % mid)
        shutil.rmtree(base)
    print("MUTATE total=%d killed=%d survived=%d not_applied=%d retired=%d equivalent=%d retired_fail=%d" % (
        killed + survived + napp, killed, survived, napp, len(retired_mutants(repo)), len(equivalent_mutants(repo)),
        retired_bad))
    return 0 if survived == napp == retired_bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
