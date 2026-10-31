#!/usr/bin/env bash
# scripts/badges/test_static_badges.sh -- behavioural tests + paired mutations for (1) the static (non-derived) badge
# passthrough list config/static_badges.list and (2) dotted-patch release tags in the Version badge.
# Every case drives the REAL scripts/badges/compute_badges.sh and the REAL scripts/gates/cm_badge_*.sh / cm_readme_badge_row_at_top.sh
# on throw-away git fixtures (no mocks). Covers: unit (static grammar, version regex), integration (computer + gates),
# e2e (the repository's own README --check), security (badge-text injection), chaos (missing/odd/unreadable config),
# determinism x3, idempotency, performance, derived-colour guarantee, and paired mutations M1..M6 on a COPY of the tool tree.
# Control needle: the helper `no` must be able to say NO (a fabricated token is asserted absent on every row).
# Usage: bash scripts/badges/test_static_badges.sh      exit 0 = all PASS, 1 = a check failed, 2 = BLIND
# Side effects: temp dir only (removed on exit). Dependencies: bash, git, sed, grep, sha256sum, python3 not required.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC="${STATIC_TEST_SRC:-$(cd "$HERE/../.." && pwd)}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/static_badges.XXXXXX")" || exit 2
: "${TMP:?}"
trap 'case "$TMP" in /*/static_badges.*) rm -rf "$TMP" ;; esac' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  ok   $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL $1"; }
has() { case "$2" in *"$1"*) return 0 ;; *) return 1 ;; esac; }
chk() { # name cond-rc
    if [ "$2" -eq 0 ]; then ok "$1"; else bad "$1"; fi
}
DW='[![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/HelixDevelopment/constitution)'
NEEDLE='ZZ_FABRICATED_NEEDLE_ZZ'

mk_tool() { # dir : copy of the tool tree (computer, reader, conf, gates)
    mkdir -p "$1/scripts/badges" "$1/scripts/gates" "$1/config"
    cp "$SRC/scripts/badges/compute_badges.sh" "$1/scripts/badges/"
    cp "$SRC/scripts/formats_export_lib.sh" "$1/scripts/"
    cp "$SRC/config/formats_export.conf" "$1/config/"
    cp "$SRC"/scripts/gates/lib_badge_row.sh "$SRC"/scripts/gates/lib_doc_manifest.sh \
       "$SRC"/scripts/gates/cm_badge_closed_color_vocabulary.sh "$SRC"/scripts/gates/cm_badge_machine_derived_source.sh \
       "$SRC"/scripts/gates/cm_readme_badge_row_at_top.sh "$1/scripts/gates/"
}
mk_repo() { # dir changelog-heading : consistent fixture repository
    local d="$1" sha
    mkdir -p "$d/scripts/gates" "$d/progressive" "$d/docs"
    printf '# C\n' >"$d/Constitution.md"
    sha="$(sha256sum "$d/Constitution.md" | cut -d' ' -f1)"
    printf '## %s — 2026-01-01 — fixture\n' "$2" >"$d/CHANGELOG.md"
    printf "generated_from:\n  source_sha256: '%s'\ngroups:\n- name: g1\nanchors:\n- id: '1.1'\n" "$sha" >"$d/constitution_index.yaml"
    printf '{"source_sha256": "%s", "anchor_count": 1}\n' "$sha" >"$d/progressive/catalog.json"
    printf '[submodule "x"]\n\tpath = x\n' >"$d/.gitmodules"
    : >"$d/scripts/gates/cm_a.sh"; : >"$d/scripts/gates/cm_a_mutation_test.sh"
    git -C "$d" init -q 2>/dev/null
    git -C "$d" update-index --add --cacheinfo 160000,1111111111111111111111111111111111111111,x 2>/dev/null
    mkdir -p "$d/config"; cp "$SRC/config/formats_export.conf" "$d/config/"
    local a; { for a in Version Anchors Groups Gates Mutation Progressive Submodules Twins Readiness; do
        printf '## %s\nSource: fixture\n\n' "$a"; done; } >"$d/docs/BADGES.md"
}
P() { bash "$1/scripts/badges/compute_badges.sh" --root "$2" --print; }   # tool-dir repo-dir
CK() { bash "$1/scripts/badges/compute_badges.sh" --root "$2" --check; }
readme_with() { printf '# T\n\n%s\n\nintro\n' "$2" >"$1/README.md"; }

T="$TMP/tool"; mk_tool "$T"
R="$TMP/repo"; mk_repo "$R" "helixconstitution-v1"

echo "== unit: version regex (dotted patch tags)"
for h in "helixconstitution-v73|green|v73" "helixconstitution-v73.1|green|v73.1" "helixconstitution-v72.2|green|v72.2" "helixconstitution-v1.2.3|green|v1.2.3" \
         "helixconstitution-v73.|amber|" "helixconstitution-v73..1|amber|" "helixconstitution-v|amber|" "helixconstitution-v73.x|amber|" "Unreleased|amber|"; do
    IFS='|' read -r head col val <<<"$h"
    D="$TMP/v_$RANDOM"; mk_repo "$D" "$head"; out="$(P "$T" "$D" 2>&1)"
    first="${out%% !*}"
    if [ "$col" = green ]; then
        has "[Version](https://img.shields.io/badge/version-$val-green)" "$first"; chk "tag '$head' -> Version green $val" $?
    else
        has "-amber?color=ffbf00" "$first"; chk "tag '$head' -> Version amber" $?
    fi
done

echo "== unit/integration: static passthrough"
readme_with "$R" "$(P "$T" "$R")"
base="$(P "$T" "$R")"
has "$NEEDLE" "$base"; [ $? -ne 0 ]; chk "control needle absent from base row" $?
has "Ask DeepWiki" "$base"; [ $? -ne 0 ]; chk "no list file -> row has no static badge" $?
printf '# c\n%s\n' "$DW" >"$R/config/static_badges.list"
withs="$(P "$T" "$R")"
[ "$withs" = "$base $DW" ]; chk "list -> static badge appended verbatim after Readiness" $?
case "$withs" in *"[Readiness]("*") $DW") ok "static is last, after the Readiness gauge" ;; *) bad "static is last" ;; esac
readme_with "$R" "$withs"; CK "$T" "$R" >/dev/null 2>&1; chk "--check accepts README with static badge" $?
readme_with "$R" "$base"; CK "$T" "$R" >/dev/null 2>&1; [ $? -eq 1 ]; chk "--check rejects README missing the declared static badge" $?
readme_with "$R" "$withs ![Evil](https://example.com/x.svg)"; CK "$T" "$R" >/dev/null 2>&1; [ $? -eq 1 ]; chk "--check rejects an undeclared extra badge" $?
printf '![Plain](https://img.shields.io/badge/a-b-blue)\n%s\n' "$DW" >"$R/config/static_badges.list"
out="$(P "$T" "$R")"; has "![Plain](https://img.shields.io/badge/a-b-blue) $DW" "$out"; chk "two static lines (plain + linked) keep file order" $?

echo "== derived-colour guarantee untouched by static badges"
printf '%s\n' "$DW" >"$R/config/static_badges.list"
sed -i "s/source_sha256: '[0-9a-f]*'/source_sha256: '$(printf 'f%.0s' $(seq 64))'/" "$R/constitution_index.yaml"
out="$(P "$T" "$R")"
has "[Anchors](https://img.shields.io/badge/anchors-1-red)" "$out"; chk "drifted index still renders Anchors red with a static list" $?
has "[Readiness](https://img.shields.io/badge/readiness-blocked-red)" "$out"; chk "Readiness gauge still red; static does not mask it" $?
mk_repo "$R" "helixconstitution-v1"; mkdir -p "$R/config"; printf '%s\n' "$DW" >"$R/config/static_badges.list"
printf '![Anchors](https://example.com/anchors-9999-green)\n' >"$R/config/static_badges.list"
P "$T" "$R" >/dev/null 2>&1; [ $? -eq 2 ]; chk "static line reusing a derived alt (Anchors) is refused rc 2" $?
printf '![X](https://e.com/a.svg)\n![X](https://e.com/b.svg)\n' >"$R/config/static_badges.list"
P "$T" "$R" >/dev/null 2>&1; [ $? -eq 2 ]; chk "duplicate static alts refused rc 2" $?

echo "== security: badge-text injection (each line must be refused rc 2, with no row printed)"
n=0
while IFS= read -r line; do
    n=$((n + 1)); printf '%s\n' "$line" >"$R/config/static_badges.list"
    out="$(P "$T" "$R" 2>/dev/null)"; rc=$?
    if [ "$rc" -eq 2 ] && [ -z "$out" ]; then ok "inject#$n refused"; else bad "inject#$n rc=$rc out='${out:0:40}' for: $line"; fi
done <<'INJ'
![a](javascript:alert(1))
![a](http://insecure.example/x.svg)
![a](https://e.com/x.svg" onerror="alert(1))
![a](https://e.com/x.svg) ![b](https://evil.example/y.svg)
![a](https://e.com/x.svg)](https://evil.example)
[![a](https://e.com/x.svg)](https://e.com/l) [click](https://evil.example)
![<script>alert(1)</script>](https://e.com/x.svg)
![a](https://e.com/<img src=x>.svg)
![a](https://e.com/x`id`.svg)
![a](https://e.com/x$(id).svg)
![a b](https://e.com/x y.svg)
text before ![a](https://e.com/x.svg)
![a](https://e.com/x.svg) trailing
![](https://e.com/x.svg)
![a]()
![a](https://)
[![a](https://e.com/x.svg)](javascript:alert(1))
![a](https://e.com/x.svg'||id||')
INJ
printf '![a](https://e.com/x.svg)\n![b](https://e.com/y.svg)' >"$R/config/static_badges.list"   # no trailing newline, valid
out="$(P "$T" "$R")"; has "![a](https://e.com/x.svg) ![b](https://e.com/y.svg)" "$out"; chk "valid list without trailing newline accepted" $?

echo "== chaos: odd or missing config"
: >"$R/config/static_badges.list"; out="$(P "$T" "$R")"; [ "$out" = "$base" ]; chk "empty list == no list" $?
printf '# only\n\n   \n# comments\n' >"$R/config/static_badges.list"; out="$(P "$T" "$R")"; [ "$out" = "$base" ]; chk "comments/blank only == no list" $?
printf '%s\r\n' "$DW" >"$R/config/static_badges.list"; out="$(P "$T" "$R")"; [ "$out" = "$base $DW" ]; chk "CRLF list line accepted and normalised" $?
printf '   %s   \n' "$DW" >"$R/config/static_badges.list"; out="$(P "$T" "$R")"; [ "$out" = "$base $DW" ]; chk "surrounding whitespace trimmed" $?
rm -f "$R/config/static_badges.list"; mkdir "$R/config/static_badges.list"
P "$T" "$R" >/dev/null 2>&1; [ $? -eq 2 ]; chk "list path is a directory -> rc 2" $?
rmdir "$R/config/static_badges.list"
printf '%s\n' "$DW" >"$R/config/static_badges.list"; chmod 000 "$R/config/static_badges.list"
if [ -r "$R/config/static_badges.list" ]; then ok "unreadable-list case skipped (running as a user that can read mode 000)"
else P "$T" "$R" >/dev/null 2>&1; [ $? -eq 2 ]; chk "unreadable list -> rc 2" $?; fi
chmod 600 "$R/config/static_badges.list"
head -c 4096 /dev/urandom >"$R/config/static_badges.list"; P "$T" "$R" >/dev/null 2>&1; [ $? -eq 2 ]; chk "binary garbage list -> rc 2" $?
bash "$T/scripts/badges/compute_badges.sh" --root "$R" --facts >/dev/null 2>&1; chk "--facts ignores the static list (independent of it)" $?

echo "== determinism x3 + idempotency + performance"
printf '%s\n' "$DW" >"$R/config/static_badges.list"
a="$(P "$T" "$R")"; b="$(P "$T" "$R")"; c="$(P "$T" "$R")"
[ "$a" = "$b" ] && [ "$b" = "$c" ]; chk "three --print runs are identical" $?
readme_with "$R" "$a"; CK "$T" "$R" >/dev/null 2>&1; r1=$?; CK "$T" "$R" >/dev/null 2>&1; r2=$?
[ $r1 -eq 0 ] && [ $r2 -eq 0 ]; chk "--check twice is stable (idempotent, no state written)" $?
s0=$(date +%s%N); P "$T" "$R" >/dev/null; s1=$(date +%s%N)
[ $(((s1 - s0) / 1000000)) -lt 15000 ]; chk "one --print under 15 s ($(((s1 - s0) / 1000000)) ms)" $?

echo "== integration: README gates accept a declared static badge"
readme_with "$R" "$a"
printf '## Ask DeepWiki\nSource: x\n' >/dev/null
G="$T/scripts/gates"
bash "$G/cm_readme_badge_row_at_top.sh" --root "$R" >/dev/null 2>&1; chk "row-at-top gate PASS with a linked static badge" $?
bash "$G/cm_badge_closed_color_vocabulary.sh" --root "$R" >/dev/null 2>&1; chk "colour-vocabulary gate PASS (static exempt)" $?
bash "$G/cm_badge_machine_derived_source.sh" --root "$R" >/dev/null 2>&1; chk "provenance gate PASS (static exempt)" $?
rm -f "$R/config/static_badges.list"
bash "$G/cm_badge_closed_color_vocabulary.sh" --root "$R" >/dev/null 2>&1; [ $? -eq 1 ]; chk "same README with the badge UNdeclared -> colour gate FAIL (no free pass)" $?
bash "$G/cm_badge_machine_derived_source.sh" --root "$R" >/dev/null 2>&1; [ $? -eq 1 ]; chk "same README UNdeclared -> provenance gate FAIL" $?
printf '%s\n' "$DW" >"$R/config/static_badges.list"

echo "== e2e: the repository's own README"
if [ -z "${STATIC_TEST_SRC:-}" ]; then
    bash "$SRC/scripts/badges/compute_badges.sh" --check >/dev/null 2>&1; chk "real README --check exits 0" $?
    has "Ask DeepWiki" "$(awk 'f&&NF{print;exit} /^# /{f=1}' "$SRC/README.md")"; chk "real README row carries the declared static badge" $?
else ok "real-README e2e skipped (mutant source tree)"; fi

if [ -z "${STATIC_TEST_INNER:-}" ]; then
echo "== paired mutations (each applied to a COPY of the tool tree; the inner case set MUST fail)"
mut() { # name sed-expr file
    local M="$TMP/m_$1"; mk_tool "$M"; sed -i "$2" "$M/$3"
    if cmp -s "$M/$3" "$T/$3"; then bad "mutation $1 did not change the file (vacuous)"; return; fi
    STATIC_TEST_SRC="$M" STATIC_TEST_INNER=1 bash "$HERE/test_static_badges.sh" >/dev/null 2>&1
    if [ $? -ne 0 ]; then ok "mutation $1 detected"; else bad "mutation $1 SURVIVED"; fi
}
mut M1_drop_passthrough 's/\[ -n "\$static_text" \] \&\& row="\$row \$static_text"//' scripts/badges/compute_badges.sh
mut M2_revert_regex 's/\\(\\\.\[0-9\]\[0-9\]\*\\)\*//' scripts/badges/compute_badges.sh
mut M3_drop_grammar 's/^        if \[\[ "\$line" =~.*$/        if true; then alt="${line%%]*}"; alt="${alt#*[}"/' scripts/badges/compute_badges.sh
mut M4_allow_derived_alt 's/seen="|Version|[^"]*"/seen="|"/' scripts/badges/compute_badges.sh
mut M5_lib_linked 's/-e .s\/\\\[!\\\[\[^\]\]\*\\\]\\(\[^)\]\*\\)\\\]\\(\[^)\]\*\\)\/\/g. //' scripts/gates/lib_badge_row.sh
mut M6_gate_exempt 's/^    case "\$static_alts" in .*$//' scripts/gates/cm_badge_closed_color_vocabulary.sh
fi
echo "RESULT: pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
