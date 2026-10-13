#!/usr/bin/env python3
"""Reference sharder for T055's test_gate_shard_red.sh (SpecKit-004,
plan.md T-C05: "shards built from T-C02 write sets (no shard writes what
another reads)").

Producer != Verifier (§11.4.240): this is THIS TEST FILE's own,
independently-authored implementation of the write-set-intersection
grouping rule stated in plan.md line 812 ("no shard writes what another
reads") and the golden-bad Protecting Test (line 819: "a planted section
pair sharing a temp file must be placed in one shard"). It is used ONLY to
prove the gs_bad_shared_temp_split/ and gs_negctrl_disjoint_temp/ fixtures
under fixtures/gate_shard/ are non-vacuous BEFORE any claim is made about
what the (today, absent) real gates/gate_runner.sh should do with them. It
never claims to BE gate_runner.sh's sharding algorithm, and it never seeds
or informs a future implementer's own code (this ordering -- reference
computed before the implementation exists -- is what makes the self-check
meaningful, exactly the T051 dec07_key_ref.py precedent).

Algorithm (the minimal correct rule the contract states -- union-find over
write-set intersection, deterministic round-robin cluster-to-shard
assignment):
  1. Two gates are "must-cosschedule" iff their declared write sets
     intersect (share >=1 path).
  2. Compute the transitive closure of must-cosschedule (union-find) ->
     disjoint clusters, each cluster's own union write-set.
  3. Assign clusters to N shards round-robin, sorted by cluster id for
     determinism (a real implementation may load-balance by cost; this
     reference only needs to prove co-scheduling correctness, not
     load-balance quality -- the contract does not name a load-balance
     assertion).
  4. A shard's own effective write set is the union of its clusters' write
     sets; by construction no two DIFFERENT shards' write sets intersect
     (the load-bearing invariant this reference proves is checkable).

CLI: shard_ref.py <manifest.json> <n_shards>
  manifest.json: {"gates": [{"name": str, "writes": [str, ...]}, ...]}
Output (stdout): JSON {"shards": [[gate_name, ...], ...], "shard_of": {gate_name: shard_index}}
Exit: 0 always (this is a pure reference computation, not a pass/fail check
-- the CALLER in test_gate_shard_red.sh asserts on the output).
"""
import json
import sys


def union_find_clusters(gates):
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
    for g in gates:
        for path in g["writes"]:
            if path in write_owner:
                union(g["name"], write_owner[path])
            else:
                write_owner[path] = g["name"]

    clusters = {}
    for g in gates:
        root = find(g["name"])
        clusters.setdefault(root, []).append(g["name"])
    return clusters


def assign_shards(clusters, n_shards):
    n_shards = max(1, n_shards)
    cluster_ids = sorted(clusters.keys())
    shards = [[] for _ in range(n_shards)]
    shard_of = {}
    for i, cid in enumerate(cluster_ids):
        shard_idx = i % n_shards
        for name in sorted(clusters[cid]):
            shards[shard_idx].append(name)
            shard_of[name] = shard_idx
    return shards, shard_of


def main():
    if len(sys.argv) != 3:
        print("usage: shard_ref.py <manifest.json> <n_shards>", file=sys.stderr)
        return 2
    with open(sys.argv[1]) as f:
        manifest = json.load(f)
    n_shards = int(sys.argv[2])
    clusters = union_find_clusters(manifest["gates"])
    shards, shard_of = assign_shards(clusters, n_shards)
    print(json.dumps({"shards": shards, "shard_of": shard_of}))
    return 0


if __name__ == "__main__":
    sys.exit(main())
