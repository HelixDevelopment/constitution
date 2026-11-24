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
from .tests_support import FakeGitHub, FakeGitLab, mkdb, cfgfile, applycfg, PROVEN

ROWS = [("A-1", "Bug", "Queued", "first", "High", "first description text here ok", "Q", "B", "Issues"),
        ("A-2", "Task", "Completed (→ Fixed.md)", "second", "", "second description text here ok", None, None, "Fixed"),
        ("A-3", "Feature", "Obsolete (→ Fixed.md)", "third", "", "third description text here ok", None, None, "Fixed")]


def _run(db, cfg, f, owner="github.com/o/r", target="github.com/o/r", cmd="verify", extra=()):
    out = io.StringIO()
    rc = cli.run([cmd, "--db", db, "--config", cfg, "--target", target, "--owner-repo", owner, *extra], proven_hosts=PROVEN, transport_factory=lambda v, h: f, out=out)
    return rc


def scenario(mutate, expect, name, results):
    f, db = FakeGitHub(), mkdb(ROWS)
    cfg = applycfg()
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
    cfg = applycfg()
    assert _run(db, cfg, f, cmd="apply", extra=["--apply"]) == 0
    results.append(("CONTROL in-sync", 0, _run(db, cfg, f), None))
    results[-1] = results[-1][:3] + (results[-1][2] == 0,)
    for fn, exp, name in [(m_delete, 1, "tracker issue deleted"), (m_title, 1, "title edited"), (m_close, 1, "open item's issue closed"),
                          (m_reopen_closed, 1, "closed item's issue reopened"), (m_dup, 1, "duplicate key"), (m_footer, 1, "hidden footer stripped"),
                          (m_corrupt_hash, 1, "footer hash corrupted"), (m_db_status, 1, "DB status change without sync"), (m_orphan, 1, "keyed issue with no item"),
                          (m_label, 1, "labels stripped"), (m_canary, 2, "redaction canary in description (hard stop, never a pass)")]:
        scenario(fn, exp, name, results)
    # visibility/ownership cases run the REAL apply path against two doubles (GitHub owner, GitLab mirror) with DIFFERENT per-repo visibility;
    # the case passes only when the verdict is the expected rc, NO double saw a write and the report names the expected reason.
    def two_hosts(name, owner, target, gh, gl, reason, proven=PROVEN, cmd="apply", extra=("--apply",), conf=None):
        out = io.StringIO()
        rc = cli.run([cmd, "--db", mkdb(ROWS), "--config", conf or applycfg(), "--target", target, "--owner-repo", owner, *extra], proven_hosts=proven,
                     transport_factory=lambda v, h: gl if h == "gitlab.com" else gh, out=out)
        ok = rc == 2 and gh.writes == 0 and gl.writes == 0 and reason in out.getvalue()
        results.append((name, 2, rc, ok))
    two_hosts("private owner mirrored to PUBLIC tracker (same repo name)", "github.com/o/r", "gitlab.com/o/r", FakeGitHub(private=True), FakeGitLab("public"), "private-to-public")
    two_hosts("owner mirrored to a DIFFERENT repo (both public)", "github.com/o/r", "gitlab.com/o/other", FakeGitHub(private=False), FakeGitLab("public"), "not-owning-repo")
    two_hosts("target visibility undetermined", "github.com/o/r", "gitlab.com/o/r", FakeGitHub(private=False), FakeGitLab(None), "visibility-undetermined")
    two_hosts("private owner to GitLab 'internal' tracker", "github.com/o/r", "gitlab.com/o/r", FakeGitHub(private=True), FakeGitLab("internal"), "visibility-undetermined")
    two_hosts("write verbs unproven (no host listed as proven)", "github.com/o/r", "gitlab.com/o/r", FakeGitHub(private=False), FakeGitLab("public"), "capability-unverified", proven=set())
    two_hosts("apply_decision names no tracked file", "github.com/o/r", "gitlab.com/o/r", FakeGitHub(private=False), FakeGitLab("public"), "apply refused",
              conf=cfgfile("enabled: true\nmode: apply\napply_decision: docs/NOPE.md\n"))
    # a DB without routing data and with several prefixes must route NOTHING (never the whole DB to the owner)
    rowsx = ROWS + [("WSP-1", "Task", "Queued", "priv", "", "private item description here ok", None, None, "Issues")]
    dbx = mkdb(rowsx); sqlite3.connect(dbx).execute("DROP TABLE sub_projects").connection.commit()
    fx = FakeGitHub(); rcx = cli.run(["apply", "--apply", "--db", dbx, "--config", cfg, "--target", "github.com/o/r", "--owner-repo", "github.com/o/r"],
                                     proven_hosts=PROVEN, transport_factory=lambda v, h: fx, out=io.StringIO())
    results.append(("routing data missing, several prefixes", 2, rcx, rcx == 2 and not fx.issues))
    # host answers 429 to everything -> could not determine, not a pass
    class Always429(FakeGitHub):
        def __call__(self, m, u, h, b): return 429, {}, None
    results.append(("host 429 for every call", 2, _run(db, cfg, Always429()), None)); results[-1] = results[-1][:3] + (results[-1][2] == 2,)
    # no token: unauthenticated private repo answers 404 -> repo-absent -> never a pass
    class NoAuth(FakeGitHub):
        def __call__(self, m, u, h, b): return 404, {}, None
    results.append(("token unset (repo invisible)", 2, _run(db, cfg, NoAuth()), None)); results[-1] = results[-1][:3] + (results[-1][2] == 2,)
    # a private-prefix item must never be written to the public owner's tracker (routing by sub_projects)
    rows3 = ROWS + [("WSP-1", "Task", "Queued", "priv", "", "private item description here ok", None, None, "Issues")]
    subs = [("WSP", "workshop", "owned", "operator", "git@github.com:o/workshop.git", "", "x")]
    f3, db3 = FakeGitHub(), mkdb(rows3, subs)
    _run(db3, cfg, f3, cmd="apply", extra=["--apply"])
    leaked = any("WSP-1" in i["title"] for i in f3.issues)
    results.append(("private-prefix item routed to public tracker", 0, 1 if leaked else 0, not leaked))
    bad = 0
    for name, exp, rc, ok in results:
        print("%s %-55s expected rc %s got rc %s" % ("OK  " if ok else "FAIL", name, exp, rc))
        bad += 0 if ok else 1
    print("PROVE-FAILURE: %s (%d cases)" % ("PASS" if not bad else "FAIL", len(results)))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
