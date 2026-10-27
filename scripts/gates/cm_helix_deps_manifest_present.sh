#!/usr/bin/env bash
# cm_helix_deps_manifest_present.sh — CM-HELIX-DEPS-MANIFEST-PRESENT gate (§11.4.31 EXTENSION of 2026-10-21).
#
# ── Purpose ───────────────────────────────────────────────────────────────
# Every own-org repository of a project — the project root, the `constitution` hub, every repository under
# <root>/submodules/* and <root>/constitution/submodules/* — MUST carry a tracked, well-formed helix-deps.yaml
# at its root. This gate is the seam wrapper around the canonical engine
# scripts/deps_manifest/verify_helix_deps_manifests.sh (it re-implements nothing) and maps its verdict.
# A third-party repository without a manifest is SKIP(third_party) inside the engine and never makes this gate
# FAIL (golden-FALSE, §11.4.201(1)); an own-org repository that is not checked out is BLIND, never PASS.
#
# ── Usage ─────────────────────────────────────────────────────────────────
#   cm_helix_deps_manifest_present.sh [--root <project-root>] [--own-orgs org1,org2]
#   Default root: the superproject that vendors this constitution, else the constitution root itself.
#
# ── Exit codes ────────────────────────────────────────────────────────────
#   0 PASS · 1 FAIL · 2 BLIND (engine missing, instrument failed its needles, or an own-org repo unreadable)
#   · 64 usage error.
#
# ── Side-effects / dependencies ───────────────────────────────────────────
#   Read-only; bash, git, python3 + PyYAML (via the engine). Classification: universal (§11.4.17).
#   Paired mutation test: cm_helix_deps_manifest_present_mutation_test.sh.
set -uo pipefail
GATE="CM-HELIX-DEPS-MANIFEST-PRESENT"
const="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.." && pwd)"
engine="${HELIX_DEPS_ENGINE:-$const/scripts/deps_manifest/verify_helix_deps_manifests.sh}"
root=""; extra=()
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || { echo "$GATE: --root needs a value" >&2; exit 64; }; root="$2"; shift 2 ;;
    --own-orgs) [ $# -ge 2 ] || { echo "$GATE: --own-orgs needs a value" >&2; exit 64; }; extra+=(--own-orgs "$2"); shift 2 ;;
    -h|--help) sed -n 2,22p "${BASH_SOURCE[0]:-$0}"; exit 0 ;;
    *) echo "$GATE: unknown argument $1" >&2; exit 64 ;;
  esac
done
if [ -z "$root" ]; then
  root="$(git -C "$const" rev-parse --show-superproject-working-tree 2>/dev/null)"
  [ -n "$root" ] || root="$const"
fi
if [ ! -r "$engine" ]; then echo "⚠ $GATE: BLIND (exit 2) — engine missing: $engine"; exit 2; fi
bash "$engine" --root "$root" "${extra[@]}"
rc=$?
case "$rc" in
  0) echo "✅ $GATE: PASS (root=$root)"; exit 0 ;;
  1) echo "❌ $GATE: FAIL — every own-org repository needs a tracked, well-formed helix-deps.yaml (see FAIL lines; guide: constitution/docs/guides/dependency_manifest_user_guide.md)"; exit 1 ;;
  2) echo "⚠ $GATE: BLIND (exit 2) — something could not be verified (see BLIND lines); this is not a PASS"; exit 2 ;;
  *) echo "⚠ $GATE: BLIND (exit 2) — engine returned unexpected rc=$rc"; exit 2 ;;
esac
