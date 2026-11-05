#!/usr/bin/env bash
# cm_submodule_pin_not_downgraded.sh — CM-SUBMODULE-PIN-NOT-DOWNGRADED gate (CON-046; §11.4.288(D), §11.4.233(G), §11.4.201).
#
# ── Purpose ───────────────────────────────────────────────────────────────
# A snapshot-style commit (`git add -A` / `commit -a`) records the HEAD of each submodule WORKTREE, not the pin the
# superproject last recorded. When a pin was advanced in the index without moving the checkout, such a commit silently
# moves the gitlink BACK to an ancestor (forensic FACT 2026-11-05: commit 724d818 moved containers 5ea870a -> 22b4970,
# an ancestor; repaired by 84084a2). This gate refuses a STAGED gitlink change whose new commit is a strict ancestor of
# the old pin.
#
# ── Status of CON-046 (§11.4.115(G) / §11.4.292(D)) ───────────────────────
# DEFENSIVE HARDENING ONLY. The mechanism was reproduced as a HOST FIXTURE (a snapshot commit over a stale checkout);
# the tool that produced the real "Auto-commit <ms>" commits is UNIDENTIFIED (UNCONFIRMED), so this change does NOT close
# CON-046: the item stays OPEN and UNREPRODUCED for the real tool.
#
# ── What it guards (and what it does not — §11.4.6) ───────────────────────
# It inspects the git INDEX (`git diff --cached`) and guards commit paths that RUN git's pre-commit hook (or call this
# script). NOT guarded (measured): `git commit --no-verify`; plumbing (commit-tree, update-ref); and commit paths that
# do not run pre-commit at all: `git merge` (auto-commit and --ff-only), `cherry-pick`, `revert`, `rebase`. Therefore
# a downgrade made on a vehicle branch can still land on `main` by ff-only merge (the §11.4.288(B)(3) landing path has no
# hook in scratch clones). Per-commit index diffs also miss a downgrade split across commits or combined with a path
# move. A `--range A..B` mode for a pre-push / landing seam is a FOLLOW-UP (not built). The hook (scripts/hooks/
# pre-commit-submodule-pin-not-downgraded) is shipped, NOT installed anywhere (operator consent).
#
# ── Verdicts ──────────────────────────────────────────────────────────────
#   FAIL  staged gitlink new commit is a strict ancestor of the old pin and no valid waiver covers (path,new sha).
#   BLIND the submodule or one of the two commits cannot be resolved, OR ancestry cannot be decided (git
#         merge-base rc other than 0/1, or rc 1 in a SHALLOW submodule): never a pass (§11.4.201). The message names the
#         cause and the fix (e.g. `git submodule update --init -- <path>`, `git -C <path> fetch --unshallow`).
#   WARN  (exit 0, visible) diverged move: new pin neither ancestor nor descendant of the old pin; old pin's commits may
#         be dropped from the superproject history — review by hand (reachability from upstream main is the owed
#         CM-SUBMODULE-POINTER-ON-MAIN, OWED-GATE-151).
#   PASS  no staged gitlink change, forward bump, diverged (WARN), new/deleted gitlink, or a valid waiver.
#
# ── Waiver (intentional rollbacks) — what IS and IS NOT enforced ─────────
# File `.submodule_pin_waivers` read from the git INDEX (so it must be STAGED in the same, reviewable commit; an
# untracked/unstaged file is ignored). TAB-separated, 5 fields: path  new_sha  authoriser  expiry  tracked_item.
# ENFORCED: all five non-empty; expiry strictly YYYY-MM-DD, a real calendar date, not before today (valid through the
# expiry day inclusive); tracked_item matches CON-NNN (the repo's item-id format; NOT checked to exist in the tracker);
# authoriser differs from the committer identity (git var GIT_COMMITTER_IDENT name or email, case-insensitive).
# NOT ENFORCED: no authoriser ROSTER exists in this repository, so the authoriser is NOT verified to be a rostered
# non-producer human — a producer can still name a second identity. This is therefore a speed bump with an audit trail,
# NOT an §11.4.271-conformant waiver; CM-WAIVER-ROSTERED-EXPIRY-TRACKED remains owed. `--waivers FILE` overrides the
# source with a plain file (tests/explicit use; the hook never uses it).
#
# ── Usage ─────────────────────────────────────────────────────────────────
#   cm_submodule_pin_not_downgraded.sh [--root <repo>] [--waivers <file>]
# Exit: 0 PASS · 1 FAIL · 2 BLIND (a usage error also exits 2). Read-only (git plumbing, no network). Deps: bash, git, awk, date.
# Submodule git calls run with GIT_DIR/GIT_WORK_TREE/GIT_INDEX_FILE/... removed (git exports them to hooks, notably in a
# linked worktree); the superproject index read keeps them (needed for `commit -a`'s temporary index).
# Classification: universal (§11.4.17). Paired mutation test: cm_submodule_pin_not_downgraded_mutation_test.sh.
set -uo pipefail
GATE="CM-SUBMODULE-PIN-NOT-DOWNGRADED"
root="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.." && pwd -P)"; waivers=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) root="$(cd "${2:?--root needs a value}" && pwd -P)" || exit 2; shift 2 ;;
    --waivers) waivers="${2:?--waivers needs a value}"; shift 2 ;;
    -h|--help) sed -n 2,40p "${BASH_SOURCE[0]:-$0}"; exit 0 ;;
    *) echo "$GATE: unknown argument $1" >&2; exit 2 ;;
  esac
done
sg() { env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_PREFIX -u GIT_COMMON_DIR -u GIT_OBJECT_DIRECTORY -u GIT_ALTERNATE_OBJECT_DIRECTORIES git "$@"; }
git -C "$root" rev-parse --git-dir >/dev/null 2>&1 || { echo "$GATE: BLIND — $root is not a git repository" >&2; exit 2; }
today="$(date +%Y-%m-%d)"
if [ -n "$waivers" ]; then wsrc="file $waivers"; wtext="$(cat "$waivers" 2>/dev/null)"
else wsrc="index :.submodule_pin_waivers"; wtext="$(git -C "$root" show :.submodule_pin_waivers 2>/dev/null)"; fi
ident="$(git -C "$root" var GIT_COMMITTER_IDENT 2>/dev/null)"; cname="${ident%% <*}"; cmail="${ident#*<}"; cmail="${cmail%%>*}"
WHY=""
waived() { # <path> <new_sha> -> 0 when a complete, valid waiver exists; sets WHY otherwise
  WHY="no waiver row for (path,new sha) in $wsrc"
  [ -n "$wtext" ] || { WHY="no waiver data ($wsrc)"; return 1; }
  local cand a e i
  cand="$(printf '%s\n' "$wtext" | awk -F'\t' -v p="$1" -v n="$2" \
    'NF==5 && $1!~/^#/ && $1==p && $2==n {print $3 "\037" $4 "\037" $5}')"
  [ -n "$cand" ] || return 1
  while IFS=$'\037' read -r a e i; do
    [ -n "$a" ] || { WHY="authoriser empty"; continue; }
    [[ "$e" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && [ "$(date -d "$e" +%Y-%m-%d 2>/dev/null)" = "$e" ] || { WHY="expiry '$e' is not a real YYYY-MM-DD date"; continue; }
    [[ "$e" < "$today" ]] && { WHY="waiver expired $e"; continue; }
    [[ "$i" =~ ^CON-[0-9]{3,}$ ]] || { WHY="tracked item '$i' does not match CON-NNN"; continue; }
    [ -n "$cname$cmail" ] || { WHY="committer identity unresolvable; cannot check authoriser != committer"; continue; }
    if [ "${a,,}" = "${cname,,}" ] || [ "${a,,}" = "${cmail,,}" ]; then WHY="authoriser '$a' is the committer (producer cannot self-waive)"; continue; fi
    return 0
  done <<<"$cand"
  return 1
}
fail=0; blind=0; checked=0
blindmsg() { echo "$GATE: BLIND $1 — $2. Fix: $3"; blind=1; }
while IFS= read -r -d '' meta && IFS= read -r -d '' path; do
  [ -n "$path" ] || continue
  set -- $meta; om="${1#:}"; nm="$2"; osha="$3"; nsha="$4"
  [ "$om" = 160000 ] && [ "$nm" = 160000 ] || continue
  [ "$osha" != "$nsha" ] || continue
  checked=$((checked+1)); sub="$root/$path"; subp="$(cd "$sub" 2>/dev/null && pwd -P)"
  if [ -z "$subp" ] || ! sg -C "$sub" rev-parse --git-dir >/dev/null 2>&1; then
    blindmsg "$path" "submodule checkout missing or not a repository" "git submodule update --init -- $path"; continue; fi
  if [ "$(sg -C "$sub" rev-parse --show-toplevel 2>/dev/null)" != "$subp" ]; then
    blindmsg "$path" "path is not its own repository (resolves into the parent worktree)" "git submodule update --init -- $path"; continue; fi
  if ! sg -C "$sub" cat-file -e "${osha}^{commit}" 2>/dev/null; then
    blindmsg "$path" "old pin ${osha:0:7} not in the submodule object store" "git -C $path fetch (then retry)"; continue; fi
  if ! sg -C "$sub" cat-file -e "${nsha}^{commit}" 2>/dev/null; then
    blindmsg "$path" "new pin ${nsha:0:7} not in the submodule object store" "git -C $path fetch (then retry)"; continue; fi
  sg -C "$sub" merge-base --is-ancestor "$nsha" "$osha" 2>/dev/null; rc=$?
  if [ "$rc" = 1 ] && [ "$(sg -C "$sub" rev-parse --is-shallow-repository 2>/dev/null)" != false ]; then rc=99; fi
  case "$rc" in
    0) if waived "$path" "$nsha"; then echo "$GATE: WAIVED $path ${osha:0:7} -> ${nsha:0:7} (waiver from $wsrc)"
       else echo "$GATE: FAIL $path — staged pin ${nsha:0:7} is an ANCESTOR of the recorded pin ${osha:0:7} (downgrade; waiver: $WHY). Advance the submodule checkout to the pin (git submodule update) or stage a valid waiver"; fail=1; fi ;;
    1) if sg -C "$sub" merge-base --is-ancestor "$osha" "$nsha" 2>/dev/null; then echo "$GATE: ok $path ${osha:0:7} -> ${nsha:0:7} (forward)"
       else echo "$GATE: WARN $path ${osha:0:7} -> ${nsha:0:7} DIVERGED (neither is an ancestor of the other; old pin's commits may be dropped — review by hand)"; fi ;;
    *) blindmsg "$path" "ancestry of ${nsha:0:7} vs ${osha:0:7} cannot be decided (merge-base rc=$rc: shallow or incomplete submodule history)" "git -C $path fetch --unshallow (or fetch the missing history), then retry" ;;
  esac
done < <(git -C "$root" diff --cached --raw -z --no-abbrev --no-renames --ignore-submodules=none)
[ "$fail" = 1 ] && exit 1
[ "$blind" = 1 ] && exit 2
echo "$GATE: PASS ($checked staged gitlink change(s) inspected)"; exit 0
