#!/usr/bin/env bash
# cm_killpg_pgid_guard_scope_test.sh — test + paired mutation for the scan SCOPE of
# CM-KILLPG-PGID-GUARD (§11.4.263): third-party trees (helix-deps.yaml deps with
# `third_party: true`, via scripts/lib/third_party_prune.sh) are pruned by default,
# own-org code stays scanned, --include-third-party opts back in.
# Usage: cm_killpg_pgid_guard_scope_test.sh   Exit 0 all hold, 1 otherwise.
# Side effects: private mktemp -d, trap-cleaned. Read-only on the repo. Inert fixtures.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/killpg_scope.XXXXXX")" || exit 2
trap 'rm -rf "${TMP:?}"' EXIT
rc=0
ok()  { echo "OK:   $1"; }
bad() { echo "FAIL: $1"; rc=1; }

mkfix() { # $1=dir : root with third-party dep `vend` (unguarded call) and own-org `mine`
    mkdir -p "$1/submodules/vend" "$1/submodules/mine"
    cat > "$1/helix-deps.yaml" <<'YML'
schema_version: 1
deps:
  - name: vend
    ssh_url: git@example.invalid:o/vend.git
    ref: abc
    why: "x"
    layout: grouped
    third_party: true
    licence: MIT
  - name: mine
    ssh_url: git@example.invalid:o/mine.git
    ref: abc
    why: "x"
    layout: grouped
YML
    printf 'import os, signal\ndef k(pg):\n    os.killpg(pg, signal.SIGKILL)\n' > "$1/submodules/vend/bad.py"
}

run_suite() { # $1=gate $2=label
    local g="$1" l="$2" T="$TMP/f_$2"
    mkfix "$T"
    if bash "$g" --root "$T" >/dev/null 2>&1; then ok "$l: unguarded call in third_party dep pruned -> PASS"
    else bad "$l: third_party dep still scanned (expected PASS)"; fi
    if bash "$g" --root "$T" --include-third-party >/dev/null 2>&1; then bad "$l: --include-third-party did not scan the third_party dep"
    else ok "$l: --include-third-party scans it -> FAIL"; fi
    cp "$T/submodules/vend/bad.py" "$T/submodules/mine/bad.py"
    if bash "$g" --root "$T" >/dev/null 2>&1; then bad "$l: golden-FALSE broken: own-org unguarded call passed"
    else ok "$l: own-org unguarded call still FAILs"; fi
}

run_suite "$HERE/cm_killpg_pgid_guard.sh" real

# paired mutation: private copy of gate+libs with the prune call removed -> the suite must fail
M="$TMP/mut"; mkdir -p "$M/gates" "$M/lib" "$M/deps_manifest"
cp "$HERE/cm_killpg_pgid_guard.sh" "$M/gates/"; cp "$HERE"/../lib/*.sh "$M/lib/"; cp "$HERE"/../deps_manifest/helix_deps_tsv.* "$M/deps_manifest/"
if ! grep -q 'cm_third_party_prune_find_expr "\$root"' "$M/gates/cm_killpg_pgid_guard.sh"; then bad "mutation anchor (prune call) absent from gate"
else
    sed -i 's/cm_third_party_prune_find_expr "\$root"/:/' "$M/gates/cm_killpg_pgid_guard.sh"
    T="$TMP/f_mut"; mkfix "$T"
    if bash "$M/gates/cm_killpg_pgid_guard.sh" --root "$T" >/dev/null 2>&1; then bad "mutant (no prune) still PASSed: test is not load-bearing"
    else ok "mutant (prune removed) FAILs on third_party fixture: test is load-bearing"; fi
fi
[ "$rc" -eq 0 ] && echo "SCOPE TEST PASS" || echo "SCOPE TEST FAIL"
exit "$rc"
