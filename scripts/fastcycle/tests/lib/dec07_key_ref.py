#!/usr/bin/env python3
"""
T051 reference (non-production) implementation of VC-001's cache-key
formula, authored independently of `constitution/scripts/fastcycle/gates/
verdict_cache.py` (T068, which does not exist yet at the time this file was
written). Used ONLY by `test_verdict_cache_red.sh` to prove its fixture
pairs under `fixtures/verdict_cache/` are non-vacuous -- it never claims to
BE verdict_cache.py and it is never itself the tool a T068 "GREEN" run
invokes.

Contract: specs/004-fast-dev-cycles/contracts/affected-set-and-verdict-cache.md
VC-001; data-model.md §5 "Verdict Cache Entry"; research.md DEC-07.

    key = SHA-256(
      gate-script bytes ||
      gate id ||
      sorted list of (path, SHA-256) for every observed input ||
      tool versions || allow-listed env ||
      target fingerprint (or "hermetic") ||
      mutation id (or "none")
    )

Field separator: U+001F (unit separator), matching the WS10 POC's own
`"\\x1f".join([...])` convention
(docs/research/tokens/ws10_testing_strategy/POC/verdict_cache_poc.py) --
reused for consistency, not independently re-derived, since DEC-07's own
"Source" line credits that POC as the mechanism T068 reuses.

`recorded_mtime` (a per-observed-input provenance field this file's own
envelope schema carries, see fixtures/verdict_cache/README.md),
`verdict`, `evidence`, and the `gate_script` PATH string (as opposed to its
BYTES, which the caller reads separately and passes in) are deliberately
EXCLUDED from the preimage: VC-002 ("content, not mtime, decides") and
data-model.md §5's `recorded_at` field ("provenance only -- not part of the
key") both name mtime/provenance as non-key-bearing; verdict/evidence are
the STORED value, never an input to their own lookup key.

Usage: dec07_key_ref.py <envelope.json> <gate_script_path>
Prints the 64-hex-char reference key to stdout and exits 0, or prints
nothing and exits 1 on a malformed envelope.
"""
import hashlib
import json
import sys

SEP = "\x1f"


def canon_map(d):
    """Sorted "name=value" pairs, SEP-joined -- order-independent, byte-stable."""
    return SEP.join(f"{k}={d[k]}" for k in sorted(d))


def reference_key(envelope, gate_script_bytes):
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


def main():
    if len(sys.argv) != 3:
        print("usage: dec07_key_ref.py <envelope.json> <gate_script_path>", file=sys.stderr)
        return 1
    envelope_path, gate_script_path = sys.argv[1], sys.argv[2]
    try:
        with open(envelope_path) as f:
            envelope = json.load(f)
        with open(gate_script_path, "rb") as f:
            gate_script_bytes = f.read()
        print(reference_key(envelope, gate_script_bytes))
    except (OSError, KeyError, json.JSONDecodeError) as exc:
        print(f"dec07_key_ref.py: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
