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
    printf '%b' "$BADPY" > "$1/${2:-bad.py}"; GIT -C "$1" add -A >/dev/null; GIT -C "$1" commit -q -m i || { bad "fixture: commit failed ($1)"; return 1; }
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
    local R; R="$TMP/rem_$(basename "$1")"; mkrepo "$R/vend" && mkrepo "$R/mine" && mkrepo "$R/url" || return 1
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
addsub "$N3" "$TMP/rn/a" submodules/a "$OWN" && commitall "$N3"; rm -rf "${N3:?}/submodules/a"; mkdir -p "$N3/submodules/a/submodules/b"; printf '%b' "$BADPY" > "$N3/submodules/a/submodules/b/bad.py"
if scanned "$GATE" "$N3" && ! pline "$GATE" "$N3" 'submodules/a/submodules/b'; then ok "N3: nested path under an unpopulated parent is not pruned (plain dir scanned)"; else bad "N3: nested path pruned through an unpopulated parent"; fi
# N4: root manifest names a nested path that is NOT a gitlink of the populated parent -> scanned
N4="$TMP/nest4"; mknest "$N4" "$TMP/rn/a" submodules/a/a_clean.py
if ! pline "$GATE" "$N4" 'submodules/a/a_clean'; then ok "N4: nested manifest path that is a plain file of the parent is not pruned"; else bad "N4: non-gitlink nested path pruned"; fi

# P1: dir `src` whose first inner entry is a gitlink; manifest marks `src` third-party -> src/main.py must stay scanned
P1="$TMP/p1"; mkrepo "$TMP/rp1/inner" ; mkdir -p "$P1/src"; GIT -C "$P1" init -q .
manifest "$P1/helix-deps.yaml" src true; printf '%b' "$BADPY" > "$P1/src/main.py"
addsub "$P1" "$TMP/rp1/inner" src/aaa "$GO"; commitall "$P1"
if scanned "$GATE" "$P1"; then ok "P1: directory whose first inner entry is a gitlink is NOT pruned (exact match) -> FAIL on first-party call"; else bad "P1: first-party src/ hidden by a prefix-listing gitlink"; fi
# P2: gate root is a subdirectory of a repo (no .git at the root); hostile manifest there must not hide src
P2="$TMP/p2"; mkdir -p "$P2/sub/src"; GIT -C "$P2" init -q .; manifest "$P2/sub/helix-deps.yaml" src true
printf '%b' "$BADPY" > "$P2/sub/src/bad.py"; commitall "$P2"
if scanned "$GATE" "$P2/sub"; then ok "P2: subdirectory gate root with hostile manifest is still scanned"; else bad "P2: subdirectory root hid first-party code"; fi
# P2 golden-FALSE: a REAL recorded, manifest-marked gitlink under a subdirectory root is pruned, path relative to the gate root
mkrepo "$TMP/rp2/v"; P2B="$TMP/p2b"; mkdir -p "$P2B/sub"; GIT -C "$P2B" init -q .; printf "def f():\n    return 1\n" > "$P2B/sub/f.py"
manifest "$P2B/sub/helix-deps.yaml" submodules/v true; addsub "$P2B" "$TMP/rp2/v" sub/submodules/v "$GO"; commitall "$P2B"
if pruned "$GATE" "$P2B/sub" 'submodules/v'; then ok "P2: real marked gitlink under a subdirectory root pruned (root-relative)"; else bad "P2 golden-FALSE: not pruned"; fi
# P3: .gitmodules entry (and manifest) but NO gitlink -> not recorded
P3="$TMP/p3"; mkdir -p "$P3/src"; GIT -C "$P3" init -q .; manifest "$P3/helix-deps.yaml" src true
printf '%b' "$BADPY" > "$P3/src/bad.py"; printf '[submodule "src"]\n\tpath = src\n\turl = %s\n' "$GO" > "$P3/.gitmodules"; commitall "$P3"
if scanned "$GATE" "$P3"; then ok "P3: .gitmodules entry without a gitlink is not recorded -> scanned"; else bad "P3: gitmodules-only entry hid first-party code"; fi
# P4: no git metadata at all -> fail closed, manifest never prunes
P4="$TMP/p4"; mkdir -p "$P4/src"; manifest "$P4/helix-deps.yaml" src true; printf '%b' "$BADPY" > "$P4/src/bad.py"
o4="$(bash "$GATE" --root "$P4" 2>&1)"; r4=$?
if [ "$r4" -eq 1 ] && grep -q 'no usable git metadata' <<<"$o4"; then ok "P4: no git metadata -> fail closed (scanned, stated on stderr)"; else bad "P4: exported tree hid first-party code (rc=$r4)"; fi
# hostile manifest with git present and no gitlink; prefix collision
H="$TMP/hostile"; mkdir -p "$H/src"; GIT -C "$H" init -q .; manifest "$H/helix-deps.yaml" src true; printf '%b' "$BADPY" > "$H/src/bad.py"; commitall "$H"
if scanned "$GATE" "$H"; then ok "hostile manifest (path: src, not a gitlink) still scanned -> FAIL"; else bad "hostile manifest hid first-party src/"; fi
P="$TMP/pc"; mkA "$P"; mkdir -p "$P/submodules/vend-bar"; printf '%b' "$BADPY" > "$P/submodules/vend-bar/bad.py"
if grep -q 'submodules/vend-bar/bad.py' <<<"$(gout "$GATE" --root "$P")"; then ok "vend does not prune its prefix sibling vend-bar"; else bad "vend pruned vend-bar"; fi
# spaces / newline / symlink components are never pruned (dropped -> scanned)
SP="$TMP/sp"; mkrepo "$TMP/rsp/s"; mkdir -p "$SP"; GIT -C "$SP" init -q .; manifest2 "$SP/helix-deps.yaml" 'sp ace' true; addsub "$SP" "$TMP/rsp/s" 'sp ace' "$GO"; commitall "$SP"
o="$(bash "$GATE" --root "$SP" 2>&1)"
if ! grep -q 'PRUNED.*sp ace' <<<"$o" && grep -q 'sp ace/bad.py' <<<"$o"; then ok "marked gitlink path with a space is not pruned (scan more)"; else bad "space path pruned"; fi
NL="$TMP/nl"; mkdir -p "$NL/src"; GIT -C "$NL" init -q .; printf 'schema_version: 1\ndeps:\n  - name: x\n    path: "src\\nx"\n    ssh_url: git@example.invalid:o/x.git\n    ref: abc\n    why: "x"\n    layout: grouped\n    third_party: true\n    licence: MIT\n' > "$NL/helix-deps.yaml"
printf '%b' "$BADPY" > "$NL/src/bad.py"; commitall "$NL"
if scanned "$GATE" "$NL" && ! grep -q 'PRUNED.*src' <<<"$(gout "$GATE" --root "$NL")"; then ok "newline in a manifest path is dropped, not pruned"; else bad "newline path handling wrong"; fi
SY="$TMP/sy"; mkA "$SY"; rm -rf "${SY:?}/submodules/vend"; mkdir -p "$SY/realdir"; printf '%b' "$BADPY" > "$SY/realdir/bad.py"; ln -s ../realdir "$SY/submodules/vend"
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
    # shellcheck disable=SC2086 # the unquoted $v is split into separate arguments on purpose: it holds a flag and its value
    timeout 20 bash "$GATE" --root "$TR" $v >/dev/null 2>&1; r=$?
    if [ "$r" -eq 2 ]; then ok "R5: '$v' is an unknown argument (exit 2)"; else bad "R5: '$v' accepted (rc=$r)"; fi
done
# (c) the reviewer's round-4 attacker probes (r4probe p1/p2/p3 shapes) -- every one scans
PR="$TMP/probe"; mkdir -p "$PR"; GIT -C "$PR" init -q .; mkrepo "$TMP/rpr/a" && addsub "$PR" "$TMP/rpr/a" submodules/mine 'git@github.com:vasic-digital/x.git' && commitall "$PR"
for v in 'vasić-digital' '.' '..' '-' '-x' '_' 'a..b' '.git' 'github.com'; do
    mkdir -p "$PR/config"; printf '%s\n' "$v" > "$PR/config/own_orgs.list"
    for L in C.UTF-8 en_US.UTF-8; do
        o="$(LC_ALL=$L bash "$GATE" --root "$PR" 2>&1)"; r=$?
        if [ "$r" -eq 1 ] && ! grep -q 'PRUNED.*submodules' <<<"$o"; then ok "R5(c): own_orgs.list '$v' under $L -> scanned (rc 1)"; else bad "R5(c): '$v' $L rc=$r"; fi
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
    local d="$1" R i; R="$TMP/rch_$(basename "$1")"
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
rm -f "${Q1:?}/src"; mkdir -p "$Q1/src"; printf '%b' "$BADPY" > "$Q1/src/main.py"
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
rm -rf "${UP:?}/submodules/a"; mkdir -p "$UP/submodules/a/x"; manifest2 "$UP/submodules/a/helix-deps.yaml" x true; printf '%b' "$BADPY" > "$UP/submodules/a/x/bad.py"
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
r7reader() { # $1=gate $2=python prelude $3=top $4=rel $5=out FILE (opened here as the reader's out fd 3) $6=cap : rc of the reader
    local lib; lib="$(cd "$(dirname "$1")/../lib" && pwd -P)/third_party_prune.sh"; shift
    timeout -k 2 15 bash -c '. "$1"; python3 -I -B -c "$2
$_CM_TP_READ_PY" "$3" "$4" 3 "$6" 3>"$5"' _ "$lib" "$@" 2>/dev/null
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

# ── R8 (review 11.4.276 follow-ups r3, H1 + H2) ──────────────────────────────────────────────────────────────────────
# H1 class: "a path string resolved more than once during one prune decision". Each level's directory is entered ONCE
# (cd -P; then pwd -P, before any git call, and git's toplevel must both equal the expected canonical path), every later
# git / reader / hash call works on that cwd with the git dir resolved once, and the level's result is used only when the
# path still names the pinned directory afterwards. A `git` shim swaps a directory at one resolution point:
#   R (manifest marks submodules/a/submodules/w true) has the populated gitlink submodules/a = A;
#   A marks v false and w true, and records v but NOT w; B / Bm (attacker repositories) mark v and w true and record both.
# A bad prune is submodules/a/submodules/v (A says false) or submodules/a/submodules/w (not a gitlink of A).
mkr8() { # $1=dir $2=A's mark for v
    local Z="$1" X
    mkrepo "$Z/vsrc" || return 1
    for X in A B Bm Rb; do
        mkdir -p "$Z/$X"; GIT -C "$Z/$X" init -q . || return 1
        case "$X" in
            A)  manifest2 "$Z/$X/helix-deps.yaml" submodules/v "$2" submodules/w true ;;
            Rb) manifest2 "$Z/$X/helix-deps.yaml" submodules/x true ;;
            *)  manifest2 "$Z/$X/helix-deps.yaml" submodules/v true submodules/w true ;;
        esac
        case "$X" in
            Rb) addsub "$Z/$X" "$Z/vsrc" submodules/x "$GO" || return 1 ;;
            A)  addsub "$Z/$X" "$Z/vsrc" submodules/v "$GO" || return 1 ;;
            *)  addsub "$Z/$X" "$Z/vsrc" submodules/v "$GO" && addsub "$Z/$X" "$Z/vsrc" submodules/w "$GO" || return 1 ;;
        esac
        printf "def f():\n    return 1\n" > "$Z/$X/f.py"; commitall "$Z/$X"
    done
    # Bm also records an (unpopulated, empty) gitlink z: the descent into it is the last git call of the Bm level
    GIT -C "$Z/Bm" update-index --add --cacheinfo "160000,$(GIT -C "$Z/vsrc" rev-parse HEAD),submodules/z" && commitall "$Z/Bm"; mkdir -p "$Z/Bm/submodules/z"
    mkdir -p "$Z/R"; GIT -C "$Z/R" init -q .; printf "def f():\n    return 1\n" > "$Z/R/f.py"; manifest2 "$Z/R/helix-deps.yaml" submodules/a/submodules/w true
    addsub "$Z/R" "$Z/A" submodules/a "$OWN" && commitall "$Z/R" || return 1
    cp -- "$Z/R/submodules/a/.git" "$Z/dotgit.save"; cp -- "$Z/R/submodules/a/helix-deps.yaml" "$Z/man.save"
    # Bc: a foreign clone of A at the RECORDED commit (embedded .git) whose index stages marks v and w true and records w;
    # it passes the recorded-checkout check, so only the post-decision identity check can refuse it
    GIT clone -q "file://$Z/A" "$Z/Bc" || return 1; : > "$Z/Bc/.bcmark"
    manifest2 "$Z/Bc/helix-deps.yaml" submodules/v true submodules/w true
    GIT -C "$Z/Bc" update-index --add --cacheinfo "160000,$(GIT -C "$Z/vsrc" rev-parse HEAD),submodules/w" && GIT -C "$Z/Bc" add helix-deps.yaml || return 1
    [ "$(GIT -C "$Z/Bc" rev-parse HEAD)" = "$(GIT -C "$Z/R" rev-parse :submodules/a)" ] || return 1
}
Z8="$TMP/r8"; mkr8 "$Z8" false || bad "R8 fixture: could not be built"
Z8T="$TMP/r8t"; mkr8 "$Z8T" true || bad "R8 fixture (golden-FALSE): could not be built"
Z8E="$TMP/r8e"; mkr8 "$Z8E" false || bad "R8 fixture (embedded): could not be built"
rm -f -- "$Z8E/R/submodules/a/.git" "$Z8E/dotgit.save"; mv -- "$Z8E/R/.git/modules/submodules/a" "$Z8E/R/submodules/a/.git"; GIT config -f "$Z8E/R/submodules/a/.git/config" --unset core.worktree
[ -d "$Z8E/R/submodules/a/.git" ] && [ "$(GIT -C "$Z8E/R/submodules/a" rev-parse --absolute-git-dir)" = "$Z8E/R/submodules/a/.git" ] || bad "R8 fixture (embedded): A's .git is not embedded"
mkshim8() { # $1=shim dir $2=event rootrev|rootlist|pin|entry|hash|glcheck|none $3=pre|post $4=action $5=restore next|never|z $6=tree
    mkdir -p "$1"; rm -rf -- "${1:?}/flag" "${1:?}/restored"
    {   printf '#!/bin/bash\nEV=%q; WHEN=%q; ACT=%q; RST=%q; Z=%q; S=%q; REAL=%q\n' "$2" "$3" "$4" "$5" "$6" "$1" "$R7REALGIT"
        cat <<'SH'
A="$Z/R/submodules/a"; H="$Z/R/submodules/.hold"; tgt="$(pwd -P)"; prev=""
for x in "$@"; do [ "$prev" = -C ] && tgt="$(cd -- "$x" 2>/dev/null && pwd -P || printf '%s' "$x")"; prev="$x"; done   # -C . resolves to the real dir
a=" $* "; hit=""
case "$EV" in
    rootrev)  [ "$tgt" = "$Z/R" ] && case "$a" in *" rev-parse "*) case "$a" in *absolute-git-dir*) ;; *) hit=1 ;; esac ;; esac ;;
    rootlist) [ "$tgt" = "$Z/R" ] && case "$a" in *" ls-files "*) case "$a" in *" -- "*) ;; *) hit=1 ;; esac ;; esac ;;
    pin)      [ "$tgt" = "$A" ] && case "$a" in *" rev-parse "*) hit=1 ;; esac ;;
    entry)    [ "$tgt" = "$A" ] && case "$a" in *":(literal)helix-deps.yaml"*) hit=1 ;; esac ;;
    hash)     [ "$tgt" = "$A" ] && case "$a" in *" hash-object "*) hit=1 ;; esac ;;
    glcheck)  [ "$tgt" = "$A" ] && case "$a" in *":(literal)submodules/w"*) hit=1 ;; esac ;;
esac
swap() {
    case "$ACT" in
        sym)      mv -- "$A" "$H" && ln -s -- "$Z/B" "$A" ;;
        sym2ren)  mv -- "$A" "$H" && ln -s -- "$Z/Bm" "$A" ;;
        ren)      mv -- "$A" "$H" && mv -- "$Z/Bm" "$A" ;;
        renc)     mv -- "$A" "$H" && mv -- "$Z/Bc" "$A" ;;
        gitf)     printf 'gitdir: %s\n' "$Z/B/.git" > "$A/.git" && cp -- "$Z/B/helix-deps.yaml" "$A/helix-deps.yaml" ;;
        rsym2ren) mv -- "$Z/R" "$Z/R.hold" && ln -s -- "$Z/Rb" "$Z/R" ;;
        rplain)   mv -- "$Z/R" "$Z/R.hold" && mkdir -- "$Z/R" && : > "$Z/R/.plainmark" && cp -- "$Z/helix-deps.yaml" "$Z/R/helix-deps.yaml" ;;
        symb)     mv -- "$A" "$H" && ln -s -- "$Z/B" "$A" && cp -- "$Z/B/helix-deps.yaml" "$H/helix-deps.yaml" ;;
        gdswap)   mv -- "$A/.git" "$Z/dotgit.aside" && cp -a -- "$Z/B/.git" "$A/.git" && cp -- "$Z/B/helix-deps.yaml" "$A/helix-deps.yaml" ;;
    esac
}
restore() {
    case "$ACT" in
        sym)      rm -f -- "$A" && mv -- "$H" "$A" ;;
        sym2ren)  rm -f -- "$A" && mv -- "$Z/Bm" "$A" ;;
        ren)      mv -- "$A" "$Z/Bm" && mv -- "$H" "$A" ;;
        renc)     mv -- "$A" "$Z/Bc" && mv -- "$H" "$A" ;;
        gitf)     cp -- "$Z/dotgit.save" "$A/.git" && cp -- "$Z/man.save" "$A/helix-deps.yaml" ;;
        rsym2ren) rm -f -- "$Z/R" && mv -- "$Z/Rb" "$Z/R" ;;
        symb)     rm -f -- "$A" && mv -- "$H" "$A" ;;
    esac
}
if [ -e "$S/flag" ] && [ ! -e "$S/restored" ]; then
    case "$RST" in
        next) mkdir -- "$S/restored" 2>/dev/null && restore ;;
        z) [ "$tgt" = "$A/submodules/z" ] && case "$a" in *" rev-parse "*) mkdir -- "$S/restored" 2>/dev/null && restore ;; esac ;;
        hash) [ "$tgt" = "$A" ] && case "$a" in *" hash-object "*) mkdir -- "$S/restored" 2>/dev/null && restore ;; esac ;;
    esac
fi
if [ -n "$hit" ] && [ "$WHEN" = pre ] && mkdir -- "$S/flag" 2>/dev/null; then swap; fi
"$REAL" "$@"; rc=$?
if [ "$RST" = glpost ] && [ -e "$S/flag" ] && [ "$tgt" = "$A" ]; then   # restore right AFTER the last listing of the level
    case "$a" in *":(literal)submodules/"*) mkdir -- "$S/restored" 2>/dev/null && restore ;; esac
fi
if [ -n "$hit" ] && [ "$WHEN" = post ] && mkdir -- "$S/flag" 2>/dev/null; then swap; fi
exit $rc
SH
    } > "$1/git"
    chmod +x "$1/git"
}
r8fix() { # $1=tree : back to the canonical layout (whatever the run left), then prove it
    local Z="$1" A="$1/R/submodules/a" H="$1/R/submodules/.hold"
    if [ -L "$Z/R" ]; then rm -f -- "$Z/R"; fi
    if [ -e "$Z/R/.plainmark" ]; then rm -rf -- "${Z:?}/R"; fi
    if [ -d "$Z/R.hold" ]; then [ -d "$Z/R" ] && mv -- "$Z/R" "$Z/Rb"; mv -- "$Z/R.hold" "$Z/R"; fi
    if [ -L "$A" ]; then rm -f -- "$A"; fi
    if [ -d "$H" ]; then if [ -d "$A" ]; then if [ -e "$A/.bcmark" ]; then mv -- "$A" "$Z/Bc"; else mv -- "$A" "$Z/Bm"; fi; fi; mv -- "$H" "$A"; fi
    if [ -d "$A/.git" ] && [ -f "$Z/dotgit.save" ]; then rm -rf -- "${A:?}/.git"; fi; rm -f -- "${Z:?}/dotgit.aside"
    if [ -f "$Z/dotgit.save" ]; then cp -- "$Z/dotgit.save" "$A/.git"; fi; cp -- "$Z/man.save" "$A/helix-deps.yaml"
    [ -d "$Z/R" ] && [ ! -L "$Z/R" ] && [ -d "$A" ] && [ ! -L "$A" ] && [ -d "$Z/Bm/.git" ] && [ -d "$Z/Rb/.git" ] && [ -d "$Z/Bc/.git" ] && [ ! -e "$A/.bcmark" ] && [ -f "$A/f.py" ]
}
r8run() { # $1=gate $2=tree $3=event $4=when $5=action $6=restore : prune set on stdout; stderr in $TMP/r7err
    local S="$TMP/r8shim"; r8fix "$2" || { bad "R8 fixture: tree not restorable"; return 1; }
    mkshim8 "$S" "$3" "$4" "$5" "$6" "$2"
    tplib "$1" "$2/R" "$S"; local r=$?
    [ "$3" = none ] || [ -d "$S/flag" ] || echo "R8NEEDLE: the $3/$5 swap never fired" >> "$TMP/r8needle"
    r8fix "$2" || echo "R8NEEDLE: tree not restored after $3/$5" >> "$TMP/r8needle"
    return $r
}
r8clean() { local o r; o="$(r8run "$@")"; r=$?; [ "$r" -eq 0 ] && grep -qx third_party <<<"$o" && ! grep -q '^submodules/a/submodules/[vw]$' <<<"$o" && ! grep -q '^submodules/x$' <<<"$o"; }
: > "$TMP/r8needle"
# baseline + golden-FALSE: no swap -> nothing of A pruned; A marking v true -> exactly submodules/a/submodules/v pruned
o8="$(r8run "$GATE" "$Z8" none pre sym never)"
if grep -qx third_party <<<"$o8" && ! grep -q '^submodules/a/submodules/' <<<"$o8"; then ok "R8 baseline: A marks v false, w is not A's gitlink -> nothing of A pruned"; else bad "R8 baseline wrong: $(tr '\n' ' ' <<<"$o8")"; fi
o8="$(r8run "$GATE" "$Z8T" none pre sym never)"
if grep -qx 'submodules/a/submodules/v' <<<"$o8" && ! grep -qx 'submodules/a/submodules/w' <<<"$o8"; then ok "R8 golden-FALSE: A marks v true -> submodules/a/submodules/v pruned (the fixture can see a prune)"; else bad "R8 golden-FALSE: A's legitimate mark not honoured: $(tr '\n' ' ' <<<"$o8")"; fi
o8="$(r8run "$GATE" "$Z8T" entry pre sym next)"
if grep -qx 'submodules/a/submodules/v' <<<"$o8"; then ok "R8 golden-FALSE: an A-B-A swap around the index lookup does not suppress A's legitimate prune"; else bad "R8 golden-FALSE: A-B-A swap suppressed a legitimate prune: $(tr '\n' ' ' <<<"$o8")"; fi
# one fixture per resolution point (each would let B's index or bytes decide for A without the pin)
t_r8rootpin() { r8clean "$1" "$Z8" rootrev post rsym2ren next; }   # root swapped for a symlink, B moved in before git's check
t_r8pinpwd()  { r8clean "$1" "$Z8" rootlist pre sym2ren next; }   # nested top a symlink at the cd, B moved in before git's check
t_r8pinpost() { r8clean "$1" "$Z8" pin post sym never; }           # swapped right after the pin
t_r8entry()   { r8clean "$1" "$Z8" entry pre sym next; }           # swapped around the index lookup and the read
t_r8hash()    { r8clean "$1" "$Z8" hash pre sym next; }            # swapped at the hash
t_r8glcheck() { r8clean "$1" "$Z8" glcheck pre sym next; }         # swapped around the gitlink check (root deep mark + A's own)
t_r8gitf()    { r8clean "$1" "$Z8" entry pre gitf next; }          # A's .git file + bytes pointed at B around the index lookup
t_r8ren()     { r8clean "$1" "$Z8E" rootlist pre renc glpost && [ -d "$TMP/r8shim/restored" ]; }   # EMBEDDED layout (r4: absorbed refuses at the pin): a clone at the recorded commit renamed INTO the path for the decision, A put back before the identity check
for t in rootpin:"root swapped between git's toplevel and the cd (B real at the path before git's check)" \
         pinpwd:"nested top is a symlink at the cd (B real at the path before git's check)" \
         pinpost:"nested top swapped right after the pin" entry:"nested top swapped around the index lookup and the read" \
         hash:"nested top swapped at hash-object" glcheck:"nested top swapped around the gitlink check" \
         gitf:"A's .git file and manifest pointed at B around the index lookup" \
         ren:"embedded layout: a clone of A at the recorded commit (foreign index) renamed into the path for the decision, A restored before the identity check"; do
    n="${t%%:*}"; l="${t#*:}"
    if "t_r8$n" "$GATE"; then ok "R8: $l -> no prune of A's v / non-gitlink w (pinned)"; else bad "R8: $l -> BAD prune or error: $(head -c 300 "$TMP/r7err" | tr '\n' ' ')"; fi
done
# the git dir is pinned as an fd too: A with an EMBEDDED .git directory (its git dir lives under the swapped path); A-B-A
# swap around the index lookup with B's bytes written into A's worktree. A git dir named by path would read B's index.
t_r8gdfd() { r8clean "$1" "$Z8E" entry pre symb next; }
if t_r8gdfd "$GATE"; then ok "R8: embedded git dir under the swapped path, A-B-A around the index lookup -> no prune (git dir pinned as an fd)"; else bad "R8: embedded git dir followed the swap -> BAD prune: $(head -c 300 "$TMP/r7err" | tr '\n' ' ')"; fi
o8="$(r8run "$GATE" "$Z8E" none pre sym never)"
if grep -qx third_party <<<"$o8" && ! grep -q '^submodules/a/submodules/' <<<"$o8"; then ok "R8 (embedded) baseline: nothing of A pruned"; else bad "R8 (embedded) baseline wrong: $(tr '\n' ' ' <<<"$o8")"; fi
# a nested level must be the checkout git made for the parent's gitlink: a foreign repository renamed INTO the path and
# held there for the whole decision (no restore) is refused; the two ways a real checkout is recognised each keep a
# legitimate prune (absorbed git dir with HEAD moved past the recorded commit; embedded .git at the recorded commit).
t_r8renall() { r8clean "$1" "$Z8" rootlist pre ren never; }
if t_r8renall "$GATE"; then ok "R8: foreign repository renamed into the path for the whole decision -> no prune (not the recorded checkout)"; else bad "R8: a foreign repository held at the path was taken as the level -> BAD prune: $(head -c 300 "$TMP/r7err" | tr '\n' ' ')"; fi
# the root's toplevel check: the tree container is itself a repository Q (manifest marks x true, records gitlink x); a
# plain directory holding Q's manifest bytes replaces the root after git's first toplevel answer. Its toplevel is Q, not
# the root: refused. Without the toplevel check Q's index (x a gitlink) would decide for the root.
Z8Q="$TMP/r8q"; mkr8 "$Z8Q" false || bad "R8 fixture (toplevel): could not be built"
GIT -C "$Z8Q" init -q . && manifest2 "$Z8Q/helix-deps.yaml" submodules/x true && GIT -C "$Z8Q" add helix-deps.yaml &&
    GIT -C "$Z8Q" update-index --add --cacheinfo "160000,$(GIT -C "$Z8Q/vsrc" rev-parse HEAD),submodules/x" && GIT -C "$Z8Q" commit -q -m q || bad "R8 fixture (toplevel): Q not built"
t_r8roottop() { r8clean "$1" "$Z8Q" rootrev post rplain never; }
if t_r8roottop "$GATE"; then ok "R8: root replaced by a plain directory inside another repository -> no prune (toplevel is not the root)"; else bad "R8: a non-top directory was pinned as the root -> BAD prune: $(head -c 300 "$TMP/r7err" | tr '\n' ' ')"; fi
Z8A="$TMP/r8adv"; mkr8 "$Z8A" true || bad "R8 fixture (advanced): could not be built"
echo adv > "$Z8A/R/submodules/a/adv.txt"; GIT -C "$Z8A/R/submodules/a" add adv.txt; GIT -C "$Z8A/R/submodules/a" commit -q -m adv
[ "$(GIT -C "$Z8A/R/submodules/a" rev-parse HEAD)" != "$(GIT -C "$Z8A/R" rev-parse :submodules/a)" ] || bad "R8 fixture (advanced): HEAD did not move past the recorded commit"
t_r8adv() { local o; o="$(r8run "$1" "$Z8A" none pre sym never)"; grep -qx 'submodules/a/submodules/v' <<<"$o"; }
if t_r8adv "$GATE"; then ok "R8 golden-FALSE: absorbed submodule with HEAD past the recorded commit keeps its legitimate prune"; else bad "R8 golden-FALSE: advanced absorbed submodule lost its prune: $(head -c 300 "$TMP/r7err" | tr '\n' ' ')"; fi
Z8ET="$TMP/r8et"; mkr8 "$Z8ET" true || bad "R8 fixture (embedded, true): could not be built"
rm -f -- "$Z8ET/R/submodules/a/.git" "$Z8ET/dotgit.save"; mv -- "$Z8ET/R/.git/modules/submodules/a" "$Z8ET/R/submodules/a/.git"; GIT config -f "$Z8ET/R/submodules/a/.git/config" --unset core.worktree
[ ! -e "$Z8ET/R/.git/modules/submodules/a" ] && [ ! -e "$Z8E/R/.git/modules/submodules/a" ] || bad "R8 fixture (embedded): a module git dir is left behind (git's embedded layout has none)"
t_r8embT() { local o; o="$(r8run "$1" "$Z8ET" none pre sym never)"; grep -qx 'submodules/a/submodules/v' <<<"$o"; }
if t_r8embT "$GATE"; then ok "R8 golden-FALSE: embedded .git at the recorded commit keeps its legitimate prune"; else bad "R8 golden-FALSE: embedded submodule at the recorded commit lost its prune: $(head -c 300 "$TMP/r7err" | tr '\n' ' ')"; fi
# K1 (review follow-ups r4): in the ABSORBED layout (what `git submodule add` makes) a clone at the recorded commit held at
# the path for the WHOLE decision is refused: the parent's modules/<path> exists, so the level's git dir must be it.
t_r8renheld() { r8clean "$1" "$Z8" rootlist pre renc never; }
if t_r8renheld "$GATE"; then ok "R8 (K1): a recorded-commit clone renamed into an absorbed-layout path and held for the whole decision -> no prune (module git dir required)"; else bad "R8 (K1): a held recorded-commit clone was taken as the absorbed level -> BAD prune: $(head -c 300 "$TMP/r7err" | tr '\n' ' ')"; fi
# O1 (review follow-ups r4): A's .git swapped for B's git dir and B's bytes AFTER the pin, before the manifest entry
# lookup, never restored: only the pinned git-dir fd keeps A's index deciding (an entry looked up by name reads B's).
t_r8gdlate() { r8clean "$1" "$Z8" entry pre gdswap never; }
if t_r8gdlate "$GATE"; then ok "R8: .git and manifest swapped after the pin (held) -> no prune (the entry is read through the pinned git dir)"; else bad "R8: a late .git swap decided for A -> BAD prune: $(head -c 300 "$TMP/r7err" | tr '\n' ' ')"; fi
# stated limit, printed (not asserted): EMBEDDED layout (no module git dir), a clone at the recorded commit held for the
# whole decision is the level (its git dir really is in the worktree)
o8="$(r8run "$GATE" "$Z8E" rootlist pre renc never)"; echo "NOTE: R8 stated limit (embedded layout, recorded-commit clone held for the whole decision) prune set: $(tr '\n' ' ' <<<"$o8")"
if [ -s "$TMP/r8needle" ]; then bad "R8 control needle: $(sort -u "$TMP/r8needle" | tr '\n' ' ')"; else ok "R8 control needle: every swap fired and every tree was restored"; fi
# ── R9 (review follow-ups r4, K1 class: "a foreign directory made to look like the recorded checkout") ──────────────
# Each member is HELD at the path for the whole call (no race): a static rename / rewrite, the call, then the canonical
# tree is put back and proved. A bad prune is submodules/a/submodules/v (A marks v false) or .../w (not A's gitlink).
r9held() { # $1=gate $2=tree $3=member : prune set on stdout (stderr in $TMP/r7err); the tree is restored
    local Z="$2" A="$2/R/submodules/a" o r
    r8fix "$Z" || { bad "R9 fixture: tree not restorable"; return 1; }
    case "$3" in
        gitfc) printf 'gitdir: %s\n' "$Z/Bc/.git" > "$A/.git"; cp -- "$Z/Bc/helix-deps.yaml" "$A/helix-deps.yaml" ;;   # .git file -> a recorded-commit clone
        wt)    mv -- "$A" "$Z/R/submodules/.hold" && mv -- "$Z/Bw" "$A" ;;   # a linked worktree of A's own module dir (commondir)
        other) printf 'gitdir: %s\n' "$Z/R/.git/modules/submodules/a" > "$A/.git"; cp -- "$Z/Bm/helix-deps.yaml" "$A/helix-deps.yaml" ;;   # .git file -> ANOTHER submodule's module dir
        held)  mv -- "$A" "$Z/R/submodules/.hold" && mv -- "$Z/Bc" "$A" ;;
    esac
    o="$(tplib "$1" "$Z/R")"; r=$?
    case "$3" in
        wt)   mv -- "$A" "$Z/Bw" && mv -- "$Z/R/submodules/.hold" "$A" ;;
        held) mv -- "$A" "$Z/Bc" && mv -- "$Z/R/submodules/.hold" "$A" ;;
    esac
    r8fix "$Z" || bad "R9 fixture: tree not restored after $3"
    printf '%s\n' "$o"; return "$r"
}
r9clean() { local o r; o="$(r9held "$@")"; r=$?; [ "$r" -eq 0 ] && grep -qx third_party <<<"$o" && ! grep -q '^submodules/a/submodules/[vw]$' <<<"$o"; }
t_r9gitfc() { r9clean "$1" "$Z8" gitfc; }
if t_r9gitfc "$GATE"; then ok "R9: absorbed path whose .git file is aimed at a recorded-commit clone (held) -> no prune"; else bad "R9: .git file aimed at a recorded-commit clone was taken as the level -> BAD prune: $(head -c 300 "$TMP/r7err" | tr '\n' ' ')"; fi
# a linked worktree of A's own module git dir (git dir modules/submodules/a/worktrees/Bw, its own index), recorded commit,
# its manifest staged true and its index recording w: not the module git dir itself -> refused
Z9W="$TMP/r9w"; mkr8 "$Z9W" false || bad "R9 fixture (worktree): could not be built"
GIT -C "$Z9W/R/submodules/a" worktree add -q --detach "$Z9W/Bw" HEAD >/dev/null 2>&1 && manifest2 "$Z9W/Bw/helix-deps.yaml" submodules/v true submodules/w true &&
    GIT -C "$Z9W/Bw" add helix-deps.yaml && GIT -C "$Z9W/Bw" update-index --add --cacheinfo "160000,$(GIT -C "$Z9W/vsrc" rev-parse HEAD),submodules/w" || bad "R9 fixture (worktree): Bw not built"
[ -f "$Z9W/Bw/.git" ] && [ "$(GIT -C "$Z9W/Bw" rev-parse HEAD)" = "$(GIT -C "$Z9W/R" rev-parse :submodules/a)" ] || bad "R9 fixture (worktree): Bw is not a linked worktree at the recorded commit"
t_r9wt() { r9clean "$1" "$Z9W" wt; }
if t_r9wt "$GATE"; then ok "R9: a linked worktree of A's module dir at the recorded commit, held at the path -> no prune"; else bad "R9: a linked worktree was taken as the level -> BAD prune: $(head -c 300 "$TMP/r7err" | tr '\n' ' ')"; fi
# name != path (`git mv` of a submodule: its module dir stays modules/<old name>): the module dir is found by NAME through
# the parent's INDEX .gitmodules; golden-FALSE the real checkout keeps its prune, a held recorded-commit clone is refused
mkr9n() { # $1=dir $2=A's mark for v : R records submodules/a, name submodules/old; Bc = recorded-commit clone, marks v true
    local Z="$1"
    mkrepo "$Z/vsrc" || return 1
    mkdir -p "$Z/A" && GIT -C "$Z/A" init -q . && manifest2 "$Z/A/helix-deps.yaml" submodules/v "$2" && addsub "$Z/A" "$Z/vsrc" submodules/v "$GO" && commitall "$Z/A" || return 1
    mkdir -p "$Z/R" && GIT -C "$Z/R" init -q . && printf "def f():\n    return 1\n" > "$Z/R/f.py" && addsub "$Z/R" "$Z/A" submodules/old "$OWN" && commitall "$Z/R" || return 1
    GIT -C "$Z/R" mv submodules/old submodules/a && commitall "$Z/R" || return 1
    GIT clone -q "file://$Z/A" "$Z/Bc" && manifest2 "$Z/Bc/helix-deps.yaml" submodules/v true && GIT -C "$Z/Bc" add helix-deps.yaml || return 1
    [ -d "$Z/R/.git/modules/submodules/old" ] && [ ! -e "$Z/R/.git/modules/submodules/a" ] &&
        [ "$(GIT -C "$Z/R" config -f .gitmodules submodule.submodules/old.path)" = submodules/a ] &&
        [ "$(GIT -C "$Z/Bc" rev-parse HEAD)" = "$(GIT -C "$Z/R" rev-parse :submodules/a)" ]
}
Z9N="$TMP/r9n"; mkr9n "$Z9N" false || bad "R9 fixture (name != path): could not be built"
Z9NT="$TMP/r9nt"; mkr9n "$Z9NT" true || bad "R9 fixture (name != path, true): could not be built"
r9nheld() { # $1=gate $2=tree : Bc held at submodules/a for the whole call
    local Z="$2" o r; mv -- "$Z/R/submodules/a" "$Z/R/submodules/.hold" && mv -- "$Z/Bc" "$Z/R/submodules/a" || { bad "R9 fixture (name != path): swap failed"; return 1; }
    o="$(tplib "$1" "$Z/R")"; r=$?
    mv -- "$Z/R/submodules/a" "$Z/Bc" && mv -- "$Z/R/submodules/.hold" "$Z/R/submodules/a" || bad "R9 fixture (name != path): not restored"
    printf '%s\n' "$o"; return "$r"
}
t_r9nameT() { local o; o="$(tplib "$1" "$Z9NT/R")"; grep -qx 'submodules/a/submodules/v' <<<"$o"; }
t_r9name()  { local o r; o="$(r9nheld "$1" "$Z9N")"; r=$?; [ "$r" -eq 0 ] && grep -qx third_party <<<"$o" && ! grep -qx 'submodules/a/submodules/v' <<<"$o"; }
if t_r9nameT "$GATE"; then ok "R9 golden-FALSE: name != path (git mv), the real absorbed checkout keeps its legitimate prune"; else bad "R9 golden-FALSE: name != path lost its legitimate prune: $(head -c 300 "$TMP/r7err" | tr '\n' ' ')"; fi
if t_r9name "$GATE"; then ok "R9: name != path, a recorded-commit clone held at the path -> no prune (module dir found by name)"; else bad "R9: name != path, a held clone was taken as the level -> BAD prune: $(head -c 300 "$TMP/r7err" | tr '\n' ' ')"; fi
# NAME PRECEDENCE: a second submodule NAMED submodules/a (path submodules/z, = Bm: marks v and w true, records both) owns
# modules/submodules/a. A's path carries a .git file aimed at that module dir plus Bm's bytes: the recorded name of the
# path is submodules/old, so modules/<path> must not vouch for it.
Z9P="$TMP/r9p"; mkr9n "$Z9P" false || bad "R9 fixture (precedence): could not be built"
mkdir -p "$Z9P/Bm" && GIT -C "$Z9P/Bm" init -q . && manifest2 "$Z9P/Bm/helix-deps.yaml" submodules/v true submodules/w true &&
    addsub "$Z9P/Bm" "$Z9P/vsrc" submodules/v "$GO" && addsub "$Z9P/Bm" "$Z9P/vsrc" submodules/w "$GO" && commitall "$Z9P/Bm" &&
    GIT -C "$Z9P/R" submodule add -q --name submodules/a "file://$Z9P/Bm" submodules/z >/dev/null 2>&1 && commitall "$Z9P/R" &&
    [ "$(GIT -C "$Z9P/R/submodules/z" rev-parse --absolute-git-dir)" = "$Z9P/R/.git/modules/submodules/a" ] || bad "R9 fixture (precedence): second submodule not built"
cp -- "$Z9P/R/submodules/a/.git" "$Z9P/dotgit.save9"
t_r9prec() { local o r Z="$Z9P"
    printf 'gitdir: %s\n' "$Z/R/.git/modules/submodules/a" > "$Z/R/submodules/a/.git"; cp -- "$Z/Bm/helix-deps.yaml" "$Z/R/submodules/a/helix-deps.yaml"
    o="$(tplib "$1" "$Z/R")"; r=$?
    cp -- "$Z/dotgit.save9" "$Z/R/submodules/a/.git"; GIT -C "$Z/R/submodules/a" checkout -q -- helix-deps.yaml || bad "R9 fixture (precedence): not restored"
    [ "$r" -eq 0 ] && grep -qx third_party <<<"$o" && ! grep -q '^submodules/a/submodules/[vw]$' <<<"$o"; }
if t_r9prec "$GATE"; then ok "R9: a .git file aimed at the module dir of ANOTHER submodule named like the path -> no prune (the recorded name decides)"; else bad "R9: another submodule's module dir vouched for the path -> BAD prune: $(head -c 300 "$TMP/r7err" | tr '\n' ' ')"; fi
o9="$(tplib "$GATE" "$Z9P/R")"; if grep -qx third_party <<<"$o9" && ! grep -q '^submodules/a/' <<<"$o9"; then ok "R9 (precedence) baseline: restored tree, nothing of A pruned"; else bad "R9 (precedence) baseline wrong: $(tr '\n' ' ' <<<"$o9")"; fi
# held member of the static harness, as a control: the same rename the K1 shim fixture makes, without a shim
t_r9held() { r9clean "$1" "$Z8" held; }
if t_r9held "$GATE"; then ok "R9: recorded-commit clone held at the absorbed path, no shim -> no prune"; else bad "R9: held clone (static) -> BAD prune: $(head -c 300 "$TMP/r7err" | tr '\n' ' ')"; fi
# nit (review r4): without a directory-fd source the refusal names that cause
t_r9nofd() { tplib "$1" "$Z8T/R" "" '_CM_TP_FD=""' >/dev/null; grep -q 'no /proc/self/fd or /dev/fd' "$TMP/r7err"; }
if t_r9nofd "$GATE"; then ok "R9: no /proc/self/fd and no /dev/fd -> the refusal names the missing fd source"; else bad "R9: no-fd refusal does not name its cause: $(head -c 300 "$TMP/r7err" | tr '\n' ' ')"; fi
# pintop: an UNPOPULATED gitlink directory holding a copy of the root's own tracked manifest must not be read as a level
U8="$TMP/r8unpop"; mkrepo "$TMP/r8u/v" && mkrepo "$TMP/r8u/a"; mkdir -p "$U8"; GIT -C "$U8" init -q .; printf "def f():\n    return 1\n" > "$U8/f.py"
manifest "$U8/helix-deps.yaml" submodules/v true; addsub "$U8" "$TMP/r8u/v" submodules/v "$GO" && addsub "$U8" "$TMP/r8u/a" submodules/a "$OWN" && commitall "$U8"
rm -rf -- "${U8:?}/submodules/a"; mkdir -p "$U8/submodules/a"; cp -- "$U8/helix-deps.yaml" "$U8/submodules/a/helix-deps.yaml"
t_r8unpop() { local o; o="$(tplib "$1" "$U8")"; grep -qx submodules/v <<<"$o" && ! grep -q '^submodules/a/' <<<"$o"; }
if t_r8unpop "$GATE"; then ok "R8: an unpopulated gitlink dir holding a copy of the root manifest is not a level (only the root's v is pruned)"; else bad "R8: unpopulated dir read as a level: $(tplib "$GATE" "$U8" | tr '\n' ' ')"; fi
# snapshot custody: the snapshot has NO name while it is hashed and parsed (a writer that rewrites tp_manifest.*/m.* after
# the hash finds nothing). Index false, worktree false; the shim rewrites every m.* to a true manifest after hash-object.
R8SD="$TMP/r8snapd"; mkdir -p "$R8SD"
mkshim_snap() { # $1=shim dir $2=TMPDIR of the call $3=bytes to write
    mkdir -p "$1"; rm -f -- "$1/found" "$1/ran"
    { printf '#!/bin/bash\nTD=%q; SRC=%q; S=%q; REAL=%q\n' "$2" "$3" "$1" "$R7REALGIT"
      cat <<'SH'
"$REAL" "$@"; rc=$?
case " $* " in *" hash-object "*) : > "$S/ran"; for f in "$TD"/tp_manifest.*/m.*; do [ -f "$f" ] && cat -- "$SRC" > "$f" && echo "$f" >> "$S/found"; done ;; esac
exit $rc
SH
    } > "$1/git"; chmod +x "$1/git"
}
t_r8snapname() { r7reset "$R7A" "$TMP/r7_false.yaml"; rm -rf -- "${R8SD:?}"; mkdir -p "$R8SD"; mkshim_snap "$TMP/r8shimS" "$R8SD" "$TMP/r7_true.yaml"
    r7refused "$1" "$R7A" "$TMP/r8shimS" "TMPDIR='$R8SD'" && [ -e "$TMP/r8shimS/ran" ] && [ ! -s "$TMP/r8shimS/found" ]; }
if t_r8snapname "$GATE"; then ok "R8: the snapshot has no name while it is hashed and parsed (a rewrite of tp_manifest.*/m.* finds nothing; needle: the shim ran)"; else bad "R8: a named snapshot was rewritten between hash and parse (found: $(tr '\n' ' ' < "$TMP/r8shimS/found" 2>/dev/null))"; fi
# H2: two concurrent calls with ONE shared TMPDIR get two distinct private (0700) snapshot directories
R8RD="$TMP/r8ri"; R8H="$TMP/r8h2"; mkcust "$R8H" true || bad "R8 H2 fixture: could not be built"   # own tree: R7C is rewritten by the R7 snapshot tests
mkshim_ri() { # $1=shim dir $2=shared TMPDIR : at hash-object, wait (bounded) until 2 snapshot dirs exist, log them with modes
    mkdir -p "$1"; rm -f -- "$1/log"
    { printf '#!/bin/bash\nTD=%q; S=%q; REAL=%q\n' "$2" "$1" "$R7REALGIT"
      cat <<'SH'
case " $* " in *" hash-object "*)
    for i in $(seq 1 80); do n=0; for d in "$TD"/tp_manifest.*; do [ -d "$d" ] && n=$((n+1)); done; [ "$n" -ge 2 ] && break; sleep 0.1; done
    blk=""; for d in "$TD"/tp_manifest.*; do [ -d "$d" ] && blk="$blk$(stat -c %a -- "$d") $d"$'\n'; done
    printf '%s--\n' "$blk" >> "$S/log" ;;   # one write per block (O_APPEND, < PIPE_BUF): concurrent shims cannot interleave lines
esac
exec "$REAL" "$@"
SH
    } > "$1/git"; chmod +x "$1/git"
}
t_r8ri() { # $1=gate
    local lib p1 p2; lib="$(cd "$(dirname "$1")/../lib" && pwd -P)/third_party_prune.sh"
    rm -rf -- "${R8RD:?}"; mkdir -p "$R8RD"; mkshim_ri "$TMP/r8shimR" "$R8RD"
    timeout -k 2 20 env TMPDIR="$R8RD" PATH="$TMP/r8shimR:$PATH" bash -c '. "$1"; cm_third_party_prune_paths "$2"' _ "$lib" "$R8H" > "$TMP/r8ri1" 2>/dev/null & p1=$!
    timeout -k 2 20 env TMPDIR="$R8RD" PATH="$TMP/r8shimR:$PATH" bash -c '. "$1"; cm_third_party_prune_paths "$2"' _ "$lib" "$R8H" > "$TMP/r8ri2" 2>/dev/null & p2=$!
    wait "$p1"; wait "$p2"
    grep -qx submodules/v "$TMP/r8ri1" && grep -qx submodules/v "$TMP/r8ri2" || return 1
    awk 'BEGIN{ok=0} /^--$/ { if (n >= 2 && bad == 0) ok=1; n=0; bad=0; delete seen; next }
         { if ($1 != "700") bad=1; if (!($2 in seen)) { seen[$2]=1; n++ } } END { exit ok ? 0 : 1 }' "$TMP/r8shimR/log" || return 1
    [ -z "$(ls -A "$R8RD")" ]
}
if t_r8ri "$GATE"; then ok "R8 (H2): two concurrent calls on one shared TMPDIR hold two distinct 0700 snapshot dirs at once, both removed"; else bad "R8 (H2): snapshot dirs shared, not private, or left behind: $(tr '\n' ' ' < "$TMP/r8shimR/log" 2>/dev/null | head -c 300)"; fi
# H2: a DIRECT caller's own EXIT trap and cwd survive an API call (the prune runs in its own subshell)
t_r8trap() { # $1=gate
    local lib M="$TMP/r8trap"; lib="$(cd "$(dirname "$1")/../lib" && pwd -P)/third_party_prune.sh"
    rm -rf -- "${M:?}"; mkdir -p "$M"
    ( cd "$M" && timeout -k 2 20 bash -c 'trap "echo ran > \"$3/ran\"" EXIT; . "$1"; cm_third_party_prune_paths "$2" > "$3/out"; trap -p EXIT > "$3/trap"; pwd -P > "$3/pwd"' _ "$lib" "$R8H" "$M" ) >/dev/null 2>&1
    grep -q 'echo ran' "$M/trap" && [ "$(cat "$M/ran" 2>/dev/null)" = ran ] && [ "$(cat "$M/pwd")" = "$M" ] && grep -qx submodules/v "$M/out"
}
if t_r8trap "$GATE"; then ok "R8 (H2): a direct caller's EXIT trap is kept and runs, and its cwd is unchanged (needle: the call pruned v)"; else bad "R8 (H2): the API call replaced the caller's EXIT trap or moved its cwd"; fi
# H2: QUIT to the process group (no default EXIT trap in bash) leaves no snapshot directory behind
t_r8quit() { # $1=gate
    local lib i pg pid seen="" TD="$TMP/r8quitd"; lib="$(cd "$(dirname "$1")/../lib" && pwd -P)/third_party_prune.sh"
    rm -rf -- "${TD:?}"; mkdir -p "$TD"
    # an async list starts with QUIT ignored (POSIX, measured: then nothing can trap it and the test proves nothing), so the
    # launcher restores the default disposition and starts a new session before exec'ing the prune
    ( ulimit -c 0; exec python3 -I -c 'import os, signal, sys; signal.signal(signal.SIGQUIT, signal.SIG_DFL); os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' \
        env TMPDIR="$TD" PATH="$TMP/r7shimT:$PATH" bash -c '. "$1"; cm_third_party_prune_paths "$2"' _ "$lib" "$R7T" ) >/dev/null 2>&1 &
    pid=$!
    for i in $(seq 1 50); do [ -n "$(ls -A "$TD")" ] && { seen=1; break; }; sleep 0.1; done
    pg="$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')"
    if [ -n "$seen" ] && [[ "$pg" =~ ^[0-9]+$ ]] && [ "$pg" -gt 1 ] && [ "$pg" = "$pid" ]; then kill -QUIT -- "-$pg"; else kill -TERM "$pid" 2>/dev/null; seen=""; fi
    wait "$pid" 2>/dev/null
    [ -n "$seen" ] && [ -z "$(ls -A "$TD")" ]
}
if command -v python3 >/dev/null 2>&1; then
    if t_r8quit "$GATE"; then ok "R8 (H2): SIGQUIT to the prune's process group leaves no tp_manifest.* behind (needle: the dir existed)"; else bad "R8 (H2): SIGQUIT left a snapshot dir behind ($(ls -A "$TMP/r8quitd" | head -3 | tr '\n' ' '))"; fi
else echo "SKIP: R8 QUIT: python3 not on PATH (topology_unsupported)"; fi

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
chk exact     's/\[ "\$path" = "\$1" \]/true/' '\[ "\$path" = "\$1" \]' t_p1
chk rec       's/if cm_tp_gitlink_deep "\${prefix:+\$prefix\/}\$pp" "\$depth"; then tp/if true; then tp/' 'if cm_tp_gitlink_deep "\${prefix:+\$prefix/}\$pp"' t_hos
chk toplvl    's/^    \[ "\$rootp" = "\$top" \] || prefix=.*/    prefix=""/' '\[ "\$rootp" = "\$top" \] || prefix=' t_p2
chk gitmod    's/^cm_tp_is_gitlink() {/cm_tp_is_gitlink() { grep -Fq "path = $1" .gitmodules 2>\/dev\/null \&\& return 0/' '^cm_tp_is_gitlink() {' t_p3
chk nogit     's/^cm_tp_is_gitlink() {/cm_tp_is_gitlink() { return 0/;s/^cm_tp_manifest_recorded() {/cm_tp_manifest_recorded() { exec {_CM_TP_RFD}<"$1"; return 0/;s/^_cm_tp_pin_here() {/_cm_tp_pin_here() { _CM_TP_HERE="$1"; return 0/;s/top="\$(_cm_tp_git -C "\$rootp" rev-parse --show-toplevel 2>\/dev\/null)" || {/top="$rootp"; true || {/' 'rev-parse --show-toplevel 2>/dev/null)" || {' t_p4
chk modecheck 's/\[ "\$mode" = 160000 \] \&\& //' '\[ "\$mode" = 160000 \] \&\& ' t_q1
chk m_off     's/then tp\["\$pp"\]=1/then :/' 'then tp\["\$pp"\]=1' t_q4
chk recurse   's/sub="\$(_cm_tp_descend /sub="$(false /' 'sub="\$(_cm_tp_descend ' t_n1
chk deepres   's/        ( _cm_tp_pin_gitlink "\$pre" .*; return \$?/        return 1/' '( _cm_tp_pin_gitlink "\$pre"' t_n2
# (deeppop -- dropping the parent-populated check -- is an EQUIVALENT mutant: an unpopulated parent resolves to the outer
#  repository, whose --full-name path never equals the nested path; recorded in the report, not a test gap)
chk pathok    's/                    cm_third_party_prune_ok "\$pp" || continue/                    :/' 'cm_third_party_prune_ok "\$pp" || continue' t_sp
chk nosym     's/                    cm_tp_no_symlink "\$base" "\$pp" || continue/                    :/' 'cm_tp_no_symlink "\$base" "\$pp" || continue' t_md2
chk ambig     's/^cm_tp_recorded() { cm_tp_is_gitlink "\$1" \&\& ! cm_tp_ambiguous "\$1"; }/cm_tp_recorded() { cm_tp_is_gitlink "$1"; }/' '^cm_tp_recorded() {' t_f11
chk ambparse  's/    _cm_tp_git config -f "\$gm" --list >\/dev\/null 2>\&1 || return 0/    :/' '_cm_tp_git config -f "\$gm" --list' t_f11p
# R6 (review follow-ups r1): the recorded-copy guards, one killing fixture each. EQUIVALENT by construction (stated,
# not tested): the literal pathspec, the exact-path compare and the one-record count in cm_tp_manifest_entry -- any
# mis-selected record carries a sha the snapshot hash cannot match unless its bytes are identical, and identical bytes
# are the recorded bytes; core.fsmonitor=false -- no command of the library refreshes the index (the fsmonitor
# fixtures above prove no injected command runs, with or without it). The old tag (`H`) check is gone: a skip-worktree
# or assume-unchanged entry is now judged by its bytes (hash vs index sha), which that state can no longer hide.
chk custody   's/^cm_tp_manifest_recorded() {/cm_tp_manifest_recorded() { exec {_CM_TP_RFD}<"$1"; return 0/' '^cm_tp_manifest_recorded() {' t_mod
chk blobgood  's/^cm_tp_manifest_recorded() {/cm_tp_manifest_recorded() { return 1/' '^cm_tp_manifest_recorded() {' t_cgood
chk hashchk   's/^    \[ "\$got" = "\$sha" \] || {/    true || {/' '^    \[ "\$got" = "\$sha" \] ||' t_mod
chk hashita   's/^    \[ "\$got" = "\$sha" \] || {/    true || {/' '^    \[ "\$got" = "\$sha" \] ||' t_ita
chk idxmode   's/        \[ "\$mode" = 100644 \] || return 1/        :/' '\[ "\$mode" = 100644 \] || return 1' t_symtype
chk idxstage  's/        \[ "\$stage" = 0 \] || return 1/        :/' '\[ "\$stage" = 0 \] || return 1' t_stage2
chk noentry   's/^cm_tp_manifest_entry() {/cm_tp_manifest_entry() { _cm_tp_gitp hash-object --no-filters --stdin < "$1"; return 0/' '^cm_tp_manifest_entry() {' t_untr
chk wtfile    's/fl | os.O_NOFOLLOW | os.O_NONBLOCK/fl | os.O_NONBLOCK/' 'fl | os.O_NOFOLLOW | os.O_NONBLOCK' t_wtsym
chk wtxbit    's/        if st.st_mode \& 0o111:/        if False:/' 'if st.st_mode & 0o111:' t_xbit
chk envscrub  's/^    env -i PATH=.*GIT_CONFIG_NOSYSTEM.*/    env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_CEILING_DIRECTORIES -u GIT_COMMON_DIR \\/;s/^        GIT_TERMINAL_PROMPT=0 GIT_OPTIONAL_LOCKS=0 "\${to\[@\]}" git -c core.fsmonitor=false/        "${to[@]}" git/' '^    env -i PATH=.*GIT_CONFIG_NOSYSTEM' t_envg
chk noreplace 's/^    env -i PATH=.*GIT_CONFIG_NOSYSTEM.*/    env -u GIT_DIR -u GIT_WORK_TREE -u GIT_INDEX_FILE -u GIT_CEILING_DIRECTORIES -u GIT_COMMON_DIR \\/;s/^        GIT_TERMINAL_PROMPT=0 GIT_OPTIONAL_LOCKS=0 "\${to\[@\]}" git -c core.fsmonitor=false/        "${to[@]}" git/;s/^    _cm_tp_bounded "\$1" "\$w"; rc=\$?/    _cm_tp_gitp cat-file blob ":$1" >\&"$w" 2>\/dev\/null; rc=$?/;s/^    \[ "\$got" = "\$sha" \] || {/    true || {/' '^    _cm_tp_bounded "\$1" "\$w"; rc=' t_repl
chk objread   's/^    _cm_tp_bounded "\$1" "\$w"; rc=\$?/    _cm_tp_gitp cat-file blob ":$1" >\&"$w" 2>\/dev\/null; rc=$?/' '^    _cm_tp_bounded "\$1" "\$w"; rc=' t_replg
# R7 (review follow-ups r2, G1/G2): the bounded-reader guards, one behaviour fixture each (reviewer RM1 / RM5 / RM9
# included). RM9 ("drop the -f check") has no literal anchor any more: the regular-file guard is the reader's S_ISREG
# (rm9isreg) and the no-hang guard is O_NONBLOCK (rm9nonblk); both are killed by the plain FIFO fixture.
chk rm1parse  's/recs="\$(cm_hdeps_tsv "\$_CM_TP_FD\/\$_CM_TP_RFD")"/recs="$(cm_hdeps_tsv "$mf")"/' 'recs="\$(cm_hdeps_tsv "\$_CM_TP_FD/\$_CM_TP_RFD")"' t_r7snapA
chk rm5hash   's/--stdin < "\$_CM_TP_FD\/\$_CM_TP_RFD" 2>/--stdin < "$p" 2>/' 'hash-object --no-filters --stdin < "\$_CM_TP_FD/\$_CM_TP_RFD"' t_r7snapB
chk rm9isreg  's/        if not stat.S_ISREG(st.st_mode):/        if False:/' 'if not stat.S_ISREG(st.st_mode):' t_r7fifo
chk rm9nonblk 's/ | os.O_NONBLOCK | / | /' 'os.O_NOFOLLOW | os.O_NONBLOCK | os.O_NOCTTY' t_r7fifo
chk bounded   's/^    _cm_tp_bounded "\$1" "\$w"; rc=\$?/    cat -- "$1" >\&"$w" 2>\/dev\/null; rc=$?/' '^    _cm_tp_bounded "\$1" "\$w"; rc=' t_r7swapfifo
chk swapzero  's/fl | os.O_NOFOLLOW | os.O_NONBLOCK/fl | os.O_NONBLOCK/' 'fl | os.O_NOFOLLOW | os.O_NONBLOCK' t_r7swapzero
chk dirnofol  's/fl | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=d/fl | os.O_DIRECTORY, dir_fd=d/' 'os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=d' t_r7walk
chk sizecap   's/        if st.st_size > cap:/        if False:/' 'if st.st_size > cap:' t_r7big
chk lencap    's/        if len(buf) > cap:/        if False:/' 'if len(buf) > cap:' t_r7grow
chk gitto     's/^    local to=(); \[ -n "\$_CM_TP_TIMEOUT" \] \&\& to=.*/    local to=()/' 'local to=(); \[ -n "\$_CM_TP_TIMEOUT" \]' t_r7hang
# (no separate HUP/INT/TERM trap: measured, bash runs the EXIT trap when a TERM kills the subshell, so a TERM trap
#  is an equivalent mutant; t_r7clean below kills its removal through the EXIT-trap mutant)
chk exittrap  's/^        trap .* EXIT .*/        :/' '^        trap .* EXIT ' t_r7clean
# R8 (review follow-ups r3, H1 + H2): each pin and each temp-custody / trap property, one behaviour fixture each.
# EQUIVALENT by construction (stated, not tested): the reader's O_NOFOLLOW on its top (the top is always "."); opening the
# git dir through a cwd-relative path instead of its absolute name and the fd -ef check (no git call sits between
# rev-parse and the open, so no deterministic fixture can swap there; the hammering harness exercises it).
chk pinpwd    's/^    \[ "\$(pwd -P 2>\/dev\/null)" = "\$exp" \] || return 1/    :/' '^    \[ "\$(pwd -P 2>/dev/null)" = "\$exp" \] || return 1' t_r8rootpin
chk pintop    's/^    \[ "\$t" = "\$exp" \] || return 1/    :/' '^    \[ "\$t" = "\$exp" \] || return 1' t_r8roottop
chk rootpin   's/cd -P -- "\$1" 2>\/dev\/null \&\& _cm_tp_pin_here "\$1"; }/cd -P -- "$1" \&\& _CM_TP_HERE="$1" \&\& exec {_g}<"$(_cm_tp_git rev-parse --absolute-git-dir)" \&\& _CM_TP_GD="$_CM_TP_FD\/$_g"; }/' 'cd -P -- "\$1" 2>/dev/null && _cm_tp_pin_here "\$1"; }' t_r8rootpin
chk pinpost   's/^_cm_tp_still_here() {/_cm_tp_still_here() { return 0/' '^_cm_tp_still_here() {' t_r8ren
chk pinpath   's/^_cm_tp_gitp() { \[ -n "\$_CM_TP_GD" \] || return 1; _cm_tp_git --git-dir="\$_CM_TP_GD" --work-tree=. "\$@"; }/_cm_tp_gitp() { _cm_tp_git -C "$_CM_TP_HERE" "$@"; }/' '^_cm_tp_gitp() {' t_r8glcheck
chk pingd     's/^_cm_tp_gitp() { \[ -n "\$_CM_TP_GD" \] || return 1; _cm_tp_git --git-dir="\$_CM_TP_GD" --work-tree=. "\$@"; }/_cm_tp_gitp() { _cm_tp_git "$@"; }/' '^_cm_tp_gitp() {' t_r8gitf
chk gdstr     's/^    _CM_TP_GD="\$_CM_TP_FD\/\$g"; _CM_TP_HERE="\$exp"/    _CM_TP_GD="$gd"; _CM_TP_HERE="$exp"/' '^    _CM_TP_GD="\$_CM_TP_FD/\$g"' t_r8gdfd
chk pingl     's/^_cm_tp_pin_gitlink() {/_cm_tp_pin_gitlink() { _cm_tp_pin "$1"; return $?/' '^_cm_tp_pin_gitlink() {' t_r8renall
chk glmod     's/^        for c in "\${acc\[@\]}"; do \[ -d "\$c" \] \&\& \[ "\$_CM_TP_GD" -ef "\$c" \] \&\& return 0; done$/        :/' '^        for c in "\${acc\[@\]}"; do \[ -d "\$c" \] && ' t_r8adv
# R9 (review follow-ups r4, K1 class): the module rule, one behaviour fixture each
chk glreq     '/^    if \[ "\$trig" = 1 \]; then$/,/^    fi$/ s/^        return 1$/        :/' '^    if \[ "\$trig" = 1 \]; then$' t_r8renheld
chk glreq2    '/^    if \[ "\$trig" = 1 \]; then$/,/^    fi$/ s/^        return 1$/        :/' '^    if \[ "\$trig" = 1 \]; then$' t_r9gitfc
chk glreq3    '/^    if \[ "\$trig" = 1 \]; then$/,/^    fi$/ s/^        return 1$/        :/' '^    if \[ "\$trig" = 1 \]; then$' t_r9wt
chk glname    's/^    names="\$(_cm_tp_modnames "\$rel")"$/    names=""/' '^    names="\$(_cm_tp_modnames "\$rel")"$' t_r9name
chk glnamesrc 's/for src in .:\.gitmodules. .HEAD:\.gitmodules.; do/for src in ":nonexistent"; do/' "for src in ':.gitmodules' 'HEAD:.gitmodules'; do" t_r9name
# (glprec -- let modules/<path> vouch even when a name is recorded -- is EQUIVALENT for safety, measured r5: every module
#  git dir git creates carries core.worktree, so a .git file aimed at ANOTHER submodule's module dir makes git's
#  --show-toplevel name that submodule's worktree and _cm_tp_pin_here refuses first; t_r9prec still guards the case.
#  Forging a module dir without core.worktree needs a write inside the parent's git dir, outside the threat model.)
chk gltrig    's/^    for c in "\${acc\[@\]}" "\$pgd\/modules\/\$rel"; do/    for c in ; do/' '^    for c in "\${acc\[@\]}" "\$pgd/modules/\$rel"; do' t_r8renheld
chk rcentry   '/^cm_tp_manifest_entry() {/,/^}/ s/< <(_cm_tp_gitp -c core.quotePath=false/< <(_cm_tp_git -C . -c core.quotePath=false/' '^cm_tp_manifest_entry() {' t_r8gdlate
chk nofdmsg   's/^    if \[ -z "\$_CM_TP_FD" \]; then$/    if false; then/' '^    if \[ -z "\$_CM_TP_FD" \]; then$' t_r9nofd
chk glhead    's/^    \[ "\$h" = "\$sha" \]$/    false/' '^    \[ "\$h" = "\$sha" \]$' t_r8embT
chk snapunlink 's/^    rm -f -- "\${f:?}"$/    :/' '^    rm -f -- "\${f:?}"$' t_r8snapname
chk snapdirpriv 's|^    _CM_TP_SNAPDIR="\$(mktemp -d .*|    _CM_TP_SNAPDIR="${TMPDIR:-/tmp}/tp_manifest.shared"; mkdir -p "$_CM_TP_SNAPDIR" 2>/dev/null \|\| _CM_TP_SNAPDIR=""|' '^    _CM_TP_SNAPDIR="\$(mktemp -d ' t_r8ri
chk nosub     's/( _cm_tp_run "\$top" "\$prefix" )/_cm_tp_run "$top" "$prefix"/' '( _cm_tp_run "\$top" "\$prefix" )' t_r8trap
chk quittrap  's/^        trap .exit 131. QUIT/        :/' "^        trap 'exit 131' QUIT" t_r8quit
chk capv      's/^_CM_TP_MAX_MANIFEST=1048576 /_CM_TP_MAX_MANIFEST=1073741824 /' '^_CM_TP_MAX_MANIFEST=1048576 ' t_r7big
chk readerrc  's/^    _cm_tp_bounded "\$1" "\$w"; rc=\$?/    _cm_tp_bounded "$1" "$w"; rc=0/' '^    _cm_tp_bounded "\$1" "\$w"; rc=' t_r7fifo
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
# ── round 9: explicit --exclude, the consumer's sanctioned and PRINTED way to leave a tree out ─────────────────
# (a consumer cannot use the ambient KILLPG_GUARD_EXCLUDE any more: it is a guarded override, honoured only under
#  HELIX_TEST_MODE=1; byte-frozen snapshots of old code whose prose spells `kill(0, 0)` need an explicit flag instead)
XC="$TMP/xcl"; mkdir -p "$XC/scripts/hooks/fixtures" "$XC/scripts/live" "$XC/node_modules"
printf 'x="$(python3 - <<'"'"'PYEOF'"'"'\ndef f(pid):\n    # The pid answered kill(0, 0) -- it exists\n    return pid\nPYEOF\n)"\n' > "$XC/scripts/hooks/fixtures/frozen.fixture.sh"
printf '%b' "$BADPY" > "$XC/scripts/live/real_bad.py"; printf '%b' "$BADPY" > "$XC/node_modules/vendored_bad.py"
printf 'def ok():\n    return 1\n' > "$XC/scripts/live/ok.py"
xg() { local g="$1"; shift; bash "$g" --root "$XC" --quiet "$@" 2>&1; }   # rc of the gate
fx_found() { grep -q 'FAIL — UNGUARD.*frozen\.fixture\.sh' <<<"$1"; }
live_found() { grep -q 'FAIL — UNGUARD.*real_bad\.py' <<<"$1"; }
nm_found() { grep -q 'vendored_bad\.py' <<<"$1"; }
excl_line() { grep -q 'EXCLUDED (explicit --exclude, not scanned): .*scripts/hooks/fixtures (1 source file(s))' <<<"$1" && grep -q 'excluded file: .*frozen\.fixture\.sh' <<<"$1"; }
x_default() { local o r; o="$(xg "$1")"; r=$?; [ "$r" -eq 1 ] && fx_found "$o" && live_found "$o" && ! nm_found "$o" && ! grep -q 'EXCLUDED' <<<"$o"; }
x_path() { local o r; o="$(xg "$1" --exclude scripts/hooks/fixtures)"; r=$?
    [ "$r" -eq 1 ] && ! fx_found "$o" && live_found "$o" && ! nm_found "$o" && excl_line "$o"; }
x_name() { local o r; o="$(xg "$1" --exclude fixtures)"; r=$?; [ "$r" -eq 1 ] && ! fx_found "$o" && live_found "$o" && excl_line "$o"; }
x_refuse() { local v r; for v in '*' '' '/abs' '../x' 'a b' '.' '*/*' 'x;y' 'a$b'; do bash "$1" --root "$XC" --exclude "$v" --quiet >/dev/null 2>&1; r=$?; [ "$r" -eq 2 ] || return 1; done
    bash "$1" --root "$XC" --exclude >/dev/null 2>&1; [ $? -eq 2 ]; }
x_nomatch() { local o r; o="$(xg "$1" --exclude nothere)"; r=$?; [ "$r" -eq 1 ] && fx_found "$o" && grep -q 'NOTE — --exclude (nothere) matched no directory' <<<"$o"; }
x_env() { local o r; o="$(env KILLPG_GUARD_EXCLUDE=scripts/hooks/fixtures bash "$1" --root "$XC" --quiet 2>&1)"; r=$?; [ "$r" -eq 1 ] && fx_found "$o" && grep -q 'ignoring KILLPG_GUARD_EXCLUDE' <<<"$o"; }
x_file() { local o; o="$(bash "$1" --root "$XC/scripts/hooks/fixtures/frozen.fixture.sh" --exclude fixtures --quiet 2>&1)"; fx_found "$o" && grep -q 'no effect on a single-file scan root' <<<"$o"; }
x_clean() { local o r; rm -f "$XC/scripts/live/real_bad.py"; o="$(xg "$1" --exclude scripts/hooks/fixtures)"; r=$?; printf '%b' "$BADPY" > "$XC/scripts/live/real_bad.py"
    [ "$r" -eq 0 ] && grep -q 'PASS' <<<"$o" && excl_line "$o"; }
if x_default "$GATE"; then ok "X1: no --exclude: the frozen fixture and the live file are both reported, node_modules stays default-pruned"; else bad "X1: baseline wrong"; fi
if x_path "$GATE"; then ok "X2: --exclude scripts/hooks/fixtures: fixture not reported, live file STILL reported, default prune kept (additive), exclusion printed with its file"; else bad "X2: path exclusion wrong"; fi
if x_name "$GATE"; then ok "X3: --exclude fixtures (directory-name form) behaves the same"; else bad "X3: name exclusion wrong"; fi
if x_refuse "$GATE"; then ok "X4: unsafe / empty / valueless --exclude refused with exit 2 (*, empty, /abs, .., space, ., */*, ;, \$)"; else bad "X4: an unsafe --exclude was accepted"; fi
if x_nomatch "$GATE"; then ok "X5: an exclusion that matches nothing prints a NOTE and scans everything"; else bad "X5: no-match exclusion silent or hid something"; fi
if x_env "$GATE"; then ok "X6: the ambient KILLPG_GUARD_EXCLUDE is still ignored without test mode (the flag is the only way)"; else bad "X6: ambient exclude honoured or not announced"; fi
if x_file "$GATE"; then ok "X7: --exclude with a single-file root has no effect and says so"; else bad "X7: single-file root + --exclude silent or effective"; fi
if x_clean "$GATE"; then ok "X8: with only the excluded fixture left unclean, the gate PASSes and still prints what it skipped"; else bad "X8: clean tree + exclusion did not PASS with a printed exclusion"; fi
# paired mutants of the --exclude feature: each must break at least one of X1..X8
mkxg() { # $1=name $2=sed script : a gate copy with its libs, mutated
    local D="$TMP/xm_$1"; mkdir -p "$D/gates" "$D/lib" "$D/deps_manifest"
    cp "$HERE/cm_killpg_pgid_guard.sh" "$D/gates/"; cp "$HERE"/../lib/*.sh "$D/lib/"; cp "$HERE"/../deps_manifest/*.* "$D/deps_manifest/" 2>/dev/null
    sed -i "$2" "$D/gates/cm_killpg_pgid_guard.sh"; echo "$D/gates/cm_killpg_pgid_guard.sh"
}
x_all() { x_path "$1" && x_name "$1" && x_refuse "$1" && x_nomatch "$1" && x_file "$1" && x_clean "$1"; }
x_mut() { # $1=label $2=anchor-grep $3=sed
    local G; G="$(mkxg "$1" "$3")"
    if ! grep -qF -- "$2" "$HERE/cm_killpg_pgid_guard.sh"; then bad "mutant $1: anchor absent"
    elif cmp -s "$G" "$HERE/cm_killpg_pgid_guard.sh"; then bad "mutant $1 did not apply"
    elif x_all "$G"; then bad "mutant $1 SURVIVED (--exclude tests are not load-bearing for it)"; else ok "mutant $1 caught"; fi
}
x_mut ignored '[ "${#cli_prune_expr[@]}" -eq 0 ] || prune_expr+=' 's/^\[ "\${#cli_prune_expr\[@\]}" -eq 0 \] || prune_expr+=.*/:/'
x_mut silent 'EXCLUDED (explicit --exclude, not scanned)' 's/EXCLUDED (explicit --exclude, not scanned)/(quiet)/; s/excluded file: /(quiet) /'
x_mut accepts_all 'exclude_glob_ok() {' 's/^exclude_glob_ok() {/exclude_glob_ok() { return 0;/'
x_mut replaces_default 'for ex in $excludes; do' 's/^for ex in \$excludes; do/for ex in ${cli_excludes:-$excludes}; do/'
x_mut nonote 'matched no directory under' 's/NOTE — --exclude (\${cli_ex_txt}) matched no directory under/(quiet) matched no directory under/'
x_mut filenote 'has no effect on a single-file scan root' 's/has no effect on a single-file scan root/applies/'

# ── round 10 (independent review round 1, NO-GO): an --exclude may not prune the scan ROOT or an ancestor of it (find applies -name /
# -path to its starting point, so the gate ended in SKIP, exit 0, with every call site unread), is taken literally (never glob-expanded
# against the caller's working directory), and may not empty the scan into a SKIP ──────────────────────────────────────────────
# fixture: $XR is the scan root, basename `live`, parent `scripts`, grandparent `xcl`; it holds a real bad call (real_bad.py)
XR="$XC/scripts/live"
XZ="$TMP/xz"; mkdir -p "$XZ/fixtures"; cp "$XC/scripts/hooks/fixtures/frozen.fixture.sh" "$XZ/fixtures/"   # the only source file lives under the excluded dir
XN="$TMP/xn"; mkdir -p "$XN/fixtures"; printf 'notes\n' > "$XN/fixtures/notes.txt"                          # no source file anywhere
XW="$TMP/xcwd"; mkdir -p "$XW/fixonly"                                                                      # a working directory holding an entry that `fix*` would expand to
xroot_refused() { # $1=gate $2=value : exit 2, the refusal says the value matches the scan root or an ancestor, no SKIP, no scan verdict
    local o r; o="$(bash "$1" --root "$XR" --exclude "$2" --quiet 2>&1)"; r=$?
    [ "$r" -eq 2 ] && grep -q "matches the scan root itself or one of its ancestors" <<<"$o" && ! grep -q 'SKIP — topology_unsupported' <<<"$o" && ! grep -q 'FAIL —' <<<"$o"; }
x_rootctl() { local o r; o="$(bash "$1" --root "$XR" --quiet 2>&1)"; r=$?; [ "$r" -eq 1 ] && live_found "$o" || return 1   # control needle: the unexcluded scan sees the bad call
    o="$(bash "$1" --root "$XR" --exclude 'zz*' --quiet 2>&1)"; r=$?                                                    # and an exclusion that matches neither the root nor an ancestor is NOT refused
    [ "$r" -eq 1 ] && live_found "$o" && ! grep -q 'matches the scan root' <<<"$o"; }
x_rootname() { xroot_refused "$1" live; }
x_roottail() { xroot_refused "$1" scripts/live; }
x_rootanc() { xroot_refused "$1" xcl/scripts && xroot_refused "$1" 'xc*/scripts'; }
x_rootglob() { xroot_refused "$1" 'li*' && xroot_refused "$1" '*ve' && xroot_refused "$1" 'l*' && xroot_refused "$1" 'scripts/l*'; }
x_zero() { local o r; o="$(bash "$1" --root "$XZ" --quiet 2>&1)"; r=$?; [ "$r" -eq 1 ] && fx_found "$o" || return 1       # control needle: unexcluded, the file is reported
    o="$(bash "$1" --root "$XZ" --exclude fixtures --quiet 2>&1)"; r=$?
    [ "$r" -eq 2 ] && grep -q 'left no source file to scan' <<<"$o" && ! grep -q 'SKIP — topology_unsupported' <<<"$o"; }
x_zeroskip() { local o r; o="$(bash "$1" --root "$XN" --quiet 2>&1)"; r=$?; [ "$r" -eq 0 ] && grep -q 'SKIP — topology_unsupported' <<<"$o" || return 1   # a tree with no source file SKIPs, as before
    o="$(bash "$1" --root "$XN" --exclude fixtures --quiet 2>&1)"; r=$?                                                  # ... and the exclusion is not what emptied it: still SKIP
    [ "$r" -eq 0 ] && grep -q 'SKIP — topology_unsupported' <<<"$o"; }
x_cwd() { local o r; o="$(cd "$XW" && bash "$1" --root "$XC" --exclude 'fix*' --quiet 2>&1)"; r=$?
    [ "$r" -eq 1 ] && ! fx_found "$o" && live_found "$o" && excl_line "$o" && ! grep -q 'matched no directory' <<<"$o"; }
x_applied() { local o; o="$(bash "$1" --root "$XC" --exclude nothere --exclude 'a/b' --quiet 2>&1)"
    grep -q "matched no directory under .* (applied as: -name 'nothere'; -path '\*/a/b' -o -path '\*/a/b/\*')" <<<"$o"; }
if x_rootctl "$GATE"; then ok "X9: control: the unexcluded root scan reports the bad call, and an exclusion unrelated to the root ('zz*') is not refused"; else bad "X9: root-exclusion control wrong"; fi
if x_rootname "$GATE"; then ok "X10: --exclude <basename of the scan root> is refused with exit 2 (no SKIP)"; else bad "X10: an exclusion naming the scan root was accepted"; fi
if x_roottail "$GATE"; then ok "X11: --exclude <tail path of the scan root> is refused with exit 2 (no SKIP)"; else bad "X11: a tail-path exclusion of the scan root was accepted"; fi
if x_rootanc "$GATE"; then ok "X12: --exclude <tail path of an ANCESTOR of the scan root> (also as a glob) is refused with exit 2 (no SKIP)"; else bad "X12: an exclusion naming an ancestor of the scan root was accepted"; fi
if x_rootglob "$GATE"; then ok "X13: --exclude <glob matching the scan root> (name and path forms) is refused with exit 2 (no SKIP)"; else bad "X13: a glob matching the scan root was accepted"; fi
if x_zero "$GATE"; then ok "X14: an exclusion that leaves NO source file to scan exits 2 (not SKIP), where the unexcluded scan has a finding"; else bad "X14: exclusion emptied the scan into SKIP or the control is wrong"; fi
if x_zeroskip "$GATE"; then ok "X15: a tree with no source file at all still SKIPs, with or without an unrelated --exclude (the exit-2 rule is only for an exclusion that emptied the scan)"; else bad "X15: no-source tree no longer SKIPs"; fi
if x_cwd "$GATE"; then ok "X16: --exclude 'fix*' run from a directory holding 'fixonly' still excludes 'fixtures' (the value is not glob-expanded against the working directory)"; else bad "X16: --exclude glob expanded against the caller's working directory"; fi
if x_applied "$GATE"; then ok "X17: the no-match NOTE prints the find test that was applied"; else bad "X17: the NOTE does not print the applied test"; fi
x2_mut() { # $1=label $2=anchor-grep $3=sed $4=case function : it must PASS on the real gate (checked) and FAIL on the mutant
    local G; G="$(mkxg "$1" "$3")"
    if ! grep -qF -- "$2" "$HERE/cm_killpg_pgid_guard.sh"; then bad "mutant $1: anchor absent"
    elif cmp -s "$G" "$HERE/cm_killpg_pgid_guard.sh"; then bad "mutant $1 did not apply"
    elif ! "$4" "$HERE/cm_killpg_pgid_guard.sh"; then bad "mutant $1: case $4 does not hold on the real gate"
    elif "$4" "$G"; then bad "mutant $1 SURVIVED ($4 is not load-bearing for it)"; else ok "mutant $1 caught by $4"; fi
}
x2_mut rootcheck_off '-maxdepth 0 -type d' 's/-maxdepth 0 -type d/-maxdepth 0 -type d -name NEVER_MATCHES_ZZ/' x_rootname
x2_mut rootcheck_off_tail '-maxdepth 0 -type d' 's/-maxdepth 0 -type d/-maxdepth 0 -type d -name NEVER_MATCHES_ZZ/' x_roottail
x2_mut rootcheck_off_glob '-maxdepth 0 -type d' 's/-maxdepth 0 -type d/-maxdepth 0 -type d -name NEVER_MATCHES_ZZ/' x_rootglob
x2_mut rootcheck_no_ancestor '-maxdepth 0 -type d' 's/\\( "\${one_expr\[@\]}" \\) -print -quit/\\( "${one_expr[@]:0:2}" \\) -print -quit/' x_rootanc
x2_mut zero_skips 'if [ -n "$cli_would_scan" ]; then' 's/if \[ -n "\$cli_would_scan" \]; then/if false; then/' x_zero
x2_mut zero_always_refuses 'if [ -n "$cli_would_scan" ]; then' 's/if \[ -n "\$cli_would_scan" \]; then/if true; then/' x_zeroskip
x2_mut cwd_glob 'for ex in ${cli_excludes[@]+"${cli_excludes[@]}"}; do' 's/^for ex in \${cli_excludes\[@\]+"\${cli_excludes\[@\]}"}; do/for ex in ${cli_excludes[*]}; do/' x_cwd
x2_mut note_without_applied '(applied as: ${cli_applied})' 's/ (applied as: \${cli_applied})//' x_applied

# ── round 11 (independent review round 2, non-blocking follow-ups M1, M2, L1, L4) ───────────────────────────────
# M1: a --root that is a SYMLINK to a directory. find(1) does not follow a symlink given as its starting point, so the logical
# path used to match no file and the gate ended in SKIP (exit 0, read as a pass by a consumer) with every call site unread.
# The root is resolved with pwd -P; the NOTE says so.
XS="$TMP/xsym"; mkdir -p "$XS/real/live"; printf '%b' "$BADPY" > "$XS/real/live/real_bad.py"
ln -s real "$XS/link"; ln -s real/live "$XS/linklive"   # relative links: one to the tree, one to a subdirectory
x_symroot() { # $1=gate : a symlinked root is scanned (rc 1, the finding reported), never a SKIP, and the resolution is announced
    local o r p
    o="$(bash "$1" --root "$XS/real" --quiet 2>&1)"; r=$?; [ "$r" -eq 1 ] && live_found "$o" && ! grep -q 'is a symlink' <<<"$o" || return 1   # control needle: the real path reports the bad call, with no symlink NOTE
    for p in link link/ linklive; do
        o="$(bash "$1" --root "$XS/$p" --quiet 2>&1)"; r=$?
        [ "$r" -eq 1 ] && live_found "$o" && ! grep -q 'SKIP' <<<"$o" && grep -q "scan root .*/xsym/${p} is a symlink; scanning the directory it resolves to: .*/xsym/real" <<<"$o" || return 1
    done
}
if x_symroot "$GATE"; then ok "X18: a --root that is a symlink to a directory (to the tree, with a trailing slash, to a subdirectory) is resolved and scanned: the bad call is reported (exit 1), not a SKIP, and the NOTE names the resolution"; else bad "X18: a symlinked --root ended in SKIP, lost its finding or was not announced"; fi
x2_mut symroot_logical_path 'pwd -P)"' 's/root="\$(cd "\$root" \&\& pwd -P)"/root="$(cd "$root" \&\& pwd)"/' x_symroot
x2_mut symroot_silent 'is a symlink; scanning the directory it resolves to' 's/is a symlink; scanning the directory it resolves to/(quiet)/' x_symroot

# M2: a scan root named like an entry of the DEFAULT prune list (out build dist vendor node_modules .venv __pycache__ and the path
# entry scripts/gates, which also prunes everything below it) or of the THIRD-PARTY list (third_party site-packages) was pruned
# as a whole by find(1) and ended in SKIP (exit 0). It is refused with exit 2, as an --exclude value that names the root already is.
XM="$TMP/xrootprune"; XM_DEF="out build dist vendor node_modules .venv __pycache__ scripts/gates scripts/gates/sub"; XM_TP="third_party site-packages"
for n in plainroot $XM_DEF $XM_TP; do mkdir -p "$XM/$n"; printf '%b' "$BADPY" > "$XM/$n/real_bad.py"; done
xm_refused() { # $1=gate $2=root name $3=list label (default|third-party) [$4...=extra gate args] : exit 2 naming the list, no SKIP, no verdict
    local g="$1" n="$2" l="$3" o r; shift 3
    o="$(bash "$g" --root "$XM/$n" --quiet "$@" 2>&1)"; r=$?
    [ "$r" -eq 2 ] && grep -q "the scan root .*/${n} matches the ${l} prune list" <<<"$o" && ! grep -q 'SKIP — topology_unsupported' <<<"$o" && ! grep -q 'FAIL —' <<<"$o"
}
x_rootdef() { local o r n
    o="$(bash "$1" --root "$XM/plainroot" --quiet 2>&1)"; r=$?; [ "$r" -eq 1 ] && live_found "$o" || return 1          # control needle: a root with an ordinary name is scanned and its bad call reported
    for n in $XM_DEF; do xm_refused "$1" "$n" default || return 1; done
    for n in $XM_DEF; do xm_refused "$1" "$n" default --include-third-party || return 1; done                               # --include-third-party does not switch the default list off
}
x_roottp() { local o r n
    for n in $XM_TP; do xm_refused "$1" "$n" third-party || return 1; done
    for n in $XM_TP; do                                                                                                  # control needle: with --include-third-party the same roots are scanned (the list is what refused them)
        o="$(bash "$1" --root "$XM/$n" --include-third-party --quiet 2>&1)"; r=$?; [ "$r" -eq 1 ] && live_found "$o" || return 1
    done
}
if x_rootdef "$GATE"; then ok "X19: a scan root named like a DEFAULT prune entry (out build dist vendor node_modules .venv __pycache__, scripts/gates, below scripts/gates) is refused with exit 2 naming the list, not a SKIP; an ordinary root is scanned"; else bad "X19: a root named like a default prune entry ended in SKIP, or was not refused with exit 2"; fi
if x_roottp "$GATE"; then ok "X20: a scan root named third_party / site-packages is refused with exit 2 naming the third-party list; with --include-third-party it is scanned"; else bad "X20: a root named like a third-party prune entry ended in SKIP, or the control is wrong"; fi
x2_mut rootprune_default_off 'matches the default prune list' 's/if rp_hit="\$(root_prune_hit \${prune_expr\[@\]+"\${prune_expr\[@\]:0:n_default_prune}"})"; then/if false; then/' x_rootdef
x2_mut rootprune_tp_off 'matches the third-party prune list' 's/if rp_hit="\$(root_prune_hit \${prune_expr\[@\]+"\${prune_expr\[@\]:\$((n_default_prune + \${#cli_prune_expr\[@\]}))}"})"; then/if false; then/' x_roottp
x2_mut rootprune_path_alternatives_skipped 'root_prune_hit()' 's/if \[ "\${#seg\[@\]}" -gt 0 \] \&\&/if [ "${#seg[@]}" -gt 0 ] \&\& [ "${seg[0]}" = -name ] \&\&/' x_rootdef

# L1: the "would the same scan without the --exclude entries find a source file" check (nocli_prune_expr) was only tested for a
# file under the excluded directory (X14). Its DEFAULT-prune part and its THIRD-PARTY part had no case: with that expression
# emptied, a tree whose only source files sit under node_modules / site-packages (pruned anyway) and that has an unrelated
# `--exclude fixtures` ended in exit 2 ("left no source file") instead of the SKIP it always was, and no case noticed.
XD1="$TMP/xdef1"; mkdir -p "$XD1/node_modules" "$XD1/fixtures"; printf '%b' "$BADPY" > "$XD1/node_modules/vend.py"; printf 'notes\n' > "$XD1/fixtures/notes.txt"
XD2="$TMP/xdef2"; mkdir -p "$XD2/site-packages" "$XD2/fixtures"; printf '%b' "$BADPY" > "$XD2/site-packages/vend.py"; printf 'notes\n' > "$XD2/fixtures/notes.txt"
XD3="$TMP/xdef3"; mkdir -p "$XD3/node_modules" "$XD3/fixtures"; printf '%b' "$BADPY" > "$XD3/node_modules/vend.py"; printf '%b' "$BADPY" > "$XD3/fixtures/frozen.py"
x_defprune() { # $1=gate
    local o r d
    # control needles: the vendored files ARE findings when their prune is off (a test-mode override of the default list; --include-third-party)
    o="$(env HELIX_TEST_MODE=1 KILLPG_GUARD_EXCLUDE=.git bash "$1" --root "$XD1" --quiet 2>&1)"; r=$?; [ "$r" -eq 1 ] && grep -q 'node_modules/vend\.py' <<<"$o" || return 1
    o="$(bash "$1" --root "$XD2" --include-third-party --quiet 2>&1)"; r=$?; [ "$r" -eq 1 ] && grep -q 'site-packages/vend\.py' <<<"$o" || return 1
    # the cases: their only source files sit under pruned trees and the exclusion is not what emptied the scan: SKIP, exit 0
    for d in "$XD1" "$XD2"; do
        o="$(bash "$1" --root "$d" --exclude fixtures --quiet 2>&1)"; r=$?; [ "$r" -eq 0 ] && grep -q 'SKIP — topology_unsupported' <<<"$o" || return 1
    done
    # ... while an exclusion that does empty the scan (a finding under fixtures, vend.py still pruned) stays exit 2
    o="$(bash "$1" --root "$XD3" --exclude fixtures --quiet 2>&1)"; r=$?; [ "$r" -eq 2 ] && grep -q 'left no source file to scan' <<<"$o"
}
if x_defprune "$GATE"; then ok "X21: files only under node_modules / site-packages (pruned anyway) with an unrelated --exclude fixtures still SKIP (exit 0); an exclusion that empties the scan stays exit 2 (the default and third-party parts of the would-scan check)"; else bad "X21: the default / third-party prune is not part of the would-scan check"; fi
NOCLI_ANCHOR='nocli_prune_expr=("${prune_expr[@]:0:n_default_prune}"'
x2_mut nocli_empty "$NOCLI_ANCHOR" 's/^nocli_prune_expr=(.*$/nocli_prune_expr=()/' x_defprune
x2_mut nocli_default_only "$NOCLI_ANCHOR" 's/^nocli_prune_expr=(.*$/nocli_prune_expr=("${prune_expr[@]:0:n_default_prune}")/' x_defprune
x2_mut nocli_tp_only "$NOCLI_ANCHOR" 's/^nocli_prune_expr=(.*$/nocli_prune_expr=("${prune_expr[@]:$((n_default_prune + ${#cli_prune_expr[@]}))}")/' x_defprune

# L4: the "EXCLUDED (explicit --exclude, not scanned)" listing ignored the default and third-party prunes: with `--exclude fixtures`
# it also listed `node_modules/pkg/fixtures` and `site-packages/lib/fixtures` (never scanned anyway) as exclusions of the flag,
# counted `fixtures/node_modules/deep.py` among the excluded files, and an --exclude that matches only inside pruned trees printed
# no "matched no directory" NOTE. The prunes now come first in both finds (the directory walk and the per-directory file count).
XL="$TMP/xlist"; mkdir -p "$XL/fixtures/node_modules" "$XL/node_modules/pkg/fixtures" "$XL/site-packages/lib/fixtures" "$XL/live"
for f in fixtures/frozen.py fixtures/node_modules/deep.py node_modules/pkg/fixtures/inner.py site-packages/lib/fixtures/sp.py live/real_bad.py; do printf '%b' "$BADPY" > "$XL/$f"; done
x_listing() { # $1=gate
    local o r
    # control needles: every file of the fixture is a finding when no prune applies (test-mode override of the default list, --include-third-party)
    o="$(env HELIX_TEST_MODE=1 KILLPG_GUARD_EXCLUDE=.git bash "$1" --root "$XL" --include-third-party --quiet 2>&1)"; r=$?
    [ "$r" -eq 1 ] && grep -q 'fixtures/frozen\.py' <<<"$o" && grep -q 'fixtures/node_modules/deep\.py' <<<"$o" && grep -q 'node_modules/pkg/fixtures/inner\.py' <<<"$o" && grep -q 'site-packages/lib/fixtures/sp\.py' <<<"$o" || return 1
    # --exclude fixtures: exactly ONE exclusion is listed (the one that changes the scan), with ONE file (the one under it that would be scanned)
    o="$(bash "$1" --root "$XL" --exclude fixtures --quiet 2>&1)"; r=$?
    [ "$r" -eq 1 ] && live_found "$o" && [ "$(grep -c 'EXCLUDED (explicit --exclude, not scanned)' <<<"$o")" -eq 1 ] \
        && grep -q 'EXCLUDED (explicit --exclude, not scanned): .*/xlist/fixtures (1 source file(s))' <<<"$o" \
        && grep -q 'excluded file: .*/xlist/fixtures/frozen\.py' <<<"$o" && [ "$(grep -c 'excluded file:' <<<"$o")" -eq 1 ] \
        && ! grep -q 'matched no directory' <<<"$o" || return 1
    # --exclude pkg: it matches only inside node_modules (pruned anyway): no exclusion is listed, the NOTE says nothing was matched
    o="$(bash "$1" --root "$XL" --exclude pkg --quiet 2>&1)"; r=$?
    [ "$r" -eq 1 ] && live_found "$o" && ! grep -q 'EXCLUDED (explicit --exclude' <<<"$o" && grep -q 'NOTE — --exclude (pkg) matched no directory' <<<"$o"
}
if x_listing "$GATE"; then ok "X22: the EXCLUDED listing skips directories below node_modules / site-packages (pruned anyway) and does not count files under a pruned subtree; an --exclude matching only there gets the 'matched no directory' NOTE"; else bad "X22: the exclusion listing ignores the default / third-party prunes"; fi
x2_mut listing_walk_unpruned 'list_pre=()' 's/done < <(find "\$root" \${list_pre\[@\]+"\${list_pre\[@\]}"} -type d/done < <(find "$root" -type d/' x_listing
x2_mut listing_count_unpruned 'list_pre=()' 's/find "\$_xd" \${list_pre\[@\]+"\${list_pre\[@\]}"} -type f/find "$_xd" -type f/' x_listing

[ "$rc" -eq 0 ] && echo "SCOPE TEST PASS" || echo "SCOPE TEST FAIL"
exit "$rc"
