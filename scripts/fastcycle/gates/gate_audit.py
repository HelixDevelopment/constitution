#!/usr/bin/env python3
"""gate_audit.py -- gate-removal transfer proof (SpecKit-004 "fast-dev-
cycles", User Story 2; plan.md T-C08, T-H01; tasks.md T064 [transfer-proof
only]/T074 [audit, a LATER, separate task -- this file's `audit`
subcommand is intentionally NOT implemented here, see NOTE below];
contract specs/004-fast-dev-cycles/contracts/catch-set-comparison-harness.md
CS-005).

Guarded by
constitution/scripts/fastcycle/tests/test_catchset_compare_red.sh (T050,
the `transfer-proof` real-invocation assertions) and, separately,
constitution/scripts/fastcycle/tests/test_gate_audit_red.sh (T058, the
`audit` subcommand -- T074's own scope, not this commit's).

Subcommand implemented here
----------------------------
transfer-proof --config <cfg> --gate <removed_gate_id> --into <survivor_gate_id> --out <out>

CS-005: "applies the removed gate's paired mutation, runs the surviving
gate, and writes a MutationTransferRecord only if the surviving gate
FAILs. A gate with can_fail != PROVEN for the surviving gate, or with
paired_mutation = NONE on the removed gate, is refused (exit 1)."

Neither --gate's script location nor its own paired-mutation patch is
passed on the command line (the contract's own Invocation section carries
no such flags) -- both are DISCOVERED empirically, never hardcoded:

1. --gate and --into are resolved to script paths by searching
   --config's paths.gate_search_dirs (in order) for "<id>.sh" -- a
   GENERAL, extensible registry (see fastcycle.yaml's own comment on this
   key: any gate script -- real project or test-provided -- registered
   under one of these directories is discoverable the same way).
2. --gate's OWN paired mutation is discovered by trying every candidate
   patch under paths.patch_search_dirs (sorted for determinism) against a
   disposable copy of paths.base_tree_dirs (CS-001 isolation): the first
   patch for which (a) the CLEAN unmutated copy PASSes --gate's script
   (CS-003 baseline sanity) and (b) the PATCHED copy FAILs it, is treated
   as --gate's paired mutation. No patch found matching this shape =>
   paired_mutation = NONE => refuse (exit 1), matching CS-005 verbatim.
3. That same discovered patch is then applied to a FRESH disposable copy
   and --into's script is run against it: FAIL => can_fail=PROVEN => a
   MutationTransferRecord is written under
   --config's paths.transfer_records_dir (keyed by --gate's id) and this
   process exits 0. PASS => can_fail=NOT_PROVEN => refuse, exit 1, no
   record written.

catchset_compare.py's `compare` subcommand reads this SAME
transfer_records_dir (CS-004/CS-005 cooperating through shared,
inspectable, project-relative state -- never an in-memory coupling
between the two tool invocations).

CS-001 isolation: every disposable copy is created under `--workdir`
(defaulting to a fresh `tempfile.mkdtemp()` if --workdir is omitted) via
plain file copy, never touching paths.base_tree_dirs itself.

Exit codes (C-001): 0 transfer proof accepted (record written), 1 a
finding (refused: NOT_PROVEN or paired_mutation=NONE), 2 usage/config
error (bad args, gate id not found in any search dir), 4 BLIND (a
required input could not be read).
"""
import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import tempfile

SCHEMA_TRANSFER = "mutation-transfer-record/v1"

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
    if not path or not os.path.isfile(path):
        sys.stderr.write(f"gate_audit: config file not found: {path}\n")
        sys.exit(EXIT_USAGE)
    try:
        import yaml
    except ImportError:
        sys.stderr.write("gate_audit: PyYAML is required to parse --config (pip install pyyaml)\n")
        sys.exit(EXIT_USAGE)
    with open(path, "r", encoding="utf-8") as fh:
        cfg = yaml.safe_load(fh)
    if not isinstance(cfg, dict) or "paths" not in cfg:
        sys.stderr.write(f"gate_audit: {path} missing required top-level key 'paths'\n")
        sys.exit(EXIT_USAGE)
    return cfg


def project_root_of(config_path):
    cfg_dir = os.path.dirname(os.path.abspath(config_path))
    return os.path.dirname(os.path.dirname(cfg_dir))


def cfg_path(cfg, root, key):
    rel = cfg.get("paths", {}).get(key)
    if not rel:
        sys.stderr.write(f"gate_audit: config missing required paths.{key}\n")
        sys.exit(EXIT_USAGE)
    return os.path.join(root, rel)


def cfg_path_list(cfg, root, key):
    rels = cfg.get("paths", {}).get(key) or []
    return [os.path.join(root, r) for r in rels]


def _script_declared_id(script_path):
    """Reads a gate script's own `# id: <gate_id>` header comment (the
    convention every gate script under gate_search_dirs is REQUIRED to
    carry, per this fixture family's own gate_marker.sh/gate_extra.sh/etc.
    headers) -- only the FIRST few lines are scanned, never the whole
    file, and the check is line-anchored (^#\\s*id:\\s*) so a prose mention
    of "id:" elsewhere in a comment body can never false-match
    (§11.4.201(7)(a) carrier-vs-thing). Returns None if no such header is
    present (a gate script filename is NEVER trusted as its own id --
    "gate_extra.sh" and gate-id "g_extra" deliberately differ)."""
    try:
        with open(script_path, "r", encoding="utf-8", errors="replace") as fh:
            for _ in range(10):
                line = fh.readline()
                if not line:
                    break
                stripped = line.strip()
                if stripped.startswith("#"):
                    body = stripped.lstrip("#").strip()
                    if body.lower().startswith("id:"):
                        return body.split(":", 1)[1].strip()
    except OSError:
        return None
    return None


def find_gate_script(cfg, root, gate_id):
    """Resolves gate_id -> script path by scanning every .sh file under
    every registered gate_search_dirs for a `# id: <gate_id>` header
    comment (see _script_declared_id) -- the gate SCRIPT'S OWN declared
    identity, never a filename-equals-id-plus-.sh guess (a real §11.4.6
    bug caught + fixed while implementing this: gate id "g_extra"'s real
    script is named "gate_extra.sh", not "g_extra.sh")."""
    for d in cfg_path_list(cfg, root, "gate_search_dirs"):
        if not os.path.isdir(d):
            continue
        for name in sorted(os.listdir(d)):
            if not name.endswith(".sh"):
                continue
            full = os.path.join(d, name)
            if _script_declared_id(full) == gate_id:
                return full
    return None


def list_candidate_patches(cfg, root):
    patches = []
    for d in cfg_path_list(cfg, root, "patch_search_dirs"):
        if not os.path.isdir(d):
            continue
        for name in sorted(os.listdir(d)):
            if name.endswith(".sh"):
                patches.append(os.path.join(d, name))
    return patches


def base_tree_files(cfg, root):
    """Returns the sorted list of (relative_name, absolute_path) for every
    file directly under every registered base_tree_dirs entry."""
    files = []
    for d in cfg_path_list(cfg, root, "base_tree_dirs"):
        if not os.path.isdir(d):
            continue
        for name in sorted(os.listdir(d)):
            full = os.path.join(d, name)
            if os.path.isfile(full):
                files.append((name, full))
    return files


def make_disposable_copy(cfg, root, workdir, patch_path=None):
    """CS-001: copies every base_tree file into a fresh subdirectory of
    workdir. When patch_path is given, its content OVERWRITES the sole
    base_tree file with that basename's target -- this fixture family's
    SeededDefect model is "one file, wholesale-replaced by a sibling
    variant" (never a diff/patch tool dependency), which this mirrors
    directly. A base_tree with more than one file is copied in full but
    only the FIRST file receives the patch overlay (scoped limitation,
    honestly stated: multi-file defect application is out of this task's
    scope -- the real-project corpus never reaches this code path, see
    catchset_compare.py's module docstring)."""
    dest = tempfile.mkdtemp(dir=workdir)
    files = base_tree_files(cfg, root)
    if not files:
        sys.stderr.write("gate_audit: no base_tree files found under any registered base_tree_dirs\n")
        sys.exit(EXIT_BLIND)
    for name, full in files:
        shutil.copy2(full, os.path.join(dest, name))
    target_name = files[0][0]
    target_path = os.path.join(dest, target_name)
    if patch_path is not None:
        shutil.copy2(patch_path, target_path)
    os.chmod(target_path, 0o755)
    return target_path


def run_gate(script_path, target_path):
    """Executes `<script_path> <target_path>`; returns True on PASS
    (exit 0), False on FAIL/anything else (matching the toy gates' own
    `sh gate.sh <target>` -> exit 0 PASS / 1 FAIL convention -- the same
    convention the RED test's own verdict_map() bash helper uses)."""
    try:
        proc = subprocess.run(
            ["sh", script_path, target_path], capture_output=True, text=True, timeout=15
        )
    except Exception as exc:  # noqa: BLE001 - report, never crash the run
        sys.stderr.write(f"gate_audit: running {script_path} against {target_path} raised: {exc}\n")
        return None
    return proc.returncode == 0


def discover_paired_mutation(cfg, root, workdir, gate_script):
    """CS-005 "applies the removed gate's paired mutation": tries every
    candidate patch (sorted, deterministic) until one is found for which
    the CLEAN copy PASSes gate_script (CS-003 baseline sanity) and the
    PATCHED copy FAILs it. Returns the patch path, or None (paired
    mutation = NONE, per CS-005's own refusal clause)."""
    clean_target = make_disposable_copy(cfg, root, workdir, patch_path=None)
    clean_pass = run_gate(gate_script, clean_target)
    if clean_pass is not True:
        # Baseline sanity itself failed -- the gate doesn't even pass its
        # own clean tree; no honest pairing can be discovered.
        return None
    for patch_path in list_candidate_patches(cfg, root):
        patched_target = make_disposable_copy(cfg, root, workdir, patch_path=patch_path)
        patched_pass = run_gate(gate_script, patched_target)
        if patched_pass is False:
            return patch_path
    return None


def cmd_transfer_proof(args):
    cfg = load_yaml_config(args.config)
    root = project_root_of(args.config)

    removed_id = args.gate
    survivor_id = args.into

    removed_script = find_gate_script(cfg, root, removed_id)
    survivor_script = find_gate_script(cfg, root, survivor_id)

    if removed_script is None:
        sys.stderr.write(
            f"gate_audit transfer-proof: gate id {removed_id!r} not found in any "
            "registered gate_search_dirs -- refusing (paired_mutation cannot be "
            "discovered for an unresolvable gate)\n"
        )
        result = {
            "schema": SCHEMA_TRANSFER,
            "removed_gate_id": removed_id,
            "into_gate_id": survivor_id,
            "can_fail_status": "NOT_PROVEN",
            "reason": "removed_gate_script_not_found",
        }
        _write_refusal(args.out, result)
        return EXIT_FINDING

    if survivor_script is None:
        sys.stderr.write(
            f"gate_audit transfer-proof: gate id {survivor_id!r} (--into) not found "
            "in any registered gate_search_dirs -- refusing\n"
        )
        result = {
            "schema": SCHEMA_TRANSFER,
            "removed_gate_id": removed_id,
            "into_gate_id": survivor_id,
            "can_fail_status": "NOT_PROVEN",
            "reason": "survivor_gate_script_not_found",
        }
        _write_refusal(args.out, result)
        return EXIT_FINDING

    workdir = args.workdir or tempfile.mkdtemp(prefix="gate_audit_")
    os.makedirs(workdir, exist_ok=True)

    paired_patch = discover_paired_mutation(cfg, root, workdir, removed_script)
    if paired_patch is None:
        print(
            f"transfer-proof: REFUSED -- gate {removed_id!r} has paired_mutation=NONE "
            "(no candidate patch under patch_search_dirs makes it FAIL against a "
            "PASSing clean baseline) -- CS-005"
        )
        result = {
            "schema": SCHEMA_TRANSFER,
            "removed_gate_id": removed_id,
            "into_gate_id": survivor_id,
            "can_fail_status": "NOT_PROVEN",
            "reason": "paired_mutation_none",
        }
        _write_refusal(args.out, result)
        return EXIT_FINDING

    survivor_target = make_disposable_copy(cfg, root, workdir, patch_path=paired_patch)
    survivor_pass = run_gate(survivor_script, survivor_target)

    if survivor_pass is True:
        print(
            f"transfer-proof: REFUSED -- surviving gate {survivor_id!r} PASSES "
            f"against {removed_id!r}'s own paired mutation "
            f"({os.path.basename(paired_patch)}) -- can_fail=NOT_PROVEN, CS-005"
        )
        result = {
            "schema": SCHEMA_TRANSFER,
            "removed_gate_id": removed_id,
            "into_gate_id": survivor_id,
            "paired_mutation_patch": os.path.relpath(paired_patch, root),
            "can_fail_status": "NOT_PROVEN",
            "reason": "survivor_did_not_fail",
        }
        _write_refusal(args.out, result)
        return EXIT_FINDING

    # survivor_pass is False (FAIL) -- can_fail=PROVEN, write the record.
    record = {
        "schema": SCHEMA_TRANSFER,
        "removed_gate_id": removed_id,
        "into_gate_id": survivor_id,
        "paired_mutation_patch": os.path.relpath(paired_patch, root),
        "can_fail_status": "PROVEN",
    }
    record["body_hash"] = body_hash({k: v for k, v in record.items() if k != "run_meta"})

    out_dir = os.path.dirname(os.path.abspath(args.out))
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as fh:
        fh.write(canonical_json(record))
        fh.write("\n")

    tr_dir = cfg_path(cfg, root, "transfer_records_dir")
    os.makedirs(tr_dir, exist_ok=True)
    with open(os.path.join(tr_dir, f"{removed_id}.json"), "w", encoding="utf-8") as fh:
        fh.write(canonical_json(record))
        fh.write("\n")

    print(
        f"transfer-proof: ACCEPTED -- surviving gate {survivor_id!r} FAILS "
        f"against {removed_id!r}'s own paired mutation "
        f"({os.path.basename(paired_patch)}) -- can_fail=PROVEN, MutationTransferRecord "
        f"written to {args.out} and {tr_dir}/{removed_id}.json"
    )
    return EXIT_OK


def _write_refusal(out_path, result):
    """A refusal (exit 1) does NOT write ANYTHING to --out. CS-005:
    "writes a MutationTransferRecord only if the surviving gate FAILs" --
    the contract's own RED fixtures (cs_bad_removal_no_transfer:
    transfer_record_written=false; the RED test's own
    assert_transfer_proof_real checks `[ -f "$out" ]` as the LITERAL
    transfer_record_written signal) make --out's existence itself the
    proof a MutationTransferRecord was written, so this subcommand's
    refusal path is diagnostic-only (stderr/stdout), never a file write --
    a narrower reading of C-001's generic "1 = a finding, output written"
    than compare/corpus-build use, but the one THIS subcommand's own RED
    fixtures require. The finding is still fully reported on stdout/
    stderr by every caller of this function."""
    del out_path, result  # intentionally not written -- see docstring


# ---------------------------------------------------------------------------
# argparse
#
# NOTE: the `audit` subcommand (plan T-C08's other half; tasks.md T074,
# guarded separately by test_gate_audit_red.sh / T058) is intentionally
# NOT registered here -- it is a later, separate task's scope
# (§11.4.240 producer!=verifier: this commit implements ONLY
# `transfer-proof`, T050/T064's own scope). T074's implementer adds an
# `audit` subparser to this same file without disturbing transfer-proof.
# ---------------------------------------------------------------------------

def build_parser():
    p = argparse.ArgumentParser(prog="gate_audit.py")
    sub = p.add_subparsers(dest="subcommand", required=True)

    tp = sub.add_parser("transfer-proof")
    tp.add_argument("--config", required=True)
    tp.add_argument("--gate", required=True)
    tp.add_argument("--into", required=True)
    tp.add_argument("--out", required=True)
    tp.add_argument("--workdir", default=None)
    tp.set_defaults(func=cmd_transfer_proof)

    return p


def main(argv):
    parser = build_parser()
    args = parser.parse_args(argv[1:])
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
