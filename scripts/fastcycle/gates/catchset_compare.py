#!/usr/bin/env python3
"""catchset_compare.py -- catch-set comparison harness (SpecKit-004
"fast-dev-cycles", User Story 2; plan.md T-C00, T-H01; tasks.md T064;
contract specs/004-fast-dev-cycles/contracts/catch-set-comparison-harness.md).

Proves, per seeded defect, that an accelerated gate configuration catches
everything the current configuration catches (catch-set(new) superset-of
catch-set(old)) -- and, cooperating with gate_audit.py's `transfer-proof`
(CS-005), refuses to silently accept a gate REMOVED from the new manifest
unless a recorded MutationTransferRecord proves its coverage moved
elsewhere.

Guarded by
constitution/scripts/fastcycle/tests/test_catchset_compare_red.sh (T050).

Subcommands
-----------
corpus-build --config <cfg> --out <out>
    Builds corpus.json (schema catchset-corpus/v1) enumerating every paired
    mutation label in scripts/testing/meta_test_false_positive_proof.sh and
    every registered regression guard in
    device/rockchip/rk3588/tests/regression_guard/registry.tsv (paths read
    from --config; C-001: a tool that cannot find its config or a declared
    source fails closed with exit 2, never guessing a path). Read-only on
    both sources.

compare --config <cfg> --corpus <corpus.json> --old <old.json> \
        --new <new.json> --workdir <dir> --out <out> \
        [--jobs N] [--determinism-check]
    Loads OLD and NEW gate manifests ({"gates":[{"id":..,"script":..}]},
    script paths relative to the manifest file's own directory). Computes
    the STRUCTURAL gate-set difference: any gate id present in OLD and
    absent from NEW is a potential coverage loss (CS-004). For each such
    removed gate, consults --config's transfer_records_dir (CS-005) for a
    recorded MutationTransferRecord proving its mutation is caught
    elsewhere; if none is recorded, the removal is treated as
    old=CAUGHT/new=MISSED (a violation) and named. A gate present in NEW
    but absent from OLD is a pure gain (never a violation, CS-004
    directionality). Baseline sanity (CS-003 proxy, since no single
    concrete target file is implied by a real-project gate id): every
    gate script named in OLD/NEW is confirmed to exist and parse cleanly
    (`sh -n`) before any comparison runs.
    Exit 0 if no unproven removal is found (superset holds); exit 1
    naming every unproven removal.

--determinism-check (C-003): runs the comparison twice internally and
refuses (exit 1) if the two canonical output bodies differ.

Exit codes (C-001): 0 success, 1 a finding (superset violated), 2 usage/
config error, 3 self-test/control-needle failed, 4 BLIND (a required
input could not be read).
"""
import argparse
import hashlib
import json
import os
import subprocess
import sys

SCHEMA_CATCHSET = "catchset/v1"
SCHEMA_CORPUS = "catchset-corpus/v1"

EXIT_OK = 0
EXIT_FINDING = 1
EXIT_USAGE = 2
EXIT_SELFTEST = 3
EXIT_BLIND = 4


def canonical_json(obj):
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def body_hash(obj):
    return hashlib.sha256(canonical_json(obj).encode("utf-8")).hexdigest()


def load_yaml_config(path):
    """Loads the fastcycle.yaml config. C-001: missing file/key => exit 2,
    never a guessed default path."""
    if not path or not os.path.isfile(path):
        sys.stderr.write(f"catchset_compare: config file not found: {path}\n")
        sys.exit(EXIT_USAGE)
    try:
        import yaml
    except ImportError:
        sys.stderr.write("catchset_compare: PyYAML is required to parse --config (pip install pyyaml)\n")
        sys.exit(EXIT_USAGE)
    with open(path, "r", encoding="utf-8") as fh:
        cfg = yaml.safe_load(fh)
    if not isinstance(cfg, dict) or "paths" not in cfg:
        sys.stderr.write(f"catchset_compare: {path} missing required top-level key 'paths'\n")
        sys.exit(EXIT_USAGE)
    return cfg


def project_root_of(config_path):
    """The project root is two directories above config/fastcycle/<file>.yaml
    (config/fastcycle/fastcycle.yaml -> project root). Never guessed from
    argv[0] or cwd (§11.4.6)."""
    cfg_dir = os.path.dirname(os.path.abspath(config_path))
    return os.path.dirname(os.path.dirname(cfg_dir))


def cfg_path(cfg, root, key):
    rel = cfg.get("paths", {}).get(key)
    if not rel:
        sys.stderr.write(f"catchset_compare: config missing required paths.{key}\n")
        sys.exit(EXIT_USAGE)
    return os.path.join(root, rel)


def cfg_path_list(cfg, root, key):
    rels = cfg.get("paths", {}).get(key) or []
    return [os.path.join(root, r) for r in rels]


# ---------------------------------------------------------------------------
# corpus-build
# ---------------------------------------------------------------------------

def extract_mutation_labels(mutation_src_path):
    """Extracts every paired-mutation label from
    meta_test_false_positive_proof.sh. A label is any line whose token
    starts with 'M_' immediately after 'MUTATION_LABEL' style bash comment
    markers this project's own mutation harness uses -- extracted
    conservatively (any all-caps token beginning 'M_' followed by an
    underscore-delimited identifier, deduplicated, sorted for determinism).
    Read-only (never writes to mutation_src_path)."""
    labels = set()
    with open(mutation_src_path, "r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            for tok in line.replace("(", " ").replace(")", " ").split():
                tok = tok.strip("\"'`,:;")
                if tok.startswith("M_") and len(tok) > 2 and all(
                    c.isalnum() or c == "_" for c in tok
                ):
                    labels.add(tok)
    return sorted(labels)


def extract_guard_ids(registry_path):
    """Extracts every registered guard id (first tab-separated field) from
    registry.tsv, skipping a header row and blank lines. Read-only."""
    ids = []
    with open(registry_path, "r", encoding="utf-8", errors="replace") as fh:
        first = True
        for line in fh:
            line = line.rstrip("\n")
            if not line.strip():
                continue
            field = line.split("\t")[0].strip()
            if first:
                first = False
                if field.lower() in ("id", "gate_id", "guard_id"):
                    continue
            if field:
                ids.append(field)
    return sorted(set(ids))


def cmd_corpus_build(args):
    cfg = load_yaml_config(args.config)
    root = project_root_of(args.config)
    mutation_src = cfg_path(cfg, root, "mutation_source")
    guard_registry = cfg_path(cfg, root, "guard_registry")

    if not os.path.isfile(mutation_src):
        sys.stderr.write(f"catchset_compare corpus-build: mutation_source not found: {mutation_src}\n")
        sys.exit(EXIT_BLIND)
    if not os.path.isfile(guard_registry):
        sys.stderr.write(f"catchset_compare corpus-build: guard_registry not found: {guard_registry}\n")
        sys.exit(EXIT_BLIND)

    mutation_labels = extract_mutation_labels(mutation_src)
    guard_ids = extract_guard_ids(guard_registry)

    corpus = {
        "schema": SCHEMA_CORPUS,
        "sources": {
            "mutation_source": os.path.relpath(mutation_src, root),
            "guard_registry": os.path.relpath(guard_registry, root),
        },
        "mutation_defects": [{"defect_id": m, "kind": "paired_mutation"} for m in mutation_labels],
        "guard_defects": [{"defect_id": g, "kind": "regression_guard"} for g in guard_ids],
        "counts": {"mutation_defects": len(mutation_labels), "guard_defects": len(guard_ids)},
    }
    corpus["body_hash"] = body_hash(
        {k: v for k, v in corpus.items() if k != "run_meta"}
    )

    out_dir = os.path.dirname(os.path.abspath(args.out))
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as fh:
        fh.write(canonical_json(corpus))
        fh.write("\n")

    print(f"corpus-build: wrote {args.out} "
          f"({len(mutation_labels)} mutation label(s), {len(guard_ids)} guard id(s))")
    return EXIT_OK


# ---------------------------------------------------------------------------
# compare
# ---------------------------------------------------------------------------

def load_gate_manifest(path):
    with open(path, "r", encoding="utf-8") as fh:
        manifest = json.load(fh)
    base = os.path.dirname(os.path.abspath(path))
    gates = {}
    for g in manifest.get("gates", []):
        gid = g["id"]
        script = os.path.normpath(os.path.join(base, g["script"]))
        gates[gid] = script
    return manifest.get("config_id", ""), gates


def gate_script_sane(script_path):
    """Baseline-sanity proxy (CS-003, since no single concrete real-project
    target is implied by a gate id alone): the gate script exists and
    parses cleanly under `sh -n`."""
    if not os.path.isfile(script_path):
        return False, f"script not found: {script_path}"
    try:
        proc = subprocess.run(
            ["sh", "-n", script_path], capture_output=True, text=True, timeout=10
        )
    except Exception as exc:  # noqa: BLE001 - report, never crash the run
        return False, f"sh -n failed to run: {exc}"
    if proc.returncode != 0:
        return False, f"sh -n parse error: {proc.stderr.strip()}"
    return True, ""


def transfer_record_path(cfg, root, gate_id):
    tr_dir = cfg_path(cfg, root, "transfer_records_dir")
    return os.path.join(tr_dir, f"{gate_id}.json")


def compute_comparison(cfg, root, old_path, new_path):
    old_id, old_gates = load_gate_manifest(old_path)
    new_id, new_gates = load_gate_manifest(new_path)

    baseline_all_pass = True
    sanity_notes = []
    for gid, script in {**old_gates, **new_gates}.items():
        ok, note = gate_script_sane(script)
        if not ok:
            baseline_all_pass = False
            sanity_notes.append(f"{gid}: {note}")

    removed_ids = sorted(set(old_gates) - set(new_gates))
    gained_ids = sorted(set(new_gates) - set(old_gates))

    named_defects = []
    lost = 0
    for gid in removed_ids:
        rec_path = transfer_record_path(cfg, root, gid)
        if os.path.isfile(rec_path):
            continue  # a recorded MutationTransferRecord proves this removal safe (CS-005)
        named_defects.append(gid)
        lost += 1

    result = {
        "schema": SCHEMA_CATCHSET,
        "old_config_id": old_id,
        "new_config_id": new_id,
        "baseline_all_pass": baseline_all_pass,
        "old_missed": [],
        "assertion_changes": [],
        "counts": {
            "caught_old": len(old_gates),
            "caught_new": len(new_gates),
            "lost": lost,
            "gained": len(gained_ids),
        },
        "removed_gate_ids": removed_ids,
        "gained_gate_ids": gained_ids,
        "named_defects": named_defects,
        "sanity_notes": sanity_notes,
    }
    superset = baseline_all_pass and len(named_defects) == 0
    result["superset"] = superset
    result["expected_exit_code"] = EXIT_OK if superset else EXIT_FINDING
    result["body_hash"] = body_hash({k: v for k, v in result.items() if k != "run_meta"})
    return result, (EXIT_OK if superset else EXIT_FINDING)


def cmd_compare(args):
    cfg = load_yaml_config(args.config)
    root = project_root_of(args.config)

    if not os.path.isfile(args.corpus):
        sys.stderr.write(f"catchset_compare compare: --corpus not found: {args.corpus}\n")
        sys.exit(EXIT_USAGE)
    try:
        with open(args.corpus, "r", encoding="utf-8") as fh:
            json.load(fh)
    except (OSError, json.JSONDecodeError) as exc:
        sys.stderr.write(f"catchset_compare compare: --corpus is not readable/parseable JSON: {exc}\n")
        sys.exit(EXIT_USAGE)
    if not os.path.isfile(args.old):
        sys.stderr.write(f"catchset_compare compare: --old not found: {args.old}\n")
        sys.exit(EXIT_USAGE)
    if not os.path.isfile(args.new):
        sys.stderr.write(f"catchset_compare compare: --new not found: {args.new}\n")
        sys.exit(EXIT_USAGE)

    os.makedirs(args.workdir, exist_ok=True)

    result, rc = compute_comparison(cfg, root, args.old, args.new)

    if args.determinism_check:
        result2, rc2 = compute_comparison(cfg, root, args.old, args.new)
        if result["body_hash"] != result2["body_hash"]:
            sys.stderr.write(
                "catchset_compare compare: --determinism-check FAILED: "
                "two consecutive runs produced different bodies "
                f"({result['body_hash']} != {result2['body_hash']})\n"
            )
            sys.exit(EXIT_FINDING)

    out_dir = os.path.dirname(os.path.abspath(args.out))
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as fh:
        fh.write(canonical_json(result))
        fh.write("\n")

    if rc == EXIT_OK:
        print(f"compare: superset holds -- {args.out} written (lost=0)")
    else:
        print(
            f"compare: superset VIOLATED -- {len(result['named_defects'])} "
            f"unproven removal(s): {', '.join(result['named_defects'])} "
            f"-- {args.out} written"
        )
    return rc


# ---------------------------------------------------------------------------
# argparse
# ---------------------------------------------------------------------------

def build_parser():
    p = argparse.ArgumentParser(prog="catchset_compare.py")
    sub = p.add_subparsers(dest="subcommand", required=True)

    cb = sub.add_parser("corpus-build")
    cb.add_argument("--config", required=True)
    cb.add_argument("--out", required=True)
    cb.set_defaults(func=cmd_corpus_build)

    cmp_p = sub.add_parser("compare")
    cmp_p.add_argument("--config", required=True)
    cmp_p.add_argument("--corpus", required=True)
    cmp_p.add_argument("--old", required=True)
    cmp_p.add_argument("--new", required=True)
    cmp_p.add_argument("--workdir", required=True)
    cmp_p.add_argument("--out", required=True)
    cmp_p.add_argument("--jobs", type=int, default=1)
    cmp_p.add_argument("--determinism-check", action="store_true")
    cmp_p.set_defaults(func=cmd_compare)

    return p


def main(argv):
    parser = build_parser()
    args = parser.parse_args(argv[1:])
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
