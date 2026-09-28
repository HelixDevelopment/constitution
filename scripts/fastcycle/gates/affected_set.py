#!/usr/bin/env python3
"""affected_set.py - sound affected-gate selection + skip-list emitter
(spec-004 "fast-dev-cycles", User Story 2; plan.md T-C03; tasks.md T069;
FR-005, SC-002). Guarded by
constitution/scripts/fastcycle/tests/test_affected_set_red.sh (T053), per
contract specs/004-fast-dev-cycles/contracts/affected-set-and-verdict-cache.md
(clauses AS-010, AS-010a, AS-011, AS-012).

Invocation (per T053's RED test, the binding contract -- see the honest
gaps noted below):
  affected_set.py --config <cfg> --base <sha> --head <sha|WORKTREE>
                   --map <map.json> --layer <layer> --out <affected.json>
                   --repo <repo-dir>

Given a change (base..head, or base..WORKTREE for an uncommitted edit),
decide SOUNDLY which gates in <map.json> must run:

  - AS-010a (self-change): a gate whose OWN script (gates/<gate_id>.sh)
    is among the changed paths is unconditionally a member.
  - Observed-input match: a gate whose observed_inputs intersects the
    changed paths is a member.
  - AS-012 (docs-only, derived): when every changed path maps only to
    doc-layer (layer=="docs") gates, change_class="docs-only" and every
    NON-doc-layer gate is skipped with LAYER_NOT_APPLICABLE instead of
    the generic NO_OBSERVED_INPUT_CHANGED.
  - Every other mapped gate is skipped with NO_OBSERVED_INPUT_CHANGED.

Soundness beats speed (AS-010): "any doubt => full applicable suite" --
determinable=false whenever ANY of the following holds, and members
becomes the FULL gate set in <map.json> (skipped=[]), with an exact
fallback_reason naming the first triggering condition:
  - AS-003 (stale map): the REAL current sha256 of some gate's OWN
    script file, read AT <base> (never at head/worktree -- a
    self-change is a positive inclusion signal, not a trust failure;
    see the "why base, not head" note below), does not match that
    gate's content_hash in <map.json>.
  - AS-001/AS-010 (unsound inputs): any gate's map entry carries a
    non-empty undeclared_reads list (INPUTS_UNSOUND).
  - AS-010 (unmapped path): a changed path is neither any gate's own
    script path NOR in any gate's observed_inputs (DEC-08 union rule).
  - The diff itself could not be computed (git failure).

Exit codes: 0 = determinable set emitted; 4 = full-suite FALLBACK
emitted (still writes --out; §11.4.201 conservative-safe-default, never
a silent narrower guess); 2 = usage error.

HONEST GAP vs the contract's prose (specs/004-fast-dev-cycles/contracts/
affected-set-and-verdict-cache.md line 55, §11.4.6 no-guessing -- this is
a genuine discrepancy between the contract's PROSE and its own RED
FIXTURES, not silently resolved either way): the contract text says
affected_set.py exits 0 for "determinable or fallback" and reserves exit
4 for "diff unreadable" specifically. T053's RED test's own fixtures
(as_bad_unmapped_path, as_bad_undeclared_read, as_bad_stale_map) pin
expected_exit_code=4 for EVERY determinable=false case, not only a
diff-read failure. This implementation matches the RED TEST (the
mechanically-checked, authoritative artifact per its own header
comment), not the narrower contract prose -- flagged here for a future
task to reconcile the contract wording, never silently "fixed" by this
implementer (producer != contract-author, §11.4.240).

HONEST GAP: --repo is required by the RED test's real invocations but is
NOT listed in the contract's own "Components and invocations" block
(line 21) -- accepted here as a required arg (the git working directory
--base/--head resolve against) since the RED test cannot pass without it.

Why the AS-003 staleness check reads a gate's own script content AT
<base>, never at <head>/WORKTREE: as_selfchange's fixture edits
gates/gate_gamma.sh itself (changed_paths=["gates/gate_gamma.sh"]) and
still expects determinable=true -- if staleness were checked against the
HEAD content, that fixture's own edit would falsely trip AS-003. Reading
at <base> (the commit the map claims to represent) correctly separates
"the map is stale/wrong" (AS-003, a trust failure over the WHOLE map)
from "this gate's own script changed in this diff" (AS-010a, a positive
per-gate inclusion signal) -- confirmed self-consistent against
as_bad_stale_map, whose planted-wrong content_hash is wrong even at
<base> (independent of what changed in this particular diff).
"""
import argparse
import hashlib
import json
import subprocess
import sys


def parse_args(argv):
    p = argparse.ArgumentParser(add_help=False)
    p.add_argument("--config", required=True)
    p.add_argument("--base", required=True)
    p.add_argument("--head", required=True)
    p.add_argument("--map", required=True)
    p.add_argument("--layer", required=True)
    p.add_argument("--out", required=True)
    p.add_argument("--repo", required=True)
    try:
        return p.parse_args(argv)
    except SystemExit:
        # argparse already wrote a usage message to stderr; normalise to
        # the contract's own usage-error exit code (2) -- argparse's
        # default is already 2, but state it explicitly (§11.4.6).
        sys.exit(2)


def git_diff_paths(repo, base, head):
    """Returns the sorted list of paths changed between base and head (or
    base and the current WORKTREE when head == "WORKTREE"), or None if
    the diff could not be computed (AS-010's 'diff cannot be computed'
    trigger)."""
    if head == "WORKTREE":
        cmd = ["git", "-C", repo, "diff", "--name-only", base]
    else:
        cmd = ["git", "-C", repo, "diff", "--name-only", base, head]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if out.returncode != 0:
        return None
    return sorted(p for p in out.stdout.splitlines() if p)


def git_show_bytes(repo, ref, path):
    """Returns the raw bytes of <path> at <ref>, or None if unreadable
    (a gate script that does not exist at base, or a repo/ref error)."""
    cmd = ["git", "-C", repo, "show", "%s:%s" % (ref, path)]
    try:
        out = subprocess.run(cmd, capture_output=True, timeout=30)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if out.returncode != 0:
        return None
    return out.stdout


def sha256_hex(data):
    return hashlib.sha256(data).hexdigest()


def main(argv):
    a = parse_args(argv)

    try:
        with open(a.map, "r", encoding="utf-8") as fh:
            gate_map = json.load(fh)
    except (OSError, json.JSONDecodeError) as exc:
        sys.stderr.write("affected_set: cannot read/parse --map %s: %s\n" % (a.map, exc))
        sys.exit(2)

    gates = gate_map.get("gates", {})
    all_gate_ids = sorted(gates.keys())

    changed_paths = git_diff_paths(a.repo, a.base, a.head)
    diff_unreadable = changed_paths is None
    if diff_unreadable:
        changed_paths = []
    changed_set = set(changed_paths)

    # --- AS-003: stale-map check -- a gate's OWN script content AT
    #     <base> must match its map-recorded content_hash. A path
    #     mismatch/unreadable-at-base is ALSO treated as stale (the
    #     map's claim cannot be verified, same untrusted-map outcome).
    stale_gate = None
    for gate_id in all_gate_ids:
        entry = gates[gate_id]
        script_path = "gates/%s.sh" % gate_id
        real_bytes = git_show_bytes(a.repo, a.base, script_path)
        if real_bytes is None:
            stale_gate = gate_id
            break
        real_hash = sha256_hex(real_bytes)
        if real_hash != entry.get("content_hash"):
            stale_gate = gate_id
            break

    # --- AS-001/AS-010: INPUTS_UNSOUND -- any gate with a non-empty
    #     undeclared_reads list poisons trust in the whole map.
    unsound_gate = None
    for gate_id in all_gate_ids:
        if gates[gate_id].get("undeclared_reads"):
            unsound_gate = gate_id
            break

    # --- AS-010 (DEC-08 union rule): a changed path is "mapped" if it
    #     is some gate's own script path OR appears in some gate's
    #     observed_inputs; the first UNMAPPED changed path triggers the
    #     fallback (first-encountered, sorted order, so the result is
    #     deterministic across repeated runs -- as_determinism).
    self_paths = {"gates/%s.sh" % gid for gid in all_gate_ids}
    mapped_paths = set(self_paths)
    for gate_id in all_gate_ids:
        mapped_paths.update(gates[gate_id].get("observed_inputs", []))
    unmapped_path = None
    for p in changed_paths:
        if p not in mapped_paths:
            unmapped_path = p
            break

    determinable = not (diff_unreadable or stale_gate or unsound_gate or unmapped_path)

    result = {}
    exit_code = 0

    if not determinable:
        if diff_unreadable:
            reason = "affected-set undeterminable: diff could not be computed (base=%s head=%s)" % (a.base, a.head)
        elif unmapped_path is not None:
            reason = "affected-set undeterminable: %s" % unmapped_path
        elif unsound_gate is not None:
            reason = "affected-set undeterminable: gate %s is INPUTS_UNSOUND (undeclared_reads present)" % unsound_gate
        else:
            reason = "affected-set undeterminable: map entry for gate %s does not match its script's real content at base %s (AS-003 stale map)" % (stale_gate, a.base)
        result = {
            "determinable": False,
            "members": all_gate_ids,
            "skipped": [],
            "fallback_reason": reason,
        }
        exit_code = 4
    else:
        members = set()
        for gate_id in all_gate_ids:
            if ("gates/%s.sh" % gate_id) in changed_set:
                members.add(gate_id)
        for gate_id in all_gate_ids:
            if gate_id in members:
                continue
            observed = set(gates[gate_id].get("observed_inputs", []))
            if observed & changed_set:
                members.add(gate_id)

        # AS-012 (docs-only, derived): every changed path maps ONLY to
        # doc-layer (layer=="docs") gates -- i.e. no changed path is
        # (a) a non-doc gate's own script, nor (b) a non-doc gate's
        # observed_input. An empty changed_set is never "docs-only"
        # (there is nothing to derive it from).
        change_class = None
        if changed_set:
            touches_non_doc = False
            for gate_id in all_gate_ids:
                if gates[gate_id].get("layer") == "docs":
                    continue
                if ("gates/%s.sh" % gate_id) in changed_set:
                    touches_non_doc = True
                    break
                if set(gates[gate_id].get("observed_inputs", [])) & changed_set:
                    touches_non_doc = True
                    break
            if not touches_non_doc:
                change_class = "docs-only"

        skipped = []
        for gate_id in all_gate_ids:
            if gate_id in members:
                continue
            if change_class == "docs-only" and gates[gate_id].get("layer") != "docs":
                skipped.append({"gate_id": gate_id, "reason_code": "LAYER_NOT_APPLICABLE"})
            else:
                skipped.append({"gate_id": gate_id, "reason_code": "NO_OBSERVED_INPUT_CHANGED"})
        skipped.sort(key=lambda e: e["gate_id"])

        result = {
            "determinable": True,
            "members": sorted(members),
            "skipped": skipped,
            "fallback_reason": None,
        }
        if change_class is not None:
            result["change_class"] = change_class
        exit_code = 0

    result["layer"] = a.layer
    try:
        with open(a.out, "w", encoding="utf-8") as fh:
            json.dump(result, fh, sort_keys=True, indent=2)
            fh.write("\n")
    except OSError as exc:
        sys.stderr.write("affected_set: cannot write --out %s: %s\n" % (a.out, exc))
        sys.exit(2)

    sys.exit(exit_code)


if __name__ == "__main__":
    main(sys.argv[1:])
