#!/usr/bin/env python3
"""docs/qa/tracker_intake_2026_11_16_v11/tools/leak_scan.py -- scan the lines a change adds for credential
shapes and for the host's identity (home directory and user name), so the published change carries
neither (section 11.4.10, and the lint's EPHEMERAL rule applied to the change itself).

Round 11 (review r10, structural): the keyword reading moved into ONE shared module,
scripts/workable-items/secret_canon.py, also used by the lint (one rule set, so the two readers can no
longer disagree on a key). The round-10 token window (window_hits) is gone: it matched a keyword as a
substring of another word (bypass=..., secretary=... were reported) and missed shapes the lint read. This
scan keeps its OWN value-shape detectors that need no key word (vendor token formats, private-key
armour, URL user-info, a tool's short flag, pgpass lines, a set statement), read through its own
decoding (views()), so a shape that carries its own evidence is still read by code independent of the
lint. The shared module is loaded by path (LEAK_SCAN_CANON overrides it; mutants pass a copy); if it
cannot be loaded the scan is BLIND (exit 3).

Rounds 8 to 10 history: docs/qa/tracker_intake_2026_11_16_v10/tools/leak_scan.py.

usage: leak_scan.py [--diff BASE] [--file PATH ...] [--db NAME=PATH ...] [--db-base NAME=PATH ...]
  --diff BASE   the added lines of `git diff --cached BASE` (binary files are skipped and counted)
  --file PATH   every line of PATH
  --db          every TEXT value of every table of a tracker database, opened read-only through a quoted
                URI; with --db-base the values that already hold the same hit in the base are counted
                apart as pre-existing
How a line is read: the views of it (NFKD, then format characters, marks and invisible fillers removed, then
NFKC, Cyrillic and Greek lookalikes and Latin letters by name folded to Latin; then, up to three layers
deep, backslash escapes decoded (octal too), percent-decoded, HTML entities decoded, adjacent string
literals joined). In each view: vendor token shapes, URL user-info, a tool's short flag (-p, -u user:pw),
a pgpass line, a set statement; and the shared keyword reading of secret_canon.py (its own decoding
and fold, words matched whole, the value after the key by layout, then the value's shape).
Output: one `HIT` line per hit with source, line or row, kind and length; NEVER any character of the
match (round 8, review N6). Then `RESULT: secret_hits=N identity_hits=N pre_existing=N binary_skipped=N`.
Before any source is read the scan runs its control needles (one per kind must be found, a plain line must
not be). Exit: 0 the scan ran (a hit is a lead, the line is the finding); 2 usage; 3 a control needle
failed or a source was unreadable.
Evidence class: gate-logic only (section 11.4.289).
"""
import argparse
import base64
import binascii
import html
import os
import re
import sqlite3
import subprocess
import sys
import unicodedata
import urllib.parse
import importlib.util as _ilu

# ambient git variables would redirect `git diff` to another repository (section 11.4.288 class census)
import os as _ge_os
for _ge_v in "GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX".split(): _ge_os.environ.pop(_ge_v, None)

_CANON_PATH = os.environ.get("LEAK_SCAN_CANON") or os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "..", "scripts", "workable-items", "secret_canon.py")


def _load_canon(path):
    try:
        spec = _ilu.spec_from_file_location("secret_canon_for_scan", path)
        mod = _ilu.module_from_spec(spec)
        spec.loader.exec_module(mod)
        return mod
    except (OSError, ImportError, AttributeError, SyntaxError):
        return None


CANON = _load_canon(_CANON_PATH)

# lookalike letters folded to Latin (an own table; the lint keeps its own)
FOLD = {
    "а": "a", "е": "e", "о": "o", "р": "p", "с": "c", "у": "y", "х": "x",
    "і": "i", "ѕ": "s", "ј": "j", "А": "A", "В": "B", "Е": "E", "К": "K",
    "М": "M", "Н": "H", "О": "O", "Р": "P", "С": "C", "Т": "T", "Х": "X",
    "ο": "o", "α": "a", "ρ": "p", "ε": "e", "ι": "i", "κ": "k", "ν": "v",
    "Ο": "O", "Α": "A", "Ρ": "P", "Ε": "E", "Τ": "T", "Ι": "I", "Κ": "K",
}


# round 10: confusable letters of other scripts (an own table, written from the Unicode names)
FOLD.update({
    "\u2c81": "a", "\u2c80": "A", "\u2c9f": "o", "\u2c9e": "O", "\u2ca3": "p", "\u2ca2": "P", "\u2ca5": "c",
    "\u2cb1": "w", "\u2cb0": "W", "\u2c93": "i", "\u2c95": "k", "\u2cad": "x",
    "\uab7a": "a", "\uabaa": "s", "\uabb2": "p", "\uab83": "w", "\uab71": "r", "\uab70": "d", "\uab72": "t",
    "\uab7c": "e", "\uab87": "m", "\uabb6": "k", "\uabae": "l", "\uaba9": "v", "\uab93": "z",
    "\u13aa": "A", "\u13da": "S", "\u13e2": "P", "\u13b3": "W", "\u13a1": "R", "\u13a0": "D", "\u13a2": "T",
    "\u0585": "o", "\u0555": "O", "\u057d": "u", "\u0578": "n", "\u0570": "h", "\u0581": "g", "\u0566": "q",
    "\ua4ee": "A", "\ua4e2": "S", "\ua4d1": "P", "\ua4ea": "W", "\ua4f3": "O", "\ua4e3": "R", "\ua4d3": "D",
    "\u0461": "w", "\u0460": "W", "\u051c": "W", "\u051d": "w", "\u04cf": "l",
})
INVISIBLE = set("\u115f\u1160\u3164\uffa0\u17b4\u17b5")
LATIN_BY_NAME = re.compile(r"LATIN (?:SMALL |CAPITAL )?LETTER (?:SMALL CAPITAL )?(ALPHA|[A-Z])\b")


def latin(ch):
    m = LATIN_BY_NAME.match(unicodedata.name(ch, ""))
    if not m:
        return ch
    return "a" if m.group(1) == "ALPHA" else m.group(1).lower()


def clean(text):
    t = unicodedata.normalize("NFKD", text)
    t = "".join(ch for ch in t if unicodedata.category(ch) not in ("Cf", "Mn", "Me") and ch not in INVISIBLE)
    t = unicodedata.normalize("NFKC", t)
    t = "".join(FOLD.get(ch, ch) for ch in t)
    return "".join(ch if ch.isascii() else latin(ch) for ch in t)


def unescape(t):
    def rep(m):
        s = m.group(0)
        if s[1] in "uUx" and len(s) > 2:
            try:
                n = int(s[2:].strip("{}"), 16)
            except ValueError:
                return s
            return chr(n) if n <= 0x10FFFF else s
        if s[1:].isdigit():
            return chr(int(s[1:], 8))
        return {"n": "\n", "t": "\t", "r": "\r"}.get(s[1], s[1])
    return re.sub(r"\\[ux]\{[0-9A-Fa-f]{1,6}\}|\\U[0-9A-Fa-f]{8}|\\u[0-9A-Fa-f]{4}|\\x[0-9A-Fa-f]{2}|\\[0-7]{3}|\\.",
                  rep, t)


def join_literals(t):
    # "ab" "cd", "ab" + "cd", 'ab' . 'cd', "ab" || "cd" (also across a newline) read as one literal;
    # triple quotes and a parenthesised literal read as one quoted literal
    t = re.sub(r"(\"\"\"|''')(.*?)\1", lambda m: m.group(1)[0] + m.group(2) + m.group(1)[0], t, flags=re.S)
    t = re.sub(r"""\(\s*(["'])""", r"\1", t)
    t = re.sub(r"""(["'])\s*\)""", r"\1", t)
    return re.sub(r"""(?<=[^\s"'])(["'])\s*(?:\+|\.\.?|\|\||&|~)?\s*\1(?=[^\s"',;])""", "", t)


def b64_runs(t):
    # a base64 run that decodes to printable text holding = or : is read decoded
    def dec(m):
        s = m.group(0)
        try:
            d = base64.b64decode(s + "=" * (-len(s) % 4), altchars=b"-_" if ("-" in s or "_" in s) else None,
                                 validate=True).decode("utf-8")
        except (binascii.Error, ValueError):
            return s
        return d if len(d) >= 8 and ("=" in d or ":" in d) and d.isprintable() else s
    return re.sub(r"(?<![\w+/=-])[A-Za-z0-9+/_-]{16,}={0,2}(?![\w+/=-])", dec, t)


def views(text):
    out = [clean(text)]
    # round 10: every decoding applied again until nothing changes (a layer of any depth). This replaced the
    # round-8 closure of three single-decoding layers: on every shared fixture row and on the round-9
    # reviewer probe the closure found nothing the fixpoint did not (docs/qa/tracker_intake_2026_11_16_v11/
    # class_inventory.md, B45), so its mutants could not be killed; each decoding in the loop is mutated instead
    t = out[0]
    for _ in range(64):
        before = t
        for f in (unescape, urllib.parse.unquote, html.unescape, join_literals, b64_runs):
            t = clean(f(t))
        if t == before:
            break
    if t not in out:
        out.append(t)
    return out


PLACEHOLDER = re.compile(r"(?i)^(?:changeme|example\w*|redacted|placeholder|none|null|nil|true|false|required|"
                         r"optional|secret|password|passwd|token|test|dummy|sample|todo|tbd|"
                         r"(?:your|my)[_-]\w*|\w*[_-]here|x{4,}|\*{4,}|\.{3,})$")
SPECIAL = set("!@#$%^&*+/~?\\")


def value_ok(tok, minlen=8, letters_ok=False):
    tok = tok.strip(".")
    if len(tok) < minlen or PLACEHOLDER.match(tok):
        return False
    if tok.startswith(("${", "$(", "{{", "%(", "<", "/", "~", "./", "../")):
        return False
    if re.fullmatch(r"\$[A-Z_][A-Z0-9_]*", tok) or re.fullmatch(r"[A-Z][A-Z0-9_]*", tok):
        return False  # a reference or an upper-case name, not a value
    if re.fullmatch(r"[A-Za-z_][\w.]*\(\)?", tok) or re.fullmatch(r"[a-z_]+(?:\.[A-Za-z_]+)+", tok):
        return False  # a call or a dotted name
    letter = any(c.isalpha() for c in tok)
    digit = any(c.isdigit() for c in tok)
    special = any(c in SPECIAL for c in tok)
    return letter and (digit or special or letters_ok)


VENDOR = [
    ("private-key", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    ("aws-key-id", re.compile(r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b")),
    ("github-token", re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})")),
    ("api-key-sk", re.compile(r"\bsk-(?:ant-)?[A-Za-z0-9_-]{20,}")),
    ("slack-token", re.compile(r"\bxox[abprs]-[A-Za-z0-9-]{10,}")),
    ("google-api-key", re.compile(r"\bAIza[0-9A-Za-z_-]{35}\b")),
    ("auth-header", re.compile(r"(?i)\bauthorization:\s*(?:basic|bearer)\s+[A-Za-z0-9+/=._-]{8,}")),
]
URL = re.compile(r"(?i)\b[a-z][a-z0-9+.-]*://([^\s/@:\[\]]*):([^\s/@]+)@")
SHORT_FLAG = re.compile(r"(?<![\w-])(-p|-u|--user|-a|-P)(?:\s|(?<=p))?(\S+)")
# htpasswd -b FILE USER PASSWORD, openssl -pass/-passin/-passout pass:PASSWORD, smbclient -U user%PASSWORD
SET_CMD = re.compile(r"(?im)(?:^|[;\[{])\s*set\s+\w*(?:pass\w*|secret|token|key)\w*\s+([^\s;\]}]+)")
TOOL_ARG = re.compile(r"\bhtpasswd\s+-\w*b\w*\s+\S+\s+\S+\s+(\S+)|(?<![\w-])-pass(?:in|out)?\s+pass:(\S+)|"
                      r"\bsmbclient\b.*?\s-U\s+[^\s%]+%(\S+)")
PGPASS = re.compile(r"(?m)^[^:\s]+:(?:\d+|\*):[^:\s]+:[^:\s]+:(\S+)$")


def scan_line(text):
    seen = set()
    # the shared keyword reading (it decodes and folds on its own); then this scan's own shape detectors
    for kind, s in CANON.hits(text):
        if (kind, s) not in seen:
            seen.add((kind, s))
            yield kind, s
    for t in views(text):
        found = []
        for kind, rx in VENDOR:
            found += [(kind, m.group(0)) for m in rx.finditer(t)]
        for m in URL.finditer(t):
            pw = m.group(2)
            # round 11: a placeholder (<password>, [x], your_x) is not a credential; the one placeholder
            # rule is the shared module's (the value shape stays this scan's own)
            if len(pw) >= 6 and not pw.startswith(("$", "{", "<", "[")) and not CANON.is_placeholder(pw) \
                    and not re.fullmatch(r"(?i)x+|\*+|port", pw):
                if not re.fullmatch(r"\d+/?.*", pw) or re.fullmatch(r"\d{6,}", pw):
                    found.append(("url-cred", pw))
        for m in SHORT_FLAG.finditer(t):
            v = m.group(2)
            if m.group(1) in ("-u", "--user"):
                v = v.split(":", 1)[1] if ":" in v else ""
            if value_ok(v):
                found.append(("short-flag", v))
        for m in TOOL_ARG.finditer(t):
            v = next(g for g in m.groups() if g is not None)
            if value_ok(v):
                found.append(("short-flag", v))
        found += [("pgpass", m.group(1)) for m in PGPASS.finditer(t) if value_ok(m.group(1))]
        found += [("set-command", m.group(1)) for m in SET_CMD.finditer(t) if value_ok(m.group(1))]
        for kind, s in found:
            if (kind, s) not in seen:
                seen.add((kind, s))
                yield kind, s


def identity():
    home = os.environ.get("HOME", "").rstrip("/")
    user = os.path.basename(home)
    if not home or not user or len(user) < 3:
        return None
    return [("home-path", re.compile(re.escape(home))),
            ("home-fragment", re.compile(re.escape("-home-" + user))),
            ("user-name", re.compile(r"(?<![A-Za-z0-9])" + re.escape(user) + r"(?![A-Za-z0-9])"))]


def ident_hits(text, ident):
    for kind, rx in ident:
        for m in rx.finditer(text):
            yield kind, m.group(0)


def needles(ident):
    # each fake value is split in two, so that this file is not a hit of its own scan
    v = "Zq7" + "Zq7Zq"
    fake = {
        "private-key": "-----BEGIN RSA PRIVATE " + "KEY-----",
        "aws-key-id": "AKIA" + "ABCDEFGHIJKLMNOP",
        "github-token": "ghp_" + "a" * 36,
        "api-key-sk": "sk-" + "b" * 24,
        "slack-token": "xoxb-" + "1" * 12,
        "google-api-key": "AIza" + "c" * 35,
        "auth-header": "Authorization: Basic " + "Zm9vOmJhcg==",
        "url-cred": "HTTPS://user:" + v + "@example.invalid/x",
        "short-flag": "mysql -p" + v + " db",
        "pgpass": "h:5432:db:u:" + v,
        "canonical-key": "pass​" + "word＝" + v,
    }
    for kind, text in fake.items():
        if kind not in {k for k, _ in scan_line(text)}:
            return "the fake %s was not found" % kind
    home = os.environ["HOME"].rstrip("/")
    user = os.path.basename(home)
    for kind, text in (("home-path", home + "/x"), ("home-fragment", "a-home-" + user + "-b"),
                       ("user-name", "by " + user + ".")):
        if kind not in {k for k, _ in ident_hits(text, ident)}:
            return "the %s needle was not found" % kind
    if list(scan_line("a plain line with password and token words, no value")) or \
            list(ident_hits("a plain line", ident)):
        return "a plain line was reported"
    return ""


def db_values(path):
    wal = path + "-wal"
    if os.path.exists(wal) and os.path.getsize(wal) > 0:
        raise OSError("non-empty -wal sidecar")
    c = sqlite3.connect("file:%s?mode=ro" % urllib.parse.quote(os.path.abspath(path)), uri=True)
    out = []
    for (t,) in c.execute("select name from sqlite_master where type='table'"):
        cols = [r[1] for r in c.execute("pragma table_info(\"%s\")" % t.replace('"', '""'))]
        for row in c.execute("select rowid, * from \"%s\"" % t.replace('"', '""')):
            for col, val in zip(cols, row[1:]):
                if isinstance(val, str):
                    out.append(("%s.%s rowid=%s" % (t, col, row[0]), val))
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
    if CANON is None:
        print("control needle FAILED: the shared module %s could not be loaded" % _CANON_PATH)
        return 3
    ident = identity()
    if ident is None:
        print("control needle FAILED: $HOME gives no user name")
        return 3
    bad = needles(ident)
    if bad:
        print("control needle FAILED: " + bad)
        return 3
    print("control needles: PASS (one fake of each of the 11 secret kinds and the 3 identity kinds found; "
          "a plain line not reported)")
    hits = {"secret": 0, "identity": 0, "pre": 0}
    binary = 0

    def report(src, where, text, base_text=None):
        seen = set()
        for kind, m in list(scan_line(text)) + list(ident_hits(text, ident)):
            if m in seen:
                continue
            seen.add(m)
            if base_text is not None and m in base_text:
                hits["pre"] += 1
                continue
            hits["identity" if kind in ("home-path", "home-fragment", "user-name") else "secret"] += 1
            print("HIT %s %s kind=%s len=%d" % (src, where, kind, len(m)))

    if a.diff:
        try:
            # bytes, decoded with replacement (round 11): a tracked file that is not UTF-8 made text=True
            # raise UnicodeDecodeError (exit 1, no RESULT line) on the merged tree; --file reads the same way
            d = subprocess.run(["git", "diff", "--cached", "--no-color", "-U0", a.diff], capture_output=True,
                               check=True).stdout.decode("utf-8", errors="replace")
        except (OSError, subprocess.CalledProcessError) as e:
            print("BLIND: git diff: %s" % type(e).__name__)
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
            with open(p, encoding="utf-8", errors="replace") as fh:
                for i, ln in enumerate(fh, 1):
                    report(p, "line=%d" % i, ln)
        except OSError as e:
            print("BLIND: %s: %s" % (p, type(e).__name__))
            return 3
    base = {}
    for spec in a.db_base:
        _, p = spec.split("=", 1)
        try:
            for where, v in db_values(p):
                base.setdefault(where.split(" rowid=")[0], []).append(v)
        except (OSError, sqlite3.Error) as e:
            print("BLIND: %s: %s" % (spec, type(e).__name__))
            return 3
    for spec in a.db:
        name, p = spec.split("=", 1)
        try:
            vals = db_values(p)
        except (OSError, sqlite3.Error) as e:
            print("BLIND: %s: %s" % (spec, type(e).__name__))
            return 3
        for where, v in vals:
            col = where.split(" rowid=")[0]
            report(name, where, v, "\n".join(base.get(col, [])) if a.db_base else None)
    print("RESULT: secret_hits=%d identity_hits=%d pre_existing=%d binary_skipped=%d"
          % (hits["secret"], hits["identity"], hits["pre"], binary))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
