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
#   PUBLISHED   the commit exists locally and `git for-each-ref --contains <sha> refs/remotes refs/tags` is non-empty
#   UNPUBLISHED the commit exists, the repo is complete (not shallow) and no remote ref or tag contains it  -> FAIL (1)
#   BLIND       no nested repo / gitdir, commit object absent, no remote refs fetched, or a SHALLOW repo that does not
#               show a containing ref (a shallow clone cannot prove absence) -> exit 2, never a PASS
# --online additionally runs `git ls-remote <url>` per non-PUBLISHED gitlink and upgrades it to PUBLISHED when the sha is
# the tip of a remote ref (network, bounded by timeout 40 per gitlink); it never downgrades a verdict.
# ── Usage ─────────────────────────────────────────────────
#   cm_gitlink_on_remote.sh [--root <repo-root>] [--online]
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
root="${SCRIPT_DIR}/../.."; online=0
while [ $# -gt 0 ]; do
  case "$1" in
    --root) [ $# -ge 2 ] || { echo "$GATE: --root requires a value" >&2; exit 2; }; root="$2"; shift 2 ;;
    --online) online=1; shift ;;
    -h|--help) sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "$GATE: unknown arg '$1'" >&2; exit 2 ;;
  esac
done
root="$(cd "$root" 2>/dev/null && pwd)" || { echo "$GATE: root not found" >&2; exit 2; }
[ -r "$root/.gitmodules" ] || { echo "$GATE: BLIND — $root/.gitmodules not readable"; exit 2; }
pgd="$(git -C "$root" rev-parse --absolute-git-dir 2>/dev/null)" || { echo "$GATE: BLIND — $root is not a git repository"; exit 2; }
links="$(git -C "$root" ls-files -s 2>/dev/null | awk '$1=="160000"{print $2 "\t" $4}' | sort -u -k2,2)"
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
  cont="$(git --git-dir="$repo" for-each-ref --contains "$sha" --count=1 --format='%(refname:short)' refs/remotes refs/tags 2>/dev/null)"   # MUT:contains
  if [ -n "$cont" ]; then echo "✅ PUBLISHED    $path ${sha:0:12}: contained in $cont"; continue; fi
  if [ "$online" = 1 ] && [ -n "$url" ]; then
    if timeout 40 git ls-remote "$url" 2>/dev/null | awk -v s="$sha" '$1==s{f=1} END{exit f?0:1}'; then echo "✅ PUBLISHED    $path ${sha:0:12}: tip of a remote ref ($url)"; continue; fi
  fi
  shallow="$(git --git-dir="$repo" rev-parse --is-shallow-repository 2>/dev/null)"
  nrem="$(git --git-dir="$repo" for-each-ref --count=1 --format='x' refs/remotes 2>/dev/null)"
  if [ "$shallow" = true ]; then echo "❓ BLIND        $path ${sha:0:12}: shallow repository, absence cannot be proven"; blind=1; continue; fi
  if [ -z "$nrem" ]; then echo "❓ BLIND        $path ${sha:0:12}: no remote refs fetched in $repo"; blind=1; continue; fi
  echo "❌ UNPUBLISHED  $path ${sha:0:12}: on no remote ref or tag (a recursive clone cannot fetch it)"; bad=1
done <<<"$links"
echo "----------------------------------------------------------------------"
[ "$bad" = 1 ] && { echo "❌ $GATE: FAIL — at least one gitlink names a commit on no remote ($n gitlinks)"; exit 1; }
[ "$blind" = 1 ] && { echo "❓ $GATE: BLIND — no unpublished gitlink found, but not every gitlink could be proven ($n gitlinks)"; exit 2; }
echo "✅ $GATE: PASS — all $n gitlinks are on a remote"
exit 0
