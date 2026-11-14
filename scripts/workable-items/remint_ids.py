#!/usr/bin/env python3
"""remint_ids.py -- land a vehicle's tracker changes onto a target tracker, three-way.

Documentation (section 11.4.18): docs/guides/remint_ids_guide.md. Class inventory behind this
revision: docs/qa/tracker_intake_2026_11_14_v6/class_inventory.md (round 6; the v5 one
is kept beside it).

WHY   Two vehicles that branch from one base both mint ids from the base's maximum, so their ids
      collide when the second lands, and the binary tracker database cannot be merged by git. A
      vehicle also changes items it did not mint (base items). This tool plans a landing from a
      three-way row diff (base B, vehicle V, target T) of every tracker table: it moves the ids the
      vehicle minted to the next free numbers of the target, replays every vehicle change (own items
      and changed base items) through the workable-items engine, and reports a change that both the
      vehicle and the target made as a conflict instead of choosing a side. It never writes a
      tracker database itself (section 11.4.93: the engine is the only writer).

USAGE
  remint_ids.py plan --vehicle-db V --base-db B --target-db T --out PLAN.json [--map-out MAP.tsv]
                     [--prefix CON] [--resolve ID=target|vehicle ...] [--foreign IDS ...]
                     [--repo-root DIR] [--no-fast-forward]
      Read-only. Writes the plan (JSON): the sha256 of the three databases, the id map, every base
      item change, every conflict, every refusal and the engine steps. When the target equals the
      base table for table, the plan is FAST-FORWARD (the vehicle database is the landed database)
      unless --no-fast-forward asks for the replay anyway. With --repo-root, a red or green command
      that runs a file which names a moved id is refused (the file would test the wrong item),
      unless the id is foreign: declared by the item's own Foreign line, by --foreign, or by a
      comment line in the file (`# Foreign ids (...): ...`, also `//` and `--`).
      Exit 0 a plan without conflicts or refusals; 1 conflicts or refusals (the plan is written so
      they can be read; replay refuses it).
  remint_ids.py replay --plan PLAN.json [--apply --engine BIN --db TARGET_COPY]
      Prints the steps (one JSON argv per line, the database as "{DB}"); with --apply runs them on
      TARGET_COPY, from the current directory (the target repository root with the vehicle's files
      in place, because the engine resolves evidence paths from there). Refuses a plan with a
      conflict or a refusal, and a target copy whose sha256 is not the plan's target sha256.
  remint_ids.py verify --plan PLAN.json --vehicle-db V --base-db B --target-db T --db R
                       [--require-segments]
      Read-only oracle, separate from the planner (section 11.4.249): it reads only the plan's map
      and resolutions, recomputes the own set and the base-item changes itself, and compares every
      id token of the landed text with its own expectation (item-wide foreign ids, map, referent
      title). It checks the untouched target rows, every replayed column, the history and the other
      tables. Its control needles run before it reads a database; a needle that fails is BLIND.
  remint_ids.py rewrite --map MAP.tsv [--write --target-db T] [--foreign IDS] [--own IDS] FILE...
      Rewrites moved ids in text files (dry run by default). A file's "Foreign ids" lines declare ids
      of another tracker, which are not rewritten anywhere in that file. With --target-db, an id the
      map moves that the target also holds is refused as ambiguous unless --own or --foreign
      declares it (IDS: comma list, ranges P-a..P-b allowed).
  remint_ids.py refs --map MAP.tsv --repo-root DIR
      Lists every tracked text file that names a moved id, with its class: EVIDENCE (under docs/qa/:
      captured evidence, never rewritten), DATABASE (never rewritten; the plan replays it) or LIVE
      (rewrite it). The mechanical file list of the guide.

RANGES  `P-a..P-b` and `P-a–P-b` (en dash) are rewritten as one token. Every other way of writing
      two ids as a range (spaced dashes, `...`, `…`, em dash, a spaced hyphen, `P-a-P-b`, `to`,
      `through`, `thru`, `till`, `until`, `between P-a and P-b`) is checked by the same rules and its
      ids are then rewritten one by one. A range that holds a moved id is rewritten only when every
      id in it is moved, none is foreign, and the new ids are again ascending and contiguous; a
      reverse range, a short form `P-a..b`, a partly moved or mixed range is refused. Ranges are
      checked by counting, never expanded, so `P-1..P-90000000` costs nothing. Ids are ASCII digits;
      a moved id written with other digits (fullwidth, Arabic-Indic) is refused, never left as is.
MERGE  A base item both sides changed is merged per unit: each update column, each state block
      (its columns and its updated_at/updated_by stamps together) and the lifecycle (status,
      location, obsolete_details). A unit only the vehicle changed lands from the vehicle; a unit
      only the target changed keeps the target's value and text, never rewritten through the map;
      a unit both changed the same way is left as the target has it; a unit both changed in
      different ways, or a lifecycle change on one side with any change on the other, is a
      conflict that --resolve decides (=target keeps the whole target item, =vehicle takes the
      vehicle's value for the conflicting units and keeps the target's other changes). A state
      block whose content both sides changed to the same values, with different stamps, cannot be
      resolved =vehicle: replaying the same content changes nothing and the engine stamps a block
      only when its content changes, so the plan refuses it and names =target. A vehicle that
      removed a base item's obsolete_details row is refused: no engine command removes one.
BODY  body_md is derived, and the steps write it in two ways (round 6, R5-1). A step RE-RENDERS
      it from the engine template, dropping every authored line, when it passes --description or
      closes the item; every other step edits only ENGINE SLOTS (the item's heading, the Status,
      Reproduction, Investigation, Reopened-Details (with its attribution bullets) and
      Obsolete-Details lines, the trailing newline). So --description is passed only when the
      vehicle changed the description, and a re-render on an item whose body the target changed
      outside the slots is a conflict (the re-render would drop the target's text). verify
      compares the body every time: with the vehicle's body when the target left the item and its
      body alone, otherwise with the target's body outside the slots (no re-render) or with the
      vehicle's body outside the slots and the template meta lines (re-render), and checks the
      heading against the landed title and the Status line against the landed status.
DATABASES  Every database is opened read-only by its path (URI-quoted, so `?` and `#` are file name
      characters), and a database with a non-empty -wal sidecar is refused (the sha256 of the main
      file would not describe what sqlite reads).
NOT CARRIED  The vehicle's history rows (the engine writes new ones on replay, M-14), created_at
      (the replay time for own items; the engine's close rewrites it for a base item it closes,
      engine defect CON-339) and last_modified. verify reports these as KNOWN, never as a pass.
EXIT  0 done; 1 a refusal, a conflict or a verify mismatch; 2 usage; 3 BLIND (a database, file or
      plan that cannot be read or does not have the expected shape, a non-UTF-8 file, a failed
      control needle).
EVIDENCE CLASS  gate-logic (section 11.4.289): the tests drive the real engine on fixture copies.
"""
import argparse
import bisect
import hashlib
import json
import os
import re
import sqlite3
import subprocess
import sys
import urllib.parse

PLAN_SCHEMA = "remint_ids.plan/5"
KNOWN_TABLES = {
    "items", "item_history", "sqlite_sequence", "obsolete_details", "operator_block_details",
    "firebase_metadata", "logic_groups", "doc_segments", "test_diary", "repro_gate_exemptions", "meta",
}
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
UPDATE_COLS = ["type", "severity", "title", "description", "created_by", "assigned_to"]
REPRO = ["reproduction_state", "reproduction_surface", "reproduction_evidence", "reproduction_red_cmd",
         "reproduction_green_cmd", "reproduction_env", "reproduction_signature", "reproduction_blocker"]
INV = ["investigation_state", "investigation_root_cause", "investigation_evidence"]
BLOCKS = [("reproduction", REPRO), ("investigation", INV)]
STAMPS = {n: [n + "_updated_at", n + "_updated_by"] for n, _ in BLOCKS}
LIFECYCLE = ["status", "current_location"]
REFUSED_COLS = ["forensic_anchor", "closure_criteria", "composes_with", "destination", "logic_group",
                "parent_atm_id", "session_ref", "closure_date", "round", "commit_ref", "representation"]
TEXT_REWRITE = ["title", "description", "reproduction_red_cmd", "reproduction_green_cmd", "reproduction_env",
                "reproduction_signature", "reproduction_blocker", "investigation_root_cause"]
OTHER_TABLES = ["operator_block_details", "firebase_metadata", "logic_groups", "test_diary", "repro_gate_exemptions"]
CLOSE_STATUS = {"Fixed": "fixed", "Implemented": "implemented", "Completed": "completed", "Obsolete": "obsolete"}
CLOSURE_EVENTS = set(CLOSE_STATUS)
FOREIGN_LINE = re.compile(r"^Foreign ids\b[^:\n]*:(.*)$", re.M)
# inside a script a declaration can only live in a comment: `# Foreign ids (...): ...` (also `//` and `--`)
SCRIPT_FOREIGN_LINE = re.compile(r"^[ \t]*(?:#|//|--)[ \t]*(Foreign ids\b[^:\n]*:.*)$", re.M)
SCRIPT_ARG = re.compile(r"[\w./-]+\.(?:sh|py|bash)\b")


class Refusal(Exception):
    pass


class Blind(Exception):
    pass


def num(iid):
    return int(iid.rsplit("-", 1)[1])


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def ro(path):
    if not os.path.isfile(path):
        raise Blind("database not found: %s" % path)
    wal = path + "-wal"
    if os.path.isfile(wal) and os.path.getsize(wal) > 0:
        raise Refusal("%s has a non-empty -wal sidecar; checkpoint it first (its sha256 would not describe the "
                      "pages sqlite reads)" % path)
    try:
        # the path is quoted: `?` and `#` in a file name are not URI syntax (round 4, R4-9)
        c = sqlite3.connect("file:%s?mode=ro" % urllib.parse.quote(os.path.abspath(path)), uri=True)
        c.row_factory = sqlite3.Row
        c.execute("select count(*) from items").fetchone()
        return c
    except sqlite3.Error as e:
        raise Blind("database unreadable: %s: %s" % (path, e))


def check_schema(c, path):
    tables = {r[0] for r in c.execute("select name from sqlite_master where type='table'")}
    if tables != KNOWN_TABLES:
        raise Blind("%s: tables differ from the known set (no landing rule for them): extra %s, missing %s"
                    % (path, sorted(tables - KNOWN_TABLES), sorted(KNOWN_TABLES - tables)))
    cols = [r[1] for r in c.execute("pragma table_info(items)")]
    if cols != ITEM_COLUMNS:
        raise Blind("%s: items columns differ from the known set: %s" % (path, sorted(set(cols) ^ set(ITEM_COLUMNS))))


def schema_version(c):
    r = c.execute("select value from meta where key='schema_version'").fetchone()
    return r[0] if r else None


def rows_by_id(c):
    out = {}
    for r in c.execute("select * from items"):
        out.setdefault(r["atm_id"], []).append(dict(r))
    return out


def table_rows(c, t):
    return sorted(tuple(r) for r in c.execute("select * from %s" % t))


def history(c):
    return {r["id"]: dict(r) for r in c.execute("select * from item_history")}


def obsolete(c):
    return {r["atm_id"]: dict(r) for r in c.execute("select * from obsolete_details")}


# ---------------------------------------------------------------- producer: text rewriting

class Foreign:
    """Ids of another tracker: single numbers and closed intervals, never expanded."""

    def __init__(self):
        self.nums, self.spans = set(), []

    def add_text(self, text, prefix):
        p = re.escape(prefix)
        for fl in FOREIGN_LINE.finditer(text or ""):
            body = fl.group(1)
            for r in re.finditer(r"(?<![\w-])" + p + r"-([0-9]+)(?:\.\.|–)(?:" + p + r"-)?([0-9]+)\b", body):
                lo, hi = int(r.group(1)), int(r.group(2))
                self.spans.append((min(lo, hi), max(lo, hi)))
            for t in re.finditer(r"(?<![\w-])" + p + r"-([0-9]+)\b", body):
                self.nums.add(int(t.group(1)))

    def add_ids(self, spec, prefix):
        for part in (x.strip() for x in spec.split(",")):
            if not part:
                continue
            m = re.fullmatch(re.escape(prefix) + r"-([0-9]+)(?:\.\.(?:" + re.escape(prefix) + r"-)?([0-9]+))?", part)
            if not m:
                raise Blind("cannot read id list item %r (want %s-N or %s-a..%s-b)" % (part, prefix, prefix, prefix))
            lo = int(m.group(1))
            hi = int(m.group(2)) if m.group(2) else lo
            self.spans.append((min(lo, hi), max(lo, hi)))

    def has(self, n):
        return n in self.nums or any(lo <= n <= hi for lo, hi in self.spans)

    def any_in(self, lo, hi):
        return any(lo <= n <= hi for n in self.nums) or any(not (h < lo or l > hi) for l, h in self.spans)


# Ids are ASCII digits ([0-9]): Python's \d also matches fullwidth and other Unicode digits, and int()
# reads them, so a \d reading would treat `P-５` as `P-5` (round 4, R4-5).
DASHES = "\u2010\u2011\u2012\u2013\u2014\u2015\u2212\u2e3a\u2e3b\ufe58\ufe63\uff0d"


def id_patterns(prefix):
    p = re.escape(prefix)
    rng = re.compile(r"(?<![\w-])(" + p + r"-([0-9]+))(\.\.|–)(" + p + r"-)?([0-9]+)\b(?![-\w])")
    tok = re.compile(r"(?<![\w-])" + p + r"-([0-9]+)\b(?!-)")
    return rng, tok


def loose_patterns(prefix):
    """Every other way to write two ids as a range (round 4, R4-4). Groups as in rng: 1 the first id,
    2 its digits, 3 the connector, 4 the second id's prefix, 5 its digits. `and` is a connector only
    after `between` (a plain `P-a and P-b` is a list)."""
    p = re.escape(prefix)
    tail = r"(" + p + r"-)?([0-9]+)\b(?![-\w])"
    loose = re.compile(r"(?<![\w-])(" + p + r"-([0-9]+))(\s*(?:\.{2,3}|…|[~\u301c" + DASHES + r"])\s*|\s+-{1,2}\s+|-(?="
                       + p + r"-)|\s+(?i:to|through|thru|till|until)\s+)" + tail)
    between = re.compile(r"(?<![\w-])(?i:between)\s+(" + p + r"-([0-9]+))(\s+(?i:and)\s+)" + tail)
    uni = re.compile(r"(?<![\w-])" + p + r"-(\d+)")  # Unicode digits on purpose: finds the non-ASCII ones
    return loose, between, uni


def in_path(line, pos, end):
    """True when line[pos:end] is part of a path: a slash just before or after it, or an extension after it."""
    before = line[pos - 1] if pos > 0 else ""
    after = line[end:end + 2]
    if before == "/" or after[:1] == "/" or re.match(r"\.\w", after):
        return True
    return False


class Rewriter:
    def __init__(self, m, prefix, ambiguous=frozenset()):
        self.m, self.prefix = m, prefix
        self.by_num = {num(k): k for k in m}
        self.own_sorted = sorted(self.by_num)
        self.rng, self.tok = id_patterns(prefix)
        self.loose, self.between, self.uni = loose_patterns(prefix)
        self.ambiguous = ambiguous  # moved ids that need a declaration (rewrite --target-db)

    def moved_in(self, lo, hi, foreign):
        a, b = bisect.bisect_left(self.own_sorted, lo), bisect.bisect_right(self.own_sorted, hi)
        return [n for n in self.own_sorted[a:b] if not foreign.has(n)]

    def text(self, text, foreign, where):
        if not text:
            return text, 0
        count = 0
        out = []
        for line in text.split("\n"):
            if FOREIGN_LINE.match(line):
                out.append(line)
                continue
            self._checks(line, foreign, where)
            parts, last = [], 0
            for r in self.rng.finditer(line):
                chunk, n = self._tokens(line[last:r.start()], foreign, where, line, last)
                parts.append(chunk)
                count += n
                rs, n = self._range(r, foreign, where)
                if n and in_path(line, r.start(), r.end()):
                    raise Refusal("%s: moved range %s is part of a path; a path is never rewritten" % (where, r.group(0)))
                parts.append(rs)
                count += n
                last = r.end()
            chunk, n = self._tokens(line[last:], foreign, where, line, last)
            parts.append(chunk)
            count += n
            out.append("".join(parts))
        return "\n".join(out), count

    def keep(self, text, foreign, where):
        """A vehicle value the landing passes as written (a path, a name, a vocabulary word, a date): it must
        not name an id the map moves, since nothing rewrites it. text() raises the refusal for a moved id in
        a path; any other moved id it would rewrite is refused here (round 5, found by the branch sweep: an
        evidence path naming a moved own id passed the plan and only verify failed)."""
        _, n = self.text(text, foreign, where)
        if n:
            raise Refusal("%s: %r names an id the map moves, in a value that is never rewritten; rename it or "
                          "declare the id foreign" % (where, text))
        return text

    def _checks(self, line, foreign, where):
        """Refusals that do not depend on how the line is rewritten: a moved id in non-ASCII digits, and
        every pair of ids written as a range, read pair by pair with overlap, so the second id of a range
        can start the next one. The tight `..` and en dash forms are checked here too, although text()
        rewrites them as rng tokens: rng.finditer does not overlap, so in `P-1..P-2..P-3` it never sees
        the pair `P-2..P-3` (round 5, found by the branch sweep: the chain was rewritten while its second
        pair was partly moved). _check is idempotent, so a pair checked here and again in _range raises
        the same refusal or none."""
        for u in self.uni.finditer(line):
            d = u.group(1)
            if d.isascii():
                continue
            n = int(d)
            if n in self.by_num and not foreign.has(n):
                raise Refusal("%s: %s writes moved %s with non-ASCII digits" % (where, u.group(0), self.by_num[n]))
        for rx in (self.loose, self.between):
            pos = 0
            while True:
                r = rx.search(line, pos)
                if not r:
                    break
                pos = r.end(3)  # the second id can start the next range
                if r.group(3) == "-":
                    lo, hi = int(r.group(2)), int(r.group(5))
                    if self.moved_in(min(lo, hi), max(lo, hi), foreign):
                        raise Refusal("%s: range %s joins its ids with a hyphen, which is never rewritten; write "
                                      "the range with `..`" % (where, r.group(0)))
                    continue
                self._check(r, foreign, where)

    def _range(self, r, foreign, where):
        moved = self._check(r, foreign, where)
        if not moved:
            return r.group(0), 0
        a = min(int(r.group(2)), int(r.group(5)))
        b = max(int(r.group(2)), int(r.group(5)))
        return "%s%s%s" % (self.m[self.by_num[a]], r.group(3), self.m[self.by_num[b]]), 1

    def _check(self, r, foreign, where):
        """The rules every range obeys; returns the moved ids it holds (empty: none, nothing to do)."""
        lo, hi = int(r.group(2)), int(r.group(5))
        a, b = min(lo, hi), max(lo, hi)
        moved = self.moved_in(a, b, foreign)
        if not moved:
            return moved
        if r.group(4) is None:
            raise Refusal("%s: short-form range %s holds a moved id; write both ends in full" % (where, r.group(0)))
        if lo > hi:
            raise Refusal("%s: reverse range %s holds a moved id" % (where, r.group(0)))
        if foreign.any_in(a, b):
            raise Refusal("%s: range %s mixes foreign and moved ids" % (where, r.group(0)))
        if len(moved) != b - a + 1:
            raise Refusal("%s: range %s is partly moved (%d of %d ids)" % (where, r.group(0), len(moved), b - a + 1))
        for n in moved:
            k = self.by_num[n]
            if k in self.ambiguous:
                raise Refusal("%s: %s in range %s is also a target id; declare it with --own or --foreign" % (where, k, r.group(0)))
        if self.by_num[a] != r.group(1) or self.by_num[b] != "%s-%s" % (self.prefix, r.group(5)):
            raise Refusal("%s: range %s is written with a different zero padding than the moved ids" % (where, r.group(0)))
        new = [num(self.m[self.by_num[n]]) for n in moved]
        if new != list(range(new[0], new[0] + len(new))):
            raise Refusal("%s: range %s maps to ids that are not contiguous" % (where, r.group(0)))
        return moved

    def _tokens(self, s, foreign, where, line, offset):
        count = 0

        def sub(t):
            nonlocal count
            n = int(t.group(1))
            if n not in self.by_num or foreign.has(n):
                return t.group(0)
            k = self.by_num[n]
            if t.group(0) != k:
                raise Refusal("%s: %s names moved %s with a different zero padding" % (where, t.group(0), k))
            if in_path(line, offset + t.start(), offset + t.end()):
                raise Refusal("%s: moved id %s is part of a path; a path is never rewritten" % (where, k))
            if k in self.ambiguous:
                raise Refusal("%s: %s is moved but the target also holds %s; declare it with --own or --foreign" % (where, k, k))
            count += 1
            return self.m[k]

        return self.tok.sub(sub, s), count


def item_foreign(versions, prefix, extra):
    f = Foreign()
    for spec in extra:
        f.add_ids(spec, prefix)
    for row in versions:
        for col in TEXT_REWRITE + ["body_md"]:
            f.add_text(row.get(col) or "", prefix)
    return f


# ---------------------------------------------------------------- planner

def read_map(path):
    try:
        lines = open(path, encoding="utf-8").read().splitlines()
    except (OSError, UnicodeDecodeError) as e:
        raise Blind("map unreadable: %s" % e)
    if not lines or lines[0] != "old\tnew":
        raise Blind("map has no `old<TAB>new` header: %s" % path)
    m = {}
    for n, line in enumerate(lines[1:], 2):
        f = line.split("\t")
        if len(f) != 2 or not re.fullmatch(r"[A-Z]+-[0-9]+", f[0]) or not re.fullmatch(r"[A-Z]+-[0-9]+", f[1]):
            raise Blind("map line %d does not parse: %r" % (n, line))
        if f[0] in m:
            raise Blind("map names %s twice" % f[0])
        m[f[0]] = f[1]
    return check_map(m)


def check_map(m):
    if not m:
        raise Blind("map is empty")
    if len(set(m.values())) != len(m):
        raise Blind("map gives two old ids one new id")
    prefixes = {k.rsplit("-", 1)[0] for k in m} | {v.rsplit("-", 1)[0] for v in m.values()}
    if len(prefixes) != 1:
        raise Blind("map mixes prefixes: %s" % ",".join(sorted(prefixes)))
    return m, prefixes.pop()


def norm(v):
    return "" if v is None else v


def changed(a, b, cols):
    return [c for c in cols if norm(a.get(c)) != norm(b.get(c))]


def status_word(s):
    return norm(s).split(" ")[0]


SLOT_PREFIXES = ("**Status:**", "**Reproduction:**", "**Investigation:**", "**Reopened-Details:**",
                 "**Obsolete-Details:**")
TEMPLATE_PREFIXES = ("**Type:**", "**Severity:**", "**Created-By:**", "**Assigned-To:**", "**Evidence:**")
REOPEN_BULLET = re.compile(r"^- \*\*(?:By|On|Reason|Evidence):\*\*")


def body_lines(body):
    """body_md as lines, with the trailing newline the engine adds to every body it stores."""
    b = norm(body)
    if b and not b.endswith("\n"):
        b += "\n"
    return b.split("\n")


def is_slot(line, iid, template=False):
    """True for a line an engine step writes without re-rendering (an engine slot); with template, also
    the meta lines of the engine's body template, which a re-render fills from the landed columns."""
    if line.startswith("## %s — " % iid) or line.startswith("## %s. " % iid):
        return True
    if line.startswith(SLOT_PREFIXES) or REOPEN_BULLET.match(line):
        return True
    return template and line.startswith(TEMPLATE_PREFIXES)


def unslotted(body, iid, template=False):
    """The lines of body that are not engine slots, in order: the text a slot edit must keep."""
    return [x for x in body_lines(body) if not is_slot(x, iid, template)]


def closure_evidence(rows):
    """The evidence of the latest `close` row (empty reason) among rows; else of the latest closure row."""
    cl = [h for h in rows if h["event_type"] in CLOSURE_EVENTS and norm(h["evidence_path"])]
    plain = [h for h in cl if not norm(h["reason"])]
    pick = (plain or cl)
    return pick[-1]["evidence_path"] if pick else None


def lifecycle_steps(iid, frm, to, v_od, new_hist, rewr, foreign, label, refuse):
    """Steps that move item iid from state frm=(status, location) to the vehicle state."""
    steps = []
    fs, fl = frm
    ts, tl = norm(to["status"]), norm(to["current_location"])
    f_term, t_term = status_word(fs) in CLOSE_STATUS, status_word(ts) in CLOSE_STATUS

    def close():
        """Append the close step; return the status word it closes with, or None after a refusal."""
        ev = closure_evidence(new_hist)
        if not ev:
            refuse("%s: the vehicle closed it but has no new closure history row with evidence to replay" % label)
            return None
        word = status_word(ts) if t_term else None
        if word is None:
            cl = [h for h in new_hist if h["event_type"] in CLOSURE_EVENTS]
            word = cl[-1]["event_type"] if cl else None
        if word not in CLOSE_STATUS:
            refuse("%s: no closure kind to replay" % label)
            return None
        ev = rewr.keep(ev, foreign, "%s closure evidence" % label)
        steps.append(("close", ["close", iid, "--db", "{DB}", "--status=" + CLOSE_STATUS[word], "--evidence=" + ev]))
        return word

    def obs(status):
        """The vehicle's obsolete_details row, written while the item's status is `status`. The engine
        writes the row only on an Obsolete item, so every lifecycle path places it where the item is
        Obsolete (round 4: a reopened own item lost its row because the reopen path never wrote it)."""
        if v_od is None or status is None:
            return
        if status_word(status) != "Obsolete":
            refuse("%s: the vehicle's obsolete_details row cannot be replayed on a %r item (the engine writes it "
                   "only on an Obsolete item)" % (label, status))
            return
        sup = norm(v_od["superseding_item"]) or "none"
        sup, _ = rewr.text(sup, foreign, "%s obsolete_details.superseding_item" % label)
        kept = {c: rewr.keep(norm(v_od[c]), foreign, "%s obsolete_details.%s" % (label, c))
                for c in ("since", "reason", "triple_check_evidence")}
        steps.append(("obsolete-details", ["obsolete-details", iid, "--db", "{DB}", "--since=" + kept["since"],
                                           "--reason=" + kept["reason"], "--superseding=" + sup,
                                           "--evidence=" + kept["triple_check_evidence"]]))

    def reopen():
        ro_rows = [h for h in new_hist if h["event_type"] == "Reopened"]
        if not ro_rows:
            refuse("%s: the vehicle reopened it but has no new Reopened history row" % label)
            return
        h = {c: rewr.keep(norm(ro_rows[-1][c]), foreign, "%s Reopened row %s" % (label, c))
             for c in ("reason", "by", "on_date", "evidence_path")}
        argv = ["reopen", "--id=" + iid, "--db", "{DB}", "--why=" + h["reason"], "--who=" + (h["by"] or "AI"),
                "--when=" + h["on_date"], "--incident=" + h["evidence_path"]]
        if tl == "Fixed":
            argv.append("--location=Fixed")
        steps.append(("reopen", argv))

    if (fs, fl) == (ts, tl) or (t_term and f_term and status_word(fs) == status_word(ts) and fl == tl):
        obs(fs)  # the lifecycle is unchanged; a changed obsolete_details row is still replayed
    elif t_term and not f_term:
        obs(ts if close() else None)
    elif ts == "Reopened" and f_term:
        obs(fs)
        reopen()
    elif ts == "Reopened" and not f_term:
        obs(close())
        reopen()
    elif not t_term and not f_term and fl == tl:
        ts = rewr.keep(ts, foreign, "%s status" % label)
        steps.append(("update-status", ["update", "--id=" + iid, "--db", "{DB}", "--location=" + fl, "--status=" + ts]))
        obs(ts)  # refuses: the engine has no path to an obsolete_details row on an open item
    else:
        refuse("%s: no engine path from %r in %s to %r in %s" % (label, fs, fl, ts, tl))
    return steps


def block_steps(iid, loc, row, cols, rewr, foreign, label, prefix_name):
    state = norm(row[cols[0]])
    by, at = norm(row[prefix_name + "_updated_by"]), norm(row[prefix_name + "_updated_at"])
    argv = ["update", "--id=" + iid, "--db", "{DB}", "--location=" + loc]
    if state in ("", "UNSET"):
        argv.append("--%s=UNSET" % cols[0].replace("_", "-"))
    else:
        for c in cols:
            val = norm(row[c])
            if c in TEXT_REWRITE:
                val, _ = rewr.text(val, foreign, "%s %s" % (label, c))
            else:
                val = rewr.keep(val, foreign, "%s %s" % (label, c))
            argv.append("--%s=%s" % (c.replace("_", "-"), val))
    # the stamp is always passed: the engine stores an empty --states-updated-at as NULL, as the vehicle has it,
    # and an omitted one as the time of the replay (round 5, found by the branch sweep: `if at:` dropped an
    # empty stamp, so the landed block carried the replay's time); the author is the vehicle's, which the
    # engine requires with every state flag (an UNSET block clears it, so the fallback name never lands)
    argv.append("--states-updated-by=" + (rewr.keep(by, foreign, "%s %s_updated_by" % (label, prefix_name)) or "remint_ids.py"))
    argv.append("--states-updated-at=" + rewr.keep(at, foreign, "%s %s_updated_at" % (label, prefix_name)))
    return ("update-" + prefix_name, argv)


def scripts_naming_moved(cmd, repo_root, m, prefix, foreign):
    """Files a red/green command runs that name an id the map moves to another number (M-9 class).

    `foreign` is the item's own foreign set (its Foreign lines and --foreign): the same declarations the
    rewrite honours on the item's text also cover the scripts it runs (round 4)."""
    moving = {k for k, v in m.items() if k != v}
    _, tok = id_patterns(prefix)
    hits = []
    for path in SCRIPT_ARG.findall(cmd or ""):
        full = os.path.join(repo_root, path)
        if not os.path.isfile(full):
            continue
        try:
            text = open(full, encoding="utf-8").read()
        except (OSError, UnicodeDecodeError) as e:
            raise Blind("cannot read %s: %s" % (full, e))
        fo = Foreign()
        fo.add_text(text, prefix)
        fo.add_text("\n".join(x.group(1) for x in SCRIPT_FOREIGN_LINE.finditer(text)), prefix)
        moved = [t.group(0) for t in tok.finditer(text)
                 if t.group(0) in moving and not fo.has(int(t.group(1))) and not foreign.has(int(t.group(1)))]
        if moved:
            hits.append("%s names %s" % (path, ",".join(sorted(set(moved)))))
    return hits


def make_plan(a):
    paths = {"vehicle": a.vehicle_db, "base": a.base_db, "target": a.target_db}
    con = {k: ro(p) for k, p in paths.items()}
    for k, c in con.items():
        check_schema(c, paths[k])
    sv = {k: schema_version(c) for k, c in con.items()}
    if len(set(sv.values())) != 1 or None in sv.values():
        raise Blind("schema_version differs or is missing: %s" % sv)
    V, B, T = (rows_by_id(con[k]) for k in ("vehicle", "base", "target"))
    prefix = a.prefix
    rx = re.compile(re.escape(prefix) + r"-[0-9]+")
    rx_uni = re.compile(re.escape(prefix) + r"-\d+")
    refusals, conflicts, notes, base_changes, merges = [], [], [], [], []
    refuse = refusals.append

    new_ids = sorted(set(V) - set(B))
    for i in new_ids:
        if not rx.fullmatch(i):
            refuse("%s: a new vehicle id with non-ASCII digits" % i if rx_uni.fullmatch(i)
                   else "%s: a new vehicle id outside the %s prefix" % (i, prefix))
    own = sorted((i for i in new_ids if rx.fullmatch(i)), key=num)
    for i in sorted(set(B) - set(V)):
        refuse("%s: the vehicle deleted a base item" % i)

    tables = {k: {t: table_rows(c, t) for t in OTHER_TABLES} for k, c in con.items()}
    hist = {k: history(c) for k, c in con.items()}
    obs = {k: obsolete(c) for k, c in con.items()}
    fast_forward = all(table_rows(con["target"], t) == table_rows(con["base"], t) for t in KNOWN_TABLES)

    for t in OTHER_TABLES:
        if tables["vehicle"][t] != tables["base"][t]:
            refuse("table %s: the vehicle changed it; the landing has no replay rule for it" % t)
    seg_non_item = "select * from doc_segments where kind <> 'item' order by id"
    if [tuple(r) for r in con["vehicle"].execute(seg_non_item)] != [tuple(r) for r in con["base"].execute(seg_non_item)]:
        refuse("doc_segments: the vehicle changed a segment that is not an item segment")
    for hid, h in hist["base"].items():
        if hist["vehicle"].get(hid) != h:
            refuse("item_history row %d (%s): the vehicle rewrote or deleted a base history row" % (hid, h["atm_id"]))

    if fast_forward and not a.no_fast_forward:
        m = {i: i for i in own}
        mode = "FAST-FORWARD"
    else:
        mode = "REPLAY"
        if not own:
            m = {}
        else:
            if not any(rx.fullmatch(i) for i in T):
                raise Blind("the target holds no %s id: the next free number cannot be known" % prefix)
            width = len(own[0].rsplit("-", 1)[1])
            start = max(num(i) for i in T if rx.fullmatch(i)) + 1
            m = {o: "%s-%0*d" % (prefix, width, start + k) for k, o in enumerate(own)}
            stay = set(V) - set(own)
            for old, new in m.items():
                if new in T:
                    refuse("new id %s already exists in the target" % new)
                if new in stay:
                    refuse("new id %s is an item of the vehicle that is not moved" % new)

    resolutions = {}
    for spec in a.resolve:
        mm = re.fullmatch(r"([A-Z]+-[0-9]+)=(target|vehicle)", spec)
        if not mm:
            raise Blind("--resolve %r: want ID=target or ID=vehicle" % spec)
        resolutions[mm.group(1)] = mm.group(2)

    # round 6 (R5-2): only an id that actually moves is the rewriter's business; under FAST-FORWARD (and any
    # identity pair) nothing is rewritten, so a path or a base text naming such an id is not refused
    rewr = Rewriter({o: n for o, n in m.items() if o != n}, prefix)
    steps = []

    def one_row(db, i):
        r = db.get(i, [])
        if len(r) != 1:
            refuse("%s: %d rows (one expected)" % (i, len(r)))
            return None
        return r[0]

    for i in sorted(set(B) & set(V), key=lambda x: (x.rsplit("-", 1)[0], num(x) if rx.fullmatch(x) else 0, x)):
        if V[i] == B[i] and obs["vehicle"].get(i) == obs["base"].get(i):
            continue
        b, v = one_row(B, i), one_row(V, i)
        if b is None or v is None:
            continue
        vb_od, bb_od = obs["vehicle"].get(i), obs["base"].get(i)
        dv = changed(v, b, UPDATE_COLS + REPRO + INV + LIFECYCLE + REFUSED_COLS)
        if vb_od != bb_od:
            dv.append("obsolete_details")
        if bb_od is not None and vb_od is None:
            # round 5: no engine command removes an obsolete_details row, so the removal had no step and the
            # landing kept the row (found while killing the final sweep's check_od survivors)
            refuse("%s: the vehicle removed the obsolete_details row; no engine command removes one" % i)
        stamp_only = [n for n, cols in BLOCKS if not changed(v, b, cols)
                      and changed(v, b, [n + "_updated_at", n + "_updated_by"])]
        for n in stamp_only:
            refuse("%s: only the %s stamp changed; the engine stamps a block only when its content changes" % (i, n))
        if not dv:
            if norm(v["body_md"]) != norm(b["body_md"]):
                refuse("%s: body_md changed with no column change (not replayable through the engine)" % i)
            if norm(v["created_at"]) != norm(b["created_at"]):
                notes.append("%s: created_at differs from the base with no other change; not carried" % i)
            if not stamp_only and norm(v["body_md"]) == norm(b["body_md"]) and norm(v["created_at"]) == norm(b["created_at"]):
                notes.append("%s: only last_modified differs from the base; nothing to replay" % i)
            continue
        for c in dv:
            if c in REFUSED_COLS:
                refuse("%s: the vehicle changed %s, which has no replay rule" % (i, c))
        new_hist = [h for hid, h in sorted(hist["vehicle"].items()) if h["atm_id"] == i and hid not in hist["base"]]
        foreign = item_foreign([v, b], prefix, a.foreign)
        for col in TEXT_REWRITE:
            for t in rewr.tok.finditer(norm(b[col])):
                if int(t.group(1)) in rewr.by_num and not foreign.has(int(t.group(1))):
                    refuse("%s: the base text of %s already names %s, an id the vehicle minted later (ambiguous)" % (i, col, t.group(0)))
        if i not in T:
            conflicts.append("%s: the target deleted the item; the vehicle changed %s" % (i, ",".join(dv)))
            continue
        t = one_row(T, i)
        if t is None:
            continue
        tb_od = obs["target"].get(i)
        dt = changed(t, b, UPDATE_COLS + REPRO + INV + LIFECYCLE + REFUSED_COLS)
        for n, cols in BLOCKS:  # a stamp the target changed alone is still a change of its block (R4-1b)
            if not changed(t, b, cols):
                dt += changed(t, b, STAMPS[n])
        if tb_od != bb_od:
            dt.append("obsolete_details")
        label = "base %s" % i

        def vland(c, v=v):  # v bound at definition: the row of this item, never None here
            """The value the vehicle's change lands as: its text through the map, other columns as they are."""
            if c in TEXT_REWRITE:
                return rewr.text(norm(v[c]), foreign, "%s %s" % (label, c))[0]
            return rewr.keep(norm(v[c]), foreign, "%s %s" % (label, c))

        # per-unit three-way merge (round 4, R4-1): a unit is a column, a state block (its columns and its
        # stamps) or the lifecycle; only a unit the vehicle changed is written, and target text is never
        # run through the map
        clash, same = [], []
        for c in UPDATE_COLS + LIFECYCLE + REFUSED_COLS:
            if c in dv and c in dt:  # vland keeps a non-text column as written (round 5: one rule, no branch)
                (same if vland(c) == norm(t[c]) else clash).append(c)
        if "obsolete_details" in dv and "obsolete_details" in dt:
            (same if vb_od == tb_od else clash).append("obsolete_details")
        v_blocks = [n for n, cols in BLOCKS if changed(v, b, cols)]
        t_blocks = [n for n, cols in BLOCKS if changed(t, b, cols + STAMPS[n])]
        for n, cols in BLOCKS:
            if n in v_blocks and n in t_blocks:
                converged = all(vland(c) == norm(t[c]) for c in cols) and not changed(v, t, STAMPS[n])
                (same if converged else clash).append("the %s block" % n)
        life_v = any(c in dv for c in LIFECYCLE + ["obsolete_details"])
        life_t = any(c in dt for c in LIFECYCLE + ["obsolete_details"])
        res = resolutions.get(i)
        entry = {"id": i, "vehicle_changed": dv, "target_changed": dt, "resolution": res or ""}
        base_changes.append(entry)
        if clash or (dt and life_v) or (dv and life_t):
            why = "both changed %s" % ",".join(clash) if clash else "a lifecycle change on one side and a change on the other"
            if res is None:
                conflicts.append("%s: %s (vehicle %s; target %s); --resolve %s=target or =vehicle decides" % (i, why, ",".join(dv), ",".join(dt), i))
                continue
        elif dt:
            merges.append("%s: vehicle %s, target %s (%s)" % (
                i, ",".join(dv), ",".join(dt), "the same change on both sides: " + ",".join(same) if same else "disjoint columns"))
        if res == "vehicle":
            # a block whose content both sides changed to the same values, with other stamps, cannot land the
            # vehicle's stamps: replaying the same content changes nothing, and the engine stamps a block only
            # when its content changes (found by verify in round 5)
            stuck = [n for n, cols in BLOCKS if "the %s block" % n in clash and all(vland(c) == norm(t[c]) for c in cols)]
            for n in stuck:
                refuse("%s: --resolve vehicle cannot land the %s block: its content is already the target's and only "
                       "the stamps differ, and the engine stamps a block only when its content changes; use "
                       "--resolve %s=target" % (i, n, i))
            if stuck:
                continue
        if res == "target":
            continue
        loc = norm(t["current_location"])
        ucols = [c for c in UPDATE_COLS if c in dv and vland(c) != norm(t[c])]
        isteps = []
        if ucols:
            # round 6 (R5-1): --description re-renders body_md from the template, so it is passed only when
            # the vehicle changed the description; a field-only update keeps the target's body and edits
            # only its engine slots (the heading for --title)
            argv = ["update", "--id=" + i, "--db", "{DB}", "--location=" + loc]
            for c in ucols:
                argv.append("--%s=%s" % (c.replace("_", "-"), vland(c)))
            isteps.append({"item": i, "from": i, "kind": "update", "argv": argv})
        for n, cols in BLOCKS:
            if n in v_blocks and "the %s block" % n not in same:
                k, argv = block_steps(i, loc, v, cols, rewr, foreign, label, n)
                isteps.append({"item": i, "from": i, "kind": k, "argv": argv})
        if life_v:
            for k, argv in lifecycle_steps(i, (norm(t["status"]), loc), v, vb_od if "obsolete_details" in dv else None,
                                           new_hist, rewr, foreign, label, refuse):
                isteps.append({"item": i, "from": i, "kind": k, "argv": argv})
        rerender = [s["kind"] for s in isteps if s["kind"] == "close"
                    or (s["kind"] == "update" and any(x.startswith("--description=") for x in s["argv"]))]
        if rerender and res is None and unslotted(t["body_md"], i) != unslotted(b["body_md"], i):
            if merges and merges[-1].startswith(i + ":"):
                merges.pop()  # not a merge after all
            conflicts.append("%s: the target changed the body outside the engine slots and the vehicle's %s re-renders "
                             "it from the template, which would drop the target's text; --resolve %s=target or =vehicle "
                             "decides" % (i, " and ".join(sorted(set(rerender))), i))
            continue
        steps.extend(isteps)
        if norm(v["created_at"]) != norm(b["created_at"]):
            notes.append("%s: created_at changed in the vehicle (%s -> %s); not carried (no engine command sets it; "
                         "a close rewrites it, engine defect CON-339)" % (i, b["created_at"], v["created_at"]))

    if mode == "REPLAY":
        for old in own:
            v = one_row(V, old)
            if v is None:
                continue
            new = m[old]
            label = "own %s" % old
            foreign = item_foreign([v], prefix, a.foreign)
            rw = {}
            for col in TEXT_REWRITE:
                rw[col], _ = rewr.text(norm(v[col]), foreign, "%s %s" % (label, col))
            kv = {c: rewr.keep(norm(v[c]), foreign, "%s %s" % (label, c))
                  for c in ("type", "severity", "created_by", "assigned_to")}
            argv = ["add", kv["type"], kv["severity"], "--db", "{DB}", "--id=" + new,
                    "--title=" + rw["title"], "--description=" + rw["description"]]
            if kv["created_by"]:
                argv.append("--created-by=" + kv["created_by"])
            if kv["assigned_to"]:
                argv.append("--assigned-to=" + kv["assigned_to"])
            steps.append({"item": new, "from": old, "kind": "add", "argv": argv})
            for n, cols in BLOCKS:
                if norm(v[cols[0]]) not in ("", "UNSET"):
                    k, argv = block_steps(new, "Issues", v, cols, rewr, foreign, label, n)
                    steps.append({"item": new, "from": old, "kind": k, "argv": argv})
            for c in REFUSED_COLS:
                if norm(v[c]) and c != "representation":
                    refuse("%s: %s is set (%r), which add cannot carry" % (old, c, v[c]))
            if norm(v["representation"]) not in ("", "section"):
                refuse("%s: representation %r cannot be replayed" % (old, v["representation"]))
            new_hist = [h for hid, h in sorted(hist["vehicle"].items()) if h["atm_id"] == old]
            for k, argv in lifecycle_steps(new, ("Queued", "Issues"), v, obs["vehicle"].get(old), new_hist, rewr,
                                           foreign, label, refuse):
                steps.append({"item": new, "from": old, "kind": k, "argv": argv})
    if a.repo_root and mode == "REPLAY":
        for i in sorted(V):
            for row in V[i]:
                foreign = item_foreign([row], prefix, a.foreign)
                for col in ("reproduction_red_cmd", "reproduction_green_cmd"):
                    for hit in scripts_naming_moved(row[col], a.repo_root, m, prefix, foreign):
                        refuse("%s %s runs %s: after the re-mint the script would test another item" % (i, col, hit))
    plan = {
        "schema": PLAN_SCHEMA, "prefix": prefix, "mode": mode,
        "sha256": {k: sha256_file(p) for k, p in paths.items()},
        "map": [[o, m[o]] for o in sorted(m, key=num)],
        "resolutions": resolutions, "foreign_extra": list(a.foreign), "base_changes": base_changes, "merges": merges,
        "conflicts": conflicts, "refusals": refusals, "notes": notes,
        "steps": steps if mode == "REPLAY" else [],
    }
    return plan


def cmd_plan(a):
    try:
        plan = make_plan(a)
    except Refusal as e:
        # round 6 (R5-2): a refusal raised while the plan is made (the rewriter's, mostly) still writes a plan,
        # as the usage text says, so it can be read; it holds that one refusal and no step, and replay and
        # verify refuse it
        paths = {"vehicle": a.vehicle_db, "base": a.base_db, "target": a.target_db}
        plan = {"schema": PLAN_SCHEMA, "prefix": a.prefix, "mode": "REFUSED",
                "sha256": {k: sha256_file(p) for k, p in paths.items()}, "map": [], "resolutions": {},
                "foreign_extra": list(a.foreign), "base_changes": [], "merges": [], "conflicts": [],
                "refusals": [str(e)], "notes": ["the plan stopped at this refusal; later items were not read"],
                "steps": []}
    with open(a.out, "w", encoding="utf-8") as h:
        json.dump(plan, h, ensure_ascii=False, indent=1, sort_keys=True)
        h.write("\n")
    if a.map_out:
        with open(a.map_out, "w", encoding="utf-8") as h:
            h.write("old\tnew\n" + "".join("%s\t%s\n" % (o, n) for o, n in plan["map"]))
    for c in plan["base_changes"]:
        print("BASE-CHANGE %s vehicle=%s target=%s%s" % (c["id"], ",".join(c["vehicle_changed"]),
                                                       ",".join(c["target_changed"]) or "-",
                                                       " resolved=" + c["resolution"] if c["resolution"] else ""))
    for x in plan["merges"]:
        print("MERGE " + x)
    for x in plan["notes"]:
        print("NOTE " + x)
    for x in plan["conflicts"]:
        print("CONFLICT " + x)
    for x in plan["refusals"]:
        print("REFUSED " + x)
    mm = plan["map"]
    print("RESULT: %s mode=%s own=%d base_changes=%d steps=%d conflicts=%d refusals=%d first=%s last=%s" % (
        "PLAN" if not plan["conflicts"] and not plan["refusals"] else "NOT-LANDABLE", plan["mode"], len(mm),
        len(plan["base_changes"]), len(plan["steps"]), len(plan["conflicts"]), len(plan["refusals"]),
        mm[0][1] if mm else "-", mm[-1][1] if mm else "-"))
    return 0 if not plan["conflicts"] and not plan["refusals"] else 1


def load_plan(path):
    try:
        plan = json.load(open(path, encoding="utf-8"))
    except (OSError, ValueError) as e:
        raise Blind("plan unreadable: %s" % e)
    if not isinstance(plan, dict) or plan.get("schema") != PLAN_SCHEMA:
        raise Blind("plan has no %s schema: %s" % (PLAN_SCHEMA, path))
    for k in ("sha256", "map", "steps", "conflicts", "refusals", "resolutions", "mode", "prefix"):
        if k not in plan:
            raise Blind("plan lacks %r" % k)
    return plan


def cmd_replay(a):
    plan = load_plan(a.plan)
    if plan["conflicts"] or plan["refusals"]:
        raise Refusal("the plan has %d conflict(s) and %d refusal(s); it cannot be replayed" % (len(plan["conflicts"]), len(plan["refusals"])))
    if plan["mode"] != "REPLAY":
        raise Refusal("the plan is %s: copy the vehicle database, there is nothing to replay" % plan["mode"])
    steps = plan["steps"]
    if not a.apply:
        for p in steps:
            print(json.dumps(p["argv"], ensure_ascii=False))
        print("RESULT: DRY-RUN steps=%d" % len(steps))
        return 0
    if not a.engine or not a.db:
        print("remint_ids: --apply needs --engine and --db", file=sys.stderr)
        return 2
    if not os.path.isfile(a.db):
        raise Blind("target copy not found: %s" % a.db)
    wal = a.db + "-wal"
    if os.path.isfile(wal) and os.path.getsize(wal) > 0:
        raise Refusal("%s has a non-empty -wal sidecar; checkpoint it before the replay (the sha256 check reads the main file)" % a.db)
    got = sha256_file(a.db)
    if got != plan["sha256"]["target"]:
        raise Refusal("the target copy's sha256 %s is not the plan's target %s: re-plan against this target" % (got[:12], plan["sha256"]["target"][:12]))
    for k, p in enumerate(steps, 1):
        argv = [a.engine] + [x.replace("{DB}", a.db) for x in p["argv"]]
        r = subprocess.run(argv, capture_output=True, text=True)
        print("step %d %s %s rc=%d" % (k, p["kind"], p["item"], r.returncode))
        if r.returncode != 0:
            sys.stderr.write(r.stdout[-600:] + r.stderr[-600:])
            print("RESULT: STOPPED at step %d of %d (the target copy is partly replayed: discard it)" % (k, len(steps)))
            return 1
    print("RESULT: APPLIED steps=%d items=%d" % (len(steps), len(plan["map"])))
    return 0


# ---------------------------------------------------------------- verify: an independent oracle

def v_foreign_numbers(texts, prefix, extra_specs):
    """Separate reading of the Foreign ids declarations: (set of numbers, list of (lo, hi))."""
    nums, spans = set(), []
    idp = re.compile(re.escape(prefix) + r"-([0-9]+)")
    for text in texts:
        for line in (text or "").split("\n"):
            if not line.startswith("Foreign ids"):
                continue
            body = line.split(":", 1)[1] if ":" in line else ""
            pos = 0
            while True:
                mm = idp.search(body, pos)
                if not mm:
                    break
                lo = int(mm.group(1))
                rest = body[mm.end():]
                sep = re.match(r"(\.\.|–)(" + re.escape(prefix) + r"-)?([0-9]+)", rest)
                if sep:
                    hi = int(sep.group(3))
                    spans.append((min(lo, hi), max(lo, hi)))
                    pos = mm.end() + sep.end()
                else:
                    nums.add(lo)
                    pos = mm.end()
    for spec in extra_specs:
        for part in spec.split(","):
            part = part.strip()
            if part:
                ends = [int(x) for x in re.findall(r"[0-9]+", part)]
                spans.append((min(ends), max(ends)))
    return nums, spans


def v_is_foreign(n, fset):
    nums, spans = fset
    return n in nums or any(lo <= n <= hi for lo, hi in spans)


def v_split(text, prefix):
    """Split text into (skeleton pieces, id tokens). A token is a single id or a range."""
    p = re.escape(prefix)
    pat = re.compile(r"(?<![\w-])(" + p + r"-[0-9]+(?:(?:\.\.|–)(?:" + p + r"-)?[0-9]+)?)(?![-\w])")
    pieces = pat.split(text or "")
    return pieces[0::2], pieces[1::2]


def v_expect(token, m, fset, prefix):
    ends = re.findall(r"[0-9]+", token)
    if len(ends) == 1:
        n = int(ends[0])
        if v_is_foreign(n, fset) or token not in m:
            return token
        return m[token]
    lo, hi = int(ends[0]), int(ends[1])
    sep = ".." if ".." in token else "–"
    own_in = [k for k in m if lo <= num(k) <= hi and not v_is_foreign(num(k), fset)]
    if not own_in:
        return token
    first, last = token.split(sep)[0], "%s-%s" % (prefix, token.split(sep)[1].rsplit("-", 1)[-1])
    return "%s%s%s" % (m.get(first, first), sep, m.get(last, last))


V_DASH = "\u2010-\u2015\u2212\u2e3a\u2e3b\ufe58\ufe63\uff0d~\u301c"


def v_text_rules(text, m, fset, prefix):
    """verify's own reading of the rules a landed text obeys, written apart from the Rewriter (R4-4, R4-5):
    a moved id in non-ASCII digits, and any pair of ids written as a range (any connector) that holds a
    moved id, cannot land. A planner that let one through is caught here."""
    p = re.escape(prefix)
    moved = {num(k): k for k in m}
    for u in re.finditer(r"(?<![\w-])" + p + r"-(\d+)", text):
        if not u.group(1).isascii() and int(u.group(1)) in moved and not v_is_foreign(int(u.group(1)), fset):
            return "id %s is written with non-ASCII digits" % u.group(0)
    pat = re.compile(r"(?<![\w-])((?i:between)\s+)?" + p + r"-([0-9]+)(\s*(?:\.\.\.?|…|[" + V_DASH + r"])\s*"
                     r"|\s+--?\s+|-(?=" + p + r"-)|\s+(?i:to|through|thru|till|until|and)\s+)(" + p + r"-)?([0-9]+)(?![\w-])")
    pos = 0
    while True:
        r = pat.search(text, pos)
        if not r:
            return None
        pos = r.end(3)
        conn = r.group(3).strip().lower()
        if conn == "and" and not r.group(1):
            continue  # a list, not a range
        lo, hi = int(r.group(2)), int(r.group(5))
        a, b = min(lo, hi), max(lo, hi)
        inside = [n for n in sorted(moved) if a <= n <= b and not v_is_foreign(n, fset)]
        if not inside:
            continue
        nums, spans = fset
        new = sorted(num(m[moved[n]]) for n in inside)
        if r.group(3) == "-":
            return "range %r joins ids with a hyphen" % r.group(0)
        if r.group(4) is None:
            return "range %r is a short form" % r.group(0)
        if lo > hi:
            return "range %r is reverse" % r.group(0)
        if any(a <= n <= b for n in nums) or any(not (h < a or l > b) for l, h in spans):
            return "range %r mixes foreign and moved ids" % r.group(0)
        if len(inside) != b - a + 1:
            return "range %r is partly moved" % r.group(0)
        if new != list(range(new[0], new[0] + len(new))):
            return "range %r maps to ids that are not contiguous" % r.group(0)


def v_compare(want_text, got_text, m, fset, prefix):
    """None when got_text is want_text with exactly the expected id rewrites; else a reason."""
    rule = v_text_rules(want_text or "", m, fset, prefix)
    if rule:
        return rule
    sk_w, tk_w = v_split(want_text, prefix)
    sk_g, tk_g = v_split(got_text, prefix)
    if sk_w != sk_g:
        for k, (x, y) in enumerate(zip(sk_w, sk_g)):
            if x != y:
                return "text differs outside the ids near %r" % (x[:40],)
        return "text differs outside the ids (piece count %d vs %d)" % (len(sk_w), len(sk_g))
    if len(tk_w) != len(tk_g):
        return "id count differs"
    for x, y in zip(tk_w, tk_g):
        e = v_expect(x, m, fset, prefix)
        if y != e:
            return "id %s landed as %s, expected %s" % (x, y, e)
    return None


def verify_needles():
    m = {"P-5": "P-21", "P-6": "P-22", "P-7": "P-23"}
    f = v_foreign_numbers(["Foreign ids (other tracker): P-6"], "P", [])
    cases = [
        ("P-5 and P-6", "P-21 and P-6", f, True),        # P-6 foreign stays
        ("P-5 and P-6", "P-21 and P-22", f, False),      # foreign re-pointed: must be caught (R3-2 needle)
        ("see P-5..P-7", "see P-21..P-23", ({0}, []), True),
        ("see P-5..P-7", "see P-21..P-7", ({0}, []), False),
        ("P-5 x", "P-21 y", ({0}, []), False),           # skeleton change
        ("no ids", "no ids", ({0}, []), True),
        ("see P-4 to P-6", "see P-4 to P-22", ({0}, []), False),   # loose partly moved range (R4-4)
        ("see P-4..P-6", "see P-4..P-22", ({0}, []), False),       # tight partly moved range
        ("see P-5 to P-7", "see P-21 to P-23", ({0}, []), True),   # a loose range, every id moved
        ("see P-4 and P-6", "see P-4 and P-22", ({0}, []), True),  # a list, not a range
        ("see P-\uff15", "see P-\uff15", ({0}, []), False),        # a moved id in fullwidth digits (R4-5)
        ("see P-5-P-6", "see P-5-P-6", ({0}, []), False),          # moved ids joined by a hyphen (round 5)
        ("see between P-4 and P-6", "see between P-4 and P-22", ({0}, []), False),  # `between ... and` is a range
        ("see P-5 to 7", "see P-21 to 7", ({0}, []), False),       # a short-form range of moved ids
        ("see P-7 to P-5", "see P-23 to P-21", ({0}, []), False),  # a reverse range of moved ids
    ]
    m2 = {"P-5": "P-21", "P-6": "P-30"}
    cases2 = [("see P-5 to P-6", "see P-21 to P-30", ({0}, []), False)]  # moved ids that land apart
    for mm, cs in ((m, cases), (m2, cases2)):
        for want, got, fset, ok in cs:
            if (v_compare(want, got, mm, fset, "P") is None) != ok:
                return "needle %r -> %r expected %s" % (want, got, "match" if ok else "mismatch")
    return None


# verify's partition of the item columns into landing units; a column outside it would go uncompared
V_UNITS = (["atm_id"] + UPDATE_COLS + REFUSED_COLS + LIFECYCLE + [c for _, cols in BLOCKS for c in cols]
           + [c for n, _ in BLOCKS for c in STAMPS[n]] + ["body_md", "created_at", "last_modified"])


def cmd_verify(a):
    needle = verify_needles()
    if needle:
        raise Blind("verify control needle failed: %s" % needle)
    if sorted(V_UNITS) != sorted(ITEM_COLUMNS) or len(set(V_UNITS)) != len(V_UNITS):
        raise Blind("verify's landing units do not partition the item columns: %s" % sorted(set(V_UNITS) ^ set(ITEM_COLUMNS)))
    plan = load_plan(a.plan)
    if plan["conflicts"] or plan["refusals"]:
        raise Refusal("the plan has %d conflict(s) and %d refusal(s): it was never landable, so there is no landing to verify"
                      % (len(plan["conflicts"]), len(plan["refusals"])))
    for k, p in (("vehicle", a.vehicle_db), ("base", a.base_db), ("target", a.target_db)):
        if not os.path.isfile(p) or sha256_file(p) != plan["sha256"][k]:
            raise Refusal("the %s database is not the one the plan was made from" % k)
    m = {}
    for pair in plan["map"]:
        if not (isinstance(pair, list) and len(pair) == 2):
            raise Blind("plan map entry does not parse: %r" % (pair,))
        m[pair[0]] = pair[1]
    prefix = plan["prefix"]
    if m:
        m, mp = check_map(m)
        if mp != prefix:
            raise Blind("plan map prefix %s is not the plan prefix %s" % (mp, prefix))
    res = plan["resolutions"]
    cv, cb, ct, cr = ro(a.vehicle_db), ro(a.base_db), ro(a.target_db), ro(a.db)
    V, B, T, R = rows_by_id(cv), rows_by_id(cb), rows_by_id(ct), rows_by_id(cr)
    HV, HT, HR, HB = history(cv), history(ct), history(cr), history(cb)
    OV, OB, OT, OR = obsolete(cv), obsolete(cb), obsolete(ct), obsolete(cr)
    bad, known = [], []
    idrx = re.compile(re.escape(prefix) + r"-[0-9]+")
    own = sorted((i for i in set(V) - set(B) if idrx.fullmatch(i)), key=num)
    for i in sorted(set(V) - set(B)):
        if not idrx.fullmatch(i):
            bad.append("%s: a new vehicle id that is not %s-<ASCII digits>; the planner refuses it" % (i, prefix))
    if sorted(m) != own:
        bad.append("the plan's map keys are not the own set the vehicle and base give (%d vs %d)" % (len(m), len(own)))
    if plan["mode"] == "FAST-FORWARD":
        if set(R) != set(V):
            bad.append("FAST-FORWARD: the landed ids are not the vehicle ids")
        for i in sorted(set(R) & set(V)):
            if R[i] != V[i]:
                bad.append("FAST-FORWARD: %s differs from the vehicle" % i)
        for t in OTHER_TABLES + ["obsolete_details", "item_history"]:
            if table_rows(cr, t) != table_rows(cv, t):
                bad.append("FAST-FORWARD: table %s differs from the vehicle" % t)
        return report(bad, known, len(V), "FAST-FORWARD")
    want_ids = set(T) | set(m.values())
    if set(R) != want_ids:
        bad.append("landed ids: missing %s, extra %s" % (sorted(want_ids - set(R))[:5], sorted(set(R) - want_ids)[:5]))
    inv = {new: old for old, new in m.items()}

    def fset_for(rows):
        return v_foreign_numbers([norm(r.get(c)) for r in rows for c in TEXT_REWRITE + ["body_md"]], prefix,
                                 plan.get("foreign_extra") or [])

    def same_text(i, col, want, got, fset):
        why = v_compare(norm(want), norm(got), m, fset, prefix)
        if why:
            bad.append("%s %s: %s" % (i, col, why))
            return
        # referent identity: every rewritten id must name the same item it named in the vehicle
        _, tw = v_split(norm(want), prefix)
        _, tg = v_split(norm(got), prefix)
        for x, y in zip(tw, tg):
            if x != y and "." not in x and "–" not in x:
                vr, rr = V.get(x), R.get(y)
                if not vr or not rr or v_split(norm(vr[0]["title"]), prefix)[0] != v_split(norm(rr[0]["title"]), prefix)[0] \
                        or vr[0]["type"] != rr[0]["type"] or norm(vr[0]["created_by"]) != norm(rr[0]["created_by"]):
                    bad.append("%s %s: %s now names %s, which is not the item %s named in the vehicle" % (i, col, x, y, x))

    def compare_row(i, want, got, fset, cols_text, cols_exact):
        for c in cols_text:
            same_text(i, c, want[c], got[c], fset)
        for c in cols_exact:
            if norm(want[c]) != norm(got[c]):
                bad.append("%s %s: landed %r, expected %r" % (i, c, got[c], want[c]))

    exact_all = [c for c in ITEM_COLUMNS if c not in TEXT_REWRITE + ["body_md", "atm_id", "created_at", "last_modified"]]
    replayed = set()
    for i in sorted(set(B) & set(V)):
        vb_same = V[i] == B[i] and OV.get(i) == OB.get(i)
        if vb_same:
            continue
        if len(V[i]) != 1 or len(B[i]) != 1:
            bad.append("%s: not one row in vehicle or base" % i)
            continue
        v, b = V[i][0], B[i][0]
        dv = [c for c in UPDATE_COLS + REPRO + INV + LIFECYCLE + REFUSED_COLS if norm(v[c]) != norm(b[c])]
        od_changed = OV.get(i) != OB.get(i)
        if not dv and not od_changed:
            continue
        if res.get(i) == "target" or i not in T:
            continue
        replayed.add(i)
        if i not in R or len(R[i]) != 1:
            bad.append("%s: not one landed row" % i)
            continue
        t, r = T[i][0], R[i][0]
        fset = fset_for([v, b])
        rv = res.get(i) == "vehicle"
        t_od = OT.get(i) != OB.get(i)
        tch = {c for c in V_UNITS if c not in ("atm_id", "body_md", "created_at", "last_modified") and norm(t[c]) != norm(b[c])}

        def same_change(c):
            if c in TEXT_REWRITE:
                return v_compare(norm(v[c]), norm(t[c]), m, fset, prefix) is None
            return norm(v[c]) == norm(t[c])

        def land(c, side, why_target):
            if side == "vehicle":
                if c in TEXT_REWRITE:
                    same_text(i, c, v[c], r[c], fset)
                elif norm(v[c]) != norm(r[c]):
                    bad.append("%s %s: landed %r, vehicle %r" % (i, c, r[c], v[c]))
            elif norm(t[c]) != norm(r[c]):
                bad.append("%s %s: landed %r, target %r (%s)" % (i, c, r[c], t[c], why_target))

        # each unit lands from one side: the vehicle when only it changed the unit (or --resolve vehicle
        # decided a conflict), the target otherwise; an unresolved conflict is a mismatch (R4-1, R4-2)
        for c in UPDATE_COLS + REFUSED_COLS:
            if c not in dv:
                land(c, "target", "a column the vehicle did not change")
            elif c in tch and same_change(c):
                land(c, "target", "both sides made the same change")
            elif c in tch and not rv:
                bad.append("%s: both changed %s, and the plan has no --resolve for it" % (i, c))
            else:
                land(c, "vehicle", "")
        for n, cols in BLOCKS:
            unit = cols + STAMPS[n]
            v_ch, t_ch = any(c in dv for c in cols), any(c in tch for c in unit)
            if not v_ch:
                for c in unit:
                    land(c, "target", "a block the vehicle did not change")
            elif t_ch and all(same_change(c) for c in cols) and all(norm(v[c]) == norm(t[c]) for c in STAMPS[n]):
                for c in unit:
                    land(c, "target", "both sides made the same change")
            elif t_ch and not rv:
                bad.append("%s: both changed the %s block, and the plan has no --resolve for it" % (i, n))
            else:
                for c in unit:
                    land(c, "vehicle", "")
        life_v = any(c in dv for c in LIFECYCLE) or od_changed
        life_t = any(c in tch for c in LIFECYCLE) or t_od
        if not rv and ((life_v and (tch or t_od)) or (life_t and (dv or od_changed))):
            bad.append("%s: a lifecycle change on one side and a change on the other, and the plan has no --resolve for it" % i)
        for c in LIFECYCLE:
            land(c, "vehicle" if life_v else "target", "a lifecycle the vehicle did not change")
        if not od_changed and OR.get(i) != OT.get(i):
            bad.append("%s obsolete_details: differs from the target, and the vehicle did not change it" % i)
        tdiff = sorted(tch) + (["obsolete_details"] if t_od else [])
        check_body(i, v, b, t, r, tdiff, rv, fset, plan["steps"], same_text, bad)
        if od_changed:
            check_od(i, OV.get(i), OR.get(i), m, fset, prefix, bad)
        if norm(r["created_at"]) != norm(t["created_at"]):
            closed = [h for h in HR.values() if h["atm_id"] == i and h["id"] not in HT and h["event_type"] in CLOSURE_EVENTS]
            (known if closed else bad).append("%s created_at: landed %s, target %s%s" % (
                i, r["created_at"], t["created_at"], " (KNOWN engine defect CON-339: close rewrites it)" if closed else ""))
        check_history(i, i, HV, HB, HT, HR, bad, known, own_item=False)

    for i in sorted(set(T)):
        if i in replayed:
            continue
        if R.get(i) != T[i]:
            bad.append("%s: an item the landing must not touch differs from the target" % i)
        if OR.get(i) != OT.get(i):
            bad.append("%s: obsolete_details differs from the target on an untouched item" % i)

    for old in own:
        new = m.get(old)
        if new is None or new not in R or len(R[new]) != 1 or len(V[old]) != 1:
            bad.append("%s -> %s: not one landed row" % (old, new))
            continue
        v, r = V[old][0], R[new][0]
        fset = fset_for([v])
        cols_exact = exact_all[:]
        compare_row(new, v, r, fset, TEXT_REWRITE, cols_exact)
        same_text(new, "body_md", v["body_md"], r["body_md"], fset)
        if norm(r["created_at"]) != norm(v["created_at"]):
            known.append("%s created_at: replay time %s (vehicle %s), not carried" % (new, r["created_at"], v["created_at"]))
        if OV.get(old) is not None or OR.get(new) is not None:
            check_od(new, OV.get(old), OR.get(new), m, fset, prefix, bad)
        check_history(old, new, HV, HB, HT, HR, bad, known, own_item=True)

    for hid, h in HT.items():
        if HR.get(hid) != h:
            bad.append("item_history row %d of the target changed or vanished" % hid)
    for t in OTHER_TABLES:
        if table_rows(cr, t) != table_rows(ct, t):
            bad.append("table %s differs from the target" % t)
    if a.require_segments:
        segs = {x[0] for x in cr.execute("select atm_id from doc_segments")}
        for i in sorted(replayed | set(m.values())):
            if i not in segs:
                bad.append("%s: not in doc_segments (export not run?)" % i)
    if not [i for i in T if i not in replayed]:
        raise Blind("no untouched target item to compare (the control comparison saw nothing)")
    return report(bad, known, len(m) + len(replayed), "REPLAY")


def check_body(i, v, b, t, r, tdiff, rv, fset, steps, same_text, bad):
    """body_md of a replayed base item, never KNOWN (round 6, R5-1). The oracle reads from the plan only which
    steps of the item re-render the body (a close, an update with --description); everything else it derives
    from the four databases. A target that left the item and its body alone: the landed body is the vehicle's.
    No re-render: the landed body is the target's outside the engine slots (target text is never rewritten).
    A re-render: the landed body is the vehicle's outside the slots and the template meta lines, unless the
    target changed the body outside the slots (then the target's text was lost, unless --resolve vehicle chose
    that). In every case the heading names the landed title and the Status line the landed status."""
    rerender = any(s.get("item") == i and (s.get("kind") == "close" or (s.get("kind") == "update" and any(
        str(x).startswith("--description=") for x in s.get("argv", [])))) for s in steps)
    t_body = unslotted(t["body_md"], i) != unslotted(b["body_md"], i)
    if not tdiff and norm(t["body_md"]) == norm(b["body_md"]):
        same_text(i, "body_md", v["body_md"], r["body_md"], fset)
    elif not rerender:
        if unslotted(r["body_md"], i) != unslotted(t["body_md"], i):
            bad.append("%s body_md: the target's text outside the engine slots is not kept" % i)
    else:
        if t_body and not rv:
            bad.append("%s body_md: a re-render replaced a body the target changed outside the engine slots" % i)
        same_text(i, "body_md", "\n".join(unslotted(v["body_md"], i, True)), "\n".join(unslotted(r["body_md"], i, True)), fset)
    lines = body_lines(r["body_md"])
    heads = [x for x in lines if x.startswith("## %s — " % i) or x.startswith("## %s. " % i)]
    if heads and heads[0] not in ("## %s — %s" % (i, norm(r["title"])), "## %s. %s" % (i, norm(r["title"]))):
        bad.append("%s body_md: the heading does not name the landed title" % i)
    if any(x.startswith("**Status:**") for x in body_lines(t["body_md"]) + body_lines(v["body_md"])) \
            and "**Status:** " + norm(r["status"]) not in lines:
        bad.append("%s body_md: no Status line names the landed status %r" % (i, norm(r["status"])))


def check_od(i, want, got, m, fset, prefix, bad):
    if (want is None) != (got is None):
        bad.append("%s obsolete_details: present in %s only" % (i, "the vehicle" if want else "the landed database"))
        return
    if want is None:
        return
    for c in ("since", "reason", "triple_check_evidence"):
        if norm(want[c]) != norm(got[c]):
            bad.append("%s obsolete_details.%s: landed %r, vehicle %r" % (i, c, got[c], want[c]))
    why = v_compare(norm(want["superseding_item"]), norm(got["superseding_item"]), m, fset, prefix)
    if why:
        bad.append("%s obsolete_details.superseding_item: %s" % (i, why))


def check_history(old, new, HV, HB, HT, HR, bad, known, own_item):
    v_new = [h for hid, h in sorted(HV.items()) if h["atm_id"] == old and hid not in HB]
    r_new = [h for hid, h in sorted(HR.items()) if h["atm_id"] == new and hid not in HT]
    if own_item and not any(h["event_type"] == "Opened" for h in r_new):
        bad.append("%s: no Opened history row" % new)
    v_ev = {norm(h["evidence_path"]) for h in v_new if h["event_type"] in CLOSURE_EVENTS and norm(h["evidence_path"])}
    r_cl = [h for h in r_new if h["event_type"] in CLOSURE_EVENTS]
    for h in r_cl:
        if norm(h["evidence_path"]) not in v_ev:
            bad.append("%s: landed closure row cites %r, which no vehicle closure row of %s cites" % (new, h["evidence_path"], old))
    v_last = {}
    for h in v_new:
        if h["event_type"] in CLOSURE_EVENTS | {"Reopened"}:
            v_last = h
    if v_last and v_last["event_type"] == "Reopened":
        r_ro = [h for h in r_new if h["event_type"] == "Reopened"]
        key = ("by", "on_date", "reason", "evidence_path")
        if not r_ro or tuple(norm(r_ro[-1][k]) for k in key) != tuple(norm(v_last[k]) for k in key):
            bad.append("%s: the last Reopened row does not match the vehicle's" % new)
    elif v_last and not r_cl:
        bad.append("%s: the vehicle closed %s but the landed history has no closure row" % (new, old))
    life_v = sum(1 for h in v_new if h["event_type"] in CLOSURE_EVENTS | {"Reopened"})
    life_r = sum(1 for h in r_new if h["event_type"] in CLOSURE_EVENTS | {"Reopened"})
    if life_v != life_r:
        known.append("%s: lifecycle history rows vehicle %d, landed %d (history is not carried; M-14)" % (new, life_v, life_r))


def report(bad, known, n, mode):
    for k in known:
        print("KNOWN " + k)
    for b in bad:
        print("MISMATCH " + b)
    print("RESULT: %s mode=%s items=%d mismatches=%d known=%d" % ("PASS" if not bad else "FAIL", mode, n, len(bad), len(known)))
    return 1 if bad else 0


# ---------------------------------------------------------------- text files

def read_text_file(f):
    if f.endswith(".db") or f.endswith(".bundle"):
        raise Refusal("refusing a database or bundle file: %s" % f)
    try:
        raw = open(f, "rb").read()
    except OSError as e:
        raise Blind("file unreadable: %s" % e)
    if b"\0" in raw:
        raise Refusal("refusing a binary file: %s" % f)
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError as e:
        raise Blind("not UTF-8: %s: %s" % (f, e))


def cmd_rewrite(a):
    m, prefix = read_map(a.map)
    if a.write and not a.target_db:
        print("remint_ids: --write needs --target-db (to find the ids the target also holds)", file=sys.stderr)
        return 2
    declared = Foreign()
    for spec in a.own + a.foreign:
        declared.add_ids(spec, prefix)
    ambiguous = set()
    if a.target_db:
        t_ids = set(rows_by_id(ro(a.target_db)))
        ambiguous = {k for k in m if k in t_ids and not declared.has(num(k))}
    results, total = [], 0
    for f in a.files:
        text = read_text_file(f)
        foreign = Foreign()
        for spec in a.foreign:
            foreign.add_ids(spec, prefix)
        foreign.add_text(text, prefix)
        amb = frozenset(k for k in ambiguous if not foreign.has(num(k)))
        new, n = Rewriter(m, prefix, amb).text(text, foreign, f)
        results.append((f, n, new, text))
        total += n
    for f, n, new, text in results:  # every file is checked before the first one is written
        print("%s\t%d" % (f, n))
        if a.write and new != text:
            with open(f, "w", encoding="utf-8") as h:
                h.write(new)
    print("RESULT: %s files=%d replaced=%d" % ("WRITTEN" if a.write else "DRY-RUN", len(results), total))
    return 0


def cmd_refs(a):
    m, prefix = read_map(a.map)
    try:
        out = subprocess.run(["git", "-C", a.repo_root, "ls-files", "-z"], capture_output=True, check=True).stdout
    except (OSError, subprocess.CalledProcessError) as e:
        raise Blind("git ls-files failed in %s: %s" % (a.repo_root, e))
    files = [x.decode("utf-8", "surrogateescape") for x in out.split(b"\0") if x]
    if not files:
        raise Blind("no tracked file under %s" % a.repo_root)
    _, tok = id_patterns(prefix)
    counts = {"EVIDENCE": 0, "DATABASE": 0, "LIVE": 0}
    for f in sorted(files):
        full = os.path.join(a.repo_root, f)
        if f.endswith(".db"):
            cls = "DATABASE"
            if not f.endswith("workable_items.db"):
                continue
            print("%s\t%s\t-" % (cls, f))
            counts[cls] += 1
            continue
        try:
            raw = open(full, "rb").read()
        except OSError:
            continue
        if b"\0" in raw:
            continue
        text = raw.decode("utf-8", "replace")
        fo = Foreign()
        fo.add_text(text, prefix)
        hits = sorted({t.group(0) for t in tok.finditer(text) if t.group(0) in m and not fo.has(num(t.group(0)))}, key=num)
        if not hits:
            continue
        cls = "EVIDENCE" if f.startswith("docs/qa/") else "LIVE"
        counts[cls] += 1
        print("%s\t%s\t%s" % (cls, f, ",".join(hits)))
    print("RESULT: REFS live=%d evidence=%d database=%d" % (counts["LIVE"], counts["EVIDENCE"], counts["DATABASE"]))
    return 0


def main(argv):
    ap = argparse.ArgumentParser(prog="remint_ids.py")
    sub = ap.add_subparsers(dest="cmd")
    p = sub.add_parser("plan")
    p.add_argument("--vehicle-db", required=True)
    p.add_argument("--base-db", required=True)
    p.add_argument("--target-db", required=True)
    p.add_argument("--prefix", default="CON")
    p.add_argument("--out", required=True)
    p.add_argument("--map-out")
    p.add_argument("--resolve", action="append", default=[])
    p.add_argument("--foreign", action="append", default=[])
    p.add_argument("--repo-root")
    p.add_argument("--no-fast-forward", action="store_true")
    p = sub.add_parser("replay")
    p.add_argument("--plan", required=True)
    p.add_argument("--apply", action="store_true")
    p.add_argument("--engine")
    p.add_argument("--db")
    p = sub.add_parser("verify")
    p.add_argument("--plan", required=True)
    p.add_argument("--vehicle-db", required=True)
    p.add_argument("--base-db", required=True)
    p.add_argument("--target-db", required=True)
    p.add_argument("--db", required=True)
    p.add_argument("--require-segments", action="store_true")
    p = sub.add_parser("rewrite")
    p.add_argument("--map", required=True)
    p.add_argument("--write", action="store_true")
    p.add_argument("--target-db")
    p.add_argument("--foreign", action="append", default=[])
    p.add_argument("--own", action="append", default=[])
    p.add_argument("files", nargs="+")
    p = sub.add_parser("refs")
    p.add_argument("--map", required=True)
    p.add_argument("--repo-root", required=True)
    try:
        a = ap.parse_args(argv)
    except SystemExit as e:
        return 2 if e.code else 0
    if not a.cmd:
        ap.print_usage(sys.stderr)
        return 2
    try:
        return {"plan": cmd_plan, "replay": cmd_replay, "verify": cmd_verify, "rewrite": cmd_rewrite,
                "refs": cmd_refs}[a.cmd](a)
    except Refusal as e:
        print("REFUSED: %s" % e, file=sys.stderr)
        return 1
    except Blind as e:
        print("BLIND: %s" % e, file=sys.stderr)
        return 3
    except (sqlite3.Error, OSError) as e:
        print("BLIND: %s: %s" % (type(e).__name__, e), file=sys.stderr)
        return 3


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
