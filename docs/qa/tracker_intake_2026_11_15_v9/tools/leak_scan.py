#!/usr/bin/env python3
"""docs/qa/tracker_intake_2026_11_15_v9/tools/leak_scan.py -- scan the lines a change adds for credential
shapes and for the host's identity (home directory and user name), so the published change carries
neither (section 11.4.10, and the lint's EPHEMERAL rule applied to the change itself).

Round 9 (review r9 F1): the scan reads the same widened class as the lint (key words with a qualifier or a
suffix, string prefixes, joined literals, HTML entities, octal escapes, repeated percent layers, marks and
invisible characters inside a word, Latin lookalikes), each written here again in its own way.
A token or secret word with a qualifier glued before it (PGid_token) takes a value of letters only, and a
long password word may have one letter replaced by any letter or any non-ASCII character (pass\u03adord read
as pass-e-ord after the fold).

Round 8 (review N2): this scan is a SECOND, INDEPENDENT implementation. It imports nothing from
scripts/workable-items/intake_lint.py; its only link to the lint is the shared fixture list
tests/workable_items/secret_shape_fixtures.py, which leak_scan_test.py runs through both. The lint
extracts key/value pairs per syntax; this scan reads a window of tokens after a credential word, so a
shape one of them cannot see shows up as a failure of that one's test, not as two agreeing nulls.

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
a pgpass line, and a token window after a credential word (password, passwd, passphrase, pwd, pass,
secret, token, api key, auth, credential): the first token that is not a filler word is the candidate
value, and it is a hit when it is at least 8 characters, holds a letter and a digit or a special
character, and is not a reference, mask, placeholder or path.
Output: one `HIT` line per hit with source, line or row, kind and length; NEVER any character of the
match (round 8, review N6). Then `RESULT: secret_hits=N identity_hits=N pre_existing=N binary_skipped=N`.
Before any source is read the scan runs its control needles (one per kind must be found, a plain line must
not be). Exit: 0 the scan ran (a hit is a lead, the line is the finding); 2 usage; 3 a control needle
failed or a source was unreadable.
Evidence class: gate-logic only (section 11.4.289).
"""
import argparse
import html
import os
import re
import sqlite3
import subprocess
import sys
import unicodedata
import urllib.parse

# lookalike letters folded to Latin (an own table; the lint keeps its own)
FOLD = {
    "а": "a", "е": "e", "о": "o", "р": "p", "с": "c", "у": "y", "х": "x",
    "і": "i", "ѕ": "s", "ј": "j", "А": "A", "В": "B", "Е": "E", "К": "K",
    "М": "M", "Н": "H", "О": "O", "Р": "P", "С": "C", "Т": "T", "Х": "X",
    "ο": "o", "α": "a", "ρ": "p", "ε": "e", "ι": "i", "κ": "k", "ν": "v",
    "Ο": "O", "Α": "A", "Ρ": "P", "Ε": "E", "Τ": "T", "Ι": "I", "Κ": "K",
}


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
        if s[1] == "u":
            try:
                return chr(int(s[2:], 16))
            except ValueError:
                return s
        if s[1:].isdigit():
            return chr(int(s[1:], 8))
        return {"n": "\n", "t": "\t", "r": "\r"}.get(s[1], s[1])
    return re.sub(r"\\u[0-9A-Fa-f]{4}|\\[0-7]{3}|\\.", rep, t)


def join_literals(t):
    # "ab" "cd", "ab" + "cd", 'ab' . 'cd' read as one literal
    return re.sub(r"""(?<=[^\s"'])(["'])\s*[+.]?\s*\1(?=[^\s"',;])""", "", t)


def views(text):
    out = [clean(text)]
    layer = list(out)
    for _ in range(3):
        nxt = []
        for b in layer:
            for v in (unescape(b), urllib.parse.unquote(b), html.unescape(b), join_literals(b)):
                v = clean(v)
                if v not in out and len(out) < 24:
                    out.append(v)
                    nxt.append(v)
        layer = nxt
    return out


# one letter may stand in a long credential word: a lookalike no fold knows (non-ASCII), or a Latin letter
# a fold produced from a letter with a diacritic (Greek epsilon with tonos -> e)
def _one_odd(word):
    return "|".join(word[:i] + "(?:[^\\W\\d_]|[^\\x00-\\x7f])" + word[i + 1:] for i in range(len(word)))


WORD = re.compile(r"(?i)(pass(?:word|wd|phrase)?|passwort|kennwort|pwd|secret|token|api[ _-]?key|apikey|auth|"
                  r"credentials?|(?:signing|sign|encryption|encrypt|master|account|private|access|client|"
                  r"shared|session|hmac|jwt|aes|storage)[ _-]?key|identified\s+by|"
                  + _one_odd("password") + "|" + _one_odd("passwd") +
                  r"|(?<![A-Za-z])(?:key|pin|session|sid|cookie)(?![A-Za-z]))")
FILLER = {"value", "key", "name", "is", "the", "of", "id", "string", "str", "env", "word", "phrase", "wd",
          "hash", "-", "+", "|", ">", "=", ":", "default"}
QUOTED = re.compile(r"""^["'`\\]{0,2}\s*(?:=>|[:=,])\s*(?:[bBrRuUfF]{1,2})?\\?(["'`])((?:\\.|(?!\1)[^\n\\])*)\\?\1""")
DELIM = re.compile(r"[\s\"'`=:,;<>()\[\]{}|]+")
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


def window_hits(t):
    for m in WORD.finditer(t):
        rest = t[m.end():m.end() + 80]
        rest = re.sub(r"^\w*", "", rest)  # the rest of the key word (secretKey, password2, a lookalike letter)
        # a long value of letters only (a base64 key) counts after a qualified key or a password word
        strong = not re.fullmatch(r"(?i)secret|token|auth|pwd|pass|key|pin|session|sid|cookie", m.group(1))
        # a token or secret word with a qualifier word glued before it (PGid_token, ID_TOKEN, sessionToken):
        # a named credential, so a value of letters only counts
        glued = (m.group(1).lower() in ("token", "secret")
                 and re.search(r"[A-Za-z]{2,}[_.-]?$", t[max(0, m.start() - 40):m.start()]) is not None)
        q = QUOTED.match(rest)
        if q:  # a quoted value is read whole: quotes of the other kind, escapes and spaces stay inside
            inner = q.group(2)
            if value_ok(re.sub(r"\s+", "", inner), letters_ok=True):
                yield "credential-window", inner
                continue
        n = 0
        for tok in DELIM.split(rest):
            if not tok:
                continue
            if tok.lower() in FILLER:
                continue
            n += 1
            if m.group(1).lower() == "pin":
                if re.fullmatch(r"\d{4,12}", tok):
                    yield "credential-window", tok
                break
            if value_ok(tok) or (glued and value_ok(tok, letters_ok=True)) or (strong and re.fullmatch(r"[A-Za-z0-9+/]{16,}", tok) and not tok.islower() and not tok.isupper()):
                yield "credential-window", tok
            break


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
TOOL_ARG = re.compile(r"\bhtpasswd\s+-\w*b\w*\s+\S+\s+\S+\s+(\S+)|(?<![\w-])-pass(?:in|out)?\s+pass:(\S+)|"
                      r"\bsmbclient\b.*?\s-U\s+[^\s%]+%(\S+)")
PGPASS = re.compile(r"(?m)^[^:\s]+:(?:\d+|\*):[^:\s]+:[^:\s]+:(\S+)$")


def scan_line(text):
    seen = set()
    for t in views(text):
        found = []
        for kind, rx in VENDOR:
            found += [(kind, m.group(0)) for m in rx.finditer(t)]
        for m in URL.finditer(t):
            pw = m.group(2)
            if len(pw) >= 6 and not pw.startswith(("$", "{")) and not re.fullmatch(r"(?i)x+|\*+|port", pw):
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
        found += list(window_hits(t))
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
        "credential-window": "pass​" + "word＝" + v,
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
            d = subprocess.run(["git", "diff", "--cached", "--no-color", "-U0", a.diff], capture_output=True,
                               text=True, check=True).stdout
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
