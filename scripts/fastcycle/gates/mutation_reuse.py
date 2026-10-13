#!/usr/bin/env python3
"""mutation_reuse.py - sound paired-mutation reuse + trivial-equivalence
(TCE) mutant dedup (spec-004 "fast-dev-cycles", User Story 2; plan.md
T-C07; FR-006, FR-007, SC-002; tasks.md T073). Guarded by
constitution/scripts/fastcycle/tests/test_mutation_reuse_red.sh (T057) and
its fixtures under tests/fixtures/mutation_reuse/.

Contract: no dedicated specs/004-fast-dev-cycles/contracts/*.md file
exists for T-C07 (confirmed by test_mutation_reuse_red.sh's own Section A
control needle, re-checked at implementation time). plan.md's T-C07
section and research.md's DEC-23 are the authoritative DESIGN sources;
T057's own RED test is the authoritative WIRE-FORMAT source (its header
comment's "UNCONFIRMED by the contract itself... DEFINED here,
binding-if-adopted" section) -- this docstring restates it, but the RED
test wins if the two ever diverge, per the sibling verdict_cache.py (T068)
precedent this file follows.

Producer != Verifier (§11.4.240): this file is an INDEPENDENT, from-scratch
implementation of DEC-23's formula, written directly from the contract
text above -- it does NOT import, and was NOT reverse-engineered from,
T057's own reference key-builder and reference TCE-normaliser modules
under tests/lib/ (used ONLY to prove the RED test's fixtures non-vacuous
before any claim is made about this file). The two key-builder /
TCE-normaliser implementations happen to agree on every fixture in this
project because both follow the SAME written DEC-23 rule, never because
one copied the other (mirrors verdict_cache.py's own "Producer != Verifier"
note about its own sibling reference module).

DEC-23 rule (plan.md T-C07, verbatim): "re-execute a paired mutation only
when hash(patch || target gate script || observed inputs || tool
versions) changed; reuse KILLED only (SURVIVED is always re-examined);
detect byte-identical (normalised) mutated scripts and report them as
equivalent/duplicate instead of running twice."

CLI (T057's own DEFINED-here, binding-if-adopted wire format):
    mutation_reuse.py put   --cache-dir <dir> --gate <gate_id> --mutation-id <id> \\
                             --patch <diff> --gate-script <path> --inputs <envelope.json> \\
                             --verdict KILLED|SURVIVED --evidence <path> [--determinism-check]
    mutation_reuse.py get   --cache-dir <dir> --gate <gate_id> --mutation-id <id> \\
                             --patch <diff> --gate-script <path> --inputs <envelope.json> \\
                             [--determinism-check]
    mutation_reuse.py check-duplicate --script-a <path> --script-b <path> [--determinism-check]

--inputs <envelope.json> envelope (T057's own DEFINED-here, binding-if-
adopted schema -- see tests/fixtures/mutation_reuse/README.md):
    {
      "patch_sha256": "<hex64>",           # informational only -- the KEY
      "gate_script_sha256": "<hex64>",     # uses the REAL --patch/--gate-
                                            # script FILE BYTES below, never
                                            # these envelope fields (a
                                            # caller-supplied hash is never
                                            # trusted over the actual bytes)
      "observed_inputs": [{"path": ..., "sha256": ..., "recorded_mtime": ...}, ...],
      "tool_versions": {...},
      "verdict": "KILLED"|"SURVIVED"|"",   # put-only bookkeeping -- see below
      "mutation_id": "...",                # put-only bookkeeping
      "gate_id": "..."                     # put-only bookkeeping
    }

DEC-23 key formula (independently authored from the SAME 4 named
components as T057's own reference key-builder under tests/lib/, never
imported from it):
    key = SHA-256(
      mutation patch bytes (read from --patch) ||
      target gate script bytes (read from --gate-script) ||
      sorted (path, sha256) for every envelope observed_input ||
      envelope tool_versions
    ), fields U+001F-separated (mirrors verdict_cache.py's own SEP
    convention), every dict component canonicalised via sorted-key
    "name=value" pairs so JSON key order never leaks into the key.
    EXPLICITLY EXCLUDED from the key (put-only bookkeeping / non-content
    fields, never part of "what changed"):
      - recorded_mtime on any observed_inputs entry (content, not mtime,
        decides -- mirrors T051's VC-002; the CLI's --gate/--mutation-id
        values, and the envelope's own gate_id/mutation_id/verdict fields.
    A gate/mutation-id PAIR is a SEPARATE lookup index (the storage row's
    PRIMARY KEY) rather than a 5th hashed component -- this is what gives
    genuine cross-gate isolation (T057 case 1's "not others" half,
    mr_gate_isolation): two unrelated gates never share one cache slot to
    begin with, regardless of whether their DEC-23 content hashes happen
    to coincide (which they never do in this project's own fixtures,
    since every gate uses a genuinely distinct patch/gate-script pair,
    but the storage design does not rely on that for soundness).

SOUNDNESS INVARIANT (the entire point of this tool, per T-C07's own
"golden-bad: a SURVIVED verdict offered for reuse is refused" protecting
test): a mutation's cached verdict is servable (HIT) if AND ONLY IF (a)
the freshly-computed DEC-23 key for this get EXACTLY matches the stored
key for this (gate, mutation-id) pair, AND (b) the stored verdict is
EXACTLY "KILLED". SURVIVED is enforced TWICE, independently, so a single
broken check can never alone create a false HIT (defense in depth):
  (1) at PUT time (cmd_put): a verdict other than "KILLED" is REFUSED
      (exit 3, "REFUSE key=<hex64> verdict_NOT_CACHEABLE=<v>") and NEVER
      written to storage at all -- mirrors verdict_cache.py's VC-003
      admission-refusal pattern for diagnosability.
  (2) at GET time (cmd_get): even in the hypothetical case a row with a
      non-KILLED verdict existed in storage (e.g. from an older/other
      writer that skipped this tool's own put-time guard), the get-time
      comparison independently re-checks `stored_verdict == "KILLED"`
      before ever reporting HIT.
A mutation that flips guard (1) away (accepts and stores SURVIVED) is
still caught by guard (2); a mutation that flips guard (2) away (drops the
verdict check on read) still cannot serve a SURVIVED row because guard (1)
never let one be written in the first place. Both must be defeated
TOGETHER to produce a false HIT -- exactly the T057/T063 "accept SURVIVED
for reuse" mutation-flip target this design is built to resist.

Exit codes / stdout (T057's own binding wire format):
  put:
    verdict == "KILLED": exit 0, stdout "PUT key=<hex64> verdict=KILLED"
    verdict != "KILLED" (SURVIVED, empty, or anything else): REFUSED --
      exit 3, stdout "REFUSE key=<hex64> verdict_NOT_CACHEABLE=<v>" (never
      silently stored as servable).
  get:
    HIT:  exit 0, stdout's first line "HIT key=<hex64> verdict=KILLED evidence=<path>"
          (a HIT's stdout NEVER contains "verdict=SURVIVED" -- soundness
          invariant above).
    MISS: exit 1, stdout's first line "MISS key=<hex64>" (or key=UNKNOWN
          if the key itself could not be computed, e.g. an unreadable
          --patch/--gate-script/--inputs) -- never a verdict= token on a
          MISS.
  check-duplicate:
    exit 0, stdout "DUPLICATE norm_sha=<hex64>" if the two scripts
      normalise (comment/whitespace-stripped, per DEC-23's TCE half) to
      the SAME digest.
    exit 1, stdout "DISTINCT" otherwise.
  --determinism-check (FR-021, mirrors the C-003 convention on this
    project's other tools, e.g. repo_verify.py / catchset_compare.py):
    runs the SAME operation twice in-process from the SAME inputs and
    compares the (stdout-line, exit-code) pair; on any mismatch, prints a
    diff to stderr and exits 1 regardless of what either individual run
    produced. put's own storage write is naturally idempotent (INSERT OR
    REPLACE keyed by (gate_id, mutation_id)), so running it twice under
    --determinism-check is itself safe, not merely diagnostic.

Honest scope boundary (§11.4.6 -- stated, not silently assumed covered):
DEC-23's "sampling/prediction confined to the nightly drift lane (T-C10)"
clause is a SYSTEM-INTEGRATION property of the fast lane calling THIS tool
unconditionally-trusting-reuse, versus T-C10's own backstop.sh sampling a
fraction of reused verdicts against a fresh full re-run to verify reuse
soundness over time. This tool never second-guesses or samples its own
HITs -- it always trusts a genuine key+KILLED match unconditionally. The
sampling/drift-verification logic itself is T-C10's job (backstop.sh, a
separate, later task) and is explicitly OUT OF SCOPE here, exactly as
tests/fixtures/mutation_reuse/README.md's own "What this RED test does
NOT cover" section states for T-C07's protecting test. Mutation-cache
PURGE/eviction and the flake-ledger interaction (T-C09, flake_ledger.py)
are likewise out of scope -- no fixture in this project's RED test
exercises either, and no plan.md text assigns them to T-C07.
"""
import hashlib
import json
import os
import sqlite3
import sys
import time

SEP = "\x1f"

CACHEABLE_VERDICTS = {"KILLED"}


def canon_map(d):
    """Sorted "name=value" pairs, SEP-joined -- order-independent, byte-
    stable (mirrors verdict_cache.py's own canon_map helper)."""
    return SEP.join(f"{k}={d[k]}" for k in sorted(d))


def compute_key(patch_bytes, gate_script_bytes, envelope):
    """DEC-23 4-component key -- see module docstring. Reads observed_inputs
    and tool_versions from the --inputs envelope; patch/gate-script content
    comes from the ACTUAL FILE BYTES read by the caller (never from the
    envelope's own patch_sha256/gate_script_sha256 fields, which are
    informational metadata only, never a trusted-by-the-tool input)."""
    observed_inputs_raw = envelope.get("observed_inputs", [])
    inputs_sorted = sorted(observed_inputs_raw, key=lambda e: e["path"])
    # recorded_mtime (if present on an entry) is deliberately NOT read here
    # -- only path and sha256 enter the key (content, not mtime, decides).
    inputs_part = SEP.join(f"{e['path']}={e['sha256']}" for e in inputs_sorted)
    tool_versions = envelope.get("tool_versions", {})
    parts = [
        patch_bytes.decode("latin-1"),
        gate_script_bytes.decode("latin-1"),
        inputs_part,
        canon_map(tool_versions),
    ]
    payload = SEP.join(parts).encode("utf-8", errors="surrogateescape")
    return hashlib.sha256(payload).hexdigest()


def load_key_inputs(patch_path, gate_script_path, inputs_path):
    """Read the 3 file-based inputs and compute the DEC-23 key. Raises on
    any malformed/unreadable input -- callers catch and report
    key=UNKNOWN per the wire format."""
    with open(patch_path, "rb") as fh:
        patch_bytes = fh.read()
    with open(gate_script_path, "rb") as fh:
        gate_script_bytes = fh.read()
    with open(inputs_path, "r", encoding="utf-8") as fh:
        envelope = json.load(fh)
    key = compute_key(patch_bytes, gate_script_bytes, envelope)
    return envelope, key


def _sha256_file_or_none(path):
    try:
        h = hashlib.sha256()
        with open(path, "rb") as fh:
            for chunk in iter(lambda: fh.read(65536), b""):
                h.update(chunk)
        return h.hexdigest()
    except OSError:
        return None


def verify_observed_inputs_integrity(envelope, envelope_dir):
    """I1 fix (T085 Round 1, 2026-09-30), mirroring verdict_cache.py's own
    fix of the SAME class of bug: compute_key() deliberately builds its
    key from the CALLER-DECLARED `sha256` field on each observed_inputs
    entry (this IS the fixture-authoring intent -- mr_one_input_changed's
    get_envelope.json keeps `path: "observed_input.txt"` unchanged but
    declares a DIFFERENT sha256, modelling "the caller re-traced and the
    file's real content had changed"; re-hashing from disk in the key
    formula itself would collapse both envelopes onto the SAME key since
    the real, unchanged file matches put's declared hash, turning the
    required MISS into a false HIT). The genuine gap: nothing verifies a
    caller's DECLARED hash is truthful about the file it names RIGHT NOW
    -- a stale envelope (never refreshed after a real file change) is
    trusted unconditionally. This function closes that gap independently
    of the key formula: for every observed_inputs[] entry, resolve `path`
    relative to the fixture-family base directory
    (`os.path.dirname(envelope_dir)` -- the same base every observed
    fixture's `observed_input.txt`/etc. actually lives in; observed_inputs
    [].path was never previously resolved as a real filesystem path at
    all) and re-hash the REAL file now. A mismatch means the envelope
    cannot be trusted for this operation. Returns a list of mismatch
    dicts (empty = every declared hash verified); an unreadable file is
    ALSO reported as a mismatch (fail-closed, §11.4.101)."""
    base = os.path.dirname(envelope_dir)
    mismatches = []
    for entry in envelope.get("observed_inputs", []):
        rel_path = entry.get("path", "")
        resolved = os.path.normpath(os.path.join(base, rel_path))
        real_hash = _sha256_file_or_none(resolved)
        declared = entry.get("sha256")
        if real_hash != declared:
            mismatches.append({
                "path": rel_path,
                "resolved_path": resolved,
                "declared_sha256": declared,
                "real_sha256": real_hash,
            })
    return mismatches


# -----------------------------------------------------------------------
# Storage: one row per (gate_id, mutation_id) pair -- PUT REPLACES the
# existing row for that pair (INSERT OR REPLACE), so each gate/mutation
# slot always holds exactly its MOST RECENT put. This is what gives
# genuine cross-gate isolation (mr_gate_isolation): gate A's put/get never
# touches gate B's row, since they are different PRIMARY KEY values, not
# because their DEC-23 content hashes happen to differ (they also do, in
# every fixture, but the storage design does not depend on that).
# -----------------------------------------------------------------------


def db_path(cache_dir):
    return os.path.join(cache_dir, "mutation_cache.db")


def open_db(cache_dir):
    os.makedirs(cache_dir, exist_ok=True)
    conn = sqlite3.connect(db_path(cache_dir))
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS mutation_cache (
            gate_id TEXT NOT NULL,
            mutation_id TEXT NOT NULL,
            cache_key TEXT NOT NULL,
            verdict TEXT NOT NULL,
            evidence_path TEXT NOT NULL,
            stored_at REAL NOT NULL,
            PRIMARY KEY (gate_id, mutation_id)
        )
        """
    )
    conn.commit()
    return conn


def parse_flags(argv, value_spec, bool_flags=()):
    """value_spec: dict of flag-name (without leading --) -> required(bool).
    bool_flags: iterable of flag-names (without leading --) that take NO
    value -- present/absent only (e.g. --determinism-check). Mirrors
    verdict_cache.py's parse_flags, extended with boolean-flag support
    since this tool needs one (--determinism-check, FR-021) that sibling
    tool does not."""
    bool_flags = set(bool_flags)
    out = {}
    bools = set()
    i = 0
    while i < len(argv):
        tok = argv[i]
        if tok.startswith("--") and tok[2:] in bool_flags:
            bools.add(tok[2:])
            i += 1
            continue
        if tok.startswith("--") and tok[2:] in value_spec:
            name = tok[2:]
            if i + 1 >= len(argv):
                sys.stderr.write(f"mutation_reuse.py: --{name} requires a value\n")
                sys.exit(2)
            out[name] = argv[i + 1]
            i += 2
            continue
        sys.stderr.write(f"mutation_reuse.py: unrecognised argument {tok!r}\n")
        sys.exit(2)
    missing = [n for n, required in value_spec.items() if required and n not in out]
    if missing:
        sys.stderr.write(
            f"mutation_reuse.py: missing required flag(s): {', '.join('--' + m for m in missing)}\n"
        )
        sys.exit(2)
    return out, bools


# -----------------------------------------------------------------------
# put
# -----------------------------------------------------------------------

PUT_SPEC = {
    "cache-dir": True,
    "gate": True,
    "mutation-id": True,
    "patch": True,
    "gate-script": True,
    "inputs": True,
    "verdict": True,
    "evidence": True,
}


def _do_put(flags):
    """Pure(ish) single execution of `put` -- returns (stdout_line,
    exit_code, stderr_diagnostic_or_None). Factored out so
    --determinism-check can run it twice and compare, without printing
    twice."""
    try:
        envelope, key = load_key_inputs(
            flags["patch"], flags["gate-script"], flags["inputs"]
        )
    except (OSError, KeyError, TypeError, json.JSONDecodeError) as exc:
        return "PUT key=UNKNOWN", 1, f"cannot compute key: {exc}"

    verdict = flags["verdict"]
    if verdict not in CACHEABLE_VERDICTS:
        # SOUNDNESS INVARIANT guard (1) of 2 -- see module docstring. A
        # SURVIVED (or empty, or any other) verdict is NEVER written to
        # storage as servable. Refused explicitly (diagnosable) rather
        # than silently accepted-but-inert, mirroring verdict_cache.py's
        # VC-003 admission-refusal precedent.
        return f"REFUSE key={key} verdict_NOT_CACHEABLE={verdict}", 3, None

    # I1 fix: refuse to STORE a verdict keyed on an envelope whose
    # observed_inputs claims do not match the real files right now --
    # mirrors verdict_cache.py's own I1 fix.
    envelope_dir = os.path.dirname(os.path.abspath(flags["inputs"]))
    mismatches = verify_observed_inputs_integrity(envelope, envelope_dir)
    if mismatches:
        paths = ",".join(m["path"] for m in mismatches)
        detail = "; ".join(
            f"{m['path']!r} (resolved {m['resolved_path']!r}) declares sha256="
            f"{m['declared_sha256']!r}, real content hashes to {m['real_sha256']!r}"
            for m in mismatches
        )
        return (
            f"REFUSE key={key} observed_inputs_integrity_mismatch={paths}",
            3,
            f"refusing to store a verdict keyed on an unverified envelope: {detail} "
            "(I1, DEC-23 key built from a caller claim never checked against reality)",
        )

    # --evidence is a caller-supplied CLI argument, resolved relative to
    # the invoking process's cwd and made absolute at put-time so the
    # stored value stays unambiguous even if a later get runs from a
    # different cwd (mirrors verdict_cache.py's own documented choice).
    evidence_path = os.path.abspath(flags["evidence"])

    conn = open_db(flags["cache-dir"])
    try:
        conn.execute(
            "INSERT OR REPLACE INTO mutation_cache "
            "(gate_id, mutation_id, cache_key, verdict, evidence_path, stored_at) "
            "VALUES (?, ?, ?, ?, ?, ?)",
            (
                flags["gate"],
                flags["mutation-id"],
                key,
                verdict,
                evidence_path,
                time.time(),
            ),
        )
        conn.commit()
    finally:
        conn.close()

    return f"PUT key={key} verdict={verdict}", 0, None


def cmd_put(argv):
    flags, bools = parse_flags(argv, PUT_SPEC, bool_flags={"determinism-check"})
    line, code, err = _do_put(flags)

    if "determinism-check" in bools:
        line2, code2, err2 = _do_put(flags)
        if line != line2 or code != code2:
            sys.stderr.write(
                "mutation_reuse.py put: --determinism-check FAILED: "
                f"run1=(exit {code}) {line!r} run2=(exit {code2}) {line2!r}\n"
            )
            return 1

    print(line)
    if err:
        sys.stderr.write(f"mutation_reuse.py put: {err}\n")
    return code


# -----------------------------------------------------------------------
# get
# -----------------------------------------------------------------------

GET_SPEC = {
    "cache-dir": True,
    "gate": True,
    "mutation-id": True,
    "patch": True,
    "gate-script": True,
    "inputs": True,
}


def _do_get(flags):
    try:
        envelope, key = load_key_inputs(
            flags["patch"], flags["gate-script"], flags["inputs"]
        )
    except (OSError, KeyError, TypeError, json.JSONDecodeError) as exc:
        return "MISS key=UNKNOWN", 1, f"cannot compute key: {exc}"

    # I1 fix: NEVER serve a HIT (or even attempt the DB lookup) from an
    # envelope whose observed_inputs claims do not match the real files
    # right now -- mirrors verdict_cache.py's own I1 fix. Reported as an
    # honest MISS (same wire format every other MISS uses), reason on
    # stderr.
    envelope_dir = os.path.dirname(os.path.abspath(flags["inputs"]))
    mismatches = verify_observed_inputs_integrity(envelope, envelope_dir)
    if mismatches:
        detail = "; ".join(
            f"{m['path']!r} (resolved {m['resolved_path']!r}) declares sha256="
            f"{m['declared_sha256']!r}, real content hashes to {m['real_sha256']!r}"
            for m in mismatches
        )
        return (
            f"MISS key={key}",
            1,
            f"refusing to trust this envelope, reporting MISS rather than risking "
            f"a stale HIT: {detail} (I1, DEC-23 key built from a caller claim "
            "never checked against reality)",
        )

    cache_dir = flags["cache-dir"]
    if not os.path.exists(db_path(cache_dir)):
        # No DB yet for this cache-dir -- a genuine, honest MISS, never a
        # crash (a fresh cache-dir is the normal first-run state).
        return f"MISS key={key}", 1, None

    conn = open_db(cache_dir)
    try:
        row = conn.execute(
            "SELECT cache_key, verdict, evidence_path FROM mutation_cache "
            "WHERE gate_id = ? AND mutation_id = ?",
            (flags["gate"], flags["mutation-id"]),
        ).fetchone()
    finally:
        conn.close()

    if row is None:
        return f"MISS key={key}", 1, None

    stored_key, stored_verdict, evidence_path = row

    # SOUNDNESS INVARIANT guard (2) of 2 -- see module docstring. Servable
    # ONLY on an EXACT key match AND stored_verdict == "KILLED",
    # independently re-checked here even though _do_put already refuses to
    # store anything else -- a single broken guard can never alone produce
    # a false HIT.
    if stored_key == key and stored_verdict == "KILLED":
        return f"HIT key={key} verdict={stored_verdict} evidence={evidence_path}", 0, None

    return f"MISS key={key}", 1, None


def cmd_get(argv):
    flags, bools = parse_flags(argv, GET_SPEC, bool_flags={"determinism-check"})
    line, code, err = _do_get(flags)

    if "determinism-check" in bools:
        line2, code2, err2 = _do_get(flags)
        if line != line2 or code != code2:
            sys.stderr.write(
                "mutation_reuse.py get: --determinism-check FAILED: "
                f"run1=(exit {code}) {line!r} run2=(exit {code2}) {line2!r}\n"
            )
            return 1

    print(line)
    if err:
        sys.stderr.write(f"mutation_reuse.py get: {err}\n")
    return code


# -----------------------------------------------------------------------
# check-duplicate (trivial-equivalence / TCE mutant dedup)
# -----------------------------------------------------------------------

CHECK_DUP_SPEC = {"script-a": True, "script-b": True}


def _normalise_line(line):
    """Strip an unquoted trailing comment ('#' outside any quoted string),
    collapse unquoted whitespace runs to a single space, and strip
    leading/trailing whitespace. Whitespace and '#' characters INSIDE a
    single- or double-quoted string are preserved verbatim -- a naive
    strip-at-first-'#' would corrupt any gate script that echoes literal
    text containing '#'. Independently authored from the SAME rule as
    T057's own reference TCE-normaliser module under tests/lib/, never
    imported from it."""
    out = []
    in_dquote = False
    in_squote = False
    pending_space = False

    def emit(ch):
        nonlocal pending_space
        if pending_space:
            out.append(" ")
            pending_space = False
        out.append(ch)

    for ch in line:
        if in_dquote:
            out.append(ch)
            if ch == '"':
                in_dquote = False
            continue
        if in_squote:
            out.append(ch)
            if ch == "'":
                in_squote = False
            continue
        if ch == "#":
            # Unquoted comment start -- discard the rest of the line.
            break
        if ch.isspace():
            if out:
                pending_space = True
            continue
        if ch == '"':
            emit(ch)
            in_dquote = True
            continue
        if ch == "'":
            emit(ch)
            in_squote = True
            continue
        emit(ch)

    return "".join(out).rstrip()


def normalise_script_text(text):
    kept = []
    for raw_line in text.splitlines():
        normalised = _normalise_line(raw_line)
        if normalised:
            kept.append(normalised)
    return "\n".join(kept)


def compute_norm_sha(path):
    with open(path, "r", encoding="utf-8", errors="surrogateescape") as fh:
        text = fh.read()
    normalised = normalise_script_text(text)
    return hashlib.sha256(normalised.encode("utf-8", errors="surrogateescape")).hexdigest()


def _do_check_duplicate(flags):
    try:
        sha_a = compute_norm_sha(flags["script-a"])
        sha_b = compute_norm_sha(flags["script-b"])
    except OSError as exc:
        return "DISTINCT", 1, f"cannot read script: {exc}"

    if sha_a == sha_b:
        return f"DUPLICATE norm_sha={sha_a}", 0, None
    return "DISTINCT", 1, None


def cmd_check_duplicate(argv):
    flags, bools = parse_flags(argv, CHECK_DUP_SPEC, bool_flags={"determinism-check"})
    line, code, err = _do_check_duplicate(flags)

    if "determinism-check" in bools:
        line2, code2, err2 = _do_check_duplicate(flags)
        if line != line2 or code != code2:
            sys.stderr.write(
                "mutation_reuse.py check-duplicate: --determinism-check FAILED: "
                f"run1=(exit {code}) {line!r} run2=(exit {code2}) {line2!r}\n"
            )
            return 1

    print(line)
    if err:
        sys.stderr.write(f"mutation_reuse.py check-duplicate: {err}\n")
    return code


def main(argv):
    if len(argv) < 2:
        sys.stderr.write(
            "usage: mutation_reuse.py put|get|check-duplicate "
            "--cache-dir <dir> --gate <gate_id> --mutation-id <id> "
            "--patch <diff> --gate-script <path> [--inputs <envelope.json>] "
            "[--verdict KILLED|SURVIVED --evidence <path>] [--determinism-check]\n"
        )
        return 2
    subcommand, rest = argv[1], argv[2:]
    if subcommand == "put":
        return cmd_put(rest)
    if subcommand == "get":
        return cmd_get(rest)
    if subcommand == "check-duplicate":
        return cmd_check_duplicate(rest)
    sys.stderr.write(
        f"mutation_reuse.py: unknown subcommand {subcommand!r} "
        "(expected put|get|check-duplicate)\n"
    )
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
