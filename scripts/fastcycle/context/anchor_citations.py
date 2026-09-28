#!/usr/bin/env python3
"""anchor_citations.py - per-item anchor-citation collector (T039; plan T-A07; FR-013, SC-005).

Collects the real constitution section-anchor ids (`11.4.NNN`-shaped tokens) cited in a work
item's own artefacts -- commit messages, its diary, review-verdict records, and closure evidence
-- as `{item_id, anchor_id, source, evidence}` rows, validated against the LIVE anchor-opener list
read from `--anchor-index` (`constitution/constitution_index.yaml`) at run time. NEVER a hardcoded
anchor list and NEVER a hardcoded anchor count (contracts/common-conventions.md C-004; plan T-A07:
"distribution of anchors bound per item against the live anchor-opener count ... never a literal").

Invocation:
    python3 anchor_citations.py --item-id <ID> --repo <PATH> --anchor-index <PATH> --out <PATH>
        [--sources commit,diary,review,closure] [--as-of YYYY-MM-DD] [--determinism-check]

--repo is the CONSUMING project's working tree (the repo whose commit/diary/review/closure
artefacts are scanned for <ID>) -- ALWAYS supplied explicitly by the caller, NEVER guessed: this
constitution submodule's own git history is a DIFFERENT repository from the consuming project's
tracked-item history (§11.4.6/§11.4.28).

Source classes (default: all four; narrow with --sources):
  commit  : `git -C <repo> log --all --grep='<item_id>\\b' -i` subject+body, per commit.
  diary   : `<repo>/docs/issues/<item_id>/Reopens.md`, if present.
  review  : `.jsonl` files under `<this-tool's-own-fastcycle-dir>/review/` (T034's output; that
            directory legitimately does not exist yet, or has no record touching this item --
            handled as zero citations, never a crash or a BLIND).
  closure : the item's OWN heading section in `<repo>/docs/Fixed.md` (never a bare grep for the
            item id anywhere in the file -- another item's write-up MAY mention this item id in
            passing, e.g. "Composes with ATM-277", and that mention's anchors are NOT this item's
            own closure evidence) PLUS any row for this item in `<repo>/docs/workable_items.db`
            whose `current_location` is not `Issues` (i.e. actually closed).

Every candidate `[0-9]{1,2}(\\.[0-9]{1,3}){1,3}(\\.[A-Za-z])?`-shaped token is kept ONLY if it is a
member of the live anchor-id set read from --anchor-index -- this is what correctly filters out a
release-version string such as "1.2.1" (present verbatim in real commit subjects, never a member
of the anchor id set) while keeping genuine anchors like "11.4.108" (contracts/common-conventions.md
C-004 false-positive guard).

Output: canonical JSON via fc_common.py's shared emit path (C-002), schema "anchor_citations/v1":
    {"item_id": "<ID>",
     "citations": [{"anchor_id": "<id>", "source": "commit"|"diary"|"review"|"closure",
                    "evidence": "<commit sha | file path>#..."}, ...],  # sorted, deduped
     "anchor_opener_count": <int -- the LIVE count of `- id:` entries under `anchors:` in
                             --anchor-index, re-derived at run time, never a literal>}

Exit codes (C-001): 0 success (citations may legitimately be empty -- this is a data-collection
tool, not a gate, so "found nothing" is success, not a finding); 2 usage/config error; 3 self-test
failed (the tokenizer+live-anchor-filter pipeline's own internal control needle did not behave as
expected -- C-004 -- no result file written); 4 BLIND (--repo is not a readable git working tree,
or --anchor-index is unreadable/has zero parseable `- id:` entries -- no honest verdict possible,
§11.4.201(6): an unreadable input is never silently read as "0 citations").

Determinism (C-003): --determinism-check runs the whole item-scan pipeline twice in-process against
the identical inputs and compares the canonical body (excluding run_meta); on any mismatch nothing
is written and the tool exits 1 (nondeterminism is itself a finding, not a self-test failure) with a
unified diff on stderr; on a match the (first) result is written normally and the tool exits 0.

Side-effects: writes --out via fc_common.py's atomic emit path. Python stdlib only.
"""
import argparse
import difflib
import glob
import json
import os
import re
import sqlite3
import subprocess
import sys
import urllib.parse

_HERE = os.path.dirname(os.path.abspath(__file__))
_FC_DIR = os.path.dirname(_HERE)  # constitution/scripts/fastcycle
sys.path.insert(0, os.path.join(_FC_DIR, "lib"))
import fc_common  # noqa: E402  (sibling module; shared C-001..C-004 conventions)

SCHEMA = "anchor_citations/v1"
SOURCE_CLASSES = ("commit", "diary", "review", "closure")
GIT_TIMEOUT_S = 60  # generous bound; a grep-narrowed `git log` on this repo measures well under 1s

# Same candidate-token shape as the plan/RED test's own tokenizer (contracts/common-conventions.md
# C-004 false-positive guard): a numeric-looking run that MUST still be filtered against the live
# anchor-id set before being trusted as a real citation.
_TOKEN_RE = re.compile(r"[0-9]{1,2}(?:\.[0-9]{1,3}){1,3}(?:\.[A-Za-z])?")
# `- id: 'X'` / `- id: X` at zero indentation under the top-level `anchors:` key -- mirrors the
# RED test's own `sed -E "s/^- id: *'?([^']+)'?\$/\1/"` extraction byte-for-byte.
_ID_LINE_RE = re.compile(r"^- id: *'?([^']+)'?$")
_AS_OF_RE = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}")


def _extract_tokens(text):
    if not text:
        return []
    return _TOKEN_RE.findall(text)


def _filter_live(tokens, live_ids):
    return [t for t in tokens if t in live_ids]


def load_live_anchor_ids(anchor_index_path):
    """Returns (ids: frozenset, error: str|None). error set => BLIND (no honest anchor set)."""
    try:
        with open(anchor_index_path, encoding="utf-8") as fh:
            lines = fh.read().split("\n")
    except OSError as exc:
        return None, "cannot read --anchor-index %s: %s" % (anchor_index_path, exc)
    ids = set()
    for line in lines:
        m = _ID_LINE_RE.match(line.rstrip("\r"))
        if m:
            ids.add(m.group(1))
    if not ids:
        return None, "--anchor-index %s has zero parseable `- id:` entries (unparseable)" % anchor_index_path
    return frozenset(ids), None


def _self_check(live_ids):
    """C-004 class-matched control needle on the tokenizer+live-anchor-filter pipeline itself,
    independent of any specific item's data: a known-present live anchor embedded in a synthetic
    haystack MUST survive extraction+filtering, and a guaranteed-fabricated decoy MUST NOT. This is
    the concrete instance of C-001 exit-3 ("a control needle ... did not behave as expected -- the
    instrument is not trustworthy this run") for this tool: without it, an item legitimately
    reporting zero citations for some anchor would be an unproven absence (§11.4.201(6)).
    Returns None on success, else a diagnostic string.
    """
    present = sorted(live_ids)[0]  # any live anchor id works as the "must survive" needle
    fabricated = "999.999.999"
    if fabricated in live_ids:
        # Astronomically unlikely (this literal is not a real anchor shape ever minted), but
        # never silently trust a decoy that turned out to collide with the real set (§11.4.6).
        fabricated = "888.888.888"
        if fabricated in live_ids:
            return "self-check: could not choose a fabricated decoy absent from the live anchor set"
    synthetic = "control needle line citing %s and the decoy %s together" % (present, fabricated)
    found = set(_filter_live(_extract_tokens(synthetic), live_ids))
    if present not in found:
        return "self-check FAILED: known-present anchor %r not recovered from a synthetic haystack" % present
    if fabricated in found:
        return "self-check FAILED: fabricated decoy %r leaked past the live-anchor-index filter" % fabricated
    return None


def _run_git(repo, args, timeout_s=GIT_TIMEOUT_S):
    try:
        return subprocess.run(["git", "-C", repo] + args, capture_output=True, text=True, timeout=timeout_s)
    except (OSError, subprocess.TimeoutExpired):
        return None


def validate_repo(repo):
    if not os.path.isdir(repo):
        return False
    result = _run_git(repo, ["rev-parse", "--is-inside-work-tree"], timeout_s=15)
    return result is not None and result.returncode == 0 and result.stdout.strip() == "true"


def scan_commits(repo, item_id, live_ids, as_of=None):
    """§11.4.6/§11.4.28: --repo is the consuming project's OWN history, never this submodule's."""
    pattern = "%s\\b" % re.escape(item_id)
    args = ["log", "--all", "--grep=%s" % pattern, "-i", "--format=%H%x00%B%x03"]
    if as_of:
        args = ["log", "--all", "--grep=%s" % pattern, "-i",
                "--until=%sT23:59:59" % as_of, "--format=%H%x00%B%x03"]
    result = _run_git(repo, args)
    if result is None or result.returncode != 0:
        # A narrowed --grep against a valid repo failing is a genuine git-level fault; report as
        # empty for this source rather than BLIND (only --repo/--anchor-index unreadability is
        # BLIND per the contract) but surface it to the caller for diagnostics.
        return [], (result.stderr.strip() if result is not None else "git log timed out or could not run")
    citations = []
    for rec in result.stdout.split("\x03"):
        rec = rec.strip("\n")
        if not rec or "\x00" not in rec:
            continue
        sha, body = rec.split("\x00", 1)
        sha = sha.strip()
        if not sha:
            continue
        for anchor_id in _filter_live(_extract_tokens(body), live_ids):
            citations.append((anchor_id, "commit", sha))
    return citations, None


def scan_diary(repo, item_id, live_ids):
    path = os.path.join(repo, "docs", "issues", item_id, "Reopens.md")
    if not os.path.isfile(path):
        return []
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            text = fh.read()
    except OSError:
        return []
    evidence = "docs/issues/%s/Reopens.md" % item_id
    return [(a, "diary", evidence) for a in _filter_live(_extract_tokens(text), live_ids)]


def scan_review(item_id, live_ids):
    """T034's output, if it exists (constitution/scripts/fastcycle/review/**/*.jsonl); handled
    gracefully -- an absent directory, or a directory with no record touching this item, is
    zero citations, never an error (T039 task text)."""
    review_dir = os.path.join(_FC_DIR, "review")
    if not os.path.isdir(review_dir):
        return []
    item_re = re.compile(r"\b%s\b" % re.escape(item_id))
    citations = []
    for path in sorted(glob.glob(os.path.join(review_dir, "**", "*.jsonl"), recursive=True)):
        try:
            with open(path, encoding="utf-8", errors="replace") as fh:
                lines = fh.readlines()
        except OSError:
            continue
        rel = os.path.relpath(path, start=os.path.dirname(_FC_DIR))
        for lineno, line in enumerate(lines, start=1):
            if not item_re.search(line):
                continue
            try:
                json.loads(line)
            except ValueError:
                continue  # not a parseable JSONL record -- never crash on a stray line
            evidence = "%s#L%d" % (rel, lineno)
            for anchor_id in _filter_live(_extract_tokens(line), live_ids):
                citations.append((anchor_id, "review", evidence))
    return citations


_FIXED_MD_ANY_HEADING_RE = re.compile(r"^#{2,3}\s+")


def scan_closure_fixed_md(repo, item_id, live_ids):
    """The item's OWN heading section only (`## <item_id> — ...`) -- never a bare grep for the
    item id anywhere in docs/Fixed.md, which would wrongly harvest anchors from an UNRELATED item's
    write-up that merely mentions this item id in a cross-reference (e.g. "Composes with ATM-277")."""
    path = os.path.join(repo, "docs", "Fixed.md")
    if not os.path.isfile(path):
        return []
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            lines = fh.read().split("\n")
    except OSError:
        return []
    own_heading_re = re.compile(r"^#{2,3}\s+%s\b" % re.escape(item_id))
    section = []
    in_section = False
    for line in lines:
        if own_heading_re.match(line):
            in_section = True
            section = [line]
            continue
        if in_section:
            if _FIXED_MD_ANY_HEADING_RE.match(line):
                break
            section.append(line)
    if not section:
        return []
    evidence = "docs/Fixed.md#%s" % item_id
    text = "\n".join(section)
    return [(a, "closure", evidence) for a in _filter_live(_extract_tokens(text), live_ids)]


def scan_closure_db(repo, item_id, live_ids):
    """Any row for this item in docs/workable_items.db that is actually CLOSED (current_location
    != 'Issues') -- an item still open (current_location == 'Issues') has no closure evidence yet,
    regardless of what its live investigation text happens to mention."""
    db_path = os.path.join(repo, "docs", "workable_items.db")
    if not os.path.isfile(db_path):
        return []
    try:
        uri = "file:%s?mode=ro" % urllib.parse.quote(os.path.abspath(db_path))
        conn = sqlite3.connect(uri, uri=True, timeout=5)
    except sqlite3.Error:
        return []
    try:
        try:
            cur = conn.cursor()
            cur.execute(
                "SELECT current_location, description, closure_criteria, body_md, forensic_anchor "
                "FROM items WHERE atm_id = ?",
                (item_id,),
            )
            rows = cur.fetchall()
        except sqlite3.Error:
            return []
    finally:
        conn.close()
    evidence = "docs/workable_items.db#%s" % item_id
    citations = []
    for current_location, description, closure_criteria, body_md, forensic_anchor in rows:
        if (current_location or "").strip().lower() == "issues":
            continue  # still open: not closure evidence
        text = "\n".join(v for v in (description, closure_criteria, body_md, forensic_anchor) if v)
        for anchor_id in _filter_live(_extract_tokens(text), live_ids):
            citations.append((anchor_id, "closure", evidence))
    return citations


def collect(item_id, repo, live_ids, sources, as_of=None):
    """Returns (citations: list[tuple], diagnostics: list[str])."""
    citations = []
    diagnostics = []
    if "commit" in sources:
        commit_citations, err = scan_commits(repo, item_id, live_ids, as_of=as_of)
        citations.extend(commit_citations)
        if err:
            diagnostics.append("commit source: %s" % err)
    if "diary" in sources:
        citations.extend(scan_diary(repo, item_id, live_ids))
    if "review" in sources:
        citations.extend(scan_review(item_id, live_ids))
    if "closure" in sources:
        citations.extend(scan_closure_fixed_md(repo, item_id, live_ids))
        citations.extend(scan_closure_db(repo, item_id, live_ids))
    # Dedupe exact (anchor_id, source, evidence) triples (e.g. the same token repeated within one
    # commit body), then sort deterministically (C-003) by anchor_id, then source, then evidence.
    unique = sorted(set(citations), key=lambda t: (t[0], t[1], t[2]))
    return unique, diagnostics


def _body_for(item_id, unique_citations, live_ids):
    return {
        "item_id": item_id,
        "citations": [
            {"anchor_id": a, "source": s, "evidence": e} for (a, s, e) in unique_citations
        ],
        "anchor_opener_count": len(live_ids),
    }


def _canon_body_bytes(body):
    return fc_common.canon(body).encode("utf-8")


def _emit(body, run_meta, out_path, code=0):
    ns = argparse.Namespace(
        schema=SCHEMA,
        body_json=json.dumps(body),
        run_meta_json=json.dumps(run_meta) if run_meta else None,
        out=out_path,
        code=code,
    )
    return fc_common.cmd_emit(ns)


def _parse_sources(raw):
    names = [s.strip() for s in raw.split(",") if s.strip()]
    bad = [s for s in names if s not in SOURCE_CLASSES]
    return names, bad


def main(argv):
    p = argparse.ArgumentParser(prog="anchor_citations.py")
    p.add_argument("--item-id", required=True)
    p.add_argument("--repo", required=True)
    p.add_argument("--anchor-index", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--sources", default=",".join(SOURCE_CLASSES))
    p.add_argument("--as-of")
    p.add_argument("--determinism-check", action="store_true")
    try:
        a = p.parse_args(argv)
    except SystemExit as se:
        return 2 if se.code else 0

    sources, bad_sources = _parse_sources(a.sources)
    if bad_sources or not sources:
        print("anchor_citations: --sources contains unknown class(es) %s (valid: %s)"
              % (bad_sources, ",".join(SOURCE_CLASSES)), file=sys.stderr)
        return 2

    as_of = None
    if a.as_of is not None:
        if not _AS_OF_RE.fullmatch(a.as_of):
            print("anchor_citations: --as-of must be YYYY-MM-DD, got %r" % a.as_of, file=sys.stderr)
            return 2
        try:
            import datetime
            datetime.date.fromisoformat(a.as_of)
        except ValueError:
            print("anchor_citations: --as-of is not a real calendar date: %r" % a.as_of, file=sys.stderr)
            return 2
        as_of = a.as_of

    if not validate_repo(a.repo):
        print("anchor_citations: BLIND -- --repo %r is not a readable git working tree" % a.repo, file=sys.stderr)
        return 4

    live_ids, err = load_live_anchor_ids(a.anchor_index)
    if err:
        print("anchor_citations: BLIND -- %s" % err, file=sys.stderr)
        return 4

    self_check_err = _self_check(live_ids)
    if self_check_err:
        print("anchor_citations: %s" % self_check_err, file=sys.stderr)
        return 3

    run_meta = {"tool": "anchor_citations.py", "repo": os.path.abspath(a.repo), "sources": sources}
    if as_of:
        run_meta["as_of"] = as_of

    if a.determinism_check:
        run1, diag1 = collect(a.item_id, a.repo, live_ids, sources, as_of=as_of)
        run2, diag2 = collect(a.item_id, a.repo, live_ids, sources, as_of=as_of)
        body1 = _body_for(a.item_id, run1, live_ids)
        body2 = _body_for(a.item_id, run2, live_ids)
        canon1 = _canon_body_bytes(body1)
        canon2 = _canon_body_bytes(body2)
        if canon1 != canon2:
            print("anchor_citations: nondeterministic across two in-process runs for --item-id %s"
                  % a.item_id, file=sys.stderr)
            diff = list(difflib.unified_diff(
                canon1.decode("utf-8", "replace").splitlines(),
                canon2.decode("utf-8", "replace").splitlines(),
                "run1", "run2", lineterm="", n=1,
            ))
            for line in diff[:40]:
                print(line, file=sys.stderr)
            return 1
        citations, diagnostics = run1, diag1
    else:
        citations, diagnostics = collect(a.item_id, a.repo, live_ids, sources, as_of=as_of)

    for d in diagnostics:
        print("anchor_citations: note: %s" % d, file=sys.stderr)

    body = _body_for(a.item_id, citations, live_ids)
    rc = _emit(body, run_meta, a.out, code=0)
    return rc


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
