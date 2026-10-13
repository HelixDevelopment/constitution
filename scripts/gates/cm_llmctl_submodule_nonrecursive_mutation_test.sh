#!/usr/bin/env bash
# cm_llmctl_submodule_nonrecursive_mutation_test.sh — §1.1 paired-mutation meta-test for
# CM-LLMCTL-SUBMODULE-NONRECURSIVE. Builds throwaway git fixtures (the real repo is never touched).
#   FAIL-expected : NO-MARKER (marker removed) · REENTRY (llmctl's constitution pin contains submodules/llmctl)
#                   · NO-ENTRY (llmctl entry absent)
#   BLIND-expected: UNRESOLVABLE (pin not present in any object db) -> exit 2
#   PASS-expected : CLEAN (marker + finite pin) · UNINIT (submodule not checked out, marker present)
# Usage: cm_llmctl_submodule_nonrecursive_mutation_test.sh   Exit: 0 proof holds · 1 misclassified · 2 env error.
# Side-effects: temp dir under $TMPDIR (trap-cleaned). Dependencies: bash, git.
# Classification: universal (§11.4.17).
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
gate="$here/cm_llmctl_submodule_nonrecursive.sh"
[ -r "$gate" ] || { echo "META: gate missing" >&2; exit 2; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
bad=0
mk_root() { # <dir> <with_marker 1|0> <with_entry 1|0> ; creates a constitution-like repo with two commits: A (finite) and B (contains submodules/llmctl)
  local d="$1"; mkdir -p "$d"; git -C "$d" init -q
  { echo "schema_version: 1"; echo "deps:"
    if [ "$3" = 1 ]; then echo "  - name: llmctl"; echo "    layout: grouped"; [ "$2" = 1 ] && echo "    recursive_init: false    # marker"; echo ""; fi
    echo "  - name: other"; echo "    layout: grouped"; echo ""; echo "transitive_handling:"; echo "  recursive: true"; } > "$d/helix-deps.yaml"
  echo a > "$d/README.md"; git -C "$d" add -A; git -C "$d" commit -qm A; A="$(git -C "$d" rev-parse HEAD)"
  mkdir -p "$d/submodules/llmctl"; echo x > "$d/submodules/llmctl/f"; git -C "$d" add -A; git -C "$d" commit -qm B; B="$(git -C "$d" rev-parse HEAD)"
  git -C "$d" rm -rq --cached submodules/llmctl; rm -rf "$d/submodules/llmctl"
}
mk_llmctl() { # <root> <pin>
  local s="$1/submodules/llmctl"; mkdir -p "$s"; git -C "$s" init -q; echo l > "$s/f"; git -C "$s" add f
  git -C "$s" update-index --add --cacheinfo "160000,$2,constitution"; git -C "$s" commit -qm L
}
expect() { # <name> <want-rc> <root>
  local out rc; out="$(bash "$gate" --root "$3" 2>&1)"; rc=$?
  if [ "$rc" = "$2" ]; then echo "✅ META OK:   $1 (rc=$rc)"; else echo "❌ META BAD:  $1 want rc=$2 got rc=$rc"; echo "$out" | sed 's/^/    /'; bad=1; fi
}
r="$tmp/clean"; mk_root "$r" 1 1; mk_llmctl "$r" "$A"; expect "CLEAN (marker + finite pin) must PASS" 0 "$r"
r="$tmp/uninit"; mk_root "$r" 1 1; expect "UNINIT (submodule not checked out) must PASS" 0 "$r"
r="$tmp/nomarker"; mk_root "$r" 0 1; mk_llmctl "$r" "$A"; expect "NO-MARKER must FAIL" 1 "$r"
r="$tmp/noentry"; mk_root "$r" 1 0; mk_llmctl "$r" "$A"; expect "NO-ENTRY must FAIL" 1 "$r"
r="$tmp/reentry"; mk_root "$r" 1 1; mk_llmctl "$r" "$B"; expect "REENTRY (pin contains submodules/llmctl) must FAIL" 1 "$r"
r="$tmp/unres"; mk_root "$r" 1 1; mk_llmctl "$r" "0123456789abcdef0123456789abcdef01234567"; expect "UNRESOLVABLE pin must be BLIND (rc 2)" 2 "$r"
echo "======================================================================"
if [ "$bad" = 0 ]; then echo "✅ META PASS: CM-LLMCTL-SUBMODULE-NONRECURSIVE is a genuine (non-bluff) gate"; exit 0; fi
echo "❌ META FAIL: a fixture was misclassified"; exit 1
