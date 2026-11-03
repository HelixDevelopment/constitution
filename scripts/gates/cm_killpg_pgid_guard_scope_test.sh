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
    printf 'def clean():\n    return 1\n' > "$1/submodules/mine/clean.py"
}

run_suite() { # $1=gate $2=label
    local g="$1" l="$2" T="$TMP/f_$2"
    mkfix "$T"
    local o; o="$(bash "$g" --root "$T" 2>&1)"
    if [ $? -eq 0 ] && grep -q 'PASS —' <<<"$o" && ! grep -q 'SKIP' <<<"$o" && grep -q 'PRUNED.*submodules/vend' <<<"$o"; then ok "$l: unguarded call in third_party dep pruned -> real PASS line, SKIP absent, PRUNED path printed"
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
cp "$HERE/cm_killpg_pgid_guard.sh" "$M/gates/"; cp "$HERE"/../lib/*.sh "$M/lib/"; cp "$HERE"/../deps_manifest/* "$M/deps_manifest/"
if ! grep -q 'cm_third_party_prune_find_expr "\$root"' "$M/gates/cm_killpg_pgid_guard.sh"; then bad "mutation anchor (prune call) absent from gate"
else
    sed -i 's/cm_third_party_prune_find_expr "\$root"/:/' "$M/gates/cm_killpg_pgid_guard.sh"
    T="$TMP/f_mut"; mkfix "$T"
    if bash "$M/gates/cm_killpg_pgid_guard.sh" --root "$T" >/dev/null 2>&1; then bad "mutant (no prune) still PASSed: test is not load-bearing"
    else ok "mutant (prune removed) FAILs on third_party fixture: test is load-bearing"; fi
fi

# --- round 2: hostile manifest marks FIRST-PARTY src/ as third_party; must still be scanned ---
H="$TMP/hostile"; mkdir -p "$H/src"
cat > "$H/helix-deps.yaml" <<'YML'
schema_version: 1
deps:
  - name: src
    path: src
    ssh_url: git@example.invalid:o/src.git
    ref: abc
    why: "x"
    layout: grouped
    third_party: true
    licence: MIT
YML
printf 'import os, signal\ndef k(pg):\n    os.killpg(pg, signal.SIGKILL)\n' > "$H/src/bad.py"
( cd "$H" && git init -q . && git add -A >/dev/null 2>&1 )   # git metadata present, src is NOT a gitlink
if bash "$HERE/cm_killpg_pgid_guard.sh" --root "$H" >/dev/null 2>&1; then bad "hostile manifest hid first-party src/ (gate passed)"
else ok "hostile manifest (path: src, third_party: true, not a submodule) still scanned -> FAIL"; fi
# same hostile manifest, but src IS a recorded submodule (gitlink) -> legitimately pruned
G="$TMP/gl"; mkdir -p "$G"; cp "$H/helix-deps.yaml" "$G/"
( cd "$G" && git init -q . && git -c user.email=a@b -c user.name=t commit -q --allow-empty -m i \
  && git update-index --add --cacheinfo 160000,"$(git rev-parse HEAD)",src ) >/dev/null 2>&1
mkdir -p "$G/src"; cp "$H/src/bad.py" "$G/src/"
if bash "$HERE/cm_killpg_pgid_guard.sh" --root "$G" >/dev/null 2>&1; then ok "recorded gitlink src marked third_party is pruned"
else bad "recorded gitlink third_party src was not pruned"; fi
# prefix collision: vend must not prune vend-bar
P="$TMP/pc"; mkfix "$P"; mkdir -p "$P/submodules/vend-bar"
cp "$P/submodules/vend/bad.py" "$P/submodules/vend-bar/bad.py"
if bash "$HERE/cm_killpg_pgid_guard.sh" --root "$P" >/dev/null 2>&1; then bad "vend pruned its prefix sibling vend-bar"
else ok "vend does not prune vend-bar (no prefix collision)"; fi
# paired mutation: lib without the recorded-submodule check -> hostile case must flip to PASS (i.e. our test catches it)
LM="$TMP/mut2"; mkdir -p "$LM/gates" "$LM/lib" "$LM/deps_manifest"
cp "$HERE/cm_killpg_pgid_guard.sh" "$LM/gates/"; cp "$HERE"/../lib/*.sh "$LM/lib/"; cp "$HERE"/../deps_manifest/* "$LM/deps_manifest/"
sed -i 's/if cm_tp_recorded .*; then printf/if true; then printf/' "$LM/lib/third_party_prune.sh"
if grep -q 'if true; then printf' "$LM/lib/third_party_prune.sh"; then
    if bash "$LM/gates/cm_killpg_pgid_guard.sh" --root "$H" >/dev/null 2>&1; then ok "mutant lib (no recorded check) hides src/: hostile test is load-bearing"
    else bad "mutant lib did not flip the hostile case: test not load-bearing"; fi
else bad "mutation anchor (cm_tp_recorded call) absent"; fi
# prefix-collision mutation: -path "$er/$x*" style prefix glob must be caught
LP="$TMP/mut3"; mkdir -p "$LP/gates" "$LP/lib" "$LP/deps_manifest"
cp "$HERE/cm_killpg_pgid_guard.sh" "$LP/gates/"; cp "$HERE"/../lib/*.sh "$LP/lib/"; cp "$HERE"/../deps_manifest/* "$LP/deps_manifest/"
sed -i 's#")/\*" -o)#")*" -o)#' "$LP/lib/third_party_prune.sh"
if grep -q '")\*" -o)' "$LP/lib/third_party_prune.sh"; then
    if bash "$LP/gates/cm_killpg_pgid_guard.sh" --root "$P" >/dev/null 2>&1; then ok "mutant prefix-glob prunes vend-bar: collision test is load-bearing"
    else bad "prefix-glob mutant not detected"; fi
else bad "prefix mutation anchor absent"; fi

# --- round 2b: braced shell kill target `-${pg}` is the same target as `-$pg` (was a false positive) ---
BR="$TMP/braced"; mkdir -p "$BR"
printf 'if [ "${pg}" -gt 1 ]; then\n  kill -INT -- "-${pg}"\nfi\n' > "$BR/ok.sh"
printf 'kill -INT -- "-${pg}"\n' > "$BR/bad.sh"
printf 'if [ "%spg" -gt 1 ]; then\n  kill -INT -- "-%spg:-1}"\nfi\n' '$' '${' > "$BR/dflt.sh"   # %s keeps the fixture text out of the env-read census
G="$HERE/cm_killpg_pgid_guard.sh"
if bash "$G" --root "$BR/ok.sh" --quiet >/dev/null 2>&1; then ok "guarded braced braced does not fire (golden-FALSE)"; else bad "guarded braced braced false positive"; fi
if bash "$G" --root "$BR/bad.sh" --quiet >/dev/null 2>&1; then bad "unguarded braced braced passed"; else ok "unguarded braced braced FAILs"; fi
if bash "$G" --root "$BR/dflt.sh" --quiet >/dev/null 2>&1; then bad "default-expansion -braced-default treated as the guarded name"; else ok "braced-default stays a non-name -> FAIL"; fi
BM="$TMP/mut4"; mkdir -p "$BM/gates" "$BM/lib" "$BM/deps_manifest"
cp "$G" "$BM/gates/"; cp "$HERE"/../lib/*.sh "$BM/lib/"; cp "$HERE"/../deps_manifest/* "$BM/deps_manifest/"
if grep -q 'while (match(txt, /' "$BM/gates/cm_killpg_pgid_guard.sh"; then
    sed -i 's/while (match(txt, \/\\\$\\{(\[A-Za-z_\]/while (0 \&\& match(txt, \/\\$\\{([A-Za-z_]/' "$BM/gates/cm_killpg_pgid_guard.sh"
    if grep -q 'while (0 &&' "$BM/gates/cm_killpg_pgid_guard.sh"; then
        if bash "$BM/gates/cm_killpg_pgid_guard.sh" --root "$BR/ok.sh" --quiet >/dev/null 2>&1; then bad "brace-strip mutant still passes guarded braced case"
        else ok "mutant (brace strip disabled) FAILs the guarded braced case: test is load-bearing"; fi
    else bad "brace mutation did not apply"; fi
else bad "brace mutation anchor absent"; fi
[ "$rc" -eq 0 ] && echo "SCOPE TEST PASS" || echo "SCOPE TEST FAIL"
exit "$rc"
