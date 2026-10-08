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
        [--sources commit,diary,review,closure] [--as-of YYYY-MM-DD]
        [--review-records <DIR>] [--determinism-check]

--item-id must be non-empty and contain no whitespace (an empty id would match every commit);
anything else is a usage error, exit 2, nothing written.

--repo is the CONSUMING project's working tree (the repo whose commit/diary/review/closure
artefacts are scanned for <ID>) -- ALWAYS supplied explicitly by the caller, NEVER guessed: this
constitution submodule's own git history is a DIFFERENT repository from the consuming project's
tracked-item history (§11.4.6/§11.4.28).

--review-records is a consumer-supplied directory of T034 (review_record.py) `record`/`backfill`
JSON documents (schema "review-record/v1", ONE document per file). Optional; when omitted the
review source is recorded as `not_supplied` in `source_status` (never a silent zero).

Which tokens count as citations (the false-positive guard, C-004):
  * Every maximal dotted-digit run is a candidate. A run whose leading segment is wider than 2
    digits, whose later segments are wider than 3, or that has fewer than 2 or more than 4
    segments is REJECTED OUTRIGHT, never truncated ("111.4.108" and "11.4.1080" never yield
    "11.4.108"). An optional `.X` single-letter suffix is kept ("11.4.10.A").
  * The candidate must be a member of the live anchor-id set from --anchor-index. This drops
    release strings such as "1.2.1".
  * A TWO-segment candidate ("7.1", "9.2", "11.4", "12.6") must ALSO be written with a section
    sign immediately before it ("§7.1", "§ 7.1"). Membership alone is not enough for these ids:
    measured on this project's own history, a bare "7.1" is an audio channel layout ("5.1/7.1")
    and a bare "9.1" is a document section number in every occurrence found (R8 F1). Ids with
    three or more segments do not collide this way and need no section sign.
  * Known gap: an anchor id with a bracketed suffix ("11.4.184(I)") is reported as its parent
    "11.4.184"; the "(X)" form is the project's ordinary clause-reference syntax for a different
    anchor's sub-clause, so capturing it would drop real citations.

Source classes (default: all four; narrow with --sources):
  commit  : `git -C <repo> log --grep=<item_id> --fixed-strings -i` over HEAD's ancestry (never
            `--all`: other tracks' branches and refs/stash are session-local state). A commit is
            attributed to <item_id> only when <item_id> appears in its SUBJECT or a genuine git
            TRAILER; a body-only mention never attributes the commit.
            Multi-item commits (R8 F2): the OWNERS of a commit are the ids of <item_id>'s own
            family (same prefix, e.g. every `ATM-<n>`) found in the subject and trailers. When
            <item_id> is the only owner, the full message is scanned. When the subject/trailers
            name more than one id of the family, only message LINES that name <item_id> and no
            other id of the family are scanned -- a line naming several items (including the
            subject "close ATM-2 ..., reopen ATM-1 (ATM-2 root cause per 11.4.13)") cannot say
            which item an anchor belongs to, so it is credited to none of them. This is a
            deliberate under-attribution: a citation on an unlabelled line of a multi-item commit
            is dropped rather than credited to every item. When <item_id> has no `PREFIX-<n>`
            shape, no family can be derived and the commit counts as single-owner (recorded in
            `commit_stats.family`).
  diary   : `<repo>/docs/issues/<item_id>/Reopens.md`, if present; decoded strictly as UTF-8.
  review  : review-record/v1 documents under --review-records whose `schema` is exactly
            "review-record/v1" and whose `item_id` equals <item_id>. Scanned fields: the free-text
            `substrate_evidence` / `source_evidence` and `reviewer_mutations` (a free-form JSON
            value: every string inside it, at any depth, is scanned). `findings` entries carry
            only `{id, severity, class}` and optionally `finding_layer` (a closed vocabulary) --
            no anchor-bearing prose -- so anchors written only inside a finding's original text
            are structurally unavailable to this source. A JSON file of another schema is skipped
            and counted in `review_stats.foreign_schema`; a file that is not valid JSON is a
            source ERROR (it could be this item's record).
  closure : EVERY section of `<repo>/docs/Fixed.md` owned by <item_id> (a `##`/`###` heading
            carrying `[<item_id>]` anywhere, or the bare id as its first token), each running to
            the next heading of the same or a higher level, `#` included (R8 F11: an item fixed,
            reopened and fixed again has two owning sections). Never a bare grep for the id: a
            cross-reference in another item's section is not this item's evidence. PLUS any row
            for this item in `<repo>/docs/workable_items.db` whose `current_location` is a known
            CLOSED location (`Fixed`). Any other value -- `Issues`, NULL, or an unknown location
            -- is not closure evidence (R8 F12).

--as-of bounds the `commit` source only (commits carry a date; the other sources do not). The
asymmetry is recorded in `run_meta.as_of_unbounded_sources`.

Output: canonical JSON via fc_common.py's shared emit path (C-002), schema "anchor_citations/v2":
    {"item_id": "<ID>",
     "citations": [{"anchor_id", "source", "evidence"}, ...],      # sorted, deduped
     "anchor_opener_count": <live count of `- id:` entries in --anchor-index>,
     "source_status": {<requested source>: "ok"|"not_supplied"|"error"},
     "source_errors": ["<source>: <what failed>", ...],              # empty unless a source failed
     "commit_stats": {"family": <prefix or null>, "candidates", "owned_single", "owned_multi",
                      "body_only_skipped"},
     "review_stats": {"records_for_item", "foreign_schema"}}
  `ok` means the source was read completely (a source whose artefact simply does not exist --
  no diary file, no Fixed.md, no DB -- is `ok` with zero citations: there is nothing to read).
  `not_supplied` is used only for the review source when --review-records was not given.

Exit codes (C-001):
  0  success, every requested source read completely (citations may be empty).
  2  usage error (bad flag, bad --sources, bad --as-of, empty/whitespace --item-id).
  3  self-test failed (the tokenizer + live-index filter did not behave on its own control
     needles; no result file written).
  4  BLIND. Either (a) --repo is not a git working tree or --anchor-index is unreadable /
     non-UTF-8 / has zero `- id:` entries -- nothing is written; or (b) one or more requested
     sources FAILED part-way (git log error, DB open/query error, an artefact that exists but
     cannot be read or decoded, a review record that is not valid JSON, a --review-records path
     that is not a directory) -- the result IS written, carries `"BLIND": true`, names the failed
     sources in `source_status` / `source_errors`, and keeps whatever citations were read
     completely before the failure. A consumer must never read a BLIND result as "zero
     citations" (R8 F3). Any unexpected internal exception also resolves to 4, never a traceback.
  1  --determinism-check found two different results for the same inputs.

Determinism (C-003): --determinism-check runs the whole collection twice in-process and compares
the canonical body; on mismatch nothing is written, exit 1, unified diff on stderr.

Side-effects: writes --out via fc_common.py's atomic emit path. Python stdlib only.
"""
import argparse
import datetime
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

SCHEMA = "anchor_citations/v2"
SOURCE_CLASSES = ("commit", "diary", "review", "closure")
GIT_TIMEOUT_S = 60  # generous bound; a grep-narrowed `git log` on this repo measures well under 1s

# Maximal contiguous dotted-digit run (digit-boundary-safe: never a truncated sub-run). Validated
# against per-segment width limits in _extract_tokens and REJECTED, never shortened, on failure.
_NUMERIC_RUN_RE = re.compile(r"(?<![0-9])[0-9]+(?:\.[0-9]+)*(?![0-9])")
# Optional single-letter dotted suffix immediately after a validated run ("11.4.10.A").
_TRAILING_LETTER_SUFFIX_RE = re.compile(r"^\.([A-Za-z])(?![A-Za-z0-9])")
# A section sign, optionally followed by ONE space, ending exactly where a candidate starts.
_SECTION_SIGN_RE = re.compile(r"§ ?$")
# `- id: 'X'` / `- id: X` at zero indentation under the top-level `anchors:` key.
_ID_LINE_RE = re.compile(r"^- id: *'?([^']+)'?$")
_AS_OF_RE = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}")
# Item-id family: `PREFIX-<digits>`; the prefix decides which other ids count as co-owners.
_ITEM_FAMILY_RE = re.compile(r"^([A-Za-z][A-Za-z0-9]*)-[0-9]+$")


class SourceError(Exception):
    """A requested source could not be read completely. Carries the citations read before the
    failure, so the BLIND result keeps them (flagged) instead of discarding them."""

    def __init__(self, message, partial=None):
        Exception.__init__(self, message)
        self.partial = partial or []


def _has_section_sign(text, start):
    return _SECTION_SIGN_RE.search(text[max(0, start - 2):start]) is not None


def _extract_tokens(text):
    """Candidate anchor tokens in `text`, in order. See the module docstring for the rules."""
    if not text:
        return []
    out = []
    for m in _NUMERIC_RUN_RE.finditer(text):
        run = m.group(0)
        segments = run.split(".")
        if len(segments) < 2 or len(segments) > 4:
            continue  # a bare number, or an implausibly long dotted run
        if len(segments[0]) > 2:
            continue  # leading segment too wide -- reject the WHOLE run, never truncate
        if any(len(s) > 3 for s in segments[1:]):
            continue  # a later segment too wide -- reject the WHOLE run, never truncate
        token = run
        suf = _TRAILING_LETTER_SUFFIX_RE.match(text[m.end():])
        if suf:
            token += suf.group(0)
        if token.count(".") == 1 and not _has_section_sign(text, m.start()):
            continue  # R8 F1: a two-segment id counts only when written with a section sign
        out.append(token)
    return out


def _filter_live(tokens, live_ids):
    return [t for t in tokens if t in live_ids]


def _anchors_in(text, live_ids):
    return _filter_live(_extract_tokens(text), live_ids)


def load_live_anchor_ids(anchor_index_path):
    """Returns (ids: frozenset, error: str|None). error set => BLIND (no honest anchor set)."""
    try:
        with open(anchor_index_path, encoding="utf-8") as fh:
            lines = fh.read().split("\n")
    except (OSError, UnicodeDecodeError, ValueError) as exc:
        return None, "cannot read --anchor-index %s: %s" % (anchor_index_path, exc)
    ids = set()
    for line in lines:
        m = _ID_LINE_RE.match(line.rstrip("\r"))
        if m:
            ids.add(m.group(1))
    if not ids:
        return None, "--anchor-index %s has zero parseable `- id:` entries (unparseable)" % anchor_index_path
    return frozenset(ids), None


# Needle shapes, chosen by a plain regex that does NOT use the tokenizer under test (R8 F17: the
# old needle was picked by the very round-trip it then re-tested, so that half could not fail).
_THREE_SEG_SHAPE_RE = re.compile(r"^[0-9]{1,2}\.[0-9]{1,3}\.[0-9]{1,3}$")
_TWO_SEG_SHAPE_RE = re.compile(r"^[0-9]{1,2}\.[0-9]{1,3}$")


def _self_check(live_ids):
    """C-004 control needles on the tokenizer + live-index filter, independent of any item. Each
    probe has a known right answer; a wrong answer means the instrument cannot be trusted this
    run (exit 3). Returns None on success, else a diagnostic string."""
    three = sorted(i for i in live_ids if _THREE_SEG_SHAPE_RE.match(i))
    if not three:
        return "self-check: the live anchor set has no plain three-segment id to use as a control needle"
    present = three[0]
    decoy = "99.999.999" if "99.999.999" not in live_ids else "88.888.888"
    if decoy in live_ids:
        return "self-check: could not choose a fabricated decoy absent from the live anchor set"
    probes = [
        ("present needle", "control needle citing %s here" % present, [present]),
        ("fabricated decoy", "decoy %s here" % decoy, []),
    ]
    # Digit-boundary probes: each widens a live id so that a TRUNCATING tokenizer would recover
    # exactly that live id, while the correct tokenizer rejects the whole run.
    lead2 = [i for i in three if len(i.split(".")[0]) == 2]
    if lead2:
        probes.append(("widened leading segment", "decoy 1%s here" % lead2[0], []))
    last3 = [i for i in three if len(i.split(".")[2]) == 3]
    if last3:
        probes.append(("widened last segment", "decoy %s0 here" % last3[0], []))
    four = "%s.7" % present
    if four not in live_ids:
        probes.append(("embedded in a longer run", "decoy %s here" % four, []))
    two = sorted(i for i in live_ids if _TWO_SEG_SHAPE_RE.match(i))
    if two:
        probes.append(("two-segment with section sign", "per §%s here" % two[0], [two[0]]))
        probes.append(("two-segment without section sign", "layout %s here" % two[0], []))
    for label, haystack, expected in probes:
        got = _anchors_in(haystack, live_ids)
        if got != expected:
            return "self-check FAILED (%s): %r gave %r, expected %r" % (label, haystack, got, expected)
    return None


def _run_git(repo, args, timeout_s=GIT_TIMEOUT_S):
    try:
        return subprocess.run(["git", "-C", repo] + args, capture_output=True, text=True,
                              encoding="utf-8", errors="strict", timeout=timeout_s)
    except (OSError, subprocess.TimeoutExpired, UnicodeDecodeError, ValueError) as exc:
        return exc


def validate_repo(repo):
    if not os.path.isdir(repo):
        return False
    result = _run_git(repo, ["rev-parse", "--is-inside-work-tree"], timeout_s=15)
    return (isinstance(result, subprocess.CompletedProcess) and result.returncode == 0
            and result.stdout.strip() == "true")


def _read_text_strict(path):
    """Returns (text, None), or (None, error) for an artefact that exists but cannot be read or
    is not valid UTF-8 (never a lossy `errors="replace"` decode, R8 F10)."""
    try:
        with open(path, encoding="utf-8", errors="strict") as fh:
            return fh.read(), None
    except (OSError, UnicodeDecodeError, ValueError) as exc:
        return None, "%s: %s" % (path, exc)


# Separator BYTES git's `%x00`/`%x1e`/`%x03` placeholders emit. The format ARGUMENT sent to git
# uses git's own escape TEXT ("%x00"); a raw NUL inside an argv element crashes exec().
_COMMIT_TRAILER_SEP = "\x1e"
_COMMIT_FIELD_SEP = "\x00"
_COMMIT_REC_SEP = "\x03"
_COMMIT_FORMAT = "%H%x00%s%x00%(trailers:unfold=true,separator=%x1e)%x00%B%x03"


def _item_family_re(item_id):
    m = _ITEM_FAMILY_RE.match(item_id)
    if not m:
        return None, None
    prefix = m.group(1)
    return prefix, re.compile(r"\b%s-[0-9]+\b" % re.escape(prefix), re.I)


def scan_commits(repo, item_id, live_ids, stats, as_of=None):
    """See the module docstring's `commit` entry. Returns a list of citation tuples; raises
    SourceError (with the citations of every COMPLETE record already read) if git fails."""
    item_re = re.compile(r"\b%s\b" % re.escape(item_id), re.I)
    item_key = item_id.upper()
    prefix, family_re = _item_family_re(item_id)
    stats["family"] = prefix
    args = ["log", "--grep=%s" % item_id, "--fixed-strings", "-i"]
    if as_of:
        args.append("--until=%sT23:59:59" % as_of)
    args.append("--format=%s" % _COMMIT_FORMAT)
    result = _run_git(repo, args)
    failed = None
    if not isinstance(result, subprocess.CompletedProcess):
        failed, stdout = "git log could not run: %s" % result, ""
    else:
        stdout = result.stdout
        if result.returncode != 0:
            failed = "git log exited %d: %s" % (result.returncode, result.stderr.strip()[:500])
    records = stdout.split(_COMMIT_REC_SEP)
    if failed:
        records = records[:-1]  # the text after the last separator is an incomplete record
    citations = []
    for rec in records:
        rec = rec.strip("\n")
        if not rec or _COMMIT_FIELD_SEP not in rec:
            continue
        parts = rec.split(_COMMIT_FIELD_SEP, 3)
        if len(parts) < 4:
            continue
        sha, subject, trailers_raw, body = parts
        sha = sha.strip()
        if not sha:
            continue
        stats["candidates"] += 1
        heads = [subject] + [t for t in trailers_raw.split(_COMMIT_TRAILER_SEP) if t]
        owners = {i.upper() for h in heads for i in (family_re.findall(h) if family_re else [])}
        if not family_re and any(item_re.search(h) for h in heads):
            owners = {item_key}
        if item_key not in owners:
            owners = set()
        if not owners:
            stats["body_only_skipped"] += 1
            continue  # a body-only mention never attributes the commit
        if len(owners) > 1:
            stats["owned_multi"] += 1
            for line in body.split("\n"):
                line_ids = {i.upper() for i in family_re.findall(line)}
                if line_ids == {item_key}:
                    for anchor_id in _anchors_in(line, live_ids):
                        citations.append((anchor_id, "commit", sha))
            continue
        stats["owned_single"] += 1
        for anchor_id in _anchors_in(body, live_ids):
            citations.append((anchor_id, "commit", sha))
    if failed:
        raise SourceError(failed, citations)
    return citations


def scan_diary(repo, item_id, live_ids):
    path = os.path.join(repo, "docs", "issues", item_id, "Reopens.md")
    if not os.path.lexists(path):
        return []
    text, err = _read_text_strict(path)  # diary
    if err:
        raise SourceError("cannot read diary %s" % err)
    evidence = "docs/issues/%s/Reopens.md" % item_id
    return [(a, "diary", evidence) for a in _anchors_in(text, live_ids)]


_REVIEW_SCHEMA = "review-record/v1"
_REVIEW_TEXT_FIELDS = ("substrate_evidence", "reviewer_mutations", "source_evidence")


def _strings_in(value):
    """Every string inside a JSON value, at any depth, in a deterministic order."""
    if isinstance(value, str):
        return [value]
    if isinstance(value, list):
        return [s for v in value for s in _strings_in(v)]
    if isinstance(value, dict):
        return [s for k in sorted(value) for s in _strings_in(value[k])]
    return []


def scan_review(item_id, live_ids, review_records_dir, stats):
    """Returns citations, or None when no --review-records was supplied (status not_supplied).
    Raises SourceError when the directory is missing or a file in it is not valid JSON."""
    if not review_records_dir:
        return None
    if not os.path.isdir(review_records_dir):
        raise SourceError("--review-records %r is not a directory" % review_records_dir)
    citations = []
    bad = []
    for path in sorted(glob.glob(os.path.join(review_records_dir, "**", "*.json"), recursive=True)):
        text, err = _read_text_strict(path)
        if err:
            bad.append(err)
            continue
        try:
            doc = json.loads(text)
        except ValueError as exc:
            bad.append("%s: not valid JSON (%s)" % (path, exc))
            continue
        if not isinstance(doc, dict):
            bad.append("%s: not a JSON object" % path)
            continue
        if doc.get("schema") != _REVIEW_SCHEMA:
            stats["foreign_schema"] += 1
            continue
        if doc.get("item_id") != item_id:
            continue
        stats["records_for_item"] += 1
        text = "\n".join(s for f in _REVIEW_TEXT_FIELDS for s in _strings_in(doc.get(f)))
        evidence = os.path.relpath(path, start=review_records_dir)
        for anchor_id in _anchors_in(text, live_ids):
            citations.append((anchor_id, "review", evidence))
    if bad:
        raise SourceError("unreadable review record(s): %s" % "; ".join(bad), citations)
    return citations


_HEADING_RE = re.compile(r"^(#{1,6})\s")


def _heading_level(line):
    m = _HEADING_RE.match(line)
    return len(m.group(1)) if m else None


def _fixed_md_owns(line, bracket_re, bare_re):
    """Heading level (2 or 3) if this line is <item_id>'s OWN `##`/`###` heading, else None: a
    `[<item_id>]` bracket anywhere on the heading, or the bare id as the first token."""
    level = _heading_level(line)
    if level not in (2, 3):
        return None
    if bracket_re.search(line) or bare_re.match(line):
        return level
    return None


def scan_closure_fixed_md(repo, item_id, live_ids):
    """Every section of docs/Fixed.md owned by <item_id>; see the module docstring."""
    path = os.path.join(repo, "docs", "Fixed.md")
    if not os.path.lexists(path):
        return []
    text, err = _read_text_strict(path)
    if err:
        raise SourceError("cannot read %s" % err)
    bracket_re = re.compile(r"\[%s\]" % re.escape(item_id))
    bare_re = re.compile(r"^#{2,3}\s+%s\b" % re.escape(item_id))
    sections = []
    section = None
    own_level = None
    for line in text.split("\n"):
        if section is not None:
            level = _heading_level(line)
            if level is not None and level <= own_level:
                sections.append(section)
                section = None
            else:
                section.append(line)
                continue
        level = _fixed_md_owns(line, bracket_re, bare_re)
        if level is not None:
            section, own_level = [line], level
    if section is not None:
        sections.append(section)
    evidence = "docs/Fixed.md#%s" % item_id
    text = "\n".join("\n".join(s) for s in sections)
    return [(a, "closure", evidence) for a in _filter_live(_extract_tokens(text), live_ids)]  # closure/Fixed.md


# The tracker's closed location(s), lower-cased. Measured on this project's DB: the only values in
# use are "Fixed" (closed) and "Issues" (open). Anything else -- NULL, or a location this tool does
# not know -- is NOT treated as closed (R8 F12): an unknown state is never read as closure evidence.
_CLOSED_LOCATIONS = ("fixed",)


def scan_closure_db(repo, item_id, live_ids):
    """Rows for this item in docs/workable_items.db at a closed location. Raises SourceError on any
    sqlite error (open or query) -- a read failure is never conflated with zero citations."""
    db_path = os.path.join(repo, "docs", "workable_items.db")
    if not os.path.lexists(db_path):
        return []
    try:
        uri = "file:%s?mode=ro" % urllib.parse.quote(os.path.abspath(db_path))
        conn = sqlite3.connect(uri, uri=True, timeout=5)
    except sqlite3.Error as exc:
        raise SourceError("closure DB: cannot open %s: %s" % (db_path, exc))
    try:
        try:
            rows = conn.execute(
                "SELECT current_location, description, closure_criteria, body_md, forensic_anchor "
                "FROM items WHERE atm_id = ?", (item_id,)).fetchall()
        except sqlite3.Error as exc:
            raise SourceError("closure DB: query failed against %s: %s" % (db_path, exc))
    finally:
        conn.close()
    evidence = "docs/workable_items.db#%s" % item_id
    citations = []
    for current_location, description, closure_criteria, body_md, forensic_anchor in rows:
        loc = (current_location or "").strip().lower()
        if loc not in _CLOSED_LOCATIONS:
            continue
        text = "\n".join(v for v in (description, closure_criteria, body_md, forensic_anchor)
                         if isinstance(v, str))
        for anchor_id in _anchors_in(text, live_ids):
            citations.append((anchor_id, "closure", evidence))
    return citations


def collect(item_id, repo, live_ids, sources, as_of=None, review_records_dir=None):
    """Returns (body: dict, source_errors: list[str]). The body is the full canonical result."""
    citations = []
    status = {}
    errors = []
    commit_stats = {"family": None, "candidates": 0, "owned_single": 0, "owned_multi": 0,
                    "body_only_skipped": 0}
    review_stats = {"records_for_item": 0, "foreign_schema": 0}

    def run(name, fn):
        try:
            got = fn()
        except SourceError as exc:
            citations.extend(exc.partial)
            status[name] = "error"
            errors.append("%s: %s" % (name, exc))
            return
        if got is None:
            status[name] = "not_supplied"
            return
        citations.extend(got)
        status[name] = "ok"

    if "commit" in sources:
        run("commit", lambda: scan_commits(repo, item_id, live_ids, commit_stats, as_of=as_of))
    if "diary" in sources:
        run("diary", lambda: scan_diary(repo, item_id, live_ids))
    if "review" in sources:
        run("review", lambda: scan_review(item_id, live_ids, review_records_dir, review_stats))
    if "closure" in sources:
        run("closure", lambda: scan_closure_fixed_md(repo, item_id, live_ids)
            + scan_closure_db(repo, item_id, live_ids))
    unique = sorted(set(citations), key=lambda t: (t[0], t[1], t[2]))
    body = {
        "item_id": item_id,
        "citations": [{"anchor_id": a, "source": s, "evidence": e} for (a, s, e) in unique],
        "anchor_opener_count": len(live_ids),
        "source_status": status,
        "source_errors": errors,
        "commit_stats": commit_stats,
        "review_stats": review_stats,
    }
    return body, errors


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


_AS_OF_UNBOUNDED_SOURCES = ("diary", "review", "closure")


def _valid_item_id(item_id):
    if not item_id or item_id != item_id.strip() or any(ch.isspace() for ch in item_id):
        return False
    return True


def _main_impl(argv):
    p = argparse.ArgumentParser(prog="anchor_citations.py")
    p.add_argument("--item-id", required=True)
    p.add_argument("--repo", required=True)
    p.add_argument("--anchor-index", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--sources", default=",".join(SOURCE_CLASSES))
    p.add_argument("--as-of")
    p.add_argument("--review-records")
    p.add_argument("--determinism-check", action="store_true")
    try:
        a = p.parse_args(argv)
    except SystemExit as se:
        return 2 if se.code else 0

    if not _valid_item_id(a.item_id):
        print("anchor_citations: --item-id must be non-empty with no whitespace, got %r" % a.item_id,
              file=sys.stderr)
        return 2

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
    if as_of is not None:
        run_meta["as_of"] = as_of
        run_meta["as_of_unbounded_sources"] = [s for s in sources if s in _AS_OF_UNBOUNDED_SOURCES]

    def one_run():
        return collect(a.item_id, a.repo, live_ids, sources, as_of=as_of,
                       review_records_dir=a.review_records)

    body, source_errors = one_run()
    if a.determinism_check:
        body2, _ = one_run()
        canon1 = _canon_body_bytes(body)
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

    for e in source_errors:
        print("anchor_citations: BLIND -- source failed: %s" % e, file=sys.stderr)
    rc = _emit(body, run_meta, a.out, code=4 if source_errors else 0)
    return rc


def main(argv):
    """Every exception _main_impl does not classify itself resolves to BLIND exit 4 with a
    diagnostic -- never a traceback under exit 1 (which C-001 reserves for nondeterminism).
    KeyboardInterrupt / SystemExit are not swallowed."""
    try:
        return _main_impl(argv)
    except Exception as exc:  # noqa: BLE001  (deliberate catch-all, see docstring)
        print("anchor_citations: BLIND -- internal error: %s: %s" % (type(exc).__name__, exc), file=sys.stderr)
        return 4


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
