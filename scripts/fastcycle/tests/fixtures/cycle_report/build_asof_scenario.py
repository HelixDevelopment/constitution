#!/usr/bin/env python3
"""build_asof_scenario.py - deterministic synthetic tracker DB + git repo for
the T048 restart round-1 R5 regression checks (cycle_report.py and
select_sample.py). Test fixture builder ONLY -- never touches the live
tracker DB or the real repository.

Usage: build_asof_scenario.py OUT_DIR {full|cut}
  full : every history row and every commit, INCLUDING rows/commits dated
         after the scenario's as-of date (2026-08-23).
  cut  : the same scenario with every item_history row whose on_date is after
         the as-of date deleted and the one post-as-of commit omitted -- i.e.
         the DB/repo exactly as they looked ON the as-of date.
A frozen as-of report MUST be byte-identical (body_hash) between the two
(the R5 B1 "delete the future rows" experiment, made deterministic).

Writes OUT_DIR/db.sqlite and OUT_DIR/repo (a git repository).

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


def build_db(path, mode):
    conn = sqlite3.connect(path)
    conn.executescript(
        "CREATE TABLE items (atm_id TEXT NOT NULL, type TEXT NOT NULL, status TEXT NOT NULL,"
        " title TEXT NOT NULL DEFAULT '', description TEXT NOT NULL DEFAULT '',"
        " created_at TEXT NOT NULL DEFAULT '2026-06-01 00:00:00',"
        " last_modified TEXT NOT NULL DEFAULT '2026-06-01 00:00:00',"
        " current_location TEXT NOT NULL DEFAULT 'Issues',"
        " representation TEXT NOT NULL DEFAULT 'section');"
        "CREATE TABLE item_history (id INTEGER PRIMARY KEY AUTOINCREMENT, atm_id TEXT NOT NULL,"
        " event_type TEXT NOT NULL, by TEXT, on_date TEXT NOT NULL, reason TEXT,"
        " evidence_path TEXT, created_at TEXT NOT NULL);")
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


def main(argv):
    if len(argv) != 2 or argv[1] not in ("full", "cut"):
        print(__doc__, file=sys.stderr)
        return 2
    out, mode = argv
    os.makedirs(out, exist_ok=True)
    build_db(os.path.join(out, "db.sqlite"), mode)
    build_repo(os.path.join(out, "repo"), mode)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
