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
[ "$rc" -eq 0 ] && echo "✅ META: all expectations held" || echo "❌ META: violations above"
exit "$rc"
