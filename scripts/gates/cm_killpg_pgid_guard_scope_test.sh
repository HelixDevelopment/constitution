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
TMP="$(cd "$TMP" && pwd -P)"   # absolute: a relative TMPDIR made every file:// submodule add fail (review F9)
trap 'rm -rf "${TMP:?}"' EXIT
rc=0
ok()  { echo "OK:   $1"; }
bad() { echo "FAIL: $1"; rc=1; }

BADPY='import os, signal\ndef k(pg):\n    os.killpg(pg, signal.SIGKILL)\n'
GIT() { env GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t \
    git -c protocol.file.allow=always -c core.hooksPath=/dev/null -c init.defaultBranch=main "$@"; }
mkrepo() { # $1=dir [$2=file to hold a bad call, default bad.py] : real repo with one commit; a build failure is a hard FAIL (F9)
    mkdir -p "$1"; GIT -C "$1" init -q . || { bad "fixture: git init failed ($1)"; return 1; }
    printf "$BADPY" > "$1/${2:-bad.py}"; GIT -C "$1" add -A >/dev/null; GIT -C "$1" commit -q -m i || { bad "fixture: commit failed ($1)"; return 1; }
}
addsub() { # $1=parent repo $2=remote repo $3=path $4=.gitmodules URL
    GIT -C "$1" submodule add -q "file://$2" "$3" >/dev/null 2>&1 || { bad "fixture: submodule add failed ($3)"; return 1; }
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
DECL=(--own-orgs vasic-digital)   # the explicit own-org DECLARATION (rule U is inert without one, review F1)
pruned()  { local o; o="$(bash "$1" --root "$2" "${DECL[@]}" 2>&1)"; [ $? -eq 0 ] && grep -q "PRUNED.*$3" <<<"$o" && ! grep -q 'SKIP' <<<"$o"; }
pline()   { grep -q "PRUNED.*$3" <<<"$(gout "$1" --root "$2" "${DECL[@]}")"; }
scanned() { ! bash "$1" --root "$2" "${DECL[@]}" >/dev/null 2>&1; }
mprune()  { grep -q "PRUNED.*$3" <<<"$(gout "$1" --root "$2")"; }   # manifest-rule view: NO declaration

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
    local o; o="$(bash "$g" --root "$T" "${DECL[@]}" 2>&1)"; local r=$?
    if grep -q 'PRUNED.*submodules/vend' <<<"$o" && grep -q 'PRUNED.*submodules/url' <<<"$o" && ! grep -q 'PRUNED.*submodules/mine' <<<"$o"; then ok "$l: recorded third-party gitlinks pruned (manifest rule M and non-own-org URL rule U), own-org gitlink not pruned"
    else bad "$l: wrong prune set (rc=$r): $(grep PRUNED <<<"$o" | tr '\n' ' ')"; fi
    if [ "$r" -ne 0 ] && grep -q 'submodules/mine/bad.py' <<<"$o" && ! grep -q 'submodules/vend/bad.py' <<<"$o" && ! grep -q 'submodules/url/bad.py' <<<"$o"; then ok "$l: only the own-org gitlink's unguarded call is reported"
    else bad "$l: findings wrong"; fi
    # F1: with NO declaration the URL rule is off: the golang-URL gitlink stays scanned, the manifest-marked one is pruned (M alone)
    o="$(bash "$g" --root "$T" 2>&1)"
    if grep -q 'PRUNED.*submodules/vend' <<<"$o" && ! grep -q 'PRUNED.*submodules/url' <<<"$o" && grep -q 'submodules/url/bad.py' <<<"$o"; then ok "$l: NO declaration => only the manifest rule prunes (URL-third gitlink stays scanned)"
    else bad "$l: undeclared run pruned by URL: $(grep PRUNED <<<"$o" | tr '\n' ' ')"; fi
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
t_own() { grep -q 'submodules/mine/bad.py' <<<"$(gout "$1" --root "$TMP/f_real" "${DECL[@]}")"; }
t_nest(){ pline "$1" "$N" 'submodules/a/submodules/b'; }
chk exact   's/\[ "\$path" = "\$2" \]/true/' '\[ "\$path" = "\$2" \]' t_p1
chk rec     's/if cm_tp_gitlink_deep "\$top" .*; then tp/if true; then tp/' 'if cm_tp_gitlink_deep "\$top"' t_hos
chk toplvl  's/^    \[ "\$rootp" = "\$top" \] || prefix=.*/    prefix=""/' '\[ "\$rootp" = "\$top" \] || prefix=' t_p2
chk gitmod  's/^cm_tp_is_gitlink() {/cm_tp_is_gitlink() { grep -Fq "path = $2" "$1\/.gitmodules" 2>\/dev\/null \&\& return 0/' '^cm_tp_is_gitlink() {' t_p3
chk nogit   's/^cm_tp_is_gitlink() {/cm_tp_is_gitlink() { return 0/;s/top="\$(_cm_tp_git -C "\$rootp" rev-parse --show-toplevel 2>\/dev\/null)" || {/top="$rootp"; true || {/' 'rev-parse --show-toplevel 2>/dev/null)" || {' t_p4
chk urlrule 's/cm_tp_url_third "\$url" "\$orgs"; then/false; then/' 'cm_tp_url_third "\$url" "\$orgs"; then' t_url
chk ownrule 's/cm_tp_url_third "\$url" "\$orgs"; then/true; then/' 'cm_tp_url_third "\$url" "\$orgs"; then' t_own
chk recurse 's/cm_tp_populated "\$base\/\$rel" \&\& cm_tp_level/false \&\& cm_tp_level/' 'cm_tp_populated "\$base/\$rel" && cm_tp_level' t_nest

# ── round 4 fixtures (review 11.4.276 r3 findings F1..F11) ──────────────────────────────────────────────
# F1: a consumer whose own repositories live under a NON-default organisation, with NO declaration: nothing pruned by URL
CS="$TMP/consumer"; mkrepo "$TMP/rcs/a"; mkrepo "$TMP/rcs/b"; mkdir -p "$CS"; GIT -C "$CS" init -q .
addsub "$CS" "$TMP/rcs/a" submodules/mine 'git@github.com:milos85vasic/OOM-Protect.git' && addsub "$CS" "$TMP/rcs/b" submodules/theirs 'https://github.com/acme/other.git' && commitall "$CS"
oc="$(bash "$GATE" --root "$CS" 2>&1)"
if ! grep -q 'PRUNED.*submodules/' <<<"$oc" && grep -q 'submodules/mine/bad.py' <<<"$oc" && grep -q 'submodules/theirs/bad.py' <<<"$oc"; then ok "F1: consumer-shaped tree, no declaration -> nothing pruned by URL (both scanned)"; else bad "F1: undeclared consumer had submodules pruned: $(grep PRUNED <<<"$oc" | tr '\n' ' ')"; fi
oc="$(bash "$GATE" --root "$CS" --own-orgs milos85vasic 2>&1)"
if grep -q 'PRUNED.*submodules/theirs' <<<"$oc" && ! grep -q 'PRUNED.*submodules/mine' <<<"$oc"; then ok "F1: with a declaration the URL rule applies (acme pruned, own org scanned)"; else bad "F1: declared run wrong: $(grep PRUNED <<<"$oc" | tr '\n' ' ')"; fi
mkdir -p "$CS/config"; printf '# declared\nmilos85vasic\n' > "$CS/config/own_orgs.list"
oc="$(bash "$GATE" --root "$CS" 2>&1)"
if grep -q 'PRUNED.*submodules/theirs' <<<"$oc" && ! grep -q 'PRUNED.*submodules/mine' <<<"$oc"; then ok "F1: config/own_orgs.list is read as the declaration"; else bad "F1: declaration file not honoured: $(grep PRUNED <<<"$oc" | tr '\n' ' ')"; fi
t_f2m() { timeout 20 bash "$1" --root "$CS" --own-orgs 'a;b' >/dev/null 2>&1; [ $? -eq 2 ]; }
t_f1() { ! grep -q 'PRUNED.*submodules/' <<<"$(gout "$1" --root "$TMP/consumer_nodecl")"; }
mkdir -p "$TMP/consumer_nodecl"; GIT -C "$TMP/consumer_nodecl" init -q .; addsub "$TMP/consumer_nodecl" "$TMP/rcs/b" submodules/theirs 'https://github.com/acme/other.git'; commitall "$TMP/consumer_nodecl"

# F2: every malformed declaration refuses (exit 2) -- flag, guarded env, file
for v in '' ' ' ',' ';' 'vasic-digital;HelixDevelopment' 'vasic digital' 'a,,b' 'a,' ',a' 'a b' 'ev"il' '$x'; do
    o="$(timeout 20 bash "$GATE" --root "$CS" --own-orgs "$v" 2>&1)"; r=$?
    if [ "$r" -eq 2 ] && grep -qi 'malformed' <<<"$o"; then ok "F2: --own-orgs '$v' refused (exit 2)"; else bad "F2: --own-orgs '$v' not refused (rc=$r)"; fi
done
for v in ' ' ',' 'a;b' 'a b'; do
    o="$(env HELIX_TEST_MODE=1 HELIX_OWN_ORGS="$v" timeout 20 bash "$GATE" --root "$CS" 2>&1)"; r=$?
    if [ "$r" -eq 2 ]; then ok "F2: HELIX_OWN_ORGS '$v' refused (exit 2)"; else bad "F2: HELIX_OWN_ORGS '$v' not refused (rc=$r)"; fi
done
FB="$TMP/f2file"; mkdir -p "$FB/config"; cp -a "$CS/.git" "$FB/.git" 2>/dev/null
for v in '' '   ' '# only a comment' 'a b' 'x;y'; do
    printf '%s\n' "$v" > "$FB/config/own_orgs.list"
    o="$(timeout 20 bash "$GATE" --root "$FB" 2>&1)"; r=$?
    if [ "$r" -eq 2 ]; then ok "F2: own_orgs.list content '$v' refused (exit 2)"; else bad "F2: own_orgs.list '$v' not refused (rc=$r)"; fi
done
# golden-FALSE: a valid declaration (mixed case, several orgs) is accepted
if timeout 20 bash "$GATE" --root "$CS" --own-orgs 'Milos85Vasic,acme' >/dev/null 2>&1 || [ $? -eq 1 ]; then ok "F2 golden-FALSE: valid declaration accepted"; else bad "F2 golden-FALSE: valid declaration refused"; fi

# F3: unparseable / non-network URLs are never third-party (scanned), with a declaration active
U3="$TMP/u3"; mkdir -p "$U3"; GIT -C "$U3" init -q .
i=0; for url in 'file:///tmp/x/vasic.git' 'C:/repos/x.git' 'https://github.com/vasic-digital%2fx/y.git' '../sibling.git' './here.git' 'weird' 'git@c:acme/x.git' 'ftp://h/acme/x.git'; do
    i=$((i+1)); mkrepo "$TMP/ru3/r$i" && addsub "$U3" "$TMP/ru3/r$i" "submodules/u$i" "$url"
done; commitall "$U3"
o3="$(bash "$GATE" --root "$U3" "${DECL[@]}" 2>&1)"
if ! grep -q 'PRUNED.*submodules/' <<<"$o3"; then ok "F3: file://, C:/, %-encoded, relative, unparseable, 1-char host, ftp URLs are never pruned"; else bad "F3: pruned by an unsafe URL: $(grep PRUNED <<<"$o3" | tr '\n' ' ')"; fi
t_f3() { ! grep -q 'PRUNED.*submodules/' <<<"$(gout "$1" --root "$U3" "${DECL[@]}")"; }

# F4: a URL-third gitlink whose directory is a PLAIN directory with code (not a repository): scanned
F4="$TMP/f4"; mkrepo "$TMP/rf4/r"; mkdir -p "$F4"; GIT -C "$F4" init -q .; addsub "$F4" "$TMP/rf4/r" submodules/plain "$GO"; commitall "$F4"
GIT -C "$F4" submodule deinit -f submodules/plain >/dev/null 2>&1; rm -rf "${F4:?}/submodules/plain"; mkdir -p "$F4/submodules/plain"; printf "$BADPY" > "$F4/submodules/plain/bad.py"
if scanned "$GATE" "$F4" && ! pline "$GATE" "$F4" 'submodules/plain'; then ok "F4: URL rule does not prune a plain (non-repository) directory holding code"; else bad "F4: plain directory hidden by the URL rule"; fi
t_f4() { scanned "$1" "$F4"; }
# F4 golden-FALSE: a populated gitlink with the same URL is pruned; an EMPTY (uninitialised) one too
if pruned "$GATE" "$P2B/sub" 'submodules/v'; then ok "F4 golden-FALSE: populated third-party gitlink still pruned"; else bad "F4 golden-FALSE: populated gitlink not pruned"; fi

# F5: a value option as the LAST argument exits 2 promptly, never loops (all three gates)
for g in cm_killpg_pgid_guard cm_dangerous_combination_fail_closed cm_oracle_strategy_named_and_independent; do
    for opt in --root --own-orgs --window --max-depth --glob --baseline --base; do
        grep -q -- "$opt)" "$HERE/$g.sh" || continue
        timeout 10 bash "$HERE/$g.sh" "$opt" >/dev/null 2>&1; r=$?
        if [ "$r" -eq 2 ]; then ok "F5: $g $opt without a value -> exit 2"; else bad "F5: $g $opt without a value -> rc=$r (hang/accept)"; fi
    done
done
t_f5() { timeout 10 bash "$1" --own-orgs >/dev/null 2>&1; [ $? -eq 2 ]; }

# F11: ambiguous .gitmodules (duplicate path, multi-valued url) is scanned
A1="$TMP/amb1"; mkrepo "$TMP/ramb/r"; mkdir -p "$A1"; GIT -C "$A1" init -q .; addsub "$A1" "$TMP/ramb/r" submodules/x "$GO"; commitall "$A1"
printf '[submodule "dup"]\n\tpath = submodules/x\n\turl = %s\n' "$GO" >> "$A1/.gitmodules"
if scanned "$GATE" "$A1" && ! pline "$GATE" "$A1" 'submodules/x'; then ok "F11: duplicate .gitmodules path -> ambiguous -> scanned"; else bad "F11: duplicate-path ambiguity pruned"; fi
A2="$TMP/amb2"; mkdir -p "$A2"; GIT -C "$A2" init -q .; addsub "$A2" "$TMP/ramb/r" submodules/x "$GO"; commitall "$A2"
GIT -C "$A2" config -f .gitmodules --add submodule.submodules/x.url "$GO"
if scanned "$GATE" "$A2" && ! pline "$GATE" "$A2" 'submodules/x'; then ok "F11: multi-valued url -> ambiguous -> scanned"; else bad "F11: multi-valued url pruned"; fi
t_f11() { scanned "$1" "$A1" && scanned "$1" "$A2"; }

# F6 / Q4: own-org URL + manifest mark: only rule M can prune it
Q4="$TMP/q4"; mkrepo "$TMP/rq4/r"; mkdir -p "$Q4"; GIT -C "$Q4" init -q .; manifest "$Q4/helix-deps.yaml" submodules/q true; addsub "$Q4" "$TMP/rq4/r" submodules/q "$OWN"; commitall "$Q4"
if pline "$GATE" "$Q4" 'submodules/q'; then ok "F6/Q4: own-org URL + manifest mark -> pruned by the manifest rule alone"; else bad "F6/Q4: manifest rule did not prune"; fi
t_q4() { pline "$1" "$Q4" 'submodules/q'; }
# F7 / Q1: typechange -- the INDEX records a regular file at src, the worktree has a directory src/ holding code; manifest marks src
Q1="$TMP/q1"; mkdir -p "$Q1"; GIT -C "$Q1" init -q .; manifest "$Q1/helix-deps.yaml" src true; printf 'x\n' > "$Q1/src"; GIT -C "$Q1" add -A >/dev/null; GIT -C "$Q1" commit -q -m c
rm -f "${Q1:?}/src"; mkdir -p "$Q1/src"; printf "$BADPY" > "$Q1/src/main.py"
if scanned "$GATE" "$Q1"; then ok "F7/Q1: typechange (index blob, worktree dir) is not a gitlink -> scanned -> FAIL"; else bad "F7/Q1: typechange hid first-party code"; fi
t_q1() { scanned "$1" "$Q1"; }
# F8 / qcase: uppercase organisation in the URL is the same organisation
QC="$TMP/qcase"; mkrepo "$TMP/rqc/r"; mkdir -p "$QC"; GIT -C "$QC" init -q .; addsub "$QC" "$TMP/rqc/r" submodules/c 'git@github.com:Vasic-Digital/c.git'; commitall "$QC"
if scanned "$GATE" "$QC" && ! pline "$GATE" "$QC" 'submodules/c'; then ok "F8: URL org case-folded (Vasic-Digital == vasic-digital) -> own-org -> scanned"; else bad "F8: case-different own-org URL pruned"; fi
t_qc() { scanned "$1" "$QC"; }

mutg() { # $1=name $2=sed expr on the GATE copy: echoes the mutated gate path
    local D="$TMP/mg_$1"; mkdir -p "$D/gates" "$D/lib" "$D/deps_manifest"
    cp "$HERE/cm_killpg_pgid_guard.sh" "$D/gates/"; cp "$HERE"/../lib/*.sh "$HERE"/../lib/*.list "$D/lib/" 2>/dev/null; cp "$HERE"/../deps_manifest/*.* "$D/deps_manifest/"
    sed -i "$2" "$D/gates/cm_killpg_pgid_guard.sh"; echo "$D/gates/cm_killpg_pgid_guard.sh"
}
# round-4 mutants (reviewer: M_off, nolower, typechange/modecheck, shift; author: the rest)
chk m_off     's/then tp\["\$pp"\]=1/then :/' 'then tp\["\$pp"\]=1' t_q4
chk nolower   's/local u="\${1,,}" orgs="\${2,,}" o/local u="$1" orgs="$2" o/' 'local u="\${1,,}" orgs="\${2,,}" o' t_qc
chk modecheck 's/\[ "\$mode" = 160000 \] \&\& //' '\[ "\$mode" = 160000 \] \&\& ' t_q1
chk default   's/^cm_tp_orgs_resolve() {/cm_tp_orgs_resolve() { printf "vasic-digital,HelixDevelopment\\n"; return 0/' '^cm_tp_orgs_resolve() {' t_f1
chk normall   's/\[\[ "\$o" =~ \^\[A-Za-z0-9._-\]+\$ \]\] || return 2/:/' '\[\[ "\$o" =~ \^\[A-Za-z0-9._-\]+\$ \]\] || return 2' t_f2m
chk fileurl   's/(https?|ssh|git):\/\//(https?|ssh|git|file):\/\//;s/\*%\*|//' 'ssh|git):' t_f3
chk popul     's/^cm_tp_prunable_dir() {/cm_tp_prunable_dir() { return 0/' '^cm_tp_prunable_dir() {' t_f4
chk ambig     's/ \&\& \[ -z "\${amb\[\$g\]:-}" \]//;s/\[ "\$nurl" = 1 \] \&\& //' 'amb\[\$g\]' t_f11
SH="$(mutg shift 's/--own-orgs) \[ \$# -ge 2 \] || { echo "\${GATE}: --own-orgs requires a value" >\&2; exit 2; }; /--own-orgs) /')"
if grep -q 'own-orgs requires' "$SH"; then bad "shift mutant did not apply"; elif t_f5 "$SH"; then bad "mutant shift survived (--own-orgs last arg not detected)"; else ok "mutant shift caught (--own-orgs as last argument)"; fi

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
