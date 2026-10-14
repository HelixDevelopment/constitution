#!/usr/bin/env bash
# cm_helix_deps_ref_matches_gitlink.sh — CM-HELIX-DEPS-REF-MATCHES-GITLINK gate (§11.4.31, §11.4.201).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# helix-deps.yaml (§11.4.31) records the `ref:` every own-org dependency is
# pinned at; the INDEX records the gitlink that is really pinned. When the two
# disagree the manifest lies about the dependency graph (label-sync review-2
# finding G: a merge kept `ref: d88a007` for continuum while the gitlink was
# 4639347). For every `deps[]` entry this gate finds the gitlink whose
# .gitmodules url equals the entry's ssh_url and asserts the ref resolves to
# exactly that commit:
#   * a hex ref (7..40 chars) must be a prefix of the gitlink sha;
#   * any other ref (a tag) is resolved inside the checked-out submodule
#     (`git -C <path> rev-parse <ref>^{commit}`) and must equal the gitlink.
# A dep with no matching gitlink, or a tag that cannot be resolved (submodule
# not checked out, tag absent locally), is BLIND — never a PASS.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_helix_deps_ref_matches_gitlink.sh [--root <constitution-root>]
#
# ── Inputs ───────────────────────────────────────────────────────────────────
#   <root>/helix-deps.yaml, <root>/.gitmodules, the index of <root>.
#
# ── Outputs ──────────────────────────────────────────────────────────────────
#   One MATCH / DRIFT / BLIND line per dependency and a verdict line.
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   None (read-only git plumbing; no network).
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, git, awk.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.31, §11.4.201, §11.4.6, §1.1 (paired mutation:
#   cm_helix_deps_ref_matches_gitlink_mutation_test.sh).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 every ref matches its gitlink · 1 at least one DRIFT · 2 BLIND (cannot
#   determine; never a pass).
#
# Classification: universal (§11.4.17).
set -uo pipefail
GATE="CM-HELIX-DEPS-REF-MATCHES-GITLINK"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
root="${SCRIPT_DIR}/../.."
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || { echo "$GATE: --root requires a value" >&2; exit 2; }; root="$2"; shift 2 ;;
    -h|--help) sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "$GATE: unknown arg '$1'" >&2; exit 2 ;;
  esac
done
root="$(cd "$root" 2>/dev/null && pwd)" || { echo "$GATE: root not found" >&2; exit 2; }
man="$root/helix-deps.yaml"
[ -r "$man" ] || { echo "$GATE: BLIND — $man not readable"; exit 2; }
[ -r "$root/.gitmodules" ] || { echo "$GATE: BLIND — .gitmodules not readable"; exit 2; }

# name<TAB>ssh_url<TAB>ref for every deps[] entry (simple, schema-v1 layout)
entries="$(awk '
  /^deps:/ {in_deps=1; next}
  in_deps && /^[A-Za-z_]/ {in_deps=0}
  !in_deps {next}
  /^  - name:/ { if (n!="") print n "\t" u "\t" r; n=$3; u=""; r=""; next }
  /^    ssh_url:/ { u=$2; next }
  /^    ref:/ { r=$2; next }
  END { if (n!="") print n "\t" u "\t" r }' "$man")"
[ -n "$entries" ] || { echo "$GATE: BLIND — no deps[] entries parsed from $man (control: the instrument saw nothing)"; exit 2; }

drift=0 blind=0 n=0
while IFS=$'\t' read -r name url ref; do
  n=$((n+1))
  key="$(git -C "$root" config -f .gitmodules --get-regexp '^submodule\..*\.url$' 2>/dev/null | awk -v u="$url" '$2==u{print $1; exit}')"
  if [ -z "$key" ] || [ -z "$ref" ]; then echo "❓ BLIND  $name: no .gitmodules entry with url $url (or no ref)"; blind=1; continue; fi
  path="$(git -C "$root" config -f .gitmodules --get "${key%.url}.path" 2>/dev/null)"
  sha="$(git -C "$root" ls-files -s -- "$path" 2>/dev/null | awk '$1=="160000"{print $2; exit}')"
  if [ -z "$sha" ]; then echo "❓ BLIND  $name: no gitlink at $path"; blind=1; continue; fi
  if [[ $ref =~ ^[0-9a-f]{7,40}$ ]]; then
    want="$ref"; case "$sha" in "$ref"*) ok=1 ;; *) ok=0 ;; esac   # MUT:prefix
  else
    want="$(git -C "$root/$path" rev-parse --verify -q "${ref}^{commit}" 2>/dev/null)"
    if [ -z "$want" ]; then echo "❓ BLIND  $name: tag '$ref' not resolvable in $path (not checked out / tag absent)"; blind=1; continue; fi
    [ "$want" = "$sha" ] && ok=1 || ok=0
  fi
  if [ "$ok" = 1 ]; then echo "✅ MATCH  $name: ref $ref == gitlink ${sha:0:12} ($path)"
  else echo "❌ DRIFT  $name: ref $ref (${want:0:12}) != gitlink ${sha:0:12} ($path)"; drift=1; fi
done <<<"$entries"

echo "----------------------------------------------------------------------"
if [ "$drift" = 1 ]; then echo "❌ $GATE: FAIL — helix-deps.yaml disagrees with the index ($n deps)"; exit 1; fi
if [ "$blind" = 1 ]; then echo "❓ $GATE: BLIND — at least one dep could not be determined ($n deps)"; exit 2; fi
echo "✅ $GATE: PASS — all $n deps match their gitlinks"
exit 0
