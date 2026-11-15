#!/usr/bin/env python3
# catalog-engine / lib / scan.py
#
# Purpose:   Walk the injected test roots, dispatch each file to its per-type
#            parser, annotate dates/version via gitmeta, derive cluster/component
#            via the injected taxonomy. §11.4.28 — roots + taxonomy are INJECTED.
# Usage:     records = scan_roots(roots, repo, taxonomy, date_index)
# Inputs:    a list of {root, type, glob} root specs; repo path; Taxonomy;
#            DateIndex.
# Outputs:   a list of fully-derived catalog records (§2 schema).
# Side-effects: read-only filesystem walk.
# Dependencies: lib/parse_shell.py, lib/derive.py, lib/gitmeta.py.
# Cross-refs: P0_design.md §3 pipeline.
"""Root-walk + per-type dispatch (decoupled)."""
import os as _ge_os  # git-env-hermetic: clear the caller's repository-locating git variables first (list = CL_GIT_SCRUB_VARS of scripts/lib/constitution_layout.sh; checked by scripts/validation/git_env_class_census.py)
for _ge_v in "GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_PREFIX GIT_COMMON_DIR GIT_OBJECT_DIRECTORY GIT_ALTERNATE_OBJECT_DIRECTORIES GIT_NAMESPACE GIT_SHALLOW_FILE GIT_GRAFT_FILE GIT_REPLACE_REF_BASE GIT_NO_REPLACE_OBJECTS GIT_QUARANTINE_PATH GIT_INTERNAL_SUPER_PREFIX".split(): _ge_os.environ.pop(_ge_v, None)

import fnmatch
import os

import parse_shell  # noqa: E402
import parse_gate  # noqa: E402
import parse_mutation  # noqa: E402
import parse_helixqa  # noqa: E402

# Per-`parser` dispatch (decoupled, §11.4.28). A root spec selects its parser
# explicitly; default "shell" preserves the P1 on-device behaviour. gate /
# mutation parsers consume a SINGLE file (the spec carries `file:` not `glob:`);
# helixqa consumes a glob of bank YAMLs.
_FILE_PARSERS = {
    "gate": parse_gate.parse_gate_file,
    "mutation": parse_mutation.parse_mutation_file,
}
_GLOB_PARSERS = {
    "shell": parse_shell.parse_shell_file,
    "helixqa": parse_helixqa.parse_helixqa_file,
}


def _iter_files(root, glob, maxdepth=None):
    """Walk `root` for files matching `glob`. `maxdepth=1` restricts to the
    top-level directory only (matches the P0 cited 458 on-device subset)."""
    root = os.path.normpath(root)
    base_depth = root.count(os.sep)
    for dirpath, dirs, files in os.walk(root):
        if maxdepth is not None:
            cur_depth = dirpath.count(os.sep) - base_depth
            # maxdepth=1 => emit ONLY the top-level dir's files: clear `dirs` at
            # the root (cur_depth 0) so os.walk never descends. In general,
            # prune once the NEXT level would exceed maxdepth.
            if cur_depth + 1 >= maxdepth:
                dirs[:] = []   # prune deeper recursion
        for fn in sorted(files):
            if fnmatch.fnmatch(fn, glob):
                yield os.path.join(dirpath, fn)


def _annotate(rec, src_path, repo, taxonomy, date_index):
    """Common post-derivation: source_path + git dates + cluster/component.
    Applied to EVERY record regardless of which parser produced it (§11.4.28 —
    the annotation layer is parser-agnostic)."""
    repo_rel = os.path.relpath(src_path, repo)
    rec["source_path"] = repo_rel
    created, updated = date_index.dates(repo_rel)
    rec["created_date"] = created or "UNCONFIRMED"
    rec["updated_date"] = updated or "UNCONFIRMED"
    if not created:
        rec["derivation_gaps"].append("created_date-UNCONFIRMED")
    cluster = taxonomy.cluster_for(rec)
    rec["cluster"] = cluster
    rec["component"] = taxonomy.component_for(rec, cluster)
    if cluster == "uncategorised":
        rec["derivation_gaps"].append("cluster-uncategorised")
    return rec


def scan_roots(root_specs, repo, taxonomy, date_index):
    """Scan each root spec -> list of derived records (per-parser dispatch)."""
    records = []
    seen_ids = set()       # (type, id) de-dup across specs
    for spec in root_specs:
        parser = spec.get("parser", "shell")
        type_root = spec.get("type", "on_device")

        # --- single-file parsers (gate / mutation): spec carries `file:` ------
        if parser in _FILE_PARSERS:
            fpath = spec.get("file")
            if not fpath:
                continue
            abs_file = (os.path.join(repo, fpath)
                        if not os.path.isabs(fpath) else fpath)
            if not os.path.isfile(abs_file):
                continue
            for rec in _FILE_PARSERS[parser](abs_file, type_root):
                key = (type_root, rec["id"])
                if key in seen_ids:
                    continue
                seen_ids.add(key)
                _annotate(rec, abs_file, repo, taxonomy, date_index)
                records.append(rec)
            continue

        # --- glob parsers (shell / helixqa): spec carries `root` + `glob` -----
        root = spec.get("root")
        if not root:
            continue
        glob = spec.get("glob", "test_*.sh")
        maxdepth = spec.get("maxdepth")
        if maxdepth is not None:
            maxdepth = int(maxdepth)
        abs_root = (os.path.join(repo, root)
                    if not os.path.isabs(root) else root)
        if not os.path.isdir(abs_root):
            continue
        glob_parse = _GLOB_PARSERS.get(parser, parse_shell.parse_shell_file)
        for path in _iter_files(abs_root, glob, maxdepth):
            out = glob_parse(path, type_root)
            # shell parser returns ONE dict; helixqa returns a LIST of dicts.
            recs = out if isinstance(out, list) else [out]
            for rec in recs:
                key = (type_root, rec["id"])
                if key in seen_ids:
                    continue
                seen_ids.add(key)
                _annotate(rec, path, repo, taxonomy, date_index)
                records.append(rec)
    return records
