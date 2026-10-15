#!/usr/bin/env bash
# cm_llmctl_submodule_nonrecursive_mutation_test.sh — §1.1 paired-mutation meta-test for
# CM-LLMCTL-SUBMODULE-NONRECURSIVE. Builds throwaway git fixtures with plumbing (the real repo is never touched).
#   PASS-expected : CLEAN (marker, finite constitution + containers pins) · UNINIT (submodule not checked out)
#                   · RECORDED-CLEAN-HEAD-DIRTY (recorded llmctl commit is clean, checked-out HEAD would re-enter: the RECORDED one governs)
#   FAIL-expected : NO-MARKER · NO-ENTRY · REENTRY-PATH (pin tree has submodules/llmctl) · REENTRY-DEEP (an entry named llmctl at a nested path)
#                   · REENTRY-GITMODULES (pin's .gitmodules url names this constitution) · VIA-CONTAINERS (containers pin re-enters)
#                   · RECORDED-DIRTY-HEAD-CLEAN (recorded llmctl commit re-enters, checked-out HEAD is clean)
#   BLIND-expected (rc 2): UNRESOLVABLE constitution pin · UNRESOLVABLE containers pin
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
# --- plumbing helpers (all objects go into repo $R) ---
blob() { printf '%s\n' "$2" | git -C "$1" hash-object -w --stdin; }
tree1() { printf '%s\t%s\n' "$2" "$3" | git -C "$1" mktree; }          # <repo> "<mode> <type> <sha>" <name>
commit() { git -C "$1" commit-tree "$2" -m x; }                          # <repo> <tree>
# kinds of constitution/containers pins, keyed by kind name (fx() looks a pin up by that name)
declare -A PIN=()
mk_pins() { # R must exist; fills PIN[CLEAN|PATH|DEEP|GM|UNRES]
  local R="$1" b t inner
  b="$(blob "$R" a)"
  PIN[CLEAN]="$(commit "$R" "$(tree1 "$R" "100644 blob $b" README.md)")"
  inner="$(tree1 "$R" "100644 blob $b" f)"                                # submodules/llmctl/f
  local subs; subs="$(tree1 "$R" "040000 tree $inner" llmctl)"
  PIN[PATH]="$(commit "$R" "$(tree1 "$R" "040000 tree $subs" submodules)")"
  local d1 d2 d3; d1="$(tree1 "$R" "040000 tree $inner" llmctl)"; d2="$(tree1 "$R" "040000 tree $d1" y)"; d3="$(tree1 "$R" "040000 tree $d2" x)"
  PIN[DEEP]="$(commit "$R" "$(tree1 "$R" "040000 tree $d3" vendor_x)")"      # vendor_x/x/y/llmctl/f
  local gm; gm="$(blob "$R" '[submodule "c"]
	path = c
	url = git@github.com:HelixDevelopment/constitution.git')"
  PIN[GM]="$(commit "$R" "$(tree1 "$R" "100644 blob $gm" .gitmodules)")"
  PIN[UNRES]="0123456789abcdef0123456789abcdef01234567"
}
mk_llmctl() { # <root> <constitution-pin> <containers-pin> -> echoes the new llmctl commit (also becomes HEAD of the fixture submodule)
  local s="$1/submodules/llmctl" idx t c
  [ -d "$s/.git" ] || { mkdir -p "$s"; git -C "$s" init -q; }
  idx="$s/.git/idx.$$"; rm -f "$idx"
  GIT_INDEX_FILE="$idx" git -C "$s" update-index --add --cacheinfo "160000,$2,constitution"
  [ -n "${3:-}" ] && GIT_INDEX_FILE="$idx" git -C "$s" update-index --add --cacheinfo "160000,$3,submodules/containers"
  t="$(GIT_INDEX_FILE="$idx" git -C "$s" write-tree)"; rm -f "$idx"
  c="$(git -C "$s" commit-tree "$t" -m L)"; git -C "$s" update-ref HEAD "$c"; echo "$c"
}
mk_root() { # <dir> <marker 1|0> <entry 1|0> ; repo with pins' objects; HEAD committed; llmctl dir not created
  local d="$1"; mkdir -p "$d"; git -C "$d" init -q
  { echo "schema_version: 1"; echo "deps:"
    if [ "$3" = 1 ]; then echo "  - name: llmctl"; echo "    layout: grouped"; [ "$2" = 1 ] && echo "    recursive_init: false    # marker"; echo ""; fi
    echo "  - name: other"; echo "    layout: grouped"; echo ""; echo "transitive_handling:"; echo "  recursive: true"; } > "$d/helix-deps.yaml"
  git -C "$d" add -A; git -C "$d" commit -qm base; mk_pins "$d"
}
record() { # <root> <llmctl-commit> : record gitlink in root HEAD
  local d="$1"; git -C "$d" update-index --add --cacheinfo "160000,$2,submodules/llmctl"; git -C "$d" commit -qm rec
}
expect() { local out rc; out="$(bash "$gate" --root "$3" 2>&1)"; rc=$?
  if [ "$rc" = "$2" ]; then echo "✅ META OK:   $1 (rc=$rc)"; else echo "❌ META BAD:  $1 want rc=$2 got rc=$rc"; echo "$out" | sed 's/^/    /'; bad=1; fi; }
fx() { # <name> <marker> <entry> <constitution-pin-kind> <containers-pin-kind|-> <want-rc> [text]  (kinds: PIN keys)
  local r="$tmp/$1"; mk_root "$r" "$2" "$3"; local cp="${PIN[$4]}" kp=""; [ "$5" != "-" ] && kp="${PIN[$5]}"
  local L; L="$(mk_llmctl "$r" "$cp" "$kp")"; record "$r" "$L"; expect "$7" "$6" "$r"; }
fx clean 1 1 CLEAN CLEAN 0 "CLEAN (marker, finite constitution + containers pins) must PASS"
r="$tmp/uninit"; mk_root "$r" 1 1; expect "UNINIT (submodule not checked out) must PASS" 0 "$r"
fx nomarker 0 1 CLEAN CLEAN 1 "NO-MARKER must FAIL"
fx noentry 1 0 CLEAN CLEAN 1 "NO-ENTRY must FAIL"
fx reentry 1 1 PATH CLEAN 1 "REENTRY-PATH (pin tree has submodules/llmctl) must FAIL"
fx deep 1 1 DEEP CLEAN 1 "REENTRY-DEEP (entry named llmctl at a nested path) must FAIL"
fx gitmodules 1 1 GM CLEAN 1 "REENTRY-GITMODULES (pin .gitmodules url names this constitution) must FAIL"
fx viacont 1 1 CLEAN PATH 1 "VIA-CONTAINERS (containers pin re-enters) must FAIL"
fx unres 1 1 UNRES CLEAN 2 "UNRESOLVABLE constitution pin must be BLIND (rc 2)"
fx unrescont 1 1 CLEAN UNRES 2 "UNRESOLVABLE containers pin must be BLIND (rc 2)"
# recorded-vs-checked-out: root records L1, the checked-out HEAD of the fixture submodule is L2
r="$tmp/rec_dirty"; mk_root "$r" 1 1; L1="$(mk_llmctl "$r" "${PIN[PATH]}" "${PIN[CLEAN]}")"; record "$r" "$L1"; mk_llmctl "$r" "${PIN[CLEAN]}" "${PIN[CLEAN]}" >/dev/null
expect "RECORDED-DIRTY-HEAD-CLEAN (recorded llmctl commit re-enters) must FAIL" 1 "$r"
r="$tmp/rec_clean"; mk_root "$r" 1 1; L1="$(mk_llmctl "$r" "${PIN[CLEAN]}" "${PIN[CLEAN]}")"; record "$r" "$L1"; mk_llmctl "$r" "${PIN[PATH]}" "${PIN[CLEAN]}" >/dev/null
expect "RECORDED-CLEAN-HEAD-DIRTY (the RECORDED commit governs) must PASS" 0 "$r"
# LARGE-ENTRY (SIGPIPE x pipefail, §11.4.276(C) class member F1): the marker sits on the FIRST line of a llmctl entry
# of ~465 KB. A `printf "$entry" | grep -q` under `set -o pipefail` lets grep exit at the first match while printf is
# still writing; printf takes SIGPIPE and pipefail turns the PRESENT marker into a false "lacks the marker" FAIL.
# Repeated (the race is deterministic only well above the ~131 KB knee) and paired with the same large entry
# WITHOUT the marker, which must still FAIL — so the PASS is the marker's, not the size's.
mk_large() { # <dir> <marker 1|0> ; uninitialised submodule (check (2) SKIPs), one huge llmctl entry
  local d="$1" i; mkdir -p "$d"
  { echo "schema_version: 1"; echo "deps:"; echo "  - name: llmctl"
    [ "$2" = 1 ] && echo "    recursive_init: false    # marker"
    for i in $(seq 1 6000); do printf '    note_%05d: %s\n' "$i" "padding-padding-padding-padding-padding-padding-padding"; done
    echo "  - name: other"; echo "    layout: grouped"; } > "$d/helix-deps.yaml"
}
r="$tmp/large_marker"; mk_large "$r" 1
lsz="$(wc -c < "$r/helix-deps.yaml")"
[ "$lsz" -ge 400000 ] || { echo "❌ META BAD:  LARGE-ENTRY fixture is only $lsz bytes (needs >= 400000 to exercise the race)"; bad=1; }
for it in 1 2 3 4 5; do
  out="$(bash "$gate" --root "$r" 2>&1)"; rc=$?
  if [ "$rc" = 0 ] && grep -q 'marker recursive_init: false present' <<<"$out"; then echo "✅ META OK:   LARGE-ENTRY ($lsz B, marker on line 1) must PASS — iteration $it (rc=$rc)"
  else echo "❌ META BAD:  LARGE-ENTRY ($lsz B, marker on line 1) iteration $it want rc=0 + marker present, got rc=$rc"; echo "$out" | sed 's/^/    /'; bad=1; fi
done
r="$tmp/large_nomarker"; mk_large "$r" 0; expect "LARGE-ENTRY without the marker must FAIL" 1 "$r"
echo "======================================================================"
if [ "$bad" = 0 ]; then echo "✅ META PASS: CM-LLMCTL-SUBMODULE-NONRECURSIVE is a genuine (non-bluff) gate"; exit 0; fi
echo "❌ META FAIL: a fixture was misclassified"; exit 1
