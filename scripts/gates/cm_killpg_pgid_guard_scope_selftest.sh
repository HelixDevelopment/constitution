#!/usr/bin/env bash
# cm_killpg_pgid_guard_scope_selftest.sh — test + paired mutation for the scan SCOPE of
# CM-KILLPG-PGID-GUARD (§11.4.263). Round 5 (review 11.4.276, structural replacement): the ONLY prune rule
# (scripts/lib/third_party_prune.sh) is "an exact, unambiguous RECORDED gitlink that the INDEX copy of a tracked
# helix-deps.yaml marks third_party: true" (custody = the index entry: worktree bytes whose hash equals the stage-0
# mode-100644 index sha; the object store is never read; any byte / mode / type difference is refused; git runs
# under env -i). No URL / own-org rule exists: every unmarked submodule is scanned,
# whatever organisation its URL names and whatever declaration files a repository carries.
# --include-third-party opts back in.
# Usage: cm_killpg_pgid_guard_scope_selftest.sh   Exit 0 all hold, 1 otherwise.
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
pruned()  { local o; o="$(bash "$1" --root "$2" 2>&1)"; [ $? -eq 0 ] && grep -q "PRUNED.*$3" <<<"$o" && ! grep -q 'SKIP' <<<"$o"; }
pline()   { grep -q "PRUNED.*$3" <<<"$(gout "$1" --root "$2")"; }
scanned() { bash "$1" --root "$2" >/dev/null 2>&1; [ $? -eq 1 ]; }   # rc 1 = scanned and the unguarded call FOUND
noprune() { ! grep -q 'PRUNED.*submodules/' <<<"$(gout "$1" --root "$2" "${@:3}")"; }
manifest2() { # $1=file then pairs of <dep path> <third_party>
    local f="$1"; shift; printf 'schema_version: 1\ndeps:\n' > "$f"
    while [ $# -ge 2 ]; do printf '  - name: %s\n    path: %s\n    ssh_url: git@example.invalid:o/x.git\n    ref: abc\n    why: "x"\n    layout: grouped\n    third_party: %s\n    licence: MIT\n' "$(basename "$1")" "$1" "$2" >> "$f"; shift 2; done
}

# fixture A: manifest-marked third-party gitlink `vend` (pruned) + own gitlink `mine` + golang-URL gitlink `url`
# (no mark: SCANNED -- a URL never prunes)
mkA() { # $1=dir
    local R="$TMP/rem_$(basename "$1")"; mkrepo "$R/vend" && mkrepo "$R/mine" && mkrepo "$R/url" || return 1
    mkdir -p "$1"; GIT -C "$1" init -q . ; manifest "$1/helix-deps.yaml" submodules/vend true
    addsub "$1" "$R/vend" submodules/vend 'file:///x/vend.git' && addsub "$1" "$R/mine" submodules/mine "$OWN" && addsub "$1" "$R/url" submodules/url "$GO" || return 1
    commitall "$1"
}
run_suite() { # $1=gate $2=label
    local g="$1" l="$2" T="$TMP/f_$2"
    mkA "$T" || { bad "$l: fixture A could not be built"; return; }
    local o; o="$(bash "$g" --root "$T" 2>&1)"; local r=$?
    if grep -q 'PRUNED.*submodules/vend' <<<"$o" && ! grep -q 'PRUNED.*submodules/url' <<<"$o" && ! grep -q 'PRUNED.*submodules/mine' <<<"$o"; then ok "$l: only the manifest-marked recorded gitlink is pruned (golang-URL and own gitlinks are not)"
    else bad "$l: wrong prune set (rc=$r): $(grep PRUNED <<<"$o" | tr '\n' ' ')"; fi
    if [ "$r" -eq 1 ] && grep -q 'submodules/mine/bad.py' <<<"$o" && grep -q 'submodules/url/bad.py' <<<"$o" && ! grep -q 'submodules/vend/bad.py' <<<"$o"; then ok "$l: unmarked gitlinks' unguarded calls are reported, the marked one's is not"
    else bad "$l: findings wrong (rc=$r)"; fi
    if grep -q 'submodules/vend/bad.py' <<<"$(gout "$g" --root "$T" --include-third-party)"; then ok "$l: --include-third-party scans the marked gitlink"
    else bad "$l: --include-third-party did not scan the third-party dep"; fi
}
run_suite "$HERE/cm_killpg_pgid_guard.sh" real
GATE="$HERE/cm_killpg_pgid_guard.sh"

# nested: own `a` nests b (golang URL) and c. Three ways to look at b:
#   N0 no mark anywhere -> b scanned;  N1 a's OWN tracked manifest marks b -> pruned;
#   N2 the ROOT manifest names submodules/a/submodules/b (the constitution's claude_toolkit/go shape) -> pruned
mkrepo "$TMP/rn/b"; mkrepo "$TMP/rn/c"; mkrepo "$TMP/rn/a" a_clean.py
addsub "$TMP/rn/a" "$TMP/rn/b" submodules/b "$GO" && addsub "$TMP/rn/a" "$TMP/rn/c" submodules/c "$OWN" && commitall "$TMP/rn/a"
mkrepo "$TMP/rn/a1" a_clean.py; addsub "$TMP/rn/a1" "$TMP/rn/b" submodules/b "$GO" && addsub "$TMP/rn/a1" "$TMP/rn/c" submodules/c "$OWN"
manifest "$TMP/rn/a1/helix-deps.yaml" submodules/b true; commitall "$TMP/rn/a1"
mknest() { # $1=dir $2=remote a $3=root-manifest-path-or-empty
    mkdir -p "$1"; GIT -C "$1" init -q .
    [ -n "$3" ] && manifest "$1/helix-deps.yaml" "$3" true
    addsub "$1" "$2" submodules/a "$OWN" && commitall "$1" || return 1
    # populate the nested gitlinks from the local remotes (never the recorded network URLs)
    GIT -C "$1/submodules/a" clone -q "file://$TMP/rn/b" submodules/b >/dev/null 2>&1 && GIT -C "$1/submodules/a" clone -q "file://$TMP/rn/c" submodules/c >/dev/null 2>&1 || { bad "fixture: nested populate failed ($1)"; return 1; }
}
N0="$TMP/nest0"; mknest "$N0" "$TMP/rn/a" ''
N1="$TMP/nest1"; mknest "$N1" "$TMP/rn/a1" ''
N2="$TMP/nest2"; mknest "$N2" "$TMP/rn/a" submodules/a/submodules/b
[ -e "$N2/submodules/a/submodules/b/bad.py" ] && ok "nested fixture is populated (real nested submodules)" || bad "nested fixture not populated"
if noprune "$GATE" "$N0" && grep -q 'submodules/a/submodules/b/bad.py' <<<"$(gout "$GATE" --root "$N0")"; then ok "N0: nested golang-URL gitlink with NO mark is scanned"; else bad "N0: unmarked nested gitlink pruned or not scanned"; fi
if pline "$GATE" "$N1" 'submodules/a/submodules/b'; then ok "N1: nested gitlink marked by its own repository's tracked manifest is pruned"; else bad "N1: nested own-manifest mark not honoured"; fi
if pline "$GATE" "$N2" 'submodules/a/submodules/b'; then ok "N2: root manifest naming a nested path (submodules/a/submodules/b) prunes it"; else bad "N2: root manifest nested path not honoured"; fi
for n in "$N0" "$N1" "$N2"; do
    if grep -q 'submodules/a/submodules/c/bad.py' <<<"$(gout "$GATE" --root "$n")"; then ok "nested unmarked gitlink c stays scanned ($(basename "$n"))"; else bad "nested gitlink c hidden ($(basename "$n"))"; fi
done
# N3: the root manifest names a nested path whose PARENT is not populated -> cannot be resolved -> scanned
N3="$TMP/nest3"; mkdir -p "$N3"; GIT -C "$N3" init -q .; manifest "$N3/helix-deps.yaml" submodules/a/submodules/b true
addsub "$N3" "$TMP/rn/a" submodules/a "$OWN" && commitall "$N3"; rm -rf "${N3:?}/submodules/a"; mkdir -p "$N3/submodules/a/submodules/b"; printf "$BADPY" > "$N3/submodules/a/submodules/b/bad.py"
if scanned "$GATE" "$N3" && ! pline "$GATE" "$N3" 'submodules/a/submodules/b'; then ok "N3: nested path under an unpopulated parent is not pruned (plain dir scanned)"; else bad "N3: nested path pruned through an unpopulated parent"; fi
# N4: root manifest names a nested path that is NOT a gitlink of the populated parent -> scanned
N4="$TMP/nest4"; mknest "$N4" "$TMP/rn/a" submodules/a/a_clean.py
if ! pline "$GATE" "$N4" 'submodules/a/a_clean'; then ok "N4: nested manifest path that is a plain file of the parent is not pruned"; else bad "N4: non-gitlink nested path pruned"; fi

# P1: dir `src` whose first inner entry is a gitlink; manifest marks `src` third-party -> src/main.py must stay scanned
P1="$TMP/p1"; mkrepo "$TMP/rp1/inner" ; mkdir -p "$P1/src"; GIT -C "$P1" init -q .
manifest "$P1/helix-deps.yaml" src true; printf "$BADPY" > "$P1/src/main.py"
addsub "$P1" "$TMP/rp1/inner" src/aaa "$GO"; commitall "$P1"
if scanned "$GATE" "$P1"; then ok "P1: directory whose first inner entry is a gitlink is NOT pruned (exact match) -> FAIL on first-party call"; else bad "P1: first-party src/ hidden by a prefix-listing gitlink"; fi
# P2: gate root is a subdirectory of a repo (no .git at the root); hostile manifest there must not hide src
P2="$TMP/p2"; mkdir -p "$P2/sub/src"; GIT -C "$P2" init -q .; manifest "$P2/sub/helix-deps.yaml" src true
printf "$BADPY" > "$P2/sub/src/bad.py"; commitall "$P2"
if scanned "$GATE" "$P2/sub"; then ok "P2: subdirectory gate root with hostile manifest is still scanned"; else bad "P2: subdirectory root hid first-party code"; fi
# P2 golden-FALSE: a REAL recorded, manifest-marked gitlink under a subdirectory root is pruned, path relative to the gate root
mkrepo "$TMP/rp2/v"; P2B="$TMP/p2b"; mkdir -p "$P2B/sub"; GIT -C "$P2B" init -q .; printf "def f():\n    return 1\n" > "$P2B/sub/f.py"
manifest "$P2B/sub/helix-deps.yaml" submodules/v true; addsub "$P2B" "$TMP/rp2/v" sub/submodules/v "$GO"; commitall "$P2B"
if pruned "$GATE" "$P2B/sub" 'submodules/v'; then ok "P2: real marked gitlink under a subdirectory root pruned (root-relative)"; else bad "P2 golden-FALSE: not pruned"; fi
# P3: .gitmodules entry (and manifest) but NO gitlink -> not recorded
P3="$TMP/p3"; mkdir -p "$P3/src"; GIT -C "$P3" init -q .; manifest "$P3/helix-deps.yaml" src true
printf "$BADPY" > "$P3/src/bad.py"; printf '[submodule "src"]\n\tpath = src\n\turl = %s\n' "$GO" > "$P3/.gitmodules"; commitall "$P3"
if scanned "$GATE" "$P3"; then ok "P3: .gitmodules entry without a gitlink is not recorded -> scanned"; else bad "P3: gitmodules-only entry hid first-party code"; fi
# P4: no git metadata at all -> fail closed, manifest never prunes
P4="$TMP/p4"; mkdir -p "$P4/src"; manifest "$P4/helix-deps.yaml" src true; printf "$BADPY" > "$P4/src/bad.py"
o4="$(bash "$GATE" --root "$P4" 2>&1)"; r4=$?
if [ "$r4" -eq 1 ] && grep -q 'no usable git metadata' <<<"$o4"; then ok "P4: no git metadata -> fail closed (scanned, stated on stderr)"; else bad "P4: exported tree hid first-party code (rc=$r4)"; fi
# hostile manifest with git present and no gitlink; prefix collision
H="$TMP/hostile"; mkdir -p "$H/src"; GIT -C "$H" init -q .; manifest "$H/helix-deps.yaml" src true; printf "$BADPY" > "$H/src/bad.py"; commitall "$H"
if scanned "$GATE" "$H"; then ok "hostile manifest (path: src, not a gitlink) still scanned -> FAIL"; else bad "hostile manifest hid first-party src/"; fi
P="$TMP/pc"; mkA "$P"; mkdir -p "$P/submodules/vend-bar"; printf "$BADPY" > "$P/submodules/vend-bar/bad.py"
if grep -q 'submodules/vend-bar/bad.py' <<<"$(gout "$GATE" --root "$P")"; then ok "vend does not prune its prefix sibling vend-bar"; else bad "vend pruned vend-bar"; fi
# spaces / newline / symlink components are never pruned (dropped -> scanned)
SP="$TMP/sp"; mkrepo "$TMP/rsp/s"; mkdir -p "$SP"; GIT -C "$SP" init -q .; manifest2 "$SP/helix-deps.yaml" 'sp ace' true; addsub "$SP" "$TMP/rsp/s" 'sp ace' "$GO"; commitall "$SP"
o="$(bash "$GATE" --root "$SP" 2>&1)"
if ! grep -q 'PRUNED.*sp ace' <<<"$o" && grep -q 'sp ace/bad.py' <<<"$o"; then ok "marked gitlink path with a space is not pruned (scan more)"; else bad "space path pruned"; fi
NL="$TMP/nl"; mkdir -p "$NL/src"; GIT -C "$NL" init -q .; printf 'schema_version: 1\ndeps:\n  - name: x\n    path: "src\\nx"\n    ssh_url: git@example.invalid:o/x.git\n    ref: abc\n    why: "x"\n    layout: grouped\n    third_party: true\n    licence: MIT\n' > "$NL/helix-deps.yaml"
printf "$BADPY" > "$NL/src/bad.py"; commitall "$NL"
if scanned "$GATE" "$NL" && ! grep -q 'PRUNED.*src' <<<"$(gout "$GATE" --root "$NL")"; then ok "newline in a manifest path is dropped, not pruned"; else bad "newline path handling wrong"; fi
SY="$TMP/sy"; mkA "$SY"; rm -rf "${SY:?}/submodules/vend"; mkdir -p "$SY/realdir"; printf "$BADPY" > "$SY/realdir/bad.py"; ln -s ../realdir "$SY/submodules/vend"
if ! grep -q 'PRUNED.*submodules/vend' <<<"$(gout "$GATE" --root "$SY")"; then ok "marked gitlink path replaced by a symlink is not pruned"; else bad "symlink component pruned"; fi

# ── round 5: the removed own-org/URL rule stays removed ───────────────────────────────────────────────────
# (a) consumer-shaped tree: own repositories under several organisations, NO manifest mark -> nothing pruned, all scanned
CS="$TMP/consumer"; mkdir -p "$CS"; GIT -C "$CS" init -q .; i=0
for u in 'git@github.com:milos85vasic/OOM-Protect.git' 'https://github.com/acme/other.git' "$GO" "$OWN" 'git@gitlab.com:HelixDevelopment/sub/x.git'; do
    i=$((i+1)); mkrepo "$TMP/rcs/r$i" && addsub "$CS" "$TMP/rcs/r$i" "submodules/s$i" "$u"
done; commitall "$CS"
oc="$(bash "$GATE" --root "$CS" 2>&1)"; rcs=$?
if [ "$rcs" -eq 1 ] && ! grep -q 'PRUNED.*submodules/' <<<"$oc" && [ "$(grep -c 'submodules/s[1-5]/bad.py' <<<"$oc")" -ge 5 ]; then ok "R5(a): consumer tree, repos under 5 orgs, no mark -> nothing pruned, all 5 reported (rc 1)"; else bad "R5(a): consumer tree pruned/not scanned (rc=$rcs): $(grep PRUNED <<<"$oc" | tr '\n' ' ')"; fi
t_r5a() { noprune "$1" "$CS"; }
# (b) declaration-looking tricks: a TRACKED config/own_orgs.list, an untracked/ignored/symlinked one, .gitmodules extra keys,
#     HELIX_OWN_ORGS (with and without test mode): none of them is read, nothing pruned
TR="$TMP/tricks"; mkdir -p "$TR/config" "$TMP/elsewhere"; GIT -C "$TR" init -q .
mkrepo "$TMP/rtr/a" && addsub "$TR" "$TMP/rtr/a" submodules/a 'git@github.com:milos85vasic/OOM-Protect.git'
GIT -C "$TR" config -f .gitmodules submodule.submodules/a.thirdparty true; GIT -C "$TR" config -f .gitmodules submodule.submodules/a.ownorg false
printf 'bogus-org\nvasic-digital\n' > "$TR/config/own_orgs.list"; commitall "$TR"
trick() { # $1=label then env assignments
    local l="$1"; shift; local o r; o="$(env "$@" bash "$GATE" --root "$TR" 2>&1)"; r=$?
    if [ "$r" -eq 1 ] && ! grep -q 'PRUNED.*submodules/' <<<"$o" && grep -q 'submodules/a/bad.py' <<<"$o"; then ok "R5(b): $l -> nothing pruned, scanned (rc 1)"; else bad "R5(b): $l pruned or not scanned (rc=$r)"; fi
}
trick "tracked config/own_orgs.list + .gitmodules third_party/own keys" X=1
trick "HELIX_OWN_ORGS (no test mode)" HELIX_OWN_ORGS=bogus-org
trick "HELIX_OWN_ORGS (test mode)" HELIX_TEST_MODE=1 HELIX_OWN_ORGS=bogus-org
GIT -C "$TR" rm -q --cached config/own_orgs.list >/dev/null 2>&1; GIT -C "$TR" commit -q -m u >/dev/null 2>&1; trick "untracked config/own_orgs.list" X=1
echo 'config/' > "$TR/.git/info/exclude"; trick "ignored config/own_orgs.list" X=1
rm -rf "${TR:?}/config"; printf 'bogus\n' > "$TMP/elsewhere/own_orgs.list"; ln -s "$TMP/elsewhere" "$TR/config"; trick "symlinked config dir" X=1
t_r5b() { noprune "$1" "$TR"; }
# --own-orgs no longer exists: it is an unknown argument (exit 2), never silently accepted
for v in '--own-orgs vasic-digital' '--own-orgs --quiet' '--own-orgs'; do
    # shellcheck disable=SC2086
    timeout 20 bash "$GATE" --root "$TR" $v >/dev/null 2>&1; r=$?
    if [ "$r" -eq 2 ]; then ok "R5: '$v' is an unknown argument (exit 2)"; else bad "R5: '$v' accepted (rc=$r)"; fi
done
# (c) the reviewer's round-4 attacker probes (r4probe p1/p2/p3 shapes) -- every one scans
PR="$TMP/probe"; mkdir -p "$PR"; GIT -C "$PR" init -q .; mkrepo "$TMP/rpr/a" && addsub "$PR" "$TMP/rpr/a" submodules/mine 'git@github.com:vasic-digital/x.git' && commitall "$PR"
for v in 'vasić-digital' '.' '..' '-' '-x' '_' 'a..b' '.git' 'github.com'; do
    mkdir -p "$PR/config"; printf '%s\n' "$v" > "$PR/config/own_orgs.list"
    for L in C.UTF-8 en_US.UTF-8; do
        o="$(LC_ALL=$L bash "$GATE" --root "$PR" 2>&1)"; r=$?
        if [ "$r" -eq 1 ] && ! grep -q PRUNED.*submodules <<<"$o"; then ok "R5(c): own_orgs.list '$v' under $L -> scanned (rc 1)"; else bad "R5(c): '$v' $L rc=$r"; fi
    done
done
rm -rf "${PR:?}/config"
for g in cm_dangerous_combination_fail_closed cm_oracle_strategy_named_and_independent; do
    mkdir -p "$PR/config"; printf 'a;b\n' > "$PR/config/own_orgs.list"
    o="$(timeout 120 bash "$HERE/$g.sh" --root "$PR" 2>&1)"; r=$?
    if [ "$r" -ne 2 ] && ! grep -qi 'own-org' <<<"$o"; then ok "R5(c): $g ignores a malformed own_orgs.list (no own-org refusal, rc=$r)"; else bad "R5(c): $g still reads own_orgs.list (rc=$r)"; fi
    rm -rf "${PR:?}/config"
done

# R5 manifest custody: only the INDEX copy of a tracked, non-symlink manifest marks anything
MC="$TMP/mcust"; mkrepo "$TMP/rmc/v"; mkdir -p "$MC"; GIT -C "$MC" init -q .; addsub "$MC" "$TMP/rmc/v" submodules/v "$GO"; commitall "$MC"
manifest "$MC/helix-deps.yaml" submodules/v true
if scanned "$GATE" "$MC" && ! pline "$GATE" "$MC" 'submodules/v'; then ok "R5: UNTRACKED manifest mark ignored (scanned)"; else bad "R5: untracked manifest pruned"; fi
t_untr() { scanned "$1" "$MC"; }
MI="$TMP/mign"; cp -a "$MC" "$MI"; echo 'helix-deps.yaml' > "$MI/.git/info/exclude"
if scanned "$GATE" "$MI"; then ok "R5: IGNORED manifest mark ignored (scanned)"; else bad "R5: ignored manifest pruned"; fi
MM="$TMP/mmod"; mkrepo "$TMP/rmm/v"; mkdir -p "$MM"; GIT -C "$MM" init -q .; printf "def f():\n    return 1\n" > "$MM/f.py"; manifest "$MM/helix-deps.yaml" submodules/other true; addsub "$MM" "$TMP/rmm/v" submodules/v "$GO"; commitall "$MM"
manifest "$MM/helix-deps.yaml" submodules/v true
if scanned "$GATE" "$MM" && ! pline "$GATE" "$MM" 'submodules/v'; then ok "R5: tracked manifest MODIFIED in the worktree is ignored (scanned)"; else bad "R5: worktree-modified manifest pruned"; fi
t_mod() { scanned "$1" "$MM"; }
# golden-FALSE: the same mark once committed prunes
MG="$TMP/mgood"; cp -a "$MM" "$MG"; commitall "$MG"
if pruned "$GATE" "$MG" 'submodules/v'; then ok "R5 golden-FALSE: committed manifest mark prunes the recorded gitlink"; else bad "R5 golden-FALSE: committed mark not honoured"; fi
# R5-1 (review round 5 follow-up): custody means the INDEX. The marks are read from the index blob, never from the
# working tree, and an index entry git is told to stop comparing with the worktree (skip-worktree `S`, assume-unchanged
# `h`, any tag but `H`) is refused. Golden-BAD: index marks false, the worktree says true behind a hidden-diff state.
mkcust() { # $1=dir $2=index mark true|false : committed manifest marking submodules/v
    mkrepo "$TMP/rcu_$(basename "$1")/v" || return 1; mkdir -p "$1"; GIT -C "$1" init -q .; manifest "$1/helix-deps.yaml" submodules/v "$2"
    printf "def f():\n    return 1\n" > "$1/f.py"   # a clean first-party file, so a full prune is PASS (rc 0), never SKIP
    addsub "$1" "$TMP/rcu_$(basename "$1")/v" submodules/v "$GO" && commitall "$1"
}
CB="$TMP/cskip"; mkcust "$CB" false; GIT -C "$CB" update-index --skip-worktree helix-deps.yaml; manifest "$CB/helix-deps.yaml" submodules/v true
CC="$TMP/cassume"; mkcust "$CC" false; GIT -C "$CC" update-index --assume-unchanged helix-deps.yaml; manifest "$CC/helix-deps.yaml" submodules/v true
CL="$TMP/cfilter"; mkcust "$CL" false; printf 'helix-deps.yaml filter=x\n' > "$CL/.gitattributes"; commitall "$CL"
GIT -C "$CL" config filter.x.clean "sed 's/third_party: true/third_party: false/'"; manifest "$CL/helix-deps.yaml" submodules/v true
for c in "$CB:skip-worktree" "$CC:assume-unchanged" "$CL:clean-filter"; do
    d="${c%%:*}"; l="${c#*:}"
    # precondition: git itself reports no worktree difference (the hole the old `git diff --quiet` custody check fell into)
    GIT -C "$d" diff --quiet -- helix-deps.yaml || bad "R5-1 fixture $l: git diff sees the edit (fixture does not reproduce the hidden diff)"
    if scanned "$GATE" "$d" && ! pline "$GATE" "$d" 'submodules/v'; then ok "R5-1 golden-BAD: $l + worktree mark true, index false -> scanned"; else bad "R5-1: $l hid an edited mark (pruned)"; fi
done
t_cfilter() { scanned "$1" "$CL"; }
# the refusal is load-bearing on its own: index marks TRUE but the entry is skip-worktree / assume-unchanged -> refused, scanned
CB2="$TMP/cskip2"; mkcust "$CB2" true; GIT -C "$CB2" update-index --skip-worktree helix-deps.yaml; manifest "$CB2/helix-deps.yaml" submodules/v false
CC2="$TMP/cassume2"; mkcust "$CC2" true; GIT -C "$CC2" update-index --assume-unchanged helix-deps.yaml; manifest "$CC2/helix-deps.yaml" submodules/v false
for c in "$CB2:skip-worktree" "$CC2:assume-unchanged"; do
    d="${c%%:*}"; l="${c#*:}"
    o="$(bash "$GATE" --root "$d" 2>&1)"; r=$?
    if [ "$r" -eq 1 ] && ! grep -q 'PRUNED.*submodules/v' <<<"$o" && grep -q 'third_party_prune: manifest .* is not the recorded' <<<"$o"; then ok "R5-1: $l entry refused even when the index marks true (scanned, stated on stderr)"; else bad "R5-1: $l entry not refused (rc=$r)"; fi
done
t_cflag() { scanned "$1" "$CB2" && scanned "$1" "$CC2"; }
# visible unstaged edit of an index-true mark: still refused (scan more), so the worktree-equals-index check stays load-bearing
CM2="$TMP/cmod2"; mkcust "$CM2" true; manifest "$CM2/helix-deps.yaml" submodules/v false
if scanned "$GATE" "$CM2"; then ok "R5-1: index-true mark with a visible unstaged edit is refused (scanned)"; else bad "R5-1: unstaged-edited manifest honoured"; fi
t_cmod2() { scanned "$1" "$CM2"; }
# golden-FALSE: a staged, uncommitted mark is the index -> honoured; a plain committed mark prunes
CD="$TMP/cstaged"; mkcust "$CD" false; manifest "$CD/helix-deps.yaml" submodules/v true; GIT -C "$CD" add helix-deps.yaml
if pruned "$GATE" "$CD" 'submodules/v'; then ok "R5-1 golden-FALSE: staged (uncommitted) mark is the index and prunes"; else bad "R5-1 golden-FALSE: staged mark not honoured"; fi
CG="$TMP/cgood"; mkcust "$CG" true
if pruned "$GATE" "$CG" 'submodules/v'; then ok "R5-1 golden-FALSE: legit committed third-party mark still prunes"; else bad "R5-1 golden-FALSE: legit mark not honoured"; fi
t_cgood() { pruned "$1" "$CG" 'submodules/v' && pruned "$1" "$CD" 'submodules/v'; }

# R5-2 (review round 5 follow-up): depth boundaries. Chain top -> s1 -> s2 -> s3 -> s4 -> s5 (s5 holds the unguarded call).
#   root-manifest resolution: a 4-hop path (s1/s2/s3/s4, resolved in the depth-3 repository) prunes; a 5-hop path stays scanned.
#   own-manifest descent: the depth-3 repository's manifest is read; the depth-4 repository's manifest is not.
mkchain() { # $1=dir $2=level whose own repository carries a manifest marking its gitlink (3 or 4, or 0 for none) $3=root mark or ''
    local d="$1" R="$TMP/rch_$(basename "$1")" i
    mkrepo "$R/r5" || return 1
    for i in 4 3 2 1; do
        mkdir -p "$R/r$i"; GIT -C "$R/r$i" init -q . || return 1; printf "def f():\n    return 1\n" > "$R/r$i/f.py"
        addsub "$R/r$i" "$R/r$((i+1))" "s$((i+1))" "file://$R/r$((i+1))" || return 1
        [ "$2" = "$i" ] && manifest "$R/r$i/helix-deps.yaml" "s$((i+1))" true
        commitall "$R/r$i"
    done
    mkdir -p "$d"; GIT -C "$d" init -q .; [ -n "$3" ] && manifest "$d/helix-deps.yaml" "$3" true
    addsub "$d" "$R/r1" s1 "file://$R/r1" && commitall "$d" || return 1
    GIT -C "$d" submodule update -q --init --recursive >/dev/null 2>&1 || { bad "fixture: chain populate failed ($d)"; return 1; }
}
D4="$TMP/depth4"; mkchain "$D4" 0 s1/s2/s3/s4
D5="$TMP/depth5"; mkchain "$D5" 0 s1/s2/s3/s4/s5
DL3="$TMP/dlev3"; mkchain "$DL3" 3 ''
DL4="$TMP/dlev4"; mkchain "$DL4" 4 ''
[ -e "$D5/s1/s2/s3/s4/s5/bad.py" ] && ok "R5-2: depth chain populated (5 nested submodules)" || bad "R5-2: depth chain not populated"
if pline "$GATE" "$D4" 's1/s2/s3/s4'; then ok "R5-2: root mark 4 hops deep (resolved at depth 3) prunes"; else bad "R5-2: depth-3 resolution not honoured"; fi
if scanned "$GATE" "$D5" && ! pline "$GATE" "$D5" 's1/s2/s3/s4/s5'; then ok "R5-2: root mark 5 hops deep (depth 4) is not resolved -> scanned"; else bad "R5-2: depth-4 root mark pruned"; fi
if pline "$GATE" "$DL3" 's1/s2/s3/s4'; then ok "R5-2: own manifest of the depth-3 repository is read"; else bad "R5-2: depth-3 own manifest not read"; fi
if scanned "$GATE" "$DL4" && ! pline "$GATE" "$DL4" 's1/s2/s3/s4/s5'; then ok "R5-2: own manifest of the depth-4 repository is not read -> scanned"; else bad "R5-2: depth-4 own manifest honoured"; fi
t_d4() { pline "$1" "$D4" 's1/s2/s3/s4'; }
t_d5() { scanned "$1" "$D5"; }
t_dl3() { pline "$1" "$DL3" 's1/s2/s3/s4'; }
t_dl4() { scanned "$1" "$DL4"; }

MS="$TMP/msym"; mkrepo "$TMP/rms/v"; mkdir -p "$MS/real"; GIT -C "$MS" init -q .; manifest "$MS/real/helix-deps.yaml" submodules/v true; ln -s real/helix-deps.yaml "$MS/helix-deps.yaml"
addsub "$MS" "$TMP/rms/v" submodules/v "$GO"; commitall "$MS"
if scanned "$GATE" "$MS"; then ok "R5: tracked SYMLINK manifest is ignored (scanned)"; else bad "R5: symlink manifest pruned"; fi
MD="$TMP/mdir"; mkrepo "$TMP/rmd/v"; mkdir -p "$MD/real/sub"; GIT -C "$MD" init -q .; manifest "$MD/real/sub/helix-deps.yaml" submodules/v true
addsub "$MD" "$TMP/rmd/v" real/sub/submodules/v "$GO"; commitall "$MD"; ln -s real "$MD/lnk"
if pline "$GATE" "$MD/real/sub" 'submodules/v' && pline "$GATE" "$MD/lnk/sub" 'submodules/v'; then ok "R5: a root given through a symlinked directory resolves physically (same prune set as the physical root)"; else bad "R5: symlinked-directory root mis-handled"; fi
# a manifest reached through a symlinked directory INSIDE the repository is ignored: nested level whose parent dir is a symlink
MD2="$TMP/mdir2"; mkrepo "$TMP/rmd2/v"; mkdir -p "$MD2"; GIT -C "$MD2" init -q .; manifest "$MD2/helix-deps.yaml" sub/submodules/v true
addsub "$MD2" "$TMP/rmd2/v" sub/submodules/v "$GO"; commitall "$MD2"; mv "$MD2/sub" "$MD2/sub_real"; ln -s sub_real "$MD2/sub"
if ! pline "$GATE" "$MD2" 'sub/submodules/v'; then ok "R5: marked gitlink reached through a symlinked directory is not pruned"; else bad "R5: symlink-reached gitlink pruned"; fi

# F5: a value option as the LAST argument exits 2 promptly, never loops (all three gates)
for g in cm_killpg_pgid_guard cm_dangerous_combination_fail_closed cm_oracle_strategy_named_and_independent; do
    for opt in --root --window --max-depth --glob --baseline --base --reason; do
        grep -q -- "$opt)" "$HERE/$g.sh" || continue
        timeout 10 bash "$HERE/$g.sh" "$opt" >/dev/null 2>&1; r=$?
        if [ "$r" -eq 2 ]; then ok "F5: $g $opt without a value -> exit 2"; else bad "F5: $g $opt without a value -> rc=$r (hang/accept)"; fi
    done
done
t_f5() { timeout 10 bash "$1" --window >/dev/null 2>&1; [ $? -eq 2 ]; }

# F11: ambiguous .gitmodules (duplicate path, multi-valued url, unparseable) keeps even a MARKED gitlink scanned
A0="$TMP/amb0"; mkrepo "$TMP/ramb/r"; mkdir -p "$A0"; GIT -C "$A0" init -q .; printf "def f():\n    return 1\n" > "$A0/f.py"; manifest "$A0/helix-deps.yaml" submodules/x true; addsub "$A0" "$TMP/ramb/r" submodules/x "$GO"; commitall "$A0"
cp -a "$A0" "$TMP/amb1"; A1="$TMP/amb1"; printf '[submodule "dup"]\n\tpath = submodules/x\n\turl = %s\n' "$GO" >> "$A1/.gitmodules"; commitall "$A1"
cp -a "$A0" "$TMP/amb2"; A2="$TMP/amb2"; GIT -C "$A2" config -f .gitmodules --add submodule.submodules/x.url "$GO"; commitall "$A2"
cp -a "$A0" "$TMP/amb3"; A3="$TMP/amb3"; printf '[submodule "broken"\n\tpath=\n' >> "$A3/.gitmodules"; commitall "$A3"
if pruned "$GATE" "$A0" 'submodules/x'; then ok "F11 golden-FALSE: unambiguous marked gitlink pruned"; else bad "F11 golden-FALSE: not pruned"; fi
if scanned "$GATE" "$A1" && ! pline "$GATE" "$A1" 'submodules/x'; then ok "F11: duplicate .gitmodules path -> ambiguous -> scanned"; else bad "F11: duplicate-path ambiguity pruned"; fi
if scanned "$GATE" "$A2" && ! pline "$GATE" "$A2" 'submodules/x'; then ok "F11: multi-valued url -> ambiguous -> scanned"; else bad "F11: multi-valued url pruned"; fi
if scanned "$GATE" "$A3" && ! pline "$GATE" "$A3" 'submodules/x'; then ok "F11: unparseable .gitmodules -> ambiguous -> scanned"; else bad "F11: unparseable .gitmodules pruned"; fi
t_f11() { scanned "$1" "$A1" && scanned "$1" "$A2"; }
t_f11p() { scanned "$1" "$A3"; }

# F6/Q4: own-org URL + manifest mark: the manifest is the ONLY rule, so it prunes
Q4="$TMP/q4"; mkrepo "$TMP/rq4/r"; mkdir -p "$Q4"; GIT -C "$Q4" init -q .; manifest "$Q4/helix-deps.yaml" submodules/q true; addsub "$Q4" "$TMP/rq4/r" submodules/q "$OWN"; commitall "$Q4"
if pline "$GATE" "$Q4" 'submodules/q'; then ok "F6/Q4: own-org URL + manifest mark -> pruned by the manifest rule"; else bad "F6/Q4: manifest rule did not prune"; fi
t_q4() { pline "$1" "$Q4" 'submodules/q'; }
# F7/Q1: typechange -- the INDEX records a regular file at src, the worktree has a directory src/ holding code; manifest marks src
Q1="$TMP/q1"; mkdir -p "$Q1"; GIT -C "$Q1" init -q .; manifest "$Q1/helix-deps.yaml" src true; printf 'x\n' > "$Q1/src"; GIT -C "$Q1" add -A >/dev/null; GIT -C "$Q1" commit -q -m c
rm -f "${Q1:?}/src"; mkdir -p "$Q1/src"; printf "$BADPY" > "$Q1/src/main.py"
if scanned "$GATE" "$Q1"; then ok "F7/Q1: typechange (index blob, worktree dir) is not a gitlink -> scanned -> FAIL"; else bad "F7/Q1: typechange hid first-party code"; fi
t_q1() { scanned "$1" "$Q1"; }

# ── R6 (review 11.4.276 follow-ups round 1, F1-F5): nothing outside the INDEX ENTRY may decide which bytes are read ──
# The class: an attacker or the ambient environment changes WHICH bytes or WHICH file the prune decision reads, with no
# `git status` trace. Closed by construction: the marks are parsed from a snapshot of the worktree file whose
# `git hash-object --no-filters` equals the sha that the stage-0, mode-100644 index entry records for exactly that
# path; the object store is never read, and every git call runs under `env -i` (no caller GIT_* / config env).
forge_obj() { # $1=objects dir $2=sha $3=file with the forged content : write a loose object under <sha> with other bytes
    python3 -I - "$1" "$2" "$3" <<'PY'
import sys, zlib, os
d, sha, f = sys.argv[1:]; c = open(f, 'rb').read(); p = os.path.join(d, sha[:2], sha[2:])
os.makedirs(os.path.dirname(p), exist_ok=True)
if os.path.exists(p): os.chmod(p, 0o644)
open(p, 'wb').write(zlib.compress(b'blob %d\0' % len(c) + c))
PY
}
manifest "$TMP/r6_true.yaml" submodules/v true; manifest "$TMP/r6_false.yaml" submodules/v false
# F1 golden-BAD: `git replace` of the index blob (index false -> replacement true), no status trace
RR="$TMP/r6repl"; mkcust "$RR" false; GIT -C "$RR" replace "$(GIT -C "$RR" rev-parse :helix-deps.yaml)" "$(GIT -C "$RR" hash-object -w "$TMP/r6_true.yaml")"
[ -z "$(GIT -C "$RR" status --porcelain)" ] || bad "R6 fixture F1: replace ref left a status trace"
if scanned "$GATE" "$RR" && ! pline "$GATE" "$RR" 'submodules/v'; then ok "R6/F1: git replace of the manifest blob does not change the marks (scanned)"; else bad "R6/F1: replace ref pruned an own submodule"; fi
# F1 golden-FALSE: a replace ref on a legitimately-true manifest (replacement false) does not hide the real mark
RG="$TMP/r6replg"; mkcust "$RG" true; GIT -C "$RG" replace "$(GIT -C "$RG" rev-parse :helix-deps.yaml)" "$(GIT -C "$RG" hash-object -w "$TMP/r6_false.yaml")"
if pruned "$GATE" "$RG" 'submodules/v'; then ok "R6/F1 golden-FALSE: replace ref on a true manifest -> the index content still prunes"; else bad "R6/F1 golden-FALSE: replace ref changed a legit verdict"; fi
t_repl() { scanned "$1" "$RR"; }
t_replg() { pruned "$1" "$RG" 'submodules/v'; }
# F2 golden-BAD: caller env redirects the object store or the replace namespace
RO="$TMP/r6objd"; mkcust "$RO" false; s="$(GIT -C "$RO" rev-parse :helix-deps.yaml)"; cp -a "$(GIT -C "$RO" rev-parse --absolute-git-dir)/objects" "$TMP/r6fobj"; forge_obj "$TMP/r6fobj" "$s" "$TMP/r6_true.yaml"
envbad() { # $1=label $2=dir then env assignments
    local l="$1" d="$2"; shift 2; local o r; o="$(env "$@" bash "$GATE" --root "$d" 2>&1)"; r=$?
    if [ "$r" -eq 1 ] && ! grep -q 'PRUNED.*submodules/v' <<<"$o"; then ok "R6/F2: $l does not change the marks (scanned)"; else bad "R6/F2: $l pruned an own submodule (rc=$r)"; fi
}
envbad "GIT_OBJECT_DIRECTORY with a forged object" "$RO" GIT_OBJECT_DIRECTORY="$TMP/r6fobj"
RB="$TMP/r6rbase"; mkcust "$RB" false; GIT -C "$RB" update-ref "refs/x/$(GIT -C "$RB" rev-parse :helix-deps.yaml)" "$(GIT -C "$RB" hash-object -w "$TMP/r6_true.yaml")"
envbad "GIT_REPLACE_REF_BASE" "$RB" GIT_REPLACE_REF_BASE=refs/x/
# F2: a forged loose object INSIDE the repository's own object store (no env at all)
RF="$TMP/r6forge"; mkcust "$RF" false; forge_obj "$(GIT -C "$RF" rev-parse --absolute-git-dir)/objects" "$(GIT -C "$RF" rev-parse :helix-deps.yaml)" "$TMP/r6_true.yaml"
if scanned "$GATE" "$RF" && ! pline "$GATE" "$RF" 'submodules/v'; then ok "R6/F2: forged loose object in the repository does not change the marks (scanned)"; else bad "R6/F2: forged in-repo object pruned"; fi
# F2 golden-FALSE: ambient git config env does not change a legit verdict (control: the same env breaks plain git)
RE="$TMP/r6envg"; mkcust "$RE" true
for e in GIT_CONFIG_PARAMETERS=bogus GIT_CONFIG_COUNT=1 GIT_OBJECT_DIRECTORY=/nonexistent; do
    if ! env "$e" git -C "$RE" rev-parse --show-toplevel >/dev/null 2>&1; then ok "R6 control needle: $e breaks an unscrubbed git"; else bad "R6 control needle: $e has no effect on plain git (test proves nothing)"; fi
done
envgood() { pruned "$1" "$RE" 'submodules/v'; }
t_envg() { local g="$1"; GIT_CONFIG_PARAMETERS=bogus envgood "$g" && GIT_CONFIG_COUNT=1 envgood "$g" \
    && GIT_INDEX_FILE=/nonexistent/idx GIT_OBJECT_DIRECTORY=/nonexistent GIT_NAMESPACE=x GIT_DIR=/nonexistent envgood "$g"; }
if t_envg "$GATE"; then ok "R6/F2 golden-FALSE: GIT_CONFIG_PARAMETERS / GIT_CONFIG_COUNT / GIT_OBJECT_DIRECTORY / GIT_INDEX_FILE / GIT_DIR do not change a legit prune"; else bad "R6/F2 golden-FALSE: ambient git env changed a legit verdict"; fi
# F2: an injected fsmonitor command never runs (control: the same env does run it under `git status`)
printf '#!/bin/sh\ntouch "%s/fsmon_ran"\nexit 1\n' "$TMP" > "$TMP/fsmon.sh"; chmod +x "$TMP/fsmon.sh"
env GIT_CONFIG_PARAMETERS="'core.fsmonitor'='$TMP/fsmon.sh'" git -C "$RE" status --porcelain >/dev/null 2>&1
if [ -e "$TMP/fsmon_ran" ]; then ok "R6 control needle: injected core.fsmonitor runs under plain git status"; rm -f -- "${TMP:?}/fsmon_ran"; else bad "R6 control needle: fsmonitor injection inert (test proves nothing)"; fi
env GIT_CONFIG_PARAMETERS="'core.fsmonitor'='$TMP/fsmon.sh'" bash "$GATE" --root "$RE" >/dev/null 2>&1
if [ ! -e "$TMP/fsmon_ran" ]; then ok "R6/F2: injected core.fsmonitor command is never run by the prune"; else bad "R6/F2: the prune ran an injected fsmonitor command"; fi
GIT -C "$RE" config core.fsmonitor "$TMP/fsmon.sh"; rm -f -- "${TMP:?}/fsmon_ran"; bash "$GATE" --root "$RE" >/dev/null 2>&1
if [ ! -e "$TMP/fsmon_ran" ]; then ok "R6/F2: a repository-local core.fsmonitor command is never run by the prune"; else bad "R6/F2: the prune ran a repository-local fsmonitor command"; fi
GIT -C "$RE" config --unset core.fsmonitor
# F3 golden-BAD: gate root whose name is index-path syntax (0:s); a sibling s/helix-deps.yaml marks true
CO="$TMP/r6colon"; mkdir -p "$CO/0:s" "$CO/s"; GIT -C "$CO" init -q .; mkrepo "$TMP/r6rco/v"
manifest "$CO/0:s/helix-deps.yaml" submodules/v false; manifest "$CO/s/helix-deps.yaml" submodules/v true; printf "def f():\n    return 1\n" > "$CO/0:s/f.py"
( cd "$CO/0:s" && GIT submodule add -q "file://$TMP/r6rco/v" submodules/v >/dev/null 2>&1 ) || bad "R6 fixture F3: submodule add failed"; commitall "$CO"
if scanned "$GATE" "$CO/0:s" && ! pline "$GATE" "$CO/0:s" 'submodules/v'; then ok "R6/F3: root named 0:s reads its own manifest, not stage 0 of s/ (scanned)"; else bad "R6/F3: index-path syntax in the root read another file (pruned)"; fi
# F4: index mode is load-bearing. SYMTYPE = the index records a SYMLINK whose link text is a YAML manifest, the worktree
# holds a regular file with exactly those bytes (hash equal): only the mode check refuses it.
mksym() { # $1=dir : committed symlink helix-deps.yaml whose link TEXT is a third_party: true manifest
    mkrepo "$TMP/r6rs_$(basename "$1")/v" || return 1; mkdir -p "$1"; GIT -C "$1" init -q .; printf "def f():\n    return 1\n" > "$1/f.py"
    ln -s "$(cat "$TMP/r6_true.yaml")" "$1/helix-deps.yaml"; addsub "$1" "$TMP/r6rs_$(basename "$1")/v" submodules/v "$GO" && commitall "$1"
}
SL="$TMP/r6symlink"; mksym "$SL"; [ "$(GIT -C "$SL" ls-files -s helix-deps.yaml | cut -c1-6)" = 120000 ] || bad "R6 fixture F4: symlink not recorded as 120000"
if scanned "$GATE" "$SL" && ! pline "$GATE" "$SL" 'submodules/v'; then ok "R6/F4: tracked symlink whose link text is YAML is refused (scanned)"; else bad "R6/F4: symlink manifest pruned"; fi
ST="$TMP/r6symtype"; mksym "$ST"; rm -f -- "${ST:?}/helix-deps.yaml"; GIT -C "$ST" cat-file blob "$(GIT -C "$ST" rev-parse :helix-deps.yaml)" > "$ST/helix-deps.yaml"
[ "$(GIT -C "$ST" hash-object --no-filters "$ST/helix-deps.yaml")" = "$(GIT -C "$ST" rev-parse :helix-deps.yaml)" ] || bad "R6 fixture SYMTYPE: worktree bytes differ from the 120000 blob"
if scanned "$GATE" "$ST" && ! pline "$GATE" "$ST" 'submodules/v'; then ok "R6/F4: index mode 120000 with an identical regular worktree file is refused (mode check)"; else bad "R6/F4: non-100644 index entry honoured"; fi
t_symtype() { scanned "$1" "$ST"; }
# the worktree must be a plain regular file: a legit 100644 true entry whose worktree is a symlink to identical bytes is refused
WS="$TMP/r6wtsym"; mkcust "$WS" true; mv "$WS/helix-deps.yaml" "$TMP/r6wtsym_target.yaml"; ln -s "$TMP/r6wtsym_target.yaml" "$WS/helix-deps.yaml"
if scanned "$GATE" "$WS"; then ok "R6: 100644 entry whose worktree is a symlink (same bytes) is refused (scanned)"; else bad "R6: symlinked worktree manifest honoured"; fi
t_wtsym() { scanned "$1" "$WS"; }
# executable bit in the worktree differs from the 100644 entry: visible difference -> refused
XB="$TMP/r6xbit"; mkcust "$XB" true; chmod +x "$XB/helix-deps.yaml"
if scanned "$GATE" "$XB"; then ok "R6: worktree +x on a 100644 manifest is refused (scanned)"; else bad "R6: exec-bit difference ignored"; fi
t_xbit() { scanned "$1" "$XB"; }
# F5: intent-to-add (git add -N): the index records the empty blob, the worktree says true -> refused
IA="$TMP/r6ita"; mkcust "$IA" false; GIT -C "$IA" rm -q --cached helix-deps.yaml; GIT -C "$IA" commit -q -m u >/dev/null 2>&1; manifest "$IA/helix-deps.yaml" submodules/v true; GIT -C "$IA" add -N helix-deps.yaml
if scanned "$GATE" "$IA" && ! pline "$GATE" "$IA" 'submodules/v'; then ok "R6/F5: intent-to-add manifest (empty index blob) is refused (scanned)"; else bad "R6/F5: intent-to-add manifest pruned"; fi
t_ita() { scanned "$1" "$IA"; }
# a single non-zero-stage entry whose content equals the worktree: there is no stage-0 record -> refused
S2="$TMP/r6stage2"; mkcust "$S2" false; GIT -C "$S2" rm -q --cached helix-deps.yaml; GIT -C "$S2" commit -q -m u >/dev/null 2>&1; cp "$TMP/r6_true.yaml" "$S2/helix-deps.yaml"
printf '100644 %s 2\thelix-deps.yaml\n' "$(GIT -C "$S2" hash-object -w "$S2/helix-deps.yaml")" | GIT -C "$S2" update-index --index-info
[ "$(GIT -C "$S2" ls-files -s helix-deps.yaml | awk '{print $3}')" = 2 ] || bad "R6 fixture STAGE2: no stage-2 entry"
if scanned "$GATE" "$S2"; then ok "R6: a lone stage-2 (unmerged) entry is refused (scanned)"; else bad "R6: unmerged stage-2 entry honoured"; fi
t_stage2() { scanned "$1" "$S2"; }
# gate root inside an UNPOPULATED gitlink holding a stray manifest + plain dir: not the recorded copy -> scanned
UP="$TMP/r6unpop"; mkrepo "$TMP/r6rup/a"; mkdir -p "$UP"; GIT -C "$UP" init -q .; printf "def f():\n    return 1\n" > "$UP/f.py"; addsub "$UP" "$TMP/r6rup/a" submodules/a "$GO" && commitall "$UP"
rm -rf "${UP:?}/submodules/a"; mkdir -p "$UP/submodules/a/x"; manifest2 "$UP/submodules/a/helix-deps.yaml" x true; printf "$BADPY" > "$UP/submodules/a/x/bad.py"
if scanned "$GATE" "$UP/submodules/a" && ! pline "$GATE" "$UP/submodules/a" 'x'; then ok "R6: root inside an unpopulated gitlink with a stray manifest is scanned"; else bad "R6: unpopulated-gitlink root pruned"; fi
# golden-FALSE: a committed CRLF manifest marking true (bytes equal to the index blob) still prunes
CR="$TMP/r6crlf"; mkcust "$CR" true; sed -i 's/$/\r/' "$CR/helix-deps.yaml"; commitall "$CR"
if pruned "$GATE" "$CR" 'submodules/v'; then ok "R6 golden-FALSE: committed CRLF manifest marking true prunes"; else bad "R6 golden-FALSE: committed CRLF manifest not honoured"; fi

# ── R7 (review 11.4.276 follow-ups round 2, G1/G2): the worktree manifest is read by ONE bounded open ─────────────
# Class closed: "a read of an attacker-influenced worktree path". The reader walks the path with O_NOFOLLOW on every
# component, opens the last one O_NONBLOCK, and fstat()s the fd (regular file, no exec bit, size <= cap); it reads at
# most cap+1 bytes into a private snapshot, and that snapshot is both hashed and parsed. Every git / reader call is time
# bounded. Every fixture runs under a short timeout so a hang FAILS fast (rc 124), and carries a control needle (the
# literal `third_party` line proves the prune function ran to its end). The race is simulated deterministically by a
# `git` shim first on PATH (PATH is the one variable _cm_tp_git forwards): on the chosen git call it swaps the file once.
R7REALGIT="$(command -v git)"
mkshim() { # $1=shim dir $2=trigger ls|hash|lshang $3=action fifo|zero|dir|inplace $4=worktree file $5=source file
    mkdir -p "$1"; rm -rf -- "${1:?}/flag"
    {
        printf '#!/bin/bash\ntrig=%q; act=%q; W=%q; SRC=%q; FLAG=%q\n' "$2" "$3" "$4" "${5:-}" "$1/flag"
        cat <<'SH'
hit=""
case "$trig" in
    ls|lshang) case " $* " in *" ls-files "*) hit=1 ;; esac ;;
    hash) case " $* " in *" hash-object "*) hit=1 ;; esac ;;
esac
if [ "$trig" = lshang ] && [ -n "$hit" ]; then exec sleep 30; fi
if [ -n "$hit" ] && mkdir -- "$FLAG" 2>/dev/null; then
    case "$act" in
        fifo) rm -f -- "${W:?}"; mkfifo -- "$W" ;;
        zero) rm -f -- "${W:?}"; ln -s /dev/zero "$W" ;;
        dir)  rm -f -- "${W:?}"; mkdir -- "$W" ;;
        inplace) cat -- "${SRC:?}" > "$W" ;;
    esac
fi
SH
        printf 'exec %q "$@"\n' "$R7REALGIT"
    } > "$1/git"
    chmod +x "$1/git"
}
tplib() { # $1=gate $2=root [$3=shim dir] [$4=bash code run after sourcing the lib] : prune set on stdout, stderr in $TMP/r7err
    local lib p="$PATH"; lib="$(cd "$(dirname "$1")/../lib" && pwd -P)/third_party_prune.sh"
    [ -n "${3:-}" ] && p="$3:$PATH"
    timeout -k 2 15 env PATH="$p" bash -c 'ulimit -f 4096; . "$1" || exit 9; eval "${3:-:}"; cm_third_party_prune_paths "$2"' _ "$lib" "$2" "${4:-}" 2>"$TMP/r7err"
}
r7refused() { local o r; o="$(tplib "$@")"; r=$?; [ "$r" -eq 0 ] && grep -qx third_party <<<"$o" && ! grep -qx 'submodules/v' <<<"$o"; }
r7pruned()  { local o r; o="$(tplib "$@")"; r=$?; [ "$r" -eq 0 ] && grep -qx 'submodules/v' <<<"$o"; }
r7why() { grep -q "reason=$1" "$TMP/r7err"; }
r7reset() { rm -rf -- "${1:?}/helix-deps.yaml"; cp -- "$2" "$1/helix-deps.yaml"; }
manifest "$TMP/r7_true.yaml" submodules/v true; manifest "$TMP/r7_false.yaml" submodules/v false
# (1) a plain FIFO as the worktree manifest, no race (the index records a true 100644 blob): refused at once
R7F="$TMP/r7fifo"; mkcust "$R7F" true; rm -f -- "${R7F:?}/helix-deps.yaml"; mkfifo -- "$R7F/helix-deps.yaml"
t_r7fifo() { r7refused "$1" "$R7F" && r7why notreg; }
if t_r7fifo "$GATE"; then ok "R7: FIFO worktree manifest refused at once (reason=notreg, no hang)"; else bad "R7: FIFO worktree manifest hung or was honoured: $(head -c 300 "$TMP/r7err" | tr '\n' ' ')"; fi
if scanned "$GATE" "$R7F"; then ok "R7: FIFO worktree manifest -> the gate scans"; else bad "R7: FIFO manifest pruned or hung through the gate"; fi
# (2) the G1 race made deterministic: the path is swapped AFTER the index lookup (first ls-files) and BEFORE the open
R7S="$TMP/r7swap"; mkcust "$R7S" true
t_r7swap() { r7reset "$R7S" "$TMP/r7_true.yaml"; mkshim "$TMP/r7shim" ls "$2" "$R7S/helix-deps.yaml"; r7refused "$1" "$R7S" "$TMP/r7shim"; }
for a in fifo:notreg zero:open dir:notreg; do
    w="${a#*:}"; a="${a%%:*}"
    if t_r7swap "$GATE" "$a" && r7why "$w" && ! grep -q 'File size limit' "$TMP/r7err"; then ok "R7: race swap to $a between the index lookup and the open -> refused (reason=$w), no hang, nothing past the cap"; else bad "R7: race swap to $a hung, filled TMPDIR or was honoured: $(head -c 300 "$TMP/r7err" | tr '\n' ' ')"; fi
done
t_r7swapfifo() { t_r7swap "$1" fifo && r7why notreg; }
t_r7swapzero() { t_r7swap "$1" zero && r7why open; }
# control needle: the shim really swaps (without it, the swap fixtures would prove nothing)
r7reset "$R7S" "$TMP/r7_true.yaml"; mkshim "$TMP/r7shim" ls dir "$R7S/helix-deps.yaml"; env PATH="$TMP/r7shim:$PATH" git -C "$R7S" ls-files >/dev/null 2>&1
if [ -d "$R7S/helix-deps.yaml" ]; then ok "R7 control needle: the git shim swaps the file on ls-files"; else bad "R7 control needle: the shim did not swap (fixtures prove nothing)"; fi
r7reset "$R7S" "$TMP/r7_true.yaml"
# (3) snapshot custody: the file is rewritten IN PLACE when hash-object runs (after the snapshot). The bytes hashed and
# the bytes parsed must both be the snapshot. A: index false, snapshot false, rewritten to true -> not pruned (kills
# "parse the worktree"). B: index false, snapshot true, rewritten to false (= the index) -> not pruned (kills "hash the
# worktree"). C golden-FALSE: index true, snapshot true, rewritten to false -> pruned (the snapshot decides).
R7A="$TMP/r7snapA"; mkcust "$R7A" false; R7B="$TMP/r7snapB"; mkcust "$R7B" false; R7C="$TMP/r7snapC"; mkcust "$R7C" true
t_r7snapA() { r7reset "$R7A" "$TMP/r7_false.yaml"; mkshim "$TMP/r7shimA" hash inplace "$R7A/helix-deps.yaml" "$TMP/r7_true.yaml"; r7refused "$1" "$R7A" "$TMP/r7shimA"; }
t_r7snapB() { r7reset "$R7B" "$TMP/r7_true.yaml"; mkshim "$TMP/r7shimB" hash inplace "$R7B/helix-deps.yaml" "$TMP/r7_false.yaml"; r7refused "$1" "$R7B" "$TMP/r7shimB"; }
t_r7snapC() { r7reset "$R7C" "$TMP/r7_true.yaml"; mkshim "$TMP/r7shimC" hash inplace "$R7C/helix-deps.yaml" "$TMP/r7_false.yaml"; r7pruned "$1" "$R7C" "$TMP/r7shimC"; }
if t_r7snapA "$GATE"; then ok "R7: snapshot A (rewritten to true after the snapshot) -> marks come from the snapshot, not pruned"; else bad "R7: snapshot A pruned (the worktree was parsed after the hash)"; fi
if t_r7snapB "$GATE"; then ok "R7: snapshot B (rewritten to match the index after the snapshot) -> refused, not pruned"; else bad "R7: snapshot B pruned (the worktree was hashed, the snapshot parsed)"; fi
if t_r7snapC "$GATE"; then ok "R7 golden-FALSE: snapshot C (true snapshot, rewritten after) -> pruned from the snapshot"; else bad "R7 golden-FALSE: snapshot C not pruned"; fi
if [ "$(cat "$R7C/helix-deps.yaml")" = "$(cat "$TMP/r7_false.yaml")" ]; then ok "R7 control needle: the hash-object shim rewrote the worktree"; else bad "R7 control needle: hash-object shim did not rewrite"; fi
# (4) an oversized regular manifest (> 1 MiB) whose bytes equal its index entry: refused by size, no full copy
R7L="$TMP/r7big"; mkcust "$R7L" true; python3 -I -c 'import sys; open(sys.argv[1],"a").write("# pad\n" * 200000)' "$R7L/helix-deps.yaml"; commitall "$R7L"
[ "$(stat -c %s "$R7L/helix-deps.yaml")" -gt 1048576 ] || bad "R7 fixture BIG: manifest is not over 1 MiB"
t_r7big() { r7refused "$1" "$R7L" && r7why toolarge; }
if t_r7big "$GATE"; then ok "R7: manifest over the 1 MiB cap refused (reason=toolarge)"; else bad "R7: oversized manifest honoured or wrong reason: $(head -c 300 "$TMP/r7err" | tr '\n' ' ')"; fi
# (5) a device node as the worktree manifest, when this host lets this uid create one
R7D="$TMP/r7dev"; mkcust "$R7D" true; rm -f -- "${R7D:?}/helix-deps.yaml"
if mknod "$R7D/helix-deps.yaml" c 1 5 2>/dev/null; then
    if r7refused "$GATE" "$R7D" && r7why notreg; then ok "R7: device-node worktree manifest refused"; else bad "R7: device-node manifest not refused"; fi
else echo "SKIP: R7 device node: mknod is not permitted for this uid (topology_unsupported); the zero-swap case covers a device reached by a symlink"; fi
# (6) every git call is time bounded: a git that hangs on ls-files is cut off, the prune finishes and scans more
R7T="$TMP/r7hang"; mkcust "$R7T" true; mkshim "$TMP/r7shimT" lshang x "$R7T/helix-deps.yaml"
t_r7hang() { r7refused "$1" "$R7T" "$TMP/r7shimT" '_CM_TP_GIT_TIMEOUT=2'; }
if t_r7hang "$GATE"; then ok "R7: a hanging git ls-files is cut off by the time bound (scan more, no hang)"; else bad "R7: a hanging git call hung the prune"; fi
# (7) the private snapshot directory is removed on normal exit AND when the prune is killed by TERM mid-run
R7TD="$TMP/r7tmpd"; mkdir -p "$R7TD"
t_r7clean() { # $1=gate: normal run leaves nothing; a TERM while git hangs leaves nothing; needle: the dir existed mid-run
    local lib i seen=""; lib="$(cd "$(dirname "$1")/../lib" && pwd -P)/third_party_prune.sh"
    rm -rf -- "${R7TD:?}"; mkdir -p "$R7TD"
    env TMPDIR="$R7TD" bash -c '. "$1"; cm_third_party_prune_paths "$2"' _ "$lib" "$R7C" >/dev/null 2>&1
    [ -z "$(ls -A "$R7TD")" ] || return 1
    timeout -s TERM 3 env TMPDIR="$R7TD" PATH="$TMP/r7shimT:$PATH" bash -c '. "$1"; cm_third_party_prune_paths "$2"' _ "$lib" "$R7T" >/dev/null 2>&1 &
    local pid=$!
    for i in $(seq 1 25); do [ -n "$(ls -A "$R7TD")" ] && { seen=1; break; }; sleep 0.1; done
    wait "$pid"
    [ -n "$seen" ] && [ -z "$(ls -A "$R7TD")" ]
}
if t_r7clean "$GATE"; then ok "R7: the snapshot dir existed mid-run and is removed on exit and on TERM (no tp_manifest.* left)"; else bad "R7: snapshot temp left behind ($(ls -A "$R7TD" | head -3 | tr '\n' ' '))"; fi
# (8) the reader on its own (unit level, the lib's embedded reader): no-follow on INTERMEDIATE components, and a file
# that grows past the cap between fstat and read (simulated: fstat returns the stat taken before the file grew)
R7U="$TMP/r7unit"; mkdir -p "$R7U/real"; cp -- "$TMP/r7_true.yaml" "$R7U/real/helix-deps.yaml"; ln -s real "$R7U/lnk"; : > "$R7U/out"
r7reader() { # $1=gate $2=python prelude then reader args : rc of the reader
    local lib; lib="$(cd "$(dirname "$1")/../lib" && pwd -P)/third_party_prune.sh"; shift
    timeout -k 2 15 bash -c '. "$1"; pre="$2"; shift 2; python3 -I -B -c "$pre
$_CM_TP_READ_PY" "$@"' _ "$lib" "$@" 2>/dev/null
}
t_r7walk() { r7reader "$1" '' "$R7U" real/helix-deps.yaml "$R7U/out" 1048576 && [ -s "$R7U/out" ] || return 1
    : > "$R7U/out"; r7reader "$1" '' "$R7U" lnk/helix-deps.yaml "$R7U/out" 1048576; [ $? -eq 7 ] && [ ! -s "$R7U/out" ]; }
if t_r7walk "$GATE"; then ok "R7 unit: a symlinked intermediate directory is refused (rc 7), the real path reads (needle)"; else bad "R7 unit: intermediate symlink followed or real path unreadable"; fi
GROWPRE='import os
_r7f = os.fstat
def _r7g(fd):
    st = _r7f(fd)
    with open("'"$R7U/real/grow.yaml"'", "ab") as g: g.write(b"#" * (2 << 20))
    return st
os.fstat = _r7g'
t_r7grow() { cp -- "$TMP/r7_true.yaml" "$R7U/real/grow.yaml"; : > "$R7U/out"
    r7reader "$1" "$GROWPRE" "$R7U" real/grow.yaml "$R7U/out" 1048576; [ $? -eq 6 ] && [ ! -s "$R7U/out" ]; }
if t_r7grow "$GATE"; then ok "R7 unit: a file that grows past the cap after fstat is refused (rc 6) and nothing is written"; else bad "R7 unit: a grown file was copied"; fi

# --- paired mutations of the remaining prune logic: each MUST be caught ---
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
    bash -n "$D/lib/third_party_prune.sh" 2>/dev/null || { bad "mutant $name does not parse (a parse error would be a false kill)"; return; }
    "$@" "$D/gates/cm_killpg_pgid_guard.sh" && bad "mutant $name survived (test not load-bearing)" || ok "mutant $name caught"
}
t_p1()  { scanned "$1" "$P1"; }
t_p2()  { scanned "$1" "$P2/sub" && pruned "$1" "$P2B/sub" 'submodules/v'; }
t_p3()  { scanned "$1" "$P3"; }
t_p4()  { scanned "$1" "$P4"; }
t_hos() { scanned "$1" "$H"; }
t_n0()  { noprune "$1" "$N0"; }
t_n2()  { pline "$1" "$N2" 'submodules/a/submodules/b'; }
t_n1()  { pline "$1" "$N1" 'submodules/a/submodules/b'; }
t_n3()  { scanned "$1" "$N3"; }
t_mg()  { pruned "$1" "$MG" 'submodules/v'; }
t_sp()  { ! pline "$1" "$SP" 'sp ace'; }
t_md2() { ! pline "$1" "$MD2" 'sub/submodules/v'; }
chk exact     's/\[ "\$path" = "\$2" \]/true/' '\[ "\$path" = "\$2" \]' t_p1
chk rec       's/if cm_tp_gitlink_deep "\$top" .*; then tp/if true; then tp/' 'if cm_tp_gitlink_deep "\$top"' t_hos
chk toplvl    's/^    \[ "\$rootp" = "\$top" \] || prefix=.*/    prefix=""/' '\[ "\$rootp" = "\$top" \] || prefix=' t_p2
chk gitmod    's/^cm_tp_is_gitlink() {/cm_tp_is_gitlink() { grep -Fq "path = $2" "$1\/.gitmodules" 2>\/dev\/null \&\& return 0/' '^cm_tp_is_gitlink() {' t_p3
chk nogit     's/^cm_tp_is_gitlink() {/cm_tp_is_gitlink() { return 0/;s/^cm_tp_manifest_recorded() {/cm_tp_manifest_recorded() { cat "$1\/$2" > "$3"; return 0/;s/top="\$(_cm_tp_git -C "\$rootp" rev-parse --show-toplevel 2>\/dev\/null)" || {/top="$rootp"; true || {/' 'rev-parse --show-toplevel 2>/dev/null)" || {' t_p4
chk modecheck 's/\[ "\$mode" = 160000 \] \&\& //' '\[ "\$mode" = 160000 \] \&\& ' t_q1
chk m_off     's/then tp\["\$pp"\]=1/then :/' 'then tp\["\$pp"\]=1' t_q4
chk recurse   's/cm_tp_populated "\$base\/\$rel" \&\& cm_tp_level/false \&\& cm_tp_level/' 'cm_tp_populated "\$base/\$rel" && cm_tp_level' t_n1
chk deepres   's/cm_tp_gitlink_deep "\$top\/\$pre" "\$rest" \$((depth+1)); return \$?/return 1/' 'cm_tp_gitlink_deep "\$top/\$pre" "\$rest"' t_n2
# (deeppop -- dropping the parent-populated check -- is an EQUIVALENT mutant: an unpopulated parent resolves to the outer
#  repository, whose --full-name path never equals the nested path; recorded in the report, not a test gap)
chk pathok    's/                    cm_third_party_prune_ok "\$pp" || continue/                    :/' 'cm_third_party_prune_ok "\$pp" || continue' t_sp
chk nosym     's/                    cm_tp_no_symlink "\$base" "\$pp" || continue/                    :/' 'cm_tp_no_symlink "\$base" "\$pp" || continue' t_md2
chk ambig     's/^cm_tp_recorded() { cm_tp_is_gitlink "\$1" "\$2" \&\& ! cm_tp_ambiguous "\$1" "\$2"; }/cm_tp_recorded() { cm_tp_is_gitlink "$1" "$2"; }/' '^cm_tp_recorded() {' t_f11
chk ambparse  's/    _cm_tp_git config -f "\$gm" --list >\/dev\/null 2>\&1 || return 0/    :/' '_cm_tp_git config -f "\$gm" --list' t_f11p
# R6 (review follow-ups r1): the recorded-copy guards, one killing fixture each. EQUIVALENT by construction (stated,
# not tested): the literal pathspec, the exact-path compare and the one-record count in cm_tp_manifest_entry -- any
# mis-selected record carries a sha the snapshot hash cannot match unless its bytes are identical, and identical bytes
# are the recorded bytes; core.fsmonitor=false -- no command of the library refreshes the index (the fsmonitor
# fixtures above prove no injected command runs, with or without it). The old tag (`H`) check is gone: a skip-worktree
# or assume-unchanged entry is now judged by its bytes (hash vs index sha), which that state can no longer hide.
chk custody   's/^cm_tp_manifest_recorded() {/cm_tp_manifest_recorded() { cat "$1\/$2" > "$3"; return 0/' '^cm_tp_manifest_recorded() {' t_mod
chk blobgood  's/^cm_tp_manifest_recorded() {/cm_tp_manifest_recorded() { return 1/' '^cm_tp_manifest_recorded() {' t_cgood
chk hashchk   's/^    \[ "\$got" = "\$sha" \]$/    true/' '^    \[ "\$got" = "\$sha" \]$' t_mod
chk hashita   's/^    \[ "\$got" = "\$sha" \]$/    true/' '^    \[ "\$got" = "\$sha" \]$' t_ita
chk idxmode   's/        \[ "\$mode" = 100644 \] || return 1/        :/' '\[ "\$mode" = 100644 \] || return 1' t_symtype
chk idxstage  's/        \[ "\$stage" = 0 \] || return 1/        :/' '\[ "\$stage" = 0 \] || return 1' t_stage2
chk noentry   's/^cm_tp_manifest_entry() {/cm_tp_manifest_entry() { _cm_tp_git -C "$1" hash-object --no-filters --stdin < "$1\/$2"; return 0/' '^cm_tp_manifest_entry() {' t_untr
chk wtfile    's/fl | os.O_NOFOLLOW | os.O_NONBLOCK/fl | os.O_NONBLOCK/' 'fl | os.O_NOFOLLOW | os.O_NONBLOCK' t_wtsym
chk wtxbit    's/        if st.st_mode \& 0o111:/        if False:/' 'if st.st_mode & 0o111:' t_xbit
chk envscrub  's/^    env -i PATH=.*GIT_CONFIG_NOSYSTEM.*/    env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_CEILING_DIRECTORIES -u GIT_COMMON_DIR \\/;s/^        GIT_TERMINAL_PROMPT=0 GIT_OPTIONAL_LOCKS=0 "\${to\[@\]}" git -c core.fsmonitor=false/        "${to[@]}" git/' '^    env -i PATH=.*GIT_CONFIG_NOSYSTEM' t_envg
chk noreplace 's/^    env -i PATH=.*GIT_CONFIG_NOSYSTEM.*/    env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_CEILING_DIRECTORIES -u GIT_COMMON_DIR \\/;s/^        GIT_TERMINAL_PROMPT=0 GIT_OPTIONAL_LOCKS=0 "\${to\[@\]}" git -c core.fsmonitor=false/        "${to[@]}" git/;s/^    _cm_tp_bounded "\$top" "\$p" "\$out"; rc=\$?/    _cm_tp_git -C "$top" cat-file blob "$sha" > "$out" 2>\/dev\/null; rc=$?/;s/^    \[ "\$got" = "\$sha" \]$/    true/' '^    _cm_tp_bounded "\$top" "\$p" "\$out"; rc=' t_repl
chk objread   's/^    _cm_tp_bounded "\$top" "\$p" "\$out"; rc=\$?/    _cm_tp_git -C "$top" cat-file blob "$sha" > "$out" 2>\/dev\/null; rc=$?/' '^    _cm_tp_bounded "\$top" "\$p" "\$out"; rc=' t_replg
# R7 (review follow-ups r2, G1/G2): the bounded-reader guards, one behaviour fixture each (reviewer RM1 / RM5 / RM9
# included). RM9 ("drop the -f check") has no literal anchor any more: the regular-file guard is the reader's S_ISREG
# (rm9isreg) and the no-hang guard is O_NONBLOCK (rm9nonblk); both are killed by the plain FIFO fixture.
chk rm1parse  's/recs="\$(cm_hdeps_tsv "\$blobf")"/recs="$(cm_hdeps_tsv "$base\/helix-deps.yaml")"/' 'recs="\$(cm_hdeps_tsv "\$blobf")"' t_r7snapA
chk rm5hash   's/--stdin < "\$out" 2>\/dev\/null)" || return 1/--stdin < "$top\/$p" 2>\/dev\/null)" || return 1/' 'hash-object --no-filters --stdin < "\$out"' t_r7snapB
chk rm9isreg  's/        if not stat.S_ISREG(st.st_mode):/        if False:/' 'if not stat.S_ISREG(st.st_mode):' t_r7fifo
chk rm9nonblk 's/ | os.O_NONBLOCK | / | /' 'os.O_NOFOLLOW | os.O_NONBLOCK | os.O_NOCTTY' t_r7fifo
chk bounded   's/^    _cm_tp_bounded "\$top" "\$p" "\$out"; rc=\$?/    cat -- "$top\/$p" > "$out" 2>\/dev\/null; rc=$?/' '^    _cm_tp_bounded "\$top" "\$p" "\$out"; rc=' t_r7swapfifo
chk swapzero  's/fl | os.O_NOFOLLOW | os.O_NONBLOCK/fl | os.O_NONBLOCK/' 'fl | os.O_NOFOLLOW | os.O_NONBLOCK' t_r7swapzero
chk dirnofol  's/fl | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=d/fl | os.O_DIRECTORY, dir_fd=d/' 'os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=d' t_r7walk
chk sizecap   's/        if st.st_size > cap:/        if False:/' 'if st.st_size > cap:' t_r7big
chk lencap    's/        if len(buf) > cap:/        if False:/' 'if len(buf) > cap:' t_r7grow
chk gitto     's/^    local to=(); \[ -n "\$_CM_TP_TIMEOUT" \] \&\& to=.*/    local to=()/' 'local to=(); \[ -n "\$_CM_TP_TIMEOUT" \]' t_r7hang
# (no separate HUP/INT/TERM trap: measured, bash runs the EXIT trap when a TERM kills the subshell, so a TERM trap
#  is an equivalent mutant; t_r7clean below kills its removal through the EXIT-trap mutant)
chk exittrap  's/^        trap .* EXIT .*/        :/' '^        trap .* EXIT ' t_r7clean
chk depthres  's/    \[ "\$depth" -lt 3 \] || return 1/    [ "$depth" -lt 4 ] || return 1/' '\[ "\$depth" -lt 3 \] || return 1' t_d5
chk depthres2 's/    \[ "\$depth" -lt 3 \] || return 1/    [ "$depth" -lt 2 ] || return 1/' '\[ "\$depth" -lt 3 \] || return 1' t_d4
chk depthlev  's/        \[ "\$depth" -lt 3 \] || continue/        [ "$depth" -lt 4 ] || continue/' '\[ "\$depth" -lt 3 \] || continue' t_dl4
chk depthlev2 's/        \[ "\$depth" -lt 3 \] || continue/        [ "$depth" -lt 2 ] || continue/' '\[ "\$depth" -lt 3 \] || continue' t_dl3
t_r5a_marked() { scanned "$1" "$N0" && ! pline "$1" "$TMP/tpflag" 'submodules/v'; }
TF="$TMP/tpflag"; mkrepo "$TMP/rtf/v"; mkdir -p "$TF"; GIT -C "$TF" init -q .; manifest "$TF/helix-deps.yaml" submodules/v false; addsub "$TF" "$TMP/rtf/v" submodules/v "$GO"; commitall "$TF"
if ! pline "$GATE" "$TF" 'submodules/v'; then ok "manifest third_party: false does not prune"; else bad "third_party: false pruned"; fi
chk tpflag   's/\[ "\$tpf" = 1 \] || continue/:/' '\[ "\$tpf" = 1 \] || continue' t_r5a_marked
mutg() { # $1=name $2=sed expr on the GATE copy: echoes the mutated gate path
    local D="$TMP/mg_$1"; mkdir -p "$D/gates" "$D/lib" "$D/deps_manifest"
    cp "$HERE/cm_killpg_pgid_guard.sh" "$D/gates/"; cp "$HERE"/../lib/*.sh "$HERE"/../lib/*.list "$D/lib/" 2>/dev/null; cp "$HERE"/../deps_manifest/*.* "$D/deps_manifest/"
    sed -i "$2" "$D/gates/cm_killpg_pgid_guard.sh"; echo "$D/gates/cm_killpg_pgid_guard.sh"
}
SH="$(mutg shift 's/--window) \[ \$# -ge 2 \] || { echo "\${GATE}: \$1 requires a value" >\&2; exit 2; }; /--window) /')"
if grep -q -- '--window) \[ \$# -ge 2' "$SH"; then bad "shift mutant did not apply"; elif t_f5 "$SH"; then bad "mutant shift survived (--window last arg not detected)"; else ok "mutant shift caught (--window as last argument)"; fi

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
cp "$G" "$BM/gates/"; cp "$HERE"/../lib/*.sh "$BM/lib/"; cp "$HERE"/../deps_manifest/*.* "$BM/deps_manifest/"
if grep -q 'while (match(txt, /' "$BM/gates/cm_killpg_pgid_guard.sh"; then
    sed -i 's/while (match(txt, \/\\\$\\{(\[A-Za-z_\]/while (0 \&\& match(txt, \/\\$\\{([A-Za-z_]/' "$BM/gates/cm_killpg_pgid_guard.sh"
    if grep -q 'while (0 &&' "$BM/gates/cm_killpg_pgid_guard.sh"; then
        if bash "$BM/gates/cm_killpg_pgid_guard.sh" --root "$BR/ok.sh" --quiet >/dev/null 2>&1; then bad "brace-strip mutant still passes guarded braced case"
        else ok "mutant (brace strip disabled) FAILs the guarded braced case: test is load-bearing"; fi
    else bad "brace mutation did not apply"; fi
else bad "brace mutation anchor absent"; fi
[ "$rc" -eq 0 ] && echo "SCOPE TEST PASS" || echo "SCOPE TEST FAIL"
exit "$rc"
