#!/usr/bin/env bash
# cm_llmctl_submodule_nonrecursive.sh — CM-LLMCTL-SUBMODULE-NONRECURSIVE gate (§11.4.277(B), §11.4.28(C), §11.4.31).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# llmctl vendors THIS constitution as its own `constitution` submodule, and this
# constitution vendors llmctl at submodules/llmctl: a mutual reference. The
# operator decision (2026-10-13) keeps llmctl as a depth-1 hub entry that
# consumers MUST NOT initialise recursively. The reference is finite only while
# llmctl's own constitution pin names a commit that contains no
# submodules/llmctl. This gate fails when:
#   (1) helix-deps.yaml has no llmctl entry carrying `recursive_init: false`;
#   (2) llmctl's own `constitution` gitlink resolves to a commit whose tree
#       contains `submodules/llmctl` (a recursive init would re-enter here).
# If submodules/llmctl is not checked out, check (2) is SKIPPED with a printed
# reason (nothing can re-enter an uninitialised path); check (1) always runs.
# A pin that cannot be resolved to a commit is BLIND (exit 2), never a PASS.
#
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_llmctl_submodule_nonrecursive.sh [--root <constitution-root>]
#
# ── Side-effects ─────────────────────────────────────────────────────────────
#   None (read-only git plumbing; no network).
#
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, git, awk.
#
# ── Cross-references ─────────────────────────────────────────────────────────
#   §11.4.277(B), §11.4.28(C), §11.4.31, §11.4.201, §1.1 (paired mutation:
#   cm_llmctl_submodule_nonrecursive_mutation_test.sh).
#
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 PASS · 1 FAIL · 2 BLIND (cannot determine).
#
# Classification: universal (§11.4.17).
set -uo pipefail
GATE="CM-LLMCTL-SUBMODULE-NONRECURSIVE"
root="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/../.." && pwd)"
while [ $# -gt 0 ]; do
  case "$1" in
    --root) root="$(cd "$2" && pwd)" || exit 2; shift 2 ;;
    -h|--help) sed -n 2,34p "${BASH_SOURCE[0]:-$0}"; exit 0 ;;
    *) echo "$GATE: unknown argument $1" >&2; exit 2 ;;
  esac
done
deps="$root/helix-deps.yaml"
[ -r "$deps" ] || { echo "$GATE: BLIND — $deps unreadable" >&2; exit 2; }
fail=0
# (1) marker inside the llmctl entry (from `- name: llmctl` to the next `- name:` or a top-level key)
entry="$(awk '/^  - name: llmctl[[:space:]]*$/{f=1;next} f&&/^  - name:/{exit} f&&/^[^ #]/{exit} f{print}' "$deps")"
if [ -z "$entry" ]; then
  echo "$GATE: FAIL — helix-deps.yaml has no llmctl entry"; fail=1
elif ! printf '%s\n' "$entry" | grep -Eq '^[[:space:]]+recursive_init:[[:space:]]*false([[:space:]]|#|$)'; then
  echo "$GATE: FAIL — helix-deps.yaml llmctl entry lacks the non-recursive marker 'recursive_init: false'"; fail=1
else
  echo "$GATE: marker recursive_init: false present"
fi
# (2) cycle finiteness
sub="$root/submodules/llmctl"
if ! git -C "$sub" rev-parse --git-dir >/dev/null 2>&1 || [ "$(git -C "$sub" rev-parse --show-toplevel 2>/dev/null)" != "$sub" ]; then
  echo "$GATE: SKIP (2) — submodules/llmctl is not checked out; nothing can re-enter this constitution through it"
else
  line="$(git -C "$sub" ls-tree HEAD constitution 2>/dev/null)"
  mode="${line%% *}"; pin="$(printf '%s' "$line" | awk '{print $3}')"
  if [ "$mode" != "160000" ] || [ -z "$pin" ]; then
    echo "$GATE: SKIP (2) — llmctl at HEAD has no 'constitution' submodule gitlink; no cycle exists"
  else
    gd=""
    for cand in "$root" "$sub"; do
      if [ "$(git -C "$cand" cat-file -t "$pin" 2>/dev/null)" = "commit" ]; then gd="$cand"; break; fi
    done
    if [ -z "$gd" ]; then
      echo "$GATE: BLIND — llmctl's constitution pin $pin is not resolvable to a commit in this repo or in llmctl (fetch it; an unresolved pin is never a PASS)" >&2
      exit 2
    fi
    if [ -n "$(git -C "$gd" ls-tree "$pin" submodules/llmctl 2>/dev/null)" ]; then
      echo "$GATE: FAIL — llmctl's constitution pin $pin contains submodules/llmctl: a recursive init would re-enter this constitution (refuse the pin bump)"; fail=1
    else
      echo "$GATE: llmctl's constitution pin ${pin:0:7} contains no submodules/llmctl (cycle finite)"
    fi
  fi
fi
if [ "$fail" -ne 0 ]; then echo "❌ $GATE: FAIL"; exit 1; fi
echo "✅ $GATE: PASS"
