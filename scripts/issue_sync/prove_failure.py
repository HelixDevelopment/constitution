#!/usr/bin/env python3
"""--prove-failure for the verifier (anchor 11.4.300(E), section 1.1): builds an in-sync mirror over an in-memory GitHub-shaped tracker, asserts the
control verdict is 0, then applies each mutation and asserts the verdict flips to its expected non-zero code. Exit 0 only when the control is green
AND every mutation is caught. Tests THIS tool's logic with a test double (anchor 11.4.289); it is not evidence about any host."""
import io
import os
import re
import sqlite3
import sys
import tempfile

from . import cli
from .tests_support import FakeGitHub, mkdb, cfgfile

ROWS = [("A-1", "Bug", "Queued", "first", "High", "first description text here ok", "Q", "B", "Issues"),
        ("A-2", "Task", "Completed (→ Fixed.md)", "second", "", "second description text here ok", None, None, "Fixed"),
        ("A-3", "Feature", "Obsolete (→ Fixed.md)", "third", "", "third description text here ok", None, None, "Fixed")]


def _run(db, cfg, f, owner="github.com/o/r", target="github.com/o/r", cmd="verify", extra=()):
    out = io.StringIO()
    rc = cli.run([cmd, "--db", db, "--config", cfg, "--target", target, "--owner-repo", owner, *extra], transport_factory=lambda v, h: f, out=out)
    return rc


def scenario(mutate, expect, name, results):
    f, db = FakeGitHub(), mkdb(ROWS)
    cfg = cfgfile("enabled: true\nmode: apply\napply_decision: d.md\n")
    assert _run(db, cfg, f, cmd="apply", extra=["--apply"]) == 0
    mutate(f, db)
    rc = _run(db, cfg, f)
    ok = rc == expect
    results.append((name, expect, rc, ok))


def m_delete(f, db): f.issues.pop(0)
def m_title(f, db): f.issues[0]["title"] += " edited"
def m_close(f, db): f.issues[0]["state"] = "closed"
def m_reopen_closed(f, db): f.issues[1]["state"] = "open"
def m_dup(f, db): f.issues.append(dict(f.issues[0], number=900))
def m_footer(f, db): f.issues[0]["body"] = re.sub(r"<!--.*?-->", "", f.issues[0]["body"])
def m_corrupt_hash(f, db): f.issues[0]["body"] = re.sub(r"sha256: [0-9a-f]{8}", "sha256: 00000000", f.issues[0]["body"])
def m_db_status(f, db): c = sqlite3.connect(db); c.execute("update items set status='In progress' where atm_id='A-1'"); c.commit()
def m_orphan(f, db): c = sqlite3.connect(db); c.execute("delete from items where atm_id='A-1'"); c.commit()
def m_canary(f, db): c = sqlite3.connect(db); c.execute("update items set description='canary ghp_%s here' where atm_id='A-1'" % ("c" * 36)); c.commit()
def m_label(f, db): f.issues[0]["labels"] = []
def m_rate(f, db): f.always = 429


def main():
    results = []
    f, db = FakeGitHub(), mkdb(ROWS)
    cfg = cfgfile("enabled: true\nmode: apply\napply_decision: d.md\n")
    assert _run(db, cfg, f, cmd="apply", extra=["--apply"]) == 0
    results.append(("CONTROL in-sync", 0, _run(db, cfg, f), None))
    results[-1] = results[-1][:3] + (results[-1][2] == 0,)
    for fn, exp, name in [(m_delete, 1, "tracker issue deleted"), (m_title, 1, "title edited"), (m_close, 1, "open item's issue closed"),
                          (m_reopen_closed, 1, "closed item's issue reopened"), (m_dup, 1, "duplicate key"), (m_footer, 1, "hidden footer stripped"),
                          (m_corrupt_hash, 1, "footer hash corrupted"), (m_db_status, 1, "DB status change without sync"), (m_orphan, 1, "keyed issue with no item"),
                          (m_label, 1, "labels stripped"), (m_canary, 2, "redaction canary in description (hard stop, never a pass)")]:
        scenario(fn, exp, name, results)
    # private owner -> public target must be refused and never a pass
    f2, db2 = FakeGitHub(private=False), mkdb(ROWS)
    results.append(("private owner mirrored to public tracker", 2, _run(db2, cfg, f2, owner="github.com/o/priv", target="github.com/o/pub"), None))
    results[-1] = results[-1][:3] + (results[-1][2] != 0 and f2.writes == 0,)
    # host answers 429 to everything -> could not determine, not a pass
    class Always429(FakeGitHub):
        def __call__(self, m, u, h, b): return 429, {}, None
    results.append(("host 429 for every call", 2, _run(db, cfg, Always429()), None)); results[-1] = results[-1][:3] + (results[-1][2] == 2,)
    # no token: unauthenticated private repo answers 404 -> repo-absent -> never a pass
    class NoAuth(FakeGitHub):
        def __call__(self, m, u, h, b): return 404, {}, None
    results.append(("token unset (repo invisible)", 2, _run(db, cfg, NoAuth()), None)); results[-1] = results[-1][:3] + (results[-1][2] == 2,)
    bad = 0
    for name, exp, rc, ok in results:
        print("%s %-55s expected rc %s got rc %s" % ("OK  " if ok else "FAIL", name, exp, rc))
        bad += 0 if ok else 1
    print("PROVE-FAILURE: %s (%d cases)" % ("PASS" if not bad else "FAIL", len(results)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
