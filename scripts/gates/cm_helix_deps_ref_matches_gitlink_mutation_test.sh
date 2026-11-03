#!/usr/bin/env bash
# cm_helix_deps_ref_matches_gitlink_mutation_test.sh — §1.1 paired-mutation
# meta-test for CM-HELIX-DEPS-REF-MATCHES-GITLINK.
#
# ── Purpose ──────────────────────────────────────────────────────────────────
# Builds a disposable fixture repo (two gitlinks recorded with
# `git update-index --cacheinfo`, a .gitmodules, a helix-deps.yaml whose refs
# match) that MUST PASS, then mutates fresh copies, each of which MUST make the
# gate exit with the stated code:
#   (1) a hex ref that disagrees with its gitlink        => 1 (DRIFT)
#   (2) a dep whose url is in no .gitmodules entry       => 2 (BLIND)
#   (3) a tag ref that cannot be resolved (no checkout)  => 2 (BLIND)
#   (4) an empty deps list (the instrument sees nothing) => 2 (BLIND)
#   (5) control: a tag ref resolving to the gitlink      => 0
#   (6) nested `path:` entry (gitlink inside a root submodule) matching => 0
#   (7) nested entry whose ref disagrees with the nested gitlink        => 1 (DRIFT)
#   (8) nested entry whose parent submodule has no gitlink in the root  => 2 (BLIND)
#   (9) root-level entry WITH `path:` and the right ssh_url             => 0
#  (10) root-level entry WITH `path:` but an ssh_url that differs from .gitmodules => 2 (BLIND)
# ── Usage ────────────────────────────────────────────────────────────────────
#   cm_helix_deps_ref_matches_gitlink_mutation_test.sh
# ── Side-effects ─────────────────────────────────────────────────────────────
#   Temp fixtures under $TMPDIR, removed on EXIT.
# ── Dependencies ─────────────────────────────────────────────────────────────
#   bash, git + the sibling gate.
# ── Exit codes ───────────────────────────────────────────────────────────────
#   0 every expectation held · 1 an expectation was violated · 2 gate missing.
# Cross-refs: §1.1, §11.4.31, §11.4.201. Classification: universal (§11.4.17).
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
GATE="$SCRIPT_DIR/cm_helix_deps_ref_matches_gitlink.sh"
[ -f "$GATE" ] || { echo "META: gate missing" >&2; exit 2; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/cm_hdeps_mut.XXXXXX")"; trap 'rm -rf "${TMP:?}"' EXIT
G=(git -c user.email=t@t -c user.name=t -c init.defaultBranch=main)
# a real repo for the tag-resolving dep (checked out at its path)
SRC="$TMP/src"; "${G[@]}" init -q "$SRC"; "${G[@]}" -C "$SRC" commit -q --allow-empty -m one
NESTSHA="fedcba9876543210fedcba9876543210fedcba98"
"${G[@]}" -C "$SRC" update-index --add --cacheinfo "160000,$NESTSHA,submodules/c"
printf '[submodule "c"]\n\tpath = submodules/c\n\turl = git@x:o/c.git\n' >"$SRC/.gitmodules"   # the PARENT records the nested url (round 3, I4)
"${G[@]}" -C "$SRC" add .gitmodules
"${G[@]}" -C "$SRC" commit -q -m nested
"${G[@]}" -C "$SRC" tag v1; TAGSHA="$("${G[@]}" -C "$SRC" rev-parse HEAD)"
HEXSHA="0123456789abcdef0123456789abcdef01234567"
build() { # root [ref-a] [ref-b] [url-b]
  local r="$1"; "${G[@]}" init -q "$r"
  printf '[submodule "a"]\n\tpath = submodules/a\n\turl = git@x:o/a.git\n[submodule "b"]\n\tpath = submodules/b\n\turl = git@x:o/b.git\n' >"$r/.gitmodules"
  "${G[@]}" -C "$r" update-index --add --cacheinfo "160000,$HEXSHA,submodules/a"
  "${G[@]}" -C "$r" update-index --add --cacheinfo "160000,$TAGSHA,submodules/b"
  mkdir -p "$r/submodules"; cp -a "$SRC" "$r/submodules/b"
  printf 'schema_version: 1\n\ndeps:\n  - name: a\n    ssh_url: git@x:o/a.git\n    ref: %s\n    layout: grouped\n\n  - name: b\n    ssh_url: %s\n    ref: %s\n    layout: grouped\n\nother: 1\n' \
    "${2:-0123456}" "${4:-git@x:o/b.git}" "${3:-v1}" >"$r/helix-deps.yaml"
}
build_nested() { # root nested-ref nested-path
  local r="$1"; build "$r"
  printf '[submodule "c"]\n\tpath = x\n\turl = git@x:o/c.git\n' >>"$r/.gitmodules"
  printf '  - name: c\n    ssh_url: git@x:o/c.git\n    ref: %s\n    layout: grouped\n    path: %s\n\n' "$2" "$3" >"$r/nested.tmp"
  awk -v f="$r/nested.tmp" '/^other:/{while((getline l<f)>0)print l} {print}' "$r/helix-deps.yaml" >"$r/h.new" && mv "$r/h.new" "$r/helix-deps.yaml"
  rm -f "$r/nested.tmp"
  # the nested url must NOT be in the root .gitmodules (it lives in the parent)
  printf '[submodule "a"]\n\tpath = submodules/a\n\turl = git@x:o/a.git\n[submodule "b"]\n\tpath = submodules/b\n\turl = git@x:o/b.git\n' >"$r/.gitmodules"
}
rc=0
expect() { # want desc root
  bash "$GATE" --root "$3" >/dev/null 2>&1; local g=$?
  if [ "$g" = "$1" ]; then echo "✅ META OK:   $2 — gate exit $g as required"; else echo "❌ META FAIL: $2 — gate exit $g, wanted $1"; rc=1; fi
}
build "$TMP/clean"; expect 0 "clean fixture (hex prefix + resolvable tag) — control" "$TMP/clean"
build "$TMP/m1" 0123457; expect 1 "hex ref disagrees with its gitlink" "$TMP/m1"
build "$TMP/m2" 0123456 v1 git@x:o/nowhere.git; expect 2 "dep url in no .gitmodules entry" "$TMP/m2"
build "$TMP/m3" 0123456 v9; expect 2 "tag ref not resolvable" "$TMP/m3"
build "$TMP/m4"; printf 'schema_version: 1\ndeps: []\n' >"$TMP/m4/helix-deps.yaml"; expect 2 "empty deps list" "$TMP/m4"
build_nested "$TMP/n1" fedcba9 submodules/b/submodules/c; expect 0 "nested path entry matching the nested gitlink" "$TMP/n1"
build_nested "$TMP/n2" fedcba8 submodules/b/submodules/c; expect 1 "nested path entry ref disagrees with nested gitlink" "$TMP/n2"
build_nested "$TMP/n3" fedcba9 submodules/zzz/submodules/c; expect 2 "nested path whose parent has no root gitlink" "$TMP/n3"
build "$TMP/p1"; sed -i 's#^    ssh_url: git@x:o/a.git#&\n    path: submodules/a#' "$TMP/p1/helix-deps.yaml"; expect 0 "root-level entry with path: and matching url" "$TMP/p1"
build "$TMP/p2"; sed -i 's#^    ssh_url: git@x:o/a.git#    ssh_url: git@x:o/other.git\n    path: submodules/a#' "$TMP/p2/helix-deps.yaml"; expect 1 "root-level entry with path: but url differs from .gitmodules (a determinable manifest lie = DRIFT, round 3 N1)" "$TMP/p2"
# round 3 I4: a nested entry whose ssh_url differs from the url the PARENT records must not MATCH
build_nested "$TMP/n4" fedcba9 submodules/b/submodules/c; sed -i 's#ssh_url: git@x:o/c.git#ssh_url: git@evil:o/c.git#' "$TMP/n4/helix-deps.yaml"; expect 1 "nested entry with an attacker ssh_url (parent .gitmodules says otherwise)" "$TMP/n4"
# round 3: field ORDER must not matter (a dep opening with ssh_url:, name later); quoted values and trailing comments parse
ordered() { # $1 root $2 ref-of-b
  build "$1"; printf 'schema_version: 1\n\ndeps:\n  - ssh_url: "git@x:o/a.git"   # quoted + comment\n    name: a\n    ref: 0123456\n    layout: grouped\n\n  - ssh_url: git@x:o/b.git\n    ref: %s\n    name: b\n    layout: grouped\n\nother: 1\n' "$2" >"$1/helix-deps.yaml"
}
ordered "$TMP/o1" v1; expect 0 "deps whose items open with ssh_url:/ref: (any field order), quoted values, trailing comments" "$TMP/o1"
ordered "$TMP/o2" v9; expect 2 "order-independent parse still BLINDs on an unresolvable tag" "$TMP/o2"
[ "$rc" -eq 0 ] && echo "✅ META: all expectations held" || echo "❌ META: violations above"
exit "$rc"
