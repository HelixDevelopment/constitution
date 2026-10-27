#!/usr/bin/env bash
# test_verify_helix_deps_manifests.sh — hermetic tests for the canonical §11.4.31 manifest engine
# scripts/deps_manifest/verify_helix_deps_manifests.sh (verify, --validate-file, --scaffold, --selftest).
#
# ── Purpose ───────────────────────────────────────────────────────────────
# Builds throwaway git trees (root + submodules/* + constitution/submodules/*) under $TMPDIR and drives
# the REAL engine through its REAL invocation path, asserting exit code AND output for every verdict class:
# PASS, FAIL (missing / malformed / untracked / undeclared / nested own-org), SKIP(third_party) (golden-FALSE:
# a third-party repo without a manifest must never FAIL and never read as PASS), KNOWN (hub-engine nesting
# already tracked by CM-HUB-ENGINE-NO-OWNORG-NESTING), BLIND (uninitialised own-org repo, unreadable root),
# usage errors, and the scaffold mode (never overwrites; output is a correct skeleton).
#
# ── Usage ─────────────────────────────────────────────────────────────────
#   bash tests/test_verify_helix_deps_manifests.sh      Exit: 0 all cases hold · 1 a case failed · 2 env error.
#
# ── Side-effects ──────────────────────────────────────────────────────────
#   Temp dir under $TMPDIR (trap-cleaned). The real repository is never touched.
#
# ── Dependencies ──────────────────────────────────────────────────────────
#   bash, git, python3 + PyYAML (the engine's own dependencies). Classification: universal (§11.4.17).
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)"
ENGINE="$here/scripts/deps_manifest/verify_helix_deps_manifests.sh"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
unset HELIX_OWN_ORGS
bad=0; n=0

good_manifest() { # [dep-lines...] — prints a well-formed manifest whose deps are the given YAML blocks
  printf 'schema_version: 1\n'
  if [ $# -eq 0 ]; then printf 'deps: []\n'; else printf 'deps:\n'; printf '%s\n' "$@"; fi
  printf 'transitive_handling:\n  recursive: true\n  conflict_resolution: operator-required\nlanguage_specific_subtree: false\n'
}
dep() { # name org repo [extra-yaml-line...]
  local nm="$1" org="$2" repo="$3"; shift 3
  printf '  - name: %s\n    ssh_url: git@github.com:%s/%s.git\n    ref: abc1234\n    why: "needed for %s"\n    layout: grouped\n' \
    "$nm" "$org" "$repo" "$nm"
  local l; for l in "$@"; do printf '    %s\n' "$l"; done
}
mkrepo() { # dir [manifest-content|-] — git repo; manifest committed when given ('-' = none)
  mkdir -p "$1"; git -C "$1" init -q
  if [ "${2:--}" != "-" ]; then printf '%s\n' "$2" >"$1/helix-deps.yaml"; git -C "$1" add helix-deps.yaml; fi
  echo x >"$1/f"; git -C "$1" add f; git -C "$1" commit -q -m init
}
addsm() { # root path url — record a .gitmodules entry (name = path)
  git -C "$1" config -f "$1/.gitmodules" "submodule.$2.path" "$2"
  git -C "$1" config -f "$1/.gitmodules" "submodule.$2.url" "$3"
}
run() { # label expected-rc regex-must regex-mustnot -- args...
  local label="$1" erc="$2" must="$3" mustnot="$4"; shift 5
  n=$((n+1))
  local out rc; out="$(bash "$ENGINE" "$@" 2>&1)"; rc=$?
  local ok=1
  [ "$rc" = "$erc" ] || { echo "BAD  $label: expected rc=$erc got rc=$rc"; ok=0; }
  if [ -n "$must" ] && ! grep -Eq -- "$must" <<<"$out"; then echo "BAD  $label: output lacks /$must/"; ok=0; fi
  if [ -n "$mustnot" ] && grep -Eq -- "$mustnot" <<<"$out"; then echo "BAD  $label: output has forbidden /$mustnot/"; ok=0; fi
  if [ "$ok" = 1 ]; then echo "ok   $label (rc=$rc)"; else bad=1; sed 's/^/     /' <<<"$out" | tail -20; fi
}
# A complete good tree: root (own-org a declared) + submodules/a (own-org, manifest) + submodules/tp (third-party, no manifest)
mktree() { # dir
  local r="$1"; mkdir -p "$r"
  mkrepo "$r/submodules/a" "$(good_manifest)"
  mkrepo "$r/submodules/tp" -
  git -C "$r/submodules/tp" remote add origin git@github.com:someone/tp.git
  mkrepo "$r" "$(good_manifest "$(dep a vasic-digital a)")"
  addsm "$r" submodules/a git@github.com:vasic-digital/a.git
  addsm "$r" submodules/tp git@github.com:someone/tp.git
  git -C "$r" add .gitmodules && git -C "$r" commit -q -m sm
}

[ -r "$ENGINE" ] || { echo "RED: engine missing at $ENGINE"; exit 1; }

# 1 golden-good
T="$tmp/good"; mktree "$T"
run GOOD 0 'VERDICT: PASS' 'FAIL' -- --root "$T"
# golden-FALSE: the third-party repo without a manifest is SKIP(third_party), never FAIL, never PASS
run THIRD-PARTY-SKIP-NOT-PASS 0 'SKIP\(third_party\)[[:space:]]+submodules/tp' 'PASS[[:space:]]+submodules/tp' -- --root "$T"
# 2 missing leaf manifest
T="$tmp/missleaf"; mktree "$T"; git -C "$T/submodules/a" rm -q helix-deps.yaml; git -C "$T/submodules/a" commit -q -m rm
run MISSING-LEAF 1 'FAIL[[:space:]]+submodules/a.*missing' '' -- --root "$T"
# 3 missing root manifest
T="$tmp/missroot"; mktree "$T"; git -C "$T" rm -q helix-deps.yaml; git -C "$T" commit -q -m rm
run MISSING-ROOT 1 'FAIL[[:space:]]+\..*missing' '' -- --root "$T"
# 4 https ssh_url
T="$tmp/https"; mktree "$T"; sed -i 's#git@github.com:vasic-digital/a.git#https://github.com/vasic-digital/a.git#' "$T/helix-deps.yaml"
run HTTPS-URL 1 'ssh_url' '' -- --root "$T"
# 5 missing why / placeholder why
T="$tmp/nowhy"; mktree "$T"; sed -i '/why:/d' "$T/helix-deps.yaml"
run MISSING-WHY 1 'why' '' -- --root "$T"
T="$tmp/unkwhy"; mktree "$T"; sed -i 's#why: .*#why: "UNKNOWN: describe"#' "$T/helix-deps.yaml"
run PLACEHOLDER-WHY 1 'placeholder' '' -- --root "$T"
# 6 bad layout
T="$tmp/layout"; mktree "$T"; sed -i 's#layout: grouped#layout: nested#' "$T/helix-deps.yaml"
run BAD-LAYOUT 1 'layout' '' -- --root "$T"
# 7 unknown key
T="$tmp/unk"; mktree "$T"; sed -i 's#    layout: grouped#    layout: grouped\n    colour: red#' "$T/helix-deps.yaml"
run UNKNOWN-KEY 1 'unknown key.*colour' '' -- --root "$T"
# 8 duplicate key
T="$tmp/dupkey"; mktree "$T"; sed -i 's#    layout: grouped#    layout: grouped\n    layout: flat#' "$T/helix-deps.yaml"
run DUPLICATE-KEY 1 'duplicate key' '' -- --root "$T"
# 9 schema_version 2
T="$tmp/schema"; mktree "$T"; sed -i 's#schema_version: 1#schema_version: 2#' "$T/submodules/a/helix-deps.yaml"
git -C "$T/submodules/a" commit -qam s
run SCHEMA-VERSION 1 'schema_version' '' -- --root "$T"
# 10 root does not declare an own-org submodule it carries
T="$tmp/undecl"; mktree "$T"; good_manifest >"$T/helix-deps.yaml"; git -C "$T" commit -qam u
run ROOT-UNDECLARED 1 'undeclared own-org submodule.*submodules/a' '' -- --root "$T"
# 11 leaf nests an own-org submodule -> FAIL; with recursive_init: false on the parent entry -> KNOWN, exit 0
T="$tmp/nest"; mktree "$T"; addsm "$T/submodules/a" submodules/x git@github.com:HelixDevelopment/x.git
git -C "$T/submodules/a" add .gitmodules && git -C "$T/submodules/a" commit -q -m n
run NESTED-OWNORG 1 'FAIL[[:space:]]+submodules/a.*nests own-org' '' -- --root "$T"
T="$tmp/nestknown"; mktree "$T"; addsm "$T/submodules/a" submodules/x git@github.com:HelixDevelopment/x.git
git -C "$T/submodules/a" add .gitmodules && git -C "$T/submodules/a" commit -q -m n
good_manifest "$(dep a vasic-digital a 'recursive_init: false')" >"$T/helix-deps.yaml"; git -C "$T" commit -qam k
run NESTED-KNOWN 0 'KNOWN[[:space:]]+submodules/a.*CM-HUB-ENGINE-NO-OWNORG-NESTING' 'FAIL' -- --root "$T"
# 12 own-org leaf not checked out -> BLIND (exit 2), never PASS
T="$tmp/uninit"; mktree "$T"; addsm "$T" submodules/b git@github.com:vasic-digital/b.git
good_manifest "$(dep a vasic-digital a)" "$(dep b vasic-digital b)" >"$T/helix-deps.yaml"; git -c advice.addEmbeddedRepo=false -C "$T" add -A; git -C "$T" commit -q -m b
run UNINIT-BLIND 2 'BLIND[[:space:]]+submodules/b' 'VERDICT: PASS' -- --root "$T"
# 13 root missing / usage
run ROOT-ABSENT 2 'BLIND' '' -- --root "$tmp/does-not-exist"
run NO-ROOT-USAGE 64 'usage' '' --
# 14 manifest present but untracked in the leaf
T="$tmp/untracked"; mktree "$T"; git -C "$T/submodules/a" rm -q --cached helix-deps.yaml; git -C "$T/submodules/a" commit -q -m u
run UNTRACKED 1 'not tracked' '' -- --root "$T"
# 15 constitution layout: root/constitution (hub) + constitution/submodules/x (own-org) without manifest
T="$tmp/hub"; mktree "$T"
mkrepo "$T/constitution/submodules/x" -
mkrepo "$T/constitution" "$(good_manifest "$(dep x vasic-digital x)")"
addsm "$T/constitution" submodules/x git@github.com:vasic-digital/x.git; git -C "$T/constitution" add .gitmodules; git -C "$T/constitution" commit -q -m x
addsm "$T" constitution git@github.com:HelixDevelopment/HelixConstitution.git; git -C "$T" add .gitmodules; git -C "$T" commit -q -m c
run HUB-LEAF-MISSING 1 'FAIL[[:space:]]+constitution/submodules/x.*missing' 'undeclared own-org submodule.*constitution[^/]' -- --root "$T"
printf '%s\n' "$(good_manifest)" >"$T/constitution/submodules/x/helix-deps.yaml"; git -C "$T/constitution/submodules/x" add helix-deps.yaml; git -C "$T/constitution/submodules/x" commit -q -m m
run HUB-GOOD 0 'PASS[[:space:]]+constitution/submodules/x' '' -- --root "$T"
# 16 custom own-org list turns the third-party repo into a required one
T="$tmp/orgs"; mktree "$T"
run CUSTOM-ORGS 1 'FAIL[[:space:]]+submodules/tp' '' -- --root "$T" --own-orgs vasic-digital,someone
# 17 a non-own-org dep without third_party: true; third_party without licence
T="$tmp/tpdep"; mktree "$T"; good_manifest "$(dep a vasic-digital a)" "$(dep z other z)" >"$T/helix-deps.yaml"; git -C "$T" commit -qam z
run FOREIGN-DEP-UNMARKED 1 'third_party' '' -- --root "$T"
good_manifest "$(dep a vasic-digital a)" "$(dep z other z 'third_party: true')" >"$T/helix-deps.yaml"; git -C "$T" commit -qam z
run THIRD-PARTY-NO-LICENCE 1 'licence' '' -- --root "$T"
good_manifest "$(dep a vasic-digital a)" "$(dep z other z 'third_party: true' 'licence: MIT')" >"$T/helix-deps.yaml"; git -C "$T" commit -qam z
run THIRD-PARTY-DECLARED 0 'VERDICT: PASS' '' -- --root "$T"
# 18 --validate-file
run VALIDATE-FILE-GOOD 0 'PASS' '' -- --validate-file "$tmp/good/helix-deps.yaml"
run VALIDATE-FILE-BAD 1 'FAIL' '' -- --validate-file "$tmp/https/helix-deps.yaml"
# 19 scaffold: prints a skeleton from .gitmodules + go.mod + package.json; never overwrites
T="$tmp/scaf"; mkdir -p "$T"; git -C "$T" init -q
addsm "$T" submodules/foo git@github.com:vasic-digital/Foo.git
addsm "$T" submodules/ext https://github.com/someone/ext.git
printf 'module x\n\nrequire (\n\tgithub.com/HelixDevelopment/gomod-dep v1.2.3\n\tdigital.vasic.assets v0.1.0\n)\n' >"$T/go.mod"
printf '{"dependencies":{"pkgdep":"github:vasic-digital/pkg-dep#v1"}}\n' >"$T/package.json"
run SCAFFOLD-PRINT 0 'name: foo' '' -- --scaffold "$T"
out="$(bash "$ENGINE" --scaffold "$T" 2>/dev/null)"
n=$((n+1))
if grep -q 'ssh_url: git@github.com:vasic-digital/Foo.git' <<<"$out" && grep -q 'layout: grouped' <<<"$out" \
   && grep -q 'git@github.com:HelixDevelopment/gomod-dep.git' <<<"$out" && grep -q 'git@github.com:vasic-digital/pkg-dep.git' <<<"$out" \
   && grep -q 'digital.vasic.assets' <<<"$out" && ! grep -q 'someone/ext' <<<"$out" && grep -q 'UNKNOWN' <<<"$out"; then
  echo "ok   SCAFFOLD-CONTENT"; else echo "BAD  SCAFFOLD-CONTENT"; sed 's/^/     /' <<<"$out"; bad=1; fi
printf '%s\n' "$out" >"$T/sk.yaml"
run SCAFFOLD-IS-NOT-A-PASS 1 'placeholder' '' -- --validate-file "$T/sk.yaml"
sed -e 's#why: "UNKNOWN:[^"]*"#why: "filled in by a human"#' -e 's#ref: UNKNOWN-pin-me#ref: main#' "$T/sk.yaml" >"$T/sk2.yaml"
run SCAFFOLD-FILLED-PASSES 0 'PASS' '' -- --validate-file "$T/sk2.yaml"
run SCAFFOLD-WRITE 0 'wrote' '' -- --scaffold "$T" --write
n=$((n+1)); [ -f "$T/helix-deps.yaml" ] && echo "ok   SCAFFOLD-WRITE-CREATED" || { echo "BAD  SCAFFOLD-WRITE-CREATED"; bad=1; }
echo "keep-me" >"$T/helix-deps.yaml"
run SCAFFOLD-NEVER-OVERWRITES 1 'exists' '' -- --scaffold "$T" --write
n=$((n+1)); [ "$(cat "$T/helix-deps.yaml")" = "keep-me" ] && echo "ok   SCAFFOLD-FILE-UNCHANGED" || { echo "BAD  SCAFFOLD-FILE-UNCHANGED"; bad=1; }
# 21 .gitmodules URL forms: https / ssh:// / scp-style, single-segment paths (https://go.googlesource.com/go)
for spec in "HTTPS-SINGLE-SEGMENT|https://go.googlesource.com/go" "HTTPS-THIRDPARTY|https://example.org/someone/tp.git" \
            "HTTPS-NESTED-GROUP|https://gitlab.com/grp/sub/tp.git" "SSH-URL-THIRDPARTY|ssh://git@example.org:2222/someone/tp.git" \
            "SCP-SINGLE-SEGMENT|git@example.org:tp.git"; do
  lab="${spec%%|*}"; url="${spec#*|}"
  T="$tmp/url-$lab"; mktree "$T"; mkrepo "$T/submodules/h" -
  addsm "$T" submodules/h "$url"; git -C "$T" add .gitmodules && git -C "$T" commit -q -m h
  run "URL-$lab" 0 'SKIP\(third_party\)[[:space:]]+submodules/h' 'BLIND|FAIL' -- --root "$T"
done
# https own-org URL is still own-org: checked out + manifest -> PASS; not checked out -> BLIND (not SKIP); undeclared -> FAIL
T="$tmp/url-own-https"; mktree "$T"; mkrepo "$T/submodules/h" "$(good_manifest)"
addsm "$T" submodules/h https://github.com/vasic-digital/h.git
good_manifest "$(dep a vasic-digital a)" "$(dep h vasic-digital h)" >"$T/helix-deps.yaml"; git -C "$T" add -A; git -C "$T" commit -q -m h
run URL-OWNORG-HTTPS-PASS 0 'PASS[[:space:]]+submodules/h' 'SKIP\(third_party\)[[:space:]]+submodules/h|BLIND' -- --root "$T"
good_manifest "$(dep a vasic-digital a)" >"$T/helix-deps.yaml"; git -C "$T" commit -qam undecl
run URL-OWNORG-HTTPS-UNDECLARED 1 'undeclared own-org submodule submodules/h' '' -- --root "$T"
T="$tmp/url-own-ssh-url"; mktree "$T"; addsm "$T" submodules/b ssh://git@github.com/HelixDevelopment/b.git
good_manifest "$(dep a vasic-digital a)" "$(dep b HelixDevelopment b)" >"$T/helix-deps.yaml"; git -C "$T" add -A; git -C "$T" commit -q -m b
run URL-OWNORG-SSHURL-UNINIT-BLIND 2 'BLIND[[:space:]]+submodules/b.*not checked out' 'SKIP\(third_party\)[[:space:]]+submodules/b' -- --root "$T"
# truly unparseable URLs stay BLIND
for spec in "FTP|ftp://example.org/o/r.git" "NO-PATH|https://example.org/" "DOTDOT|https://example.org/a/../b" "SPACES|not a url"; do
  lab="${spec%%|*}"; url="${spec#*|}"
  T="$tmp/url-bad-$lab"; mktree "$T"; mkrepo "$T/submodules/h" -
  addsm "$T" submodules/h "$url"; git -C "$T" add .gitmodules && git -C "$T" commit -q -m h
  run "URL-UNPARSEABLE-$lab" 2 'BLIND[[:space:]]+submodules/h.*unparseable' 'SKIP\(third_party\)[[:space:]]+submodules/h' -- --root "$T"
done
# 22 relative .gitmodules URLs (git's superproject-relative ./x and ../x) resolve against the parent's URL,
#    so ../Containers.git under an own-org repository is own-org; unresolvable ones are BLIND, never a pass
T="$tmp/rel-nest-own"; mktree "$T"; addsm "$T/submodules/a" submodules/c ../Containers.git
git -C "$T/submodules/a" add .gitmodules && git -C "$T/submodules/a" commit -q -m n
run RELATIVE-NESTED-OWNORG 1 'FAIL[[:space:]]+submodules/a.*nests own-org.*vasic-digital/Containers' '' -- --root "$T"
T="$tmp/rel-nest-tp"; mktree "$T"; addsm "$T/submodules/a" submodules/l ../../ggml-org/llama.cpp.git
git -C "$T/submodules/a" add .gitmodules && git -C "$T/submodules/a" commit -q -m n
run RELATIVE-NESTED-THIRDPARTY 0 'PASS[[:space:]]+submodules/a' 'FAIL' -- --root "$T"
T="$tmp/rel-nest-unres"; mktree "$T"; addsm "$T/submodules/a" submodules/z ../../../../z.git
git -C "$T/submodules/a" add .gitmodules && git -C "$T/submodules/a" commit -q -m n
run RELATIVE-NESTED-UNRESOLVABLE 2 'BLIND[[:space:]]+submodules/a.*relative' 'VERDICT: PASS' -- --root "$T"
T="$tmp/rel-root"; mktree "$T"; git -C "$T" remote add origin git@github.com:vasic-digital/root.git
mkrepo "$T/submodules/h" "$(good_manifest)"; addsm "$T" submodules/h ../h.git; git -C "$T" add .gitmodules && git -C "$T" commit -q -m h
run RELATIVE-ROOT-UNDECLARED 1 'undeclared own-org submodule submodules/h' '' -- --root "$T"
good_manifest "$(dep a vasic-digital a)" "$(dep h vasic-digital h)" >"$T/helix-deps.yaml"; git -C "$T" commit -qam h
run RELATIVE-ROOT-DECLARED 0 'PASS[[:space:]]+submodules/h' 'BLIND|SKIP\(third_party\)[[:space:]]+submodules/h' -- --root "$T"
T="$tmp/rel-root-noorigin"; mktree "$T"; mkrepo "$T/submodules/h" "$(good_manifest)"; addsm "$T" submodules/h ../h.git
git -C "$T" add .gitmodules && git -C "$T" commit -q -m h
run RELATIVE-ROOT-UNRESOLVABLE 2 'BLIND[[:space:]]+submodules/h.*relative' 'PASS[[:space:]]+submodules/h' -- --root "$T"
# 23 a hub NAME under a foreign owner nested in a leaf is still forbidden (is_hub_name in the nesting filter)
T="$tmp/hubname-nest"; mktree "$T"; addsm "$T/submodules/a" submodules/k git@github.com:someone/constitution.git
git -C "$T/submodules/a" add .gitmodules && git -C "$T/submodules/a" commit -q -m n
run HUB-NAME-NESTED-FOREIGN-OWNER 1 'FAIL[[:space:]]+submodules/a.*nests own-org/hub.*someone/constitution' '' -- --root "$T"
# 24 transitive_handling.conflict_resolution other than operator-required is a defect
T="$tmp/conflict"; mktree "$T"; sed -i 's#conflict_resolution: operator-required#conflict_resolution: auto-merge#' "$T/helix-deps.yaml"
run CONFLICT-RESOLUTION 1 'conflict_resolution' '' -- --root "$T"
# 25 is_checkout: an own-org leaf whose directory holds only an EMPTY .git directory is not a checkout (git would
#    find the ROOT repository there) -> BLIND; a leaf that is a symlink to a real checkout IS one -> PASS
T="$tmp/emptygit"; mktree "$T"; mkdir -p "$T/submodules/b/.git"; addsm "$T" submodules/b git@github.com:vasic-digital/b.git
good_manifest "$(dep a vasic-digital a)" "$(dep b vasic-digital b)" >"$T/helix-deps.yaml"; git -C "$T" add .gitmodules helix-deps.yaml; git -C "$T" commit -q -m b
run EMPTY-GITDIR-NOT-A-CHECKOUT 2 'BLIND[[:space:]]+submodules/b.*not checked out' 'FAIL|PASS[[:space:]]+submodules/b' -- --root "$T"
T="$tmp/symlink"; mktree "$T"; mkrepo "$tmp/symlink-target-b" "$(good_manifest)"; ln -s "$tmp/symlink-target-b" "$T/submodules/b"
addsm "$T" submodules/b git@github.com:vasic-digital/b.git
good_manifest "$(dep a vasic-digital a)" "$(dep b vasic-digital b)" >"$T/helix-deps.yaml"; git -C "$T" add .gitmodules helix-deps.yaml; git -C "$T" commit -q -m b
run SYMLINKED-CHECKOUT 0 'PASS[[:space:]]+submodules/b' 'BLIND' -- --root "$T"
# 20 built-in self-test (control needles + golden fixtures inside the engine)
run SELFTEST 0 'SELFTEST PASS' '' -- --selftest

echo "cases=$n"
[ "$bad" = 0 ] && echo "PASS — verify_helix_deps_manifests.sh classifies every case" || { echo "FAIL"; exit 1; }
