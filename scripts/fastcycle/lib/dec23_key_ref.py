#!/usr/bin/env python3
"""dec23_key_ref.py — reference (independent, from-scratch) implementation of
the DEC-23 mutation-reuse cache-key formula, used ONLY by
tests/test_mutation_reuse_red.sh (T057, SpecKit-004 "fast-dev-cycles") to
self-validate that the fixtures under tests/fixtures/mutation_reuse/
genuinely encode the HIT/MISS scenarios their README/expected files claim
-- BEFORE any claim is made about gates/mutation_reuse.py (T-C07), the
real implementation this file MUST NOT be imported by (checked by a
control needle in the RED test's Section A; verified independent
authorship, not reverse-engineered from the real tool's source, since this
file predates it).

DEC-23 (plan.md T-C07 / research.md): re-execute a paired mutation only
when

    hash(patch || target gate script || observed inputs || tool versions)

changed. This file implements exactly that 4-component formula over the
--inputs envelope shape defined by test_mutation_reuse_red.sh's own
contract stub 2/3 (no dedicated contracts/*.md file exists for T-C07 at
the time this file was written):

    {
      "patch_sha256": "<hex64>",
      "gate_script_sha256": "<hex64>",
      "observed_inputs": [{"path": "...", "sha256": "<hex64>",
                            "recorded_mtime": "..." (OPTIONAL, IGNORED)}, ...],
      "tool_versions": {"<tool>": "<version>", ...},
      "verdict": "...",        # put-only bookkeeping -- OUTSIDE the key
      "mutation_id": "...",    # put-only bookkeeping -- OUTSIDE the key
      "gate_id": "..."         # put-only bookkeeping -- OUTSIDE the key
    }

Key components (exactly 4, per DEC-23) and what is deliberately EXCLUDED:
  1. patch_sha256          -- the mutation patch's own content hash.
  2. gate_script_sha256    -- the target gate script's own content hash.
  3. observed_inputs       -- list of {path, sha256} pairs, SORTED by path
                               (order-independent); recorded_mtime is
                               EXPLICITLY DROPPED before hashing -- content,
                               not mtime, decides (mirrors T051's VC-002
                               principle; proven non-vacuous by the RED
                               test's mr_negctrl_mtime_only fixture).
  4. tool_versions         -- dict, canonicalised via
                               json.dumps(sort_keys=True) so JSON key ORDER
                               never leaks into the digest (proven by the
                               RED test's own reorder control needle).

verdict / mutation_id / gate_id are put-time bookkeeping fields carried in
the SAME envelope for convenience but are NEVER hashed into the key --
the SURVIVED-vs-KILLED distinction is a servability rule applied AFTER key
comparison (gates/mutation_reuse.py's own job), never part of the key
itself (proven by the RED test's own named check on
mr_bad_survived_never_reused: put/get keys are IDENTICAL there, so its
expected MISS can only come from the SURVIVED-never-reused rule).

Usage: dec23_key_ref.py <envelope.json>
  Prints the 64-hex-char sha256 key to stdout, exit 0.
  Prints nothing to stdout and a short diagnostic to stderr, exit 1, on
  any malformed input (missing required field, unreadable/invalid JSON).
"""
import hashlib
import json
import sys


def build_key(envelope: dict) -> str:
    """The DEC-23 4-component key, canonicalised so JSON key/array ORDER
    never leaks into the digest and non-key fields (verdict, mutation_id,
    gate_id, per-input recorded_mtime) are never part of the preimage."""
    patch_sha256 = envelope["patch_sha256"]
    gate_script_sha256 = envelope["gate_script_sha256"]

    observed_inputs_raw = envelope.get("observed_inputs", [])
    observed_inputs = sorted(
        (
            {"path": entry["path"], "sha256": entry["sha256"]}
            for entry in observed_inputs_raw
        ),
        key=lambda entry: entry["path"],
    )

    tool_versions = envelope.get("tool_versions", {})

    canonical = {
        "patch_sha256": patch_sha256,
        "gate_script_sha256": gate_script_sha256,
        "observed_inputs": observed_inputs,
        "tool_versions": tool_versions,
    }
    # sort_keys=True canonicalises every nested dict's key order (including
    # tool_versions and each observed_inputs entry); the observed_inputs
    # LIST order was already made canonical by the sort() above (sort_keys
    # does not touch list/array element order, only dict key order).
    blob = json.dumps(canonical, sort_keys=True, separators=(",", ":")).encode(
        "utf-8"
    )
    return hashlib.sha256(blob).hexdigest()


def main(argv):
    if len(argv) != 2:
        sys.stderr.write("usage: dec23_key_ref.py <envelope.json>\n")
        return 2
    try:
        with open(argv[1], "r", encoding="utf-8") as fh:
            envelope = json.load(fh)
        key = build_key(envelope)
    except (OSError, KeyError, TypeError, json.JSONDecodeError) as exc:
        sys.stderr.write(f"dec23_key_ref.py: {exc}\n")
        return 1
    print(key)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
