#!/usr/bin/env bash
# verify_helix_deps_manifests.sh — canonical §11.4.31 dependency-manifest verifier + skeleton generator.
#
# ── Purpose ───────────────────────────────────────────────────────────────
# Every own-org repository of a project MUST carry a tracked, well-formed helix-deps.yaml at its root
# (§11.4.31). This tool walks the project root, every submodule the root declares (the `constitution`
# hub included), every submodule the hub declares, and any checked-out repository under
# <root>/submodules/* or <root>/constitution/submodules/*, and reports one verdict per repository:
#   PASS · FAIL · SKIP(third_party) (never PASS) · KNOWN (hub-engine nesting owned by
#   CM-HUB-ENGINE-NO-OWNORG-NESTING) · BLIND (cannot determine — e.g. an own-org submodule not checked out).
# The schema rules, the walk and the scaffold heuristics live in helix_deps_manifest.py next to this file;
# the full reference is docs/manuals/dependency_manifest_manual.md.
#
# Consumed BY REFERENCE (§11.4.28 / §11.4.177): carries no project literal; the project root is an argument.
#
# ── Usage ─────────────────────────────────────────────────────────────────
#   verify_helix_deps_manifests.sh --root <project-root> [--own-orgs org1,org2]
#   verify_helix_deps_manifests.sh --validate-file <path/to/helix-deps.yaml> [--own-orgs ...]
#   verify_helix_deps_manifests.sh --scaffold <repo-dir> [--write] [--own-orgs ...]
#   verify_helix_deps_manifests.sh --selftest
#   verify_helix_deps_manifests.sh --help
# Own-org list: --own-orgs, else $HELIX_OWN_ORGS, else "vasic-digital,HelixDevelopment".
#
# ── Output ────────────────────────────────────────────────────────────────
#   One line per repository: STATUS<TAB>path<TAB>role<TAB>detail, then
#   `VERDICT: PASS|FAIL|BLIND (pass=… fail=… blind=… skip_third_party=… known=…)`. Parse the VERDICT line.
#
# ── Exit codes ────────────────────────────────────────────────────────────
#   0 PASS · 1 FAIL · 2 BLIND (nothing failed but something could not be verified, or the instrument failed
#   its own control needles) · 64 usage error. --scaffold: 0 printed/written · 1 refused (file exists — it
#   never overwrites) · 2 unreadable directory. --selftest: 0 · 1.
#
# ── Side-effects ──────────────────────────────────────────────────────────
#   Read-only, no network. Only `--scaffold <dir> --write` writes, and only <dir>/helix-deps.yaml when absent.
#
# ── Dependencies ──────────────────────────────────────────────────────────
#   bash, git, python3 with PyYAML. Classification: universal (§11.4.17).
#   Tests: tests/test_verify_helix_deps_manifests.sh. Gate: scripts/gates/cm_helix_deps_manifest_present.sh.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
helper="$here/helix_deps_manifest.py"
if [ ! -r "$helper" ]; then
  printf 'BLIND\t.\tinstrument\thelper %s is missing; nothing was verified\nVERDICT: BLIND\n' "$helper"; exit 2
fi
if ! command -v python3 >/dev/null 2>&1; then
  printf 'BLIND\t.\tinstrument\tpython3 not found on PATH; nothing was verified\nVERDICT: BLIND\n'; exit 2
fi
if ! command -v git >/dev/null 2>&1; then
  printf 'BLIND\t.\tinstrument\tgit not found on PATH; nothing was verified\nVERDICT: BLIND\n'; exit 2
fi
# -I: isolated mode, so nothing in the inspected trees or the current directory can shadow a module.
exec python3 -I "$helper" "$@"
