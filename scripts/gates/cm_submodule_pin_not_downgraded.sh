#!/usr/bin/env bash
# cm_submodule_pin_not_downgraded.sh — CM-SUBMODULE-PIN-NOT-DOWNGRADED gate (CON-046; §11.4.288(D), §11.4.233(G), §11.4.201, §11.4.271).
#
# ── Purpose ───────────────────────────────────────────────────────────────
# A snapshot-style commit (`git add -A` / `commit -a`) records the HEAD of each submodule WORKTREE, not the pin the
# superproject last recorded. When a pin was advanced in the index without moving the checkout, such a commit silently
# moves the gitlink BACK to an ancestor (forensic FACT 2026-11-05: commit 724d818 moved containers 5ea870a -> 22b4970,
# an ancestor; repaired by 84084a2). This gate refuses a STAGED gitlink change whose new commit is a strict ancestor of
# the old pin.
#
# ── What it guards (and what it does not — §11.4.6) ───────────────────────
# It inspects the git INDEX (`git diff --cached`): it guards any commit path that runs this gate before committing
# (a git pre-commit hook, e.g. scripts/hooks/pre-commit-submodule-pin-not-downgraded, or a commit wrapper). The tool that
# produced the "Auto-commit <ms>" commits is UNIDENTIFIED (UNCONFIRMED); the gate is NOT proven to catch commits made by
# that tool, because it only runs if that tool honours git hooks / calls this script. It does not guard `git commit
# --no-verify` or commits made through plumbing.
#
# ── Verdicts ──────────────────────────────────────────────────────────────
#   FAIL  staged gitlink new commit is a strict ancestor of the old pin and no valid waiver covers (path,new sha).
#   BLIND the submodule (or one of the two commits) cannot be resolved locally — never a pass (§11.4.201).
#   PASS  no staged gitlink change, forward bump, diverged commit, new/deleted gitlink, or a valid waiver.
# Waiver (§11.4.271-style, intentional rollbacks): file <root>/.submodule_pin_waivers (override: --waivers FILE),
# TAB-separated: path  new_sha  authoriser  expiry(YYYY-MM-DD)  tracked_item — all five non-empty, expiry not elapsed.
#
# ── Usage ─────────────────────────────────────────────────────────────────
#   cm_submodule_pin_not_downgraded.sh [--root <repo>] [--waivers <file>]
# Exit: 0 PASS · 1 FAIL · 2 BLIND/usage. Read-only (git plumbing, no network). Deps: bash, git, awk, date.
# Classification: universal (§11.4.17). Paired mutation test: cm_submodule_pin_not_downgraded_mutation_test.sh.
set -uo pipefail
GATE="CM-SUBMODULE-PIN-NOT-DOWNGRADED"
root="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.." && pwd)"; waivers=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) root="$(cd "${2:?--root needs a value}" && pwd)" || exit 2; shift 2 ;;
    --waivers) waivers="${2:?--waivers needs a value}"; shift 2 ;;
    -h|--help) sed -n 2,30p "${BASH_SOURCE[0]:-$0}"; exit 0 ;;
    *) echo "$GATE: unknown argument $1" >&2; exit 2 ;;
  esac
done
waivers="${waivers:-$root/.submodule_pin_waivers}"
git -C "$root" rev-parse --git-dir >/dev/null 2>&1 || { echo "$GATE: BLIND — $root is not a git repository" >&2; exit 2; }
today="$(date +%Y-%m-%d)"
waived() { # <path> <new_sha> -> 0 when a complete, unexpired waiver exists
  [ -r "$waivers" ] || return 1
  awk -F'\t' -v p="$1" -v n="$2" -v t="$today" \
    '$1!~/^#/ && $1==p && $2==n && $3!="" && $4!="" && $5!="" && $4>=t {f=1} END{exit f?0:1}' "$waivers"
}
fail=0; blind=0; checked=0
while IFS=$'\t' read -r meta path; do
  [ -n "$path" ] || continue
  set -- $meta; om="${1#:}"; nm="$2"; osha="$3"; nsha="$4"
  [ "$om" = 160000 ] && [ "$nm" = 160000 ] || continue
  [ "$osha" != "$nsha" ] || continue
  checked=$((checked+1)); sub="$root/$path"
  if ! git -C "$sub" rev-parse --git-dir >/dev/null 2>&1 || [ "$(git -C "$sub" rev-parse --show-toplevel 2>/dev/null)" != "$sub" ] \
     || ! git -C "$sub" cat-file -e "${osha}^{commit}" 2>/dev/null || ! git -C "$sub" cat-file -e "${nsha}^{commit}" 2>/dev/null; then
    echo "$GATE: BLIND $path — submodule or one of ${osha:0:7}/${nsha:0:7} not resolvable locally; cannot judge"; blind=1; continue
  fi
  if git -C "$sub" merge-base --is-ancestor "$nsha" "$osha" 2>/dev/null; then
    if waived "$path" "$nsha"; then echo "$GATE: WAIVED $path ${osha:0:7} -> ${nsha:0:7} (waiver in $waivers)"
    else echo "$GATE: FAIL $path — staged pin ${nsha:0:7} is an ANCESTOR of the recorded pin ${osha:0:7} (downgrade). Advance the submodule checkout to the pin (git submodule update) or add a waiver"; fail=1; fi
  else echo "$GATE: ok $path ${osha:0:7} -> ${nsha:0:7} (not a downgrade)"; fi
done < <(git -C "$root" diff --cached --raw --no-abbrev --no-renames --ignore-submodules=none | awk -F'\t' '{print $1 "\t" $2}')
[ "$fail" = 1 ] && exit 1
[ "$blind" = 1 ] && exit 2
echo "$GATE: PASS ($checked staged gitlink change(s) inspected)"; exit 0
