#!/usr/bin/env bash
# cm_gitlink_on_remote.sh — CM-GITLINK-ON-REMOTE gate (§11.4.28, §11.4.113, §11.4.288(D)).
#
# ── Purpose ───────────────────────────────────────────────
# Every gitlink the index of <root> records MUST name a commit that is reachable from a remote ref
# (refs/remotes/* or a tag) of the nested repository, i.e. one a recursive clone can fetch. A commit that exists
# only in a local checkout makes every consumer's `git submodule update` fail. Review round 1 of the 2026-10-27
# constitution landing found three such pins (claude_toolkit f79d449, docs_chain fdc3676, token_optimizer a5bd538):
# the sanctioned committer records whatever commit each nested checkout is on, not the merge result (class: a nested
# checkout that moved ahead of its published pin rides into the parent commit). This gate closes that class.
#   PUBLISHED   the commit exists locally and is contained in a remote-tracking ref `refs/remotes/<R>/*` of a remote R whose
#               URL equals the .gitmodules URL of that gitlink (a local tag, a local branch or the refs of a foreign or
#               stale remote never count: review round 2, R2-F5)
#   UNPUBLISHED the commit exists, the repo is complete (not shallow) and no remote ref or tag contains it  -> FAIL (1)
#   BLIND       no nested repo / gitdir, commit object absent, no remote refs fetched, or a SHALLOW repo that does not
#               show a containing ref (a shallow clone cannot prove absence) -> exit 2, never a PASS
# --online re-validates every gitlink against the remote as it is NOW (`git ls-remote <url>`, timeout 40 per gitlink): PUBLISHED
# only when the sha equals a listed tip, or is an ancestor of a listed tip whose object is present locally; the offline
# refs/remotes verdict is NOT trusted (a branch the remote has since lost downgrades the gitlink). An unreachable remote is BLIND.
# --rev <commit> reads the gitlinks of that commit (`git ls-tree -r`) instead of the index, so a pre-push run judges the commit
# that is actually pushed (default: the index).
# ── Usage ─────────────────────────────────────────────────
#   cm_gitlink_on_remote.sh [--root <repo-root>] [--online] [--rev <commit>]
# ── Inputs ────────────────────────────────────────────────
#   <root>/.gitmodules, the index of <root>, the nested repos (worktree .git or <gitdir>/modules/<name>).
# ── Outputs ───────────────────────────────────────────────
#   One PUBLISHED / UNPUBLISHED / BLIND line per gitlink and a verdict line.
# ── Side-effects ──────────────────────────────────────────
#   None (read-only git plumbing; --online only reads remotes).
# ── Dependencies ──────────────────────────────────────────
#   bash, git, awk, timeout (for --online).
# ── Exit codes ────────────────────────────────────────────
#   0 every gitlink published · 1 at least one UNPUBLISHED · 2 BLIND (nothing unpublished found, but not all proven).
# ── Cross-references ──────────────────────────────────────
#   §11.4.28, §11.4.113, §11.4.288(D), §11.4.6, §1.1 (paired mutation: cm_gitlink_on_remote_mutation_test.sh).
# Classification: universal (§11.4.17).
set -uo pipefail
GATE="CM-GITLINK-ON-REMOTE"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
root="${SCRIPT_DIR}/../.."; online=0; rev=""
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || { echo "$GATE: --root requires a value" >&2; exit 2; }; root="$2"; shift 2 ;;
    --online) online=1; shift ;;
    --rev) [ $# -ge 2 ] || { echo "$GATE: --rev requires a value" >&2; exit 2; }; rev="$2"; shift 2 ;;
    -h|--help) sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "$GATE: unknown arg '$1'" >&2; exit 2 ;;
  esac
done
root="$(cd "$root" 2>/dev/null && pwd)" || { echo "$GATE: root not found" >&2; exit 2; }
[ -r "$root/.gitmodules" ] || { echo "$GATE: BLIND — $root/.gitmodules not readable"; exit 2; }
pgd="$(git -C "$root" rev-parse --absolute-git-dir 2>/dev/null)" || { echo "$GATE: BLIND — $root is not a git repository"; exit 2; }
if [ -n "$rev" ]; then
  git -C "$root" rev-parse --verify -q "${rev}^{commit}" >/dev/null 2>&1 || { echo "$GATE: BLIND — --rev $rev is not a commit of $root"; exit 2; }
  links="$(git -C "$root" ls-tree -r "$rev" 2>/dev/null | awk '$2=="commit"{print $3 "\t" $4}' | sort -u -k2,2)"
else
  links="$(git -C "$root" ls-files -s 2>/dev/null | awk '$1=="160000"{print $2 "\t" $4}' | sort -u -k2,2)"
fi
[ -n "$links" ] || { echo "$GATE: BLIND — no gitlinks in the index of $root (control: the instrument saw nothing)"; exit 2; }
bad=0 blind=0 n=0
while IFS=$'\t' read -r sha path; do
  n=$((n+1))
  key="$(git -C "$root" config -f .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null | awk -v p="$path" '$2==p{print $1; exit}')"
  name="${key#submodule.}"; name="${name%.path}"
  url="$(git -C "$root" config -f .gitmodules --get "submodule.$name.url" 2>/dev/null)"
  repo=""
  if [ -e "$root/$path/.git" ]; then repo="$(git -C "$root/$path" rev-parse --absolute-git-dir 2>/dev/null)"; fi
  if [ -z "$repo" ] && [ -n "$name" ] && [ -d "$pgd/modules/$name" ]; then repo="$pgd/modules/$name"; fi
  if [ -z "$repo" ]; then echo "❓ BLIND        $path ${sha:0:12}: no nested repository or gitdir"; blind=1; continue; fi
  if ! git --git-dir="$repo" cat-file -e "${sha}^{commit}" 2>/dev/null; then echo "❓ BLIND        $path ${sha:0:12}: commit object not present in $repo"; blind=1; continue; fi
  # remotes of the nested repository whose URL equals the .gitmodules URL
  rems="$(git --git-dir="$repo" config --get-regexp '^remote\..*\.url$' 2>/dev/null | awk -v u="$url" '$2==u{k=$1; sub(/^remote\./,"",k); sub(/\.url$/,"",k); print k}')"
  if [ "$online" = 1 ]; then
    tips="$(timeout 40 git ls-remote --heads --tags "$url" 2>/dev/null | awk '{print $1}' | sort -u)"
    if [ -z "$tips" ]; then echo "❓ BLIND        $path ${sha:0:12}: ls-remote $url returned nothing (unreachable or empty)"; blind=1; continue; fi
    hit=""
    while read -r tip; do
      [ -n "$tip" ] || continue
      if [ "$tip" = "$sha" ]; then hit="tip $tip"; break; fi
      if git --git-dir="$repo" cat-file -e "${tip}^{commit}" 2>/dev/null && git --git-dir="$repo" merge-base --is-ancestor "$sha" "$tip" 2>/dev/null; then hit="ancestor of listed tip ${tip:0:12}"; break; fi   # MUT:online-ancestor
    done <<<"$tips"
    if [ -n "$hit" ]; then echo "✅ PUBLISHED    $path ${sha:0:12}: $hit ($url)"; continue; fi
    missing=0
    while read -r tip; do [ -n "$tip" ] && ! git --git-dir="$repo" cat-file -e "${tip}^{commit}" 2>/dev/null && missing=1; done <<<"$tips"
    if [ "$missing" = 1 ]; then echo "❓ BLIND        $path ${sha:0:12}: not a remote tip and some remote tips are not fetched locally, ancestry cannot be tested (fetch, then re-run)"; blind=1; continue; fi
    echo "❌ UNPUBLISHED  $path ${sha:0:12}: not a remote tip and not an ancestor of any remote tip ($url)"; bad=1; continue
  else
    cont=""
    for r in $rems; do
      c="$(git --git-dir="$repo" for-each-ref --contains "$sha" --count=1 --format='%(refname:short)' "refs/remotes/$r" 2>/dev/null)"   # MUT:contains
      [ -n "$c" ] && { cont="$c"; break; }
    done
    if [ -n "$cont" ]; then echo "✅ PUBLISHED    $path ${sha:0:12}: contained in $cont"; continue; fi
  fi
  shallow="$(git --git-dir="$repo" rev-parse --is-shallow-repository 2>/dev/null)"
  nrem=""; for r in $rems; do nrem="$(git --git-dir="$repo" for-each-ref --count=1 --format='x' "refs/remotes/$r" 2>/dev/null)"; [ -n "$nrem" ] && break; done
  if [ "$shallow" = true ]; then echo "❓ BLIND        $path ${sha:0:12}: shallow repository, absence cannot be proven"; blind=1; continue; fi
  if [ -z "$nrem" ]; then echo "❓ BLIND        $path ${sha:0:12}: no refs/remotes/<remote> of a remote whose URL equals the .gitmodules URL ("$url") in $repo (run with --online or fetch)"; blind=1; continue; fi
  echo "❌ UNPUBLISHED  $path ${sha:0:12}: on no remote ref or tag (a recursive clone cannot fetch it)"; bad=1
done <<<"$links"
echo "----------------------------------------------------------------------"
[ "$bad" = 1 ] && { echo "❌ $GATE: FAIL — at least one gitlink names a commit on no remote ($n gitlinks)"; exit 1; }
[ "$blind" = 1 ] && { echo "❓ $GATE: BLIND — no unpublished gitlink found, but not every gitlink could be proven ($n gitlinks)"; exit 2; }
echo "✅ $GATE: PASS — all $n gitlinks are on a remote"
exit 0
