#!/usr/bin/env python3
"""build_asof_scenario.py - deterministic synthetic tracker DB + git repo for
the T048 restart round-1 R5 regression checks (cycle_report.py and
select_sample.py). Test fixture builder ONLY -- never touches the live
tracker DB or the real repository.

Usage: build_asof_scenario.py OUT_DIR {full|cut|matrix-full|matrix-cut}
  full : every history row and every commit, INCLUDING rows/commits dated
         after the scenario's as-of date (2026-08-23).
  cut  : the same scenario with every item_history row whose on_date is after
         the as-of date deleted and the one post-as-of commit omitted -- i.e.
         the DB/repo exactly as they looked ON the as-of date.
  matrix-full / matrix-cut : the GENERATED window-boundary matrix (T048
         restart round 3, V3-1/V3-2/V3-8 -- see "BOUNDARY MATRIX" below),
         full or cut at the matrix's own as-of. Also writes
         OUT_DIR/repo/review_records/ and OUT_DIR/manifest.json.
A frozen as-of report MUST be byte-identical (body_hash) between the two
(the R5 B1 "delete the future rows" experiment, made deterministic).

Writes OUT_DIR/db.sqlite and OUT_DIR/repo (a git repository).

BOUNDARY MATRIX (matrix-* modes). Round 2 and round 3 each found inclusive
bounds the hand-picked rows below did not sit on (V2-4, then V3-1: a closure
ON window.from, a Reopened row ON the as-of day; V3-2: a commit exactly at
the cutoff instant). The defect class is "an inclusive/exclusive bound
nobody placed a row on", so the matrix is GENERATED from declarative tables
-- every event class x every bound x {one unit outside, exactly on, one unit
inside} -- instead of listing rows by hand:
  WINDOW_CELLS   {closure, Reopened} x {window.from, window.to (= as-of)} x
                 {-1 day, 0, +1 day} x on_date {YYYY-MM-DD, "YYYY-MM-DD 12:00:00"}
  COMMIT_CELLS   {author, committer} instant at {cutoff-1s, cutoff, cutoff+1s}
                 x offset {Z, +05:00} (cutoff = 00:00:00Z of as-of + 1 day)
  REVIEW_CELLS   a round whose end, or (inverted) start, sits at {cutoff-1s,
                 cutoff, cutoff+1s}, plus one round straddling the cutoff
  RULE_CELLS     first-vs-latest closure for the retroactive and the bulk-
                 cluster rules; classifier-population variants (a candidate
                 present only through a Reopened row); the derived CT-009
                 needle (the matrix as-of predates the default needle row)
manifest.json records every cell's RAW facts (rows, commits, rounds) and its
declared dimensions -- NO expected outcome. The expected outcome of every
cell is computed by an independent reference oracle inside each test, which
also fails if a cell has no assertion (tests/test_select_sample_r5_
regression.sh S9, tests/test_cycle_report_red.sh R5-C15).

Scenario (as_of=2026-08-23; tests use --window-days 60 => from 2026-06-24,
--min-per-type 2, --bulk-threshold 3). Hand-derived expectations are stated in
the tests that use this builder, not computed here.
  Bug  ATM-300  Fixed 06-20 (before window), Reopened 06-24 (= window.from,
                boundary row, V2-4), Fixed 06-30
                                       FUTURE: Reopened 09-01, Fixed 09-28 (dir qa/z)
  Bug  ATM-953  Fixed 07-01
  Bug  ATM-1002 Fixed 07-10            (two NON-UTC commits, V2-3)
  Bug  ATM-800  Fixed 06-26, Reopened 07-15 (+1 EXACT duplicate row), Fixed 07-25
  Bug  ATM-277  Fixed 08-20            FUTURE: Reopened 09-05, Fixed 09-20
  Bug  ATM-310  Fixed 08-23 = ON the as-of day (boundary row, V2-4)
  Bug  ATM-1003 Fixed 06-25, its closure row WRITTEN LAST (highest row id) --
                created_at says least-recent, row id says most-recent (V2 SS_N4)
  Task ATM-501/502/503 Completed 07-05 (distinct dirs)
                                       FUTURE: Reopened 09-02, Completed 09-28 (shared dir qa/bulk)
  Task ATM-504  Completed 07-06 whose created_at is 60 s BEFORE its Opened row
                (negative gap: NOT a retroactive registration, V2 SS_N3)
  Task ATM-601/602/603 Completed 07-20 (shared dir qa/realbulk -> genuine bulk cluster)
  Feature ATM-700 Opened+Implemented 08-01, 20 s apart (retroactive registration)
                                       FUTURE: Reopened 09-02, Implemented 09-10
Commits:
  fix(ATM-800): ...   author 07-25T09:00Z committer 07-25T09:20Z
  fix(ATM-800): earlier-authored  author 07-24T08:00Z committer 07-25T11:00Z
                      (the latest COMMITTER instant is not on the latest-AUTHORED commit)
  fix ATM-277 part    author 08-20T09:00Z committer 08-20T09:30Z
  ATM-2770 unrelated  author 08-21T11:00Z committer 08-21T12:00Z (token-boundary trap for ATM-277)
  chore: misc (body names ATM-277)  author 08-22T09:00Z committer 08-22T09:05Z (body-only trap)
  fix ATM-1002 tz-a   author 07-10T09:00+05:00 (04:00Z) committer 09:10+05:00 (04:10Z)
  fix ATM-1002 tz-b   author 07-10T08:00+03:00 (05:00Z) committer 08:30+03:00 (05:30Z)
                      (lexically "08:00+03:00" < "09:00+05:00" although it is LATER)
  fix ATM-310 on as-of day  author 08-23T10:00Z committer 08-23T10:30Z
  fix ATM-310 late    author 08-24T02:00+05:00 (= 08-23T21:00Z) committer
                      08-24T02:30+05:00 (= 08-23T21:30Z) -- inside the as-of day in UTC
  FUTURE rebased ATM-277  author 08-22T09:00Z committer 08-25T09:00Z (rebased:
                      authored before, committed after the cutoff; full mode only)
  FUTURE followup ATM-277  author 09-20T09:00Z committer 09-20T10:00Z  (full mode only)
"""
import datetime
import json
import os
import sqlite3
import subprocess
import sys

AS_OF = "2026-08-23"

ITEMS = [
    ("ATM-300", "Bug", "Fixed (→ Fixed.md)"),
    ("ATM-953", "Bug", "Fixed (→ Fixed.md)"),
    ("ATM-1002", "Bug", "Fixed (→ Fixed.md)"),
    ("ATM-800", "Bug", "Fixed (→ Fixed.md)"),
    ("ATM-277", "Bug", "Fixed (→ Fixed.md)"),
    ("ATM-501", "Task", "Completed (→ Fixed.md)"),
    ("ATM-502", "Task", "Completed (→ Fixed.md)"),
    ("ATM-503", "Task", "Completed (→ Fixed.md)"),
    ("ATM-601", "Task", "Completed (→ Fixed.md)"),
    ("ATM-602", "Task", "Completed (→ Fixed.md)"),
    ("ATM-603", "Task", "Completed (→ Fixed.md)"),
    ("ATM-700", "Feature", "Implemented (→ Fixed.md)"),
    ("ATM-310", "Bug", "Fixed (→ Fixed.md)"),
    ("ATM-1003", "Bug", "Fixed (→ Fixed.md)"),
    ("ATM-504", "Task", "Completed (→ Fixed.md)"),
]

# (atm_id, event_type, by, on_date, reason, evidence_path, created_at)
HISTORY = [
    ("ATM-300", "Opened", "User", "2026-06-04", None, None, "2026-06-04 08:00:00"),
    ("ATM-300", "Fixed", "AI", "2026-06-20", None, "qa/d0/x.log", "2026-06-20 10:00:00"),
    ("ATM-300", "Reopened", "User", "2026-06-24", "manual-testing-detected", None, "2026-06-24 10:00:00"),
    ("ATM-300", "Fixed", "AI", "2026-06-30", None, "qa/d/x.log", "2026-06-30 10:00:00"),
    ("ATM-300", "Reopened", "User", "2026-09-01", "manual-testing-detected", None, "2026-09-01 10:00:00"),
    ("ATM-300", "Fixed", "AI", "2026-09-28", None, "qa/z/y.log", "2026-09-28 10:00:00"),

    ("ATM-953", "Opened", "User", "2026-06-01", None, None, "2026-06-01 08:00:00"),
    ("ATM-953", "Fixed", "AI", "2026-07-01", None, "qa/a/x.log", "2026-07-01 10:00:00"),

    ("ATM-1002", "Opened", "User", "2026-06-02", None, None, "2026-06-02 08:00:00"),
    ("ATM-1002", "Fixed", "AI", "2026-07-10", None, "qa/b/x.log", "2026-07-10 10:00:00"),

    ("ATM-800", "Opened", "User", "2026-06-01", None, None, "2026-06-01 08:00:00"),
    ("ATM-800", "Fixed", "AI", "2026-06-26", None, "qa/e/x.log", "2026-06-26 10:00:00"),
    ("ATM-800", "Reopened", "User", "2026-07-15", "manual-testing-detected", None, "2026-07-15 10:00:00"),
    ("ATM-800", "Reopened", "User", "2026-07-15", "manual-testing-detected", None, "2026-07-15 10:00:00"),
    ("ATM-800", "Fixed", "AI", "2026-07-25", None, "qa/f/x.log", "2026-07-25 10:00:00"),

    ("ATM-277", "Opened", "User", "2026-06-03", None, None, "2026-06-03 08:00:00"),
    ("ATM-277", "Fixed", "AI", "2026-08-20", None, "qa/c/x.log", "2026-08-20 10:00:00"),
    ("ATM-277", "Reopened", "User", "2026-09-05", "manual-testing-detected", None, "2026-09-05 10:00:00"),
    ("ATM-277", "Fixed", "AI", "2026-09-20", None, "qa/g/x.log", "2026-09-20 09:00:00"),
]
for n, hh in (("501", "10"), ("502", "11"), ("503", "12")):
    aid = "ATM-" + n
    HISTORY += [
        (aid, "Opened", "User", "2026-06-10", None, None, "2026-06-10 08:00:00"),
        (aid, "Completed", "AI", "2026-07-05", None, "qa/t%s/x.log" % n, "2026-07-05 %s:00:00" % hh),
        (aid, "Reopened", "User", "2026-09-02", "manual-testing-detected", None, "2026-09-02 %s:00:00" % hh),
        (aid, "Completed", "AI", "2026-09-28", None, "qa/bulk/%s.log" % n, "2026-09-28 %s:00:00" % hh),
    ]
for n, hh in (("601", "10"), ("602", "11"), ("603", "12")):
    aid = "ATM-" + n
    HISTORY += [
        (aid, "Opened", "User", "2026-06-11", None, None, "2026-06-11 08:00:00"),
        (aid, "Completed", "AI", "2026-07-20", None, "qa/realbulk/%s.log" % n, "2026-07-20 %s:00:00" % hh),
    ]
HISTORY += [
    ("ATM-700", "Opened", "User", "2026-08-01", None, None, "2026-08-01 10:00:00"),
    ("ATM-700", "Implemented", "AI", "2026-08-01", None, "qa/h/x.log", "2026-08-01 10:00:20"),
    ("ATM-700", "Reopened", "User", "2026-09-02", "manual-testing-detected", None, "2026-09-02 10:00:00"),
    ("ATM-700", "Implemented", "AI", "2026-09-10", None, "qa/i/x.log", "2026-09-10 10:00:00"),

    ("ATM-310", "Opened", "User", "2026-06-05", None, None, "2026-06-05 08:00:00"),
    ("ATM-310", "Fixed", "AI", "2026-08-23", None, "qa/j/x.log", "2026-08-23 10:00:00"),

    ("ATM-504", "Opened", "User", "2026-07-06", None, None, "2026-07-06 10:00:00"),
    ("ATM-504", "Completed", "AI", "2026-07-06", None, "qa/t504/x.log", "2026-07-06 09:59:00"),

    ("ATM-1003", "Opened", "User", "2026-06-06", None, None, "2026-06-06 08:00:00"),
]
# ATM-1003's closure row is appended LAST so it carries the highest row id
# while its created_at is the least recent of every Bug closure.
HISTORY.append(("ATM-1003", "Fixed", "AI", "2026-06-25", None, "qa/k/x.log", "2026-06-25 10:00:00"))

# (subject, body, author_date, committer_date, future)
COMMITS = [
    ("fix(ATM-800): restore state", "", "2026-07-25T09:00:00+00:00", "2026-07-25T09:20:00+00:00", False),
    ("fix(ATM-800): earlier-authored", "", "2026-07-24T08:00:00+00:00", "2026-07-25T11:00:00+00:00", False),
    ("fix ATM-277 part", "", "2026-08-20T09:00:00+00:00", "2026-08-20T09:30:00+00:00", False),
    ("ATM-2770 unrelated change", "", "2026-08-21T11:00:00+00:00", "2026-08-21T12:00:00+00:00", False),
    ("chore: misc", "refs ATM-277 in the body only", "2026-08-22T09:00:00+00:00", "2026-08-22T09:05:00+00:00", False),
    ("fix ATM-1002 tz-a", "", "2026-07-10T09:00:00+05:00", "2026-07-10T09:10:00+05:00", False),
    ("fix ATM-1002 tz-b", "", "2026-07-10T08:00:00+03:00", "2026-07-10T08:30:00+03:00", False),
    ("fix ATM-310 on as-of day", "", "2026-08-23T10:00:00+00:00", "2026-08-23T10:30:00+00:00", False),
    ("fix ATM-310 late", "", "2026-08-24T02:00:00+05:00", "2026-08-24T02:30:00+05:00", False),
    ("fix ATM-277 rebased", "", "2026-08-22T09:00:00+00:00", "2026-08-25T09:00:00+00:00", True),
    ("followup ATM-277", "", "2026-09-20T09:00:00+00:00", "2026-09-20T10:00:00+00:00", True),
]


SCHEMA_SQL = (
    "CREATE TABLE items (atm_id TEXT NOT NULL, type TEXT NOT NULL, status TEXT NOT NULL,"
    " title TEXT NOT NULL DEFAULT '', description TEXT NOT NULL DEFAULT '',"
    " created_at TEXT NOT NULL DEFAULT '2026-06-01 00:00:00',"
    " last_modified TEXT NOT NULL DEFAULT '2026-06-01 00:00:00',"
    " current_location TEXT NOT NULL DEFAULT 'Issues',"
    " representation TEXT NOT NULL DEFAULT 'section');"
    "CREATE TABLE item_history (id INTEGER PRIMARY KEY AUTOINCREMENT, atm_id TEXT NOT NULL,"
    " event_type TEXT NOT NULL, by TEXT, on_date TEXT NOT NULL, reason TEXT,"
    " evidence_path TEXT, created_at TEXT NOT NULL);")


def build_db(path, mode):
    conn = sqlite3.connect(path)
    conn.executescript(SCHEMA_SQL)
    conn.executemany("INSERT INTO items (atm_id, type, status) VALUES (?,?,?)", ITEMS)
    rows = [r for r in HISTORY if mode == "full" or r[3] <= AS_OF]
    conn.executemany(
        "INSERT INTO item_history (atm_id, event_type, by, on_date, reason, evidence_path, created_at)"
        " VALUES (?,?,?,?,?,?,?)", rows)
    # The CT-009 needle defaults (ATM-953 Fixed 2026-07-28) do not exist here;
    # tests pass --needle-* overrides pointing at ATM-953 Fixed 2026-07-01.
    conn.commit()
    conn.close()


def git(repo, *args, env=None):
    subprocess.run(["git", "-C", repo] + list(args), check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, env=env)


def build_repo(repo, mode):
    os.makedirs(repo)
    git(repo, "init", "-q")
    git(repo, "config", "user.name", "fixture")
    git(repo, "config", "user.email", "fixture@example.invalid")
    git(repo, "config", "commit.gpgsign", "false")
    for subject, body, ad, cd, future in COMMITS:
        if future and mode != "full":
            continue
        env = dict(os.environ, GIT_AUTHOR_DATE=ad, GIT_COMMITTER_DATE=cd)
        msg = subject + ("\n\n" + body if body else "")
        git(repo, "commit", "-q", "--allow-empty", "-m", msg, env=env)


# ===========================================================================
# BOUNDARY MATRIX (matrix-full / matrix-cut). Declarative tables; every cell
# becomes one or more items with their own rows, commits and review rounds.
# ===========================================================================
M_AS_OF = "2026-05-20"           # predates the default CT-009 needle row (07-28)
M_WINDOW_DAYS = 30               # => window [2026-04-20, 2026-05-20]
M_CUTOFF = "2026-05-21T00:00:00+00:00"   # first instant after the as-of day
M_BULK_THRESHOLD = 3

WINDOW_EVENTS = ("closure", "reopened")
WINDOW_BOUNDS = ("from", "to")
DAY_OFFSETS = (-1, 0, 1)
ON_DATE_FORMATS = ("date", "datetime")
COMMIT_WHO = ("author", "committer")
SECOND_OFFSETS = (-1, 0, 1)
COMMIT_TZ = ("Z", "+05:00")
REVIEW_CELLS = [("end", -1), ("end", 0), ("end", 1), ("start", -1), ("start", 0), ("start", 1),
                ("straddle", None)]
RULE_CELLS = ("retro_terminal_not_first", "retro_terminal_is_retro",
              "bulk_latest_shared", "bulk_first_shared",
              "pop_retro_reopen_only", "pop_bulk_reopen_only", "needle_derived")
TYPE_ROTATION = ("Bug", "Task", "Feature")


def _iso_day(base, days):
    return (datetime.date.fromisoformat(base) + datetime.timedelta(days=days)).isoformat()


def _instant(seconds_from_cutoff, tz):
    """M_CUTOFF + seconds, rendered in offset `tz` (the instant is the same)."""
    cut = datetime.datetime.fromisoformat(M_CUTOFF)
    t = cut + datetime.timedelta(seconds=seconds_from_cutoff)
    if tz == "Z":
        return t.astimezone(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S+00:00")
    sign = 1 if tz[0] == "+" else -1
    off = datetime.timezone(sign * datetime.timedelta(hours=int(tz[1:3]), minutes=int(tz[4:6])))
    return t.astimezone(off).isoformat()


def matrix_cells():
    """Generate every cell. Returns a list of dicts:
    {cell_id, kind, dims, items: [{atm_id, type, rows: [(event, by, on_date,
    reason, evidence_path, created_at)], commits: [(subject, author, committer)],
    rounds: [(started_at, ended_at, tokens)]}]}"""
    from_day = _iso_day(M_AS_OF, -M_WINDOW_DAYS)
    bound_day = {"from": from_day, "to": M_AS_OF}
    cells, n = [], [80000]

    def new_id():
        n[0] += 1
        return "ATM-%d" % n[0]

    def opened(day="2026-03-01", t="08:00:00"):
        return ("Opened", "User", day, None, None, "%s %s" % (day, t))

    # WINDOW_CELLS ---------------------------------------------------------
    i = 0
    for ev in WINDOW_EVENTS:
        for bound in WINDOW_BOUNDS:
            for off in DAY_OFFSETS:
                for fmt in ON_DATE_FORMATS:
                    aid = new_id()
                    day = _iso_day(bound_day[bound], off)
                    on_date = day if fmt == "date" else day + " 12:00:00"
                    if ev == "closure":
                        rows = [opened(),
                                ("Fixed", "AI", on_date, None, "qa/m/%s/x.log" % aid, day + " 10:00:00")]
                    else:
                        rows = [opened(),
                                ("Fixed", "AI", "2026-03-15", None, "qa/m/%s/x.log" % aid, "2026-03-15 10:00:00"),
                                ("Reopened", "User", on_date, "manual-testing-detected", None, day + " 10:00:00")]
                    cells.append({"cell_id": "window/%s/%s/%+d/%s" % (ev, bound, off, fmt), "kind": "window",
                                  "dims": {"event": ev, "bound": bound, "offset_days": off, "on_date_format": fmt},
                                  "items": [{"atm_id": aid, "type": TYPE_ROTATION[i % 3], "rows": rows,
                                             "commits": [], "rounds": []}]})
                    i += 1

    # COMMIT_CELLS: a closure in the window, one baseline commit long before
    # the cutoff, and the cell commit whose author OR committer instant is at
    # cutoff + offset (the other instant 2 h before the cutoff).
    for who in COMMIT_WHO:
        for off in SECOND_OFFSETS:
            for tz in COMMIT_TZ:
                aid = new_id()
                rows = [opened(), ("Fixed", "AI", "2026-04-30", None, "qa/m/%s/x.log" % aid, "2026-04-30 10:00:00")]
                base = ("fix %s base" % aid, _instant(-36000, "Z"), _instant(-32400, "Z"))
                varied, other = _instant(off, tz), _instant(-7200, "Z")
                cell_commit = ("fix %s cell" % aid,) + ((varied, other) if who == "author" else (other, varied))
                cells.append({"cell_id": "commit/%s/%+ds/%s" % (who, off, tz), "kind": "commit",
                              "dims": {"who": who, "offset_seconds": off, "tz": tz},
                              "items": [{"atm_id": aid, "type": "Bug", "rows": rows,
                                         "commits": [base, cell_commit], "rounds": []}]})

    # REVIEW_CELLS: a baseline round long before the cutoff (1 token) and the
    # cell round (10 tokens).
    for who, off in REVIEW_CELLS:
        aid = new_id()
        rows = [opened(), ("Fixed", "AI", "2026-04-30", None, "qa/m/%s/x.log" % aid, "2026-04-30 10:00:00")]
        base = (_instant(-36000, "Z"), _instant(-32400, "Z"), 1)
        if who == "end":
            cell_round = (_instant(-3600, "Z"), _instant(off, "Z"), 10)
        elif who == "start":   # inverted round: its start is the varied instant
            cell_round = (_instant(off, "Z"), _instant(-1800, "Z"), 10)
        else:                  # straddles the cutoff
            cell_round = (_instant(-3600, "Z"), _instant(3600, "Z"), 10)
        cid = "review/%s/%+ds" % (who, off) if off is not None else "review/straddle"
        cells.append({"cell_id": cid, "kind": "review", "dims": {"who": who, "offset_seconds": off},
                      "items": [{"atm_id": aid, "type": "Task", "rows": rows, "commits": [],
                                 "rounds": [base, cell_round]}]})

    # RULE_CELLS -----------------------------------------------------------
    def item(t, rows):
        return {"atm_id": new_id(), "type": t, "rows": rows, "commits": [], "rounds": []}
    for cid in RULE_CELLS:
        items = []
        if cid == "retro_terminal_not_first":
            # first closure 20 s after Opened, the TERMINAL one days later
            it = item("Feature", [])
            it["rows"] = [opened("2026-04-25", "10:00:00"),
                          ("Implemented", "AI", "2026-04-25", None, "qa/m/%s/a.log" % it["atm_id"], "2026-04-25 10:00:20"),
                          ("Reopened", "User", "2026-04-28", "manual-testing-detected", None, "2026-04-28 10:00:00"),
                          ("Implemented", "AI", "2026-05-02", None, "qa/m/%s/b.log" % it["atm_id"], "2026-05-02 10:00:00")]
            items.append(it)
        elif cid == "retro_terminal_is_retro":
            # first closure row written BEFORE Opened (negative gap), the
            # terminal one 30 s after Opened
            it = item("Bug", [])
            it["rows"] = [opened("2026-04-26", "10:00:00"),
                          ("Fixed", "AI", "2026-04-22", None, "qa/m/%s/a.log" % it["atm_id"], "2026-04-22 10:00:00"),
                          ("Fixed", "AI", "2026-04-26", None, "qa/m/%s/b.log" % it["atm_id"], "2026-04-26 10:00:30")]
            items.append(it)
        elif cid == "bulk_latest_shared":
            for k in range(3):
                it = item("Task", [])
                it["rows"] = [opened(),
                              ("Completed", "AI", "2026-04-22", None, "qa/m/%s/x.log" % it["atm_id"], "2026-04-22 1%d:00:00" % k),
                              ("Completed", "AI", "2026-05-05", None, "qa/m/bulklatest/%d.log" % k, "2026-05-05 1%d:00:00" % k)]
                items.append(it)
        elif cid == "bulk_first_shared":
            for k in range(3):
                it = item("Task", [])
                it["rows"] = [opened(),
                              ("Completed", "AI", "2026-04-23", None, "qa/m/bulkfirst/%d.log" % k, "2026-04-23 1%d:00:00" % k),
                              ("Completed", "AI", "2026-05-06", None, "qa/m/%s/x.log" % it["atm_id"], "2026-05-06 1%d:00:00" % k)]
                items.append(it)
        elif cid == "pop_retro_reopen_only":
            it = item("Bug", [])
            it["rows"] = [opened("2026-03-10", "10:00:00"),
                          ("Fixed", "AI", "2026-03-10", None, "qa/m/%s/x.log" % it["atm_id"], "2026-03-10 10:00:20"),
                          ("Reopened", "User", "2026-05-01", "manual-testing-detected", None, "2026-05-01 10:00:00")]
            items.append(it)
        elif cid == "pop_bulk_reopen_only":
            for k in range(3):
                it = item("Bug", [])
                it["rows"] = [opened(),
                              ("Fixed", "AI", "2026-03-12", None, "qa/m/popbulk/%d.log" % k, "2026-03-12 1%d:00:00" % k),
                              ("Reopened", "User", "2026-05-03", "manual-testing-detected", None, "2026-05-03 1%d:00:00" % k)]
                items.append(it)
        # needle_derived: no items of its own -- the oracle derives the needle
        # from every row of the matrix (closures exist ON the as-of day).
        cells.append({"cell_id": "rule/" + cid, "kind": "rule", "dims": {"rule": cid}, "items": items})
    return cells


def _row_visible(row, mode):
    return mode == "matrix-full" or row[2][:10] <= M_AS_OF


def _instant_visible(iso, mode):
    return mode == "matrix-full" or datetime.datetime.fromisoformat(iso) < datetime.datetime.fromisoformat(M_CUTOFF)


def build_matrix(out, mode):
    cells = matrix_cells()
    conn = sqlite3.connect(os.path.join(out, "db.sqlite"))
    conn.executescript(SCHEMA_SQL)
    all_items = [it for c in cells for it in c["items"]]
    conn.executemany("INSERT INTO items (atm_id, type, status) VALUES (?,?,?)",
                     [(it["atm_id"], it["type"], "Fixed (→ Fixed.md)") for it in all_items])
    for it in all_items:
        conn.executemany(
            "INSERT INTO item_history (atm_id, event_type, by, on_date, reason, evidence_path, created_at)"
            " VALUES (?,?,?,?,?,?,?)", [(it["atm_id"],) + r for r in it["rows"] if _row_visible(r, mode)])
    conn.commit()
    conn.close()

    repo = os.path.join(out, "repo")
    os.makedirs(repo)
    git(repo, "init", "-q")
    git(repo, "config", "user.name", "fixture")
    git(repo, "config", "user.email", "fixture@example.invalid")
    git(repo, "config", "commit.gpgsign", "false")
    root_env = dict(os.environ, GIT_AUTHOR_DATE="2026-01-01T00:00:00+00:00",
                    GIT_COMMITTER_DATE="2026-01-01T00:00:00+00:00")
    git(repo, "commit", "-q", "--allow-empty", "-m", "matrix root", env=root_env)
    git(repo, "branch", "-q", "matrix-root")
    # One branch per item, each forked from the root, so a commit omitted in
    # matrix-cut (a tip) never changes another commit's sha: the full and cut
    # reports must be byte-identical, evidence_path (git_log#<sha>) included.
    for it in all_items:
        if not it["commits"]:
            continue
        git(repo, "checkout", "-q", "-b", "item-" + it["atm_id"], "matrix-root")
        for subject, ad, cd in it["commits"]:
            if not (_instant_visible(ad, mode) and _instant_visible(cd, mode)):
                continue
            env = dict(os.environ, GIT_AUTHOR_DATE=ad, GIT_COMMITTER_DATE=cd)
            git(repo, "commit", "-q", "--allow-empty", "-m", subject, env=env)

    # Review records live INSIDE the repo root (untracked) so their
    # evidence_path is repo-relative and identical in the full and cut reports.
    rr = os.path.join(repo, "review_records")
    os.makedirs(rr)
    for it in all_items:
        for k, (s, e, tok) in enumerate(it["rounds"]):
            if not (_instant_visible(s, mode) and _instant_visible(e, mode)):
                continue
            d = os.path.join(rr, it["atm_id"])
            os.makedirs(d, exist_ok=True)
            with open(os.path.join(d, "r%d.json" % k), "w", encoding="utf-8") as fh:
                json.dump({"schema": "review-record/v1", "item_id": it["atm_id"], "started_at": s,
                           "ended_at": e, "tokens": tok}, fh)

    # The manifest is the SAME in both modes: the full raw facts. Row order is
    # the DB insert order (item_history.id), which the needle rule uses.
    manifest = {"as_of": M_AS_OF, "window_days": M_WINDOW_DAYS, "cutoff": M_CUTOFF,
                "bulk_threshold": M_BULK_THRESHOLD,
                "dimensions": {"window_events": WINDOW_EVENTS, "window_bounds": WINDOW_BOUNDS,
                               "day_offsets": DAY_OFFSETS, "on_date_formats": ON_DATE_FORMATS,
                               "commit_who": COMMIT_WHO, "second_offsets": SECOND_OFFSETS,
                               "commit_tz": COMMIT_TZ, "review_cells": REVIEW_CELLS,
                               "rule_cells": RULE_CELLS},
                "cells": [{"cell_id": c["cell_id"], "kind": c["kind"], "dims": c["dims"],
                           "items": [{"atm_id": it["atm_id"], "type": it["type"],
                                      "rows": [dict(zip(("event_type", "by", "on_date", "reason",
                                                         "evidence_path", "created_at"), r)) for r in it["rows"]],
                                      "commits": [dict(zip(("subject", "author_date", "committer_date"), cm))
                                                  for cm in it["commits"]],
                                      "rounds": [dict(zip(("started_at", "ended_at", "tokens"), rd))
                                                 for rd in it["rounds"]]}
                                     for it in c["items"]]}
                          for c in cells]}
    with open(os.path.join(out, "manifest.json"), "w", encoding="utf-8") as fh:
        json.dump(manifest, fh, indent=1, sort_keys=True)


def main(argv):
    modes = ("full", "cut", "matrix-full", "matrix-cut")
    if len(argv) != 2 or argv[1] not in modes:
        print(__doc__, file=sys.stderr)
        return 2
    out, mode = argv
    os.makedirs(out, exist_ok=True)
    if mode.startswith("matrix-"):
        build_matrix(out, mode)
        return 0
    build_db(os.path.join(out, "db.sqlite"), mode)
    build_repo(os.path.join(out, "repo"), mode)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
