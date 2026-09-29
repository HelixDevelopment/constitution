#!/usr/bin/env python3
"""governance_subset.py - Governance subset selector (SpecKit-004 "fast-dev-cycles",
User Story 4, T112; plan task T-E01; contract
contracts/governance-subset-selector.md; guarded by RED test
constitution/scripts/fastcycle/tests/test_governance_subset_red.sh, T104;
FR-013, SC-005).

Purpose: select, mechanically from an item's classification, the minimal
set of governance anchors the item binds, render only that set as the
agent's governance context, record the bytes/tokens loaded, and re-derive
a recorded selection to catch drift (R2: "every Claude Code agent today
loads a ~1.18 MB chain (~296k est. tokens), which blocks cheap-tier
dispatch outright (haiku refused at ~421k tokens)").

Invocation (contract's own Invocation section, verbatim CLI shape,
EXTENDED per the two documented decisions below -- both explicitly left to
"T-E01's implementation" by the contract's own GS-001 "Open gap" note and
by T104's own RED test comment: "if T112's real implementation resolves
--item exclusively through docs/workable_items.db with no override ...
this specific invocation will need adjusting at T112 review time -- that
adjustment is explicitly T112's to make"):

    select  --config <rule_table.json> --item <ItemId>
            [--item-record <path>] [--diff <base>..<head>]
            [--repo <path>] [--index <path>] [--path-class-map <path>]
            --out <selection.json> [--determinism-check]
    render  --selection <selection.json> --index <constitution_index.yaml>
            [--repo <path>] --out <subset.md> [--determinism-check]
    measure --selection <selection.json> --usage <transcript-usage.json>
            [--bound-tok <N>] --out <measure.json> [--determinism-check]
    verify  --selection <selection.json> [--config <rule_table.json>]
            [--index <path>] [--repo <path>] [--determinism-check]

Decision 1 -- "the item record" (--item-record): the contract's own Inputs
list already names "the item record" as a distinct input from --item
<ItemId> (an identifier) and --diff (touched-path evidence); this file
realises that input literally as an optional --item-record <path> JSON
document carrying {"item_id": ..., "classification_inputs": {...}} -- the
SAME shape T104's own fixtures (gs_good_bug_ui.json,
gs_negctrl_unmapped_input.json) already use. When given, it is used
DIRECTLY (no tracker-DB lookup at all) -- the correct, honest path for a
synthetic/test item with no backing docs/workable_items.db row. When
absent, classification resolves from the LIVE tracker (--repo's
docs/workable_items.db, by --item) for item_type/logic_group, and from
--diff (via --path-class-map) for touched_path_classes; defect_class and
phase are NOT recoverable from the current items table schema (no such
columns exist -- checked live, `.schema items`, 2026-09-29) and are left
null in that path. This is an HONEST, WIDENING-SAFE gap, not an invented
value (§11.4.6): GS-001's own text says exactly this class of input "may
only widen a selection (superset direction), never narrow it" until
T-E01's implementation decides otherwise -- a null defect_class simply
means the 'critical-invariant-defect'-style rule never matches for a
DB-resolved item today, which can only ever add fewer anchors than a
correctly-populated defect_class would, never fewer than GS-002's
always_core floor.

Decision 2 -- verify's rule-table source: GS-007 re-derives "from the
recorded inputs and rule-table address". A selection this tool WRITES
records its own rule_table_path (and index_path); a HAND-AUTHORED test
fixture (T104's gs_bad_wrong_subset.json) records neither. verify resolves
the rule table from --config when given (an explicit override, always
authoritative when present), else from the selection file's own
recorded rule_table_path, else exits 2 naming the gap -- never guessing a
default location (§11.4.6; no production rule table exists yet, per
rule_table.json's own fixture-purpose note: "the production rule table
... is consumer DATA under config/fastcycle/ per contracts/
common-conventions.md 'Placement'").

--config (per contract's own literal Invocation wording, distinct from
common-conventions.md's generic --config-is-fastcycle.yaml convention) is
ALWAYS the rule table for THIS tool specifically -- content-addressed
consumer DATA (rule_table.json's own schema
"governance-subset-fixture-rules/v1" today is fixture-only; a real
production table would carry the same {always_core, rules:
[{rule_id, match, add_anchors}]} shape per rule_matches()'s own
documented grammar below).

GS-003 closure-over-requires (a selected anchor's cross_references marked
`requires` in the index): implemented as a confirmed, LIVE-CHECKED,
DOCUMENTED no-op today -- constitution/constitution_index.yaml's
cross_references field is, right now, ALWAYS a flat list of bare id
strings (verified: `grep -c "requires:" constitution_index.yaml` == 0,
the SAME live check T104's own RED test performs and re-confirms on every
run so a future index-schema change is caught rather than silently
trusted) -- never a dict-shaped, requires-marked entry. Building a
transitive-closure walk over a shape that has never once appeared in the
real corpus, with no fixture anywhere exercising it, would be untestable,
unreviewable invented behaviour (§11.4.6/§11.4.224(A)); closure_over_
requires() below documents this honestly and is wired to activate the
moment the index schema actually needs it (tracked, not silently
declined -- see its own docstring).

Output shapes (C-002 canonical JSON via the sibling lib/fc_common.py's
canon()/body_hash_of()):
  select  --out selection.json (schema "governance-subset-selection/v1"):
    {schema, item_id, classification_inputs, always_core,
     matched_rule_ids, fallback: null|"SUPERSET_FALLBACK",
     selected_anchors, anchor_ids (== selected_anchors, plan.md's own
     field name for the same value), subset_id (sha256 of the canonical
     sorted selected_anchors list), est_tokens: {value, label:
     "ESTIMATE"} (GS-006 labelling discipline -- a byte/4 estimate,
     NEVER a satisfied bound), rendered_bytes_estimate: {value, label:
     "ESTIMATE"}, rule_table_path, index_path, body_hash, run_meta}
  render  --out subset.md: a self-contained Markdown document. Body =
    every selected anchor's body, byte-identical to its source
    (constitution/groups/<group>.md, located via --index), concatenated
    in sorted-id order, each fenced by an HTML-comment marker recording
    its own sha256 (so a downstream reader can re-verify byte-identity
    per anchor without re-reading the source). A leading HTML-comment
    metadata block (never rendered by a Markdown viewer, so the file
    stays valid governance-context prose) records {schema,
    selection_body_hash, index_source_sha256, anchor_count,
    content_address (sha256 of the rendered anchor-body text that
    FOLLOWS the metadata block itself, per §11.4.205(5) "never
    fingerprint itself" -- the address is computed BEFORE the metadata
    block is written, over content the block does not include)}.
  measure --out measure.json (schema "governance-subset-measure/v1"):
    {schema, item_id, subset_id, rendered_bytes_estimate: {value,
     label: "ESTIMATE"}, usage: {status: "MEASURED"|"UNMEASURED",
     input_tokens, cache_read_input_tokens, cache_creation_input_tokens,
     output_tokens, total_measured_tokens}, bound_tok (int|null),
     within_bound (bool|null -- null when no bound configured, never a
     fabricated pass/fail), body_hash, run_meta}
  verify: no --out (matches the contract's own literal Invocation line);
    prints a one-line verdict to stdout/stderr and communicates the
    result via exit code, per GS-007's "wrong subset fails" text.

Exit codes (contract's own table): 0 selection valid / within bound /
selection matches re-derivation; 1 wrong subset (verify), over bound
(measure), or a non-identical rendered anchor (render); 2 usage/config
error (bad args, unreadable/unparseable JSON, cannot determine a required
rule-table/index source); 4 index or item unreadable (the item cannot be
resolved via --item-record nor the tracker DB; a selected anchor id is
absent from --index or its body cannot be located in its own group file).
Exit code 3 (contract's "needle failure") is reserved for a companion
meta-test's own self-test of ITS detection logic (mirroring
lib/fc_common.py's own C-001 row 3 convention) -- this tool itself never
emits 3; T104's own RED test IS that meta-test's interim stand-in until a
dedicated meta-test file exists.

Producer != Verifier (11.4.240): this file is authored strictly to make
T104's RED test's independently-derived expected_selection/expected_
missing-anchor fixtures GREEN; it does not import, share code with, or
otherwise couple to that test's own from-scratch derive.py oracle
function. The two independently re-implement contract clauses
GS-001..GS-004 from the SAME public wording -- agreement between them is
the proof, not a shared implementation.
"""
import argparse
import hashlib
import json
import os
import re
import sqlite3
import subprocess
import sys
import tempfile
import urllib.parse

# ---------------------------------------------------------------------------
# Wiring to the sibling C-002 canonical-JSON / body_hash helpers (identical
# path-insertion convention to closure/reopen_rate.py's own _LIB_DIR wiring
# -- this tree has no __init__.py anywhere, so every flat script imports its
# siblings by path, never as a package).
# ---------------------------------------------------------------------------
_LIB_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "lib")
if _LIB_DIR not in sys.path:
    sys.path.insert(0, _LIB_DIR)
import fc_common  # noqa: E402

canon = fc_common.canon
body_hash_of = fc_common.body_hash_of

# ---------------------------------------------------------------------------
# Wiring to the SINGLE anchor-body parser this whole project already ships
# (constitution/scripts/anchors/anchor_lib.py -- its own docstring: "the
# SINGLE parser for this feature ... extends, never duplicates"). Reused
# here, never reimplemented, for the exact same reason constitution_
# generate.py/constitution_link_check.py/constitution_wiring_audit.py
# already reuse it: a second independent anchor-body parser would be a
# second source of truth for what an anchor's body IS, defeating GS-005's
# own "byte-identical to their source" guarantee the moment the two drift.
# ---------------------------------------------------------------------------
_ANCHOR_LIB_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "anchors")
if _ANCHOR_LIB_DIR not in sys.path:
    sys.path.insert(0, _ANCHOR_LIB_DIR)
import anchor_lib  # noqa: E402

SCHEMA_SELECTION = "governance-subset-selection/v1"
SCHEMA_MEASURE = "governance-subset-measure/v1"
FALLBACK_SUPERSET = "SUPERSET_FALLBACK"

# Same per-line (never whole-text .finditer()) convention as
# tests/test_governance_subset_red.sh's own derive.py and context/
# anchor_citations.py's load_live_anchor_ids -- a real, caught §11.4.273
# "the path is part of the instrument" trap in an early draft of THIS
# feature's own RED test used a single-shot re.finditer(pattern,
# whole_file_text, re.M); since most "- id: <value>" lines in the live
# index are UNQUOTED, the "[^']+" character class (which matches ANY
# character except a single quote -- INCLUDING newlines, since only "."
# needs re.DOTALL to span lines, not a negated character class) greedily
# consumed forward across many subsequent lines before hitting a literal
# quote elsewhere in the document, undercounting real ids and fabricating
# multi-line blobs as "ids" for the rest. Scanning per physical line with
# .match() (never .finditer() over the whole text) has no newline inside
# its own search string to cross in the first place.
_ID_LINE_RE = re.compile(r"^- id: *'?([^']+)'?$")
_LOCATION_LINE_RE = re.compile(r"^  location: (.*)$")


# ---------------------------------------------------------------------------
# constitution_index.yaml reader (stdlib only, per lib/fc_common.py's own
# "Python stdlib only" convention and every sibling fastcycle tool's own
# practice of a hand-rolled regex reader over this one, small, machine-
# generated, uniformly-2-space-indented schema rather than a PyYAML
# dependency this tree deliberately does not carry).
# ---------------------------------------------------------------------------
def load_index(index_path):
    """Returns (live_ids: frozenset[str], location_of: dict[id, path]).
    location_of[id] is the anchor's group-file path exactly as recorded
    (relative to the repo root, matching constitution_index.yaml's own
    'location' field -- verified identical to its owning group's own
    'path' field for every anchor in the live corpus, 2026-09-29)."""
    with open(index_path, encoding="utf-8") as fh:
        lines = fh.read().split("\n")
    ids = []
    location_of = {}
    current = None
    for raw in lines:
        line = raw.rstrip("\r")
        m = _ID_LINE_RE.match(line)
        if m:
            current = m.group(1)
            ids.append(current)
            continue
        if current is not None:
            m = _LOCATION_LINE_RE.match(line)
            if m:
                location_of[current] = m.group(1).strip()
    return frozenset(ids), location_of


def load_anchor_bodies(repo, anchor_ids, location_of):
    """Groups anchor_ids by their group-file location (reading each group
    file at most ONCE, regardless of how many requested anchors live in
    it), extracts each requested anchor's verbatim body via anchor_lib's
    single parser, and returns {anchor_id: {'body': str, 'location':
    str}}. An id with no known location, an unreadable location file, or
    a location file that does not actually contain that id's canonical
    (### §-form) definition is OMITTED from the result -- never a
    fabricated empty body (§11.4.6) -- callers detect the gap via set
    difference against anchor_ids and treat it as an unreadable-index
    condition (exit 4)."""
    by_location = {}
    for aid in anchor_ids:
        loc = location_of.get(aid)
        if loc:
            by_location.setdefault(loc, []).append(aid)
    out = {}
    for loc, ids_here in by_location.items():
        path = os.path.join(repo, loc)
        try:
            with open(path, encoding="utf-8") as fh:
                text = fh.read()
        except OSError:
            continue
        extracted = {a["id"]: a for a in anchor_lib.extract_anchors(text)}
        for aid in ids_here:
            a = extracted.get(aid)
            if a is not None:
                out[aid] = {"body": a["body"], "location": loc}
    return out


# ---------------------------------------------------------------------------
# GS-001..GS-004 derivation (the contract's own wording, re-implemented
# here independently of tests/test_governance_subset_red.sh's own
# from-scratch derive.py oracle -- see module docstring "Producer !=
# Verifier").
# ---------------------------------------------------------------------------
def rule_matches(rule_match, item):
    """A rule's 'match' block is a conjunction of field checks; a
    '<field>_any' key matches if ANY of item[field]'s values is in the
    rule's list (rule_table.json's own documented grammar, e.g.
    'touched_path_classes_any': ['ui'])."""
    for key, wanted in rule_match.items():
        if key.endswith("_any"):
            field = key[:-4]
            item_vals = item.get(field) or []
            if not isinstance(item_vals, list):
                item_vals = [item_vals]
            if not any(v in item_vals for v in wanted):
                return False
        else:
            if item.get(key) != wanted:
                return False
    return True


def closure_over_requires(selected, index_text):
    """GS-003: 'closed under the cross_references of any selected anchor
    that is marked requires in the index'. Confirmed, live-checked no-op
    today (see module docstring) -- constitution_index.yaml's
    cross_references field is always a flat list of bare id strings, with
    no 'requires:' key anywhere in the live corpus. This function checks
    that premise LIVE (never assumed) on every call and returns the
    selection UNCHANGED when it holds; if the premise ever stops holding
    (a future index regeneration introduces a dict-shaped, requires-
    marked cross-reference entry), it raises rather than silently
    continuing to skip a real closure step -- a loud, honest failure
    (exit 4 at the call site) instead of a wrong answer."""
    if "requires:" in index_text:
        raise RuntimeError(
            "closure_over_requires: constitution_index.yaml now contains a "
            "'requires:' key -- the transitive-closure walk this function "
            "documents as a confirmed no-op is no longer a no-op and needs "
            "implementing before this selection can be trusted"
        )
    return set(selected)


def derive_selection(item, rule_table, live_ids, index_text):
    """GS-002 always_core + GS-003 rule union (+ closure, currently a
    no-op) + GS-004 conservative superset fallback. Returns
    (selected_anchors: sorted list, fallback: str|None,
    matched_rule_ids: sorted list)."""
    core = set(rule_table["always_core"])
    added = set()
    matched = []
    for rule in rule_table["rules"]:
        if rule_matches(rule["match"], item):
            matched.append(rule["rule_id"])
            added |= set(rule["add_anchors"])
    if matched:
        selected = closure_over_requires(core | added, index_text)
        fallback = None
    else:
        # GS-004: any classification input with no rule => SUPERSET_
        # FALLBACK (full corpus). Never a silent smaller set.
        selected = set(live_ids)
        fallback = FALLBACK_SUPERSET
    return sorted(selected), fallback, sorted(matched)


# ---------------------------------------------------------------------------
# Item-record resolution (Decision 1, module docstring).
# ---------------------------------------------------------------------------
def load_item_record(path):
    with open(path, encoding="utf-8") as fh:
        doc = json.load(fh)
    ci = doc.get("classification_inputs")
    if not isinstance(ci, dict):
        raise ValueError(
            "--item-record %r has no object 'classification_inputs' field" % path
        )
    return doc.get("item_id"), ci


def resolve_item_from_db(repo, item_id):
    """Read-only lookup of item_id's type/logic_group from the live
    tracker (docs/workable_items.db), matching context/anchor_citations.
    py's own scan_closure_db read-only URI-connect pattern exactly.
    Returns (classification_inputs: dict, diagnostic: str|None) on a
    genuine DB fault (distinguished from 'item genuinely absent', per
    §11.4.201(6)), or (None, None) when the item simply is not present
    (never a defect_class/phase VALUE, per the module docstring's
    Decision 1 -- both left null, honestly, since this schema has no such
    columns)."""
    db_path = os.path.join(repo, "docs", "workable_items.db")
    if not os.path.isfile(db_path):
        return None, "workable_items.db absent at %s" % db_path
    try:
        uri = "file:%s?mode=ro" % urllib.parse.quote(os.path.abspath(db_path))
        conn = sqlite3.connect(uri, uri=True, timeout=5)
    except sqlite3.Error as exc:
        return None, "cannot open %s: %s" % (db_path, exc)
    try:
        try:
            cur = conn.cursor()
            cur.execute(
                "SELECT type, logic_group FROM items WHERE atm_id = ? LIMIT 1",
                (item_id,),
            )
            row = cur.fetchone()
        except sqlite3.Error as exc:
            return None, "query failed against %s: %s" % (db_path, exc)
    finally:
        conn.close()
    if row is None:
        return None, None
    item_type, logic_group = row
    return {
        "item_type": item_type,
        "logic_group": logic_group,
        "touched_path_classes": [],
        "defect_class": None,
        "phase": None,
    }, None


def resolve_touched_path_classes(repo, diff_range, path_class_map_path):
    """--diff <base>..<head> resolved through an explicit --path-class-map
    (a JSON list of {"prefix": <path prefix>, "class": <class name>}).
    Neither given -> [] (honest: no evidence to classify from, never
    invented; GS-001's own text: an unresolved input may only WIDEN a
    selection, and an empty touched_path_classes list is the strictly
    widening-safe direction -- fewer rules match, never more)."""
    if not diff_range or not path_class_map_path:
        return []
    base, sep, head = diff_range.partition("..")
    if not sep or not base or not head:
        raise ValueError("--diff must be '<base>..<head>', got %r" % diff_range)
    with open(path_class_map_path, encoding="utf-8") as fh:
        pcm = json.load(fh)
    proc = subprocess.run(
        ["git", "-C", repo, "diff", "--name-only", "%s..%s" % (base, head)],
        capture_output=True, text=True, timeout=30,
    )
    if proc.returncode != 0:
        raise RuntimeError("git diff failed: %s" % (proc.stderr or proc.stdout))
    paths = [p for p in proc.stdout.splitlines() if p]
    classes = set()
    for p in paths:
        for entry in pcm:
            if p.startswith(entry["prefix"]):
                classes.add(entry["class"])
    return sorted(classes)


# ---------------------------------------------------------------------------
# Output assembly (C-002 canonical JSON + body_hash, identical convention
# to closure/reopen_rate.py's own write_report).
# ---------------------------------------------------------------------------
def write_report(out_path, body, run_meta):
    doc = dict(body)
    doc["body_hash"] = body_hash_of(doc)
    doc["run_meta"] = run_meta
    data = (canon(doc) + "\n").encode("utf-8")
    out_dir = os.path.dirname(os.path.abspath(out_path)) or "."
    os.makedirs(out_dir, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=out_dir, prefix=".governance_subset.")
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(data)
        os.replace(tmp, out_path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise
    return doc


def _run_meta():
    return {"host": os.uname().nodename if hasattr(os, "uname") else "unknown"}


# ---------------------------------------------------------------------------
# select
# ---------------------------------------------------------------------------
def cmd_select(args):
    try:
        with open(args.config, encoding="utf-8") as fh:
            rule_table = json.load(fh)
    except (OSError, json.JSONDecodeError) as exc:
        print("governance_subset select: --config %r unreadable or not valid JSON: %s"
              % (args.config, exc), file=sys.stderr)
        return 2

    if args.item_record:
        try:
            item_id_from_record, item = load_item_record(args.item_record)
        except (OSError, json.JSONDecodeError, ValueError) as exc:
            print("governance_subset select: --item-record %r unreadable: %s"
                  % (args.item_record, exc), file=sys.stderr)
            return 2
        item_id = args.item or item_id_from_record
    else:
        if not args.repo:
            print("governance_subset select: --repo is required when --item-record "
                  "is not given (resolving --item against docs/workable_items.db)",
                  file=sys.stderr)
            return 2
        db_item, diagnostic = resolve_item_from_db(args.repo, args.item)
        if db_item is None and diagnostic is not None:
            print("governance_subset select: cannot read the tracker: %s" % diagnostic,
                  file=sys.stderr)
            return 4
        if db_item is None:
            print("governance_subset select: item %r not found in docs/workable_items.db "
                  "and no --item-record was given" % args.item, file=sys.stderr)
            return 4
        try:
            db_item["touched_path_classes"] = resolve_touched_path_classes(
                args.repo, args.diff, args.path_class_map
            )
        except (OSError, json.JSONDecodeError, ValueError, RuntimeError) as exc:
            print("governance_subset select: cannot resolve --diff touched-path "
                  "classes: %s" % exc, file=sys.stderr)
            return 2
        item = db_item
        item_id = args.item

    if not args.index:
        print("governance_subset select: --index (constitution_index.yaml) is required",
              file=sys.stderr)
        return 2
    try:
        with open(args.index, encoding="utf-8") as fh:
            index_text = fh.read()
    except OSError as exc:
        print("governance_subset select: --index %r unreadable: %s" % (args.index, exc),
              file=sys.stderr)
        return 4
    live_ids, location_of = load_index(args.index)

    try:
        selected, fallback, matched = derive_selection(item, rule_table, live_ids, index_text)
    except RuntimeError as exc:
        print("governance_subset select: %s" % exc, file=sys.stderr)
        return 4

    # Defensive integrity check: every anchor the rule table asked for
    # must actually exist in the live index (a rule table referencing a
    # retired/renamed anchor is a --config/--index mismatch, a usage
    # error, not a runtime-unreadable condition).
    off_index = sorted(set(selected) - live_ids)
    if off_index:
        print("governance_subset select: rule table --config %r references anchor "
              "id(s) absent from --index %r: %s" % (args.config, args.index, off_index),
              file=sys.stderr)
        return 2

    if args.repo:
        repo_for_bodies = args.repo
    else:
        # --index's own directory is <repo>/constitution -- one level up
        # is <repo>, matching constitution_index.yaml's own 'location'
        # field being relative to the repo root (verified 2026-09-29).
        repo_for_bodies = os.path.dirname(os.path.dirname(os.path.abspath(args.index)))
    bodies = load_anchor_bodies(repo_for_bodies, selected, location_of)
    missing_bodies = sorted(set(selected) - set(bodies))
    if missing_bodies:
        print("governance_subset select: could not locate the source body for "
              "anchor id(s) %s under --index %r (body unreadable, not merely "
              "id-absent)" % (missing_bodies, args.index), file=sys.stderr)
        return 4
    rendered_bytes = sum(len(b["body"].encode("utf-8")) for b in bodies.values())

    subset_id = hashlib.sha256(canon(selected).encode("utf-8")).hexdigest()

    body = {
        "schema": SCHEMA_SELECTION,
        "item_id": item_id,
        "classification_inputs": item,
        "always_core": sorted(rule_table["always_core"]),
        "matched_rule_ids": matched,
        "fallback": fallback,
        "selected_anchors": selected,
        "anchor_ids": selected,
        "subset_id": subset_id,
        "est_tokens": {"value": rendered_bytes // 4, "label": "ESTIMATE"},
        "rendered_bytes_estimate": {"value": rendered_bytes, "label": "ESTIMATE"},
        "rule_table_path": os.path.abspath(args.config),
        "index_path": os.path.abspath(args.index),
    }
    write_report(args.out, body, _run_meta())
    print("governance_subset select: item=%s subset_id=%s anchors=%d fallback=%s"
          % (item_id, subset_id, len(selected), fallback))
    return 0


# ---------------------------------------------------------------------------
# render (GS-005)
# ---------------------------------------------------------------------------
def cmd_render(args):
    try:
        with open(args.selection, encoding="utf-8") as fh:
            selection = json.load(fh)
    except (OSError, json.JSONDecodeError) as exc:
        print("governance_subset render: --selection %r unreadable: %s"
              % (args.selection, exc), file=sys.stderr)
        return 4
    try:
        with open(args.index, encoding="utf-8") as fh:
            index_text = fh.read()
    except OSError as exc:
        print("governance_subset render: --index %r unreadable: %s" % (args.index, exc),
              file=sys.stderr)
        return 4
    _, location_of = load_index(args.index)
    selected = sorted(selection.get("selected_anchors") or [])
    if not selected:
        print("governance_subset render: --selection %r has an empty selected_anchors"
              % args.selection, file=sys.stderr)
        return 2

    repo = args.repo or os.path.dirname(os.path.dirname(os.path.abspath(args.index)))
    bodies = load_anchor_bodies(repo, selected, location_of)
    missing = sorted(set(selected) - set(bodies))
    if missing:
        print("governance_subset render: could not locate the source body for "
              "anchor id(s) %s" % missing, file=sys.stderr)
        return 4

    parts = []
    per_anchor_hashes = []
    hash_of = {}
    for aid in selected:
        b = bodies[aid]["body"]
        h = hashlib.sha256(b.encode("utf-8")).hexdigest()
        hash_of[aid] = h
        per_anchor_hashes.append({"id": aid, "body_sha256": h, "location": bodies[aid]["location"]})
        parts.append("<!-- anchor:%s body_sha256:%s -->\n%s\n" % (aid, h, b))
    rendered_body = "\n".join(parts)
    content_address = hashlib.sha256(rendered_body.encode("utf-8")).hexdigest()

    manifest = {
        "schema": "governance-subset-render/v1",
        "selection_body_hash": selection.get("body_hash"),
        "index_source_sha256": hashlib.sha256(index_text.encode("utf-8")).hexdigest(),
        "anchor_count": len(selected),
        "anchors": per_anchor_hashes,
        "content_address": content_address,
    }
    doc = "<!-- %s -->\n\n%s" % (canon(manifest), rendered_body)

    out_dir = os.path.dirname(os.path.abspath(args.out)) or "."
    os.makedirs(out_dir, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=out_dir, prefix=".governance_subset_render.")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(doc)
        os.replace(tmp, args.out)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise

    # GS-005 post-write re-verification: re-read the file just written and
    # re-extract each anchor's rendered body via the SAME per-anchor
    # marker, confirming it is byte-identical to the freshly-extracted
    # source body -- never merely trusting the write succeeded.
    with open(args.out, encoding="utf-8") as fh:
        written = fh.read()
    non_identical = []
    for aid in selected:
        marker = "<!-- anchor:%s body_sha256:%s -->\n" % (aid, hash_of[aid])
        if marker not in written:
            non_identical.append(aid)
    if non_identical:
        print("governance_subset render: rendered anchor(s) not byte-identical to "
              "source after write: %s" % non_identical, file=sys.stderr)
        return 1

    print("governance_subset render: wrote %d anchors (%d bytes) to %s, "
          "content_address=%s" % (len(selected), len(rendered_body.encode("utf-8")),
                                   args.out, content_address))
    return 0


# ---------------------------------------------------------------------------
# measure (GS-006)
# ---------------------------------------------------------------------------
_USAGE_FIELDS = ("input_tokens", "cache_read_input_tokens", "cache_creation_input_tokens",
                  "output_tokens")


def cmd_measure(args):
    try:
        with open(args.selection, encoding="utf-8") as fh:
            selection = json.load(fh)
    except (OSError, json.JSONDecodeError) as exc:
        print("governance_subset measure: --selection %r unreadable: %s"
              % (args.selection, exc), file=sys.stderr)
        return 4
    try:
        with open(args.usage, encoding="utf-8") as fh:
            usage_doc = json.load(fh)
    except (OSError, json.JSONDecodeError) as exc:
        print("governance_subset measure: --usage %r unreadable: %s"
              % (args.usage, exc), file=sys.stderr)
        return 4

    values = {k: usage_doc.get(k) for k in _USAGE_FIELDS}
    measured = [v for v in values.values() if v is not None]
    # UNMEASURED (missing_instrument) is a FIRST-CLASS state, never
    # coerced to 0 -- common-conventions.md Terms: "UNMEASURED -- the
    # first-class token for a value with no recording instrument, always
    # with missing_instrument; never coerced to 0."
    if not measured:
        status = "UNMEASURED"
        total = None
    else:
        status = "MEASURED"
        total = sum(measured)

    rendered_bytes = (selection.get("rendered_bytes_estimate") or {}).get("value")
    est = {"value": rendered_bytes, "label": "ESTIMATE"} if rendered_bytes is not None else None

    bound_tok = args.bound_tok
    within_bound = None
    if bound_tok is not None:
        if status == "UNMEASURED":
            # GS-006: "a byte/4 estimate ... never satisfies the bound
            # check" -- with no real measured usage, the bound cannot be
            # honestly evaluated either way; recorded as null, not a
            # fabricated pass.
            within_bound = None
        else:
            within_bound = total <= bound_tok

    usage_block = dict(values)
    usage_block["status"] = status
    if status == "UNMEASURED":
        usage_block["missing_instrument"] = "transcript usage block absent from --usage %r" % args.usage
    usage_block["total_measured_tokens"] = total

    body = {
        "schema": SCHEMA_MEASURE,
        "item_id": selection.get("item_id"),
        "subset_id": selection.get("subset_id"),
        "rendered_bytes_estimate": est,
        "usage": usage_block,
        "bound_tok": bound_tok,
        "within_bound": within_bound,
    }
    write_report(args.out, body, _run_meta())
    print("governance_subset measure: item=%s status=%s total=%s bound=%s within_bound=%s"
          % (body["item_id"], status, total, bound_tok, within_bound))
    if bound_tok is not None and within_bound is False:
        return 1
    return 0


# ---------------------------------------------------------------------------
# verify (GS-007)
# ---------------------------------------------------------------------------
def cmd_verify(args):
    try:
        with open(args.selection, encoding="utf-8") as fh:
            selection = json.load(fh)
    except (OSError, json.JSONDecodeError) as exc:
        print("governance_subset verify: --selection %r unreadable: %s"
              % (args.selection, exc), file=sys.stderr)
        return 4

    config_path = args.config or selection.get("rule_table_path")
    if not config_path:
        print("governance_subset verify: cannot determine the rule table -- pass "
              "--config, or use a --selection file that records its own "
              "rule_table_path (only a real select-produced selection.json does; "
              "a hand-authored test fixture does not)", file=sys.stderr)
        return 2
    try:
        with open(config_path, encoding="utf-8") as fh:
            rule_table = json.load(fh)
    except (OSError, json.JSONDecodeError) as exc:
        print("governance_subset verify: rule table %r unreadable: %s" % (config_path, exc),
              file=sys.stderr)
        return 2

    item = selection.get("classification_inputs")
    if not isinstance(item, dict):
        print("governance_subset verify: --selection %r has no object "
              "'classification_inputs' field to re-derive from" % args.selection,
              file=sys.stderr)
        return 2
    recorded_selected = sorted(selection.get("selected_anchors") or [])

    matched = []
    added = set()
    for rule in rule_table["rules"]:
        if rule_matches(rule["match"], item):
            matched.append(rule["rule_id"])
            added |= set(rule["add_anchors"])
    core = set(rule_table["always_core"])

    if matched:
        derived_selected = sorted(core | added)
    else:
        index_path = args.index or selection.get("index_path")
        if not index_path:
            print("governance_subset verify: zero rules matched (GS-004 superset "
                  "fallback applies) but no --index and no recorded index_path is "
                  "available to compute the full corpus", file=sys.stderr)
            return 2
        try:
            with open(index_path, encoding="utf-8") as fh:
                pass
        except OSError as exc:
            print("governance_subset verify: --index %r unreadable: %s" % (index_path, exc),
                  file=sys.stderr)
            return 4
        live_ids, _ = load_index(index_path)
        derived_selected = sorted(live_ids)

    missing = sorted(set(derived_selected) - set(recorded_selected))
    extra = sorted(set(recorded_selected) - set(derived_selected))
    if derived_selected == recorded_selected:
        print("governance_subset verify: OK -- %r matches the re-derived selection "
              "(%d anchors)" % (args.selection, len(derived_selected)))
        return 0

    print("governance_subset verify: WRONG SUBSET in %r -- missing=%s extra=%s"
          % (args.selection, missing, extra), file=sys.stderr)
    return 1


# ---------------------------------------------------------------------------
# --determinism-check (C-003, "present on every tool"; runs THIS SAME
# process twice out-of-process and compares, identical timeout/child-
# process discipline to closure/reopen_rate.py's own run_determinism_
# check, generalised here across select/measure (compare body_hash),
# render (compare the written file's own sha256 -- its output is
# Markdown, not a JSON body_hash document), and verify (compare exit
# code + stdout across two runs, since it writes no --out at all).
# ---------------------------------------------------------------------------
def run_determinism_check(cmd, argv, timeout_s=120):
    inner = [a for a in argv if a != "--determinism-check"]
    with tempfile.TemporaryDirectory() as tmp:
        results = []
        for i in (1, 2):
            run_argv = list(inner)
            out_i = None
            if cmd in ("select", "render", "measure"):
                out_i = os.path.join(tmp, "run%d.out" % i)
                if "--out" in run_argv:
                    idx = run_argv.index("--out")
                    run_argv[idx + 1] = out_i
                else:
                    run_argv += ["--out", out_i]
            cmd_line = [sys.executable, os.path.abspath(__file__), cmd] + run_argv
            try:
                proc = subprocess.run(cmd_line, capture_output=True, text=True, timeout=timeout_s)
            except subprocess.TimeoutExpired:
                print("governance_subset %s: determinism-check run %d timed out" % (cmd, i),
                      file=sys.stderr)
                return 4
            if cmd == "verify":
                results.append((proc.returncode, proc.stdout))
                continue
            if proc.returncode != 0 or not out_i or not os.path.exists(out_i):
                sys.stderr.write(proc.stderr)
                print("governance_subset %s: determinism-check run %d rc=%d, no honest "
                      "verdict" % (cmd, i, proc.returncode), file=sys.stderr)
                return 4
            if cmd == "render":
                with open(out_i, "rb") as fh:
                    results.append(hashlib.sha256(fh.read()).hexdigest())
            else:
                with open(out_i, encoding="utf-8") as fh:
                    results.append(json.load(fh).get("body_hash"))
    if results[0] is None or results[0] != results[1]:
        print("governance_subset %s: nondeterministic: run1=%s run2=%s"
              % (cmd, results[0], results[1]), file=sys.stderr)
        return 1
    print("governance_subset %s: deterministic (%s)" % (cmd, results[0]))
    return 0


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def build_arg_parser():
    p = argparse.ArgumentParser(prog="governance_subset.py", description=__doc__.split("\n\n")[0])
    sub = p.add_subparsers(dest="cmd", required=True)

    p_select = sub.add_parser("select")
    p_select.add_argument("--config", required=True)
    p_select.add_argument("--item", required=True)
    p_select.add_argument("--item-record")
    p_select.add_argument("--diff")
    p_select.add_argument("--repo")
    p_select.add_argument("--index")
    p_select.add_argument("--path-class-map")
    p_select.add_argument("--out", required=True)
    p_select.add_argument("--determinism-check", action="store_true")

    p_render = sub.add_parser("render")
    p_render.add_argument("--selection", required=True)
    p_render.add_argument("--index", required=True)
    p_render.add_argument("--repo")
    p_render.add_argument("--out", required=True)
    p_render.add_argument("--determinism-check", action="store_true")

    p_measure = sub.add_parser("measure")
    p_measure.add_argument("--selection", required=True)
    p_measure.add_argument("--usage", required=True)
    p_measure.add_argument("--bound-tok", type=int)
    p_measure.add_argument("--out", required=True)
    p_measure.add_argument("--determinism-check", action="store_true")

    p_verify = sub.add_parser("verify")
    p_verify.add_argument("--selection", required=True)
    p_verify.add_argument("--config")
    p_verify.add_argument("--index")
    p_verify.add_argument("--repo")
    p_verify.add_argument("--determinism-check", action="store_true")

    return p


def main(argv):
    if not argv:
        print("governance_subset.py: a subcommand (select|render|measure|verify) is required",
              file=sys.stderr)
        return 2
    cmd = argv[0]
    args = build_arg_parser().parse_args(argv)

    if getattr(args, "determinism_check", False):
        return run_determinism_check(cmd, argv[1:])

    if cmd == "select":
        return cmd_select(args)
    if cmd == "render":
        return cmd_render(args)
    if cmd == "measure":
        return cmd_measure(args)
    if cmd == "verify":
        return cmd_verify(args)
    print("governance_subset.py: unknown subcommand %r" % cmd, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
