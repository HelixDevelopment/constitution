#!/usr/bin/env bash
# scripts/badges/compute_badges.sh — README quality-badge computer for the
# HelixConstitution repository itself (§11.4.259, applied to this repo).
#
# Every badge value AND colour is COMPUTED from a live source of truth in the
# working tree — nothing is typed by hand (§11.4.6). The provenance of each
# badge (alt text -> source) is declared in docs/BADGES.md, which
# CM-BADGE-MACHINE-DERIVED-SOURCE cross-checks against the README badge row.
#
# Usage:
#   compute_badges.sh [--root DIR] --print       print the badge row (one line)
#   compute_badges.sh [--root DIR] --facts       print KEY=VALUE facts the README quotes
#   compute_badges.sh [--root DIR] --check       exit 0 iff README.md's badge row equals --print
#   compute_badges.sh --selftest                 golden-good / golden-bad / negative-control run
#
# Formats-export switch (config/formats_export.conf, shipped false; operator order 2026-10-26): the Twins badge
#   judges the .html/.pdf/.docx siblings ONLY when the switch resolves to enabled (DOCS_EXPORT=1, a repository
#   enabled=1 policy, or the conf default). Switch off => Twins is GRAY "markdown only" and no sibling is probed;
#   the shared reader scripts/formats_export_lib.sh is required (absent => BLIND, exit 2).
#
# Closed colour vocabulary (§11.4.259(A)): green | amber | red | gray.
#   amber is emitted with an explicit `?color=ffbf00` override because the badge
#   renderer has no named "amber"; the literal token stays in the URL path so the
#   closed-vocabulary gate can read it.
#
# Exit codes: 0 ok · 1 check mismatch / selftest failure · 2 BLIND (a source of
# truth is missing — a missing source is NEVER rendered as a green badge).
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
ROOT_DEFAULT="$(cd "$HERE/../.." && pwd)"

_esc() { # shields.io static-badge escaping for a path segment
    printf '%s' "$1" | sed -e 's/-/--/g' -e 's/_/__/g' -e 's/ /_/g' -e 's#/#%2F#g'
}

_badge() { # alt label value color
    local alt="$1" label="$2" value="$3" color="$4" q=""
    [ "$color" = "amber" ] && q="?color=ffbf00"
    printf '![%s](https://img.shields.io/badge/%s-%s-%s%s)' \
        "$alt" "$(_esc "$label")" "$(_esc "$value")" "$color" "$q"
}

# compute_facts ROOT -> KEY=VALUE lines on stdout; exit 2 when a source is missing.
compute_facts() {
    local root="$1" f
    for f in Constitution.md CHANGELOG.md constitution_index.yaml progressive/catalog.json .gitmodules; do
        [ -s "$root/$f" ] || { echo "BLIND: missing source of truth: $f" >&2; return 2; }
    done
    [ -d "$root/scripts/gates" ] || { echo "BLIND: missing scripts/gates" >&2; return 2; }

    local canon_sha idx_sha idx_anchors idx_groups cat_sha cat_anchors
    canon_sha="$(sha256sum "$root/Constitution.md" | cut -d' ' -f1)"
    idx_sha="$(sed -n "s/^  source_sha256: *'\{0,1\}\([0-9a-f]\{64\}\).*/\1/p" "$root/constitution_index.yaml" | head -1)"
    idx_anchors="$(grep -c "^- id: " "$root/constitution_index.yaml")"
    idx_groups="$(grep -c "^- name: " "$root/constitution_index.yaml")"
    cat_sha="$(python3 -I -c 'import json,sys;print(json.load(open(sys.argv[1]))["source_sha256"])' "$root/progressive/catalog.json" 2>/dev/null)"
    cat_anchors="$(python3 -I -c 'import json,sys;print(json.load(open(sys.argv[1]))["anchor_count"])' "$root/progressive/catalog.json" 2>/dev/null)"
    [ -n "$idx_sha" ] && [ -n "$cat_sha" ] && [ -n "$cat_anchors" ] || { echo "BLIND: index/catalog fields unreadable" >&2; return 2; }

    # version: the first "## " heading of CHANGELOG.md
    local head1 ver
    head1="$(grep -m1 '^## ' "$root/CHANGELOG.md" | sed 's/^## //')"
    ver="$(printf '%s' "$head1" | sed -n 's/^\(helixconstitution-v[0-9][0-9]*\)\( .*\)\{0,1\}$/\1/p')"
    local ver_state=released
    if [ -z "$ver" ]; then ver="$(printf '%s' "$head1" | cut -d' ' -f1)"; ver_state=unreleased; fi

    # gates: cm_*.sh minus mutation tests; paired = has <name>_mutation_test.sh
    local g n_gates=0 n_paired=0 n_unpaired=0 unpaired=""
    for g in "$root"/scripts/gates/cm_*.sh; do
        [ -e "$g" ] || continue
        case "$g" in *_mutation_test.sh|*_selftest.sh) continue ;; esac
        n_gates=$((n_gates + 1))
        # a gate is paired when it has a *_mutation_test.sh sibling, or an OUTSIDE *_selftest.sh sibling
        if [ -e "${g%.sh}_mutation_test.sh" ] || [ -e "${g%.sh}_selftest.sh" ]; then n_paired=$((n_paired + 1))
        else n_unpaired=$((n_unpaired + 1)); unpaired="$unpaired $(basename "$g" .sh)"; fi
    done
    local n_mut
    n_mut="$(find "$root/scripts/gates" -maxdepth 1 -name '*_mutation_test.sh' | wc -l | tr -d ' ')"

    # submodules: .gitmodules paths vs recorded gitlinks (mode 160000)
    local n_decl n_link
    n_decl="$(grep -c '^[[:space:]]*path = ' "$root/.gitmodules")"
    n_link="$(git -C "$root" ls-files -s 2>/dev/null | grep -c '^160000 ')"

    # formats-export switch (config/formats_export.conf, shipped `false`; operator order 2026-10-26: agents work only
    # with Markdown). The twins are produced, demanded and checked ONLY when the switch resolves to enabled; with it
    # off a twin count would be a false number either way ("7/7 current" over zero files, or "0/7 current" for a
    # sibling nobody asked for), so the Twins badge is GRAY ("markdown only", not applicable) and no twin is probed.
    # The shared reader is mandatory: a tree without it is BLIND, never a green or guessed badge.
    local fe_lib="$HERE/../formats_export_lib.sh" fe=0
    [ -r "$fe_lib" ] || { echo "BLIND: missing source of truth: scripts/formats_export_lib.sh (formats-export switch)" >&2; return 2; }
    . "$fe_lib"
    if formats_export_enabled "$root"; then fe=1; fi

    # rendered twins of the root governance documents: stale when the .md was
    # committed after its .html/.pdf/.docx sibling (never hand-regenerated here)
    local d t ext md_ct tw_ct have_tw n_tw=0 n_tw_stale=0 stale_list=""
    for d in Constitution CLAUDE AGENTS QWEN GEMINI README CHANGELOG; do
        [ "$fe" = 1 ] || break   # switch off: nothing is probed, TWIN_DOCS=0 / TWIN_DOCS_STALE=0 describe "not applicable"
        [ -e "$root/$d.md" ] || continue
        n_tw=$((n_tw + 1))
        md_ct="$(git -C "$root" log -1 --format=%ct -- "$d.md" 2>/dev/null)"
        t=0; have_tw=0
        for ext in html pdf docx; do
            [ -e "$root/$d.$ext" ] || continue
            have_tw=1
            tw_ct="$(git -C "$root" log -1 --format=%ct -- "$d.$ext" 2>/dev/null)"
            if [ -n "$md_ct" ] && [ -n "$tw_ct" ] && [ "$md_ct" -gt "$tw_ct" ]; then t=1; fi
        done
        # switch ON: a document with NO twin at all is not current (never generated / removed) -- an absent sibling
        # must not read as "current" (a missing source is never rendered green; switch OFF never reaches this loop)
        [ "$have_tw" = 1 ] || t=1
        if [ "$t" = 1 ]; then n_tw_stale=$((n_tw_stale + 1)); stale_list="$stale_list $d"; fi
    done

    # twins are "tracked" when the canon header (first 20 lines) openly declares them stale/pending
    local tw_tracked=no
    sed -n 1,20p "$root/Constitution.md" | grep -qiE 'twins.{0,80}(stale|pending)|(stale|pending).{0,80}twins' && tw_tracked=yes

    printf 'VERSION=%s\nVERSION_STATE=%s\n' "$ver" "$ver_state"
    printf 'CANON_SHA=%s\nINDEX_SHA=%s\nCATALOG_SHA=%s\n' "$canon_sha" "$idx_sha" "$cat_sha"
    printf 'INDEX_ANCHORS=%s\nINDEX_GROUPS=%s\nCATALOG_ANCHORS=%s\n' "$idx_anchors" "$idx_groups" "$cat_anchors"
    printf 'GATES=%s\nGATES_PAIRED=%s\nGATES_UNPAIRED=%s\nGATES_UNPAIRED_NAMES=%s\nMUTATION_TESTS=%s\n' \
        "$n_gates" "$n_paired" "$n_unpaired" "${unpaired# }" "$n_mut"
    printf 'SUBMODULES_DECLARED=%s\nSUBMODULES_LINKED=%s\n' "$n_decl" "$n_link"
    printf 'FORMATS_EXPORT=%s\n' "$fe"
    printf 'TWIN_DOCS=%s\nTWIN_DOCS_STALE=%s\nTWIN_DOCS_STALE_NAMES=%s\nTWIN_STALE_TRACKED=%s\n' "$n_tw" "$n_tw_stale" "${stale_list# }" "$tw_tracked"
}

# row_from_facts <facts-file> -> the badge row line on stdout
row_from_facts() {
    local facts="$1"
    eval "$(sed -n 's/^\([A-Z_]*\)=\(.*\)$/\1=\x27\2\x27/p' "$facts")"
    local c_ver=green c_anc=green c_grp=green c_gat=green c_mut=green c_prog=green c_sub=green c_twin=green

    [ "$VERSION_STATE" = released ] || c_ver=amber
    [ "$CANON_SHA" = "$INDEX_SHA" ] || c_anc=red
    [ "$INDEX_GROUPS" -gt 0 ] || c_grp=red
    if [ "$GATES_UNPAIRED" -eq 0 ]; then c_gat=green
    elif [ $((GATES_UNPAIRED * 10)) -le "$GATES" ]; then c_gat=amber; else c_gat=red; fi
    [ "$MUTATION_TESTS" -ge "$GATES_PAIRED" ] || c_mut=red
    [ "$CANON_SHA" = "$CATALOG_SHA" ] || c_prog=red
    [ "$SUBMODULES_DECLARED" = "$SUBMODULES_LINKED" ] || c_sub=red
    # stale twins are AMBER only while the canon header tracks them as pending regeneration; untracked staleness is RED
    # formats-export switch OFF => GRAY "markdown only" (a class that does not apply; gray never moves the Readiness gauge).
    # A facts file with no FORMATS_EXPORT key keeps the pre-switch behaviour (twins are judged) -- never a silent gray.
    local twin_val
    if [ "${FORMATS_EXPORT:-1}" = 0 ]; then c_twin=gray; twin_val="markdown only"
    else
        twin_val="$((TWIN_DOCS - TWIN_DOCS_STALE))/${TWIN_DOCS} current"
        if [ "$TWIN_DOCS_STALE" -eq 0 ]; then c_twin=green
        elif [ "$TWIN_STALE_TRACKED" = yes ]; then c_twin=amber; else c_twin=red; fi
    fi

    local gauge=green c
    for c in $c_ver $c_anc $c_grp $c_gat $c_mut $c_prog $c_sub $c_twin; do
        if [ "$c" = red ]; then gauge=red; break; fi
        [ "$c" = amber ] && gauge=amber
    done
    local gword
    case "$gauge" in green) gword=ready ;; amber) gword=attention ;; *) gword=blocked ;; esac

    local row="" b
    for b in \
        "$(_badge Version version "${VERSION#helixconstitution-}" "$c_ver")" \
        "$(_badge Anchors anchors "$INDEX_ANCHORS" "$c_anc")" \
        "$(_badge Groups groups "$INDEX_GROUPS" "$c_grp")" \
        "$(_badge Gates gates "${GATES_PAIRED}/${GATES} paired" "$c_gat")" \
        "$(_badge Mutation mutation_tests "$MUTATION_TESTS" "$c_mut")" \
        "$(_badge Progressive progressive "$CATALOG_ANCHORS rules" "$c_prog")" \
        "$(_badge Submodules submodules "${SUBMODULES_LINKED}/${SUBMODULES_DECLARED} linked" "$c_sub")" \
        "$(_badge Twins twins "$twin_val" "$c_twin")" \
        "$(_badge Readiness readiness "$gword" "$gauge")"; do
        row="${row:+$row }$b"
    done
    printf '%s\n' "$row"
}

_selftest() {
    local tmp rc=0 out
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/badges_selftest.XXXXXX")" || return 2

    _mk() { # dir: build a minimal consistent fixture tree
        local d="$1" sha
        mkdir -p "$d/scripts/gates" "$d/progressive"
        printf '# C\n' >"$d/Constitution.md"
        sha="$(sha256sum "$d/Constitution.md" | cut -d' ' -f1)"
        printf '## helixconstitution-v1 — 2026-01-01 — fixture\n' >"$d/CHANGELOG.md"
        printf "generated_from:\n  source_sha256: '%s'\ngroups:\n- name: g1\nanchors:\n- id: '1.1'\n" "$sha" >"$d/constitution_index.yaml"
        printf '{"source_sha256": "%s", "anchor_count": 1}\n' "$sha" >"$d/progressive/catalog.json"
        printf '[submodule "x"]\n\tpath = x\n' >"$d/.gitmodules"
        : >"$d/scripts/gates/cm_a.sh"; : >"$d/scripts/gates/cm_a_mutation_test.sh"
        local x; for x in Constitution CHANGELOG; do : >"$d/$x.html"; : >"$d/$x.pdf"; : >"$d/$x.docx"; done   # switch-ON golden-good needs its twins present
        git -C "$d" init -q 2>/dev/null
        git -C "$d" update-index --add --cacheinfo 160000,1111111111111111111111111111111111111111,x 2>/dev/null
    }

    # the pre-existing cases below judge the twins, so they run with the formats-export switch ON (DOCS_EXPORT=1);
    # the switch-OFF behaviour (GRAY, nothing probed) is asserted separately further down.
    # golden-good: a consistent fixture must render ONLY green badges
    _mk "$tmp/good"
    DOCS_EXPORT=1 compute_facts "$tmp/good" >"$tmp/good.facts" 2>/dev/null || { echo "selftest FAIL golden-good: facts rc!=0"; rm -rf "$tmp"; return 1; }
    out="$(row_from_facts "$tmp/good.facts")"
    case "$out" in *-red*|*-amber*) echo "selftest FAIL golden-good: non-green badge in $out"; rc=1 ;; esac
    case "$out" in *"Anchors"*"-green"*) : ;; *) echo "selftest FAIL golden-good: Anchors badge not green"; rc=1 ;; esac

    # golden-bad: a drifted index digest MUST turn Anchors AND Readiness red
    _mk "$tmp/bad"
    sed -i "s/source_sha256: '[0-9a-f]*'/source_sha256: '$(printf 'f%.0s' $(seq 64))'/" "$tmp/bad/constitution_index.yaml"
    DOCS_EXPORT=1 compute_facts "$tmp/bad" >"$tmp/bad.facts" 2>/dev/null || { echo "selftest FAIL golden-bad: facts rc!=0"; rm -rf "$tmp"; return 1; }
    out="$(row_from_facts "$tmp/bad.facts")"
    case "$out" in *"[Anchors]"*"-red)"*) : ;; *) echo "selftest FAIL golden-bad: drifted index not red: $out"; rc=1 ;; esac
    case "$out" in *"[Readiness]"*"-red)"*) : ;; *) echo "selftest FAIL golden-bad: readiness gauge not red"; rc=1 ;; esac

    # negative-control: a tree with the index removed MUST be BLIND (rc 2), never a green row
    _mk "$tmp/neg"; rm -f "$tmp/neg/constitution_index.yaml"
    DOCS_EXPORT=1 compute_facts "$tmp/neg" >"$tmp/neg.facts" 2>/dev/null
    if [ $? -ne 2 ]; then echo "selftest FAIL negative-control: missing index did not return BLIND(2)"; rc=1; fi

    # formats-export switch OFF: Twins must be GRAY "markdown only" (never a green "x/y current" over files nobody asked
    # for), the Readiness gauge must stay green on the otherwise-consistent fixture, and a drifted index must still go red.
    DOCS_EXPORT=0 compute_facts "$tmp/good" >"$tmp/off.facts" 2>/dev/null || { echo "selftest FAIL switch-off: facts rc!=0"; rc=1; }
    out="$(row_from_facts "$tmp/off.facts")"
    case "$out" in *"[Twins]("*"-markdown_only-gray)"*) : ;; *) echo "selftest FAIL switch-off: Twins badge not gray markdown_only: $out"; rc=1 ;; esac
    case "$out" in *"[Readiness]("*"-ready-green)"*) : ;; *) echo "selftest FAIL switch-off: gray Twins moved the Readiness gauge: $out"; rc=1 ;; esac
    DOCS_EXPORT=0 compute_facts "$tmp/bad" >"$tmp/off_bad.facts" 2>/dev/null
    out="$(row_from_facts "$tmp/off_bad.facts")"
    case "$out" in *"[Readiness]("*"-red)"*) : ;; *) echo "selftest FAIL switch-off: gray Twins masked a red badge in the gauge: $out"; rc=1 ;; esac
    # BLIND when the shared switch reader is absent: a copy of this script with no sibling formats_export_lib.sh
    mkdir -p "$tmp/nolib/scripts/badges"; cp "${BASH_SOURCE[0]:-$0}" "$tmp/nolib/scripts/badges/compute_badges.sh"
    bash "$tmp/nolib/scripts/badges/compute_badges.sh" --root "$tmp/good" --facts >/dev/null 2>&1
    if [ $? -ne 2 ]; then echo "selftest FAIL negative-control: missing formats_export_lib.sh did not return BLIND(2)"; rc=1; fi

    # amber carries the explicit colour override and a closed-vocabulary token
    out="$(_badge T t v amber)"
    case "$out" in *"-amber?color=ffbf00)") : ;; *) echo "selftest FAIL: amber badge form wrong: $out"; rc=1 ;; esac

    rm -rf "$tmp"
    [ "$rc" -eq 0 ] && echo "SELFTEST PASS: golden-good all green, golden-bad red, negative-control BLIND, amber form ok, switch-off Twins gray + gauge unmoved + lib-absent BLIND"
    return "$rc"
}

main() {
    local root="$ROOT_DEFAULT" mode=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --root) root="$2"; shift 2 ;;
            --print|--facts|--check|--selftest) mode="$1"; shift ;;
            -h|--help) sed -n '2,22p' "${BASH_SOURCE[0]:-$0}" | sed 's/^# \{0,1\}//'; return 0 ;;
            *) echo "unknown arg: $1" >&2; return 2 ;;
        esac
    done
    [ -n "$mode" ] || { echo "usage: compute_badges.sh [--root DIR] --print|--facts|--check|--selftest" >&2; return 2; }
    [ "$mode" = "--selftest" ] && { _selftest; return $?; }

    local tmp rc
    tmp="$(mktemp "${TMPDIR:-/tmp}/badges_facts.XXXXXX")" || return 2
    compute_facts "$root" >"$tmp"; rc=$?
    if [ "$rc" -ne 0 ]; then rm -f "$tmp"; return "$rc"; fi
    case "$mode" in
        --facts) cat "$tmp" ;;
        --print) row_from_facts "$tmp" ;;
        --check)
            local want have
            want="$(row_from_facts "$tmp")"
            have="$(awk 'f&&NF{print;exit} /^# /{f=1}' "$root/README.md")"
            if [ "$want" = "$have" ]; then echo "BADGES: README badge row matches the computed row"; rc=0
            else echo "BADGES: MISMATCH" >&2; echo " computed: $want" >&2; echo " readme:   $have" >&2; rc=1; fi ;;
    esac
    rm -f "$tmp"
    return "$rc"
}

main "$@"
