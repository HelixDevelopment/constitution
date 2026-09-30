#!/usr/bin/env python3
"""gate_audit.py -- gate-removal transfer proof + gate classification audit
(SpecKit-004 "fast-dev-cycles", User Story 2; plan.md T-C08, T-H01;
tasks.md T064 [transfer-proof, landed first] / T074 [classify + audit,
THIS commit -- see the "Subcommands implemented here" section below];
contracts specs/004-fast-dev-cycles/contracts/catch-set-comparison-harness.md
CS-005 and plan.md T-C08 "Gate audit: vacuous, duplicate and single-mention
gates; propagation-family consolidation").

Guarded by
constitution/scripts/fastcycle/tests/test_catchset_compare_red.sh (T050,
the `transfer-proof` real-invocation assertions) and
constitution/scripts/fastcycle/tests/test_gate_audit_red.sh (T058, the
`classify` and `audit` subcommands -- T074's own scope).

Subcommands implemented here
-----------------------------
transfer-proof --config <cfg> --gate <removed_gate_id> [--into <survivor_gate_id>]
                [--out <out>] [--gates-dir <dir>] [--workdir <dir>]

CS-005: "applies the removed gate's paired mutation, runs the surviving
gate, and writes a MutationTransferRecord only if the surviving gate
FAILs. A gate with can_fail != PROVEN for the surviving gate, or with
paired_mutation = NONE on the removed gate, is refused (exit 1)."

Two gate-resolution + mutation-discovery MODES, chosen by whether
--gates-dir is passed:

  (A) LEGACY cfg-based mode (--gates-dir omitted, T050's own contract,
      UNCHANGED by this commit): --gate/--into resolved to script paths by
      searching --config's paths.gate_search_dirs for a script whose own
      `# id: <gate_id>` header comment matches (see find_gate_script());
      the paired mutation is DISCOVERED by trying every candidate PATCH
      under paths.patch_search_dirs against a disposable copy of
      paths.base_tree_dirs (CS-001 isolation, see discover_paired_mutation()).
      --into and --out are effectively required in this mode (as before).

  (B) GATES-DIR mode (--gates-dir <dir> given, T074/T058's addition):
      --gate/--into resolved via resolve_gate() -- registry.tsv lookup
      (explicit --registry, else an IMPLICIT <gates-dir>/ledger/registry.tsv
      if present) first, then a filename-SLUG fallback (lowercase, every
      run of non-alnum -> "_", + ".sh") searched recursively under
      --gates-dir. The paired mutation is DISCOVERED by running the
      removed gate's script directly (read-only, no copy needed) against
      every file under <gates-dir>/targets/ (sorted, deterministic): the
      first that PASSes is the clean baseline (CS-003), the first that
      FAILs is the planted mutation (see discover_paired_mutation_gatesdir()).
      --into is OPTIONAL here: omitting it is itself CS-005's "a removal
      without a transferred-mutation record" case and is REFUSED
      immediately (no transfer target named => no transfer to prove).

Either mode: FAIL on the survivor's run of the discovered mutation =>
can_fail=PROVEN => a MutationTransferRecord is written to --out (if given)
AND to --config's paths.transfer_records_dir (keyed by --gate's id),
exit 0. PASS => can_fail=NOT_PROVEN => refuse, exit 1, no record written.

catchset_compare.py's `compare` subcommand reads this SAME
transfer_records_dir (CS-004/CS-005 cooperating through shared,
inspectable, project-relative state -- never an in-memory coupling
between the two tool invocations).

CS-001 isolation (legacy mode only): every disposable copy is created
under `--workdir` (defaulting to a fresh `tempfile.mkdtemp()` if
--workdir is omitted) via plain file copy, never touching
paths.base_tree_dirs itself. Gates-dir mode never mutates anything -- it
runs gate scripts read-only against pre-existing fixture target files, so
no disposable copy is needed there.

classify --config <cfg> --gate <gate_id> [--registry <tsv>] [--deferrals <tsv>]
          [--gates-dir <dir>]

Resolves <gate_id> via resolve_gate() (see gates-dir mode above; when
--gates-dir is omitted this falls back to the legacy --config
gate_search_dirs header-scan) and classifies it into the T-C08 taxonomy:
  "executing"   -- a real script/body was found AND it contains a
                   reachable fail-signal (log_fail / exit N>0 / return N>0
                   / the ${RED}-FAIL echo convention / an ERRORS-counter
                   increment -- see FAIL_SIGNAL_RE) -- it can genuinely FAIL.
  "vacuous"     -- a real script/body was found but contains NO such
                   fail-signal anywhere -- structurally incapable of
                   failing (DEC-32/T-C08: "no mutation can make it fail").
  "named-only"  -- no script/body was found for this id, but it IS present
                   in the --deferrals ledger (§11.4.227 registered
                   deferral) -- named, not yet backed by an executing
                   check.
  "unresolved"  -- no script/body AND no registered deferral (a genuine
                   audit finding, counted as "refused" by `audit`).
A thin-wrapper gate that sources a sibling `lib/*.sh` engine (the
§11.4.251 role-as-data-pack pattern this project's own
`cm_covenant_114_<N>_propagation.sh` family uses) is classified by
reading BOTH the wrapper's own text AND every `lib/*.sh` file sitting
next to it (see read_gate_body_with_siblings()) -- a wrapper whose own
few lines show no fail-signal but whose sourced engine genuinely branches
is correctly "executing", not a false "vacuous".

audit --config <cfg> [--registry <tsv> --deferrals <tsv> --gates-dir <dir>]
      [--corpus <path>] [--out <path>]

Two modes:
  REGISTRY mode (--registry + --gates-dir): classifies EVERY gate id
  present in --registry, reporting gate_count / refused_count (ids that
  resolve to neither a script nor a registered deferral -- "unresolved")
  / a per-gate classification list. Mirrors the T-C08 "lists each gate
  id's executing body ... and paired mutation" audit-table requirement
  for a directory-of-scripts gate family.

  CORPUS mode (--corpus <path>, this commit's T074 real-deliverable path):
  audits a SINGLE MONOLITHIC file containing MANY inline gate checks (the
  shape device/rockchip/rk3588/tests/pre_build_verification.sh actually
  is -- one bash file, thousands of `CM-*`-labelled inline checks, not
  separate per-gate scripts). Extracts every `CM-*` token (dehyphenating
  prose line-wraps first -- see extract_corpus_token_counts()'s own
  docstring for the forensic false-positive this closes), finds the
  SINGLE-MENTION subset (T-C08's own "for the 182 single-mention ids,
  classify" scope), and classifies each by inspecting its real
  surrounding source block (see classify_corpus_occurrence()) -- never a
  synthetic/invented body. Read-only: never modifies the corpus file.

Exit codes (C-001): 0 accepted / clean audit (transfer-proof PROVEN,
audit refused_count==0), 1 a finding (transfer-proof refused,
audit refused_count>0), 2 usage/config error, 4 BLIND (a required input
could not be read).
"""
import argparse
import collections
import hashlib
import json
import os
import re
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


def discover_paired_mutation_gatesdir(gates_dir, gate_script):
    """GATES-DIR mode paired-mutation discovery (CS-005, DEC-32). The
    legacy discover_paired_mutation() above applies a candidate PATCH that
    wholesale-replaces one base_tree file; a gates-dir fixture family
    instead ships its candidate scenarios as STANDALONE target files
    under <gates-dir>/targets/, each one runnable DIRECTLY (read-only, no
    disposable copy needed since nothing is ever mutated -- CS-001
    isolation is trivially satisfied by never writing anything).

    Returns (mutated_target_path_or_None, clean_target_path_or_None): the
    FIRST target under targets/ (sorted, deterministic) that makes
    gate_script FAIL is the discovered planted mutation; the FIRST target
    that makes it PASS is the clean baseline (CS-003 baseline sanity) --
    mirrors discover_paired_mutation()'s own clean-then-patched shape,
    minus the patch-application step this mode does not need.
    """
    targets_dir = os.path.join(gates_dir, "targets")
    if not os.path.isdir(targets_dir):
        return None, None
    clean_target = None
    mutated_target = None
    for name in sorted(os.listdir(targets_dir)):
        full = os.path.join(targets_dir, name)
        if not os.path.isfile(full):
            continue
        verdict = run_gate(gate_script, full)
        if verdict is True and clean_target is None:
            clean_target = full
        elif verdict is False and mutated_target is None:
            mutated_target = full
    if clean_target is None:
        # Baseline sanity itself failed (or the removed gate genuinely
        # PASSes on every target on disk) -- no honest pairing can be
        # discovered from this fixture set.
        return None, None
    return mutated_target, clean_target


# ---------------------------------------------------------------------------
# T-C08 / T074 -- gate classification (classify + audit subcommands)
# ---------------------------------------------------------------------------
#
# Taxonomy (plan.md T-C08 "Work:" line): for a single-mention gate id,
# classify executing / named-only (ledger deferral per §11.4.227) /
# vacuous (no mutation can make it fail). Two independent gate-body
# SOURCES feed this classifier:
#   (1) a real per-gate SCRIPT file (gates-dir / registry.tsv mode --
#       classify_gate() below), and
#   (2) an EXTRACTED SNIPPET of a monolithic multi-gate corpus file like
#       pre_build_verification.sh (corpus mode -- classify_corpus_occurrence()
#       below). Both funnel through the SAME fail-signal vocabulary
#       (FAIL_SIGNAL_RE) so "can this body ever fail" is answered
#       identically regardless of which shape the gate's real check takes
#       -- no divergent, un-cross-checked second classifier (§11.4.251).

# A gate BODY is classified "executing" iff it contains a reachable
# FAIL-signalling call. Four real, independently-verified conventions this
# project's own gate code uses (never invented -- every one of these was
# found live in either the toy fixtures under tests/fixtures/gate_audit/
# or in device/rockchip/rk3588/tests/pre_build_verification.sh itself
# while this classifier was being built and tuned against real bodies):
#   * `log_fail` / `return N>0` / `exit N>0` -- the toy fixture + shared-
#     lib convention (gate_executing.sh, covenant_propagation_engine.sh).
#   * `${RED}` -- pre_build_verification.sh's own ANSI-colour FAIL
#     convention (RED='\033[0;31m'; 683 of 686 real ${RED} occurrences in
#     that file are literally "${RED}FAIL", measured directly, control-
#     needled against the 3 non-FAIL occurrences which are the summary
#     line + the log_fail() definition itself -- both still genuinely
#     fail-signalling, so the needle strengthens rather than weakens this
#     signal).
#   * `ERRORS=$((ERRORS+1))` (or spaced variants) -- the raw counter-
#     increment form some inline checks use instead of calling log_fail.
FAIL_SIGNAL_RE = re.compile(
    r"\blog_fail\b"
    r"|\bexit\s+[1-9][0-9]*\b"
    r"|\breturn\s+[1-9][0-9]*\b"
    r"|\$\{RED\}"
    r"|\bERRORS\s*=\s*\$\(\(\s*ERRORS"
)


def slugify_gate_id(gate_id):
    """gate_id -> filename-slug: lowercase, every run of non-[a-z0-9]
    collapsed to a single "_", leading/trailing "_" stripped. Matches
    this project's own real naming convention verbatim (verified live,
    2026-09-30): "CM-COVENANT-114-162-PROPAGATION" -> the real, on-disk
    "cm_covenant_114_162_propagation.sh" under constitution/scripts/gates/
    -- not a guess, confirmed by diffing the fixture's real_sample/ copies
    against that live file (byte-identical)."""
    return re.sub(r"[^a-z0-9]+", "_", gate_id.lower()).strip("_")


def find_gate_script_by_slug(gates_dir, gate_id):
    """Recursively searches gates_dir for a file named slugify(gate_id)+".sh".
    Used as the gates-dir-mode fallback when no registry entry resolves the
    id (or no registry was given at all -- e.g. the real_sample/ fixture
    family, which ships real repo files under their real, convention-
    matching names and no registry.tsv)."""
    target_name = slugify_gate_id(gate_id) + ".sh"
    for dirpath, dirnames, filenames in os.walk(gates_dir):
        dirnames[:] = [d for d in dirnames if not d.startswith(".")]
        if target_name in filenames:
            return os.path.join(dirpath, target_name)
    return None


def load_registry_tsv(path):
    """<gate_id>\\t<script-path-relative-to-gates-dir-or-"NONE">[\\t...]
    rows, comment (#) and blank lines inert. Returns {gate_id: raw_field}."""
    rows = {}
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line or line.lstrip().startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) < 2:
                continue
            rows[parts[0]] = parts[1]
    return rows


def load_deferrals_tsv(path):
    """<gate_id>\\t<tracked-item-id>[\\t<note>] rows -- the SAME schema as
    the real constitution/scripts/gates/gate_ledger_deferrals.tsv (§11.4.227
    registered-deferral ledger this project already ships). Returns
    {gate_id: tracked_item_id}."""
    rows = {}
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line or line.lstrip().startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) < 2:
                continue
            rows[parts[0]] = parts[1]
    return rows


def resolve_gate(gate_id, gates_dir, registry_path, deferrals_path, cfg, root):
    """Resolves gate_id -> {"script": path|None, "resolution": str,
    "registry_entry": raw|None, "deferral_item": tracked_id|None}.

    Resolution order (first match wins), never a guess (§11.4.6):
      1. --registry (explicit, or an IMPLICIT <gates_dir>/ledger/registry.tsv
         when gates_dir is given and no explicit --registry was passed --
         matching this fixture family's own on-disk layout convention)
         -- an id mapped to the literal "NONE" is a deliberate named-only
         entry (script=None immediately, no further search); an id mapped
         to a real relative path that does not exist on disk falls
         through rather than being silently trusted.
      2. gates_dir slug-fallback (find_gate_script_by_slug) -- for a
         family shipping real, convention-named scripts with no registry
         at all (real_sample/).
      3. LEGACY header-scan via cfg's gate_search_dirs (find_gate_script)
         -- ONLY when gates_dir was not given at all (preserves T050's
         existing, unmodified contract exactly).
      4. Unresolved: script=None; deferral_item is still looked up (an id
         can be a registered deferral even with no registry entry citing
         it, or with a registry entry whose script path is stale).
    """
    registry_path_used = registry_path
    if gates_dir and not registry_path_used:
        implicit = os.path.join(gates_dir, "ledger", "registry.tsv")
        if os.path.isfile(implicit):
            registry_path_used = implicit

    deferrals_path_used = deferrals_path
    if gates_dir and not deferrals_path_used:
        implicit_d = os.path.join(gates_dir, "ledger", "deferrals.tsv")
        if os.path.isfile(implicit_d):
            deferrals_path_used = implicit_d

    registry = load_registry_tsv(registry_path_used) if registry_path_used else None
    deferrals = load_deferrals_tsv(deferrals_path_used) if deferrals_path_used else {}

    if registry is not None and gate_id in registry:
        raw = registry[gate_id]
        if raw.strip().upper() == "NONE":
            return {
                "script": None,
                "resolution": "registry-none",
                "registry_entry": raw,
                "deferral_item": deferrals.get(gate_id),
            }
        base = gates_dir if gates_dir else root
        script_path = os.path.join(base, raw)
        if os.path.isfile(script_path):
            return {
                "script": script_path,
                "resolution": "registry",
                "registry_entry": raw,
                "deferral_item": None,
            }
        # Registry cites a script path that does not exist on disk -- fall
        # through to the other resolution strategies rather than trusting
        # a stale registry row (§11.4.6 no-guessing).

    if gates_dir:
        hit = find_gate_script_by_slug(gates_dir, gate_id)
        if hit:
            return {
                "script": hit,
                "resolution": "slug",
                "registry_entry": None,
                "deferral_item": None,
            }

    if not gates_dir:
        hs = find_gate_script(cfg, root, gate_id)
        if hs:
            return {
                "script": hs,
                "resolution": "header-scan",
                "registry_entry": None,
                "deferral_item": None,
            }

    return {
        "script": None,
        "resolution": "none",
        "registry_entry": None,
        "deferral_item": deferrals.get(gate_id),
    }


def read_gate_body_with_siblings(script_path):
    """Reads script_path's own text PLUS every `lib/*.sh` file sitting in
    a `lib/` subdirectory next to it (the §11.4.251 thin-wrapper /
    role-as-data-pack pattern this project's own cm_covenant_114_<N>_
    propagation.sh family uses -- see that family's own header: "the code
    lives ONCE in lib/covenant_propagation_engine.sh"). A wrapper whose
    own few lines show no fail-signal but whose sourced engine genuinely
    branches is thereby correctly classified "executing", not a false
    "vacuous" (verified live against the 5 real, frozen
    cm_covenant_114_{162,167,176,187,190}_propagation.sh files).

    Honest boundary (§11.4.6): this unconditionally includes every
    lib/*.sh sibling (never attempts to parse which one a dynamic
    `. "$_engine"`-style source line actually resolves to at runtime --
    that path is itself a shell variable, not a literal this tool can
    statically resolve). A gate sharing a lib/ directory with an
    unrelated gate's engine could theoretically borrow a false
    "executing" signal from a sibling it does not actually source; no
    such case was found in this project's real corpus, and it is a
    documented, coarse-but-honest limitation, not a silent one.
    """
    parts = []
    try:
        with open(script_path, "r", encoding="utf-8", errors="replace") as fh:
            parts.append(fh.read())
    except OSError:
        return ""
    lib_dir = os.path.join(os.path.dirname(script_path), "lib")
    if os.path.isdir(lib_dir):
        for name in sorted(os.listdir(lib_dir)):
            if name.endswith(".sh"):
                try:
                    with open(os.path.join(lib_dir, name), "r", encoding="utf-8", errors="replace") as fh:
                        parts.append(fh.read())
                except OSError:
                    continue
    return "\n".join(parts)


def classify_gate(res):
    """Classifies a resolve_gate() result into the T-C08 taxonomy.
    Returns one of "executing" / "vacuous" / "named-only" / None
    (None = genuinely unresolved -- no script, no deferral; callers treat
    this as a `audit` "refused" finding)."""
    if res["script"]:
        body = read_gate_body_with_siblings(res["script"])
        return "executing" if FAIL_SIGNAL_RE.search(body) else "vacuous"
    if res["deferral_item"]:
        return "named-only"
    return None


# --- corpus (monolithic multi-gate file) mode ---

CORPUS_TOKEN_RE = re.compile(r"CM-[A-Z0-9][A-Z0-9-]*")
CORPUS_HEADER_RE = re.compile(r'^\s*echo\s+-n\s+"\s*CM-')
CORPUS_BOUNDARY_RE = re.compile(r"^#\s*---\s*end|^_fc_section_boundary\b|^#\s*={10,}")
CORPUS_CALL_SITE_RE = re.compile(
    r"^\s*(_r5_run_gate|check_config_(set|str|off|range)|_check_fork_apk_label)\b"
)
CORPUS_WINDOW_CAP = 400


def _corpus_norm_token(tok):
    return re.sub(r"[-.,:;)]+$", "", tok)


def extract_corpus_token_counts(raw_text):
    """Extracts every CM-* token and its total mention count from raw_text.

    Forensic finding (measured live against pre_build_verification.sh
    while building this tool, 2026-09-30): a naive per-line regex
    extraction produces SPURIOUS single-mention "ids" from prose comment
    word-wrap -- e.g. a comment line ending "...CM-AF-RECENTS-\\n" whose
    very next line continues "# CLEAR-ALL-TEST already proves..." is
    counted as a bare, standalone "CM-AF-RECENTS" token distinct from the
    real "CM-AF-RECENTS-CLEAR-ALL-TEST"/"CM-AF-RECENTS-CLEAR-ALL-OVERLAY"
    ids mentioned elsewhere (confirmed: 16 such spurious tokens found in
    this project's real corpus, e.g. CM-BRANCH-NAME, CM-SYSTEM-STABILITY,
    CM-SPK547, CM-PRESENTER-AUTOSTART -- every one hand-verified to be a
    mid-sentence line-wrap, never a real distinct gate id). Before
    tokenizing, a trailing "-" at end of physical line, optionally
    followed by a leading "#" comment marker + whitespace on the next
    line, then a continuing uppercase/digit character, is rejoined -- the
    wrapped comment word is not a second, shorter gate id
    (§11.4.201(7)(a) carrier-vs-thing)."""
    joined = re.sub(r"-\n#?[ \t]*(?=[A-Z0-9])", "-", raw_text)
    counts = collections.Counter(
        _corpus_norm_token(t) for t in CORPUS_TOKEN_RE.findall(joined)
    )
    return counts


def find_corpus_single_mention_occurrences(lines, single_ids):
    """For each id in single_ids, the (0-based) line index of its one real
    occurrence, found by re-tokenizing each physical line individually
    (the dehyphenation above only affects COUNTING; a genuinely
    single-mention id's real occurrence -- after the spurious wrap
    artifacts are excluded from single_ids by the caller -- is always
    intact on one physical line, since every multi-line-split case was a
    spurious wrap artifact and was excluded)."""
    single_set = set(single_ids)
    occ = {}
    for i, line in enumerate(lines):
        for t in CORPUS_TOKEN_RE.findall(line):
            nt = _corpus_norm_token(t)
            if nt in single_set and nt not in occ:
                occ[nt] = i
    return occ


def classify_corpus_occurrence(lines, idx):
    """Classifies a single-mention id's occurrence at 0-based line idx.

    (a) The occurrence line is a bare `#` comment -> "named-only" (a
        citation with no adjacent check body attached to THIS literal
        mention -- includes RETIRED-gate markers, section-header false
        matches, and genuine documentation-only citations).
    (b) The occurrence line is a call-site into a KNOWN, independently-
        verified-branching shared helper (_r5_run_gate / check_config_* /
        _check_fork_apk_label -- each read live and confirmed to contain
        real if/case branching to a FAIL outcome) -> "executing"
        immediately, no forward scan needed.
    (c) Otherwise (the common `echo -n "  CM-<id>: ..."` inline-check-
        header shape): scan FORWARD from idx, bounded by whichever comes
        first -- the NEXT such header line, a recognized section-boundary
        marker (`# --- end ...`, `_fc_section_boundary`, or a
        "# ====...===="-shaped banner -- this project's own real section
        separators, confirmed 588 live occurrences), or a CORPUS_WINDOW_CAP
        safety net. FAIL_SIGNAL_RE searched over that window decides
        executing/vacuous.

    This 3-tier scheme + the two boundary classes were tuned against and
    verified against REAL pre_build_verification.sh content (never
    synthetic): a fixed 80-line cap alone mis-classified a genuinely
    long, real "executing" 40-invariant batch gate as vacuous (window cut
    off before its actual PASS/FAIL decision); widening the cap alone
    then mis-classified a genuinely vacuous WARN-only check
    (CM-OWNED-SUBMODULE-DECOUPLING-DOCS, an `if ...warn_count -gt 0;
    then log_warn ...; fi` with NO else/fail branch at all) as
    "executing" by reading past its section boundary into the NEXT
    section's unrelated log_fail calls. The boundary-aware scan (this
    function) resolved BOTH real cases correctly, hand-verified by
    reading their real surrounding source (see this task's own evidence
    notes for both line numbers).
    """
    line = lines[idx]
    stripped = line.strip()
    if stripped.startswith("#"):
        return "named-only", "comment-only mention (no adjacent check body for this literal occurrence)"
    if CORPUS_CALL_SITE_RE.match(stripped):
        return "executing", "call-site into a shared, independently-verified-branching helper function"
    end = min(len(lines), idx + CORPUS_WINDOW_CAP + 1)
    window = []
    for j in range(idx, end):
        if j != idx:
            probe = lines[j]
            if CORPUS_HEADER_RE.match(probe) or CORPUS_BOUNDARY_RE.match(probe.strip()):
                break
        window.append(lines[j])
    body = "\n".join(window)
    if FAIL_SIGNAL_RE.search(body):
        return "executing", "forward-scanned block (%d lines, bounded by next header/section-boundary) contains a reachable fail-signal" % len(window)
    return "vacuous", "forward-scanned block (%d lines, bounded by next header/section-boundary) contains no fail-signal call; structurally cannot fail" % len(window)


def _transfer_proof_gatesdir(args, cfg, root, removed_id, survivor_id, removed_script, survivor_script, gates_dir):
    """GATES-DIR mode transfer-proof body (both gate scripts already
    resolved by the caller). Discovers the removed gate's planted
    mutation among <gates-dir>/targets/* (see
    discover_paired_mutation_gatesdir()), runs the survivor against it
    read-only, and writes a MutationTransferRecord on PROVEN exactly like
    the legacy cfg-based path does."""
    mutated_target, clean_target = discover_paired_mutation_gatesdir(gates_dir, removed_script)
    del clean_target  # baseline sanity already checked inside the discovery call
    if mutated_target is None:
        print(
            f"transfer-proof: REFUSED -- gate {removed_id!r} has paired_mutation=NONE "
            f"(no target file under {gates_dir}/targets/ makes it FAIL against a "
            "PASSing clean baseline discovered first) -- CS-005"
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

    survivor_pass = run_gate(survivor_script, mutated_target)
    if survivor_pass is True:
        print(
            f"transfer-proof: REFUSED -- surviving gate {survivor_id!r} PASSES "
            f"against {removed_id!r}'s own planted mutation target "
            f"({os.path.basename(mutated_target)}) -- survivor did not fail on "
            "the removed gate's mutation, can_fail=NOT_PROVEN, CS-005"
        )
        result = {
            "schema": SCHEMA_TRANSFER,
            "removed_gate_id": removed_id,
            "into_gate_id": survivor_id,
            "planted_mutation_target": os.path.relpath(mutated_target, root),
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
        "planted_mutation_target": os.path.relpath(mutated_target, root),
        "can_fail_status": "PROVEN",
    }
    record["body_hash"] = body_hash({k: v for k, v in record.items() if k != "run_meta"})

    if args.out:
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
        "transfer-proof: ACCEPTED -- recorded run shows survivor gate fails on "
        "the removed gate's planted mutation target (DEC-32 proof) "
        f"({os.path.basename(mutated_target)}); MutationTransferRecord written"
        + (f" to {args.out} and {tr_dir}/{removed_id}.json" if args.out else f" to {tr_dir}/{removed_id}.json")
    )
    return EXIT_OK


def cmd_transfer_proof(args):
    cfg = load_yaml_config(args.config)
    root = project_root_of(args.config)

    removed_id = args.gate
    survivor_id = args.into
    gates_dir = args.gates_dir

    if not survivor_id:
        # CS-005's own "a removal without a transferred-mutation record is
        # refused" case, at its most literal: no --into survivor gate was
        # even named, so there is no transfer target and therefore no
        # transfer record can ever exist for this removal. Refuse
        # immediately -- no gate resolution, no mutation discovery, no
        # transfer to prove (T074/T058's ga_bad_no_transfer_record fixture).
        print(
            f"transfer-proof: REFUSED -- gate {removed_id!r} has no --into "
            "survivor gate specified; a removal with no transfer target "
            "produces no transfer record at all (CS-005: a removal without "
            "a transferred-mutation record is refused) -- there is no "
            "transfer to prove"
        )
        result = {
            "schema": SCHEMA_TRANSFER,
            "removed_gate_id": removed_id,
            "into_gate_id": None,
            "can_fail_status": "NOT_PROVEN",
            "reason": "no_transfer_target_specified",
        }
        _write_refusal(args.out, result)
        return EXIT_FINDING

    if gates_dir:
        removed_res = resolve_gate(removed_id, gates_dir, None, None, cfg, root)
        survivor_res = resolve_gate(survivor_id, gates_dir, None, None, cfg, root)
        removed_script = removed_res["script"]
        survivor_script = survivor_res["script"]
        resolution_note = f"gates-dir {gates_dir!r}"
    else:
        removed_script = find_gate_script(cfg, root, removed_id)
        survivor_script = find_gate_script(cfg, root, survivor_id)
        resolution_note = "registered gate_search_dirs"

    if removed_script is None:
        sys.stderr.write(
            f"gate_audit transfer-proof: gate id {removed_id!r} not found via "
            f"{resolution_note} -- refusing (paired_mutation cannot be "
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
            f"via {resolution_note} -- refusing\n"
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

    if gates_dir:
        return _transfer_proof_gatesdir(args, cfg, root, removed_id, survivor_id, removed_script, survivor_script, gates_dir)

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


def cmd_classify(args):
    """`classify --config <cfg> --gate <id> [--registry] [--deferrals]
    [--gates-dir]` -- reports the single gate's T-C08 classification as a
    JSON object on stdout. Always exits 0 (this subcommand REPORTS; it
    never gates a build -- `audit` is the subcommand that turns an
    unclassifiable id into a nonzero exit)."""
    cfg = load_yaml_config(args.config)
    root = project_root_of(args.config)
    res = resolve_gate(args.gate, args.gates_dir, args.registry, args.deferrals, cfg, root)
    classification = classify_gate(res)
    result = {
        "schema": "gate-classification/v1",
        "gate_id": args.gate,
        "classification": classification if classification is not None else "unresolved",
        "resolution": res["resolution"],
        "script": os.path.relpath(res["script"], root) if res["script"] else None,
        "deferral_item": res["deferral_item"],
    }
    print(json.dumps(result, sort_keys=True))
    return EXIT_OK


def cmd_audit(args):
    """`audit --config <cfg> {--registry --deferrals --gates-dir | --corpus}
    [--out]` -- either mode reports the SAME JSON shape: gate_count,
    refused_count (ids resolving to neither a script nor a registered
    deferral -- an "unresolved"/audit-blocking finding), a per-gate
    classification list, and a classification_counts summary. Exits 0
    when refused_count==0, else EXIT_FINDING (a genuine audit problem)."""
    if args.corpus:
        return cmd_audit_corpus(args)

    if not args.registry or not args.gates_dir:
        sys.stderr.write(
            "gate_audit audit: either --corpus <path>, or both --registry "
            "<tsv> and --gates-dir <dir>, are required\n"
        )
        return EXIT_USAGE

    cfg = load_yaml_config(args.config)
    root = project_root_of(args.config)
    registry = load_registry_tsv(args.registry)

    gates = []
    refused = 0
    class_counts = {"executing": 0, "vacuous": 0, "named-only": 0}
    for gid in registry:
        res = resolve_gate(gid, args.gates_dir, args.registry, args.deferrals, cfg, root)
        classification = classify_gate(res)
        if classification is None:
            refused += 1
            gates.append({"gate_id": gid, "classification": "unresolved", "resolution": res["resolution"]})
            continue
        class_counts[classification] += 1
        gates.append({"gate_id": gid, "classification": classification, "resolution": res["resolution"]})

    result = {
        "schema": "gate-audit/v1",
        "gates_dir": args.gates_dir,
        "registry": args.registry,
        "gate_count": len(registry),
        "refused_count": refused,
        "classification_counts": class_counts,
        "gates": sorted(gates, key=lambda g: g["gate_id"]),
    }
    _write_audit_result(args.out, result)
    print(json.dumps(result, sort_keys=True))
    return EXIT_OK if refused == 0 else EXIT_FINDING


def cmd_audit_corpus(args):
    """`audit --config <cfg> --corpus <path> [--out]` -- CORPUS mode: audits
    a single monolithic multi-gate file (pre_build_verification.sh's own
    shape). See classify_corpus_occurrence()'s docstring for the
    classification method; extract_corpus_token_counts()'s docstring for
    the dehyphenation-vs-prose-wrap forensic finding this closes.
    Read-only: the corpus file is only ever opened for reading. gate_count
    here is the SINGLE-MENTION subset's size (T-C08's own stated scope:
    "for the 182 single-mention ids, classify"), NOT the corpus's total
    unique-token count (reported separately as total_unique_tokens for
    context)."""
    path = args.corpus
    if not os.path.isfile(path):
        sys.stderr.write(f"gate_audit audit: --corpus file not found: {path}\n")
        return EXIT_USAGE
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        raw = fh.read()
    counts = extract_corpus_token_counts(raw)
    if not counts:
        sys.stderr.write(
            f"gate_audit audit: zero CM-* tokens extracted from --corpus {path} -- "
            "needle the corpus (or the extractor) before trusting this as a real "
            "absence (§11.4.201(7)(b))\n"
        )
        return EXIT_BLIND
    single_ids = sorted(k for k, v in counts.items() if v == 1)
    lines = raw.split("\n")
    occ = find_corpus_single_mention_occurrences(lines, single_ids)

    gates = []
    refused = 0
    class_counts = {"executing": 0, "vacuous": 0, "named-only": 0}
    for gid in single_ids:
        idx = occ.get(gid)
        if idx is None:
            # Should not happen once extract_corpus_token_counts()'s own
            # dehyphenation has run (every remaining single-mention id's
            # real occurrence is intact on one physical line) -- if it
            # ever does, this is an honest, counted BLIND finding, never a
            # silently-dropped id.
            refused += 1
            gates.append({"gate_id": gid, "classification": "unresolved", "reason": "no single-line occurrence found after dehyphenation"})
            continue
        classification, reason = classify_corpus_occurrence(lines, idx)
        class_counts[classification] += 1
        gates.append({"gate_id": gid, "classification": classification, "line": idx + 1, "reason": reason})

    result = {
        "schema": "gate-audit-corpus/v1",
        "corpus": path,
        "total_unique_tokens": len(counts),
        "gate_count": len(single_ids),
        "refused_count": refused,
        "classification_counts": class_counts,
        "gates": sorted(gates, key=lambda g: g["gate_id"]),
    }
    _write_audit_result(args.out, result)
    print(json.dumps(result, sort_keys=True, indent=2))
    return EXIT_OK if refused == 0 else EXIT_FINDING


def _write_audit_result(out_path, result):
    if not out_path:
        return
    out_dir = os.path.dirname(os.path.abspath(out_path))
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as fh:
        json.dump(result, fh, sort_keys=True, indent=2)
        fh.write("\n")


# ---------------------------------------------------------------------------
# argparse
#
# All three T-C08/T074 subcommands are registered: transfer-proof (T050/
# T064, gates-dir mode added this commit), classify and audit (T074,
# guarded by test_gate_audit_red.sh / T058).
# ---------------------------------------------------------------------------

def build_parser():
    p = argparse.ArgumentParser(prog="gate_audit.py")
    sub = p.add_subparsers(dest="subcommand", required=True)

    tp = sub.add_parser("transfer-proof")
    tp.add_argument("--config", required=True)
    tp.add_argument("--gate", required=True)
    tp.add_argument("--into", default=None)
    tp.add_argument("--out", default=None)
    tp.add_argument("--workdir", default=None)
    tp.add_argument("--gates-dir", dest="gates_dir", default=None)
    tp.set_defaults(func=cmd_transfer_proof)

    cl = sub.add_parser("classify")
    cl.add_argument("--config", required=True)
    cl.add_argument("--gate", required=True)
    cl.add_argument("--registry", default=None)
    cl.add_argument("--deferrals", default=None)
    cl.add_argument("--gates-dir", dest="gates_dir", default=None)
    cl.set_defaults(func=cmd_classify)

    au = sub.add_parser("audit")
    au.add_argument("--config", required=True)
    au.add_argument("--registry", default=None)
    au.add_argument("--deferrals", default=None)
    au.add_argument("--gates-dir", dest="gates_dir", default=None)
    au.add_argument("--corpus", default=None)
    au.add_argument("--out", default=None)
    au.set_defaults(func=cmd_audit)

    return p


def main(argv):
    parser = build_parser()
    args = parser.parse_args(argv[1:])
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main(sys.argv))
