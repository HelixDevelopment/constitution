#!/usr/bin/env bash
# scripts/badges/test_twins_badge_formats_switch.sh -- behavioural test + paired mutations for the Twins badge and the
# formats-export switch (config/formats_export.conf, operator order 2026-10-26: agents work only with Markdown).
#
# What it proves (each case drives the REAL scripts/badges/compute_badges.sh on a throw-away git fixture):
#   OFF_CLEAN    switch off, no twins in the tree       -> Twins badge GRAY "markdown only", Readiness stays green, TWIN_DOCS=0
#   OFF_STALE    switch off, stale twins still present  -> still GRAY and still nothing probed (TWIN_DOCS=0): twins are not demanded
#   DEFAULT      no DOCS_EXPORT, shipped conf (false)   -> GRAY (the shipped default is Markdown-only)
#   ON_STALE     switch on, twins older than the .md, header declares them pending -> AMBER "0/2 current", Readiness amber
#   ON_UNTRACKED switch on, stale twins, header silent  -> RED, Readiness red
#   ON_MISSING   switch on, twins absent                -> never green (an absent sibling is not "current")
#   ON_CURRENT   switch on, twins newer than the .md    -> GREEN "2/2 current"
#   BLIND        formats_export_lib.sh absent next to the script -> exit 2, no row (never a guessed/green badge)
# Paired mutations (each applied to a COPY of the computer; the case set MUST fail, otherwise the test is decoration):
#   M1 OFF branch removed, M2 twins probed while OFF, M3 staleness comparison inverted, M4 absent-twin rule removed,
#   M5 BLIND return removed, M6 gray moves the Readiness gauge, M7 shipped conf default flipped to true.
# Control needle: the assertion helper must be able to say NO (a fabricated token is asserted absent on every row).
# Usage: bash scripts/badges/test_twins_badge_formats_switch.sh      exit 0 = all PASS, 1 = a case/mutation check failed
# Side effects: temp dir only (removed on exit). Dependencies: bash, git, sed, grep, sha256sum, python3 not required.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
SRC_ROOT="$(cd "$HERE/../.." && pwd)"
[ -r "$SRC_ROOT/scripts/badges/compute_badges.sh" ] && [ -r "$SRC_ROOT/scripts/formats_export_lib.sh" ] && [ -r "$SRC_ROOT/config/formats_export.conf" ] \
    || { echo "BLIND: compute_badges.sh / formats_export_lib.sh / formats_export.conf missing under $SRC_ROOT" >&2; exit 2; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/twins_badge_sw.XXXXXX")" || exit 2
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
ok()  { PASS=$((PASS + 1)); echo "  ok   $1"; }
bad() { FAIL=$((FAIL + 1)); echo "  FAIL $1"; }

# --- throw-away "tool tree": computer + shared reader + conf, mutable per mutant ------------------------------------
mk_tool() { # dir
    mkdir -p "$1/scripts/badges" "$1/config"
    cp "$SRC_ROOT/scripts/badges/compute_badges.sh" "$1/scripts/badges/"
    cp "$SRC_ROOT/scripts/formats_export_lib.sh" "$1/scripts/"
    cp "$SRC_ROOT/config/formats_export.conf" "$1/config/"
}

# --- fixture repository: kind = none | stale | fresh ; header = pending | silent -------------------------------------
mk_repo() { # dir twins header
    local d="$1" twins="$2" header="$3" sha x g="git -C $1 -c user.name=t -c user.email=t@t"
    mkdir -p "$d/scripts/gates" "$d/progressive"
    git -C "$d" init -q 2>/dev/null
    if [ "$twins" = stale ]; then   # twins committed FIRST (old), the .md later -> .md newer than its twins
        for x in Constitution CHANGELOG; do : >"$d/$x.html"; : >"$d/$x.pdf"; : >"$d/$x.docx"; done
        $g add -A >/dev/null 2>&1
        GIT_AUTHOR_DATE="2020-01-01T00:00:00" GIT_COMMITTER_DATE="2020-01-01T00:00:00" $g commit -q -m twins >/dev/null 2>&1
    fi
    if [ "$header" = pending ]; then printf '# C\nThe generated twins are stale (pending regeneration).\n' >"$d/Constitution.md"
    else printf '# C\nplain header\n' >"$d/Constitution.md"; fi
    sha="$(sha256sum "$d/Constitution.md" | cut -d' ' -f1)"
    printf '## helixconstitution-v1 -- 2026-01-01 -- fixture\n' >"$d/CHANGELOG.md"
    printf "generated_from:\n  source_sha256: '%s'\ngroups:\n- name: g1\nanchors:\n- id: '1.1'\n" "$sha" >"$d/constitution_index.yaml"
    printf '{"source_sha256": "%s", "anchor_count": 1}\n' "$sha" >"$d/progressive/catalog.json"
    printf '[submodule "x"]\n\tpath = x\n' >"$d/.gitmodules"
    : >"$d/scripts/gates/cm_a.sh"; : >"$d/scripts/gates/cm_a_mutation_test.sh"
    $g add -A >/dev/null 2>&1
    GIT_AUTHOR_DATE="2021-01-01T00:00:00" GIT_COMMITTER_DATE="2021-01-01T00:00:00" $g commit -q -m docs >/dev/null 2>&1
    if [ "$twins" = fresh ]; then   # twins committed AFTER the .md -> current
        for x in Constitution CHANGELOG; do : >"$d/$x.html"; : >"$d/$x.pdf"; : >"$d/$x.docx"; done
        $g add -A >/dev/null 2>&1
        GIT_AUTHOR_DATE="2022-01-01T00:00:00" GIT_COMMITTER_DATE="2022-01-01T00:00:00" $g commit -q -m twins >/dev/null 2>&1
    fi
    git -C "$d" update-index --add --cacheinfo 160000,1111111111111111111111111111111111111111,x 2>/dev/null
}
mk_repo "$TMP/r_none"            none  silent
mk_repo "$TMP/r_stale_pending"   stale pending
mk_repo "$TMP/r_stale_silent"    stale silent
mk_repo "$TMP/r_fresh"           fresh silent
mk_repo "$TMP/r_none_pending"    none  pending

# --- helpers -----------------------------------------------------------------------------------------------------------
# run <tool-dir> <repo-dir> <env-assignment|-> <mode>   (env-assignment: DOCS_EXPORT=1 | DOCS_EXPORT=0 | - => variable unset)
run() {
    local tool="$1" repo="$2" envs="$3" mode="$4"
    if [ "$envs" = "-" ]; then env -u DOCS_EXPORT bash "$tool/scripts/badges/compute_badges.sh" --root "$repo" "$mode" 2>/dev/null
    else env "$envs" bash "$tool/scripts/badges/compute_badges.sh" --root "$repo" "$mode" 2>/dev/null; fi
}
has() { printf '%s' "$1" | grep -qF -- "$2"; }

# the case set; echoes one line per failed assertion (empty output == all assertions of the case hold)
case_OFF_CLEAN() { local t="$1" row facts; row="$(run "$t" "$TMP/r_none" DOCS_EXPORT=0 --print)"; facts="$(run "$t" "$TMP/r_none" DOCS_EXPORT=0 --facts)"
    has "$row" 'badge/twins-markdown_only-gray)' || echo "OFF_CLEAN Twins not gray markdown_only"
    has "$row" 'badge/readiness-ready-green)'    || echo "OFF_CLEAN Readiness not green"
    has "$facts" 'FORMATS_EXPORT=0'              || echo "OFF_CLEAN fact FORMATS_EXPORT=0 missing"
    has "$facts" 'TWIN_DOCS=0'                   || echo "OFF_CLEAN TWIN_DOCS != 0"; }
case_OFF_STALE() { local t="$1" row facts; row="$(run "$t" "$TMP/r_stale_pending" DOCS_EXPORT=0 --print)"; facts="$(run "$t" "$TMP/r_stale_pending" DOCS_EXPORT=0 --facts)"
    has "$row" 'badge/twins-markdown_only-gray)' || echo "OFF_STALE Twins not gray"
    has "$row" 'badge/readiness-ready-green)'    || echo "OFF_STALE Readiness not green"
    has "$facts" 'TWIN_DOCS=0'                   || echo "OFF_STALE twins were probed while the switch is off"; }
case_DEFAULT() { local t="$1" row; row="$(run "$t" "$TMP/r_stale_pending" - --print)"
    has "$row" 'badge/twins-markdown_only-gray)' || echo "DEFAULT shipped conf did not give gray"; }
case_ON_STALE() { local t="$1" row; row="$(run "$t" "$TMP/r_stale_pending" DOCS_EXPORT=1 --print)"
    has "$row" 'badge/twins-0%2F2_current-amber?color=ffbf00)'         || echo "ON_STALE Twins not amber 0/2"
    has "$row" 'badge/readiness-attention-amber?color=ffbf00)'         || echo "ON_STALE Readiness not amber"; }
case_ON_UNTRACKED() { local t="$1" row; row="$(run "$t" "$TMP/r_stale_silent" DOCS_EXPORT=1 --print)"
    has "$row" 'badge/twins-0%2F2_current-red)'  || echo "ON_UNTRACKED Twins not red 0/2"
    has "$row" 'badge/readiness-blocked-red)'    || echo "ON_UNTRACKED Readiness not red"; }
case_ON_MISSING() { local t="$1" row; row="$(run "$t" "$TMP/r_none" DOCS_EXPORT=1 --print)"
    has "$row" 'badge/twins-2%2F2_current-green)' && echo "ON_MISSING absent twins read as green 2/2 current"
    has "$row" 'badge/twins-0%2F2_current-red)'   || echo "ON_MISSING Twins not red 0/2 (untracked header)"
    row="$(run "$t" "$TMP/r_none_pending" DOCS_EXPORT=1 --print)"
    has "$row" 'badge/twins-0%2F2_current-amber?color=ffbf00)' || echo "ON_MISSING Twins not amber 0/2 (pending header)"; }
case_ON_CURRENT() { local t="$1" row; row="$(run "$t" "$TMP/r_fresh" DOCS_EXPORT=1 --print)"
    has "$row" 'badge/twins-2%2F2_current-green)' || echo "ON_CURRENT Twins not green 2/2"
    has "$row" 'badge/readiness-ready-green)'     || echo "ON_CURRENT Readiness not green"; }
case_BLIND() { local t="$1" out rc; mkdir -p "$TMP/nolib/scripts/badges"; cp "$t/scripts/badges/compute_badges.sh" "$TMP/nolib/scripts/badges/"
    out="$(DOCS_EXPORT=0 bash "$TMP/nolib/scripts/badges/compute_badges.sh" --root "$TMP/r_none" --print 2>/dev/null)"; rc=$?
    [ "$rc" -eq 2 ]    || echo "BLIND exit code $rc != 2 with the shared switch reader absent"
    [ -z "$out" ]      || echo "BLIND printed a row without the shared switch reader"; }
case_NEEDLE() { local t="$1" row; row="$(run "$t" "$TMP/r_none" DOCS_EXPORT=0 --print)"
    has "$row" 'badge/twins-fabricated_needle-gray)' && echo "NEEDLE the assertion helper found a token that is not there (instrument cannot say no)"; }
ALL_CASES="OFF_CLEAN OFF_STALE DEFAULT ON_STALE ON_UNTRACKED ON_MISSING ON_CURRENT BLIND NEEDLE"

# --- 1. the pristine tree: every case holds ---------------------------------------------------------------------------
echo "== pristine computer + shipped conf =="
mk_tool "$TMP/tool_ok"
for c in $ALL_CASES; do
    out="$("case_$c" "$TMP/tool_ok")"
    if [ -z "$out" ]; then ok "$c"; else bad "$c: $out"; fi
done

# --- 2. paired mutations: each must be CAUGHT (at least one case of its set fails) ------------------------------------
echo "== paired mutations (each must make a case fail) =="
mutant() { # name sed-expr cases-that-must-notice [conf-edit]
    local name="$1" expr="$2" cases="$3" t="$TMP/tool_$1" c out caught=0
    mk_tool "$t"
    if [ "$expr" != "-" ]; then
        sed -i "$expr" "$t/scripts/badges/compute_badges.sh"
        cmp -s "$t/scripts/badges/compute_badges.sh" "$SRC_ROOT/scripts/badges/compute_badges.sh" && { bad "$name: sed did not change the computer (mutation not applied)"; return; }
    fi
    if [ "${4:-}" = conf_true ]; then sed -i 's/^formats_export=.*/formats_export=true/' "$t/config/formats_export.conf"; fi
    for c in $cases; do
        out="$("case_$c" "$t")"
        [ -n "$out" ] && caught=1
    done
    if [ "$caught" = 1 ]; then ok "$name caught by {$cases}"; else bad "$name SURVIVED {$cases}"; fi
}
mutant M1_off_branch_removed     's/\[ "${FORMATS_EXPORT:-1}" = 0 \]/false/'                       "OFF_CLEAN OFF_STALE DEFAULT"
mutant M2_twins_probed_when_off  '/\[ "\$fe" = 1 \] || break/d'                                      "OFF_STALE"
mutant M3_stale_cmp_inverted     's/"\$md_ct" -gt "\$tw_ct"/"$md_ct" -lt "$tw_ct"/'                  "ON_STALE ON_UNTRACKED ON_CURRENT"
mutant M4_absent_twin_rule_gone  's/\[ "\$have_tw" = 1 \] || t=1/:/'                                  "ON_MISSING"
mutant M5_blind_return_removed   's/\[ -r "\$fe_lib" \] || { echo "BLIND[^}]*}/:/'                    "BLIND"
mutant M6_gray_moves_gauge       's/\[ "\$c" = amber \] \&\& gauge=amber/[ "$c" = amber -o "$c" = gray ] \&\& gauge=amber/' "OFF_CLEAN OFF_STALE"
mutant M7_shipped_default_true   -                                                                   "OFF_CLEAN DEFAULT" conf_true

echo
echo "twins_badge_formats_switch: PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && { echo "RESULT: PASS"; exit 0; }
echo "RESULT: FAIL"; exit 1
