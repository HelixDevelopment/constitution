#!/usr/bin/env python3
"""gate_runner_shard.py -- bounded parallel gate sharding for
gate_runner.sh's `--mode shard` (SpecKit-004 "fast-dev-cycles", User Story
2; plan.md T-C05 "Bounded parallel sharding"; tasks.md T071; SC-002,
FR-018, FR-021). Guarded by
constitution/scripts/fastcycle/tests/test_gate_shard_red.sh (T055) and its
fixtures under tests/fixtures/gate_shard/.

Invoked ONLY by ../gate_runner.sh's `--mode shard` -- not a standalone CLI
contract of its own (mirrors the gates/io_trace.sh -> gates/lib/
io_trace_parse.py split already established in this tool family, and
provides the 3 pieces ../gate_runner.sh's shell orchestration calls
directly around a real `xargs -P N` fan-out: `plan` (compute shard
assignment + write per-shard job files), `run-shard` (execute one shard's
gates SERIALLY -- an xargs worker invocation), `finalize` (merge every
shard's result, print the contract's stdout lines, compute the canonical
evidence hash).

manifest.json ("UNCONFIRMED by plan.md itself... DEFINED here, binding-if-
adopted", per test_gate_shard_red.sh's own header comment; matches every
fixture under tests/fixtures/gate_shard/):
    {"gates": [{"name": str, "script": str, "args": [str,...],
                "writes": [str,...], "reads": [str,...] (OPTIONAL, T085
                Round 1 I3 addition -- a gate omitting it behaves exactly
                as before; see _union_find_clusters()'s own docstring)},
               ...], "n_shards": int (informational
               only -- the REAL partition count is gate_runner.sh's own
               --n-shards CLI flag, since the RED test invokes the SAME
               manifest with DIFFERENT --n-shards values to compare
               "serial" (n_shards=1) against "sharded" (n_shards=3) runs)}

Sharding algorithm (plan.md line 812: "no shard writes what another
reads"; the write-set-intersection grouping rule, independently
implemented here from the SAME written contract
tests/lib/shard_ref.py uses as its OWN from-scratch reference -- producer
!= verifier, §11.4.240; the two happen to share the same union-find shape
because both follow the one written rule, not because either copied the
other):
  1. Two gates are "must-coschedule" iff their declared `writes` paths
     intersect, compared via `os.path.normpath` (never a raw string
     compare -- §11.4.201(7)(a) match-structure-not-substring discipline:
     two nominally-different-looking paths that resolve to the same file
     must still be treated as intersecting, and this tool never assumes a
     fixture's paths are already normalised).
  2. Transitive closure (union-find) -> disjoint clusters.
  3. TRACKER-DB / REGISTRY PROTECTION (this project's own extra safety
     rule, beyond the bare "no shard writes what another reads" clause --
     tasks.md T071's own text: "tracker DB and registry never written by
     gates running in parallel"): any cluster containing a gate whose
     normalised `writes` includes a path structurally ending in
     `docs/workable_items.db` or `docs/requests/agent_registry.jsonl`
     (PROTECTED_PATH_SUFFIXES below) is NEVER assigned into the parallel
     `xargs -P` batch, regardless of how many OTHER gates do or do not
     also touch that exact path -- it is placed into its own dedicated
     "serial" shard slot that ../gate_runner.sh's shell orchestration runs
     strictly AFTER the parallel phase has fully completed, one shard at a
     time, never overlapping with any other shard's execution. (The
     ordinary write-set-intersection rule from clauses 1-2 already forces
     any TWO gates that both declare the SAME protected path into one
     cluster together; this clause additionally guarantees that cluster
     never runs concurrently with anything ELSE, which the bare
     intersection rule alone does not promise for a single isolated
     protected-path gate.)
  4. Non-protected clusters are assigned to shards 0..N-1 round-robin,
     sorted by cluster id (the root gate name after union-find) for
     determinism -- never Python dict/hash-map iteration order (C-002/
     C-003). Protected clusters are appended as shard indices N, N+1, ...
     (one dedicated shard per protected cluster).
  5. A shard's own effective write set is therefore the union of its
     clusters' write sets, and by construction no two DIFFERENT shards'
     write sets ever intersect (the load-bearing invariant this tool -- as
     well as tests/lib/shard_ref.py -- exists to prove is checkable, per
     that reference's own docstring).

`script` path resolution (also UNCONFIRMED by plan.md -- DEFINED here,
binding-if-adopted): (a) if `script` is an absolute path to an existing
file, use it as-is; (b) else resolve relative to the manifest file's own
directory; (c) else resolve relative to a sibling `_shared/gates/`
directory one level up from the manifest's own directory (the established
house convention this fixture family already uses -- see
tests/fixtures/gate_shard/README.md's own `_shared/gates/` section and the
identically-shaped tests/fixtures/gate_order/_shared/ layout); (d) if none
of the above resolves to an existing file, the gate's script is genuinely
ABSENT -- a "run itself could not complete" condition for that gate (never
silently skipped, never fabricated as any verdict).

Canonical evidence hash (tests/fixtures/gate_shard/README.md "Canonical
evidence hash", also DEFINED there, binding-if-adopted):
    sha256(sorted("gate_name:VERDICT" for every gate in the manifest,
                  newline-joined))
where VERDICT is PASS (exit 0) or FAIL (nonzero exit).

Subcommands
-----------
plan --manifest <manifest.json> --n-shards <N> --out-dir <dir>
    Computes the shard assignment (clauses 1-5 above), writes
    <dir>/shard_<i>.json for every shard index 0..(n_shards + count(
    protected clusters) - 1), and <dir>/plan.json describing which shard
    indices are the "parallel" batch (0..n_shards-1, run under
    `xargs -P N`) and which are the "serial" batch (run strictly
    afterward, one at a time). Exit 0 on success, 2 on a manifest that
    cannot be read/parsed or declares zero gates.

run-shard --manifest <manifest.json> --shard-file <dir>/shard_<i>.json
          --out <dir>/result_<i>.json
    Runs every gate in that ONE shard SERIALLY, in the shard file's own
    declared order (same shard = same write cluster, so intra-shard
    concurrency would itself be exactly the race this whole mechanism
    exists to prevent). Writes {"shard", "gates", "verdicts", "errors"?}
    to --out. Always exits 0 (a per-gate resolution/execution failure is
    recorded in "errors" and simply OMITTED from "verdicts" -- detected by
    `finalize`'s own completeness check, never by this subcommand's own
    exit code, so a parallel xargs -P batch is never aborted mid-flight by
    one shard's partial failure).

finalize --result-dir <dir>
    Reads <dir>/plan.json plus every <dir>/result_<i>.json it names,
    merges every shard's "verdicts" into one verdict-set dict keyed by
    gate name. If any gate declared in the manifest never received a
    verdict (its shard's run-shard invocation never ran, or omitted it via
    "errors"), the RUN ITSELF could not complete: nothing is printed, exit
    2, naming the missing gate(s) on stderr. Otherwise prints one JSON
    line per shard-run summary (shard index order), then the final line
    `VERDICT-SET <canonical_evidence_sha256> <sorted gate:VERDICT pairs,
    space-joined>`, and exits 0.
"""
import argparse
import hashlib
import json
import os
import subprocess
import sys

EXIT_OK = 0
EXIT_USAGE = 2

GATE_TIMEOUT_SECONDS = 300  # §11.4.89: stays under the ~5min no-progress watchdog.

# tasks.md T071: "the tracker DB (docs/workable_items.db) and the agent
# registry (docs/requests/agent_registry.jsonl) must NEVER be written by
# gates running in parallel". Matched structurally (a normalised path that
# ENDS with one of these relative-path suffixes, on a path-segment
# boundary), never a bare substring (§11.4.201(7)(a)) -- so
# "some/other/docs/workable_items.db" matches (same relative tail) but
# "docs/workable_items.db.bak" does not.
PROTECTED_PATH_SUFFIXES = (
    os.path.normpath("docs/workable_items.db"),
    os.path.normpath("docs/requests/agent_registry.jsonl"),
)


def _die(prefix, msg, code=EXIT_USAGE):
    sys.stderr.write("gate_runner_shard %s: %s\n" % (prefix, msg))
    sys.exit(code)


def _is_protected(path):
    norm = os.path.normpath(path)
    for suf in PROTECTED_PATH_SUFFIXES:
        if norm == suf or norm.endswith(os.sep + suf):
            return True
    return False


def _load_manifest(path, cmd):
    if not os.path.isfile(path):
        _die(cmd, "--manifest file not found: %s" % path)
    try:
        with open(path, "r", encoding="utf-8") as fh:
            manifest = json.load(fh)
    except (OSError, json.JSONDecodeError) as exc:
        _die(cmd, "cannot parse --manifest %s: %s" % (path, exc))
    gates = manifest.get("gates")
    if not isinstance(gates, list) or not gates:
        _die(cmd, "%s declares no gates" % path)
    return manifest, gates


def _union_find_clusters(gates):
    """Returns (clusters: {root_name: [gate_name,...]}, protected_roots:
    set(root_name)) per this file's own header-comment algorithm.

    I3 fix (T085 Round 1, 2026-09-30): the pre-remediation version unioned
    ONLY write-write path intersections, contra plan.md line 812's own
    literal rule "no shard writes what another READS" and this file's own
    header-comment clause 1 (restated above the sole prior mention of the
    word). Reproduced live before this fix (§11.4.199): a gate declaring
    `writes: ["shared.txt"]` and a SEPARATE gate declaring
    `reads: ["shared.txt"]` (no writes overlap at all) landed in DIFFERENT
    shards and ran under `xargs -P` in PARALLEL -- exactly the
    reader/writer race this whole mechanism exists to prevent, since a
    manifest gate can now declare an OPTIONAL `"reads": [str, ...]` field
    (additive to the existing `"writes"` field this tool already
    consumed; a gate omitting `reads` behaves exactly as before). The
    fix: after the existing write-write union pass, a SECOND pass unions
    any gate's declared READ path with whichever OTHER gate (if any)
    declared that SAME path as a WRITE -- so a reader is always
    co-scheduled into the same cluster (and therefore the same shard) as
    that path's writer, never split across shards to run concurrently
    with it. Read-read intersections are NOT unioned (two gates that only
    ever READ the same file are not a race and may run in parallel, per
    the same "no shard writes what another reads" rule -- writes are the
    hazard, not reads)."""
    parent = {g["name"]: g["name"] for g in gates}

    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[ra] = rb

    write_owner = {}
    protected_names = set()
    for g in gates:
        for raw_path in g.get("writes", []):
            path = os.path.normpath(raw_path)
            if _is_protected(path):
                protected_names.add(g["name"])
            if path in write_owner:
                union(g["name"], write_owner[path])
            else:
                write_owner[path] = g["name"]

    # I3 fix: write-vs-read union pass -- a gate that READS a path another
    # gate WRITES must co-schedule with that writer (never split across
    # shards). This pass runs strictly AFTER every write-write union above
    # has completed, so `write_owner` already reflects every writer's
    # FINAL cluster membership before any reader is folded in.
    for g in gates:
        for raw_path in g.get("reads", []):
            path = os.path.normpath(raw_path)
            owner = write_owner.get(path)
            if owner is not None and owner != g["name"]:
                union(g["name"], owner)
            if owner is not None and _is_protected(path):
                # A reader of a PROTECTED path (tracker DB / agent
                # registry) is swept into the same protected treatment as
                # its writer -- see protected_roots computation below,
                # which runs AFTER this pass so `find()` reflects the
                # read-write union too.
                protected_names.add(g["name"])

    clusters = {}
    for g in gates:
        root = find(g["name"])
        clusters.setdefault(root, []).append(g["name"])

    protected_roots = {find(n) for n in protected_names}
    return clusters, protected_roots


def _assign_shards(clusters, protected_roots, n_shards):
    """Non-protected clusters round-robin across shards 0..n_shards-1;
    each protected cluster gets its OWN dedicated shard index appended at
    n_shards, n_shards+1, ... Returns {shard_index: [gate_name,...]}
    (every index 0..n_shards-1 present, possibly empty)."""
    n_shards = max(1, n_shards)
    cluster_ids = sorted(clusters.keys())
    normal_ids = [c for c in cluster_ids if c not in protected_roots]
    protected_ids = [c for c in cluster_ids if c in protected_roots]

    shards = {i: [] for i in range(n_shards)}
    for i, cid in enumerate(normal_ids):
        shard_idx = i % n_shards
        shards[shard_idx].extend(sorted(clusters[cid]))

    serial_base = n_shards
    for j, cid in enumerate(protected_ids):
        shard_idx = serial_base + j
        shards[shard_idx] = sorted(clusters[cid])

    return shards, list(range(n_shards)), list(range(serial_base, serial_base + len(protected_ids)))


def resolve_script(manifest_path, script_rel):
    """script resolution per this file's own header-comment rule (a),(b),(c)."""
    if os.path.isabs(script_rel) and os.path.isfile(script_rel):
        return script_rel
    manifest_dir = os.path.dirname(os.path.abspath(manifest_path))
    cand1 = os.path.join(manifest_dir, script_rel)
    if os.path.isfile(cand1):
        return cand1
    cand2 = os.path.normpath(os.path.join(manifest_dir, "..", "_shared", "gates", script_rel))
    if os.path.isfile(cand2):
        return cand2
    return None


def cmd_plan(a):
    manifest, gates = _load_manifest(a.manifest, "plan")
    if a.n_shards < 1:
        _die("plan", "--n-shards must be >= 1: %d" % a.n_shards)

    clusters, protected_roots = _union_find_clusters(gates)
    shards, parallel, serial = _assign_shards(clusters, protected_roots, a.n_shards)

    os.makedirs(a.out_dir, exist_ok=True)
    gate_by_name = {g["name"]: g for g in gates}
    for idx, names in shards.items():
        shard_doc = {
            "shard": idx,
            "gates": [
                {
                    "name": n,
                    "script": gate_by_name[n]["script"],
                    "args": gate_by_name[n].get("args", []),
                }
                for n in names
            ],
        }
        with open(os.path.join(a.out_dir, "shard_%d.json" % idx), "w", encoding="utf-8") as fh:
            json.dump(shard_doc, fh, sort_keys=True)

    plan_doc = {
        "manifest": os.path.abspath(a.manifest),
        "n_shards_requested": a.n_shards,
        "n_shards_total": len(shards),
        "parallel_shards": parallel,
        "serial_shards": serial,
        "all_gate_names": sorted(g["name"] for g in gates),
    }
    with open(os.path.join(a.out_dir, "plan.json"), "w", encoding="utf-8") as fh:
        json.dump(plan_doc, fh, sort_keys=True)
    print(json.dumps(plan_doc, sort_keys=True))
    return EXIT_OK


def cmd_run_shard(a):
    if not os.path.isfile(a.shard_file):
        _die("run-shard", "--shard-file not found: %s" % a.shard_file)
    with open(a.shard_file, "r", encoding="utf-8") as fh:
        shard_doc = json.load(fh)

    verdicts = {}
    errors = {}
    for g in shard_doc.get("gates", []):
        name = g["name"]
        script_path = resolve_script(a.manifest, g["script"])
        if script_path is None:
            errors[name] = "gate script not found (tried manifest-dir-relative and " \
                            "sibling _shared/gates/-relative resolution): %s" % g["script"]
            continue
        cmd = ["sh", script_path] + [str(x) for x in g.get("args", [])]
        try:
            proc = subprocess.run(cmd, capture_output=True, timeout=GATE_TIMEOUT_SECONDS)
            verdicts[name] = "PASS" if proc.returncode == 0 else "FAIL"
        except subprocess.TimeoutExpired:
            errors[name] = "gate run timed out after %ss" % GATE_TIMEOUT_SECONDS
        except OSError as exc:
            errors[name] = "gate run failed: %s" % exc

    result_doc = {
        "shard": shard_doc.get("shard"),
        "gates": [g["name"] for g in shard_doc.get("gates", [])],
        "verdicts": verdicts,
    }
    if errors:
        result_doc["errors"] = errors
    with open(a.out, "w", encoding="utf-8") as fh:
        json.dump(result_doc, fh, sort_keys=True)
    return EXIT_OK


def cmd_finalize(a):
    plan_path = os.path.join(a.result_dir, "plan.json")
    if not os.path.isfile(plan_path):
        _die("finalize", "no plan.json under --result-dir %s" % a.result_dir)
    with open(plan_path, "r", encoding="utf-8") as fh:
        plan_doc = json.load(fh)

    all_names = set(plan_doc["all_gate_names"])
    n_total = plan_doc["n_shards_total"]

    shard_summaries = []
    verdict_set = {}
    for i in range(n_total):
        rf = os.path.join(a.result_dir, "result_%d.json" % i)
        if not os.path.isfile(rf):
            continue
        with open(rf, "r", encoding="utf-8") as fh:
            rd = json.load(fh)
        shard_summaries.append(rd)
        for name, v in rd.get("verdicts", {}).items():
            verdict_set[name] = v

    missing = sorted(all_names - set(verdict_set.keys()))
    if missing:
        sys.stderr.write(
            "gate_runner_shard finalize: the run could not complete -- the "
            "following gate(s) never produced a verdict: %s\n" % ", ".join(missing)
        )
        return EXIT_USAGE

    for s in shard_summaries:
        print(json.dumps(s, sort_keys=True))

    lines = sorted("%s:%s" % (n, v) for n, v in verdict_set.items())
    canonical = "\n".join(lines)
    digest = hashlib.sha256(canonical.encode("utf-8")).hexdigest()
    print("VERDICT-SET %s %s" % (digest, " ".join(lines)))
    return EXIT_OK


def main(argv):
    p = argparse.ArgumentParser(add_help=False)
    sub = p.add_subparsers(dest="cmd", required=True)

    pl = sub.add_parser("plan")
    pl.add_argument("--manifest", required=True)
    pl.add_argument("--n-shards", required=True, type=int)
    pl.add_argument("--out-dir", required=True)

    rs = sub.add_parser("run-shard")
    rs.add_argument("--manifest", required=True)
    rs.add_argument("--shard-file", required=True)
    rs.add_argument("--out", required=True)

    fz = sub.add_parser("finalize")
    fz.add_argument("--result-dir", required=True)

    try:
        a = p.parse_args(argv)
    except SystemExit:
        sys.exit(EXIT_USAGE)

    table = {"plan": cmd_plan, "run-shard": cmd_run_shard, "finalize": cmd_finalize}
    sys.exit(table[a.cmd](a))


if __name__ == "__main__":
    main(sys.argv[1:])
