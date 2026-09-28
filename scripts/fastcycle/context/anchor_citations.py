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

--repo is the CONSUMING project's working tree (the repo whose commit/diary/review/closure
artefacts are scanned for <ID>) -- ALWAYS supplied explicitly by the caller, NEVER guessed: this
constitution submodule's own git history is a DIFFERENT repository from the consuming project's
tracked-item history (§11.4.6/§11.4.28).

--review-records is a consumer-supplied directory of T034 (review_record.py) `record`/`backfill`
JSON documents (schema "review-record/v1", ONE document per file, NEVER a `.jsonl` stream --
review_record.py's real output is a single canonical JSON document per invocation written to an
arbitrary `--out` path, see the `review` source class note below). Optional; omitted -> the review
source is honestly reported UNAVAILABLE (see below), never a silent zero citations from a directory
that structurally could never hold anything (this fixes a defect: the tool used to scan its own
`<fastcycle-dir>/review/**/*.jsonl`, a directory that never legitimately contains any `.jsonl` file
at all, and that also breaks `--repo` scoping by reading FROM the constitution submodule instead of
the consuming project).

Source classes (default: all four; narrow with --sources):
  commit  : `git -C <repo> log --grep='<item_id>' --fixed-strings -i` (scoped to HEAD's own
            ancestry, NEVER `--all` -- `--all` additionally scans every local branch of every
            other track/worktree PLUS `refs/stash`, ephemeral session-local state that is not part
            of the repo's shared canonical history and would make citations non-reproducible
            across clones/sessions), attributed to <item_id> ONLY when <item_id> itself is present
            in that commit's SUBJECT line or a genuine git trailer (e.g. `ATM-277: ...`) -- NEVER
            on the strength of a bare body mention alongside unrelated ids, which over-attributes a
            large multi-item digest/summary commit's ENTIRE anchor set to every id it happens to
            list in passing (measured real defect, fixed: a "SpecKit Constitution v2.1.0" commit
            whose body tallies "ATM-277 x11, ATM-343 x3, ..." previously credited every anchor in
            that huge body to ATM-277 alone). Once a commit is confirmed OWNED this way, its FULL
            message (subject+body) is scanned for anchor tokens, same as before the fix -- the
            subject/trailer gate decides WHETHER a commit's anchors attribute to this item, not
            which lines of an attributed commit are scanned.
  diary   : `<repo>/docs/issues/<item_id>/Reopens.md`, if present.
  review  : T034 (review_record.py) JSON documents under a consumer-supplied `--review-records`
            directory (never this tool's own directory -- see the Invocation note above), matched
            by `item_id` field equality, scanned across the `substrate_evidence` / `reviewer_mutations`
            / `source_evidence` free-text fields (the ONLY fields in review_record.py's real
            "review-record/v1" schema that can legitimately carry prose; `findings` entries carry
            only `{id, severity, class}` -- a closed vocabulary with NO anchor-bearing text field).
            Because that structural gap in the schema is permanent (not merely "this directory is
            currently empty"), whenever "review" is a requested source class the tool ALWAYS emits
            an honest diagnostic explaining it, distinct from (and in addition to) reporting zero
            citations when genuinely none are found -- an UNAVAILABLE/no-anchor-bearing-field state
            is never silently indistinguishable from "scanned it, found nothing."
  closure : the item's OWN heading section in `<repo>/docs/Fixed.md` (never a bare grep for the
            item id anywhere in the file -- another item's write-up MAY mention this item id in
            passing, e.g. "Composes with ATM-277", and that mention's anchors are NOT this item's
            own closure evidence) PLUS any row for this item in `<repo>/docs/workable_items.db`
            whose `current_location` is not `Issues` (i.e. actually closed).

--as-of bounds the `commit` source only (commits carry a real committer/author date to bound
against; the diary/review/closure sources have no comparable per-artefact timestamp to bound by
today) -- the tool records this asymmetry explicitly in `run_meta.as_of_unbounded_sources` rather
than silently producing inconsistent-but-undocumented behaviour across sources.

Every candidate `[0-9]{1,2}(\\.[0-9]{1,3}){1,3}(\\.[A-Za-z])?`-shaped token is kept ONLY if it is a
member of the live anchor-id set read from --anchor-index -- this is what correctly filters out a
release-version string such as "1.2.1" (present verbatim in real commit subjects, never a member
of the anchor id set) while keeping genuine anchors like "11.4.108" (contracts/common-conventions.md
C-004 false-positive guard). The tokenizer is digit-boundary-aware (N nit, this task): a run of
digits is REJECTED OUTRIGHT (never silently truncated into a shorter valid-looking id) if it is
adjacent to more digits outside the candidate span, or if any dotted segment exceeds its width limit
-- e.g. "111.4.108" and "11.4.1080" must never yield the wrong "11.4.108". Known, documented,
tracked gap: a small number of live anchor ids append a bracketed disambiguation suffix instead of a
dotted one (e.g. "11.4.184(I)"), which is LEXICALLY IDENTICAL to this project's common in-text
clause-reference syntax for a DIFFERENT anchor's sub-clause (e.g. "11.4.28(B)" means "clause B of
anchor 11.4.28", not a standalone anchor "11.4.28(B)") -- extending the tokenizer to always capture
a trailing "(X)" was measured to silently drop 20+ real, currently-correct citations across this
project's own corpus (every genuine clause-reference of that shape), so it is NOT implemented; text
citing "11.4.184(I)" is reported as citing its parent anchor "11.4.184" (itself independently
registered and correct), never as citing "11.4.184(I)" by its own distinct id.

Output: canonical JSON via fc_common.py's shared emit path (C-002), schema "anchor_citations/v1":
    {"item_id": "<ID>",
     "citations": [{"anchor_id": "<id>", "source": "commit"|"diary"|"review"|"closure",
                    "evidence": "<commit sha | file path>#..."}, ...],  # sorted, deduped
     "anchor_opener_count": <int -- the LIVE count of `- id:` entries under `anchors:` in
                             --anchor-index, re-derived at run time, never a literal>}

Exit codes (C-001): 0 success (citations may legitimately be empty -- this is a data-collection
tool, not a gate, so "found nothing" is success, not a finding); 2 usage/config error; 3 self-test
failed (the tokenizer+live-anchor-filter pipeline's own internal control needle did not behave as
expected -- C-004 -- no result file written); 4 BLIND (--repo is not a readable git working tree;
--anchor-index is unreadable, non-UTF-8, or has zero parseable `- id:` entries; a scanned artefact
--repo/--anchor-index/--review-records is present but not decodable as text; or any other internal
error -- no honest verdict possible, §11.4.201(6): an unreadable input is never silently read as
"0 citations", and never surfaced as a raw unhandled traceback under the reserved-for-nondeterminism
exit 1 (I2 fix, this task) -- `main()`'s whole body is guarded so every internal failure this tool
cannot classify more precisely resolves to 4, never a crash.

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

# Candidate-token shape (contracts/common-conventions.md C-004 false-positive guard): a
# numeric-looking run that MUST still be filtered against the live anchor-id set before being
# trusted as a real citation. Digit-boundary-safe (N nit, this task): the MAXIMAL contiguous
# dotted-digit run is captured in one piece (no per-segment length cap at the regex level, so no
# backtracking can silently truncate a too-long run into a shorter valid-looking prefix); the run
# is then validated in Python (_extract_tokens) against the real per-segment width limits and
# REJECTED OUTRIGHT -- never shortened -- if it does not fit.
_NUMERIC_RUN_RE = re.compile(r"(?<![0-9])[0-9]+(?:\.[0-9]+)*(?![0-9])")
# An optional single-letter dotted suffix immediately following a validated numeric run (e.g. the
# ".A" of "11.4.10.A"), never followed by another letter/digit (so "11.4.10.ABC" is not mistaken
# for the suffix form).
_TRAILING_LETTER_SUFFIX_RE = re.compile(r"^\.([A-Za-z])(?![A-Za-z0-9])")
# `- id: 'X'` / `- id: X` at zero indentation under the top-level `anchors:` key -- mirrors the
# RED test's own `sed -E "s/^- id: *'?([^']+)'?\$/\1/"` extraction byte-for-byte.
_ID_LINE_RE = re.compile(r"^- id: *'?([^']+)'?$")
_AS_OF_RE = re.compile(r"[0-9]{4}-[0-9]{2}-[0-9]{2}")


def _extract_tokens(text):
    """See the module docstring's digit-boundary + `11.4.184(I)`-gap notes (N nit / M2). Every
    real constitution anchor id is 2-4 dotted segments, leading segment 1-2 digits, every later
    segment 1-3 digits -- a maximal numeric run violating either limit is REJECTED OUTRIGHT, never
    truncated into a shorter valid-looking id (measured real bug fixed here: "111.4.108" and
    "11.4.1080" must never yield the wrong "11.4.108")."""
    if not text:
        return []
    out = []
    for m in _NUMERIC_RUN_RE.finditer(text):
        run = m.group(0)
        segments = run.split(".")
        if len(segments) < 2 or len(segments) > 4:
            continue  # not a real anchor shape (bare number, or an implausibly long dotted run)
        if len(segments[0]) > 2:
            continue  # leading segment too wide -- reject the WHOLE run, never truncate
        if any(len(s) > 3 for s in segments[1:]):
            continue  # a later segment too wide -- reject the WHOLE run, never truncate
        token = run
        suf = _TRAILING_LETTER_SUFFIX_RE.match(text[m.end():])
        if suf:
            token += suf.group(0)
        out.append(token)
    return out


def _filter_live(tokens, live_ids):
    return [t for t in tokens if t in live_ids]


def load_live_anchor_ids(anchor_index_path):
    """Returns (ids: frozenset, error: str|None). error set => BLIND (no honest anchor set).
    I2 fix: a non-UTF-8 --anchor-index MUST resolve here as an ordinary BLIND diagnostic (this
    function's documented contract), never an unhandled UnicodeDecodeError (a ValueError subclass,
    NOT an OSError, so the pre-fix bare `except OSError` let it propagate as a raw traceback with
    the wrong exit code -- see main()'s own top-level guard for the remaining, more general half
    of this fix)."""
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


def _pick_self_check_present(live_ids):
    """M2 fix: the self-check's "must survive" needle MUST be a live anchor id the tokenizer is
    PROVEN able to reproduce byte-for-byte -- never merely `sorted(live_ids)[0]` (the prior
    implementation), which "happens to work" only because the alphabetically-first id in THIS
    project's current anchor set is tokenizer-producible; a live id shaped like the KNOWN,
    documented tokenizer gap "11.4.184(I)" (see the module docstring / _extract_tokens) could sort
    earlier in a future anchor set and silently defeat the needle's own premise. Returns the first
    (sorted, for determinism) live id that round-trips through extract+filter, or None if literally
    none does (an honest self-check failure, never a crash)."""
    for candidate in sorted(live_ids):
        if _filter_live(_extract_tokens(candidate), live_ids) == [candidate]:
            return candidate
    return None


def _self_check(live_ids):
    """C-004 class-matched control needle on the tokenizer+live-anchor-filter pipeline itself,
    independent of any specific item's data: a known-present live anchor embedded in a synthetic
    haystack MUST survive extraction+filtering, and a guaranteed-fabricated decoy MUST NOT. This is
    the concrete instance of C-001 exit-3 ("a control needle ... did not behave as expected -- the
    instrument is not trustworthy this run") for this tool: without it, an item legitimately
    reporting zero citations for some anchor would be an unproven absence (§11.4.201(6)).
    Returns None on success, else a diagnostic string.
    """
    present = _pick_self_check_present(live_ids)
    if present is None:
        return "self-check: no live anchor id is tokenizer-producible (cannot choose a control needle)"
    # A tokenizer-producible-SHAPE decoy (2-4 segments, correct per-segment width) so this needle
    # actually exercises the live-anchor-INDEX filter, not merely the tokenizer's own shape rules
    # (a shape-violating decoy like "999.999.999" would be rejected by _extract_tokens itself,
    # trivially "passing" this check for the wrong reason -- it would never reach the filter step).
    fabricated = "99.999.999"
    if fabricated in live_ids:
        # Astronomically unlikely (no real anchor is ever minted with this literal), but never
        # silently trust a decoy that turned out to collide with the real set (§11.4.6).
        fabricated = "88.888.888"
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
    except (OSError, subprocess.TimeoutExpired, UnicodeDecodeError, ValueError):
        # UnicodeDecodeError/ValueError (I2 fix): `text=True` decodes stdout/stderr using the
        # process locale encoding; a commit message containing bytes not valid in that encoding
        # would otherwise surface as a raw unhandled traceback rather than the documented
        # git-level-fault-for-this-source handling every OTHER _run_git failure already gets.
        return None


def validate_repo(repo):
    if not os.path.isdir(repo):
        return False
    result = _run_git(repo, ["rev-parse", "--is-inside-work-tree"], timeout_s=15)
    return result is not None and result.returncode == 0 and result.stdout.strip() == "true"


# The REAL separator bytes git's `%x00`/`%x1e`/`%x03` format placeholders emit -- used to split the
# tool's OWN Python-side view of git's stdout. NEVER embed these actual characters into the
# `--format` ARGUMENT STRING itself: an argv element containing a raw NUL byte crashes exec()
# (`ValueError: embedded null byte`, caught live while building this fix) -- the format string sent
# TO git must use git's own literal 4/5-character escape-code TEXT ("%x00" etc.), which git then
# expands into the real byte in its OUTPUT.
_COMMIT_TRAILER_SEP = "\x1e"
_COMMIT_FIELD_SEP = "\x00"
_COMMIT_REC_SEP = "\x03"
_COMMIT_FORMAT = "%H%x00%s%x00%(trailers:unfold=true,separator=%x1e)%x00%B%x03"


def scan_commits(repo, item_id, live_ids, as_of=None):
    """§11.4.6/§11.4.28: --repo is the consuming project's OWN history, never this submodule's.

    Scoped to HEAD's own ancestry, NEVER `--all` (I1 fix, secondary point): `--all` additionally
    walks every local branch (other tracks/worktrees) and `refs/stash` -- ephemeral, session-local
    state that is not part of the repo's shared canonical history and would make citations
    non-reproducible across clones/sessions.

    `--grep` uses `--fixed-strings` on the bare <item_id> (N nit fix): a `re.escape()`-produced
    pattern passed to git's DEFAULT (BRE) `--grep` dialect is not guaranteed to mean the same thing
    under BRE's escaping rules as it does under Python's -- `--fixed-strings` removes the ambiguity
    entirely (no regex metacharacters to escape either way) at the cost of a slightly broader
    candidate net (e.g. it would also match "ATM-2770" as a substring of a search for "ATM-277");
    the REAL, precise word-boundary check that git's `\\b` extension previously supplied is then
    re-applied in Python via `item_re` below (Python's own regex dialect, no cross-dialect risk),
    so the net correctness is equal or better, never worse.

    I1 fix (over-attribution): a commit's message is scanned for anchor tokens ONLY once <item_id>
    itself is confirmed present in that commit's SUBJECT line or a genuine git trailer (e.g.
    `ATM-277: ...`) -- never on the strength of a bare --grep candidate-match alone, which also
    matches a large multi-item digest/summary commit that merely LISTS this item id among many
    unrelated ones deep in its body (measured real case, ATM-277: a "SpecKit Constitution v2.1.0"
    commit whose body tallies "ATM-277 x11, ATM-343 x3, ..." credited EVERY anchor in that huge
    body to ATM-277 alone under the prior implementation -- 28 of ATM-277's 76 distinct
    commit-source anchors traced ONLY to such over-attributed commits before this fix). Once the
    subject/trailer gate confirms real ownership, the commit's FULL message (subject+body) is
    scanned for anchor tokens, same as before the fix -- the gate decides WHETHER a commit's
    anchors attribute to this item, not which lines of an ALREADY-attributed commit are scanned.
    """
    item_re = re.compile(r"\b%s\b" % re.escape(item_id), re.I)
    args = ["log", "--grep=%s" % item_id, "--fixed-strings", "-i", "--format=%s" % _COMMIT_FORMAT]
    if as_of:
        args = ["log", "--grep=%s" % item_id, "--fixed-strings", "-i",
                 "--until=%sT23:59:59" % as_of, "--format=%s" % _COMMIT_FORMAT]
    result = _run_git(repo, args)
    if result is None or result.returncode != 0:
        # A narrowed --grep against a valid repo failing is a genuine git-level fault; report as
        # empty for this source rather than BLIND (only --repo/--anchor-index unreadability is
        # BLIND per the contract) but surface it to the caller for diagnostics.
        return [], (result.stderr.strip() if result is not None else "git log timed out or could not run")
    citations = []
    for rec in result.stdout.split(_COMMIT_REC_SEP):
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
        trailer_lines = [t for t in trailers_raw.split(_COMMIT_TRAILER_SEP) if t]
        owned = bool(item_re.search(subject)) or any(item_re.search(t) for t in trailer_lines)
        if not owned:
            continue  # I1 fix: a candidate --grep match with <item_id> ONLY in the body (never
            # the subject or a trailer) is a body-mention-alongside-other-ids risk, not attributed.
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


# B2 fix: review_record.py's real "review-record/v1" schema (constitution/scripts/fastcycle/
# review/review_record.py) carries NO anchor-bearing prose field in its `findings` array (each
# entry is only {id, severity, class} -- a closed vocabulary); the free-text fields it DOES emit
# that could legitimately carry an anchor citation are exactly these three.
_REVIEW_TEXT_FIELDS = ("substrate_evidence", "reviewer_mutations", "source_evidence")
_REVIEW_SCHEMA_GAP_NOTE = (
    "review source: review_record.py's 'review-record/v1' schema's `findings` array carries only "
    "{id, severity, class} -- a closed vocabulary with NO anchor-bearing prose field -- so only "
    "the substrate_evidence/reviewer_mutations/source_evidence free-text fields were scanned; a "
    "review whose ONLY anchor mentions live inside a `findings` entry's discarded free text is "
    "structurally UNAVAILABLE to this source, never silently reported as zero-and-indistinguishable"
    "-from-scanned-and-found-nothing"
)


def _review_record_text(doc):
    """Concatenate the free-text fields of one review-record/v1 document that could legitimately
    carry an anchor citation (see _REVIEW_TEXT_FIELDS). Non-string / absent values contribute
    nothing (never invented text, §11.4.6); a list value (e.g. `reviewer_mutations`) is flattened
    to its string elements only -- a non-string list entry (a dict, say) is skipped rather than
    guessed at."""
    parts = []
    for field in _REVIEW_TEXT_FIELDS:
        val = doc.get(field)
        if isinstance(val, str):
            parts.append(val)
        elif isinstance(val, list):
            parts.extend(v for v in val if isinstance(v, str))
    return "\n".join(parts)


def scan_review(item_id, live_ids, review_records_dir):
    """B2 fix: T034 (review_record.py) output is a single canonical JSON DOCUMENT per invocation
    (schema "review-record/v1"), written to an ARBITRARY --out path the caller chooses -- never a
    `.jsonl` stream under a fixed directory, and never this constitution submodule's own tree (the
    prior implementation scanned `<this-tool's-own-fastcycle-dir>/review/**/*.jsonl`, a directory
    that structurally can never legitimately contain a `.jsonl` file, and which also broke --repo
    scoping by reading FROM the constitution submodule instead of the consuming project).

    `review_records_dir` is therefore a CONSUMER-SUPPLIED directory of real review_record.py JSON
    documents (one per file); `None` means the caller did not supply one. Returns
    (citations: list[tuple], diagnostic: str) -- the diagnostic is ALWAYS populated (the permanent
    schema-gap note per _REVIEW_SCHEMA_GAP_NOTE, honestly distinguishing "this source structurally
    cannot see everything" from a plain "found nothing"), with an additional UNAVAILABLE note
    prepended when no directory was supplied or it does not exist -- never a silent empty return
    indistinguishable from "scanned it, found nothing" (§11.4.201(6))."""
    if not review_records_dir:
        return [], "review source: UNAVAILABLE (no --review-records directory supplied); " + _REVIEW_SCHEMA_GAP_NOTE
    if not os.path.isdir(review_records_dir):
        return [], ("review source: UNAVAILABLE (--review-records %r is not a directory); " % review_records_dir
                     + _REVIEW_SCHEMA_GAP_NOTE)
    citations = []
    for path in sorted(glob.glob(os.path.join(review_records_dir, "**", "*.json"), recursive=True)):
        try:
            with open(path, encoding="utf-8", errors="replace") as fh:
                doc = json.load(fh)
        except (OSError, ValueError):
            continue  # unreadable/unparseable record -- never crash on a stray file
        if not isinstance(doc, dict) or doc.get("item_id") != item_id:
            continue
        text = _review_record_text(doc)
        if not text:
            continue
        evidence = os.path.relpath(path, start=review_records_dir)
        for anchor_id in _filter_live(_extract_tokens(text), live_ids):
            citations.append((anchor_id, "review", evidence))
    return citations, _REVIEW_SCHEMA_GAP_NOTE


_FIXED_MD_HEADING_LEVEL_RE = re.compile(r"^(#{2,3})\s")


def _fixed_md_heading_level(line):
    """Returns 2 or 3 for a `## `/`### ` heading line, else None."""
    m = _FIXED_MD_HEADING_LEVEL_RE.match(line)
    return len(m.group(1)) if m else None


def _fixed_md_owns(line, item_id, bracket_re, bare_re):
    """Returns the heading LEVEL (2 or 3) if this `## `/`### ` line is <item_id>'s OWN heading,
    else None. Ownership is real-data-derived (measured against every heading in docs/Fixed.md,
    B1 finding evidence): a `[<item_id>]` bracket appearing ANYWHERE on a heading line is ALWAYS
    that item's own id in this corpus (verified: zero headings ever carry two distinct bracketed
    ids), covering the `## [ATM-340] ...`, `## §FL [ATM-498] ...`, and `## GO. [ATM-401] ...`
    prefixed forms alike -- the B1 gap: the prior pattern required the id immediately after the
    heading marker, which a bracket or a `§X`/`GO.`-class prefix always defeats. The legacy BARE
    form (`## ATM-292 -- title`, no brackets at all) is accepted ONLY when <item_id> is the FIRST
    token right after the marker: a bare id appearing later in the title text is a cross-reference
    to a DIFFERENT item (measured real cases: "## ATM-697 -- ... (sibling of ATM-695)" MUST NOT be
    read as ATM-695's own heading), never this item's own evidence."""
    level = _fixed_md_heading_level(line)
    if level is None:
        return None
    if bracket_re.search(line) or bare_re.match(line):
        return level
    return None


def scan_closure_fixed_md(repo, item_id, live_ids):
    """The item's OWN heading section only -- never a bare grep for the item id anywhere in
    docs/Fixed.md, which would wrongly harvest anchors from an UNRELATED item's write-up that
    merely mentions this item id in a cross-reference (e.g. "Composes with ATM-277"). A section
    runs from its owning heading line up to (excluding) the next heading at the SAME level or
    HIGHER (never a heading at a deeper level, which is a subsection of the same item, e.g.
    `### Root cause` / `### Fix` / `### Captured evidence` under a `## [ID]` owning heading --
    B1 finding: stopping at ANY `###` line cut 41 real item sections short). This is a strict
    generalisation of the reviewer's "stop only at the next `^## `" fix: for the overwhelming
    common case (an item owned by a level-2 `## [ID]` heading) it is byte-identical to that
    fix (boundary = next `^##\\s`); it additionally handles the rare real case of an item owned
    by a level-3 heading (e.g. `### [ATM-008]` nested under an unrelated grouping heading) without
    over-absorbing a SIBLING level-3 item's content into this item's closure evidence -- a
    same-level-3 heading still ends the section in that case, exactly as a `##` heading would for
    a level-2-owned item."""
    path = os.path.join(repo, "docs", "Fixed.md")
    if not os.path.isfile(path):
        return []
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            lines = fh.read().split("\n")
    except OSError:
        return []
    bracket_re = re.compile(r"\[%s\]" % re.escape(item_id))
    bare_re = re.compile(r"^#{2,3}\s+%s\b" % re.escape(item_id))
    section = []
    in_section = False
    own_level = None
    for line in lines:
        if in_section:
            cur_level = _fixed_md_heading_level(line)
            if cur_level is not None and cur_level <= own_level:
                break
            section.append(line)
            continue
        lvl = _fixed_md_owns(line, item_id, bracket_re, bare_re)
        if lvl is not None:
            in_section = True
            own_level = lvl
            section = [line]
    if not section:
        return []
    evidence = "docs/Fixed.md#%s" % item_id
    text = "\n".join(section)
    return [(a, "closure", evidence) for a in _filter_live(_extract_tokens(text), live_ids)]


def scan_closure_db(repo, item_id, live_ids):
    """Any row for this item in docs/workable_items.db that is actually CLOSED (current_location
    != 'Issues') -- an item still open (current_location == 'Issues') has no closure evidence yet,
    regardless of what its live investigation text happens to mention.

    I3 fix: returns (citations: list[tuple], diagnostic: str|None). A `sqlite3.Error` on connect
    OR on query execution (e.g. a schema change dropping/renaming a column this query selects) now
    surfaces a diagnostic the same way the commit source's own git-level faults already do, rather
    than silently returning [] -- a real DB-read FAILURE must be distinguishable from "this item
    genuinely has zero closure citations in the DB", never conflated (§11.4.201(6))."""
    db_path = os.path.join(repo, "docs", "workable_items.db")
    if not os.path.isfile(db_path):
        return [], None
    try:
        uri = "file:%s?mode=ro" % urllib.parse.quote(os.path.abspath(db_path))
        conn = sqlite3.connect(uri, uri=True, timeout=5)
    except sqlite3.Error as exc:
        return [], "closure/db source: cannot open %s: %s" % (db_path, exc)
    try:
        try:
            cur = conn.cursor()
            cur.execute(
                "SELECT current_location, description, closure_criteria, body_md, forensic_anchor "
                "FROM items WHERE atm_id = ?",
                (item_id,),
            )
            rows = cur.fetchall()
        except sqlite3.Error as exc:
            return [], "closure/db source: query failed against %s: %s" % (db_path, exc)
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
    return citations, None


def collect(item_id, repo, live_ids, sources, as_of=None, review_records_dir=None):
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
        review_citations, review_note = scan_review(item_id, live_ids, review_records_dir)
        citations.extend(review_citations)
        if review_note:
            diagnostics.append(review_note)
    if "closure" in sources:
        citations.extend(scan_closure_fixed_md(repo, item_id, live_ids))
        db_citations, db_err = scan_closure_db(repo, item_id, live_ids)
        citations.extend(db_citations)
        if db_err:
            diagnostics.append(db_err)
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


# M1: the commit source is the only one bounded by --as-of (commits carry a real committer/author
# date to bound against; diary/review/closure have no comparable per-artefact timestamp today) --
# recorded explicitly in run_meta rather than left an undocumented inconsistency.
_AS_OF_UNBOUNDED_SOURCES = ("diary", "review", "closure")


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
        run_meta["as_of_unbounded_sources"] = [s for s in sources if s in _AS_OF_UNBOUNDED_SOURCES]

    if a.determinism_check:
        run1, diag1 = collect(a.item_id, a.repo, live_ids, sources, as_of=as_of, review_records_dir=a.review_records)
        run2, diag2 = collect(a.item_id, a.repo, live_ids, sources, as_of=as_of, review_records_dir=a.review_records)
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
        citations, diagnostics = collect(a.item_id, a.repo, live_ids, sources, as_of=as_of,
                                          review_records_dir=a.review_records)

    for d in diagnostics:
        print("anchor_citations: note: %s" % d, file=sys.stderr)

    body = _body_for(a.item_id, citations, live_ids)
    rc = _emit(body, run_meta, a.out, code=0)
    return rc


def main(argv):
    """I2 fix: `_main_impl`'s WHOLE body is guarded here so any internal failure this tool does
    not classify more specifically (a decode error on an artefact _main_impl's own per-call guards
    do not yet cover, or any other unforeseen internal fault) resolves to the documented BLIND exit
    code 4 with a diagnostic on stderr -- never a raw unhandled traceback surfacing under the
    reserved-for-nondeterminism exit 1 (the contract's own C-001 exit-1 meaning "the SAME inputs
    produced two DIFFERENT results", never "the tool crashed")."""
    try:
        return _main_impl(argv)
    except (OSError, UnicodeDecodeError, ValueError, RuntimeError) as exc:
        print("anchor_citations: BLIND -- internal error: %s: %s" % (type(exc).__name__, exc), file=sys.stderr)
        return 4


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
