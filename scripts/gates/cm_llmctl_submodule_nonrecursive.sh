#!/usr/bin/env bash
# cm_llmctl_submodule_nonrecursive.sh — CM-LLMCTL-SUBMODULE-NONRECURSIVE gate (§11.4.277(B), §11.4.28(C), §11.4.31).
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# This constitution vendors llmctl at submodules/llmctl as a depth-1 hub engine.
# Under the §11.4.28(C) EXTENSION (2026-10-21, superseding the 2026-10-13
# mutual-reference decision) llmctl MUST NOT nest this constitution or any
# own-org repository; it resolves them via lib/resolve_deps.sh. llmctl still
# nests third-party repositories (llama.cpp, colibri), so consumers keep it
# non-recursive (`recursive_init: false`). This narrower re-entry check stays as
# a backstop to CM-HUB-ENGINE-NO-OWNORG-NESTING. This gate fails when:
#   (1) helix-deps.yaml has no llmctl entry carrying `recursive_init: false`;
#   (2) re-entry: starting from the llmctl commit RECORDED for submodules/llmctl
#       (a STAGED index gitlink that differs from HEAD governs, as in
#       CM-HUB-ENGINE-NO-OWNORG-NESTING; else the HEAD record; falling back
#       LOUDLY to the checked-out HEAD only when the recorded commit is not
#       resolvable), the own-org submodules it
#       pins (`constitution` and `submodules/containers`) are inspected; a pin
#       whose tree contains an entry named `llmctl` at ANY path, or a
#       `.gitmodules` whose url names this constitution or llmctl, re-enters
#       this constitution and FAILs (the offending path is reported).
# If submodules/llmctl is not checked out, check (2) is SKIPPED with a printed
# reason (nothing can re-enter an uninitialised path); check (1) always runs.
# A pin that cannot be resolved to a commit is BLIND (exit 2), never a PASS;
# extra object stores may be supplied with git's own GIT_ALTERNATE_OBJECT_DIRECTORIES,
# or by initialising the one level (`git -C submodules/llmctl submodule update --init submodules/containers`).
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
    -h|--help) sed -n 2,44p "${BASH_SOURCE[0]:-$0}"; exit 0 ;;
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
# here-string, not `printf | grep -q`: under pipefail an early-exiting grep can SIGPIPE the producer and turn a
# PRESENT marker into a false FAIL on a large entry (SIGPIPE x pipefail class, §11.4.276(C))
elif ! grep -Eq '^[[:space:]]+recursive_init:[[:space:]]*false([[:space:]]|#|$)' <<<"$entry"; then
  echo "$GATE: FAIL — helix-deps.yaml llmctl entry lacks the non-recursive marker 'recursive_init: false'"; fail=1
else
  echo "$GATE: marker recursive_init: false present"
fi
# (2) cycle finiteness
sub="$root/submodules/llmctl"
blind=0
if ! git -C "$sub" rev-parse --git-dir >/dev/null 2>&1 || [ "$(git -C "$sub" rev-parse --show-toplevel 2>/dev/null)" != "$sub" ]; then
  echo "$GATE: SKIP (2) — submodules/llmctl is not checked out; nothing can re-enter this constitution through it"
else
  # object stores tried for any commit: this repo, llmctl, a one-level nested containers checkout (+ GIT_ALTERNATE_OBJECT_DIRECTORIES)
  stores=("$root" "$sub")
  [ -e "$sub/submodules/containers/.git" ] && stores+=("$sub/submodules/containers")
  find_store() { local c; for c in "${stores[@]}"; do [ "$(git -C "$c" cat-file -t "$1" 2>/dev/null)" = "commit" ] && { echo "$c"; return 0; }; done; return 1; }
  rec="$(git -C "$root" ls-tree HEAD submodules/llmctl 2>/dev/null | awk '$1=="160000"{print $3}')"
  rec_idx="$(git -C "$root" ls-files -s -- submodules/llmctl 2>/dev/null | awk '$1=="160000"{print $2}')"
  if [ -n "$rec_idx" ] && [ "$rec_idx" != "$rec" ]; then
    echo "$GATE: NOTE — using the STAGED (index) gitlink ${rec_idx:0:7}; HEAD records ${rec:-<none>}" >&2
    rec="$rec_idx"
  fi
  L=""
  if [ -n "$rec" ]; then
    if st="$(find_store "$rec")"; then L="$rec"; lstore="$st"; echo "$GATE: using the llmctl commit recorded in this repo: ${rec:0:7}"
    else echo "$GATE: NOTE — recorded llmctl commit ${rec:0:7} is not resolvable; FALLING BACK to the checked-out HEAD (less authoritative)" >&2; fi
  else
    echo "$GATE: NOTE — this repo's HEAD records no gitlink for submodules/llmctl; FALLING BACK to the checked-out HEAD" >&2
  fi
  if [ -z "$L" ]; then L="$(git -C "$sub" rev-parse HEAD)"; lstore="$sub"; fi
  # inspect <label> <commit>: flags re-entry of this constitution/llmctl anywhere in that commit's tree; sets fail/blind
  inspect() {
    local label="$1" c="$2" st hit gm
    if ! st="$(find_store "$c")"; then
      echo "$GATE: BLIND — $label pin $c is not resolvable to a commit (fetch it, or init that one submodule level); an unresolved pin is never a PASS" >&2; blind=1; return
    fi
    hit="$(git -C "$st" ls-tree -r -t --name-only "$c" 2>/dev/null | awk -F/ '$NF=="llmctl"')"
    if [ -n "$hit" ]; then echo "$GATE: FAIL — $label pin ${c:0:7} contains entry named llmctl at: $(echo "$hit" | tr '\n' ' ')— a recursive init would re-enter this constitution (refuse the pin bump)"; fail=1; return; fi
    gm="$(git -C "$st" show "$c:.gitmodules" 2>/dev/null | awk -F'= *' '/^[[:space:]]*url[[:space:]]*=/{print $2}' | grep -Ei '(^|[/:])(helixconstitution|constitution|llmctl)(\.git)?$' || true)"
    if [ -n "$gm" ]; then echo "$GATE: FAIL — $label pin ${c:0:7} .gitmodules names this constitution/llmctl as a dependency: $(echo "$gm" | tr '\n' ' ')"; fail=1; return; fi
    echo "$GATE: $label pin ${c:0:7} does not re-enter this constitution (cycle finite)"
  }
  seen=0
  for name in constitution submodules/containers; do
    line="$(git -C "$lstore" ls-tree "$L" "$name" 2>/dev/null)"
    mode="${line%% *}"; pin="$(printf '%s' "$line" | awk '{print $3}')"
    if [ "$mode" != "160000" ] || [ -z "$pin" ]; then echo "$GATE: llmctl@${L:0:7} has no gitlink '$name' (nothing to inspect)"; continue; fi
    seen=1; inspect "llmctl->$name" "$pin"
  done
  [ "$seen" = 1 ] || echo "$GATE: llmctl pins no own-org submodule; no cycle exists"
fi
if [ "$fail" -ne 0 ]; then echo "❌ $GATE: FAIL"; exit 1; fi
if [ "$blind" -ne 0 ]; then echo "⚠ $GATE: BLIND (exit 2) — could not determine"; exit 2; fi
echo "✅ $GATE: PASS"
