#!/usr/bin/env python3
"""slicer.py - related-change batching into ordered <=slice-limit review
slices with a context pack (spec-004 "fast-dev-cycles", plan.md T-C11;
tasks.md T078; FR-023, SC-009, SC-002). Guarded by
constitution/scripts/fastcycle/tests/test_precheck_slicer_red.sh (T061),
per contract specs/004-fast-dev-cycles/contracts/review-batch-and-
precheck.md (RB-001) and data-model.md #10.2 ReviewBatch.

Invocation (contract "Invocations", verbatim):
    slicer.py --config <cfg> --changes <sha-range|list> --slice-limit <lines>
              --out <batch.json> [--determinism-check]

--config: a YAML file carrying a top-level `components: {<changed path>:
<logic group>}` mapping -- this RED test's own fixture-level definition
of the --config-driven "shared logic group" relation RB-001/DEC-06 names
(fixtures/precheck_slicer/case4_unrelated_not_batched/config.yaml),
UNCONFIRMED by the contract beyond "config-defined relation", adopted
here per the RED test's own README ("binding-if-adopted on T-C11's
implementer, per house precedent set by fixtures/verdict_cache/README.md
/fixtures/io_trace/README.md"). A changed path NOT present in the map
gets its OWN singleton group, keyed "unmapped:<path>" -- never silently
lumped with an unrelated change (constitution 11.4.6 no-guessing;
11.4.101 conservative-safe default).

--changes: a comma-separated list of paths to per-change descriptor JSON
files (the SAME RED-test README's own defined wire format for the
contract's "<sha-range|list>" grammar slot), each:
    {"change_id": "sha256:<64-hex>", "path": "<changed path>",
     "diff": "<sibling diff file, path relative to the descriptor's own
     directory>", "lines_changed": <int>}
`change_id` MUST equal the real sha256 over the sibling diff file's real
bytes -- verified here on every load, never trusted blindly (a mismatch
refuses with exit 2, constitution 11.4.6 "never a fabricated content
address").

RB-001 (batching): changes sharing a logic group land in exactly ONE
ReviewBatch; changes in different logic groups NEVER share a batch;
batching never drops a change (the union of every produced batch's
`changes` equals every input change_id -- asserted internally before
--out is written, see _partition_into_groups). Each batch's changes
(sorted by change_id -- C-003 determinism, never dict/set iteration
order) are packed into ordered slices whose cumulative lines_changed
stays <= --slice-limit; a single change whose OWN lines_changed already
exceeds --slice-limit is never dropped for that reason -- it becomes its
own oversized slice (RB-001's "never drops a change" outranks the limit,
matching R4 rec. 4's own framing of the limit as "a parameter to be
measured, not a constant").

Output (--out): ONE canonical ReviewBatch document (C-002: UTF-8, sorted
keys, no insignificant whitespace, `schema: "review-batch/v1"`,
`body_hash` excluding `run_meta`) PER LINE -- JSON Lines. A single-group
input therefore writes exactly one line, which a plain `json.load()` on
the whole file also parses correctly (one complete JSON value followed
only by trailing whitespace); a multi-group input writes one line per
group, requiring a JSON-Lines-aware reader (this RED test's own C4
checker already implements exactly that fallback: try `json.load` first,
on JSONDecodeError re-read line by line -- documented, binding-if-
adopted, per fixtures/precheck_slicer/README.md "Case 4").

Per-slice context_pack (data-model.md #10.2): `intent` and `blast_radius`
are real, factual sentences derived from the batch's OWN change paths
(never fabricated causal claims); `sibling_search_ref` is the honest
literal "UNMEASURED" -- this revision integrates no sibling-search tool
(HONEST GAP, constitution 11.4.6, matching precheck_pack_run.py's own
documented gaps for the checks it does not yet wire).

Exit: 0 = batch(es) written; 2 = usage/config error (bad args, --config
missing/malformed/not-a-mapping, a --changes entry missing/malformed/
unreadable/content-address-mismatched, --slice-limit <= 0). The contract
reserves exit 1 for "change lost" -- unreachable by construction here
(see the internal assertion in _partition_into_groups): a genuine "change
lost" defect fails LOUD as an AssertionError before any --out is written,
never as a silently-incomplete output file (constitution 11.4.6).

Determinism (C-003, FR-021): --determinism-check re-invokes this same
process twice out-of-process (matching context/governance_subset.py's own
run_determinism_check pattern) on the identical inputs, into distinct
scratch --out files, and compares the ORDERED LIST of per-line body_hash
values between the two runs (never raw file bytes -- each written
document's own `run_meta.written_at` legitimately differs between the two
runs and must not be read as nondeterminism; never a single body_hash
either -- this tool's own output can be multi-document).
"""
import argparse
import datetime
import hashlib
import json
import os
import subprocess
import sys
import tempfile

SCHEMA = "review-batch/v1"
_EXCLUDED = ("run_meta", "body_hash")


def _canon(obj):
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False)


def _body_hash_of(doc):
    body = {k: v for k, v in doc.items() if k not in _EXCLUDED}
    return hashlib.sha256(_canon(body).encode("utf-8")).hexdigest()


def load_config(path):
    if not path or not os.path.isfile(path):
        print("slicer: --config not found: %s" % path, file=sys.stderr)
        sys.exit(2)
    try:
        import yaml
    except ImportError:
        print("slicer: PyYAML is required to parse --config (pip install pyyaml)", file=sys.stderr)
        sys.exit(2)
    with open(path, encoding="utf-8") as fh:
        try:
            cfg = yaml.safe_load(fh)
        except yaml.YAMLError as exc:
            print("slicer: malformed --config %s: %s" % (path, exc), file=sys.stderr)
            sys.exit(2)
    if not isinstance(cfg, dict):
        print("slicer: --config must be a YAML mapping: %s" % path, file=sys.stderr)
        sys.exit(2)
    components = cfg.get("components")
    if components is not None and not isinstance(components, dict):
        print("slicer: --config 'components' must itself be a mapping: %s" % path, file=sys.stderr)
        sys.exit(2)
    return components or {}


def load_change(descriptor_path):
    """Loads one --changes descriptor JSON file, verifying its declared change_id
    against the REAL sha256 of its sibling diff file's REAL bytes (module docstring)."""
    if not os.path.isfile(descriptor_path):
        print("slicer: --changes entry not found: %s" % descriptor_path, file=sys.stderr)
        sys.exit(2)
    try:
        with open(descriptor_path, encoding="utf-8") as fh:
            doc = json.load(fh)
    except (OSError, ValueError) as exc:
        print("slicer: cannot read/parse change descriptor %s: %s" % (descriptor_path, exc), file=sys.stderr)
        sys.exit(2)
    if not isinstance(doc, dict):
        print("slicer: change descriptor must be a JSON object: %s" % descriptor_path, file=sys.stderr)
        sys.exit(2)

    required = ("change_id", "path", "diff", "lines_changed")
    missing = [k for k in required if k not in doc]
    if missing:
        print("slicer: change descriptor %s missing field(s): %s"
              % (descriptor_path, ", ".join(missing)), file=sys.stderr)
        sys.exit(2)

    change_id = doc["change_id"]
    if not isinstance(change_id, str) or not change_id.startswith("sha256:") or len(change_id) != 71:
        print("slicer: change descriptor %s has a malformed change_id (want sha256:<64-hex>): %r"
              % (descriptor_path, change_id), file=sys.stderr)
        sys.exit(2)

    lines_changed = doc["lines_changed"]
    if not isinstance(lines_changed, int) or isinstance(lines_changed, bool) or lines_changed < 0:
        print("slicer: change descriptor %s has a non-integer-or-negative lines_changed: %r"
              % (descriptor_path, lines_changed), file=sys.stderr)
        sys.exit(2)

    path_field = doc["path"]
    if not isinstance(path_field, str) or not path_field:
        print("slicer: change descriptor %s has a missing/empty 'path'" % descriptor_path, file=sys.stderr)
        sys.exit(2)

    diff_rel = doc["diff"]
    if not isinstance(diff_rel, str) or not diff_rel:
        print("slicer: change descriptor %s has a missing/empty 'diff'" % descriptor_path, file=sys.stderr)
        sys.exit(2)
    diff_path = os.path.join(os.path.dirname(os.path.abspath(descriptor_path)), diff_rel)
    if not os.path.isfile(diff_path):
        print("slicer: change descriptor %s names a diff file that does not exist: %s"
              % (descriptor_path, diff_path), file=sys.stderr)
        sys.exit(2)
    with open(diff_path, "rb") as fh:
        real_hash = "sha256:" + hashlib.sha256(fh.read()).hexdigest()
    if real_hash != change_id:
        print("slicer: change descriptor %s's declared change_id (%s) does not match the real "
              "sha256 of its own diff file %s (%s) -- refusing a fabricated content address "
              "(constitution 11.4.6)" % (descriptor_path, change_id, diff_path, real_hash), file=sys.stderr)
        sys.exit(2)

    return {"change_id": change_id, "path": path_field, "lines_changed": lines_changed}


def group_of(path, components):
    if path in components:
        return "logic_group:%s" % components[path]
    return "unmapped:%s" % path


def partition_into_groups(changes, components):
    """RB-001 (batching + conservation): partitions `changes` by group_of(), then
    ASSERTS every input change_id appears exactly once in the union of the produced
    groups -- a genuine "change lost" defect fails LOUD here, before --out is ever
    written (see module docstring "Exit")."""
    groups = {}
    for ch in changes:
        groups.setdefault(group_of(ch["path"], components), []).append(ch)
    all_in = sorted(c["change_id"] for c in changes)
    all_out = sorted(c["change_id"] for g in groups.values() for c in g)
    assert all_in == all_out, (
        "slicer: internal invariant violated -- a change was lost while partitioning "
        "into logic groups (RB-001 conservation)"
    )
    return groups


def make_slices(changes_sorted, slice_limit):
    """Greedy, order-preserving packing: never splits a single change across two
    slices; a change whose own lines_changed exceeds slice_limit still gets its own
    (oversized) slice rather than being dropped (module docstring)."""
    slices = []
    current = []
    current_lines = 0
    for ch in changes_sorted:
        if current and current_lines + ch["lines_changed"] > slice_limit:
            slices.append(current)
            current = []
            current_lines = 0
        current.append(ch)
        current_lines += ch["lines_changed"]
    if current:
        slices.append(current)
    return slices


def build_batch(group, changes, slice_limit):
    changes_sorted = sorted(changes, key=lambda c: c["change_id"])
    slice_groups = make_slices(changes_sorted, slice_limit)
    total_lines = sum(c["lines_changed"] for c in changes_sorted)
    change_ids = [c["change_id"] for c in changes_sorted]

    # Deterministic (C-003), content-derived batch_id -- never random, never wall-clock.
    short_hash = hashlib.sha256("|".join(change_ids).encode("utf-8")).hexdigest()[:12]
    group_label = group.split(":", 1)[1] if ":" in group else group
    batch_id = "RB-%s-%s" % (group_label, short_hash)

    slices_out = []
    for i, sl in enumerate(slice_groups, start=1):
        lines = sum(c["lines_changed"] for c in sl)
        paths = sorted({c["path"] for c in sl})
        intent = ("Slice %d/%d of %s: %d change(s) touching %s"
                  % (i, len(slice_groups), group, len(sl), ", ".join(paths)))
        blast_radius = "%d changed path(s) in this slice: %s" % (len(paths), ", ".join(paths))
        slices_out.append({
            "slice_id": "S%d" % i,
            "lines": lines,
            "context_pack": {
                "intent": intent,
                "blast_radius": blast_radius,
                "sibling_search_ref": "UNMEASURED",
            },
        })

    return {
        "batch_id": batch_id,
        "changes": change_ids,
        "related_by": group,
        "total_changed_lines": total_lines,
        "slices": slices_out,
    }


def _finalize_doc(body):
    doc = dict(body)
    doc["schema"] = SCHEMA
    doc["body_hash"] = _body_hash_of(doc)
    doc["run_meta"] = {"written_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")}
    return doc


def _write_bodies(bodies, out_path):
    lines = [_canon(_finalize_doc(b)) for b in bodies]
    data = ("\n".join(lines) + "\n").encode("utf-8")
    out_dir = os.path.dirname(os.path.abspath(out_path)) or "."
    fd, tmp = tempfile.mkstemp(dir=out_dir, prefix=".slicer.")
    try:
        with os.fdopen(fd, "wb") as fh:
            fh.write(data)
        os.replace(tmp, out_path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


# ---------------------------------------------------------------------------
# --determinism-check (C-003) -- see module docstring.
# ---------------------------------------------------------------------------
def run_determinism_check(argv, timeout_s=60):
    inner = [a for a in argv if a != "--determinism-check"]
    with tempfile.TemporaryDirectory() as tmp:
        runs = []
        for i in (1, 2):
            run_argv = list(inner)
            out_i = os.path.join(tmp, "run%d.jsonl" % i)
            if "--out" in run_argv:
                idx = run_argv.index("--out")
                run_argv[idx + 1] = out_i
            else:
                run_argv += ["--out", out_i]
            cmd_line = [sys.executable, os.path.abspath(__file__)] + run_argv
            try:
                proc = subprocess.run(cmd_line, capture_output=True, text=True, timeout=timeout_s)
            except subprocess.TimeoutExpired:
                print("slicer determinism-check: run %d timed out" % i, file=sys.stderr)
                return 4
            if proc.returncode != 0 or not os.path.exists(out_i):
                sys.stderr.write(proc.stderr)
                print("slicer determinism-check: run %d rc=%d, no honest verdict" % (i, proc.returncode),
                      file=sys.stderr)
                return 4
            with open(out_i, encoding="utf-8") as fh:
                body_hashes = [json.loads(ln).get("body_hash") for ln in fh if ln.strip()]
            runs.append(body_hashes)
    if not runs[0] or runs[0] != runs[1]:
        print("slicer determinism-check: nondeterministic: run1=%s run2=%s" % (runs[0], runs[1]),
              file=sys.stderr)
        return 1
    print("slicer determinism-check: deterministic (%d batch(es), %s)" % (len(runs[0]), runs[0]))
    return 0


def cmd_run(a):
    if a.slice_limit <= 0:
        print("slicer: --slice-limit must be a positive integer, got %d" % a.slice_limit, file=sys.stderr)
        return 2

    components = load_config(a.config)

    descriptor_paths = [c.strip() for c in a.changes.split(",") if c.strip()]
    if not descriptor_paths:
        print("slicer: --changes must name at least one change descriptor", file=sys.stderr)
        return 2

    changes = [load_change(dp) for dp in descriptor_paths]
    groups = partition_into_groups(changes, components)

    bodies = [build_batch(group, group_changes, a.slice_limit)
              for group, group_changes in sorted(groups.items())]

    try:
        _write_bodies(bodies, a.out)
    except OSError as exc:
        print("slicer: cannot write --out: %s" % exc, file=sys.stderr)
        return 2
    return 0


def main(argv):
    p = argparse.ArgumentParser(prog="slicer")
    p.add_argument("--config", required=True)
    p.add_argument("--changes", required=True)
    p.add_argument("--slice-limit", required=True, type=int)
    p.add_argument("--out", required=True)
    p.add_argument("--determinism-check", action="store_true")
    try:
        a = p.parse_args(argv)
    except SystemExit as se:
        return 2 if se.code else 0

    if a.determinism_check:
        return run_determinism_check(argv)

    return cmd_run(a)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
