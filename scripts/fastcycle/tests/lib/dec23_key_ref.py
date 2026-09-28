#!/usr/bin/env python3
"""
T057 reference (non-production) implementation of DEC-23's mutation-reuse
cache-key formula, authored independently of
`constitution/scripts/fastcycle/gates/mutation_reuse.py` (T-C07, which does
not exist yet at the time this file was written). Used ONLY by
`test_mutation_reuse_red.sh` to prove its fixture pairs under
`fixtures/mutation_reuse/` are non-vacuous -- it never claims to BE
mutation_reuse.py and it is never itself the tool a T-C07 "GREEN" run
invokes.

Contract: specs/004-fast-dev-cycles/plan.md T-C07 (no dedicated
contracts/*.md file exists for T-C07 at the time this file was written --
confirmed by a real directory listing, not assumed); research.md DEC-23.

    key = SHA-256(
      mutation patch bytes ||
      target gate script bytes ||
      gate's observed inputs (sorted list of (path, SHA-256)) ||
      tool versions
    )

DEC-23's plan.md text names exactly these 4 components (mutation patch,
target gate script, observed inputs, tool versions) -- a strict subset of
DEC-07's 7-component verdict-cache key (T051's dec07_key_ref.py), since
mutation reuse does not key on env_allowlist / target_fingerprint /
mutation_id (mutation_id is what is being looked up, not an input to its
own key, mirroring how DEC-07 excludes verdict/evidence from VC-001's key).

Field separator: U+001F (unit separator), reused from dec07_key_ref.py's
own convention for consistency across this feature's cache-key builders --
not independently re-derived.

`recorded_mtime` (a per-observed-input provenance field this file's own
envelope schema carries, mirroring T051's fixtures/verdict_cache/README.md
convention) is deliberately EXCLUDED from the preimage: content, not mtime,
decides (the same VC-002 principle DEC-07 states, applied here by direct
analogy since DEC-23 states no separate mtime-exclusion rule of its own but
plan.md T-C07's "Rollback: reuse off -> every mutation runs" framing only
makes sense if the key is content-addressed, not mtime-addressed).

`verdict` (KILLED/SURVIVED) is EXCLUDED from the preimage -- it is the
STORED value being looked up, never an input to its own lookup key (same
principle as DEC-07's exclusion of `verdict`/`evidence`).

Usage: dec23_key_ref.py <envelope.json>
Prints the 64-hex-char reference key to stdout and exits 0, or prints
nothing and exits 1 on a malformed envelope.
"""
import hashlib
import json
import sys

SEP = "\x1f"


def sorted_inputs(entries):
    """Sorted (path, sha256) pairs, SEP-joined -- order-independent, byte-stable."""
    pairs = sorted((e["path"], e["sha256"]) for e in entries)
    return SEP.join(f"{p}={h}" for p, h in pairs)


def canon_map(d):
    """Sorted "name=value" pairs, SEP-joined -- order-independent, byte-stable."""
    return SEP.join(f"{k}={d[k]}" for k in sorted(d))


def main():
    if len(sys.argv) != 2:
        sys.exit(1)
    try:
        with open(sys.argv[1]) as f:
            env = json.load(f)
        patch_sha256 = env["patch_sha256"]
        gate_script_sha256 = env["gate_script_sha256"]
        observed_inputs = env["observed_inputs"]
        tool_versions = env["tool_versions"]
    except (OSError, KeyError, json.JSONDecodeError, TypeError):
        sys.exit(1)

    preimage = SEP.join(
        [
            patch_sha256,
            gate_script_sha256,
            sorted_inputs(observed_inputs),
            canon_map(tool_versions),
        ]
    )
    print(hashlib.sha256(preimage.encode("utf-8")).hexdigest())
    sys.exit(0)


if __name__ == "__main__":
    main()
