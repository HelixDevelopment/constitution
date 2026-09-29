#!/usr/bin/env python3
"""dispatch_prefix.py — dispatch-prompt ordering for cache reuse (SpecKit-004
"fast-dev-cycles", User Story 4, T115; plan T-E03; FR-013, SC-005). RED test
(T106, a SEPARATE, EARLIER task): constitution/scripts/fastcycle/tests/
test_prefix_cache_red.sh + fixtures under tests/fixtures/prefix_cache/ —
read that test before touching this file; it is this tool's interim
contract (no contracts/*.md file exists for this tool yet —
contracts/common-conventions.md's own "Plan tools that no contract in
this directory covers" note names `$FC/context/dispatch_prefix.py (T-E03)`
explicitly, matching `$FC/tokens/transcript_ingest.py`'s own identical,
already-documented situation).

Purpose (plan.md T-E03 + tasks.md T115, restated precisely, never invented):

  1. ORDER every dispatch prompt as [core][subset][per-item] — ALWAYS,
     unconditionally. This is the ONE property that lets a provider serve
     a cache READ on the second of two same-class dispatches (Anthropic's
     own prompt-caching mechanics, R5:20-24, already cited by T106's own
     RED test: a cache read is served only when the byte prefix up to the
     cache breakpoint is byte-IDENTICAL to a previously cached prefix).
     `compose` below is deliberately NOT parameterised by an "order" flag
     — there is no correct alternative ordering this tool ever produces.
     A caller that wants the golden-bad "broken" ordering (per-item placed
     before the subset) builds it itself; T106's RED test does exactly
     that, entirely independently of this file, via its own from-scratch
     `derive_prompt()` oracle — never by asking this real tool to
     misorder on purpose (§11.4.240 producer != verifier: this file never
     imports, copies, or otherwise couples to that test's oracle).

  2. KEEP tool lists (the [core][subset] prefix) BYTE-IDENTICAL within a
     dispatch class. `compose` upholds this BY CONSTRUCTION — the
     [core][subset] bytes it writes are the caller's own `--core`/
     `--subset` file bytes, concatenated verbatim, with NO injected
     timestamp, no run-varying content, no whitespace normalisation that
     could drift between two otherwise-identical inputs. `verify-class`
     below is the ACTIVE, independently-callable enforcement of this
     property: given the same (`--core`, `--subset`) pair supplied for N
     dispatches of one class, it reports whether every pair's composed
     prefix is genuinely byte-identical — a caller (the dispatch
     orchestration layer) can run it before or after `compose` to CONFIRM
     the invariant held, rather than merely trusting the construction
     argument above. `compose` itself additionally accepts an OPTIONAL
     `--class-id` (with `--class-state-dir`) to record and enforce this
     SAME invariant in-line, across separate `compose` invocations over
     time — entirely opt-in. T106's own RED test's real-tool invocation
     block never passes `--class-id`, so this path stays dormant for that
     test; the tested `compose --core ... --subset ... --per-item ...
     --out ...` contract is unaffected either way.

  3. READ `cache_read_input_tokens` via the ALREADY-LANDED, ALREADY-TESTED
     `tokens/transcript_ingest.py` (T038/T020) — `cache-status` below
     invokes that module's own `main()` DIRECTLY (imported by path, never
     reimplemented, never a subprocess re-parse of the same JSONL bytes)
     to ingest a real transcript and then reports, for one named dispatch
     message, whether the provider actually served a cache READ
     (measured, `cache_read_input_tokens` > 0), a cache MISS (measured,
     == 0), or the honest U-12 limitation (genuinely UNMEASURED — the CLI
     exposed no subagent cache metric for this turn at all; research.md:
     "The CLI exposes prompt-cache hit metrics per subagent — UNCONFIRMED,
     R5:157"). This mirrors T106's own RED test's Oracle B exactly, using
     the SAME real instrument, so a caller of THIS real tool sees the
     identical three-way discrimination that test already proved
     possible — never a fourth, invented "no signal means miss" outcome.

Invocation:
    dispatch_prefix.py compose --core FILE --subset FILE --per-item FILE
        --out FILE [--class-id ID] [--class-state-dir DIR]
    dispatch_prefix.py verify-class --core FILE --subset FILE
        [--core FILE --subset FILE ...]   (repeatable pairs, paired by
        position; >=2 pairs needed for a meaningful comparison — a single
        pair is trivially PASS, nothing to compare against)
    dispatch_prefix.py cache-status --transcript PATH --msg-id ID [--db PATH]

Wire format for `compose` (FIXED by T106's own RED test — see that file's
"Forward-compatible real-tool invocation" section, binding on this file
unless an explicit, evidenced deviation is recorded): `--out` receives the
RAW COMPOSED PROMPT BYTES — core-file-bytes + subset-file-bytes +
per-item-file-bytes, concatenated verbatim, in that exact order, with NO
JSON envelope and NO schema/body_hash wrapper (unlike this tool's C-002-
following siblings `tier_route.py`/`evidence_ref.py`/`governance_subset.py`
— `--out` here IS the prompt text a dispatcher hands to a provider, not a
report ABOUT one; T106's own test reads it back with a raw `open(...,
'rb').read()`, never `json.load`). `verify-class` and `cache-status`,
neither exercised by T106's fixed contract, print a plain human-readable
report to stdout — matching `tokens/transcript_ingest.py`'s own simpler,
print-based convention, the closest sibling in spirit since both read
real transcript/cache data rather than emitting a structured decision
document a downstream tool consumes.

Exit codes (this tool is NOT bound by contracts/common-conventions.md's
C-001 5-code table — dispatch_prefix.py is explicitly among the "no
contract" tools per that same note, matching `tokens/transcript_ingest.py`
's own already-documented deviation): 0 = success (`compose` wrote `--out`
with no `--class-id` invariant violation; `verify-class` found every
supplied pair's prefix byte-identical; `cache-status` reached a real,
determinate answer — measured HIT, measured MISS, or the honest U-12
UNMEASURED state; all three are success, never a failure, matching T106's
own RED test's own treatment of the U-12 branch). 1 = a finding:
`compose --class-id` detected a DIFFERENT core+subset byte-prefix
previously recorded for the SAME class id (the tool-list-byte-identity
invariant broken — bullet 2 above); `verify-class` found two or more
supplied pairs whose composed prefixes differ. 2 = usage/argument/IO error
(a named `--core`/`--subset`/`--per-item`/`--transcript` file does not
exist or cannot be read; malformed arguments; an internal invariant
transcript_ingest.py itself documents was contradicted). 4 = BLIND
(`cache-status` only: the named `--msg-id` was never found anywhere in
the ingested transcript at all — distinct from "found but UNMEASURED"; no
honest verdict of ANY of the three states above is possible), matching
C-001's own row-4 meaning precisely even though this tool is not formally
bound by that table.

Side-effects: `compose` writes only `--out` (write-temp-then-rename,
section 11.4.205(6), matching the already-landed sibling `tier_route.py`'s
own `write_doc_atomic` pattern) and, when `--class-id` is given, one small
JSON record file under `--class-state-dir` (default: a
`.dispatch_prefix_classes/` directory beside `--out`) — created if
absent, never touching any other file. `verify-class` is fully read-only.
`cache-status` writes only its own `--db` (created if absent, matching
`transcript_ingest.py`'s own `open_db`, appended-to only — never deleted
or truncated). None of the three ever writes to, renames, or deletes a
source transcript/core/subset/per-item file.

Determinism: `compose`'s output is a pure function of its three input
files' bytes (no injected timestamp, no run-varying content, no
locale/hash-order dependence) — two consecutive runs over byte-identical
inputs produce a byte-identical `--out`. No formal `--determinism-check`
flag is implemented (no contract mandates one for this tool, per the
deviation noted above); the property holds by construction and is
exercised by T106's own RED test running `compose` twice per fixture.

Dependencies: Python stdlib only, plus one sibling import by path
(`tokens/transcript_ingest.py`, for `cache-status` — bullet 3's task
instruction: "import/invoke it directly, do not reimplement transcript
parsing"), matching `context/tier_route.py`'s own identical
path-inserted-sys.path-then-import pattern for `lib/fc_common.py`
(`constitution/scripts/fastcycle` has no `__init__.py` anywhere, this
tree's existing flat-script layout).
"""
import argparse
import hashlib
import json
import os
import sqlite3
import sys
import tempfile

# ---------------------------------------------------------------------------
# Wiring to the sibling tokens/transcript_ingest.py, imported BY PATH (never
# reimplemented — bullet 3 above, this task's own explicit instruction).
# Identical import-by-path pattern to context/tier_route.py's own
# lib/fc_common.py wiring.
# ---------------------------------------------------------------------------
_TOKENS_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tokens")
if _TOKENS_DIR not in sys.path:
    sys.path.insert(0, _TOKENS_DIR)
import transcript_ingest  # noqa: E402  (path-inserted import, see above)


EXIT_OK = 0
EXIT_FINDING = 1
EXIT_USAGE = 2
EXIT_BLIND = 4


def _read_bytes(path, label):
    """Read `path` as raw bytes. Returns (data, error) — error is a
    human-readable string on failure and data is None; on success error
    is None. Never raises — every caller decides its own exit code."""
    if not os.path.isfile(path):
        return None, "%s not found: %s" % (label, path)
    try:
        with open(path, "rb") as fh:
            return fh.read(), None
    except OSError as exc:
        return None, "cannot read %s %s: %s" % (label, path, exc)


def write_bytes_atomic(out_path, data):
    """Write-temp-then-rename (section 11.4.205(6)), matching the
    already-landed sibling `tier_route.py`'s own `write_doc_atomic`
    pattern, applied here to raw bytes instead of a JSON document —
    `compose`'s `--out` is the prompt text itself, never a report about
    one (see module docstring "Wire format")."""
    out_dir = os.path.dirname(os.path.abspath(out_path)) or "."
    os.makedirs(out_dir, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=out_dir, prefix=".dispatch_prefix.")
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(data)
        os.replace(tmp, out_path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def _write_json_atomic(path, obj):
    data = (json.dumps(obj, sort_keys=True, indent=2) + "\n").encode("utf-8")
    out_dir = os.path.dirname(os.path.abspath(path)) or "."
    os.makedirs(out_dir, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=out_dir, prefix=".dispatch_prefix_class.")
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(data)
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def _class_id_to_filename(class_id):
    """Sanitise an arbitrary caller-supplied class id into a safe
    filename — never trusts it to already be filesystem-safe."""
    safe = "".join(ch if (ch.isalnum() or ch in "-_.") else "_" for ch in class_id)
    return (safe or "class") + ".json"


def _check_and_record_class(class_id, prefix_bytes, state_dir):
    """The OPT-IN, in-line enforcement of bullet 2 (tool-list-byte-identity
    within a dispatch class) across separate `compose` invocations over
    time. Returns (ok, message). Never touches anything outside
    state_dir; state_dir is created if absent."""
    digest = hashlib.sha256(prefix_bytes).hexdigest()
    os.makedirs(state_dir, exist_ok=True)
    state_path = os.path.join(state_dir, _class_id_to_filename(class_id))

    if not os.path.isfile(state_path):
        record = {
            "class_id": class_id,
            "prefix_sha256": digest,
            "prefix_len": len(prefix_bytes),
            "observations": 1,
        }
        _write_json_atomic(state_path, record)
        return True, (
            "first observation recorded for this class (prefix=%dB, sha256=%s)"
            % (len(prefix_bytes), digest)
        )

    try:
        with open(state_path, encoding="utf-8") as fh:
            record = json.load(fh)
    except (OSError, ValueError) as exc:
        return False, (
            "cannot read existing class-state record %s: %s — refusing to "
            "silently overwrite it (fix or remove it by hand)" % (state_path, exc)
        )

    if record.get("prefix_sha256") == digest:
        record["observations"] = int(record.get("observations", 1)) + 1
        record["prefix_len"] = len(prefix_bytes)
        _write_json_atomic(state_path, record)
        return True, (
            "byte-identical to the previously recorded [core][subset] prefix "
            "(sha256=%s, now %d observation(s))" % (digest, record["observations"])
        )

    return False, (
        "tool-list-byte-identity VIOLATED for class %r: this composition's "
        "[core][subset] prefix (sha256=%s, %dB) differs from the one "
        "previously recorded for this class (sha256=%s, %sB, recorded at "
        "%s) — a caching provider will NOT serve a cache read across these "
        "two dispatches"
        % (
            class_id, digest, len(prefix_bytes),
            record.get("prefix_sha256"), record.get("prefix_len"), state_path,
        )
    )


# ---------------------------------------------------------------------------
# compose — the fixed, T106-tested contract (bullet 1 + bullet 2's opt-in
# in-line class check).
# ---------------------------------------------------------------------------
def cmd_compose(args):
    core, err = _read_bytes(args.core, "--core")
    if err:
        print("dispatch_prefix: %s" % err, file=sys.stderr)
        return EXIT_USAGE
    subset, err = _read_bytes(args.subset, "--subset")
    if err:
        print("dispatch_prefix: %s" % err, file=sys.stderr)
        return EXIT_USAGE
    per_item, err = _read_bytes(args.per_item, "--per-item")
    if err:
        print("dispatch_prefix: %s" % err, file=sys.stderr)
        return EXIT_USAGE

    # bullet 1: the mandatory [core][subset][per-item] order — never
    # configurable, never parameterised by a caller-supplied flag.
    prefix = core + subset
    composed = prefix + per_item

    if args.class_id:
        state_dir = args.class_state_dir or os.path.join(
            os.path.dirname(os.path.abspath(args.out)) or ".", ".dispatch_prefix_classes"
        )
        ok, msg = _check_and_record_class(args.class_id, prefix, state_dir)
        if not ok:
            print("dispatch_prefix: %s" % msg, file=sys.stderr)
            return EXIT_FINDING
        print("dispatch_prefix: class-id %s: %s" % (args.class_id, msg))

    try:
        write_bytes_atomic(args.out, composed)
    except OSError as exc:
        print("dispatch_prefix: cannot write --out %s: %s" % (args.out, exc), file=sys.stderr)
        return EXIT_USAGE

    print(
        "dispatch_prefix: composed [core][subset][per-item] -> %s "
        "(core=%dB subset=%dB per_item=%dB prefix=%dB total=%dB)"
        % (args.out, len(core), len(subset), len(per_item), len(prefix), len(composed))
    )
    return EXIT_OK


# ---------------------------------------------------------------------------
# verify-class — bullet 2's standalone, independently-callable enforcement.
# ---------------------------------------------------------------------------
def cmd_verify_class(args):
    cores = args.core or []
    subsets = args.subset or []
    if not cores or not subsets:
        print(
            "dispatch_prefix: verify-class requires at least one --core/--subset pair",
            file=sys.stderr,
        )
        return EXIT_USAGE
    if len(cores) != len(subsets):
        print(
            "dispatch_prefix: verify-class requires the SAME number of --core "
            "and --subset flags (paired by position): got %d --core, %d --subset"
            % (len(cores), len(subsets)),
            file=sys.stderr,
        )
        return EXIT_USAGE

    prefixes = []
    for i, (core_path, subset_path) in enumerate(zip(cores, subsets)):
        core, err = _read_bytes(core_path, "--core[%d]" % i)
        if err:
            print("dispatch_prefix: %s" % err, file=sys.stderr)
            return EXIT_USAGE
        subset, err = _read_bytes(subset_path, "--subset[%d]" % i)
        if err:
            print("dispatch_prefix: %s" % err, file=sys.stderr)
            return EXIT_USAGE
        prefixes.append(core + subset)

    first = prefixes[0]
    mismatches = [i for i, p in enumerate(prefixes) if p != first]
    if mismatches:
        print(
            "dispatch_prefix: verify-class: %d of %d pair(s) do NOT share a "
            "byte-identical [core][subset] prefix with pair 0 — indices %s "
            "(bullet 2's tool-list-byte-identity invariant is BROKEN for this "
            "class; a caching provider will NOT serve a cache read across "
            "these dispatches)"
            % (len(mismatches), len(prefixes), mismatches),
            file=sys.stderr,
        )
        return EXIT_FINDING

    print(
        "dispatch_prefix: verify-class: all %d pair(s) share a byte-identical "
        "[core][subset] prefix (%d bytes, sha256=%s)"
        % (len(prefixes), len(first), hashlib.sha256(first).hexdigest())
    )
    return EXIT_OK


# ---------------------------------------------------------------------------
# cache-status — bullet 3: reads cache_read_input_tokens via
# tokens/transcript_ingest.py's own main(), imported by path and invoked
# directly. Never reimplements JSONL/transcript parsing.
# ---------------------------------------------------------------------------
def cmd_cache_status(args):
    if not os.path.exists(args.transcript):
        print("dispatch_prefix: --transcript not found: %s" % args.transcript, file=sys.stderr)
        return EXIT_USAGE

    db_path = args.db if args.db else transcript_ingest.DEFAULT_DB

    ingest_rc = transcript_ingest.main(["ingest", args.transcript, "--db", db_path])
    if ingest_rc != 0:
        print(
            "dispatch_prefix: transcript_ingest.py ingest of %s failed (rc=%d) — "
            "cannot determine cache status" % (args.transcript, ingest_rc),
            file=sys.stderr,
        )
        return EXIT_USAGE

    try:
        conn = transcript_ingest.open_db(db_path)
    except sqlite3.Error as exc:
        print("dispatch_prefix: cannot open --db %s: %s" % (db_path, exc), file=sys.stderr)
        return EXIT_USAGE

    row = conn.execute(
        "SELECT usage_status, cache_read_input_tokens, missing_instrument "
        "FROM transcript_usage_events WHERE msg_id = ?",
        (args.msg_id,),
    ).fetchone()

    if row is None:
        print(
            "dispatch_prefix: BLIND: --msg-id %r was never found in the ingested "
            "transcript %s (db=%s) — no honest cache-status verdict is possible "
            "(distinct from 'found but unmeasured')"
            % (args.msg_id, args.transcript, db_path),
            file=sys.stderr,
        )
        return EXIT_BLIND

    usage_status, cache_read, missing_instrument = row

    if usage_status == transcript_ingest.UNMEASURED:
        print(
            "dispatch_prefix: U-12 LIMITATION RECORDED for msg-id %s: the CLI "
            "exposed no subagent cache metric for this turn (missing_instrument=%s) "
            "— per research.md U-12 ('The CLI exposes prompt-cache hit metrics "
            "per subagent — UNCONFIRMED, R5:157'), this is NEITHER a hit NOR a "
            "miss; it is honestly UNMEASURED. status=UNMEASURED"
            % (args.msg_id, missing_instrument)
        )
        return EXIT_OK

    if cache_read is None:
        print(
            "dispatch_prefix: UNEXPECTED: msg-id %s is usage_status=measured "
            "but cache_read_input_tokens is NULL — this contradicts "
            "transcript_ingest.py's own documented invariant; refusing to "
            "guess a verdict" % args.msg_id,
            file=sys.stderr,
        )
        return EXIT_USAGE

    if cache_read > 0:
        print(
            "dispatch_prefix: CACHE HIT for msg-id %s: cache_read_input_tokens=%d "
            "(measured, > 0) — this dispatch's [core][subset] prefix reused a "
            "previously cached prefix" % (args.msg_id, cache_read)
        )
    else:
        print(
            "dispatch_prefix: CACHE MISS for msg-id %s: cache_read_input_tokens=0 "
            "(measured, a genuine captured zero — never NULL) — no cache read "
            "was served for this dispatch" % args.msg_id
        )
    return EXIT_OK


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def build_arg_parser():
    p = argparse.ArgumentParser(prog="dispatch_prefix.py", description=__doc__.split("\n\n")[0])
    sub = p.add_subparsers(dest="cmd_name", required=True)

    c = sub.add_parser("compose")
    c.add_argument("--core", required=True)
    c.add_argument("--subset", required=True)
    c.add_argument("--per-item", required=True)
    c.add_argument("--out", required=True)
    c.add_argument("--class-id", default=None)
    c.add_argument("--class-state-dir", default=None)

    v = sub.add_parser("verify-class")
    v.add_argument("--core", action="append")
    v.add_argument("--subset", action="append")

    s = sub.add_parser("cache-status")
    s.add_argument("--transcript", required=True)
    s.add_argument("--msg-id", required=True)
    s.add_argument("--db", default=None)

    return p


def main(argv):
    args = build_arg_parser().parse_args(argv)
    table = {
        "compose": cmd_compose,
        "verify-class": cmd_verify_class,
        "cache-status": cmd_cache_status,
    }
    return table[args.cmd_name](args)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
