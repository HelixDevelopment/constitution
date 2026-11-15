#!/usr/bin/env python3
"""docs/qa/tracker_intake_2026_11_14_v6/tools/leak_scan.py -- scan the lines a change adds for secret
shapes and for the host's identity (home directory and user name), so the published change carries
neither (section 11.4.10, and the lint's EPHEMERAL rule applied to the change itself).

usage: leak_scan.py [--diff BASE] [--file PATH ...] [--db NAME=PATH ...]
  --diff BASE   the added lines of `git diff --cached BASE` (staged changes; binary files are skipped
                and counted), read from the current directory
  --file PATH   every line of PATH (for files outside the diff)
  --db          every TEXT value of every table of a tracker database, opened read-only through a quoted
                URI; with --db-base NAME=PATH the values that already hold the same hit in the base
                database are counted apart as pre-existing
  The secret kinds are this file's own list plus every SECRET pattern of scripts/workable-items/intake_lint.py
  (kind "lint:<name>", loaded from the lint at run time, so the two scans read one class; round 6, R5-3);
  the lint's own positive needles must each be found before any source is read.
  The identity needles come from $HOME at run time (its last component is the user name); they are
  never written into this file or its output. A hit prints its source, line or row, kind and length,
  never the matched text: secret kinds print the first six characters only, identity kinds print
  nothing of the match.
Before any source is read the scan runs control needles: one fake string of each kind must be found,
and a plain line must not be.
Output: one `HIT` line per hit, then `RESULT: secret_hits=N identity_hits=N pre_existing=N
binary_skipped=N`. Exit: 0 the scan ran (read the hits: a hit is a lead, the line is the finding);
2 usage; 3 a control needle failed or a source was unreadable.
Evidence class: gate-logic only (section 11.4.289).
"""
import argparse
import os
import re
import sqlite3
import subprocess
import sys
import urllib.parse
import importlib.util

LINT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "..", "scripts", "workable-items",
                    "intake_lint.py")


def lint_kinds():
    """The lint's SECRET patterns and positive needles; None when the lint cannot be loaded."""
    try:
        sp = importlib.util.spec_from_file_location("intake_lint_for_leak_scan", LINT)
        m = importlib.util.module_from_spec(sp)
        sp.loader.exec_module(m)
        return [("lint:" + n, rx) for n, rx in m.SECRET_PATTERNS], [("lint:" + n, pos) for n, pos, _ in m.secret_needles()]
    except Exception:  # any load failure is a blind scan, reported by the caller
        return None

SECRET = [
    ("private-key", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    ("aws-key-id", re.compile(r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b")),
    ("github-token", re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})")),
    ("api-key-sk", re.compile(r"\bsk-(?:ant-)?[A-Za-z0-9_-]{20,}")),
    ("slack-token", re.compile(r"\bxox[abprs]-[A-Za-z0-9-]{10,}")),
    ("google-api-key", re.compile(r"\bAIza[0-9A-Za-z_-]{35}\b")),
    ("url-cred", re.compile(r"\b[a-z][a-z0-9+.-]*://[^\s/:@'\"]+:[^\s/@'\"]+@")),
    ("assignment", re.compile(r"(?i)\b(?:password|passwd|passphrase|secret|token|api[_-]?key)\b['\"]?\s*[:=]\s*['\"]?[^\s'\"]{6,}")),
    ("auth-header", re.compile(r"(?i)\bauthorization:\s*(?:basic|bearer)\s+[A-Za-z0-9+/=._-]{8,}")),
]


def identity():
    home = os.environ.get("HOME", "").rstrip("/")
    user = os.path.basename(home)
    if not home or not user or len(user) < 3:
        return None
    return [("home-path", re.compile(re.escape(home))),
            ("home-fragment", re.compile(re.escape("-home-" + user))),
            ("user-name", re.compile(r"(?<![A-Za-z0-9])" + re.escape(user) + r"(?![A-Za-z0-9])"))]


def scan_line(text, kinds):
    for kind, rx in kinds:
        for m in rx.finditer(text):
            yield kind, m.group(0)


def needles(ident):
    # each fake value is split in two, so that this file is not a hit of its own scan
    fake = {
        "private-key": "-----BEGIN RSA PRIVATE " + "KEY-----",
        "aws-key-id": "AKIA" + "ABCDEFGHIJKLMNOP",
        "github-token": "ghp_" + "a" * 36,
        "api-key-sk": "sk-" + "b" * 24,
        "slack-token": "xoxb-" + "1" * 12,
        "google-api-key": "AIza" + "c" * 35,
        "url-cred": "https://user:" + "pass@example.invalid/x",
        "assignment": "PASS" + "WORD=fakevalue1",
        "assignment-json": "{\"pass" + "word\": \"fakevalue1\"}",
        "auth-header": "Authorization: Basic " + "Zm9vOmJhcg==",
    }
    for kind, text in fake.items():
        if kind.split("-json")[0] not in {k for k, _ in scan_line(text, SECRET)}:
            return "the fake %s was not found" % kind
    home = os.environ["HOME"].rstrip("/")
    user = os.path.basename(home)
    for kind, text in (("home-path", home + "/x"), ("home-fragment", "a-home-" + user + "-b"),
                       ("user-name", "by " + user + ".")):
        if kind not in {k for k, _ in scan_line(text, ident)}:
            return "the %s needle was not found" % kind
    if list(scan_line("a plain line with password and token words, no value", SECRET + ident)):
        return "a plain line was reported"
    return ""


def show(kind, match):
    if kind in ("home-path", "home-fragment", "user-name"):
        return "kind=%s" % kind
    return "kind=%s len=%d" % (kind, len(match))  # round-8 review N6: no character of the match


def db_values(path):
    wal = path + "-wal"
    if os.path.exists(wal) and os.path.getsize(wal) > 0:
        raise OSError("non-empty -wal sidecar")
    c = sqlite3.connect("file:%s?mode=ro" % urllib.parse.quote(os.path.abspath(path)), uri=True)
    out = []
    for (t,) in c.execute("select name from sqlite_master where type='table'"):
        cols = [r[1] for r in c.execute("pragma table_info(%s)" % t)]
        for row in c.execute("select rowid, * from %s" % t):
            for col, v in zip(cols, row[1:]):
                if isinstance(v, str):
                    out.append(("%s.%s rowid=%s" % (t, col, row[0]), v))
    return out


def main(argv):
    ap = argparse.ArgumentParser(add_help=True)
    ap.add_argument("--diff")
    ap.add_argument("--file", action="append", default=[])
    ap.add_argument("--db", action="append", default=[])
    ap.add_argument("--db-base", action="append", default=[])
    a = ap.parse_args(argv)
    if not (a.diff or a.file or a.db):
        ap.print_usage(sys.stderr)
        return 2
    ident = identity()
    if ident is None:
        print("control needle FAILED: $HOME gives no user name")
        return 3
    lk = lint_kinds()
    if lk is None:
        print("control needle FAILED: the lint's SECRET patterns could not be loaded from " + LINT)
        return 3
    SECRET.extend(k for k in lk[0] if k[0] not in {x for x, _ in SECRET})
    for kind, text in lk[1]:
        if kind not in {k for k, _ in scan_line(text, SECRET)}:
            print("control needle FAILED: the lint needle %s was not found" % kind)
            return 3
    bad = needles(ident)
    if bad:
        print("control needle FAILED: " + bad)
        return 3
    print("control needles: PASS (one fake of each of the %d secret kinds and the 3 identity kinds found; a plain line not reported)" % len(SECRET))
    kinds = SECRET + ident
    hits = {"secret": 0, "identity": 0, "pre": 0}
    binary = 0

    def report(src, where, text, base_text=None):
        seen = set()  # one hit per matched text: the lint's patterns overlap this file's own kinds
        for kind, m in scan_line(text, kinds):
            if m in seen:
                continue
            seen.add(m)
            if base_text is not None and m in base_text:
                hits["pre"] += 1
                continue
            hits["identity" if kind in ("home-path", "home-fragment", "user-name") else "secret"] += 1
            print("HIT %s %s %s" % (src, where, show(kind, m)))

    if a.diff:
        try:
            d = subprocess.run(["git", "diff", "--cached", "--no-color", "-U0", a.diff], capture_output=True,
                               text=True, check=True).stdout
        except (OSError, subprocess.CalledProcessError) as e:
            print("BLIND: git diff: %s" % e)
            return 3
        f, n = "?", 0
        for ln in d.splitlines():
            if ln.startswith("+++ "):
                f = ln[6:] if ln.startswith("+++ b/") else ln[4:]
            elif ln.startswith("@@"):
                m = re.search(r"\+(\d+)", ln)
                n = int(m.group(1)) if m else 0
            elif ln.startswith("Binary files "):
                binary += 1
            elif ln.startswith("+") and not ln.startswith("+++"):
                report(f, "line=%d" % n, ln[1:])
                n += 1
    for p in a.file:
        try:
            for i, ln in enumerate(open(p, encoding="utf-8", errors="replace"), 1):
                report(p, "line=%d" % i, ln)
        except OSError as e:
            print("BLIND: %s: %s" % (p, e))
            return 3
    base = {}
    for spec in a.db_base:
        _, p = spec.split("=", 1)
        try:
            for where, v in db_values(p):
                base.setdefault(where.split(" rowid=")[0], []).append(v)
        except (OSError, sqlite3.Error) as e:
            print("BLIND: %s: %s" % (spec, e))
            return 3
    for spec in a.db:
        name, p = spec.split("=", 1)
        try:
            vals = db_values(p)
        except (OSError, sqlite3.Error) as e:
            print("BLIND: %s: %s" % (spec, e))
            return 3
        for where, v in vals:
            col = where.split(" rowid=")[0]
            report(name, where, v, "\n".join(base.get(col, [])) if a.db_base else None)
    print("RESULT: secret_hits=%d identity_hits=%d pre_existing=%d binary_skipped=%d"
          % (hits["secret"], hits["identity"], hits["pre"], binary))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
