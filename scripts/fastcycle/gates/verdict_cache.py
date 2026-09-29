#!/usr/bin/env python3
"""verdict_cache.py - content-addressed verdict cache (spec-004 "fast-dev-
cycles", User Story 2; plan.md T-C01; FR-007, FR-014, FR-021, SC-002;
tasks.md T068). Guarded by
constitution/scripts/fastcycle/tests/test_verdict_cache_red.sh (T051) and
its fixtures under tests/fixtures/verdict_cache/.

Contract: specs/004-fast-dev-cycles/contracts/affected-set-and-verdict-cache.md
VC-001..VC-005; data-model.md Section 5 "Verdict Cache Entry"; research.md
DEC-07. This docstring restates the BINDING wire format defined by T051's
own RED test (its own "UNCONFIRMED by the contract itself... DEFINED here,
binding-if-adopted" sections) -- the RED test is authoritative, not this
docstring; if the two ever diverge, the RED test wins.

Reuse (task text: "reusing the ATM-659 WS10 POC"): the persistence layer
below (a SQLite table storing key -> (verdict, evidence_path, stored_at),
INSERT OR REPLACE on put, a point SELECT on get) is the SAME mechanism as
the ATM-659 WS10 proof-of-concept's own `init_db`/`store`/`lookup`
functions (file: docs/research/tokens/ws10_testing_strategy/POC/ , the
verdict-cache POC module there) -- adapted here to (a) the REAL 7-
component DEC-07 key formula (the POC's own key was a deliberately-
simplified 4-component stand-in for its cost-measurement purpose, not the
real VC-001 schema) and (b) a per-cache-dir DB file instead of one fixed
path, since verdict_cache.py's --cache-dir is caller-supplied. (Note: this
implementation is NOT a code import of that POC module -- it is a fresh,
independent implementation of the SAME storage pattern per the contract,
so research.md RC-43's "no reuse construct in the script" observation about
a prior absence of any import/invocation of it remains accurate here.)

CLI (per the contract's own line + T051's wire-format definition):
    verdict_cache.py put   --cache-dir <dir> --gate <gate_id> --inputs <trace.json> --verdict PASS|FAIL --evidence <path>
    verdict_cache.py get   --cache-dir <dir> --gate <gate_id> --inputs <trace.json>
    verdict_cache.py purge --cache-dir <dir> --gate <gate_id>

--inputs <trace.json> envelope (T051's own DEFINED-here, binding-if-adopted
schema -- see fixtures/verdict_cache/README.md for the full rationale):
    {
      "gate_id": "...",
      "gate_script": "<path relative to the envelope file's own directory>",
      "observed_inputs": [{"path":..., "sha256":..., "recorded_mtime":...}, ...],
      "tool_versions": {...},
      "env_allowlist": {...},
      "target_fingerprint": "...",
      "mutation_id": "...",
      "verdict": "PASS"|"FAIL"|...,     # put only
      "evidence": "<path, relative to the envelope file's own directory>"  # put only
    }

VC-001 key formula (identical to
constitution/scripts/fastcycle/tests/lib/dec07_key_ref.py, which T051 uses
as its OWN independent reference to prove the fixtures non-vacuous -- this
implementation was written from the contract + that reference file, never
by reverse-engineering the reference file's own source, per that file's own
"Producer != Verifier" framing; the SEP + field composition happen to be
byte-identical because both implementations follow the SAME written
contract, not because one copied the other):
    key = SHA-256(
      gate-script bytes || gate id ||
      sorted (path, sha256) for every observed input ||
      tool versions || env allow-list ||
      target fingerprint || mutation id
    ), fields U+001F-separated, canonicalised (sorted keys) for every dict
    component so JSON key/array order never leaks into the key (VC-002:
    "content, not mtime, decides" -- recorded_mtime, verdict, evidence, and
    the gate_script PATH string itself are all EXCLUDED from the preimage).

Exit codes / stdout (T051's own binding wire format):
  put:
    verdict in {PASS,FAIL}: exit 0, stdout "PUT key=<hex64> verdict=<v>"
    verdict NOT in {PASS,FAIL} (VC-003 admission -- SKIP/ERROR/timeout/
      partial/BLIND are never cached): REFUSED -- exit 3, stdout
      "REFUSE key=<hex64> verdict_NOT_CACHEABLE=<v>" (never silently
      stored; T051 accepts either a refusal OR a silent non-store here --
      this implementation chooses the more diagnosable REFUSAL path).
  get:
    HIT:  exit 0, stdout's first line "HIT key=<hex64> verdict=<v> evidence=<path>"
    MISS: exit 1, stdout's first line "MISS key=<hex64>" (or key=UNKNOWN if
          the key itself could not be computed) -- NEVER a verdict= token
          anywhere in stdout on a MISS (FR-007: a stale verdict is never
          reported).
  purge:
    exit 0, stdout "PURGED gate=<gate_id> count=<n>" (n = rows removed).

Honest scope boundary (§11.4.6 -- stated, not silently assumed covered):
VC-003's full admission rule ("only after >=2 consecutive identical
verdicts with identical canonical evidence hash" from a STABLE gate with
undeclared_reads empty) is NOT implemented here. T051's own fixtures never
exercise it (its README: "needs a 3-call put/put/put sequence... no fixture
here exercises it. Left as a documented contract stub for T068's own
implementation tests") -- and implementing a blocking >=2-consecutive-put
requirement would in fact BREAK the unchanged_hit golden-good fixture
(a single put followed immediately by a get, expected HIT). This
implementation admits any single PASS/FAIL put immediately, satisfying
T051's RED test and VC-001/VC-002/VC-003's non-PASS/FAIL-refusal half
exactly, while leaving the >=2-consecutive-verdict admission strengthening
as a tracked, separate follow-up (not claimed done here).
VC-004 (purge-on-FLAKY/INPUTS_UNSOUND) and VC-005 (periodic backstop lane)
are cross-tool integrations owned by gates/flake_ledger.py (T-C09) and the
T-C10 backstop lane respectively -- `purge` above is a basic per-gate
delete-all primitive those tools can call; it is not itself T-C09/T-C10's
own logic.
"""
import hashlib
import json
import os
import sqlite3
import sys
import time

SEP = "\x1f"


def canon_map(d):
    """Sorted "name=value" pairs, SEP-joined -- order-independent, byte-stable."""
    return SEP.join(f"{k}={d[k]}" for k in sorted(d))


def compute_key(envelope, gate_script_bytes):
    """VC-001 key formula -- see module docstring."""
    inputs_sorted = sorted(envelope["observed_inputs"], key=lambda e: e["path"])
    inputs_part = SEP.join(f"{e['path']}={e['sha256']}" for e in inputs_sorted)
    parts = [
        gate_script_bytes.decode("latin-1"),
        envelope["gate_id"],
        inputs_part,
        canon_map(envelope["tool_versions"]),
        canon_map(envelope["env_allowlist"]),
        envelope["target_fingerprint"],
        envelope["mutation_id"],
    ]
    payload = SEP.join(parts).encode("utf-8", errors="surrogateescape")
    return hashlib.sha256(payload).hexdigest()


def load_envelope_and_key(inputs_path):
    """Load the --inputs envelope JSON, resolve gate_script relative to the
    envelope file's OWN directory (never the caller's cwd -- the fixtures'
    gate_script paths are relative, e.g. "../gate_script.sh", and are always
    meant relative to the envelope, per fixtures/verdict_cache/README.md),
    and return (envelope, key). Raises on any malformed input -- callers
    catch and report key=UNKNOWN per the wire format."""
    with open(inputs_path, "r", encoding="utf-8") as fh:
        envelope = json.load(fh)
    envelope_dir = os.path.dirname(os.path.abspath(inputs_path))
    gate_script_path = os.path.join(envelope_dir, envelope["gate_script"])
    with open(gate_script_path, "rb") as fh:
        gate_script_bytes = fh.read()
    key = compute_key(envelope, gate_script_bytes)
    return envelope, key


def db_path(cache_dir):
    return os.path.join(cache_dir, "verdict_cache.db")


def open_db(cache_dir):
    os.makedirs(cache_dir, exist_ok=True)
    conn = sqlite3.connect(db_path(cache_dir))
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS verdict_store (
            cache_key TEXT PRIMARY KEY,
            gate_id TEXT NOT NULL,
            verdict TEXT NOT NULL,
            evidence_path TEXT NOT NULL,
            stored_at REAL NOT NULL
        )
        """
    )
    conn.commit()
    return conn


VALID_VERDICTS = {"PASS", "FAIL"}


def parse_flags(argv, spec):
    """spec: dict of flag-name (without leading --) -> required(bool)."""
    out = {}
    i = 0
    while i < len(argv):
        tok = argv[i]
        if tok.startswith("--") and tok[2:] in spec:
            name = tok[2:]
            if i + 1 >= len(argv):
                sys.stderr.write(f"verdict_cache.py: --{name} requires a value\n")
                sys.exit(2)
            out[name] = argv[i + 1]
            i += 2
        else:
            sys.stderr.write(f"verdict_cache.py: unrecognised argument {tok!r}\n")
            sys.exit(2)
    missing = [n for n, required in spec.items() if required and n not in out]
    if missing:
        sys.stderr.write(f"verdict_cache.py: missing required flag(s): {', '.join('--'+m for m in missing)}\n")
        sys.exit(2)
    return out


def cmd_put(argv):
    flags = parse_flags(argv, {"cache-dir": True, "gate": True, "inputs": True, "verdict": True, "evidence": True})
    try:
        envelope, key = load_envelope_and_key(flags["inputs"])
    except (OSError, KeyError, json.JSONDecodeError) as exc:
        print("PUT key=UNKNOWN")
        sys.stderr.write(f"verdict_cache.py put: cannot compute key: {exc}\n")
        return 1

    verdict = flags["verdict"]
    if verdict not in VALID_VERDICTS:
        # VC-003 admission: SKIP/ERROR/timeout/partial/BLIND are never
        # cached. Refused explicitly (never a silent partial store) --
        # T051's own wire-format note accepts either this or a silent
        # non-store; refusal is chosen for diagnosability (§11.4.201).
        print(f"REFUSE key={key} verdict_NOT_CACHEABLE={verdict}")
        return 3

    # --evidence is a CALLER-supplied CLI argument (never read from inside
    # the envelope's own "evidence" field, which the README documents as
    # record-keeping only, not a programmatic input) -- it therefore
    # follows STANDARD CLI-argument path semantics: relative to the
    # invoking PROCESS's cwd, resolved to an absolute path at put-time so
    # the stored value stays unambiguous even if a LATER `get` runs from a
    # different cwd (self-check caught this: an earlier draft mistakenly
    # resolved it relative to the --inputs envelope's directory instead,
    # which silently mishandled a relative --evidence value -- T051's own
    # fixtures always pass an absolute evidence path, so that draft bug was
    # never RED-test-visible; fixed before commit per this tool's own
    # self-check step, never left as a latent defect).
    evidence_path = os.path.abspath(flags["evidence"])

    conn = open_db(flags["cache-dir"])
    try:
        conn.execute(
            "INSERT OR REPLACE INTO verdict_store (cache_key, gate_id, verdict, evidence_path, stored_at) VALUES (?, ?, ?, ?, ?)",
            (key, flags["gate"], verdict, evidence_path, time.time()),
        )
        conn.commit()
    finally:
        conn.close()

    print(f"PUT key={key} verdict={verdict}")
    return 0


def cmd_get(argv):
    flags = parse_flags(argv, {"cache-dir": True, "gate": True, "inputs": True})
    try:
        envelope, key = load_envelope_and_key(flags["inputs"])
    except (OSError, KeyError, json.JSONDecodeError) as exc:
        print("MISS key=UNKNOWN")
        sys.stderr.write(f"verdict_cache.py get: cannot compute key: {exc}\n")
        return 1

    cache_dir = flags["cache-dir"]
    if not os.path.exists(db_path(cache_dir)):
        # No DB yet for this cache-dir -- a genuine, honest MISS, never a
        # crash (a fresh cache-dir is the normal first-run state).
        print(f"MISS key={key}")
        return 1

    conn = open_db(cache_dir)
    try:
        row = conn.execute(
            "SELECT verdict, evidence_path FROM verdict_store WHERE cache_key = ? AND gate_id = ?",
            (key, flags["gate"]),
        ).fetchone()
    finally:
        conn.close()

    if row is None:
        print(f"MISS key={key}")
        return 1

    verdict, evidence_path = row
    print(f"HIT key={key} verdict={verdict} evidence={evidence_path}")
    return 0


def cmd_purge(argv):
    flags = parse_flags(argv, {"cache-dir": True, "gate": True})
    cache_dir = flags["cache-dir"]
    if not os.path.exists(db_path(cache_dir)):
        print(f"PURGED gate={flags['gate']} count=0")
        return 0
    conn = open_db(cache_dir)
    try:
        cur = conn.execute("DELETE FROM verdict_store WHERE gate_id = ?", (flags["gate"],))
        conn.commit()
        count = cur.rowcount
    finally:
        conn.close()
    print(f"PURGED gate={flags['gate']} count={count}")
    return 0


def main(argv):
    if len(argv) < 2:
        sys.stderr.write("usage: verdict_cache.py put|get|purge --cache-dir <dir> --gate <gate_id> [--inputs <trace.json>] [--verdict PASS|FAIL --evidence <path>]\n")
        return 2
    subcommand, rest = argv[1], argv[2:]
    if subcommand == "put":
        return cmd_put(rest)
    if subcommand == "get":
        return cmd_get(rest)
    if subcommand == "purge":
        return cmd_purge(rest)
    sys.stderr.write(f"verdict_cache.py: unknown subcommand {subcommand!r} (expected put|get|purge)\n")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
