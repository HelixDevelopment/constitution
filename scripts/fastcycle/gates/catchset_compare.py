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

T085 Round 1 remediation (2026-09-30, B1): the pre-remediation `compare`
was a bare gate-ID-SET diff -- it (a) accepted `--corpus` on JSON-parse
alone (an empty `{}` was silently accepted, never consulted again),
(b) never implemented CS-001/CS-002/CS-003/CS-006/CS-007, (c) hard-coded
`old_missed`/`assertion_changes` to `[]` regardless of reality, (d) reported
`caught_old`/`caught_new` as raw gate COUNTS rather than caught-defect
counts, and (e) accepted a MutationTransferRecord on file EXISTENCE alone,
never reading its `can_fail_status`. Reproduced live before this fix
(§11.4.199): same gate id retained across OLD/NEW, NEW's script body
GUTTED to unconditional `exit 0` (an "asserts text changed" mutation) with
an empty `{}` --corpus -> `superset=true rc=0 assertion_changes=[]`. This
module now implements, honestly bounded (see "Scope and honest boundary"
below):

  * genuine `--corpus` structural validation (schema + non-empty union of
    mutation_defects/guard_defects; an empty/degenerate corpus is REFUSED,
    never silently accepted) -- see load_corpus();
  * a same-gate-id CONTENT-HASH diff (sha256 of the resolved script) for
    every gate id retained in both manifests: a content change with no
    proven MutationTransferRecord is now treated exactly like a REMOVAL
    (requires the same CS-005 proof) -- this is the concrete mechanism
    that closes the gutted-script repro above, since a gate id staying
    present can no longer silently retain "coverage" credit for a script
    whose behaviour changed underneath it;
  * genuine CS-006 `assertion_changes` population (never hard-coded):
    every same-id content change is listed with old/new sha256 + paths;
  * genuine CS-005 transfer-record validation: `compare` now reads each
    candidate record's `can_fail_status` and `schema` fields and accepts
    it ONLY when `can_fail_status == "PROVEN"` and the schema matches
    gate_audit.py's `mutation-transfer-record/v1` -- file existence alone
    is no longer sufficient;
  * genuine `caught_old`/`caught_new` counts derived from real gate-BODY
    inspection (gate_audit.py's own FAIL_SIGNAL_RE classifier, imported --
    not duplicated -- so both tools agree on "can this gate ever fail"):
    a gate whose body can never signal FAIL (`gate_noop.sh`'s shape) no
    longer inflates the catch count the way a bare `len(gates)` did;
  * an OPTIONAL, additive per-manifest `seed_defects` + `base_tree` field
    (SeededDefect, data-model.md §3.2) that, when a manifest declares it,
    drives a REAL CS-001/CS-002/CS-003 per-defect execution: a disposable
    mktemp copy of `base_tree` is made, the defect's `patch` is overlaid,
    and EVERY gate in OLD then NEW is run against the SAME mutated copy,
    producing genuine `old_verdict`/`new_verdict ∈ {CAUGHT, MISSED}` per
    defect (data-model.md §3.3's CatchSetComparison.per_defect shape) --
    `old_missed` is now populated from REAL per-defect execution results,
    never hard-coded; a CAUGHT verdict cites a content-addressed evidence
    file under `--workdir/evidence/` (CS-007);
  * baseline sanity (CS-003) is strengthened from `sh -n` (syntax only)
    to ALSO run every gate against an unmutated disposable copy of any
    declared `base_tree`, requiring all-PASS, when one is declared.

Scope and honest boundary (§11.4.6): this project's REAL corpus
(corpus-build's `mutation_defects`/`guard_defects`, sourced from
`meta_test_false_positive_proof.sh`'s inline mutation labels and the
on-device `regression_guard/registry.tsv`) does not, as of this commit,
carry a generic, source-side-invocable seed/patch reference per entry --
mutation labels are inline bash logic inside their own harness, not
standalone patch files, and guard-registry rows are almost entirely
on-device (video_display/audio_output) checks a source-only comparison
run cannot execute. `compare` therefore does NOT attempt to generically
"apply" an arbitrary `--corpus` entry; it validates the corpus
structurally (so a degenerate/empty corpus is refused, never silently
accepted) and reports its real counts, and it performs GENUINE per-defect
execution only for manifest-declared `seed_defects` (the concrete,
generalisable mechanism the toy RED fixtures under
tests/fixtures/catchset_compare/ now use). This is a real, load-bearing
strengthening over the pre-remediation stub (which never used --corpus or
ran anything), not a claim that every real corpus entry is executed here
-- wiring the real corpus into a fully generic per-defect proof (T065/T083
per tasks.md) remains separate, larger, device-gated follow-on work.

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
    Loads OLD and NEW gate manifests ({"gates":[{"id":..,"script":..}],
    "base_tree": <optional>, "seed_defects": <optional>}, paths relative to
    the manifest file's own directory). Computes the gate-set diff plus the
    content-hash diff for retained ids (CS-004/CS-006); consults
    --config's transfer_records_dir (CS-005) for a PROVEN
    MutationTransferRecord before accepting a removal or a content change
    as safe. When either manifest declares `seed_defects`, runs the real
    per-defect CS-001/CS-002/CS-003 execution described above.
    Exit 0 if superset holds (no unproven removal/change AND no per-defect
    old=CAUGHT/new=MISSED row); exit 1 naming every violation.

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
import re
import subprocess
import sys
import tempfile

SCHEMA_CATCHSET = "catchset/v1"
SCHEMA_CORPUS = "catchset-corpus/v1"
SCHEMA_TRANSFER = "mutation-transfer-record/v1"

EXIT_OK = 0
EXIT_FINDING = 1
EXIT_USAGE = 2
EXIT_SELFTEST = 3
EXIT_BLIND = 4

_HERE = os.path.dirname(os.path.abspath(__file__))
if _HERE not in sys.path:
    sys.path.insert(0, _HERE)
import gate_audit as _gate_audit  # noqa: E402 -- sibling module, single source of
# truth for "can this gate body ever fail" (FAIL_SIGNAL_RE) and the
# `<script> <target>` execution convention (run_gate), never duplicated.


def canonical_json(obj):
    return json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def body_hash(obj):
    return hashlib.sha256(canonical_json(obj).encode("utf-8")).hexdigest()


def sha256_file(path):
    h = hashlib.sha256()
    try:
        with open(path, "rb") as fh:
            for chunk in iter(lambda: fh.read(65536), b""):
                h.update(chunk)
    except OSError:
        return None
    return h.hexdigest()


# T085 Round 2 I-R2-1: matches a shell dot-command / `source` statement at
# the START of a (whitespace-stripped) line -- `. lib/foo.sh` or
# `source lib/foo.sh`, the two conventions POSIX sh and bash both accept.
_SOURCE_LINE_RE = re.compile(r'^[ \t]*(?:\.[ \t]+|source[ \t]+)(?P<target>\S+)', re.MULTILINE)

# Path-prefix idioms this project's gate scripts commonly use to source a
# sibling `lib/` file relative to their OWN directory (never the caller's
# cwd) -- substituted with the gate script's real directory when found.
_DIRNAME_IDIOMS = (
    '$(dirname "$0")', "$(dirname '$0')", '$(dirname "${BASH_SOURCE[0]}")',
    "$(dirname '${BASH_SOURCE[0]}')", '"$HERE"', "$HERE",
)


def resolve_sourced_files(script_path):
    """T085 Round 2 I-R2-1: best-effort STATIC extraction of every file a
    gate script `.`/`source`s -- the content-hash diff below must cover
    these too, not only the gate script's own bytes (reproduced live
    before this fix: gutting a SOURCED lib/*.sh engine a gate calls into,
    leaving the gate script itself byte-identical, gave
    old_sha256==new_sha256 and a clean rc=0/superset=true/changed=[]
    verdict -- a retained-id coverage change that genuinely altered the
    gate's behaviour went completely unreported). Handles a literal
    relative/absolute path argument and the '$(dirname "$0")/...' idiom;
    a target this cannot statically resolve (an unrecognised variable, a
    glob) is SKIPPED, never guessed (§11.4.6) -- this is a best-effort
    STATIC heuristic over the script TEXT, never a shell interpreter."""
    try:
        with open(script_path, "r", errors="replace") as fh:
            text = fh.read()
    except OSError:
        return []
    script_dir = os.path.dirname(os.path.abspath(script_path))
    resolved = []
    for m in _SOURCE_LINE_RE.finditer(text):
        target = m.group("target").strip().strip('"').strip("'")
        if not target:
            continue
        matched_idiom = False
        for idiom in _DIRNAME_IDIOMS:
            if target.startswith(idiom):
                target = script_dir + target[len(idiom):]
                matched_idiom = True
                break
        if not matched_idiom and (target.startswith("$") or "*" in target or "?" in target):
            continue  # cannot statically resolve -- honestly skipped, not guessed
        candidate = target if os.path.isabs(target) else os.path.join(script_dir, target)
        candidate = os.path.normpath(candidate)
        if os.path.isfile(candidate):
            resolved.append(candidate)
    return resolved


def combined_content_hash(script_path):
    """T085 Round 2 I-R2-1: the gate script's OWN sha256 PLUS the sha256 of
    every statically-resolvable file it `.`/`source`s (transitively, via a
    visited-set-bounded BFS so a sourced file that itself sources another
    is also covered, with no risk of looping on a cyclical/self-
    referential source chain). Returns a single sha256 hex digest over the
    SORTED (path, per-file-sha256) list, so gutting a sourced engine file
    -- leaving the gate script's own bytes untouched -- changes THIS
    combined hash even though sha256_file(script_path) alone would not."""
    visited = set()
    queue = [os.path.abspath(script_path)]
    file_hashes = []
    while queue:
        p = queue.pop()
        if p in visited:
            continue
        visited.add(p)
        h = sha256_file(p)
        if h is None:
            continue
        file_hashes.append((p, h))
        queue.extend(resolve_sourced_files(p))
    file_hashes.sort()
    payload = "\x1f".join(f"{p}={h}" for p, h in file_hashes)
    return hashlib.sha256(payload.encode("utf-8")).hexdigest()


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
# compare -- corpus loading + validation (B1 fix: genuinely consulted, never
# merely JSON-parsed and discarded)
# ---------------------------------------------------------------------------

def load_corpus(path):
    """Loads and STRUCTURALLY VALIDATES --corpus (B1 fix). A corpus that
    parses as JSON but carries no real defect union (e.g. the bare `{}`
    the pre-remediation `compare` silently accepted) is refused here --
    CS-002 requires "the same corpus" to genuinely drive the comparison,
    which an empty/degenerate corpus structurally cannot do. Returns the
    parsed dict on success; never returns a corpus this function has not
    itself confirmed carries `mutation_defects` + `guard_defects` lists
    (empty lists are permitted individually -- e.g. a project with zero
    registered guards yet -- but their UNION must be non-empty, and the
    required schema/sources keys must be present)."""
    if not os.path.isfile(path):
        sys.stderr.write(f"catchset_compare compare: --corpus not found: {path}\n")
        sys.exit(EXIT_USAGE)
    try:
        with open(path, "r", encoding="utf-8") as fh:
            corpus = json.load(fh)
    except (OSError, json.JSONDecodeError) as exc:
        sys.stderr.write(f"catchset_compare compare: --corpus is not readable/parseable JSON: {exc}\n")
        sys.exit(EXIT_USAGE)
    if not isinstance(corpus, dict):
        sys.stderr.write("catchset_compare compare: --corpus must be a JSON object\n")
        sys.exit(EXIT_USAGE)
    mutation_defects = corpus.get("mutation_defects")
    guard_defects = corpus.get("guard_defects")
    if not isinstance(mutation_defects, list) or not isinstance(guard_defects, list):
        sys.stderr.write(
            "catchset_compare compare: --corpus is missing required list keys "
            "'mutation_defects'/'guard_defects' (or corpus-build has not been run "
            f"against real sources) -- refusing a degenerate/empty corpus: {path}\n"
        )
        sys.exit(EXIT_USAGE)
    if len(mutation_defects) + len(guard_defects) == 0:
        sys.stderr.write(
            f"catchset_compare compare: --corpus {path} carries ZERO defects "
            "(mutation_defects and guard_defects are both empty) -- CS-002 "
            "requires a real corpus to drive the comparison; run corpus-build "
            "against real, non-empty sources first. Refusing rather than "
            "silently proceeding as if the corpus were unused (B1)\n"
        )
        sys.exit(EXIT_USAGE)
    return corpus


# ---------------------------------------------------------------------------
# compare -- gate manifest loading (extended with optional seed_defects /
# base_tree, additive over the original {"gates":[...]} shape)
# ---------------------------------------------------------------------------

def load_gate_manifest(path):
    """Returns (config_id, gates: {id: script_abs_path}, base_tree_abs_or_None,
    seed_defects: {defect_id: patch_abs_path}). `base_tree`/`seed_defects`
    are OPTIONAL, additive manifest fields (SeededDefect, data-model.md
    §3.2) -- their absence is not an error; every existing manifest lacking
    them behaves exactly as before (structural diff + sh -n baseline only).
    """
    with open(path, "r", encoding="utf-8") as fh:
        manifest = json.load(fh)
    base = os.path.dirname(os.path.abspath(path))
    gates = {}
    for g in manifest.get("gates", []):
        gid = g["id"]
        script = os.path.normpath(os.path.join(base, g["script"]))
        gates[gid] = script

    base_tree = None
    bt = manifest.get("base_tree")
    if bt:
        base_tree = os.path.normpath(os.path.join(base, bt))

    seed_defects = {}
    for sd in manifest.get("seed_defects", []):
        did = sd["defect_id"]
        patch = os.path.normpath(os.path.join(base, sd["patch"]))
        seed_defects[did] = patch

    return manifest.get("config_id", ""), gates, base_tree, seed_defects


def load_seed_manifest(path):
    """T085 Round 2 I-R2-9: loads an INDEPENDENT seed-defect source -- a
    file DISTINCT from --old/--new, so the gate manifests actually under
    comparison can never supply, override, or neutralize their own seed
    corpus. Deliberately reuses load_gate_manifest()'s exact parsing (same
    `{"seed_defects": [...], "base_tree": ...}` shape) rather than
    inventing a second format -- only the `gates` field, if present in
    this file, is ignored (a pure seed-manifest has no gates of its own to
    compare). Returns (seed_defects: {defect_id: patch_abs_path},
    base_tree_abs_or_None)."""
    _config_id, _gates, base_tree, seed_defects = load_gate_manifest(path)
    return seed_defects, base_tree


def gate_script_sane(script_path):
    """Baseline-sanity proxy (CS-003 parse-level check, since no single
    concrete real-project target is implied by a gate id alone in the
    general case): the gate script exists and parses cleanly under
    `sh -n`. A REAL execution baseline check runs additionally in
    compute_comparison() whenever a `base_tree` is declared (see
    baseline_execution_check())."""
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


def make_disposable_target(workdir, base_tree, patch=None):
    """CS-001 isolation: copies base_tree into a fresh mktemp subdirectory
    of workdir (never the real tree), optionally overlaying `patch`'s
    content onto that same file (the toy-fixture SeededDefect model this
    contract's own gate_audit.py make_disposable_copy() already
    established: "one file, wholesale-replaced by a sibling variant").
    Returns the disposable copy's absolute path."""
    dest_dir = tempfile.mkdtemp(dir=workdir)
    dest = os.path.join(dest_dir, os.path.basename(base_tree))
    import shutil
    shutil.copy2(base_tree, dest)
    if patch is not None:
        shutil.copy2(patch, dest)
    os.chmod(dest, 0o755)
    return dest


def baseline_execution_check(workdir, base_tree, gates):
    """Runs every gate in `gates` (dict of id->script) against an
    UNMUTATED disposable copy of base_tree (CS-003: "run both configs on
    the unmutated tree; both must be all-PASS") -- a REAL execution check,
    strengthening the pre-remediation `sh -n`-only baseline (B1). Returns
    (all_pass: bool, failing_notes: [str])."""
    target = make_disposable_target(workdir, base_tree, patch=None)
    notes = []
    all_pass = True
    for gid, script in sorted(gates.items()):
        verdict = _gate_audit.run_gate(script, target)
        if verdict is not True:
            all_pass = False
            notes.append(f"{gid}: baseline execution against clean {os.path.basename(base_tree)} did not PASS (CS-003)")
    return all_pass, notes


def write_evidence(workdir, defect_id, gate_id, script, target):
    """CS-007: captures the FAIL gate's real stdout+stderr to a
    content-addressed evidence file under workdir/evidence/. Returns the
    workdir-relative path (never a bare gate id/defect id as 'evidence')."""
    try:
        proc = subprocess.run(
            ["sh", script, target], capture_output=True, text=True, timeout=15
        )
        payload = f"gate={gate_id} defect={defect_id} rc={proc.returncode}\n--- stdout ---\n{proc.stdout}\n--- stderr ---\n{proc.stderr}\n"
    except Exception as exc:  # noqa: BLE001 - never crash the comparison over an evidence-capture failure
        payload = f"gate={gate_id} defect={defect_id} evidence capture raised: {exc}\n"
    digest = hashlib.sha256(payload.encode("utf-8", errors="replace")).hexdigest()
    ev_dir = os.path.join(workdir, "evidence")
    os.makedirs(ev_dir, exist_ok=True)
    rel = os.path.join("evidence", f"{digest}.txt")
    full = os.path.join(workdir, rel)
    if not os.path.isfile(full):
        with open(full, "w", encoding="utf-8") as fh:
            fh.write(payload)
    return rel


def run_defect_against_config(workdir, base_tree, patch, defect_id, gates):
    """CS-001/CS-002: applies `defect_id`'s seed patch onto a fresh
    disposable copy of base_tree, runs every gate in `gates`, and returns
    (verdict ∈ {"CAUGHT","MISSED","BLIND"}, catchers: [gate_id],
    evidence: {gate_id: rel_path}, blind_gates: [gate_id]).
    A CAUGHT gate's evidence is captured (CS-007); a PASSing gate is not
    (nothing to cite -- it did not fail).

    T085 Round 2 I-R2-9: `_gate_audit.run_gate()` returns `None` (never
    True/False) when a gate times out or raises -- the pre-fix version
    here checked ONLY `verdict is False`, so a `None` silently fell
    through neither branch and the defect's OVERALL verdict became
    "MISSED" whenever no OTHER gate happened to catch it -- INDISTINGUISH-
    ABLE from a genuine clean miss. Reproduced live before this fix
    (§11.4.199): a gate that hangs past its own 15s timeout reported
    MISSED, not "we could not establish whether this gate catches the
    defect". Any gate returning None for this defect now makes the WHOLE
    defect's verdict "BLIND" (unless >=1 OTHER gate genuinely CAUGHT it,
    in which case CAUGHT still wins -- a real catch is real evidence
    regardless of a DIFFERENT gate's own timeout) -- a defect whose
    verdict could not be honestly established is never silently folded
    into the clean-miss state."""
    target = make_disposable_target(workdir, base_tree, patch=patch)
    catchers = []
    evidence = {}
    blind_gates = []
    for gid, script in sorted(gates.items()):
        verdict = _gate_audit.run_gate(script, target)
        if verdict is False:
            catchers.append(gid)
            evidence[gid] = write_evidence(workdir, defect_id, gid, script, target)
        elif verdict is None:
            blind_gates.append(gid)
    if catchers:
        overall = "CAUGHT"
    elif blind_gates:
        overall = "BLIND"
    else:
        overall = "MISSED"
    return overall, catchers, evidence, blind_gates


def transfer_record_path(cfg, root, gate_id):
    tr_dir = cfg_path(cfg, root, "transfer_records_dir")
    return os.path.join(tr_dir, f"{gate_id}.json")


def transfer_record_proven(cfg, root, gate_id, bound_content_hash=None):
    """CS-005 consultation (B1 fix): reads the candidate MutationTransferRecord
    and requires its `can_fail_status` field to literally equal "PROVEN"
    AND its `schema` to match gate_audit.py's mutation-transfer-record/v1 --
    file EXISTENCE alone (the pre-remediation behaviour) is no longer
    sufficient.

    T085 Round 2 I-R2-2: a minimal two-field JSON
    ({"schema": "mutation-transfer-record/v1", "can_fail_status": "PROVEN"})
    with NO `into_gate_id` and no content binding previously satisfied
    every check above -- reproduced live before this fix -- so the SAME
    record could be copy-pasted to "prove" ANY gate id's removal/change,
    for ANY manifest, forever (a record never expires nor binds to what
    it actually claims to cover). Fixed by requiring TWO binding fields:
    `into_gate_id` (must equal the gate_id this call is being consulted
    for) and `bound_gate_sha256` (must equal `bound_content_hash`, the
    CALLER-COMPUTED combined_content_hash() of the actual script content
    under review right now -- the removed gate's old script for a
    removed_ids consultation, the changed gate's NEW script for a
    changed_ids consultation) -- a record whose binding fields do not
    match the CURRENT change/manifest is refused exactly as a missing
    record would be. `bound_content_hash=None` (a caller that has not
    been updated to pass it) is treated as "binding check not requested"
    ONLY for backward-compatibility of direct unit callers -- both real
    call sites in compute_comparison() below always pass it."""
    rec_path = transfer_record_path(cfg, root, gate_id)
    if not os.path.isfile(rec_path):
        return False, f"no transfer record at {rec_path}"
    try:
        with open(rec_path, "r", encoding="utf-8") as fh:
            rec = json.load(fh)
    except (OSError, json.JSONDecodeError) as exc:
        return False, f"transfer record at {rec_path} is not readable/parseable JSON: {exc}"
    if not isinstance(rec, dict):
        return False, f"transfer record at {rec_path} is not a JSON object"
    if rec.get("schema") != SCHEMA_TRANSFER:
        return False, f"transfer record at {rec_path} has schema={rec.get('schema')!r}, expected {SCHEMA_TRANSFER!r}"
    if rec.get("can_fail_status") != "PROVEN":
        return False, f"transfer record at {rec_path} has can_fail_status={rec.get('can_fail_status')!r}, not PROVEN"
    if rec.get("into_gate_id") != gate_id:
        return False, (
            f"transfer record at {rec_path} has into_gate_id={rec.get('into_gate_id')!r}, "
            f"expected {gate_id!r} (T085 Round 2 I-R2-2: unbound record refused)"
        )
    if bound_content_hash is not None and rec.get("bound_gate_sha256") != bound_content_hash:
        return False, (
            f"transfer record at {rec_path} has bound_gate_sha256={rec.get('bound_gate_sha256')!r}, "
            f"expected {bound_content_hash!r} (T085 Round 2 I-R2-2: record does not bind to the "
            "actual gate script content under review right now -- refused)"
        )
    return True, f"transfer record at {rec_path} is PROVEN and bound to {gate_id!r}"


def compute_comparison(cfg, root, old_path, new_path, corpus, workdir,
                        independent_seed_defects=None, independent_base_tree=None):
    old_id, old_gates, old_base_tree, old_seed_defects = load_gate_manifest(old_path)
    new_id, new_gates, new_base_tree, new_seed_defects = load_gate_manifest(new_path)

    # --- baseline sanity (CS-003): sh -n on every gate, plus a REAL
    #     execution baseline whenever either manifest declares base_tree.
    baseline_all_pass = True
    sanity_notes = []
    all_gates = {**old_gates, **new_gates}
    for gid, script in all_gates.items():
        ok, note = gate_script_sane(script)
        if not ok:
            baseline_all_pass = False
            sanity_notes.append(f"{gid}: {note}")

    # T085 Round 2 I-R2-9: when an independent seed manifest ALSO declares
    # its own base_tree, that takes precedence -- the manifests under test
    # must not be able to control the clean tree the independent seeds run
    # against either (a malicious/buggy old|new base_tree could otherwise
    # make even a genuinely-independent seed's patch fail to apply/catch).
    base_tree = independent_base_tree or new_base_tree or old_base_tree
    if base_tree is not None and baseline_all_pass:
        ok, notes = baseline_execution_check(workdir, base_tree, all_gates)
        if not ok:
            baseline_all_pass = False
            sanity_notes.extend(notes)

    # --- structural gate-set diff (CS-004 core) ---
    removed_ids = sorted(set(old_gates) - set(new_gates))
    gained_ids = sorted(set(new_gates) - set(old_gates))
    retained_ids = sorted(set(old_gates) & set(new_gates))

    # --- content-hash diff for retained ids (CS-006 + the concrete B1
    #     fix: a same-id gate whose SCRIPT CONTENT changed can no longer
    #     silently keep "coverage" credit -- it requires the same CS-005
    #     transfer proof a removal would). T085 Round 2 I-R2-1: the hash
    #     COVERS every statically-resolvable `.`/`source`d file the gate
    #     script declares, not only the gate script's own bytes --
    #     combined_content_hash() above. ---
    assertion_changes = []
    changed_ids = []
    for gid in retained_ids:
        old_hash = combined_content_hash(old_gates[gid])
        new_hash = combined_content_hash(new_gates[gid])
        if old_hash is not None and new_hash is not None and old_hash != new_hash:
            changed_ids.append(gid)
            assertion_changes.append({
                "gate_id": gid,
                "old_script": os.path.relpath(old_gates[gid], root) if old_gates[gid].startswith(root) else old_gates[gid],
                "new_script": os.path.relpath(new_gates[gid], root) if new_gates[gid].startswith(root) else new_gates[gid],
                "old_sha256": old_hash,
                "new_sha256": new_hash,
                "note": "ASSERTION_CHANGED -- gate id retained, script content differs; review decides "
                        "whether this is structural/additive (CS-006); this harness never approves it "
                        "automatically -- it is treated as an unproven coverage change unless a PROVEN "
                        "MutationTransferRecord exists for this gate id.",
            })

    # T085 Round 2 I-R2-2: bind each consultation to the ACTUAL content
    # under review right now -- the removed gate's OLD script for a
    # removed_ids consultation (proving the record matches what is
    # genuinely being removed), the changed gate's NEW script for a
    # changed_ids consultation (proving it matches what the gate id now
    # is, already computed above for assertion_changes).
    changed_new_hash_by_gid = {c["gate_id"]: c["new_sha256"] for c in assertion_changes}

    named_defects = []
    named_defects_detail = []
    for gid in removed_ids:
        proven, note = transfer_record_proven(cfg, root, gid, bound_content_hash=combined_content_hash(old_gates[gid]))
        if proven:
            continue
        named_defects.append(gid)
        named_defects_detail.append({"gate_id": gid, "reason": "removed", "detail": note})
    for gid in changed_ids:
        proven, note = transfer_record_proven(cfg, root, gid, bound_content_hash=changed_new_hash_by_gid[gid])
        if proven:
            continue
        named_defects.append(gid)
        named_defects_detail.append({"gate_id": gid, "reason": "changed_unproven", "detail": note})

    # --- genuine caught_old/caught_new (B1 fix): counts of gates whose
    #     body actually carries a reachable FAIL signal (gate_audit.py's
    #     own classifier, imported -- single source of truth), never raw
    #     manifest sizes. A gate that can structurally never fail
    #     (gate_noop.sh's shape) does not inflate this count. ---
    def executing_count(gates):
        n = 0
        for script in gates.values():
            if os.path.isfile(script):
                body = _gate_audit.read_gate_body_with_siblings(script)
                if _gate_audit.FAIL_SIGNAL_RE.search(body):
                    n += 1
        return n

    caught_old = executing_count(old_gates)
    caught_new = executing_count(new_gates)
    catch_count_basis = "gate_capability_heuristic"

    # --- genuine per-defect execution (CS-001/CS-002/CS-003) when either
    #     manifest declares seed_defects (B1 fix: old_missed is now
    #     computed from real execution, never hard-coded).
    #
    #     T085 Round 2 I-R2-9: seeds now come from an INDEPENDENT source
    #     whenever `independent_seed_defects` is supplied by the caller
    #     (cmd_compare's new --seed-manifest, a file DISTINCT from --old/
    #     --new) -- the gate manifests UNDER TEST can no longer supply,
    #     override, or neutralize their own seed corpus in that mode. When
    #     no independent source is given (legacy/back-compat path, the
    #     existing RED-test fixture corpus's own self-declared
    #     seed_defects), a defect_id BOTH old and new manifests declare
    #     with DIFFERING patches is no longer silently resolved by "new
    #     wins" -- reproduced live before this fix: a NEW manifest could
    #     redeclare an EXISTING defect_id with a neutered/no-op patch,
    #     silently overriding old's real one with zero indication. Such a
    #     defect_id is now excluded from per-defect execution and reported
    #     as an explicit "seed_conflict" finding instead. ---
    if independent_seed_defects is not None:
        seed_defects = dict(independent_seed_defects)
        seed_conflicts = []
    else:
        seed_conflicts = sorted(
            did for did in (set(old_seed_defects) & set(new_seed_defects))
            if old_seed_defects[did] != new_seed_defects[did]
        )
        seed_defects = dict(old_seed_defects)
        seed_defects.update(new_seed_defects)
        for did in seed_conflicts:
            seed_defects.pop(did, None)
    per_defect = []
    old_missed = []
    for did in seed_conflicts:
        # T085 Round 3 R3-I2 (IMPORTANT): the pre-fix version below
        # recorded a seed_conflict ONLY in named_defects_detail, which
        # `superset` (computed from `len(named_defects) == 0` alone)
        # never consults -- so a detected seed_conflict NEVER changed the
        # reported verdict: Round 2's EXACT repro (NEW manifest
        # redeclares an EXISTING defect_id with a no-op patch) still
        # produced rc=0, superset:true, lost:0 after the Round 2 fix
        # "landed" -- the detail entry existed but was cosmetic. Fixed
        # by also appending `did` into `named_defects` (the SAME pattern
        # the BLIND-verdict branch just below already uses for a
        # defect_id), so superset genuinely goes false and the exit code
        # (EXIT_FINDING) genuinely reflects the conflict, matching
        # every OTHER named-defect class in this function.
        if did not in named_defects:
            named_defects.append(did)
        named_defects_detail.append({
            "defect_id": did,
            "reason": "seed_conflict",
            "detail": (
                f"old manifest declares patch {old_seed_defects[did]!r}, new manifest "
                f"declares a DIFFERENT patch {new_seed_defects[did]!r} for the SAME "
                "defect_id -- excluded from per-defect execution rather than silently "
                "resolved by 'new wins' (T085 Round 2 I-R2-9); supply --seed-manifest "
                "for an independent, unforgeable seed source"
            ),
        })
    if seed_defects and base_tree is not None:
        catch_count_basis = "per_defect_execution"
        real_caught_old = 0
        real_caught_new = 0
        for defect_id in sorted(seed_defects):
            patch = seed_defects[defect_id]
            old_verdict, old_catchers, old_evidence, old_blind = run_defect_against_config(
                workdir, base_tree, patch, defect_id, old_gates)
            new_verdict, new_catchers, new_evidence, new_blind = run_defect_against_config(
                workdir, base_tree, patch, defect_id, new_gates)
            if old_verdict == "CAUGHT":
                real_caught_old += 1
            if new_verdict == "CAUGHT":
                real_caught_new += 1
            evidence = {f"old:{k}": v for k, v in old_evidence.items()}
            evidence.update({f"new:{k}": v for k, v in new_evidence.items()})
            per_defect.append({
                "defect_id": defect_id,
                "old_verdict": old_verdict,
                "new_verdict": new_verdict,
                "old_catchers": old_catchers,
                "new_catchers": new_catchers,
                "old_blind_gates": old_blind,
                "new_blind_gates": new_blind,
                "evidence": evidence,
            })
            if old_verdict == "BLIND" or new_verdict == "BLIND":
                # T085 Round 2 I-R2-9: a defect this run could not honestly
                # establish a verdict for (>=1 gate timed out/errored, and
                # no OTHER gate genuinely caught it) is its OWN finding
                # class -- never silently folded into old_missed nor into
                # a clean pass; the superset test cannot be trusted for
                # this defect_id until it is re-run cleanly.
                if defect_id not in named_defects:
                    named_defects.append(defect_id)
                named_defects_detail.append({
                    "defect_id": defect_id,
                    "reason": "defect_blind",
                    "detail": f"old={old_verdict} (blind_gates={old_blind}) new={new_verdict} "
                              f"(blind_gates={new_blind}): could not honestly establish a verdict "
                              "-- never reported as a clean miss",
                })
            elif old_verdict == "MISSED":
                # CS-003: a defect OLD does not catch is OLD_MISSED -- a
                # pre-existing gap, excluded from the superset test for
                # this row, its count published (never silently dropped).
                old_missed.append(defect_id)
            elif new_verdict == "MISSED":
                # old=CAUGHT & new=MISSED -- the ONLY superset-violating
                # shape (CS-004 directionality).
                if defect_id not in named_defects:
                    named_defects.append(defect_id)
                named_defects_detail.append({
                    "defect_id": defect_id,
                    "reason": "defect_missed",
                    "detail": f"old={old_verdict} (catchers={old_catchers}) -> "
                              f"new={new_verdict}: superset violated for this defect",
                })
        caught_old = real_caught_old
        caught_new = real_caught_new

    result = {
        "schema": SCHEMA_CATCHSET,
        "old_config_id": old_id,
        "new_config_id": new_id,
        "baseline_all_pass": baseline_all_pass,
        "old_missed": old_missed,
        "assertion_changes": assertion_changes,
        "counts": {
            "caught_old": caught_old,
            "caught_new": caught_new,
            "lost": len(named_defects),
            "gained": len(gained_ids),
        },
        "catch_count_basis": catch_count_basis,
        "removed_gate_ids": removed_ids,
        "gained_gate_ids": gained_ids,
        "changed_gate_ids": changed_ids,
        "named_defects": named_defects,
        "named_defects_detail": named_defects_detail,
        "per_defect": per_defect,
        "corpus_summary": {
            "schema": corpus.get("schema"),
            "mutation_defect_count": len(corpus.get("mutation_defects", [])),
            "guard_defect_count": len(corpus.get("guard_defects", [])),
        },
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

    corpus = load_corpus(args.corpus)  # B1: genuinely validated, refuses on empty/degenerate
    if not os.path.isfile(args.old):
        sys.stderr.write(f"catchset_compare compare: --old not found: {args.old}\n")
        sys.exit(EXIT_USAGE)
    if not os.path.isfile(args.new):
        sys.stderr.write(f"catchset_compare compare: --new not found: {args.new}\n")
        sys.exit(EXIT_USAGE)

    os.makedirs(args.workdir, exist_ok=True)

    # T085 Round 2 I-R2-9: --seed-manifest is an INDEPENDENT seed source,
    # a file DISTINCT from --old/--new -- when supplied, the old/new gate
    # manifests' own self-declared seed_defects are entirely ignored for
    # this run (see compute_comparison()'s own docstring/comments).
    independent_seed_defects = None
    independent_base_tree = None
    if getattr(args, "seed_manifest", None):
        if not os.path.isfile(args.seed_manifest):
            sys.stderr.write(f"catchset_compare compare: --seed-manifest not found: {args.seed_manifest}\n")
            sys.exit(EXIT_USAGE)
        independent_seed_defects, independent_base_tree = load_seed_manifest(args.seed_manifest)

    result, rc = compute_comparison(
        cfg, root, args.old, args.new, corpus, args.workdir,
        independent_seed_defects=independent_seed_defects,
        independent_base_tree=independent_base_tree,
    )

    if args.determinism_check:
        result2, rc2 = compute_comparison(
            cfg, root, args.old, args.new, corpus, args.workdir,
            independent_seed_defects=independent_seed_defects,
            independent_base_tree=independent_base_tree,
        )
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
            f"unproven removal/change/defect(s): {', '.join(str(x) for x in result['named_defects'])} "
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
    cmp_p.add_argument(
        "--seed-manifest",
        help=(
            "T085 Round 2 I-R2-9: an INDEPENDENT seed-defect source (a file "
            "DISTINCT from --old/--new) -- when given, the --old/--new gate "
            "manifests' own self-declared seed_defects are ignored entirely, "
            "so neither manifest under test can supply, override, or "
            "neutralize its own seed corpus."
        ),
    )
    cmp_p.set_defaults(func=cmd_compare)

    return p


def main(argv):
    parser = build_parser()
    args = parser.parse_args(argv[1:])
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
