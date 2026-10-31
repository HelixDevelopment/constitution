#!/usr/bin/env bash
# tests/layout/test_deps_manifest_layout.sh — CM-HELIX-DEPS-MANIFEST-PRESENT
# engine (scripts/deps_manifest/verify_helix_deps_manifests.sh ->
# helix_deps_manifest.py) in BOTH constitution layouts.
#
# Asserts (I-4, round 2): the constitution hub at the STANDARD path
# submodules/constitution is recognised as the hub (never reported as a leaf
# that "nests own-org/hub submodule(s)"), is not required in the root's deps,
# and its nested submodules/constitution/submodules/* repositories ARE scanned
# (a missing manifest there FAILs, a good one PASSes) — exactly as for the
# legacy path constitution. A plain leaf that nests an own-org repo still FAILs
# in both layouts (false-negative guard).
# Usage: bash tests/layout/test_deps_manifest_layout.sh
LT_SUITE="deps_manifest_layout"
. "$(cd "$(dirname "$0")" && pwd)/lib_layout_harness.sh"

ENGINE="$LAYOUT_SRC_ROOT/scripts/deps_manifest/verify_helix_deps_manifests.sh"
unset HELIX_OWN_ORGS

good_manifest() {
    printf 'schema_version: 1\n'
    if [ $# -eq 0 ]; then printf 'deps: []\n'; else printf 'deps:\n'; printf '%s\n' "$@"; fi
    printf 'transitive_handling:\n  recursive: true\n  conflict_resolution: operator-required\nlanguage_specific_subtree: false\n'
}
dep() { # name org repo
    printf '  - name: %s\n    ssh_url: git@github.com:%s/%s.git\n    ref: abc1234\n    why: "needed for %s"\n    layout: grouped\n' \
        "$1" "$2" "$3" "$1"
}
mkrepo() { # dir [manifest|-]
    mkdir -p "$1"; lt_git init -q "$1"
    if [ "${2:--}" != "-" ]; then printf '%s\n' "$2" >"$1/helix-deps.yaml"; lt_git -C "$1" add helix-deps.yaml; fi
    printf 'x\n' >"$1/f"; lt_git -C "$1" add f; lt_git -C "$1" commit -q -m init
}
addsm() { # repo path url
    lt_git -C "$1" config -f "$1/.gitmodules" "submodule.$2.path" "$2"
    lt_git -C "$1" config -f "$1/.gitmodules" "submodule.$2.url" "$3"
    lt_git -C "$1" add .gitmodules; lt_git -C "$1" commit -q -m "sm $2"
}
# mkhub ROOT REL -> a constitution hub at ROOT/REL (Constitution.md + scripts/)
# with an own-org leaf submodules/x that has NO manifest yet.
mktree() {
    local r="$1" rel="$2"
    mkrepo "$r/$rel/submodules/x" -
    mkrepo "$r/$rel" "$(good_manifest "$(dep x vasic-digital x)")"
    mkdir -p "$r/$rel/scripts"; printf '# C\n' > "$r/$rel/Constitution.md"; printf 'x\n' > "$r/$rel/scripts/k"
    lt_git -C "$r/$rel" add Constitution.md scripts; lt_git -C "$r/$rel" commit -q -m c
    addsm "$r/$rel" submodules/x git@github.com:vasic-digital/x.git
    mkrepo "$r" "$(good_manifest)"
    addsm "$r" "$rel" git@github.com:HelixDevelopment/HelixConstitution.git
}
run() { # label expected-rc must mustnot -- args
    local label="$1" erc="$2" must="$3" mustnot="$4"; shift 5
    local out rc ok=1
    out="$(bash "$ENGINE" "$@" 2>&1)"; rc=$?
    [ "$rc" = "$erc" ] || ok=0
    if [ -n "$must" ] && ! grep -Eq -- "$must" <<<"$out"; then ok=0; fi
    if [ -n "$mustnot" ] && grep -Eq -- "$mustnot" <<<"$out"; then ok=0; fi
    if [ "$ok" = 1 ]; then lt_ok "$label (rc=$rc)"; else lt_bad "$label (rc=$rc, want $erc)"; sed 's/^/     /' <<<"$out" | tail -8; fi
}

for rel in submodules/constitution constitution; do
    tag="[$rel]"
    T="$LT_SB/dm $(printf '%s' "$rel" | tr / _)"
    mktree "$T" "$rel"
    erel="$(printf '%s' "$rel" | sed 's/[/.]/\\&/g')"
    run "$tag hub-nested leaf without manifest -> FAIL names $rel/submodules/x" 1 \
        "FAIL[[:space:]]+${erel}/submodules/x.*missing" "FAIL[[:space:]]+${erel}[[:space:]].*nests own-org" -- --root "$T"
    run "$tag the hub itself is role hub, not a nesting leaf" 1 \
        "PASS[[:space:]]+${erel}[[:space:]]+hub" "nests own-org/hub" -- --root "$T"
    run "$tag the root is not asked to list the hub" 1 '' 'undeclared own-org submodule' -- --root "$T"
    printf '%s\n' "$(good_manifest)" > "$T/$rel/submodules/x/helix-deps.yaml"
    lt_git -C "$T/$rel/submodules/x" add helix-deps.yaml; lt_git -C "$T/$rel/submodules/x" commit -q -m m
    run "$tag all manifests good -> PASS incl. $rel/submodules/x" 0 \
        "PASS[[:space:]]+${erel}/submodules/x" 'FAIL' -- --root "$T"

    # false-negative guard: an ordinary own-org leaf that nests an own-org repo
    # is still refused in this layout.
    L="$LT_SB/dmleaf $(printf '%s' "$rel" | tr / _)"
    mktree "$L" "$rel"
    printf '%s\n' "$(good_manifest)" > "$L/$rel/submodules/x/helix-deps.yaml"
    lt_git -C "$L/$rel/submodules/x" add helix-deps.yaml; lt_git -C "$L/$rel/submodules/x" commit -q -m m
    mkrepo "$L/submodules/a" "$(good_manifest)"
    addsm "$L/submodules/a" submodules/k git@github.com:vasic-digital/k.git
    printf '%s\n' "$(good_manifest "$(dep a vasic-digital a)")" > "$L/helix-deps.yaml"
    lt_git -C "$L" add helix-deps.yaml; lt_git -C "$L" commit -q -m deps
    addsm "$L" submodules/a git@github.com:vasic-digital/a.git
    run "$tag a plain leaf nesting own-org is still FAIL" 1 \
        'FAIL[[:space:]]+submodules/a[[:space:]].*nests own-org' '' -- --root "$L"
done

# undeclared standard-layout checkout (no .gitmodules entry) is still the hub
U="$LT_SB/dm_undeclared"
mkrepo "$U/submodules/constitution/submodules/x" -
mkrepo "$U/submodules/constitution" "$(good_manifest "$(dep x vasic-digital x)")"
addsm "$U/submodules/constitution" submodules/x git@github.com:vasic-digital/x.git
lt_git -C "$U/submodules/constitution" remote add origin git@github.com:HelixDevelopment/HelixConstitution.git
mkdir -p "$U/submodules/constitution/scripts"; printf '# C\n' > "$U/submodules/constitution/Constitution.md"
mkrepo "$U" "$(good_manifest)"
run "undeclared submodules/constitution checkout: its nested leaf is scanned" 1 \
    'FAIL[[:space:]]+submodules/constitution/submodules/x.*missing' '' -- --root "$U"

# an UNDECLARED checkout under the standard hub's submodules/ dir is scanned too
mkrepo "$U/submodules/constitution/submodules/y" -
lt_git -C "$U/submodules/constitution/submodules/y" remote add origin git@github.com:vasic-digital/y.git
run "undeclared checkout submodules/constitution/submodules/y (not in any .gitmodules) is scanned" 1 \
    'FAIL[[:space:]]+submodules/constitution/submodules/y.*missing' '' -- --root "$U"

lt_check "verifier --selftest green" bash "$ENGINE" --selftest
lt_summary
