#!/usr/bin/env python3
"""docs/qa/tracker_intake_2026_11_12_v5/tools/range_scan.py -- live scan for the id-range forms that
remint_ids.py does NOT read as ranges (class inventory R, "Open"): a range written across a line break,
an open-ended range ("up to P-n", "P-n onwards"), and two ids joined by a short sign or one or two words
outside the read set. The planner reads text line by line, so a range split over two lines is rewritten
id by id; a connector outside the read set is a list to it. The scan cannot tell a range from prose: it
prints the connectors it found (a table of connector, hits, hits naming a moved id) for a reader to judge,
and the cross-line, open-ended and sign-joined hits that name a moved id (the first 15 of each kind
per source, then a count of the rest).

usage: range_scan.py --prefix P [--moved LO..HI] [--files-from LIST] [--db NAME=PATH ...]
  --moved       the ids a landing moves (for example CON-299..CON-342); every hit that names one of
                them is counted apart (`*_moved`) and listed in full: those are the hits a re-mint
                would rewrite id by id instead of as a range
  --files-from  a file of repository-relative paths (one per line; `git ls-files` output), read from
                the current directory; files that are not UTF-8 text are counted and skipped
  --db          a tracker database to scan (every TEXT value of every table), opened read-only through
                a quoted URI; NAME labels it in the output
The scanner is written apart from remint_ids.py (its own patterns), so it does not share a blind spot
with the code it audits. Before it reads any source it runs control needles on fixed strings: each form
it claims to find must be found, and a plain list must not be reported (exit 3 when a needle fails).
Output: one block per source, then `RESULT: sources=N cross_line=N unlisted_pairs=N open_forms=N
cross_line_moved=N unlisted_pairs_moved=N open_forms_moved=N` (the `_moved` counts only with --moved).
Exit: 0 the scan ran (read the counts); 2 usage; 3 a control needle failed or a source was unreadable.
Evidence class: gate-logic only (section 11.4.289).
"""
import argparse
import os
import re
import sqlite3
import sys
import urllib.parse

DASH = "\u2010-\u2015\u2212\u2e3a\u2e3b\ufe58\ufe63\uff0d"
# the connectors remint_ids.py reads as a range (loose_patterns and id_patterns), written out again here
READ_SET = re.compile(r"^\s*(?:\.{2,3}|…|[~\u301c" + DASH + r"]|-{1,2}|(?i:to|through|thru|till|until))\s*$")
LIST_SET = re.compile(r"^\s*(?:,|;|/|&|\+|(?i:and|or|,\s*and|,\s*or|and/or|vs\.?|versus))\s*$")


def patterns(prefix):
    p = re.escape(prefix)
    ident = r"(?<![\w-])" + p + r"-[0-9]+\b(?!-)"
    # the read connectors; `and` only after `between` (a plain `P-a and P-b` is a list)
    conn = r"(?:\.{2,3}|…|[~\u301c" + DASH + r"]|-{1,2}|(?i:to|through|thru|till|until))"
    cross = re.compile(ident + r"[ \t]*" + conn + r"[ \t]*\n[ \t]*" + ident + "|" + ident + r"[ \t]*\n[ \t]*"
                       + conn + r"[ \t]*" + ident + r"|(?i:\bbetween)\s+" + ident + r"(?:[ \t]*\n[ \t]*(?i:and)"
                       r"|[ \t]+(?i:and)[ \t]*\n)[ \t]*" + ident)
    # two ids on one line joined by a short sign (1..4 characters, no letter or digit) or by one or two
    # words; no third id, no sentence end between them
    pair = re.compile("(" + ident + r")(\s*[^\w\s.;:()\[\]]{1,4}\s*|\s+[^\W\d_]{1,12}(?:\s+[^\W\d_]{1,12})?\s+)(?=("
                      + ident + "))")
    # an open-ended range: one id and a word for "and everything after (or before) it"
    opened = re.compile(r"(?i:\bup\s+to|\bstarting\s+(?:at|from))\s+" + ident + r"|" + ident
                        + r"\s+(?i:onwards?|and\s+(?:up|above|later|beyond)|or\s+later)\b")
    return cross, pair, opened


def scan_text(text, pats):
    cross, pair, opened = pats
    found = {"cross_line": [], "unlisted": [], "open_forms": []}
    for m in cross.finditer(text):
        found["cross_line"].append(m.group(0))
    for m in pair.finditer(text):
        mid = m.group(2)
        if READ_SET.match(mid) or LIST_SET.match(mid):
            continue
        if re.search(r"\b(?i:between)\s+$", text[max(0, m.start() - 12):m.start()]) and re.match(r"^\s+(?i:and)\s+$", mid):
            continue
        found["unlisted"].append((mid.strip().lower(), m.group(1) + mid + m.group(3)))
    for m in opened.finditer(text):
        found["open_forms"].append(m.group(0))
    return found


def selfcheck(pats):
    must = {
        "cross_line": ["CON-001 ..\nCON-004", "CON-001\nto CON-004", "CON-001 –\nCON-004",
                       "between CON-001\nand CON-004", "between CON-001 and\nCON-004"],
        "unlisted": ["CON-001 up through CON-004", "CON-001 -> CON-004", "CON-001 \u2192 CON-004"],
        "open_forms": ["up to CON-004", "CON-004 onwards", "starting at CON-004", "CON-004 or later"],
    }
    for kind, texts in must.items():
        for t in texts:
            if not scan_text(t, pats)[kind]:
                return "needle %r not reported as %s" % (t, kind)
    for t in ("CON-001 and CON-004", "CON-001, CON-004", "CON-001..CON-004", "CON-001 to CON-004", "from CON-004",
              "between CON-001 and CON-004", "CON-001\n\nCON-004", "CON-001 or CON-004", "CON-001 and\nCON-004"):
        f = scan_text(t, pats)
        if any(f.values()):
            return "plain text %r reported: %r" % (t, f)
    return ""


def names_moved(s, prefix, moved):
    if moved is None:
        return False
    lo, hi = moved
    return any(lo <= int(d) <= hi for d in re.findall(r"(?<![\w-])" + re.escape(prefix) + r"-([0-9]+)\b", s))


def label(where, k, s):
    """a hit with its location: `where: text` (an unlisted pair keeps its connector beside it)"""
    return (s[0], "%s: %s" % (where, s[1])) if k == "unlisted" else "%s: %s" % (where, s)


def hit_text(k, s):
    return s[1] if k == "unlisted" else s


def report(name, found, out, prefix, moved):
    n = {k: len(v) for k, v in found.items()}
    for k in list(found):
        n[k + "_moved"] = sum(1 for s in found[k] if names_moved(hit_text(k, s).split(": ", 1)[-1], prefix, moved))
    out.append("source %s: cross_line=%d unlisted_pairs=%d open_forms=%d cross_line_moved=%d "
               "unlisted_pairs_moved=%d open_forms_moved=%d" % (
                   name, n["cross_line"], n["unlisted"], n["open_forms"], n["cross_line_moved"],
                   n["unlisted_moved"], n["open_forms_moved"]))
    table = {}
    for conn, s in found["unlisted"]:
        hits, mv = table.get(conn, (0, 0))
        table[conn] = (hits + 1, mv + (1 if names_moved(s.split(": ", 1)[-1], prefix, moved) else 0))
    out.append("  connectors outside the read set: %d distinct (connector, hits, hits naming a moved id; top 25)"
               % len(table))
    for conn, (hits, mv) in sorted(table.items(), key=lambda x: (-x[1][0], x[0]))[:25]:
        out.append("    %r %d %d" % (conn, hits, mv))
    for k in ("cross_line", "open_forms", "unlisted"):
        seen = {}
        for s in found[k]:
            if k == "unlisted" and re.search(r"\w", s[0]):
                continue  # word connectors: the table above; listed in full only for signs
            seen[hit_text(k, s)] = seen.get(hit_text(k, s), 0) + 1
        mv = sorted(x for x in seen if names_moved(x.split(": ", 1)[-1], prefix, moved))
        for s in mv[:15]:
            out.append("  %s NAMES A MOVED ID x%d: %r" % ("sign_pair" if k == "unlisted" else k, seen[s], s))
        if len(mv) > 15:
            out.append("  %s NAMES A MOVED ID: %d more distinct hits not listed" % (
                "sign_pair" if k == "unlisted" else k, len(mv) - 15))
    return n


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--prefix", required=True)
    ap.add_argument("--files-from", default="")
    ap.add_argument("--db", action="append", default=[])
    ap.add_argument("--moved", default="")
    a = ap.parse_args(argv)
    if not re.fullmatch(r"[A-Z]{2,}", a.prefix):
        print("usage: --prefix must be capital ASCII letters", file=sys.stderr)
        return 2
    moved = None
    if a.moved:
        mm = re.fullmatch(re.escape(a.prefix) + r"-([0-9]+)\.\." + re.escape(a.prefix) + r"-([0-9]+)", a.moved)
        if not mm or int(mm.group(1)) > int(mm.group(2)):
            print("usage: --moved P-lo..P-hi", file=sys.stderr)
            return 2
        moved = (int(mm.group(1)), int(mm.group(2)))
    if moved and not names_moved("x %s-%d y" % (a.prefix, moved[0]), a.prefix, moved):
        print("BLIND: control needle failed: the moved-id reader misses the first moved id")
        return 3
    pats = patterns(a.prefix)
    bad = selfcheck(pats)
    if bad:
        print("BLIND: control needle failed: " + bad)
        return 3
    print("control needles: PASS (every claimed form found; plain lists and read ranges not reported)")
    keys = ("cross_line", "unlisted", "open_forms", "cross_line_moved", "unlisted_moved", "open_forms_moved")
    out, total = [], {k: 0 for k in keys}
    sources = 0
    if a.files_from:
        agg = {"cross_line": [], "unlisted": [], "open_forms": []}
        nfiles = skipped = 0
        with open(a.files_from, encoding="utf-8") as f:
            paths = [x.rstrip("\n") for x in f if x.strip()]
        for path in paths:
            if not os.path.isfile(path):
                continue
            try:
                with open(path, encoding="utf-8") as g:
                    text = g.read()
            except (UnicodeDecodeError, OSError):
                skipped += 1
                continue
            nfiles += 1
            for k, v in scan_text(text, pats).items():
                agg[k] += [label(path, k, s) for s in v]
        n = report("tracked-files (%d read, %d not UTF-8 text)" % (nfiles, skipped), agg, out, a.prefix, moved)
        sources += 1
        for k in total:
            total[k] += n[k]
    for spec in a.db:
        if "=" not in spec:
            print("usage: --db NAME=PATH", file=sys.stderr)
            return 2
        name, path = spec.split("=", 1)
        if os.path.exists(path + "-wal") and os.path.getsize(path + "-wal") > 0:
            print("BLIND: %s-wal is not empty" % path)
            return 3
        try:
            con = sqlite3.connect("file:%s?mode=ro" % urllib.parse.quote(os.path.abspath(path)), uri=True)
            agg = {"cross_line": [], "unlisted": [], "open_forms": []}
            values = 0
            tables = [r[0] for r in con.execute("select name from sqlite_master where type='table'")]
            for t in tables:
                cols = [r[1] for r in con.execute('pragma table_info("%s")' % t.replace('"', '""'))]
                for row in con.execute('select * from "%s"' % t.replace('"', '""')):
                    for c, v in zip(cols, row):
                        if isinstance(v, str):
                            values += 1
                            for k, hits in scan_text(v, pats).items():
                                agg[k] += [label("%s.%s" % (t, c), k, s) for s in hits]
            con.close()
        except sqlite3.Error as e:
            print("BLIND: %s unreadable: %s" % (name, e))
            return 3
        if values == 0:
            print("BLIND: %s holds no text value" % name)
            return 3
        n = report("db %s (%d text values)" % (name, values), agg, out, a.prefix, moved)
        sources += 1
        for k in total:
            total[k] += n[k]
    print("\n".join(out))
    print("RESULT: sources=%d cross_line=%d unlisted_pairs=%d open_forms=%d" % (
        sources, total["cross_line"], total["unlisted"], total["open_forms"])
          + ("" if moved is None else " cross_line_moved=%d unlisted_pairs_moved=%d open_forms_moved=%d" % (
              total["cross_line_moved"], total["unlisted_moved"], total["open_forms_moved"])))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
