#!/usr/bin/env bash
# cm_hub_engine_no_ownorg_nesting.sh — CM-HUB-ENGINE-NO-OWNORG-NESTING gate (§11.4.28(C) EXTENSION of 2026-10-21, §11.4.31, §11.4.277(B)).
#
# ── Purpose ───────────────────────────────────────────────────────────────
# One source of truth: a reusable engine anchored under <hub>/submodules/<engine> MUST declare ZERO own-org nested submodules
# (vasic-digital, HelixDevelopment) and MUST NOT declare the constitution/hub itself. Third-party nested repositories an engine
# really builds against (llama.cpp, colibri, go, ...) are legal. It generalises CM-LLMCTL-SUBMODULE-NONRECURSIVE (which stays).
# Detection is NAME MATCHING on the nested submodule URLs: an owner segment vasic-digital/HelixDevelopment, or a repository named
# constitution / HelixConstitution under ANY owner (case-insensitive). A RELATIVE nested URL (./x or ../x, git's
# superproject-relative form) is first resolved against the engine's own URL in the hub .gitmodules, exactly as
# git does, so ../Containers.git under an own-org engine is own-org; a relative URL that cannot be resolved (no
# parseable base, or more ../ than the base has segments) is BLIND, never a pass. It does not compare trees.
# The engine's .gitmodules is read from the commit the hub RECORDS for it: the staged (index) gitlink when it differs from HEAD's
# (printed as a NOTE), else HEAD's; the checked-out HEAD is a LOUD fallback only when that commit is not resolvable. An engine that
# is not checked out is SKIPPED with a printed reason; when NO engine could be inspected the result is SKIP (exit 3), never PASS.
#
# ── Usage ─────────────────────────────────────────────────────────────────
#   cm_hub_engine_no_ownorg_nesting.sh [--root <hub-root>]        (default: the constitution root two levels above this script)
#
# ── Side-effects ──────────────────────────────────────────────────────────
#   None (read-only git plumbing; no network).
#
# ── Dependencies ──────────────────────────────────────────────────────────
#   bash, git, awk, grep.
#
# ── Exit codes ────────────────────────────────────────────────────────────
#   0 PASS · 1 FAIL (an own-org / hub nested declaration was found) · 2 BLIND (cannot determine)
#   · 3 SKIP (no hub engine was checked out, so nothing was inspected — not a PASS).
#
# Classification: universal (§11.4.17). Paired mutation test: cm_hub_engine_no_ownorg_nesting_mutation_test.sh.
set -uo pipefail
GATE="CM-HUB-ENGINE-NO-OWNORG-NESTING"
root="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.." && pwd)"
while [ $# -gt 0 ]; do
  case "$1" in
    --root) root="$(cd "$2" && pwd)" || exit 2; shift 2 ;;
    -h|--help) sed -n 2,26p "${BASH_SOURCE[0]:-$0}"; exit 0 ;;
    *) echo "$GATE: unknown argument $1" >&2; exit 2 ;;
  esac
done
[ -r "$root/.gitmodules" ] || { echo "$GATE: BLIND — $root/.gitmodules unreadable" >&2; exit 2; }
OWN='(^|[/:])(vasic-digital|helixdevelopment)/'
HUB='(^|[/:])(helixconstitution|constitution)(\.git)?$'
fail=0; blind=0; seen=0
# resolve_url <url> <base> -> prints the absolute URL; returns 1 when a relative URL cannot be resolved.
# git semantics: ./x and ../x are relative to the superproject's URL; each ../ drops one path segment of the base.
resolve_url() {
  local u="$1" b="$2" prefix path part
  case "$u" in ./*|../*) ;; *) printf '%s\n' "$u"; return 0 ;; esac
  case "$b" in ./*|../*|"") return 1 ;; esac
  if [[ "$b" =~ ^([A-Za-z]+://[^/[:space:]]+/)([^[:space:]]+)$ ]]; then prefix="${BASH_REMATCH[1]}"; path="${BASH_REMATCH[2]}"
  elif [[ "$b" =~ ^([A-Za-z0-9._-]+@)?([A-Za-z0-9.-]+):([^/[:space:]][^[:space:]]*)$ ]]; then
    prefix="${BASH_REMATCH[1]}${BASH_REMATCH[2]}:"; path="${BASH_REMATCH[3]}"
  else return 1; fi
  local -a segs=() rel=()
  IFS=/ read -r -a segs <<<"${path%/}"
  IFS=/ read -r -a rel <<<"$u"
  for part in "${rel[@]}"; do
    case "$part" in
      ""|.) ;;
      ..) [ "${#segs[@]}" -gt 0 ] || return 1; unset 'segs[${#segs[@]}-1]'; segs=("${segs[@]}") ;;
      *) segs+=("$part") ;;
    esac
  done
  [ "${#segs[@]}" -gt 0 ] || return 1
  local IFS=/; printf '%s%s\n' "$prefix" "${segs[*]}"
}
pathkeys="$(git config -f "$root/.gitmodules" --get-regexp '^submodule\..*\.path$' | awk '$2 ~ /^submodules\// {print $1 "\t" $2}' || true)"
while IFS=$'\t' read -r key p; do
  [ -n "$p" ] || continue
  base="$(git config -f "$root/.gitmodules" --get "${key%.path}.url" 2>/dev/null || true)"
  sub="$root/$p"
  if ! git -C "$sub" rev-parse --git-dir >/dev/null 2>&1 || [ "$(git -C "$sub" rev-parse --show-toplevel 2>/dev/null)" != "$sub" ]; then
    echo "$GATE: SKIP $p — not checked out; nothing to inspect"; continue
  fi
  seen=$((seen+1))
  rec_head="$(git -C "$root" ls-tree HEAD "$p" 2>/dev/null | awk '$1=="160000"{print $3}')"
  rec_idx="$(git -C "$root" ls-files -s -- "$p" 2>/dev/null | awk '$1=="160000"{print $2}')"
  rec="$rec_head"
  if [ -n "$rec_idx" ] && [ "$rec_idx" != "$rec_head" ]; then
    echo "$GATE: NOTE — $p: using the STAGED (index) gitlink ${rec_idx:0:7}; HEAD records ${rec_head:-<none>}" >&2
    rec="$rec_idx"
  elif [ -z "$rec_idx" ] && [ -z "$rec_head" ]; then
    echo "$GATE: NOTE — $p: no gitlink in the index or in HEAD" >&2
  fi
  src=""
  if [ -n "$rec" ] && [ "$(git -C "$sub" cat-file -t "$rec" 2>/dev/null)" = "commit" ]; then src="$rec"
  else
    echo "$GATE: NOTE — $p: recorded commit ${rec:0:7} not resolvable; FALLING BACK to the checked-out HEAD (less authoritative)" >&2
    src="$(git -C "$sub" rev-parse HEAD 2>/dev/null)" || { echo "$GATE: BLIND — $p has no HEAD" >&2; blind=1; continue; }
  fi
  raw="$(git -C "$sub" show "$src:.gitmodules" 2>/dev/null | awk -F'= *' '/^[[:space:]]*url[[:space:]]*=/{print $2}')"
  if [ -z "$raw" ]; then echo "$GATE: $p@${src:0:7} declares no nested submodule"; continue; fi
  urls=""; unres=""
  while IFS= read -r u; do
    [ -n "$u" ] || continue
    if r="$(resolve_url "$u" "$base")"; then urls+="$r"$'\n'; else unres+="$u "; fi
  done <<<"$raw"
  if [ -n "$unres" ]; then
    echo "$GATE: BLIND — $p@${src:0:7} declares relative nested URL(s) that cannot be resolved against ${base:-<no engine URL>}: $unres" >&2
    blind=1
  fi
  [ -n "$urls" ] || continue
  bad="$(grep -Ei "$OWN|$HUB" <<<"$urls" || true)"
  if [ -n "$bad" ]; then
    echo "$GATE: FAIL — $p@${src:0:7} declares own-org/hub nested submodule(s): $(tr '\n' ' ' <<<"$bad")"; fail=1
  else
    echo "$GATE: $p@${src:0:7} nests only third-party repositories"
  fi
done <<<"$pathkeys"
if [ "$fail" -ne 0 ]; then echo "❌ $GATE: FAIL"; exit 1; fi
if [ "$blind" -ne 0 ]; then echo "⚠ $GATE: BLIND (exit 2)"; exit 2; fi
if [ "$seen" -eq 0 ]; then echo "⚠ $GATE: SKIP (exit 3) — no hub engine is checked out; nothing was inspected (not a PASS)"; exit 3; fi
echo "✅ $GATE: PASS"
