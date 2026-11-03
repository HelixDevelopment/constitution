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

BADPY='import os, signal\ndef k(pg):\n    os.killpg(pg, signal.SIGKILL)\n'
GIT() { env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
    git -c protocol.file.allow=always -c core.hooksPath=/dev/null -c init.defaultBranch=main "$@"; }
mkrepo() { # $1=dir [$2=file to hold a bad call, default bad.py] : real repo with one commit
    mkdir -p "$1"; GIT -C "$1" init -q . || return 1
    printf "$BADPY" > "$1/${2:-bad.py}"; GIT -C "$1" add -A >/dev/null; GIT -C "$1" commit -q -m i
}
addsub() { # $1=parent repo $2=remote repo $3=path $4=.gitmodules URL
    GIT -C "$1" submodule add -q "file://$2" "$3" >/dev/null 2>&1 || { echo "fixture: submodule add failed ($3)" >&2; return 1; }
    GIT -C "$1" config -f .gitmodules "submodule.$3.url" "$4"
}
manifest() { # $1=file $2=dep path $3=third_party true|false
    cat > "$1" <<YML
schema_version: 1
deps:
  - name: $(basename "$2")
    path: $2
    ssh_url: git@example.invalid:o/x.git
    ref: abc
    why: "x"
    layout: grouped
    third_party: $3
    licence: MIT
YML
}
commitall() { GIT -C "$1" add -A >/dev/null 2>&1; GIT -C "$1" commit -q -m c >/dev/null 2>&1; }
GO='https://github.com/golang/go.git'; OWN='https://github.com/vasic-digital/mine.git'
gout() { bash "$@" 2>&1; return 0; }
pruned()  { local o; o="$(bash "$1" --root "$2" 2>&1)"; [ $? -eq 0 ] && grep -q "PRUNED.*$3" <<<"$o" && ! grep -q 'SKIP' <<<"$o"; }
pline()   { grep -q "PRUNED.*$3" <<<"$(gout "$1" --root "$2")"; }
scanned() { ! bash "$1" --root "$2" >/dev/null 2>&1; }

# fixture A: manifest-marked third-party gitlink (M) + own-org gitlink (scanned) + URL-third gitlink (U)
mkA() { # $1=dir
    local R="$TMP/rem_$(basename "$1")"; mkrepo "$R/vend"; mkrepo "$R/mine"; mkrepo "$R/url"
    mkdir -p "$1"; GIT -C "$1" init -q . ; manifest "$1/helix-deps.yaml" submodules/vend true
    addsub "$1" "$R/vend" submodules/vend 'file:///x/vend.git' && addsub "$1" "$R/mine" submodules/mine "$OWN" && addsub "$1" "$R/url" submodules/url "$GO" || return 1
    commitall "$1"
}
run_suite() { # $1=gate $2=label
    local g="$1" l="$2" T="$TMP/f_$2"
    mkA "$T" || { bad "$l: fixture A could not be built"; return; }
    local o; o="$(bash "$g" --root "$T" 2>&1)"; local r=$?
    if grep -q 'PRUNED.*submodules/vend' <<<"$o" && grep -q 'PRUNED.*submodules/url' <<<"$o" && ! grep -q 'PRUNED.*submodules/mine' <<<"$o"; then ok "$l: recorded third-party gitlinks pruned (manifest rule M and non-own-org URL rule U), own-org gitlink not pruned"
    else bad "$l: wrong prune set (rc=$r): $(grep PRUNED <<<"$o" | tr '\n' ' ')"; fi
    if [ "$r" -ne 0 ] && grep -q 'submodules/mine/bad.py' <<<"$o" && ! grep -q 'submodules/vend/bad.py' <<<"$o" && ! grep -q 'submodules/url/bad.py' <<<"$o"; then ok "$l: only the own-org gitlink's unguarded call is reported"
    else bad "$l: findings wrong"; fi
    if grep -q 'submodules/vend/bad.py' <<<"$(gout "$g" --root "$T" --include-third-party)"; then ok "$l: --include-third-party scans them"
    else bad "$l: --include-third-party did not scan the third-party dep"; fi
    # own-org list is consumer DATA: declaring golang as own makes the URL gitlink scanned
    if grep -q 'submodules/url/bad.py' <<<"$(gout "$g" --root "$T" --own-orgs 'vasic-digital,golang')"; then ok "$l: --own-orgs makes a listed org own-org (scanned)"
    else bad "$l: --own-orgs not honoured"; fi
}
run_suite "$HERE/cm_killpg_pgid_guard.sh" real
GATE="$HERE/cm_killpg_pgid_guard.sh"

# nested (M2): own-org `a` (vasic-digital URL) nests third-party gitlink b (golang URL) and own-org c
N="$TMP/nest"; mkdir -p "$N"; mkrepo "$TMP/rn/b"; mkrepo "$TMP/rn/c"; mkrepo "$TMP/rn/a" a_clean.py
GIT -C "$N" init -q .
addsub "$TMP/rn/a" "$TMP/rn/b" submodules/b "$GO" && addsub "$TMP/rn/a" "$TMP/rn/c" submodules/c "$OWN" && commitall "$TMP/rn/a"
addsub "$N" "$TMP/rn/a" submodules/a "$OWN" && commitall "$N"
GIT -C "$N/submodules/a" clone -q "file://$TMP/rn/b" submodules/b >/dev/null 2>&1; GIT -C "$N/submodules/a" clone -q "file://$TMP/rn/c" submodules/c >/dev/null 2>&1
if pline "$GATE" "$N" 'submodules/a/submodules/b'; then ok "nested third-party gitlink (golang URL) inside an own-org submodule is pruned by recursion"; else bad "nested third-party gitlink not pruned"; fi
if grep -q 'submodules/a/submodules/c/bad.py' <<<"$(gout "$GATE" --root "$N")"; then ok "nested own-org gitlink stays scanned"; else bad "nested own-org gitlink was hidden"; fi

# P1: dir `src` whose first inner entry is a gitlink; manifest marks `src` third-party -> src/main.py must stay scanned
P1="$TMP/p1"; mkrepo "$TMP/rp1/inner" ; mkdir -p "$P1/src"; GIT -C "$P1" init -q .
manifest "$P1/helix-deps.yaml" src true; printf "$BADPY" > "$P1/src/main.py"
addsub "$P1" "$TMP/rp1/inner" src/aaa "$GO"; commitall "$P1"
if scanned "$GATE" "$P1"; then ok "P1: directory whose first inner entry is a gitlink is NOT pruned (exact match) -> FAIL on first-party call"; else bad "P1: first-party src/ hidden by a prefix-listing gitlink"; fi
# P2: gate root is a subdirectory of a repo (no .git at the root); hostile manifest there must not hide src
P2="$TMP/p2"; mkdir -p "$P2/sub/src"; GIT -C "$P2" init -q .; manifest "$P2/sub/helix-deps.yaml" src true
printf "$BADPY" > "$P2/sub/src/bad.py"; commitall "$P2"
if scanned "$GATE" "$P2/sub"; then ok "P2: subdirectory gate root with hostile manifest is still scanned"; else bad "P2: subdirectory root hid first-party code"; fi
# P2 golden-FALSE: a REAL recorded third-party gitlink under a subdirectory root is pruned, path relative to the gate root
mkrepo "$TMP/rp2/v"; P2B="$TMP/p2b"; mkdir -p "$P2B/sub"; GIT -C "$P2B" init -q .; printf "def f():\n    return 1\n" > "$P2B/sub/f.py"; addsub "$P2B" "$TMP/rp2/v" sub/submodules/v "$GO"; commitall "$P2B"
if pruned "$GATE" "$P2B/sub" 'submodules/v'; then ok "P2: real third-party gitlink under a subdirectory root pruned (root-relative)"; else bad "P2 golden-FALSE: not pruned"; fi
# P3: .gitmodules entry (and manifest) but NO gitlink -> not recorded
P3="$TMP/p3"; mkdir -p "$P3/src"; GIT -C "$P3" init -q .; manifest "$P3/helix-deps.yaml" src true
printf "$BADPY" > "$P3/src/bad.py"; printf '[submodule "src"]\n\tpath = src\n\turl = %s\n' "$GO" > "$P3/.gitmodules"; commitall "$P3"
if scanned "$GATE" "$P3"; then ok "P3: .gitmodules entry without a gitlink is not recorded -> scanned"; else bad "P3: gitmodules-only entry hid first-party code"; fi
# P4: no git metadata at all -> fail closed, manifest never prunes
P4="$TMP/p4"; mkdir -p "$P4/src"; manifest "$P4/helix-deps.yaml" src true; printf "$BADPY" > "$P4/src/bad.py"
o4="$(bash "$GATE" --root "$P4" 2>&1)"; r4=$?
if [ "$r4" -ne 0 ] && grep -q 'no usable git metadata' <<<"$o4"; then ok "P4: no git metadata -> fail closed (scanned, stated on stderr)"; else bad "P4: exported tree hid first-party code (rc=$r4)"; fi
# hostile manifest with git present and no gitlink; prefix collision
H="$TMP/hostile"; mkdir -p "$H/src"; GIT -C "$H" init -q .; manifest "$H/helix-deps.yaml" src true; printf "$BADPY" > "$H/src/bad.py"; commitall "$H"
if scanned "$GATE" "$H"; then ok "hostile manifest (path: src, not a gitlink) still scanned -> FAIL"; else bad "hostile manifest hid first-party src/"; fi
P="$TMP/pc"; mkA "$P"; mkdir -p "$P/submodules/vend-bar"; printf "$BADPY" > "$P/submodules/vend-bar/bad.py"
if grep -q 'submodules/vend-bar/bad.py' <<<"$(gout "$GATE" --root "$P")"; then ok "vend does not prune its prefix sibling vend-bar"; else bad "vend pruned vend-bar"; fi
# spaces / newline / symlink components are never pruned (dropped -> scanned)
SP="$TMP/sp"; mkrepo "$TMP/rsp/s"; mkdir -p "$SP"; GIT -C "$SP" init -q .; addsub "$SP" "$TMP/rsp/s" 'sp ace' "$GO"; commitall "$SP"
o="$(bash "$GATE" --root "$SP" 2>&1)"
if ! grep -q 'PRUNED.*sp ace' <<<"$o"; then ok "gitlink path with a space is not pruned (scan more)"; else bad "space path pruned"; fi
NL="$TMP/nl"; mkdir -p "$NL/src"; GIT -C "$NL" init -q .; printf 'schema_version: 1\ndeps:\n  - name: x\n    path: "src\\nx"\n    ssh_url: git@example.invalid:o/x.git\n    ref: abc\n    why: "x"\n    layout: grouped\n    third_party: true\n    licence: MIT\n' > "$NL/helix-deps.yaml"
printf "$BADPY" > "$NL/src/bad.py"; commitall "$NL"
if scanned "$GATE" "$NL" && ! grep -q 'PRUNED.*src' <<<"$(gout "$GATE" --root "$NL")"; then ok "newline in a manifest path is dropped, not pruned"; else bad "newline path handling wrong"; fi
SY="$TMP/sy"; mkA "$SY"; rm -rf "${SY:?}/submodules/url"; mkdir -p "$SY/realdir"; ln -s ../realdir "$SY/submodules/url"
if ! grep -q 'PRUNED.*submodules/url' <<<"$(gout "$GATE" --root "$SY")"; then ok "gitlink path replaced by a symlink is not pruned"; else bad "symlink component pruned"; fi

# --- paired mutations: each new rule, each caught ---
mutlib() { # $1=name $2=sed expr ; builds private gate+lib copy, applies expr to the lib, echoes dir
    local D="$TMP/m_$1"; mkdir -p "$D/gates" "$D/lib" "$D/deps_manifest"
    cp "$HERE/cm_killpg_pgid_guard.sh" "$D/gates/"; cp "$HERE"/../lib/*.sh "$HERE"/../lib/*.list "$D/lib/" 2>/dev/null; cp "$HERE"/../deps_manifest/*.* "$D/deps_manifest/"
    sed -i "$2" "$D/lib/third_party_prune.sh"; echo "$D"
}
chk() { # $1=name $2=sed $3=anchor-regex $4=expectation-fn args...: root, mutant must make fn FAIL
    local name="$1" expr="$2" anchor="$3" D; shift 3
    grep -q "$anchor" "$HERE/../lib/third_party_prune.sh" || { bad "mutation anchor absent: $name"; return; }
    D="$(mutlib "$name" "$expr")"
    cmp -s "$D/lib/third_party_prune.sh" "$HERE/../lib/third_party_prune.sh" && { bad "mutation did not apply: $name"; return; }
    "$@" "$D/gates/cm_killpg_pgid_guard.sh" && bad "mutant $name survived (test not load-bearing)" || ok "mutant $name caught"
}
t_p1()  { scanned "$1" "$P1"; }
t_p2()  { scanned "$1" "$P2/sub" && pruned "$1" "$P2B/sub" 'submodules/v'; }
t_p3()  { scanned "$1" "$P3"; }
t_p4()  { scanned "$1" "$P4"; }
t_hos() { scanned "$1" "$H"; }
t_url() { pruned "$1" "$TMP/f_real" 'submodules/url'; }
t_own() { grep -q 'submodules/mine/bad.py' <<<"$(gout "$1" --root "$TMP/f_real")"; }
t_nest(){ pline "$1" "$N" 'submodules/a/submodules/b'; }
chk exact   's/\[ "\$path" = "\$2" \]/true/' '\[ "\$path" = "\$2" \]' t_p1
chk rec     's/if cm_tp_gitlink_deep "\$top" .*; then tp/if true; then tp/' 'if cm_tp_gitlink_deep "\$top"' t_hos
chk toplvl  's/^    \[ "\$rootp" = "\$top" \] || prefix=.*/    prefix=""/' '\[ "\$rootp" = "\$top" \] || prefix=' t_p2
chk gitmod  's/^cm_tp_is_gitlink() {/cm_tp_is_gitlink() { grep -Fq "path = $2" "$1\/.gitmodules" 2>\/dev\/null \&\& return 0/' '^cm_tp_is_gitlink() {' t_p3
chk nogit   's/^cm_tp_is_gitlink() {/cm_tp_is_gitlink() { return 0/;s/top="\$(_cm_tp_git -C "\$rootp" rev-parse --show-toplevel 2>\/dev\/null)" || {/top="$rootp"; true || {/' 'rev-parse --show-toplevel 2>/dev/null)" || {' t_p4
chk urlrule 's/if cm_tp_url_third "\$url" "\$orgs"; then/if false; then/' 'if cm_tp_url_third "\$url"' t_url
chk ownrule 's/if cm_tp_url_third "\$url" "\$orgs"; then/if true; then/' 'if cm_tp_url_third "\$url"' t_own
chk recurse 's/cm_tp_populated "\$base\/\$rel" \&\& cm_tp_level/false \&\& cm_tp_level/' 'cm_tp_populated "\$base/\$rel" && cm_tp_level' t_nest
# no-prune mutation of the gate itself
M="$TMP/mut"; mkdir -p "$M/gates" "$M/lib" "$M/deps_manifest"
cp "$HERE/cm_killpg_pgid_guard.sh" "$M/gates/"; cp "$HERE"/../lib/*.sh "$M/lib/"; cp "$HERE"/../deps_manifest/*.* "$M/deps_manifest/"
if grep -q 'cm_third_party_prune_find_expr "\$root"' "$M/gates/cm_killpg_pgid_guard.sh"; then
    sed -i 's/cm_third_party_prune_find_expr "\$root"/:/' "$M/gates/cm_killpg_pgid_guard.sh"
    if scanned "$M/gates/cm_killpg_pgid_guard.sh" "$TMP/f_real" && ! pruned "$M/gates/cm_killpg_pgid_guard.sh" "$TMP/f_real" 'submodules/vend'; then ok "mutant (prune call removed) detected"; else bad "no-prune mutant survived"; fi
else bad "gate prune-call anchor absent"; fi
# prefix-glob mutation (collision)
LP="$TMP/mut3"; mkdir -p "$LP/gates" "$LP/lib" "$LP/deps_manifest"
cp "$HERE/cm_killpg_pgid_guard.sh" "$LP/gates/"; cp "$HERE"/../lib/*.sh "$LP/lib/"; cp "$HERE"/../deps_manifest/*.* "$LP/deps_manifest/"
sed -i 's#")/\*" -o)#")*" -o)#' "$LP/lib/third_party_prune.sh"
if grep -q '")\*" -o)' "$LP/lib/third_party_prune.sh"; then
    if grep -q 'submodules/vend-bar/bad.py' <<<"$(gout "$LP/gates/cm_killpg_pgid_guard.sh" --root "$P")"; then bad "prefix-glob mutant not detected"; else ok "mutant prefix-glob prunes vend-bar: collision test is load-bearing"; fi
else bad "prefix mutation anchor absent"; fi

# --- round 2b: braced shell kill target `-${pg}` is the same target as `-$pg` (was a false positive) ---
BR="$TMP/braced"; mkdir -p "$BR"
printf 'if [ "${pg}" -gt 1 ]; then\n  kill -INT -- "-${pg}"\nfi\n' > "$BR/ok.sh"
printf 'kill -INT -- "-${pg}"\n' > "$BR/bad.sh"
printf 'if [ "%spg" -gt 1 ]; then\n  kill -INT -- "-%spg:-1}"\nfi\n' '$' '${' > "$BR/dflt.sh"   # %s keeps the fixture text out of the env-read census
G="$HERE/cm_killpg_pgid_guard.sh"
if bash "$G" --root "$BR/ok.sh" --quiet >/dev/null 2>&1; then ok "guarded braced does not fire (golden-FALSE)"; else bad "guarded braced false positive"; fi
if bash "$G" --root "$BR/bad.sh" --quiet >/dev/null 2>&1; then bad "unguarded braced passed"; else ok "unguarded braced FAILs"; fi
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
