#!/usr/bin/env python3
# scripts/workable-items/intake_lint.py -- read-only CONTENT lint for a set of workable items
# (an intake batch) in a workable-items SQLite database.
#
# Documentation (section 11.4.18): docs/guides/intake_lint_guide.md (user guide and manual).
#
# WHY  `workable-items validate` and `diff` prove the closed sets, the description floor and the
#   DB-to-Markdown sync. They do not read what a description SAYS. The independent review of the
#   2026-11-12 tracker-intake vehicle found two wrong tracker facts that both passed validate and
#   diff: a duplicate of two open items (section 11.4.214) and a cross-reference that named an
#   anchor number as if it were an item id. Its data mutants M2, M3, M9, M10 and M11 (description
#   and body diverge, dangling umbrella id, a secret-shaped string, a missing section header, a
#   state written in prose that disagrees with the state column) also survived. This lint checks
#   those classes for a SELECTED set of items, deterministically, and never writes.
#
# USAGE
#   python3 -I scripts/workable-items/intake_lint.py --db <db> (--origin <text> | --ids <A,B,..>)...
#           [--prefix CON] [--require-dup-check] [--repo-root DIR] [--skip-check CODES]
#           [--embeddings] [--no-selfcheck]
#   --origin TEXT    select every item whose description contains TEXT (repeatable)
#   --ids LIST       select these item ids (comma list, repeatable)
#   --prefix P       id prefix of this tracker (default: the most common prefix in the DB)
#   --require-dup-check
#                    every selected item must carry a `Duplicate check (section 11.4.214):` line
#                    with a verdict from {DISTINCT, DISTINCT-but-similar, SAME-DEFECT, UNDECIDED}
#   --embeddings     print every id embedded in the selected items' text (own / foreign / main)
#                    as TSV and exit 0; for the lander's re-mint (section 11.4.214)
#   --repo-root DIR  enable PATH-MISSING against this checkout
#   --skip-check C   comma list of finding codes not to report (repeatable; an unknown code is a
#                    usage error); a skipped code must be stated wherever the result is cited
#   --no-selfcheck   skip the built-in control needles (tests only; never in a gate)
#
# CHECKS (finding codes; each finding is one line `FINDING <code> <item> <detail>`)
#   XREF-DANGLING    an id of this tracker named in the text does not exist and is not declared foreign
#   XREF-LABEL       `<id> (<label>)`: no significant word of the label is in the target's title
#   FOREIGN-STALE    a `Foreign ids` line declares an id the rest of the text never names
#   STATE-PROSE      a closed reproduction/investigation state word in prose, or a hand-written
#                    `**Reproduction:**` / `**Investigation:**` line in the description, disagrees with
#                    the item's state column (section 11.4.294(A): the column is the source)
#   SECTIONS         a section 11.4.148 marker is missing (What, Affected scope, Reproduction /
#                    context, Acceptance criteria, Parent / links)
#   BODY-SYNC        the description is not contained in body_md (they diverged)
#   SECRET           a credential-shaped string (pattern name printed, never the match; section 11.4.10)
#   EPHEMERAL        a session-scratchpad location, a mktemp-shaped directory, a .bundle file or a bare
#                    review_*.md / *_lander_items.md name (not under docs/) with no `(ephemeral` note
#   SHARED-PATH      a file named in the item's Affected-scope section is named by an OPEN item outside
#                    the selection, and the Duplicate check line does not name that item
#   DUP-CHECK        (--require-dup-check) the line is missing or its verdict is outside the closed set
#   DUP-SAME-OPEN    the verdict is SAME-DEFECT but the item is not Obsolete duplicate-of the named id
#   PATH-MISSING     (--repo-root) a cited docs/qa/ or docs/operator_decisions/ path does not exist
#
# EXIT  0 no finding; 1 findings; 2 usage error; 3 BLIND (database unreadable, empty selection, or a
#   built-in control needle failed: the instrument could not see, so no verdict is given).
# EVIDENCE CLASS  gate-logic only (section 11.4.289): it reads text, it does not prove an item true.
import argparse
import os
import re
import sqlite3
import sys

STOP = set(
    "the a an on in of to is and or for with by from not no as at be it its this that are was when "
    "into than then there their these those over under after again only also each every item items "
    "vehicle review issue issues sync".split()
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
SECRET_PATTERNS = [
    ("aws-access-key-id", re.compile(r"\b(?:AKIA|ASIA)[0-9A-Z]{16}\b")),
    ("github-pat", re.compile(r"\bgh[pousr]_[A-Za-z0-9]{36,}\b")),
    ("github-fine-grained-pat", re.compile(r"\bgithub_pat_[A-Za-z0-9_]{40,}\b")),
    ("gcp-api-key", re.compile(r"\bAIza[0-9A-Za-z_-]{35}\b")),
    ("private-key-block", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    ("huggingface-token", re.compile(r"\bhf_[A-Za-z0-9]{30,}\b")),
    ("jwt", re.compile(r"\beyJ[A-Za-z0-9_-]{8,}\.eyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]+")),
    ("slack-token", re.compile(r"\bxox[abposr]-[A-Za-z0-9-]{10,}\b")),
    ("openai-style-key", re.compile(r"\bsk-[A-Za-z0-9_-]{32,}\b")),
]
EPHEMERAL_PATTERNS = [
    ("scratchpad", re.compile(r"scratchpad|/\.cache/claude-tmp/", re.I)),
    ("mktemp-dir", re.compile(r"(?<![\w/.-])[\w-]+\.(?=[A-Za-z0-9]*[A-Z])(?=[A-Za-z0-9]*[a-z0-9])[A-Za-z0-9]{4,6}(?=[/,;)\s]|$)")),
    ("bundle-file", re.compile(r"[\w./-]+\.bundle\b")),
    ("bare-review-file", re.compile(r"(?<![\w/.-])(?:review_[\w-]+\.(?:md|txt)|[\w-]+_lander_items\.md|review_[\w-]+_logs/)")),
]
CODES = {
    "XREF-DANGLING", "XREF-LABEL", "FOREIGN-STALE", "STATE-PROSE", "SECTIONS", "BODY-SYNC", "SECRET",
    "EPHEMERAL", "SHARED-PATH", "DUP-CHECK", "DUP-SAME-OPEN", "PATH-MISSING",
}
DUP_LINE = re.compile(r"^Duplicate check \(section 11\.4\.214\):\s*(\S+)(.*)$", re.M)
DUP_VERDICTS = {"DISTINCT", "DISTINCT-but-similar", "SAME-DEFECT", "UNDECIDED"}
FOREIGN_LINE = re.compile(r"^Foreign ids\b[^:]*:(.*)$", re.M)
EVIDENCE_PATH = re.compile(r"(?<![\w./-])(docs/(?:qa|operator_decisions)/[\w./-]*[\w/])")
PATH_IN_SCOPE = re.compile(r"(?<![\w.-])((?:[\w.-]+/)*[\w.-]+\.(?:sh|py|go|tsv|yaml|yml|json))\b")


def words(s):
    return {t for t in re.split(r"[^a-z0-9_]+", s.lower()) if len(t) >= 4 and t not in STOP and not t.isdigit()}


def id_re(prefix):
    return re.compile(r"(?<![\w-])" + re.escape(prefix) + r"-(\d+)\b(?!-)")


def strip_structured_state_lines(desc):
    return "\n".join(
        l for l in desc.split("\n") if not (l.startswith("**Reproduction:**") or l.startswith("**Investigation:**"))
    )


def scope_section(desc):
    m = re.search(r"^\*\*Affected scope / file-scope manifest:\*\*\n(.*?)(?:\n\n|\Z)", desc, re.S | re.M)
    return m.group(1) if m else ""


def foreign_ids(desc, rx):
    out = set()
    for m in FOREIGN_LINE.finditer(desc):
        out |= {x.group(0) for x in rx.finditer(m.group(1))}
    return out


def text_without_foreign_line(desc):
    return FOREIGN_LINE.sub("", desc)


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
        fids = foreign_ids(desc, rx)
        body_text = r["title"] + "\n" + text_without_foreign_line(desc)
        named = {m.group(0) for m in rx.finditer(body_text)}
        # XREF-DANGLING / XREF-LABEL
        for m in rx.finditer(body_text):
            ref = m.group(0)
            if ref in fids:
                continue
            if ref not in all_items:
                findings.append(("XREF-DANGLING", iid, ref))
                continue
            lab = re.match(r"\s*\(([^()]{2,80})\)", body_text[m.end():])
            if lab and ref != iid:
                lw = words(lab.group(1))
                if lw and not (lw & words(all_items[ref]["title"])):
                    findings.append(("XREF-LABEL", iid, "%s (%s) vs title: %s" % (ref, lab.group(1), all_items[ref]["title"][:60])))
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
        # description (the engine renders these lines into body_md from the columns) must name the
        # column's state (reviewer mutant M11)
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
        # BODY-SYNC
        if r["body"] and desc not in r["body"]:
            findings.append(("BODY-SYNC", iid, "description is not contained in body_md"))
        # SECRET
        for name, pat in SECRET_PATTERNS:
            if pat.search(r["title"] + "\n" + desc):
                findings.append(("SECRET", iid, name))
        # EPHEMERAL (a line that carries an "(ephemeral" note is exempt; the note covers its own line only)
        for line in desc.split("\n"):
            if "(ephemeral" in line:
                continue
            for name, pat in EPHEMERAL_PATTERNS:
                if pat.search(line):
                    findings.append(("EPHEMERAL", iid, "%s: %s" % (name, pat.search(line).group(0)[:60])))
        # PATH-MISSING (only with --repo-root): a cited evidence path under docs/qa/ or
        # docs/operator_decisions/ must exist in the repository (section 11.4.215)
        if repo_root:
            for m in EVIDENCE_PATH.finditer(desc):
                rel = m.group(1).rstrip(".,;:)")
                if not exists(rel):
                    findings.append(("PATH-MISSING", iid, rel))
        # DUP-CHECK / DUP-SAME-OPEN / SHARED-PATH
        dl = DUP_LINE.search(desc)
        dup_named = {m.group(0) for m in rx.finditer(dl.group(0))} if dl else set()
        if require_dup:
            if not dl:
                findings.append(("DUP-CHECK", iid, "no `Duplicate check (section 11.4.214):` line"))
            elif dl.group(1).rstrip(";,.:") not in DUP_VERDICTS:
                findings.append(("DUP-CHECK", iid, "verdict %r not in the closed set" % dl.group(1)))
        if dl and dl.group(1).rstrip(";,.:") == "SAME-DEFECT":
            head = r["obsolete_superseding"]
            if not (r["status"].startswith("Obsolete") and r["obsolete_reason"] == "duplicate-of" and head in dup_named):
                findings.append(("DUP-SAME-OPEN", iid, "SAME-DEFECT but not Obsolete duplicate-of a named id"))
        names = {p.rsplit("/", 1)[-1] for p in PATH_IN_SCOPE.findall(scope_section(desc))}
        names = {n for n in names if len(n) >= 8}
        for o in open_others:
            otext = o["title"] + "\n" + o["description"]
            hit = sorted(n for n in names if re.search(r"(?<![\w.-])" + re.escape(n) + r"(?![\w-])", otext))
            if hit and o["id"] not in dup_named:
                findings.append(("SHARED-PATH", iid, "%s also named by open %s" % (hit[0], o["id"])))
    return findings


def embeddings(sel, all_items, prefix):
    rx = id_re(prefix)
    sel_ids = {r["id"] for r in sel}
    rows = []
    for r in sel:
        fids = foreign_ids(r["description"], rx)
        counts = {}
        for m in rx.finditer(r["title"] + "\n" + r["description"]):
            counts[m.group(0)] = counts.get(m.group(0), 0) + 1
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


SELF_GOOD = {
    "id": "ZZ-2", "title": "Needle good item", "status": "Queued", "location": "Issues", "repro": "reproduced-live", "inv": "UNSET",
    "obsolete_reason": None, "obsolete_superseding": None,
    "description": "**What:** a needle.\n\n**Affected scope / file-scope manifest:**\nx/needle_only.sh\n\n"
    "**Reproduction / context:**\nnone\n\n**Acceptance criteria:**\nnone\n\nParent / links: ZZ-1 (needle umbrella)\n"
    "Duplicate check (section 11.4.214): DISTINCT\n"
    "Context: ZZ-8 of another tracker; evidence docs/qa/needle_present/x.txt; see x.bundle (ephemeral: a scratch file)\n"
    "Foreign ids (another tracker): ZZ-8\n"
    "**Reproduction:** reproduced-live — REPRODUCED",
}
NEEDLE_EXISTS = {"docs/qa/needle_present/x.txt"}


def selfcheck():
    """Control needles (section 11.4.201(7)(b)): every check must stay silent on the golden-good
    texts (which carry a declared foreign id, an existing evidence path, a noted ephemeral name, a
    structured state line and a correct duplicate-of row) and fire on its golden-bad text.
    Returns a list of failed needle names."""
    base = {"ZZ-1": dict(SELF_GOOD, id="ZZ-1", title="Needle umbrella", description="umbrella", body="")}
    good = dict(SELF_GOOD, body=SELF_GOOD["description"] + "\n")
    allitems = dict(base, **{"ZZ-2": good})
    ex = lambda rel: rel in NEEDLE_EXISTS
    failed = []

    def run(row, items):
        return {f[0] for f in lint_items([row], items, "ZZ", True, "<needle>", ex)}

    d = good["description"]
    dup_good = dict(good, status="Obsolete", obsolete_reason="duplicate-of", obsolete_superseding="ZZ-1",
                    description=d.replace(": DISTINCT", ": SAME-DEFECT of ZZ-1"))
    dup_good["body"] = dup_good["description"]
    for name, row in (("golden-good", good), ("golden-good-duplicate", dup_good)):
        if run(row, dict(allitems, **{"ZZ-2": row})):
            failed.append(name)
    bad_cases = {
        "XREF-DANGLING": dict(good, description=d.replace("ZZ-1 (needle umbrella)", "ZZ-9")),
        "XREF-LABEL": dict(good, description=d.replace("(needle umbrella)", "(GitHub issues sync)")),
        "FOREIGN-STALE": dict(good, description=d.replace("Foreign ids (another tracker): ZZ-8", "Foreign ids (another tracker): ZZ-8, ZZ-7")),
        "STATE-PROSE": dict(good, description=d + "\nReproduction state: UNREPRODUCED."),
        "STATE-PROSE/structured": dict(good, repro="UNSET"),
        "SECTIONS": dict(good, description=d.replace("**Acceptance criteria:**", "Acceptance:")),
        "BODY-SYNC": dict(good, body="something else"),
        "SECRET": dict(good, description=d + "\nkey AKIA" + "ABCDEFGHIJKLMNOP"),
        "EPHEMERAL": dict(good, description=d + "\nsee review_x_r1.md"),
        "DUP-CHECK": dict(good, description=d.replace(": DISTINCT", ": PROBABLY")),
        "DUP-SAME-OPEN": dict(good, description=d.replace(": DISTINCT", ": SAME-DEFECT of ZZ-1")),
        "SHARED-PATH": dict(good),
        "PATH-MISSING": dict(good, description=d.replace("needle_present", "needle_absent_zz9")),
    }
    for code, row in bad_cases.items():
        if code != "BODY-SYNC":
            row = dict(row, body=row["description"])
        items = dict(allitems, **{"ZZ-2": row})
        if code == "SHARED-PATH":
            items["ZZ-3"] = dict(SELF_GOOD, id="ZZ-3", title="other open", description="touches x/needle_only.sh", body="")
        if code.split("/")[0] not in run(row, items):
            failed.append(code)
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
    prefix = a.prefix
    if not prefix:
        counts = {}
        for i in items:
            p = i.rsplit("-", 1)[0]
            counts[p] = counts.get(p, 0) + 1
        prefix = max(sorted(counts), key=lambda k: counts[k])
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
    if a.embeddings:
        print("item\tembedded_id\tnamespace\tcount")
        for row in embeddings(sel, items, prefix):
            print("%s\t%s\t%s\t%d" % row)
        return 0
    skip = set()
    for lst in a.skip_check:
        skip |= {x.strip() for x in lst.split(",") if x.strip()}
    unknown = sorted(skip - CODES)
    if unknown:
        print("intake_lint: unknown --skip-check code(s): " + ",".join(unknown), file=sys.stderr)
        return 2
    findings = []
    if a.repo_root and not os.path.isdir(a.repo_root):
        print("intake_lint: --repo-root is not a directory: %s" % a.repo_root, file=sys.stderr)
        return 2
    for f in lint_items(sel, items, prefix, a.require_dup_check, a.repo_root):
        if f[0] not in skip and f not in findings:
            findings.append(f)
    for code, iid, detail in findings:
        print("FINDING %s %s %s" % (code, iid, detail))
    print("RESULT: %s selected=%d findings=%d prefix=%s" % ("PASS" if not findings else "FAIL", len(sel), len(findings), prefix))
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
