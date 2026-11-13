#!/usr/bin/env python3
# scripts/workable-items/intake_lint.py -- read-only CONTENT lint for a set of workable items
# (an intake batch) in a workable-items SQLite database.
#
# Documentation (section 11.4.18): docs/guides/intake_lint_guide.md (user guide and manual).
#
# WHY  `workable-items validate` and `diff` prove the closed sets, the description floor and the
#   DB-to-Markdown sync. They do not read what a description SAYS. The independent reviews of the
#   2026-11-12 tracker-intake vehicle found wrong tracker facts that passed validate and diff: a
#   duplicate closed onto one of two open heads (section 11.4.214(0)), a cross-reference that named
#   an anchor number as if it were an item id, and data mutants (description and body diverge in
#   either direction, a dangling umbrella id, secret-shaped strings, a missing section header, a
#   state written in prose, a mktemp location). This lint checks those classes for a SELECTED set of
#   items, deterministically, and never writes.
#
# USAGE
#   python3 -I scripts/workable-items/intake_lint.py --db <db> (--origin <text> | --ids <A,B,..>)...
#           [--prefix CON] [--require-dup-check] [--repo-root DIR] [--skip-check CODES]
#           [--embeddings] [--no-selfcheck]
#   --origin TEXT    select every item whose description contains TEXT (repeatable)
#   --ids LIST       select these item ids (comma list, repeatable)
#   --prefix P       id prefix of this tracker (default: the most common prefix in the DB); a prefix
#                    that no item of the DB carries is BLIND (the id checks could not see)
#   --require-dup-check
#                    every selected item must carry a `Duplicate check (section 11.4.214):` line
#                    with a verdict from {DISTINCT, DISTINCT-but-similar, SAME-DEFECT, UNDECIDED}
#   --embeddings     print every id embedded in the selected items' text (own / foreign / main /
#                    unknown) as TSV and exit 0; for the lander's re-mint (section 11.4.214); the
#                    interior ids of a range `A..B` are listed too
#   --repo-root DIR  enable PATH-MISSING against this checkout
#   --skip-check C   comma list of finding codes not to report (repeatable; an unknown code is a
#                    usage error, also with --embeddings); a skipped code must be stated wherever
#                    the result is cited
#   --no-selfcheck   skip the built-in control needles (tests only; never in a gate)
#
# CHECKS (finding codes; each finding is one line `FINDING <code> <item> <detail>`)
#   XREF-DANGLING    an id of this tracker named in the text (a range `A..B` names every id in it)
#                    does not exist and is not declared foreign
#   XREF-LABEL       `<id> (<label>)`: no significant label word is in the target's title, or more
#                    than a third of the significant label words occur nowhere in the target's title
#                    or description
#   XREF-UNLABELLED  an id of another existing item written without a label, in a clause that shares
#                    no significant word with the target's title
#   FOREIGN-STALE    a `Foreign ids` line declares an id the rest of the text never names
#   STATE-PROSE      a closed reproduction/investigation state word in prose, or a hand-written
#                    `**Reproduction:**` / `**Investigation:**` line in the description, disagrees with
#                    the item's state column (section 11.4.294(A): the column is the source)
#   SECTIONS         a section 11.4.148 marker is missing (What, Affected scope, Reproduction /
#                    context, Acceptance criteria, Parent / links)
#   BODY-SYNC        body_md is not the engine rendering of the columns: empty, the description not
#                    in it, text before or after the rendered parts, a heading or header line that
#                    disagrees with the columns, or a header key outside the engine's set
#   SECRET           a credential-shaped string (pattern name printed, never the match; section 11.4.10)
#   EPHEMERAL        a session-scratchpad location, a /tmp path, a mktemp-shaped name, a .bundle file
#                    or a bare review_*.md / *_lander_items.md name (not under docs/) on a line with no
#                    `(ephemeral` note
#   SHARED-PATH      a file named in the item's Affected-scope section is named by an OPEN item outside
#                    the selection, and the Duplicate check line does not name that item
#   DUP-CHECK        (--require-dup-check) the line is missing or its verdict is outside the closed set;
#                    (always) a SAME-DEFECT verdict that names no id
#   DUP-SAME-OPEN    the verdict is SAME-DEFECT of X but the item is not Obsolete duplicate-of X
#   DUP-HEAD         the verdict is SAME-DEFECT of X but X is not a single surviving head: X is itself
#                    Obsolete, or X records an UNDECIDED candidate duplicate that is open (more than
#                    one distinct head: section 11.4.214(0) makes the verdict UNDECIDED)
#   DUP-UNDECIDED    the verdict is UNDECIDED but names no candidate id, or the item is closed
#   DUP-STATUS       the item is Obsolete duplicate-of but its verdict is not SAME-DEFECT
#   OBSOLETE-STALE   an obsolete_details row on an item that is not Obsolete, with no
#                    `Stale obsolete_details row (...)` note naming an existing open item
#   PATH-MISSING     (--repo-root) a cited docs/qa/ or docs/operator_decisions/ path does not exist
#
# EXIT  0 no finding; 1 findings; 2 usage error; 3 BLIND (database unreadable, empty selection, a
#   prefix no item carries, or a built-in control needle failed: the instrument could not see, so no
#   verdict is given).
# EVIDENCE CLASS  gate-logic only (section 11.4.289): it reads text, it does not prove an item true.
import argparse
import os
import re
import sqlite3
import sys

STOP = set(
    "the a an on in of to is and or for with by from not no as at be it its this that are was when "
    "into than then there their these those over under after again only also each every item items "
    "vehicle review issue issues sync same other another says said already whose must change changes "
    "class instance level different symptom related parent links both have here need needs "
    "owed which where while about against before being does done like more most much such some what "
    "they them will would should could".split()
)
REPRO_TOKENS = [
    "reproduced-live",
    "reproduced-host-fixture",
    "not-reproducible-with-evidence",
    "blocked-no-device-with-recorded-blocker",
    "blocked-no-device",
    "UNREPRODUCED",
]
INV_TOKENS = ["root-cause-found-with-evidence", "root-cause-unconfirmed", "closed-no-defect"]
INV_STATES = ["not-started", "in-progress"] + INV_TOKENS
UNREPRO_FAMILY = {"UNREPRODUCED", "not-reproducible-with-evidence", "blocked-no-device-with-recorded-blocker"}
SECTION_MARKERS = [
    ("What", re.compile(r"^\*\*What\b[^*]*:\*\*", re.M)),
    ("Affected scope", re.compile(r"^\*\*Affected scope / file-scope manifest:\*\*", re.M)),
    ("Reproduction / context", re.compile(r"^\*\*Reproduction / context:\*\*", re.M)),
    ("Acceptance criteria", re.compile(r"^\*\*Acceptance criteria:\*\*", re.M)),
    ("Parent / links", re.compile(r"^Parent / links:", re.M)),
]
# Credential shapes (section 11.4.10). The set matches the independent reviewer's 18-pattern scan of
# 2026-11-13; every member has a positive and a negative control needle in selfcheck().
SECRET_PATTERNS = [
    ("aws-access-key-id", re.compile(r"\b(?:AKIA|ASIA|AGPA|AIDA|AROA|ANPA)[0-9A-Z]{16}\b")),
    ("aws-secret-assign", re.compile(r"(?i)aws_?secret_?access_?key\s*[:=]\s*['\"]?[A-Za-z0-9/+]{40}")),
    ("github-token", re.compile(r"\bgh[pousr]_[A-Za-z0-9]{30,}\b")),
    ("github-fine-grained-pat", re.compile(r"\bgithub_pat_[A-Za-z0-9_]{30,}\b")),
    ("gitlab-pat", re.compile(r"\bglpat-[A-Za-z0-9_-]{20,}\b")),
    ("gitlab-other-token", re.compile(r"\bgl(?:dt|ptt|rt|soat|cbt|imt|agent)-[A-Za-z0-9_-]{20,}\b")),
    ("gcp-api-key", re.compile(r"\bAIza[0-9A-Za-z_-]{35}\b")),
    ("private-key-block", re.compile(r"-----BEGIN [A-Z0-9 ]*PRIVATE KEY( BLOCK)?-----")),
    ("huggingface-token", re.compile(r"\bhf_[A-Za-z0-9]{30,}\b")),
    ("jwt", re.compile(r"\beyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]+")),
    ("slack-token", re.compile(r"\bxox[abposre]-[A-Za-z0-9-]{10,}\b")),
    ("openai-anthropic-key", re.compile(r"\bsk-(?:ant-|proj-)?[A-Za-z0-9_-]{32,}\b")),
    ("url-userinfo-password", re.compile(r"[a-z][a-z0-9+.-]*://[^/\s:@]+:[^/\s@]{6,}@")),
    ("bearer-token", re.compile(r"(?i)authorization:\s*bearer\s+[A-Za-z0-9._~+/=-]{20,}")),
    ("password-assign", re.compile(r"(?i)\b(?:password|passwd|secret|api_?key|token)\s*[=:]\s*['\"][^'\"\s]{8,}['\"]")),
    ("stripe-key", re.compile(r"\b[rs]k_(?:live|test)_[A-Za-z0-9]{20,}\b")),
    ("npm-token", re.compile(r"\bnpm_[A-Za-z0-9]{36}\b")),
    ("telegram-bot-token", re.compile(r"\b\d{8,10}:AA[A-Za-z0-9_-]{33}\b")),
]
EPHEMERAL_PATTERNS = [
    ("scratchpad", re.compile(r"scratchpad|/\.cache/claude-tmp/", re.I)),
    ("tmp-path", re.compile(r"(?<![\w.-])/(?:var/)?tmp/[^\s,;)`'\"]+")),
    ("mktemp-default", re.compile(r"(?<![\w.-])tmp\.(?!X{10})[A-Za-z0-9]{10}(?![\w-])")),
    # a mktemp-style suffix: 4 to 12 letters and digits, mixed (an upper-case letter or a digit, and a
    # lower-case letter), or all lower-case when the name is a directory (followed by a slash)
    ("mktemp-dir", re.compile(
        r"(?<![\w/.-])[\w-]+\.(?:(?=[A-Za-z0-9]{0,11}[A-Z0-9])(?=[A-Za-z0-9]{0,11}[a-z])[A-Za-z0-9]{4,12}"
        r"(?=[/,;):\s]|$)|[a-z]{4,12}(?=/))")),
    ("bundle-file", re.compile(r"[\w./-]+\.bundle\b")),
    ("bare-review-file", re.compile(r"(?<![\w/.-])(?:review_[\w-]+\.(?:md|txt)|[\w-]+_lander_items\.md|review_[\w-]+_logs/)")),
]
CODES = {
    "XREF-DANGLING", "XREF-LABEL", "XREF-UNLABELLED", "FOREIGN-STALE", "STATE-PROSE", "SECTIONS",
    "BODY-SYNC", "SECRET", "EPHEMERAL", "SHARED-PATH", "DUP-CHECK", "DUP-SAME-OPEN", "DUP-HEAD",
    "DUP-UNDECIDED", "DUP-STATUS", "OBSOLETE-STALE", "PATH-MISSING",
}
DUP_LINE = re.compile(r"^Duplicate check \(section 11\.4\.214\):\s*(\S+)(.*)$", re.M)
DUP_VERDICTS = {"DISTINCT", "DISTINCT-but-similar", "SAME-DEFECT", "UNDECIDED"}
FOREIGN_LINE = re.compile(r"^Foreign ids\b[^:]*:(.*)$", re.M)
STALE_NOTE = re.compile(r"^Stale obsolete_details row \(([^)]*)\)", re.M)
EVIDENCE_PATH = re.compile(r"(?<![\w./-])(docs/(?:qa|operator_decisions)/[\w./-]*[\w/])")
PATH_IN_SCOPE = re.compile(r"(?<![\w.-])((?:[\w.-]+/)*[\w.-]+\.(?:sh|py|go|tsv|yaml|yml|json))\b")
# keys of the header block the engine renders into body_md (renderItemBody and the closure,
# reopen, block and obsolete-details paths)
BODY_KEYS = {
    "Status", "Type", "Severity", "Created-By", "Assigned-To", "Evidence", "Reproduction", "Investigation",
    "Obsolete-Details", "Reopened-Details", "Operator-Block-Details", "Reopens-count",
}
LINE_SEPARATORS = re.compile("[\r\x0b\x0c\x1c\x1d\x1e\x85\u2028\u2029]")
CLAUSE_SPLIT = re.compile(r"[;\n]|\.(?=\s|$)")
MAX_RANGE = 200


def words(s):
    return {t for t in re.split(r"[^a-z0-9_]+", s.lower()) if len(t) >= 4 and t not in STOP and not t.isdigit()}


def id_re(prefix):
    return re.compile(r"(?<![\w-])" + re.escape(prefix) + r"-(\d+)\b(?!-)")


def range_re(prefix):
    p = re.escape(prefix)
    return re.compile(r"(?<![\w-])" + p + r"-(\d+)\.\." + p + r"-(\d+)\b(?!-)")


def ids_in(text, prefix):
    """Every id named in text: each token, plus the interior of each range `P-a..P-b` (0 < b-a <= 200).
    Returns a dict id -> count."""
    out = {}
    for m in id_re(prefix).finditer(text):
        out[m.group(0)] = out.get(m.group(0), 0) + 1
    for m in range_re(prefix).finditer(text):
        a, b = int(m.group(1)), int(m.group(2))
        if 0 < b - a <= MAX_RANGE:
            w = len(m.group(1))
            for n in range(a + 1, b):
                iid = "%s-%0*d" % (prefix, w, n)
                out[iid] = out.get(iid, 0) + 1
    return out


def strip_structured_state_lines(desc):
    return "\n".join(
        l for l in desc.split("\n") if not (l.startswith("**Reproduction:**") or l.startswith("**Investigation:**"))
    )


def scope_section(desc):
    m = re.search(r"^\*\*Affected scope / file-scope manifest:\*\*\n(.*?)(?:\n\n|\Z)", desc, re.S | re.M)
    return m.group(1) if m else ""


def foreign_ids(desc, prefix):
    out = set()
    for m in FOREIGN_LINE.finditer(desc):
        out |= set(ids_in(m.group(1), prefix))
    return out


def text_without_foreign_line(desc):
    return FOREIGN_LINE.sub("", desc)


def clause_at(text, start, end):
    s = 0
    for m in CLAUSE_SPLIT.finditer(text, 0, start):
        s = m.end()
    m = CLAUSE_SPLIT.search(text, end)
    return text[s:m.start() if m else len(text)]


def exempt_line(text, pos):
    """An unlabelled id on a `Duplicate check` line or a `Stale obsolete_details row` note is judged by
    the DUP-* and OBSOLETE-STALE checks, not by XREF-UNLABELLED."""
    s = text.rfind("\n", 0, pos) + 1
    line = text[s:text.find("\n", pos) if text.find("\n", pos) >= 0 else len(text)]
    return bool(DUP_LINE.match(line) or STALE_NOTE.match(line))


def body_problems(r):
    """BODY-SYNC in both directions: body_md must be the engine rendering of the item's columns."""
    b, d = r["body"], r["description"]
    if not b:
        return ["body_md is empty"]
    k = b.find(d)
    if k < 0:
        return ["description is not contained in body_md"]
    pre, suf = b[:k], b[k + len(d):]
    out = []
    if suf.strip():
        out.append("body_md carries text after the description: %r" % suf.strip()[:40])
    m = re.match(r"## (\S+) — ([^\n]*)\n\n((?:\*\*[A-Za-z-]+:\*\*[^\n]*\n)*)\n\Z", pre)
    if not m:
        out.append("body_md carries text before the description outside the heading and header block")
        return out
    if m.group(1) != r["id"] or m.group(2) != r["title"]:
        out.append("body_md heading disagrees with the id or title column")
    hdr = {}
    # split on "\n" only: str.splitlines() also splits on U+2028, U+0085, \r and others, which the
    # header pattern lets through inside a line; such a line is a finding, never a crash (Pyright lead)
    for line in m.group(3).split("\n")[:-1]:
        if LINE_SEPARATORS.search(line):
            out.append("body_md header line carries a line separator other than a newline: %r" % line[:40])
        km = re.match(r"\*\*([A-Za-z-]+):\*\*", line)
        if km is None:  # unreachable while the header pattern holds; a finding, never a crash
            out.append("body_md header line does not start with a key: %r" % line[:40])
            continue
        key = km.group(1)
        if key not in BODY_KEYS:
            out.append("body_md header key %s is not an engine key" % key)
        hdr.setdefault(key, line)
    st = hdr.get("Status")
    if st is None or not st[len("**Status:** "):].startswith(r["status"]):
        out.append("body_md Status line disagrees with the status column %r" % r["status"])
    rs, ivs = r["repro"] or "UNSET", r["inv"] or "UNSET"
    rl, il = hdr.get("Reproduction"), hdr.get("Investigation")
    if rs == "UNSET":
        if rl is not None:
            out.append("body_md has a Reproduction line while reproduction_state is UNSET")
    elif rl is None or not (rl.startswith("**Reproduction:** " + rs + " ") or
                            (rs == "UNREPRODUCED" and " UNREPRODUCED " in rl + " ")):
        out.append("body_md Reproduction line disagrees with reproduction_state %s" % rs)
    if ivs == "UNSET":
        if il is not None:
            out.append("body_md has an Investigation line while investigation_state is UNSET")
    elif il is None or not il.startswith("**Investigation:** " + ivs + " "):
        out.append("body_md Investigation line disagrees with investigation_state %s" % ivs)
    if "Obsolete-Details" in hdr and not r["status"].startswith("Obsolete"):
        out.append("body_md shows Obsolete-Details on an item that is not Obsolete")
    return out


def undecided_open_candidates(target, all_items, exclude):
    """Open items that `target` records as UNDECIDED candidate duplicates (a sentence that says both
    'candidate' and 'UNDECIDED'), minus `exclude`."""
    out = set()
    rx = id_re(target["id"].rsplit("-", 1)[0])
    for sent in re.split(r"(?<=\.)\s+(?=[A-Z])|\n", target["description"]):
        if "UNDECIDED" in sent and re.search(r"(?i)candidate", sent):
            for m in rx.finditer(sent):
                o = all_items.get(m.group(0))
                if m.group(0) not in exclude and o and o["location"] == "Issues" and not o["status"].startswith("Obsolete"):
                    out.add(m.group(0))
    return out


def lint_items(sel, all_items, prefix, require_dup, repo_root=None, exists=None):
    """sel: list of dict rows; all_items: dict id -> row (first location). Returns list of findings.
    exists(rel) decides PATH-MISSING; default: the path exists under repo_root."""
    if repo_root and exists is None:
        exists = lambda rel: os.path.exists(os.path.join(repo_root, rel))
    rx = id_re(prefix)
    findings = []
    sel_ids = {r["id"] for r in sel}
    open_others = [r for i, r in all_items.items() if i not in sel_ids and r["location"] == "Issues"]
    for r in sel:
        iid, desc = r["id"], r["description"]
        fids = foreign_ids(desc, prefix)
        body_text = r["title"] + "\n" + text_without_foreign_line(desc)
        named = set(ids_in(body_text, prefix))
        # XREF-DANGLING (tokens and range interiors)
        for ref in sorted(named):
            if ref not in fids and ref not in all_items:
                findings.append(("XREF-DANGLING", iid, ref))
        # XREF-LABEL / XREF-UNLABELLED (explicit tokens)
        for m in rx.finditer(body_text):
            ref = m.group(0)
            if ref in fids or ref not in all_items or ref == iid:
                continue
            target = all_items[ref]
            tw = words(target["title"])
            lab = re.match(r"\s*\(([^()]{2,80})\)", body_text[m.end():])
            if lab:
                lw = words(lab.group(1))
                if lw:
                    missing = lw - (tw | words(target["description"]))
                    if not (lw & tw) or 3 * len(missing) > len(lw):
                        findings.append(("XREF-LABEL", iid, "%s (%s) vs title: %s" % (ref, lab.group(1), target["title"][:60])))
            elif not exempt_line(body_text, m.start()):
                cw = words(rx.sub(" ", clause_at(body_text, m.start(), m.end())))
                if not (cw & tw):
                    findings.append(("XREF-UNLABELLED", iid, "%s without a label in a clause that shares no title word: %s" % (ref, target["title"][:60])))
        for f in sorted(fids - named):
            findings.append(("FOREIGN-STALE", iid, f))
        # STATE-PROSE
        prose = strip_structured_state_lines(desc)
        rs, ivs = r["repro"] or "UNSET", r["inv"] or "UNSET"
        for tok in REPRO_TOKENS:
            for _ in re.finditer(r"(?<![\w-])" + re.escape(tok) + r"(?![\w-])", prose):
                canon = "blocked-no-device-with-recorded-blocker" if tok == "blocked-no-device" else tok
                ok = (rs in UNREPRO_FAMILY) if canon == "UNREPRODUCED" else (rs == canon)
                if not ok:
                    findings.append(("STATE-PROSE", iid, "prose says %s, reproduction_state is %s" % (tok, rs)))
                break
        for tok in INV_TOKENS:
            if re.search(r"(?<![\w-])" + re.escape(tok) + r"(?![\w-])", prose) and ivs != tok:
                findings.append(("STATE-PROSE", iid, "prose says %s, investigation_state is %s" % (tok, ivs)))
        for m in re.finditer(r"\bInvestigation:\s*([\w-]+)", prose):
            if m.group(1) in INV_STATES and m.group(1) != ivs:
                findings.append(("STATE-PROSE", iid, "prose says Investigation: %s, investigation_state is %s" % (m.group(1), ivs)))
        # STATE-PROSE, structured form: a `**Reproduction:**` / `**Investigation:**` line written into the
        # description must name the column's state (reviewer mutant M11)
        for line in desc.split("\n"):
            if line.startswith("**Reproduction:**"):
                toks = [t for t in REPRO_TOKENS if re.search(r"(?<![\w-])" + re.escape(t) + r"(?![\w-])", line)]
                tok = toks[0] if toks else None
                canon = "blocked-no-device-with-recorded-blocker" if tok == "blocked-no-device" else tok
                ok = canon is not None and ((rs in UNREPRO_FAMILY) if canon == "UNREPRODUCED" else (rs == canon))
                if not ok:
                    findings.append(("STATE-PROSE", iid, "structured line says %s, reproduction_state is %s" % (tok, rs)))
            elif line.startswith("**Investigation:**"):
                toks = [t for t in INV_STATES if re.search(r"(?<![\w-])" + re.escape(t) + r"(?![\w-])", line)]
                if not toks or toks[0] != ivs:
                    findings.append(("STATE-PROSE", iid, "structured line says %s, investigation_state is %s" % (toks[0] if toks else None, ivs)))
        # SECTIONS
        for name, pat in SECTION_MARKERS:
            if not pat.search(desc):
                findings.append(("SECTIONS", iid, "missing: " + name))
        # BODY-SYNC (both directions)
        for p in body_problems(r):
            findings.append(("BODY-SYNC", iid, p))
        # SECRET
        for name, pat in SECRET_PATTERNS:
            if pat.search(r["title"] + "\n" + desc):
                findings.append(("SECRET", iid, name))
        # EPHEMERAL (a line that carries an "(ephemeral" note is exempt; the note covers its own line only)
        for line in (r["title"] + "\n" + desc).split("\n"):
            if "(ephemeral" in line:
                continue
            for name, pat in EPHEMERAL_PATTERNS:
                em = pat.search(line)
                if em:
                    findings.append(("EPHEMERAL", iid, "%s: %s" % (name, em.group(0)[:60])))
        # PATH-MISSING (only with --repo-root): a cited evidence path under docs/qa/ or
        # docs/operator_decisions/ must exist in the repository (section 11.4.215)
        if repo_root and exists is not None:
            for m in EVIDENCE_PATH.finditer(desc):
                rel = m.group(1).rstrip(".,;:)")
                if not exists(rel):
                    findings.append(("PATH-MISSING", iid, rel))
        # OBSOLETE-STALE
        if r["obsolete_reason"] is not None and not r["status"].startswith("Obsolete"):
            note = STALE_NOTE.search(desc)
            ok = False
            if note:
                for m in rx.finditer(note.group(1)):
                    o = all_items.get(m.group(0))
                    if o and o["location"] == "Issues" and not o["status"].startswith("Obsolete"):
                        ok = True
            if not ok:
                findings.append(("OBSOLETE-STALE", iid, "obsolete_details row (%s) on a %s item" % (r["obsolete_reason"], r["status"])))
        # DUP-*
        dl = DUP_LINE.search(desc)
        dup_named = {m.group(0) for m in rx.finditer(dl.group(0))} if dl else set()
        verdict = dl.group(1).rstrip(";,.:") if dl else None
        if require_dup:
            if not dl:
                findings.append(("DUP-CHECK", iid, "no `Duplicate check (section 11.4.214):` line"))
            elif verdict not in DUP_VERDICTS:
                findings.append(("DUP-CHECK", iid, "verdict %r not in the closed set" % dl.group(1)))
        closed_dup = r["status"].startswith("Obsolete") and r["obsolete_reason"] == "duplicate-of"
        if dl is not None and verdict == "SAME-DEFECT":
            hm = re.match(r"\s*of\s+(" + re.escape(prefix) + r"-\d+)\b", dl.group(2))
            head = hm.group(1) if hm else None
            if head is None:
                findings.append(("DUP-CHECK", iid, "SAME-DEFECT names no id (`SAME-DEFECT of <id>`)"))
            if not (closed_dup and head is not None and r["obsolete_superseding"] == head):
                findings.append(("DUP-SAME-OPEN", iid, "SAME-DEFECT of %s but not Obsolete duplicate-of %s" % (head, head)))
            t = all_items.get(head) if head else None
            if t is not None:
                if t["status"].startswith("Obsolete") or t["location"] != "Issues":
                    findings.append(("DUP-HEAD", iid, "%s is not an open head (status %s): resolve the chain (section 11.4.214(0))" % (head, t["status"])))
                else:
                    others = undecided_open_candidates(t, all_items, {iid, head})
                    if others:
                        findings.append(("DUP-HEAD", iid, "%s records open UNDECIDED candidate(s) %s: more than one head, the verdict is UNDECIDED (section 11.4.214(0))" % (head, ",".join(sorted(others)))))
        elif verdict == "UNDECIDED":
            cands = {x for x in dup_named if x != iid}
            if not cands:
                findings.append(("DUP-UNDECIDED", iid, "UNDECIDED names no candidate id"))
            if r["status"].startswith("Obsolete") or r["location"] != "Issues":
                findings.append(("DUP-UNDECIDED", iid, "UNDECIDED but the item is closed (%s); mint-with-link keeps it open" % r["status"]))
        if closed_dup and verdict != "SAME-DEFECT":
            findings.append(("DUP-STATUS", iid, "Obsolete duplicate-of %s but the verdict is %s" % (r["obsolete_superseding"], verdict)))
        # SHARED-PATH
        names = {p.rsplit("/", 1)[-1] for p in PATH_IN_SCOPE.findall(scope_section(desc))}
        names = {n for n in names if len(n) >= 8}
        for o in open_others:
            otext = o["title"] + "\n" + o["description"]
            hit = sorted(n for n in names if re.search(r"(?<![\w.-])" + re.escape(n) + r"(?![\w-])", otext))
            if hit and o["id"] not in dup_named:
                findings.append(("SHARED-PATH", iid, "%s also named by open %s" % (hit[0], o["id"])))
    return findings


def embeddings(sel, all_items, prefix):
    sel_ids = {r["id"] for r in sel}
    rows = []
    for r in sel:
        fids = foreign_ids(r["description"], prefix)
        counts = ids_in(r["title"] + "\n" + r["description"], prefix)
        for ref in sorted(counts):
            ns = "foreign" if ref in fids else ("own" if ref in sel_ids else ("main" if ref in all_items else "unknown"))
            rows.append((r["id"], ref, ns, counts[ref]))
    return rows


def load(db):
    con = sqlite3.connect("file:%s?mode=ro" % db, uri=True)
    con.row_factory = sqlite3.Row
    od = {}
    try:
        for row in con.execute("select atm_id, reason, superseding_item from obsolete_details"):
            od[row[0]] = (row[1], row[2])
    except sqlite3.Error:
        pass
    items = {}
    for row in con.execute(
        "select atm_id, title, description, coalesce(body_md,'') as body, status, current_location as loc, "
        "reproduction_state as rs, investigation_state as ivs from items order by atm_id, current_location"
    ):
        if row["atm_id"] in items:
            continue
        reason, sup = od.get(row["atm_id"], (None, None))
        items[row["atm_id"]] = {
            "id": row["atm_id"], "title": row["title"], "description": row["description"], "body": row["body"],
            "status": row["status"], "location": row["loc"], "repro": row["rs"], "inv": row["ivs"],
            "obsolete_reason": reason, "obsolete_superseding": sup,
        }
    con.close()
    return items


def render_body(r):
    """The body the engine renders for a fixture row (heading, header block, description)."""
    hdr = ["**Status:** %s" % r["status"], "**Type:** Task"]
    if (r["repro"] or "UNSET") != "UNSET":
        hdr.append("**Reproduction:** %s — fixture" % ("none — UNREPRODUCED" if r["repro"] == "UNREPRODUCED" else r["repro"]))
    if (r["inv"] or "UNSET") != "UNSET":
        hdr.append("**Investigation:** %s — fixture" % r["inv"])
    if r["status"].startswith("Obsolete") and r["obsolete_reason"]:
        hdr.append("**Obsolete-Details:** Reason: %s" % r["obsolete_reason"])
    return "## %s — %s\n\n%s\n\n%s\n\n" % (r["id"], r["title"], "\n".join(hdr), r["description"])


def secret_needles():
    """(name, positive at the pattern's minimum, negative just below it); assembled from fragments so
    that this file never carries a credential-shaped literal."""
    a, q = "a", "Q"
    return [
        ("aws-access-key-id", "AK" + "IA" + q * 16, "AK" + "IA" + q * 15),
        ("aws-secret-assign", "aws_secret_" + "access_key = " + a * 40, "aws_secret_" + "access_key = " + a * 39),
        ("github-token", "gh" + "p_" + a * 30, "gh" + "p_" + a * 29),
        ("github-fine-grained-pat", "github" + "_pat_" + a * 30, "github" + "_pat_" + a * 29),
        ("gitlab-pat", "gl" + "pat-" + a * 20, "gl" + "pat-" + a * 19),
        ("gitlab-other-token", "gl" + "rt-" + a * 20, "gl" + "rt-" + a * 19),
        ("gcp-api-key", "AI" + "za" + a * 35, "AI" + "za" + a * 34),
        ("private-key-block", "-----BEGIN " + "RSA PRIVATE" + " KEY-----", "-----BEGIN " + "RSA PUBLIC" + " KEY-----"),
        ("huggingface-token", "hf" + "_" + a * 30, "hf" + "_" + a * 29),
        ("jwt", "ey" + "J" + a * 8 + ".ey" + "J" + a * 8 + ".x", "ey" + "J" + a * 7 + ".ey" + "J" + a * 7 + ".x"),
        ("slack-token", "xo" + "xb-" + "1" * 10, "xo" + "xb-" + "1" * 9),
        ("openai-anthropic-key", "s" + "k-" + a * 32, "s" + "k-" + a * 31),
        ("url-userinfo-password", "https://u:" + "p" * 6 + "@h", "https://u:" + "p" * 5 + "@h"),
        ("bearer-token", "Authorization: " + "Bearer " + a * 20, "Authorization: " + "Bearer " + a * 19),
        ("password-assign", "pass" + "word = '" + "x" * 8 + "'", "pass" + "word = '" + "x" * 7 + "'"),
        ("stripe-key", "s" + "k_" + "live_" + a * 20, "s" + "k_" + "live_" + a * 19),
        ("npm-token", "np" + "m_" + a * 36, "np" + "m_" + a * 35),
        ("telegram-bot-token", "123456789" + ":AA" + a * 33, "123456789" + ":AA" + a * 32),
    ]


SELF_GOOD = {
    "id": "ZZ-2", "title": "Needle good item", "status": "Queued", "location": "Issues", "repro": "reproduced-live", "inv": "UNSET",
    "obsolete_reason": None, "obsolete_superseding": None,
    "description": "**What:** a needle.\n\n**Affected scope / file-scope manifest:**\nx/needle_only.sh\n\n"
    "**Reproduction / context:**\nnone\n\n**Acceptance criteria:**\nnone\n\nParent / links: ZZ-1 (the needle umbrella, the parent of this one); see ZZ-4 for the needle range\n"
    "Duplicate check (section 11.4.214): DISTINCT\n"
    "Context: ZZ-8..ZZ-10 of another tracker; evidence docs/qa/needle_present/x.txt; see x.bundle (ephemeral: a scratch file)\n"
    "Foreign ids (another tracker): ZZ-8..ZZ-10\n"
    "**Reproduction:** reproduced-live — REPRODUCED",
}
NEEDLE_EXISTS = {"docs/qa/needle_present/x.txt", "docs/operator_decisions/needle_present.md"}


def selfcheck():
    """Control needles (section 11.4.201(7)(b)): every check must stay silent on the golden-good
    texts (a declared foreign range, an existing evidence path, a noted ephemeral name, a structured
    state line, a correct duplicate-of row, an UNDECIDED verdict, a noted stale obsolete row) and fire
    on its golden-bad text; every secret pattern must fire on its positive needle and stay silent on
    its negative one. Returns a list of failed needle names."""
    umb = dict(SELF_GOOD, id="ZZ-1", title="Needle umbrella", description="umbrella", repro="UNSET")
    rng = dict(SELF_GOOD, id="ZZ-4", title="Needle range holder", description="range holder", repro="UNSET")
    good = dict(SELF_GOOD)
    good["body"] = render_body(good)
    for x in (umb, rng):
        x["body"] = render_body(x)
    allitems = {"ZZ-1": umb, "ZZ-2": good, "ZZ-4": rng}
    ex = lambda rel: rel in NEEDLE_EXISTS
    failed = []

    def fixed(row):
        row = dict(row)
        row["body"] = render_body(row)
        return row

    def run(row, items):
        return {f[0] for f in lint_items([row], items, "ZZ", True, "<needle>", ex)}

    d = good["description"]
    dup_good = fixed(dict(good, status="Obsolete", location="Fixed", obsolete_reason="duplicate-of", obsolete_superseding="ZZ-1",
                          description=d.replace(": DISTINCT", ": SAME-DEFECT of ZZ-1")))
    und_good = fixed(dict(good, description=d.replace(": DISTINCT", ": UNDECIDED; candidate duplicates ZZ-1 and ZZ-4")))
    stale_good = fixed(dict(good, status="Reopened", obsolete_reason="duplicate-of", obsolete_superseding="ZZ-1",
                            description=d + "\nStale obsolete_details row (engine gap ZZ-4): kept by the engine"))
    od_good = fixed(dict(good, description=d.replace("docs/qa/needle_present/x.txt", "docs/operator_decisions/needle_present.md")))
    for name, row in (("golden-good", good), ("golden-good-duplicate", dup_good), ("golden-good-undecided", und_good),
                      ("golden-good-stale-noted", stale_good), ("golden-good-decision-path", od_good)):
        if run(row, dict(allitems, **{"ZZ-2": row})):
            failed.append(name)
    head_umb = fixed(dict(umb, description="umbrella; candidate duplicate ZZ-4, merge UNDECIDED"))
    bad_cases = {
        "XREF-DANGLING": (dict(good, description=d.replace("ZZ-1 (the needle umbrella, the parent of this one)", "ZZ-19")), {}),
        "XREF-DANGLING/range": (dict(good, description=d.replace("Foreign ids (another tracker): ZZ-8..ZZ-10", "Foreign ids (another tracker): ZZ-8, ZZ-10")), {}),
        "XREF-LABEL": (dict(good, description=d.replace("(the needle umbrella, the parent of this one)", "(GitHub issues sync)")), {}),
        "XREF-LABEL/one-shared-word": (dict(good, description=d.replace("(the needle umbrella, the parent of this one)", "(umbrella of github runners)")), {}),
        "XREF-UNLABELLED": (dict(good, description=d.replace("see ZZ-4 for the needle range", "related ZZ-4, not a parent")), {}),
        "FOREIGN-STALE": (dict(good, description=d.replace("tracker): ZZ-8..ZZ-10", "tracker): ZZ-8..ZZ-10, ZZ-7")), {}),
        "STATE-PROSE": (dict(good, description=d + "\nReproduction state: UNREPRODUCED."), {}),
        "STATE-PROSE/structured": (dict(good, repro="UNSET"), {}),
        "SECTIONS": (dict(good, description=d.replace("**Acceptance criteria:**", "Acceptance:")), {}),
        "BODY-SYNC": (dict(good, body="something else"), {"raw": True}),
        "BODY-SYNC/empty": (dict(good, body=""), {"raw": True}),
        "BODY-SYNC/header-line-separator": (dict(good, body=render_body(good).replace("**Status:** Queued\n", "**Status:** Queued\u2028x\n")), {"raw": True}),
        "BODY-SYNC/extra-paragraph": (dict(good, body=render_body(good) + "Update: already fixed; no work owed.\n"), {"raw": True}),
        "SECRET": (dict(good, description=d + "\nkey AK" + "IA" + "ABCDEFGHIJKLMNOP"), {}),
        "EPHEMERAL": (dict(good, description=d + "\nsee review_x_r1.md"), {}),
        "EPHEMERAL/mktemp-default": (dict(good, description=d + "\nlog at /tmp/tmp." + "k3Jx9QvT2a" + "/out.txt"), {}),
        "EPHEMERAL/mktemp-default-lowercase": (dict(good, description=d + "\nwork dir tmp." + "qwertyuiop" + " kept"), {}),
        "EPHEMERAL/lowercase-dir": (dict(good, description=d + "\nsee scratch." + "zobh" + "/c"), {}),
        "EPHEMERAL/4-char": (dict(good, description=d + "\nsee scratch." + "Ab3d" + " for it"), {}),
        "DUP-CHECK": (dict(good, description=d.replace(": DISTINCT", ": PROBABLY")), {}),
        "DUP-SAME-OPEN": (dict(good, description=d.replace(": DISTINCT", ": SAME-DEFECT of ZZ-1")), {}),
        "DUP-SAME-OPEN/wrong-head": (dict(dup_good, obsolete_superseding="ZZ-4"), {}),
        "DUP-SAME-OPEN/head-is-first-id": (dict(dup_good, obsolete_superseding="ZZ-4",
                                               description=dup_good["description"].replace("SAME-DEFECT of ZZ-1", "SAME-DEFECT of ZZ-1 (see also ZZ-4)")), {}),
        "DUP-HEAD": (dup_good, {"ZZ-1": head_umb}),
        "DUP-UNDECIDED": (dict(good, description=d.replace(": DISTINCT", ": UNDECIDED")), {}),
        "DUP-STATUS": (dict(dup_good, description=d.replace(": DISTINCT", ": UNDECIDED; candidate ZZ-1")), {}),
        "OBSOLETE-STALE": (dict(good, status="Reopened", obsolete_reason="duplicate-of", obsolete_superseding="ZZ-1"), {}),
        "SHARED-PATH": (dict(good), {"ZZ-3": dict(SELF_GOOD, id="ZZ-3", title="other open", description="touches x/needle_only.sh", body="")}),
        "PATH-MISSING": (dict(good, description=d.replace("needle_present", "needle_absent_zz9")), {}),
        "PATH-MISSING/decisions": (dict(od_good, description=od_good["description"].replace("needle_present.md", "needle_absent.md")), {}),
    }
    for code, (row, extra) in bad_cases.items():
        extra = dict(extra)
        if not extra.pop("raw", False):
            row = fixed(row)
        items = dict(allitems, **{"ZZ-2": row})
        items.update(extra)
        if code.split("/")[0] not in run(row, items):
            failed.append(code)
    for name, pos, neg in secret_needles():
        pat = dict(SECRET_PATTERNS).get(name)
        if pat is None or not pat.search("x " + pos + " y") or pat.search("x " + neg + " y"):
            failed.append("SECRET/" + name)
    if len(secret_needles()) != len(SECRET_PATTERNS):
        failed.append("SECRET/needle-count")
    return failed


def main(argv):
    ap = argparse.ArgumentParser(prog="intake_lint.py", add_help=True)
    ap.add_argument("--db", required=True)
    ap.add_argument("--origin", action="append", default=[])
    ap.add_argument("--ids", action="append", default=[])
    ap.add_argument("--prefix")
    ap.add_argument("--require-dup-check", action="store_true")
    ap.add_argument("--embeddings", action="store_true")
    ap.add_argument("--no-selfcheck", action="store_true")
    ap.add_argument("--skip-check", action="append", default=[])
    ap.add_argument("--repo-root")
    try:
        a = ap.parse_args(argv)
    except SystemExit as e:
        return 2 if e.code else 0
    if not a.origin and not a.ids:
        print("intake_lint: give --origin or --ids", file=sys.stderr)
        return 2
    skip = set()
    for lst in a.skip_check:
        skip |= {x.strip() for x in lst.split(",") if x.strip()}
    unknown = sorted(skip - CODES)
    if unknown:
        print("intake_lint: unknown --skip-check code(s): " + ",".join(unknown), file=sys.stderr)
        return 2
    if a.repo_root and not os.path.isdir(a.repo_root):
        print("intake_lint: --repo-root is not a directory: %s" % a.repo_root, file=sys.stderr)
        return 2
    if not a.no_selfcheck:
        bad = selfcheck()
        if bad:
            print("BLIND: control needle failed: " + ",".join(bad), file=sys.stderr)
            return 3
    if not os.path.isfile(a.db):
        print("BLIND: database not found: %s" % a.db, file=sys.stderr)
        return 3
    try:
        items = load(a.db)
    except sqlite3.Error as e:
        print("BLIND: database unreadable: %s" % e, file=sys.stderr)
        return 3
    if not items:
        print("BLIND: database holds no items", file=sys.stderr)
        return 3
    nulls = sorted(i for i, r in items.items() if r["title"] is None or r["description"] is None or r["status"] is None or r["location"] is None)
    if nulls:
        print("BLIND: item(s) with a NULL title, description, status or location: " + ",".join(nulls[:5]), file=sys.stderr)
        return 3
    counts = {}
    for i in items:
        p = i.rsplit("-", 1)[0]
        counts[p] = counts.get(p, 0) + 1
    prefix = a.prefix
    if not prefix:
        prefix = max(sorted(counts), key=lambda k: counts[k])
    if not any(id_re(prefix).fullmatch(i) for i in items):
        print("BLIND: no item in the database carries the prefix %s: the id checks could not see" % prefix, file=sys.stderr)
        return 3
    want = set()
    for lst in a.ids:
        want |= {x.strip() for x in lst.split(",") if x.strip()}
    missing = sorted(want - set(items))
    if missing:
        print("BLIND: selected ids not in the database: " + ",".join(missing), file=sys.stderr)
        return 3
    sel = [r for i, r in sorted(items.items()) if i in want or any(o in r["description"] for o in a.origin)]
    if not sel:
        print("BLIND: the selection is empty", file=sys.stderr)
        return 3
    # a crash is never a result: any unexpected error is BLIND (exit 3), never a traceback read as a
    # finding (exit 1) or a silent pass (Pyright leads, round 3)
    rows, raw = [], []
    try:
        if a.embeddings:
            rows = embeddings(sel, items, prefix)
        else:
            raw = lint_items(sel, items, prefix, a.require_dup_check, a.repo_root)
    except Exception as e:  # noqa: BLE001 -- the point is to catch every class of crash
        print("BLIND: the lint crashed (%s: %s): no verdict" % (type(e).__name__, str(e)[:200]), file=sys.stderr)
        return 3
    if a.embeddings:
        print("item\tembedded_id\tnamespace\tcount")
        for row in rows:
            print("%s\t%s\t%s\t%d" % row)
        return 0
    findings = []
    for f in raw:
        if f[0] not in skip and f not in findings:
            findings.append(f)
    for code, iid, detail in findings:
        print("FINDING %s %s %s" % (code, iid, detail))
    print("RESULT: %s selected=%d findings=%d prefix=%s" % ("PASS" if not findings else "FAIL", len(sel), len(findings), prefix))
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
