#!/usr/bin/env python3
# scripts/workable-items/intake_lint.py -- read-only CONTENT lint for a set of workable items
# (an intake batch) in a workable-items SQLite database.
#
# Documentation (section 11.4.18): docs/guides/intake_lint_guide.md (user guide and manual).
#
# WHY  `workable-items validate` and `diff` prove the closed sets, the description floor and the
#   DB-to-Markdown sync. They do not read what a description SAYS, and they do not compare the
#   body_md header lines with their source columns. The independent reviews of the 2026-11-12
#   tracker-intake vehicle found wrong tracker facts that passed validate and diff. This lint checks
#   those classes for a SELECTED set of items, deterministically, and never writes.
#
# USAGE
#   python3 -I scripts/workable-items/intake_lint.py --db <db> (--origin <text> | --ids <A,B,..>)...
#           [--prefix CON] [--require-dup-check] [--repo-root DIR] [--rendered DIR | --no-rendered]
#           [--skip-check CODES] [--embeddings] [--no-selfcheck]
#   --origin TEXT    select every item whose description contains TEXT (repeatable)
#   --ids LIST       select these item ids (comma list, repeatable)
#   --prefix P       id prefix of this tracker (default: the most common prefix in the DB); a prefix
#                    that no item of the DB carries is BLIND (the id checks could not see)
#   --require-dup-check
#                    every selected item must carry a `Duplicate check (section 11.4.214):` line
#                    with a verdict from {DISTINCT, DISTINCT-but-similar, SAME-DEFECT, UNDECIDED}
#   --embeddings     print every id embedded in the selected items' text (title, description and the
#                    state text columns; own / foreign / main / unknown) as TSV and exit 0
#   --repo-root DIR  enable PATH-MISSING and the evidence-file checks of STATE-EVIDENCE against this
#                    checkout; the rendered documents default to DIR/docs
#   --rendered DIR   scan the rendered Issues.md, Fixed.md, Issues_Summary.md and Fixed_Summary.md in
#                    DIR (the published sink): the section of each selected item and the summary rows
#                    whose id cell names it. A selected item that appears in none of them is BLIND.
#   --no-rendered    do not scan rendered documents (the RESULT line says rendered=none)
#   --skip-check C   comma list of finding codes not to report (repeatable; an unknown code is a
#                    usage error); a skipped code must be stated wherever the result is cited
#   --no-selfcheck   skip the built-in control needles (tests only; never in a gate)
#
# SURFACES  SECRET, EPHEMERAL and CONTROL-CHAR read every text surface of a selected item: the title,
#   the description, body_md (every line, the header lines included), every other column of `items`
#   (enumerated from the row, so a new column is read without a code change), the item's
#   obsolete_details, operator_block_details and item_history rows, and the rendered lines (above).
#   One finding per (code, item, pattern) names every surface the pattern was found on. One control
#   needle per surface runs in the self-check.
#
# CHECKS (finding codes; each finding is one line `FINDING <code> <item> <detail>`)
#   XREF-DANGLING    an id of this tracker named in the title, the description or a state text column
#                    (a range `A..B` names every id in it) does not exist and is not declared foreign
#   XREF-LABEL       `<id> (<label>)`: no significant label word is in the target's title, or more
#                    than a third of the significant label words occur nowhere in the target's title
#                    or description
#   XREF-UNLABELLED  an id of another existing item written without a label, in a clause that shares
#                    no significant word with the target's title
#   FOREIGN-STALE    a `Foreign ids` line declares an id the rest of the item never names
#   STATE-PROSE      a closed reproduction/investigation state word in prose, or a hand-written
#                    `**Reproduction:**` / `**Investigation:**` line in the description, disagrees with
#                    the item's state column (section 11.4.294(A): the column is the source)
#   STATE-EVIDENCE   a reproduction state that needs evidence (reproduced-*, not-reproducible-with-
#                    evidence) has no evidence path or no 64-hex sha256 in reproduction_env; an
#                    investigation state that needs evidence (root-cause-found-with-evidence,
#                    closed-no-defect) has no evidence path or no sha256; a blocked state has no
#                    blocker; with --repo-root: the evidence file is missing or its sha256 differs
#   SECTIONS         a section 11.4.148 marker is missing (What, Affected scope, Reproduction /
#                    context, Acceptance criteria, Parent / links)
#   BODY-SYNC        body_md is not the engine rendering of its sources: empty, the description not in
#                    it, text before or after the rendered parts, the heading, or any header line that
#                    differs from its source (Status, Type, Severity, Created-By, Assigned-To,
#                    Reproduction, Investigation and Obsolete-Details exactly; Evidence must be the
#                    evidence of a closure row; Reopened-Details the last Reopened row;
#                    Operator-Block-Details the item's row), a key written twice, or a key outside
#                    the engine's set. The table in docs/guides/intake_lint_guide.md lists every key.
#   SECRET           a credential-shaped string on any surface (pattern name printed, never the match;
#                    section 11.4.10)
#   EPHEMERAL        a session-scratchpad location, a /tmp path, a mktemp-shaped name, a .bundle file,
#                    a home directory path, a session store directory, or a bare review_*.md /
#                    *_lander_items.md name (not under docs/) on a line with no `(ephemeral` note
#   CONTROL-CHAR     NUL, a C0 control other than tab and newline, DEL, a C1 control, U+2028 or U+2029,
#                    or a Unicode format character (category Cf: bidi overrides and isolates, the BOM,
#                    the soft hyphen, zero-width characters, tag characters); the earliest one is named
#                    on any surface; a tab or newline in the title
#   SHARED-PATH      a file named in the item's Affected-scope section is named by an OPEN item outside
#                    the selection, and the Duplicate check line does not name that item
#   DUP-CHECK        (--require-dup-check) the line is missing or its verdict is outside the closed set;
#                    (always) a SAME-DEFECT verdict that names no id
#   DUP-SAME-OPEN    the verdict is SAME-DEFECT of X but the item is not Obsolete duplicate-of X
#   DUP-HEAD         the verdict is SAME-DEFECT of X but X is not the single open head: X is closed, or
#                    another open item is, or may be, a head of the same defect (section 11.4.214(0)):
#                    its own Duplicate check line names X with SAME-DEFECT or UNDECIDED (any case), or
#                    it names X, or X names it, in a duplicate clause (candidate, undecided, duplicate,
#                    same defect, second / canonical / open head; any case), or it carries an
#                    obsolete_details row duplicate-of X while open and has no stale-row note
#   DUP-UNDECIDED    the verdict is UNDECIDED but names no candidate id, or the item is closed
#   DUP-STATUS       the item is Obsolete duplicate-of but its verdict is not SAME-DEFECT
#   OBSOLETE-STALE   an obsolete_details row on an item that is not Obsolete, with no
#                    `Stale obsolete_details row (...)` note naming an existing open item
#   PATH-MISSING     (--repo-root) a cited docs/qa/ or docs/operator_decisions/ path does not exist
#
# EXIT  0 no finding; 1 findings; 2 usage error; 3 BLIND (database unreadable, a required table
#   missing, a non-text value, empty selection, a prefix no item carries, a selected item absent from
#   every rendered document, any crash of the lint, or a built-in control needle failed: the
#   instrument could not see, so no verdict is given).
# EVIDENCE CLASS  gate-logic only (section 11.4.289): it reads text, it does not prove an item true.
import argparse
import hashlib
import os
import re
import sqlite3
import sys
import unicodedata
import urllib.parse

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
REPRO_NEEDS_EVIDENCE = {"reproduced-live", "reproduced-host-fixture", "not-reproducible-with-evidence"}
INV_NEEDS_EVIDENCE = {"root-cause-found-with-evidence", "closed-no-defect"}
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
    # an unquoted assignment (shell, env file, URL query); a value that starts like a reference
    # ($VAR, <placeholder>, {template}, %VAR%, a quote, `(`, `[`) is not a value (round 4, R4-3)
    ("password-assign-unquoted", re.compile(
        r"(?i)(?:\b|_)(?:password|passwd|secret|api_?key|token)\s*=\s*(?![$<{%'\"`(\[])[^\s'\"`]{8,}")),
    ("basic-auth", re.compile(r"(?i)authorization:\s*basic\s+[A-Za-z0-9+/=]{8,}")),
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
    # a home directory of a named user, or a dotted directory under ~ (agent and tool state)
    ("home-path", re.compile(r"(?<![\w.-])(?:/(?:home|Users)/[\w.-]+/|~/\.[\w-]+/)")),
    # an agent session store (transcripts, todo lists, shell snapshots)
    ("session-store", re.compile(r"\.claude[\w-]*/(?:projects|todos|shell-snapshots)/")),
]
# NUL, C0 other than tab and newline, DEL, C1, and the two Unicode line separators
CONTROL_CHAR = re.compile("[\x00-\x08\x0b-\x1f\x7f-\x9f\u2028\u2029]")


def control_char(text):
    """The earliest control character, line separator or format character (Cf) in text, or None. Cf
    holds the bidi overrides and isolates (Trojan Source), the BOM, the soft hyphen, the zero-width
    characters and the tag characters, which change what a reader sees without being visible."""
    if text.isascii():
        cm = CONTROL_CHAR.search(text)
        return cm.group(0) if cm else None
    for ch in text:
        if CONTROL_CHAR.match(ch) or unicodedata.category(ch) == "Cf":
            return ch
    return None
CODES = {
    "XREF-DANGLING", "XREF-LABEL", "XREF-UNLABELLED", "FOREIGN-STALE", "STATE-PROSE", "STATE-EVIDENCE",
    "SECTIONS", "BODY-SYNC", "SECRET", "EPHEMERAL", "CONTROL-CHAR", "SHARED-PATH", "DUP-CHECK",
    "DUP-SAME-OPEN", "DUP-HEAD", "DUP-UNDECIDED", "DUP-STATUS", "OBSOLETE-STALE", "PATH-MISSING",
}
DUP_LINE = re.compile(r"^Duplicate check \(section 11\.4\.214\):\s*(\S+)(.*)$", re.M)
DUP_VERDICTS = {"DISTINCT", "DISTINCT-but-similar", "SAME-DEFECT", "UNDECIDED"}
DUP_LINK_VERDICTS = {"SAME-DEFECT", "UNDECIDED"}
DUP_WORDS = re.compile(r"(?i)\b(?:candidates?|undecided|duplicates?|same[- ]defect|(?:second|canonical|open|two|other) heads?)\b")
FOREIGN_LINE = re.compile(r"^Foreign ids\b[^:]*:(.*)$", re.M)
STALE_NOTE = re.compile(r"^Stale obsolete_details row \(([^)]*)\)", re.M)
# the match may end with a sentence dot ("see docs/qa/x/e.txt."); PATH-MISSING strips it (round-3
# review LC9: with the end class [\w/] the strip was dead code, so its mutant could not die)
EVIDENCE_PATH = re.compile(r"(?<![\w./-])(docs/(?:qa|operator_decisions)/[\w./-]*[\w/.])")
PATH_IN_SCOPE = re.compile(r"(?<![\w.-])((?:[\w.-]+/)*[\w.-]+\.(?:sh|py|go|tsv|yaml|yml|json))\b")
SHA_RX = re.compile(r"(?<![0-9a-f])[0-9a-f]{64}(?![0-9a-f])")
# keys of the header block the engine renders into body_md (renderItemBody and the closure, reopen,
# block and obsolete-details paths); Reopens-count is legacy (no current engine path writes it)
BODY_KEYS = {
    "Status", "Type", "Severity", "Created-By", "Assigned-To", "Evidence", "Reproduction", "Investigation",
    "Obsolete-Details", "Reopened-Details", "Operator-Block-Details", "Reopens-count",
}
EXACT_KEYS = ["Status", "Type", "Severity", "Created-By", "Assigned-To", "Reproduction", "Investigation", "Obsolete-Details"]
CLOSURE_EVENTS = {"Fixed", "Implemented", "Completed", "Obsolete"}
LINE_SEPARATORS = re.compile("[\r\x0b\x0c\x1c\x1d\x1e\x85  ]")
CLAUSE_SPLIT = re.compile(r"[;\n]|\.(?=\s|$)")
MAX_RANGE = 200
REQUIRED_TABLES = ("items", "obsolete_details", "operator_block_details", "item_history")
ITEM_COLUMNS = [
    "atm_id", "type", "status", "severity", "title", "description", "forensic_anchor", "closure_criteria",
    "composes_with", "destination", "logic_group", "created_by", "assigned_to", "current_location", "body_md",
    "representation", "closure_date", "round", "commit_ref", "parent_atm_id", "session_ref",
    "reproduction_state", "reproduction_surface", "reproduction_evidence", "reproduction_red_cmd",
    "reproduction_green_cmd", "reproduction_env", "reproduction_signature", "reproduction_blocker",
    "reproduction_updated_at", "reproduction_updated_by", "investigation_state", "investigation_root_cause",
    "investigation_evidence", "investigation_updated_at", "investigation_updated_by", "created_at",
    "last_modified",
]
STATE_TEXT_COLS = ["reproduction_red_cmd", "reproduction_green_cmd", "reproduction_env",
                   "reproduction_signature", "reproduction_blocker", "investigation_root_cause"]
RENDERED_FILES = ["Issues.md", "Fixed.md", "Issues_Summary.md", "Fixed_Summary.md"]
RENDERED_ID_CELL = re.compile(r"^([A-Za-z][A-Za-z0-9]*-[0-9]+)(?: — |$)")
RENDERED_HEADING = re.compile(r"^## ([A-Za-z][A-Za-z0-9]*-[0-9]+)(?: — |\. )")
STATE_SEP = " — "


class Blind(Exception):
    """The instrument could not see: no verdict (exit 3)."""


def words(s):
    return {t for t in re.split(r"[^a-z0-9_]+", s.lower()) if len(t) >= 4 and t not in STOP and not t.isdigit()}


def id_re(prefix):
    # ASCII digits: \d also reads fullwidth and other Unicode digits (round 4, R4-5)
    return re.compile(r"(?<![\w-])" + re.escape(prefix) + r"-([0-9]+)\b(?!-)")


def range_re(prefix):
    p = re.escape(prefix)
    return re.compile(r"(?<![\w-])" + p + r"-([0-9]+)\.\." + p + r"-([0-9]+)\b(?!-)")


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


def col(r, name):
    """A column value as text ("" for NULL)."""
    v = r.get(name)
    return "" if v is None else str(v)


def state_text(r):
    return "\n".join(col(r, c) for c in STATE_TEXT_COLS if col(r, c))


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
    # scan the whole text: an endpos bound makes `$` match at the bound, so the dot before the end of a
    # range (`FX-001..FX-003`) read as a sentence end and the range end lost its clause (round 4)
    s = 0
    for m in CLAUSE_SPLIT.finditer(text):
        if m.end() > start:
            break
        s = m.end()
    m = CLAUSE_SPLIT.search(text, end)
    return text[s:m.start() if m else len(text)]


def line_at(text, pos):
    s = text.rfind("\n", 0, pos) + 1
    e = text.find("\n", pos)
    return text[s:e if e >= 0 else len(text)]


def exempt_line(text, pos):
    """An unlabelled id on a `Duplicate check` line or a `Stale obsolete_details row` note is judged by
    the DUP-* and OBSOLETE-STALE checks, not by XREF-UNLABELLED."""
    line = line_at(text, pos)
    return bool(DUP_LINE.match(line) or STALE_NOTE.match(line))


# ---- engine renderings (a port of scripts/workable-items/cmd/workable-items/states.go) -------------

def encode_code_span(v):
    """encodeCodeSpan: the fence is one backtick longer than the longest backtick run; a value that
    starts or ends with a backtick is padded with one space on each side."""
    run = best = 0
    for ch in v:
        run = run + 1 if ch == "`" else 0
        best = max(best, run)
    fence = "`" * (best + 1)
    if v.startswith("`") or v.endswith("`"):
        return fence + " " + v + " " + fence
    return fence + v + fence


def details(pairs):
    out = []
    for key, val in pairs:
        if val == "":
            continue
        out.append(STATE_SEP + key + " " + (val if key in ("surface", "updated") else encode_code_span(val)))
    return "".join(out)


def repro_details(r):
    return [("surface", col(r, "reproduction_surface")), ("evidence", col(r, "reproduction_evidence")),
            ("red-command", col(r, "reproduction_red_cmd")), ("green-command", col(r, "reproduction_green_cmd")),
            ("env", col(r, "reproduction_env")), ("signature", col(r, "reproduction_signature")),
            ("blocker", col(r, "reproduction_blocker")), ("updated", col(r, "reproduction_updated_at")),
            ("by", col(r, "reproduction_updated_by"))]


def repro_label(r):
    """reproLabel: REPRODUCED only for a live or host-fixture state with every required detail, no
    UNCONFIRMED value, and not a host fixture on a live-target surface."""
    st = col(r, "reproduction_state") or "UNSET"
    if st not in ("reproduced-live", "reproduced-host-fixture"):
        return "UNREPRODUCED"
    d = dict(repro_details(r))
    if any(d[k] == "" for k in ("surface", "evidence", "red-command", "env", "signature")):
        return "UNREPRODUCED"
    if st == "reproduced-host-fixture" and d["surface"] == "live-target":
        return "UNREPRODUCED"
    if any(v.startswith("UNCONFIRMED") for _, v in repro_details(r)):
        return "UNREPRODUCED"
    return "REPRODUCED"


def repro_line(r):
    st = col(r, "reproduction_state") or "UNSET"
    if st == "UNSET":
        return None
    head = "none" + STATE_SEP + "UNREPRODUCED" if st == "UNREPRODUCED" else st + STATE_SEP + repro_label(r)
    return "**Reproduction:** " + head + details(repro_details(r))


def inv_line(r):
    st = col(r, "investigation_state") or "UNSET"
    if st == "UNSET":
        return None
    return "**Investigation:** " + st + details([
        ("root-cause", col(r, "investigation_root_cause")), ("evidence", col(r, "investigation_evidence")),
        ("updated", col(r, "investigation_updated_at")), ("by", col(r, "investigation_updated_by"))])


def obsolete_line(od):
    return "**Obsolete-Details:** Since: %s; Reason: %s; Superseding-item: %s; Triple-check evidence: %s" % (
        col(od, "since"), col(od, "reason"), col(od, "superseding_item"), col(od, "triple_check_evidence"))


def reopened_rows(r):
    return [h for h in r["hist"] if h.get("event_type") == "Reopened"]


def reopen_line(h):
    return "**Reopened-Details:** By: %s On: %s Reason: %s Evidence: %s" % (
        col(h, "by"), col(h, "on_date"), col(h, "reason"), col(h, "evidence_path"))


def closure_evidence(r):
    out = {col(h, "evidence_path") for h in r["hist"] if h.get("event_type") in CLOSURE_EVENTS}
    if r["od"]:
        out.add(col(r["od"], "triple_check_evidence"))
    return out - {""}


def expected_lines(r):
    """The exact header line each EXACT_KEYS key must carry, or None when it must be absent."""
    exp: "dict[str, str | None]" = {"Status": "**Status:** %s" % col(r, "status"), "Type": "**Type:** %s" % col(r, "type")}
    for key, name in (("Severity", "severity"), ("Created-By", "created_by"), ("Assigned-To", "assigned_to")):
        v = col(r, name)
        exp[key] = "**%s:** %s" % (key, v) if v.strip() else None
    exp["Reproduction"] = repro_line(r)
    exp["Investigation"] = inv_line(r)
    exp["Obsolete-Details"] = obsolete_line(r["od"]) if col(r, "status").startswith("Obsolete") and r["od"] else None
    return exp


def engine_body(r):
    """The body the engine renders for a row (fixtures of the self-check): heading, the header block
    with every key the sources give, then the description."""
    exp = expected_lines(r)
    hdr = [x for x in (exp[k] for k in ("Status", "Type")) if x]
    ev = sorted(closure_evidence(r))
    if ev:
        hdr.append("**Evidence:** " + ev[0])
    hdr += [x for x in (exp[k] for k in EXACT_KEYS[2:]) if x]
    rr = reopened_rows(r)
    if rr:
        hdr.append(reopen_line(rr[-1]))
    if r["obd"]:
        hdr.append("**Operator-Block-Details:** WHAT: %s" % col(r["obd"], "what"))
    return "## %s — %s\n\n%s\n\n%s\n\n" % (r["id"], r["title"], "\n".join(hdr), r["description"])


def body_problems(r):
    """BODY-SYNC in both directions: body_md must be the engine rendering of the item's sources."""
    b, d = r["body"], r["description"]
    if not b:
        return ["body_md is empty"]
    if b.find(d) < 0:
        return ["description is not contained in body_md"]
    # parse the rendered prefix first (heading, header block, one blank line); the description must
    # start right after it. Searching for the description first would find a description equal to the
    # title inside the heading.
    m = re.match(r"## (\S+) — ([^\n]*)\n\n((?:\*\*[A-Za-z-]+:\*\*[^\n]*\n)*)\n", b)
    out = []
    if not m or not b.startswith(d, m.end()):
        out.append("body_md carries text before the description outside the heading and header block")
        return out
    suf = b[m.end() + len(d):]
    if suf.strip():
        out.append("body_md carries text after the description: %r" % suf.strip()[:40])
    if m.group(1) != r["id"] or m.group(2) != r["title"]:
        out.append("body_md heading disagrees with the id or title column")
    hdr = {}
    # split on "\n" only: str.splitlines() also splits on U+2028, U+0085, \r and others, which the
    # header pattern lets through inside a line; such a line is a finding, never a crash
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
        if key in hdr:
            out.append("body_md header key %s is written twice" % key)
            continue
        hdr[key] = line
    exp = expected_lines(r)
    for key in EXACT_KEYS:
        want, have = exp[key], hdr.get(key)
        if want is None and have is not None:
            out.append("body_md has %s line while its source gives none" % ("an " + key if key[0] in "AEIOU" else "a " + key))
        elif want is not None and have is None:
            out.append("body_md lacks the %s line its source gives" % key)
        elif want is not None and have != want:
            out.append("body_md %s line differs from its source" % key)
    if "Evidence" in hdr and hdr["Evidence"][len("**Evidence:** "):] not in closure_evidence(r):
        out.append("body_md Evidence line names no closure evidence of the item")
    if "Reopened-Details" in hdr:
        rr = reopened_rows(r)
        if not rr:
            out.append("body_md has a Reopened-Details line but the item has no Reopened history row")
        elif hdr["Reopened-Details"] != reopen_line(rr[-1]):
            out.append("body_md Reopened-Details line differs from the last Reopened history row")
    if "Operator-Block-Details" in hdr:
        o = r["obd"]
        if o is None:
            out.append("body_md has an Operator-Block-Details line but the item has no operator_block_details row")
        elif not hdr["Operator-Block-Details"].startswith("**Operator-Block-Details:** WHAT: %s" % col(o, "what")):
            out.append("body_md Operator-Block-Details line differs from the item's row")
    if "Reopens-count" in hdr and hdr["Reopens-count"] != "**Reopens-count:** %d" % len(reopened_rows(r)):
        out.append("body_md Reopens-count line differs from the number of Reopened history rows")
    return out


# ---- surfaces ---------------------------------------------------------------------------------------

def surfaces(r, rendered):
    """(surface name, text) for every text surface of an item (see SURFACES in the header)."""
    yield "title", r["title"]
    yield "description", r["description"]
    yield "body_md", r["body"]
    for name in r["_cols"]:
        if name in ("title", "description", "body_md"):
            continue
        v = r.get(name)
        if v is not None:
            yield "items." + name, str(v)
    for table, row in (("obsolete_details", r["od"]), ("operator_block_details", r["obd"])):
        for name, v in sorted((row or {}).items()):
            if name != "atm_id" and v is not None:
                yield "%s.%s" % (table, name), str(v)
    for h in r["hist"]:
        for name, v in sorted(h.items()):
            if name not in ("atm_id", "id") and v is not None:
                yield "item_history[%s].%s" % (h.get("id"), name), str(v)
    for fname, line in rendered.get(r["id"], []):
        yield "rendered:" + fname, line


def scan_surfaces(r, rendered):
    """SECRET, EPHEMERAL and CONTROL-CHAR over every surface: one finding per (code, pattern)."""
    hits = {}

    def hit(code, name, surface, shown=""):
        key = (code, name)
        if key not in hits:
            hits[key] = (shown, [])
        if surface not in hits[key][1]:
            hits[key][1].append(surface)

    for surface, text in surfaces(r, rendered):
        for name, pat in SECRET_PATTERNS:
            if pat.search(text):
                hit("SECRET", name, surface)
        # an "(ephemeral" note exempts its own line only
        for line in text.split("\n"):
            if "(ephemeral" in line:
                continue
            for name, pat in EPHEMERAL_PATTERNS:
                em = pat.search(line)
                if em:
                    hit("EPHEMERAL", name, surface, em.group(0)[:60])
        ch = control_char(text)
        if ch:
            hit("CONTROL-CHAR", "U+%04X" % ord(ch), surface)
        if surface == "title" and ("\n" in text or "\t" in text):
            hit("CONTROL-CHAR", "newline or tab in the title", surface)
    out = []
    for (code, name), (shown, where) in sorted(hits.items()):
        label = name + (": " + shown if shown else "")
        out.append((code, r["id"], "%s on %s" % (label, ",".join(where))))
    return out


# ---- state evidence ---------------------------------------------------------------------------------

def state_evidence_problems(r, fs):
    """STATE-EVIDENCE (section 11.4.294(C)); fs is None or an object with exists(rel) and sha256(rel)."""
    out = []
    rs = col(r, "reproduction_state") or "UNSET"
    if rs in REPRO_NEEDS_EVIDENCE:
        out += evidence_problems("reproduction", rs, col(r, "reproduction_evidence"),
                                 col(r, "reproduction_env"), fs)
    if rs == "blocked-no-device-with-recorded-blocker" and not col(r, "reproduction_blocker").strip():
        out.append("reproduction_state %s without a reproduction_blocker" % rs)
    ivs = col(r, "investigation_state") or "UNSET"
    if ivs in INV_NEEDS_EVIDENCE:
        out += evidence_problems("investigation", ivs, col(r, "investigation_evidence"),
                                 col(r, "investigation_root_cause") + " " + col(r, "investigation_evidence"), fs)
    return out


def evidence_problems(block, state, path, sha_text, fs):
    out = []
    shas = set(SHA_RX.findall(sha_text))
    if not path:
        out.append("%s_state %s without an evidence path" % (block, state))
    if not shas:
        out.append("%s_state %s carries no evidence sha256" % (block, state))
    if fs is not None and path:
        if not fs.exists(path):
            out.append("%s evidence %s does not exist" % (block, path))
        elif shas and fs.sha256(path) not in shas:
            out.append("%s evidence sha256 differs from the file %s" % (block, path))
    return out


class RepoFS:
    def __init__(self, root):
        self.root = root

    def exists(self, rel):
        return os.path.isfile(os.path.join(self.root, rel))

    def sha256(self, rel):
        h = hashlib.sha256()
        with open(os.path.join(self.root, rel), "rb") as f:
            for chunk in iter(lambda: f.read(1 << 16), b""):
                h.update(chunk)
        return h.hexdigest()


# ---- duplicate heads --------------------------------------------------------------------------------

def is_open(o):
    return o["location"] == "Issues" and not o["status"].startswith("Obsolete")


def links_as_duplicate(text, target, prefix):
    """True when text names target as a possible duplicate: on its Duplicate check line with a
    SAME-DEFECT or UNDECIDED verdict (any case), or outside that line in a clause with a duplicate
    word (any case). A Duplicate check line with any other verdict does not count."""
    for m in id_re(prefix).finditer(text):
        if m.group(0) != target:
            continue
        line = line_at(text, m.start())
        dl = DUP_LINE.match(line)
        if dl:
            if dl.group(1).rstrip(";,.:").upper() in DUP_LINK_VERDICTS:
                return True
            continue
        if DUP_WORDS.search(clause_at(text, m.start(), m.end())):
            return True
    return False


def competing_heads(head, all_items, exclude, prefix):
    """Open items other than head that are, or may be, a second head of the same defect."""
    out = {}
    hid = head["id"]
    for y, o in all_items.items():
        if y in exclude or y == hid or not is_open(o):
            continue
        if links_as_duplicate(o["description"], hid, prefix):
            out[y] = "%s names %s as a duplicate" % (y, hid)
        elif links_as_duplicate(head["description"], y, prefix):
            out[y] = "%s names %s as a duplicate" % (hid, y)
        elif (o["obsolete_reason"] == "duplicate-of" and o["obsolete_superseding"] == hid
              and not STALE_NOTE.search(o["description"])):
            out[y] = "%s is open with an obsolete_details row duplicate-of %s" % (y, hid)
    return out


# ---- the lint ---------------------------------------------------------------------------------------

def lint_items(sel, all_items, prefix, require_dup, repo_root=None, exists=None, rendered=None, fs=None):
    """sel: list of rows; all_items: dict id -> row (first location). Returns a list of findings.
    exists(rel) decides PATH-MISSING (default: the path exists under repo_root); fs gives the
    evidence-file checks of STATE-EVIDENCE (default: RepoFS(repo_root) when repo_root is set)."""
    if repo_root and exists is None:
        exists = lambda rel: os.path.exists(os.path.join(repo_root, rel))
    if repo_root and fs is None and repo_root != "<needle>":
        fs = RepoFS(repo_root)
    rendered = rendered or {}
    rx = id_re(prefix)
    findings = []
    sel_ids = {r["id"] for r in sel}
    open_others = [r for i, r in all_items.items() if i not in sel_ids and r["location"] == "Issues"]
    for r in sel:
        iid, desc = r["id"], r["description"]
        fids = foreign_ids(desc, prefix)
        body_text = r["title"] + "\n" + text_without_foreign_line(desc)
        named = set(ids_in(body_text + "\n" + state_text(r), prefix))
        # XREF-DANGLING (tokens and range interiors, title, description and state text columns)
        for ref in sorted(named):
            if ref not in fids and ref not in all_items:
                findings.append(("XREF-DANGLING", iid, ref))
        # an id written with non-ASCII digits is no id of this tracker and no reader can follow it
        for u in sorted({u.group(0) for u in re.finditer(r"(?<![\w-])" + re.escape(prefix) + r"-(\d+)",
                                                          body_text + "\n" + state_text(r)) if not u.group(1).isascii()}):
            findings.append(("XREF-DANGLING", iid, "%s (non-ASCII digits)" % u))
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
        # STATE-EVIDENCE
        for p in state_evidence_problems(r, fs):
            findings.append(("STATE-EVIDENCE", iid, p))
        # SECTIONS
        for name, pat in SECTION_MARKERS:
            if not pat.search(desc):
                findings.append(("SECTIONS", iid, "missing: " + name))
        # BODY-SYNC (both directions, every header key)
        for p in body_problems(r):
            findings.append(("BODY-SYNC", iid, p))
        # SECRET, EPHEMERAL, CONTROL-CHAR on every surface
        findings += scan_surfaces(r, rendered)
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
                    if o and is_open(o):
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
            hm = re.match(r"\s*of\s+(" + re.escape(prefix) + r"-[0-9]+)\b", dl.group(2))
            head = hm.group(1) if hm else None
            if head is None:
                findings.append(("DUP-CHECK", iid, "SAME-DEFECT names no id (`SAME-DEFECT of <id>`)"))
            if not (closed_dup and head is not None and r["obsolete_superseding"] == head):
                findings.append(("DUP-SAME-OPEN", iid, "SAME-DEFECT of %s but not Obsolete duplicate-of %s" % (head, head)))
            t = all_items.get(head) if head else None
            if t is not None:
                if not is_open(t):
                    findings.append(("DUP-HEAD", iid, "%s is not an open head (status %s): resolve the chain (section 11.4.214(0))" % (head, t["status"])))
                else:
                    others = competing_heads(t, all_items, {iid}, prefix)
                    for y in sorted(others):
                        findings.append(("DUP-HEAD", iid, "more than one head (section 11.4.214(0)): %s" % others[y]))
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
        counts = ids_in(r["title"] + "\n" + r["description"] + "\n" + state_text(r), prefix)
        for ref in sorted(counts):
            ns = "foreign" if ref in fids else ("own" if ref in sel_ids else ("main" if ref in all_items else "unknown"))
            rows.append((r["id"], ref, ns, counts[ref]))
    return rows


# ---- loading ----------------------------------------------------------------------------------------

def make_row(cols, od=None, obd=None, hist=(), names=None):
    """An item row: every column under its own name, plus the aliases the checks read."""
    r = dict(cols)
    r["_cols"] = list(names if names is not None else cols.keys())
    r["id"] = cols["atm_id"]
    r["body"] = cols.get("body_md") or ""
    r["location"] = cols["current_location"]
    r["repro"] = cols.get("reproduction_state")
    r["inv"] = cols.get("investigation_state")
    r["od"], r["obd"], r["hist"] = od, obd, list(hist)
    r["obsolete_reason"] = od["reason"] if od else None
    r["obsolete_superseding"] = od["superseding_item"] if od else None
    return r


def check_values(table, rows):
    """A BLOB anywhere, or a non-text title, description, status or location, is BLIND (a crash or a
    false null otherwise)."""
    for row in rows:
        for name, v in row.items():
            if isinstance(v, (bytes, bytearray, memoryview)):
                raise Blind("a BLOB value in %s.%s (row %s)" % (table, name, row.get("atm_id")))
        if table == "items":
            for name in ("title", "description", "status", "current_location"):
                if not isinstance(row.get(name), str):
                    raise Blind("item %s has a NULL or non-text %s" % (row.get("atm_id"), name))
            if row.get("body_md") is not None and not isinstance(row["body_md"], str):
                raise Blind("item %s has a non-text body_md" % row.get("atm_id"))


def load(db):
    """(items, extras): every item (its first location row) with its obsolete_details,
    operator_block_details and item_history rows, and the rows of its other locations. A missing
    required table, an unreadable table, a non-text value or a non-empty -wal sidecar is BLIND."""
    wal = db + "-wal"
    if os.path.isfile(wal) and os.path.getsize(wal) > 0:
        raise Blind("%s has a non-empty -wal sidecar; checkpoint it first" % db)
    # the path is quoted: `?` and `#` in a file name are not URI syntax (round 4, R4-9)
    con = sqlite3.connect("file:%s?mode=ro" % urllib.parse.quote(os.path.abspath(db)), uri=True)
    try:
        tables = {r[0] for r in con.execute("select name from sqlite_master where type='table'")}
        missing = [t for t in REQUIRED_TABLES if t not in tables]
        if missing:
            raise Blind("required table(s) missing: " + ",".join(missing))
        con.row_factory = sqlite3.Row
        od_rows = [dict(r) for r in con.execute("select * from obsolete_details")]
        obd_rows = [dict(r) for r in con.execute("select * from operator_block_details")]
        hist_rows = [dict(r) for r in con.execute("select * from item_history order by id")]
        cur = con.execute("select * from items order by atm_id, current_location")
        names = [d[0] for d in cur.description]
        item_rows = [dict(r) for r in cur]
    finally:
        con.close()
    for table, rows in (("obsolete_details", od_rows), ("operator_block_details", obd_rows),
                        ("item_history", hist_rows), ("items", item_rows)):
        check_values(table, rows)
    od = {r["atm_id"]: r for r in od_rows}
    obd = {r["atm_id"]: r for r in obd_rows}
    hist = {}
    for h in hist_rows:
        hist.setdefault(h["atm_id"], []).append(h)
    items, extras = {}, {}
    for row in item_rows:
        i = row["atm_id"]
        r = make_row(row, od.get(i), obd.get(i), hist.get(i, ()), names)
        if i in items:  # a second location row is linted too (round 4, R4-6), never dropped
            extras.setdefault(i, []).append(r)
            continue
        items[i] = r
    return items, extras


def load_rendered(d):
    """id -> [(file, line)]: the lines of each item's section in Issues.md / Fixed.md and the summary
    rows whose id cell names it. Returns (map, files read)."""
    out, read = {}, []
    for fname in RENDERED_FILES:
        p = os.path.join(d, fname)
        if not os.path.isfile(p):
            continue
        try:
            with open(p, encoding="utf-8") as f:
                text = f.read()
        except (OSError, UnicodeDecodeError) as e:
            raise Blind("rendered document unreadable: %s (%s)" % (fname, e))
        read.append(fname)
        if fname.endswith("_Summary.md"):
            for line in text.split("\n"):
                if not line.startswith("|"):
                    continue
                for cell in line.split("|"):
                    cm = RENDERED_ID_CELL.match(cell.strip())
                    if cm:
                        out.setdefault(cm.group(1), []).append((fname, line))
                        break
        else:
            cur = None
            for line in text.split("\n"):
                if line.startswith("## "):
                    hm = RENDERED_HEADING.match(line)
                    cur = hm.group(1) if hm else None
                if cur:
                    out.setdefault(cur, []).append((fname, line))
    if not read:
        raise Blind("no rendered document in %s" % d)
    return out, read


# ---- self-check -------------------------------------------------------------------------------------

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
        ("password-assign-unquoted", "DB_PASS" + "WORD=" + "x" * 8, "DB_PASS" + "WORD=" + "x" * 7),
        ("basic-auth", "Authorization: " + "Basic " + a * 8, "Authorization: " + "Basic " + a * 7),
        ("stripe-key", "s" + "k_" + "live_" + a * 20, "s" + "k_" + "live_" + a * 19),
        ("npm-token", "np" + "m_" + a * 36, "np" + "m_" + a * 35),
        ("telegram-bot-token", "123456789" + ":AA" + a * 33, "123456789" + ":AA" + a * 32),
    ]


NEEDLE_SHA = "ab" * 32
NEEDLE_FILES = {"docs/qa/needle_present/x.txt": NEEDLE_SHA, "docs/operator_decisions/needle_present.md": "cd" * 32}


class NeedleFS:
    def exists(self, rel):
        return rel in NEEDLE_FILES

    def sha256(self, rel):
        return NEEDLE_FILES[rel]


GOOD_DESC = (
    "**What:** a needle.\n\n**Affected scope / file-scope manifest:**\nx/needle_only.sh\n\n"
    "**Reproduction / context:**\nnone\n\n**Acceptance criteria:**\nnone\n\nParent / links: ZZ-1 (the needle umbrella, the parent of this one); see ZZ-4 for the needle range\n"
    "Duplicate check (section 11.4.214): DISTINCT\n"
    "Context: ZZ-8..ZZ-10 of another tracker; evidence docs/qa/needle_present/x.txt; see x.bundle (ephemeral: a scratch file)\n"
    "Foreign ids (another tracker): ZZ-8..ZZ-10\n"
    "**Reproduction:** reproduced-live — REPRODUCED"
)
GOOD_KW = {
    "atm_id": "ZZ-2", "title": "Needle good item", "status": "Queued", "current_location": "Issues", "type": "Task",
    "severity": "Low", "created_by": "AI", "representation": "section", "description": GOOD_DESC,
    "reproduction_state": "reproduced-live", "reproduction_surface": "host-only",
    "reproduction_evidence": "docs/qa/needle_present/x.txt", "reproduction_red_cmd": "bash x/needle_only.sh",
    "reproduction_env": "needle host; evidence sha256 " + NEEDLE_SHA, "reproduction_signature": "needle `signature`",
    "reproduction_updated_at": "2026-11-13T00:00:00Z", "reproduction_updated_by": "needle",
}


def fx(**kw):
    """A fixture row; body_md is the engine rendering unless given."""
    od, obd, hist = kw.pop("od", None), kw.pop("obd", None), kw.pop("hist", ())
    cols = {c: None for c in ITEM_COLUMNS}
    cols.update(kw)
    r = make_row(cols, od, obd, hist, ITEM_COLUMNS)
    if "body_md" not in kw:
        r["body_md"] = r["body"] = engine_body(r)
    return r


def var(**kw):
    return fx(**dict(GOOD_KW, **kw))


def raw_body(row, body):
    row = dict(row)
    row["body_md"] = row["body"] = body
    return row


def selfcheck():
    """Control needles (section 11.4.201(7)(b)): every check must stay silent on the golden-good
    texts and fire on its golden-bad text; every secret pattern must fire on its positive needle and
    stay silent on its negative one; each scanned surface must carry a planted needle to a finding
    that names that surface. Returns a list of failed needle names."""
    umb = fx(atm_id="ZZ-1", title="Needle umbrella", description="umbrella", status="Queued", current_location="Issues", type="Task")
    rng = fx(atm_id="ZZ-4", title="Needle range holder", description="range holder", status="Queued", current_location="Issues", type="Task")
    good = var()
    allitems = {"ZZ-1": umb, "ZZ-2": good, "ZZ-4": rng}
    ex = NEEDLE_FILES.__contains__
    fs = NeedleFS()
    failed = []

    def run(row, items, rendered=None):
        return lint_items([row], items, "ZZ", True, "<needle>", ex, rendered, fs)

    d = GOOD_DESC
    od_dup = {"atm_id": "ZZ-2", "since": "2026-11-13", "reason": "duplicate-of", "superseding_item": "ZZ-1",
              "triple_check_evidence": "docs/qa/needle_present/x.txt"}
    close_rows = [{"id": 7, "atm_id": "ZZ-2", "event_type": "Obsolete", "by": "AI", "on_date": "2026-11-13",
                   "reason": "duplicate-of", "evidence_path": "docs/qa/needle_present/x.txt"}]
    reopen_rows = [{"id": 8, "atm_id": "ZZ-2", "event_type": "Reopened", "by": "AI", "on_date": "2026-11-13",
                    "reason": "design-reconsidered", "evidence_path": "docs/qa/needle_present/x.txt"}]
    dup_good = var(status="Obsolete", current_location="Fixed", od=od_dup, hist=close_rows,
                   description=d.replace(": DISTINCT", ": SAME-DEFECT of ZZ-1"))
    und_good = var(description=d.replace(": DISTINCT", ": UNDECIDED; candidate duplicates ZZ-1 and ZZ-4"))
    stale_good = var(status="Reopened", od=od_dup, hist=close_rows + reopen_rows,
                     description=d + "\nStale obsolete_details row (engine gap ZZ-4): kept by the engine")
    od_good = var(description=d.replace("docs/qa/needle_present/x.txt", "docs/operator_decisions/needle_present.md"),
                  reproduction_evidence="docs/operator_decisions/needle_present.md",
                  reproduction_env="needle host; evidence sha256 " + "cd" * 32)
    blocked_good = var(status="Operator-blocked", obd={"atm_id": "ZZ-2", "what": "needle block", "why_exhausted_alternatives": "w",
                                                     "unblock_condition": "[A] u", "who": "operator"})
    punct_good = var(description=d.replace("evidence docs/qa/needle_present/x.txt;", "evidence docs/qa/needle_present/x.txt. Also "
                                           "(docs/qa/needle_present/x.txt), docs/qa/needle_present/x.txt:"))
    distinct_link_good = fx(atm_id="ZZ-4", title="Needle range holder", status="Queued", current_location="Issues", type="Task",
                            description="range holder\nDuplicate check (section 11.4.214): DISTINCT (ZZ-1 is a different defect)")
    rendered_good = {"ZZ-2": [("Issues.md", "## ZZ-2 — Needle good item"), ("Issues_Summary.md", "| ZZ-2 | Task | needle |")]}
    # the end of a range keeps the clause it stands in (round 4: an endpos bound read `..` as a sentence end)
    range_mid = fx(atm_id="ZZ-3", title="Needle range middle", description="range middle", status="Queued",
                   current_location="Issues", type="Task")
    range_good = var(description=d + "\nthe needle umbrella to the needle range holder, ZZ-1..ZZ-4")
    for name, row, extra, rnd in (("golden-good", good, {}, None), ("golden-good-duplicate", dup_good, {}, None),
                                  ("golden-good-range-end-clause", range_good, {"ZZ-3": range_mid}, None),
                                  ("golden-good-undecided", und_good, {}, None), ("golden-good-stale-noted", stale_good, {}, None),
                                  ("golden-good-decision-path", od_good, {}, None), ("golden-good-blocked", blocked_good, {}, None),
                                  ("golden-good-trailing-punctuation", punct_good, {}, None),
                                  ("golden-good-head-distinct-link", dup_good, {"ZZ-4": distinct_link_good}, None),
                                  ("golden-good-rendered", good, {}, rendered_good)):
        got = run(row, dict(allitems, **dict({"ZZ-2": row}, **extra)), rnd)
        if got:
            failed.append("%s (%s)" % (name, ",".join(sorted({f[0] for f in got}))))
    gb = engine_body(good)
    head_umb = fx(atm_id="ZZ-1", title="Needle umbrella", description="umbrella; candidate duplicate ZZ-4, merge UNDECIDED",
                  status="Queued", current_location="Issues", type="Task")
    bad_cases = {
        "XREF-DANGLING": (var(description=d.replace("ZZ-1 (the needle umbrella, the parent of this one)", "ZZ-19")), {}),
        "XREF-DANGLING/range": (var(description=d.replace("Foreign ids (another tracker): ZZ-8..ZZ-10", "Foreign ids (another tracker): ZZ-8, ZZ-10")), {}),
        "XREF-DANGLING/range-interior-150": (var(description=d + "\nsee ZZ-4..ZZ-160 for the needle range", reproduction_signature="sig"), {}),
        "XREF-DANGLING/state-column": (var(reproduction_red_cmd="bash x/needle_only.sh ZZ-77"), {}),
        "XREF-LABEL": (var(description=d.replace("(the needle umbrella, the parent of this one)", "(GitHub issues sync)")), {}),
        "XREF-LABEL/one-shared-word": (var(description=d.replace("(the needle umbrella, the parent of this one)", "(umbrella of github runners)")), {}),
        "XREF-UNLABELLED": (var(description=d.replace("see ZZ-4 for the needle range", "related ZZ-4, not a parent")), {}),
        "FOREIGN-STALE": (var(description=d.replace("tracker): ZZ-8..ZZ-10", "tracker): ZZ-8..ZZ-10, ZZ-7")), {}),
        "STATE-PROSE": (var(description=d + "\nReproduction state: UNREPRODUCED."), {}),
        "STATE-PROSE/structured": (var(reproduction_state=None), {}),
        "STATE-PROSE/structured-investigation": (var(description=d + "\n**Investigation:** in-progress"), {}),
        "STATE-EVIDENCE": (var(reproduction_env="needle host"), {}),
        "STATE-EVIDENCE/sha-mismatch": (var(reproduction_env="needle host; evidence sha256 " + "ef" * 32), {}),
        "STATE-EVIDENCE/missing-file": (var(reproduction_evidence="docs/qa/needle_absent/x.txt"), {}),
        "STATE-EVIDENCE/investigation": (var(investigation_state="root-cause-found-with-evidence", investigation_root_cause="needle cause",
                                             investigation_evidence="docs/qa/needle_present/x.txt"), {}),
        "STATE-EVIDENCE/blocker": (var(reproduction_state="blocked-no-device-with-recorded-blocker",
                                       description=d.replace("**Reproduction:** reproduced-live — REPRODUCED", "")), {}),
        "SECTIONS": (var(description=d.replace("**Acceptance criteria:**", "Acceptance:")), {}),
        "BODY-SYNC": (raw_body(good, "something else"), {}),
        "BODY-SYNC/empty": (raw_body(good, ""), {}),
        "BODY-SYNC/header-line-separator": (raw_body(good, gb.replace("**Status:** Queued\n", "**Status:** Queued x\n")), {}),
        "BODY-SYNC/extra-paragraph": (raw_body(good, gb + "Update: already fixed; no work owed.\n"), {}),
        "BODY-SYNC/heading-id": (raw_body(good, gb.replace("## ZZ-2 — ", "## ZZ-3 — ")), {}),
        "BODY-SYNC/status-second": (raw_body(good, gb.replace("**Type:** Task\n", "**Type:** Task\n**Status:** Fixed\n")), {}),
        "BODY-SYNC/status-value": (raw_body(good, gb.replace("**Status:** Queued", "**Status:** Queued later")), {}),
        "BODY-SYNC/type": (raw_body(good, gb.replace("**Type:** Task", "**Type:** Bug")), {}),
        "BODY-SYNC/severity": (raw_body(good, gb.replace("**Severity:** Low", "**Severity:** Critical")), {}),
        "BODY-SYNC/created-by": (raw_body(good, gb.replace("**Created-By:** AI", "**Created-By:** User")), {}),
        "BODY-SYNC/assigned-to-extra": (raw_body(good, gb.replace("**Type:** Task\n", "**Type:** Task\n**Assigned-To:** someone\n")), {}),
        "BODY-SYNC/severity-missing": (raw_body(good, gb.replace("**Severity:** Low\n", "")), {}),
        "BODY-SYNC/reproduction-detail": (raw_body(good, gb.replace("needle `signature`", "other `signature`")), {}),
        "BODY-SYNC/investigation-extra": (raw_body(good, gb.replace("**Type:** Task\n", "**Type:** Task\n**Investigation:** in-progress\n")), {}),
        "BODY-SYNC/obsolete-missing": (raw_body(dup_good, engine_body(dup_good).replace(obsolete_line(od_dup) + "\n", "")), {}),
        "BODY-SYNC/obsolete-content": (raw_body(dup_good, engine_body(dup_good).replace("Superseding-item: ZZ-1", "Superseding-item: ZZ-4")), {}),
        "BODY-SYNC/obsolete-on-open": (raw_body(good, gb.replace("**Type:** Task\n", "**Type:** Task\n" + obsolete_line(od_dup) + "\n")), {}),
        "BODY-SYNC/evidence": (raw_body(good, gb.replace("**Type:** Task\n", "**Type:** Task\n**Evidence:** docs/qa/needle_present/x.txt\n")), {}),
        "BODY-SYNC/reopened-without-row": (raw_body(good, gb.replace("**Type:** Task\n", "**Type:** Task\n" + reopen_line(reopen_rows[0]) + "\n")), {}),
        "BODY-SYNC/block-without-row": (raw_body(good, gb.replace("**Type:** Task\n", "**Type:** Task\n**Operator-Block-Details:** WHAT: x\n")), {}),
        "BODY-SYNC/unknown-key": (raw_body(good, gb.replace("**Type:** Task\n", "**Type:** Task\n**Priority:** P1\n")), {}),
        "SECRET": (var(description=d + "\nkey AK" + "IA" + "ABCDEFGHIJKLMNOP"), {}),
        "SECRET/state-column": (var(reproduction_env="needle host; evidence sha256 " + NEEDLE_SHA + "; key AK" + "IA" + "ABCDEFGHIJKLMNOP"), {}),
        "EPHEMERAL": (var(description=d + "\nsee review_x_r1.md"), {}),
        "EPHEMERAL/note-needs-parenthesis": (var(description=d + "\nan ephemeral copy at /tmp/needle/x"), {}),
        "EPHEMERAL/mktemp-default": (var(description=d + "\nlog at /tmp/tmp." + "k3Jx9QvT2a" + "/out.txt"), {}),
        "EPHEMERAL/mktemp-default-lowercase": (var(description=d + "\nwork dir tmp." + "qwertyuiop" + " kept"), {}),
        "EPHEMERAL/lowercase-dir": (var(description=d + "\nsee scratch." + "zobh" + "/c"), {}),
        "EPHEMERAL/4-char": (var(description=d + "\nsee scratch." + "Ab3d" + " for it"), {}),
        "EPHEMERAL/home-path": (var(description=d + "\nfile /ho" + "me/needleuser/x.txt"), {}),
        "EPHEMERAL/home-dotdir": (var(description=d + "\nfile ~/.needle" + "tool/x.txt"), {}),
        "EPHEMERAL/session-store": (var(description=d + "\nfile .claude-needle/" + "projects/abc/x.jsonl"), {}),
        "EPHEMERAL/state-column": (var(reproduction_red_cmd="bash /tmp/" + "needle/x.sh"), {}),
        "CONTROL-CHAR/title": (var(title="Needle good item"), {}),
        "CONTROL-CHAR/nul": (var(description=d + "\nnul\x00here"), {}),
        "CONTROL-CHAR/title-tab": (var(title="Needle\tgood item"), {}),
        "CONTROL-CHAR/bidi": (var(description=d + "\nbidi\u202ehere"), {}),
        "XREF-DANGLING/non-ascii-digits": (var(description=d + "\nsee ZZ-\uff13"), {}),
        "DUP-CHECK": (var(description=d.replace(": DISTINCT", ": PROBABLY")), {}),
        "DUP-SAME-OPEN": (var(description=d.replace(": DISTINCT", ": SAME-DEFECT of ZZ-1")), {}),
        "DUP-SAME-OPEN/wrong-head": (var(status="Obsolete", current_location="Fixed", od=dict(od_dup, superseding_item="ZZ-4"),
                                         hist=close_rows, description=d.replace(": DISTINCT", ": SAME-DEFECT of ZZ-1")), {}),
        "DUP-SAME-OPEN/head-is-first-id": (var(status="Obsolete", current_location="Fixed", od=dict(od_dup, superseding_item="ZZ-4"),
                                               hist=close_rows, description=d.replace(": DISTINCT", ": SAME-DEFECT of ZZ-1 (see also ZZ-4)")), {}),
        "DUP-HEAD": (dup_good, {"ZZ-1": head_umb}),
        "DUP-HEAD/head-closed": (dup_good, {"ZZ-1": fx(atm_id="ZZ-1", title="Needle umbrella", description="umbrella",
                                                      status="Fixed", current_location="Fixed", type="Task")}),
        "DUP-HEAD/lowercase": (dup_good, {"ZZ-1": fx(atm_id="ZZ-1", title="Needle umbrella", status="Queued", current_location="Issues", type="Task",
                                                    description="umbrella; candidate ZZ-4, merge undecided")}),
        "DUP-HEAD/wording": (dup_good, {"ZZ-1": fx(atm_id="ZZ-1", title="Needle umbrella", status="Queued", current_location="Issues", type="Task",
                                                  description="umbrella; ZZ-4 is a possible second head, open question")}),
        "DUP-HEAD/reverse": (dup_good, {"ZZ-4": fx(atm_id="ZZ-4", title="Needle range holder", status="Queued", current_location="Issues", type="Task",
                                                  description="range holder\nDuplicate check (section 11.4.214): undecided; candidate ZZ-1")}),
        "DUP-HEAD/stale-row": (dup_good, {"ZZ-4": fx(atm_id="ZZ-4", title="Needle range holder", status="Reopened", current_location="Issues", type="Task",
                                                    description="range holder", od=dict(od_dup, atm_id="ZZ-4"))}),
        "DUP-UNDECIDED": (var(description=d.replace(": DISTINCT", ": UNDECIDED")), {}),
        "DUP-STATUS": (var(status="Obsolete", current_location="Fixed", od=od_dup, hist=close_rows,
                           description=d.replace(": DISTINCT", ": UNDECIDED; candidate ZZ-1")), {}),
        "OBSOLETE-STALE": (var(status="Reopened", od=od_dup, hist=close_rows + reopen_rows), {}),
        "SHARED-PATH": (good, {"ZZ-3": fx(atm_id="ZZ-3", title="other open", description="touches x/needle_only.sh",
                                         status="Queued", current_location="Issues", type="Task")}),
        "PATH-MISSING": (var(description=d.replace("needle_present", "needle_absent_zz9")), {}),
        "PATH-MISSING/decisions": (var(description=od_good["description"].replace("needle_present.md", "needle_absent.md"),
                                       reproduction_evidence="docs/operator_decisions/needle_present.md",
                                       reproduction_env="needle host; evidence sha256 " + "cd" * 32), {}),
    }
    # Each golden-bad case names the check it proves: a finding of the case's code is not enough,
    # because a second check under the same code can catch the same text (round 4: the line-separator
    # case was also caught by the Status-value compare, so switching the separator check off left the
    # needle silent). The finding must carry the named check's own message text.
    check_text = {
        "XREF-DANGLING": "ZZ-19", "XREF-DANGLING/range": "ZZ-9", "XREF-DANGLING/range-interior-150": "ZZ-100",
        "XREF-DANGLING/state-column": "ZZ-77", "XREF-LABEL": "(GitHub issues sync) vs title",
        "XREF-LABEL/one-shared-word": "(umbrella of github runners) vs title",
        "XREF-UNLABELLED": "without a label in a clause", "FOREIGN-STALE": "ZZ-7",
        "STATE-PROSE": "prose says UNREPRODUCED", "STATE-PROSE/structured": "structured line says reproduced-live",
        "STATE-PROSE/structured-investigation": "structured line says in-progress",
        "STATE-EVIDENCE": "reproduction_state reproduced-live carries no evidence sha256",
        "STATE-EVIDENCE/sha-mismatch": "sha256 differs from the file", "STATE-EVIDENCE/missing-file": "does not exist",
        "STATE-EVIDENCE/investigation": "investigation_state root-cause-found-with-evidence carries no evidence",
        "STATE-EVIDENCE/blocker": "without a reproduction_blocker", "SECTIONS": "missing: Acceptance criteria",
        "BODY-SYNC": "description is not contained in body_md", "BODY-SYNC/empty": "body_md is empty",
        "BODY-SYNC/header-line-separator": "line separator other than a newline",
        "BODY-SYNC/extra-paragraph": "text after the description", "BODY-SYNC/heading-id": "heading disagrees",
        "BODY-SYNC/status-second": "key Status is written twice",
        "BODY-SYNC/status-value": "Status line differs from its source", "BODY-SYNC/type": "Type line differs",
        "BODY-SYNC/severity": "Severity line differs", "BODY-SYNC/created-by": "Created-By line differs",
        "BODY-SYNC/assigned-to-extra": "has an Assigned-To line while its source gives none",
        "BODY-SYNC/severity-missing": "lacks the Severity line", "BODY-SYNC/reproduction-detail": "Reproduction line differs",
        "BODY-SYNC/investigation-extra": "has an Investigation line while",
        "BODY-SYNC/obsolete-missing": "lacks the Obsolete-Details line",
        "BODY-SYNC/obsolete-content": "Obsolete-Details line differs",
        "BODY-SYNC/obsolete-on-open": "has an Obsolete-Details line while",
        "BODY-SYNC/evidence": "Evidence line names no closure evidence",
        "BODY-SYNC/reopened-without-row": "no Reopened history row",
        "BODY-SYNC/block-without-row": "no operator_block_details row", "BODY-SYNC/unknown-key": "is not an engine key",
        "SECRET": "aws-access-key-id on description", "SECRET/state-column": "items.reproduction_env",
        "EPHEMERAL": "bare-review-file:", "EPHEMERAL/note-needs-parenthesis": "tmp-path: /tmp/needle/x on",
        "EPHEMERAL/mktemp-default": "mktemp-default: tmp.k3Jx9QvT2a",
        "EPHEMERAL/mktemp-default-lowercase": "mktemp-default: tmp.qwertyuiop",
        "EPHEMERAL/lowercase-dir": "mktemp-dir: scratch.zobh", "EPHEMERAL/4-char": "mktemp-dir: scratch.Ab3d",
        "EPHEMERAL/home-path": "home-path: /home/needleuser/", "EPHEMERAL/home-dotdir": "home-path: ~/.needletool/",
        "EPHEMERAL/session-store": "session-store:", "EPHEMERAL/state-column": "items.reproduction_red_cmd",
        "CONTROL-CHAR/title": "U+2028 on title", "CONTROL-CHAR/nul": "U+0000",
        "CONTROL-CHAR/title-tab": "newline or tab in the title", "DUP-CHECK": "not in the closed set",
        "CONTROL-CHAR/bidi": "U+202E", "XREF-DANGLING/non-ascii-digits": "(non-ASCII digits)",
        "DUP-SAME-OPEN": "but not Obsolete duplicate-of ZZ-1", "DUP-SAME-OPEN/wrong-head": "but not Obsolete duplicate-of ZZ-1",
        "DUP-SAME-OPEN/head-is-first-id": "but not Obsolete duplicate-of ZZ-1",
        "DUP-HEAD": "ZZ-1 names ZZ-4 as a duplicate", "DUP-HEAD/head-closed": "is not an open head",
        "DUP-HEAD/lowercase": "ZZ-1 names ZZ-4 as a duplicate", "DUP-HEAD/wording": "ZZ-1 names ZZ-4 as a duplicate",
        "DUP-HEAD/reverse": "ZZ-4 names ZZ-1 as a duplicate", "DUP-HEAD/stale-row": "is open with an obsolete_details row",
        "DUP-UNDECIDED": "names no candidate id", "DUP-STATUS": "but the verdict is UNDECIDED",
        "OBSOLETE-STALE": "on a Reopened item", "SHARED-PATH": "also named by open ZZ-3",
        "PATH-MISSING": "needle_absent_zz9", "PATH-MISSING/decisions": "needle_absent.md",
    }
    if set(check_text) != set(bad_cases):  # a case without its check text, or a text without a case
        failed.append("golden-bad/check-text-map")
    for code, (row, extra) in bad_cases.items():
        items = dict(allitems, **{"ZZ-2": row})
        items.update(extra)
        want = check_text.get(code, "\0")
        if not any(f[0] == code.split("/")[0] and want in f[2] for f in run(row, items)):
            failed.append(code)
    # one needle per surface: a planted credential shape, ephemeral path and control character must be
    # reported with that surface named
    key = "AK" + "IA" + "ABCDEFGHIJKLMNOP"
    planted = {
        "title": lambda s: var(title="Needle good item " + s),
        "description": lambda s: var(description=d + "\n" + s),
        "body_md": lambda s: raw_body(good, gb.replace("\n\n" + d, "\n\n" + d + "\n" + s, 1)),
        "items.reproduction_signature": lambda s: var(reproduction_signature="needle " + s),
        "items.closure_criteria": lambda s: var(closure_criteria=s),
        "obsolete_details.triple_check_evidence": lambda s: var(status="Reopened", od=dict(od_dup, triple_check_evidence=s),
                                                                description=d + "\nStale obsolete_details row (engine gap ZZ-4): kept"),
        "operator_block_details.why_exhausted_alternatives": lambda s: var(
            status="Operator-blocked", obd={"atm_id": "ZZ-2", "what": "w", "why_exhausted_alternatives": s, "unblock_condition": "u", "who": "o"}),
        "item_history[9].reason": lambda s: var(hist=[{"id": 9, "atm_id": "ZZ-2", "event_type": "Updated", "by": "AI", "reason": s}]),
    }
    for surface, make in planted.items():
        for code, s in (("SECRET", key), ("EPHEMERAL", "/tmp/" + "needle/x"), ("CONTROL-CHAR", "x\x07y")):
            row = make(s)
            got = [f for f in run(row, dict(allitems, **{"ZZ-2": row})) if f[0] == code]
            if not any(surface in f[2].split(" on ", 1)[-1].split(",") for f in got):
                failed.append("surface/%s/%s" % (code, surface))
    for code, s in (("SECRET", key), ("EPHEMERAL", "/tmp/" + "needle/x"), ("CONTROL-CHAR", "x\x07y")):
        rnd = {"ZZ-2": [("Issues.md", "## ZZ-2 — Needle good item"), ("Issues_Summary.md", "| ZZ-2 | " + s + " |")]}
        got = [f for f in run(good, allitems, rnd) if f[0] == code]
        if not any("rendered:Issues_Summary.md" in f[2] for f in got):
            failed.append("surface/%s/rendered" % code)
    for name, pos, neg in secret_needles():
        pat = dict(SECRET_PATTERNS).get(name)
        if pat is None or not pat.search("x " + pos + " y") or pat.search("x " + neg + " y"):
            failed.append("SECRET/" + name)
    if len(secret_needles()) != len(SECRET_PATTERNS):
        failed.append("SECRET/needle-count")
    return failed


# ---- main -------------------------------------------------------------------------------------------

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
    ap.add_argument("--rendered")
    ap.add_argument("--no-rendered", action="store_true")
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
    if a.rendered and a.no_rendered:
        print("intake_lint: --rendered and --no-rendered exclude each other", file=sys.stderr)
        return 2
    rendered_dir = None
    if not a.no_rendered:
        rendered_dir = a.rendered or (os.path.join(a.repo_root, "docs") if a.repo_root else None)
    if not a.no_selfcheck:
        bad = selfcheck()
        if bad:
            print("BLIND: control needle failed: " + ",".join(bad), file=sys.stderr)
            return 3
    if not os.path.isfile(a.db):
        print("BLIND: database not found: %s" % a.db, file=sys.stderr)
        return 3
    want = set()
    for lst in a.ids:
        want |= {x.strip() for x in lst.split(",") if x.strip()}
    # a crash is never a result: any unexpected error is BLIND (exit 3), never a traceback read as a
    # finding (exit 1) or a silent pass; the selection runs inside this block too (M-3)
    rows, raw, files = [], [], []
    try:
        items, extras = load(a.db)
        if not items:
            raise Blind("database holds no items")
        counts = {}
        for i in items:
            p = i.rsplit("-", 1)[0]
            counts[p] = counts.get(p, 0) + 1
        prefix = a.prefix or max(sorted(counts), key=lambda k: counts[k])
        if not any(id_re(prefix).fullmatch(i) for i in items):
            raise Blind("no item in the database carries the prefix %s: the id checks could not see" % prefix)
        missing = sorted(want - set(items))
        if missing:
            raise Blind("selected ids not in the database: " + ",".join(missing))
        sel = [r for i, r in sorted(items.items()) if i in want or any(o in r["description"] for o in a.origin)]
        if not sel:
            raise Blind("the selection is empty")
        rendered = {}
        if rendered_dir:
            rendered, files = load_rendered(rendered_dir)
            unseen = sorted(r["id"] for r in sel if r["id"] not in rendered)
            if unseen:
                raise Blind("selected item(s) absent from every rendered document: " + ",".join(unseen[:5]))
        if a.embeddings:
            rows = embeddings(sel, items, prefix)
        else:
            raw = lint_items(sel, items, prefix, a.require_dup_check, a.repo_root, rendered=rendered)
            for r in sel:
                for e in extras.get(r["id"], ()):
                    for f in lint_items([e], dict(items, **{r["id"]: e}), prefix, a.require_dup_check, a.repo_root,
                                        rendered=rendered):
                        if f not in raw:
                            raw.append((f[0], f[1], "%s [%s row]" % (f[2], e["location"])))
    except Blind as e:
        print("BLIND: %s" % e, file=sys.stderr)
        return 3
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
    print("RESULT: %s selected=%d findings=%d prefix=%s rendered=%s" % (
        "PASS" if not findings else "FAIL", len(sel), len(findings), prefix, ",".join(files) or "none"))
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
